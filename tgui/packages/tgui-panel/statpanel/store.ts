/**
 * The stat panel's state and its side of the server protocol: the messages
 * code/content/client/statpanel_service.dm sends, as data, with the tab bar
 * derived from them instead of kept in the DOM.
 */

import { type AbilitiesData, hasAbilities } from './abilities';
import type { InspectData } from './inspect';
import {
  ADMIN_VIEWS,
  dataTabOf,
  groupRank,
  type PanelView,
  PLAYER_VIEWS,
  placeOf,
  type ServerPage,
} from './layout';
import type { McHealthData } from './mcHealthData';

export type Host = {
  sendMessage: (type: string, payload?: object) => void;
};

/** [category, name, description] */
export type Verb = [string, string, string?];

export type State = {
  version: number;
  currentTab: string;
  statusParts: string[];
  /** Where the admin's eye is, for the MC Health panel's Advanced section. */
  mcLocation: string;
  mcMetrics: McHealthData | null;
  hrefToken: string | null;
  verbs: Verb[];
  spells: string[][];
  examine: string[];
  inspect: InspectData | null;
  abilities: AbilitiesData | null;
  /** Date.now() when the abilities arrived: the cooldowns count down from it. */
  abilitiesAt: number;
  tickets: string[][];
  misc: Record<string, any[][]>;
  sdql2: string[][];
  permanentTabs: string[];
  turfName: string;
  turfContents: string[][];
  splitAdminTabs: boolean;
  /** Which of the five views is shown (layout.ts); currentTab is the server tab whose data it needs, or a card over it. */
  view: PanelView;
  serverPage: ServerPage;
};

export function initialState(): State {
  return {
    version: 0,
    currentTab: 'Status',
    statusParts: ['Loading...'],
    mcLocation: '',
    mcMetrics: null,
    hrefToken: null,
    verbs: [],
    spells: [],
    examine: [],
    inspect: null,
    abilities: null,
    abilitiesAt: 0,
    tickets: [],
    misc: {},
    sdql2: [],
    permanentTabs: ['Status'],
    turfName: '',
    turfContents: [],
    splitAdminTabs: false,
    view: 'Status',
    serverPage: 'Health',
  };
}

/** The tab a verb category shows under: "Admin.Game" is in "Admin". */
export function tabOfCategory(category: string, split: boolean): string {
  if (!category.includes('.')) return category;
  const [head, tail] = category.split('.');
  return split && head === 'Admin' ? tail : head;
}

const PINNED = ['Status', 'Abilities', 'MC', 'Tickets'];

function pinOrder(tab: string): number {
  const index = PINNED.indexOf(tab);
  return index === -1 ? PINNED.length : index;
}

export function visibleTabs(state: State): string[] {
  const tabs = new Set(state.permanentTabs);
  for (const verb of state.verbs) {
    const tab = tabOfCategory(verb[0], state.splitAdminTabs);
    if (tab.trim()) tabs.add(tab);
  }
  for (const spell of state.spells) {
    if (spell[0]) tabs.add(spell[0]);
  }
  return [...tabs].sort(
    (a, b) => pinOrder(a) - pinOrder(b) || a.localeCompare(b),
  );
}

/** The views this client gets: admins (a Staff or Server verb, or the MC or Tickets tab) get all five. */
export function viewsOf(state: State): PanelView[] {
  const admin =
    state.permanentTabs.includes('MC') ||
    state.permanentTabs.includes('Tickets') ||
    state.verbs.some((verb) => {
      const view = placeOf(verb[0]).view;
      return view === 'Staff' || view === 'Server';
    });
  return admin ? ADMIN_VIEWS : PLAYER_VIEWS;
}

/** The verbs a view shows, grouped (layout.ts places each category), groups in layout order, verbs by name. */
export function verbGroupsOf(
  state: State,
  view: PanelView,
): { group: string; verbs: Verb[] }[] {
  const groups = new Map<string, Verb[]>();
  for (const verb of state.verbs) {
    const place = placeOf(verb[0]);
    if (place.view !== view) continue;
    if (!groups.has(place.group)) groups.set(place.group, []);
    groups.get(place.group)!.push(verb);
  }
  const byName = (a: Verb, b: Verb) => a[1].localeCompare(b[1]);
  return [...groups]
    .sort(([a], [b]) => groupRank(a) - groupRank(b) || a.localeCompare(b))
    .map(([group, verbs]) => ({ group, verbs: verbs.sort(byName) }));
}

/** A search result: what to show, where it lives, the command it runs. */
export type Found = { label: string; path: string; command: string };

/** Menu page sections searched with the verbs (menu.ts). */
export type MenuSection = {
  name: string;
  items: { label: string; command: string }[];
};

/**
 * One search over everything the panel offers: the verbs of every view this client has (with the view and group they
 * sit in) and the Menu page's items. Names that start with the query come first, then the rest by name.
 */
