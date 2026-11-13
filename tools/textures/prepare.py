"""TX1: turn raw texture images into the game's detail maps.

Each output is art/textures/<name>.png: 512 x 512 greyscale, tileable, its
lighting flattened (a high-pass), mean grey 0.5 and the same contrast for
every material, so the shader can lay any of them over a flat colour.

    python3 tools/textures/prepare.py <dir with raw PNGs>

Raw files are matched by the Magnific creation id at the end of their name
(see SOURCES). The sidewalk is drawn here (square slabs with joints), since
generating it kept failing.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parents[2] / "art" / "textures"
SIZE = 512
CONTRAST = 0.16          # standard deviation of every map around 0.5
FLATTEN_FRACTION = 0.12  # lighting broader than this share of the image is removed
SEAM_RATIO = 1.6         # an edge this much rougher than the inside gets blended
SOURCES = {
    "rgeGlmdxtc": "stucco", "gOI0JHXSXO": "brick", "nVjuT9XYQD": "block",
    "0egqpZMTfW": "clay", "huRwEd5vqL": "shingle", "6AHI2OniJO": "gravel",
    "If6gaXJtvE": "asphalt", "eIOr8egdqL": "grass", "jUXnUsuLD0": "dirt",
    "s7oW7UTl8e": "wood", "N2F822W6D9": "tile", "LwBYZGoswO": "carpet",
}
SLAB_M = 1.5             # sidewalk slab size; the map covers 3 m (SurfaceDetail.TILE_M)
SIDEWALK_M = 3.0


def periodic_blur(img: np.ndarray, sigma: float) -> np.ndarray:
    """Gaussian blur that wraps round the edges (FFT), so tiling survives."""
    h, w = img.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    kernel = np.exp(-2.0 * (np.pi * sigma) ** 2 * (fx ** 2 + fy ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(img) * kernel))


def seam_score(img: np.ndarray) -> float:
    """How much rougher the wrap-round edges are than the inside."""
    inside = np.mean(np.abs(np.diff(img, axis=1))) + np.mean(np.abs(np.diff(img, axis=0)))
    edges = np.mean(np.abs(img[:, 0] - img[:, -1])) + np.mean(np.abs(img[0, :] - img[-1, :]))
    return float(edges / max(inside, 1e-6))


def make_tileable(img: np.ndarray) -> np.ndarray:
    """Cross-fade with a half-shifted copy: each copy hides the other's seam."""
    h, w = img.shape
    shifted = np.roll(img, (h // 2, w // 2), axis=(0, 1))
    wy = np.sin(np.linspace(0.0, np.pi, h))[:, None]
    wx = np.sin(np.linspace(0.0, np.pi, w))[None, :]
    weight = np.minimum(wy, wx) ** 0.5
    return img * weight + shifted * (1.0 - weight)


def normalise(img: np.ndarray) -> np.ndarray:
    flat = img - periodic_blur(img, img.shape[0] * FLATTEN_FRACTION)
    flat = (flat - flat.mean()) / max(float(flat.std()), 1e-6)
    return np.clip(0.5 + flat * CONTRAST, 0.0, 1.0)


def to_png(img: np.ndarray, name: str) -> None:
    out = Image.fromarray((img * 255.0 + 0.5).astype(np.uint8), mode="L")
    if out.size != (SIZE, SIZE):
        out = out.resize((SIZE, SIZE), Image.LANCZOS)
    OUT.mkdir(parents=True, exist_ok=True)
    out.save(OUT / f"{name}.png", optimize=True)


def prepare(path: Path, name: str) -> str:
    grey = np.asarray(Image.open(path).convert("L"), dtype=np.float64) / 255.0
    score = seam_score(grey)
    if score > SEAM_RATIO:
        grey = make_tileable(grey)
    to_png(normalise(grey), name)
    return f"{name}: seam {score:.2f}{' (blended)' if score > SEAM_RATIO else ''}"


def sidewalk(seed: int = 7) -> None:
    """Grey concrete: fine grain, a tone per slab, dark joints every SLAB_M."""
    rng = np.random.default_rng(seed)
    px_per_m = SIZE / SIDEWALK_M
    grain = periodic_blur(rng.normal(size=(SIZE, SIZE)), 1.0)
    blotch = periodic_blur(rng.normal(size=(SIZE, SIZE)), 24.0) * 14.0
    img = grain / grain.std() * 0.22 + blotch
    slab = int(SLAB_M * px_per_m)
    tones = rng.normal(size=(SIZE // slab, SIZE // slab)) * 0.6
    img += np.kron(tones, np.ones((slab, slab)))[:SIZE, :SIZE]
    joint = np.zeros(SIZE, dtype=bool)
    joint[np.r_[0:2, slab - 1:slab + 1, SIZE - 1]] = True
    img[joint, :] -= 4.0
    img[:, joint] -= 4.0
    to_png(normalise(img), "sidewalk")


def main(raw_dir: str) -> None:
    for path in sorted(Path(raw_dir).glob("*.png")):
        match = [ident for ident in SOURCES if path.stem.endswith(ident)]
        if match:
            print(prepare(path, SOURCES[match[0]]))
    sidewalk()
    print("sidewalk: drawn")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
