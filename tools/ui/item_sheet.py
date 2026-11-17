"""IC2: cuts a generated item sheet (Magnific, plain light grey background) into
bag pictures for art/ui/items/<id>.png.

    python3 -I tools/ui/item_sheet.py <sheet.png> <cols>x<rows> <id,id,...> <out_dir> [--catalog <item_catalog.gd>] [--preview <png>]

Ids go row by row; "-" skips a cell. Only background joined to the cell's edge
goes (grey metal inside an object stays), and so does the soft floor shadow
below each object. With --catalog, an item whose bag footprint is long (1x2,
2x1, 1x4) is turned so its own long axis lies along the footprint's, as
ItemArt expects. Pictures are trimmed and kept at most SIZE px on the long side.
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 256
BG_DIST = 14             # this close to the background colour = background (if joined to the edge)
SHADOW_SAT = 16          # floor shadows: hardly any colour ...
SHADOW_DARK = 90         # ... and at most this much darker than the background
TURN_MIN_DEG = 8.0
HOLE_DIST = 5            # a trapped hole is this close to the background colour ...
HOLE_PX = 11             # ... and at least this wide


def bg_colour(px: np.ndarray) -> np.ndarray:
    edge = np.concatenate([px[:4].reshape(-1, 3), px[-4:].reshape(-1, 3), px[:, :4].reshape(-1, 3), px[:, -4:].reshape(-1, 3)])
    return np.median(edge, axis=0)


def edge_joined(mask: np.ndarray) -> np.ndarray:
    """The part of `mask` that touches the image border."""
    img = Image.fromarray(np.where(mask, 255, 0).astype(np.uint8), "L").copy()   # a writable copy, or the fill does nothing
    h, w = mask.shape
    seeds = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)] + [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]
    for s in seeds:
        if img.getpixel(s) == 255:
            ImageDraw.floodfill(img, s, 128)
    return np.asarray(img) == 128


def cut_out(cell: Image.Image) -> Image.Image:
    px = np.asarray(cell.convert("RGB"), dtype=np.float32)
    bg = bg_colour(px)
    dist = np.abs(px - bg).max(axis=2)
    sat = px.max(axis=2) - px.min(axis=2)
    darker = bg.mean() - px.mean(axis=2)
    shadow = (sat < SHADOW_SAT) & (darker > -10) & (darker < SHADOW_DARK)
    near = dist < BG_DIST
    strict = edge_joined(near)                       # plain background joined to the edge
    loose = edge_joined(near | shadow)               # ... plus the soft grey floor shadows
    # A shadow only counts as ground below the object's lowest solid pixel in its column
    # (grey wrappers and metal joined to a shadow stay).
    core = ~loose
    rows = np.arange(px.shape[0])[:, None]
    lowest = np.where(core.any(axis=0), px.shape[0] - 1 - np.argmax(core[::-1], axis=0), -1)
    ground = strict | (loose & (rows > lowest[None, :]))
    # Background trapped inside a ring (headphones, a chain): a wide patch of exactly that grey.
    flat = Image.fromarray(np.where(dist < HOLE_DIST, 255, 0).astype(np.uint8), "L")
    flat = flat.filter(ImageFilter.MinFilter(HOLE_PX)).filter(ImageFilter.MaxFilter(HOLE_PX))
    ground |= np.asarray(flat) > 0
    a = np.where(ground, 0.0, 255.0)   # everything inside an object stays solid; the blur softens the edge
    alpha = Image.fromarray(a.astype(np.uint8), "L").filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    al = np.asarray(alpha).astype(np.float32)[:, :, None] / 255.0
    clean = np.where(al > 0.02, (px - (1.0 - al) * bg) / np.maximum(al, 0.02), px)   # no grey halo on dark tiles
    out = Image.fromarray(np.clip(clean, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    out.putalpha(alpha)
    box = alpha.point(lambda v: 255 if v > 40 else 0).getbbox()
    return out.crop(box) if box else out


def long_axis_deg(icon: Image.Image) -> float:
    """Angle of the object's long axis, 0 = across, 90 = upright (image y down)."""
    a = np.asarray(icon.getchannel("A")) > 128
    ys, xs = np.nonzero(a)
    if xs.size < 10:
        return 0.0
    cov = np.cov(np.vstack([xs - xs.mean(), ys - ys.mean()]))
    vals, vecs = np.linalg.eigh(cov)
    v = vecs[:, np.argmax(vals)]
    return float(np.degrees(np.arctan2(v[1], v[0])))


def orient(icon: Image.Image, size: tuple) -> Image.Image:
    w, h = size
    if w == h:
        return icon
    ang = long_axis_deg(icon)
    target = 0.0 if w > h else 90.0
    turn = ((ang - target + 90.0) % 180.0) - 90.0     # smallest turn onto the target axis
    if abs(turn) < TURN_MIN_DEG:
        return icon
    out = icon.rotate(turn, resample=Image.BICUBIC, expand=True)   # PIL turns anticlockwise; y is down
    box = out.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
    return out.crop(box) if box else out


def fit(icon: Image.Image) -> Image.Image:
    k = SIZE / max(icon.size)
    if k >= 1.0:
        return icon
    return icon.resize((max(1, round(icon.width * k)), max(1, round(icon.height * k))), Image.LANCZOS)


def footprints(catalog: str) -> dict:
    text = Path(catalog).read_text()
    return {m[0]: (int(m[1]), int(m[2])) for m in re.findall(r'^\t&"(\w+)":\s*\{"size": Vector2i\((\d+), (\d+)\)', text, re.M)}


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {sys.argv[i][2:]: sys.argv[i + 1] for i in range(1, len(sys.argv) - 1) if sys.argv[i].startswith("--")}
    args = [a for a in args if a not in flags.values()]
    sheet = Image.open(args[0])
    cols, rows = (int(v) for v in args[1].split("x"))
    names = args[2].split(",")
    out = Path(args[3])
    out.mkdir(parents=True, exist_ok=True)
    feet = footprints(flags["catalog"]) if "catalog" in flags else {}
    cw, ch = sheet.width / cols, sheet.height / rows
    made = []
    for i, name in enumerate(names):
        if name == "-":
            continue
        c, r = i % cols, i // cols
        cell = sheet.crop((round(c * cw), round(r * ch), round((c + 1) * cw), round((r + 1) * ch)))
        icon = fit(orient(cut_out(cell), feet.get(name, (1, 1))))
        icon.save(out / f"{name}.png")
        made.append((name, icon))
    if "preview" in flags:   # on the bag's dark tiles, big and at about the real size
        board = Image.new("RGBA", (cols * 140 + 20, rows * 140 + 20), (40, 38, 36, 255))
        for k, (name, icon) in enumerate(made):
            w, h = feet.get(name, (1, 1))
            box = (130 * w // max(w, h), 130 * h // max(w, h))
            s = min(box[0] / icon.width, box[1] / icon.height)
            small = icon.resize((max(1, int(icon.width * s)), max(1, int(icon.height * s))), Image.LANCZOS)
            board.paste(small, (10 + (k % cols) * 140, 10 + (k // cols) * 140), small)
        board.save(flags["preview"])
    print(f"{len(made)} pictures -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
