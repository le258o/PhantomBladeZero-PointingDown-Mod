#define _WIN32_WINNT 0x0600
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <setupapi.h>
#include <hidpi.h>
#include <hidsdi.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>
#include <stdlib.h>
/* These standard HID declarations are missing from the older MinGW headers. */
HIDAPI BOOLEAN NTAPI HidD_GetPreparsedData(HANDLE, PHIDP_PREPARSED_DATA *);
HIDAPI BOOLEAN NTAPI HidD_FreePreparsedData(PHIDP_PREPARSED_DATA);

/* In-process Lua loadlib module. Entry points deliberately use no Lua C API:
   they push no values and return zero results, so no Lua version/CRT is shared.
   Shared HID reads preserve the game's own Raw Input registration and bindings.
   Protocol field offsets checked against SDL's PS4/PS5 HID driver packet layouts.
   No SDL code is linked or copied. No HID output/feature reports are sent. */

#define MAX_DEVICES 8
typedef struct { int id, active, fired, x, y; ULONGLONG began, last, cooldown; } Gesture;
typedef struct { int x,y,id,down,second; } Touch;
typedef struct {
 HANDLE handle, event; OVERLAPPED ov; WCHAR path[512];
 USHORT product, length; BYTE data[512]; int pending; Gesture gesture;
} Device;
static Device devices[MAX_DEVICES];
static CRITICAL_SECTION mailbox;
static WCHAR event_path[MAX_PATH], temp_path[MAX_PATH];
static LONG initialized;
static unsigned long sequence;
static ULONGLONG issued;
static int queued;

static int foreground(void) {
 DWORD pid=0; HWND w=GetForegroundWindow();
 if(w) GetWindowThreadProcessId(w,&pid);
 return pid==GetCurrentProcessId();
}

static void publish_locked(const char *command) {
 char row[96]; DWORD written;
 HANDLE f=CreateFileW(temp_path,GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
                     NULL,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,NULL);
 if(f==INVALID_HANDLE_VALUE) return;
 int n=snprintf(row,sizeof(row),"%lu|%s\n",++sequence,command);
 BOOL ok=WriteFile(f,row,(DWORD)n,&written,NULL); CloseHandle(f);
 if(ok && written==(DWORD)n) {
  int retry;for(retry=0;retry<8;++retry) {
   if(MoveFileExW(temp_path,event_path,MOVEFILE_REPLACE_EXISTING)) break;
   Sleep(1);
  }
 }
}
static void publish(const char *command) {
 EnterCriticalSection(&mailbox);
 publish_locked(command);
 issued=GetTickCount64(); queued=!strcmp(command,"down") || !strcmp(command,"up");
 LeaveCriticalSection(&mailbox);
}

/* Exact Sony retail PID allowlist. Unknown and short/simple reports are ignored. */
static int model(USHORT product) {
 if(product==0x05c4 || product==0x09cc) return 4;
 if(product==0x0ce6 || product==0x0df2) return 5;
 return 0;
}
static int decode(USHORT product,const BYTE *b,int n,Touch *t) {
 if(!b || n<1) return 0;
 int type=model(product),o=-1,maxY=0;
 if(type==4) {
  if(b[0]==1 && n==64) o=35;
  else if(b[0]>=0x11 && b[0]<=0x19 && n>=78) o=37;
  maxY=944;
 } else if(type==5) {
  if(b[0]==1 && n==64) o=33;
  else if(b[0]==0x31 && n==78) o=34;
  maxY=1080;
 }
 if(o<0 || n<o+8) return 0;
 t->down=(b[o]&0x80)==0; t->second=(b[o+4]&0x80)==0;
 t->id=b[o]&0x7f;
 t->x=b[o+1]|((b[o+2]&15)<<8); t->y=(b[o+2]>>4)|(b[o+3]<<4);
 return !t->down || (t->x<1920 && t->y<maxY);
}

/* One command per finger contact, radial drift rejection, min/max duration,
   two-finger rejection, device/focus gap resets and 1s cooldown. */
static int update(Gesture *g,const Touch *t,ULONGLONG now,int focused) {
 if(!focused || !t->down || t->second) { g->active=0; return 0; }
 if(!g->active || g->id!=t->id || now-g->last>150) {
  g->id=t->id;g->x=t->x;g->y=t->y;g->began=now;g->last=now;
  g->active=1;g->fired=0;return 0;
 }
 g->last=now;
 if(g->fired || now-g->began>900 || now<g->cooldown) return 0;
 int dy=t->y-g->y,dx=abs(t->x-g->x);
 if(now-g->began>=60 && abs(dy)>=220 && dx*100<=abs(dy)*65) {
  g->fired=1;g->cooldown=now+1000;return dy>0?1:-1;
 }
 return 0;
}

