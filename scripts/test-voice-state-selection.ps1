$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$exe = Join-Path $root '.benchmark-cache\rust\unpacked\pocket-tts-3.3.0-x86_64-pc-windows-msvc\pocket-tts.exe'
$prompt = Join-Path $root '.benchmark-cache\prompts\sloane_5s.wav'
$state = Join-Path $root '.benchmark-cache\prompts\sloane_5s.safetensors'
$out = Join-Path $root 'results\voice-state-request.wav'
$priorCache = $env:HF_HUB_CACHE
$priorOffline = $env:HF_HUB_OFFLINE
$env:HF_HUB_CACHE = Join-Path $root '.benchmark-cache\hf'
$env:HF_HUB_OFFLINE = '1'
$server = $null
try {
    $server = Start-Process -FilePath $exe -ArgumentList @('serve','--host','127.0.0.1','--port','18765','--language','english_7m_refl_2026-10','--default-voice',$prompt) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'results\voice-state-server.log') -RedirectStandardError (Join-Path $root 'results\voice-state-server.err.log')
    $ready = $false
    for ($i=0; $i -lt 80; $i++) {
        try { Invoke-WebRequest 'http://127.0.0.1:18765/health' -UseBasicParsing -TimeoutSec 1 | Out-Null; $ready=$true; break }
        catch { Start-Sleep -Milliseconds 100 }
    }
    if (-not $ready) { throw 'Pocket TTS Rust server did not become healthy.' }
    $response = Invoke-WebRequest -Uri 'http://127.0.0.1:18765/tts' -Method Post -Form @{
        text = 'This is a per-token cloned voice test.'
        voice_wav = Get-Item -LiteralPath $state
    } -OutFile $out -PassThru
    $file = Get-Item -LiteralPath $out
    if ($response.StatusCode -ne 200 -or $file.Length -le 44) { throw 'Per-token voice state request did not return audio.' }
    Write-Host "Per-token local voice state accepted: HTTP $($response.StatusCode), wav_bytes=$($file.Length)"
} finally {
    $expectedExe = [IO.Path]::GetFullPath($exe)
    foreach ($listener in @(Get-NetTCPConnection -LocalPort 18765 -State Listen -ErrorAction SilentlyContinue)) {
        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)" -ErrorAction SilentlyContinue
        if ($process -and [string]::Equals($process.ExecutablePath,$expectedExe,[StringComparison]::OrdinalIgnoreCase)) {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
    if ($null -eq $priorCache) { Remove-Item Env:HF_HUB_CACHE -ErrorAction SilentlyContinue } else { $env:HF_HUB_CACHE=$priorCache }
    if ($null -eq $priorOffline) { Remove-Item Env:HF_HUB_OFFLINE -ErrorAction SilentlyContinue } else { $env:HF_HUB_OFFLINE=$priorOffline }
}
