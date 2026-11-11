# Gate 2: first Windows SAPI proof

Status: **Core Gate 2 local SAPI checks pass, including per-utterance rate; rapid-overlap and latest Edge retest remain open** (2026-11-09).

## What was built

`src/sapi/pocket_sapi.cpp` is an x64 COM `ISpTTSEngine` / `ISpObjectWithToken` proof DLL with a separate Pocket TTS CLSID. It sends text to Kyutai's official v4.0.1 Rust server over local loopback (`127.0.0.1:18765`), uses the exported `VoiceStatePath` in the normal rate bucket, and selects the slow or fast prompt WAV for the corresponding non-normal rate bucket. Prompt WAVs are normalized to 24 kHz mono and limited to 1.8 MB so the complete multipart request fits the official server's 2 MiB limit. The engine checks the 24 kHz PCM16 mono response, passes PCM to `ISpTTSEngineSite::Write`, and emits sentence and word boundary events. Word audio positions are proportional estimates. The DLL does not contain Paradee code or model assets. `scripts/build-sapi-proof.ps1` builds it with Visual Studio x64 Build Tools and builds the small prompt tempo utility.

`scripts/test-sapi-proof.ps1` starts the offline Rust server with the official `english_7m_refl_2026-10` cloning model and the 5.36-second user-provided Sloane prompt excerpt. It supports temporary per-user or machine-wide SAPI/COM registration, checks enumeration for the machine-wide token, renders WAVs, and removes its exact registry keys and server in a `finally` block.

`src/sapi/event_probe.cpp` is a small native SAPI host that requests sentence and word events during speech. The build and proof scripts compile and run it with the same temporary token.

## Observed result

- The DLL built with Visual Studio 18 Build Tools and Windows SDK 10.0.26100.0.
- The direct SAPI `SpVoice.Speak` call completed; the latest output WAV is `results/sapi-proof.wav` (366,766 bytes, 24 kHz, mono, about 7.64 seconds, non-silent).
- The native event probe completed with `hr=0x00000000`, **1 sentence event and 14 word events**. This verifies event delivery through SAPI, not the accuracy of estimated word timing.
- Cancellation was checked with a native SAPI host issuing a 150-repeat asynchronous utterance, then purging it after 250 ms. The proof engine checks `SPVES_ABORT` between WinHTTP response reads and audio writes; the latest standard proof purge-to-completion call returned in about **109 ms**. Other apps and slow/stalled worker behavior still need testing.
- SAPI volume is applied as linear PCM gain using `ISpTTSEngineSite::GetVolume` (0–100). The repeatable 100-versus-25 comparison passed: full-volume RMS was 1664 and quarter-volume RMS was 406 in the latest run.
- A native SAPI SSML probe with two speech fragments and a 500 ms break passed with **2 sentence events and 4 word events**, exercising fragment source offsets and a SAPI silence action. The engine now speaks fragments separately, writes timed silence, and bounds each request to 32,768 UTF-16 characters and total output to 32 MiB.
- The 32,769-character probe was rejected with `0x8007006f` (`ERROR_BUFFER_OVERFLOW`). After stopping the local Rust server, the missing-worker probe returned `0x80072efd`; the SAPI host remained alive and the test harness cleaned its temporary registration.
- With an approved elevated run, `SAPI.SpVoice.GetVoices()` enumerated the temporary HKLM token and direct SAPI playback succeeded. The HKLM CLSID/token were removed afterward; the loopback server is stopped. Per-user token selection remains possible by exact ID but is not included in the standard SAPI voice enumeration.
- The official server accepts both exported voice states and uploaded prompt audio through `voice_wav`. Rate variants use raw prompt WAVs because exported states did not preserve the pace difference. `SetRate(-5, 0, +5)` selected slow/normal/fast prompts and produced latest median durations of **9.56 s, 7.64 s, and 6.04 s**. SAPI XML `<rate absspeed>` fragment requests also selected the appropriate variants. The user listened to the integrated SAPI captures and confirmed they sound excellent with clearly distinct pace. See `docs/SAPI_RATE_BENCHMARK.md`.
- The first WAV mispronounced “TTS.” The engine now sends “tee tee ess” to the model for a standalone `TTS` acronym while retaining the original SAPI text for boundary events. The regenerated `results/sapi-proof.wav` passed the user's listening check; the earlier WAV is retained as `results/sapi-proof-before-acronym-fix.wav`. This targeted pronunciation fix does not establish general acronym handling.
- The temporary CLSID and voice-token registry paths were absent after the test. The local Rust server was stopped.
- `SAPI.SpVoice.GetVoices()` did **not** enumerate the per-user proof token; exact-ID `SAPI.SpObjectToken.SetId()` selection worked. Machine-wide SAPI and OneCore discovery, Edge Read Aloud, and NVDA still require later installer/app testing. This mirrors the distinction observed in Paradee-SAPI between token existence and application discovery.

## Remaining Gate 2 work

1. Improve word-event audio timing before claiming Edge highlighting. The engine currently estimates word positions by source character fraction; actual Edge highlight progression is untested.
2. SAPI rate now selects among three prompt pace bands. Review the integrated captures, test Edge/NVDA rate behavior and mid-utterance changes, and repeat the rapid stale-tail check before broad compatibility claims. Continuous speed and pitch tuning remain unavailable.
3. Cancellation, SSML fragments, silence, text/audio limits, volume, and missing-worker error pass local host checks. Test cancellation in Edge/NVDA and during a deliberately stalled response before claiming broad support.
4. Classic machine-wide enumeration and playback pass. OneCore/Edge and NVDA discovery/highlighting remain untested under Gate 4.
5. The offline installer is built and includes the prompt rate utility and default variants, but the rate-aware installer has not been installed for a fresh app check. Production startup, per-user voice selection, concurrency, recovery, and clean offline install behavior still need testing.

## Reference boundary

Paradee-SAPI informed the need for a native COM engine, temporary token testing, boundary events, and cleanup. This project has its own CLSID, source, model, runtime, build scripts, and proof artifacts. Pocket TTS model and voice terms remain governed by Kyutai's [model card](https://huggingface.co/kyutai/pocket-tts) and [voice repository](https://huggingface.co/kyutai/tts-voices).
