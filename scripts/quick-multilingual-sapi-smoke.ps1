$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$testRoot=Join-Path $root 'build\sapi-test\quick-install'
$manifest=Get-Content (Join-Path $root 'packaging\language-packs.json') -Raw | ConvertFrom-Json
$sourceCache=Join-Path $root '.benchmark-cache\hf'
$runtime=Join-Path $root '.benchmark-cache\rust\unpacked\pocket-tts-3.3.0-x86_64-pc-windows-msvc\pocket-tts.exe'
$testDll=Join-Path $root 'build\sapi-test\pocket_sapi_test.dll'
$clsid='{2F28F1B0-0E38-49E7-9F14-0CCB3C11C709}'
$com="Registry::HKEY_CURRENT_USER\Software\Classes\CLSID\$clsid"
$tokenRoot='Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Speech\Voices\Tokens'
$cases=@(
    @{Id='french';Text='Bonjour ! Ravi de faire votre connaissance.'},
    @{Id='italian';Text='Buongiorno! Piacere di conoscerti.'},
    @{Id='spanish';Text='¡Buenos días! Mucho gusto en conocerte.'},
    @{Id='portuguese';Text='Bom dia! Prazer em conhecer você.'},
    @{Id='dutch';Text='Goedemorgen! Leuk je te ontmoeten.'}
)
if (Test-Path -LiteralPath $testRoot) { throw "Test directory already exists: $testRoot" }
if (Test-Path -LiteralPath $com) { throw "Test COM class already exists: $com" }
if (-not (Test-Path -LiteralPath $testDll)) { throw "Test SAPI DLL missing: $testDll" }
$workspace=[IO.Path]::GetFullPath($root).TrimEnd('\')+'\'
if (-not [IO.Path]::GetFullPath($testRoot).StartsWith($workspace,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test directory.' }
$tokens=@($cases | ForEach-Object { 'PocketTTSQuick.'+$_.Id })
foreach ($id in $tokens) { if (Test-Path -LiteralPath (Join-Path $tokenRoot $id)) { throw "Test token already exists: $id" } }
$env:POCKETTTS_SAPI_TEST_ROOT=$testRoot
$results=@()
try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    Copy-Item -LiteralPath $runtime -Destination (Join-Path $testRoot 'pocket-tts.exe')
    foreach ($case in $cases) {
        $pack=@($manifest.packs | Where-Object id -eq $case.Id)[0]
        foreach ($asset in $pack.assets) {
            $repoKey=([string]$asset.repository) -replace '/','--'
            $source=Join-Path $sourceCache "models--$repoKey\snapshots\$($asset.revision)\$(($asset.path -replace '/','\'))"
            $target=Join-Path $testRoot (($asset.installPath -replace '/','\'))
            if (-not (Test-Path -LiteralPath $source)) { throw "Missing verified source: $source" }
            New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $target
        }
    }
    New-Item -Path (Join-Path $com 'InprocServer32') -Force | Out-Null
    Set-Item -LiteralPath (Join-Path $com 'InprocServer32') -Value $testDll
    New-ItemProperty -LiteralPath (Join-Path $com 'InprocServer32') -Name ThreadingModel -Value Both -PropertyType String -Force | Out-Null
    foreach ($case in $cases) {
        $pack=@($manifest.packs | Where-Object id -eq $case.Id)[0]
        $id='PocketTTSQuick.'+$case.Id
        $key=Join-Path $tokenRoot $id
        $state=Join-Path $testRoot (($pack.assets | Where-Object installPath -Like 'voices/*' | Select-Object -First 1).installPath -replace '/','\')
        New-Item -Path (Join-Path $key 'Attributes') -Force | Out-Null
        Set-Item -LiteralPath $key -Value $pack.voiceName
        foreach ($entry in @{CLSID=$clsid;ModelLanguage=$pack.modelLanguage;VoiceStatePath=$state}.GetEnumerator()) { New-ItemProperty -LiteralPath $key -Name $entry.Key -Value $entry.Value -PropertyType String -Force | Out-Null }
        foreach ($entry in @{Name=$pack.voiceName;Language=$pack.lcid;Gender=$pack.gender;Age='Adult'}.GetEnumerator()) { New-ItemProperty -LiteralPath (Join-Path $key 'Attributes') -Name $entry.Key -Value $entry.Value -PropertyType String -Force | Out-Null }
    }
    & (Join-Path $root 'scripts\stop-worker.ps1') -InstallRoot 'C:\Program Files\PocketTTS'
    if (Get-NetTCPConnection -LocalPort 18765 -State Listen -ErrorAction SilentlyContinue) { throw 'Port 18765 is still in use.' }
    foreach ($case in $cases) {
        $id='PocketTTSQuick.'+$case.Id
        $voice=New-Object -ComObject SAPI.SpVoice
        $selected=New-Object -ComObject SAPI.SpObjectToken
        $stream=New-Object -ComObject SAPI.SpFileStream
        try {
            $selected.SetId("HKEY_CURRENT_USER\SOFTWARE\Microsoft\Speech\Voices\Tokens\$id",'', $false)
            $voice.Voice=$selected
            $output=Join-Path $root "results\quick-sapi-$($case.Id).wav"
            $stream.Format.Type=26
            $stream.Open($output,3,$false)
            $voice.AudioOutputStream=$stream
            $timer=[Diagnostics.Stopwatch]::StartNew()
            try { $null=$voice.Speak($case.Text) } finally { $timer.Stop(); $stream.Close() }
            $bytes=(Get-Item -LiteralPath $output).Length
            if ($bytes -le 44) { throw "No audio from $($case.Id)" }
            $worker=Get-ItemProperty 'Registry::HKEY_CURRENT_USER\Software\PocketTTS' -ErrorAction Stop
            if ($worker.WorkerLanguage -ne $case.Id) { throw "Wrong model loaded for $($case.Id): $($worker.WorkerLanguage)" }
            $results += [pscustomobject]@{Language=$case.Id;Milliseconds=$timer.ElapsedMilliseconds;WavBytes=$bytes;Output=$output}
        } finally {
            [Runtime.InteropServices.Marshal]::ReleaseComObject($stream) | Out-Null
            [Runtime.InteropServices.Marshal]::ReleaseComObject($selected) | Out-Null
            [Runtime.InteropServices.Marshal]::ReleaseComObject($voice) | Out-Null
        }
    }
    $results | Format-Table -AutoSize | Out-String | Write-Host
    $results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'results\quick-multilingual-sapi-result.json') -Encoding utf8
} finally {
    & (Join-Path $root 'scripts\stop-worker.ps1') -InstallRoot $testRoot
    foreach ($id in $tokens) { $key=Join-Path $tokenRoot $id; if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force } }
    if (Test-Path -LiteralPath $com) { Remove-Item -LiteralPath $com -Recurse -Force }
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
    Remove-ItemProperty -LiteralPath 'Registry::HKEY_CURRENT_USER\Software\PocketTTS' -Name WorkerLanguage,WorkerVoice -ErrorAction SilentlyContinue
}
