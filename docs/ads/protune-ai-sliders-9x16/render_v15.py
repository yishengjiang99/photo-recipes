#!/usr/bin/env python3
"""ProTune selfie reel v15: v13 title card -> FAST girl-portrait optimize scene -> v13 food/landscape + end card.

v15 edit list (frame numbers are v13's, 24 fps):
  keep 0-24      title card (1.04 s)
  drop 25-72     phone-in-hand selfie / Optimize-tap scene (user: "we don't need this scene")
  NEW  78 frames girl slider scene (3.25 s): Exposure/Contrast reach final values by 2.3 s (ease-out), then hold
  drop 73-216    v13 city "AI Processing..." scene (replaced by the scene above)
  keep 217-330   "ProTune sees this" food/landscape + end card
Result: 217 frames = 9.04 s. Audio is built separately by mix_v15.py.

(History) v14: swap the city "AI Processing..." scene for the CC0 portrait.

Takes docs/ads/protune-selfie-reels-v13.mp4 (720x1280, 24 fps, AAC). The 3.0417-9.0417 s scene
(frames 73-216, 144 frames = 6.0 s) is the AI-generated take of the 6-slider brief, but it has a foggy
city street where the young woman should be. This script redraws that scene in the same look (deep purple
UI, spinner + AI badge header, Before/After toggle, magenta-to-violet slider tracks with value boxes)
with the girl portrait on the left. Every other frame is passed through, and the original audio is
stream-copied, so VO and music timing don't change.

Spec held exactly: 6 unique labels (Exposure, Contrast, Saturation, Sharpness, Color Balance, HDR Boost);
only Exposure (-1.0 -> +0.8) and Contrast (-0.8 -> +0.6) move; the others stay at 0.0; "AI Processing..."
at top; the portrait grades from foggy/dull/cool to vibrant/warm.

Photo: "Brunette woman portrait (Unsplash).jpg" by Christopher Campbell, CC0 1.0, via Wikimedia Commons.
Audio: this script writes the picture and stream-copies v13's audio. The shipped v14 audio comes from
mix_vo.py (new ElevenLabs VO, ducked music bed, whooshes, -14 LUFS), muxed afterwards:
  ffmpeg -i out.mp4 -i final_audio.wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 192k out_final.mp4
Usage: python3 render_v13_cut.py <v13.mp4> <out.mp4>
"""
from __future__ import annotations
import hashlib, math, subprocess, sys, urllib.request
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
SRC_VIDEO = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parent / "protune-selfie-reels-v13.mp4"
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else HERE.parent / "protune-selfie-reels-v15-girl.video.mp4"
SRC_URL = "https://upload.wikimedia.org/wikipedia/commons/1/16/Brunette_woman_portrait_%28Unsplash%29.jpg"
SRC_SHA1 = "29612991a226c0f9dbdd33be0b8014ee4f00629c"
PHOTO_SRC = HERE / "portrait_src.jpg"

OW, OH, FPS = 720, 1280, 24          # v13 output geometry
KEEP_HEAD = 25                       # v13 frames [0, 25): title card
CUT_OUT = 217                        # v13 frames [25, 217) dropped; [217, end) kept
N = 78                               # new girl scene: 3.25 s
OPT_START, OPT_END = 0.15, 2.30      # optimize animation window (scene time, s)
W, H = 1080, 1920                    # draw at 1.5x, downsample to 720x1280
SS = 2

FONT_DIRS = [HERE / "fonts", HERE.parent.parent / "asc" / "screenshots" / "en-US" / "fonts"]
_fc = {}
def font(name, size):
    k = (name, size)
    if k not in _fc:
        for d in FONT_DIRS:
            if (d / name).exists():
                _fc[k] = ImageFont.truetype(str(d / name), size); break
        else:
            raise FileNotFoundError(name)
    return _fc[k]
SEMI, BOLD, XB = "Inter-SemiBold.ttf", "Inter-Bold.ttf", "Inter-ExtraBold.ttf"

