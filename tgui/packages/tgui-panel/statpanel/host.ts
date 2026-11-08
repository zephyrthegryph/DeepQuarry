/**
 * The stat panel inside the right-hand column's page (doc/rewrite/proposals/
 * window_system.md section 12). The server's stat panel is a column window
 * with the id `statbrowser`: what it sends arrives here unwrapped, and what
 * the panel sends goes out through `send`, wrapped for that id.
 */
import { loadMappings, loadStyleSheet } from 'common/assets';
import { StatStore } from './store';

/** The stat panel's window id, as the server knows it (SKIN_STAT_BROWSER). */
export const STAT_WINDOW_ID = 'statbrowser';

export type StatHost = {
  store: StatStore;
  /** A message the server sent the stat panel's window. */
  receive: (type: string, payload: any) => void;
  /** The panel is mounted: the server marks it ready and sends its data. */
  ready: () => void;
};

export function createStatHost(
  send: (type: string, payload?: Record<string, unknown>) => void,
): StatHost {
  const store = new StatStore({
    sendMessage: (type, payload) =>
      send(type, payload as Record<string, unknown> | undefined),
  });
  // Sprite sheets the server sends the panel (the abilities sheet: code/content/abilities/ability_icons.dm).
  const assetMap: Record<string, string> = {};
  return {
    store,
    receive(type, payload) {
      if (type === 'asset/stylesheet') {
        loadStyleSheet(payload);
        return;
      }
      if (type === 'asset/mappings') {
        loadMappings(payload, assetMap);
        return;
      }
      if (type === 'ping') {
        send('ping/reply', payload);
        return;
      }
      store.receive(type, payload);
    },
    ready() {
      send('ready');
      send('Set-Tab', { tab: 'Status' });
      send('Update-Verbs');
      // The server can miss the first request while the client is still logging in.
      setTimeout(() => {
        if (!store.state.verbs.length) send('Update-Verbs');
      }, 5000);
    },
  };
}
