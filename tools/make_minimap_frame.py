"""The square minimap's frame (Minimap.lua, the Square minimap setting): a
bronze band in the colours of the game's round minimap frame, a dark line
either side of it, a soft shadow inward, a diamond on each corner.

  ic_minimap_square   128 x 128 nine-slice, corners of 32 (the band 12 px in)

Run: python3 tools/make_minimap_frame.py [preview.png]   (needs Pillow; with a
path, also a preview of the frame over a stand-in map, 256 px)
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "ImprovedForever", "textures")
SIZE, SS = 128, 4
DARK = (24, 16, 8, 255)
LIGHT = (236, 206, 140, 255)
GOLD = (196, 158, 86, 255)
BRONZE = (118, 86, 40, 255)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))


def frame():
    n = SIZE * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def px(v):
        return int(v * SS)

    # (a shadow inward of the band, blurred)
    shadow = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rectangle([px(9), px(9), n - px(9) - 1, n - px(9) - 1], outline=(0, 0, 0, 150), width=px(4))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(px(2.5))))
    d = ImageDraw.Draw(img)

    # The band: lighter at the top left, darker at the bottom right, row by row
    for i in range(px(1.5), px(9)):
        t = (i - px(1.5)) / (px(9) - px(1.5))
        # (a bevel: light near its outer edge, darker inward)
        tone = lerp(GOLD, BRONZE, t)
        d.rectangle([i, i, n - 1 - i, n - 1 - i], outline=tone, width=1)
    # (lit along the top and the left, in shade along the bottom and the right)
    d.line([px(2), px(2.5), n - px(2), px(2.5)], fill=LIGHT, width=px(1))
    d.line([px(2.5), px(2), px(2.5), n - px(2)], fill=LIGHT, width=px(1))
    d.line([px(2), n - px(2.5), n - px(2), n - px(2.5)], fill=BRONZE, width=px(1))
    d.line([n - px(2.5), px(2), n - px(2.5), n - px(2)], fill=BRONZE, width=px(1))
    # The dark lines: outside the band and inside it
    d.rectangle([0, 0, n - 1, n - 1], outline=DARK, width=px(1.5))
    d.rectangle([px(9), px(9), n - 1 - px(9), n - 1 - px(9)], outline=DARK, width=px(1))

    # A diamond on each corner, over the band
    for cx, cy in ((px(6), px(6)), (n - px(6), px(6)), (px(6), n - px(6)), (n - px(6), n - px(6))):
        for r, fill in ((px(9), DARK), (px(7.5), GOLD), (px(5), LIGHT), (px(3), BRONZE)):
            d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=fill)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def preview(img, path):
    n = 256
    # (a stand-in map: green and sand in patches)
    base = Image.new("RGBA", (n, n), (70, 96, 52, 255))
    d = ImageDraw.Draw(base)
    for x, y, r, c in ((60, 70, 50, (132, 120, 80, 255)), (180, 160, 70, (52, 80, 40, 255)), (200, 50, 40, (60, 90, 120, 255))):
        d.ellipse([x - r, y - r, x + r, y + r], fill=c)
    base = base.filter(ImageFilter.GaussianBlur(6))
    # (the frame as the game draws a nine-slice: corners at 32, edges stretched)
    big = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    c = 32
    cuts = [(0, c), (c, SIZE - c), (SIZE - c, SIZE)]
    dst = [(0, c), (c, n - c), (n - c, n)]
    for (sy0, sy1), (dy0, dy1) in zip(cuts, dst):
        for (sx0, sx1), (dx0, dx1) in zip(cuts, dst):
            part = img.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0), Image.LANCZOS)
            big.paste(part, (dx0, dy0))
    out = Image.new("RGBA", (n + 40, n + 40), (30, 30, 34, 255))
    out.paste(Image.alpha_composite(base, big), (20, 20))
    out.save(path)


if __name__ == "__main__":
    img = frame()
    img.save(os.path.join(OUT, "ic_minimap_square.tga"))
    if len(sys.argv) > 1:
        preview(img, sys.argv[1])
