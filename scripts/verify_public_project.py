#!/usr/bin/env python3
"""Keep ShotMap's public entry points consistent without network access.

The repository page, README files, and Pages site are the first product
experience for most people. This lightweight check guards the links and assets
that are easy to overlook during a release.
"""

from __future__ import annotations

import re
import sys
import json
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = "https://github.com/ixiehao/ShotMap"
WEBSITE = "https://ixiehao.github.io/ShotMap/"
LANGUAGES = {"en": "en", "zh": "zh-CN", "fr": "fr", "ru": "ru", "es": "es", "ja": "ja", "ko": "ko"}
READMES = ("README.md", "README.zh-CN.md", "README.fr.md", "README.ru.md", "README.es.md", "README.ja.md", "README.ko.md")


class PublicPage(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.elements: list[tuple[str, dict[str, str]]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.elements.append((tag, dict(attrs)))


def verify_local_target(source: Path, target: str) -> None:
    parsed = urlsplit(target)
    if parsed.scheme or parsed.netloc or not parsed.path:
        return
    resolved = (source.parent / unquote(parsed.path)).resolve()
    if not resolved.exists():
        fail(f"{source.relative_to(ROOT)} links to missing {target}")


def verify_page(path: Path, locale: str) -> None:
    text = require_text(path, f'<html lang="{LANGUAGES[locale]}"', WEBSITE)
    page = PublicPage()
    page.feed(text)
    elements = page.elements
    links = [attrs for tag, attrs in elements if tag == "link"]
    canonical = next(attrs["href"] for attrs in links if attrs.get("rel") == "canonical")
    expected_url = WEBSITE + (locale + "/" if locale != "en" else "")
    if canonical != expected_url:
        fail(f"wrong canonical URL in {path.relative_to(ROOT)}")
    alternates = {attrs.get("hreflang"): attrs.get("href") for attrs in links if attrs.get("rel") == "alternate"}
    expected_alternates = {language: WEBSITE + (key + "/" if key != "en" else "") for key, language in LANGUAGES.items()}
    expected_alternates["x-default"] = WEBSITE
    if alternates != expected_alternates:
        fail(f"incomplete hreflang links in {path.relative_to(ROOT)}")
    menu = [attrs for tag, attrs in elements if tag == "a" and "data-lang" in attrs]
    if [link["data-lang"] for link in menu] != list(LANGUAGES):
        fail(f"incomplete language menu in {path.relative_to(ROOT)}")
    if [link["data-lang"] for link in menu if link.get("aria-current") == "page"] != [locale]:
        fail(f"incorrect current language in {path.relative_to(ROOT)}")
    for tag, attrs in elements:
        target = attrs.get("src") or attrs.get("href")
        if target:
            verify_local_target(path, target)
        if tag == "a" and target and "/releases/" in target and target != REPOSITORY + "/releases/latest":
            fail(f"stale download link in {path.relative_to(ROOT)}")
    for schema in re.findall(r'<script[^>]+type="application/ld\+json"[^>]*>(.*?)</script>', text, re.S):
        value = json.loads(schema)
        if value.get("@type") == "SoftwareApplication":
            if value.get("url") != expected_url or value.get("inLanguage") != ["en", "zh-Hans", "fr", "ru", "es", "ja", "ko"]:
                fail(f"incorrect software metadata in {path.relative_to(ROOT)}")


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
    for readme in READMES:
        text = require_text(ROOT / readme, "ShotMap", REPOSITORY, WEBSITE)
        for sibling in READMES:
            if f"]({sibling})" not in text:
                fail(f"{readme} is missing a link to {sibling}")
        for target in re.findall(r"\]\(([^\s)]+)\)", text):
            verify_local_target(ROOT / readme, target)
            if "/releases/" in target and target != REPOSITORY + "/releases/latest":
                fail(f"stale download link in {readme}")

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
    for locale in LANGUAGES:
        verify_page(ROOT / "website" / ("" if locale == "en" else locale) / "index.html", locale)

    sitemap = ET.parse(ROOT / "website/sitemap.xml")
    indexed_urls = {node.text for node in sitemap.findall("{*}url/{*}loc")}
    expected_urls = {WEBSITE + (locale + "/" if locale != "en" else "") for locale in LANGUAGES}
    if indexed_urls != expected_urls:
        fail("sitemap must include all seven language URLs")

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
