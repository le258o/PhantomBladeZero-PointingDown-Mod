param([string]$Compiler='gcc',[string]$Lua='lua',[switch]$RunTests)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scratch=Join-Path $root 'work'
$null=New-Item -ItemType Directory -Force -Path $scratch
$source=Join-Path $PSScriptRoot 'PSNative.c'
$dll=Join-Path $scratch 'PSNative.dll'
& $Compiler -std=c99 -Wall -Wextra -Werror -O2 -shared -static-libgcc $source -o $dll -lsetupapi -lhid
if($LASTEXITCODE -ne 0){throw 'Native DLL build failed'}
$relative='platform\steam\ue4ss\Mods\PointDown\Scripts'
foreach($variant in @('首次安装','已有UE4SS')){
 $destination=Join-Path (Join-Path $root $variant) $relative
 Copy-Item -LiteralPath $dll -Destination (Join-Path $destination 'PSNative.dll') -Force
}
if($RunTests){
 $test=Join-Path $scratch 'test_native.exe'
 & $Compiler -std=c99 -Wall -Wextra -Werror -O2 -DPBZ_TEST $source -o $test -lsetupapi -lhid
 if($LASTEXITCODE -ne 0){throw 'Native test build failed'}
 & $test
 if($LASTEXITCODE -ne 0){throw 'Native tests failed'}
 Push-Location $root
 try {
  & $Lua (Join-Path $PSScriptRoot 'tests\test_mod.lua') (Join-Path $root ('已有UE4SS\'+$relative+'\main.lua'))
  if($LASTEXITCODE -ne 0){throw 'Lua integration tests failed'}
  & $Lua (Join-Path $PSScriptRoot 'tests\test_module.lua') $scratch
  if($LASTEXITCODE -ne 0){throw 'DLL load test failed'}
 } finally {Pop-Location}
}
Write-Output 'Built PSNative.dll and copied it into both installation variants.'
Write-Output 'Refresh the changed DLL entries in SHA256SUMS.txt before publishing a rebuilt package.'
