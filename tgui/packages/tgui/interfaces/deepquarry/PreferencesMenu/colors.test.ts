import { describe, expect, it } from 'bun:test';
import {
  colorCategory,
  colorsInUse,
  isSlotName,
  SUGGESTED_COLORS,
  slotColors,
  suggestedColors,
} from './colors';

describe('colorCategory', () => {
  it('reads the category from a pref key or label', () => {
    expect(colorCategory('hair_color')).toBe('hair');
    expect(colorCategory('facial_hair_color')).toBe('hair');
    expect(colorCategory('eyes_color')).toBe('eyes');
    expect(colorCategory('skin_color')).toBe('skin');
    expect(colorCategory('Wing colour')).toBe('other');
    expect(colorCategory(undefined)).toBe('other');
  });
  it('has a curated set for every category, all valid hex', () => {
    for (const set of Object.values(SUGGESTED_COLORS)) {
      expect(set.length).toBeGreaterThan(0);
      for (const c of set) expect(c).toMatch(/^#[0-9a-f]{6}$/);
    }
    expect(suggestedColors('eyes_color')).toBe(SUGGESTED_COLORS.eyes);
  });
});

describe('colorsInUse', () => {
  it('collects distinct hex values, including lists, and ignores the rest', () => {
    const used = colorsInUse({
      skin_color: '#C8A283',
      hair_color: '#5a3b1e',
      again: '#c8a283',
      parts: ['#111111', 'not a colour', 7],
      name: 'Bob',
    });
    expect(used).toEqual(['#c8a283', '#5a3b1e', '#111111']);
  });
  it('stops at the limit', () => {
    const values = Object.fromEntries(
      Array.from({ length: 30 }, (_, i) => [
        `c${i}`,
        `#${String(i).padStart(2, '0')}0000`,
      ]),
    );
    expect(colorsInUse(values, 5)).toHaveLength(5);
  });
});

describe('palette slots', () => {
  it('knows a slot name from a hex', () => {
    expect(isSlotName('primary')).toBe(true);
    expect(isSlotName('extra2')).toBe(true);
    expect(isSlotName('#ffffff')).toBe(false);
    expect(isSlotName('')).toBe(false);
  });
  it('reads the slots from the values, each as a hex', () => {
    const slots = slotColors({ palette_primary: '#AABBCC' });
    expect(slots.primary).toBe('#aabbcc');
    expect(slots.extra2).toBe('#000000');
  });
});
