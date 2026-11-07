import { describe, expect, it } from 'bun:test';

import {
  clampCssSize,
  isDragMove,
  isReachable,
  MIN_HEIGHT,
  MIN_WIDTH,
  minNativeSize,
  parseStoredPosition,
  sizeToRestore,
  VIRTUAL_DESKTOP,
} from './placement';

const size = { w: 360, h: 30 };
const left = { x: -1920, y: 0, w: 1920, h: 1080 };
const main = { x: 0, y: 0, w: 1920, h: 1080 };

describe('clampCssSize', () => {
  it('raises a too-small request to the minimum', () => {
    expect(clampCssSize(100, 5)).toEqual({ w: MIN_WIDTH, h: MIN_HEIGHT });
  });
  it('keeps a larger request', () => {
    expect(clampCssSize(500, 120)).toEqual({ w: 500, h: 120 });
  });
  it('treats NaN as the minimum', () => {
    expect(clampCssSize(Number.NaN, Number.NaN)).toEqual({
      w: MIN_WIDTH,
      h: MIN_HEIGHT,
    });
  });
});

describe('minNativeSize / sizeToRestore', () => {
  it('scales the minimum by the factor', () => {
    expect(minNativeSize(2)).toEqual({ w: 600, h: 60 });
    expect(minNativeSize(0)).toEqual({ w: MIN_WIDTH, h: MIN_HEIGHT });
  });
  it('restores only the axis that is too small', () => {
    const min = minNativeSize(1);
    expect(sizeToRestore({ w: 200, h: 80 }, min)).toEqual({ w: 300, h: 80 });
    expect(sizeToRestore({ w: 400, h: 10 }, min)).toEqual({ w: 400, h: 30 });
  });
  it('leaves a big enough window alone', () => {
    expect(sizeToRestore({ w: 300, h: 30 }, minNativeSize(1))).toBeNull();
  });
});

describe('isReachable', () => {
  it('accepts a position outside the game window on another screen', () => {
    expect(isReachable({ x: -1500, y: 400 }, size, [left, main])).toBe(true);
  });
  it('accepts a window hanging partly off the edge', () => {
    expect(isReachable({ x: 1850, y: 100 }, size, [main])).toBe(true);
  });
  it('rejects a window fully off every screen', () => {
    expect(isReachable({ x: -3000, y: 100 }, size, [left, main])).toBe(false);
    expect(isReachable({ x: 100, y: 5000 }, size, [left, main])).toBe(false);
  });
  it('rejects a sliver too thin to grab', () => {
    expect(isReachable({ x: 1915, y: 100 }, size, [main])).toBe(false);
  });
  it('uses the virtual desktop when screens are unknown', () => {
    expect(isReachable({ x: 5000, y: 300 }, size, [VIRTUAL_DESKTOP])).toBe(
      true,
    );
    expect(isReachable({ x: 40000, y: 300 }, size, [VIRTUAL_DESKTOP])).toBe(
      false,
    );
  });
});

describe('parseStoredPosition', () => {
  it('reads a stored point, rounding', () => {
    expect(parseStoredPosition({ x: 10.4, y: -20 })).toEqual({ x: 10, y: -20 });
  });
  it('rejects junk', () => {
    expect(parseStoredPosition(null)).toBeNull();
    expect(parseStoredPosition('1,2')).toBeNull();
    expect(parseStoredPosition({ x: 1 })).toBeNull();
    expect(parseStoredPosition({ x: Number.NaN, y: 1 })).toBeNull();
  });
});

describe('isDragMove', () => {
  it('tells a click from a drag', () => {
    expect(isDragMove({ x: 5, y: 5 }, { x: 6, y: 6 })).toBe(false);
    expect(isDragMove({ x: 5, y: 5 }, { x: 5, y: 40 })).toBe(true);
  });
});
