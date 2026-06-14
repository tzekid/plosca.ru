import { expect, test } from "@playwright/test";

const pages = [
  { name: "home", path: "/", status: 200 },
  { name: "about", path: "/about", status: 200 },
  { name: "hello-world", path: "/hello_world", status: 200 },
  { name: "prose", path: "/prose", status: 200 },
  { name: "not-found", path: "/tailwind-missing-page", status: 404 },
];

for (const pageCase of pages) {
  test(`${pageCase.name} renders without layout overflow`, async ({ page }, testInfo) => {
    await page.route("**/plausible.plosca.ru/**", (route) => route.abort());
    const response = await page.goto(pageCase.path);
    expect(response?.status()).toBe(pageCase.status);
    await page.evaluate(() => document.fonts.ready);
    await expect(page.locator("body")).toBeVisible();
    await expect(page.locator(".nav")).toBeVisible();

    const overflow = await page.evaluate(() => {
      return document.documentElement.scrollWidth - document.documentElement.clientWidth;
    });
    expect(overflow).toBeLessThanOrEqual(4);

    await page.screenshot({
      path: testInfo.outputPath(`${pageCase.name}.png`),
      fullPage: true,
      animations: "disabled",
    });
  });
}

const centeredArticlePages = [
  { name: "about", path: "/about", selector: "article.about-page" },
  { name: "hello-world", path: "/hello_world", selector: "main > article" },
  { name: "prose", path: "/prose", selector: "main > article" },
];

for (const pageCase of centeredArticlePages) {
  test(`${pageCase.name} article column is centered`, async ({ page }) => {
    await page.route("**/plausible.plosca.ru/**", (route) => route.abort());
    const response = await page.goto(pageCase.path);
    expect(response?.status()).toBe(200);
    await page.evaluate(() => document.fonts.ready);

    const delta = await page.locator(pageCase.selector).evaluate((element) => {
      const rect = element.getBoundingClientRect();
      const articleCenter = rect.left + rect.width / 2;
      return Math.abs(articleCenter - window.innerWidth / 2);
    });

    expect(delta).toBeLessThanOrEqual(2);
  });
}

test("mobile navigation opens", async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.route("**/plausible.plosca.ru/**", (route) => route.abort());
  const response = await page.goto("/");
  expect(response?.status()).toBe(200);
  await page.evaluate(() => document.fonts.ready);
  await page.locator(".nav-btn").click();
  await expect(page.locator("#primary-navigation")).toHaveCSS("opacity", "1");
  await expect(page.locator("#primary-navigation a", { hasText: "About" })).toBeVisible();
  await page.screenshot({
    path: testInfo.outputPath("mobile-nav-open.png"),
    fullPage: true,
    animations: "disabled",
  });
});

test("mobile home overview keeps article date visible", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.route("**/plausible.plosca.ru/**", (route) => route.abort());
  const response = await page.goto("/");
  expect(response?.status()).toBe(200);
  await page.evaluate(() => document.fonts.ready);

  await expect(page.locator(".home-box .a-date", { hasText: "1 January 2019" })).toBeVisible();
});
