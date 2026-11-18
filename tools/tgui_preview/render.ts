/**
 * Renders tgui windows from their fixtures in headless Chrome (or Edge) and checks each render. doc/tgui_preview.md.
 *
 *   bun tools/tgui_preview/render.ts [filter ...] [--out <dir>] [--reuse] [--jobs N] [--widths std,narrow] [--theme <name>]
 *                                    [--baseline <dir>] [--save-baseline <dir>] [--threshold 0.005] [--no-check]
 *
 * A filter is a window name, a `Window.variant`, or a substring (`Ntos`); none renders every fixture the bundle holds (hand-written
 * presets, census captures, the unit-test capture). One browser, N pages in parallel, each page sized to the window's own
 * <Window width height> (and to 360 px wide for `narrow`). Writes <out>/<Window>[.<variant>][@narrow].png, <out>/report.json and
 * <out>/index.html (the contact sheet: every shot with its problems). Problems: a JS exception, a console error, a blank render
 * (one colour covers >= 99% of the shot, or no text), a missing window export, horizontal overflow, elements running off the right edge.
 * --baseline compares each shot with the same file there (pixel share differing by more than 16/255 in any channel, over
 * --threshold) and reports REGRESSED shots; --save-baseline copies this run's shots there. Exit 1 when anything failed.
 * The bundle (E:/dq-cache/tgui-preview/bundle) is rebuilt unless --reuse; sprites come from E:/dq-cache/tgui-preview/sprites
 * (tools/tgui_preview/capture.ts) and .dmi frames from icons/gen.
 */
import { spawn, spawnSync } from 'node:child_process';
import {
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  type Dmi,
  decodePng,
  diffRatio,
  dmiFrame,
  dominantShare,
  parseDmi,
} from './png';

const root = path.resolve(import.meta.dirname, '..', '..');
const tgui = path.join(root, 'tgui');
const CACHE = process.env.DQ_TGUI_PREVIEW_CACHE ?? 'E:/dq-cache/tgui-preview';
const BROWSERS = [
  process.env.CHROME,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
].filter(Boolean) as string[];
const NARROW = 360;
/** Space (CSS px) a window may leave under or need beyond its content before the fit check reports it. */
const FIT_SLACK = 16;
/** The filling entry's minimum body height in the column (tgui-panel/column/model.ts FILL_MIN). */
const DOCK_FILL_MIN = 160;
/** Windows that draw nothing on purpose (an audio host, a tooltip layer, a screen overlay): never "blank". */
const NO_UI = new Set(['MediaPlayer', 'Tooltip', 'BellyOverlay']);

const args = process.argv.slice(2);
const valued = new Set([
  '--bundle',
  '--out',
  '--jobs',
  '--widths',
  '--theme',
  '--baseline',
  '--save-baseline',
  '--threshold',
  '--label',
]);
const opt = (n: string) =>
  args.includes(n) ? args[args.indexOf(n) + 1] : undefined;
const flag = (n: string) => args.includes(n);
const filters = args.filter(
  (a, i) => !a.startsWith('--') && !valued.has(args[i - 1]),
);
const out = path.resolve(
  opt('--out') ?? path.join(CACHE, 'runs', opt('--label') ?? 'latest'),
);
const jobsN = Number(opt('--jobs') ?? 6);
const widths = (opt('--widths') ?? 'std,narrow').split(',');
const theme = opt('--theme');
const threshold = Number(opt('--threshold') ?? 0.005);
const baselineDir = opt('--baseline')
  ? path.resolve(opt('--baseline')!)
  : undefined;
const bundle = path.resolve(opt('--bundle') ?? path.join(CACHE, 'bundle'));
const sprites =
  process.env.DQ_TGUI_SPRITES ?? 'E:/dq-cache/tgui-sprites/current';
if (!existsSync(path.join(sprites, 'index.json')))
  console.warn(
    `no sprite cache at ${sprites} (evicted or never made): sprites and game images will be missing; run bun tools/tgui_preview/capture.ts`,
  );

