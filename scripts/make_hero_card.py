#!/usr/bin/env python3
"""
Generate (or regenerate) a class hero-card reference image.

Hero cards are the per-class style anchors that get passed as a reference image
on every panel generation. They lock down costume, palette, and painted style
across all 12 panels of every camper in that class.

Generate ONCE per class, pre-camp. Iterate by re-running until each looks
D&D-sourcebook correct. Saved to templates/refs/{class}_hero.png.

Usage:
    python scripts/make_hero_card.py healer
    python scripts/make_hero_card.py healer --prompt "...custom override..."
    python scripts/make_hero_card.py --all          # generate all 6 at once

The auto-built prompt pulls costume + palette directly from the class YAML so
the hero card and the per-panel generations stay stylistically locked.
"""

import argparse
import os
import sys
from pathlib import Path

import yaml
from google import genai
from google.genai import types

REPO_ROOT = Path(__file__).resolve().parent.parent
PROJECT_ID = os.environ.get("GCP_PROJECT", "your-gcp-project-id")
LOCATION = os.environ.get("GCP_LOCATION", "us-central1")
MODEL = "gemini-2.5-flash-image"

CLASSES = ["druid", "warrior", "wizard", "bard", "healer", "trickster"]


def hero_card_prompt(class_data: dict) -> str:
    """Build a faceless full-body costume reference.

    The face is deliberately not shown — when this card is passed as a
    secondary reference alongside a camper's photo, no face means no
    identity contamination. The card's job is to anchor costume, palette,
    and painted style only.
    """
    palette = class_data["palette"]
    return (
        f"A heroic full-body composition of a generic {class_data['display_name']} "
        f"character in classic Dungeons & Dragons fantasy art. The figure stands "
        f"in a neutral three-quarter pose with their BACK PARTIALLY TURNED to "
        f"the camera — the head is turned away and the face is NOT visible in "
        f"the frame. This is a costume and painted-style reference only; no "
        f"face should appear anywhere in this image. "
        f"Costume: {class_data['costume']}. "
        f"Lighting and color: {palette['lighting']}, {palette['colors']}. "
        f"Style: painted digital fantasy illustration in the style of a Dungeons "
        f"& Dragons 5th Edition sourcebook, cinematic lighting, painterly "
        f"brushwork, high detail on costume textures and fabric. No text or "
        f"letters anywhere in the image. "
        f"Image aspect ratio: 2:3 portrait."
    )


def generate_one(class_name: str, custom_prompt: str | None, client) -> Path:
    yaml_path = REPO_ROOT / "templates" / f"{class_name}.yaml"
    if not yaml_path.exists():
        raise SystemExit(f"No template at {yaml_path}")
    class_data = yaml.safe_load(yaml_path.read_text())
    prompt = custom_prompt or hero_card_prompt(class_data)

    print(f"\n=== {class_name} ===")
    print(f"prompt: {prompt[:120]}...")
    response = client.models.generate_content(model=MODEL, contents=[prompt])
    for part in response.candidates[0].content.parts:
        if getattr(part, "inline_data", None):
            out = REPO_ROOT / "templates" / "refs" / f"{class_name}_hero.png"
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(part.inline_data.data)
            print(f"saved: {out}")
            return out
    raise SystemExit(f"Gemini returned no image for {class_name}")


def main() -> None:
    p = argparse.ArgumentParser()
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("class_name", nargs="?", help=f"One of: {', '.join(CLASSES)}")
    g.add_argument("--all", action="store_true", help="Generate hero cards for all 6 classes")
    p.add_argument("--prompt", help="Custom prompt override (only valid with a single class_name)")
    args = p.parse_args()

    if args.all and args.prompt:
        sys.exit("--prompt is only valid when generating a single class")

    client = genai.Client(vertexai=True, project=PROJECT_ID, location=LOCATION)

    targets = CLASSES if args.all else [args.class_name]
    for c in targets:
        try:
            out = generate_one(c, args.prompt, client)
            print(f"open {out}")
        except Exception as exc:
            print(f"  ! {c}: {exc}")

    print(f"\nDone. Review each PNG; re-run for any class you want to re-roll.")


if __name__ == "__main__":
    main()
