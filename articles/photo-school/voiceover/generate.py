#!/usr/bin/env python3
"""Photo School voiceover: narration.json -> narration.mp3 (one track, chapter-aligned) + transcript.html.

Runs where the ElevenLabs key lives (the grepawk.com server). The key is read from $ELEVENLABS_API_KEY, or from
the ELEVENLABS_API_KEY line of $ELEVENLABS_ENV_FILE (default /etc/photo-recipes.env). It is never printed or written.

  scp narration.json generate.py root@64.23.239.208:/tmp/pse-vo/ && ssh root@64.23.239.208 'cd /tmp/pse-vo && python3 generate.py'
  scp root@64.23.239.208:/tmp/pse-vo/out/{narration.mp3,transcript.html,report.json} articles/photo-school/

Each chapter clip starts leadIn seconds into its chapter and is padded with silence to the chapter's exact
duration, so audio time == animation time (the player seeks audio.currentTime to the animation clock).
The joined track is loudness-normalized to -16 LUFS (two-pass ffmpeg loudnorm), mono MP3.
"""
import html, json, os, subprocess, sys, urllib.request, urllib.error

here = os.path.dirname(os.path.abspath(__file__))
cfg = json.load(open(os.path.join(here, 'narration.json')))
out = os.path.join(here, 'out'); os.makedirs(out, exist_ok=True)

def api_key():
    k = os.environ.get('ELEVENLABS_API_KEY')
    if k: return k.strip()
    for line in open(os.environ.get('ELEVENLABS_ENV_FILE', '/etc/photo-recipes.env')):
        line = line.strip()
        if line.startswith('ELEVENLABS_API_KEY='):
            return line.split('=', 1)[1].strip().strip('"').strip("'")
    sys.exit('ELEVENLABS_API_KEY not found')

def run(*a):
    return subprocess.run(a, check=True, capture_output=True, text=True)

def dur(p):
    return float(run('ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', p).stdout.strip())

key = api_key()
chars = 0
clips = []
prev_ids = []
for i, ch in enumerate(cfg['chapters']):
    raw = os.path.join(out, f'ch{i+1:02d}.mp3')
    stamp = os.path.join(out, f'ch{i+1:02d}.json')
    want = json.dumps({'text': ch['text'], 'speed': ch.get('speed', 1.0), 'voice': cfg['voice']['id'], 'model': cfg['model']})
    cached = os.path.exists(raw) and os.path.exists(stamp) and open(stamp).read() == want
    body = {
        'text': ch['text'], 'model_id': cfg['model'],
        'voice_settings': {'stability': 0.5, 'similarity_boost': 0.75, 'style': 0.15, 'use_speaker_boost': True, 'speed': ch.get('speed', 1.0)},
        'previous_text': cfg['chapters'][i-1]['text'] if i else None,
        'next_text': cfg['chapters'][i+1]['text'] if i + 1 < len(cfg['chapters']) else None,
    }
    req = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{cfg['voice']['id']}?output_format=mp3_44100_128",
        data=json.dumps(body).encode(), method='POST',
        headers={'xi-api-key': key, 'Content-Type': 'application/json', 'Accept': 'audio/mpeg'})
    if not cached:  # unchanged chapters keep their previous take (and cost nothing)
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                open(raw, 'wb').write(r.read())
                chars += int(r.headers.get('character-cost') or len(ch['text']))
            open(stamp, 'w').write(want)
        except urllib.error.HTTPError as e:
            sys.exit(f'chapter {i+1}: HTTP {e.code} {e.read()[:300]!r}')
    trimmed = os.path.join(out, f'ch{i+1:02d}-trim.wav')
    sil = 'silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.05'
    run('ffmpeg', '-y', '-v', 'error', '-i', raw, '-af', f'{sil},areverse,{sil},areverse', '-ar', '44100', '-ac', '1', trimmed)
    d = dur(trimmed)
    room = ch['duration'] - cfg['leadIn'] - 0.15
    clips.append({'chapter': i + 1, 'title': ch['title'], 'speech': round(d, 2), 'room': round(room, 2), 'fits': d <= room})
    print(f"ch{i+1:02d} {d:5.2f}s / room {room:4.2f}s {'ok' if d <= room else 'TOO LONG'}", flush=True)

