# SAPI rate support

Run: 2026-11-09, Windows x64, official 6.9M ReFL model, warm local Rust server, Sloane prompt. The SAPI proof routes each utterance to a stored slow, normal, or fast audio prompt based on the combined `ISpTTSEngineSite::GetRate` and SAPI fragment `RateAdj` value.

## Results

| SAPI rate | Selected prompt pace | Median output duration | Relative duration |
|---:|---|---:|---:|
| −5 | Slow, source tempo 0.70× | 9.56 s | 1.25× normal |
| 0 | Original prompt | 7.64 s | baseline |
| +5 | Fast, source tempo 1.40× | 6.04 s | 0.79× normal |

Three utterances were captured at each setting. SAPI XML `<rate absspeed>` fragments also selected variants: −5 generated 9.72 s and +5 generated 6.04 s. Rate buckets are discrete: −10…−3 selects slow, −2…+2 normal, and +3…+10 fast. SAPI does not get 21 distinct Pocket TTS speeds from this mapping.

Current SAPI output captures: [slow](../results/sapi-rate-captures/rate_slow_1.wav), [normal](../results/sapi-rate-captures/rate_normal_1.wav), and [fast](../results/sapi-rate-captures/rate_fast_1.wav). The standalone prompt-clone samples generated using the same SoundTouch transform are [slow](../results/clone-rate-experiment/soundtouch/slow.wav), [normal](../results/clone-rate-experiment/soundtouch/normal.wav), and [fast](../results/clone-rate-experiment/soundtouch/fast.wav). The user listened to the integrated SAPI outputs and confirmed they sound excellent with clearly distinct pace.

## Implementation

Voice Manager creates slow, normal, and fast prompt variants at voice creation time. Each WAV is normalized to 24 kHz mono PCM and capped at 1.8 MB. It also exports slow and fast `.safetensors` sidecars from those pace-adjusted WAVs. The SAPI engine uses the original voice state for normal rate (−2…+2) and the pace sidecars for slow and fast rates. If a sidecar is missing, it falls back to the corresponding WAV. A state over the server's 2 MiB upload limit is re-exported from a six-second excerpt of its pace-adjusted WAV. Current SoundTouch prompt variants retained distinct output durations after state export; this corrects the earlier finding based on older prompt samples. The three pace bands remain discrete.

**Legacy-token repair:** custom tokens created before pace prompts were added have only `VoiceStatePath`; they continue to use the same voice state for every SAPI rate. Supply the original authorized PCM prompt to `scripts/VoiceManager.ps1 -SetVoicePromptVariants <token-id> -PromptAudio <original.wav> -ConfirmAuthorizedPrompt` to add the three pace paths without changing the cloned state. This updates both classic SAPI and OneCore registrations and requires Windows elevation. Do not infer/reconstruct a speaker prompt from a `.safetensors` state.

Applied to `PocketTTS.Custom.Sloane_170.38aae283` using the original `Sloane_170WPM.wav`. Slow, normal, and fast prompt WAVs are registered in both classic SAPI and OneCore; the exported `.safetensors` voice state was left unchanged. On 2026-11-09, Edge Read Aloud used `Sloane_170` on the local compatibility page. The user moved the speed slider from `0.5` to `2.0` during playback and confirmed the speech pace changed audibly.

Prompt tempo conversion uses SoundTouch 2.3.3, dynamically linked as `pocket_soundtouch.dll`; the DLL is small and included with its LGPL 2.1 license and source archive. Prompt variants and cached states are made offline. Current rate-enabled import supports 16-bit PCM WAV with one or two channels, sampled from 8 to 96 kHz. MP3 and compressed WAV input are rejected with an explanation.

## Latency and remaining checks

Warm SAPI-site first-audio p95 with prompt upload and re-encoding was 283.3 ms (`Z`), 282.4 ms (`a`), 285.9 ms (`yes`), and 281.5 ms (`next`)—under the 600 ms target. Rapid purge/restart p95 was 525.7 ms (max 532.2 ms), also under 600 ms, but 2 of 20 captured outputs exceeded the baseline stale-audio threshold, so that run failed its stale-tail check. Repeat the overlap investigation before closing Gate 2.

The test command is `scripts/test-sapi-proof.ps1`; use `-Latency` for first-audio and rapid-restart measurements. The standard rate proof verifies both `SetRate` and XML fragment selection, cancellation, voice-state fallback, and output duration. Mid-utterance rate changes are not verified. Rate changes alter the prompt conditioning, so verify voice identity, pitch, and speech quality in the integrated samples before release. See [Windows app compatibility](WINDOWS_APP_COMPATIBILITY.md) and [latency benchmark](SAPI_LATENCY_BENCHMARK.md).
