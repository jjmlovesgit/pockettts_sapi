# Milestone 1: local benchmark, initial results

Run on 2026-11-05 in CPU-only mode with `HF_HUB_OFFLINE=1` after downloading official assets. This is a first local benchmark pass, not final adapter approval: subjective speech-quality review and a production-runtime footprint check remain open.

## Machine and setup

- Windows x64; AMD Ryzen 9 9950X, 16 cores / 32 logical processors; 61.6 GiB RAM.
- Python 3.12.4, `pocket-tts==4.0.1`, PyTorch 2.15.0+cpu. One Torch thread.
- Official cloning weights at `db04f0e653473e5c7333c69686ac92b7460b0c1d`; SentencePiece tokenizer at `08ffc58775e62aad9409511b9591c9af626270f3`.
- Voice prompt: `assets/Butter.wav`, 480,044 bytes, from the official volunteer-donation set (CC0); SHA-256 `B889E080EEC3EFA824BDDAF875B4F531D75464F88128D08941AE648D9D3ADE70`.
- The model weights and prompt were cached before the measured run. Network access was disabled for the generation pass. Speech sample rate: 24 kHz mono.

## Results

Model file bytes come from the official downloaded artifacts. RSS is process working set. Peak sampling ran every 20 ms. “Private” is Windows private committed bytes reported by psutil; this unusually large value includes Python/PyTorch and is not resident RAM.

| Model | Weight file | Idle RSS after 60 s | Peak RSS while speaking | Peak private bytes | Prompt to voice-state | RTF case 1 / 2 / 3 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 18.2M | 111,728,528 B (106.6 MiB) | 553,574,400 B (527.9 MiB) | 763,961,344 B (728.5 MiB) | 2,403,688,448 B (2,292.0 MiB) | 0.77 s | 12.10× / 11.18× / 11.48× |
| 6.9M | 66,482,920 B (63.4 MiB) | 522,350,592 B (498.1 MiB) | 719,888,384 B (686.5 MiB) | 2,429,153,280 B (2,317.1 MiB) | 0.73 s | 13.07× / 12.56× / 11.35× |
| 1.9M | 46,713,080 B (44.5 MiB) | 503,472,128 B (480.3 MiB) | 697,847,808 B (665.5 MiB) | 2,254,712,832 B (2,150.4 MiB) | 0.75 s | 10.64× / 10.76× / 9.80× |

RTF is generated audio seconds divided by wall-clock generation seconds; above 1× is faster than real time. Each model rendered the same three English prompts from the same licensed prompt. Results are single-pass per case, useful for a first comparison but too small a sample to treat as stable performance estimates. `TTSModel.load_model()` returned in 0.08–0.13 s with assets already cached; this is a warm-cache load and does not measure fresh download or first-ever initialization.

The three model weights total **224,924,528 bytes (214.5 MiB)**. The isolated Python environment occupies **920,072,376 bytes (877.5 MiB)** across 28,371 files, before installer compression. These numbers show that the Python deployment does not meet the small-install goal by itself. The official Rust Windows binary must be measured as the next runtime candidate before rejecting Pocket TTS as a whole.

## Speech quality and cloning observations

Each model successfully loaded the CC0 volunteer's audio prompt and generated all three output files offline. This confirms the basic prompt-conditioning path works in the official Python package for all three checkpoint sizes. The user found those initial outputs unsatisfactory; the later Sloane prompt comparison below passed subjective review.

User listening first found the Butter prompt WAVs “not all that great.” Replacing it with the user-provided Sloane prompt improved the results: the user approved all three small models, both small reward-fine-tuned variants, and the ~100M reference for this matched passage. See [Sloane prompt comparison](SLOANE_PROMPT_COMPARISON.md). Speech quality passes for this sample set; general quality remains to be verified across representative text and voice prompts.

Output WAVs are in `results/audio/` (`english_{18m,7m,2m}_2026-10_{1,2,3}.wav`). The 1.9M results are explicitly experimental upstream. No model was modified, fine-tuned, or quantized.

## Gate decision

**GO to a scoped SAPI proof using `english_7m_refl_2026-10` (6.9M).** The user approved the full Sloane prompt comparison and 5.36-/9.15-second excerpt outputs. The persistent Rust server with the 5.36-second prompt measured 83.3 MiB idle RSS, 149.2 MiB after warm speech, and 251.8 MiB sampled peak RSS; first response chunks arrived in 23 and 32 ms. The model weight is 66.5 MB, giving a large margin under the 300 MB installed-size target for a single-model package. This is one measurement cycle; repeat and app-host integration gates remain before product acceptance. The 1.9M model fails optional CLI int8 quantization and is not the selected candidate.