# Build the chapter-aligned track: [leadIn silence][clip][silence to chapter duration] x N
parts = []
for i, ch in enumerate(cfg['chapters']):
    seg = os.path.join(out, f'seg{i+1:02d}.wav')
    run('ffmpeg', '-y', '-v', 'error', '-i', os.path.join(out, f'ch{i+1:02d}-trim.wav'),
        '-af', f"adelay={int(cfg['leadIn']*1000)}:all=1,apad,atrim=0:{ch['duration']}",
        '-ar', '44100', '-ac', '1', seg)
    parts.append(seg)
lst = os.path.join(out, 'list.txt')
open(lst, 'w').write(''.join(f"file '{p}'\n" for p in parts))
joined = os.path.join(out, 'joined.wav')
run('ffmpeg', '-y', '-v', 'error', '-f', 'concat', '-safe', '0', '-i', lst, '-c', 'copy', joined)
# two-pass loudnorm to -16 LUFS, true peak -1.5 dBTP
m = run('ffmpeg', '-hide_banner', '-i', joined, '-af', 'loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json', '-f', 'null', '-').stderr
meas = json.loads(m[m.rindex('{'):m.rindex('}') + 1])
af = (f"loudnorm=I=-16:TP=-1.5:LRA=11:measured_I={meas['input_i']}:measured_TP={meas['input_tp']}:"
      f"measured_LRA={meas['input_lra']}:measured_thresh={meas['input_thresh']}:offset={meas['target_offset']}:linear=true")
final = os.path.join(out, 'narration.mp3')
run('ffmpeg', '-y', '-v', 'error', '-i', joined, '-af', af + ',aresample=44100', '-ac', '1', '-c:a', 'libmp3lame', '-b:a', '64k', final)
def measure(p):
    e = run('ffmpeg', '-hide_banner', '-i', p, '-af', 'loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json', '-f', 'null', '-').stderr
    return json.loads(e[e.rindex('{'):e.rindex('}') + 1])
# loudnorm lands a little low on a track with long pauses: trim the residual with a plain gain step (peak-limited)
m1 = measure(final)
gain = min(-16 - float(m1['input_i']), -0.5 - float(m1['input_tp']))
if abs(gain) > 0.1:
    run('ffmpeg', '-y', '-v', 'error', '-i', joined, '-af', af + f',volume={gain:.2f}dB,aresample=44100', '-ac', '1', '-c:a', 'libmp3lame', '-b:a', '64k', final)
chk = run('ffmpeg', '-hide_banner', '-i', final, '-af', 'loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json', '-f', 'null', '-').stderr
chk = json.loads(chk[chk.rindex('{'):chk.rindex('}') + 1])

# Transcript (accessible + crawlable), included by article.html
t, rows = 0, []
for ch in cfg['chapters']:
    rows.append(f'<li><span class="ts">{int(t)//60}:{int(t)%60:02d}</span> <strong>{html.escape(ch["title"])}.</strong> {html.escape(ch["text"])}</li>')
    t += ch['duration']
open(os.path.join(out, 'transcript.html'), 'w').write(
    '<!-- GENERATED by voiceover/generate.py from voiceover/narration.json -->\n'
    '<details class="transcript" id="pse-transcript"><summary>Narration transcript</summary>\n<ol>\n' + '\n'.join(rows) + '\n</ol>\n</details>\n')
report = {'voice': cfg['voice'], 'model': cfg['model'], 'characters_this_run': chars, 'duration': round(dur(final), 2),
          'bytes': os.path.getsize(final), 'loudness_after': {k: chk[k] for k in ('input_i', 'input_tp', 'input_lra')}, 'clips': clips}
json.dump(report, open(os.path.join(out, 'report.json'), 'w'), indent=2)
print(json.dumps(report, indent=2))
