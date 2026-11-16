"""IC1: cuts a generated 4 x 3 icon sheet (Magnific) into the mood icons.

    python3 -I tools/ui/icon_sheet.py <sheet.png|jpg> <out_dir> [--preview <png>]

The sheet is 12 icons on a plain white background, in this order (rows of 4):
hunger thirst fatigue health / calm well_fed bleeding wanted / warrant heavy breath eye.
Each cell: the white background becomes transparent (soft edge, the floor shadow
fades out), the icon is trimmed, squared and saved as <out_dir>/<name>.png at 96 px.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageFilter

NAMES = ["hunger", "thirst", "fatigue", "health",
         "calm", "well_fed", "bleeding", "wanted",
         "warrant", "heavy", "breath", "eye"]
COLS, ROWS = 4, 3
SIZE = 96
PAD = 4                  # px of air round the icon in the 96 px square
WHITE_FROM = 232         # this bright and greyish = background
EDGE_SOFT = 22           # alpha ramps up over this many levels below WHITE_FROM
SHADOW_SAT = 14          # floor shadows: hardly any colour ...
SHADOW_BRIGHT = 105      # ... and lighter than a dark object (only ground joined to the edge goes)


def cut_out(cell: Image.Image) -> Image.Image:
    rgb = cell.convert("RGB")
    # How far each pixel is from white, colour included (a pale pink lung is not background).
    dist = ImageChops.difference(rgb, Image.new("RGB", rgb.size, (255, 255, 255))).convert("L")
    alpha = dist.point(lambda d: 0 if d < 255 - WHITE_FROM else min(255, int((d - (255 - WHITE_FROM)) * 255 / EDGE_SOFT)))
    # The soft floor shadow under each icon is light and colourless: background too
    # (a dark object, even a black one, is far below SHADOW_BRIGHT).
    px = np.asarray(rgb, dtype=np.int16)
    sat = px.max(axis=2) - px.min(axis=2)
    a = np.asarray(alpha).copy()
    open_ground = ((sat < SHADOW_SAT) & (px.mean(axis=2) > SHADOW_BRIGHT)) | (a == 0)
    # A floor shadow lies below the object: only grey ground below the lowest solid
    # pixel of its column goes. Grey metal, eye whites and paper have more of the
    # icon under them and stay.
    solid = (a > 0) & ~open_ground
    rows = np.arange(a.shape[0])[:, None]
    lowest = np.where(solid.any(axis=0), a.shape[0] - 1 - np.argmax(solid[::-1], axis=0), -1)
    a[open_ground & (rows > lowest[None, :])] = 0
    alpha = Image.fromarray(a.astype(np.uint8), "L")
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    box = alpha.point(lambda a: 255 if a > 40 else 0).getbbox()
    return out.crop(box) if box else out


def square(icon: Image.Image) -> Image.Image:
    inner = SIZE - 2 * PAD
    scale = inner / max(icon.size)
    icon = icon.resize((max(1, round(icon.width * scale)), max(1, round(icon.height * scale))), Image.LANCZOS)
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    canvas.paste(icon, ((SIZE - icon.width) // 2, (SIZE - icon.height) // 2), icon)
    return canvas


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    sheet = Image.open(args[0])
    out = Path(args[1])
    out.mkdir(parents=True, exist_ok=True)
    preview = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else ""
    cw, ch = sheet.width / COLS, sheet.height / ROWS
    icons = []
    for i, name in enumerate(NAMES):
        c, r = i % COLS, i // COLS
        cell = sheet.crop((round(c * cw), round(r * ch), round((c + 1) * cw), round((r + 1) * ch)))
        icon = square(cut_out(cell))
        icon.save(out / f"{name}.png")
        icons.append(icon)
    if preview:   # how they read on the game's dark tiles, big and at the real 20-30 px
        board = Image.new("RGBA", (COLS * 110 + 20, ROWS * 110 + 70), (40, 38, 36, 255))
        for i, icon in enumerate(icons):
            board.paste(icon, (10 + (i % COLS) * 110, 10 + (i // COLS) * 110), icon)
            small = icon.resize((28, 28), Image.LANCZOS)
            board.paste(small, (10 + i * 36, ROWS * 110 + 25), small)
        board.save(preview)
    print(f"{len(icons)} icons -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
