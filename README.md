# Pocket TTS SAPI — Windows evaluation release 0.1.1

This is a separate Windows SAPI 5 integration project for [Kyutai Pocket TTS](https://github.com/kyutai-labs/pocket-tts). Version 0.1.1 is a published evaluation release using the official 6.9M-parameter ReFL cloning model (66.5 MB weights) selected by the [written specification](docs/SPEC.md) and [local model benchmark](docs/MILESTONE_1_BENCHMARK.md). The installer supports an English default voice and optional language packs. It warns before stopping the Pocket TTS worker and closing apps Windows reports are using Pocket TTS files. Voice Manager registers imported voices machine-wide; voice-state files remain in the creating user's profile, so multi-user behavior needs a permissions design. Edge Read Aloud word highlighting and NVDA voice switching with NVDA's WASAPI option off were verified on the development machine. Follow-up validation items, including clean-profile setup, offline-network operation, and broader NVDA navigation, are documented in the compatibility reports. No model was modified.

The target is selectable, offline English voices in Windows applications, with Pocket TTS audio-prompt voice cloning preserved as a supported utility. [Paradee-SAPI](https://github.com/jjmlovesgit/paradee-sapi) informs Windows integration and verification only. Its model, performance, and footprint are not Pocket TTS claims.

## Included languages and default voices

English is included in the base installer. The other languages are optional checkboxes; each selected pack downloads its language-specific model, tokenizer, and default demo voice during setup. Installed packs work offline.

| Language | Default voice | Install option | Approx. pack download |
|---|---|---|---:|
| English | Alba | Included | Included in base installer |
| French | Estelle | Optional | 227 MB |
| German | Juergen | Optional | 225 MB |
| Italian | Giovanni | Optional | 223 MB |
| Spanish | Lola | Optional | 225 MB |
| Brazilian Portuguese | Rafael | Optional | 226 MB |
| Dutch | Daan | Optional | 223 MB |

This repository is a source and documentation backup. It does not include installer binaries, downloaded model weights, generated voice states, source prompt audio, raw benchmark recordings, or local caches. Download the published installer from the [Pocket TTS for Windows 0.1.1 release](https://github.com/jjmlovesgit/pockettts_sapi/releases/tag/v0.1.1-evaluation); optional language packs download during setup. Review the [license audit](docs/MILESTONE_0_LICENSE_AUDIT.md) for attribution and model terms.

## Quick Start

1. Download and run [PocketTTS-SAPI-Setup.exe](https://github.com/jjmlovesgit/pockettts_sapi/releases/download/v0.1.1-evaluation/PocketTTS-SAPI-Setup.exe). Setup requires administrator approval.
2. Accept the license screen. **English: Alba (6.9M)** is included. Check any optional language packs you want; each selected pack downloads about 220–227 MB during setup and then works offline.
3. Use the Start menu shortcut **Pocket TTS → Voice Manager** to clone a voice from an audio prompt. Or open PowerShell and run:

   ```powershell
   & "$env:ProgramFiles\PocketTTS\tools\VoiceManager.ps1"
   ```

   Enter a voice name, choose an audio prompt, confirm that you are authorized to use it, and select **Create and register voice**. The new voice is registered for Windows SAPI applications.

4. Fully exit and reopen Edge to refresh its Read Aloud voice list. In NVDA, choose **Microsoft Speech API version 5 (64 bit)** and leave **Use modern audio output system (WASAPI)** unchecked for Pocket voices.

The English model and installed voices run offline. The published Setup installer is unsigned; its SHA-256 is listed in the release notes.

Latest compatibility and latency evidence is recorded in [Windows app compatibility](docs/WINDOWS_APP_COMPATIBILITY.md), [NVDA voice benchmark](docs/NVDA_VOICE_BENCHMARK.md), [SAPI latency benchmark](docs/SAPI_LATENCY_BENCHMARK.md), and [SAPI rate benchmark](docs/SAPI_RATE_BENCHMARK.md). SAPI rate control selects slow, normal, and fast cached voice states; classic SAPI rate and XML tests pass. The latest local proof passed 20 rapid stop/restart trials per rate band. Edge Read Aloud highlighting passed. In NVDA 2026.3.1, Pocket voice selection fell back to Alba with "Use modern audio output system (WASAPI)" enabled; turning that NVDA option off allowed cloned and language tokens to reach the engine. The WASAPI-on path and NVDA navigation latency remain open.

Project handoff and conversation link: [notes.md](notes.md).

## Acknowledgments and licenses

Pocket TTS is created by [Kyutai](https://github.com/kyutai-labs/pocket-tts). This is an independent Windows SAPI adapter and is not made or endorsed by Kyutai. The runtime is MIT licensed; model weights, tokenizers, and bundled demo voices carry their own CC BY 4.0 attribution and license terms. The included English Alba voice is attributed to Alba MacKenna. SoundTouch, by Olli Parviainen and contributors, is used under LGPL-2.1. Full license texts, asset attributions, source revisions, and change notes are included in `C:\Program Files\PocketTTS\LICENSES` after installation. Paradee-SAPI was consulted as a separate Windows integration reference; its code and model are not part of this project.

