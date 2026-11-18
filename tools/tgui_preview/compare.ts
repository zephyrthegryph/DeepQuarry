/**
 * A before/after contact sheet for two render runs (tools/tgui_preview/render.ts). doc/tgui_preview.md.
 *
 *   bun tools/tgui_preview/compare.ts <beforeRun> <afterRun> [--out <dir>] [--threshold 0.005]
 *
 * Pairs every shot present in both runs whose pixels differ by more than the threshold (render.ts's measure), side by side and
 * worst first, and lists the shots only one run has. Writes <out>/index.html (default <afterRun>/compare) with the PNGs copied
 * beside it, so the folder can be opened or shared on its own.
 */
import {
  cpSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';
import { decodePng, diffRatio } from './png';

const args = process.argv.slice(2);
const opt = (n: string) =>
  args.includes(n) ? args[args.indexOf(n) + 1] : undefined;
const [beforeDir, afterDir] = args
  .filter(
    (a, i) =>
      !a.startsWith('--') && !['--out', '--threshold'].includes(args[i - 1]),
  )
  .map((p) => path.resolve(p));
const out = path.resolve(opt('--out') ?? path.join(afterDir, 'compare'));
const threshold = Number(opt('--threshold') ?? 0.005);
const pngs = (d: string) =>
  new Set(readdirSync(d).filter((f) => f.endsWith('.png')));
const before = pngs(beforeDir);
const after = pngs(afterDir);
mkdirSync(path.join(out, 'before'), { recursive: true });
mkdirSync(path.join(out, 'after'), { recursive: true });

const report = (d: string) => {
  const p = path.join(d, 'report.json');
  if (!existsSync(p)) return new Map<string, string[]>();
  return new Map<string, string[]>(
    JSON.parse(readFileSync(p, 'utf8')).results.map((r: any) => [
      r.file,
      r.problems,
    ]),
  );
};
const problemsBefore = report(beforeDir);
const problemsAfter = report(afterDir);
const changed: Array<{ file: string; diff: number }> = [];
for (const f of after) {
  if (!before.has(f)) continue;
  const diff = diffRatio(
    decodePng(readFileSync(path.join(beforeDir, f))),
    decodePng(readFileSync(path.join(afterDir, f))),
  );
  if (diff > threshold) changed.push({ file: f, diff });
}
changed.sort((a, b) => b.diff - a.diff);
const added = [...after].filter((f) => !before.has(f)).sort();
for (const { file } of changed) {
  cpSync(path.join(beforeDir, file), path.join(out, 'before', file));
  cpSync(path.join(afterDir, file), path.join(out, 'after', file));
}
for (const f of added)
  cpSync(path.join(afterDir, f), path.join(out, 'after', f));

const esc = (s: string) => s.replace(/[&<>"]/g, (c) => `&#${c.charCodeAt(0)};`);
const chips = (p: string[] | undefined) =>
  (p ?? []).map((x) => `<span class="chip">${esc(x)}</span>`).join(' ');
const name = (f: string) => esc(f.replace(/\.png$/, ''));
const pair = ({
  file,
  diff,
}: {
  file: string;
  diff: number;
}) => `<section><h3>${name(file)} <small>${(diff * 100).toFixed(1)}% of pixels changed</small></h3>
<div class="pair"><figure><figcaption>before ${chips(problemsBefore.get(file))}</figcaption><img loading="lazy" src="before/${encodeURI(file)}"></figure>
<figure><figcaption>after ${chips(problemsAfter.get(file))}</figcaption><img loading="lazy" src="after/${encodeURI(file)}"></figure></div></section>`;
writeFileSync(
  path.join(out, 'index.html'),
  `<!doctype html><html><head><meta charset="utf-8"><title>tgui before / after</title>
<style>body{background:#0d1117;color:#c9d1d9;font:13px system-ui,sans-serif;margin:16px}h1{font-size:18px}h3{margin:18px 0 6px}small{color:#8b949e;font-weight:normal}
.pair{display:flex;gap:16px;flex-wrap:wrap;align-items:flex-start}figure{margin:0}figcaption{margin:4px 0;color:#8b949e}img{display:block;max-width:min(560px,90vw);border:1px solid #30363d}
.chip{background:#3d1d20;color:#ffa198;border-radius:8px;padding:0 6px;font-size:11px}.grid{display:flex;gap:12px;flex-wrap:wrap}</style></head><body>
<h1>tgui before / after: ${changed.length} windows changed, ${added.length} new shots</h1>
<p>Before: ${esc(beforeDir)}<br>After: ${esc(afterDir)}<br>Shots that differ by more than ${(threshold * 100).toFixed(1)}% of their pixels, most changed first.</p>
${changed.map(pair).join('\n')}
<h2>New shots (presets and windows the before run had no fixture for)</h2>
<div class="grid">${added.map((f) => `<figure><figcaption>${name(f)} ${chips(problemsAfter.get(f))}</figcaption><img loading="lazy" src="after/${encodeURI(f)}" style="max-width:360px"></figure>`).join('\n')}</div>
</body></html>`,
);
console.log(
  `${changed.length} changed, ${added.length} new: ${path.join(out, 'index.html')}`,
);