# palette sampled from v13's city scene
SCREEN_TOP, SCREEN_BOT = (42, 30, 66), (30, 25, 44)
PANEL = (40, 34, 48); LEFT_BOX = (50, 36, 82); TOGGLE_BG = (63, 40, 119); TOGGLE_ON = (72, 29, 194)
TRACK_OFF = (69, 58, 94); MAGENTA = (194, 36, 238); VIOLET = (92, 37, 229); THUMB = (150, 70, 240)
VALBOX = (47, 46, 66); INK = (246, 244, 252); INK2 = (205, 198, 225); LAV = (199, 165, 255)
BEZEL = (24, 20, 20)

SLIDERS = [("Exposure", -1.0, 0.8), ("Contrast", -0.8, 0.6), ("Saturation", 0.0, 0.0),
           ("Sharpness", 0.0, 0.0), ("Color Balance", 0.0, 0.0), ("HDR Boost", 0.0, 0.0)]
assert len({s[0] for s in SLIDERS}) == 6
VMIN, VMAX = -2.0, 2.0

# layout (1080x1920 space, mirrors v13 city scene x1.5)
SCR_X0, SCR_X1 = 14, 1046                    # phone screen inside thin bezels
LEFT = (26, 168, 632, 1920 + 40)             # left container (runs off bottom like v13)
PHOTO = (34, 300, 624, 1884)
RIGHT = (644, 168, 1034, 1920 + 40)
ROW0, PITCH = 330, 262

def ease(x):
    x = min(max(x, 0.0), 1.0); return x * x * x * (x * (x * 6 - 15) + 10)
def progress(f):
    x = min(max((f / FPS - OPT_START) / (OPT_END - OPT_START), 0.0), 1.0)
    return 1 - (1 - x) ** 3            # snappy ease-out: most of the change lands in the first second
def fmt(v):
    r = round(v + 0.0, 1); return "0.0" if abs(r) < 0.05 else f"{r:+.1f}"

def rr_mask(w, h, r, k=4):
    m = Image.new("L", (w * k, h * k), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w * k - 1, h * k - 1), r * k, fill=255)
    return m.resize((w, h), Image.LANCZOS)

