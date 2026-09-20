import { chromium } from 'playwright';
import path from 'path';
import { fileURLToPath, pathToFileURL } from 'url';
import fs from 'fs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.join(__dirname, 'out');
const htmlUrl = pathToFileURL(path.join(__dirname, 'frame.html')).href;
fs.mkdirSync(outDir, { recursive: true });

const FRAME_SLUGS = {
  1: '01-dial-burst',
  2: '02-ao-cta',
  3: '03-recipe-dials',
  4: '04-field-look',
  5: '05-ready-pan',
};

const SIZES = [
  { key: '67', w: 1290, h: 2796, prefix: 'iphone-67' },
  { key: '61', w: 1179, h: 2556, prefix: 'iphone-61' },
];

const browser = await chromium.launch({ headless: true });
for (const frame of [1, 2, 3, 4, 5]) {
  for (const size of SIZES) {
    const page = await browser.newPage({
      viewport: { width: size.w, height: size.h },
      deviceScaleFactor: 1,
    });
    await page.goto(`${htmlUrl}?frame=${frame}&size=${size.key}`, { waitUntil: 'networkidle' });
    await page.waitForFunction(() => window.__READY__ === true);
    await page.evaluate(async () => { if (document.fonts?.ready) await document.fonts.ready; });
    await page.waitForTimeout(500);
    const fileName = `${size.prefix}-${FRAME_SLUGS[frame]}.png`;
    await page.locator('#ad').screenshot({ path: path.join(outDir, fileName), type: 'png' });
    console.log('OK', fileName);
    await page.close();
  }
}
await browser.close();
console.log('Done — 10 PNGs in', outDir);
