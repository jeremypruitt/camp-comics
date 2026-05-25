#!/usr/bin/env python3
"""
Camp Comics — Stage 3 render script.

Fills layout/comic.html.j2 from a camper's manifest + cabinmates' manifests,
renders to outputs/{id}/comic.pdf via WeasyPrint.

Usage:
    python scripts/render.py --camper camper_042
    python scripts/render.py --all

Prerequisites:
    pip install jinja2 weasyprint
"""

import argparse
import json
import sys
from pathlib import Path

from jinja2 import Environment, FileSystemLoader
from PIL import Image, ImageDraw
from weasyprint import HTML

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUTS = REPO_ROOT / "outputs"
LAYOUT = REPO_ROOT / "layout"

# Override per camp.
CAMP_NAME = "Camp Eldermoot"
WEEK_LABEL = "Summer 2026"


def collect_cabin_members(my_manifest: dict) -> list[dict]:
    """Find all campers sharing this cabin; gather their roster info."""
    cabin = my_manifest.get("cabin")
    if not cabin:
        return []

    members = []
    for cd in OUTPUTS.iterdir():
        if not cd.is_dir():
            continue
        m_path = cd / "manifest.json"
        hero_path = cd / "panel_04.png"
        if not m_path.exists() or not hero_path.exists():
            continue
        m = json.loads(m_path.read_text())
        if m.get("cabin") != cabin:
            continue
        members.append({
            "character_name": m["character_name"],
            "class": m["class"],
            "hero_image": str(hero_path.relative_to(REPO_ROOT)),
        })
    members.sort(key=lambda x: x["character_name"])
    return members


# Container aspect ratio for the diagonal pair cell. Computed from the
# CSS: page is 6.625in × 10.25in with 0.3in interior padding, so the grid
# is 6.025in wide × 9.65in tall. Row 2 of the act-III grid is 1fr of
# 3.5fr total, so ~2.76in tall. Aspect ≈ 6.025 / 2.76 ≈ 2.18.
# If you change the CSS row sizes, update this.
DIAGONAL_PAIR_ASPECT = 2.18


def _crop_to_aspect(img: Image.Image, target_aspect: float) -> Image.Image:
    """Crop to target aspect ratio, preserving the top portion (faces)."""
    w, h = img.size
    if w / h > target_aspect:
        new_w = int(h * target_aspect)
        offset = (w - new_w) // 2
        return img.crop((offset, 0, offset + new_w, h))
    if w / h < target_aspect:
        new_h = int(w / target_aspect)
        return img.crop((0, 0, w, new_h))  # keep top
    return img


