#!/usr/bin/env node
import { chromium } from "@playwright/test";
import { spawn } from "node:child_process";
import { mkdir, rm } from "node:fs/promises";
import path from "node:path";

const phase = process.argv[2] ?? "before";
if (!["before", "after"].includes(phase)) {
  console.error("Usage: node scripts/capture-screenshots.mjs <before|after>");
  process.exit(2);
}

const port = Number(process.env.PLOSCA_TEST_PORT ?? 19329);
const baseURL = process.env.PLOSCA_BASE_URL ?? `http://127.0.0.1:${port}`;
const outRoot = path.join("artifacts", "css-migration", phase);

const pages = [
  { name: "home", path: "/" },
  { name: "about", path: "/about" },
  { name: "hello-world", path: "/hello_world" },
  { name: "prose", path: "/prose" },
  { name: "not-found", path: "/tailwind-missing-page" },
];

const viewports = [
  { name: "desktop", width: 1440, height: 1000 },
  { name: "breakpoint-plus", width: 865, height: 1000 },
  { name: "breakpoint", width: 864, height: 1000 },
  { name: "small", width: 640, height: 900 },
  { name: "narrow", width: 520, height: 900 },
  { name: "mobile", width: 390, height: 844 },
];

let server;
if (!process.env.PLOSCA_BASE_URL) {
  server = spawn("zig", ["build", "run", "--", "serve", "--host", "127.0.0.1", "--port", String(port)], {
    stdio: ["ignore", "pipe", "pipe"],
  });
  server.stdout.on("data", (chunk) => process.stdout.write(chunk));
  server.stderr.on("data", (chunk) => process.stderr.write(chunk));
  await waitForServer(baseURL);
}

try {
  await rm(outRoot, { recursive: true, force: true });
  await mkdir(outRoot, { recursive: true });

  const browser = await chromium.launch();
  for (const viewport of viewports) {
    const context = await browser.newContext({
      viewport: { width: viewport.width, height: viewport.height },
      deviceScaleFactor: 1,
    });
    const page = await context.newPage();
    await mkdir(path.join(outRoot, viewport.name), { recursive: true });
    await preparePage(page);

    for (const pageCase of pages) {
      await page.goto(new URL(pageCase.path, baseURL).toString(), { waitUntil: "load" });
      await page.evaluate(() => document.fonts.ready);
      await page.screenshot({
        path: path.join(outRoot, viewport.name, `${pageCase.name}.png`),
        fullPage: true,
        animations: "disabled",
      });
    }

    if (viewport.name === "mobile") {
      await page.goto(baseURL, { waitUntil: "load" });
      await page.evaluate(() => document.fonts.ready);
      await page.locator(".nav-btn").click();
      await page.screenshot({
        path: path.join(outRoot, viewport.name, "mobile-nav-open.png"),
        fullPage: true,
        animations: "disabled",
      });
    }

    await context.close();
  }
  await browser.close();
  console.log(`Captured ${phase} screenshots in ${outRoot}`);
} finally {
  if (server) server.kill();
}

async function waitForServer(url) {
  const deadline = Date.now() + 120_000;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url);
      if (response.ok) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Timed out waiting for ${url}`);
}

async function preparePage(page) {
  await page.route("**/plausible.plosca.ru/**", (route) => route.abort());
}
