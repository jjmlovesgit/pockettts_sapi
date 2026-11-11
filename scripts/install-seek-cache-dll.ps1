$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source = Join-Path $root 'build\sapi\pocket_sapi.dll'
$staged = Join-Path $root 'build\package\pocket_sapi.dll'
$statusPath = Join-Path $root 'results\seek-cache-install-status.json'
$backupPath = Join-Path $root 'results\pocket_sapi-before-seek-cache.dll'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Run the installer update from an elevated PowerShell process.' }

try {
    $installRoot = (Get-ItemProperty -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\PocketTTS' -Name InstallRoot).InstallRoot
    $installRoot = [IO.Path]::GetFullPath($installRoot).TrimEnd('\')
    $installed = [IO.Path]::GetFullPath((Join-Path $installRoot 'pocket_sapi.dll'))
    $registered = (Get-Item -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\{52586884-b3dc-46c5-a298-a49606cc5421}\InprocServer32').GetValue('')
    if (-not [string]::Equals($registered, $installed, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The registered SAPI DLL is not the PocketTTS installation DLL.'
    }
    foreach ($path in @($source, $staged, $installed)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing DLL: $path" }
    }
    $expectedHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if ((Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash -ne $expectedHash) {
        throw 'The packaged DLL does not match the tested build.'
    }
    Copy-Item -LiteralPath $installed -Destination $backupPath -Force
    & (Join-Path $root 'scripts\prepare-upgrade.ps1') -InstallRoot $installRoot -LogPath (Join-Path $root 'results\seek-cache-lockfix.log')
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Could not release PocketTTS DLL: $LASTEXITCODE" }
    try {
        Copy-Item -LiteralPath $source -Destination $installed -Force
        $installedHash = (Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash
        if ($installedHash -ne $expectedHash) { throw 'Installed DLL hash does not match the build.' }
    } catch {
        Copy-Item -LiteralPath $backupPath -Destination $installed -Force
        throw
    }
    [pscustomobject]@{
        status = 'installed'
        installed_dll = $installed
        sha256 = $expectedHash
        backup = $backupPath
        completed_at = (Get-Date).ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding UTF8
} catch {
    [pscustomobject]@{
        status = 'failed'
        error = $_.Exception.Message
        completed_at = (Get-Date).ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding UTF8
    throw
}
