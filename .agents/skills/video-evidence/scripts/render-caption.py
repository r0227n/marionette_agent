#!/usr/bin/env python3
"""Render literal UTF-8 captions with an explicit font; no window server needed."""

import argparse
import io
from pathlib import Path
import sys
import unicodedata


def render(args):
    try:
        from PIL import Image, ImageDraw, ImageFont
        from fontTools.ttLib import TTFont, TTLibError
    except ImportError as error:
        raise ValueError("Install Pillow and fonttools in the editing environment") from error

    size = args.font_size if args.font_size is not None else max(16, min(160, args.width // 22))
    if not (320 <= args.width <= 4096 and 200 <= args.height <= 8192):
        raise ValueError("Width must be 320..4096 and height 200..8192 pixels")
    if not 16 <= size <= 160 or args.font_index < 0:
        raise ValueError("Font size must be 16..160 and font index nonnegative")
    if not args.text.is_file() or not args.font.is_file():
        raise ValueError("Text and font must be local regular files")
    if args.output.exists() or args.output.is_symlink():
        raise ValueError("Output must be a new file")
    text = unicodedata.normalize("NFC", args.text.read_text(encoding="utf-8"))
    if not text.strip() or len(text) > 8192:
        raise ValueError("Caption must contain 1..8192 characters")
    if any(unicodedata.category(c).startswith("C") for c in text if c != "\n"):
        raise ValueError("Control/format characters other than newlines are unsupported")

    try:
        with TTFont(str(args.font), fontNumber=args.font_index) as face:
            cmap = face.getBestCmap() or {}
            missing = sorted({ord(c) for c in text if c != "\n" and ord(c) not in cmap})
    except TTLibError as error:
        raise ValueError("Cannot load the requested font face") from error
    if missing:
        points = ", ".join(f"U+{point:04X}" for point in missing[:12])
        raise ValueError(f"Font lacks characters: {points}; choose a font covering the caption")
    font = ImageFont.truetype(str(args.font), size, index=args.font_index)
    margin = max(16, round(args.width * 0.03))
    available_width = args.width - 2 * margin

    # Wrap on measured glyph bounds, keeping combining marks with their base.
    lines = []
    for paragraph in text.split("\n"):
        clusters = []
        for character in paragraph:
            if clusters and unicodedata.combining(character):
                clusters[-1] += character
            else:
                clusters.append(character)
        line = ""
        for cluster in clusters:
            left, _, right, _ = font.getbbox(line + cluster)
            if right - left > available_width:
                if not line:
                    raise ValueError("A character exceeds the caption width")
                lines.append(line)
                line = ""
            line += cluster
        lines.append(line)

    image = Image.new("RGB", (args.width, args.height), (14, 20, 33))
    draw = ImageDraw.Draw(image)
    wrapped = "\n".join(lines)
    spacing = max(4, size // 4)
    left, top, right, bottom = draw.multiline_textbbox(
        (0, 0), wrapped, font=font, spacing=spacing
    )
    content_top = margin + 20
    available_height = args.height - margin - content_top
    if right - left > available_width or bottom - top > available_height:
        raise ValueError("Caption overflows; shorten it or adjust its rectangle/font size")
    draw.rectangle((margin, margin, args.width - margin - 1, margin + 7), fill=(64, 217, 235))
    draw.multiline_text(
        (margin - left, content_top + (available_height - (bottom - top)) // 2 - top),
        wrapped, font=font, spacing=spacing, fill="white"
    )
    encoded = io.BytesIO()
    image.save(encoded, format="PNG")
    with args.output.open("xb") as output:
        output.write(encoded.getvalue())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("width", type=int)
    parser.add_argument("height", type=int)
    parser.add_argument("text", type=Path, help="UTF-8 text file")
    parser.add_argument("output", type=Path, help="New PNG path")
    parser.add_argument("--font", type=Path, required=True, help="Local TTF/OTF/TTC font")
    parser.add_argument("--font-index", type=int, default=0, help="TTC face index")
    parser.add_argument("--font-size", type=int, help="Pixel size (16..160)")
    args = parser.parse_args()
    try:
        render(args)
    except (OSError, ValueError) as error:
        print(f"caption: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
