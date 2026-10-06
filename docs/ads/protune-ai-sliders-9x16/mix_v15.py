#!/usr/bin/env python3
"""v15 audio. 0-2.62 s is v13's original audio, untouched ("One tap and AI edits your photos like a pro.").
After that come ElevenLabs "Roger" VO lines (the closest timbre match to v13's voice), the music bed fading in at the seam
and ducked under the VO, and whooshes before the cuts. The selfie/Optimize scene was removed, so v13's "Tap. Optimize." is dropped, and the girl scene is cut to 3.25 s.
Program loudness is -14 LUFS."""
import json, subprocess, sys
from pathlib import Path
D = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
V13 = sys.argv[2] if len(sys.argv) > 2 else "v13_44k.wav"
DUR = 9.04; SEAM = 2.62
VO = [("l4_trim.wav", 2.78), ("l5_trim.wav", 4.37), ("l6_trim.wav", 6.55)]   # Foggy to golden / Food... / CTA
WHOOSH_AT = [4.15, 6.30]   # before the cuts at 4.29 (food) and ~6.45 (end card)
def run(*a): subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *a], check=True)

# new VO lines, levelled to the original VO's loudness (-16 LUFS for v13's opening)
inp, fl = [], []
for i, (f, t) in enumerate(VO):
    inp += ["-i", str(D / f)]; ms = int(t * 1000)
    fl.append(f"[{i}:a]aresample=44100,adelay={ms}|{ms},apad[v{i}]")
fl.append("".join(f"[v{i}]" for i in range(len(VO))) + f"amix=inputs={len(VO)}:normalize=0,atrim=0:{DUR},loudnorm=I=-16:TP=-2:LRA=7[vo]")
run(*inp, "-filter_complex", ";".join(fl), "-map", "[vo]", "-ac", "1", "-ar", "44100", str(D / "vo_new.wav"))

n = len(WHOOSH_AT)
fc = (f"[0:a]atrim=0:{SEAM},afade=t=out:st={SEAM-0.03}:d=0.03,apad,atrim=0:{DUR}[orig];"      # v13 opening, verbatim
      f"[2:a]atrim=0:{DUR - SEAM + 0.2},aresample=44100,volume=-10dB,afade=t=in:d=0.35,afade=t=out:st={DUR-SEAM-0.55}:d=0.55,"
      f"adelay={int(SEAM*1000)}|{int(SEAM*1000)},apad,atrim=0:{DUR}[m];"
      f"[3:a]aresample=44100,volume=-7dB,asplit={n}" + "".join(f"[w{i}]" for i in range(n)) + ";"
      + ";".join(f"[w{i}]adelay={int(t*1000)}|{int(t*1000)},apad[wd{i}]" for i, t in enumerate(WHOOSH_AT)) + ";"
      + "".join(f"[wd{i}]" for i in range(n)) + f"amix=inputs={n}:normalize=0,atrim=0:{DUR}[sfx];"
      "[1:a]asplit=2[vo][sc];"
      "[m][sc]sidechaincompress=threshold=0.015:ratio=10:attack=12:release=300:makeup=1[md];"
      "[vo]pan=stereo|c0=c0|c1=c0[vos];"
      f"[orig][md][sfx][vos]amix=inputs=4:normalize=0,atrim=0:{DUR}[mix]")
run("-i", V13, "-i", str(D / "vo_new.wav"), "-i", str(D / "music_bed.mp3"), "-i", str(D / "whoosh.mp3"),
    "-filter_complex", fc, "-map", "[mix]", "-ar", "44100", "-ac", "2", str(D / "premix.wav"))
# master: one static gain to -14 LUFS, then a brickwall limiter (catches only v13's opening transients)
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
j = {"normalization_type": f"static gain {g:+.2f} dB + limiter"}
print("ok", j["normalization_type"])
