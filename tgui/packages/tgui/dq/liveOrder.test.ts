import { describe, expect, it } from 'bun:test';
import { liveClamp, liveDropIndex, liveSlide, moveTo } from './liveOrder';

// A vertical list (the window dock) on the same model as the tab strips.
const rows = [
  { id: 'a', start: 0, size: 100 },
  { id: 'b', start: 100, size: 40 },
  { id: 'c', start: 140, size: 60 },
];

describe('live order', () => {
  it('lands where the dragged centre passes the others', () => {
    expect(liveDropIndex(rows, 'a', 30)).toBe(0);
    expect(liveDropIndex(rows, 'a', 80)).toBe(1);
    expect(liveDropIndex(rows, 'a', 130)).toBe(2);
    expect(liveDropIndex(rows, 'c', -140)).toBe(0);
    expect(liveDropIndex(rows, 'zzz', 0)).toBe(-1);
  });

  it('slides the passed items by the dragged one', () => {
    expect(liveSlide(rows, 0, 2, 1)).toBe(-100);
    expect(liveSlide(rows, 0, 2, 2)).toBe(-100);
    expect(liveSlide(rows, 2, 0, 0)).toBe(60);
    expect(liveSlide(rows, 0, 1, 2)).toBe(0);
  });

  it('only counts items on the dragged one’s line', () => {
    const wrapped = [
      { id: 'a', start: 0, size: 50, line: 0 },
      { id: 'b', start: 0, size: 50, line: 20 },
    ];
    expect(liveDropIndex(wrapped, 'a', 40)).toBe(0);
  });

  it('stays inside the list', () => {
    expect(liveClamp(rows[0], -40, 0, 200)).toBe(0);
    expect(liveClamp(rows[0], 500, 0, 200)).toBe(100);
    expect(moveTo(['a', 'b', 'c'], 'a', 2)).toEqual(['b', 'c', 'a']);
  });
});
