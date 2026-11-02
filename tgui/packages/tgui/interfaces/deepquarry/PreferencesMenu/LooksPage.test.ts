import { describe, expect, it } from 'bun:test';
import {
  legChoices,
  REGION_CARDS,
  regionForHighlight,
  withNoneChoice,
  withSkin,
} from './LooksPage';

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

describe('withNoneChoice', () => {
  it('puts None first and drops the old blank styles', () => {
    const c = withNoneChoice(['none', 'fox', 'cat']);
    expect(Object.entries(c)).toEqual([
      ['', 'None'],
      ['fox', 'Fox'],
      ['cat', 'Cat'],
    ]);
  });
});

describe('legChoices', () => {
  it('offers Normal, Digitigrade and every taur body in one list', () => {
    expect(Object.keys(legChoices(true, [['Horse', 'Horse']]))).toEqual([
      'plantigrade',
      'digitigrade',
      'Horse',
    ]);
    expect(Object.keys(legChoices(false, []))).toEqual(['plantigrade']);
  });
});

describe('withSkin', () => {
  it("tints the body's skin layers with the character's skin colour", () => {
    const thumbs = withSkin(
      {
        '': {
          layers: [
            { icon: 'b', icon_state: 'torso_m', color: 'skin', blend: 'add' },
            { icon: 'b', icon_state: 'eyes', color: null },
          ],
          base: 1,
        },
        fox: { icon: 'e', icon_state: 'fox' },
      },
      '#C8A283',
    );
    expect(thumbs[''].layers?.[0].color).toBe('#c8a283');
    expect(thumbs[''].layers?.[1].color).toBeNull();
    expect(thumbs.fox).toEqual({ icon: 'e', icon_state: 'fox' });
  });
});
