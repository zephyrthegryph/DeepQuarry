/**
 * Renders one tgui window from fixtures in an ordinary browser, for screenshots (tools/tgui_preview/render.ts builds this
 * bundle and drives it; doc/tgui_preview.md). `index.html?w=<Window>` shows that window with, first found: its hand-written
 * fixture (`__fixtures__/windows/<Window>.json`), the census capture (`__fixtures__/captured/<Window>.json`, written by
 * tools/tgui_preview/capture.ts), the unit-test capture (`__fixtures__/ui_data.json`), else {}.
 * `&v=<variant>` picks a preset (`__fixtures__/windows/<Window>.<variant>.json`, e.g. empty/full/error states) laid over the
 * base data, so a preset only names the keys it changes; `&v=captured` forces the census capture. A preset's `__shared` object presets useSharedState values (an intro already played). `&data=<url>` loads the
 * data from that JSON file instead. `&theme=<name>` draws the window in that theme. When the server has the sprite cache
 * (`sprites/index.json`), spritesheet classes, resolveAsset() names and DmIcon show real game sprites.
 */
import './byond';
import '../styles/main.scss';
import '../embeddedStyles';

import { Provider } from 'jotai';
import { type ComponentType, StrictMode, Suspense } from 'react';
import { createRoot } from 'react-dom/client';
import { loadedMappings } from '../assets';
import {
  configAtom,
  gameDataAtom,
  gameStaticDataAtom,
  sharedAtom,
  store,
  suspendedAtom,
} from '../events/store';
import captured from '../interfaces/__fixtures__/ui_data.json';
import { measureFitHeight } from '../layouts/fitWindow';
import { alignmentFindings, markFindings } from './alignment';

const requireInterface = require.context(
  '../interfaces',
  true,
  /^\.\/(?!.*\.test\.)(?!__)(chompstation\/)?[^/]+(\/index)?\.(tsx|jsx)$/,
  'sync',
);
const requireWritten = require.context(
  '../interfaces/__fixtures__/windows',
  false,
  /\.json$/,
  'sync',
);
const requireCaptured = require.context(
  '../interfaces/__fixtures__/captured',
  false,
  /\.json$/,
  'sync',
);

type Data = Record<string, unknown>;

function findInterface(name: string): ComponentType | undefined {
  for (const key of [
    `./chompstation/${name}.tsx`,
    `./chompstation/${name}/index.tsx`,
    `./${name}.tsx`,
    `./${name}/index.tsx`,
    `./${name}.jsx`,
  ]) {
    if (requireInterface.keys().includes(key)) {
      return requireInterface(key)[name];
    }
  }
  return undefined;
}

function load(ctx: any, key: string): Data | undefined {
  return ctx.keys().includes(key) ? ctx(key) : undefined;
}

function baseDataFor(name: string): Data {
  return (
    load(requireWritten, `./${name}.json`) ??
    load(requireCaptured, `./${name}.json`) ??
    (captured as unknown as Record<string, Data>)[name] ??
    {}
  );
}

/**
 * A hand-written fixture names a game sprite as `"dmi:<icon path>:<state>[:<dir>]"` where the window expects an image (a base64
 * icon, an <img> src): the render server crops that frame out of the .dmi, so presets show real sprites without a capture.
 */
function withSprites(v: unknown): any {
  if (typeof v === 'string') {
    // Optionally quoted, for the windows that strip the quotes BYOND's photo refs carry.
    const m = v.match(/^('?)dmi:([^:]+\.dmi):([^:']*)(?::(\d+))?'?$/);
    return m
      ? `${m[1]}dmi/${m[2]}?state=${encodeURIComponent(m[3])}&dir=${m[4] ?? 2}${m[1]}`
      : v;
  }
  if (Array.isArray(v)) return v.map(withSprites);
  if (v && typeof v === 'object') {
    return Object.fromEntries(
      Object.entries(v).map(([k, x]) => [k, withSprites(x)]),
    );
  }
  return v;
}

function dataFor(name: string, variant: string | null): Data {
  return withSprites(rawDataFor(name, variant));
}

