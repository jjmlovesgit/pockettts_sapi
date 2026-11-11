# SAPI first audio and rapid restart benchmark

The later installed German/Dutch replay-cache check is recorded in [SAPI_SEEK_CACHE.md](SAPI_SEEK_CACHE.md).

Baseline run: 2026-11-09, Windows x64, installed 6.9M ReFL model (`english_7m_refl_2026-10`), warm local worker, Sloane cloned voice state. The probe uses a non-playback SAPI WAV stream for rapid restart captures. First-audio timing is measured from `Speak` submission until generated PCM reaches `ISpTTSEngineSite::Write` successfully. The rate-aware implementation was measured separately below.

## Warm first audio

| Input | Samples | Median | p95 | Maximum |
|---|---:|---:|---:|---:|
| `Z` | 20 | 30.4 ms | 33.7 ms | 37.8 ms |
| `a` | 20 | 28.8 ms | 39.9 ms | 43.6 ms |
| `yes` | 20 | 31.3 ms | 33.6 ms | 33.9 ms |
| `next` | 20 | 30.9 ms | 32.7 ms | 33.8 ms |
| Purge a pending longer utterance, immediately submit `Z`/`next` | 20 | 129.9 ms | 175.6 ms | 203.8 ms |

All measured p95 values are below the 600 ms target.

## Captured output during rapid stop/restart

The probe saved one WAV for each of 20 rapid purge/restart trials. The `Z` baseline was 1,080 ms and `next` baseline was 1,160 ms. Trial outputs ranged from 1,080 to 1,320 ms; none exceeded the matching baseline by the test's 250 ms stale-audio threshold. The generated captures contain active PCM rather than silence. The raw WAVs are in `../results/sapi-latency-captures/`.

This rules out a canceled long utterance being appended as a large stale tail in these trials. It does not independently prove that two simultaneous live playback streams can never overlap; the probe captures each serialized SAPI output stream separately. Edge's audible playback/highlighting check is recorded in [WINDOWS_APP_COMPATIBILITY.md](WINDOWS_APP_COMPATIBILITY.md).

## Compatibility finding: `System.Speech`

The first managed-host test exposed a real truncation: the host accepted a 32 KiB PCM buffer but returned success without updating `pcbWritten`. The adapter treated zero as failure and stopped after about 0.68 seconds. The final adapter seeds the output count before `Write` and treats a successful call with an untouched/zero count as consuming the requested buffer. This follows the behavior handled in the Paradee reference and is checked with a duration assertion.

The latest `System.Speech.Synthesis.SpeechSynthesizer` test enumerated and selected `Butter (Pocket TTS)` and wrote a 5.24-second non-silent WAV (peak 13,048). The full proof also passed direct SAPI speech, volume, cancellation, SSML fragments/silence, bounded-text rejection, and installed-worker restart. Cancellation completed in 969 ms in this run.

## Remaining limits

- The adapter buffers the complete server WAV before its first SAPI write. Short utterances are fast in this run; long-text progressive delivery is not implemented.
- Only the tested Windows machine, model, voice state, and hosts are covered. `System.Speech` and classic SAPI passed; Edge Read Aloud picker/playback/highlighting was verified on the current installation in a separate UI check. NVDA is not installed on this machine, so its 64-bit SAPI driver remains untested.
- Rate-aware requests upload a slow, normal, or fast raw prompt WAV and the worker re-encodes it per utterance. Warm first-audio p95 was 282–286 ms in the latest short-input run, below 600 ms; rapid purge/restart p95 was 525.7 ms with two stale-tail threshold failures among 20 captures. See [SAPI_RATE_BENCHMARK.md](SAPI_RATE_BENCHMARK.md).
- Rapid captures test stale tails by comparing duration with baseline; they do not provide an independent acoustic overlap detector.
- A user-confirmed Edge check and a local test page are not a clean-profile or clean-install acceptance run.

Source: [benchmark procedure](BENCHMARK_PLAN.md), [SAPI implementation](../src/sapi/pocket_sapi.cpp), [latency/capture probe](../src/sapi/event_probe.cpp), and [Windows app compatibility record](WINDOWS_APP_COMPATIBILITY.md).

## Rate-aware follow-up run

The current proof build uses three prompt variants. Warm SAPI-site first-audio p95: `Z` 283.3 ms, `a` 282.4 ms, `yes` 285.9 ms, `next` 281.5 ms. Rapid purge/restart: median 517.1 ms, p95 525.7 ms, max 532.2 ms. Two of 20 serialized output captures exceeded their baseline by the test's 250 ms stale-audio threshold. The rate/latency command therefore did **not** pass the full stale-tail assertion. Raw captures are under `../results/sapi-latency-captures/`.

## Repeat run after the Edge rate investigation

