$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$stage = Join-Path $root 'build\package'
$nsisRoot = Join-Path $root '.benchmark-cache\nsis\unpacked\nsis-3.12'
$archive = Join-Path $root '.benchmark-cache\nsis\nsis-3.12.zip'
$compiler = Join-Path $nsisRoot 'Bin\makensis.exe'
$archiveHash = '56581F90DB321581C5381193D796FFFCF2D24B2F8FED2160A6C6A3BAA67F2C4F'
$compilerHash = '25D1AA7081DB1A9DE9690B59983F9652B7409A189C3444328CC1841EFF693E8D'
$runtime = Join-Path $root '.benchmark-cache\rust\unpacked\pocket-tts-3.3.0-x86_64-pc-windows-msvc\pocket-tts.exe'
$model = Join-Path $root '.benchmark-cache\hf-minimal\models--kyutai--pocket-tts\snapshots\db04f0e653473e5c7333c69686ac92b7460b0c1d\languages\english_7m_refl_2026-10\model.safetensors'
$tokenizer = Join-Path $root '.benchmark-cache\hf-minimal\models--kyutai--pocket-tts-without-voice-cloning\snapshots\08ffc58775e62aad9409511b9591c9af626270f3\languages\english_7m_refl_2026-10\tokenizer.model'
foreach ($item in @(
    @{Path=$runtime; Hash='813CABFC2F8FC7A4E5310DEDA6025426B3164610DD9F3C3098A6078E5CC1895A'},
    @{Path=$model; Hash='5C55BAE685E505553F02F7C856FDA55F0BA3A09F149338D87C0F8D21192B40BC'},
    @{Path=$tokenizer; Hash='D461765AE179566678C93091C5FA6F2984C31BBE990BF1AA62D92C64D91BC3F6'},
    @{Path=(Join-Path $root 'assets\Alba.safetensors'); Hash='6020D6F7D0A27E64D2348D315403411ED27F4F733D536CC0EC01FB354B9832D2'},
    @{Path=(Join-Path $root 'assets\Alba.wav'); Hash='46264E83CB99115C3D210260E029117566D9C64F20266D10DAA78107759EDE3E'},
    @{Path=(Join-Path $root 'build\pocket-tts-LICENSE.txt'); Hash='23F18E03DC49DF91622FE2A76176497404E46CED8A715D9D2B67A7446571CCA3'},
    @{Path=(Join-Path $root 'third_party\licenses\CC-BY-4.0.txt'); Hash='9BA9550AD48438D0836DDAB3DA480B3B69FFA0AAC7B7878B5A0039E7AB429411'}
)) {
    if (-not (Test-Path -LiteralPath $item.Path) -or (Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash -ne $item.Hash) {
        throw "Pinned package input missing or hash mismatch: $($item.Path)"
    }
}
if (-not (Test-Path -LiteralPath $archive)) { throw "Pinned NSIS archive not found: $archive" }
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $archiveHash) { throw 'NSIS archive hash mismatch.' }
if (-not (Test-Path -LiteralPath $compiler)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $nsisRoot) | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath (Split-Path $nsisRoot) -Force
}
if ((Get-FileHash -LiteralPath $compiler -Algorithm SHA256).Hash -ne $compilerHash) { throw 'NSIS compiler hash mismatch.' }
& (Join-Path $PSScriptRoot 'build-sapi-proof.ps1')
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "SAPI engine build failed: $LASTEXITCODE" }
if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'voices'),(Join-Path $stage 'models-medium'),(Join-Path $stage 'models-common') | Out-Null
Copy-Item $runtime (Join-Path $stage 'pocket-tts.exe')
Copy-Item (Join-Path $root 'build\sapi\pocket_sapi.dll') (Join-Path $stage 'pocket_sapi.dll')
Copy-Item (Join-Path $root 'assets\pockettts-pocket.ico') (Join-Path $stage 'pockettts-pocket.ico')
Copy-Item $model (Join-Path $stage 'models-medium\model.safetensors')
Copy-Item $tokenizer (Join-Path $stage 'models-common\tokenizer.model')
Copy-Item (Join-Path $root 'assets\Alba.safetensors') (Join-Path $stage 'voices\Alba-medium.safetensors') -Force
$env:HF_HUB_CACHE = Join-Path $root '.benchmark-cache\hf'
$env:HF_HUB_OFFLINE = '1'
$promptRateUtility = Join-Path $root 'build\sapi\pocket_prompt_rate.exe'
& $promptRateUtility (Join-Path $root 'assets\Alba.wav') (Join-Path $stage 'voices\Alba-slow.wav') '0.70'
if ($LASTEXITCODE -ne 0) { throw 'Could not prepare the slow Alba voice prompt.' }
Copy-Item (Join-Path $root 'assets\Alba.wav') (Join-Path $stage 'voices\Alba-normal.wav') -Force
& $promptRateUtility (Join-Path $root 'assets\Alba.wav') (Join-Path $stage 'voices\Alba-fast.wav') '1.40'
if ($LASTEXITCODE -ne 0) { throw 'Could not prepare the fast Alba voice prompt.' }
foreach ($modelSpec in @(
    @{Language='english_7m_refl_2026-10';Suffix='medium'}
)) {
    foreach ($pace in @('slow','fast')) {
        $inputPath = Join-Path $stage ("voices\Alba-$pace.wav")
        $statePath = Join-Path $stage ("voices\Alba-$($modelSpec.Suffix)-$pace.safetensors")
        & $runtime export-voice --quiet --language $modelSpec.Language $inputPath $statePath
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $statePath) -or
            (Get-Item -LiteralPath $statePath).Length -gt 1900000) {
            throw "Could not prepare the $($modelSpec.Suffix) $pace cached voice state."
        }
    }
}
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'tools'),(Join-Path $stage 'LICENSES') | Out-Null
Copy-Item (Join-Path $root 'scripts\VoiceManager.ps1') (Join-Path $stage 'tools\VoiceManager.ps1')
Copy-Item (Join-Path $root 'scripts\remove-user-voices.ps1') (Join-Path $stage 'tools\remove-user-voices.ps1')
Copy-Item (Join-Path $root 'scripts\stop-worker.ps1') (Join-Path $stage 'tools\stop-worker.ps1')
Copy-Item (Join-Path $root 'scripts\machine-voice-token.ps1') (Join-Path $stage 'tools\machine-voice-token.ps1')
Copy-Item (Join-Path $root 'scripts\prepare-upgrade.ps1') (Join-Path $stage 'tools\prepare-upgrade.ps1')
Copy-Item (Join-Path $root 'scripts\install-language-pack.ps1') (Join-Path $stage 'tools\install-language-pack.ps1')
Copy-Item (Join-Path $root 'packaging\language-packs.json') (Join-Path $stage 'tools\language-packs.json')
Copy-Item (Join-Path $root 'build\sapi\pocket_prompt_rate.exe') (Join-Path $stage 'tools\pocket_prompt_rate.exe')
Copy-Item (Join-Path $root 'build\sapi\pocket_soundtouch.dll') (Join-Path $stage 'tools\pocket_soundtouch.dll')
Copy-Item (Join-Path $root 'build\pocket-tts-LICENSE.txt') (Join-Path $stage 'LICENSES\pocket-tts-MIT.txt')
Copy-Item (Join-Path $root 'third_party\licenses\CC-BY-4.0.txt') (Join-Path $stage 'LICENSES\CC-BY-4.0.txt')
Copy-Item (Join-Path $root 'third_party\soundtouch\COPYING.TXT') (Join-Path $stage 'LICENSES\SoundTouch-LGPL-2.1.txt')
Copy-Item (Join-Path $root 'build\soundtouch-2.3.3.tar.gz') (Join-Path $stage 'LICENSES\SoundTouch-2.3.3-source.tar.gz')
@'
POCKET TTS FOR WINDOWS — UPSTREAM ATTRIBUTION AND LOCAL EVALUATION NOTICE

