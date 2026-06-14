import { defineConfig, devices } from "@playwright/test";

const port = Number(process.env.PLOSCA_TEST_PORT ?? 19329);
const baseURL = process.env.PLOSCA_BASE_URL ?? `http://127.0.0.1:${port}`;

export default defineConfig({
  testDir: "./tests",
  timeout: 30_000,
  expect: {
    timeout: 5_000,
  },
  use: {
    baseURL,
    trace: "on-first-retry",
  },
  reporter: [["list"], ["html", { open: "never" }]],
  webServer: process.env.PLOSCA_BASE_URL
    ? undefined
    : {
        command: `zig build run -- serve --host 127.0.0.1 --port ${port}`,
        url: baseURL,
        reuseExistingServer: !process.env.CI,
        timeout: 120_000,
      },
  projects: [
    {
      name: "chromium-desktop",
      use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 1000 } },
    },
    {
      name: "chromium-breakpoint",
      use: { ...devices["Desktop Chrome"], viewport: { width: 864, height: 1000 } },
    },
    {
      name: "chromium-mobile",
      use: { ...devices["Pixel 5"], viewport: { width: 390, height: 844 } },
    },
  ],
});
