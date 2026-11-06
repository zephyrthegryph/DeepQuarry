import { describe, expect, test } from 'bun:test';
import {
  cursorInMap,
  type MapGeometry,
  mapScale,
  placeMenu,
} from './InteractionMenuPlacement';

// A 15x15 view stretched into a 1100x700 control: scale 700/480, letterboxed in x.
const stretch: MapGeometry = {
  mapW: 1100,
  mapH: 700,
  iconSize: 0,
  viewW: 15,
  viewH: 15,
  tileSize: 32,
};
const fixed: MapGeometry = { ...stretch, iconSize: 32, mapW: 480, mapH: 480 };

describe('mapScale', () => {
  test('stretch fits the view and centres it', () => {
    const s = mapScale(stretch);
    expect(s.scale).toBeCloseTo(700 / 480);
    expect(s.renderedH).toBeCloseTo(700);
    expect(s.left).toBeCloseTo((1100 - 700) / 2);
    expect(s.top).toBeCloseTo(0);
  });
  test('fixed zoom is icon-size per tile', () => {
    expect(mapScale(fixed).scale).toBe(1);
  });
});

describe('cursorInMap', () => {
  test('a mob click mid-view on a stretched map lands mid-screen, not at the left', () => {
    const p = cursorInMap(
      'icon-x=16;icon-y=16;right=1;screen-loc=8:16,8:16',
      stretch,
    );
    expect(p).not.toBeNull();
    expect(p?.[0]).toBeGreaterThan(540);
    expect(p?.[0]).toBeLessThan(560);
    expect(p?.[1]).toBeGreaterThan(340);
    expect(p?.[1]).toBeLessThan(360);
  });
  test('fixed zoom is tile times 32 plus the pixel', () => {
    expect(cursorInMap('screen-loc=3:5,15:1', fixed)).toEqual([68, 31]);
  });
  test('a zero pixel offset is still a position', () => {
    expect(cursorInMap('screen-loc=2:0,1:0', fixed)).not.toBeNull();
  });
  test('no pixel part is the tile corner', () => {
    expect(cursorInMap('screen-loc=2,15', fixed)).toEqual([32, 31]);
  });
  test('secondary map prefix and url-encoded params', () => {
    expect(cursorInMap('screen-loc=map%3a3%3a5%2c15%3a1', fixed)).toEqual([
      68, 31,
    ]);
  });
  test('no screen-loc gives null', () => {
    expect(cursorInMap('left=1', fixed)).toBeNull();
  });
});

describe('placeMenu', () => {
  test('opens down and right of the cursor', () => {
    expect(placeMenu([100, 100], 150, 200, 1000, 700)).toEqual([100, 100]);
  });
  test('flips at the right and bottom edges', () => {
    expect(placeMenu([950, 650], 150, 200, 1000, 700)).toEqual([800, 450]);
  });
  test('stays inside when it fits on neither side', () => {
    expect(placeMenu([60, 100], 150, 900, 100, 700)).toEqual([0, 0]);
    expect(placeMenu([5, 5], 300, 300, 200, 200)).toEqual([0, 0]);
  });
});
