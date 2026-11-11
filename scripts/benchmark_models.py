"""Local, CPU-only benchmark for Kyutai's official small English models.

Run inside the isolated benchmark venv after installing pocket-tts==4.0.1 and
psutil. Set HF_HUB_OFFLINE=1 to require previously cached assets.
"""
from __future__ import annotations

import argparse
import json
import os
import threading
import time
from pathlib import Path

import numpy as np
import psutil
import soundfile as sf

MODELS = (
    "english_18m_2026-10",
    "english_7m_2026-10",
    "english_2m_2026-10",
)
TEXTS = (
    "Good morning. This is a short reading test, with commas, questions, and a clear ending. How does this sound?",
    "In 2026, the Pocket TTS project is testing names, numbers like 1, 2, and 3, and ordinary paragraphs for daily reading.",
    "A longer passage helps reveal whether a voice stays clear and steady over time. The listener should be able to follow each sentence without missing words or hearing repeated phrases. This test also gives us a useful measure of how quickly the computer can produce speech compared with the length of the finished audio.",
)


def event(kind: str, **data: object) -> None:
    print(json.dumps({"event": kind, **data}), flush=True)


def memory_sampler(stop: threading.Event, peaks: dict[str, int]) -> None:
    proc = psutil.Process()
    while not stop.is_set():
        try:
            mi = proc.memory_info()
            peaks["rss"] = max(peaks.get("rss", 0), mi.rss)
            full = proc.memory_full_info()
            private = getattr(full, "private", getattr(full, "uss", 0))
            peaks["private"] = max(peaks.get("private", 0), private)
        except (psutil.Error, OSError):
            pass
        stop.wait(0.02)


def run_worker(model_name: str, prompt_path: Path, out_dir: Path, idle_seconds: float) -> int:
    import torch
    from pocket_tts import TTSModel

    torch.set_num_threads(1)
    os.environ["OMP_NUM_THREADS"] = "1"
    os.environ["MKL_NUM_THREADS"] = "1"
    stop = threading.Event()
    peaks: dict[str, int] = {}
    sampler = threading.Thread(target=memory_sampler, args=(stop, peaks), daemon=True)
    sampler.start()
    started = time.perf_counter()
    model = TTSModel.load_model(language=model_name)
    load_seconds = time.perf_counter() - started
    event("loaded", model=model_name, load_seconds=load_seconds, sample_rate=model.sample_rate)

    clone_started = time.perf_counter()
    state = model.get_state_for_audio_prompt(str(prompt_path))
    clone_seconds = time.perf_counter() - clone_started
    event("prompt_ready", model=model_name, prompt=str(prompt_path), prompt_seconds=clone_seconds)

    time.sleep(max(0.0, idle_seconds))
    event("idle", model=model_name, seconds=idle_seconds,
          rss_bytes=psutil.Process().memory_info().rss,
          private_bytes=getattr(psutil.Process().memory_full_info(), "private", 0))

    out_dir.mkdir(parents=True, exist_ok=True)
    for i, text in enumerate(TEXTS, 1):
        t0 = time.perf_counter()
        audio = model.generate_audio(state, text)
        wall = time.perf_counter() - t0
        samples = audio.detach().cpu().numpy() if hasattr(audio, "detach") else np.asarray(audio)
        samples = np.asarray(samples, dtype=np.float32).reshape(-1)
        audio_seconds = len(samples) / float(model.sample_rate)
        path = out_dir / f"{model_name}_{i}.wav"
        sf.write(path, samples, model.sample_rate)
        event("render", model=model_name, case=i, text=text, wall_seconds=wall,
              audio_seconds=audio_seconds,
              real_time_factor=(audio_seconds / wall if wall else None),
              wav=str(path), wav_bytes=path.stat().st_size)

    stop.set()
    sampler.join(timeout=1)
    event("complete", model=model_name, load_seconds=load_seconds,
          prompt_seconds=clone_seconds, peak_rss_bytes=peaks.get("rss"),
          peak_private_bytes=peaks.get("private"))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--worker", choices=MODELS)
    parser.add_argument("--prompt", type=Path, default=Path("assets/Butter.wav"))
    parser.add_argument("--out", type=Path, default=Path("results/audio"))
    parser.add_argument("--idle-seconds", type=float, default=60)
    args = parser.parse_args()
    if args.worker:
        if not args.prompt.is_file():
            raise SystemExit(f"Prompt not found: {args.prompt}")
        return run_worker(args.worker, args.prompt, args.out, args.idle_seconds)
    print("Run one model per fresh process, e.g. --worker english_18m_2026-10")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
