"""Render the TSV column tables from the committed schema contract at build time.

The tables in :doc:`output_format` describe every session and annotation
column. Hand-maintaining that in reStructuredText guarantees it drifts from the
code, so it is generated instead, out of ``schema/tsv_schema.json``, which is
the same file the application loads at runtime and several tests assert against.

Generated at build time rather than committed, which makes staleness
structurally impossible: there is no second copy to fall behind. The input is
committed, so Read the Docs has everything it needs and no extra install step.

Standard library only, so ``docs/requirements.txt`` stays four Sphinx wheels.
"""

from __future__ import annotations

import csv
import json
import re
import textwrap
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_DOCS = _HERE.parent
_ROOT = _DOCS.parent
_OUT = _DOCS / "_generated"

#: The fixture shown as a worked example, copied into ``_generated`` so the
#: ``:download:`` link stays inside Sphinx's source dir.
_FIXTURE = _ROOT / "test" / "fixtures" / ("sub-01_ses-20260203_task-programming_run-01_beh.tsv")


def _rst_table(columns: list[dict], title: str) -> str:
    r"""A list-table of ``name / type / units / description``.

    ``list-table`` rather than a grid table because the descriptions contain
    inline RST markup (``\`\`YYYY-MM-DD\`\```) and would need re-wrapping by
    hand in any character-aligned table format.

    ``units`` is the same value the JSON sidecar publishes as ``Units``, so the
    page and the machine-readable file cannot disagree about what a number is.
    """
    lines = [
        f".. list-table:: {title}",
        "   :header-rows: 1",
        "   :widths: 20 10 8 62",
        "",
        "   * - Column",
        "     - Type",
        "     - Units",
        "     - Description",
    ]
    for col in columns:
        lines += [
            f"   * - ``{col['name']}``",
            f"     - {col.get('type', 'string')}",
            f"     - {col.get('units', '') or 'n/a'}",
            f"     - {col.get('description', '').strip() or 'n/a'}",
        ]
    return "\n".join(lines) + "\n"


def _slug(name: str) -> str:
    """The ``scale_<name>`` column of a scale, as ``scaleColumnSlug`` builds it."""
    slug = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
    return "scale_" + (slug or "unnamed")


def _example_table(path: Path, max_rows: int = 4) -> str:
    """The first configurations of the worked example, as the ``beh/`` file holds them.

    The fixture is in the app's long working form, so its rows are folded into
    one row per configuration here. Only a few columns are shown: the point is
    the *row shape*, one row per configuration with one column per scale.
    """
    with path.open(encoding="utf-8", newline="") as fh:
        long = list(csv.DictReader(fh, delimiter="\t"))
    blocks: dict[str, dict[str, str]] = {}
    scales: list[str] = []
    for r in long:
        if r["is_initial"].strip() in ("1", "1.0"):
            continue
        row = blocks.setdefault(
            r["block_id"],
            {c: r[c] for c in ("acq_time", "left_amplitude", "left_cathode")},
        )
        col = _slug(r["scale_name"])
        if col not in scales:
            scales.append(col)
        row[col] = r["scale_value"]
    rows = list(blocks.values())[:max_rows]
    show = ["acq_time", "left_amplitude", "left_cathode", *scales[:2]]

    widths = [max(len(c), *(len(r.get(c, "")) for r in rows)) for c in show]

    def fmt(cells: list[str]) -> str:
        return "   " + "  ".join(c.ljust(w) for c, w in zip(cells, widths, strict=True)).rstrip()

    out = ["::", ""]
    out.append(fmt(show))
    out.append(fmt(["-" * w for w in widths]))
    for r in rows:
        out.append(fmt([r.get(c, "") for c in show]))
    return "\n".join(out) + "\n"


def _sidecar_excerpt(contract: dict, columns: tuple[str, ...]) -> str:
    """A few entries of the JSON sidecar, exactly as the app writes them.

    Rendered rather than hand-copied into the page, because these descriptions
    and the ones the app ships are the same strings: a prose edit in
    ``schema/tsv_schema.json`` would otherwise leave the documented example
    quietly disagreeing with the file on disk.

    Mirrors ``lib/core/bids_sidecar.dart``: BIDS key names, the reStructuredText
    inline-literal markers stripped, ``Units`` only where the column has one.
    """
    by_name = {c["name"]: c for c in contract["session_tsv"]["columns"]}
    sidecar: dict[str, object] = {}
    if contract.get("bids", {}).get("na"):
        sidecar["MissingValueCode"] = contract["bids"]["na"]
    for name in columns:
        col = by_name[name]
        entry = {
            "LongName": name.replace("_", " ").capitalize(),
            "Description": col.get("description", "").replace("``", ""),
        }
        if col.get("units"):
            entry["Units"] = col["units"]
        sidecar[name] = entry

    body = textwrap.indent(json.dumps(sidecar, indent=2), "   ")
    return f".. code-block:: json\n\n{body}\n"


def _write(app, *_args) -> None:
    contract = json.loads((_ROOT / "schema" / "tsv_schema.json").read_text(encoding="utf-8"))
    _OUT.mkdir(parents=True, exist_ok=True)

    (_OUT / "session_columns.inc.rst").write_text(
        _rst_table(contract["session_tsv"]["columns"], "Programming session columns"),
        encoding="utf-8",
    )
    (_OUT / "sessions_columns.inc.rst").write_text(
        _rst_table(contract["sessions_tsv"]["columns"], "Visit columns (sessions.tsv)"),
        encoding="utf-8",
    )
    (_OUT / "scans_columns.inc.rst").write_text(
        _rst_table(contract["scans_tsv"]["columns"], "Run columns (scans.tsv)"),
        encoding="utf-8",
    )
    bids = _ROOT / "test" / "fixtures" / "bids"
    tree = sorted(p.relative_to(bids).as_posix() for p in bids.rglob("*") if p.is_file())
    (_OUT / "example_bids_tree.inc.rst").write_text(
        ".. code-block:: text\n\n" + "".join(f"   {p}\n" for p in tree),
        encoding="utf-8",
    )
    (_OUT / "participants_columns.inc.rst").write_text(
        _rst_table(contract["participants_tsv"]["columns"], "Participant columns"),
        encoding="utf-8",
    )
    (_OUT / "scale_columns.inc.rst").write_text(
        contract["session_tsv"]["scale_columns"]["description"] + "\n",
        encoding="utf-8",
    )
    (_OUT / "annotation_columns.inc.rst").write_text(
        _rst_table(contract["annotation_tsv"]["columns"], "Notes file columns"),
        encoding="utf-8",
    )

    (_OUT / "sidecar_example.inc.rst").write_text(
        _sidecar_excerpt(contract, ("is_final", "left_stim_freq")),
        encoding="utf-8",
    )

    if _FIXTURE.exists():
        (_OUT / "example_rows.inc.rst").write_text(_example_table(_FIXTURE), encoding="utf-8")
        # Inside srcdir, so `:download:` needs no traversal above it.
        (_OUT / _FIXTURE.name).write_bytes(_FIXTURE.read_bytes())
    else:  # pragma: no cover - a missing fixture should be loud
        raise FileNotFoundError(f"example fixture not found: {_FIXTURE}")


def setup(app):
    app.connect("builder-inited", _write)
    return {"version": "1", "parallel_read_safe": True}
