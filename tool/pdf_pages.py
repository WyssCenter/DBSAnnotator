"""Render each page of a PDF to PNG, for the docs video to show the report it saved.

    uvx --from pymupdf python -I tool/pdf_pages.py <report.pdf> <out_dir>

The pages are written as ``page01.png``, ``page02.png``... so they sort in order.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pymupdf

pdf, out = Path(sys.argv[1]), Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
with pymupdf.open(pdf) as doc:
    for number, page in enumerate(doc, start=1):
        page.get_pixmap(dpi=110).save(out / f"page{number:02d}.png")
