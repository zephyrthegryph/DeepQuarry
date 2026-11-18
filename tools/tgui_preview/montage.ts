/**
 * Packs a render run's shots into labelled-by-order grid PNGs, for reviewing many windows at once (an agent can Read one image
 * instead of forty). doc/tgui_preview.md.
 *
 *   bun tools/tgui_preview/montage.ts <runDir> [--per 12] [--scale 0.5] [--narrow] [--only-problems]
 *
 * Writes <runDir>/montage/NN.png and NN.txt (the shot names in grid order, left to right, top to bottom).
 */
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { decodePng, encodePng } from './png';

const args = process.argv.slice(2);
const opt = (n: string, d: string) =>
  args.includes(n) ? args[args.indexOf(n) + 1] : d;
const run = path.resolve(args[0]);
const per = Number(opt('--per', '12'));
const scale = Number(opt('--scale', '0.5'));
const report = JSON.parse(readFileSync(path.join(run, 'report.json'), 'utf8'));
const shots: string[] = report.results
  .filter((r: any) =>
    args.includes('--narrow')
      ? r.tag.includes('@narrow')
      : !r.tag.includes('@narrow'),
  )
  .filter((r: any) => !args.includes('--only-problems') || r.problems.length)
  .map((r: any) => r.file);
const outDir = path.join(run, 'montage');
rmSync(outDir, { recursive: true, force: true });
mkdirSync(outDir, { recursive: true });
const COLS = 4;
const CELL_W = Math.round(560 * scale);
const CELL_H = Math.round(720 * scale);
for (let page = 0; page * per < shots.length; page++) {
  const names = shots.slice(page * per, (page + 1) * per);
  const rows = Math.ceil(names.length / COLS);
  const W = COLS * (CELL_W + 4);
  const H = rows * (CELL_H + 4);
  const out = new Uint8Array(W * H * 4);
  for (let i = 3; i < out.length; i += 4) out[i] = 255;
  names.forEach((f, i) => {
    const img = decodePng(readFileSync(path.join(run, f)));
    const s = Math.min(scale, CELL_W / img.width, CELL_H / img.height);
    const w = Math.floor(img.width * s);
    const h = Math.floor(img.height * s);
    const ox = (i % COLS) * (CELL_W + 4);
    const oy = Math.floor(i / COLS) * (CELL_H + 4);
    for (let y = 0; y < h; y++)
      for (let x = 0; x < w; x++) {
        const sx = Math.min(img.width - 1, Math.floor(x / s));
        const sy = Math.min(img.height - 1, Math.floor(y / s));
        const from = (sy * img.width + sx) * 4;
        const to = ((oy + y) * W + ox + x) * 4;
        out.set(img.data.subarray(from, from + 4), to);
      }
  });
  const id = String(page + 1).padStart(2, '0');
  writeFileSync(path.join(outDir, `${id}.png`), encodePng(W, H, out));
  writeFileSync(
    path.join(outDir, `${id}.txt`),
    names.map((n, i) => `${i + 1}. ${n}`).join('\n'),
  );
}
console.log(`${Math.ceil(shots.length / per)} montages in ${outDir}`);
