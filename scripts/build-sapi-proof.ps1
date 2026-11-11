$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$out = Join-Path $root 'build\sapi'
$soundTouchArchive = Join-Path $root 'build\soundtouch-2.3.3.tar.gz'
if (-not (Test-Path -LiteralPath $soundTouchArchive) -or (Get-FileHash -LiteralPath $soundTouchArchive -Algorithm SHA256).Hash -ne '43B23DFAC2F64A3AFF55D64BE096FFC7B73842C3F5665CAFF44975633A975A99') {
    throw 'Pinned SoundTouch 2.3.3 source archive is missing or has a hash mismatch.'
}
$soundTouchVersion = Join-Path $root 'third_party\soundtouch\include\SoundTouch.h'
if (-not (Select-String -LiteralPath $soundTouchVersion -Pattern 'SOUNDTOUCH_VERSION_ID\s+\(20303\)' -Quiet)) {
    throw 'The vendored SoundTouch source is not the pinned 2.3.3 version.'
}
New-Item -ItemType Directory -Force -Path $out | Out-Null
$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio Build Tools are missing.' }
$vcvars = & $vswhere -latest -products '*' -find 'VC\Auxiliary\Build\vcvars64.bat'
if (-not $vcvars) { throw 'The Visual Studio x64 C++ toolchain is missing.' }
$source = Join-Path $root 'src\sapi\pocket_sapi.cpp'
$module = Join-Path $root 'src\sapi\pocket_sapi.def'
$probe = Join-Path $root 'src\sapi\event_probe.cpp'
$promptRate = Join-Path $root 'src\sapi\prompt_rate.cpp'
$soundTouchAdapter = Join-Path $root 'src\sapi\soundtouch_adapter.cpp'
$soundTouchInclude = Join-Path $root 'third_party\soundtouch\include'
$soundTouchSources = @('AAFilter.cpp','BPMDetect.cpp','cpu_detect_x86.cpp','FIFOSampleBuffer.cpp','FIRFilter.cpp','InterpolateCubic.cpp','InterpolateLinear.cpp','InterpolateShannon.cpp','mmx_optimized.cpp','PeakFinder.cpp','RateTransposer.cpp','SoundTouch.cpp','sse_optimized.cpp','TDStretch.cpp') | ForEach-Object { Join-Path $root ('third_party\soundtouch\source\SoundTouch\' + $_) }
$soundTouchSources = ($soundTouchSources | ForEach-Object { '"' + $_ + '"' }) -join ' '
$command = 'call "' + $vcvars + '" >nul && cd /d "' + $out + '" && cl /nologo /std:c++17 /utf-8 /EHsc /LD /O2 /D _WINDLL "' + $source + '" /link /DEF:"' + $module + '" winhttp.lib ole32.lib'
& cmd.exe /d /s /c $command
if ($LASTEXITCODE -ne 0) { throw "SAPI proof build failed: $LASTEXITCODE" }
$command = 'call "' + $vcvars + '" >nul && cd /d "' + $out + '" && cl /nologo /std:c++17 /utf-8 /EHsc /O2 "' + $probe + '" /link sapi.lib ole32.lib'
& cmd.exe /d /s /c $command
if ($LASTEXITCODE -ne 0) { throw "SAPI event probe build failed: $LASTEXITCODE" }
$command = 'call "' + $vcvars + '" >nul && cd /d "' + $out + '" && cl /nologo /std:c++17 /utf-8 /EHsc /O2 /LD /D SOUNDTOUCH_FLOAT_SAMPLES /I"' + $soundTouchInclude + '" "' + $soundTouchAdapter + '" ' + $soundTouchSources + ' /link /OUT:pocket_soundtouch.dll'
& cmd.exe /d /s /c $command
if ($LASTEXITCODE -ne 0) { throw "SoundTouch adapter build failed: $LASTEXITCODE" }
$command = 'call "' + $vcvars + '" >nul && cd /d "' + $out + '" && cl /nologo /std:c++17 /utf-8 /EHsc /O2 /Fepocket_prompt_rate.exe /I"' + (Join-Path $root 'src\sapi') + '" "' + $promptRate + '" soundtouch_adapter.lib'
& cmd.exe /d /s /c $command
if ($LASTEXITCODE -ne 0) { throw "Prompt rate utility build failed: $LASTEXITCODE" }
Write-Host "Built $out\pocket_sapi.dll"
