$ErrorActionPreference = 'Continue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$log = Join-Path $root 'results\machinewide-test.log'
& (Join-Path $PSScriptRoot 'test-sapi-proof.ps1') -MachineWide *>&1 |
    Tee-Object -FilePath $log
exit $LASTEXITCODE
