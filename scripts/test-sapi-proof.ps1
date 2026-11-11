param([switch]$MachineWide, [switch]$Latency, [switch]$SystemSpeech)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$dll = Join-Path $root 'build\sapi\pocket_sapi.dll'
$benchmarkExe = Join-Path $root '.benchmark-cache\rust\unpacked\pocket-tts-3.3.0-x86_64-pc-windows-msvc\pocket-tts.exe'
$installRoot = $null
try { $installRoot = (Get-ItemProperty -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\PocketTTS' -Name InstallRoot -ErrorAction Stop).InstallRoot } catch {}
$installedExe = if ($installRoot) { Join-Path $installRoot 'pocket-tts.exe' } else { $null }
$exe = if ($installedExe -and (Test-Path -LiteralPath $installedExe)) { $installedExe } else { $benchmarkExe }
$modelCache = if ($installRoot -and (Test-Path -LiteralPath (Join-Path $installRoot 'models\hf'))) {
    Join-Path $installRoot 'models\hf'
} else {
    Join-Path $root '.benchmark-cache\hf'
}
$prompt = Join-Path $root '.benchmark-cache\prompts\sloane_5s.wav'
$voiceState = Join-Path $root '.benchmark-cache\prompts\sloane_5s.safetensors'
$promptRateUtility = Join-Path $root 'build\sapi\pocket_prompt_rate.exe'
$ratePromptDir = Join-Path $root 'results\sapi-rate-prompts'
$rateSlowPrompt = Join-Path $ratePromptDir 'slow.wav'
$rateNormalPrompt = Join-Path $ratePromptDir 'normal.wav'
$rateFastPrompt = Join-Path $ratePromptDir 'fast.wav'
$out = Join-Path $root 'results\sapi-proof.wav'
$quietOut = Join-Path $root 'results\sapi-volume-25.wav'
$log = Join-Path $root 'results\sapi-server.log'
$errLog = Join-Path $root 'results\sapi-server.err.log'
$probe = Join-Path $root 'build\sapi\event_probe.exe'
$clsid = '{52586884-b3dc-46c5-a298-a49606cc5421}'
$registryHive = if ($MachineWide) { 'HKEY_LOCAL_MACHINE' } else { 'HKEY_CURRENT_USER' }
$registryProvider = if ($MachineWide) { 'Registry::HKEY_LOCAL_MACHINE' } else { 'Registry::HKEY_CURRENT_USER' }
$comKey = $registryProvider + '\SOFTWARE\Classes\CLSID\' + $clsid
$tokenKey = $registryProvider + '\SOFTWARE\Microsoft\Speech\Voices\Tokens\PocketTTSProof7m'
$probePrefix = if ($MachineWide) { @('--machine') } else { @() }
function Stop-ProofServer {
    $expectedExe = [IO.Path]::GetFullPath($exe)
    $listeners = @(Get-NetTCPConnection -LocalPort 18765 -State Listen -ErrorAction SilentlyContinue)
    foreach ($listener in $listeners) {
        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)" -ErrorAction SilentlyContinue
        if ($process -and [string]::Equals($process.ExecutablePath, $expectedExe, [StringComparison]::OrdinalIgnoreCase)) {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
}
if (-not (Test-Path -LiteralPath $dll)) { throw 'Build the SAPI DLL first.' }
if (-not (Test-Path -LiteralPath $probe)) { throw 'Build the SAPI event probe first.' }
if (-not (Test-Path -LiteralPath $exe)) { throw 'Official Rust binary missing.' }
if (-not (Test-Path -LiteralPath $prompt)) { throw 'Benchmark prompt missing.' }
if (-not (Test-Path -LiteralPath $voiceState)) { throw 'Exported proof voice state missing.' }
if (-not (Test-Path -LiteralPath $promptRateUtility)) { throw 'Prompt rate utility missing.' }
if (Test-Path -LiteralPath $tokenKey) {
    $owner = (Get-ItemProperty -LiteralPath $tokenKey -Name CLSID -ErrorAction SilentlyContinue).CLSID
    if ($owner -ne $clsid) { throw 'Proof token key exists but is not owned by this proof; refusing to alter it.' }
    Remove-Item -LiteralPath $tokenKey -Recurse -Force
}
if (Test-Path -LiteralPath $comKey) {
    $ownerDll = (Get-Item -LiteralPath ($comKey + '\InprocServer32') -ErrorAction SilentlyContinue).GetValue('')
    if ($ownerDll -ne $dll) { throw 'Proof CLSID key points to another DLL; refusing to alter it.' }
    Remove-Item -LiteralPath $comKey -Recurse -Force
}
New-Item -ItemType Directory -Force -Path (Join-Path $root 'results') | Out-Null
New-Item -ItemType Directory -Force -Path $ratePromptDir | Out-Null
& $promptRateUtility $prompt $rateSlowPrompt 0.70
if ($LASTEXITCODE -ne 0) { throw 'Could not prepare slow proof prompt.' }
Copy-Item -LiteralPath $prompt -Destination $rateNormalPrompt -Force
& $promptRateUtility $prompt $rateFastPrompt 1.40
if ($LASTEXITCODE -ne 0) { throw 'Could not prepare fast proof prompt.' }
$priorCache = $env:HF_HUB_CACHE
$priorOffline = $env:HF_HUB_OFFLINE
$env:HF_HUB_CACHE = $modelCache
$env:HF_HUB_OFFLINE = '1'
foreach ($pace in @('slow','fast')) {
    $inputPath = if ($pace -eq 'slow') { $rateSlowPrompt } else { $rateFastPrompt }
    $statePath = [IO.Path]::ChangeExtension($inputPath, '.safetensors')
    & $exe export-voice --quiet --language english_7m_refl_2026-10 $inputPath $statePath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $statePath)) {
        throw "Could not prepare cached $pace rate state for the SAPI proof."
    }
}
$server = $null
try {
    $server = Start-Process -FilePath $exe -ArgumentList @('serve', '--host', '127.0.0.1', '--port', '18765', '--language', 'english_7m_refl_2026-10', '--default-voice', $prompt) -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError $errLog
    $ready = $false
    for ($i=0; $i -lt 80; $i++) {
        if ($server.HasExited) { throw "Rust server exited: $($server.ExitCode)" }
        try {
            $health = Invoke-WebRequest -Uri 'http://127.0.0.1:18765/health' -UseBasicParsing -TimeoutSec 1
            if ($health.StatusCode -eq 200) { $ready = $true; break }
        } catch { Start-Sleep -Milliseconds 100 }
    }
    if (-not $ready) { throw 'Rust server did not become healthy.' }
    $inproc = New-Item -Path ($comKey + '\InprocServer32') -Force
    Set-Item -LiteralPath $inproc.PSPath -Value $dll
    New-ItemProperty -LiteralPath $inproc.PSPath -Name ThreadingModel -Value Both -PropertyType String -Force | Out-Null
    New-Item -Path ($tokenKey + '\Attributes') -Force | Out-Null
    Set-Item -LiteralPath $tokenKey -Value 'Pocket TTS 6.9M ReFL Proof'
    New-ItemProperty -LiteralPath $tokenKey -Name CLSID -Value $clsid -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath $tokenKey -Name VoiceStatePath -Value $voiceState -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath $tokenKey -Name VoicePromptSlowPath -Value $rateSlowPrompt -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath $tokenKey -Name VoicePromptNormalPath -Value $rateNormalPrompt -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath $tokenKey -Name VoicePromptFastPath -Value $rateFastPrompt -PropertyType String -Force | Out-Null
    $attributes = $tokenKey + '\Attributes'
    foreach ($entry in @{'Name'='Pocket TTS 6.9M ReFL Proof'; 'Language'='409'; 'Gender'='Female'; 'Age'='Adult'; 'Vendor'='Kyutai / Pocket TTS SAPI proof'}.GetEnumerator()) {
        New-ItemProperty -LiteralPath $attributes -Name $entry.Key -Value $entry.Value -PropertyType String -Force | Out-Null
    }
    $selected = New-Object -ComObject SAPI.SpObjectToken
    $selected.SetId($registryHive + '\SOFTWARE\Microsoft\Speech\Voices\Tokens\PocketTTSProof7m', '', $false)
    $voice = New-Object -ComObject SAPI.SpVoice
    if ($MachineWide) {
        $enumerated = @($voice.GetVoices() | ForEach-Object { $_.GetDescription() })
        if ($enumerated -notcontains 'Pocket TTS 6.9M ReFL Proof') {
            throw 'Machine-wide Pocket TTS token was not enumerated by SAPI.SpVoice.GetVoices().'
        }
    }
    $voice.Voice = $selected
    $stream = New-Object -ComObject SAPI.SpFileStream
    try {
        $stream.Format.Type = 26 # SAFT24kHz16BitMono
        $stream.Open($out, 3, $false)
        $voice.AudioOutputStream = $stream
        $voice.Volume = 100
        $spoken = $voice.Speak('Pocket TTS is speaking through Windows SAPI. This proof uses a local cloned voice.')
        $stream.Close()
        $stream.Open($quietOut, 3, $false)
        $voice.Volume = 25
        $voice.Speak('Pocket TTS is speaking through Windows SAPI. This proof uses a local cloned voice.') | Out-Null
        $voice.Volume = 100
    } finally {
        $stream.Close()
    }
    $file = Get-Item -LiteralPath $out -ErrorAction Stop
    if ($file.Length -le 44) { throw 'SAPI output WAV has no audio.' }
    $quietFile = Get-Item -LiteralPath $quietOut -ErrorAction Stop
    if ($quietFile.Length -le 44) { throw 'Reduced-volume SAPI output WAV has no audio.' }
    if ($SystemSpeech) {
        Add-Type -AssemblyName System.Speech
        $managed = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $managedOut = Join-Path $root 'results\system-speech-proof.wav'
        $entryEventName = 'Local\PocketTTSEngineEntry_' + [guid]::NewGuid().ToString('N')
        $entryCreated = $false
        $entryEvent = [System.Threading.EventWaitHandle]::new($false, [System.Threading.EventResetMode]::ManualReset, $entryEventName, [ref]$entryCreated)
        $previousEntryEvent = $env:POCKETTTS_SAPI_ENGINE_ENTRY_EVENT
        $previousFragmentTrace = $env:POCKETTTS_SAPI_FRAGMENT_TRACE
        $fragmentTrace = Join-Path $root 'results\system-speech-fragments.txt'
        Remove-Item -LiteralPath $fragmentTrace -Force -ErrorAction SilentlyContinue
        try {
            $env:POCKETTTS_SAPI_ENGINE_ENTRY_EVENT = $entryEventName
            $env:POCKETTTS_SAPI_FRAGMENT_TRACE = $fragmentTrace
            $managedVoices = @($managed.GetInstalledVoices() | ForEach-Object { $_.VoiceInfo.Name })
            if ($managedVoices -notcontains 'Alba (Pocket TTS)') {
                throw "System.Speech did not enumerate the installed machine voice. Voices: $($managedVoices -join ', ')"
            }
            $managed.SelectVoice('Alba (Pocket TTS)')
            $managed.SetOutputToWaveFile($managedOut)
            $managed.Speak('System Speech is speaking with the local Pocket TTS voice.')
            $managed.SetOutputToNull()
            if (-not $entryEvent.WaitOne(0)) {
                throw 'System.Speech did not call the Pocket TTS SAPI engine.'
            }
        } finally {
            if ($null -eq $previousEntryEvent) { Remove-Item Env:POCKETTTS_SAPI_ENGINE_ENTRY_EVENT -ErrorAction SilentlyContinue }
            else { $env:POCKETTTS_SAPI_ENGINE_ENTRY_EVENT = $previousEntryEvent }
            if ($null -eq $previousFragmentTrace) { Remove-Item Env:POCKETTTS_SAPI_FRAGMENT_TRACE -ErrorAction SilentlyContinue }
            else { $env:POCKETTTS_SAPI_FRAGMENT_TRACE = $previousFragmentTrace }
            $entryEvent.Dispose()
            $managed.Dispose()
        }
        $managedFile = Get-Item -LiteralPath $managedOut -ErrorAction Stop
        $managedBytes = [IO.File]::ReadAllBytes($managedOut)
        $managedPeak = 0
        for ($i = 44; $i + 1 -lt $managedBytes.Length; $i += 2) {
            $sample = [math]::Abs([BitConverter]::ToInt16($managedBytes, $i))
            if ($sample -gt $managedPeak) { $managedPeak = $sample }
        }
        $managedRate = [BitConverter]::ToInt32($managedBytes, 24)
        $managedDataBytes = [math]::Max(0, $managedFile.Length - 46)
        $managedDuration = if ($managedRate -gt 0) { $managedDataBytes / $managedRate / 2 } else { 0 }
        if ($managedFile.Length -le 46 -or $managedPeak -lt 100 -or $managedDuration -lt 1.5) {
            throw "System.Speech output was silent, truncated, or empty: bytes=$($managedFile.Length) duration=$([math]::Round($managedDuration, 2))s peak=$managedPeak"
        }
        Write-Host "System.Speech passed: voice=Alba (Pocket TTS); bytes=$($managedFile.Length); duration=$([math]::Round($managedDuration, 2))s; peak=$managedPeak; output=$managedOut"
    }
    $fullBytes = [IO.File]::ReadAllBytes($out)
    $quietBytes = [IO.File]::ReadAllBytes($quietOut)
    $fullSquares = [double]0
    $quietSquares = [double]0
    for ($i = 44; $i + 1 -lt $fullBytes.Length; $i += 2) {
        $sample = [BitConverter]::ToInt16($fullBytes, $i)
        $fullSquares += [double]$sample * $sample
    }
    for ($i = 44; $i + 1 -lt $quietBytes.Length; $i += 2) {
        $sample = [BitConverter]::ToInt16($quietBytes, $i)
        $quietSquares += [double]$sample * $sample
    }
    $fullRms = [math]::Sqrt($fullSquares / (($fullBytes.Length - 44) / 2))
    $quietRms = [math]::Sqrt($quietSquares / (($quietBytes.Length - 44) / 2))
    if ($quietRms -ge $fullRms * 0.35) { throw "Volume gain check failed: full=$fullRms reduced=$quietRms" }
    if (-not $MachineWide) {
        & $probe @probePrefix
        if ($LASTEXITCODE -ne 0) { throw "SAPI event probe failed: $LASTEXITCODE" }
        $rateCaptureDir = Join-Path $root 'results\sapi-rate-captures'
        & $probe @probePrefix --rate $rateCaptureDir
        if ($LASTEXITCODE -ne 0) { throw "SAPI rate probe failed: $LASTEXITCODE" }
        & $probe @probePrefix --cancel
        if ($LASTEXITCODE -ne 0) { throw "SAPI cancellation probe failed: $LASTEXITCODE" }
        & $probe @probePrefix --ssml
        if ($LASTEXITCODE -ne 0) { throw "SAPI SSML fragment/silence probe failed: $LASTEXITCODE" }
        & $probe @probePrefix --limit
        if ($LASTEXITCODE -ne 0) { throw "SAPI text-limit probe failed: $LASTEXITCODE" }
        if ($Latency) {
            foreach ($rateCase in @(@{Name='normal';Value=0}, @{Name='slow';Value=-5}, @{Name='fast';Value=5})) {
                $captureDir = Join-Path $root ('results\sapi-latency-captures-' + $rateCase.Name)
                & $probe @probePrefix --latency $captureDir --latency-rate $rateCase.Value
                if ($LASTEXITCODE -ne 0) { throw "SAPI $($rateCase.Name) first-audio latency probe failed: $LASTEXITCODE" }
            }
        }
        Stop-ProofServer
        if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Milliseconds 200
        if ($installRoot) {
            & $probe @probePrefix
            if ($LASTEXITCODE -ne 0) { throw "SAPI worker auto-start after stop failed: $LASTEXITCODE" }
        } else {
            & $probe @probePrefix --missing
            if ($LASTEXITCODE -ne 0) { throw "SAPI missing-server probe failed: $LASTEXITCODE" }
        }
    }
    Write-Host "SAPI proof passed: $($selected.GetDescription()); spoken=$spoken; full_rms=$fullRms; volume25_rms=$quietRms; wav_bytes=$($file.Length); output=$out"
} finally {
    if (Test-Path -LiteralPath $tokenKey) {
        $registered = (Get-ItemProperty -LiteralPath $tokenKey -Name CLSID -ErrorAction SilentlyContinue).CLSID
        if ($registered -eq $clsid) { Remove-Item -LiteralPath $tokenKey -Recurse -Force }
    }
    if (Test-Path -LiteralPath $comKey) {
        $registeredDll = (Get-Item -LiteralPath ($comKey + '\InprocServer32') -ErrorAction SilentlyContinue).GetValue('')
        if ($registeredDll -eq $dll) { Remove-Item -LiteralPath $comKey -Recurse -Force }
    }
    if (-not $installRoot) {
        Stop-ProofServer
        if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
    }
    if ($null -eq $priorCache) { Remove-Item Env:HF_HUB_CACHE -ErrorAction SilentlyContinue } else { $env:HF_HUB_CACHE = $priorCache }
    if ($null -eq $priorOffline) { Remove-Item Env:HF_HUB_OFFLINE -ErrorAction SilentlyContinue } else { $env:HF_HUB_OFFLINE = $priorOffline }
}