function rawDataFor(name: string, variant: string | null): Data {
  if (variant === 'captured') {
    return load(requireCaptured, `./${name}.json`) ?? {};
  }
  if (variant) {
    return {
      ...baseDataFor(name),
      ...(load(requireWritten, `./${name}.${variant}.json`) ?? {}),
    };
  }
  return baseDataFor(name);
}

/** Names of every window this bundle can show, for the driver. */
(window as any).previewWindows = () =>
  requireInterface
    .keys()
    .map((k: string) =>
      k
        .replace(/^\.\/(chompstation\/)?/, '')
        .replace(/(\/index)?\.[tj]sx$/, ''),
    );

/** Every render target, [window, variant | null], one per fixture this bundle holds, for the driver. */
(window as any).previewFixtures = () => {
  const out: Array<[string, string | null]> = [];
  const seen = new Set<string>();
  const add = (w: string, v: string | null) => {
    if (!seen.has(`${w}.${v}`)) {
      seen.add(`${w}.${v}`);
      out.push([w, v]);
    }
  };
  for (const k of requireWritten.keys()) {
    const m = k.match(/^\.\/([^.]+)(?:\.([^.]+))?\.json$/);
    if (m) add(m[1], m[2] ?? null);
  }
  for (const k of requireCaptured.keys()) {
    const m = k.match(/^\.\/([^.]+)\.json$/);
    if (m) add(m[1], null);
  }
  for (const w of Object.keys(captured)) add(w, null);
  return out.filter(([w]) => findInterface(w));
};

const params = new URLSearchParams(location.search);
const name = params.get('w') ?? '';
const variant = params.get('v');
const Routed = findInterface(name);
const themeOverride = params.get('theme');
if (themeOverride) (globalThis as any).__TGUI_PREVIEW_THEME__ = themeOverride;

store.set(suspendedAtom, false);
store.set(configAtom, {
  title: name,
  status: 2,
  interface: { name, layout: 'default' },
  window: {
    key: `preview-${name}`,
    size: [560, 640],
    fancy: false,
    locked: false,
    native_shell: true,
  },
  user: { name: 'tester', observer: 0 },
} as any);
store.set(gameStaticDataAtom, {});
// A preset's `__shared` key presets the window's useSharedState values (an intro already seen, a tab already open).
const { __shared, ...windowData } = dataFor(name, variant) as Data & {
  __shared?: Record<string, unknown>;
};
store.set(sharedAtom, __shared ?? {});
store.set(gameDataAtom, windowData);
// useBackend reads the store without subscribing, so the data is in place before the first render.
/**
 * ?dock=1: the window docked in the right-hand column (tgui-panel's real Column and its host), under a stat-panel-sized
 * entry and above nothing: the column fits the entry to the window's content (Column.tsx), as a docked window in the game.
 */
async function renderDocked() {
  // The column page's own layout styles (only what the column draws; the windows keep the tgui bundle's).
  await import('../../tgui-panel/styles/components/Column.scss');
  const [{ Column }, { columnHost }] = await Promise.all([
    import('../../tgui-panel/column/Column'),
    import('../../tgui-panel/column/host'),
  ]);
  const { store: panelStore } = await import('../../tgui-panel/events/store');
  columnHost.receive('col/open', { wid: 'col-preview', kind: 'tgui' });
  columnHost.receive('col/msg', {
    wid: 'col-preview',
    type: 'update',
    payload: {
      config: {
        interface: { name, layout: 'default' },
        title: name,
        status: 2,
        user: { name: 'tester', observer: 0 },
      },
      data: windowData,
      shared: __shared ?? {},
    },
  });
  // A second entry below stands in for the chat: the last entry fills the column, so the window is a sized entry above it.
  columnHost.receive('col/open', { wid: 'col-filler', kind: 'tgui' });
  columnHost.receive('col/msg', {
    wid: 'col-filler',
    type: 'update',
    payload: {
      config: {
        interface: { name: 'StatPanel', layout: 'default' },
        title: 'Chat (stand-in)',
        status: 2,
        user: { name: 'tester', observer: 0 },
      },
      data: {},
    },
  });
  createRoot(document.getElementById('app')!).render(
    <Provider store={panelStore}>
      <Column />
    </Provider>,
  );
}

