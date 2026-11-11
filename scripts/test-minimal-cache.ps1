$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$exe=Join-Path $root '.benchmark-cache\rust\unpacked\pocket-tts-3.3.0-x86_64-pc-windows-msvc\pocket-tts.exe'
$prompt=Join-Path $root '.benchmark-cache\prompts\sloane_5s.safetensors'
$priorCache=$env:HF_HUB_CACHE
$priorOffline=$env:HF_HUB_OFFLINE
$env:HF_HUB_CACHE=Join-Path $root '.benchmark-cache\hf-minimal'
$env:HF_HUB_OFFLINE='1'
$server=$null
try {
    $server=Start-Process $exe -ArgumentList @('serve','--host','127.0.0.1','--port','18767','--language','english_7m_refl_2026-10','--default-voice',$prompt) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root 'results\minimal-cache.log') -RedirectStandardError (Join-Path $root 'results\minimal-cache.err.log')
    $ready=$false
    for($i=0;$i -lt 80;$i++) {
        try { Invoke-WebRequest 'http://127.0.0.1:18767/health' -UseBasicParsing -TimeoutSec 1 | Out-Null; $ready=$true; break }
        catch { Start-Sleep -Milliseconds 100 }
    }
    if(-not $ready) { Get-Content (Join-Path $root 'results\minimal-cache.err.log') -Tail 20; throw 'Minimal offline model cache failed to load.' }
    Write-Host 'Minimal offline model cache loaded successfully.'
} finally {
    foreach($listener in @(Get-NetTCPConnection -LocalPort 18767 -State Listen -ErrorAction SilentlyContinue)) {
        $process=Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)" -ErrorAction SilentlyContinue
        if($process -and [string]::Equals($process.ExecutablePath,[IO.Path]::GetFullPath($exe),[StringComparison]::OrdinalIgnoreCase)) {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    if($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
    if($null -eq $priorCache) { Remove-Item Env:HF_HUB_CACHE -ErrorAction SilentlyContinue } else { $env:HF_HUB_CACHE=$priorCache }
    if($null -eq $priorOffline) { Remove-Item Env:HF_HUB_OFFLINE -ErrorAction SilentlyContinue } else { $env:HF_HUB_OFFLINE=$priorOffline }
}
