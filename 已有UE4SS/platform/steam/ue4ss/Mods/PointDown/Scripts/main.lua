-- Native AnimSequence test candidate. No helper meshes or LeaderPose changes.
local U=require('UEHelpers')
local VERSION='0.5.4'
local TURN_RATE=360 -- degrees per second, shortest arc, no instantaneous snap
local ASSET='/HuaShira/PointDownMod/PD_PointDown_V3.PD_PointDown_V3'
local state=nil
local queued=false
local function log(s) print('[PointDownNative] '..tostring(s)..'\n') end
local function valid(v) local ok,r=pcall(function() return v:IsValid() end);return ok and r end
local function time(p) return U.GetGameplayStatics():GetTimeSeconds(p) end
local keys={};for _,k in ipairs({'W','A','S','D','MouseX','MouseY'}) do keys[k]={KeyName=FName(k)} end
keys.Mouse2D={KeyName=FName('Mouse2D')}
local calibration={x={},y={}}
local previous=nil
local function angle(v) return (v+180)%360-180 end
local function gain(samples)
 if #samples<6 then return nil end
 local a={};for i,v in ipairs(samples) do a[i]=v end;table.sort(a)
 local median=a[math.floor(#a/2)+1]
 local good=0;for _,v in ipairs(a) do if math.abs(v-median)<=math.abs(median)*.12 then good=good+1 end end
 return good>=math.ceil(#a*.75) and median or nil
end
local function observe()
 local p,pc=U.GetPlayer(),U.GetPlayerController()
 if not valid(p) or not valid(pc) or pc:IsMoveInputIgnored() or pc:IsLookInputIgnored() or U.GetGameplayStatics():IsGamePaused(p) then previous=nil;return end
 local stamp=time(p);local r=pc:GetControlRotation();local raw=pc:GetInputVectorKeyState(keys.Mouse2D)
 local addr=p:GetAddress()
 if previous and previous.address==addr and stamp==previous.time then return end
 local v=p:GetVelocity()
 if previous and previous.address==addr and stamp>previous.time and stamp-previous.time<.1 and v.X*v.X+v.Y*v.Y+v.Z*v.Z<1 then
  for _,axis in ipairs({'x','y'}) do
   local input=axis=='x' and raw.X or raw.Y
   local delta=angle((axis=='x' and r.Yaw or r.Pitch)-(axis=='x' and previous.yaw or previous.pitch))
   if math.abs(input)>=.5 and math.abs(delta)>.0001 and math.abs(delta)<20 then
    local ratio=delta/input
    if math.abs(ratio)<20 then
     local samples=calibration[axis];samples[#samples+1]=ratio;if #samples>16 then table.remove(samples,1) end
    end
   end
  end
 end
 previous={address=addr,time=stamp,yaw=r.Yaw,pitch=r.Pitch}
end
local function finish(why)
 local s=state;if not s then return end;state=nil
 previous=nil
 local errors={}
 local function restore(f) local ok,e=pcall(f);if not ok then errors[#errors+1]=tostring(e) end end
 restore(function() if s.animChanged and valid(s.mesh) then s.mesh:SetAnimInstanceClass(s.animClass) end end)
 restore(function() if s.locked and valid(s.move) then s.move:SetMovementMode(s.mode,s.custom) end end)
 restore(function() if s.rotationChanged and valid(s.move) then s.move.bOrientRotationToMovement=s.orient;s.move.bUseControllerDesiredRotation=s.desired end end)
 restore(function() if s.rotationChanged and valid(s.pawn) then s.pawn.bUseControllerRotationYaw=s.controllerYaw end end)
 restore(function() if s.inputLocked and valid(s.pc) and valid(s.pawn) then
  -- Do not undo a new game's own move-input suppression during a cutscene.
  if not s.pc:IsMoveInputIgnored() then s.pawn:EnableInput(s.pc);s.pc:EnableInput(s.pc) end
 end end)
 log('RESTORE '..why..(#errors>0 and (' ERRORS '..table.concat(errors,' | ')) or ''))
end
local function start()
 if state then return end
 local p,pc=U.GetPlayer(),U.GetPlayerController()
 if not valid(p) or not valid(pc) or pc:IsMoveInputIgnored() or U.GetGameplayStatics():IsGamePaused(p) then return end
 local m=p.Mesh;local mv=p.CharacterMovement
 if not valid(m) or not valid(mv) or not mv:IsMovingOnGround() then return end
 if m:GetAnimationMode()~=0 then log('Native animation mode is not Blueprint: ignored.');return end
 local ai=m:GetAnimInstance();if not valid(ai) or ai:IsAnyMontagePlaying() then log('Wait until the current action finishes.');return end
 local v=p:GetVelocity();if v.X*v.X+v.Y*v.Y+v.Z*v.Z>1 then log('Stand still first.');return end
 local gx,gy=gain(calibration.x),gain(calibration.y)
 if not gx or not gy then log('LOOK CALIBRATION: stand still and move mouse left/right and up/down for a moment before O.');return end
 -- LoadAsset_Blocking takes TSoftObjectPtr, NOT an FSoftObjectPath/Lua table.
 -- Use engine conversion and preserve UE4SS's native TSoftObjectPtr userdata.
 local k=U.GetKismetSystemLibrary()
 log('LOAD 1 make engine path '..ASSET)
 local path=k:MakeSoftObjectPath(ASSET)
 log('LOAD 2 convert engine path to soft reference')
 local ref=k:Conv_SoftObjPathToSoftObjRef(path)
 if type(ref)~='userdata' then log('LOAD ABORT: soft reference is not native userdata');return end
 local resolved=k:Conv_SoftObjectReferenceToString(ref)
 if type(resolved)~='string' then resolved=resolved:ToString() end
 log('LOAD reference='..resolved)
 if resolved~=ASSET then log('LOAD ABORT: soft reference path changed during conversion');return end
 log('LOAD 3 synchronous load with native soft reference')
 local clip=k:LoadAsset_Blocking(ref)
 log('LOAD 4 load returned')
 if not valid(clip) then log('Native asset could not be loaded; nothing changed.');return end
 log('CHECK native skeleton compatibility')
 local sk=m:GetSkinnedAsset().Skeleton
 if not valid(sk) or not valid(clip.Skeleton) or sk:GetAddress()~=clip.Skeleton:GetAddress() then log('Skeleton pointer mismatch: no playback.');return end
 local l=p:K2_GetActorLocation()
 local s={pawn=p,pc=pc,mesh=m,move=mv,animClass=ai:GetClass(),mode=mv.MovementMode,custom=mv.CustomMovementMode,
  orient=mv.bOrientRotationToMovement,desired=mv.bUseControllerDesiredRotation,controllerYaw=p.bUseControllerRotationYaw,
  anchor={X=l.X,Y=l.Y,Z=l.Z},clip=clip,started=time(p)}
 s.lastTick=s.started
 s.lookX=gx;s.lookY=gy
 local camera=pc.PlayerCameraManager
 s.pitchMin=valid(camera) and camera.ViewPitchMin or -80
 s.pitchMax=valid(camera) and camera.ViewPitchMax or 80
 log('LOOK calibrated degrees/raw-unit X='..gx..' Y='..gy)
 state=s
 -- Block gameplay input at BOTH Pawn and Controller, not only movement.
 -- PlayerInput raw axis state remains available. Forward calibrated mouse look;
 -- keep native gameplay bindings disabled to prevent attacks/dodges moving the pawn.
 log('LOCK native pawn/controller input')
 s.inputLocked=true;p:DisableInput(pc);pc:DisableInput(pc)
 s.rotationChanged=true;mv.bOrientRotationToMovement=false;mv.bUseControllerDesiredRotation=false;p.bUseControllerRotationYaw=false
 s.locked=true;mv:StopMovementImmediately();mv:DisableMovement()
 log('PLAY native animation')
 s.animChanged=true;m:PlayAnimation(clip,false)
 log('START native asset='..clip:GetFullName())
end
local function tick()
 local s=state;if not s then return end
 local p=U.GetPlayer()
 if not valid(p) or not valid(s.mesh) or not valid(s.pc) or p:GetAddress()~=s.pawn:GetAddress() then finish('pawn changed');return end
 if U.GetGameplayStatics():IsGamePaused(p) or s.pc:IsMoveInputIgnored() then finish('interrupted');return end
 if s.move.MovementMode~=0 then s.locked=false;finish('game movement override');return end
 local t=time(p)-s.started
 if t<0 or t>=5 then finish('finished');return end
 local now=s.started+t
 if now<=s.lastTick then return end
 local dt=math.max(0,math.min(now-s.lastTick,.1));s.lastTick=now
 if not s.pc:IsLookInputIgnored() then
  local raw=s.pc:GetInputVectorKeyState(keys.Mouse2D)
  if raw.X~=0 or raw.Y~=0 then
   local r=s.pc:GetControlRotation()
   s.pc:SetControlRotation({Yaw=r.Yaw+raw.X*s.lookX,
    Pitch=math.max(s.pitchMin,math.min(angle(r.Pitch)+raw.Y*s.lookY,s.pitchMax)),Roll=r.Roll})
  end
 end
 local l=p:K2_GetActorLocation();local a=s.anchor
 if (l.X-a.X)^2+(l.Y-a.Y)^2+(l.Z-a.Z)^2>.0001 then p:K2_SetActorLocation(a,false,{},true) end
 local x=(s.pc:IsInputKeyDown(keys.D) and 1 or 0)-(s.pc:IsInputKeyDown(keys.A) and 1 or 0)
 local y=(s.pc:IsInputKeyDown(keys.W) and 1 or 0)-(s.pc:IsInputKeyDown(keys.S) and 1 or 0)
 if x~=0 or y~=0 then
  local target=s.pc:GetControlRotation().Yaw+math.deg(math.atan(x,y))
  local current=p:K2_GetActorRotation().Yaw
  local delta=(target-current+180)%360-180
  local step=math.max(-TURN_RATE*dt,math.min(delta,TURN_RATE*dt))
  p:K2_SetActorRotation({Pitch=0,Yaw=current+step,Roll=0},false)
 end
end
local function guarded(f) local ok,e=xpcall(f,debug.traceback);if not ok then log('ERROR '..tostring(e));finish('error') end end
RegisterKeyBind(Key.O,function() ExecuteInGameThread(function() guarded(start) end) end)
RegisterKeyBind(Key.BACKSPACE,function() ExecuteInGameThread(function() finish('cancelled') end) end)
LoopAsync(5,function() if not queued then queued=true;ExecuteInGameThread(function() guarded(state and tick or observe);queued=false end) end;return false end)
log('Candidate '..VERSION..' loaded. O=play, WASD=turn, Backspace=cancel. Game validation pending.')
