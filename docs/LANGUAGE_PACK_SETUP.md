# Optional language packs: evaluation build

Status: installer compiled, local pack staging/registration tested, and German pack installed on the evaluation machine on 2026-11-10. English remains the mandatory 6.9M ReFL base voice.

The current evaluation installer is `build/PocketTTS-SAPI-Setup-BluePocket-NoHiddenPrompts-Eval.exe`. It uses the blue denim pocket icon for Setup and Uninstall and installs the same icon for the Voice Manager window and Start menu shortcut. The icon source is `scripts/build-pocket-icon.py`; the generated Windows icon is `assets/pockettts-pocket.ico`. Setup no longer pauses behind its progress window for a routine upgrade notice; failure dialogs request the foreground and topmost position.

## Setup choices

The component page starts with **English: Alba (6.9M, included)** as a checked, required item. Alba is the official English default voice. It then offers six optional, initially unchecked packs. Each provides the official native model, tokenizer, and one demo voice state: French Estelle, German Juergen, Italian Giovanni, Spanish Lola, Brazilian Portuguese Rafael, and Dutch Daan. Each selection adds about 223–227 MB of download and installed files; the Setup space estimate increases when a pack is checked. The installer itself stays about 50 MB and the English base payload stays below 300 MB.

Setup first downloads every selected pack to a local cache and verifies the exact file length and SHA-256 from `packaging/language-packs.json`. Only after all downloads pass does it release locked Pocket TTS files, replace the base installation, copy the selected packs, and create classic SAPI 5 and OneCore voice tokens. A failed download stops before altering the existing installation. Setup can be rerun to use verified cache files; partial files are discarded. In-file HTTP resume is not implemented.

The packs use the same worker process. Selecting a different language or voice causes a one-time model/voice switch; consecutive speech from the same token uses the loaded worker. The existing isolated SAPI probe proved English → German → German warm reuse. Other app-level paths remain to be verified.

## Source, access, and redistribution

The pinned model files come from `kyutai/pocket-tts`; tokenizers and demo voice states come from `kyutai/pocket-tts-without-voice-cloning`. Source revisions, URLs, sizes, and hashes are in `packaging/language-packs.json`. Kyutai attribution and the CC BY 4.0 legal text are included in the installer. The assets are copied unchanged. The main model repository may require acceptance of Kyutai's Hugging Face access conditions and a `HF_TOKEN` environment variable on the installing machine. This build is for local evaluation; public download access and redistribution workflow still need a release decision.

## Verification completed

- NSIS installer compiled with six optional components and a required base section.
- All six packs prepared from the local official asset cache with length and SHA-256 checks; each then copied and registered to an isolated per-user registry branch for both SAPI and OneCore. The test removed the temporary registry branch and install folder. Results: `results/language-pack-install-local-result.json`.
- A deliberately wrong German model digest was rejected during preparation. An authenticated HEAD request to the pinned official German model URL returned HTTP 200 and the expected 219,029,196-byte content length.
- An isolated COM/SAPI probe generated English, German-first, and German-warm WAVs. German used the native model and Juergen state; the warm second request reused the same worker PID. Results: `results/german-switch-local-result.txt`.
- The evaluation installer completed with German selected. Both installed machine token branches and all three German pack files match the manifest. The installed SAPI engine generated two non-silent Juergen WAVs: 844 ms first request and 318 ms second request, with the same worker PID. Results: `results/installed-juergen-result.json` and `results/installed-juergen-{first,warm}.wav`.
- Edge Read Aloud listed `Juergen (Pocket TTS German)`. On the German test page, Edge initially selected a Microsoft German voice automatically; after explicitly selecting Juergen, it played the German passage with visible word highlighting. The worker marker recorded `german` and `voices/juergen-german.safetensors`.
- A quick isolated SAPI smoke generated one non-silent utterance with the correct native model for each remaining pack: French, Italian, Spanish, Brazilian Portuguese, and Dutch. The complete run took about 4.5 seconds; the per-voice synthesis calls took 495–849 ms. Results and WAV paths are in `results/quick-multilingual-sapi-result.json`. A subsequent German restart with `HF_HUB_OFFLINE=1` passed (530 ms first, 329 ms warm, same worker PID).
- Warm local verification timing on this machine: SHA-256 of all 18 files in the six-pack cache (1,349,038,241 bytes) took 1.02 seconds; the six `install-language-pack.ps1 -PrepareOnly` calls, including manifest and file checks, took 1.13 seconds. These timings exclude download, copying into Program Files, and UI interaction and should not be represented as a guaranteed cold-disk or network time.
- An earlier evaluation installer was run with all six optional packs selected. The pack cache reported each pack ready, then the routine upgrade notice appeared behind Setup and made progress look stuck at "Verifying Dutch." After the notice was dismissed, Setup completed and all six classic SAPI and OneCore locale tokens were present. The revised installer removes that notice.

## Remaining gates

1. For evaluation, perform one installer lifecycle check: upgrade with a selected pack, then uninstall and confirm Pocket TTS-owned classic/OneCore tokens and files are removed. Do not repeat the full installer and Edge UI path for every locale unless a specific failure appears.
2. Before public release, check unavailable-network Setup behavior, NVDA interruption, and broader app compatibility. The helper's bad-hash rejection has passed; the full Setup failure UI remains to test.
3. Resolve public access to gated assets and release terms before distributing the language-pack installer.

The larger English demo voice selection and additional male/female voices per locale are separate follow-up work; only the six native demo voices listed above are installed by these checkboxes.
