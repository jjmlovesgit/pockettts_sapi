# Windows app compatibility checks

Updated 2026-11-10. This is evidence from the development machine, not a general support guarantee. The app list and test boundaries follow the separate [Paradee-SAPI proof approach](https://github.com/jjmlovesgit/paradee-sapi/blob/main/docs/SAPI_PROOF.md).

The pending voice-by-voice NVDA comparison table and procedure are in [NVDA_VOICE_BENCHMARK.md](NVDA_VOICE_BENCHMARK.md).

This project integrates **Kyutai Pocket TTS** (the installer packages Pocket TTS 6.9M ReFL), not Kokoro. Voice Manager exports a Pocket TTS state and keeps slow, normal, and fast prompt WAVs from an authorized recording; a SAPI/OneCore token points to those prompt variants. Each cloned voice is not a separate engine binary.

| Host / path | Status | Evidence and remaining work |
|---|---|---|
| Classic SAPI (`SAPI.SpVoice`) | **Passed on latest proof build** | The registered proof token enumerated and generated WAV output. Volume reduction, cancel/purge, SSML fragments and silence, bounded-text rejection, and installed worker auto-start passed. Full proof output is `../results/sapi-proof.wav`; test command is `scripts/test-sapi-proof.ps1`. |
| .NET `System.Speech` | **Passed on latest proof build** | Enumerated and selected `Butter (Pocket TTS)`, generated 5.24 seconds of non-silent output (peak 13,048), and passed a duration floor that catches the initial 0.68-second truncation. The fix handles successful `ISpTTSEngineSite::Write` calls where the host does not update `pcbWritten`; compare Microsoft's [Write contract](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ms719570%28v%3Dvs.85%29) and the tested [Paradee write path](../docs/PARADEE_REFERENCE_AUDIT.md). |
| Edge Read Aloud | **Picker, playback, highlighting, and live rate change verified** | On `results/edge_sapi_compat.html`, Edge selected the cloned `Sloane_170` voice, played and highlighted text, and the user confirmed an audible change after moving the Read Aloud speed slider from Slow (`0.5`) to Fast (`2.0`) during playback. The original browser tab was left intact. Repeat on a clean Windows profile before general compatibility claims. |
| NVDA 64-bit SAPI 5 | **Voice switching works with NVDA's WASAPI option off; WASAPI-on path fails here** | The installed diagnostic DLL traced NVDA sending only Alba while the user heard the fallback with "Use modern audio output system (WASAPI)" enabled. After that option was disabled, NVDA sent Angie, cloned Sloane, and Dutch Daan tokens with their correct voice-state paths. The mechanism inside NVDA's alternate audio path remains unproven; measure navigation, interruption, and latency with the working setting before acceptance. See [NVDA benchmark](NVDA_VOICE_BENCHMARK.md). |
| Windows Speech Properties (`sapi.cpl`, x64) | **Enumeration passed; preview control available** | Opened the Text to Speech page. It selected `Sloane_170` as the current voice and exposed the preview-text field, Preview/Stop control, and voice-speed slider. The UI showed Stop while the preview was active. The dialog was dismissed without applying settings. An audible preview and saved global-rate change still need user-confirmed listening. |
| Speech rate | **Three pace bands pass classic SAPI; Edge slider was verified before latest fast-path change** | `SetRate` and XML `<rate absspeed>` use the exported state at normal rates and slow/fast cloned-prompt variants outside the normal bucket. The latest classic SAPI proof passed with distinct durations at −5/0/+5. The user previously confirmed Edge's live slider changed pace audibly; retest the rebuilt package in Edge. See [rate captures and measurements](SAPI_RATE_BENCHMARK.md). |
| Offline app use | **Package path tested previously; clean network-disconnected app check open** | Runtime/model files are bundled, and the worker uses offline mode. Repeat Edge and classic SAPI playback after disconnecting the network and clearing nonessential caches. |

## Native integration paths

**Edge voice-list refresh (2026-11-09):** A new `Pokettts_Sloane` token was present in both classic SAPI and OneCore after its prompt files were created at 7:30 PM. Edge's main process had started at 7:25 PM and remained alive when browser windows were closed and reopened. Edge therefore retained its earlier voice picker list. A full Edge process exit and relaunch is required for this case; merely closing the window was insufficient. Voice Manager currently reports only that speech apps should be restarted, which does not explain Edge background processes.

These entries separate what has been observed from what still needs a dedicated app test.

| Path | Current expectation and verification plan |
|---|---|
| NVDA 64-bit SAPI 5 driver | On this machine, disable NVDA Speech settings → "Use modern audio output system (WASAPI)" to select Pocket TTS custom and language voices reliably. Then use rapid arrow/line navigation through short and long text; record purge-to-last-audio latency, stale tail, clipping, and onset. The WASAPI-on failure remains open. |
| Edge Read Aloud / OneCore | Pocket voice tokens are mirrored to OneCore. Installed Pocket voices appeared in the picker; playback and word highlighting were seen. Highlight positions are estimated from generated audio, so the acceptance target is readable synchronization across short/long text, punctuation, and cloned tokens—not a claim of sample-perfect timing. Repeat against the latest packaged build and confirm both default and Voice Manager-created Pocket tokens. |

## Legacy and Windows system utilities

| Utility | Current scope and verification plan |
|---|---|
| 64-bit Windows Speech Properties (`sapi.cpl`) | `Sloane_170` appeared as the selected voice, and the preview and speed controls were present. Verify audible preview, other Pocket tokens, 5-second cloned prompt states, and saved global rate changes. The current product build is x64. |
| 32-bit Speech Properties / 32-bit SAPI clients | Outside the current build: no x86 SAPI DLL is produced or registered. Do not advertise 32-bit compatibility unless a separate x86 build, registration, installer, and host tests pass. |
| Windows Narrator | Not tested. OneCore token registration may make voices discoverable to some OneCore consumers; it does not establish Narrator support. Verify picker visibility, reading, interruption, and behavior after logoff/reboot before making a claim. |

## AppContainer and external-service boundaries

| Environment | Classification |
|---|---|
| UWP / Microsoft Store AppContainer apps | **Unverified / not a support commitment.** A client using SAPI/OneCore does not necessarily access the model files or loopback endpoint itself: the registered engine and local Pocket TTS worker perform that work. AppContainer COM activation, token visibility, policy, and each app's choice of speech API still require direct tests. Do not attribute failure to folder or endpoint isolation without collecting evidence from the specific app. |
| Cloud TTS websites and browser extensions | **Outside initial scope.** Machine SAPI/OneCore registration does not make local voices available to a remote service. A browser extension can only use local voices if its host explicitly bridges to the relevant Windows API; filtering is host-specific and unverified. |
| Telemetry | The product has no planned usage telemetry. The SAPI adapter and local worker operate on-device; any diagnostic logging used for proof is local test instrumentation. Verify network-disconnected operation before public release rather than describing it as proven by registry visibility. |

Keep an explicit **not tested**, **unverified**, or **outside scope** status where there is no direct evidence. Do not call a path intentionally blocked, flawless, production-ready, or universally compatible based only on token registration.

## Managed-host regression found and fixed

`System.Speech` previously wrote only about 0.68 seconds of the utterance. The managed SAPI host returned `S_OK` from `ISpTTSEngineSite::Write` but left `pcbWritten` as zero after consuming the supplied buffer. The adapter interpreted zero as an error and stopped sending the remaining PCM. The adapter now seeds the count to the requested size, honors any reported partial count, and advances on the successful host behavior. The proof runner now checks both non-silent samples and a minimum output duration so this truncation cannot pass as a successful WAV.

When a host has not subscribed to word-boundary events, the adapter sends the complete PCM fragment without splitting it at estimated word offsets. It only divides output to queue word events when the host requested those events. Edge's subscribed-event path remains enabled for Read Aloud highlighting.

## Gate status

The warm SAPI first-audio and rapid purge/restart latency targets passed on the freshly rebuilt proof DLL: rapid p95 518.6 ms across 20 trials, with no stale-tail threshold failures. `System.Speech` and classic SAPI passed on the latest proof DLL. Edge Read Aloud playback, highlighting, and live rate change passed on the installed build after repairing the legacy Sloane token. Speech Properties enumerated `Sloane_170` and showed its preview and rate controls. Gate 2 remains **open** for a clean-profile repeat. Gate 4 remains open for NVDA navigation and WASAPI-on behavior, offline-network checks, and an audible Speech Properties preview/rate check.

**Cold-start follow-up (2026-11-09):** A stopped Pocket worker caused 4,589 ms direct `System.Speech` speech time with the prior adapter. A failed WinHTTP health request on the closed local port accounted for the wait before worker creation. The fixed adapter checks the local TCP listener table first; three cold direct SAPI runs took 170–172 ms to speak. The user reports that the upgrade fixed many Edge delays. The exact post-upgrade cold Edge sound-onset measurement remains to be repeated. NVDA navigation, disconnected-network playback, and clean-profile acceptance remain open.
