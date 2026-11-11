"""Sphinx configuration for the Wyss DBS Annotator documentation.

The application is written in Dart, so nothing here imports the software. Two
consequences:

* Read the Docs installs only ``docs/requirements.txt``, with no project
  install and no system libraries.
* ``autodoc``, ``autosummary``, ``napoleon`` and ``viewcode`` are absent because
  they would have no target. A Dart API reference via ``dartdoc`` is a separate
  decision.
"""

from __future__ import annotations

import re
import sys
from datetime import datetime
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_ROOT = _HERE.parent
sys.path.insert(0, str(_HERE / "_ext"))

# -- Identity ----------------------------------------------------------------
# Literals on purpose. The upstream values live in lib/app_info.dart, and
# regex-scraping three strings that change approximately never out of Dart
# source is more machinery than one duplicated line. Only the VERSION is
# derived, because only the version changes every release.
project = "Wyss DBS Annotator"
author = "Lucia Poma"
_HOLDERS = (
    "Wyss Center for Bio and Neuroengineering, Massachusetts General Hospital, "
    "and Harvard Medical School"
)
_FIRST_YEAR = 2026  # matches lib/app_info.dart's About-dialog notice
_YEAR = datetime.now().year
_SPAN = str(_FIRST_YEAR) if _YEAR <= _FIRST_YEAR else f"{_FIRST_YEAR}-{_YEAR}"
copyright = f"{_SPAN}, {_HOLDERS}"
html_context = {"contact_email": "lucia.poma@wysscenter.ch"}


def _flutter_version() -> str:
    """The ``0.5.0`` out of a pubspec ``version: 0.5.0+1``.

    A regex rather than a YAML parser, because PyYAML is not in the standard
    library and this is the only field needed: a pubspec ``version`` is always
    a top-level scalar.

    Raises rather than defaulting: a silent ``0.0.0`` in the footer of a
    clinical tool's documentation is worse than a red build.
    """
    text = (_ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(r"^version:\s*([0-9][^\s+#]*)", text, re.MULTILINE)
    if match is None:
        raise RuntimeError("no `version:` found in pubspec.yaml")
    return match.group(1)


release = _flutter_version()
version = ".".join(release.split(".")[:2])

# -- General -----------------------------------------------------------------
extensions = [
    "sphinx_copybutton",
    "myst_parser",
    # Local: renders docs/_generated/*.inc.rst from schema/tsv_schema.json at
    # build time. See docs/_ext/generated_includes.py.
    "generated_includes",
]

# `intersphinx` is deliberately absent. With fail_on_warning enabled, a
# transient failure fetching a remote objects.inv emits a warning and therefore
# breaks publishing. Re-add it only when something actually cross-references
# another project's API.

exclude_patterns = [
    "_build",
    "Thumbs.db",
    ".DS_Store",
    "requirements.txt",
    # Fragments pulled in with `.. include::`. Excluding them stops Sphinx
    # treating each as a standalone page (which then warns about not being in
    # any toctree); `include` still reads them as raw text.
    "_generated/*.inc.rst",
]

source_suffix = {".rst": "restructuredtext", ".md": "markdown"}

# -- HTML --------------------------------------------------------------------
templates_path = ["_templates"]

html_theme = "sphinx_rtd_theme"
html_static_path = ["_static"]
html_css_files = ["custom.css"]
html_js_files = ["video_speed.js"]
html_favicon = "_static/favicon-32.png"

html_theme_options = {
    "logo_only": False,
    "prev_next_buttons_location": "bottom",
    "style_external_links": True,
    "collapse_navigation": False,
    "sticky_navigation": True,
    "navigation_depth": 3,
}

# No `suppress_warnings`. Every screenshot is committed, so a missing image is a
# real error and should fail the build rather than publish a page with a broken
# figure.

# -- MyST --------------------------------------------------------------------
myst_enable_extensions = ["colon_fence", "deflist", "smartquotes"]
myst_heading_anchors = 3

# -- linkcheck ---------------------------------------------------------------
linkcheck_timeout = 15
linkcheck_retries = 2
linkcheck_anchors = False
