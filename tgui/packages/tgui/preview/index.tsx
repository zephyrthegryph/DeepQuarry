/**
 * Renders one tgui window from the renderAll fixtures in an ordinary browser, for screenshots
 * (tools/tgui_preview/shoot.ts builds this bundle and drives it). `index.html?w=<Window>` shows
 * that window with its hand-written fixture, else the captured ui_data, else empty data.
 */
import './byond';
import '../styles/main.scss';
import '../embeddedStyles';

import { Provider } from 'jotai';
import { type ComponentType, StrictMode, Suspense } from 'react';
import { createRoot } from 'react-dom/client';
import {
  configAtom,
  gameDataAtom,
  gameStaticDataAtom,
  store,
  suspendedAtom,
} from '../events/store';
import captured from '../interfaces/__fixtures__/ui_data.json';

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

function dataFor(name: string): Record<string, unknown> {
  const key = `./${name}.json`;
  if (requireWritten.keys().includes(key)) {
    return requireWritten(key);
  }
  return (captured as unknown as Record<string, Record<string, unknown>>)[name] ?? {};
}

/** Names of every window this bundle can show, for the driver. */
(window as any).previewWindows = () =>
  requireInterface
    .keys()
    .map((k: string) => k.replace(/^\.\/(chompstation\/)?/, '').replace(/(\/index)?\.[tj]sx$/, ''));

const name = new URLSearchParams(location.search).get('w') ?? '';
const Routed = findInterface(name);

store.set(suspendedAtom, false);
store.set(configAtom, {
  title: name,
  status: 2,
  interface: { name, layout: 'default' },
  window: { key: 'preview', size: [560, 640], fancy: false, locked: false, native_shell: true },
  user: { name: 'tester', observer: 0 },
} as any);
store.set(gameStaticDataAtom, {});
store.set(gameDataAtom, dataFor(name));

createRoot(document.getElementById('app')!).render(
  <StrictMode>
    <Provider store={store}>
      <Suspense fallback={null}>
        {Routed ? <Routed /> : <div id="preview-missing">missing {name}</div>}
      </Suspense>
    </Provider>
  </StrictMode>,
);
(window as any).previewReady = true;
