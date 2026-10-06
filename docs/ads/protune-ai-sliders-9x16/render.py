#!/usr/bin/env python3
"""ProTune AI Camera — "AI Processing..." 6-slider promo (9:16, 1080x1920, 6 s @ 30 fps).

Rendered programmatically (Pillow + numpy -> ffmpeg) so every label is exact.
Styled after the real iOS app (ios/PhotoRecipes):
  - Theme.swift            graphite surfaces #111111/#1C1C1E/#2C2C2E, Signal Amber #E0A812/#F5C518, ink #F5F5F7
  - AgentStatusPill.swift  black 55% capsule, pulsing amber dot (0.8 s ease, 0.4<->1.0), bodySm ink copy
  - ManualDialsSheet.swift evRow: surface card r=12pt, overline label + monoSm value, Slider .tint(accent)
  - CameraView.swift       shutterRow: Recommend box (sparkles), white-ring/amber-core shutter, ellipsis.circle
  - docs/asc/screenshots/en-US (Inter fonts, store-frame look)
Photo: "Brunette woman portrait (Unsplash).jpg" by Christopher Campbell, CC0 1.0, via Wikimedia Commons
  https://commons.wikimedia.org/wiki/File:Brunette_woman_portrait_(Unsplash).jpg

Usage: python3 render.py [out.mp4] [poster.png]
"""
from __future__ import annotations
import hashlib, math, subprocess, sys, urllib.request
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "protune-ai-sliders-9x16.mp4"
POSTER = Path(sys.argv[2]) if len(sys.argv) > 2 else HERE / "poster.png"
SRC_URL = "https://upload.wikimedia.org/wikipedia/commons/1/16/Brunette_woman_portrait_%28Unsplash%29.jpg"
SRC_SHA1 = "29612991a226c0f9dbdd33be0b8014ee4f00629c"
SRC = HERE / "portrait_src.jpg"

W, H, FPS, SECS = 1080, 1920, 30, 6.0
N = int(FPS * SECS)
SS = 2  # supersample factor for vector UI

# ---- Theme.swift palette -------------------------------------------------
BG = (17, 17, 17); SURFACE = (28, 28, 30); SURFACE2 = (44, 44, 46)
BORDER = (58, 58, 60); BORDER_STRONG = (84, 84, 86)
INK = (245, 245, 247); INK2 = (199, 199, 204); INK3 = (142, 142, 147); CAPTION = (168, 168, 179)
AMBER = (224, 168, 18); AMBER_SOFT = (245, 197, 24)
TRACK = (57, 57, 61)

FONT_DIRS = [HERE / "fonts", HERE.parent.parent / "asc" / "screenshots" / "en-US" / "fonts"]
_fc: dict = {}
def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    k = (name, size)
    if k not in _fc:
        for d in FONT_DIRS:
            if (d / name).exists():
                _fc[k] = ImageFont.truetype(str(d / name), size); break
        else:
            raise FileNotFoundError(name)
    return _fc[k]
SEMI, BOLD, MONO = "Inter-SemiBold.ttf", "Inter-Bold.ttf", "IBMPlexMono-SemiBold.ttf"

# ---- layout (px) ---------------------------------------------------------
PAD = 36
TOP = 300; BOTTOM = 1560
PHOTO = (PAD, TOP, PAD + 600, BOTTOM)             # left ~56%
PANEL_X0, PANEL_X1 = PHOTO[2] + 24, W - PAD       # right ~36% card column (384px)
GAP = 16
CARD_H = (BOTTOM - TOP - 5 * GAP) // 6
SLIDERS = [  # (label, start, end) — only Exposure & Contrast move
    ("Exposure", -1.0, 0.8),
    ("Contrast", -0.8, 0.6),
    ("Saturation", 0.0, 0.0),
    ("Sharpness", 0.0, 0.0),
    ("Color Balance", 0.0, 0.0),
    ("HDR Boost", 0.0, 0.0),
]
assert len({s[0] for s in SLIDERS}) == 6
VMIN, VMAX = -2.0, 2.0

def card_box(i):
    y0 = TOP + i * (CARD_H + GAP)
    return (PANEL_X0, y0, PANEL_X1, y0 + CARD_H)

