/**
 * The stat panel as a tgui window (code/content/client/stat_panel_window.dm,
 * doc/rewrite/proposals/window_system.md section 12): docked in the
 * right-hand column by default, floating like any other window. Its server
 * code keeps its own protocol (update_verbs, update_stat, Set-Tab, ...):
 * the messages come and go through this window's channel, native or
 * embedded alike, into the stat panel's store and views (tgui-panel/statpanel).
 */
import 'tgui-panel/statpanel/statpanel.scss';

import { useEffect, useMemo, useSyncExternalStore } from 'react';
import { useWindowMessages, useWindowSend } from 'tgui/backend';
import { Tabs } from 'tgui/dq';
import { Window } from 'tgui/layouts';
import { StatWindow } from 'tgui-panel/statpanel/App';
import { createStatHost } from 'tgui-panel/statpanel/host';
import type { PanelView } from 'tgui-panel/statpanel/layout';
import { type StatStore, viewsOf } from 'tgui-panel/statpanel/store';

export function StatPanel() {
  const send = useWindowSend();
  // One store per window: a docked or floated panel is a fresh window, and the server re-sends its data when it asks.
  const host = useMemo(() => createStatHost(send), []);
  useWindowMessages((type, payload) => host.receive(type, payload));
  useEffect(() => host.ready(), [host]);
  return (
    <Window title="Status" width={440} height={640}>
      <Window.Content fitted>
        <StatPanelBody store={host.store} />
      </Window.Content>
    </Window>
  );
}

function StatPanelBody(props: { store: StatStore }) {
  const { store } = props;
  useSyncExternalStore(store.subscribe, store.getVersion);
  const { state } = store;
  const views = useMemo(
    () => viewsOf(state),
    [state.verbs, state.permanentTabs],
  );
  return (
    <div className="stat-root stat-root--window">
      <Tabs
        className="stat-views"
        tabs={views.map((view) => ({
          id: view,
          label:
            view === 'Staff' && state.tickets.length ? (
              <>
                Staff <span className="stat-badge">{state.tickets.length}</span>
              </>
            ) : (
              view
            ),
          selected: view === state.view,
        }))}
        onSelect={(view) => store.setView(view as PanelView)}
      />
      <StatWindow store={store} view={state.view} />
    </div>
  );
}