# ---------------- photo + grade ----------------
PW, PH = PHOTO[2] - PHOTO[0], PHOTO[3] - PHOTO[1]
def load_photo():
    if not PHOTO_SRC.exists():
        req = urllib.request.Request(SRC_URL, headers={"User-Agent": "ProTuneRender/1.0"})
        PHOTO_SRC.write_bytes(urllib.request.urlopen(req).read())
    assert hashlib.sha1(PHOTO_SRC.read_bytes()).hexdigest() == SRC_SHA1
    im = Image.open(PHOTO_SRC).convert("RGB")
    cw = round(im.height * PW / PH); cx = 2690
    im = im.crop((cx - cw // 2, 0, cx - cw // 2 + cw, im.height)).resize((PW, PH), Image.LANCZOS)
    return np.asarray(im).astype(np.float32) / 255.0

_yy, _xx = np.mgrid[0:PH, 0:PW].astype(np.float32)
_u, _v = _xx / PW, _yy / PH
WARM_GLOW = np.clip(1.0 - np.sqrt(((_u - 0.95) * 1.1) ** 2 + ((_v - 0.06) * 0.85) ** 2) / 0.95, 0, 1) ** 1.6
VIGNETTE = np.clip(1.0 - (((_u - 0.5) * 1.25) ** 2 + ((_v - 0.42) * 0.95) ** 2), 0, 1) ** 0.5
LUMA = np.array([0.2126, 0.7152, 0.0722], np.float32)

def grade(img, p, exposure, contrast):
    x = img * (2.0 ** (exposure * 0.30))
    x = np.where(x > 0.75, 0.75 + 0.25 * np.tanh((x - 0.75) / 0.25), x)
    x = (x - 0.42) * (1.0 + contrast * 0.38) + 0.42
    haze = (0.22 + 0.06 * (1 - _v[..., None])) * (1 - p)          # fog veil, like v13's "before"
    x = x * (1 - haze) + haze * 0.66
    cool = np.array([0.92, 0.98, 1.09], np.float32); warm = np.array([1.05, 1.0, 0.90], np.float32)
    x = x * (cool * (1 - p) + warm * p)
    sat = 0.36 + 0.79 * p
    y = (x @ LUMA)[..., None]; x = y + (x - y) * sat
    g = (WARM_GLOW * (0.30 * p))[..., None]
    x = 1 - (1 - np.clip(x, 0, 1)) * (1 - g * np.array([1.0, 0.74, 0.42], np.float32))
    lum = (x @ LUMA)[..., None]
    x = x + p * ((1 - lum) ** 2 * np.array([-0.025, 0.006, 0.03], np.float32)
                 + lum ** 2 * np.array([0.03, 0.008, -0.03], np.float32))
    x = x * (1 - (1 - VIGNETTE[..., None]) * 0.38 * p)
    return np.clip(x, 0, 1)

# ---------------- icons ----------------
def icon(d, kind, cx, cy, s):
    c = INK
    if kind == "sun":
        d.ellipse((cx - 9 * s, cy - 9 * s, cx + 9 * s, cy + 9 * s), outline=c, width=3 * s)
        for i in range(8):
            a = i * math.pi / 4
            d.line((cx + 14 * s * math.cos(a), cy + 14 * s * math.sin(a), cx + 20 * s * math.cos(a), cy + 20 * s * math.sin(a)), fill=c, width=3 * s)
    elif kind == "pct":
        d.text((cx, cy), "%", font=font(BOLD, 40 * s), fill=c, anchor="mm")
    elif kind == "drop":
        d.ellipse((cx - 11 * s, cy - 2 * s, cx + 11 * s, cy + 20 * s), fill=LAV)
        d.polygon([(cx, cy - 20 * s), (cx - 10 * s, cy + 4 * s), (cx + 10 * s, cy + 4 * s)], fill=LAV)
    elif kind == "sharp":
        for dx, dy in [(0, -1), (0, 1), (-1, 0), (1, 0)]:
            d.line((cx + dx * 6 * s, cy + dy * 6 * s, cx + dx * 18 * s, cy + dy * 18 * s), fill=c, width=3 * s)
        d.line((cx + 9 * s, cy - 15 * s, cx + 19 * s, cy - 5 * s), fill=c, width=3 * s)
    elif kind == "wheel":
        cols = [(255, 69, 58), (255, 159, 10), (255, 214, 10), (48, 209, 88), (100, 210, 255), (94, 92, 230), (191, 90, 242)]
        for i, col in enumerate(cols):
            d.pieslice((cx - 20 * s, cy - 20 * s, cx + 20 * s, cy + 20 * s), i * 360 / 7 - 90, (i + 1) * 360 / 7 - 90, fill=col)
        d.ellipse((cx - 9 * s, cy - 9 * s, cx + 9 * s, cy + 9 * s), fill=PANEL)
    elif kind == "hdr":
        d.rounded_rectangle((cx - 24 * s, cy - 16 * s, cx + 24 * s, cy + 16 * s), 6 * s, fill=(72, 52, 120))
        d.text((cx, cy), "HDR", font=font(XB, 17 * s), fill=INK, anchor="mm")
ICONS = ["sun", "pct", "drop", "sharp", "wheel", "hdr"]

# ---------------- static base ----------------
def build_base():
    s = SS
    yy = np.linspace(0, 1, H * s, dtype=np.float32)[:, None, None]
    bg = np.array(SCREEN_TOP, np.float32) * (1 - yy) + np.array(SCREEN_BOT, np.float32) * yy
    base = Image.fromarray(np.broadcast_to(bg, (H * s, W * s, 3)).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(base)
    # header: back arrow, (spinner drawn per frame), AI badge, title, overflow
    d.line((48 * s, 82 * s, 92 * s, 82 * s), fill=INK, width=6 * s)
    d.line((48 * s, 82 * s, 68 * s, 62 * s), fill=INK, width=6 * s)
    d.line((48 * s, 82 * s, 68 * s, 102 * s), fill=INK, width=6 * s)
    bx = 222
    bm = Image.new("L", (66 * s, 66 * s), 0); ImageDraw.Draw(bm).rounded_rectangle((0, 0, 66 * s - 1, 66 * s - 1), 14 * s, fill=255)
    gx = np.linspace(0, 1, 66 * s, dtype=np.float32)[None, :, None]
    badge = Image.fromarray((np.array((122, 72, 245), np.float32) * (1 - gx) + np.array((196, 70, 235), np.float32) * gx).repeat(66 * s, 0).astype(np.uint8))
    base.paste(badge, (bx * s, 50 * s), bm)
    d.text(((bx + 33) * s, 83 * s), "AI", font=font(BOLD, 34 * s), fill=INK, anchor="mm")
    d.text((306 * s, 83 * s), "AI Processing...", font=font(BOLD, 60 * s), fill=INK, anchor="lm")
    for i in range(3):
        d.ellipse(((968 + i * 16) * s, 80 * s, (976 + i * 16) * s, 88 * s), fill=INK)
    # containers
    d.rounded_rectangle(tuple(v * s for v in LEFT), 28 * s, fill=LEFT_BOX)
    d.rounded_rectangle(tuple(v * s for v in RIGHT), 28 * s, fill=PANEL)
    # eraser icon top-right of panel
    ex, ey = 990 * s, 214 * s
    d.polygon([(ex - 20 * s, ey + 8 * s), (ex + 4 * s, ey - 16 * s), (ex + 18 * s, ey - 2 * s), (ex - 6 * s, ey + 22 * s)], fill=(235, 232, 245))
    # toggle track
    d.rounded_rectangle((44 * s, 196 * s, 412 * s, 272 * s), 22 * s, fill=TOGGLE_BG)
    # photo shadow inside container
    sh = Image.new("L", base.size, 0)
    ImageDraw.Draw(sh).rounded_rectangle((PHOTO[0] * s, (PHOTO[1] + 8) * s, PHOTO[2] * s, (PHOTO[3] + 8) * s), 30 * s, fill=140)
    base.paste((10, 6, 18), (0, 0), sh.filter(ImageFilter.GaussianBlur(14 * s)))
    # slider labels / icons / static tracks are drawn per row (cheap) — rows built in row_img()
    base = base.resize((W, H), Image.LANCZOS)
    # bezels (phone edge visible at frame sides, like v13)
    bd = ImageDraw.Draw(base)
    bd.rectangle((0, 0, SCR_X0 - 1, H), fill=BEZEL); bd.rectangle((SCR_X1, 0, W, H), fill=BEZEL)
    return base

def toggle(after_amt: float) -> Image.Image:
    """Before/After segmented control; highlight slides to After."""
    s = SS; w, h = 368, 76
    im = Image.new("RGBA", (w * s, h * s), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    seg = (w - 12) / 2
    x0 = 6 + after_amt * seg
    d.rounded_rectangle((x0 * s, 6 * s, (x0 + seg) * s, (h - 6) * s), 18 * s, fill=TOGGLE_ON + (255,))
    f = font(BOLD, 34 * s)
    d.text(((6 + seg / 2) * s, h / 2 * s), "Before", font=f, anchor="mm", fill=INK if after_amt < 0.5 else INK2)
    d.text(((6 + seg * 1.5) * s, h / 2 * s), "After", font=f, anchor="mm", fill=INK if after_amt >= 0.5 else INK2)
    return im.resize((w, h), Image.LANCZOS)

def spinner(t: float) -> Image.Image:
    s = 3; R = 26; sz = 72
    im = Image.new("RGBA", (sz * s, sz * s), (0, 0, 0, 0)); d = ImageDraw.Draw(im); c = sz * s / 2
    head = t * 1.25 * 12
    for i in range(12):
        a = i / 12 * 2 * math.pi - math.pi / 2
        k = ((i - head) % 12) / 12
        col = tuple(int(LAV[j] * (1 - k) + (90, 60, 160)[j] * k) for j in range(3))
        r = (4.2 - 1.6 * k) * s
        x, y = c + R * s * math.cos(a), c + R * s * math.sin(a)
        d.ellipse((x - r, y - r, x + r, y + r), fill=col + (255,))
    return im.resize((sz, sz), Image.LANCZOS)

ROW_W, ROW_H = RIGHT[2] - RIGHT[0] - 16, 236
def row_img(i: int, value: float) -> Image.Image:
    s = SS; w, h = ROW_W * s, ROW_H * s
    im = Image.new("RGB", (w, h), PANEL); d = ImageDraw.Draw(im)
    label = SLIDERS[i][0]
    icon(d, ICONS[i], 34 * s, 36 * s, s)
    d.text((74 * s, 36 * s), label, font=font(BOLD, 37 * s), fill=INK, anchor="lm")
    tx0, tx1, ty, th = 18 * s, w - 18 * s, 106 * s, 16 * s
    d.rounded_rectangle((tx0, ty - th, tx1, ty + th), th, fill=TRACK_OFF)
    kx = tx0 + (value - VMIN) / (VMAX - VMIN) * (tx1 - tx0)
    fm = Image.new("L", im.size, 0)
    ImageDraw.Draw(fm).rounded_rectangle((tx0, ty - th, kx + th, ty + th), th, fill=255)
    gx = np.clip((np.arange(w, dtype=np.float32) - tx0) / max(kx - tx0, 1), 0, 1)[None, :, None]
    grad = (np.array(MAGENTA, np.float32) * (1 - gx) + np.array(VIOLET, np.float32) * gx).repeat(h, 0)
    im.paste(Image.fromarray(grad.astype(np.uint8)), (0, 0), fm)
    # glossy thumb
    kr = 30 * s
    tg = Image.new("L", im.size, 0); ImageDraw.Draw(tg).ellipse((kx - kr - 6 * s, ty - kr - 2 * s, kx + kr + 6 * s, ty + kr + 10 * s), fill=150)
    im.paste((14, 8, 26), (0, 0), tg.filter(ImageFilter.GaussianBlur(8 * s)))
    d.ellipse((kx - kr, ty - kr, kx + kr, ty + kr), fill=THUMB)
    d.ellipse((kx - kr * 0.72, ty - kr * 0.85, kx + kr * 0.5, ty - kr * 0.05), fill=(178, 120, 248))
    # value box
    txt = fmt(value); f = font(SEMI, 30 * s)
    bw = f.getlength(txt) + 28 * s
    d.rounded_rectangle((w - 18 * s - bw, 152 * s, w - 18 * s, 200 * s), 10 * s, fill=VALBOX)
    d.text((w - 18 * s - bw / 2, 176 * s), txt, font=f, fill=INK, anchor="mm")
    return im.resize((ROW_W, ROW_H), Image.LANCZOS)

def scene_frames():
    photo = load_photo(); base = build_base()
    pmask = rr_mask(PW, PH, 30)
    static_rows = {i: row_img(i, 0.0) for i in range(2, 6)}
    for f in range(N):
        t = f / FPS; p = progress(f)
        vals = [a + (b - a) * p for _, a, b in SLIDERS]
        fr = base.copy()
        g = grade(photo, p, vals[0], vals[1])
        sy = ((t * 0.5) % 1.0) * (PH + 300) - 150                     # AI scan shimmer
        band = np.exp(-((_yy - sy) / 70.0) ** 2)[..., None] * 0.06 * (1 - 0.6 * p)
        g = np.clip(g + band * np.array([0.85, 0.75, 1.0], np.float32), 0, 1)
        fr.paste(Image.fromarray((g * 255 + 0.5).astype(np.uint8)), PHOTO[:2], pmask)
        tg = toggle(ease((t - 2.05) / 0.25)); fr.paste(tg, (44, 196), tg)
        sp = spinner(t); fr.paste(sp, (114, 83 - 36), sp)
        for i in range(6):
            r = static_rows.get(i) or row_img(i, vals[i])
            fr.paste(r, (RIGHT[0] + 8, ROW0 - 50 + i * PITCH))
        yield fr.resize((OW, OH), Image.LANCZOS)

def main():
    dec = subprocess.Popen(["ffmpeg", "-loglevel", "error", "-i", str(SRC_VIDEO), "-f", "rawvideo",
                            "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
    tmp = OUT.with_suffix(".video.mp4")
    enc = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
                            "-s", f"{OW}x{OH}", "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-profile:v", "high",
                            "-preset", "slow", "-crf", "17", "-pix_fmt", "yuv420p", str(tmp)], stdin=subprocess.PIPE)
    fsz = OW * OH * 3; i = 0
    while True:
        buf = dec.stdout.read(fsz)
        if len(buf) < fsz: break
        if i < KEEP_HEAD or i >= CUT_OUT:
            enc.stdin.write(buf)
        if i == KEEP_HEAD - 1:
            for fr in scene_frames():
                enc.stdin.write(fr.tobytes())
        i += 1
    enc.stdin.close(); enc.wait(); dec.wait()
    assert enc.returncode == 0 and i >= CUT_OUT, i
    tmp.replace(OUT)                   # picture only; audio from mix_v15.py
    print("frames", i, "->", OUT)

if __name__ == "__main__":
    main()