def _make_diagonal_pair_images(camper_dir: Path) -> None:
    """Pre-process panels 10 and 11 with alpha-masked trapezoid shapes.

    WeasyPrint 68 doesn't reliably support clip-path, mask-image, or SVG
    clipPath — but it always renders alpha-channel PNGs correctly. So we
    bake the trapezoid masks directly into the PNG alpha here. The HTML
    just overlays two PNGs with transparent backgrounds; together they
    tile the row with a clean diagonal seam.

    Left  trapezoid: (0,0) → (70%,0) → (30%,100) → (0,100)
    Right trapezoid: (70%,0) → (100%,0) → (100%,100) → (30%,100)
    Both share the diagonal from (70%,0) to (30%,100) — same line, so the
    two shapes meet edge-to-edge with no gap and no overlap.
    """
    p10_path = camper_dir / "panel_10.png"
    p11_path = camper_dir / "panel_11.png"
    if not p10_path.exists() or not p11_path.exists():
        return  # one or both panels missing/skipped; HTML will fall back

    p10 = Image.open(p10_path).convert("RGBA")
    p11 = Image.open(p11_path).convert("RGBA")

    # Pre-crop both source images to the container's aspect ratio. Without
    # this, object-fit:cover at display time would crop ~18% off the bottom
    # of a 16:9 source landing in a 2.18:1 cell, hiding our bottom border.
    p10 = _crop_to_aspect(p10, DIAGONAL_PAIR_ASPECT)
    p11 = _crop_to_aspect(p11, DIAGONAL_PAIR_ASPECT)

    # Common canvas — use the larger of each dimension so neither image upsizes more than needed.
    w = max(p10.width, p11.width)
    h = max(p10.height, p11.height)
    if (p10.width, p10.height) != (w, h):
        p10 = p10.resize((w, h), Image.LANCZOS)
    if (p11.width, p11.height) != (w, h):
        p11 = p11.resize((w, h), Image.LANCZOS)

    # Diagonal split, gentler than before (60%→40%). Cream gap between
    # the two trapezoids is 2.7% horizontal — matches the 0.16in grid gap
    # between every other panel pair (0.16 / 6.025in ≈ 0.027).
    #
    # Left trapezoid:  (0,0)    - (58.65%,0) - (38.65%,h) - (0,h)
    # Right trapezoid: (61.35%,0) - (w,0)    - (w,h)     - (41.35%,h)
    l_top, l_bot = int(w * 0.5865), int(w * 0.3865)
    r_top, r_bot = int(w * 0.6135), int(w * 0.4135)

    stroke_color = (42, 31, 21, 255)  # #2a1f15 — matches panel border color
    stroke_width = max(3, int(w * 0.003))  # ~1pt at display scale
    half = stroke_width // 2

    # Draw all four edges of each trapezoid so the borders match the rest
    # of the comic (every panel has a 1pt border on all sides). Each line
    # is shifted inward by half the stroke width so the full weight stays
    # inside the visible trapezoid (the alpha mask trims anything outside).
    # The 4% cream gap between trapezoids means the top/bottom edges of
    # each are visually distinct, not one continuous line across the row.

    def draw_trapezoid_border(img, edges):
        for (x0, y0), (x1, y1) in edges:
            ImageDraw.Draw(img).line(
                [(x0, y0), (x1, y1)],
                fill=stroke_color, width=stroke_width,
            )

    # LEFT trapezoid edges (inward-shifted)
    draw_trapezoid_border(p10, [
        ((half,         half),     (l_top - half, half)),         # top
        ((l_top - half, half),     (l_bot - half, h - half)),     # diagonal
        ((l_bot - half, h - half), (half,         h - half)),     # bottom
        ((half,         h - half), (half,         half)),         # left (outer)
    ])
    left_mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(left_mask).polygon(
        [(0, 0), (l_top, 0), (l_bot, h), (0, h)], fill=255,
    )
    p10.putalpha(left_mask)
    p10.save(camper_dir / "_diag_left.png")

    # RIGHT trapezoid edges (mirrored)
    draw_trapezoid_border(p11, [
        ((r_top + half, half),     (w - half,     half)),         # top
        ((w - half,     half),     (w - half,     h - half)),     # right (outer)
        ((w - half,     h - half), (r_bot + half, h - half)),     # bottom
        ((r_bot + half, h - half), (r_top + half, half)),         # diagonal
    ])
    right_mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(right_mask).polygon(
        [(r_top, 0), (w, 0), (w, h), (r_bot, h)], fill=255,
    )
    p11.putalpha(right_mask)
    p11.save(camper_dir / "_diag_right.png")


def render_camper(camper_id: str) -> Path:
    camper_dir = OUTPUTS / camper_id
    manifest = json.loads((camper_dir / "manifest.json").read_text())

    # Bake the diagonal trapezoid masks into PNG alpha (panels 10 & 11).
    _make_diagonal_pair_images(camper_dir)

    env = Environment(loader=FileSystemLoader(str(LAYOUT)))
    html_str = env.get_template("comic.html.j2").render(
        character_name=manifest["character_name"],
        camp_name=CAMP_NAME,
        week_label=WEEK_LABEL,
        cabin=manifest["cabin"],
        captions=manifest["captions"],
        panel_dir=str(camper_dir.relative_to(REPO_ROOT)),
        cover_image=str((camper_dir / "cover.png").relative_to(REPO_ROOT)),
        cabin_members=collect_cabin_members(manifest),
    )

    pdf_path = camper_dir / "comic.pdf"
    HTML(string=html_str, base_url=str(REPO_ROOT)).write_pdf(str(pdf_path))
    return pdf_path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--camper", help="Camper ID")
    parser.add_argument("--all", action="store_true",
                        help="Render every camper with a manifest")
    args = parser.parse_args()

    if args.all:
        ids = [d.name for d in OUTPUTS.iterdir()
               if d.is_dir() and (d / "manifest.json").exists()]
    elif args.camper:
        ids = [args.camper]
    else:
        sys.exit("Specify --camper {id} or --all")

    for cid in ids:
        try:
            pdf = render_camper(cid)
            print(f"  rendered: {pdf}")
        except Exception as exc:
            print(f"  ! failed {cid}: {exc}")


if __name__ == "__main__":
    main()
