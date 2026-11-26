/**
 * The stat panel's store and its message handling, as the StatPanel tgui
 * window hosts them (tgui/interfaces/StatPanel.tsx, docked in the right-hand
 * column or floating): what the server sends the window arrives in
 * `receive`, and what the panel sends goes out through `send`.
 */
import { loadMappings, loadStyleSheet } from 'common/assets';
import { StatStore } from './store';

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
      store.receive(type, payload);
    },
    ready() {
      send('Set-Tab', { tab: 'Status' });
      send('Update-Verbs');
      // The server can miss the first request while the client is still logging in.
      setTimeout(() => {
        if (!store.state.verbs.length) send('Update-Verbs');
      }, 5000);
    },
  };
}
