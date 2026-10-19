#!/usr/bin/env python3
"""v19 sound: voiceover (tts.py, Kokoro) + UI sound effects + soft pad, mastered to -14 LUFS,
muxed onto a silent render from render.py.

Usage: python3 audio.py --video in.mp4 --out out.mp4 --models DIR --espeak DIR --vocab config.json \
          [--voice af_heart]
"""
from __future__ import annotations
import argparse, json, subprocess, sys, tempfile
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
import tts

SR = tts.SR
DUR = 12.0

# (start s, text, speed) - copy is the brief's exact lines; the last line repeats the end card
VO = [
    (0.15, "Your selfies are one tap from stunning.", 1.15),
    (2.9, "Watch AI edit your photos like a pro.", 1.2),
    (9.2, "ProTune AI Camera. Free on the App Store.", 1.18),
]
T_TAP, T_REVEAL, T_SPLIT, T_END = 2.7, 5.0, 7.0, 9.0

def env(n, a=0.005, r=0.08):
    t = np.arange(n) / SR
    return np.minimum(1, t / a) * np.exp(-t / r)

def click(f=2400, dur=0.06, gain=0.35):
    n = int(dur * SR); t = np.arange(n) / SR
    return gain * env(n, 0.001, 0.012) * (np.sin(2 * np.pi * f * t) + 0.4 * np.random.default_rng(1).standard_normal(n))

def whoosh(dur=0.9, gain=0.22):
    n = int(dur * SR); rng = np.random.default_rng(2)
    noise = rng.standard_normal(n)
    # sweep a one-pole lowpass upward
    out = np.zeros(n); y = 0.0
    for i in range(n):
        k = 0.02 + 0.25 * (i / n); y += k * (noise[i] - y); out[i] = y
    shape = np.sin(np.pi * np.arange(n) / n) ** 2
    return gain * out * shape / (np.abs(out).max() + 1e-9)

def chime(gain=0.18):
    n = int(1.6 * SR); t = np.arange(n) / SR
    s = sum(np.sin(2 * np.pi * f * t) * w for f, w in ((880, 1), (1320, 0.5), (1760, 0.25)))
    return gain * s * env(n, 0.004, 0.5)

def pad(gain=0.05):
    n = int(DUR * SR); t = np.arange(n) / SR
    chords = [(0, (220.0, 277.18, 329.63)), (T_REVEAL, (246.94, 311.13, 369.99)), (T_END, (220.0, 277.18, 329.63, 440.0))]
    out = np.zeros(n)
    for i, (t0, fs) in enumerate(chords):
        t1 = chords[i + 1][0] if i + 1 < len(chords) else DUR
        a, b = int(t0 * SR), int(t1 * SR)
        seg = sum(np.sin(2 * np.pi * f * t[a:b]) + 0.3 * np.sin(4 * np.pi * f * t[a:b]) for f in fs) / len(fs)
        fade = np.minimum(1, np.minimum(np.arange(b - a), (b - a) - np.arange(b - a)) / (0.4 * SR))
        out[a:b] += seg * fade
    fin = np.minimum(1, t / 1.0) * np.minimum(1, (DUR - t) / 0.6)
    return gain * out * fin

def place(bus, clip, t):
    a = int(t * SR); b = min(len(bus), a + len(clip)); bus[a:b] += clip[: b - a]

def main():
    ap = argparse.ArgumentParser()
    for k in ("video", "out", "models", "espeak", "vocab"): ap.add_argument("--" + k, required=True)
    ap.add_argument("--voice", default="af_heart")
    a = ap.parse_args()
    vocab = json.loads(Path(a.vocab).read_text())["vocab"]
    es = tts.Espeak(Path(a.espeak))
    n = int(DUR * SR)
    vo = np.zeros(n); fx = np.zeros(n)
    duck = np.ones(n)
    for t0, text, sp in VO:
        ph, clip = tts.synth(text, a.voice, sp, Path(a.models), es, vocab)
        nz = np.flatnonzero(np.abs(clip) > 0.01 * np.abs(clip).max())
        clip = clip[max(0, nz[0] - 240): nz[-1] + 1200]          # trim model silence
        clip = clip / (np.abs(clip).max() + 1e-9) * 0.9
        place(vo, clip, t0)
        s, e = int(t0 * SR), int((t0 + len(clip) / SR) * SR)
        duck[max(0, s - 2400):min(n, e + 4800)] = 0.45
        print(f"{t0:5.2f}-{t0 + len(clip) / SR:5.2f}  {text}  [{ph}]")
    duck = np.convolve(duck, np.ones(2400) / 2400, mode="same")
    place(fx, click(), T_TAP)
    place(fx, whoosh(), T_REVEAL - 0.15)
    place(fx, click(1800, gain=0.2), T_SPLIT)
    place(fx, chime(), T_END + 0.1)
    mix = vo + (fx + pad()) * duck
    with tempfile.TemporaryDirectory() as td:
        wav = Path(td) / "mix.wav"; tts.write_wav(wav, mix / (np.abs(mix).max() + 1e-9) * 0.8)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", a.video, "-i", str(wav),
                        "-filter_complex", "[1:a]aresample=48000,loudnorm=I=-15:TP=-1.5:LRA=11,aresample=48000,pan=stereo|c0=c0|c1=c0[a]",
                        "-map", "0:v", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
                        "-shortest", "-movflags", "+faststart", a.out], check=True)

if __name__ == "__main__":
    main()
