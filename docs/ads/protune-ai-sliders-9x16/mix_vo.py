#!/usr/bin/env python3
"""Build the v14 audio: ElevenLabs VO lines (Liam) + generated music bed (ducked) + whooshes, -14 LUFS."""
import json, subprocess, sys
from pathlib import Path
D = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
DUR = 13.79
VO = [("l1_trim.wav", 0.05), ("l2_trim.wav", 1.92), ("l3_trim.wav", 3.20),
      ("l4_trim.wav", 6.20), ("l5_trim.wav", 9.15), ("l6_trim.wav", 11.35)]
WHOOSH_AT = [0.90, 2.90, 8.90, 11.02]          # just ahead of the cuts at 1.04 / 3.04 / 9.04 / ~11.2
def run(*a): subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *a], check=True)

inp, fl = [], []
for i, (f, t) in enumerate(VO):
    inp += ["-i", str(D / f)]; ms = int(t * 1000)
    fl.append(f"[{i}:a]aresample=44100,adelay={ms}|{ms},apad[v{i}]")
fl.append("".join(f"[v{i}]" for i in range(len(VO))) + f"amix=inputs={len(VO)}:normalize=0,atrim=0:{DUR},loudnorm=I=-15:TP=-2:LRA=7[vo]")
run(*inp, "-filter_complex", ";".join(fl), "-map", "[vo]", "-ac", "1", "-ar", "44100", str(D / "vo_track.wav"))

n = len(WHOOSH_AT)
wh = "".join(f"[w{i}]" for i in range(n))
fc = (f"[1:a]atrim=0:{DUR},aresample=44100,volume=-10dB,afade=t=in:d=0.12,afade=t=out:st={DUR-0.6}:d=0.6[m];"
      f"[2:a]aresample=44100,volume=-7dB,asplit={n}" + wh + ";"
      + ";".join(f"[w{i}]adelay={int(t*1000)}|{int(t*1000)},apad[wd{i}]" for i, t in enumerate(WHOOSH_AT)) + ";"
      + "".join(f"[wd{i}]" for i in range(n)) + f"amix=inputs={n}:normalize=0,atrim=0:{DUR}[sfx];"
      "[0:a]asplit=2[vo][sc];"
      "[m][sc]sidechaincompress=threshold=0.015:ratio=10:attack=12:release=300:makeup=1[md];"
      "[vo]pan=stereo|c0=c0|c1=c0[vos];"
      f"[md][sfx][vos]amix=inputs=3:normalize=0,atrim=0:{DUR}[mix]")
run("-i", str(D / "vo_track.wav"), "-i", str(D / "music_bed.mp3"), "-i", str(D / "whoosh.mp3"),
    "-filter_complex", fc, "-map", "[mix]", "-ar", "44100", str(D / "premix.wav"))
t = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(D / "premix.wav"), "-af",
                    "loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json", "-f", "null", "-"],
                   capture_output=True, text=True).stderr
s = t.rfind("{"); j = json.loads(t[s:t.find("}", s) + 1])
run("-i", str(D / "premix.wav"), "-af",
    f"loudnorm=I=-14:TP=-1.5:LRA=11:measured_I={j['input_i']}:measured_TP={j['input_tp']}:measured_LRA={j['input_lra']}"
    f":measured_thresh={j['input_thresh']}:offset={j['target_offset']}:linear=true,aresample=44100",
    str(D / "final_audio.wav"))
print("ok")
