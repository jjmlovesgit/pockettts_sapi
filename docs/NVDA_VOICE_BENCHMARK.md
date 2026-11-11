# NVDA voice navigation benchmark

Status: **NVDA 2026.3.1 selects the requested Pocket SAPI 5 voice with NVDA WASAPI off; warm navigation response measured, final-line correctness remains unverified by this capture** (2026-11-10). With "Use modern audio output system (WASAPI)" enabled, the user heard Alba after selecting other Pocket voices. The installed diagnostic DLL recorded NVDA repeatedly sending `PocketTTSDefaultAlba` to `ISpTTSEngine::Speak`, despite a saved Angie token in `nvda.ini`. After the user disabled that NVDA option, traces recorded Angie, cloned Sloane, and Dutch Daan requests with their correct `VoiceStatePath` values. This establishes voice-token selection when NVDA WASAPI is off, but not a fix for the WASAPI-on path.

## Observed compatibility

| Voice or path | Result on this PC | Evidence | Still to measure |
|---|---|---|---|
| Alba, English default | Speaks in NVDA | NVDA sent the Alba SAPI token; the user heard Alba. | Cold and warm audible onset; rapid navigation. |
| Angie, English clone | Correct voice token and state reached the engine with NVDA WASAPI off | 47 Angie `Speak` entries in the diagnostic trace; the user reports Pocket voice switching works well. | Per-voice audible onset and interruption. |
| Sloane, English clone | Correct voice token and state reached the engine with NVDA WASAPI off | 8 Sloane `Speak` entries; the worker selected Sloane's state. | Per-voice audible onset and interruption. |
| Daan, Dutch pack | Correct language token and state reached the engine with NVDA WASAPI off | 4 Daan `Speak` entries with the Dutch voice state. | Dutch listening assessment and navigation. |
| Pocket voices with NVDA WASAPI on | Voice selection failed in this session | The user heard Alba after choosing other voices; NVDA's trace showed Alba token requests. | Determine the NVDA alternate-output-path mechanism; retest after any fix. |
| Microsoft David and Mark, SAPI 5 / OneCore | Comparison not run | Their tokens are installed, but no matched NVDA listening or loopback trial was captured. | Full baseline rows below. |

The trace counts are diagnostic utterances across interactive tests, not timed benchmark samples. The user's latest overall assessment of the working Pocket voices was “works great.” These observations do not supply numeric latency or error rates.

## Rapid-navigation pilot (2026-11-10)

I drove the existing 20-line Notepad fixture with NVDA 2026.3.1 and the selected cloned Sloane SAPI 5 voice. From the first line, the test sent 19 Down Arrow presses roughly 150 ms apart, paused, then sent 10 Up Arrow presses at the same pace. NVDA's SAPI WASAPI option remained off. The Logi USB headset output was recorded with WASAPI loopback; keypress timestamps and the SAPI trace were captured separately.

| Observation | Result | Evidence / limit |
|---|---|---|
| Final line after the Down sequence | Not confirmed | Recognition of the short end-window did not reliably match the expected line 20. |
| Final line after the Up sequence | Not confirmed | Recognition of the short end-window did not reliably match the expected line 10. |
| Final keypress to next audible sound | About 442 ms Down; 466 ms Up in the first capture | 20 ms RMS windows, threshold 0.006 full scale. Two warm-cache observations, not a median or p95. |
| Purge/cancellation requests | Present | 29 Sloane `Speak` entries and 28 `write_abort` entries in the first trace. All fetches were cache hits, so this does not measure new-text synthesis. |
| Stale speech, overlap, clipping, stop latency | Not graded | These recordings do not establish zero artifacts or an interruption distribution. |

Artifacts: [recording](../results/nvda-rapid2-listen.wav), [key timestamps](../results/nvda-rapid2-keys.json), and [SAPI trace](../results/nvda-rapid2-trace.txt). Diagnostic tracing was disabled after the run. The full trial counts and first-time-text measurements below remain open.

### Settled rapid-navigation retest on the rolled-back installer

After the user confirmed the previous installer worked again, NVDA SAPI 5 was run with `Pokettts_Sloane` selected and NVDA's modern WASAPI option off. The same 20-line Notepad fixture received 19 Down presses, a 3.65 second pause, then 10 Up presses. The capture lasted 22.03 seconds from the Logi USB headset loopback.

| Metric | Result | Evidence / limit |
|---|---:|---|
| Final Down key to next audio above 0.006 RMS | 460 ms | Single warm-cache observation, 20 ms RMS windows. |
| Final Up key to next audio above 0.006 RMS | 460 ms | Single warm-cache observation, 20 ms RMS windows. |
| SAPI utterances / write cancellations / completed fragments | 29 / 27 / 2 | All 29 requests were cache hits. This validates cancellation activity, not first-time synthesis speed. |
| Pocket worker peak working set | 177,881,088 bytes (169.6 MiB) | Worker CPU delta was 0.0 seconds because every captured request hit cache. |
| NVDA peak working set / CPU | 186,183,680 bytes (177.5 MiB) / 0.516 seconds | Approximately 2.3% of one logical CPU over the 22.03 second capture. |
| Expected final line recognition | Not confirmed | Local Whisper did not reliably recognize the expected line 20 or line 10 from the short crops. Treat final-line accuracy, stale-tail audibility, and clipping as unverified. |

