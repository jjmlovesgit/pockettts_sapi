param([int]$Port = 18766)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$installRoot = (Get-ItemProperty -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\PocketTTS').InstallRoot
$language = (Get-ItemProperty -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\PocketTTS').ModelLanguage
$exe = Join-Path $installRoot 'pocket-tts.exe'
$voice = Join-Path $installRoot 'voices\Alba.safetensors'
$env:HF_HUB_CACHE = Join-Path $installRoot 'models\hf'
$env:HF_HUB_OFFLINE = '1'
$out = Join-Path $root 'results\cold-start-stdout.log'
$err = Join-Path $root 'results\cold-start-stderr.log'
$url = "http://127.0.0.1:$Port"
$timer = [Diagnostics.Stopwatch]::StartNew()
$process = Start-Process -FilePath $exe -ArgumentList @('serve','--host','127.0.0.1','--port',"$Port",'--language',$language,'--default-voice',('"' + $voice + '"')) -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
try {
    $ready = $false
    for ($i = 0; $i -lt 150; $i++) {
        if ($process.HasExited) { throw "Server exited with code $($process.ExitCode). See $err" }
        try {
            $response = Invoke-WebRequest "$url/health" -UseBasicParsing -TimeoutSec 1
            if ($response.StatusCode -eq 200) { $ready = $true; break }
        } catch {}
        Start-Sleep -Milliseconds 50
    }
    if (-not $ready) { throw "Server did not become ready. See $err" }
    $healthMs = [math]::Round($timer.Elapsed.TotalMilliseconds)
    $timer.Restart()
    $response = Invoke-WebRequest "$url/tts" -Method Post -ContentType 'application/x-www-form-urlencoded' -Body 'text=Hello.' -UseBasicParsing -TimeoutSec 30
    $firstMs = [math]::Round($timer.Elapsed.TotalMilliseconds)
    $timer.Restart()
    $response2 = Invoke-WebRequest "$url/tts" -Method Post -ContentType 'application/x-www-form-urlencoded' -Body 'text=Hello.' -UseBasicParsing -TimeoutSec 30
    $warmMs = [math]::Round($timer.Elapsed.TotalMilliseconds)
    "health_ms=$healthMs first_request_ms=$firstMs warm_request_ms=$warmMs first_bytes=$($response.RawContentLength) warm_bytes=$($response2.RawContentLength)"
} finally {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
}
