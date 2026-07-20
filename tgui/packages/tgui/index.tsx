/**
 * @file
 * @copyright 2020 Aleksej Komarov
 * @license MIT
 */

// Themes
import './styles/main.scss';
import './styles/themes/abductor.scss';
import './styles/themes/cardtable.scss';
import './styles/themes/spookyconsole.scss';
import './styles/themes/nuclear.scss';
import './styles/themes/hackerman.scss';
import './styles/themes/crtsoul.scss';
import './styles/themes/malfunction.scss';
import './styles/themes/neutral.scss';
import './styles/themes/ntos.scss';
import './styles/themes/ntos_cat.scss';
import './styles/themes/ntos_darkmode.scss';
import './styles/themes/ntos_lightmode.scss';
import './styles/themes/ntOS95.scss';
import './styles/themes/ntos_synth.scss';
import './styles/themes/ntos_terminal.scss';
import './styles/themes/ntos_spooky.scss';
import './styles/themes/paper.scss';
import './styles/themes/pda-retro.scss';
import './styles/themes/retro.scss';
import './styles/themes/syndicate.scss';
import './styles/themes/wizard.scss';
import './styles/themes/admin.scss';
import './styles/themes/abstract.scss';
import './styles/themes/bingle.scss';
import './styles/themes/algae.scss';

import { setupGlobalEvents } from 'tgui-core/events';
import { captureExternalLinks } from 'tgui-core/links';
import { setupHotReloading } from 'tgui-dev-server/link/client';

import { App } from './App';
import { setDebugHotKeys } from './debug/use-debug';
import { bus } from './events/listeners';
import { setupHotKeys } from './hotkeys';
import { profileStartup } from './profiling/hooks';
import { render } from './renderer';
import { createStackAugmentor } from './stack';

function setupApp() {
  // Delay setup
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', setupApp);
    return;
  }

  window.__augmentStack__ = createStackAugmentor();
  profileStartup('document_ready');

  setupGlobalEvents();
  setupHotKeys({
    keyUpVerb: 'KeyUp',
    keyDownVerb: 'KeyDown',
    // In the future you could send a winget here to get mousepos/size from the map here if it's necessary
    verbParamsFn: (verb, key) => `${verb} "${key}" 0 0 0 0`,
  });
  captureExternalLinks();

  Byond.subscribe((type, payload) => bus.dispatch({ type, payload }));

  // Dispatch incoming messages as store actions. The profiler is dynamically
  // imported only by development builds, so its observers and overlay are absent
  // from production bundles and cannot affect player-facing performance.
  if (process.env.NODE_ENV === 'development') {
    // Render the application before requesting the optional profiler chunk. BYOND
    // cache reloads are not atomic, so a temporarily missing development-only chunk
    // must never leave every TGUI as a blank window.
    render(<App />);
    profileStartup('initial_render');
    profileStartup('profiler_requested');
    import('./profiling/DevelopmentProfiler')
      .then(({ DevelopmentProfiler }) => {
        profileStartup('profiler_loaded');
        render(
          <DevelopmentProfiler>
            <App />
          </DevelopmentProfiler>,
        );
      })
      .catch((error) => {
        console.error('Development profiler failed to load:', error);
      });
  } else {
    render(<App />);
  }

  // Enable hot module reloading
  if (import.meta.webpackHot) {
    setDebugHotKeys();
    setupHotReloading();
    import.meta.webpackHot.accept(['./layouts', './routes', './App'], () =>
      render(<App />),
    );
  }
}

setupApp();
