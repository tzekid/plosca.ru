#!/usr/bin/env node
import pixelmatch from "pixelmatch";
import { PNG } from "pngjs";
import { mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const root = path.join("artifacts", "css-migration");
const beforeRoot = path.join(root, "before");
const afterRoot = path.join(root, "after");
const diffRoot = path.join(root, "diff");
const rows = [];

await mkdir(diffRoot, { recursive: true });

for (const viewport of await safeList(beforeRoot)) {
  const beforeViewport = path.join(beforeRoot, viewport);
  const afterViewport = path.join(afterRoot, viewport);
  const diffViewport = path.join(diffRoot, viewport);
  await mkdir(diffViewport, { recursive: true });

  for (const file of await safeList(beforeViewport)) {
    if (!file.endsWith(".png")) continue;
    const beforePath = path.join(beforeViewport, file);
    const afterPath = path.join(afterViewport, file);
    const diffPath = path.join(diffViewport, file);

    const before = PNG.sync.read(await readFile(beforePath));
    const after = PNG.sync.read(await readFile(afterPath));
    if (before.width !== after.width || before.height !== after.height) {
      rows.push({ viewport, file, status: "size-changed", diff: "n/a" });
      continue;
    }

    const diff = new PNG({ width: before.width, height: before.height });
    const diffPixels = pixelmatch(before.data, after.data, diff.data, before.width, before.height, {
      threshold: 0.15,
    });
    await writeFile(diffPath, PNG.sync.write(diff));
    const ratio = diffPixels / (before.width * before.height);
    rows.push({ viewport, file, status: "compared", diff: `${diffPixels} (${(ratio * 100).toFixed(2)}%)` });
  }
}

const markdown = [
  "# CSS Migration Screenshot Comparison",
  "",
  "| Viewport | File | Status | Diff |",
  "| --- | --- | --- | ---: |",
  ...rows.map((row) => `| ${row.viewport} | ${row.file} | ${row.status} | ${row.diff} |`),
  "",
].join("\n");

await writeFile(path.join(root, "compare.md"), markdown);
console.log(markdown);

async function safeList(dir) {
  try {
    return await readdir(dir);
  } catch {
    return [];
  }
}
