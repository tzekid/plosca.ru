#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const staticDir = "static";
const cssPath = path.join(staticDir, "style.css");
const css = await readFile(cssPath);
const version = createHash("sha256").update(css).digest("hex").slice(0, 16);
const stylesheetHref = `/style.css?v=${version}`;
let updated = 0;

for (const file of await readdir(staticDir)) {
  if (!file.endsWith(".html")) continue;

  const htmlPath = path.join(staticDir, file);
  const before = await readFile(htmlPath, "utf8");
  const after = before.replace(
    /href=(["'])\/style\.css(?:\?v=[^"']+)?\1/g,
    (_match, quote) => `href=${quote}${stylesheetHref}${quote}`,
  );

  if (after !== before) {
    await writeFile(htmlPath, after);
    updated += 1;
  }
}

console.log(`style.css version ${version}; updated ${updated} HTML file(s)`);
