"""Render the app icon and the Wyss Center lockup into every raster the app and the docs need.

Run by hand and commit the output, then regenerate the platform icons:

    uv run --no-project --with pymupdf --with pillow \\
        python tool/build_brand_assets.py
    dart run flutter_launcher_icons

`assets/brand/ann-icon.svg` is the icon master and `assets/brand/wyss-center-*.svg`
the lockup masters. Every icon variant is the master's black ink repainted on mint,
so no two variants can disagree about geometry.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pymupdf
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ICON_MASTER = ROOT / "assets" / "brand" / "ann-icon.svg"
LOCKUP_MASTER = ROOT / "assets" / "brand" / "wyss-center-black.svg"
LOCKUP_ASPECT = 1134.22 / 176

BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
MINT = (149, 249, 216)
SIZE = 1024
CORNER = 58.367 / 768
MACOS_CORNER = 0.225
MACOS_BODY = 824 / 1024
ADAPTIVE_INK = 0.747
SUPERSAMPLE = 4


def _icon_ink() -> Image.Image:
    """Ink coverage of the icon master: 255 on black, 0 on mint."""
    with pymupdf.open(ICON_MASTER) as doc:
        page = doc[0]
        big = SIZE * SUPERSAMPLE
        pix = page.get_pixmap(matrix=pymupdf.Matrix(big / page.rect.width, big / page.rect.height))
        rendered = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
    grey = rendered.convert("L").resize((SIZE, SIZE), Image.LANCZOS)
    mint = round(0.299 * MINT[0] + 0.587 * MINT[1] + 0.114 * MINT[2])
    return Image.eval(grey, lambda v: max(0, min(255, round((mint - v) * 255 / mint))))


def _paint(
    mask: Image.Image, ink: tuple[int, int, int], bg: tuple[int, int, int] | None
) -> Image.Image:
    out = Image.new("RGBA", mask.size, (*bg, 255) if bg else (0, 0, 0, 0))
    out.paste(Image.new("RGBA", mask.size, (*ink, 255)), (0, 0), mask)
    return out


def _rounded(image: Image.Image, corner: float) -> Image.Image:
    """[image] clipped to a rounded square, corners transparent."""
    big = image.width * SUPERSAMPLE
    shape = Image.new("L", (big, big), 0)
    ImageDraw.Draw(shape).rounded_rectangle((0, 0, big - 1, big - 1), round(big * corner), fill=255)
    out = image.copy()
    out.putalpha(shape.resize(image.size, Image.LANCZOS))
    return out


def _centred(inner: Image.Image, fraction: float) -> Image.Image:
    side = round(SIZE * fraction)
    small = inner.resize((side, side), Image.LANCZOS)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    offset = (SIZE - side) // 2
    out.paste(small, (offset, offset), small)
    return out


def _write(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG", optimize=True)
    print(f"  {path.relative_to(ROOT).as_posix():54} {image.width}x{image.height}")


def _lockup(width: int, ink: tuple[int, int, int]) -> Image.Image:
    """The Wyss Center lockup in [ink] on transparency."""
    height = round(width / LOCKUP_ASPECT)
    with pymupdf.open(LOCKUP_MASTER) as doc:
        page = doc[0]
        matrix = pymupdf.Matrix(
            width * SUPERSAMPLE / page.rect.width, height * SUPERSAMPLE / page.rect.height
        )
        pix = page.get_pixmap(matrix=matrix, alpha=False)
        rendered = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
    mask = Image.eval(rendered.convert("L"), lambda v: 255 - v)
    return _paint(mask.resize((width, height), Image.LANCZOS), ink, None)


def main() -> int:
    for master in (ICON_MASTER, LOCKUP_MASTER):
        if not master.exists():
            print(f"missing master: {master}", file=sys.stderr)
            return 1

    print("icon")
    ink = _icon_ink()
    square = _paint(ink, BLACK, MINT)
    rounded = _rounded(square, CORNER)
    _write(square, ROOT / "assets/icon/app_icon.png")
    _write(rounded, ROOT / "assets/icon/desktop_icon.png")
    _write(
        _centred(_rounded(square, MACOS_CORNER), MACOS_BODY), ROOT / "assets/icon/macos_icon.png"
    )
    _write(square.resize((512, 512), Image.LANCZOS), ROOT / "assets/store/play_store_icon_512.png")

    circle = ink.crop(ink.getbbox())
    _write(
        _centred(_paint(circle, BLACK, None), ADAPTIVE_INK),
        ROOT / "assets/icon/app_icon_adaptive_foreground.png",
    )

    print("msix badge")
    for scale, px in ((100, 24), (125, 30), (150, 36), (200, 48), (400, 96)):
        _write(
            _paint(circle.resize((px, px), Image.LANCZOS), WHITE, None),
            ROOT / f"windows/msix/BadgeLogo.scale-{scale}.png",
        )

    print("lockup")
    _write(_lockup(1440, BLACK), ROOT / "assets/icon/wyss_lockup_black.png")
    _write(_lockup(1440, WHITE), ROOT / "assets/icon/wyss_lockup_white.png")

    print("docs")
    _write(_lockup(720, BLACK), ROOT / "docs/_static/logo.png")
    for px in (16, 32, 48):
        _write(rounded.resize((px, px), Image.LANCZOS), ROOT / f"docs/_static/favicon-{px}.png")
    ico = ROOT / "docs/_static/favicon.ico"
    rounded.resize((48, 48), Image.LANCZOS).save(ico, "ICO", sizes=[(16, 16), (32, 32), (48, 48)])
    print(f"  {ico.relative_to(ROOT).as_posix():54} 16/32/48")

    print("\nregenerate the platform icons next:  dart run flutter_launcher_icons")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
