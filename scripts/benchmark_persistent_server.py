"""Measure the official Rust server with a local preloaded voice prompt."""
from __future__ import annotations

import http.client
import json
import os
import socket
import subprocess
import threading
import time
from pathlib import Path
from urllib.parse import urlencode

import psutil

ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / ".benchmark-cache/rust/unpacked/pocket-tts-3.3.0-x86_64-pc-windows-msvc/pocket-tts.exe"
PROMPT = ROOT / ".benchmark-cache/prompts/sloane_5s.wav"
MODELS = ("english_18m_refl_2026-10", "english_7m_refl_2026-10")
TEXT = "A longer passage helps reveal whether a voice stays clear and steady over time. The listener should be able to follow each sentence without missing words or hearing repeated phrases. This test also gives us a useful measure of how quickly the computer can produce speech compared with the length of the finished audio."
OUT = ROOT / "results/audio"


def sample_loop(pid: int, stop: threading.Event, stats: dict[str, int]) -> None:
    try:
        proc = psutil.Process(pid)
    except psutil.Error:
        return
    while not stop.is_set():
        try:
            mi = proc.memory_info()
            full = proc.memory_full_info()
            stats["peak_rss"] = max(stats.get("peak_rss", 0), mi.rss)
            stats["peak_private"] = max(stats.get("peak_private", 0), getattr(full, "private", 0))
        except psutil.Error:
            pass
        stop.wait(0.01)


def post_speech(port: int, model: str, index: int) -> dict[str, object]:
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=60)
    body = urlencode({"text": TEXT})
    start = time.perf_counter()
    conn.request("POST", "/tts", body=body,
                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    response = conn.getresponse()
    first = response.read(4096)
    first_byte = time.perf_counter() - start
    chunks = [first]
    while True:
        chunk = response.read(65536)
        if not chunk:
            break
        chunks.append(chunk)
    elapsed = time.perf_counter() - start
    payload = b"".join(chunks)
    conn.close()
    if response.status != 200:
        raise RuntimeError(f"{model}: HTTP {response.status}: {payload[:500]!r}")
    path = OUT / f"persistent_{model}_{index}.wav"
    path.write_bytes(payload)
    return {"request": index, "first_chunk_seconds": first_byte,
            "total_seconds": elapsed, "bytes": len(payload), "wav": str(path)}


def run(model: str, idle_seconds: float) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    env = os.environ.copy()
    env["HF_HUB_CACHE"] = str(ROOT / ".benchmark-cache/hf")
    env["HF_HUB_OFFLINE"] = "1"
    log = OUT / f"persistent_{model}.log"
    with log.open("w", encoding="utf-8") as log_handle:
        start = time.perf_counter()
        proc = subprocess.Popen(
            [str(EXE), "serve", "--host", "127.0.0.1", "--port", str(port),
             "--language", model, "--default-voice", str(PROMPT)],
            cwd=ROOT, env=env, stdout=log_handle, stderr=subprocess.STDOUT,
        )
        stats: dict[str, int] = {}
        stop = threading.Event()
        sampler = threading.Thread(target=sample_loop, args=(proc.pid, stop, stats), daemon=True)
        sampler.start()
        process = psutil.Process(proc.pid)
        ready = False
        deadline = time.perf_counter() + 120
        while time.perf_counter() < deadline:
            if proc.poll() is not None:
                raise RuntimeError(f"server exited early; inspect {log}")
            try:
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
                conn.request("GET", "/health")
                resp = conn.getresponse()
                okay = resp.status == 200
                resp.read()
                conn.close()
                if okay:
                    ready = True
                    break
            except OSError:
                time.sleep(0.1)
        if not ready:
            proc.terminate()
            raise TimeoutError(f"server not ready; inspect {log}")
        ready_seconds = time.perf_counter() - start
        idle: dict[str, int] = {}
        for _ in range(max(1, int(idle_seconds * 10))):
            try:
                mi, full = process.memory_info(), process.memory_full_info()
                idle["rss"] = mi.rss
                idle["private"] = getattr(full, "private", 0)
            except psutil.Error:
                break
            time.sleep(0.1)
        requests = [post_speech(port, model, 1), post_speech(port, model, 2)]
        try:
            mi, full = process.memory_info(), process.memory_full_info()
            after = {"rss": mi.rss, "private": getattr(full, "private", 0)}
        except psutil.Error:
            after = {}
        stop.set()
        sampler.join(timeout=1)
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)
        print(json.dumps({"model": model, "server_ready_seconds": ready_seconds,
                          "idle_seconds": idle_seconds, "idle": idle,
                          "after_warm_speech": after, "peak_rss": stats.get("peak_rss"),
                          "peak_private": stats.get("peak_private"), "requests": requests,
                          "log": str(log)},), flush=True)


if __name__ == "__main__":
    for name in MODELS:
        run(name, 10)
