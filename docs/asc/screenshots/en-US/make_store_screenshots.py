#!/usr/bin/env python3
"""Build the App Store screenshots for AI Camera - Auto Recipes (photo-recipes).

5 frames x {iphone-69 1320x2868, ipad-13 2064x2752}, RGB PNG, no alpha.
Brand style: Signal Amber #E0A812 on dark #111111 (the app's palette). Every frame
carries LARGE ExtraBold hero text at the top explaining the functionality; hero
value frame first.

Phone screens are UI-chrome mock frames (not pixel-perfect device captures): the
shared viewfinder still from source/viewfinder-scene.jpg plus drawn dials, cards
and pills in the app's visual language.

Usage: python3 docs/asc/screenshots/en-US/make_store_screenshots.py   (Pillow + numpy)
"""
from __future__ import annotations
import numpy as np
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = Path(__file__).resolve().parent
SRC = HERE / "source" / "viewfinder-scene.jpg"
FONTS = HERE / "fonts"

SIZES = {"iphone-69": (1320, 2868), "ipad-13": (2064, 2752)}

# Brand palette (docs/marketing/asc-screenshot-brief-build16.md: Signal Amber)
AMBER = (224, 168, 18)
AMBER_SOFT = (245, 197, 24)
INK = (245, 245, 247)
MUTED = (168, 168, 172)
CARD = (26, 26, 29)
CARD_EDGE = (58, 58, 62)

# (slug, hero text, sub text) — every hero line must stay <= 5 words (check_copy.py).
SHOTS = [
    ("01-set-the-shot", "Set the shot.\nThen take it.", "Auto Optimize sets every dial for you"),
    ("02-auto-optimize", "Auto Optimize sets\nshutter, ISO, EV,\nWB and focus", "One tap reads the scene, applies the recipe"),
    ("03-real-dials", "Real capture dials.\nNot filters.", "Manual control whenever you want it"),
    ("04-teach-mode", "Every dial,\nexplained.", "Teach Mode shows the why behind the shot"),
    ("05-field-looks", "Field looks,\ngraded live.", "Capture grades in the viewfinder"),
]

_fonts: dict[tuple[int, str], ImageFont.FreeTypeFont] = {}


def font(size: int, weight: str = "ExtraBold") -> ImageFont.FreeTypeFont:
    key = (size, weight)
    if key not in _fonts:
        name = {"ExtraBold": "Inter-ExtraBold.ttf", "SemiBold": "Inter-SemiBold.ttf",
                "Bold": "Inter-Bold.ttf"}[weight]
        _fonts[key] = ImageFont.truetype(str(FONTS / name), size)
    return _fonts[key]


def dark_bg(W, H):
    """Dark gradient with a soft amber glow behind the caption, the app's palette."""
    y = np.linspace(0, 1, H)[:, None]
    x = np.linspace(0, 1, W)[None, :]
    top = np.array([34, 34, 37], float)
    bot = np.array([12, 12, 13], float)
    img = top[None, None, :] * (1 - y[..., None]) + bot[None, None, :] * y[..., None]
    d = np.sqrt((((x - 0.5) * W / H)) ** 2 + (y - 0.16) ** 2)
    glow = np.clip(1 - d / 0.5, 0, 1) ** 2 * 0.55
    amber = np.array(AMBER, float)
    img = img * (1 - glow[..., None] * 0.45) + amber * (glow[..., None] * 0.16)
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")


def draw_caption(canvas, text, sub, scale):
    d = ImageDraw.Draw(canvas)
    W = canvas.width
    f = font(round(126 * scale))
    y = round(150 * scale)
    lh = round(146 * scale)
    for line in text.split("\n"):
        w = d.textlength(line, font=f)
        assert w <= W - 2 * 60 * scale, (line, w)
        d.text(((W - w) / 2, y), line, font=f, fill=INK)
        y += lh
    if sub:
        fs = font(round(58 * scale), "SemiBold")
        y += round(22 * scale)
        w = d.textlength(sub, font=fs)
        d.text(((W - w) / 2, y), sub, font=fs, fill=AMBER_SOFT)
        y += round(70 * scale)
    return y


def rounded_mask(size, r):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), r, fill=255)
    return m


def drop_shadow(canvas, box, r, blur, offset, alpha):
    x0, y0, x1, y1 = box
    pad = blur * 3
    sh = Image.new("L", (x1 - x0 + 2 * pad, y1 - y0 + 2 * pad), 0)
    ImageDraw.Draw(sh).rounded_rectangle((pad, pad, pad + x1 - x0, pad + y1 - y0), r, fill=alpha)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    canvas.paste(Image.new("RGB", sh.size, (0, 0, 0)), (x0 - pad, y0 - pad + offset), sh)


