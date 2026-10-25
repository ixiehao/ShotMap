import { mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { appLanguageCodes, htmlLanguage, languageNames, localeURLs, localizedVisualAssets, releaseURL, siteURL, translations } from "./script.js";

const root = resolve(fileURLToPath(new URL(".", import.meta.url)));
const source = await readFile(resolve(root, "index.html"), "utf8");
const languages = Object.keys(translations);
const checkOnly = process.argv.includes("--check");

// Fail on missing or extra keys instead of publishing mixed-language copy.
const expectedKeys = Object.keys(translations.en).sort().join("|");
for (const language of languages) {
  const copy = translations[language];
  if (Object.keys(copy).sort().join("|") !== expectedKeys || Object.values(copy).some(value => typeof value !== "string" || !value.trim())) {
    throw new Error("Incomplete translation: " + language);
  }
}

function escapeAttribute(value) {
  return String(value).replaceAll("&", "&amp;").replaceAll('"', "&quot;");
}

function replaceLocalizedContent(html, copy, attribute, useHTML) {
  const expression = new RegExp("(<([a-z0-9-]+)[^>]*" + attribute + "=\"([^\"]+)\"[^>]*>)([\\s\\S]*?)(<\\/\\2>)", "gi");
  return html.replace(expression, (match, open, tag, key, content, close) => {
    if (!(key in copy)) throw new Error("Missing translation key: " + key);
    return open + (useHTML ? copy[key] : copy[key].replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;")) + close;
  });
}

function replaceTagAttribute(html, dataAttribute, targetAttribute, copy) {
  const expression = new RegExp("<[^>]*" + dataAttribute + "=\"([^\"]+)\"[^>]*>", "gi");
  return html.replace(expression, (tag, key) => {
    if (!(key in copy)) throw new Error("Missing translation key: " + key);
    const target = new RegExp(targetAttribute + "=\"[^\"]*\"", "i");
    return target.test(tag)
      ? tag.replace(target, targetAttribute + "=\"" + escapeAttribute(copy[key]) + "\"")
      : tag.replace(/>$/, " " + targetAttribute + "=\"" + escapeAttribute(copy[key]) + "\">");
  });
}

function setMeta(html, selector, content) {
  const expression = new RegExp("(<meta[^>]*" + selector + "[^>]*content=\")[^\"]*(\")", "i");
  if (!expression.test(html)) throw new Error("Missing meta selector: " + selector);
  return html.replace(expression, "$1" + escapeAttribute(content) + "$2");
}

function setLink(html, selector, href) {
  const expression = new RegExp("(<link[^>]*" + selector + "[^>]*href=\")[^\"]*(\")", "i");
  if (!expression.test(html)) throw new Error("Missing link selector: " + selector);
  return html.replace(expression, "$1" + href + "$2");
}

function buildSchema(copy, language) {
  const product = localizedVisualAssets[language].product;
  return {
    "@context": "https://schema.org", "@type": "SoftwareApplication", "@id": siteURL + "#software",
    name: "ShotMap", applicationCategory: "MultimediaApplication", operatingSystem: "macOS 13 or later",
    url: localeURLs[language], description: copy.pageDescription, downloadUrl: releaseURL,
    screenshot: new URL(product[0], siteURL).href,
    featureList: copy.schemaFeatureList,
    offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    author: { "@type": "Person", name: "ixiehao", url: "https://github.com/ixiehao" },
    codeRepository: "https://github.com/ixiehao/ShotMap", license: "https://opensource.org/license/mit",
    inLanguage: appLanguageCodes
  };
}

function replaceSchema(html, id, value) {
  const expression = new RegExp("(<script id=\"" + id + "\"[^>]*>)[\\s\\S]*?(<\\/script>)", "i");
  if (!expression.test(html)) throw new Error("Missing schema: " + id);
  return html.replace(expression, "$1\n      " + JSON.stringify(value) + "\n    $2");
}

function replaceProductVisual(html, className, visual, prefix) {
  const expression = new RegExp("(<img[^>]*class=\"" + className + "\"[^>]*)(>)", "i");
  if (!expression.test(html)) throw new Error("Missing visual: " + className);
  const [sourcePath, alt, width, height] = visual;
  const source = prefix + sourcePath;
  return html.replace(expression, (_match, tag, close) => {
    return tag
      .replace(/src="[^"]*"/, "src=\"" + source + "\"")
      .replace(/alt="[^"]*"/, "alt=\"" + escapeAttribute(alt) + "\"")
      .replace(/width="[^"]*"/, "width=\"" + width + "\"")
      .replace(/height="[^"]*"/, "height=\"" + height + "\"") + close;
  });
}

function languagePicker(language, prefix) {
  const icon = name => `<svg class="link-icon" aria-hidden="true" focusable="false" viewBox="0 0 24 24"><use href="assets/tabler-icons.svg?v=20261026-seven-locales#${name}"></use></svg>`;
  const links = languages.map(key => {
    const href = key === "en" ? (prefix || "./") : prefix + key + "/";
    return `<a href="${href}" data-lang="${key}" lang="${htmlLanguage(key)}" hreflang="${htmlLanguage(key)}"${key === language ? ' aria-current="page"' : ""}>${languageNames[key]}</a>`;
  }).join("\n            ");
  return `<details class="language-picker">\n          <summary aria-label="${escapeAttribute(translations[language].languageLabel + ": " + languageNames[language])}">${icon("language")}<span lang="${htmlLanguage(language)}">${languageNames[language]}</span>${icon("chevron-down")}</summary>\n          <div class="language-options">\n            ${links}\n          </div>\n        </details>`;
}

