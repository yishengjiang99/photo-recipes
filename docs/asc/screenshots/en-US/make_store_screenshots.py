#!/usr/bin/env python3
"""Build the App Store screenshots for ProTune AI Camera (photo-recipes).

5 frames x {iphone-69 1320x2868, ipad-13 2064x2752}, RGB PNG, no alpha.
Brand style: Signal Amber #E0A812 on dark #111111 (the app's palette). Every frame
carries LARGE ExtraBold hero text at the top explaining the functionality; hero
value frame first.

Phone screens are UI-chrome mock frames (not pixel-perfect device captures): the
shared viewfinder still from source/viewfinder-scene.jpg plus the NEW camera
chrome (v1.3 redesign): Auto Optimize as the primary button next to the shutter,
last-photo thumbnail, right-edge filter rail, left slide-out controls drawer.

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
# v1.3: the set features the redesigned camera chrome.
SHOTS = [
    ("01-new-chrome", "The camera,\nrebuilt around you.", "Auto Optimize is now the primary button"),
    ("02-auto-optimize", "One tap sets\nevery dial.", "Shutter, ISO, EV, WB, focus — written for you"),
    ("03-filter-rail", "Looks live on\nthe right rail.", "Field grades, one tap in the viewfinder"),
    ("04-control-drawer", "Every dial,\none swipe away.", "Slide out full manual control"),
    ("05-last-photo", "Your last shot,\none tap away.", "Review it without leaving the finder"),
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


# ---------------------------------------------------------------------------
# v1.3 camera chrome — matches the approved redesign mockup
# (docs/camera-chrome-mockup.html).
# ---------------------------------------------------------------------------

FILTERS = [("N", "Natural"), ("V", "Vivid"), ("W", "Warm"), ("M", "Mono"), ("K", "Noir")]


def draw_sparkle(d, cx, cy, r, fill):
    """4-point star glyph (Inter lacks ✦)."""
    import math
    pts = []
    for i in range(8):
        ang = math.pi / 4 * i - math.pi / 2
        rr = r if i % 2 == 0 else r * 0.36
        pts.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang)))
    d.polygon(pts, fill=fill)


def draw_mic(d, cx, cy, r, fill):
    """Minimal microphone glyph (Inter lacks ◉)."""
    w = r * 0.95
    d.rounded_rectangle((cx - w / 2, cy - r, cx + w / 2, cy + r * 0.35),
                        max(1, int(w / 4)), fill=fill)
    d.arc((cx - r * 0.78, cy - r * 0.55, cx + r * 0.78, cy + r * 0.95),
          25, 155, fill=fill, width=max(2, int(r * 0.24)))
    d.line((cx, cy + r * 0.95, cx, cy + r * 1.3), fill=fill, width=max(2, int(r * 0.24)))


def top_bar(d, w, s, wordmark="AI CAMERA"):
    """Top chrome: wordmark, upgrade pill, utility icons."""
    f = font(round(30 * s), "Bold")
    d.text((round(36 * s), round(30 * s)), wordmark, font=f, fill=INK)
    # Upgrade pill (amber outline)
    fu = font(round(26 * s), "Bold")
    ut = "PRO"
    uw = d.textlength(ut, font=fu)
    upw, uph = uw + round(44 * s), round(52 * s)
    ux1 = w - round(36 * s)
    ux0 = ux1 - upw
    uy = round(28 * s)
    d.rounded_rectangle((ux0, uy, ux1, uy + uph), uph // 2, outline=AMBER,
                        width=max(2, round(3 * s)))
    ctext(d, ((ux0 + ux1) / 2, uy + uph / 2), ut, fu, AMBER_SOFT)
    for i, cx in enumerate((ux0 - round(70 * s), ux0 - round(140 * s))):
        r = round(22 * s)
        cy = round(52 * s)
        d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=MUTED, width=max(2, round(3 * s)))


def filter_rail(d, w, h, s, active=1):
    """Right-edge vertical stack of filter/look buttons."""
    f = font(round(30 * s), "Bold")
    r = round(44 * s)
    gap = round(28 * s)
    n = len(FILTERS)
    total = n * (2 * r) + (n - 1) * gap
    y = round(h * 0.44) - total // 2
    cx = w - round(64 * s)
    for i, (glyph, _name) in enumerate(FILTERS):
        cy = y + r + i * (2 * r + gap)
        if i == active:
            d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=AMBER)
            ctext(d, (cx, cy), glyph, f, (18, 18, 18))
        else:
            d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(24, 24, 28),
                      outline=(90, 90, 96), width=max(2, round(3 * s)))
            ctext(d, (cx, cy), glyph, f, INK)


def drawer_handle(d, h, s):
    """Big left-edge handle that opens the manual-controls drawer."""
    hw, hh = round(64 * s), round(190 * s)
    x0, y0 = 0, round(h * 0.44) - hh // 2
    d.rounded_rectangle((x0 - round(20 * s), y0, x0 + hw, y0 + hh), round(24 * s),
                        fill=(24, 24, 28), outline=(90, 90, 96), width=max(2, round(3 * s)))
    # chevron ›
    f = font(round(44 * s), "Bold")
    ctext(d, (x0 + hw // 2 + round(6 * s), y0 + hh // 2), "›", f, AMBER_SOFT)


def ao_primary_button(d, cx, cy, s, text="Auto Optimize", running=False):
    """The primary Auto Optimize CTA — filled amber, next to the shutter."""
    f = font(round(36 * s), "Bold")
    tw = d.textlength(text, font=f)
    sr = round(20 * s)
    gap = round(18 * s)
    pw = sr * 2 + gap + tw + round(96 * s)
    ph = round(116 * s)
    x0, y0 = cx - pw / 2, cy - ph / 2
    if running:
        d.rounded_rectangle((x0, y0, x0 + pw, y0 + ph), ph // 2, fill=(60, 60, 64))
        ctext(d, (cx, cy), "Working…", f, MUTED)
    else:
        d.rounded_rectangle((x0, y0, x0 + pw, y0 + ph), ph // 2, fill=AMBER)
        sx = x0 + round(48 * s) + sr
        draw_sparkle(d, sx, cy, sr, (18, 18, 18))
        d.text((sx + sr + gap, cy - round(24 * s)), text, font=f, fill=(18, 18, 18))
    return pw


def last_photo_thumb(img, d, x, cy, s, highlight=False):
    """Rounded-square last-photo thumbnail (mini crop of the viewfinder)."""
    ts = round(128 * s)
    y0 = cy - ts // 2
    # mini crop of the scene itself as the "photo"
    thumb = img.crop((img.width // 3, img.height // 3,
                      img.width // 3 + ts * 2, img.height // 3 + ts * 2)).resize((ts, ts), Image.LANCZOS)
    img.paste(thumb, (x, y0), rounded_mask((ts, ts), round(24 * s)))
    d.rounded_rectangle((x, y0, x + ts, y0 + ts), round(24 * s),
                        outline=AMBER if highlight else (240, 240, 240),
                        width=max(3, round(6 * s) if highlight else round(4 * s)))
    return ts


def scene_field(d, w, y, s, text="Golden hour, backlit ridge…"):
    """Dictation scene field above the shutter row, with mic button."""
    f = font(round(32 * s), "SemiBold")
    ph = round(88 * s)
    x0, x1 = round(60 * s), w - round(60 * s)
    d.rounded_rectangle((x0, y, x1, y + ph), ph // 2, fill=(22, 22, 26),
                        outline=(80, 80, 86), width=max(2, round(3 * s)))
    d.text((x0 + round(36 * s), y + ph // 2 - round(22 * s)), text, font=f, fill=MUTED)
    # mic button
    mr = round(32 * s)
    mcx = x1 - round(52 * s)
    mcy = y + ph // 2
    d.ellipse((mcx - mr, mcy - mr, mcx + mr, mcy + mr), fill=AMBER)
    draw_mic(d, mcx, mcy - round(4 * s), round(20 * s), (18, 18, 18))
    return y + ph


def shutter_row_new(img, d, w, y, s, ao_text="Auto Optimize", thumb_highlight=False):
    """v1.3 shutter row: last-photo thumb | shutter | primary AO button."""
    cy = y
    # last-photo thumbnail, left
    last_photo_thumb(img, d, round(60 * s), cy, s, highlight=thumb_highlight)
    # shutter, center-left of the remaining space
    r = round(62 * s)
    cx = w // 2 - round(60 * s)
    d.ellipse((cx - r - round(10 * s), cy - r - round(10 * s), cx + r + round(10 * s), cy + r + round(10 * s)),
              outline=(255, 255, 255), width=max(3, round(6 * s)))
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(245, 245, 245))
    # AO primary button, right of shutter (clear of the ring)
    ao_cx = cx + r + round(10 * s) + round(215 * s)
    ao_primary_button(d, ao_cx, cy, s, text=ao_text)


def drawer_panel(img, w, h, s):
    """Mostly-transparent slide-out drawer with manual sliders (left edge)."""
    dw = min(round(430 * s), w // 2)
    dh = round(760 * s)
    y0 = round(h * 0.44) - dh // 2
    panel = Image.new("RGBA", (dw, dh), (14, 14, 17, 178))  # ~70% transparent
    pd = ImageDraw.Draw(panel)
    f_t = font(round(32 * s), "Bold")
    pd.text((round(36 * s), round(30 * s)), "Manual controls", font=f_t, fill=INK)
    sliders = [("Exposure", 0.55), ("Warmth", 0.62), ("Tint", 0.45),
               ("Contrast", 0.70), ("Saturation", 0.58)]
    f_l = font(round(28 * s), "SemiBold")
    f_v = font(round(28 * s), "Bold")
    y = round(110 * s)
    rh = round(118 * s)
    for lab, frac in sliders:
        pd.text((round(36 * s), y), lab, font=f_l, fill=MUTED)
        val = f"{int(frac * 100)}"
        vw = pd.textlength(val, font=f_v)
        pd.text((dw - round(36 * s) - vw, y), val, font=f_v, fill=AMBER_SOFT)
        ty = y + round(56 * s)
        tx0, tx1 = round(36 * s), dw - round(36 * s)
        pd.rounded_rectangle((tx0, ty, tx1, ty + round(14 * s)), round(7 * s), fill=(70, 70, 76))
        pd.rounded_rectangle((tx0, ty, tx0 + (tx1 - tx0) * frac, ty + round(14 * s)),
                             round(7 * s), fill=AMBER)
        kx = tx0 + (tx1 - tx0) * frac
        kr = round(20 * s)
        pd.ellipse((kx - kr, ty + round(7 * s) - kr, kx + kr, ty + round(7 * s) + kr),
                   fill=(245, 245, 245))
        y += rh
    img.paste(panel, (0, y0), panel)


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
        bw = d.textlength(before, font=f_v)
        aw = d.textlength("  →  ", font=f_v)
        x = cw - pad - vw
        d.text((x, y), before, font=f_v, fill=MUTED)
        d.text((x + bw, y), "  →  ", font=f_v, fill=MUTED)
        d.text((x + bw + aw, y), after, font=f_v, fill=INK)
        y += rh
    return card


def screen_01(s):
    """Hero: the full v1.3 chrome — AO primary, thumb, filter rail, drawer handle."""
    w, h = round(940 * s), round(1920 * s)
    img = viewfinder(w, h)
    d = ImageDraw.Draw(img)
    top_bar(d, w, s)
    filter_rail(d, w, h, s, active=1)
    drawer_handle(d, h, s)
    scene_field(d, w, round(h * 0.70), s)
    shutter_row_new(img, d, w, round(h * 0.88), s)
    return img


def screen_02(s):
    """Auto Optimize burst: settings-applied card over the new chrome."""
    w, h = round(940 * s), round(1920 * s)
    img = viewfinder(w, h, dim=0.45)
    d = ImageDraw.Draw(img)
    top_bar(d, w, s)
    card = dial_rows_card(w, s)
    img.paste(card, ((w - card.width) // 2, round(h * 0.26)), rounded_mask(card.size, round(36 * s)))
    f = font(round(38 * s), "Bold")
    bw, bh = round(560 * s), round(104 * s)
    bx, by = (w - bw) // 2, round(h * 0.26) + card.height + round(56 * s)
    d.rounded_rectangle((bx, by, bx + bw, by + bh), bh // 2, fill=AMBER)
    ctext(d, (w // 2, by + bh // 2), "Apply to camera", f, (18, 18, 18))
    drawer_handle(d, h, s)
    filter_rail(d, w, h, s, active=1)
    return img


def screen_03(s):
    """Filter rail spotlight: warm grade applied, rail highlighted."""
    w, h = round(940 * s), round(1920 * s)
    img = viewfinder(w, h, warm=0.22)
    d = ImageDraw.Draw(img)
    top_bar(d, w, s)
    filter_rail(d, w, h, s, active=2)  # Warm
    drawer_handle(d, h, s)
    # active look label
    f = font(round(34 * s), "Bold")
    label = "Warm"
    lw = d.textlength(label, font=f)
    lx = w - round(64 * s) - lw // 2
    d.text((lx - lw // 2, round(h * 0.44) + round(330 * s)), label, font=f, fill=AMBER_SOFT)
    scene_field(d, w, round(h * 0.70), s)
    shutter_row_new(img, d, w, round(h * 0.88), s)
    return img


def screen_04(s):
    """Control drawer open: translucent panel with manual sliders."""
    w, h = round(940 * s), round(1920 * s)
    img = viewfinder(w, h, dim=0.15)
    d = ImageDraw.Draw(img)
    top_bar(d, w, s)
    filter_rail(d, w, h, s, active=1)
    scene_field(d, w, round(h * 0.70), s)
    # shutter row BEFORE the drawer: the last-photo thumbnail crops the clean scene
    shutter_row_new(img, d, w, round(h * 0.88), s)
    drawer_panel(img, w, h, s)
    return img


def screen_05(s):
    """Last-photo thumbnail spotlight."""
    w, h = round(940 * s), round(1920 * s)
    img = viewfinder(w, h)
    d = ImageDraw.Draw(img)
    top_bar(d, w, s)
    filter_rail(d, w, h, s, active=1)
    drawer_handle(d, h, s)
    scene_field(d, w, round(h * 0.70), s)
    shutter_row_new(img, d, w, round(h * 0.88), s, thumb_highlight=True)
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
