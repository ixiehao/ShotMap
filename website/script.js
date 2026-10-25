import en from "./locales/en.js";
import zh from "./locales/zh.js";
import fr from "./locales/fr.js";
import ru from "./locales/ru.js";
import es from "./locales/es.js";
import ja from "./locales/ja.js";
import ko from "./locales/ko.js";

export const siteURL = "https://ixiehao.github.io/ShotMap/";
export const releaseURL = "https://github.com/ixiehao/ShotMap/releases/latest";
export const appLanguageCodes = ["en", "zh-Hans", "fr", "ru", "es", "ja", "ko"];
export const translations = { en, zh, fr, ru, es, ja, ko };
export const languageNames = { en: "English", zh: "简体中文", fr: "Français", ru: "Русский", es: "Español", ja: "日本語", ko: "한국어" };
export const localeURLs = Object.fromEntries(Object.keys(translations).map(language => [language, siteURL + (language === "en" ? "" : language + "/")]));
export const htmlLanguage = language => language === "zh" ? "zh-CN" : language;

// Reuse real captures; captions identify the English UI in the four new locales.
export const localizedVisualAssets = Object.fromEntries(Object.entries(translations).map(([language, copy]) => {
  const imageLanguage = ["en", "zh", "ja"].includes(language) ? language : "en";
  return [language, {
    product: [`assets/workspace-${imageLanguage}.webp?v=20261017`, copy.productAlt, 1400, 995],
    manual: [`assets/manual-${imageLanguage}.webp?v=20261017`, copy.manualAlt, 1280, 828]
  }];
}));
