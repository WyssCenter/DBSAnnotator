"""Rasterise the generated report PDFs into the images the docs embed.

Run after the docs screenshot test, which writes the PDFs:

    $env:DOCS_SCREENSHOT_DIR = "docs/_static/screenshots"
    flutter test test/docs/screenshots_test.dart
    uv run --no-project --with pymupdf --with pillow python tool/report_screenshots.py

The pages listed in PAGES become `<report>_page<n>.png`, and every section
named in SECTIONS is cropped from its heading down to the next heading, or to the page footer, as
`<report>_<section>.png`. Sections are found by their heading text, so the crops
follow the layout rather than hard-coded coordinates. A section that runs past a
page break is continued from the top of the next page and stitched on.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pymupdf
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "build" / "docs_reports"
OUT = ROOT / "docs" / "_static" / "reports"

DPI = 150
# Margin above a heading (enough to keep a box border that frames it) and
# below the crop, in points.
PAD_TOP = 14
PAD = 6

# Only what docs/reports.rst embeds: every image here is committed.
PAGES = {"session_report": [2], "longitudinal_report": [3]}

# Headings that end the section above them without being cropped themselves.
STOPS = {
    "session_report": ["Attestation"],
    "annotations_report": ["Attestation"],
    "longitudinal_report": ["Session data", "Programming summary", "Source files"],
}

SECTIONS = {
    "session_report": {
        "summary": "At start of session",
        "baseline": "Initial assessment (before programming)",
        "session_data": ("Session data", "Figure 1."),
        "electrodes": "Electrode configuration",
        "programming_summary": "Programming summary",
    },
    "annotations_report": {
        "notes": "Wyss DBS Annotator - Session notes",
    },
    "longitudinal_report": {
        "clinical": "Clinical scales by visit",
        "session_scales": "Session scales by visit and block",
        "visits": "Visits",
    },
}


def _heading_hits(doc: pymupdf.Document) -> list[tuple[int, float, str]]:
    """(page, top, heading) for every known heading, in reading order."""
    hits = []
    for index, page in enumerate(doc):
        for block in page.get_text("dict")["blocks"]:
            for line in block.get("lines", []):
                text = "".join(span["text"] for span in line["spans"]).strip()
                hits.append((index, line["bbox"][1], text))
    return hits


def _footer_top(page: pymupdf.Page) -> float:
    """Top of the running footer, the last text line on the page."""
    lines = [
        line["bbox"][1]
        for block in page.get_text("dict")["blocks"]
        for line in block.get("lines", [])
    ]
    return max(lines) if lines else page.rect.height


def _pixels(page: pymupdf.Page, clip: pymupdf.Rect) -> Image.Image:
    pix = page.get_pixmap(dpi=DPI, clip=clip)
    return Image.frombytes("RGB", (pix.width, pix.height), pix.samples)


def _render(page: pymupdf.Page, clip: pymupdf.Rect, path: Path) -> None:
    _save(_pixels(page, clip), path)


def _save(image: Image.Image, path: Path) -> None:
    image.save(path)
    print(f"  {path.relative_to(ROOT).as_posix()}")


def _content_bottom(page: pymupdf.Page, limit: float) -> float:
    """Bottom of the last drawn element above [limit], so a crop ends at its
    content rather than at the footer."""
    drawn = [d["rect"].y1 for d in page.get_drawings()]
    text = [block[3] for block in page.get_text("blocks")]
    bottoms = [y for y in drawn + text if y < limit]
    return max(bottoms) if bottoms else limit


def _paragraph_bottom(page: pymupdf.Page, prefix: str, below: float) -> float:
    """Bottom of the first text block under [below] that starts with [prefix]."""
    for block in page.get_text("blocks"):
        if block[1] > below and block[4].strip().startswith(prefix):
            return block[3]
    return _footer_top(page)


def _body_top(page: pymupdf.Page) -> float:
    """Top of the first text line: the page's content start."""
    lines = [
        line["bbox"][1]
        for block in page.get_text("dict")["blocks"]
        for line in block.get("lines", [])
    ]
    return min(lines) if lines else 0


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    for report, sections in SECTIONS.items():
        pdf = SOURCE / f"{report}.pdf"
        if not pdf.exists():
            print(f"missing {pdf}; run the docs screenshot test first", file=sys.stderr)
            return 1
        doc = pymupdf.open(pdf)
        for number in PAGES.get(report, []):
            page = doc[number - 1]
            _render(page, page.rect, OUT / f"{report}_page{number}.png")

        lines = _heading_hits(doc)
        headings = {name: h if isinstance(h, str) else h[0] for name, h in sections.items()}
        wanted = set(headings.values()) | set(STOPS.get(report, []))
        starts = [(p, top, text) for p, top, text in lines if text in wanted]
        for name, entry in sections.items():
            heading = headings[name]
            match = next(((p, top) for p, top, text in starts if text == heading), None)
            if match is None:
                print(f"  {report}: heading not found: {heading!r}", file=sys.stderr)
                continue
            page_index, top = match
            page = doc[page_index]
            later = [t for p, t, _ in starts if p == page_index and t > top]
            bottom = min(later) if later else _content_bottom(page, _footer_top(page)) + PAD
            if not isinstance(entry, str):
                # Up to the end of the paragraph that starts with this text: a
                # figure without the table that follows it.
                bottom = _paragraph_bottom(page, entry[1], top) + PAD
                later = [bottom]
            clip = pymupdf.Rect(0, max(top - PAD_TOP, 0), page.rect.width, bottom - PAD)
            parts = [_pixels(page, clip)]
            # Nothing else starts on this page, so the section may go on.
            nxt = page_index + 1
            if not later and nxt < len(doc):
                follow = [t for p, t, _ in starts if p == nxt]
                end = (
                    min(follow)
                    if follow
                    else _content_bottom(doc[nxt], _footer_top(doc[nxt])) + PAD
                )
                top_next = _body_top(doc[nxt])
                if end - top_next > PAD * 2:
                    parts.append(
                        _pixels(
                            doc[nxt],
                            pymupdf.Rect(0, top_next - PAD, page.rect.width, end - PAD),
                        )
                    )
            stitched = Image.new("RGB", (parts[0].width, sum(p.height for p in parts)), "white")
            y = 0
            for part in parts:
                stitched.paste(part, (0, y))
                y += part.height
            _save(stitched, OUT / f"{report}_{name}.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
