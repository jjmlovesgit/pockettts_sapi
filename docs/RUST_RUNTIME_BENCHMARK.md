# Official Rust runtime: Windows follow-up

Run 2026-11-05 with Kyutai Pocket TTS v4.0.1 release asset `pocket-tts-3.3.0-x86_64-pc-windows-msvc.zip`, x64 Windows, same Ryzen 9 9950X, cached official model weights, and the CC0 `Butter.wav` voice-donation prompt. `HF_HUB_OFFLINE=1` was set. The archive is 7,914,990 bytes; its unpacked executable is 22,080,000 bytes (SHA-256 `813CABFC2F8FC7A4E5310DEDA6025426B3164610DD9F3C3098A6078E5CC1895A`).

## Unquantized CLI generation

One fresh process per model rendered the same long passage. Times include process start, model loading, prompt encoding, and output writing. Sampled memory used psutil at 10 ms intervals; brief peaks may be missed.

| Model | Total wall time | Peak RSS / private bytes | Upstream runtime log |
| --- | ---: | ---: | --- |
| 18.2M | 1.33 s | 562.5 / 560.1 MiB | 6.56 s audio in 0.304 s (21.58×) |
| 6.9M | 1.31 s | 519.9 / 519.1 MiB | see `results/audio/rust_english_7m_2026-10.log` |
| 1.9M | 0.92 s | 501.5 / 499.3 MiB | see `results/audio/rust_english_2m_2026-10.log` |

The run log gives frame generation timing and says the voice state is 4 MB for this prompt. CLI process wall time is not the same as a persistent in-process SAPI engine, but it is a useful upper bound for a process-per-request design. The Python memory results should not be compared as an identical host setup, but the Rust binary still reaches about 500–563 MiB RSS here.

## Optional dynamic int8

`--quantize` completed for 18.2M and 6.9M, with peaks of 526.9 MiB and 510.1 MiB RSS. The apparent reduction is modest and has not been quality-reviewed. It failed on 1.9M with `quantized tensor must have their last dim divisible by block size [320, 112] 32`, so the option is not a consistent family-wide solution.

## Footprint projection and decision

The exact measured payload components are 224,924,528 bytes for all three cloning model files, 22,080,000 bytes for the unpacked CLI executable, and 480,044 bytes for the CC0 prompt, plus a shared 59,339-byte tokenizer and small configuration/license files. That is **about 247.5 MB decimal / 236 MiB** before installer compression, fitting the user's preferred 300 MB complete-install target if all three models are bundled. A single selected model is smaller. The Python environment is not required for this Rust runtime.

**Footprint: promising. Memory: still unresolved.** To reach a lower-memory design, evaluate an in-process Rust library integration or shared long-lived worker with resident model reuse, then measure host baseline, idle, and peak. The one-shot CLI's process footprint is high for the low-memory goal and restarts would repeat model/prompt setup. Listen to all generated output before selecting a model. No weights were changed. See WAVs named `rust_english_*_2026-10.wav` and corresponding logs in `results/audio/`.

## Quality diagnostic candidates

After the user found the initial small-model WAVs unsatisfactory, three comparison candidates were generated with the same prompt and passage, offline:

| Candidate | Weight size | Total output audio | End-to-end CLI wall time | Overall RTF | Peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| 18.2M + reward fine-tuning | 111,728,528 B | 19.08 s | 2.80 s | 6.81× | 570.4 MiB |
| 6.9M + reward fine-tuning | 66,482,920 B | 20.44 s | 1.64 s | 12.46× | 526.6 MiB |
| Original ~100M English reference | 219,029,196 B | 19.80 s | 3.79 s | 5.23× | 891.2 MiB |

The total audio duration was calculated from the output WAV size; overall RTF includes CLI startup, model load, prompt encoding, synthesis, and output writing. Per-chunk generation RTF in each `.log` excludes some of those costs. The reward fine-tuned checkpoint files are the same size as their corresponding base checkpoints. A single 100M model plus the 22,080,000-byte runtime and a small prompt/tokenizer is projected around 242 MB decimal / 231 MiB before installer overhead, so it may still fit the 300 MB goal when packaged alone. Human listening review of these three comparison files is needed to determine whether either reward-tuned checkpoint or the 100M reference resolves the quality complaint.

## Comparison target from Paradee-SAPI

The local [Paradee-SAPI measurement record](C:/Users/Jim/Documents/ChatGPT/Paradee/docs/SAPI_PROOF.md) used a fresh PowerShell SAPI host and sampled every 20 ms. It recorded 78.7 MiB before voice selection, 139.5–141.8 MiB after cold/warm speech (+61–63 MiB), 237.2 MiB sampled warm peak (+158.5 MiB over baseline), and 209.4–209.5 MiB private-byte peak. Its installed payload was 43.74 MiB and installer 18.08 MiB. The machine description (9950X, approximately 64 GiB RAM) matches this Pocket TTS test host closely, making these useful local engineering targets.

This is not a direct apples-to-apples runtime comparison: Pocket's current Rust results are one-shot CLI process totals (no idle baseline subtraction), while Paradee is a warmed in-process SAPI engine hosted in PowerShell. Before choosing a backend, measure Pocket in a persistent SAPI-like host with the same before-load, idle, cold-speech, warm-speech, 20 ms peak, and private-bytes phases. Keep the installed-size target under 300 MB; aim for Paradee-like incremental memory if the selected Pocket model can meet it.
