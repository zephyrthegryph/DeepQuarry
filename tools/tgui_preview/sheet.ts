/**
 * Assembles the contact-sheet page: bun tools/tgui_preview/sheet.ts <afterDir> <beforeDir> <outDir>
 * Copies the PNGs into <outDir>/after and <outDir>/before and writes <outDir>/index.html (before/after pairs first, then every after shot).
 */
import { copyFileSync, mkdirSync, readdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const [afterDir, beforeDir, outDir] = process.argv.slice(2).map((p) => path.resolve(p));
const pngs = (d: string) => readdirSync(d).filter((f) => f.endsWith('.png')).sort();
for (const [src, sub] of [[afterDir, 'after'], [beforeDir, 'before']] as const) {
  mkdirSync(path.join(outDir, sub), { recursive: true });
  for (const f of pngs(src)) copyFileSync(path.join(src, f), path.join(outDir, sub, f));
}
const before = new Set(pngs(beforeDir));
const name = (f: string) => f.replace(/\.png$/, '');
const pairs = pngs(afterDir).filter((f) => before.has(f)).map((f) => `<section class="pair"><h3>${name(f)}</h3><div><figure><figcaption>before (default theme)</figcaption><img src="before/${f}"></figure><figure><figcaption>after (console)</figcaption><img src="after/${f}"></figure></div></section>`).join('\n');
const all = pngs(afterDir).map((f) => `<figure><figcaption>${name(f)}</figcaption><img loading="lazy" src="after/${f}"></figure>`).join('\n');
writeFileSync(path.join(outDir, 'index.html'), `<!doctype html><html><head><meta charset="utf-8"><title>Console theme preview</title>
<style>body{background:#111;color:#cde;font:14px monospace;margin:16px}h1,h2{color:#8bf}figure{margin:0;display:inline-block;vertical-align:top}
figcaption{color:#9ab;margin:4px 0}img{max-width:100%;border:1px solid #384e68}.pair>div{display:flex;gap:16px;flex-wrap:wrap}.grid{display:flex;gap:16px;flex-wrap:wrap}</style></head><body>
<h1>Console theme preview</h1><p>Rendered from the renderAll fixtures (tools/tgui_preview). Game sprite images (dm icon) are not available in this harness.</p>
<h2>Before / after</h2>${pairs}<h2>Contact sheet (${pngs(afterDir).length} windows)</h2><div class="grid">${all}</div></body></html>`);
