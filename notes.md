# Project notes and handoff

## Working preference (2026-11-05)

Use GPT-6 Luna for the specification, benchmark scripts, routine implementation, and documentation. Escalate to GPT-6.1 Sol for difficult SAPI integration or debugging if Luna gets stuck; tell the user when that switch is warranted. Keep processing at Standard, not Fast. Keep tasks narrow and provide only relevant files and tool output to conserve the user's allowance. The assistant cannot change the main chat's model or speed setting itself; the user selects those in Codex.

Conversation shortcut: [this Codex conversation](https://chatgpt.com/). This is a general ChatGPT destination and may not reopen the exact conversation. The text below is the reliable handoff.

## Request and current state

Build a Windows SAPI 5 adapter for Kyutai Pocket TTS only after benchmarking the official 18.2M, 6.9M, and 1.9M English models locally. Preserve cloning from an audio prompt, support bundled sample voices and user-managed prompts, prioritize a small offline install and low CPU/memory use, and validate SAPI, Edge Read Aloud, NVDA, and highlighting. Do not train or modify models before the benchmark and stop/go decision. Keep this project separate from Paradee-SAPI; use that repository solely for SAPI, installer, test, and documentation lessons.

As of 2026-11-05, the official-model benchmark is complete with **GO to a scoped SAPI proof using 6.9M ReFL**. See `docs/MILESTONE_0_LICENSE_AUDIT.md`, `docs/MILESTONE_1_BENCHMARK.md`, `docs/RUST_RUNTIME_BENCHMARK.md`, `docs/SLOANE_PROMPT_COMPARISON.md`, and `docs/PERSISTENT_RUNTIME_BENCHMARK.md`. The user approved all full-prompt and short-excerpt candidates. A persistent Rust server using a 5.36-second Sloane prompt measured 83.3 MiB idle RSS, 149.2 MiB post-speech RSS, and 251.8 MiB peak RSS for 6.9M ReFL. The first direct SAPI COM speech proof passed; see `docs/SAPI_PROOF.md`. The proof used and removed temporary per-user registry keys. No installer or app compatibility release has been built.

## Sources inspected

- [Pocket TTS upstream repository](https://github.com/kyutai-labs/pocket-tts), HEAD `0d2010682f3ec336890f55cb2acc0f22abbc1d8d` observed 2026-11-05; README, three official small-model configurations, and v4.0.1 release metadata.
- [Kyutai small-model article](https://kyutai.org/blog/2026-10-20-pocket-tts-small/) (2026-10-20), including model quality and single-thread CPU-speed table.
- [Official model card and access terms](https://huggingface.co/kyutai/pocket-tts); [sample-voice repository](https://huggingface.co/kyutai/tts-voices).
- [Paradee-SAPI repository](https://github.com/jjmlovesgit/paradee-sapi), particularly its [SAPI proof](https://github.com/jjmlovesgit/paradee-sapi/blob/main/docs/SAPI_PROOF.md), [spec](https://github.com/jjmlovesgit/paradee-sapi/blob/main/docs/SPEC.md), and [install guide](https://github.com/jjmlovesgit/paradee-sapi/blob/main/docs/INSTALL.md).

Recheck upstream revisions, model terms, and sample-voice licenses immediately before downloading or redistribution.

## Deferred installer UI reference (2026-11-09)

Keep the current installer UI as standard NSIS for now. When visual polish is prioritized, use [Browser Speech](https://github.com/jjmlovesgit/Browser-Speech) as the reference for a custom Windows setup window, including its dark navy header, Segoe UI typography, light content cards, and clear install progress. The example screenshot is in the Codex conversation; the local checkout is C:\Projects\Browser-Speech. This is a deferred design task, not part of the current model-choice installer work.

## Paradee implementation cross-check (2026-11-09)

Use the local Paradee-SAPI project as an active reference for pronunciation, rate, SAPI event timing, registry ownership, installer lock recovery, and test procedures. The Pocket-vs-Paradee gap audit is in docs/PARADEE_REFERENCE_AUDIT.md. Keep Paradee model assets and performance claims separate.

## Windows host compatibility update (2026-11-09)

Latest proof build passed classic `SAPI.SpVoice`, .NET `System.Speech`, cancellation, volume, SSML/silence fragments, bounded text, worker restart, and per-utterance rate. Managed-host output exposed an unset `pcbWritten` count causing truncation; this is fixed and now guarded by a minimum duration test. Latest warm SAPI first-write p95: 41–47 ms; rapid purge/restart p95: 254 ms. Twenty captured WAVs were within the matching baseline +250 ms. See `docs/SAPI_LATENCY_BENCHMARK.md` and `docs/WINDOWS_APP_COMPATIBILITY.md`.

Rate probe ran 3 samples at each `ISpVoice::SetRate` value: −5 median 10.69 s, 0 median 7.72 s, +5 median 5.52 s. SAPI XML `<rate absspeed>` also passed. A bounded local WSOLA-style time stretch replaces linear resampling; synthetic-tone pitch errors were below 0.5%, and voiced-speech pitch estimates stayed similar across rates. The earlier WSOLA attempt crashed the host; the new implementation passed the standalone DSP and full SAPI proof. FFmpeg remains excluded for package size/licensing reasons. See `docs/SAPI_RATE_BENCHMARK.md`; listen for time-stretch artifacts.

Edge Read Aloud picker/playback/highlighting has been checked on the installed build. NVDA is not installed. Per-utterance SAPI rate changes output duration while synthetic-tone and speech pitch measurements stay stable; perceptual artifacts and mid-utterance changes remain unverified. Latest first-audio p95 is 33–40 ms for short cases and 175.6 ms during rapid restart. Gate 2 remains open until the user reviews the samples, Edge is repeated against the latest installed DLL, and overlap evidence is improved. Keep the installed worker running when possible; the final proof run auto-started it.

## Compatibility planning framework (2026-11-09)

`docs/WINDOWS_APP_COMPATIBILITY.md` now organizes acceptance into native integration, legacy/system utilities, and app-boundary sections. It explicitly distinguishes tested Pocket TTS paths from unknown paths: NVDA arrow-navigation and actual audio-tail behavior; Edge timing quality and cloned tokens; 64-bit `sapi.cpl`; x86 exclusion; Narrator; exploratory AppContainer/UWP behavior; and cloud sites/extensions outside initial scope. Do not describe Pocket TTS as Kokoro or claim perfect highlighting, instant WASAPI silence, universal app support, or production readiness without direct evidence. No usage telemetry is planned; release claims still require offline verification.

## Existing local Pocket TTS server (discovered 2026-11-05)

`C:\Projects\pocket-tts-openai_streaming_server` is a separate FastAPI streaming project. Its virtual environment currently contains `pocket-tts 2.1.0`, older than the upstream 4.0.1 small-model release. The server loads the default model with `TTSModel.load_model()`, discovers local WAV prompts in `voices-celebrities`, and caches voice states from `get_state_for_audio_prompt()` by voice and language. It offers useful local examples of prompt discovery, import, and cache behavior, but is **not** evidence for the 18.2M/6.9M/1.9M benchmark or a suitable SAPI/offline installer by itself. Keep this server unmodified. Use a separate environment for Gate 1 and use only audio prompts with clear consent; do not automatically bundle or register the server's voice files, whose provenance and redistribution rights have not been reviewed.