export function searchAll(
  state: State,
  query: string,
  menu: MenuSection[],
): Found[] {
  const needle = query.trim().toLowerCase();
  if (!needle) return [];
  const views = viewsOf(state);
  const found: Found[] = [];
  for (const verb of state.verbs) {
    if (!verb[1].toLowerCase().includes(needle)) continue;
    const place = placeOf(verb[0]);
    if (!views.includes(place.view)) continue;
    found.push({
      label: verb[1],
      path: `${place.view} › ${place.group}`,
      command: verbCommand(verb[1]),
    });
  }
  for (const section of menu) {
    for (const item of section.items) {
      if (!item.label.toLowerCase().includes(needle)) continue;
      found.push({
        label: item.label,
        path: `Game › ${section.name}`,
        command: item.command,
      });
    }
  }
  const starts = (f: Found) =>
    f.label.toLowerCase().startsWith(needle) ? 0 : 1;
  return found.sort(
    (a, b) => starts(a) - starts(b) || a.label.localeCompare(b.label),
  );
}

export function searchVerbs(state: State, query: string): Verb[] {
  const needle = query.trim().toLowerCase();
  if (!needle) return [];
  return state.verbs
    .filter((verb) => verb[1].toLowerCase().includes(needle))
    .sort((a, b) => a[1].localeCompare(b[1]));
}

/** The command a verb click runs. */
export function verbCommand(name: string): string {
  return name.replace(/\s/g, '-');
}

