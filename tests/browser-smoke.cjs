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

async function checkEnhanced(browser) {
  const context = await browser.newContext();
  const page = await context.newPage();
  const counts = { tracker: 0, connect: 0, pixel: 0 };
  const errors = [];
  const sameOriginStartupReads = [];

  page.on("console", (message) => {
    if (message.type() === "error") errors.push(`console: ${message.text()}`);
  });
  page.on("pageerror", (error) => errors.push(`page: ${error.message}`));
  page.on("requestfailed", (request) => {
    errors.push(`request: ${request.url()} ${request.failure()?.errorText || "failed"}`);
  });
  page.on("request", (request) => {
    if (!["fetch", "xhr"].includes(request.resourceType())) return;
    if (new URL(request.url()).origin === new URL(baseUrl).origin) {
      sameOriginStartupReads.push(request.url());
    }
  });
  await page.addInitScript(() => {
    window.__cspViolations = [];
    document.addEventListener("securitypolicyviolation", (event) => {
      window.__cspViolations.push(`${event.violatedDirective}: ${event.blockedURI}`);
    });
  });
  await interceptAnalytico(page, counts);

  await page.goto(`${baseUrl}/prose`, { waitUntil: "load" });
  await page.waitForFunction(() => window.__analyticoTrackerLoaded === true);
  await page.waitForFunction(() => window.__analyticoConnectCompleted === true);

  assert.equal(counts.tracker, 1, "the external tracker fixture must load once");
  assert.equal(counts.connect, 1, "the tracker must be allowed to submit one event");
  assert.deepEqual(await page.evaluate(() => window.__cspViolations), []);
  assert.deepEqual(sameOriginStartupReads, [], "the first view must not refetch server-known data");

  const first = page.locator('a[data-previewable][href="/hello_world"]').first();
  const second = page.locator('a[data-previewable][href="/"]').first();
  const target = page.locator("#link-preview");
  const previewReadCount = () => sameOriginStartupReads.filter((url) =>
    new URL(url).pathname.startsWith("/metadata/previews/")
  ).length;

  await first.hover();
  await page.waitForTimeout(150);
  await page.mouse.move(1, 1);
  await page.waitForTimeout(350);
  assert.equal(await target.isVisible(), false, "a brief flyover must not open a preview");
  assert.equal(previewReadCount(), 0, "a brief flyover must not request preview metadata");

  await second.focus();
  await page.waitForTimeout(50);
  assert.equal(await target.isVisible(), false, "non-keyboard focus must not bypass the pointer intent delay");

  await first.hover();
  await page.waitForTimeout(150);
  assert.equal(await target.isVisible(), false, "the preview must respect the pointer intent delay");
  const pointerPreview = page.locator('#link-preview[data-preview-href="/hello_world"]');
  await pointerPreview.waitFor({ state: "visible" });

  await pointerPreview.hover();
  await page.waitForTimeout(650);
  assert.equal(await pointerPreview.isVisible(), true, "moving from the source into the preview must keep it open");

  await page.mouse.move(1, 1);
  await page.waitForTimeout(250);
  assert.equal(await pointerPreview.isVisible(), true, "the preview must survive the exit grace period");
  await pointerPreview.waitFor({ state: "hidden" });

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
  await Promise.all([
    page.waitForURL(`${baseUrl}/about`),
    about.click(),
  ]);
  assert.equal(new URL(page.url()).pathname, "/about");
  await context.close();
}

(async () => {
  const browser = await chromium.launch({ executablePath, headless: true });
  try {
    await checkEnhanced(browser);
    await checkBaseline(browser);
  } finally {
    await browser.close();
  }
  console.log("browser smoke checks passed");
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
