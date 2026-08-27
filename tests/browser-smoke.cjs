const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");

const repoDir = path.resolve(__dirname, "..");
const { chromium } = require(path.join(
  repoDir,
  ".zig-cache/browser-e2e/node_modules/playwright-core",
));

const baseUrl = process.argv[2];
if (!baseUrl) throw new Error("usage: node tests/browser-smoke.cjs BASE_URL");

const baselineRoutes = fs.readFileSync(path.join(repoDir, "tests/baseline/routes.tsv"), "utf8")
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
  for (const [route, baselineStatus] of baselineRoutes) {
    const expectedStatus = route === "/preview-controller.js" ? 404 : baselineStatus;
    const response = await context.request.get(`${baseUrl}${route}`);
    assert.equal(response.status(), expectedStatus, `${route} status changed unexpectedly`);
  }
  for (const name of fs.readdirSync(path.join(repoDir, "dist/previews"))) {
    const response = await context.request.get(`${baseUrl}/previews/${name}`);
    assert.equal(response.status(), 200, `/previews/${name} must exist`);
  }
  assert.equal((await context.request.get(`${baseUrl}/preview.js`)).status(), 200);
  assert.equal((await context.request.get(`${baseUrl}/vendor/htmx.min.js`)).status(), 404);
  assert.equal((await context.request.get(`${baseUrl}/metadata/pages.json`)).status(), 404);
  const missing = await context.request.get(`${baseUrl}/definitely-missing-browser-route`);
  assert.equal(missing.status(), 404);
  assert.match(await missing.text(), /Page not found/);
  const archive = await context.request.get(`${baseUrl}/archive`);
  assert.equal(archive.status(), 200);
  assert.match(await archive.text(), /External link archive registry/);
  await context.close();
}

async function checkBaseline(browser) {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  const counts = { tracker: 0, connect: 0, pixel: 0 };
  await interceptAnalytico(page, counts);

  await page.goto(`${baseUrl}/prose`, { waitUntil: "load" });
  assert.equal(counts.tracker, 0, "JavaScript-disabled clients must not request the tracker");
  assert.equal(counts.pixel, 1, "JavaScript-disabled clients must request the analytics pixel");

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
    await checkAboutAndRoutes(browser);
    await checkBaseline(browser);
  } finally {
    await browser.close();
  }
  console.log("browser acceptance checks passed");
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