// ---- bundle ----------------------------------------------------------------------------------------------------------------
if (!flag('--reuse') || !existsSync(path.join(bundle, 'index.html'))) {
  const t0 = Date.now();
  const r = spawnSync(
    'bunx',
    ['rspack', 'build', '-c', 'rspack.preview.config.ts'],
    {
      cwd: tgui,
      stdio: ['ignore', 'ignore', 'inherit'],
      shell: true,
      env: { ...process.env, PREVIEW_OUT: bundle },
    },
  );
  if (r.status !== 0) throw new Error('preview bundle build failed');
  cpSync(
    path.join(root, 'html', 'font-awesome'),
    path.join(bundle, 'font-awesome'),
    { recursive: true },
  );
  cpSync(
    path.join(bundle, 'font-awesome', 'webfonts'),
    path.join(bundle, 'font-awesome', 'css'),
    { recursive: true },
  );
  console.log(`bundle built in ${((Date.now() - t0) / 1000).toFixed(1)} s`);
}

// ---- server ----------------------------------------------------------------------------------------------------------------
const dmiCache = new Map<string, Dmi | null>();
function dmiFor(rel: string): Dmi | null {
  if (dmiCache.has(rel)) return dmiCache.get(rel)!;
  let dmi: Dmi | null = null;
  for (const p of [
    path.join(root, 'icons', 'gen', rel),
    path.join(root, rel),
  ]) {
    if (existsSync(p)) {
      try {
        dmi = parseDmi(readFileSync(p));
      } catch {}
      break;
    }
  }
  dmiCache.set(rel, dmi);
  return dmi;
}
const missingSprites = new Set<string>();
// Files a window fetches by bare name that ship in the repo rather than the asset cache (the changelog archive).
const repoFiles = new Map<string, string>();
for (const f of spawnSync('git', ['ls-files', 'html/changelogs/archive'], {
  cwd: root,
  encoding: 'utf8',
}).stdout.split('\n'))
  if (f) repoFiles.set(path.basename(f), path.join(root, f));
