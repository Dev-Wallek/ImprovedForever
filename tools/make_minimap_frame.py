"""The square minimap's mitred corners (Minimap.lua, the Square minimap
setting): masks, each one triangle of a square cut along a diagonal, so the
two bands meeting at a corner each fill their own half.

  ic_minimap_miter_ur / _ul / _lr / _ll   16 x 16, white, the triangle
  in the named corner opaque

Run: python3 tools/make_minimap_frame.py   (needs Pillow)
"""
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "ImprovedForever", "textures")
SIZE, SS = 16, 8

TRIANGLES = {
    "ur": [(0, 0), (1, 0), (1, 1)],
    "ll": [(0, 0), (0, 1), (1, 1)],
    "ul": [(0, 0), (1, 0), (0, 1)],
    "lr": [(1, 0), (1, 1), (0, 1)],
}

for name, points in TRIANGLES.items():
    n = SIZE * SS
    alpha = Image.new("L", (n, n), 0)
    ImageDraw.Draw(alpha).polygon([(x * n, y * n) for x, y in points], fill=255)
    img = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 255))
    img.putalpha(alpha.resize((SIZE, SIZE), Image.LANCZOS))
    img.save(os.path.join(OUT, "ic_minimap_miter_" + name + ".tga"))
