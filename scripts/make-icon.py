#!/usr/bin/env python3
"""Renders Kept's app icon from Resources/Icon/*.svg into Resources/AppIcon.icns.

    scripts/make-icon.py                 # writes Resources/AppIcon.icns
    scripts/make-icon.py --iconset DIR   # also keeps the PNGs (AppIcon.iconset layout)

Sources: AppIcon.svg draws 64 px and up; AppIcon-32.svg and AppIcon-16.svg
are hinted twins for the small sizes. Needs Python 3 with Pillow and CairoSVG
(`pip install pillow cairosvg`; on macOS CairoSVG also needs `brew install
cairo`). Uses `iconutil` when it exists (macOS) and otherwise writes the
.icns itself, so it runs on Linux too. The result is committed, so `make app`
needs none of this.
"""

from __future__ import annotations

import argparse
import io
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    import cairosvg
    from PIL import Image
except ImportError as error:
    sys.exit(f"error: {error.name} is missing. Run: pip install pillow cairosvg")

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Resources" / "Icon"
OUTPUT = ROOT / "Resources" / "AppIcon.icns"

# iconutil's file names -> (pixel size, source SVG).
ICONSET = {
    "icon_16x16.png": (16, "AppIcon-16.svg"),
    "icon_16x16@2x.png": (32, "AppIcon-32.svg"),
    "icon_32x32.png": (32, "AppIcon-32.svg"),
    "icon_32x32@2x.png": (64, "AppIcon.svg"),
    "icon_128x128.png": (128, "AppIcon.svg"),
    "icon_128x128@2x.png": (256, "AppIcon.svg"),
    "icon_256x256.png": (256, "AppIcon.svg"),
    "icon_256x256@2x.png": (512, "AppIcon.svg"),
    "icon_512x512.png": (512, "AppIcon.svg"),
    "icon_512x512@2x.png": (1024, "AppIcon.svg"),
}

# PNG-encoded .icns entries (macOS 10.7+) for the fallback writer.
PNG_TYPES = {
    "icon_16x16@2x.png": b"ic11",
    "icon_32x32@2x.png": b"ic12",
    "icon_128x128.png": b"ic07",
    "icon_128x128@2x.png": b"ic13",
    "icon_256x256.png": b"ic08",
    "icon_256x256@2x.png": b"ic14",
    "icon_512x512.png": b"ic09",
    "icon_512x512@2x.png": b"ic10",
}
# 16 and 32 px at 1x use the classic RLE RGB + 8-bit mask pairs, which every
# macOS version reads.
RGB_TYPES = {
    "icon_16x16.png": (b"is32", b"s8mk"),
    "icon_32x32.png": (b"il32", b"l8mk"),
}


def render(svg: Path, size: int) -> bytes:
    return cairosvg.svg2png(url=str(svg), output_width=size, output_height=size)


def packbits(channel: bytes) -> bytes:
    """The .icns run-length encoding: 0x00-0x7F = n+1 literal bytes follow,
    0x80-0xFF = the next byte repeats n-125 times (3...130)."""
    out = bytearray()
    literal = bytearray()
    i, n = 0, len(channel)
    while i < n:
        run = 1
        while i + run < n and run < 130 and channel[i + run] == channel[i]:
            run += 1
        if run >= 3:
            if literal:
                out += bytes([len(literal) - 1]) + literal
                literal.clear()
            out += bytes([run + 125, channel[i]])
            i += run
        else:
            literal.append(channel[i])
            i += 1
            if len(literal) == 128:
                out += bytes([127]) + literal
                literal.clear()
    if literal:
        out += bytes([len(literal) - 1]) + literal
    return bytes(out)


def rgb_entries(png: bytes) -> tuple[bytes, bytes]:
    image = Image.open(io.BytesIO(png)).convert("RGBA")
    r, g, b, a = image.split()
    rgb = b"".join(packbits(channel.tobytes()) for channel in (r, g, b))
    return rgb, a.tobytes()


def write_icns(pngs: dict[str, bytes], path: Path) -> None:
    entries: list[tuple[bytes, bytes]] = []
    for name, (rgb_type, mask_type) in RGB_TYPES.items():
        rgb, mask = rgb_entries(pngs[name])
        entries += [(rgb_type, rgb), (mask_type, mask)]
    entries += [(kind, pngs[name]) for name, kind in PNG_TYPES.items()]

    toc = b"".join(kind + struct.pack(">I", 8 + len(data)) for kind, data in entries)
    body = b"TOC " + struct.pack(">I", 8 + len(toc)) + toc
    body += b"".join(kind + struct.pack(">I", 8 + len(data)) + data for kind, data in entries)
    path.write_bytes(b"icns" + struct.pack(">I", 8 + len(body)) + body)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--iconset", type=Path, help="also write the PNGs to this .iconset folder")
    parser.add_argument("--output", type=Path, default=OUTPUT, help=f"default: {OUTPUT.relative_to(ROOT)}")
    args = parser.parse_args()

    pngs: dict[str, bytes] = {}
    for name, (size, source) in ICONSET.items():
        pngs[name] = render(SOURCES / source, size)
        print(f"    {name:22} {size:>4} px  from {source}")

    with tempfile.TemporaryDirectory() as temp:
        iconset = args.iconset or Path(temp) / "AppIcon.iconset"
        iconset.mkdir(parents=True, exist_ok=True)
        for name, data in pngs.items():
            (iconset / name).write_bytes(data)

        if shutil.which("iconutil"):
            subprocess.run(["iconutil", "-c", "icns", "-o", str(args.output), str(iconset)], check=True)
            how = "iconutil"
        else:
            write_icns(pngs, args.output)
            how = "built-in writer"

    print(f"==> Wrote {args.output} ({args.output.stat().st_size // 1024} KB, {how})")


if __name__ == "__main__":
    main()