def phone(canvas, screen, cx, top, screen_w):
    """Clean rounded graphite phone frame with the mock screen inside and a soft shadow."""
    sw = screen_w
    sh = round(screen.height * sw / screen.width)
    b = round(sw * 0.036)
    R = round(sw * 0.14)
    pw, ph = sw + 2 * b, sh + 2 * b
    x0 = round(cx - pw / 2)
    drop_shadow(canvas, (x0, top, x0 + pw, top + ph), R, round(sw * 0.05), round(sw * 0.04), 160)
    body = Image.new("RGB", (pw, ph), (58, 58, 62))
    inner = Image.new("RGB", (pw - 6, ph - 6), (18, 18, 20))
    body.paste(inner, (3, 3), rounded_mask(inner.size, R - 3))
    canvas.paste(body, (x0, top), rounded_mask((pw, ph), R))
    scr = screen.resize((sw, sh), Image.LANCZOS)
    canvas.paste(scr, (x0 + b, top + b), rounded_mask((sw, sh), R - b))
    return top + ph


def ctext(d, xy_center, s, f, fill):
    tb = d.textbbox((0, 0), s, font=f)
    d.text((xy_center[0] - (tb[0] + tb[2]) / 2, xy_center[1] - (tb[1] + tb[3]) / 2),
           s, font=f, fill=fill)


_viewfinder_src: Image.Image | None = None


def viewfinder(w, h, dim=0.0, warm=0.0):
    """Portrait center crop of the shared viewfinder still with top/bottom chrome gradients."""
    global _viewfinder_src
    if _viewfinder_src is None:
        _viewfinder_src = Image.open(SRC).convert("RGB")
    src = _viewfinder_src
    cw = int(src.height * w / h)
    x0 = (src.width - cw) // 2
    img = src.crop((x0, 0, x0 + cw, src.height)).resize((w, h), Image.LANCZOS)
    a = np.asarray(img).astype(float)
    if warm:
        a = a * (1 - warm) + np.array(AMBER, float) * warm
    yy = np.linspace(0, 1, h)[:, None]
    top_shade = np.clip((0.30 - yy) / 0.30, 0, 1) * 0.62
    bot_shade = np.clip((yy - 0.66) / 0.34, 0, 1) * 0.72
    dark = 1 - np.maximum(top_shade, bot_shade)[..., None]
    a = a * dark
    if dim:
        a = a * (1 - dim)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB")


def top_bar(d, w, s, wordmark="AI CAMERA"):
    f = font(round(30 * s), "Bold")
    d.text((round(36 * s), round(30 * s)), wordmark, font=f, fill=INK)
    for i, cx in enumerate((w - round(150 * s), w - round(80 * s))):
        r = round(22 * s)
        cy = round(48 * s)
        d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=MUTED, width=max(2, round(3 * s)))


def amber_pill(d, cx, cy, s, text="Auto Optimize"):
    f = font(round(40 * s), "Bold")
    tw = d.textlength(text, font=f)
    pw, ph = tw + round(110 * s), round(104 * s)
    x0, y0 = cx - pw / 2, cy - ph / 2
    d.rounded_rectangle((x0, y0, x0 + pw, y0 + ph), ph // 2, fill=AMBER)
    ctext(d, (cx, cy), text, f, (18, 18, 18))
    return y0 + ph


def shutter_row(d, w, y, s):
    cy = y
    r = round(64 * s)
    cx = w // 2
    d.ellipse((cx - r - round(10 * s), cy - r - round(10 * s), cx + r + round(10 * s), cy + r + round(10 * s)),
              outline=(255, 255, 255), width=max(3, round(6 * s)))
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(245, 245, 245))
    for sx in (round(150 * s), w - round(150 * s)):
        rr = round(34 * s)
        d.ellipse((sx - rr, cy - rr, sx + rr, cy + rr), outline=MUTED, width=max(2, round(4 * s)))


