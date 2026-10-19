#!/usr/bin/env python3
"""ProTune selfie reel v19, 9:16 1080x1920, 30 fps, 12 s. Brief: ../video-agent-prompt.md

The picture is two REAL images of the same shot, composited into the shipped camera UI
(Signal Amber on graphite, ios/PhotoRecipes/Theme.swift; chrome as in the v1.3 App Store
screenshots):
  --before  the untouched selfie
  --after   the photo ProTune saved after Auto Optimize (and the Photo Look, if any)
Nothing here grades the photo. Without --after the script renders a MOCK draft
(approximate grade, watermarked "MOCK AFTER") for timing review only; never upload it.

Timeline: 0-2 s before + hook; 2-5 s finger taps Auto Optimize; 5-9 s transformation
(scan reveal, then a before/after divider sweep to prove it is the same photo);
9-12 s end card.

Usage:
  python3 render.py --before raw.jpg --after protune.jpg --look Warm \
      --out ../protune-selfie-reels-v19.mp4 --poster ../protune-selfie-reels-v19-poster.webp
  python3 render.py --probe 1.0 6.0 10.5      # PNG frames for review
audio.py adds the sound bed afterwards.
"""
from __future__ import annotations
import argparse, subprocess
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageOps

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
ADS = REPO / "docs" / "ads"
FONTS = REPO / "docs" / "asc" / "screenshots" / "en-US" / "fonts"
MONO = ADS / "protune-ai-sliders-9x16" / "fonts" / "IBMPlexMono-SemiBold.ttf"
ICON = REPO / "ios/PhotoRecipes/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
THUMB_SRC = REPO / "docs/asc/screenshots/en-US/source/viewfinder-scene.jpg"

W, H, FPS, DUR = 1080, 1920, 30, 12.0
N = int(DUR * FPS)

# Copy: exact lines from the brief.
HOOK = "Your selfies are\none tap from stunning."
LINE2 = "Watch AI edit your\nphotos like a pro."
HEADLINE = "Your selfies are one tap\nfrom stunning."

BG = (17, 17, 17); SURFACE2 = (44, 44, 46)
INK = (245, 245, 247); INK2 = (199, 199, 204); INK3 = (142, 142, 147)
AMBER = (224, 168, 18); AMBER_SOFT = (245, 197, 24); ON_AMBER = (18, 18, 18); GREEN = (48, 209, 88)

T_TAP = 2.7          # finger lands on Auto Optimize
T_REVEAL = 5.0       # after starts replacing before
T_REVEAL_END = 5.9
T_SPLIT = 7.0        # before/after divider sweep
T_SPLIT_END = 8.6
T_END = 9.0

_f = {}
def font(sz, w="ExtraBold"):
    k = (sz, w)
    if k not in _f:
        p = MONO if w == "Mono" else FONTS / f"Inter-{w}.ttf"
        _f[k] = ImageFont.truetype(str(p), sz)
    return _f[k]

def clamp(x, a=0.0, b=1.0): return max(a, min(b, x))
def ramp(t, t0, t1): return clamp((t - t0) / (t1 - t0))
def ease(x): x = clamp(x); return x * x * (3 - 2 * x)
def eout(x): x = clamp(x); return 1 - (1 - x) ** 3

SCR_W, SCR_H = 760, 1352
PX, PY, BEZ, SCR_R = (W - SCR_W) // 2, 470, 14, 78

def fit(im):
    return ImageOps.fit(im.convert("RGB"), (SCR_W, SCR_H), Image.LANCZOS, centering=(0.5, 0.4))

def mock_pair():
    """v17 'before' frame + an APPROXIMATE grade. Draft only (watermarked)."""
    raw = subprocess.run(["ffmpeg", "-v", "error", "-ss", "4.6", "-i", str(ADS / "protune-selfie-reels-v17.mp4"),
                          "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         check=True, capture_output=True).stdout
    b = Image.frombytes("RGB", (720, 1280), raw).crop((0, 40, 354, 670)).resize((SCR_W, SCR_H), Image.LANCZOS)
    b = b.filter(ImageFilter.UnsharpMask(2.2, 70, 2))
    a = np.asarray(b).astype(np.float32) / 255
    a = a * 1.3 * np.array([1.13, 1.02, 0.84], np.float32)
    l = a @ np.array([0.299, 0.587, 0.114], np.float32)
    a = l[..., None] + (a - l[..., None]) * 1.2
    return b, Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))

def rrect(d, box, r, **kw): d.rounded_rectangle(box, r, **kw)
def text_c(d, cx, y, s, f, fill):
    d.text((cx - d.textlength(s, font=f) / 2, y), s, font=f, fill=fill)

