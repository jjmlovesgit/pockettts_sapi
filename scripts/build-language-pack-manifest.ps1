$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$cache = Join-Path $root '.benchmark-cache\hf'
$modelRev = '3e82814a68665eec246ff649b14c71331f955c06'
$voiceRev = 'a3055dcb533cf2ec90458008a01e7cef550bae2a'
$packs = @(
    @{Id='french';Name='French';Locale='fr-FR';Lcid='040c';Voice='estelle';Gender='Female';TokenizerRev='8843db76457a91db32077edf8dfcd1c0e3e755fd'},
    @{Id='german';Name='German';Locale='de-DE';Lcid='0407';Voice='juergen';Gender='Male';TokenizerRev='4e1e0a3e611c51c0b4ed8174fc10f32a54644303'},
    @{Id='italian';Name='Italian';Locale='it-IT';Lcid='0410';Voice='giovanni';Gender='Male';TokenizerRev='4e1e0a3e611c51c0b4ed8174fc10f32a54644303'},
    @{Id='spanish';Name='Spanish';Locale='es-ES';Lcid='0c0a';Voice='lola';Gender='Female';TokenizerRev='4e1e0a3e611c51c0b4ed8174fc10f32a54644303'},
    @{Id='portuguese';Name='Brazilian Portuguese';Locale='pt-BR';Lcid='0416';Voice='rafael';Gender='Male';TokenizerRev='4e1e0a3e611c51c0b4ed8174fc10f32a54644303'},
    @{Id='dutch';Name='Dutch';Locale='nl-NL';Lcid='0413';Voice='daan';Gender='Male';TokenizerRev='4e1e0a3e611c51c0b4ed8174fc10f32a54644303'}
)
function New-Asset([string]$repo,[string]$revision,[string]$repoPath,[string]$installPath) {
    $repoKey = $repo -replace '/', '--'
    $local = Join-Path $cache "models--$repoKey\snapshots\$revision\$repoPath"
    if (-not (Test-Path -LiteralPath $local -PathType Leaf)) { throw "Missing pinned asset: $local" }
    [ordered]@{
        repository = $repo
        revision = $revision
        path = ($repoPath -replace '\\','/')
        url = "https://huggingface.co/$repo/resolve/$revision/$(($repoPath -replace '\\','/'))"
        installPath = ($installPath -replace '\\','/')
        bytes = (Get-Item -LiteralPath $local).Length
        sha256 = (Get-FileHash -LiteralPath $local -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
$manifest = [ordered]@{schema=1;source='Kyutai official Pocket TTS assets';packs=@()}
foreach ($pack in $packs) {
    $lang = $pack.Id
    $tokRev = $pack.TokenizerRev
    $assets = @(
        (New-Asset 'kyutai/pocket-tts' $modelRev "languages\$lang\model.safetensors" "models\hf\models--kyutai--pocket-tts\snapshots\$modelRev\languages\$lang\model.safetensors"),
        (New-Asset 'kyutai/pocket-tts-without-voice-cloning' $tokRev "languages\$lang\tokenizer.json" "models\hf\models--kyutai--pocket-tts-without-voice-cloning\snapshots\$tokRev\languages\$lang\tokenizer.json"),
        (New-Asset 'kyutai/pocket-tts-without-voice-cloning' $voiceRev "languages\$lang\embeddings\$($pack.Voice).safetensors" "voices\$($pack.Voice)-$lang.safetensors")
    )
    $totalBytes = [int64]0
    foreach ($asset in $assets) { $totalBytes += [int64]$asset.bytes }
    $manifest.packs += [ordered]@{ id=$lang; name=$pack.Name; locale=$pack.Locale; lcid=$pack.Lcid; modelLanguage=$lang; voiceId=$pack.Voice; voiceName=(Get-Culture).TextInfo.ToTitleCase($pack.Voice); gender=$pack.Gender; totalBytes=$totalBytes; assets=$assets }
}
$out=Join-Path $root 'packaging\language-packs.json'
$manifest|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $out -Encoding utf8
$manifest.packs|ForEach-Object { [pscustomobject]@{Id=$_.id;TotalBytes=$_.totalBytes} }|Format-Table -AutoSize
Write-Host "Manifest: $out"
