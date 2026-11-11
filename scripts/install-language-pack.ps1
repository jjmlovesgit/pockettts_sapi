param(
    [Parameter(Mandatory=$true)][ValidateSet('french','german','italian','spanish','portuguese','dutch')][string]$Language,
    [Parameter(Mandatory=$true)][string]$InstallRoot,
    [string]$ManifestPath = (Join-Path $PSScriptRoot '..\packaging\language-packs.json'),
    [string]$DownloadCache = (Join-Path $env:LOCALAPPDATA 'PocketTTS\PackDownloads'),
    [string]$SourceCache,
    [switch]$PrepareOnly,
    [switch]$IsolatedTestRegistry
)
$ErrorActionPreference='Stop'
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($manifest.schema -ne 1) { throw 'Unsupported language pack manifest.' }
$pack = @($manifest.packs | Where-Object id -eq $Language)
if ($pack.Count -ne 1) { throw "Language pack not found: $Language" }
$pack = $pack[0]
$install = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$download = [IO.Path]::GetFullPath($DownloadCache).TrimEnd('\')
if ($install.Length -lt 10 -or $download.Length -lt 10) { throw 'Unsafe install or cache path.' }
$assets = @($pack.assets)
if ($assets.Count -ne 3) { throw 'Expected model, tokenizer, and one demo voice state.' }
New-Item -ItemType Directory -Path $download -Force | Out-Null
$prepared = @()
foreach ($asset in $assets) {
    $relative = [string]$asset.installPath
    if ($relative -match '(^[\\/]|\.\.|:)' -or $relative -notmatch '^(models/hf/|voices/)') { throw "Unsafe manifest path: $relative" }
    $parts = $relative -split '/'
    $cacheFile = Join-Path $download (($Language + '_' + $parts[-1]) -replace '[^a-zA-Z0-9_.-]','_')
    $expectedHash = ([string]$asset.sha256).ToUpperInvariant()
    $expectedBytes = [int64]$asset.bytes
    if ($expectedHash -notmatch '^[A-F0-9]{64}$' -or $expectedBytes -le 0) { throw 'Invalid asset digest or size.' }
    $valid = (Test-Path -LiteralPath $cacheFile -PathType Leaf) -and
        (Get-Item -LiteralPath $cacheFile).Length -eq $expectedBytes -and
        (Get-FileHash -LiteralPath $cacheFile -Algorithm SHA256).Hash -eq $expectedHash
    if (-not $valid) {
        $partial = $cacheFile + '.partial'
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
        if ($SourceCache) {
            $repoKey = ([string]$asset.repository) -replace '/', '--'
            $source = Join-Path $SourceCache "models--$repoKey\snapshots\$($asset.revision)\$(($asset.path -replace '/','\'))"
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Offline source missing: $source" }
            Copy-Item -LiteralPath $source -Destination $partial
        } else {
            $uri = [uri]$asset.url
            if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'huggingface.co') { throw "Unapproved download host: $($uri.Host)" }
            $headers = @{}
            if ($env:HF_TOKEN) { $headers.Authorization = 'Bearer ' + $env:HF_TOKEN }
            try { Invoke-WebRequest -Uri $uri -Headers $headers -OutFile $partial -TimeoutSec 300 }
            catch { throw "Could not download $Language asset $($asset.path). Accept the official model access conditions and provide HF_TOKEN if required. $($_.Exception.Message)" }
        }
        if ((Get-Item -LiteralPath $partial).Length -ne $expectedBytes -or
            (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ne $expectedHash) {
            Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
            throw "Download size or SHA-256 mismatch: $($asset.path)"
        }
        Move-Item -LiteralPath $partial -Destination $cacheFile -Force
    }
    $target = Join-Path $install ($relative -replace '/','\')
    $prepared += [pscustomobject]@{Source=$cacheFile;Target=$target;Hash=$expectedHash;Bytes=$expectedBytes}
}
if ($PrepareOnly) { Write-Host "$($pack.name) ready: $($pack.totalBytes) verified bytes in $download"; return }
if (-not (Test-Path -LiteralPath (Join-Path $install 'pocket-tts.exe'))) { throw 'Pocket TTS base runtime is not installed.' }
$clsid='{52586884-B3DC-46C5-A298-A49606CC5421}'
$tokenId='PocketTTS.Locale.'+$Language
$roots=if ($IsolatedTestRegistry) {
    @('Registry::HKEY_CURRENT_USER\SOFTWARE\PocketTTS\PackTest\Speech\Tokens','Registry::HKEY_CURRENT_USER\SOFTWARE\PocketTTS\PackTest\OneCore\Tokens')
} else {
    @('Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\Tokens','Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens')
}
foreach ($registryRoot in $roots) {
    $key=Join-Path $registryRoot $tokenId
    if (Test-Path $key) {
        $owner=(Get-ItemProperty -LiteralPath $key -Name CLSID -ErrorAction SilentlyContinue).CLSID
        if ($owner -ne $clsid) { throw "Voice token belongs to another engine: $key" }
    }
}
foreach ($item in $prepared) {
    New-Item -ItemType Directory -Path (Split-Path $item.Target) -Force | Out-Null
    if ((Test-Path -LiteralPath $item.Target) -and (Get-FileHash -LiteralPath $item.Target -Algorithm SHA256).Hash -eq $item.Hash) { continue }
    Copy-Item -LiteralPath $item.Source -Destination $item.Target -Force
    if ((Get-FileHash -LiteralPath $item.Target -Algorithm SHA256).Hash -ne $item.Hash) { throw "Installed hash mismatch: $($item.Target)" }
}
$statePath = ($prepared | Where-Object Target -Like '*\voices\*' | Select-Object -First 1).Target
$display = "$($pack.voiceName) (Pocket TTS $($pack.name))"
foreach ($registryRoot in $roots) {
    $key=Join-Path $registryRoot $tokenId
    New-Item -Path (Join-Path $key 'Attributes') -Force | Out-Null
    Set-Item -LiteralPath $key -Value $display
    foreach ($entry in @{CLSID=$clsid;ModelLanguage=$pack.modelLanguage;VoiceStatePath=$statePath;VoiceName=$tokenId}.GetEnumerator()) {
        New-ItemProperty -LiteralPath $key -Name $entry.Key -Value $entry.Value -PropertyType String -Force | Out-Null
    }
    foreach ($entry in @{Name=$display;VoiceName=$display;Language=$pack.lcid;Gender=$pack.gender;Age='Adult';Vendor='Pocket TTS';VoiceId=$tokenId;VoiceStatePath=$statePath}.GetEnumerator()) {
        New-ItemProperty -LiteralPath (Join-Path $key 'Attributes') -Name $entry.Key -Value $entry.Value -PropertyType String -Force | Out-Null
    }
}
Write-Host "$display installed with native $Language model and tokenizer."