This independent Windows SAPI adapter is not made or endorsed by Kyutai.
Pocket TTS runtime: Kyutai, MIT. Full upstream notice: pocket-tts-MIT.txt.
Pocket TTS 6.9M ReFL model weights and tokenizer: Kyutai, CC BY 4.0. Attribution, source revisions, and license link: model-CC-BY-4.0.txt. Full license: CC-BY-4.0.txt. The weights and tokenizer are unmodified.
Optional native-language packs: Kyutai, CC BY 4.0. Each selected pack downloads the pinned native model, tokenizer, and demo voice state listed in tools/language-packs.json. The assets are redistributed unchanged. Full license: CC-BY-4.0.txt. The official model downloads require Hugging Face access to Kyutai's gated model repository.
Default Alba voice: Alba MacKenna's official Pocket TTS voice, CC BY 4.0. The voice state was exported locally with the pinned Pocket TTS runtime from the official casual recording; the prompt and attribution are documented in Alba-CC-BY-4.0.txt. Slow and fast prompt WAVs are tempo-adjusted from the same recording; their cached states are exported with Pocket TTS.
SoundTouch 2.3.3: Olli Parviainen and contributors, LGPL 2.1. Its DLL is dynamically linked; license and corresponding source archive are included as SoundTouch-LGPL-2.1.txt and SoundTouch-2.3.3-source.tar.gz.
Pocket TTS model access conditions prohibit unauthorized voice cloning and deceptive or unlawful uses. See https://huggingface.co/kyutai/pocket-tts . Voice Manager requires the user to confirm authorization for imported prompts.
This package remains a local evaluation artifact until its public distribution review is completed.
'@ | Set-Content -Encoding utf8 (Join-Path $stage 'LICENSES\NOTICE.txt')
@'
Attribution: Kyutai, Pocket TTS, english_7m_refl_2026-10 (6.9M ReFL model).
Model source: https://huggingface.co/kyutai/pocket-tts/tree/db04f0e653473e5c7333c69686ac92b7460b0c1d
Model revision: db04f0e653473e5c7333c69686ac92b7460b0c1d
Tokenizer source: https://huggingface.co/kyutai/pocket-tts-without-voice-cloning/tree/08ffc58775e62aad9409511b9591c9af626270f3
Tokenizer revision: 08ffc58775e62aad9409511b9591c9af626270f3
License for model and tokenizer: Creative Commons Attribution 4.0 International, https://creativecommons.org/licenses/by/4.0/ . The full legal code is in CC-BY-4.0.txt.
Changes: The model weights and tokenizer are redistributed unchanged. The Pocket TTS SAPI adapter and locally exported Alba voice and rate states are separate additions; no model training, fine-tuning, or weight modification was performed.
No endorsement by Kyutai is implied. Upstream materials are provided without warranties, as detailed in the respective licenses.
Model access and prohibited-use conditions: https://huggingface.co/kyutai/pocket-tts
'@ | Set-Content -Encoding utf8 (Join-Path $stage 'LICENSES\model-CC-BY-4.0.txt')
@'
Default English voice: Alba MacKenna, from Kyutai's Pocket TTS official predefined voices and kyutai/tts-voices/alba-mackenna/casual.wav.
Pinned model repository revision: db04f0e653473e5c7333c69686ac92b7460b0c1d. Voice prompt repository revision: 323332d33f997de8394f24a193e1a76df720e01a.
The Alba recordings and voice are released under CC BY 4.0. Source: https://huggingface.co/kyutai/tts-voices/tree/323332d33f997de8394f24a193e1a76df720e01a/alba-mackenna . Attribution: Alba MacKenna, via Kyutai's Pocket TTS voice collection. License: https://creativecommons.org/licenses/by/4.0/ . Full license: CC-BY-4.0.txt.
Changes: Alba-slow.wav and Alba-fast.wav are tempo-adjusted from casual.wav using SoundTouch. The normal voice state and the rate-specific cached voice states were exported from the official prompt WAVs with Pocket TTS.
'@ | Set-Content -Encoding utf8 (Join-Path $stage 'LICENSES\Alba-CC-BY-4.0.txt')
$size = (Get-ChildItem $stage -Recurse -File | Measure-Object Length -Sum).Sum
if ($size -gt 300MB) { throw "Staged payload exceeds 300 MB: $size bytes" }
$env:POCKETTTS_STAGE = $stage
$nsis = Join-Path $root 'packaging\pockettts-sapi.nsi'
$outputName = if ($env:POCKETTTS_SETUP_OUTPUT_NAME) { $env:POCKETTTS_SETUP_OUTPUT_NAME } else { 'PocketTTS-SAPI-Setup.exe' }
& $compiler /V3 "/DOUT_NAME=$outputName" $nsis
if ($LASTEXITCODE -ne 0) { throw "makensis failed: $LASTEXITCODE" }
Write-Host "Staged payload: $size bytes; installer: $(Join-Path $root ('build\' + $outputName))"
if ($outputName -eq 'PocketTTS-SAPI-Setup.exe') {
    Copy-Item (Join-Path $root 'build\PocketTTS-SAPI-Setup.exe') (Join-Path $root 'build\PocketTTS-SAPI-Setup-6.9M.exe') -Force
}
