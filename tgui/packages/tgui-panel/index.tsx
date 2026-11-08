/**
 * @file
 * @copyright 2020 Aleksej Komarov
 * @license MIT
 */

import './styles/main.scss';

import { createRoot } from 'react-dom/client';
import { setupGlobalEvents } from 'tgui-core/events';
import { captureExternalLinks } from 'tgui-core/links';
import { setupHotReloading } from 'tgui-dev-server/link/client';
import { App } from './app';
import { bus } from './events/listeners';
import { store } from './events/store';
import { fitChatBrowser } from './layout/geometry';
import { setupPanelFocusHacks } from './panelFocus';

const root = createRoot(document.getElementById('react-root')!);

function render(component: React.ReactElement) {
  root.render(component);
}

function setupApp() {
  // Delay setup
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', setupApp);
    return;
  }

  // Force speechSynthesis to check the server for voices as soon as the chat loads, so it's ready for us
  window.speechSynthesis.getVoices();

  setupGlobalEvents({
    ignoreWindowFocus: true,
  });

  setupPanelFocusHacks();
  captureExternalLinks();

  render(<App />);

  // Dispatch incoming messages as store actions
  Byond.subscribe((type, payload) => bus.dispatch({ type, payload }));

  // Unhide the panel
  Byond.winset('outputwindow.legacy_output_selector', {
    left: 'output_browser',
  });

  // Fill our own pane. Not the legacy `output` control: its pane is hidden,
  // so its size is stale. Sized to what the host really has (fitChatBrowser),
  // again after a second while the pane lays out; the server's chat/layout
  // message fits it again whenever the pane moves. Once the browser matches
  // the pane, its 0,0-100,100 anchors track every later resize.
  const fill = (reason: string) => fitChatBrowser(reason);
  fill('start');
  setTimeout(() => fill('start-settled'), 1000);

  // Enable hot module reloading
  if (import.meta.webpackHot) {
    setupHotReloading();

    import.meta.webpackHot.accept(['./app'], () => {
      render(<App />);
    });
  }
}

setupApp();
