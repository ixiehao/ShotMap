import { tutorialCopy } from "./tutorial-copy.mjs";
import { htmlLanguage, languageNames, siteURL } from "./script.js";

const languages = Object.keys(tutorialCopy);
const examples = {
  "video-to-storyboard": ["generate", 2432, 1460, "automatic-storyboard.jpg"],
  "choose-frames": ["frames", 2380, 1520, "manual-storyboard.jpg"],
  "layout-and-export": ["layout", 2432, 1810, "square-storyboard.webp"]
};
const guideKeys = Object.keys(examples);
const assets = "assets/tutorials/";
const prefixFor = language => language === "en" ? "" : language + "/";
const route = (language, guide) => prefixFor(language) + "tutorials/" + guide + "/";
const escape = value => value.replaceAll("&", "&amp;").replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;").replaceAll('"', "&quot;");
const richText = value => escape(value).replace(/\*\*(.*?)\*\*/g, "<strong>$1</strong>");
const linkList = (language, prefix, exclude) => guideKeys.filter(key => key !== exclude).map(key => {
  const guide = tutorialCopy[language].guides[key];
  return `          <li><a href="${prefix}${key}/"><strong>${escape(guide.title)}</strong><span>${escape(guide.summary)}</span></a></li>`;
}).join("\n");

export function addTutorialLinks(html, language) {
  const copy = tutorialCopy[language];
  const marker = /    <!-- tutorials:start -->[\s\S]*?    <!-- tutorials:end -->\n/;
  if (!marker.test(html)) throw new Error("Missing tutorial links placeholder");
  if (!copy) return html.replace(marker, "");
  return html.replace(marker, `    <!-- tutorials:start -->
      <section class="section shell" id="tutorials" aria-labelledby="tutorials-title">
        <div class="section-heading compact-heading">
          <h2 id="tutorials-title">${escape(copy.title)}</h2>
          <p>${escape(copy.intro)}</p>
        </div>
        <ul class="tutorial-links">
${linkList(language, "tutorials/")}
        </ul>
      </section>
    <!-- tutorials:end -->
`).replace("</head>", `  <link rel="stylesheet" href="${language === "en" ? "" : "../"}tutorials.css" />\n  </head>`);
}

export function tutorialPages(stylesheet) {
  return guideKeys.flatMap(key => languages.map(language => {
    const copy = tutorialCopy[language];
    const guide = copy.guides[key];
    const path = route(language, key);
    const root = language === "en" ? "../../" : "../../../";
    const home = language === "en" ? root : root + language + "/";
    const url = siteURL + path;
    const [stem, width, height, result] = examples[key];
    const image = assets + stem + "-" + language + ".webp";
    const alternates = [...languages.map(id => [htmlLanguage(id), siteURL + route(id, key)]),
      ["x-default", siteURL + route("en", key)]];
    const localeLinks = languages.map(id => `<a href="${root + route(id, key)}" lang="${htmlLanguage(id)}" hreflang="${htmlLanguage(id)}"${id === language ? ' aria-current="page"' : ""}>${languageNames[id]}</a>`).join("\n          ");
    const schema = JSON.stringify({
      "@context": "https://schema.org", "@type": "Article", headline: guide.title,
      description: guide.summary, inLanguage: htmlLanguage(language), url,
      mainEntityOfPage: url, image: siteURL + image, author: { "@type": "Person", name: "ixiehao" }
    }).replaceAll("<", "\\u003c");
    const content = `<!doctype html>
<html lang="${htmlLanguage(language)}">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${escape(guide.title)} · ShotMap</title>
    <meta name="description" content="${escape(guide.summary)}" />
    <link rel="canonical" href="${url}" />
${alternates.map(([id, href]) => `    <link rel="alternate" hreflang="${id}" href="${href}" />`).join("\n")}
    <link rel="alternate" type="text/markdown" href="${url}index.md" />
    <link rel="describedby" type="text/plain" href="${siteURL}llms.txt" />
    <meta property="og:type" content="article" />
    <meta property="og:title" content="${escape(guide.title)}" />
    <meta property="og:description" content="${escape(guide.summary)}" />
    <meta property="og:url" content="${url}" />
    <meta property="og:locale" content="${{ en: "en_US", zh: "zh_CN", ja: "ja_JP" }[language]}" />
    <meta property="og:image" content="${siteURL + image}" />
    <meta property="og:image:alt" content="${escape(guide.alt)}" />
    <link rel="icon" href="${root}favicon.svg" type="image/svg+xml" />
    <link rel="stylesheet" href="${root + stylesheet}" />
    <link rel="stylesheet" href="${root}tutorials.css" />
    <script type="application/ld+json">${schema}</script>
  </head>
  <body>
    <header class="site-header tutorial-header">
      <a class="brand" href="${home}" aria-label="${escape(copy.home)}">
        <img class="brand-mark" src="${root}assets/app-icon.png" width="36" height="36" alt="" />
        <span>ShotMap</span>
      </a>
      <nav aria-label="${escape(copy.language)}">
          ${localeLinks}
      </nav>
    </header>
    <main class="shell tutorial-page">
      <article>
        <header class="tutorial-heading">
          <a class="tutorial-return" href="${home}#tutorials">${escape(copy.title)}</a>
          <h1>${escape(guide.title)}</h1>
          <p class="tutorial-summary">${escape(guide.summary)}</p>
        </header>
        <p>${escape(copy.setup)}</p>
        <p><a href="${root + assets}Color%20Trail.mp4" download>${escape(copy.sample)}</a></p>
        <ol class="tutorial-steps">
${guide.steps.map(step => `          <li>${richText(step)}</li>`).join("\n")}
        </ol>
        <figure>
          <a class="tutorial-figure-link" href="${root + image}" aria-label="${escape(copy.openImage)}"><img src="${root + image}" alt="${escape(guide.alt)}" width="${width}" height="${height}" /></a>
          <figcaption>${escape(guide.caption)} <a href="${root + image}">${escape(copy.openImage)}</a></figcaption>
        </figure>
        <h2>${escape(copy.verification)}</h2>
        <p>${richText(guide.check)}</p>
        <p><a href="${root + assets + result}" download>${escape(copy.result)}</a></p>
      </article>
      <section class="tutorial-related" aria-labelledby="related-title">
        <h2 id="related-title">${escape(copy.related)}</h2>
        <ul class="tutorial-links">
${linkList(language, "../", key)}
        </ul>
      </section>
    </main>
  </body>
</html>
`;
    return { path, url, alternates, content, files: [image, assets + "Color Trail.mp4", assets + result] };
  }));
}
