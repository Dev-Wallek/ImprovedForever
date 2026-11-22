"""Draws the module icons that have no designer art, in the designed set's look
(import_icons.py: cream shapes, green accents, black outline, soft shadow):
  ic_mod_addons      a puzzle piece, a green "/" through it
  ic_mod_panel       a bar, a green fill along it, a coin over its end
  ic_mod_bags        a backpack, its front pocket and two strap tabs green

Run: python3 tools/draw_module_icons.py   (needs Pillow)
"""
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

TEX = os.path.join(os.path.dirname(__file__), "..", "ImprovedForever", "textures")
S = 4                       # drawn at 4x, scaled down to 128
N = 128 * S
CREAM = (255, 255, 192, 255)
GREEN = (124, 204, 140, 255)


def p(v):
    return int(v * S)


def mask():
    m = Image.new("L", (N, N), 0)
    return m, ImageDraw.Draw(m)


def rr(d, box, r):
    d.rounded_rectangle([p(b) for b in box], radius=p(r), fill=255)


def compose(layers):
    """[(mask, colour)] -> 128 x 128 RGBA, a black outline round their union, a shadow under it"""
    union = Image.new("L", (N, N), 0)
    for m, _ in layers:
        union = ImageChops.lighter(union, m)
    outline = union.filter(ImageFilter.MaxFilter(4 * S + 1))
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    shadow.putalpha(outline.filter(ImageFilter.GaussianBlur(3 * S)).point(lambda a: a * 0.6))
    img.alpha_composite(shadow, (0, p(3)))
    img.paste(Image.new("RGBA", (N, N), (0, 0, 0, 255)), (0, 0), outline)
    for m, col in layers:
        img.paste(Image.new("RGBA", (N, N), col), (0, 0), m)
    return img.resize((128, 128), Image.LANCZOS)


def puzzle():
    piece, d = mask()
    rr(d, (22, 34, 96, 108), 8)
    d.ellipse([p(48), p(16), p(70), p(38)], fill=255)   # top knob
    d.ellipse([p(90), p(60), p(112), p(82)], fill=255)  # right knob
    hole, dh = mask()
    dh.ellipse([p(10), p(60), p(32), p(82)], fill=255)  # left socket
    piece = ImageChops.subtract(piece, hole)
    slash, ds = mask()
    ds.line([p(66), p(50), p(48), p(96)], fill=255, width=p(10))
    piece = ImageChops.subtract(piece, slash.filter(ImageFilter.MaxFilter(3 * S + 1)))
    return [(piece, CREAM), (slash, GREEN)]


def panel():
    bar, d = mask()
    rr(d, (10, 50, 118, 78), 10)
    coin, dc = mask()
    dc.ellipse([p(74), p(30), p(122), p(78)], fill=255)
    bar = ImageChops.subtract(bar, coin.filter(ImageFilter.MaxFilter(4 * S + 1)))
    fill, df = mask()
    rr(df, (18, 57, 60, 71), 5)
    bar = ImageChops.subtract(bar, fill.filter(ImageFilter.MaxFilter(2 * S + 1)))
    return [(bar, CREAM), (fill, GREEN), (coin, CREAM)]


def backpack():
    body, d = mask()
    rr(d, (30, 30, 98, 116), 18)
    d.arc([p(44), p(10), p(84), p(46)], 180, 360, fill=255, width=p(7))   # handle
    cut, dc = mask()
    rr(dc, (30, 52, 98, 57), 0)           # flap seam
    rr(dc, (40, 76, 88, 104), 8)          # front pocket's rim
    body = ImageChops.subtract(body, cut)
    accents, da = mask()
    rr(da, (44, 80, 84, 100), 6)          # front pocket
    rr(da, (42, 46, 52, 68), 3)           # strap tabs
    rr(da, (76, 46, 86, 68), 3)
    gap, dg = mask()
    rr(dg, (40, 44, 54, 70), 4)
    rr(dg, (74, 44, 88, 70), 4)
    body = ImageChops.subtract(body, gap)
    return [(body, CREAM), (accents, GREEN)]


for name, layers in (("ic_mod_addons", puzzle()), ("ic_mod_panel", panel()), ("ic_mod_bags", backpack())):
    path = os.path.join(TEX, name + ".tga")
    compose(layers).save(path)
    print("wrote", path)
