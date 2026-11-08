import { describe, expect, it } from 'bun:test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  dataTabOf,
  groupRank,
  isOverlayTab,
  KNOWN_CATEGORIES,
  placeOf,
} from './layout';

const root = join(import.meta.dir, '../../../..');

/** Every verb category the DM defines (VERB_CAT_*), as its string. */
function definedCategories(): string[] {
  const text = readFileSync(
    join(root, 'code/defines/host/verb_categories.dm'),
    'utf8',
  );
  return [...text.matchAll(/#define VERB_CAT_\w+ "([^"]+)"/g)].map((m) => m[1]);
}

describe('right panel layout', () => {
  it('every staff and server category has a place outside Actions', () => {
    for (const cat of definedCategories()) {
      const head = cat.split('.')[0];
      if (!['Admin', 'Debug', 'Fun', 'Server', 'Mapping'].includes(head)) {
        continue;
      }
      const place = placeOf(cat);
      expect({ cat, view: place.view }).not.toEqual({ cat, view: 'Actions' });
    }
  });

  it('known categories are real ones, so a rename is noticed', () => {
    const defined = new Set(definedCategories());
    const extra = KNOWN_CATEGORIES.filter(
      (c) => !defined.has(c) && !['Server', 'Profile'].includes(c),
    );
    expect(extra).toEqual([]);
  });

  it('an unknown category still lands somewhere', () => {
    expect(placeOf('Brand New.Thing')).toEqual({
      view: 'Actions',
      group: 'Brand New: Thing',
    });
  });

  it('a view asks the server for the data it shows', () => {
    expect(dataTabOf('Status', 'Health')).toBe('Status');
    expect(dataTabOf('Staff', 'Health')).toBe('Tickets');
    expect(dataTabOf('Server', 'Health')).toBe('MC');
    expect(dataTabOf('Server', 'Queries')).toBe('SDQL2');
    expect(dataTabOf('Actions', 'Health')).toBe('Actions');
  });

  it('examine, inspect and the turf list are cards over the view', () => {
    expect(isOverlayTab('Examine', '')).toBe(true);
    expect(isOverlayTab('Inspect', '')).toBe(true);
    expect(isOverlayTab('Floor', 'Floor')).toBe(true);
    expect(isOverlayTab('Status', 'Floor')).toBe(false);
  });

  it('dangerous groups come after the everyday ones', () => {
    expect(groupRank('Talk')).toBeLessThan(groupRank('Destructive'));
    expect(groupRank('Debug: game')).toBeLessThan(
      groupRank('Debug: dangerous'),
    );
  });
});

describe('panel search', () => {
  it('finds panels and admin verbs the panel does not list', async () => {
    const { searchAll, initialState } = await import('./store');
    const state = {
      ...initialState(),
      verbs: [['Admin', 'Admin Verbs']] as [string, string][],
      searchable: [
        ['Debug', 'Toggle Client Lighting'],
        ['Admin', 'Admin Verbs'],
      ] as [string, string][],
    };
    expect(searchAll(state, 'client light', [])[0].command).toBe(
      'Toggle-Client-Lighting',
    );
    expect(searchAll(state, 'admin verbs', [])).toHaveLength(1);
    expect(searchAll(state, 'health', [])[0].opens).toEqual({
      view: 'Server',
      page: 'Health',
    });
    expect(searchAll(state, 'staff', [])[0].opens).toEqual({ view: 'Staff' });
  });

  it('finds verbs and Menu items, says where each lives, prefix first', async () => {
    const { searchAll, initialState } = await import('./store');
    const { MENU_SECTIONS } = await import('./menu');
    const state = {
      ...initialState(),
      verbs: [
        ['OOC.Game', 'Ghost'],
        ['Admin.Logs', 'Get Server Logs'],
        ['IC.Game', 'Pray'],
      ] as [string, string][],
    };
    const found = searchAll(state, 'log', MENU_SECTIONS);
    // A player (no admin verbs other than this one) still finds it only because the admin view is shown.
    expect(found.map((f) => f.path)).toContain('Staff › Investigate');
    const lobby = searchAll(state, 'return', MENU_SECTIONS);
    expect(lobby[0]).toEqual({
      label: 'Return to lobby',
      path: 'Game › Round',
      command: 'return-to-menu',
    });
    expect(searchAll(state, 'pray', MENU_SECTIONS)[0].path).toBe(
      'Actions › Round',
    );
  });
});
