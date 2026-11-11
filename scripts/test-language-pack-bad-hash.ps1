$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$temporaryManifest = Join-Path $root 'build\language-packs-bad-hash.json'
$manifest = Get-Content (Join-Path $root 'packaging\language-packs.json') -Raw | ConvertFrom-Json
$manifest.packs[1].assets[0].sha256 = '0000000000000000000000000000000000000000000000000000000000000000'
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temporaryManifest -Encoding utf8
try {
    try {
        & (Join-Path $PSScriptRoot 'install-language-pack.ps1') -Language german -InstallRoot (Join-Path $root 'build\sapi-test\install') -ManifestPath $temporaryManifest -DownloadCache (Join-Path $root 'build\pack-download-test') -SourceCache (Join-Path $root '.benchmark-cache\hf') -PrepareOnly
        throw 'Bad digest was accepted.'
    } catch {
        if ($_.Exception.Message -notmatch 'Download size or SHA-256 mismatch') { throw }
        Write-Host 'PASS: bad digest rejected before installation.'
    }
} finally {
    Remove-Item -LiteralPath $temporaryManifest -Force -ErrorAction SilentlyContinue
}
