import { readFileSync, readdirSync } from 'node:fs';

const languages = readdirSync(new URL('./website/locales/', import.meta.url)).filter(name => name.endsWith('.js')).map(name => name.slice(0, -3));
export default {
  ...{
  "prefix": "/ShotMap/",
  "url": "https://ixiehao.github.io/ShotMap/",
  "directory": "website",
  "build": null,
  "breakpoints": [
    390,
    700,
    980,
    1020
  ],
  "cards": ".steps > li,.capability-grid > article,.faq-grid > article",
  "uniform": [
    ".steps > li",
    ".capability-grid > article"
  ],
  "picker": ".language-picker",
  "menu": ".language-options",
  "languageAttribute": "data-lang"
},
  grids: [{"selector": ".capability-grid", "columns": [[700, 1], [980, 2], [10000, 4]]}],
  languages
};
