import { describe, expect, it } from 'bun:test';
import { REGION_CARDS, regionForHighlight } from './LooksPage';

describe('Looks categories', () => {
  it('shows every card in exactly one category', () => {
    const cards = Object.values(REGION_CARDS).flat();
    expect(new Set(cards).size).toBe(cards.length);
  });
  it('lands a search jump on the category holding the setting', () => {
    expect(regionForHighlight('pref:tail_color2')).toBe('tail');
    expect(regionForHighlight('pref:hair_style_name')).toBe('hair');
    expect(regionForHighlight('editor:body_markings')).toBe('markings');
    expect(regionForHighlight('editor:organs')).toBe('organs');
    expect(regionForHighlight('pref:digitigrade')).toBe('body');
    expect(regionForHighlight('group:appearance/wings')).toBe('wings');
    expect(regionForHighlight('pref:something_unclaimed')).toBe('body');
  });
  it('stays put for the left column, which is always shown', () => {
    expect(regionForHighlight('pref:palette_primary')).toBeNull();
    expect(regionForHighlight('group:appearance/preview')).toBeNull();
  });
});
