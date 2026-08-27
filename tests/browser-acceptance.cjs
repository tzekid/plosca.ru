const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");

const repoDir = path.resolve(__dirname, "..");
const { chromium } = require(path.join(
  repoDir,
  ".cache/browser-e2e/node_modules/playwright-core",
));

const baseUrl = process.argv[2];
if (!baseUrl) throw new Error("usage: node tests/browser-acceptance.cjs BASE_URL");

const routes = fs.readFileSync(path.join(repoDir, "tests/routes.tsv"), "utf8")
  .split("\n")
  .filter((line) => line && !line.startsWith("#"))
  .map((line) => {
    const [route, status] = line.split("\t");
    return [route, Number(status)];
  });

const browserCandidates = [
  process.env.PLOSCA_CHROMIUM_PATH,
  "/usr/bin/google-chrome",
  "/usr/bin/google-chrome-stable",
  "/usr/bin/chromium",
  "/usr/bin/chromium-browser",
].filter(Boolean);
const executablePath = browserCandidates.find((candidate) => fs.existsSync(candidate));
if (!executablePath) {
  throw new Error("set PLOSCA_CHROMIUM_PATH to an installed Chromium executable");
}

const pixel = Buffer.from(
  "R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs=",
  "base64",
);

function parseCssColor(value) {
  const parts = value.match(/[\d.]+/g)?.map(Number);
  if (!parts || parts.length < 3) throw new Error(`unsupported CSS color: ${value}`);
  return { red: parts[0], green: parts[1], blue: parts[2], alpha: parts[3] ?? 1 };
}

function composite(foreground, background) {
  return {
    red: foreground.red * foreground.alpha + background.red * (1 - foreground.alpha),
    green: foreground.green * foreground.alpha + background.green * (1 - foreground.alpha),
    blue: foreground.blue * foreground.alpha + background.blue * (1 - foreground.alpha),
    alpha: 1,
  };
}

function contrastRatio(first, second) {
  const channel = (value) => {
    const normalized = value / 255;
    return normalized <= 0.04045 ? normalized / 12.92 : ((normalized + 0.055) / 1.055) ** 2.4;
  };
  const luminance = (color) => 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue);
  const high = Math.max(luminance(first), luminance(second));
  const low = Math.min(luminance(first), luminance(second));
  return (high + 0.05) / (low + 0.05);
}

async function interceptAnalytico(page, counts) {
  await page.route("https://analytico.plosca.ru/**", async (route) => {
    const url = new URL(route.request().url());
    if (url.pathname.startsWith("/tracker.")) {
      counts.tracker += 1;
      await route.fulfill({
        status: 200,
        contentType: "application/javascript",
        headers: { "access-control-allow-origin": "*" },
        body: `
          window.__analyticoTrackerLoaded = true;
          fetch("https://analytico.plosca.ru/v1/event?fixture=1")
            .then(() => { window.__analyticoConnectCompleted = true; });
        `,
      });
      return;
    }
    if (url.pathname === "/v1/event") {
      counts.connect += 1;
      await route.fulfill({
        status: 200,
        contentType: "text/plain",
        headers: { "access-control-allow-origin": "*" },
        body: "ok",
      });
      return;
    }
    if (url.pathname === "/v1/p.gif") {
      counts.pixel += 1;
      await route.fulfill({ status: 200, contentType: "image/gif", body: pixel });
      return;
    }
    await route.abort("blockedbyclient");
  });
}

function collectErrors(page) {
  const errors = [];
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(`console: ${message.text()}`);
  });
  page.on("pageerror", (error) => errors.push(`page: ${error.message}`));
  page.on("requestfailed", (request) => {
    errors.push(`request: ${request.url()} ${request.failure()?.errorText || "failed"}`);
  });
  return errors;
}

