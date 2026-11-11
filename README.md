# Pocket TTS SAPI — local evaluation

This is a separate Windows SAPI 5 integration project for [Kyutai Pocket TTS](https://github.com/kyutai-labs/pocket-tts). The [written specification](docs/SPEC.md) and [local model benchmark](docs/MILESTONE_1_BENCHMARK.md) selected the official 6.9M ReFL cloning model for quality. The installer supports an English default voice and optional language packs. It warns before stopping the Pocket TTS worker and closing apps Windows reports are using Pocket TTS files. Voice Manager requests elevation to register imported voices machine-wide; voice-state files remain in the creating user's profile, so multi-user behavior needs a permissions design. Edge Read Aloud word highlighting and NVDA voice switching with NVDA's WASAPI option off were verified on the development machine. Clean-profile, offline-network, broader NVDA navigation, and final redistribution checks remain open. No model was modified.

The target is selectable, offline English voices in Windows applications, with Pocket TTS audio-prompt voice cloning preserved as a supported utility. [Paradee-SAPI](https://github.com/jjmlovesgit/paradee-sapi) informs Windows integration and verification only. Its model, performance, and footprint are not Pocket TTS claims.

This repository is a source and documentation backup. It does not include installer binaries, downloaded model weights, generated voice states, source prompt audio, raw benchmark recordings, or local caches. The installer is a local evaluation artifact pending final redistribution review for gated model assets. Follow the licensing audit before downloading, building, or redistributing model and voice files.

Latest compatibility and latency evidence is recorded in [Windows app compatibility](docs/WINDOWS_APP_COMPATIBILITY.md), [NVDA voice benchmark](docs/NVDA_VOICE_BENCHMARK.md), [SAPI latency benchmark](docs/SAPI_LATENCY_BENCHMARK.md), and [SAPI rate benchmark](docs/SAPI_RATE_BENCHMARK.md). SAPI rate control selects slow, normal, and fast cached voice states; classic SAPI rate and XML tests pass. The latest local proof passed 20 rapid stop/restart trials per rate band. Edge Read Aloud highlighting passed. In NVDA 2026.3.1, Pocket voice selection fell back to Alba with "Use modern audio output system (WASAPI)" enabled; turning that NVDA option off allowed cloned and language tokens to reach the engine. The WASAPI-on path and NVDA navigation latency remain open.

Project handoff and conversation link: [notes.md](notes.md).