function makeStaticPage(language) {
  const copy = translations[language];
  const prefix = language === "en" ? "" : "../";
  let html = source;
  html = replaceLocalizedContent(html, copy, "data-i18n", false);
  html = replaceLocalizedContent(html, copy, "data-i18n-html", true);
  html = replaceTagAttribute(html, "data-i18n-alt", "alt", copy);
  html = replaceTagAttribute(html, "data-i18n-aria", "aria-label", copy);
  html = html.replace(/<html lang="[^"]+" data-default-language="[^"]+">/, `<html lang="${htmlLanguage(language)}" data-default-language="${language}">`);
  html = html.replace(/<details class="language-picker">[\s\S]*?<\/details>/, languagePicker(language, prefix));
  html = html.replace(/    <link rel="alternate" hreflang="[^"]+"[^>]*\/>\n/g, "");
  const alternates = [...languages.map(key => [htmlLanguage(key), localeURLs[key]]), ["x-default", siteURL]];
  html = html.replace(/(<link id="canonical-url"[^>]+\/>)\n/, "$1\n" + alternates.map(([key, url]) => `    <link rel="alternate" hreflang="${key}" href="${url}" />`).join("\n") + "\n");
  html = html.replace(/    <meta property="og:locale:alternate"[^>]*\/>\n/g, "");
  html = html.replace(/(<meta property="og:locale"[^>]+\/>)\n/, "$1\n" + languages.filter(key => key !== language).map(key => `    <meta property="og:locale:alternate" content="${translations[key].locale}" />`).join("\n") + "\n");
  html = html.replace(/<title>[\s\S]*?<\/title>/, "<title>" + copy.pageTitle + "</title>");
  html = setMeta(html, 'name="description"', copy.pageDescription);
  html = setMeta(html, 'property="og:title"', copy.ogTitle);
  html = setMeta(html, 'property="og:description"', copy.ogDescription);
  html = setMeta(html, 'id="og-url" property="og:url"', localeURLs[language]);
  html = setMeta(html, 'property="og:locale"', copy.locale);
  html = setMeta(html, 'name="twitter:title"', copy.ogTitle);
  html = setMeta(html, 'name="twitter:description"', copy.ogDescription);
  html = setMeta(html, 'id="og-image-alt" property="og:image:alt"', copy.socialPreviewAlt);
  html = setMeta(html, 'id="twitter-image-alt" name="twitter:image:alt"', copy.socialPreviewAlt);
  html = setLink(html, 'id="canonical-url" rel="canonical"', localeURLs[language]);
  html = replaceSchema(html, "software-schema", buildSchema(copy, language));
  html = replaceSchema(html, "faq-schema", {
    "@context": "https://schema.org", "@type": "FAQPage", mainEntity: ["One", "Two", "Three", "Four"].map((number) => ({
      "@type": "Question", name: copy["faq" + number + "Question"], acceptedAnswer: { "@type": "Answer", text: copy["faq" + number + "Answer"] }
    }))
  });
  html = replaceProductVisual(html, "localized-product", localizedVisualAssets[language].product, prefix);
  html = replaceProductVisual(html, "localized-manual", localizedVisualAssets[language].manual, prefix);
  if (prefix) html = html
    .replace(/href="styles\.css([^"]*)"/g, 'href="../styles.css$1"')
    .replace(/src="navigation\.js([^"]*)"/g, 'src="../navigation.js$1"')
    .replaceAll('href="favicon.svg', 'href="../favicon.svg')
    .replaceAll('href="assets/', 'href="../assets/')
    .replaceAll('src="assets/', 'src="../assets/');
  return html;
}

for (const language of languages) {
  const output = makeStaticPage(language);
  const directory = language === "en" ? root : resolve(root, language);
  const path = resolve(directory, "index.html");
  if (checkOnly) {
    const existing = await readFile(path, "utf8");
    if (existing !== output) throw new Error("Generated website/" + language + "/index.html is out of date. Run node website/build-static-pages.mjs.");
  } else {
    await mkdir(directory, { recursive: true });
    await writeFile(path, output);
  }
}

const alternates = [...languages.map(key => [htmlLanguage(key), localeURLs[key]]), ["x-default", siteURL]];
const sitemap = '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n' + languages.map(language => `  <url>\n    <loc>${localeURLs[language]}</loc>\n${alternates.map(([key, url]) => `    <xhtml:link rel="alternate" hreflang="${key}" href="${url}" />`).join("\n")}\n  </url>`).join("\n") + '\n</urlset>\n';
if (checkOnly) {
  if (await readFile(resolve(root, "sitemap.xml"), "utf8") !== sitemap) throw new Error("sitemap.xml is out of date.");
} else {
  await writeFile(resolve(root, "sitemap.xml"), sitemap);
}
console.log(`Verified ${languages.length} complete website translations and sitemap.`);
