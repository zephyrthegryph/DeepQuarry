/**
 * The stat panel page. Loaded by /client/New through tgui_window; the page's
 * inline fallback (see client procs.dm) shows unless this marks itself mounted.
 */
import './statpanel.scss';

import { createRoot } from 'react-dom/client';
import { App, PanelBoundary } from './App';
import { dockHost } from './dockHost';
import { applyDockPreview } from './dockPreview';
import { StatStore } from './store';

const win = window as any;

const store = new StatStore({
  sendMessage: (type, payload) => Byond.sendMessage(type, payload),
});

let tabsStyle = 'default';
const displayListeners = new Set<() => void>();
const displayStore = {
  subscribe(listener: () => void) {
    displayListeners.add(listener);
    return () => {
      displayListeners.delete(listener);
    };
  },
  get: () => tabsStyle,
};

// tgui-panel drives these with `.output statbrowser:<name>`.
win.set_theme = (name: string) => {
  const light = name === 'light' || name === 'vchatlight';
  document.documentElement.className = light ? 'light' : 'dark';
};
win.set_font_size = (size: string) => {
  document.body.style.setProperty('font-size', size);
};
win.set_tabs_style = (style: string) => {
  tabsStyle = style;
  for (const listener of displayListeners) listener();
};
win.set_theme('dark');

// Image assets can arrive after the markup: retry. Error events do not bubble,
// so this listens in the capture phase.
document.addEventListener(
  'error',
  (event) => {
    const node = event.target as HTMLImageElement;
    if (node?.tagName !== 'IMG') return;
    const attempts = Number(node.dataset.attempts) || 0;
    if (attempts > 50) return;
    node.dataset.attempts = `${attempts + 1}`;
    const src = node.src.split('#')[0];
    setTimeout(() => {
      node.src = `${src}#${attempts}`;
    }, 500);
  },
  true,
);

// Clicks and keys return focus to the map, except while typing in the search.
function restoreFocus(event: Event) {
  const target = event.target as HTMLElement;
  if (target?.tagName === 'INPUT') {
    if ((event as KeyboardEvent).key !== 'Escape') return;
    target.blur();
  }
  setTimeout(() => Byond.winset('map', { focus: true }), 0);
}
document.addEventListener('mouseup', restoreFocus);
document.addEventListener('keyup', restoreFocus);

Byond.subscribe((type: string, payload: any) => {
  if (type === 'dock/preview') {
    applyDockPreview(payload);
    return;
  }
  if (dockHost.receive(type, payload)) {
    return;
  }
  store.receive(type, payload);
});

function showFallback() {
  const fallback = document.getElementById('statpanel-fallback');
  if (fallback) fallback.style.display = 'block';
}

function mount() {
  createRoot(document.getElementById('react-root')!).render(
    <PanelBoundary onError={showFallback}>
      <App store={store} displayStore={displayStore} />
    </PanelBoundary>,
  );
  win.__statpanelMounted = true;
  Byond.winset(Byond.windowId, { 'is-visible': true });
  Byond.sendMessage('Set-Tab', { tab: 'Status' });
  Byond.sendMessage('Update-Verbs');
  dockHost.ready();
  // The server can miss the first request while the client is still logging in.
  setTimeout(() => {
    if (!store.state.verbs.length) Byond.sendMessage('Update-Verbs');
  }, 5000);
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', mount);
} else {
  mount();
}
