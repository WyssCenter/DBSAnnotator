"""Render the Wyss Center logo into every raster the app and the docs need.

Run by hand and commit the output, the same way the launcher icons are handled:

    uv run --no-project --with pymupdf --with pillow \\
        python tool/build_brand_assets.py

`assets/brand/*.svg` are the masters. Everything under `assets/icon/` and the
docs logo and favicons are generated from them, so the mark is never traced by
hand and the two never drift.

Only the black master is rasterised. Its ink coverage becomes an alpha mask and
the colour is painted through it, so a white or tinted variant needs no second
render and cannot disagree with the black one about geometry. It also avoids
depending on how the renderer resolves the CSS class that carries the fill.

PyMuPDF ships a prebuilt wheel and reads SVG directly. cairosvg and reportlab's
renderPM both need libcairo, which is absent on Windows, and neither
ImageMagick nor Inkscape is installed.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import pymupdf
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "assets" / "brand" / "wyss-center-black.svg"

# The circular mark occupies the left square of the lockup canvas: the wordmark
# starts at x = 236.93, so cropping the viewBox is lossless and needs no
# redrawing.
MARK_VIEWBOX = (0, 0, 176, 176)
LOCKUP_ASPECT = 1134.22 / 176

BLACK = (0, 0, 0)
WHITE = (255, 255, 255)

# Rendered at this multiple and downsampled, because the mark carries hairline
# circuit traces that alias badly at icon sizes.
SUPERSAMPLE = 4


def _ink_mask(viewbox: tuple[int, int, int, int] | None, width: int, height: int) -> Image.Image:
    """Ink coverage of the master as an 8-bit mask, antialiasing included."""
    svg = MASTER.read_text(encoding="utf-8")
    if viewbox is not None:
        x, y, w, h = viewbox
        svg = re.sub(r'viewBox="[^"]+"', f'viewBox="{x} {y} {w} {h}"', svg, count=1)
        svg = svg.replace("<svg ", f'<svg width="{w}" height="{h}" ', 1)

    with pymupdf.open(stream=svg.encode("utf-8"), filetype="svg") as doc:
        page = doc[0]
        big_w, big_h = width * SUPERSAMPLE, height * SUPERSAMPLE
        matrix = pymupdf.Matrix(big_w / page.rect.width, big_h / page.rect.height)
        pix = page.get_pixmap(matrix=matrix, alpha=False)
        rendered = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)

    # Black ink on white, so the inverted greyscale IS the coverage.
    mask = Image.eval(rendered.convert("L"), lambda v: 255 - v)
    return mask.resize((width, height), Image.LANCZOS)


def _paint(
    mask: Image.Image, ink: tuple[int, int, int], bg: tuple[int, int, int] | None
) -> Image.Image:
    """Paint [ink] through [mask], over [bg] or over transparency."""
    size = mask.size
    out = Image.new("RGBA", size, (*bg, 255) if bg else (0, 0, 0, 0))
    out.paste(Image.new("RGBA", size, (*ink, 255)), (0, 0), mask)
    return out


def _centred(inner: Image.Image, canvas: int, fraction: float) -> Image.Image:
    """[inner] scaled to [fraction] of a square [canvas], on transparency."""
    side = round(canvas * fraction)
    small = inner.resize((side, side), Image.LANCZOS)
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    offset = (canvas - side) // 2
    out.paste(small, (offset, offset), small)
    return out


def _write(image: Image.Image, path: Path, *, flatten: tuple[int, int, int] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if flatten is not None:
        base = Image.new("RGBA", image.size, (*flatten, 255))
        image = Image.alpha_composite(base, image)
    image.save(path, "PNG", optimize=True)
    print(f"  {path.relative_to(ROOT).as_posix():54} {image.width}x{image.height}")


def _on_disc(mark: Image.Image) -> Image.Image:
    """[mark] over a white disc of its own diameter, corners transparent."""
    big = mark.width * SUPERSAMPLE
    disc = Image.new("L", (big, big), 0)
    ImageDraw.Draw(disc).ellipse((0, 0, big - 1, big - 1), fill=255)
    out = _paint(disc.resize(mark.size, Image.LANCZOS), WHITE, None)
    return Image.alpha_composite(out, mark)


def _lockup(width: int, ink: tuple[int, int, int], bg: tuple[int, int, int] | None) -> Image.Image:
    height = round(width / LOCKUP_ASPECT)
    return _paint(_ink_mask(None, width, height), ink, bg)


def main() -> int:
    if not MASTER.exists():
        print(f"missing master: {MASTER}", file=sys.stderr)
        return 1

    print("mark")
    mark_1024 = _paint(_ink_mask(MARK_VIEWBOX, 1024, 1024), BLACK, None)

    # Both fractions match what the previous icons measured, so the launcher
    # keeps the size it was calibrated to: the mark filled 0.937 of the icon
    # and 0.747 of the adaptive foreground.
    #
    # The app icon is flattened onto white, because iOS forbids alpha and a
    # white ground is what the official black variant is drawn for.
    _write(_centred(mark_1024, 1024, 0.937), ROOT / "assets/icon/app_icon.png", flatten=WHITE)

    # Desktop window and taskbar: no white square around the mark, but the
    # traces cut through it need a ground, or a dark taskbar swallows them.
    _write(_centred(_on_disc(mark_1024), 1024, 0.937), ROOT / "assets/icon/desktop_icon.png")

    # Android composites 108dp and guarantees only the inner 72dp, and
    # ic_launcher.xml insets this layer by a further 16%, so 0.747 here lands
    # the mark at about three quarters of the safe circle.
    _write(_centred(mark_1024, 1024, 0.747), ROOT / "assets/icon/app_icon_adaptive_foreground.png")

    # What the app itself draws, on transparency and in both inks. The launcher
    # master above is flattened onto white for iOS, which in the AppBar would be
    # a white tile, and on the dark scaffold a black mark would vanish.
    _write(mark_1024, ROOT / "assets/icon/mark_black.png")
    _write(
        _paint(_ink_mask(MARK_VIEWBOX, 1024, 1024), WHITE, None),
        ROOT / "assets/icon/mark_white.png",
    )

    print("msix badge")
    for scale, px in ((100, 24), (125, 30), (150, 36), (200, 48), (400, 96)):
        badge = Image.new("RGBA", (px, px), (*WHITE, 0))
        badge.putalpha(_ink_mask(MARK_VIEWBOX, px, px))
        _write(badge, ROOT / f"windows/msix/BadgeLogo.scale-{scale}.png")

    print("lockup")
    _write(_lockup(1440, BLACK, None), ROOT / "assets/icon/wyss_lockup_black.png")
    _write(_lockup(1440, WHITE, None), ROOT / "assets/icon/wyss_lockup_white.png")

    print("docs")
    _write(_lockup(720, BLACK, None), ROOT / "docs/_static/logo.png")
    for px in (16, 32, 48):
        _write(
            _paint(_ink_mask(MARK_VIEWBOX, px, px), BLACK, None),
            ROOT / f"docs/_static/favicon-{px}.png",
        )
    ico = ROOT / "docs/_static/favicon.ico"
    _paint(_ink_mask(MARK_VIEWBOX, 48, 48), BLACK, None).save(
        ico, "ICO", sizes=[(16, 16), (32, 32), (48, 48)]
    )
    print(f"  {ico.relative_to(ROOT).as_posix():54} 16/32/48")

    print("\nregenerate the platform icons next:  dart run flutter_launcher_icons")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
