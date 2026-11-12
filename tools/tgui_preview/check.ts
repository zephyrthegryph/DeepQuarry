/**
 * Alignment check over every window that has a fixture (tgui/packages/tgui/preview/alignment.ts runs in the page).
 *
 *   bun tools/tgui_preview/check.ts --out <dir> [--reuse <bundleDir>] [--no-shots] [Window ...]
 *
 * Builds the preview bundle (unless --reuse), loads each window in an iframe of its own size inside one headless
 * Chrome page, collects the findings, and writes <dir>/alignment.json plus <dir>/issues/<Window>.png (the window with
 * every finding outlined). Windows that carry a theme of their own are skipped: only the console look is checked.
 * Exit status is 1 when anything was found.
 */
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = path.resolve(import.meta.dirname, '..', '..');
const tgui = path.join(root, 'tgui');
const CHROME = process.env.CHROME ?? 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const args = process.argv.slice(2);
const opt = (n: string) => (args.indexOf(n) >= 0 ? args[args.indexOf(n) + 1] : undefined);
const out = path.resolve(opt('--out') ?? path.join(root, 'data', 'tgui_alignment'));
const reuse = opt('--reuse');
const injectCss = opt('--css') ?? '';
const names = args.filter((a, i) => !a.startsWith('--') && args[i - 1] !== '--out' && args[i - 1] !== '--reuse' && args[i - 1] !== '--css');
mkdirSync(out, { recursive: true });

const bundle = reuse ? path.resolve(reuse) : path.join(out, 'bundle');
if (!reuse) {
  const r = spawnSync('bun', [path.join(root, 'tools/tgui_preview/shoot.ts'), '--out', out, '--build-only'], { stdio: 'inherit' });
  if (r.status !== 0) throw new Error('bundle build failed');
}

const fixtures = JSON.parse(readFileSync(path.join(tgui, 'packages/tgui/interfaces/__fixtures__/ui_data.json'), 'utf8'));
const written = readdirSync(path.join(tgui, 'packages/tgui/interfaces/__fixtures__/windows')).map((f) => f.replace(/\.json$/, ''));
const all = [...new Set([...Object.keys(fixtures), ...written])].sort();
const targets = names.length ? names : all;

const { buildWindowGeometryManifest } = await import(pathToFileURL(path.join(tgui, 'windowGeometryManifest.ts')).href);
const geometry = buildWindowGeometryManifest(path.join(tgui, 'packages/tgui/interfaces'));
// A window is laid out at the size it asks the game for (its Window width/height); the manifest size, read from the source text, is the fallback.
const jobs = targets.map((n) => ({ name: n, width: geometry[n]?.width ?? 560, height: geometry[n]?.height ?? 640}));

type Row = { name: string; theme: string; findings: unknown[]; size?: [number, number] };
const results = new Map<string, Row>();
let finish: () => void = () => {};
const done = new Promise<void>((r) => (finish = r));

const driver = `<!doctype html><body style="margin:0"><script>
const jobs = ${JSON.stringify(jobs)};
const post = (path, body) => fetch(path, { method: 'POST', body: JSON.stringify(body) });
let next = 0, active = 0;
function start() {
  while (active < 6 && next < jobs.length) run(jobs[next++]);
  if (next >= jobs.length && active === 0) post('/done', {});
}
function run(job) {
  active++;
  const f = document.createElement('iframe');
  f.style.cssText = 'border:0;position:absolute;left:0;top:0;width:' + job.width + 'px;height:' + job.height + 'px';
  let settled = false;
  const finishJob = (row) => {
    if (settled) return; settled = true;
    window.removeEventListener('message', onMsg);
    f.remove(); post('/result', row).then(() => { active--; start(); });
  };
  const onMsg = (e) => {
    if (e.source !== f.contentWindow) return;
    if (e.data.sizeRequest) {
      // 256x256 is the shell's default before a window has stated its own size.
      if (e.data.sizeRequest[0] === 256 && e.data.sizeRequest[1] === 256) return;
      job.size = e.data.sizeRequest;
      f.style.width = job.size[0] + 'px'; f.style.height = job.size[1] + 'px';
      return;
    }
    e.data.size = job.size;
    finishJob(e.data);
  };
  window.addEventListener('message', onMsg);
  setTimeout(() => finishJob({ name: job.name, theme: 'timeout', findings: [] }), 15000);
  f.src = '/index.html?w=' + job.name + '&check=1' + ${JSON.stringify(injectCss ? '&css=' : '')} + encodeURIComponent(${JSON.stringify(injectCss)});
  document.body.appendChild(f);
}
start();
</script></body>`;

const server = Bun.serve({
  port: 0,
  fetch: async (req) => {
    const url = new URL(req.url);
    if (url.pathname === '/driver.html') return new Response(driver, { headers: { 'content-type': 'text/html' } });
    if (url.pathname === '/result') {
      const row = JSON.parse(await req.text()) as Row;
      results.set(row.name, row);
      return new Response('ok');
    }
    if (url.pathname === '/done') {
      finish();
      return new Response('ok');
    }
    const file = Bun.file(path.join(bundle, decodeURIComponent(url.pathname)));
    return file.size ? new Response(file) : new Response('not found', { status: 404 });
  },
});

const profile = path.join(out, 'chrome-profile');
const chrome = Bun.spawn(
  [CHROME, '--headless=new', '--disable-gpu', `--user-data-dir=${profile}`, '--window-size=1400,1000', `http://localhost:${server.port}/driver.html`],
  { stdout: 'ignore', stderr: 'ignore' },
);
await Promise.race([done, Bun.sleep(25 * 60 * 1000)]);
chrome.kill();
server.stop(true);

// The size each window asked for, for the screenshots (shoot.ts --sizes).
const sizes: Record<string, [number, number]> = {};
for (const job of jobs) {
  const row = results.get(job.name);
  sizes[job.name] = row?.size ?? [job.width, job.height];
}
writeFileSync(path.join(out, 'sizes.json'), JSON.stringify(sizes));
const byRule: Record<string, number> = {};
const windows: Record<string, unknown[]> = {};
let checked = 0;
const skipped: Record<string, string> = {};
for (const job of jobs) {
  const row = results.get(job.name);
  if (!row) {
    skipped[job.name] = 'no result';
    continue;
  }
  if (!row.theme.includes('theme-console')) {
    skipped[job.name] = row.theme || 'no theme';
    continue;
  }
  checked++;
  if (row.findings.length) windows[job.name] = row.findings;
  for (const f of row.findings as Array<{ rule: string }>) byRule[f.rule] = (byRule[f.rule] ?? 0) + 1;
}
const total = Object.values(byRule).reduce((a, b) => a + b, 0);
writeFileSync(path.join(out, 'alignment.json'), JSON.stringify({ checked, total, byRule, skipped, windows }, null, 1));
console.log(`checked ${checked} windows, skipped ${Object.keys(skipped).length}, findings ${total}`, byRule);

if (!flagOff('--no-shots') && Object.keys(windows).length) {
  mkdirSync(path.join(out, 'issues'), { recursive: true });
  spawnSync('bun', [path.join(root, 'tools/tgui_preview/shoot.ts'), '--reuse', bundle, '--sizes', path.join(out, 'sizes.json'), '--mark', '--out', path.join(out, 'issues'), ...Object.keys(windows)], { stdio: 'inherit' });
}
process.exit(total ? 1 : 0);

function flagOff(n: string) {
  return args.includes(n);
}
