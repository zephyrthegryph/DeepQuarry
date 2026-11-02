import { describe, expect, it } from 'bun:test';
import { REGION_CARDS, regionForHighlight } from './LooksPage';

describe('Looks categories', () => {
  it('shows every card in exactly one category', () => {
    const cards = Object.values(REGION_CARDS).flat();
    expect(new Set(cards).size).toBe(cards.length);
  });
  it('lands a search jump on the category holding the setting', () => {
    for (const target of [
      'pref:tail_color2',
      'pref:hair_style_name',
      'editor:body_markings',
      'pref:digitigrade',
      'group:appearance/wings',
      'group:appearance/markings',
      'pref:something_unclaimed',
    ]) {
      expect(regionForHighlight(target)).toBe('body');
    }
    expect(regionForHighlight('editor:organs')).toBe('organs');
    expect(regionForHighlight('group:appearance/organs')).toBe('organs');
  });
  it('stays put for the left column, which is always shown', () => {
    expect(regionForHighlight('pref:palette_primary')).toBeNull();
    expect(regionForHighlight('group:appearance/preview')).toBeNull();
  });
});
