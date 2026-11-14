"""B2: four spray-paint tags on white -> art/textures/graffiti.png.

The source is one image with a tag in each quadrant on pure white. Each tag
is cropped to its paint, its alpha taken from how far it is from white (and
its colour un-blended from the white), and the four stacked into a 512 x
1024 atlas, one 512 x 256 cell each (Graffiti3D picks a cell by row).

    python3 tools/textures/graffiti.py <source image>
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parents[2] / "art" / "textures" / "graffiti.png"
CELL = (512, 256)
ALPHA_GAIN = 3.0      # paint this far from white is fully opaque
PAINT_MIN = 0.12      # alpha below this is paper


def cut_out(tile: np.ndarray) -> Image.Image:
    rgb = tile.astype(np.float64) / 255.0
    alpha = np.clip((1.0 - rgb.min(axis=2)) * ALPHA_GAIN, 0.0, 1.0)
    alpha[alpha < PAINT_MIN] = 0.0
    safe = np.maximum(alpha, 1e-3)[..., None]
    colour = np.clip((rgb - (1.0 - alpha[..., None])) / safe, 0.0, 1.0)
    ys, xs = np.nonzero(alpha)
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    rgba = np.dstack([colour, alpha]) * 255.0
    img = Image.fromarray(rgba.astype(np.uint8), "RGBA").crop(box)
    scale = min(CELL[0] / img.width, CELL[1] / img.height) * 0.96   # fill the cell, up or down
    img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    cell = Image.new("RGBA", CELL, (0, 0, 0, 0))
    cell.paste(img, ((CELL[0] - img.width) // 2, (CELL[1] - img.height) // 2))
    return cell


def main(source: str) -> None:
    src = np.asarray(Image.open(source).convert("RGB"))
    h, w = src.shape[0] // 2, src.shape[1] // 2
    atlas = Image.new("RGBA", (CELL[0], CELL[1] * 4), (0, 0, 0, 0))
    for k in range(4):
        y, x = divmod(k, 2)
        atlas.paste(cut_out(src[y * h:(y + 1) * h, x * w:(x + 1) * w]), (0, CELL[1] * k))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(OUT, optimize=True)
    print(f"graffiti: {OUT}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
