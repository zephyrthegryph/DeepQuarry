import { describe, expect, it } from 'bun:test';
import { filterLanguages, languageKeyProblem } from './LanguagePicker';

const meta = (name: string, restricted = false, desc = '') => ({
  name,
  desc,
  restricted,
  default_key: '',
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

describe('languageKeyProblem', () => {
  const keys = { Galcom: ',g', Siik: ',q' };
  it("takes a free prefix, and the language's own", () => {
    expect(languageKeyProblem(',x', 'Siik', keys)).toBeNull();
    expect(languageKeyProblem('~lat', 'Siik', keys)).toBeNull();
    expect(languageKeyProblem(',q', 'Siik', keys)).toBeNull();
  });
  it('refuses a key another language holds, and anything else', () => {
    expect(languageKeyProblem(',g', 'Siik', keys)).toContain('Galcom');
    expect(languageKeyProblem(':x', 'Siik', keys)).not.toBeNull();
    expect(languageKeyProblem('', 'Siik', keys)).not.toBeNull();
  });
});
