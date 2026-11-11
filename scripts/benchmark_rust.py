"""Measure the official Windows Pocket TTS binary on local cached assets."""
from __future__ import annotations

import json
import os
import subprocess
import time
import argparse
from pathlib import Path

import psutil

ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / ".benchmark-cache/rust/unpacked/pocket-tts-3.3.0-x86_64-pc-windows-msvc/pocket-tts.exe"
PROMPT = ROOT / "assets/Butter.wav"
OUT = ROOT / "results/audio"
MODELS = (
    "english_18m_2026-10", "english_7m_2026-10", "english_2m_2026-10",
    "english_18m_refl_2026-10", "english_7m_refl_2026-10", "english_2026-10",
)
TEXT = "A longer passage helps reveal whether a voice stays clear and steady over time. The listener should be able to follow each sentence without missing words or hearing repeated phrases. This test also gives us a useful measure of how quickly the computer can produce speech compared with the length of the finished audio."

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--quantize", action="store_true")
    parser.add_argument("--model", action="append", choices=MODELS,
                        help="Model to run; repeat to run multiple. Defaults to all.")
    parser.add_argument("--prompt", type=Path, default=ROOT / "assets/Butter.wav")
    parser.add_argument("--text", default=TEXT)
    parser.add_argument("--output-prefix", default="rust")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["HF_HUB_CACHE"] = str(ROOT / ".benchmark-cache/hf")
    env["HF_HUB_OFFLINE"] = "1"
    for model in (args.model or MODELS):
        wav = OUT / f"{args.output_prefix}_{model}.wav"
        log = OUT / f"{args.output_prefix}_{model}.log"
        cmd = [str(EXE), "generate", "--language", model, "--voice", str(args.prompt),
               "--text", args.text, "--output-path", str(wav)]
        if args.quantize:
            cmd.append("--quantize")
        started = time.perf_counter()
        proc = subprocess.Popen(cmd, cwd=ROOT, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True)
        child = psutil.Process(proc.pid)
        rss_peak = private_peak = 0
        while proc.poll() is None:
            try:
                rss_peak = max(rss_peak, child.memory_info().rss)
                private_peak = max(private_peak, child.memory_full_info().private)
            except psutil.Error:
                pass
            time.sleep(0.01)
        output, _ = proc.communicate()
        wall = time.perf_counter() - started
        log.write_text(output, encoding="utf-8")
        if proc.returncode:
            raise SystemExit(f"{model} failed ({proc.returncode}); see {log}\n{output}")
        event = {"model": model, "wall_seconds": wall, "peak_rss_bytes": rss_peak,
                 "peak_private_bytes": private_peak, "wav": str(wav),
                 "wav_bytes": wav.stat().st_size, "log": str(log),
                 "quantized": args.quantize}
        print(json.dumps(event), flush=True)

if __name__ == "__main__":
    main()
