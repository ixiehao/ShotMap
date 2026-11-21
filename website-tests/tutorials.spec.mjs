import { test, expect, languages, measureLayout, openPage, site } from './support.mjs';

const tutorialLanguages = ['en', 'zh', 'ja'];
const examples = {
  'video-to-storyboard': ['generate', 'automatic-storyboard.jpg'],
  'choose-frames': ['frames', 'manual-storyboard.jpg'],
  'layout-and-export': ['layout', 'square-storyboard.webp']
};
const home = language => language === 'en' ? './' : language + '/';

for (const language of languages.filter(id => tutorialLanguages.includes(id))) {
  for (const [slug, [image, result]] of Object.entries(examples)) {
    for (const width of [320, 1440]) {
      test(`${language} ${slug} is readable at ${width}px`, async ({ page, request }) => {
        await page.setViewportSize({ width, height: 900 });
        await openPage(page, language);
        const entry = page.locator(`#tutorials a[href="tutorials/${slug}/"]`);
        await expect(entry).toBeVisible();
        await entry.click();
        const canonical = site.url + (language === 'en' ? '' : home(language)) + 'tutorials/' + slug + '/';
        await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', canonical);
        const screenshot = page.locator('main figure img');
        await expect(screenshot).toHaveAttribute('src', new RegExp(`/${image}-${language}\\.webp$`));
        await expect(screenshot).toHaveAttribute('alt', /\S/);
        expect(await screenshot.evaluate(async element => {
          await element.decode();
          return [
            element.naturalWidth === Number(element.getAttribute('width')),
            element.naturalHeight === Number(element.getAttribute('height'))
          ];
        })).toEqual([true, true]);

        const figure = page.locator('.tutorial-figure-link');
        expect(await figure.getAttribute('href')).toBe(await screenshot.getAttribute('src'));
        const { violations } = await page.evaluate(measureLayout, { root: 'body', language });
        expect(violations).toEqual([]);

        const img = await request.get(new URL(await figure.getAttribute('href'), page.url()).href);
        expect(img.status()).toBe(200);
        expect(img.headers()['content-type']).toContain('image/webp');
        const downloads = await page.locator('main a[download]').evaluateAll(links => links.map(link => link.href));
        expect(downloads.map(url => decodeURIComponent(new URL(url).pathname.split('/').at(-1)))).toEqual(['Color Trail.mp4', result]);
        for (const url of downloads) expect((await request.head(url)).status()).toBe(200);

        for (const id of tutorialLanguages.filter(id => id !== language)) {
          await page.locator(`.tutorial-header [hreflang="${id === 'zh' ? 'zh-CN' : id}"]`).click();
          await expect(page.locator('html')).toHaveAttribute('lang', id === 'zh' ? 'zh-CN' : id);
          await expect(page.locator('main figure img')).toHaveAttribute('src', new RegExp(`/${image}-${id}\\.webp$`));
          await page.goBack();
        }
      });
    }
  }
}
