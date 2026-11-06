import { describe, expect, it } from 'bun:test';
import { markingCategory, markingSubgroup } from './markingCategories';

describe('markingCategory', () => {
  it('reads what a marking is from its name first', () => {
    expect(markingCategory('Bandage, Head 1', ['head'])).toBe('Bandages');
    expect(markingCategory('Tattoo (Heart, R. Arm)', ['r_arm'])).toBe(
      'Tattoos & paint',
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
    expect(markingCategory('Odd', ['head', 'l_foot'])).toBe('Full body');
    expect(markingCategory('Odd', [])).toBe('Other');
  });
  it('corrects what the old rules read wrong', () => {
    expect(markingCategory('Top surgery scars', ['torso'])).toBe('Scars');
    expect(markingCategory('face (Vulp)', ['head'])).toBe('Species');
    expect(markingCategory('Sleek YR3 Plating', ['head', 'torso'])).toBe(
      'Robotic',
    );
    expect(markingCategory('Thin Bodytype', ['torso', 'l_arm'])).toBe(
      'Body shape',
    );
    expect(markingCategory('Hazard Sign (Chest)', ['torso'])).toBe(
      'Tattoos & paint',
    );
    expect(markingCategory('Monoeye', ['head'])).toBe('Eyes & brows');
  });
  it('groups a big category', () => {
    expect(markingSubgroup('Species', 'Vox Beak', ['head'])).toBe('Vox');
    expect(markingSubgroup('Snout & mouth', 'Thin Snout', ['head'])).toBe(
      'Snouts & muzzles',
    );
    expect(markingSubgroup('Scars', 'Scar, Right Leg', ['r_leg'])).toBe('Legs');
    expect(markingSubgroup('Head', 'Blush', ['head'])).toBe('');
  });
});
