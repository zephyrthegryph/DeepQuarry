import { describe, expect, it } from 'bun:test';
import {
  categoryCounts,
  filterToggles,
  filterVerbs,
  groupBySub,
  groupToggles,
  matchesQuery,
  pick,
  subCategory,
  type ToggleRow,
  topCategory,
  type VerbRow,
} from './logic';

const verbs: VerbRow[] = [
  {
    id: 'a',
    name: 'View Variables',
    desc: 'Inspect a datum',
    cat: 'Debug.Investigate',
  },
  { id: 'b', name: 'Spawn', desc: 'Create an atom', cat: 'Debug.Game' },
  { id: 'c', name: 'Aghost', desc: 'Ghost out', cat: 'Admin.Game' },
  { id: 'd', name: 'Mapping Thing', desc: '', cat: 'Mapping' },
];

describe('categories', () => {
  it('splits a dotted category', () => {
    expect(topCategory('Debug.Investigate')).toBe('Debug');
    expect(subCategory('Debug.Investigate')).toBe('Investigate');
    expect(topCategory('Mapping')).toBe('Mapping');
    expect(subCategory('Mapping')).toBe('');
  });

  it('counts the top-level categories', () => {
    expect(categoryCounts(verbs)).toEqual([
      ['Admin', 1],
      ['Debug', 2],
      ['Mapping', 1],
    ]);
  });

  it('groups by sub-category with the top level first', () => {
    const groups = groupBySub([
      ...verbs,
      { id: 'e', name: 'Top', desc: '', cat: 'Debug' },
    ]);
    expect(groups[0].sub).toBe('');
  });
});

describe('search', () => {
  it('matches every word in name, description or category', () => {
    expect(matchesQuery(verbs[0], 'variables')).toBe(true);
    expect(matchesQuery(verbs[0], 'inspect datum')).toBe(true);
    expect(matchesQuery(verbs[0], 'investigate')).toBe(true);
    expect(matchesQuery(verbs[0], 'variables atom')).toBe(false);
    expect(matchesQuery(verbs[0], '')).toBe(true);
  });

  it('filters by query and category, sorted by name', () => {
    expect(filterVerbs(verbs, '', 'Debug').map((verb) => verb.id)).toEqual([
      'b',
      'a',
    ]);
    expect(filterVerbs(verbs, 'ghost', null).map((verb) => verb.id)).toEqual([
      'c',
    ]);
    expect(filterVerbs(verbs, 'ghost', 'Debug')).toEqual([]);
  });
});

describe('pick', () => {
  it('keeps the order of the ids and skips verbs the admin may not use', () => {
    expect(pick(verbs, ['c', 'zz', 'a']).map((verb) => verb.id)).toEqual([
      'c',
      'a',
    ]);
  });
});

describe('toggles', () => {
  const toggles: ToggleRow[] = [
    {
      id: 'ooc',
      label: 'Player OOC',
      desc: '',
      group: 'Chat',
      value: true,
      can: true,
    },
    {
      id: 'ai',
      label: 'AI job',
      desc: 'Players may play as AI',
      group: 'Game',
      value: false,
      can: true,
    },
    {
      id: 'dsay',
      label: 'Deadchat',
      desc: '',
      group: 'Chat',
      value: true,
      can: false,
    },
  ];

  it('groups in first-seen order', () => {
    const groups = groupToggles(toggles);
    expect(groups.map((group) => group.group)).toEqual(['Chat', 'Game']);
    expect(groups[0].rows).toHaveLength(2);
  });

  it('searches label, description and group', () => {
    expect(filterToggles(toggles, 'player').map((toggle) => toggle.id)).toEqual(
      ['ooc', 'ai'],
    );
    expect(filterToggles(toggles, 'game')).toHaveLength(1);
  });
});
