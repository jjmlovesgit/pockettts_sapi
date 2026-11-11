"""Capture the current default speaker's WASAPI loopback for an NVDA trial."""

import argparse
import json
import threading
import time
from pathlib import Path

import numpy as np
import psutil
import soundcard as sc
from scipy.io import wavfile


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seconds", type=float, default=20)
    parser.add_argument("--device", help="Substring of an output-device name; defaults to the system default")
    parser.add_argument("--process", action="append", default=[], help="Process name to sample; may be repeated")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    process_names = {name.lower().removesuffix(".exe") for name in args.process}

    speakers = sc.all_speakers()
    matches = [speaker for speaker in speakers if args.device.lower() in speaker.name.lower()] if args.device else [sc.default_speaker()]
    if len(matches) != 1:
        raise SystemExit(f"Expected one output device, found {len(matches)}: {[s.name for s in matches]}")
    speaker = matches[0]
    microphone = sc.get_microphone(speaker.id, include_loopback=True)
    rate = 48000
    samples = []
    process_stats = {}
    processes = []
    for process in psutil.process_iter(["name"]):
        name = (process.info.get("name") or "").lower().removesuffix(".exe")
        if name not in process_names:
            continue
        try:
            cpu = process.cpu_times()
            processes.append((process, {
                "name": name, "pid": process.pid, "first_cpu_s": cpu.user + cpu.system,
                "max_rss_bytes": process.memory_info().rss, "last_cpu_s": cpu.user + cpu.system,
            }))
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    sampling = threading.Event()

    def sample_processes() -> None:
        while not sampling.wait(0.5):
            for process, stats in processes:
                try:
                    cpu = process.cpu_times()
                    stats["last_cpu_s"] = cpu.user + cpu.system
                    stats["max_rss_bytes"] = max(stats["max_rss_bytes"], process.memory_info().rss)
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue

    sampler = threading.Thread(target=sample_processes, daemon=True)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    ready = args.out.with_suffix(".ready.json")
    with microphone.recorder(samplerate=rate, channels=2, blocksize=1024) as recorder:
        start = time.time()
        ready.write_text(json.dumps({"start_epoch_s": start, "device": speaker.name, "sample_rate": rate}), encoding="utf-8")
        sampler.start()
        while time.time() - start < args.seconds:
            samples.append(recorder.record(numframes=1024))
        sampling.set()
        sampler.join()
    process_stats = {str(stats["pid"]): stats for _, stats in processes}
    audio = np.concatenate(samples, axis=0)
    wavfile.write(args.out, rate, np.clip(audio * 32767, -32768, 32767).astype(np.int16))
    end = time.time()
    for stats in process_stats.values():
        stats["cpu_delta_s"] = round(stats["last_cpu_s"] - stats["first_cpu_s"], 4)
        stats.pop("first_cpu_s")
        stats.pop("last_cpu_s")
    args.out.with_suffix(".complete.json").write_text(
        json.dumps({"start_epoch_s": start, "end_epoch_s": end, "duration_s": round(end-start, 3),
                    "frames": len(audio), "device": speaker.name, "process_stats": list(process_stats.values())}, indent=2),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
