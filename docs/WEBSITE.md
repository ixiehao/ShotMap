# ShotMap website maintenance

[Documentation index](README.md) · [Development](DEVELOPMENT.md)

## Source and public URL

- Source: [`website/`](../website/), not the repository root or `docs/`.
- Public URL: https://ixiehao.github.io/ShotMap/
- Deployment: [`.github/workflows/pages.yml`](../.github/workflows/pages.yml).
- Website, README and app languages: English, Simplified Chinese, French, Russian,
  Spanish, Japanese and Korean. The website uses `/`, `/zh/`, `/fr/`, `/ru/`,
  `/es/`, `/ja/` and `/ko/`; each README links to all seven translations.
- Keep English first in language menus and documentation links, without explaining
  that implementation detail in product copy. Keep supported languages visible
  near the main download button and at the top of each README.

`website/` is a source directory, not part of the public URL. Keep the public address and existing external links unchanged.

## Copy and localization

Lead with the visitor's problem and the plain-language outcome. For ShotMap, the agreed message is: “Your videos, easier to find” / “你的视频，不再难找。把视频，编成一张分镜图。” / “動画を、もっと見つけやすく。” Avoid obscure technical metaphors, keyword stuffing, unsupported speed claims, and literal translations that sound unnatural. Keep product facts and user control consistent across locales; localize examples and sentence structure naturally.

Use real app screenshots and describe what they show. English, Chinese and Japanese have existing localized captures. French, Russian, Spanish and Korean currently reuse the English captures, clearly identified in localized captions and alt text; never imply those captures show a translated interface. Check image rights and keep the *Tears of Steel* attribution visible. Keep page titles, descriptions, social metadata, schema, and visible content aligned.

## Icons

Website pictograms follow the app's Tabler Icons Outline v3.49.0 set. Use the original local or inline SVG paths with the same outline treatment; do not substitute Unicode symbols or mix in another icon library. The ShotMap logo and favicon are project artwork, not UI pictograms. Keep decorative SVGs hidden from assistive technology and preserve the MIT attribution in [`NOTICE.md`](../NOTICE.md).

## Local preview

Run from the repository root:

```sh
python3 -m http.server 8000 --bind 127.0.0.1 --directory website
```

Open <http://127.0.0.1:8000/>. Use HTTP rather than opening files directly, especially when testing fetched resources.

## Validation

```sh
node --check website/script.js
node --check website/navigation.js
node website/build-static-pages.mjs --check
python3 scripts/verify_public_project.py
git diff --check
```

`website/locales/*.js` is the copy source for all seven languages. `website/script.js` registers their URLs and assets; `website/index.html` supplies the shared layout. After editing, regenerate all seven static pages and the sitemap with `node website/build-static-pages.mjs`, review the generated changes, and run `--check` again. Do not hand-edit localized pages as separate sources of truth. Every locale must have exactly the same nonempty translation keys.

Language switching uses native links in a compact, keyboard-accessible disclosure menu. It works without JavaScript. The URL determines the language, including English at the root; a saved preference must never silently translate a different locale URL. `navigation.js` only handles legacy `?lang=` links and closing the menu. Keep reciprocal hreflang links, localized canonical URLs, Open Graph locales, and sitemap entries consistent across all pages.

Check images, favicon, navigation, official download destinations, desktop and narrow layouts, keyboard focus, language switching, localized metadata and download/signing wording. Check canonical and share URLs, robots and sitemap where present. A path-only migration should preserve site content.

Keep download links pointed at `https://github.com/ixiehao/ShotMap/releases/latest`
so they follow the latest stable international release. Verify the actual redirect
and DMG asset against GitHub's latest-release response before publishing; do not
hard-code an older version into product download buttons. SoftwareApplication
metadata lists all seven app languages, while each page retains its own HTML
language and locale links. Bump asset query versions when adding translation keys
or styling so a cached script cannot replace new copy with missing values.

## Deployment

The workflow uploads `website/` and deploys it as the site root. It runs on relevant changes to `main` and supports manual dispatch. Pages should be configured to use **GitHub Actions**; moving the source directory must be accompanied by the matching workflow path update.

Only publish when authorized. After deployment, read the public URL back and verify resources, navigation and downloads. A successful local preview is not proof that the public site has updated.
