"""Build the Pocket TTS Windows icon from simple vector shapes."""

from pathlib import Path
from math import hypot
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
SIZE = 512


def stitch(draw: ImageDraw.ImageDraw, points: list[tuple[int, int]], color: str, width: int = 7) -> None:
    for start, end in zip(points, points[1:]):
        dx, dy = end[0] - start[0], end[1] - start[1]
        length = hypot(dx, dy)
        if not length:
            continue
        step = 18
        for offset in range(0, int(length), step):
            stop = min(offset + 10, length)
            a = (round(start[0] + dx * offset / length), round(start[1] + dy * offset / length))
            b = (round(start[0] + dx * stop / length), round(start[1] + dy * stop / length))
            draw.line((a, b), fill=color, width=width)


image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(image)

# A dark tile gives the blue denim pocket a recognizable silhouette at 16 px.
draw.rounded_rectangle((20, 20, 492, 492), radius=112, fill="#102649")
draw.rounded_rectangle((29, 29, 483, 483), radius=105, outline="#274b79", width=7)

outer = [(92, 137), (420, 137), (403, 354), (256, 436), (109, 354)]
draw.polygon(outer, fill="#287bd2")
draw.line(outer + [outer[0]], fill="#0a4c9d", width=12, joint="curve")

# Folded opening, denim weave, metal rivets, and pale double stitching.
draw.polygon([(92, 137), (420, 137), (414, 187), (98, 187)], fill="#1664b6")
draw.line([(101, 179), (411, 179)], fill="#66b6f2", width=7)
stitch(draw, [(122, 205), (137, 337), (256, 404), (375, 337), (390, 205)], "#c7eaff", 7)
stitch(draw, [(136, 225), (256, 284), (376, 225)], "#a9daf9", 6)
draw.ellipse((113, 153, 139, 179), fill="#eef7ff", outline="#5c9ad0", width=3)
draw.ellipse((373, 153, 399, 179), fill="#eef7ff", outline="#5c9ad0", width=3)

ASSETS.mkdir(exist_ok=True)
image.save(ASSETS / "pockettts-pocket.png")
image.save(
    ASSETS / "pockettts-pocket.ico",
    format="ICO",
    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)
print(ASSETS / "pockettts-pocket.ico")
