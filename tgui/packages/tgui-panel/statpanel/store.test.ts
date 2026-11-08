import { describe, expect, it } from 'bun:test';
import {
  StatStore,
  searchVerbs,
  verbCommand,
  verbGroupsOf,
  visibleTabs,
} from './store';

function setup() {
  const sent: [string, any][] = [];
  const store = new StatStore({
    sendMessage: (type, payload) => sent.push([type, payload]),
  });
  return { sent, store };
}

const verblist = [
  ['IC', 'Say', 'speak'],
  ['IC', 'Emote'],
  ['OOC', 'Who'],
  ['Admin.Game', 'Ban'],
  ['Admin', 'Aghost'],
];

describe('stat panel store', () => {
  it('derives pinned-then-sorted tabs from verbs', () => {
    const { store } = setup();
    store.receive('init_verbs', { verblist });
    store.receive('add_tickets_tabs', 'token');
    expect(visibleTabs(store.state)).toEqual([
      'Status',
      'Tickets',
      'Admin',
      'IC',
      'OOC',
    ]);
  });

  it('groups verbs by view and group, in layout order, by name', () => {
    const { store } = setup();
    store.receive('init_verbs', { verblist });
    expect(verbGroupsOf(store.state, 'Staff').map((g) => g.group)).toEqual([
      'Players',
      'Your admin session',
    ]);
    expect(
      verbGroupsOf(store.state, 'Actions')[0].verbs.map((v) => v[1]),
    ).toEqual(['Emote', 'Say']);
  });

  it('a tab that empties goes away and the view returns to Status', () => {
    const { sent, store } = setup();
    store.receive('init_verbs', { verblist });
    store.setTab('OOC');
    store.receive('remove_verb_list', [['OOC', 'Who']]);
    expect(store.state.currentTab).toBe('Status');
    expect(sent.at(-1)).toEqual(['Set-Tab', { tab: 'Status' }]);
  });

  it('does not duplicate verbs by name', () => {
    const { store } = setup();
    store.receive('init_verbs', { verblist });
    store.receive('add_verb_list', [['IC', 'Say']]);
    expect(store.state.verbs.filter((v) => v[1] === 'Say').length).toBe(1);
  });

  it('init_verbs sends only the permanent tabs back, not a topic per tab', () => {
    const { sent, store } = setup();
    store.receive('add_admin_tabs', 'token');
    sent.length = 0;
    store.receive('init_verbs', { verblist });
    expect(sent.map((m) => m[1].tab)).toEqual(['Status', 'MC', 'Tickets']);
  });

  it('removing admin tabs clears them and tells the server', () => {
    const { sent, store } = setup();
    store.receive('add_admin_tabs', 'token');
    store.setTab('MC');
    store.receive('remove_admin_tabs', undefined);
    expect(store.state.hrefToken).toBeNull();
    expect(store.state.currentTab).toBe('Status');
    expect(visibleTabs(store.state)).toEqual(['Status']);
    expect(sent).toContainEqual(['Remove-Tabs', { tab: 'MC' }]);
  });

  it('builds the status lines, skipping nulls', () => {
    const { store } = setup();
    store.receive('update_stat', {
      ping_str: 'Ping',
      global_data: ['Map', null],
      other_str: ['Mine'],
    });
    expect(store.state.statusParts).toEqual(['Ping', 'Map', 'Mine']);
  });

  it('a listed turf replaces the last one and takes the view', () => {
    const { store } = setup();
    store.receive('create_listedturf', 'Floor');
    store.receive('create_listedturf', 'Wall');
    expect(visibleTabs(store.state)).toEqual(['Status', 'Wall']);
    expect(store.state.currentTab).toBe('Wall');
  });

  it('examine with UPD switches to the tab', () => {
    const { store } = setup();
    store.receive('update_examine', { EX: ['a'], UPD: 1 });
    expect(store.state.currentTab).toBe('Examine');
  });

  it('inspect data adds the Inspect tab and switches to it', () => {
    const { store, sent } = setup();
    store.receive('update_inspect', { data: { target: 'Pen' }, switch: true });
    expect(visibleTabs(store.state)).toContain('Inspect');
    expect(store.state.currentTab).toBe('Inspect');
    expect(store.state.inspect?.target).toBe('Pen');
    expect(sent).toContainEqual(['Set-Tab', { tab: 'Inspect' }]);
  });

  it('an inspect refresh keeps the current tab', () => {
    const { store } = setup();
    store.receive('update_inspect', { data: { target: 'Pen' }, switch: false });
    expect(store.state.currentTab).toBe('Status');
  });

  it('misc tabs come and go', () => {
    const { store } = setup();
    store.receive('create_misc', 'Vore');
    store.receive('update_misc', { TN: 'Vore', TC: [['x']] });
    expect(store.state.misc.Vore).toEqual([['x']]);
    store.receive('remove_misc', 'Vore');
    expect(store.state.misc.Vore).toBeUndefined();
    expect(visibleTabs(store.state)).toEqual(['Status']);
  });

  it('searches verbs across tabs and builds the command', () => {
    const { store } = setup();
    store.receive('init_verbs', { verblist });
    expect(searchVerbs(store.state, 'a').map((v) => v[1])).toEqual([
      'Aghost',
      'Ban',
      'Say',
    ]);
    expect(searchVerbs(store.state, ' ')).toEqual([]);
    expect(verbCommand('Fix Stat Panel')).toBe('Fix-Stat-Panel');
  });

  it('the Abilities tab comes with the first ability and goes with the last', () => {
    const { sent, store } = setup();
    store.receive('init_verbs', { verblist });
    const entry = {
      ref: 'r1',
      id: 'Items/x',
      name: 'Toggle Flashlight',
      desc: '',
      category: 'Items',
      icon: null,
      cost: null,
      cooldown: 0,
      toggled: null,
      channel: null,
      refusal: null,
      slot: 1,
    };
    store.receive('update_abilities', {
      abilities: [entry],
      resources: [],
      slots: 9,
    });
    expect(visibleTabs(store.state).slice(0, 2)).toEqual([
      'Status',
      'Abilities',
    ]);
    expect(store.state.abilities?.abilities[0].name).toBe('Toggle Flashlight');
    store.setTab('Abilities');
    store.receive('update_abilities', {
      abilities: [],
      resources: [],
      slots: 9,
    });
    expect(visibleTabs(store.state)).not.toContain('Abilities');
    expect(store.state.abilities).toBeNull();
    expect(store.state.currentTab).toBe('Status');
    expect(sent.at(-1)).toEqual(['Set-Tab', { tab: 'Status' }]);
  });

  it('a resource alone is enough for the tab', () => {
    const { store } = setup();
    store.receive('update_abilities', {
      abilities: [],
      resources: [{ name: 'Energy', value: 50, max: 100 }],
      slots: 9,
    });
    expect(visibleTabs(store.state)).toContain('Abilities');
  });
});

describe('MC Health updates', () => {
  it('merge the sections a partial update carries into the panel data', () => {
    const store = new StatStore({ sendMessage: () => {} });
    store.receive('update_mc', {
      mc_metrics: { header: { current_usage: 20 }, rust: { a: 1 } },
      partial: false,
    });
    store.receive('update_mc', {
      mc_metrics: { header: { current_usage: 30 } },
      partial: true,
    });
    const data = store.state.mcMetrics as any;
    expect(data.current_usage).toBe(30);
    expect(data.rust).toEqual({ a: 1 });
    store.receive('update_mc', { mc_metrics: { header: {} }, partial: false });
    expect((store.state.mcMetrics as any).rust).toBeUndefined();
  });
});

describe('stat panel store, fail-safe', () => {
  it('a message it cannot read is dropped, and the next one still lands', () => {
    const { store } = setup();
    // A malformed abilities payload (no lists) once threw out of receive().
    expect(() => store.receive('update_abilities', {})).not.toThrow();
    store.receive('init_verbs', { verblist });
    expect(store.state.verbs.length).toBe(verblist.length);
  });
});