static void close_device(Device *d) {
 if(d->handle && d->handle!=INVALID_HANDLE_VALUE) {
  CancelIo(d->handle);
  if(d->pending) { DWORD n; GetOverlappedResult(d->handle,&d->ov,&n,TRUE); }
  CloseHandle(d->handle);
 }
 if(d->event) CloseHandle(d->event);
 memset(d,0,sizeof(*d));
}

static void discover(void) {
 GUID guid; HidD_GetHidGuid(&guid);
 HDEVINFO list=SetupDiGetClassDevsW(&guid,NULL,NULL,DIGCF_PRESENT|DIGCF_DEVICEINTERFACE);
 if(list==INVALID_HANDLE_VALUE) return;
 SP_DEVICE_INTERFACE_DATA iface; memset(&iface,0,sizeof(iface));iface.cbSize=sizeof(iface);
 DWORD index;
 for(index=0;SetupDiEnumDeviceInterfaces(list,NULL,&guid,index,&iface);++index) {
  DWORD bytes=0;
  SetupDiGetDeviceInterfaceDetailW(list,&iface,NULL,0,&bytes,NULL);
  if(bytes<sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA_W) || bytes>65536) continue;
  PSP_DEVICE_INTERFACE_DETAIL_DATA_W detail=(PSP_DEVICE_INTERFACE_DETAIL_DATA_W)malloc(bytes);
  if(!detail) continue; detail->cbSize=sizeof(*detail);
  if(!SetupDiGetDeviceInterfaceDetailW(list,&iface,detail,bytes,NULL,NULL)) { free(detail);continue; }
  int k,slot=-1,known=0;
  for(k=0;k<MAX_DEVICES;++k) {
   if(devices[k].handle && !_wcsicmp(devices[k].path,detail->DevicePath)) known=1;
   if(!devices[k].handle) slot=k;
  }
  if(known || slot<0 || wcslen(detail->DevicePath)>=512) {free(detail);continue;}
  HANDLE h=CreateFileW(detail->DevicePath,GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE,
                      NULL,OPEN_EXISTING,FILE_FLAG_OVERLAPPED,NULL);
  if(h==INVALID_HANDLE_VALUE) {free(detail);continue;}
  HIDD_ATTRIBUTES attr; memset(&attr,0,sizeof(attr));attr.Size=sizeof(attr);
  PHIDP_PREPARSED_DATA pp=NULL; HIDP_CAPS caps;
  int accepted=HidD_GetAttributes(h,&attr) && attr.VendorID==0x054c && model(attr.ProductID);
  if(accepted) {
   accepted=HidD_GetPreparsedData(h,&pp);
   if(accepted) { accepted=HidP_GetCaps(pp,&caps)==HIDP_STATUS_SUCCESS; HidD_FreePreparsedData(pp); }
  }
  if(!accepted || caps.UsagePage!=1 || (caps.Usage!=5 && caps.Usage!=4) ||
     caps.InputReportByteLength<64 || caps.InputReportByteLength>512) {
   CloseHandle(h);free(detail);continue;
  }
  Device *d=&devices[slot]; memset(d,0,sizeof(*d));
  d->event=CreateEventW(NULL,TRUE,FALSE,NULL);
  if(!d->event) {CloseHandle(h);free(detail);continue;}
  d->handle=h;d->product=attr.ProductID;d->length=caps.InputReportByteLength;
  wcscpy(d->path,detail->DevicePath); free(detail);
 }
 SetupDiDestroyDeviceInfoList(list);
}

static void consume(Device *d,DWORD n) {
 Touch t;
 if(decode(d->product,d->data,(int)n,&t)) {
  int command=update(&d->gesture,&t,GetTickCount64(),foreground());
  if(command) publish(command>0?"down":"up");
 } else d->gesture.active=0;
}

static DWORD WINAPI worker(void *unused) {
 ULONGLONG next_discovery=0;
 (void)unused;
 for(;;) {
  ULONGLONG now=GetTickCount64();
  if(now>=next_discovery) {discover();next_discovery=now+2000;}
  int k;
  for(k=0;k<MAX_DEVICES;++k) {
   Device *d=&devices[k]; if(!d->handle) continue;
   /* Drain queued reports in bounded batches so 1kHz devices cannot accumulate
      a growing backlog behind our 2ms worker interval. */
   int batch;
   for(batch=0;batch<32 && d->handle;++batch) {
    DWORD n=0;
    if(d->pending) {
     if(!GetOverlappedResult(d->handle,&d->ov,&n,FALSE)) {
      if(GetLastError()!=ERROR_IO_INCOMPLETE) close_device(d);
      break;
     }
     d->pending=0;consume(d,n);
    }
    memset(&d->ov,0,sizeof(d->ov));d->ov.hEvent=d->event;ResetEvent(d->event);
    if(ReadFile(d->handle,d->data,d->length,&n,&d->ov)) consume(d,n);
    else if(GetLastError()==ERROR_IO_PENDING) {d->pending=1;break;}
    else {close_device(d);break;}
   }
  }
  Sleep(2);
 }
 return 0;
}