const server = Bun.serve({
  port: 0,
  fetch(req) {
    const url = new URL(req.url);
    const pathname = decodeURIComponent(url.pathname);
    if (pathname.startsWith('/dmi/')) {
      const rel = pathname.slice(5);
      const dmi = dmiFor(rel);
      const q = url.searchParams;
      const png =
        dmi &&
        dmiFrame(
          dmi,
          q.get('state') ?? '',
          Number(q.get('dir') ?? 2),
          Number(q.get('frame') ?? 1),
        );
      if (!png) {
        missingSprites.add(`${rel}:${q.get('state')}`);
        return new Response('no such state', { status: 404 });
      }
      return new Response(png, { headers: { 'content-type': 'image/png' } });
    }
    const base = pathname.startsWith('/sprites/') ? sprites : bundle;
    const rel = pathname.startsWith('/sprites/') ? pathname.slice(9) : pathname;
    if (/\.(ogg|mp3|wav)$/.test(rel))
      return new Response(new Uint8Array(0), {
        headers: { 'content-type': 'audio/ogg' },
      }); // sounds: silence
    const file = Bun.file(
      repoFiles.get(rel.replace(/^\//, '')) ?? path.join(base, rel),
    );
    return file.size
      ? new Response(file)
      : new Response('not found', { status: 404 });
  },
});
const origin = `http://localhost:${server.port}`;

// ---- browser (Chrome DevTools Protocol over one WebSocket) -----------------------------------------------------------------
const exe = BROWSERS.find((b) => existsSync(b));
if (!exe) throw new Error('no Chrome or Edge found (set CHROME)');
const profile = path.join(CACHE, 'chrome');
mkdirSync(profile, { recursive: true });
// A fresh profile every run: windows recall their geometry from storage, so a kept profile lays a window out at an old size.
rmSync(profile, { recursive: true, force: true });
mkdirSync(profile, { recursive: true });
const browser = spawn(
  exe,
  [
    '--headless=new',
    '--disable-gpu',
    '--hide-scrollbars',
    '--remote-debugging-port=0',
    `--user-data-dir=${profile}`,
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-background-timer-throttling',
    '--disable-renderer-backgrounding',
    '--disable-backgrounding-occluded-windows',
    '--disable-extensions',
    '--mute-audio',
    'about:blank',
  ],
  { stdio: 'ignore' },
);
let portFile = '';
for (let i = 0; i < 200 && !portFile; i++) {
  try {
    portFile = readFileSync(path.join(profile, 'DevToolsActivePort'), 'utf8');
  } catch {
    await Bun.sleep(50);
  }
}
if (!portFile) throw new Error('the browser did not open its DevTools port');
const [port, wsPath] = portFile.trim().split('\n');
const ws = new WebSocket(`ws://127.0.0.1:${port}${wsPath}`);
await new Promise((r, e) => {
  ws.onopen = r;
  ws.onerror = e;
});
let nextId = 1;
const pending = new Map<
  number,
  { ok: (v: any) => void; fail: (e: Error) => void }
>();
const listeners = new Map<string, (method: string, params: any) => void>();
ws.onmessage = (ev) => {
  const msg = JSON.parse(String(ev.data));
  if (msg.id && pending.has(msg.id)) {
    const p = pending.get(msg.id)!;
    pending.delete(msg.id);
    msg.error ? p.fail(new Error(msg.error.message)) : p.ok(msg.result);
  } else if (msg.sessionId && listeners.has(msg.sessionId))
    listeners.get(msg.sessionId)!(msg.method, msg.params);
};
function send(
  method: string,
  params: any = {},
  sessionId?: string,
): Promise<any> {
  const id = nextId++;
  ws.send(JSON.stringify({ id, method, params, sessionId }));
  return new Promise((ok, fail) => pending.set(id, { ok, fail }));
}

// ---- targets ---------------------------------------------------------------------------------------------------------------
const { buildWindowGeometryManifest } = await import(
  pathToFileURL(path.join(tgui, 'windowGeometryManifest.ts')).href
);
const geometry: Record<string, { width: number; height: number }> =
  buildWindowGeometryManifest(path.join(tgui, 'packages/tgui/interfaces'));

async function openPage() {
  const { targetId } = await send('Target.createTarget', {
    url: 'about:blank',
    newWindow: true,
  });
  const { sessionId } = await send('Target.attachToTarget', {
    targetId,
    flatten: true,
  });
  await send('Runtime.enable', {}, sessionId);
  await send('Page.enable', {}, sessionId);
  await send('Log.enable', {}, sessionId);
  return { targetId, sessionId };
}

const first = await openPage();
await send('Page.navigate', { url: `${origin}/index.html` }, first.sessionId);
await Bun.sleep(300);
const listing = await send(
  'Runtime.evaluate',
  {
    expression:
      'new Promise(r => { const t = () => window.previewFixtures ? r(window.previewFixtures()) : setTimeout(t, 50); t(); })',
    awaitPromise: true,
    returnByValue: true,
  },
  first.sessionId,
);
const all: Array<[string, string | null]> = listing.result.value;
const match = (w: string, v: string | null) => {
  if (!filters.length) return true;
  const id = v ? `${w}.${v}` : w;
  // An exact window or window.variant name, else a case-insensitive substring of either.
  return filters.some(
    (f) =>
      f === id ||
      f === w ||
      (!all.some(([x]) => x === f) &&
        id.toLowerCase().includes(f.toLowerCase())),
  );
};
type Job = {
  window: string;
  variant: string | null;
  width: number;
  height: number;
  tag: string;
  file: string;
  narrow: boolean;
  dock?: boolean;
};
const jobs: Job[] = [];
for (const [w, v] of all.filter(([w, v]) => match(w, v))) {
  const g = geometry[w] ?? { width: 400, height: 600 };
  for (const kind of widths) {
    if (kind === 'dock') {
      const tag = `${w}${v ? `.${v}` : ''}@dock`;
      jobs.push({
        window: w,
        variant: v,
        width: 600,
        height: 1000,
        tag,
        file: `${tag}.png`,
        narrow: false,
        dock: true,
      });
      continue;
    }
    const width = kind === 'narrow' ? Math.min(NARROW, g.width) : g.width;
    if (kind === 'narrow' && width === g.width && g.width <= NARROW) continue; // already narrow
    const tag = `${w}${v ? `.${v}` : ''}${kind === 'narrow' ? '@narrow' : ''}`;
    jobs.push({
      window: w,
      variant: v,
      width,
      height: g.height,
      tag,
      file: `${tag}.png`,
      narrow: kind === 'narrow',
    });
  }
}
console.log(
  `${jobs.length} renders of ${all.filter(([w, v]) => match(w, v)).length} fixtures, ${jobsN} pages, ${exe.includes('msedge') ? 'Edge' : 'Chrome'}`,
);
mkdirSync(out, { recursive: true });

type Result = Job & {
  problems: string[];
  errors: string[];
  ms: number;
  diff?: number;
  second?: Buffer;
};
const results: Result[] = [];
const PROBE = `(() => {
  const app = document.getElementById('app');
  const W = innerWidth;
  let offRight = 0;
  let sideScroll = 0;
  const offenders = [];
  for (const el of app.querySelectorAll('*')) {
    const r = el.getBoundingClientRect();
    if (!(r.width && r.height && r.right > W + 2)) continue;
    // A LabeledList is 1em wider than its box by design (negative margins line its rows up with the section edge).
    const list = el.closest('.LabeledList');
    if (list && r.right <= W + 2 + parseFloat(getComputedStyle(list).fontSize)) continue;
    const cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.pointerEvents === 'none') continue; // decoration (scanlines, vignettes)
    // Inside a scroll or clip box that itself fits, it is scrolled content (a carousel, a scrollable table), not overflow.
    let clipped = false;
    let scrolled = false;
    for (let p = el.parentElement; p && p !== app.parentElement; p = p.parentElement) {
      const o = getComputedStyle(p);
      if (/Layout|Window/.test(String(p.className))) continue; // the window's own scroller clips everything
      if (/Section__content/.test(String(p.className))) {
        // A section that scrolls sideways (the narrow-window fallback, styles/dq/narrow.scss): reachable, but worth a look.
        if (o.overflowX !== 'visible' && o.overflowX !== 'hidden' && p.getBoundingClientRect().right <= W + 2) { scrolled = true; break; }
        continue;
      }
      if (o.overflowX !== 'visible' && p.getBoundingClientRect().right <= W + 2) { clipped = true; break; }
    }
    if (scrolled) sideScroll++;
    else if (!clipped) {
      offRight++;
      offenders.push(el);
    }
  }
  // Sections with a title and nothing in them: an empty list with no word saying so (the wiki style says it: EmptyState).
  const emptySections = [];
  for (const sec of app.querySelectorAll('.Section')) {
    const title = sec.querySelector(':scope > .Section__title .Section__titleText');
    const content = sec.querySelector(':scope > .Section__rest > .Section__content');
    // A title-only section (a header bar with buttons, content collapsed) is a design, not an empty list.
    if (!title || !content || content.getBoundingClientRect().height < 20) continue;
    const hasText = (content.innerText || '').trim().length > 0;
    const hasThing = content.querySelector('img, canvas, svg, input, textarea, .Button, .ProgressBar, .NumberInput, .Knob, .ColorBox, .Slider, .Dropdown, .Tab, [class*="32x32"], [class*="64x64"]');
    if (!hasText && !hasThing && emptySections.length < 3) emptySections.push((title.textContent || '').trim().slice(0, 24));
    else if (!hasText && !hasThing) emptySections.push('');
  }
  // Broken images (a sprite or asset that did not load) and text drawn under 10px (unreadable on a game client).
  let brokenImg = 0;
  for (const img of app.querySelectorAll('img')) if (img.complete && !img.naturalWidth && img.getBoundingClientRect().width) brokenImg++;
  let tiny = 0;
  const tinyAt = [];
  const walker = document.createTreeWalker(app, NodeFilter.SHOW_TEXT);
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    if (!n.textContent.trim() || !n.parentElement) continue;
    const r = n.parentElement.getBoundingClientRect();
    if (r.width && parseFloat(getComputedStyle(n.parentElement).fontSize) < 10) { tiny++; if (tinyAt.length < 3) tinyAt.push(String(n.parentElement.className).split(' ')[0] || n.parentElement.tagName.toLowerCase()); }
  }
  return {
    brokenImg, tiny, tinyAt, emptySections,
    fit: window.__tguiFit ? window.__tguiFit() : null,
    autofit: document.documentElement.dataset.tguiAutofit || 'unknown',
    inner: innerHeight,
    text: (app.innerText || '').trim().length,
    nodes: app.querySelectorAll('*').length,
    missing: !!document.getElementById('preview-missing'),
    crashed: /An error has occurred|Uncaught|TypeError/.test(app.innerText || '') && !!app.querySelector('.Layout__content, .Window') === false,
    hOverflow: document.documentElement.scrollWidth > W + 1,
    offRight,
    sideScroll,
    // The innermost elements that run off (an ancestor only runs off because they do): the ones to fix.
    offenders: offenders
      .filter((el) => !offenders.some((o) => o !== el && el.contains(o)))
      .slice(0, 3)
      .map((el) => [el.className && String(el.className).split(' ')[0], el.tagName.toLowerCase(), (el.textContent || '').trim().slice(0, 18)].filter(Boolean).join(':')),
  };
})()`;

async function runJob(page: { sessionId: string }, job: Job): Promise<Result> {
  const t0 = Date.now();
  const errors: string[] = [];
  listeners.set(page.sessionId, (method, p) => {
    if (method === 'Runtime.exceptionThrown')
      errors.push(
        `exception: ${p.exceptionDetails?.exception?.description?.split('\n')[0] ?? p.exceptionDetails?.text}`,
      );
    else if (method === 'Runtime.consoleAPICalled' && p.type === 'error')
      errors.push(
        `console: ${p.args
          .map((a: any) => a.value ?? a.description ?? '')
          .join(' ')
          .slice(0, 200)}`,
      );
    else if (
      method === 'Log.entryAdded' &&
      p.entry.level === 'error' &&
      !/dmi\/|sprites\//.test(p.entry.url ?? '')
    )
      errors.push(`log: ${p.entry.text.slice(0, 120)} ${p.entry.url ?? ''}`);
  });
  await send(
    'Emulation.setDeviceMetricsOverride',
    {
      width: job.width,
      height: job.height,
      deviceScaleFactor: 1,
      mobile: false,
      // A 1080p screen: auto-fit clamps a window to 90% of the screen height (layouts/Window.tsx).
      screenWidth: 1920,
      screenHeight: 1080,
    },
    page.sessionId,
  );
  const q = new URLSearchParams({ w: job.window });
  if (job.variant) q.set('v', job.variant);
  if (job.dock) q.set('dock', '1');
  if (theme) q.set('theme', theme);
  // Animations run to their end at once and transitions are off, so a shot is the same every run (regression mode compares pixels).
  q.set(
    'css',
    '*,*::before,*::after{animation-duration:1ms!important;animation-iteration-count:1!important;animation-delay:0s!important;transition:none!important;caret-color:transparent!important}',
  );
  await send(
    'Page.navigate',
    { url: `${origin}/index.html?${q}` },
    page.sessionId,
  );
  const settle = await send(
    'Runtime.evaluate',
    {
      expression: `new Promise(r => { const s = Date.now(); const t = () => (window.previewReady || Date.now() - s > 8000) ? document.fonts.ready.then(() => setTimeout(() => r(!!window.previewReady), 400)) : setTimeout(t, 30); t(); })`,
      awaitPromise: true,
      returnByValue: true,
    },
    page.sessionId,
  ).catch(() => ({ result: { value: false } }));
  // A window whose size is computed (width={grid * 66}) asks for it at run time (Byond.winset): lay it out again at that size.
  // The window asks for its size at run time (Byond.winset): once from its <Window width height> or a computed size, then
  // again as auto-fit (layouts/fitWindow.ts) settles on its content. Follow each request until it stops changing.
  const askedNow = async (waitMs: number) =>
    (
      await send(
        'Runtime.evaluate',
        {
          expression: `new Promise(r => { const s = Date.now(); const t = () => (window.__previewSize || Date.now() - s > ${waitMs}) ? r(window.__previewSize ?? null) : setTimeout(t, 25); t(); })`,
          awaitPromise: true,
          returnByValue: true,
        },
        page.sessionId,
      )
    ).result.value;
  if (job.dock) await Bun.sleep(1200); // the docked interface loads on demand, then the column fits its entry
  for (let round = 0; round < (job.dock ? 0 : 6); round++) {
    const asked = await askedNow(round === 0 ? 1500 : 0);
    if (process.env.DQ_PREVIEW_DEBUG)
      console.log(job.tag, 'asked', JSON.stringify(asked));
    if (!(Array.isArray(asked) && asked[0] > 0 && asked[1] > 0)) break;
    const w = job.narrow ? Math.min(NARROW, asked[0]) : asked[0];
    if (w === job.width && asked[1] === job.height) {
      if (round > 0) break;
      await Bun.sleep(250); // the fit runs 60 ms after the content settles
      continue;
    }
    job.width = w;
    job.height = asked[1];
    await send(
      'Emulation.setDeviceMetricsOverride',
      {
        width: job.width,
        height: job.height,
        deviceScaleFactor: 1,
        mobile: false,
        screenWidth: 1920,
        screenHeight: 1080,
      },
      page.sessionId,
    );
    await Bun.sleep(250);
  }
  const probed = await send(
    'Runtime.evaluate',
    { expression: PROBE, returnByValue: true },
    page.sessionId,
  );
  // The checks themselves failing (a syntax error in PROBE) must not read as a clean window.
  if (probed.exceptionDetails)
    throw new Error(
      `the page checks failed: ${probed.exceptionDetails.exception?.description ?? probed.exceptionDetails.text}`,
    );
  const probe = probed.result.value ?? {};
  const shot = await send(
    'Page.captureScreenshot',
    { format: 'png' },
    page.sessionId,
  );
  const png = Buffer.from(shot.data, 'base64');
  // A second frame shows what animates (GIFs, clocks): regression mode ignores those pixels.
  const second = baselineDir
    ? await Bun.sleep(500).then(async () =>
        Buffer.from(
          (
            await send(
              'Page.captureScreenshot',
              { format: 'png' },
              page.sessionId,
            )
          ).data,
          'base64',
        ),
      )
    : undefined;
  writeFileSync(path.join(out, job.file), png);
  const problems: string[] = [];
  if (!settle.result.value) problems.push('never ready');
  if (probe.missing) problems.push('no export');
  if (errors.some((e) => e.startsWith('exception')))
    problems.push('js-exception');
  else if (errors.length) problems.push('console-error');
  const share = dominantShare(decodePng(png));
  if (
    !probe.missing &&
    !NO_UI.has(job.window) &&
    (share >= 0.99 || probe.text === 0)
  )
    problems.push('blank');
  if (probe.hOverflow) problems.push('h-overflow');
  if (probe.sideScroll) problems.push('h-scroll');
  if (process.env.DQ_PREVIEW_DEBUG) console.log(job.tag, JSON.stringify(probe));
  // Window fit (layouts/fitWindow.ts): space left under the content, or content cut off / scrolling at this size.
  if (job.dock && probe.fit && typeof probe.fit === 'object') {
    // Docked: the column entry against its content (Column.tsx fits it, the column caps it).
    // Docked bounds (tgui-panel/column/model.ts): at least DOCK_HEIGHT_MIN; it grows only into the room the filling entry
    // (the chat) has above its own minimum, so a long window that has taken all of that is capped, not overfull.
    const target = Math.max(80 - probe.fit.head, probe.fit.fit);
    const slack = probe.fit.docked - target;
    const room = probe.fit.fillRoom - DOCK_FILL_MIN;
    if (slack > FIT_SLACK) problems.push(`slack:${Math.round(slack)}px`);
    else if (slack < -FIT_SLACK && room > FIT_SLACK)
      problems.push(`overfull:${Math.round(-slack)}px`);
  } else if (
    !job.narrow &&
    typeof probe.fit === 'number' &&
    probe.autofit !== 'off'
  ) {
    // What auto-fit aims for (layouts/Window.tsx): the content height, at least FIT_MIN_HEIGHT, at most 90% of the screen.
    const target = Math.min(972, Math.max(120, probe.fit));
    const slack = probe.inner - target;
    if (slack > FIT_SLACK) problems.push(`slack:${slack}px`);
    else if (slack < -FIT_SLACK) problems.push(`overfull:${-slack}px`);
  }
  if (probe.emptySections?.length)
    problems.push(
      `empty-section:${probe.emptySections.length}(${probe.emptySections.filter(Boolean).join(',')})`,
    );
  if (probe.brokenImg) problems.push(`broken-img:${probe.brokenImg}`);
  if (probe.tiny)
    problems.push(`tiny-text:${probe.tiny}(${probe.tinyAt.join(',')})`);
  if (probe.offRight > 0)
    problems.push(`off-right:${probe.offRight}(${probe.offenders.join(',')})`);
  listeners.delete(page.sessionId);
  return {
    ...job,
    problems,
    errors: [...new Set(errors)].slice(0, 5),
    ms: Date.now() - t0,
    second,
  };
}

const pages = [
  first,
  ...(await Promise.all(
    Array.from({ length: Math.max(0, jobsN - 1) }, openPage),
  )),
];
const t0 = Date.now();
let cursor = 0;
await Promise.all(
  pages.map(async (page) => {
    while (cursor < jobs.length) {
      const job = jobs[cursor++];
      try {
        results.push(await runJob(page, job));
      } catch (e) {
        results.push({
          ...job,
          problems: ['render-failed'],
          errors: [String(e)],
          ms: 0,
        });
      }
    }
  }),
);
const elapsed = (Date.now() - t0) / 1000;
ws.close();
browser.kill();
server.stop(true);

// ---- regression --------------------------------------------------------------------------------------------------------------
if (baselineDir) {
  for (const r of results) {
    const b = path.join(baselineDir, r.file);
    if (!existsSync(b)) continue;
    r.diff = diffRatio(
      decodePng(readFileSync(b)),
      decodePng(readFileSync(path.join(out, r.file))),
      16,
      r.second ? decodePng(r.second) : undefined,
    );
    delete r.second;
    if (r.diff > threshold)
      r.problems.push(`REGRESSED:${(r.diff * 100).toFixed(2)}%`);
  }
}
const save = opt('--save-baseline');
if (save) {
  mkdirSync(path.resolve(save), { recursive: true });
  for (const r of results)
    cpSync(path.join(out, r.file), path.join(path.resolve(save), r.file));
}

// ---- report ------------------------------------------------------------------------------------------------------------------
for (const r of results) delete r.second;
results.sort((a, b) => a.tag.localeCompare(b.tag));
writeFileSync(
  path.join(out, 'report.json'),
  JSON.stringify(
    {
      when: new Date().toISOString(),
      theme: theme ?? null,
      threshold,
      results,
      missingSprites: [...missingSprites].sort(),
    },
    null,
    1,
  ),
);
const esc = (s: string) => s.replace(/[&<>"]/g, (c) => `&#${c.charCodeAt(0)};`);
const bad = results.filter((r) => r.problems.length);
const card = (r: Result) =>
  `<figure class="${r.problems.length ? 'bad' : ''}" data-tag="${esc(r.tag.toLowerCase())}"><figcaption><b>${esc(r.tag)}</b> ${r.width}x${r.height}${r.problems.map((p) => ` <span class="chip">${esc(p)}</span>`).join('')}${r.errors.length ? `<details><summary>errors</summary><pre>${esc(r.errors.join('\n'))}</pre></details>` : ''}</figcaption><a href="${encodeURI(r.file)}"><img loading="lazy" src="${encodeURI(r.file)}" style="max-width:${Math.min(r.width, 480)}px"></a></figure>`;
writeFileSync(
  path.join(out, 'index.html'),
  `<!doctype html><html><head><meta charset="utf-8"><title>tgui renders</title>
<style>body{background:#0d1117;color:#c9d1d9;font:13px system-ui,sans-serif;margin:16px}h1{font-size:18px}figure{display:inline-block;vertical-align:top;margin:0 12px 16px 0;max-width:480px}
figcaption{margin:4px 0;word-break:break-all}img{display:block;max-width:100%;border:1px solid #30363d}.bad img{border-color:#f85149}.chip{background:#3d1d20;color:#ffa198;border-radius:8px;padding:0 6px;font-size:11px}
pre{white-space:pre-wrap;font-size:11px;color:#ffa198}input{background:#161b22;color:#c9d1d9;border:1px solid #30363d;padding:4px 8px;width:260px}</style></head><body>
<h1>tgui renders: ${results.length} shots, ${bad.length} with problems (${elapsed.toFixed(1)} s${theme ? `, theme ${esc(theme)}` : ''})</h1>
<p><input id="f" placeholder="filter by window" oninput="for(const f of document.querySelectorAll('figure'))f.style.display=f.dataset.tag.includes(this.value.toLowerCase())?'':'none'"> <label><input type="checkbox" style="width:auto" onchange="document.body.classList.toggle('only',this.checked)"> problems only</label></p>
<style>.only figure:not(.bad){display:none}</style>
${bad.map(card).join('\n')}
${results
  .filter((r) => !r.problems.length)
  .map(card)
  .join('\n')}
</body></html>`,
);
for (const r of bad)
  console.log(
    `${r.tag}: ${r.problems.join(' ')}${r.errors[0] ? ` | ${r.errors[0]}` : ''}`,
  );
console.log(
  `${results.length} shots in ${elapsed.toFixed(1)} s, ${bad.length} with problems; ${missingSprites.size} sprite states missing. ${path.join(out, 'index.html')}`,
);
process.exit(
  bad.some((r) =>
    r.problems.some(
      (p) =>
        p !== 'console-error' &&
        p !== 'h-scroll' &&
        !p.startsWith('off-right') &&
        !p.startsWith('empty-section') &&
        !p.startsWith('slack') &&
        !p.startsWith('overfull'),
    ),
  )
    ? 1
    : 0,
);
