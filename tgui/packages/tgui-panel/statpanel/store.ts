/**
 * The stat panel's state and its side of the server protocol: the messages
 * code/content/client/statpanel_service.dm sends, as data, with the tab bar
 * derived from them instead of kept in the DOM.
 */

export type Host = {
  sendMessage: (type: string, payload?: object) => void;
};

/** [category, name, description] */
export type Verb = [string, string, string?];

export type State = {
  version: number;
  currentTab: string;
  statusParts: string[];
  mcParts: (string | number)[][];
  mcMetrics: any;
  hrefToken: string | null;
  verbs: Verb[];
  spells: string[][];
  examine: string[];
  tickets: string[][];
  misc: Record<string, any[][]>;
  sdql2: string[][];
  permanentTabs: string[];
  turfName: string;
  turfContents: string[][];
  splitAdminTabs: boolean;
};

export function initialState(): State {
  return {
    version: 0,
    currentTab: 'Status',
    statusParts: ['Loading...'],
    mcParts: [['Loading...', '']],
    mcMetrics: null,
    hrefToken: null,
    verbs: [],
    spells: [],
    examine: [],
    tickets: [],
    misc: {},
    sdql2: [],
    permanentTabs: ['Status'],
    turfName: '',
    turfContents: [],
    splitAdminTabs: false,
  };
}

/** The tab a verb category shows under: "Admin.Game" is in "Admin". */
export function tabOfCategory(category: string, split: boolean): string {
  if (!category.includes('.')) return category;
  const [head, tail] = category.split('.');
  return split && head === 'Admin' ? tail : head;
}

const PINNED = ['Status', 'MC', 'Tickets'];

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

/** Verbs of one tab: top level first, then one group per subcategory. */
export function verbsOfTab(
  state: State,
  tab: string,
): { group: string | null; verbs: Verb[] }[] {
  const groups = new Map<string | null, Verb[]>([[null, []]]);
  for (const verb of state.verbs) {
    if (tabOfCategory(verb[0], state.splitAdminTabs) !== tab) continue;
    const group = verb[0].includes('.') ? verb[0].split('.')[1] : null;
    if (!groups.has(group)) groups.set(group, []);
    groups.get(group)!.push(verb);
  }
  const byName = (a: Verb, b: Verb) => a[1].localeCompare(b[1]);
  return [...groups]
    .filter(([, verbs]) => verbs.length)
    .sort(([a], [b]) => (a ?? '').localeCompare(b ?? ''))
    .map(([group, verbs]) => ({ group, verbs: verbs.sort(byName) }));
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
    // A tab that went away takes the view back to Status.
    const leaving = !visibleTabs(next).includes(next.currentTab);
    if (leaving) next.currentTab = 'Status';
    this.state = next;
    if (leaving) this.host.sendMessage('Set-Tab', { tab: 'Status' });
    for (const listener of this.listeners) listener();
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

  /** One server message. */
  receive(type: string, payload: any) {
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
      case 'update_stat':
        this.changed({
          statusParts: [
            payload.ping_str,
            ...payload.global_data,
            ...(payload.other_str || []),
          ].filter((part) => part !== null && part !== undefined),
        });
        break;
      case 'update_mc':
        this.changed({
          mcParts: [['Location:', payload.coord_entry], ...payload.mc_data],
          mcMetrics: payload.mc_metrics,
          permanentTabs: this.withTab(tabs, 'MC'),
        });
        break;
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
