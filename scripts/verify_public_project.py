#!/usr/bin/env python3
"""Keep ShotMap's public entry points consistent without network access.

The repository page, README files, and Pages site are the first product
experience for most people. This lightweight check guards the links and assets
that are easy to overlook during a release.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = "https://github.com/ixiehao/ShotMap"
WEBSITE = "https://ixiehao.github.io/ShotMap/"


def fail(message: str) -> None:
    print(f"public-project check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def require_text(path: Path, *snippets: str) -> str:
    if not path.is_file():
        fail(f"missing {path.relative_to(ROOT)}")
    text = path.read_text(encoding="utf-8")
    for snippet in snippets:
        if snippet not in text:
            fail(f"{path.relative_to(ROOT)} is missing {snippet!r}")
    return text


def jpeg_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if not data.startswith(b"\xff\xd8"):
        fail(f"{path.relative_to(ROOT)} is not a JPEG")

    offset = 2
    sof_markers = set(range(0xC0, 0xC4)) | set(range(0xC5, 0xC8)) | set(range(0xC9, 0xCC)) | set(range(0xCD, 0xD0))
    while offset + 9 < len(data):
        if data[offset] != 0xFF:
            offset += 1
            continue
        while offset < len(data) and data[offset] == 0xFF:
            offset += 1
        marker = data[offset]
        offset += 1
        if marker in {0xD8, 0xD9} or 0xD0 <= marker <= 0xD7:
            continue
        if offset + 2 > len(data):
            break
        segment_length = int.from_bytes(data[offset : offset + 2], "big")
        if segment_length < 2 or offset + segment_length > len(data):
            break
        if marker in sof_markers:
            return (
                int.from_bytes(data[offset + 5 : offset + 7], "big"),
                int.from_bytes(data[offset + 3 : offset + 5], "big"),
            )
        offset += segment_length
    fail(f"could not read dimensions from {path.relative_to(ROOT)}")


def main() -> None:
    for readme in ("README.md", "README.zh-CN.md", "README.ja.md"):
        text = require_text(ROOT / readme, "ShotMap", REPOSITORY, WEBSITE)
        if "ixiehao/tap/shottessera" in text:
            fail(f"{readme} still advertises the legacy Homebrew cask")

    metadata = require_text(ROOT / "docs/GITHUB_METADATA.md", "Repository description", "ShotMap")
    description_match = re.search(r"`(ShotMap[^`]+)`", metadata)
    if description_match is None or len(description_match.group(1)) > 160:
        fail("GitHub repository description is absent or longer than 160 characters")

    site = require_text(
        ROOT / "website/index.html",
        WEBSITE,
        "SoftwareApplication",
        "og:image",
        "twitter:image",
    )
    if "ShotTessera" in site:
        fail("website/index.html contains the legacy product name")

    social_preview = ROOT / "docs/assets/social-preview-v2.jpg"
    if social_preview.stat().st_size >= 1_000_000:
        fail("social preview is too large for GitHub's 1 MB recommendation")
    if jpeg_size(social_preview) != (1280, 640):
        fail("social preview must be exactly 1280 × 640 px")

    for template in ("bug_report.yml", "feature_request.yml"):
        require_text(ROOT / ".github/ISSUE_TEMPLATE" / template, "name:", "description:")

    print("Public project materials are consistent.")


if __name__ == "__main__":
    main()