async function checkEnhanced(browser) {
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    colorScheme: "light",
    reducedMotion: "reduce",
  });
  const page = await context.newPage();
  const counts = { tracker: 0, connect: 0, pixel: 0 };
  const errors = collectErrors(page);
  const sameOriginReads = [];

  page.on("request", (request) => {
    if (!["fetch", "xhr"].includes(request.resourceType())) return;
    if (new URL(request.url()).origin === new URL(baseUrl).origin) {
      sameOriginReads.push(request.url());
    }
  });
  await page.addInitScript(() => {
    window.__cspViolations = [];
    document.addEventListener("securitypolicyviolation", (event) => {
      window.__cspViolations.push(`${event.violatedDirective}: ${event.blockedURI}`);
    });
  });
  await interceptAnalytico(page, counts);

  const response = await page.goto(`${baseUrl}/prose`, { waitUntil: "load" });
  assert.match(response.headers()["content-security-policy"], /default-src 'self'/);
  await page.waitForFunction(() => window.__analyticoTrackerLoaded === true);
  await page.waitForFunction(() => window.__analyticoConnectCompleted === true);

  assert.equal(counts.tracker, 1, "the external tracker fixture must load once");
  assert.equal(counts.connect, 1, "the tracker must be allowed to submit one event");
  assert.deepEqual(await page.evaluate(() => window.__cspViolations), []);
  assert.deepEqual(sameOriginReads, [], "the first view must not refetch server-known data");

  const first = page.locator('a[data-previewable][href="/hello_world"]').first();
  const second = page.locator('a[data-previewable][href="/"]').first();
  const target = page.locator("#link-preview");
  const previewReadCount = () => sameOriginReads.filter((url) =>
    new URL(url).pathname.startsWith("/previews/")
  ).length;

  await first.hover();
  await page.waitForTimeout(150);
  await page.mouse.move(1, 1);
  await page.waitForTimeout(350);
  assert.equal(await target.isVisible(), false, "a brief flyover must not open a preview");
  assert.equal(previewReadCount(), 0, "a brief flyover must not request a preview fragment");

  await second.focus();
  await page.waitForTimeout(50);
  assert.equal(await target.isVisible(), false, "non-keyboard focus must not bypass pointer intent");

  await first.hover();
  await page.waitForTimeout(150);
  assert.equal(await target.isVisible(), false, "the preview must respect the pointer intent delay");
  const firstPreview = page.locator('#link-preview[data-preview-href="/hello_world"]');
  await firstPreview.waitFor({ state: "visible" });
  assert.equal(previewReadCount(), 1);

  await firstPreview.hover();
  await page.waitForTimeout(650);
  assert.equal(await firstPreview.isVisible(), true, "moving into the preview must keep it open");
  await page.mouse.move(1, 1);
  await page.waitForTimeout(250);
  assert.equal(await firstPreview.isVisible(), true, "the preview must survive its exit grace period");
  await firstPreview.waitFor({ state: "hidden" });

  await first.hover();
  await firstPreview.waitFor({ state: "visible" });
  assert.equal(previewReadCount(), 1, "a cached preview must not be fetched twice");
  await page.mouse.move(1, 1);
  await firstPreview.waitFor({ state: "hidden" });

  await first.hover();
  await page.waitForTimeout(100);
  await second.hover();
  const switchedPreview = page.locator('#link-preview[data-preview-href="/"]');
  await switchedPreview.waitFor({ state: "visible" });
  assert.equal(await switchedPreview.isVisible(), true, "only the deliberately hovered link must open");

  await page.mouse.click(1, 1);
  assert.equal(await target.isVisible(), false, "clicking outside must dismiss the preview immediately");

  await page.keyboard.press("Tab");
  for (const [link, expected] of [[first, "/hello_world"], [second, "/"], [first, "/hello_world"]]) {
    await link.focus();
    const preview = page.locator(`#link-preview[data-preview-href="${expected}"]`);
    await preview.waitFor({ state: "visible" });
    assert.equal(await preview.getAttribute("data-preview-href"), expected);
  }

  assert.deepEqual(errors, []);
  await context.close();
}

