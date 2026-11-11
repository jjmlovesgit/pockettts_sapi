$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$dll = Join-Path $root 'build\sapi\pocket_sapi.dll'
$clsid = '{52586884-b3dc-46c5-a298-a49606cc5421}'
$key = 'Registry::HKEY_CURRENT_USER\SOFTWARE\Classes\CLSID\' + $clsid
if (Test-Path -LiteralPath $key) { throw 'Temporary COM override already exists; refusing to replace it.' }
$worker = Get-CimInstance Win32_Process -Filter "Name='pocket-tts.exe'" |
    Where-Object { $_.ExecutablePath -eq 'C:\Program Files\PocketTTS\pocket-tts.exe' -and
        $_.CommandLine -match 'serve --host 127\.0\.0\.1 --port 18765' }
foreach ($item in $worker) { Stop-Process -Id $item.ProcessId -Force }
try {
    $inproc = New-Item -Path ($key + '\InprocServer32') -Force
    Set-Item -LiteralPath $inproc.PSPath -Value $dll
    New-ItemProperty -LiteralPath $inproc.PSPath -Name ThreadingModel -Value Both -PropertyType String -Force | Out-Null
    Add-Type -AssemblyName System.Speech
    $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
    try {
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $s.SelectVoice('Pockettts_Elle_mono')
        $selectMs = [math]::Round($clock.Elapsed.TotalMilliseconds)
        $clock.Restart()
        $s.SetOutputToWaveFile((Join-Path $root 'results\cold-elle-sapi-dev.wav'))
        $s.Speak('Hello.')
        $s.SetOutputToNull()
        "cold_select_ms=$selectMs cold_speak_ms=$([math]::Round($clock.Elapsed.TotalMilliseconds))"
    } finally { $s.Dispose() }
} finally {
    if (Test-Path -LiteralPath $key) {
        $registered = (Get-Item -LiteralPath ($key + '\InprocServer32')).GetValue('')
        if ($registered -eq $dll) { Remove-Item -LiteralPath $key -Recurse -Force }
    }
}
