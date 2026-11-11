# Paradee-SAPI reference audit

Reviewed 2026-11-09 against C:\Users\Jim\Documents\ChatGPT\Paradee, especially its SAPI bridge, native phoneme path, installer, install guide, and proof log. Paradee is an integration and verification reference only; Pocket TTS uses its own upstream runtime, model, voice states, and license.

## What Pocket TTS already follows

| Area | Pocket TTS status |
| --- | --- |
| SAPI COM engine and voice tokens | Implements ISpTTSEngine/ISpObjectWithToken, machine SAPI registration, and default/custom voice tokens. |
| Edge token discovery pattern | Mirrors default and custom tokens into Speech_OneCore, following Paradee. User confirms Edge Read Aloud word highlighting works in the current 6.9M installation. Clean-profile repeat checks remain open. |
| Playback controls and interruption | Reads SAPI volume, honors abort/purge while writing audio, and applies bounded text/audio/state limits. |
| Word and sentence events | Emits SAPI boundary events, informed by Paradee. Pocket word positions are estimated proportionally within generated audio, not model timestamps; user confirms they currently produce Edge Read Aloud word highlighting. |
| Offline operation | Packages runtime, tokenizer, selected model and default voice state; launches Rust with local cache and offline mode. A network-disconnected app test remains open. |
| Installation and removal | Uses an offline NSIS installer, registers the COM server and tokens, and has product-scoped uninstall cleanup. The installer packages the selected 6.9M Pocket model. |
| Prompt cloning and Voice Manager | Pocket's model-specific prompt export, clone-state storage, and manager are product-specific; Paradee does not supply a directly reusable feature here. Keep these flows grounded in Pocket TTS upstream behavior. |
| Evidence and compatibility gates | Tracks direct SAPI checks separately from Edge and NVDA acceptance; successful Paradee tests are not treated as Pocket TTS evidence. |

## Gaps to carry forward from the reference

| Area | Paradee pattern | Pocket TTS gap / action |
| --- | --- | --- |
| Pronunciation | Paradee phonemizes input with eSpeak NG and maps it to its own Misaki/model phoneme vocabulary. | Pocket now applies boundary-aware synthesis rewrites for TTS and ZP (spoken as “zee eye pee”), while SAPI events retain original host text. There is not yet a user-managed pronunciation dictionary, and non-Speak pronunciation/spell-out fragment actions are not handled. The Paradee phonemizer is a design reference, not a transferable vocabulary/model. |
| SAPI rate | Paradee combines ISpTTSEngineSite::GetRate with fragment RateAdj, then scales synthesis speed. | Pocket combines `GetRate` and fragment `RateAdj`, then applies a local WSOLA-style time stretch. Three runs per setting confirmed −5/0/+5 duration changes; synthetic tones and speech pitch estimates remained stable. Perceptual artifact review is still needed. See `docs/SAPI_RATE_BENCHMARK.md`. |
| Engine-site writes | Paradee checks the `Write` HRESULT and does not depend on `pcbWritten` being set. | Pocket's managed-host test found that `System.Speech` consumed the audio but returned success with `pcbWritten=0`. The adapter now initializes that out value to the requested count and advances on successful writes. The managed-host WAV duration check guards against truncation. |
| Event timing and highlighting | Paradee maps source spans to audio offsets and verified Edge word highlighting after emitting word events. | User confirms Pocket estimated word offsets produce Edge highlighting. Keep source offsets correct for pronunciation rewrites and verify longer/normalized text and a clean profile. |
| Upgrade lock handling | Paradee's install guide tells users to close Edge and other speech apps before upgrade/uninstall. | LockFix-3 warns the user, stops the worker from its own install root, and uses Windows Restart Manager to close only processes reported as using its executable or SAPI DLL. The user reran setup; the transcript says files were unlocked, setup completed, and the installed DLL matches the rebuilt DLL. |
| Registry ownership safeguards | Paradee setup checks whether another engine owns its SAPI/OneCore token and protects the default token during uninstall. | Pocket cleanup is scoped to its CLSID, but setup should also refuse to overwrite a same-name token owned by another engine and should verify default-token behavior before deleting registrations. |
| Application acceptance | Paradee has user-confirmed Edge picker/playback and word highlighting, plus offline install/playback evidence on its tested machine. | Pocket word highlighting is user-confirmed with the current 6.9M install. Clean-profile and longer-text repeat checks, NVDA 64-bit SAPI checks, and network-disconnected playback remain open. Paradee results do not transfer. |
| Installer visual design | Browser Speech's custom setup window is a separate visual reference; this project currently uses standard NSIS. | Visual matching is explicitly deferred. See the deferred UI reference in notes.md. |

## Current user-observed pronunciation issue

Voice Manager creates or registers a cloned voice; it does not define how acronyms are spoken. Pocket's adapter can transform synthesis text before sending it to the Rust worker, as its existing TTS rule demonstrates. A reusable rule must retain a mapping to the original text so SAPI word events/highlighting still refer to the text shown by the host. The explicit ZP rule now expands to “zee eye pee” in the synthesis copy; the Edge highlight confirmation applies to the earlier rule set, so verify this normalized-text case after installing the rebuilt adapter.

## Work order

1. Verify the ZP → “zee eye pee” rule in speech and Edge highlighting; retain source-offset mapping.
2. Have the user listen to slow/normal/fast SAPI rate samples; verify rate and highlighting in Edge/NVDA, including mid-utterance changes where supported.
3. Install and verify the new automatic lock-release path during upgrade.
4. Repeat Edge picker/playback/highlighting on clean-profile and normalized-text cases; complete NVDA, offline, and clean-install acceptance.
5. Revisit the custom installer visual design only when the user un-defers that task.





