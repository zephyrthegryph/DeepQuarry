/**
 * Captures every window's real data and the game's spritesheets for the render preview. doc/tgui_preview.md.
 *
 *   bun tools/tgui_preview/capture.ts [--skip-bench]
 *
 * Runs the ui_census bench (tools/build/build.sh bench --scenario=ui_census; it builds each declared window for a dummy viewer,
 * generates every spritesheet and writes data/tgui_fixtures/census.json), then:
 *  - writes tgui/packages/tgui/interfaces/__fixtures__/captured/<Window>.json, one per window, with volatile values made stable
 *    (refs renumbered per window, the dummy's random name, clock readings zeroed) so a recapture only diffs where the data changed;
 *  - copies the generated spritesheets (CSS + PNG) into E:/dq-cache/tgui-preview/sprites with their URLs pointed at the copies, and
 *    writes sprites/index.json (asset name -> URL, the CSS list) for the preview page.
 * --skip-bench reuses the last census output.
 */
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..', '..');
const CACHE = process.env.DQ_TGUI_PREVIEW_CACHE ?? 'E:/dq-cache/tgui-preview';
const fixturesDir = path.join(
  root,
  'tgui/packages/tgui/interfaces/__fixtures__/captured',
);
const censusFile = path.join(root, 'data/tgui_fixtures/census.json');
const metaFile = path.join(root, 'data/tgui_fixtures/census_meta.json');

if (!process.argv.includes('--skip-bench')) {
  const r = spawnSync(
    'bash',
    ['tools/build/build.sh', 'bench', '--scenario=ui_census'],
    { cwd: root, stdio: 'inherit' },
  );
  if (r.status !== 0)
    console.warn(`capture: the bench exited ${r.status}; using what it wrote`);
}
if (!existsSync(censusFile))
  throw new Error(`${censusFile} is missing: the census did not run`);
const census: Record<string, unknown> = JSON.parse(
  readFileSync(censusFile, 'utf8'),
);
const meta = JSON.parse(readFileSync(metaFile, 'utf8'));

// ---- fixtures ----------------------------------------------------------------------------------------------------------------
/** Keys whose numbers are a clock reading: zeroed so each capture is the same. */
const CLOCK_KEY =
  /(^|_)(world_?time|time_?now|uptime|round_?time|station_?time|realtime|timeofday|server_?time|current_?time|tick|ticks|world_time_min|opened_at|elapsed(_s)?|last_run_ms|timeout_percent|remaining)$/i;
/** Keys whose numbers are an instance id (a datum's numeric ref): renumbered per window, in order of appearance. */
const NUM_REF_KEY = /(^|_)ref$/i;
const REF = /^\[0x[0-9a-f]+\]$/i;
function stable(window: string, data: unknown): unknown {
  const refs = new Map<string, string>();
  const numRefs = new Map<number, number>();
  const name = String(meta.user_name ?? '');
  const walk = (v: unknown, key = ''): unknown => {
    if (typeof v === 'string') {
      if (REF.test(v)) {
        if (!refs.has(v))
          refs.set(v, `[0x${(refs.size + 1).toString(16).padStart(7, '0')}]`);
        return refs.get(v);
      }
      if (key === 'session') return 'session';
      // A ref inside a longer string (a map control's id): renumbered the same way.
      const inner = v.replace(/\[0x[0-9a-f]+\]/gi, (r) => String(walk(r)));
      return name && inner.includes(name)
        ? inner.split(name).join('Test Subject')
        : inner;
    }
    if (typeof v === 'number' && CLOCK_KEY.test(key)) return 0;
    if (typeof v === 'number' && NUM_REF_KEY.test(key)) {
      if (!numRefs.has(v)) numRefs.set(v, numRefs.size + 1);
      return numRefs.get(v);
    }
    if (Array.isArray(v)) return v.map((x) => walk(x));
    if (v && typeof v === 'object') {
      const o: Record<string, unknown> = {};
      for (const [k, x] of Object.entries(v))
        o[REF.test(k) ? String(walk(k)) : k] = walk(x, k);
      return o;
    }
    return v;
  };
  return walk(data, window);
}
mkdirSync(fixturesDir, { recursive: true });
const before = new Set(readdirSync(fixturesDir));
let written = 0;
for (const [window, data] of Object.entries(census)) {
  if (
    !/^[A-Za-z0-9_]+$/.test(window) ||
    !data ||
    typeof data !== 'object' ||
    Array.isArray(data)
  )
    continue;
  writeFileSync(
    path.join(fixturesDir, `${window}.json`),
    `${JSON.stringify(stable(window, data), null, '\t')}\n`,
  );
  before.delete(`${window}.json`);
  written++;
}
// A window the census no longer builds loses its capture (the hand-written fixtures are untouched).
for (const stale of before)
  if (stale.endsWith('.json')) rmSync(path.join(fixturesDir, stale));
