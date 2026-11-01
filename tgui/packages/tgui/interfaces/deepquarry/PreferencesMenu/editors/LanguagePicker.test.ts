import { describe, expect, it } from 'bun:test';
import { filterLanguages } from './LanguagePicker';

const meta = (name: string, restricted = false, desc = '') => ({
  name,
  desc,
  restricted,
});
const entries: [string, ReturnType<typeof meta>][] = [
  ['Galcom', meta('Galcom', false, 'Common tongue')],
  ['Sol Common', meta('Sol Common')],
  ['Hivemind', meta('Hivemind', true)],
  ['Secret', meta('Secret')],
  ['Terminus', meta('Terminus')],
];

describe('filterLanguages', () => {
  it('drops restricted and unpickable languages', () => {
    const rows = filterLanguages(
      entries,
      new Set(['Galcom', 'Sol Common', 'Hivemind']),
      new Set(),
      '',
    );
    expect(rows.map(([k]) => k)).toEqual(['Galcom', 'Sol Common']);
  });
  it('keeps an already-picked language even if it is no longer pickable', () => {
    const rows = filterLanguages(
      entries,
      new Set(['Galcom']),
      new Set(['Secret']),
      '',
    );
    expect(rows.map(([k]) => k)).toEqual(['Secret', 'Galcom']);
  });
  it('lists everything unrestricted when the server sent no pickable set', () => {
    expect(filterLanguages(entries, null, new Set(), '')).toHaveLength(4);
  });
  it('searches name and description, case-insensitively', () => {
    expect(
      filterLanguages(entries, null, new Set(), 'SOL').map(([k]) => k),
    ).toEqual(['Sol Common']);
    expect(
      filterLanguages(entries, null, new Set(), 'tongue').map(([k]) => k),
    ).toEqual(['Galcom']);
  });
});
