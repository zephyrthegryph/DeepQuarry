import { describe, expect, it } from 'bun:test';
import { gridDropIndex } from './liveGrid';

// Two rows of two: a wrapping grid (the abilities grid).
const rects = [
  { id: 'a', left: 0, top: 0, width: 50, height: 30 },
  { id: 'b', left: 60, top: 0, width: 50, height: 30 },
  { id: 'c', left: 0, top: 40, width: 50, height: 30 },
  { id: 'd', left: 60, top: 40, width: 50, height: 30 },
];

describe('live grid', () => {
  it('takes the place of the item under the pointer, across rows', () => {
    expect(gridDropIndex(rects, 10, 10)).toBe(0);
    expect(gridDropIndex(rects, 70, 50)).toBe(3);
    expect(gridDropIndex(rects, 10, 50)).toBe(2);
  });

  it('takes the nearest item in a gap or past the end', () => {
    expect(gridDropIndex(rects, 55, 50)).toBe(2);
    expect(gridDropIndex(rects, 200, 60)).toBe(3);
    expect(gridDropIndex([], 0, 0)).toBe(-1);
  });
});
