$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$installRoot = Join-Path $root 'build\pack-install-test'
$downloadCache = Join-Path $root 'build\pack-download-test'
$sourceCache = Join-Path $root '.benchmark-cache\hf'
$manifest = Join-Path $root 'packaging\language-packs.json'
$helper = Join-Path $PSScriptRoot 'install-language-pack.ps1'
$registry = 'Registry::HKEY_CURRENT_USER\SOFTWARE\PocketTTS\PackTest'
if (Test-Path -LiteralPath $installRoot) { throw "Test target already exists: $installRoot" }
if (Test-Path -LiteralPath $registry) { throw "Test registry branch already exists: $registry" }
$workspace = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
if (-not ([IO.Path]::GetFullPath($installRoot).StartsWith($workspace, [StringComparison]::OrdinalIgnoreCase))) { throw 'Unsafe test target.' }
$results = @()
try {
    New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
    Copy-Item (Join-Path $root '.benchmark-cache\rust\unpacked\pocket-tts-3.3.0-x86_64-pc-windows-msvc\pocket-tts.exe') (Join-Path $installRoot 'pocket-tts.exe')
    foreach ($language in @('french','german','italian','spanish','portuguese','dutch')) {
        & $helper -Language $language -InstallRoot $installRoot -ManifestPath $manifest -DownloadCache $downloadCache -SourceCache $sourceCache -PrepareOnly
        & $helper -Language $language -InstallRoot $installRoot -ManifestPath $manifest -DownloadCache $downloadCache -SourceCache $sourceCache -IsolatedTestRegistry
        $id = 'PocketTTS.Locale.' + $language
        $classic = Join-Path $registry "Speech\Tokens\$id"
        $oneCore = Join-Path $registry "OneCore\Tokens\$id"
        foreach ($key in @($classic,$oneCore)) {
            if (-not (Test-Path -LiteralPath $key)) { throw "Missing token: $key" }
            $properties = Get-ItemProperty -LiteralPath $key
            if ($properties.ModelLanguage -ne $language -or $properties.CLSID -ne '{52586884-B3DC-46C5-A298-A49606CC5421}') { throw "Wrong token metadata: $key" }
            if (-not (Test-Path -LiteralPath $properties.VoiceStatePath)) { throw "Missing installed voice state: $key" }
        }
        $results += [pscustomobject]@{Language=$language;Classic=$true;OneCore=$true;StateBytes=(Get-Item -LiteralPath $properties.VoiceStatePath).Length}
    }
    $results | Format-Table -AutoSize | Out-String | Write-Host
    $results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'results\language-pack-install-local-result.json') -Encoding utf8
} finally {
    if (Test-Path -LiteralPath $registry) { Remove-Item -LiteralPath $registry -Recurse -Force }
    if (Test-Path -LiteralPath $installRoot) { Remove-Item -LiteralPath $installRoot -Recurse -Force }
}
