# Pocket TTS SAPI — local evaluation

This is a separate Windows SAPI 5 integration project for [Kyutai Pocket TTS](https://github.com/kyutai-labs/pocket-tts). The [written specification](docs/SPEC.md) and [local model benchmark](docs/MILESTONE_1_BENCHMARK.md) selected the official 6.9M ReFL cloning model for quality. The installer supports an English default voice and optional language packs. It warns before stopping the Pocket TTS worker and closing apps Windows reports are using Pocket TTS files. Voice Manager registers imported voices machine-wide; voice-state files remain in the creating user's profile, so multi-user behavior needs a permissions design. Edge Read Aloud word highlighting and NVDA voice switching with NVDA's WASAPI option off were verified on the development machine. This is an evaluation pre-release; clean-profile, offline-network, broader NVDA navigation, and full release checks remain open. No model was modified.

The target is selectable, offline English voices in Windows applications, with Pocket TTS audio-prompt voice cloning preserved as a supported utility. [Paradee-SAPI](https://github.com/jjmlovesgit/paradee-sapi) informs Windows integration and verification only. Its model, performance, and footprint are not Pocket TTS claims.

This repository is a source and documentation backup. It does not include installer binaries, downloaded model weights, generated voice states, source prompt audio, raw benchmark recordings, or local caches. The evaluation installer is attached to the [GitHub pre-release](https://github.com/jjmlovesgit/pockettts_sapi/releases/tag/v0.1.0-evaluation); optional language packs download during setup. Review the [license audit](docs/MILESTONE_0_LICENSE_AUDIT.md) for attribution and model terms.

## Quick Start

1. Download and run [PocketTTS-SAPI-Setup.exe](https://github.com/jjmlovesgit/pockettts_sapi/releases/download/v0.1.0-evaluation/PocketTTS-SAPI-Setup.exe). Setup requires administrator approval.
2. Accept the license screen. **English: Alba (6.9M)** is included. Check any optional language packs you want; each selected pack downloads about 220–227 MB during setup and then works offline.
3. Use the Start menu shortcut **Pocket TTS → Voice Manager** to clone a voice from an audio prompt. Or open PowerShell and run:

   ```powershell
   & "$env:ProgramFiles\PocketTTS\tools\VoiceManager.ps1"
   ```

   Enter a voice name, choose an audio prompt, confirm that you are authorized to use it, and select **Create and register voice**. The new voice is registered for Windows SAPI applications.

4. Fully exit and reopen Edge to refresh its Read Aloud voice list. In NVDA, choose **Microsoft Speech API version 5 (64 bit)** and leave **Use modern audio output system (WASAPI)** unchecked for Pocket voices.

The English model and installed voices run offline. The Setup download is an unsigned evaluation build; its SHA-256 is listed in the release notes.

Latest compatibility and latency evidence is recorded in [Windows app compatibility](docs/WINDOWS_APP_COMPATIBILITY.md), [NVDA voice benchmark](docs/NVDA_VOICE_BENCHMARK.md), [SAPI latency benchmark](docs/SAPI_LATENCY_BENCHMARK.md), and [SAPI rate benchmark](docs/SAPI_RATE_BENCHMARK.md). SAPI rate control selects slow, normal, and fast cached voice states; classic SAPI rate and XML tests pass. The latest local proof passed 20 rapid stop/restart trials per rate band. Edge Read Aloud highlighting passed. In NVDA 2026.3.1, Pocket voice selection fell back to Alba with "Use modern audio output system (WASAPI)" enabled; turning that NVDA option off allowed cloned and language tokens to reach the engine. The WASAPI-on path and NVDA navigation latency remain open.

Project handoff and conversation link: [notes.md](notes.md).