On 2026-11-09, `scripts/test-sapi-proof.ps1 -Latency` completed using the installed 6.9M model and a freshly rebuilt DLL and probe. Warm first-audio p95 was 277.5 ms (`Z` and `a`), 278.1 ms (`yes`), and 278.3 ms (`next`). During 20 rapid purge/restart captures, first-audio median was 513.4 ms, p95 518.6 ms, and maximum 518.8 ms. All captures stayed within their matching baseline +250 ms threshold (`excess_audio=0`). The overall proof passed. Per-trial first-audio timing is now included in probe output. An earlier 735.8 ms result was from a run whose probe executable had not been rebuilt from the current source; it is retained above as historical evidence, not as the current result.

The build step matters: `test-sapi-proof.ps1` consumes existing binaries and does not rebuild them. Rebuild with `scripts/build-sapi-proof.ps1` before collecting changes to the C++ probe or adapter.

## Normal-rate voice-state fast path

The custom Angie prompt WAV returned its first HTTP audio chunk in 0.90 s on four consecutive warm requests; using its exported `.safetensors` state returned in 0.6–0.7 ms, with the same server process. The adapter now uses `VoiceStatePath` for the normal rate bucket (−2…+2) and keeps the slow/fast prompt variants for non-normal rate buckets. The full local proof passed: warm SAPI first-audio p95 was 31.7–33.3 ms, and rapid purge/restart p95 was 151.3 ms (max 161.7 ms) with no stale-tail failures. The three rate bands remained distinct: tested phrase medians were 9.72 s slow, 7.56 s normal, and 6.04 s fast.

The normal-rate fast path was followed by rate-specific `.safetensors` states generated from the slow and fast SoundTouch prompts. The adapter now prefers those states for slow/fast as well, with WAV fallback for older voices. This removes prompt re-encoding from all three rate bands while preserving the measured duration difference.

## Cached-rate and cancellable-request proof, 2026-11-09

With the 6.9M ReFL model and rebuilt DLL, `scripts/test-sapi-proof.ps1 -Latency` passed rate, cancellation, fragment, volume, and three-band latency checks. The slow/normal/fast duration ratios were 1.29/1.00/0.80. A SAPI cancel request completed in under the probe's 1 ms timer resolution. Across 20 rapid purge/restart trials per rate, first-audio p95 was 92.8 ms slow, 79.5 ms normal, and 85.7 ms fast. The corresponding 20 WAV captures per rate had no output more than one second longer than a same-word reference. Warm short-input first-audio p95 was at most 85.2 ms across all rates and cases; full per-trial data is in [`rate-cache-cancel-proof-final.log`](../results/rate-cache-cancel-proof-final.log).

The capture duration guard is one second because repeated one-word Pocket TTS output varied by several hundred milliseconds. It detects a substantial stale tail, but cannot prove absence of brief overlap in live playback. These are local proof-token measurements; the newly packaged DLL has not yet been exercised in Edge or NVDA after installation.

## Installed runtime cold-start isolation

On 2026-11-09, `scripts/measure-cold-start.ps1` launched a second installed 6.9M server on port 18766 without stopping the active speech server. Its health endpoint was ready in **588 ms**; the first short `/tts` request took **81 ms** and the next took **50 ms**. With the active server, a fresh `System.Speech` process selected installed Pocket voices in **0–29 ms** and synthesized “Hello” in **48–84 ms**. Edge's voice-picker UI refreshed in about **238 ms**, but that UI timing does not measure sound onset. These checks show that isolated server startup and SAPI selection do not account for the reported five-second wait; the corrected Edge audio test below measured the full delay.

### Cold Edge switch, Paradee to Pocket Elle

The first live audio test above was invalid as a cross-engine comparison because it switched Angie to Elle, both Pocket voices. A corrected test then closed Edge and stopped the installed Pocket worker. A new Edge process opened the local long-form test page, and Read Aloud was verified playing with `Paradee bm_fable`; no `pocket-tts.exe` process existed. Selecting `Pockettts_Elle_mono` occurred at epoch **1794274846973 ms**. The installed Pocket worker was created at **1794274851142 ms**, **4,169 ms** after selection. The next system loopback audio onset was at **1794274851890 ms**, **4,917 ms** after selection and **748 ms** after worker creation. This reproduces the user's roughly five-second wait. The audio probe records system output onset, not which application or voice produced it, so the exact first Elle sample is not independently identified. The delayed worker creation prompted the SAPI cold check below, which found the delay inside the adapter's failed health probes rather than in Edge's scheduling.

### Closed-port health-check diagnosis and fix

A fresh `System.Speech` host selecting Elle with the installed worker stopped took **45 ms** to select the token and **4,589 ms** to speak “Hello.” Thus the same delay occurs outside Edge; the interpretation that Edge alone delays the worker was incorrect. The adapter called `IsServerHealthy()` twice before creating the worker. On this machine, WinHTTP checks against the closed loopback port consume most of that time. The adapter now queries the local TCP listener table first and skips WinHTTP when port 18765 has no loopback listener. With the rebuilt DLL loaded through a temporary per-user COM override, three cold runs selected Elle in **63/44/5 ms** and spoke in **170/171/172 ms**. The COM override was removed after each test. The standard SAPI proof also passed rate and cancellation checks. This fix is packaged but is not yet installed for the user's Edge session.