def background():
    y = np.linspace(0, 1, H)[:, None, None]; x = np.linspace(0, 1, W)[None, :, None]
    glow = np.exp(-(((x - 0.5) / 0.55) ** 2 + ((y - 0.10) / 0.16) ** 2))
    img = np.array(BG, np.float32) + glow * np.array([60, 44, 6], np.float32)
    return Image.fromarray(np.clip(img * (1 - 0.25 * y), 0, 255).astype(np.uint8)).convert("RGBA")

def overlay(base, fn, alpha=1.0, size=None, pos=(0, 0)):
    lay = Image.new("RGBA", size or base.size, (0, 0, 0, 0))
    fn(ImageDraw.Draw(lay))
    if alpha < 1: lay.putalpha(lay.getchannel("A").point(lambda v: int(v * alpha)))
    base.alpha_composite(lay, pos)

# ---------- captions (burned in, sound-off readable) ----------
CAPS = [(0.0, 2.25, HOOK, "Before"), (2.25, T_END, LINE2, None)]

def draw_caption(base, t):
    for t0, t1, hero, _ in CAPS:
        if t0 <= t < t1:
            a_in = 1.0 if t0 == 0 else eout(ramp(t, t0, t0 + 0.3))
            a = a_in * (1 - ramp(t, t1 - 0.15, t1))
            dy = (1 - a_in) * 26
            def fn(d):
                y = 110
                for ln in hero.split("\n"):
                    text_c(d, W / 2, y + dy, ln, font(80), INK + (255,)); y += 96
            overlay(base, fn, a)

# ---------- phone screen UI ----------
RAIL = ["N", "V", "W", "M", "K"]

def draw_ui(scr, t, look, thumb):
    d = ImageDraw.Draw(scr)
    d.text((44, 52), "AI CAMERA", font=font(26, "Bold"), fill=INK)
    for cx in (560, 612): d.ellipse((cx - 17, 54, cx + 17, 88), outline=INK2, width=3)
    rrect(d, (648, 52, 722, 90), 19, outline=AMBER, width=3); text_c(d, 685, 57, "PRO", font(22, "Bold"), AMBER)
    # status pill
    pill = None
    if T_TAP + 0.15 <= t < T_REVEAL: pill = ("Reading the light…", AMBER)
    elif T_REVEAL <= t < T_REVEAL_END + 0.5: pill = ("Applying…", AMBER) if t < T_REVEAL_END else ("Ready", GREEN)
    elif T_REVEAL_END + 0.5 <= t and look: pill = (f"Photo look · {look[1]}", AMBER)
    elif T_REVEAL_END + 0.5 <= t: pill = ("Ready", GREEN)
    if pill:
        s, col = pill; f = font(28, "SemiBold"); w = d.textlength(s, font=f) + 92; x0 = (SCR_W - w) / 2
        overlay(scr, lambda o: o.rounded_rectangle((x0, 120, x0 + w, 180), 30, fill=(0, 0, 0, 150)))
        d = ImageDraw.Draw(scr)
        p = 0.55 + 0.45 * abs(np.sin(t * np.pi / 0.8))
        d.ellipse((x0 + 30, 141, x0 + 48, 159), fill=tuple(int(v * p) for v in col))
        d.text((x0 + 62, 132), s, font=f, fill=INK)
    # Photo Looks rail
    on_key = look[0] if (look and t >= T_REVEAL_END + 0.3) else None
    for i, k in enumerate(RAIL):
        cy, cx = 470 + i * 78, SCR_W - 54; on = k == on_key
        d.ellipse((cx - 28, cy - 28, cx + 28, cy + 28), fill=AMBER if on else (12, 12, 12))
        text_c(d, cx, cy - 16, k, font(26, "Bold"), ON_AMBER if on else INK)
        if on:
            lw = d.textlength(look[1], font=font(26, "SemiBold"))
            d.text((cx - 44 - lw, cy - 16), look[1], font=font(26, "SemiBold"), fill=AMBER_SOFT)
    # bottom row
    by = 1216
    rrect(d, (44, by, 140, by + 96), 16, fill=SURFACE2, outline=INK2, width=3)
    th = ImageOps.fit(thumb, (88, 88), Image.LANCZOS)
    m = Image.new("L", (88, 88), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, 87, 87), 13, fill=255)
    scr.paste(th, (48, by + 4), m); d = ImageDraw.Draw(scr)
    sc = (306, by + 48)
    d.ellipse((sc[0] - 62, sc[1] - 62, sc[0] + 62, sc[1] + 62), outline=INK, width=6)
    d.ellipse((sc[0] - 50, sc[1] - 50, sc[0] + 50, sc[1] + 50), fill=INK)
    p = 1 - 0.07 * np.exp(-((t - T_TAP - 0.06) / 0.09) ** 2)
    cx, cy = 556, by + 48; bw, bh = 320 * p, 84 * p
    rrect(d, (cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2), bh / 2, fill=AMBER)
    f = font(int(31 * p), "Bold"); text_c(d, cx + 14, cy - 20 * p, "Auto Optimize", f, ON_AMBER)
    sx = cx + 14 - d.textlength("Auto Optimize", font=f) / 2 - 26
    for dx, dy in ((0, -11), (0, 11), (-11, 0), (11, 0)): d.line((sx, cy, sx + dx, cy + dy), fill=ON_AMBER, width=4)