def ease(x):  # smootherstep
    x = min(max(x, 0.0), 1.0)
    return x * x * x * (x * (x * 6 - 15) + 10)

def progress(f):
    return ease((f / FPS - 0.35) / (5.45 - 0.35))

def fmt(v: float) -> str:
    r = round(v + 0.0, 1)
    return "0.0" if abs(r) < 0.05 else f"{r:+.1f}"

# ---- helpers ---------------------------------------------------------------
def rr_mask(w, h, r):
    m = Image.new("L", (w * 4, h * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w * 4 - 1, h * 4 - 1), r * 4, fill=255)
    return m.resize((w, h), Image.LANCZOS)

def shadow(base: Image.Image, box, r, blur=22, alpha=150, dy=10):
    x0, y0, x1, y1 = box
    sh = Image.new("L", base.size, 0)
    ImageDraw.Draw(sh).rounded_rectangle((x0, y0 + dy, x1, y1 + dy), r, fill=alpha)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    base.paste(Image.new("RGB", base.size, (0, 0, 0)), (0, 0), sh)

def sparkles(d, cx, cy, s, fill):
    def star(x, y, r):
        k = r * 0.28
        d.polygon([(x, y - r), (x + k, y - k), (x + r, y), (x + k, y + k),
                   (x, y + r), (x - k, y + k), (x - r, y), (x - k, y - k)], fill=fill)
    star(cx - s * 0.15, cy + s * 0.1, s * 0.62)
    star(cx + s * 0.55, cy - s * 0.5, s * 0.3)