def dial_rows_card(w, s):
    """'Settings applied' card: before -> after dial values (the Auto Optimize burst)."""
    rows = [("SHUTTER", "1/60", "1/250"), ("ISO", "640", "400"), ("EV", "+0.7", "0.0"),
            ("WB", "Auto", "5200K"), ("FOCUS", "Auto", "Locked")]
    f_t = font(round(34 * s), "Bold")
    f_l = font(round(30 * s), "SemiBold")
    f_v = font(round(38 * s), "Bold")
    rh = round(86 * s)
    pad = round(44 * s)
    cw = w - round(120 * s)
    ch = round(96 * s) + len(rows) * rh + round(36 * s)
    card = Image.new("RGB", (cw, ch), CARD)
    d = ImageDraw.Draw(card)
    d.rounded_rectangle((0, 0, cw - 1, ch - 1), round(36 * s), outline=CARD_EDGE,
                        width=max(2, round(3 * s)))
    d.rectangle((0, round(28 * s), round(10 * s), ch - round(28 * s)), fill=AMBER)
    d.text((pad, round(30 * s)), "✓  Settings applied", font=f_t, fill=AMBER_SOFT)
    y = round(96 * s)
    for lab, before, after in rows:
        d.text((pad, y + round(8 * s)), lab, font=f_l, fill=MUTED)
        vr = f"{before}  →  {after}"
        vw = d.textlength(vr, font=f_v)
        # amber only on the new value
        bw = d.textlength(before, font=f_v)
        aw = d.textlength("  →  ", font=f_v)
        x = cw - pad - vw
        d.text((x, y), before, font=f_v, fill=MUTED)
        d.text((x + bw, y), "  →  ", font=f_v, fill=MUTED)
        d.text((x + bw + aw, y), after, font=f_v, fill=INK)
        y += rh
    return card


