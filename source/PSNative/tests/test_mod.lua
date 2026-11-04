local target=assert(arg[1])
local checks=0
local function check(v,msg) checks=checks+1;assert(v,msg) end
local logs={}
local originalPrint=print
print=function(s) logs[#logs+1]=s end
local bindings,loop={},nil
Key={O='O',BACKSPACE='BACKSPACE'}
FName=function(s)return s end
RegisterKeyBind=function(k,f) bindings[k]=f end
ExecuteInGameThread=function(f) f() end
LoopAsync=function(_,f)loop=f end
local stamp,paused=10,false
local analog,keyboard={},{}
local yaw,pitch,actorYaw=0,0,0
local played,restored,enabled,disabled=0,0,0,0
local raw={X=0,Y=0}
local function object(t) t=t or {};t.IsValid=function()return true end;return t end
local skeleton=object{GetAddress=function()return 123 end}
local clip=object{Skeleton=skeleton,GetFullName=function()return 'clip' end}
local anim=object{GetClass=function()return 'originalAnim' end,IsAnyMontagePlaying=function()return false end}
local mesh=object{
 GetAnimationMode=function()return 0 end,GetAnimInstance=function()return anim end,
 GetSkinnedAsset=function()return {Skeleton=skeleton}end,
 PlayAnimation=function()played=played+1 end,
 SetAnimInstanceClass=function(_,c)assert(c=='originalAnim');restored=restored+1 end,
}
local move=object{MovementMode=1,CustomMovementMode=0,bOrientRotationToMovement=true,bUseControllerDesiredRotation=true}
move.IsMovingOnGround=function()return true end
move.StopMovementImmediately=function()end
move.DisableMovement=function(self)self.MovementMode=0 end
move.SetMovementMode=function(self,m,c)self.MovementMode=m;self.CustomMovementMode=c end
local pc=object{
 IsMoveInputIgnored=function()return false end,IsLookInputIgnored=function()return false end,
 GetControlRotation=function()return {Yaw=yaw,Pitch=pitch,Roll=0}end,
 SetControlRotation=function(_,r)yaw=r.Yaw;pitch=r.Pitch end,
 GetInputAnalogKeyState=function(_,k)return analog[k.KeyName] or 0 end,
 GetInputVectorKeyState=function()return raw end,
 IsInputKeyDown=function(_,k)return keyboard[k.KeyName] or false end,
 DisableInput=function()disabled=disabled+1 end,
 EnableInput=function()enabled=enabled+1 end,
 PlayerCameraManager=object{ViewPitchMin=-80,ViewPitchMax=80},
}
local pawn=object{
 Mesh=mesh,CharacterMovement=move,bUseControllerRotationYaw=true,
 GetAddress=function()return 234 end,GetVelocity=function()return {X=0,Y=0,Z=0}end,
 K2_GetActorLocation=function()return {X=0,Y=0,Z=0}end,
 K2_GetActorRotation=function()return {Yaw=actorYaw}end,
 K2_SetActorRotation=function(_,r)actorYaw=r.Yaw end,
 K2_SetActorLocation=function()end,
 DisableInput=function()disabled=disabled+1 end,EnableInput=function()enabled=enabled+1 end,
}
local ref=assert(io.open('work/test_ref.tmp','w+b'))
local kismet={
 MakeSoftObjectPath=function(_,p)return p end,
 Conv_SoftObjPathToSoftObjRef=function()return ref end,
 Conv_SoftObjectReferenceToString=function()return '/HuaShira/PointDownMod/PD_PointDown_V3.PD_PointDown_V3' end,
 LoadAsset_Blocking=function()return clip end,
}
package.preload.UEHelpers=function()return {
 GetPlayer=function()return pawn end,GetPlayerController=function()return pc end,
 GetGameplayStatics=function()return {GetTimeSeconds=function()return stamp end,IsGamePaused=function()return paused end}end,
 GetKismetSystemLibrary=function()return kismet end,
}end
local source=assert(io.open(target)):read('*a')
local row='0|ready'
local originalOpen=io.open
io.open=function(path,...)
 if path:match('PSNative%.event$') then return {read=function()return row end,close=function()end}end
 return originalOpen(path,...)
end
local loaded={}
package.loadlib=function(path,symbol)
 loaded[#loaded+1]={path,symbol}
 return function()end
end
assert(load(source,'@C:/test/main.lua'))()
check(#loaded==2 and loaded[1][1]=='C:/test/PSNative.dll','module path and both exports')
check(bindings.O and bindings.BACKSPACE and loop,'keyboard and update registrations')
bindings.O()
check(played==1 and disabled==2,'pure controller start must not require mouse calibration')
local function step(dt)stamp=stamp+dt;loop()end
analog.Gamepad_RightX=1;analog.Gamepad_RightY=1
step(1/60)
check(yaw>0 and pitch>0,'right stick must control both camera axes')
check(yaw<=3.001 and pitch<=2.001,'diagonal input clamped and dt applied')
local beforeYaw,beforePitch=yaw,pitch
analog.Gamepad_RightX=.05;analog.Gamepad_RightY=.04
step(1/60)
check(yaw==beforeYaw and pitch==beforePitch,'small drift must not move camera')
analog.Gamepad_LeftX=1;analog.Gamepad_LeftY=0
step(1/60)
check(actorYaw>0 and actorYaw<=6.001,'left stick turns pawn at limited rate')
analog.Gamepad_RightX=0;analog.Gamepad_RightY=0
raw={X=10,Y=2};beforeYaw=yaw
step(1/60)
check(yaw>beforeYaw,'mouse camera remains usable')
raw={X=0,Y=0}
bindings.BACKSPACE()
check(restored==1 and move.MovementMode==1 and enabled==2,'cancel restores animation, movement and input')
check(pawn.bUseControllerRotationYaw and move.bOrientRotationToMovement,'rotation flags restored')
row='1|down';for i=1,6 do step(.005) end
check(played==2,'touch down event starts action')
for i=1,12 do step(.005) end
check(played==2,'same event is not replayed')
row='2|up';for i=1,6 do step(.005) end
check(restored==2,'touch up cancels')
paused=true;row='3|down';for i=1,6 do step(.005) end
check(played==2,'paused game rejects trigger')
paused=false;row='4|discard';for i=1,6 do step(.005) end
check(played==2,'discarded stale/background event cannot trigger')
bindings.O();check(played==3,'can restart after cancel')
step(5.1);check(restored==3 and move.MovementMode==1,'natural completion restores state')
for _,s in ipairs(logs)do check(not s:match('ERROR '),'script logged an error: '..s)end
print=originalPrint
print('PASS: '..checks..' Lua integration assertions (mock engine, real script)')
ref:close()
