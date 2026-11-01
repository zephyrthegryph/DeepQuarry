import { describe, expect, it } from 'bun:test';
import { type DollRegion, dollPixel, zoneAt } from './ZoneDoll';

// A slice of GLOB.zone_sel_regions (code/content/_onclick/hud/screen_objects.dm), in the same order.
const regions: DollRegion[] = [
  ['mouth', 15, 23, 17, 24],
  ['eyes', 14, 26, 18, 26],
  ['eyes', 15, 25, 17, 27],
  ['head', 12, 23, 20, 30],
  ['torso', 12, 14, 20, 22],
  ['r_leg', 10, 4, 15, 9],
];

describe('zoneAt', () => {
  it('finds the part under a pixel', () => {
    expect(zoneAt(regions, 16, 18)).toBe('torso');
    expect(zoneAt(regions, 12, 5)).toBe('r_leg');
  });
  it('puts the mouth and eyes before the head they sit on', () => {
    expect(zoneAt(regions, 16, 23)).toBe('mouth');
    expect(zoneAt(regions, 14, 26)).toBe('eyes');
    expect(zoneAt(regions, 14, 25)).toBe('head');
  });
  it('is null outside every part', () => {
    expect(zoneAt(regions, 1, 1)).toBeNull();
    expect(zoneAt(regions, 16, 31)).toBeNull();
  });
});

describe('dollPixel', () => {
  it('counts from the bottom left and scales with the box', () => {
    expect(dollPixel(0, 127, 128)).toEqual([1, 1]);
    expect(dollPixel(127, 0, 128)).toEqual([32, 32]);
    expect(dollPixel(64, 64, 128)).toEqual([17, 16]);
  });
});