console.log(
  `capture: ${written} window fixtures in ${path.relative(root, fixturesDir)} (${before.size} stale removed)`,
);

// ---- sprites -----------------------------------------------------------------------------------------------------------------
const sheetDir = path.resolve(
  root,
  String(meta.spritesheet_dir ?? 'data/spritesheets/'),
);
const spritesOut = path.join(CACHE, 'sprites');
rmSync(spritesOut, { recursive: true, force: true });
mkdirSync(spritesOut, { recursive: true });
const byHash = new Map<string, string>();
const mappings: Record<string, string> = {};
const css: string[] = [];
// The batched sheets sit in the folder as sent (spritesheet_<name>.css, <name>_<size>.png); the legacy sheets keep their copies in
// legacy_cache as spritesheet.<name>.css / spritesheet.<name>_<size>.png: both are read under their sent names.
const sources = new Map<string, string>();
const legacy = path.join(sheetDir, 'legacy_cache');
if (existsSync(legacy))
  for (const f of readdirSync(legacy)) {
    const m = f.match(/^spritesheet\.(.+)\.(css|png)$/);
    if (m)
      sources.set(
        m[2] === 'css' ? `spritesheet_${m[1]}.css` : `${m[1]}.png`,
        path.join(legacy, f),
      );
  }
if (existsSync(sheetDir))
  for (const f of readdirSync(sheetDir))
    if (/\.(png|css)$/.test(f)) sources.set(f, path.join(sheetDir, f));
const files = [...sources.keys()];
for (const f of files.filter((x) => x.endsWith('.png'))) {
  const buf = readFileSync(sources.get(f)!);
  writeFileSync(path.join(spritesOut, f), buf);
  byHash.set(createHash('md5').update(buf).digest('hex'), f);
  mappings[f] = `sprites/${f}`;
}
// Every other image/data asset the census exported (simple assets, generated program icons, a pod's idle frame), under its asset name.
const exported = path.join(root, 'data/tgui_fixtures/assets');
let assets = 0;
if (existsSync(exported))
  for (const f of readdirSync(exported)) {
    if (sources.has(f)) continue;
    writeFileSync(
      path.join(spritesOut, f),
      readFileSync(path.join(exported, f)),
    );
    mappings[f] = `sprites/${f}`;
    assets++;
  }
console.log(`capture: ${assets} exported assets`);
let unresolved = 0;
for (const f of files.filter((x) => x.endsWith('.css'))) {
  // A sheet's CSS names its PNGs by the transport's URL (asset.<md5>.png) or a %name% placeholder: point both at the copies.
  const text = readFileSync(sources.get(f)!, 'utf8').replace(
    /url\(['"]?([^'")]+)['"]?\)/g,
    (all, url: string) => {
      const md5 = url.match(/asset\.([0-9a-f]{32})\./)?.[1];
      const named = url.match(/^%(.+)%$/)?.[1];
      const file =
        (md5 && byHash.get(md5)) ||
        (named && mappings[named] ? named : undefined);
      if (!file) {
        unresolved++;
        return all;
      }
      return `url('${file}')`;
    },
  );
  writeFileSync(path.join(spritesOut, f), text);
  mappings[f] = `sprites/${f}`;
  css.push(`sprites/${f}`);
}
writeFileSync(
  path.join(spritesOut, 'index.json'),
  JSON.stringify({ css, mappings }, null, 1),
);
console.log(
  `capture: ${css.length} spritesheets (${Object.keys(mappings).length - css.length} PNGs, ${unresolved} unresolved URLs) in ${spritesOut}`,
);
