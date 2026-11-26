import { describe, expect, it } from 'bun:test';
import {
  legChoices,
  legThumbnails,
  REGION_CARDS,
  withNoneChoice,
  withSkin,
} from './LooksPage';

describe('Looks categories', () => {
  it('shows every card in exactly one category', () => {
    const cards = Object.values(REGION_CARDS).flat();
    expect(new Set(cards).size).toBe(cards.length);
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

describe('legThumbnails', () => {
  it('leaves the None body out so it does not sit under a taur sprite', () => {
    const thumbs = legThumbnails({
      '': {
        layers: [{ icon: 'b', icon_state: 'torso_m', color: null }],
        base: 1,
      },
      Horse: { icon: 't', icon_state: 'horse' },
    });
    expect(Object.keys(thumbs)).toEqual(['Horse']);
    expect(legThumbnails(undefined)).toEqual({});
  });
});