def touch(scr, t, c, t0):
    a = ramp(t, t0 - 0.3, t0) * (1 - ramp(t, t0 + 0.15, t0 + 0.6))
    if a <= 0: return
    def fn(d):
        x, y = c
        d.ellipse((x - 40, y - 40, x + 40, y + 40), fill=(255, 255, 255, int(120 * a)))
        if t >= t0:
            r = 40 + 80 * eout(ramp(t, t0, t0 + 0.5))
            d.ellipse((x - r, y - r, x + r, y + r), outline=(255, 255, 255, int(180 * (1 - ramp(t, t0, t0 + 0.5)))), width=5)
    overlay(scr, fn)

def tag(scr, s, a):
    if a <= 0: return
    def fn(d):
        f = font(26, "Bold"); w = d.textlength(s, font=f) + 36
        d.rounded_rectangle((40, 210, 40 + w, 256), 12, fill=(0, 0, 0, 160))
        d.text((58, 217), s, font=f, fill=INK + (255,))
    overlay(scr, fn, a)

def watermark(scr):
    lay = Image.new("RGBA", (SCR_W * 2, 200), (0, 0, 0, 0)); d = ImageDraw.Draw(lay)
    text_c(d, SCR_W, 60, "MOCK AFTER · replace with device capture", font(44, "Bold"), (255, 60, 60, 200))
    lay = lay.rotate(58, expand=True, resample=Image.BICUBIC)
    scr.alpha_composite(lay, ((SCR_W - lay.width) // 2, (SCR_H - lay.height) // 2))

def screen(t, before, after, look, mock, thumb):
    # composite: reveal (top-down scan), then divider sweep after|before
    yl = SCR_H * ease(ramp(t, T_REVEAL, T_REVEAL_END))
    img = before.copy()
    if yl > 0: img.paste(after.crop((0, 0, SCR_W, int(yl))), (0, 0))
    split = None
    if T_SPLIT <= t < T_SPLIT_END:
        u = ramp(t, T_SPLIT, T_SPLIT_END)
        split = SCR_W * (1 - 0.5 * np.sin(np.pi * u))     # right edge -> centre -> right edge
        img.paste(before.crop((int(split), 0, SCR_W, SCR_H)), (int(split), 0))
    scr = img.convert("RGBA")
    if mock and t >= T_REVEAL: watermark(scr)
    d = ImageDraw.Draw(scr)
    if 0 < yl < SCR_H:
        for i in range(18):
            d.line((0, yl - i, SCR_W, yl - i), fill=AMBER_SOFT + (int(200 * (1 - i / 18)),))
    draw_ui(scr, t, look, thumb)
    if split is not None and split < SCR_W - 4:
        def fn(o):
            o.rectangle((split - 3, 0, split + 3, SCR_H), fill=INK + (255,))
            o.ellipse((split - 34, SCR_H / 2 - 34, split + 34, SCR_H / 2 + 34), fill=INK + (255,))
            o.text((split - 22, SCR_H / 2 - 18), "‹ ›", font=font(28, "Bold"), fill=ON_AMBER + (255,))
            f = font(26, "Bold")
            o.text((split - 20 - o.textlength("AFTER", font=f), 220), "AFTER", font=f, fill=INK + (255,))
            o.text((split + 20, 220), "BEFORE", font=f, fill=INK + (255,))
        overlay(scr, fn)
    else:
        tag(scr, "BEFORE", 1 - ramp(t, T_REVEAL, T_REVEAL + 0.2))
        tag(scr, "AFTER", ramp(t, T_REVEAL_END, T_REVEAL_END + 0.2) * (1 - ramp(t, T_SPLIT - 0.2, T_SPLIT)) +
            ramp(t, T_SPLIT_END, T_SPLIT_END + 0.2))
    touch(scr, t, (556, 1264), T_TAP)
    return scr

def end_card(t, after, mock):
    img = BG_IMG.copy()
    bgp = ImageOps.fit(after, (W, H), Image.LANCZOS).filter(ImageFilter.GaussianBlur(40)).convert("RGBA")
    img.alpha_composite(bgp); img.alpha_composite(Image.new("RGBA", (W, H), (12, 12, 12, 200)))
    a1, a2, a3 = (eout(ramp(t, T_END + o, T_END + o + 0.45)) for o in (0.15, 0.5, 0.85))
    icon = Image.open(ICON).convert("RGBA").resize((220, 220), Image.LANCZOS)
    m = Image.new("L", (220, 220), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, 219, 219), 50, fill=255)
    icon.putalpha(Image.fromarray((np.asarray(m) * a1).astype(np.uint8)))
    img.alpha_composite(icon, ((W - 220) // 2, int(430 - (1 - a1) * 30)))
    def tx(y, s, f, col, a):
        overlay(img, lambda d: text_c(d, W / 2, 0, s, f, col + (255,)), a, (W, 140), (0, int(y + (1 - a) * 24)))
    tx(700, "ProTune AI Camera", font(92), INK, a1)
    for i, ln in enumerate(HEADLINE.split("\n")):
        tx(850 + i * 74, ln, font(56, "Bold"), AMBER_SOFT, a2)
    def cta(d):
        d.rounded_rectangle(((W - 640) / 2, 0, (W + 640) / 2, 116), 58, fill=AMBER + (255,))
        text_c(d, W / 2, 30, "Free on the App Store", font(46, "Bold"), ON_AMBER + (255,))
    overlay(img, cta, a3, (W, 130), (0, int(1080 + (1 - a3) * 24)))
    tx(1236, "1 free Auto Optimize a day", font(34, "SemiBold"), INK3, a3)
    if mock: tx(1700, "DRAFT · MOCK AFTER · NOT FOR UPLOAD", font(34, "Bold"), (255, 80, 80), 1.0)
    return img

def frame(t, before, after, look, mock, thumbs):
    base = BG_IMG.copy()
    scr = screen(t, before, after, look, mock, thumbs[0])
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((PX - BEZ, PY - BEZ + 18, PX + SCR_W + BEZ, PY + SCR_H + BEZ + 18), SCR_R + BEZ, fill=(0, 0, 0, 170))
    base.alpha_composite(sh.filter(ImageFilter.GaussianBlur(28)))
    d = ImageDraw.Draw(base)
    d.rounded_rectangle((PX - BEZ, PY - BEZ, PX + SCR_W + BEZ, PY + SCR_H + BEZ), SCR_R + BEZ, fill=(10, 10, 10), outline=(70, 70, 74), width=3)
    base.paste(scr, (PX, PY), MASK)
    d.rounded_rectangle((W / 2 - 92, PY + 18, W / 2 + 92, PY + 70), 26, fill=(0, 0, 0))
    draw_caption(base, t)
    if t >= T_END:
        base = Image.blend(base, end_card(t, after, mock), ease(ramp(t, T_END, T_END + 0.35)))
    return base.convert("RGB")

def main():
    global BG_IMG, MASK
    ap = argparse.ArgumentParser()
    ap.add_argument("--before"); ap.add_argument("--after")
    ap.add_argument("--look", help="rail key and name of the Photo Look the app applied, e.g. W:Warm")
    ap.add_argument("--out", default=str(HERE / "draft.mp4")); ap.add_argument("--poster")
    ap.add_argument("--probe", nargs="*", type=float)
    a = ap.parse_args()
    mock = not (a.before and a.after)
    before, after = mock_pair() if mock else (fit(Image.open(a.before)), fit(Image.open(a.after)))
    look = tuple(a.look.split(":", 1)) if a.look else None
    BG_IMG = background()
    MASK = Image.new("L", (SCR_W, SCR_H), 0)
    ImageDraw.Draw(MASK).rounded_rectangle((0, 0, SCR_W - 1, SCR_H - 1), SCR_R, fill=255)
    thumbs = (Image.open(THUMB_SRC).convert("RGB"),)
    out = Path(a.out)
    if a.probe:
        for t in a.probe: frame(t, before, after, look, mock, thumbs).save(out.parent / f"probe_{t:05.2f}.png")
        return
    p = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
                          "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "slow", "-crf", "17",
                          "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(out)], stdin=subprocess.PIPE)
    for i in range(N):
        p.stdin.write(frame(i / FPS, before, after, look, mock, thumbs).tobytes())
    p.stdin.close(); p.wait()
    if a.poster:
        frame(8.8, before, after, look, mock, thumbs).save(a.poster, quality=90)

if __name__ == "__main__":
    main()
