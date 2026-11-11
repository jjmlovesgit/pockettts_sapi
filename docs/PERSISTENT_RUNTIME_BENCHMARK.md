# Persistent Rust runtime benchmark

Run 2026-11-05 using Kyutai's official v4.0.1 Rust `serve` binary, offline, on Windows x64 / Ryzen 9 9950X / 16 cores / 64 GiB RAM. The server kept one model and one 5.36-second Sloane prompt state resident. Each model had a fresh server process, 10 seconds idle after readiness, then two sequential local `/tts` requests with the same long test passage. RSS/private values are process totals sampled every 10 ms; they include the server/runtime process. This is one measured cycle per model, not a variance study.

| Candidate | Ready time | Idle after load (RSS/private) | After warm speech | Sampled peak (RSS/private) | First response chunk, req 1/2 | Full response, req 1/2 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 18.2M ReFL | 0.51 s | 125.8 / 120.8 MiB | 238.1 / 233.4 MiB | 341.0 / 348.6 MiB | 44 / 46 ms | 0.935 / 0.854 s |
| 6.9M ReFL | 0.52 s | 83.3 / 78.2 MiB | 149.2 / 143.7 MiB | 251.8 / 284.8 MiB | 23 / 32 ms | 0.803 / 0.710 s |

Prompt encoding occurred at server startup through `--default-voice`; generation reused the resulting voice state. Server requests ran only over loopback; `HF_HUB_OFFLINE=1` prevented model downloads. Generated outputs are `results/audio/persistent_*.wav`. Runner and per-model logs are in `scripts/benchmark_persistent_server.py` and `results/audio/persistent_*.log`.

## Decision

The 6.9M ReFL result is promising for an initial SAPI proof: the user approved this model's five-second-prompt audio, the loaded idle RSS was 83 MiB, the warm post-speech RSS was 149 MiB, and sampled process peak RSS was 252 MiB. The Rust offline payload is projected well below 300 MB for a single model. The 18.2M ReFL candidate exceeds a 300 MiB peak RSS target in this server run. Proceed to a narrowly scoped SAPI proof using 6.9M ReFL and the 5–6-second prompt workflow, while repeating the measurement and testing prompt errors, cancellation, app compatibility, and offline install before calling the product accepted. These results do not prove a final installer or clean-machine behavior.
