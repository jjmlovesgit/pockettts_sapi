# User supplied prompt comparison

Run 2026-11-05 after the user said the original passage/sample was poor and provided `C:\Users\Jim\Downloads\Sloane_170WPM.wav`. The WAV was used as the **audio voice prompt**; the matched benchmark passage remained the same. No speech inside the file was treated as instructions. The source file is mono, 16-bit PCM, 24 kHz, 23.946 seconds, 1,149,470 bytes. The benchmark did not modify the source WAV. All generation ran with `HF_HUB_OFFLINE=1`.

| Model | Output duration | End-to-end wall time | Overall RTF | Peak RSS | Prompt encoding (from Rust log) |
| --- | ---: | ---: | ---: | ---: | ---: |
| 18.2M | 18.20 s | 3.07 s | 5.93× | 2,398.8 MiB | 2.21 s |
| 6.9M | 19.16 s | 2.69 s | 7.12× | 2,379.2 MiB | 1.84 s |
| 1.9M | 20.04 s | 2.14 s | 9.38× | 2,339.1 MiB | 1.71 s |
| 18.2M + reward fine-tuning | 18.12 s | 2.57 s | 7.05× | 2,398.9 MiB | 1.71 s |
| 6.9M + reward fine-tuning | 19.72 s | 2.58 s | 7.64× | 2,357.9 MiB | 1.70 s |
| Original ~100M reference | 18.28 s | 4.15 s | 4.40× | 2,728.9 MiB | 1.77 s |

RTF includes process start, model load, prompt encoding, synthesis, and WAV write. Output durations derive from WAV size at 24 kHz mono PCM16. Rust's per-chunk generation logs omit startup and prompt costs. RSS was sampled every 10 ms; private bytes and sampling limitations are in individual runner JSON output / process metrics where available. The 23.9-second prompt sharply increases peak memory compared with the short CC0 benchmark prompt (about 500–900 MiB in the one-shot Rust runs). This is a critical prompt-length behavior to investigate before accepting arbitrary-length audio in a SAPI voice utility.

Audio files are `results/audio/sloane_<model>.wav`; log files share the same base name. Keep SAPI implementation on hold until prompt-length and persistent-host resource use are measured. The provided voice prompt's speaker/reuse permission is supplied by the user for this local test only; do not redistribute the prompt or generated examples.

User listening review (2026-11-05): “much better -- these are all good.” Mark speech quality as **pass for this prompt and passage** for all six candidates. This does not establish quality with all voices, text types, prompt lengths, or applications. Next resource investigation should shorten the 23.9-second prompt at natural pauses and confirm quality and memory at those practical prompt lengths.

## Natural-pause prompt-length test

Two PCM excerpts from the supplied file were cut at its natural pauses near 5.36 and 9.15 seconds (the original file was left intact). Fresh Rust CLI processes generated the same passage from each excerpt for the 18.2M ReFL, 6.9M ReFL, and ~100M reference models.

| Prompt / model | End-to-end time | Peak RSS | Peak private bytes |
| --- | ---: | ---: | ---: |
| 5.36 s / 18.2M ReFL | 1.12 s | 269.7 MiB | 324.8 MiB |
| 5.36 s / 6.9M ReFL | 1.09 s | 280.8 MiB | 285.6 MiB |
| 5.36 s / ~100M | 2.54 s | 770.1 MiB | 769.9 MiB |
| 9.15 s / 18.2M ReFL | 1.39 s | 491.0 MiB | 510.6 MiB |
| 9.15 s / 6.9M ReFL | 1.28 s | 469.2 MiB | 468.4 MiB |
| 9.15 s / ~100M | 2.89 s | 819.1 MiB | 820.9 MiB |

This initial one-shot sampling suggests prompt duration is a major memory factor for small checkpoints. The 5.36-second prompts stayed near/below 300 MiB RSS for the small models; the 9.15-second prompts did not. This is process-total RSS without host-baseline subtraction, sampled every 10 ms. It does not yet represent a resident SAPI host. User listening review for the excerpt-conditioned outputs is pending. Files use prefixes `sloane5_` and `sloane9_` in `results/audio/`; excerpt prompts are in the benchmark cache and are not package assets.

User listening review (2026-11-05): the user confirmed the 5.36- and 9.15-second excerpt-conditioned comparison outputs “sound good.” Quality passes for these prompt lengths for the tested models/passage. This supports a practical prompt-duration limit as an option, subject to the persistent-runtime and broader voice/text checks.