/** Two lists of status lines are the same lines in the same order. */
export function sameLines(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

export class StatStore {
  state = initialState();
  private listeners = new Set<() => void>();
  private host: Host;

  constructor(host: Host) {
    this.host = host;
  }

  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  getVersion = () => this.state.version;

  private changed(patch: Partial<State>) {
    const next = { ...this.state, ...patch, version: this.state.version + 1 };
    // A tab that went away (a card's subject, a queries list) takes the panel back to the data its view needs.
    const home = dataTabOf(next.view, next.serverPage);
    const leaving =
      next.currentTab !== home && !visibleTabs(next).includes(next.currentTab);
    if (leaving) next.currentTab = home;
    this.state = next;
    if (leaving) this.host.sendMessage('Set-Tab', { tab: home });
    for (const listener of this.listeners) listener();
  }

  /** Shows a view (and, for Server, a page): the server is told which tab's data to send. */
  setView(view: PanelView, serverPage: ServerPage = this.state.serverPage) {
    const tab = dataTabOf(view, serverPage);
    if (tab !== this.state.currentTab)
      this.host.sendMessage('Set-Tab', { tab });
    this.changed({ view, serverPage, currentTab: tab });
  }

  /** Closes the card over the view (examine, inspect, the turf list). */
  closeCard() {
    this.setTab(dataTabOf(this.state.view, this.state.serverPage));
  }

  setTab(tab: string) {
    if (tab === this.state.currentTab) return;
    this.host.sendMessage('Set-Tab', { tab });
    this.changed({ currentTab: tab });
  }

  /**
   * The server only reads panel_tabs for the permanent tabs and rebuilds the
   * rest from init_verbs itself, so there is no topic per verb tab.
   */
  private withTab(tabs: string[], tab: string) {
    if (tabs.includes(tab)) return tabs;
    this.host.sendMessage('Send-Tabs', { tab });
    return [...tabs, tab];
  }

  private withoutTabs(tabs: string[], remove: string[]) {
    for (const tab of remove) {
      if (tabs.includes(tab)) this.host.sendMessage('Remove-Tabs', { tab });
    }
    return tabs.filter((tab) => !remove.includes(tab));
  }

  private addVerbs(into: Verb[], add: Verb[]) {
    const names = new Set(into.map((verb) => verb[1]));
    const verbs = [...into];
    for (const verb of add) {
      if (!verb[0] || names.has(verb[1])) continue;
      names.add(verb[1]);
      verbs.push(verb);
    }
    return verbs;
  }

  /** One server message; one it cannot read is logged and dropped, so the panel keeps taking the next. */
  receive(type: string, payload: any) {
    try {
      this.receiveUnsafe(type, payload);
    } catch (error) {
      console.error(`stat panel: dropped ${type}`, error);
    }
  }

  private receiveUnsafe(type: string, payload: any) {
    const { state } = this;
    const tabs = state.permanentTabs;
    switch (type) {
      case 'init_verbs':
        // The server just cut panel_tabs: it needs the permanent tabs back.
        for (const tab of tabs) this.host.sendMessage('Send-Tabs', { tab });
        this.changed({ verbs: this.addVerbs([], payload.verblist || []) });
        break;
      case 'add_verb_list':
        this.changed({ verbs: this.addVerbs(state.verbs, payload) });
        break;
      case 'remove_verb_list': {
        const gone = new Set(payload.map((verb: Verb) => verb[1]));
        this.changed({
          verbs: state.verbs.filter((verb) => !gone.has(verb[1])),
        });
        break;
      }
      case 'update_stat': {
        const statusParts = [
          payload.ping_str,
          ...payload.global_data,
          ...(payload.other_str || []),
        ].filter((part) => part !== null && part !== undefined);
        // Unchanged lines: no new state, so nothing re-renders.
        if (sameLines(statusParts, state.statusParts)) break;
        this.changed({ statusParts });
        break;
      }
      case 'update_mc': {
        // The server sends only the sections that changed ("partial"); the header's fields sit at the top level of the panel's data.
        const sections = payload.mc_metrics || {};
        const base = payload.partial && state.mcMetrics ? state.mcMetrics : {};
        this.changed({
          mcLocation: payload.coord_entry || '',
          mcMetrics: { ...base, ...sections, ...(sections.header || {}) },
          permanentTabs: this.withTab(tabs, 'MC'),
        });
        break;
      }
      case 'update_spells':
        this.changed({ spells: payload.actions || [] });
        break;
      case 'remove_spells':
        this.changed({ spells: [] });
        break;
      case 'create_debug': {
        const tab = 'Debug Stat Panel';
        this.changed({
          permanentTabs: tabs.includes(tab)
            ? this.withoutTabs(tabs, [tab])
            : this.withTab(tabs, tab),
        });
        break;
      }
      case 'create_listedturf':
        this.changed({
          turfName: payload,
          permanentTabs: this.withTab(
            this.withoutTabs(tabs, state.turfName ? [state.turfName] : []),
            payload,
          ),
        });
        this.setTab(payload);
        break;
      case 'update_listedturf':
        this.changed({ turfContents: payload });
        break;
      case 'remove_listedturf':
        this.changed({
          permanentTabs: this.withoutTabs(tabs, [state.turfName]),
          turfName: '',
        });
        break;
      case 'create_misc':
        this.changed({ permanentTabs: this.withTab(tabs, payload) });
        break;
      case 'remove_misc': {
        const { [payload]: _gone, ...misc } = state.misc;
        this.changed({
          permanentTabs: this.withoutTabs(tabs, [payload]),
          misc,
        });
        break;
      }
      case 'update_misc':
        this.changed({ misc: { ...state.misc, [payload.TN]: payload.TC } });
        break;
      case 'remove_admin_tabs':
        this.changed({
          hrefToken: null,
          tickets: [],
          sdql2: [],
          permanentTabs: this.withoutTabs(tabs, ['MC', 'Tickets', 'SDQL2']),
        });
        break;
      case 'add_admin_tabs':
        this.changed({
          hrefToken: payload,
          permanentTabs: this.withTab(this.withTab(tabs, 'MC'), 'Tickets'),
        });
        break;
      case 'add_tickets_tabs':
        this.changed({
          hrefToken: payload,
          permanentTabs: this.withTab(tabs, 'Tickets'),
        });
        break;
      case 'update_tickets':
        this.changed({
          tickets: payload,
          permanentTabs: this.withTab(tabs, 'Tickets'),
        });
        break;
      case 'update_sdql2':
        this.changed({
          sdql2: payload,
          permanentTabs: payload.length ? this.withTab(tabs, 'SDQL2') : tabs,
        });
        break;
      case 'remove_sdql2':
        this.changed({
          sdql2: [],
          permanentTabs: this.withoutTabs(tabs, ['SDQL2']),
        });
        break;
      case 'remove_mc':
        this.changed({ permanentTabs: this.withoutTabs(tabs, ['MC']) });
        break;
      case 'update_examine':
        this.changed({
          examine: payload.EX,
          permanentTabs: payload.EX.length
            ? this.withTab(tabs, 'Examine')
            : tabs,
        });
        if (payload.UPD) this.setTab('Examine');
        break;
      case 'update_inspect':
        this.changed({
          inspect: payload.data ?? null,
          permanentTabs: payload.data ? this.withTab(tabs, 'Inspect') : tabs,
        });
        if (payload.switch) this.setTab('Inspect');
        break;
      case 'update_abilities': {
        const shown = hasAbilities(payload);
        this.changed({
          abilities: shown ? payload : null,
          abilitiesAt: Date.now(),
          permanentTabs: shown
            ? this.withTab(tabs, 'Abilities')
            : this.withoutTabs(tabs, ['Abilities']),
        });
        break;
      }
      case 'update_split_admin_tabs':
        this.changed({ splitAdminTabs: payload === true });
        break;
    }
  }

  /** The Debug tab's reset. */
  wipeVerbs() {
    this.changed({ verbs: [] });
    this.host.sendMessage('Update-Verbs');
  }
}
