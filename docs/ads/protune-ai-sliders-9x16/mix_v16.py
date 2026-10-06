#!/usr/bin/env python3
"""v16 audio: all four VO lines in "Curt - Midwestern Storyteller" over the music bed (ducked) with whooshes, -14 LUFS.
Same picture and timing as v15. v13's title-card SFX weren't kept: its demucs no-vocals stem is about -60 dB, so there's nothing to keep."""
import subprocess, sys
from pathlib import Path
D = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
DUR = 9.04
VO = [("l1_trim.wav", 0.05), ("l2_trim.wav", 2.78), ("l3_trim.wav", 4.37), ("l4_trim.wav", 6.50)]
WHOOSH_AT = [0.90, 4.15, 6.30]   # before the cuts at 1.04 (girl), 4.29 (food), ~6.45 (end card)
def run(*a): subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *a], check=True)

inp, fl = [], []
for i, (f, t) in enumerate(VO):
    inp += ["-i", str(D / f)]; ms = int(t * 1000)
    fl.append(f"[{i}:a]aresample=44100,adelay={ms}|{ms},apad[v{i}]")
fl.append("".join(f"[v{i}]" for i in range(len(VO))) + f"amix=inputs={len(VO)}:normalize=0,atrim=0:{DUR},loudnorm=I=-15:TP=-2:LRA=7[vo]")
run(*inp, "-filter_complex", ";".join(fl), "-map", "[vo]", "-ac", "1", "-ar", "44100", str(D / "vo_track.wav"))

n = len(WHOOSH_AT)
fc = (f"[1:a]atrim=0:{DUR},aresample=44100,volume=-10dB,afade=t=in:d=0.12,afade=t=out:st={DUR-0.55}:d=0.55[m];"
      f"[2:a]aresample=44100,volume=-7dB,asplit={n}" + "".join(f"[w{i}]" for i in range(n)) + ";"
      + ";".join(f"[w{i}]adelay={int(t*1000)}|{int(t*1000)},apad[wd{i}]" for i, t in enumerate(WHOOSH_AT)) + ";"
      + "".join(f"[wd{i}]" for i in range(n)) + f"amix=inputs={n}:normalize=0,atrim=0:{DUR}[sfx];"
      "[0:a]asplit=2[vo][sc];"
      "[m][sc]sidechaincompress=threshold=0.015:ratio=10:attack=12:release=300:makeup=1[md];"
      "[vo]pan=stereo|c0=c0|c1=c0[vos];"
      f"[md][sfx][vos]amix=inputs=3:normalize=0,atrim=0:{DUR}[mix]")
run("-i", str(D / "vo_track.wav"), "-i", str(D / "music_bed.mp3"), "-i", str(D / "whoosh.mp3"),
    "-filter_complex", fc, "-map", "[mix]", "-ar", "44100", "-ac", "2", str(D / "premix.wav"))

def measure(p):
    t = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(p), "-af", "ebur128=peak=true", "-f", "null", "-"],
                       capture_output=True, text=True).stderr
    return float(t.split("Integrated loudness:")[1].split("I:")[1].split("LUFS")[0])
g = -14.0 - measure(D / "premix.wav")
for _ in range(3):
    run("-i", str(D / "premix.wav"), "-af",
        f"volume={g:.2f}dB,alimiter=limit=0.84:attack=1:release=40:level=disabled,aresample=44100", str(D / "final_audio.wav"))
    err = -14.0 - measure(D / "final_audio.wav")
    if abs(err) < 0.1: break
    g += err
print(f"ok gain {g:+.2f} dB")