function renderWindow() {
  if (params.get('dock')) {
    renderDocked();
    return;
  }
  createRoot(document.getElementById('app')!).render(
    <StrictMode>
      <Provider store={store}>
        <Suspense fallback={null}>
          {Routed ? <Routed /> : <div id="preview-missing">missing {name}</div>}
        </Suspense>
      </Provider>
    </StrictMode>,
  );
}

/** The sprite cache, when the server has one (tools/tgui_preview/capture.ts): asset names -> URLs, and every spritesheet's CSS. */
async function loadSprites() {
  try {
    const r = await fetch('sprites/index.json');
    if (!r.ok) return;
    const index = await r.json();
    // Names only: loadMappings() would also inject every .css/.js asset the game ships (old panel styles); the sheets are linked below.
    Object.assign(loadedMappings, index.mappings ?? {});
    await Promise.all(
      (index.css ?? []).map(
        (href: string) =>
          new Promise<void>((done) => {
            const link = document.createElement('link');
            link.rel = 'stylesheet';
            link.href = href;
            link.onload = () => done();
            link.onerror = () => done();
            document.head.appendChild(link);
          }),
      ),
    );
  } catch {
    // No cache: sprites stay blank.
  }
}

// A window that wraps its base64 icon in a data: URL wraps a `dmi:` sprite too: unwrap it to the server's frame URL.
const unwrapSprite = (img: HTMLImageElement) => {
  const m = img.getAttribute('src')?.match(/^data:[^,]*,(dmi\/.+)$/);
  if (m) img.setAttribute('src', m[1]);
};
new MutationObserver((records) => {
  for (const r of records) {
    if (r.type === 'attributes' && r.target instanceof HTMLImageElement) {
      unwrapSprite(r.target);
    }
    for (const n of r.addedNodes) {
      if (n instanceof HTMLElement) {
        if (n instanceof HTMLImageElement) unwrapSprite(n);
        n.querySelectorAll('img').forEach(unwrapSprite);
      }
    }
  }
}).observe(document.documentElement, {
  subtree: true,
  childList: true,
  attributes: true,
  attributeFilter: ['src'],
});

// ?data=<url>: the window's data from a JSON file served beside the bundle (more than one sample per window, e.g. one per article).
const dataUrl = params.get('data');
(async () => {
  await loadSprites();
  if (dataUrl) {
    try {
      store.set(gameDataAtom, await (await fetch(dataUrl)).json());
    } catch {
      // keep the fixture
    }
  }
  renderWindow();
  (window as any).previewReady = true;
})();

/** The window's fitted inner height (layouts/fitWindow.ts), for the render checks. */
(window as any).__tguiFit = () => {
  // Docked (?dock=1): the entry's body against what its window's content wants.
  const body = document.querySelector<HTMLElement>(
    '[data-column-group] .column-body',
  );
  if (body) {
    const fit = measureFitHeight(body, body.getBoundingClientRect().top);
    // The room the filling entry (the chat stand-in) still has: a window can only grow into that.
    const bodies = document.querySelectorAll<HTMLElement>('.column-body');
    const filler = bodies[bodies.length - 1];
    const fillRoom =
      filler && filler !== body ? filler.getBoundingClientRect().height : 0;
    return fit === null
      ? null
      : {
          docked: body.getBoundingClientRect().height,
          fit,
          fillRoom,
          // The entry's own frame (its head): the column's minimum height counts it.
          head:
            (body
              .closest<HTMLElement>('[data-column-group]')
              ?.getBoundingClientRect().height ?? 0) -
            body.getBoundingClientRect().height,
        };
  }
  return measureFitHeight(document);
};

// ?css=<rules> injects a stylesheet: the checker's self-test breaks the layout on purpose to prove each rule fires.
const injected = params.get('css');
if (injected) {
  const style = document.createElement('style');
  style.textContent = injected;
  document.head.appendChild(style);
}
// ?check=1: once the window has settled, run the alignment checks and hand the findings to the parent frame;
// ?mark=1 outlines them (for the per-issue screenshot).
if (params.get('check') || params.get('mark')) {
  setTimeout(async () => {
    await document.fonts?.ready;
    const findings = alignmentFindings();
    if (params.get('mark')) markFindings(findings);
    parent.postMessage(
      { name, findings, theme: document.documentElement.className },
      '*',
    );
  }, 800);
}