# ---- source photo ----------------------------------------------------------
def load_photo():
    if not SRC.exists():
        req = urllib.request.Request(SRC_URL, headers={"User-Agent": "ProTuneRender/1.0"})
        SRC.write_bytes(urllib.request.urlopen(req).read())
    assert hashlib.sha1(SRC.read_bytes()).hexdigest() == SRC_SHA1, "source photo changed"
    im = Image.open(SRC).convert("RGB")
    pw, ph = PHOTO[2] - PHOTO[0], PHOTO[3] - PHOTO[1]
    cw = round(im.height * pw / ph); cx = 2696
    im = im.crop((cx - cw // 2, 0, cx - cw // 2 + cw, im.height)).resize((pw, ph), Image.LANCZOS)
    return np.asarray(im).astype(np.float32) / 255.0

PH_W, PH_H = PHOTO[2] - PHOTO[0], PHOTO[3] - PHOTO[1]
_yy, _xx = np.mgrid[0:PH_H, 0:PH_W].astype(np.float32)
_u, _v = _xx / PH_W, _yy / PH_H
# warm key light from upper-right (golden hour), soft falloff
WARM_GLOW = np.clip(1.0 - np.sqrt(((_u - 0.95) * 1.1) ** 2 + ((_v - 0.08) * 0.85) ** 2) / 0.95, 0, 1) ** 1.6
VIGNETTE = np.clip(1.0 - (((_u - 0.5) * 1.25) ** 2 + ((_v - 0.45) * 0.95) ** 2), 0, 1) ** 0.5
LUMA = np.array([0.2126, 0.7152, 0.0722], np.float32)

def grade(img, p, exposure, contrast):
    """Real per-pixel grade: dull/flat/cool (p=0) -> vibrant/warm (p=1)."""
    x = img * (2.0 ** (exposure * 0.30))                       # exposure (stops-ish)
    x = np.where(x > 0.75, 0.75 + 0.25 * np.tanh((x - 0.75) / 0.25), x)  # highlight roll-off
    x = (x - 0.42) * (1.0 + contrast * 0.38) + 0.42            # contrast around mid pivot
    haze = 0.10 * (1 - p)                                       # flat milky blacks at start
    x = x * (1 - haze) + haze * 0.52
    cool = np.array([0.92, 0.98, 1.09], np.float32); warm = np.array([1.05, 1.0, 0.90], np.float32)
    x = x * (cool * (1 - p) + warm * p)                         # white balance cool -> warm
    sat = 0.38 + 0.77 * p                                       # desaturated -> vibrant
    y = (x @ LUMA)[..., None]
    x = y + (x - y) * sat
    g = (WARM_GLOW * (0.30 * p))[..., None]                     # warm light wash (screen)
    light = np.array([1.0, 0.74, 0.42], np.float32)
    x = 1 - (1 - np.clip(x, 0, 1)) * (1 - g * light)
    x = x * (1 - (1 - VIGNETTE[..., None]) * 0.35 * p)          # gentle vignette at end
    return np.clip(x, 0, 1)

# ---- static base -----------------------------------------------------------
def status_bar(d, s):
    d.text((96 * s, 76 * s), "9:41", font=font(SEMI, 44 * s), fill=INK, anchor="lm")
    x = 838 * s; cy = 76 * s
    for i, hgt in enumerate([12, 18, 24, 30]):  # cellular bars
        bx = x + i * 13 * s
        d.rounded_rectangle((bx, cy + 15 * s - hgt * s, bx + 9 * s, cy + 15 * s), 2 * s, fill=INK)
    wx, wy = 918 * s, cy + 14 * s                    # wifi arcs
    for r, wdt in [(30, 6), (19, 6)]:
        d.arc((wx - r * s, wy - r * s, wx + r * s, wy + r * s), 225, 315, fill=INK, width=wdt * s)
    d.pieslice((wx - 8 * s, wy - 8 * s, wx + 8 * s, wy + 8 * s), 225, 315, fill=INK)
    bx0 = 962 * s                                     # battery
    d.rounded_rectangle((bx0, cy - 13 * s, bx0 + 50 * s, cy + 13 * s), 8 * s, outline=(140, 140, 145), width=3 * s)
    d.rounded_rectangle((bx0 + 5 * s, cy - 8 * s, bx0 + 38 * s, cy + 8 * s), 4 * s, fill=INK)
    d.rounded_rectangle((bx0 + 53 * s, cy - 5 * s, bx0 + 57 * s, cy + 5 * s), 2 * s, fill=(140, 140, 145))

def floating_icon(d, cx, cy, s, kind):
    r = 50 * s
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(38, 38, 40))
    if kind == "bolt":
        pts = [(cx + 6, cy - 26), (cx - 14, cy + 4), (cx - 1, cy + 4), (cx - 6, cy + 26), (cx + 14, cy - 4), (cx + 1, cy - 4)]
        d.polygon([(cx + (px - cx) * s, cy + (py - cy) * s) for px, py in pts], fill=INK)
    elif kind == "flip":
        for a0, a1 in [(200, 340), (20, 160)]:
            d.arc((cx - 22 * s, cy - 22 * s, cx + 22 * s, cy + 22 * s), a0, a1, fill=INK, width=5 * s)
        d.polygon([(cx + 20 * s, cy - 14 * s), (cx + 30 * s, cy + 2 * s), (cx + 12 * s, cy + 2 * s)], fill=INK)
        d.polygon([(cx - 20 * s, cy + 14 * s), (cx - 30 * s, cy - 2 * s), (cx - 12 * s, cy - 2 * s)], fill=INK)
    elif kind == "ellipsis":
        d.ellipse((cx - 26 * s, cy - 26 * s, cx + 26 * s, cy + 26 * s), outline=INK, width=4 * s)
        for dx in (-12, 0, 12):
            d.ellipse((cx + (dx - 3.5) * s, cy - 3.5 * s, cx + (dx + 3.5) * s, cy + 3.5 * s), fill=INK)

def build_base():
    s = SS
    yy = np.linspace(0, 1, H * s, dtype=np.float32)[:, None, None]
    top = np.array([24, 24, 26], np.float32); bot = np.array(BG, np.float32)
    bg = np.broadcast_to(top * (1 - yy) + bot * yy, (H * s, W * s, 3))
    base = Image.fromarray(bg.astype(np.uint8), "RGB")
    sb = lambda b: tuple(v * s for v in b)
    shadow(base, sb(PHOTO), 44 * s, blur=26 * s, alpha=170, dy=12 * s)
    for i in range(6):
        shadow(base, sb(card_box(i)), 33 * s, blur=14 * s, alpha=130, dy=6 * s)
    d = ImageDraw.Draw(base)
    status_bar(d, s)
    floating_icon(d, 96 * s, 222 * s, s, "bolt")
    floating_icon(d, (W - 96) * s, 222 * s, s, "flip")
    # photo frame placeholder
    d.rounded_rectangle(sb(PHOTO), 44 * s, fill=(30, 30, 32))
    # shutterRow (CameraView.swift): Recommend box | shutter | ellipsis.circle
    cy = 1720
    rb = (PAD + 30, cy - 78, PAD + 30 + 156, cy + 78)
    d.rounded_rectangle(sb(rb), 28 * s, fill=(30, 30, 32), outline=(58, 58, 60), width=2 * s)
    sparkles(d, (rb[0] + rb[2]) / 2 * s, (cy - 22) * s, 22 * s, INK)
    d.text(((rb[0] + rb[2]) / 2 * s, (cy + 38) * s), "Recommend", font=font(SEMI, 25 * s), fill=INK2, anchor="mm")
    cx = W // 2
    d.ellipse(((cx - 98) * s, (cy - 98) * s, (cx + 98) * s, (cy + 98) * s), outline=INK, width=10 * s)
    d.ellipse(((cx - 78) * s, (cy - 78) * s, (cx + 78) * s, (cy + 78) * s), fill=AMBER)
    floating_icon(d, (W - PAD - 30 - 78) * s, cy * s, s, "ellipsis")
    d.rounded_rectangle(((W // 2 - 190) * s, 1884 * s, (W // 2 + 190) * s, 1898 * s), 7 * s, fill=INK)  # home indicator
    return base.resize((W, H), Image.LANCZOS)

# ---- dynamic elements ------------------------------------------------------
_KNOB = None
def knob_sprite():
    global _KNOB
    if _KNOB is None:
        k = 4; R = 23; pad = 14; sz = (R + pad) * 2
        im = Image.new("RGBA", (sz * k, sz * k), (0, 0, 0, 0))
        sh = Image.new("L", im.size, 0)
        c = sz * k / 2
        ImageDraw.Draw(sh).ellipse((c - R * k, c - R * k + 4 * k, c + R * k, c + R * k + 4 * k), fill=120)
        sh = sh.filter(ImageFilter.GaussianBlur(5 * k))
        im.paste((0, 0, 0, 255), (0, 0), sh)
        ImageDraw.Draw(im).ellipse((c - R * k, c - R * k, c + R * k, c + R * k), fill=(255, 255, 255, 255))
        _KNOB = im.resize((sz, sz), Image.LANCZOS)
    return _KNOB

def card(label: str, value: float, active: bool) -> Image.Image:
    """ManualDialsSheet.evRow look: surface card, overline label, monoSm value, amber-tinted Slider."""
    x0, y0, x1, y1 = 0, 0, PANEL_X1 - PANEL_X0, CARD_H
    s = SS; w, h = x1 * s, y1 * s
    im = Image.new("RGB", (w, h), SURFACE)
    d = ImageDraw.Draw(im)
    p = 26
    d.text((p * s, 52 * s), label, font=font(SEMI, 31 * s), fill=CAPTION, anchor="lm")
    d.text((w - p * s, 52 * s), fmt(value), font=font(MONO, 38 * s),
           fill=AMBER_SOFT if active else INK, anchor="rm")
    tx0, tx1, ty = (p + 6) * s, w - (p + 6) * s, 128 * s
    th = 5 * s
    kx = tx0 + (value - VMIN) / (VMAX - VMIN) * (tx1 - tx0)
    d.rounded_rectangle((tx0, ty - th, tx1, ty + th), th, fill=TRACK)
    d.rounded_rectangle((tx0, ty - th, kx, ty + th), th, fill=AMBER)
    cxm = (tx0 + tx1) / 2  # zero tick
    d.rounded_rectangle((cxm - 2 * s, ty + 22 * s, cxm + 2 * s, ty + 34 * s), 2 * s, fill=BORDER_STRONG)
    im = im.resize((x1, y1), Image.LANCZOS)
    k = knob_sprite()
    im.paste(k, (round(kx / s - k.width / 2), round(ty / s - k.height / 2)), k)
    return im

def pill(t: float) -> tuple[Image.Image, Image.Image]:
    """AgentStatusPill: black 55% capsule, pulsing amber dot, 'AI Processing...' with a soft shimmer."""
    s = SS
    text = "AI Processing..."
    f = font(SEMI, 40 * s)
    tw = f.getlength(text)
    padx, dot, gap = 40 * s, 22 * s, 22 * s
    w = int(padx * 2 + dot + gap + tw); h = 92 * s
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, w - 1, h - 1), h // 2, fill=(0, 0, 0, 150), outline=(70, 70, 72, 255), width=2 * s)
    pulse = 0.4 + 0.6 * (0.5 + 0.5 * math.cos(math.pi * t / 0.8))  # 0.8 s autoreverse
    a = int(255 * pulse)
    glow = Image.new("L", im.size, 0)
    ImageDraw.Draw(glow).ellipse((padx - 10 * s, h / 2 - dot / 2 - 10 * s, padx + dot + 10 * s, h / 2 + dot / 2 + 10 * s), fill=int(110 * pulse))
    glow = glow.filter(ImageFilter.GaussianBlur(7 * s))
    im.paste(Image.new("RGBA", im.size, AMBER_SOFT + (255,)), (0, 0), glow)
    d.ellipse((padx, h / 2 - dot / 2, padx + dot, h / 2 + dot / 2), fill=AMBER_SOFT + (a,))
    # text mask + shimmer band
    mask = Image.new("L", im.size, 0)
    tx = padx + dot + gap
    ImageDraw.Draw(mask).text((tx, h / 2), text, font=f, fill=255, anchor="lm")
    m = np.asarray(mask).astype(np.float32) / 255
    xs = np.arange(w, dtype=np.float32)
    phase = (t % 1.6) / 1.6
    bc = tx - 120 * s + phase * (tw + 240 * s)
    band = np.exp(-((xs - bc) / (55 * s)) ** 2)[None, :]
    col = np.array(INK2, np.float32) * (1 - band[..., None]) + np.array((255, 248, 225), np.float32) * band[..., None]
    rgba = np.asarray(im).astype(np.float32)
    rgba[..., :3] = rgba[..., :3] * (1 - m[..., None]) + col * m[..., None]
    rgba[..., 3] = np.maximum(rgba[..., 3], m * 255)
    out = Image.fromarray(rgba.astype(np.uint8), "RGBA").resize((w // s, h // s), Image.LANCZOS)
    return out

def main():
    photo = load_photo()
    base = build_base()
    pmask = rr_mask(PH_W, PH_H, 44)
    static_cards = {i: card(lbl, a, False) for i, (lbl, a, b) in enumerate(SLIDERS) if a == b}
    ff = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
                           "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "slow",
                           "-crf", "16", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-an", str(OUT)],
                          stdin=subprocess.PIPE)
    poster_f = N - 6
    for f in range(N):
        t = f / FPS; p = progress(f)
        vals = [a + (b - a) * p for _, a, b in SLIDERS]
        fr = base.copy()
        g = grade(photo, p, vals[0], vals[1])
        # AI scan sweep (subtle light band moving down while processing)
        sy = ((t * 0.55) % 1.0) * (PH_H + 300) - 150
        band = np.exp(-((_yy - sy) / 60.0) ** 2)[..., None] * 0.07 * (1 - 0.6 * p)
        g = np.clip(g + band * np.array([1.0, 0.92, 0.75], np.float32), 0, 1)
        fr.paste(Image.fromarray((g * 255 + 0.5).astype(np.uint8)), PHOTO[:2], pmask)
        for i, (lbl, a, b) in enumerate(SLIDERS):
            c = static_cards.get(i) or card(lbl, vals[i], True)
            fr.paste(c, card_box(i)[:2], _CM[0])
        pl = pill(t)
        fr.paste(pl, ((W - pl.width) // 2, 222 - pl.height // 2), pl)
        ff.stdin.write(fr.tobytes())
        if f == poster_f:
            fr.save(POSTER)
    ff.stdin.close(); ff.wait()
    assert ff.returncode == 0
    print("wrote", OUT, POSTER)

_CM = [None]
if __name__ == "__main__":
    _CM[0] = rr_mask(PANEL_X1 - PANEL_X0, CARD_H, 33)
    main()
