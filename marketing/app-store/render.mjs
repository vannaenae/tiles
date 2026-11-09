// Renders the six Mac App Store screenshots (2880×1800 PNG each) from slides.html.
//
//   node marketing/app-store/render.mjs <captures folder> [output folder]
//
// The captures are the PNGs scripts/marketing-shots.sh makes (01-dwindle.png, 02-grid.png, ...).
// Needs Playwright with Chromium (npm i -D playwright && npx playwright install chromium).
import { createRequire } from "node:module";
import { mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

// require() also finds a globally installed Playwright.
const { chromium } = createRequire(import.meta.url)("playwright");

const [shotsArg, outArg = "app-store-out"] = process.argv.slice(2);
if (!shotsArg) {
  console.error("usage: node marketing/app-store/render.mjs <captures folder> [output folder]");
  process.exit(2);
}
const here = dirname(fileURLToPath(import.meta.url));
const shots = pathToFileURL(resolve(shotsArg) + "/").href;
const out = resolve(outArg);
mkdirSync(out, { recursive: true });

const names = ["01-every-window", "02-layouts", "03-scrolling", "04-scenes", "05-themes", "06-keyboard"];
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 2880, height: 1800 }, deviceScaleFactor: 1 });
await page.goto(`${pathToFileURL(resolve(here, "slides.html")).href}?shots=${encodeURIComponent(shots)}`);
await page.evaluate(() => document.fonts.ready);
// Wait for every capture to load, so no slide renders with an empty screen.
await page.evaluate(async () => {
  const urls = [...document.querySelectorAll("[data-shot]")].map(el => getComputedStyle(el).backgroundImage.slice(5, -2));
  await Promise.all([...new Set(urls)].map(u => new Promise((ok, fail) => {
    const img = new Image(); img.onload = ok; img.onerror = () => fail(new Error("missing capture: " + u)); img.src = u;
  })));
});
for (const [i, name] of names.entries()) {
  await page.locator(`#s${i + 1}`).screenshot({ path: `${out}/${name}.png` });
  console.log(`${out}/${name}.png`);
}
await browser.close();