def screen_01(s):
    w, h = round(940 * s), round(1920 * s)
    img = viewfinder(w, h)
    d = ImageDraw.Draw(img)
    top_bar(d, w, s)
    amber_pill(d, w // 2, round(h * 0.60), s)
    shutter_row(d, w, round(h * 0.90), s)
    return img


def screen_02(s):
    w, h = round(940 * s), round(1920 * s)
    img = viewfinder(w, h, dim=0.45)
    d = ImageDraw.Draw(img)
    top_bar(d, w, s)
    card = dial_rows_card(w, s)
    img.paste(card, ((w - card.width) // 2, round(h * 0.30)), rounded_mask(card.size, round(36 * s)))
    f = font(round(38 * s), "Bold")
    bw, bh = round(560 * s), round(104 * s)
    bx, by = (w - bw) // 2, round(h * 0.30) + card.height + round(56 * s)
    d.rounded_rectangle((bx, by, bx + bw, by + bh), bh // 2, fill=AMBER)
    ctext(d, (w // 2, by + bh // 2), "Apply to camera", f, (18, 18, 18))
    shutter_row(d, w, round(h * 0.90), s)
    return img


def screen_03(s):
    w, h = round(940 * s), round(1920 * s)
    img = Image.new("RGB", (w, h), (16, 16, 18))
    d = ImageDraw.Draw(img)
    top_bar(d, w, s)
    f_h = font(round(36 * s), "Bold")
    d.text((round(60 * s), round(h * 0.10)), "MANUAL DIALS", font=f_h, fill=MUTED)
    dials = [("SHUTTER", "1/250"), ("ISO", "400"), ("EV", "±0.0"), ("WB", "5200K"),
             ("FOCUS", "Locked"), ("ZOOM", "1.0x"), ("TORCH", "Off"), ("LOOK", "goldenHour")]
    f_l = font(round(28 * s), "SemiBold")
    f_v = font(round(44 * s), "Bold")
    cols, gap = 2, round(28 * s)
    cw = (w - round(120 * s) - gap) // cols
    chh = round(190 * s)
    x0, y0 = round(60 * s), round(h * 0.155)
    for i, (lab, val) in enumerate(dials):
        x = x0 + (i % cols) * (cw + gap)
        y = y0 + (i // cols) * (chh + gap)
        d.rounded_rectangle((x, y, x + cw, y + chh), round(28 * s), fill=CARD,
                            outline=CARD_EDGE, width=max(2, round(3 * s)))
        d.text((x + round(32 * s), y + round(28 * s)), lab, font=f_l, fill=MUTED)
        d.text((x + round(32 * s), y + round(84 * s)), val, font=f_v, fill=AMBER_SOFT)
    f_n = font(round(32 * s), "SemiBold")
    ctext(d, (w // 2, round(h * 0.90)), "Tap a dial to adjust", f_n, MUTED)
    return img


def screen_04(s):
    w, h = round(940 * s), round(1920 * s)
    img = Image.new("RGB", (w, h), (16, 16, 18))
    d = ImageDraw.Draw(img)
    top_bar(d, w, s)
    f_t = font(round(44 * s), "Bold")
    f_b = font(round(36 * s), "SemiBold")
    f_c = font(round(34 * s), "SemiBold")
    cw = w - round(120 * s)
    body = ("Backlit ridge at golden hour. 1/250s freezes the drifting "
            "clouds; ISO 400 keeps shadow detail clean without noise.")
    # wrap body
    words = body.split()
    lines, line = [], ""
    maxw = cw - round(88 * s)
    for wd in words:
        t = (line + " " + wd).strip()
        if d.textlength(t, font=f_b) <= maxw:
            line = t
        else:
            lines.append(line); line = wd
    lines.append(line)
    ch = round(120 * s) + len(lines) * round(56 * s) + 3 * round(92 * s) + round(60 * s)
    card = Image.new("RGB", (cw, ch), CARD)
    cd = ImageDraw.Draw(card)
    cd.rounded_rectangle((0, 0, cw - 1, ch - 1), round(36 * s), outline=CARD_EDGE,
                         width=max(2, round(3 * s)))
    cd.rectangle((0, round(28 * s), round(10 * s), ch - round(28 * s)), fill=AMBER)
    cd.text((round(44 * s), round(36 * s)), "Why this recipe?", font=f_t, fill=AMBER_SOFT)
    y = round(120 * s)
    for ln in lines:
        cd.text((round(44 * s), y), ln, font=f_b, fill=INK)
        y += round(56 * s)
    checks = ["Shutter 1/250 — freeze motion", "ISO 400 — clean shadows", "EV 0.0 — hold highlights"]
    y += round(28 * s)
    for c in checks:
        r = round(22 * s)
        cx, cy = round(44 * s) + r, y + round(24 * s)
        cd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=AMBER)
        cd.line([(cx - r * 0.45, cy), (cx - r * 0.08, cy + r * 0.38), (cx + r * 0.5, cy - r * 0.35)],
                fill=(18, 18, 18), width=max(3, round(7 * s)), joint="curve")
        cd.text((cx + r + round(28 * s), y), c, font=f_c, fill=INK)
        y += round(92 * s)
    img.paste(card, ((w - cw) // 2, round(h * 0.22)), rounded_mask(card.size, round(36 * s)))
    f_n = font(round(32 * s), "SemiBold")
    ctext(d, (w // 2, round(h * 0.90)), "Ask “Why this?” after any run", f_n, MUTED)
    return img


def screen_05(s):
    w, h = round(940 * s), round(1920 * s)
    img = viewfinder(w, h, warm=0.16)
    d = ImageDraw.Draw(img)
    top_bar(d, w, s)
    looks = ["goldenHour", "monoInk", "tealOrange", "warmGlow", "crispCool"]
    f = font(round(32 * s), "Bold")
    gap = round(20 * s)
    hh = round(88 * s)
    rows = [looks[:3], looks[3:]]
    y = round(h * 0.68)
    for row in rows:
        ws = [d.textlength(l, font=f) + round(72 * s) for l in row]
        tw = sum(ws) + gap * (len(row) - 1)
        x = (w - tw) // 2
        for lab, ww in zip(row, ws):
            hl = lab == "goldenHour"
            d.rounded_rectangle((x, y, x + ww, y + hh), hh // 2,
                                fill=AMBER if hl else (30, 30, 34))
            ctext(d, (x + ww / 2, y + hh / 2), lab, f, (18, 18, 18) if hl else INK)
            x += ww + gap
        y += hh + gap
    # intensity slider
    f_s = font(round(30 * s), "SemiBold")
    sy = y + round(36 * s)
    sx0, sx1 = round(120 * s), w - round(120 * s)
    d.text((sx0, sy - round(64 * s)), "Intensity", font=f_s, fill=MUTED)
    d.rounded_rectangle((sx0, sy, sx1, sy + round(16 * s)), round(8 * s), fill=(60, 60, 64))
    d.rounded_rectangle((sx0, sy, sx0 + (sx1 - sx0) * 0.7, sy + round(16 * s)), round(8 * s), fill=AMBER)
    return img


BUILDERS = [screen_01, screen_02, screen_03, screen_04, screen_05]
SCREEN_HW = 1920 / 940  # screen height per unit width


def build_frame(W, H, scale, idx):
    c = dark_bg(W, H)
    y = draw_caption(c, SHOTS[idx][1], SHOTS[idx][2], scale)
    top = y + round(70 * scale)
    avail = H - top - round(110 * scale)
    sw = int(avail / (SCREEN_HW + 0.072))
    sw = min(sw, W - round(160 * scale))
    s = sw / 940  # screen-content scale relative to the 940-wide design
    screen = BUILDERS[idx](s)
    phone(c, screen, W / 2, top, sw)
    return c


def main():
    for f in HERE.glob("*.png"):
        if f.name.startswith(("iphone-69-", "ipad-13-")):
            f.unlink()
    for prefix, (W, H) in SIZES.items():
        scale = W / 1320 if prefix == "iphone-69" else 1.4
        for idx, (name, _, _) in enumerate(SHOTS):
            img = build_frame(W, H, scale, idx).convert("RGB")
            assert img.size == (W, H), img.size
            dst = HERE / f"{prefix}-{name}.png"
            img.save(dst, optimize=True)
            print(dst.name, img.size, img.mode)


if __name__ == "__main__":
    main()
