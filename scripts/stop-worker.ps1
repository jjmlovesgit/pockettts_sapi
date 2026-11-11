param([Parameter(Mandatory=$true)][string]$InstallRoot)
$ErrorActionPreference = 'Stop'
$expectedExe = [IO.Path]::GetFullPath((Join-Path $InstallRoot 'pocket-tts.exe'))
$processes = Get-CimInstance Win32_Process -Filter "Name='pocket-tts.exe'" -ErrorAction SilentlyContinue
foreach ($process in $processes) {
    if (-not [string]::Equals([IO.Path]::GetFullPath($process.ExecutablePath),$expectedExe,[StringComparison]::OrdinalIgnoreCase)) { continue }
    if ($process.CommandLine -notmatch '\bserve\b' -or $process.CommandLine -notmatch '--port\s+18765') { continue }
    Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    $null = Wait-Process -Id $process.ProcessId -Timeout 10 -ErrorAction SilentlyContinue
}
