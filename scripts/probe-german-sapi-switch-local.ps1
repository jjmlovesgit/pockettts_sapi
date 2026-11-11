$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$testRoot = Join-Path $root 'build\sapi-test\install'
$env:POCKETTTS_SAPI_TEST_ROOT = $testRoot
$env:POCKETTTS_SAPI_FRAGMENT_TRACE = Join-Path $root 'results\german-switch-local-trace.txt'
$env:POCKETTTS_SAPI_HTTP_TRACE = '1'
$clsid = '{2F28F1B0-0E38-49E7-9F14-0CCB3C11C709}'
$com = "Registry::HKEY_CURRENT_USER\Software\Classes\CLSID\$clsid"
$tokenRoot = 'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Speech\Voices\Tokens'
$tokens = @('PocketTTSEnglishProbe','PocketTTSGermanProbe')
if (Get-NetTCPConnection -LocalPort 18765 -State Listen -ErrorAction SilentlyContinue) { throw 'Port 18765 is in use; close Pocket TTS apps before the isolated probe.' }
if (Test-Path $com) { throw 'Temporary COM registration already exists.' }
foreach ($id in $tokens) { if (Test-Path (Join-Path $tokenRoot $id)) { throw "Temporary voice token already exists: $id" } }
$modelRevEnglish = 'db04f0e653473e5c7333c69686ac92b7460b0c1d'
$tokenRevEnglish = '08ffc58775e62aad9409511b9591c9af626270f3'
$modelRevGerman = '3e82814a68665eec246ff649b14c71331f955c06'
$tokenRevGerman = '4e1e0a3e611c51c0b4ed8174fc10f32a54644303'
$voiceRevGerman = 'a3055dcb533cf2ec90458008a01e7cef550bae2a'
$inputs = @(
    @{From=(Join-Path $root '.benchmark-cache\rust\unpacked\pocket-tts-3.3.0-x86_64-pc-windows-msvc\pocket-tts.exe'); To=(Join-Path $testRoot 'pocket-tts.exe')},
    @{From=(Join-Path $root ".benchmark-cache\hf\models--kyutai--pocket-tts\snapshots\$modelRevEnglish\languages\english_7m_refl_2026-10\model.safetensors"); To=(Join-Path $testRoot "models\hf\models--kyutai--pocket-tts\snapshots\$modelRevEnglish\languages\english_7m_refl_2026-10\model.safetensors")},
    @{From=(Join-Path $root ".benchmark-cache\hf\models--kyutai--pocket-tts-without-voice-cloning\snapshots\$tokenRevEnglish\languages\english_7m_refl_2026-10\tokenizer.model"); To=(Join-Path $testRoot "models\hf\models--kyutai--pocket-tts-without-voice-cloning\snapshots\$tokenRevEnglish\languages\english_7m_refl_2026-10\tokenizer.model")},
    @{From=(Join-Path $root ".benchmark-cache\hf\models--kyutai--pocket-tts\snapshots\$modelRevGerman\languages\german\model.safetensors"); To=(Join-Path $testRoot "models\hf\models--kyutai--pocket-tts\snapshots\$modelRevGerman\languages\german\model.safetensors")},
    @{From=(Join-Path $root ".benchmark-cache\hf\models--kyutai--pocket-tts-without-voice-cloning\snapshots\$tokenRevGerman\languages\german\tokenizer.json"); To=(Join-Path $testRoot "models\hf\models--kyutai--pocket-tts-without-voice-cloning\snapshots\$tokenRevGerman\languages\german\tokenizer.json")},
    @{From=(Join-Path $root 'assets\Butter.safetensors'); To=(Join-Path $testRoot 'voices\Butter.safetensors')},
    @{From=(Join-Path $root ".benchmark-cache\hf\models--kyutai--pocket-tts-without-voice-cloning\snapshots\$voiceRevGerman\languages\german\embeddings\juergen.safetensors"); To=(Join-Path $testRoot 'voices\Juergen.safetensors')}
)
foreach ($item in $inputs) {
    if (!(Test-Path -LiteralPath $item.From)) { throw "Missing input: $($item.From)" }
    New-Item -ItemType Directory -Path (Split-Path $item.To) -Force | Out-Null
    if (!(Test-Path -LiteralPath $item.To) -or (Get-Item $item.To).Length -ne (Get-Item $item.From).Length) { Copy-Item -LiteralPath $item.From -Destination $item.To -Force }
}
try {
    New-Item -Path (Join-Path $com 'InprocServer32') -Force | Out-Null
    Set-Item -LiteralPath (Join-Path $com 'InprocServer32') -Value (Join-Path $root 'build\sapi-test\pocket_sapi_test.dll')
    New-ItemProperty -LiteralPath (Join-Path $com 'InprocServer32') -Name ThreadingModel -Value Both -PropertyType String -Force | Out-Null
    $specs = @(
        @{Id=$tokens[0];Name='Butter English Probe';Language='409';Model='english_7m_refl_2026-10';State=(Join-Path $testRoot 'voices\Butter.safetensors')},
        @{Id=$tokens[1];Name='Juergen German Probe';Language='407';Model='german';State=(Join-Path $testRoot 'voices\Juergen.safetensors')}
    )
    foreach ($spec in $specs) {
        $key = Join-Path $tokenRoot $spec.Id
        New-Item -Path (Join-Path $key 'Attributes') -Force | Out-Null
        Set-Item -LiteralPath $key -Value $spec.Name
        foreach ($entry in @{CLSID=$clsid;ModelLanguage=$spec.Model;VoiceStatePath=$spec.State}.GetEnumerator()) { New-ItemProperty -LiteralPath $key -Name $entry.Key -Value $entry.Value -PropertyType String -Force | Out-Null }
        foreach ($entry in @{Name=$spec.Name;Language=$spec.Language;Gender='Unknown';Age='Adult'}.GetEnumerator()) { New-ItemProperty -LiteralPath (Join-Path $key 'Attributes') -Name $entry.Key -Value $entry.Value -PropertyType String -Force | Out-Null }
    }
    $results = @()
    foreach ($case in @(
        @{Name='english';Id=$tokens[0];Text='Hello. This is the English voice.'},
        @{Name='german-first';Id=$tokens[1];Text='Freut mich! Es freut mich, dich kennenzulernen.'},
        @{Name='german-warm';Id=$tokens[1];Text='Guten Morgen. Das ist der zweite Satz.'}
    )) {
        $voice = New-Object -ComObject SAPI.SpVoice
        $selected = New-Object -ComObject SAPI.SpObjectToken
        $selected.SetId("HKEY_CURRENT_USER\SOFTWARE\Microsoft\Speech\Voices\Tokens\$($case.Id)", '', $false)
        $voice.Voice = $selected
        $stream = New-Object -ComObject SAPI.SpFileStream
        $output = Join-Path $root "results\german-switch-local-$($case.Name).wav"
        $stream.Format.Type = 26
        $stream.Open($output, 3, $false)
        $voice.AudioOutputStream = $stream
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $null = $voice.Speak($case.Text)
        $timer.Stop()
        $stream.Close()
        $size = (Get-Item -LiteralPath $output).Length
        if ($size -le 44) { throw "No audio for $($case.Name)" }
        $workerPid = (Get-NetTCPConnection -LocalPort 18765 -State Listen | Select-Object -First 1).OwningProcess
        $results += [pscustomobject]@{Case=$case.Name;Milliseconds=$timer.ElapsedMilliseconds;WorkerPid=$workerPid;WavBytes=$size;Output=$output}
        [Runtime.InteropServices.Marshal]::ReleaseComObject($stream) | Out-Null
        [Runtime.InteropServices.Marshal]::ReleaseComObject($selected) | Out-Null
        [Runtime.InteropServices.Marshal]::ReleaseComObject($voice) | Out-Null
    }
    if ($results[0].WorkerPid -eq $results[1].WorkerPid) { throw 'English to German did not switch workers.' }
    if ($results[1].WorkerPid -ne $results[2].WorkerPid) { throw 'Second German sentence reloaded the worker.' }
    $results | Format-Table -AutoSize | Out-String | Set-Content -LiteralPath (Join-Path $root 'results\german-switch-local-result.txt')
    Get-Content (Join-Path $root 'results\german-switch-local-result.txt')
} finally {
    & (Join-Path $root 'scripts\stop-worker.ps1') -InstallRoot $testRoot
    foreach ($id in $tokens) { $key=Join-Path $tokenRoot $id; if(Test-Path $key){Remove-Item -LiteralPath $key -Recurse -Force} }
    if (Test-Path $com) { Remove-Item -LiteralPath $com -Recurse -Force }
    $workerKey='Registry::HKEY_CURRENT_USER\Software\PocketTTS'
    if(Test-Path $workerKey){Remove-ItemProperty -LiteralPath $workerKey -Name WorkerLanguage,WorkerVoice -ErrorAction SilentlyContinue}
}
