# Gate 3: shared install and Voice Manager

Status: The 6.9M-only cold-start-fix installer is installed on 2026-11-09. The installed SAPI DLL contains the current fix, the registry selects `english_7m_refl_2026-10`, and only that model weight is present. The user reports that the cold-start fix removed many Edge delays and that the subsequently listed functional acceptance checks pass. Independent logs for every app/profile scenario are not yet collected. The current clean installer filename is `PocketTTS-SAPI-Setup-6.9M.exe` (49,733,924 bytes); `PocketTTS-SAPI-Setup.exe` is an identical copy. Public redistribution clearance remains open.

## Built package

- The packaging script produces a private offline evaluation installer for the official Pocket TTS 3.3.0 Windows Rust CLI, the selected 6.9M English ReFL model with tokenizer, the SAPI engine, model-matched Alba pace prompts, Voice Manager, and license notices. The 1.9M choice was removed because existing cloned states are model-specific and no migration flow has been validated.
- Build inputs are SHA-256 pinned; NSIS 3.12 and SoundTouch archive hashes are checked. The rate-aware staged offline payload measures 139,893,923 bytes (under the 300 MB goal); its compressed installer measures 69,517,854 bytes.
- Three pace prompts are created offline with SoundTouch 2.3.3. The small DLL is dynamically linked and ships with the LGPL 2.1 license and original source archive.
- Installer registers a machine-wide default voice token and COM SAPI engine. The SAPI engine starts one shared local Rust server on demand, sets the official model cache and offline environment, and verifies that the expected executable owns the listening port.
- Default and custom voice tokens are mirrored into classic SAPI and Speech_OneCore, following the Paradee bridge pattern for Edge voice discovery. The user confirms Edge Read Aloud word highlighting works with the current installation. LockFix-3 preparation completed: it stopped the Pocket TTS worker, released file owners, and the install proceeded with the selected 6.9M model.
- Voice Manager supports authorized 16-bit PCM WAV import, offline voice-state export, slow/normal/fast prompt variants, elevated machine-wide token registration, exact-token preview, and removal. Removal deletes both classic SAPI and OneCore tokens and removes the profile-local state and pace prompts when owned.
- Uninstall stops only the Pocket TTS server launched from its own install folder, removes its machine token and COM registration, removes its own install folder and per-user Pocket TTS custom tokens, and leaves voice-state files in the user's profile intact by design.

## Checks run

- Built the x64 SAPI DLL and NSIS installer.
- Installed to `C:\Program Files\PocketTTS`; confirmed the runtime, model, tokenizer, DLL, default state, machine SAPI token, and COM registration.
- With no worker listening, selected the installed machine token through `SAPI.SpVoice`, generated a WAV, and confirmed that the installed Rust worker started and owned port 18765.
- Used Voice Manager's command-line add path with the licensed Butter prompt. It exported a 1,025,672-byte state, elevated to register a machine token, and generated a 266,926-byte WAV. Confirmed `SAPI.SpVoice.GetVoices()` listed the custom voice; after removal it no longer appeared, and its profile state file was deleted.
- Earlier custom-token removal deleted both registry tokens and the profile state. The manager now verifies both SAPI and OneCore deletion and reports that speech apps may need restarting.
- Ran the elevated uninstaller while the shared worker was running. Confirmed the worker stopped, the default token/COM/install-root registrations disappeared, the listener closed, and the complete install directory was removed.
- Built the rate-aware SAPI engine and installer. Classic SAPI `SetRate` and XML rate tests selected the slow, normal, and fast prompt paths and passed duration checks; latest medians at −5/0/+5 were 9.56/7.64/6.04 seconds. The package build and size check passed. The new installer has not yet been installed on the user's Windows system.
- The rate-aware warm first-audio p95 was 282–286 ms. In the rapid purge/restart run, p95 was 525.7 ms but 2/20 captures exceeded the stale-tail threshold; investigate before closing Gate 2.
- Diagnosed the user's Sloane Preview failure: the 23.95-second `Sloane_170WPM.wav` export produced a 2,426,512-byte state; the local Rust server returned HTTP 400 `Request payload is too large`, which the SAPI bridge surfaced as `E_FAIL`. A 5-second crop produced a 525,944-byte state and the same server returned HTTP 200 with a WAV. Voice Manager now rejects exported states over 1.9 MB and explains that a shorter prompt is needed; the SAPI engine has the same preflight cap.
- Diagnosed the generic COM preview failure for `Pockettts_angie`: its 2,727,980-byte, 44.1 kHz stereo normal prompt exceeded the Rust server's 2 MiB multipart limit and returned HTTP 400 `Request payload is too large`. Updated the prompt-rate utility to resample output to 24 kHz mono, changed Voice Manager to generate a normalized normal variant, and capped generated prompt variants at 1.8 MB. Reprocessed the three existing Angie prompt variants without changing their pace, backed up the originals under `results/angie-original-prompt-variants/`, verified all three returned HTTP 200, and confirmed `SAPI.SpVoice` successfully generated a 132,322-byte preview WAV. No registry entries were deleted or changed during diagnosis.
- A follow-up attempt to leave a custom token in place for uninstaller cleanup was canceled at the UAC prompt. The uninstaller's machine-token cleanup path is implemented but that exact case is not verified yet.

