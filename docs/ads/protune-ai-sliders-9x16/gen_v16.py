#!/usr/bin/env python3
"""v16 VO: all four lines in ElevenLabs shared voice "Curt - Midwestern Storyteller" (hU1ratPhBTZNviWitzAh)."""
import json, os, subprocess, sys, urllib.request
key = os.environ["ELEVENLABS_API_KEY"]; VOICE = "hU1ratPhBTZNviWitzAh"
speed = float(sys.argv[1]) if len(sys.argv) > 1 else 1.15
only = sys.argv[2:]  # optional subset of line ids
lines = json.load(open("lines.json"))
for i, (n, txt, a, b) in enumerate(lines):
    if only and n not in only: continue
    body = {"text": txt, "model_id": "eleven_multilingual_v2",
            "voice_settings": {"stability": 0.35, "similarity_boost": 0.8, "style": 0.6, "use_speaker_boost": True, "speed": speed},
            "previous_text": lines[i-1][1] if i else None, "next_text": lines[i+1][1] if i + 1 < len(lines) else None}
    req = urllib.request.Request(f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE}?output_format=mp3_44100_128",
                                 data=json.dumps(body).encode(), headers={"xi-api-key": key, "Content-Type": "application/json"})
    open(f"{n}.mp3", "wb").write(urllib.request.urlopen(req).read())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", f"{n}.mp3", "-af",
                    "silenceremove=start_periods=1:start_threshold=-45dB,areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse",
                    "-ar", "44100", "-ac", "1", f"{n}_trim.wav"], check=True)
    d = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", f"{n}_trim.wav"],
                             capture_output=True, text=True).stdout)
    print(n, f"{d:.2f}s window {b-a:.2f}s ratio {d/(b-a):.2f}", txt)
