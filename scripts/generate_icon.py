#!/usr/bin/env python3
"""Generate the DropShelf app icon (1024 master + .iconset PNGs).

Dropover-style aesthetic: a casual stack of white "cards/papers" with a
friendly green "+" badge on a vibrant blue->purple diagonal gradient.
Full-bleed square; the system applies the Big Sur squircle mask.
"""
import os
from PIL import Image, ImageDraw, ImageFilter

SS = 2                 # supersample factor (render at 2x then downsample)
S = 1024               # final master size
W = S * SS             # internal working size
OUT = os.path.join(os.path.dirname(__file__), "..", "build")
ICONSET = os.path.join(OUT, "AppIcon.iconset")

# ---------------------------------------------------------------- gradient
STOPS = [(0.0, (40, 110, 255)),    # vibrant blue
         (0.5, (104, 58, 240)),    # indigo
         (1.0, (166, 50, 236))]    # purple


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def gcol(t):
    if t <= 0:
        return STOPS[0][1]
    if t >= 1:
        return STOPS[-1][1]
    for i in range(len(STOPS) - 1):
        t0, c0 = STOPS[i]
        t1, c1 = STOPS[i + 1]
        if t0 <= t <= t1:
            return lerp(c0, c1, (t - t0) / (t1 - t0))
    return STOPS[-1][1]


# build small diagonal gradient then upscale (smooth, cheap)
g = 256
sm = Image.new("RGB", (g, g))
sp = sm.load()
for y in range(g):
    for x in range(g):
        sp[x, y] = gcol((x + y) / (2 * (g - 1)))
bg = sm.resize((W, W), Image.LANCZOS).convert("RGBA")

# soft radial highlight near the top for depth
hi = Image.new("L", (g, g), 0)
ImageDraw.Draw(hi).ellipse([g * 0.08, -g * 0.30, g * 0.92, g * 0.55], fill=80)
hi = hi.resize((W, W), Image.LANCZOS).filter(ImageFilter.GaussianBlur(W // 36))
glow = Image.new("RGBA", (W, W), (255, 255, 255, 0))
glow.putalpha(hi)
bg = Image.alpha_composite(bg, glow)


# ---------------------------------------------------------------- cards
def card(base, cx, cy, w, h, r, fill, angle=0, sh_dy=20, sh_blur=26, sh_a=85):
    cx *= SS; cy *= SS; w = int(w * SS); h = int(h * SS); r = int(r * SS)
    sh_dy *= SS; sh_blur *= SS
    pad = int(max(w, h))
    cw, ch = w + pad, h + pad
    layer = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(
        [(cw - w) // 2, (ch - h) // 2, (cw + w) // 2, (ch + h) // 2],
        radius=r, fill=fill)
    layer = layer.rotate(angle, resample=Image.BICUBIC, expand=False)

    alpha = layer.split()[3]
    shp = Image.new("RGBA", layer.size, (18, 14, 55, 0))
    shp.putalpha(alpha.point(lambda v: int(v * sh_a / 255)))
    shp = shp.filter(ImageFilter.GaussianBlur(sh_blur))
    base.alpha_composite(shp, (int(cx - cw / 2), int(cy - ch / 2 + sh_dy)))
    base.alpha_composite(layer, (int(cx - cw / 2), int(cy - ch / 2)))


# casually stacked papers (back -> front)
card(bg, 512, 470, 560, 360, 64, (255, 255, 255, 235), angle=-8,
     sh_dy=10, sh_blur=22, sh_a=55)
card(bg, 512, 508, 560, 360, 64, (255, 255, 255, 245), angle=5,
     sh_dy=14, sh_blur=24, sh_a=65)
card(bg, 512, 545, 560, 360, 64, (255, 255, 255, 255), angle=-2,
     sh_dy=22, sh_blur=30, sh_a=95)


# ---------------------------------------------------------------- "+" badge
def badge(base, cx, cy, rad, fill):
    cx *= SS; cy *= SS; rad *= SS
    sh = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse(
        [cx - rad, cy - rad + 9 * SS, cx + rad, cy + rad + 9 * SS],
        fill=(8, 50, 28, 130))
    sh = sh.filter(ImageFilter.GaussianBlur(18 * SS))
    base.alpha_composite(sh)

    l = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(l)
    d.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=fill)
    t = rad * 0.16
    arm = rad * 0.48
    d.rounded_rectangle([cx - t, cy - arm, cx + t, cy + arm], radius=t,
                        fill=(255, 255, 255, 255))
    d.rounded_rectangle([cx - arm, cy - t, cx + arm, cy + t], radius=t,
                        fill=(255, 255, 255, 255))
    base.alpha_composite(l)


badge(bg, 716, 716, 96, (43, 209, 126, 255))   # friendly green "add"

# ---------------------------------------------------------------- export
os.makedirs(ICONSET, exist_ok=True)
master = bg.resize((S, S), Image.LANCZOS)
master.save(os.path.join(OUT, "AppIcon-1024.png"))

sizes = {
    "icon_16x16.png": 16, "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128, "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256, "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512, "icon_512x512@2x.png": 1024,
}
for name, px in sizes.items():
    bg.resize((px, px), Image.LANCZOS).save(os.path.join(ICONSET, name))

print("OK: master + %d iconset PNGs written to %s" % (len(sizes), OUT))