Artifacts: [settled loopback recording](../results/nvda-sloane-settled-loopback.wav), [capture/process statistics](../results/nvda-sloane-settled-loopback.complete.json), and [SAPI trace](../results/nvda-sloane-settled-trace.txt). The currently installed DLL is the prior installer build, not the rejected lead-trim candidate. The temporary SAPI trace registry override was cleared after capture.

### Microsoft David final comparison attempt (2026-11-10)

NVDA's Speech settings showed Microsoft David - English (United States) in the 64-bit SAPI 5 synthesizer, with NVDA WASAPI off. The same Notepad fixture received 19 Down presses, a 3.5 second pause, then 10 Up presses. The user-facing voice choice was confirmed in NVDA and in `nvda.ini`.

| Metric | Result | Evidence / limit |
|---|---:|---|
| Capture duration | 60.04 seconds | Logi USB headset system loopback. |
| NVDA peak working set / CPU | 209,969,152 bytes (200.2 MiB) / 0.625 seconds | About 1.0% of one logical CPU over the capture. |
| Pocket worker peak working set / CPU | 178,184,192 bytes (169.9 MiB) / 0.0 seconds | Worker was resident but idle for this Microsoft voice test. |
| Final-key-to-audio onset | Invalid | System loopback already contained audio at the last key; it cannot isolate David's onset. |
| Final line recognition | Not confirmed | Local speech recognition returned unrelated speech instead of the expected fixture lines, indicating the captured system output was contaminated. Do not compare this run's timing with Sloane. |

Artifacts: [David loopback recording](../results/nvda-david-final3-loopback.wav), [capture/process statistics](../results/nvda-david-final3-loopback.complete.json), and [key timestamps](../results/nvda-david-final3-keys.json). No Pocket SAPI trace was produced because Microsoft David bypasses the Pocket engine. The temporary trace registry override was cleared after capture.

### David clean-fixture retry (2026-11-10)

The fixture was verified clean before and after another 19 Down / 10 Up run, with Microsoft David selected and NVDA WASAPI off. A prior accidental test hotkey insertion was undone before this retry. The capture still does not yield a valid latency or intelligibility result: the loopback already had substantial audio before the final keys, the measured threshold crossing was therefore 0 ms, and local recognition did not return the expected line text.

| Metric | Result | Evidence / limit |
|---|---:|---|
| NVDA peak working set / CPU | 212,606,976 bytes (202.7 MiB) / 0.5312 seconds | About 1.8% of one logical CPU over the 30.04 second capture. |
| Pocket worker peak working set / CPU | 178,184,192 bytes (169.9 MiB) / 0 seconds | Resident worker was idle. |
| Threshold onset after final Down / Up | 0 / 0 ms | Invalid: pre-key RMS was already 0.127 / 0.078, so these do not measure a new utterance onset. |
| Expected final-line recognition | Not confirmed | Local recognition returned “I'm sorry” and “I,” not fixture lines 20 and 10. |

Artifact: [clean-fixture David loopback](../results/nvda-david-final4-loopback.wav) and [capture/process statistics](../results/nvda-david-final4-loopback.complete.json). Do not use this retry as a David-versus-Sloane latency comparison. The Pocket trace override is cleared.

### Matched Microsoft David pilot

After the user selected Microsoft David in NVDA, I repeated the same Notepad fixture, Logi USB headset, 19 Down / 10 Up key sequence, and roughly 150 ms key spacing. I did not change NVDA settings during this capture. The saved `nvda.ini` still contains an older Pocket voice value, so the in-memory David selection is based on the user's confirmation; the Microsoft runtime token was not independently traced.

| Final keypress to next audible sound | Pocket Sloane | Microsoft David | Pilot difference |
|---|---:|---:|---:|
| Down sequence, ending at line 20 | ~460 ms | ~155 ms | David ~305 ms earlier |
| Up sequence, ending at line 10 | ~463 ms | ~103 ms | David ~360 ms earlier |

Both captures were analyzed in 20 ms RMS windows on the same output device, using a 0.006 full-scale threshold. Thresholds from 0.004 to 0.015 moved the estimates by at most 20 ms for Sloane and 20 ms for David's Up result; David's Down result ranged 135–155 ms. Local speech recognition returned the correct final fixture lines for David in both directions. This supports a meaningful speed gap in these two warm navigation sequences, **not** a median, p95, first-time-text comparison, or claim about all Microsoft voices. [David recording](../results/nvda-david-rapid-loopback.wav) and [key timestamps](../results/nvda-david-rapid-keys.json).