## Known gaps and stop/go decision

- Custom tokens are machine-wide while state files remain in the creating user's profile. Other Windows accounts may see those tokens but cannot read the creator's profile state. A multi-user access/privacy design is still required before claiming multi-user support.
- The currently registered Sloane state is too large for the shared Rust server and will continue to fail preview until replaced with a shorter prompt state. The new size guard is in the rebuilt installer, not necessarily the user's currently installed Voice Manager.
- The WinForms add/preview/remove workflow has not been driven interactively. The automated add/remove path exercises the same installed runtime, state format, and registry data shape.
- Repair/update, multiple user profiles, network-disconnected install and playback, clean-profile compatibility, and NVDA acceptance remain open. Repeat Edge picker/playback/highlighting checks on a clean profile and with normalized text.
- This is a local evaluation package, **not cleared for redistribution**. The model repo is gated and marked CC BY 4.0; attribution is included, but redistribution conditions and obligations still need review. No public installer release should be made from this artifact.

## Next gate work

1. Drive the WinForms flow and test rollback, duplicate names, bad prompts, and removal of external state paths.
2. Test multiple Windows accounts and design state/token permissions so one user's voice is not exposed as a broken voice to other profiles.
3. Run clean install, repair/update, offline-with-network-disabled playback, and uninstall/reinstall checks.
4. Obtain a clear model redistribution decision before any public release.

SAPI rate now has three pace bands, not a continuous pitch-and-speed tuning slider. Changing speaker identity or pitch still requires another authorized prompt. The Voice Manager's rate-aware flow currently accepts PCM WAV only; MP3/compressed WAV conversion remains open.

## Existing clone rate repair

The installed `Sloane_170` token predated rate-aware cloning and therefore lacked `VoicePromptSlowPath`, `VoicePromptNormalPath`, and `VoicePromptFastPath`. Voice Manager now supports `-SetVoicePromptVariants` with the original authorized WAV and updates both classic SAPI and OneCore tokens without re-exporting or replacing the clone state. The Sloane token was repaired on 2026-11-09, and the user confirmed that moving Edge Read Aloud's slider from 0.5 to 2.0 during playback audibly changes speech pace.

## Rate cache and cancellation follow-up

The slow and fast prompts now have exported `.safetensors` sidecars, created offline by Voice Manager and bundled for the English default voice. SAPI prefers these compact states and falls back to the prompt WAV for older voices. Voice Manager stages replacement rate prompts before switching a registered token, preserving the old files if export fails. Existing Sloane and Angie profile voices received sidecars without registry changes.

The SAPI HTTP request now polls for `SPVES_ABORT` while the worker is in WinHTTP and closes the active request to interrupt it. The rebuilt local proof passed 20 rapid purge/restart trials at each of slow, normal, and fast rates. First-audio p95 was 92.8, 79.5, and 85.7 ms respectively; duration checks found no tail over one second beyond a same-word reference. See [latency benchmark](SAPI_LATENCY_BENCHMARK.md) for limits. Installed Edge and NVDA behavior still needs confirmation with the new package.

The five-second cold Pocket voice selection delay was reproduced after closing Edge and stopping the worker. A direct cold SAPI call also took 4,589 ms to speak a one-word phrase, isolating the delay to the adapter. Its WinHTTP health checks against an absent loopback listener were the cause. The rebuilt adapter skips WinHTTP when the TCP listener table shows no server; three cold SAPI runs then took 170–172 ms to speak. The new 6.9M-only installer was built, and Edge needs a post-install cold retest.