__declspec(dllexport) int pbz_start(void *lua_state) {
 (void)lua_state;
 if(InterlockedCompareExchange(&initialized,1,0)) return 0;
 InitializeCriticalSection(&mailbox);
 HMODULE self=NULL;
 /* Lua can unload its module table during a reload. Pin this one module so its
    reader thread cannot execute freed code; it dies with the host process. */
 if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,
                       (LPCWSTR)(uintptr_t)&pbz_start,&self)) return 0;
 DWORD len=GetModuleFileNameW(self,event_path,MAX_PATH);
 if(!len || len>=MAX_PATH-16) return 0;
 WCHAR *slash=wcsrchr(event_path,L'\\'); if(!slash) return 0;
 wcscpy(slash+1,L"PSNative.event");wcscpy(temp_path,event_path);wcscat(temp_path,L".tmp");
 publish("ready");
 HANDLE thread=CreateThread(NULL,0,worker,NULL,0,NULL);
 if(thread) CloseHandle(thread); else publish("thread_failed");
 return 0;
}

__declspec(dllexport) int pbz_sync(void *lua_state) {
 (void)lua_state;
 if(!initialized || !event_path[0]) return 0;
 EnterCriticalSection(&mailbox);
 if(queued && (!foreground() || GetTickCount64()-issued>1000)) {
  publish_locked("discard");queued=0;
 }
 LeaveCriticalSection(&mailbox);
 return 0;
}

#ifdef PBZ_TEST
static int checks=0;
#define CHECK(x) do{++checks;if(!(x)){fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#x);return 1;}}while(0)
static void pack(BYTE *b,int o,int id,int x,int y,int down) {
 b[o]=(BYTE)(id|(down?0:0x80));b[o+1]=(BYTE)x;
 b[o+2]=(BYTE)(((x>>8)&15)|((y&15)<<4));b[o+3]=(BYTE)(y>>4);b[o+4]=0x80;
}
int main(void) {
 USHORT pids[]={0x05c4,0x09cc,0x0ce6,0x0df2};
 int i,j; BYTE b[78]; Touch t;
 for(i=0;i<4;++i) for(j=0;j<2;++j) {
  memset(b,0,sizeof(b));int n=j?78:64;
  b[0]=j?(i<2?0x11:0x31):1;
  int o=i<2?(j?37:35):(j?34:33);
  pack(b,o,17,1700,800,1);
  CHECK(decode(pids[i],b,n,&t)); CHECK(t.down && !t.second && t.id==17 && t.x==1700 && t.y==800);
  CHECK(!decode(pids[i],b,10,&t));
  pack(b,o,17,1700,800,0);CHECK(decode(pids[i],b,n,&t) && !t.down);
 }
 memset(b,0,sizeof(b));b[0]=1;
 CHECK(!decode(0x0ce6,b,78,&t));CHECK(!decode(0x09cc,b,10,&t));CHECK(!decode(0xffff,b,64,&t));
 Gesture g={0};t=(Touch){900,100,1,1,0};
 CHECK(!update(&g,&t,1000,1));t.y=350;CHECK(update(&g,&t,1100,1)==1);
 t.y=700;CHECK(!update(&g,&t,1200,1));
 t.down=0;CHECK(!update(&g,&t,1300,1));t.down=1;t.y=700;
 CHECK(!update(&g,&t,2200,1));t.y=400;CHECK(update(&g,&t,2300,1)==-1);
 memset(&g,0,sizeof(g));t=(Touch){900,100,1,1,0};update(&g,&t,1000,1);
 t.x=1500;t.y=350;CHECK(!update(&g,&t,1100,1));
 t.x=900;t.second=1;CHECK(!update(&g,&t,1150,1));CHECK(!g.active);
 t.second=0;update(&g,&t,1200,1);t.y=700;CHECK(!update(&g,&t,1300,0));CHECK(!g.active);
 memset(&g,0,sizeof(g));t=(Touch){900,100,1,1,0};update(&g,&t,1000,1);
 t.y=350;CHECK(!update(&g,&t,1010,1));
 t.id=2;CHECK(!update(&g,&t,1100,1));
 t.y=700;CHECK(!update(&g,&t,1500,1)); /* missing packet gap */
 memset(&g,0,sizeof(g));t=(Touch){900,100,1,1,0};update(&g,&t,1000,1);
 for(i=1;i<=10;++i) CHECK(!update(&g,&t,1000+i*100,1));
 t.y=500;CHECK(!update(&g,&t,2100,1)); /* too slow */
 printf("PASS: %d native protocol/gesture assertions\n",checks);return 0;
}
#endif