### Leading-silence diagnosis and candidate fix

The direct Sloane SAPI WAV begins with about **420 ms** of near-silence; a second Sloane capture begins at about **480 ms**. The David comparison WAV begins at about **120 ms**. This explains most of the measured NVDA gap without implicating model loading or the replay cache. The adapter now removes generated leading near-silence while keeping 100 ms before sustained speech energy. Explicit SAPI silence fragments are handled separately and are not trimmed. Word-boundary offsets are calculated on the resulting PCM length.

The rebuilt DLL rendered “The final line says the test is complete” through `System.Speech`; the first audible PCM was at about **100 ms**, and local transcription retained the complete sentence. The per-user COM override was restored to the installed DLL immediately after this proof. The candidate is packaged as `build/PocketTTS-SAPI-Setup-LeadTrim.exe` (50.7 MB); **it has not yet been installed or retested in NVDA**. Check quiet initial consonants, other languages, Edge highlighting, and rapid cancellation after installation before treating the fix as accepted.

## Voices to compare

Use the same English text and NVDA speech rate as closely as the drivers allow. Compare Pocket TTS Sloane with Windows Microsoft David and Mark in NVDA's SAPI 5 synthesizer first. Also run the native Windows OneCore synthesizer with David and Mark, if NVDA lists them, as a real-world baseline. Keep Zira as an optional different-voice check. Record the exact NVDA version, synthesizer, selected voice, speed setting, Windows output device, Pocket model, and whether its worker was already warm. The installed Microsoft SAPI 5 and OneCore tokens currently include David, Mark, and Zira.

| Metric (same document and key sequence) | Pocket Sloane, SAPI 5 | MS David, SAPI 5 | MS Mark, SAPI 5 | MS David, OneCore | MS Mark, OneCore |
|---|---:|---:|---:|---:|---:|
| Correct voice selected in NVDA | Pass with WASAPI off | Pending | Pending | Pending | Pending |
| NVDA SAPI WASAPI setting | Off required in this session | Pending | Pending | Not applicable | Not applicable |
| First audible sound after cold launch, ms | Pending | Pending | Pending | Pending | Pending |
| New short line, warm: median / p95 onset, ms | Pending | Pending | Pending | Pending | Pending |
| New full sentence, warm: median / p95 onset, ms | Pending | Pending | Pending | Pending | Pending |
| Return to an identical earlier line: median / p95 onset, ms | Pending | Pending | Pending | Pending | Pending |
| 20 rapid Down Arrow trials: correct final line / 20 | Pending | Pending | Pending | Pending | Pending |
| 10 rapid Up Arrow trials: correct final line / 10 | Pending | Pending | Pending | Pending | Pending |
| Stop command to last audible sample: median / p95, ms | Pending | Pending | Pending | Pending | Pending |
| Stale or overlapping speech after direction change: count / 20 | Pending | Pending | Pending | Pending | Pending |
| Clipped first or last word: count / 20 | Pending | Pending | Pending | Pending | Pending |
| Sustained CPU / working-set RAM while reading | Pending | Pending | Pending | Pending | Pending |
| Subjective responsiveness and intelligibility | Pending | Pending | Pending | Pending | Pending |

## Test procedure

1. Prepare one plain-text document with 20 short, unique navigation lines, 10 ordinary sentences, and 3 long paragraphs. Save the exact file and its SHA-256 with results. Use the same application and document for every voice.
2. Fix audio output device, Windows volume, NVDA punctuation level, and NVDA rate. Record synthesizer-specific rate values and read a reference paragraph to estimate actual words per minute; a matching slider number alone does not mean matching speech pace.
3. For each voice, perform one genuine cold start and then warm runs. Time from the key event to first **audible loopback PCM**, not to SAPI completion or screen highlighting. Use at least 20 trials for each warm onset row and report median and p95. Run voice order in rotation to reduce warm-up bias.
4. Read forward, revisit an identical previously spoken line, move rapidly forward and backward, then press NVDA's stop key while a long paragraph is speaking. Capture the key timestamps and system loopback audio. Mark the actual last spoken line and any old speech heard after the cursor moved. Leave enough separation between trials to assign onsets to keys.
5. Repeat at a practical faster NVDA rate, recording actual intelligibility and missed or clipped words. Treat first-time text and exact replay as distinct cases; Pocket's bounded in-process replay cache can only accelerate an utterance after it has been synthesized once in that process.

The primary acceptance criterion is that rapid navigation speaks the **current** item promptly, with no sustained stale speech, clipping, or overlap. First-time latency matters at least as much as replay latency for NVDA use. A cache hit measured inside SAPI does not establish audible onset in NVDA; its speech queue and audio device must be measured end to end.