async function checkCancellation(browser) {
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await context.newPage();
  const counts = { tracker: 0, connect: 0, pixel: 0 };
  const errors = collectErrors(page);
  await page.addInitScript(() => {
    const nativeFetch = window.fetch.bind(window);
    window.__previewFetchEvents = [];
    window.fetch = (input, options = {}) => {
      const url = new URL(typeof input === "string" ? input : input.url, window.location.href);
      if (url.pathname !== "/previews/3979d6c13901b2e1.html") return nativeFetch(input, options);
      window.__previewFetchEvents.push("start");
      return new Promise((resolve, reject) => {
        const signal = options.signal;
        let settled = false;
        const timer = window.setTimeout(() => {
          if (settled) return;
          settled = true;
          nativeFetch(input, options).then(resolve, reject);
        }, 1500);
        signal?.addEventListener("abort", () => {
          if (settled) return;
          settled = true;
          window.clearTimeout(timer);
          window.__previewFetchEvents.push("abort");
          reject(new DOMException("Aborted", "AbortError"));
        }, { once: true });
      });
    };
  });
  await interceptAnalytico(page, counts);
  await page.goto(`${baseUrl}/prose`, { waitUntil: "load" });

  const first = page.locator('a[data-previewable][href="/hello_world"]').first();
  const second = page.locator('a[data-previewable][href="/"]').first();
  await page.keyboard.press("Tab");
  await first.focus();
  await page.waitForFunction(() => window.__previewFetchEvents.includes("start"));
  await second.focus();
  await page.locator('#link-preview[data-preview-href="/"]').waitFor({ state: "visible" });
  assert.deepEqual(await page.evaluate(() => window.__previewFetchEvents), ["start", "abort"]);
  assert.deepEqual(errors, [], "an intentional stale-request abort must stay silent");
  await context.close();
}

