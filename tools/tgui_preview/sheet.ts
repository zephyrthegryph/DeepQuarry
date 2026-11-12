/**
 * Assembles the contact-sheet page: bun tools/tgui_preview/sheet.ts <afterDir> <beforeDir> <outDir>
 * Writes <outDir>/index.html as ONE self-contained file: every PNG is embedded as a data: URI (before/after pairs first, then every after shot).
 */
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const [afterDir, beforeDir, outDir] = process.argv.slice(2).map((p) => path.resolve(p));
const pngs = (d: string) => readdirSync(d).filter((f) => f.endsWith('.png')).sort();
mkdirSync(outDir, { recursive: true });
const uri = (dir: string, f: string) => `data:image/png;base64,${readFileSync(path.join(dir, f)).toString('base64')}`;
const before = new Set(pngs(beforeDir));
const name = (f: string) => f.replace(/\.png$/, '');
const pairs = pngs(afterDir).filter((f) => before.has(f)).map((f) => `<section class="pair"><h3>${name(f)}</h3><div><figure><figcaption>before (default theme)</figcaption><img src="${uri(beforeDir, f)}"></figure><figure><figcaption>after (console)</figcaption><img src="${uri(afterDir, f)}"></figure></div></section>`).join('\n');
const all = pngs(afterDir).map((f) => `<figure><figcaption>${name(f)}</figcaption><img loading="lazy" src="${uri(afterDir, f)}"></figure>`).join('\n');
writeFileSync(path.join(outDir, 'index.html'), `<!doctype html><html><head><meta charset="utf-8"><title>Console theme preview</title>
<style>body{background:#111;color:#cde;font:14px monospace;margin:16px}h1,h2{color:#8bf}figure{margin:0;display:inline-block;vertical-align:top}
figcaption{color:#9ab;margin:4px 0}img{max-width:100%;border:1px solid #384e68}.pair>div{display:flex;gap:16px;flex-wrap:wrap}.grid{display:flex;gap:16px;flex-wrap:wrap}</style></head><body>
<h1>Console theme preview</h1><p>Rendered from the renderAll fixtures (tools/tgui_preview). Game sprite images (dm icon) are not available in this harness.</p>
<h2>Before / after</h2>${pairs}<h2>Contact sheet (${pngs(afterDir).length} windows)</h2><div class="grid">${all}</div></body></html>`);
