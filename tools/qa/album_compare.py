"""QA4: compares the photo album just taken with the approved one.

    python3 -I tools/qa/album_compare.py <approved_dir> <album_dir> [--approve]

For each <name>.png in album_dir (with its <name>.log beside it):
  FAIL     the tool crashed or timed out, logged an engine/script error, or the picture is blank
  NEW      no approved picture yet
  CHANGED  more than CHANGED_SHARE of the picture differs from the approved one;
           album_dir/changed/<name>.png shows approved | now | difference
  same     otherwise
Approved pictures are small JPEGs (debug/album/<name>.jpg) so the repo stays light.
--approve writes the pictures just taken as the new approved set (only those that did not FAIL).
"""
import re
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageOps, ImageStat

THUMB = (640, 360)          # approved pictures are stored at this size
COMPARE = (320, 180)        # and compared at this one, which hides tiny jitter
PIXEL_DIFF = 40             # 0..255: a pixel counts as changed past this
CHANGED_SHARE = 0.03        # 3% of the picture changed = worth a look
BLANK_STDDEV = 4.0          # a picture this flat is blank
ERROR = re.compile(r"^(ERROR|SCRIPT ERROR|USER ERROR|USER SCRIPT ERROR):")
EXIT_NOTES = re.compile(r"still in use at exit|leaked at exit|were leaked|in use exist at exit")


def log_problem(log: Path) -> str:
    if not log.exists():
        return "no log"
    text = log.read_text(errors="replace").splitlines()
    exit_line = next((l for l in reversed(text) if l.startswith("exit ")), "exit ?")
    code = exit_line.split()[-1]
    if code == "124":
        return "froze, killed"
    if code not in ("0", "?"):
        return f"tool exited with {code}"
    errors = [l for l in text if ERROR.match(l) and not EXIT_NOTES.search(l)]
    if errors:
        return f"{len(errors)} errors, first: {errors[0][:110]}"
    if any("_VERIFY: FAIL" in l for l in text):
        return next(l for l in text if "_VERIFY: FAIL" in l)[:140]
    return ""


def changed_share(a: Image.Image, b: Image.Image) -> float:
    a = a.convert("RGB").resize(COMPARE)
    b = b.convert("RGB").resize(COMPARE)
    diff = ImageChops.difference(a, b).convert("L")
    hist = diff.histogram()
    return sum(hist[PIXEL_DIFF:]) / (COMPARE[0] * COMPARE[1])


def side_by_side(approved: Image.Image, now: Image.Image, out: Path) -> None:
    a = approved.convert("RGB").resize(THUMB)
    b = now.convert("RGB").resize(THUMB)
    mask = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v >= PIXEL_DIFF else 0)
    red = Image.new("RGB", THUMB, (255, 40, 40))
    diff = Image.composite(red, ImageOps.grayscale(b).convert("RGB"), mask)
    sheet = Image.new("RGB", (THUMB[0] * 3, THUMB[1]))
    for i, img in enumerate((a, b, diff)):
        sheet.paste(img, (THUMB[0] * i, 0))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    approve = "--approve" in sys.argv
    approved_dir, album_dir = Path(args[0]), Path(args[1])
    rows, counts = [], {"FAIL": 0, "NEW": 0, "CHANGED": 0, "same": 0}
    names = sorted({p.stem for p in album_dir.glob("*.log")})
    for name in names:
        png, log = album_dir / f"{name}.png", album_dir / f"{name}.log"
        problem = log_problem(log)
        now = Image.open(png) if png.exists() else None
        if now is None and not problem:
            problem = "no picture written"
        if now is not None and not problem and max(ImageStat.Stat(now.convert("L")).stddev) < BLANK_STDDEV:
            problem = "the picture is blank"
        ref = approved_dir / f"{name}.jpg"
        if problem:
            status, note = "FAIL", problem
        elif not ref.exists():
            status, note = "NEW", "no approved picture yet"
        else:
            share = changed_share(Image.open(ref), now)
            if share > CHANGED_SHARE:
                status, note = "CHANGED", f"{share:.0%} of the picture differs: see changed/{name}.png"
                side_by_side(Image.open(ref), now, album_dir / "changed" / f"{name}.png")
            else:
                status, note = "same", f"{share:.1%} differs"
        counts[status] += 1
        rows.append(f"{status:8} {name:18} {note}")
        if approve and status != "FAIL" and now is not None:
            approved_dir.mkdir(parents=True, exist_ok=True)
            now.convert("RGB").resize(THUMB).save(ref, quality=82)
    summary = "  ".join(f"{k} {v}" for k, v in counts.items())
    report = "\n".join(rows + ["", summary + ("   (approved)" if approve else "")])
    (album_dir / "report.txt").write_text(report + "\n")
    print(report)
    return 1 if counts["FAIL"] else 0


if __name__ == "__main__":
    sys.exit(main())