async function checkCodeBlocks(browser) {
  for (const width of [320, 390, 768, 1440]) {
    const context = await browser.newContext({
      viewport: { width, height: width <= 390 ? 844 : 900 },
      colorScheme: width === 768 ? "light" : "dark",
      reducedMotion: "reduce",
      hasTouch: width <= 390,
      isMobile: width <= 390,
    });
    await context.grantPermissions(["clipboard-read", "clipboard-write"], {
      origin: new URL(baseUrl).origin,
    });
    const page = await context.newPage();
    const counts = { tracker: 0, connect: 0, pixel: 0 };
    const errors = collectErrors(page);
    await interceptAnalytico(page, counts);
    await page.goto(`${baseUrl}/hello_world`, { waitUntil: "load" });
    await page.waitForFunction(() => document.querySelector("[data-code-block]")?.classList.contains("code-block-ready"));

    const blocks = page.locator("[data-code-block]");
    assert.equal(await blocks.count(), 2);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth), width);

    const first = blocks.first();
    const scroller = first.locator("pre.sourceCode");
    assert.equal(await scroller.getAttribute("tabindex"), width <= 640 ? "0" : null);
    assert.equal(await scroller.getAttribute("role"), width <= 640 ? "region" : null);
    assert.equal(await scroller.getAttribute("aria-label"), "Bash code: site build pipeline");
    assert.equal(await scroller.getAttribute("aria-describedby"), width <= 640 ? "cb1-guidance" : null);
    assert.equal(await first.locator(".code-language").textContent(), "Bash");
    assert.equal(await first.locator(".code-copy").isVisible(), true);

    const metrics = await first.evaluate((block) => {
      const pre = block.querySelector("pre.sourceCode");
      const body = document.querySelector("article > p");
      return {
        overflowing: pre.scrollWidth > pre.clientWidth,
        codeSize: Number.parseFloat(getComputedStyle(pre).fontSize),
        bodySize: Number.parseFloat(getComputedStyle(body).fontSize),
      };
    });
    assert.equal(metrics.overflowing, width <= 640);
    assert(metrics.codeSize < metrics.bodySize, "code must stay subordinate to article copy");
    assert.equal(await first.evaluate((block) => block.classList.contains("can-scroll-right")), width <= 640);

    const colors = await first.evaluate((block) => {
      const background = getComputedStyle(block).backgroundColor;
      const page = getComputedStyle(document.body).backgroundColor;
      const tokens = [".co", ".ex", ".va", ".kw", ".fu", ".op"].map((selector) => ({
        selector,
        color: getComputedStyle(document.querySelector(`code.sourceCode ${selector}`)).color,
      }));
      return { background, page, tokens };
    });
    const codeBackground = composite(parseCssColor(colors.background), parseCssColor(colors.page));
    for (const token of colors.tokens) {
      assert(
        contrastRatio(parseCssColor(token.color), codeBackground) >= 4.5,
        `${token.selector} must retain readable contrast`,
      );
    }

    if (width <= 390) {
      assert.equal(await first.locator(".code-overflow-hint").isVisible(), true);
      assert.equal(await first.locator(".code-hint-touch").isVisible(), true);
      await scroller.focus();
      assert.notEqual(await scroller.evaluate((pre) => getComputedStyle(pre).boxShadow), "none");
      await scroller.evaluate((pre) => { pre.scrollLeft = pre.scrollWidth; });
      await page.waitForFunction(() => !document.querySelector("[data-code-block]").classList.contains("can-scroll-right"));
      assert.equal(await first.locator(".code-overflow-hint").evaluate((node) => getComputedStyle(node).opacity), "0");
      assert.equal(await first.evaluate((block) => block.classList.contains("can-scroll-left")), true);

      const source = await first.locator("code.sourceCode").textContent();
      await first.locator(".code-copy").click();
      await page.waitForFunction(() => document.querySelector(".code-copy")?.textContent === "Copied");
      assert.equal(await page.evaluate(() => navigator.clipboard.readText()), source.replace(/\n$/, ""));
    }
    if (width === 320) {
      await page.evaluate(() => { document.documentElement.style.fontSize = "32px"; });
      const enlarged = await first.evaluate((block) => {
        const toolbar = block.querySelector(".code-toolbar");
        const copy = block.querySelector(".code-copy").getBoundingClientRect();
        const bounds = block.getBoundingClientRect();
        return {
          toolbarFits: toolbar.scrollWidth <= toolbar.clientWidth,
          copyFits: copy.left >= bounds.left && copy.right <= bounds.right,
        };
      });
      assert.equal(enlarged.toolbarFits, true, "the toolbar must reflow at 200% text size");
      assert.equal(enlarged.copyFits, true, "Copy must remain reachable at 200% text size");
    }
    assert.deepEqual(errors, []);
    await context.close();
  }
}

async function checkCodeCopyFailure(browser) {
  const context = await browser.newContext({ viewport: { width: 320, height: 844 }, hasTouch: true, isMobile: true });
  const page = await context.newPage();
  const counts = { tracker: 0, connect: 0, pixel: 0 };
  const errors = collectErrors(page);
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText: async () => { throw new DOMException("Denied", "NotAllowedError"); } },
    });
  });
  await interceptAnalytico(page, counts);
  await page.goto(`${baseUrl}/hello_world`, { waitUntil: "load" });
  const first = page.locator("[data-code-block]").first();
  await first.locator(".code-copy").click();
  await page.waitForFunction(() => document.querySelector(".code-copy")?.textContent === "Select");
  assert.equal(await first.locator(".code-copy-status").textContent(), "Copy failed. Select the code manually.");
  assert.deepEqual(errors, []);
  await context.close();
}

