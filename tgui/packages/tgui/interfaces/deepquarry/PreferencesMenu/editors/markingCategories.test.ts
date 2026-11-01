import { describe, expect, it } from 'bun:test';
import { markingCategory } from './markingCategories';

describe('markingCategory', () => {
  it('reads what a marking is from its name first', () => {
    expect(markingCategory('Bandage, Head 1', ['head'])).toBe('Bandages');
    expect(markingCategory('Tattoo (Heart, R. Arm)', ['r_arm'])).toBe(
      'Tattoos',
    );
    expect(markingCategory('Vox Beak', ['head'])).toBe('Species');
    expect(markingCategory('RACS Spectre FBP Panels', ['head'])).toBe(
      'Robotic',
    );
  });
  it('then where it sits', () => {
    expect(markingCategory('VALE Eyes', ['head'])).toBe('Eyes & brows');
    expect(markingCategory('Fox Chest', ['torso'])).toBe('Torso');
    expect(markingCategory('Fox Hand Socks', ['l_hand', 'r_hand'])).toBe(
      'Arms & hands',
    );
    expect(
      markingCategory('Spots', [
        'head',
        'torso',
        'l_arm',
        'r_arm',
        'l_leg',
        'r_leg',
      ]),
    ).toBe('Full body');
    expect(markingCategory('Odd', ['head', 'l_foot'])).toBe('Other');
  });
});