async function checkAboutAndRoutes(browser) {
  for (const viewport of [{ width: 1440, height: 900 }, { width: 768, height: 900 }]) {
    const context = await browser.newContext({ viewport, colorScheme: "light" });
    const page = await context.newPage();
    const counts = { tracker: 0, connect: 0, pixel: 0 };
    const errors = collectErrors(page);
    await interceptAnalytico(page, counts);
    await page.goto(`${baseUrl}/about`, { waitUntil: "load" });

    const timeline = page.locator('details[name="experience"]');
    assert.deepEqual(await timeline.evaluateAll((items) => items.map((item) => item.open)), [true, false, false, false, false]);
    await timeline.nth(1).locator("summary").click();
    assert.deepEqual(await timeline.evaluateAll((items) => items.map((item) => item.open)), [false, true, false, false, false]);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true);

    assert.equal(await page.locator("html").getAttribute("data-theme"), "light");
    await page.locator(".theme-toggle").first().click();
    assert.equal(await page.locator("html").getAttribute("data-theme"), "dark");
    await page.reload({ waitUntil: "load" });
    assert.equal(await page.locator("html").getAttribute("data-theme"), "dark");

    const download = page.locator('a[href="/resume.pdf"][download]').first();
    assert.equal(await download.isVisible(), true);
    const resume = await context.request.get(`${baseUrl}/resume.pdf`);
    assert.equal(resume.status(), 200);
    assert.equal(resume.headers()["content-type"], "application/pdf");
    assert((await resume.body()).length > 0);
    assert.deepEqual(errors, []);
    await context.close();
  }

  const context = await browser.newContext();
  for (const [route, expectedStatus] of routes) {
    const response = await context.request.get(`${baseUrl}${route}`);
    assert.equal(response.status(), expectedStatus, `${route} status changed unexpectedly`);
  }
  for (const name of fs.readdirSync(path.join(repoDir, "site/previews"))) {
    const response = await context.request.get(`${baseUrl}/previews/${name}`);
    assert.equal(response.status(), 200, `/previews/${name} must exist`);
  }
  assert.equal((await context.request.get(`${baseUrl}/preview.js`)).status(), 200);
  assert.equal((await context.request.get(`${baseUrl}/code.js`)).status(), 200);
  const missing = await context.request.get(`${baseUrl}/definitely-missing-route`);
  assert.equal(missing.status(), 404);
  assert.match(await missing.text(), /Page not found/);
  const archive = await context.request.get(`${baseUrl}/archive`);
  assert.equal(archive.status(), 200);
  assert.match(await archive.text(), /External link archive registry/);
  await context.close();
}

async function checkJavaScriptFree(browser) {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  const counts = { tracker: 0, connect: 0, pixel: 0 };
  await interceptAnalytico(page, counts);

  await page.goto(`${baseUrl}/prose`, { waitUntil: "load" });
  assert.equal(counts.tracker, 0, "JavaScript-disabled clients must not request the tracker");
  assert.equal(counts.pixel, 1, "JavaScript-disabled clients must request the analytics pixel");

  await page.setViewportSize({ width: 320, height: 844 });
  await page.goto(`${baseUrl}/hello_world`, { waitUntil: "load" });
  assert.equal(await page.locator(".code-language").first().isVisible(), true);
  assert.equal(await page.locator(".code-overflow-hint").first().isVisible(), true);
  assert.equal(await page.locator(".code-copy").first().isVisible(), false);
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true);

  await page.setViewportSize({ width: 1280, height: 720 });
  const about = page.locator('a[href="/about"]').first();
  assert.equal(await about.isVisible(), true, "native navigation must remain visible");
  await Promise.all([page.waitForURL(`${baseUrl}/about`), about.click()]);
  assert.equal(new URL(page.url()).pathname, "/about");
  await context.close();
}

(async () => {
  const browser = await chromium.launch({ executablePath, headless: true });
  try {
    await checkEnhanced(browser);
    await checkCancellation(browser);
    await checkCodeBlocks(browser);
    await checkCodeCopyFailure(browser);
    await checkAboutAndRoutes(browser);
    await checkJavaScriptFree(browser);
  } finally {
    await browser.close();
  }
  console.log("browser acceptance checks passed");
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
