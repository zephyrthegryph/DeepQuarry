import { describe, expect, it } from 'bun:test';
import { clampDrag, dropIndex, moveTo, slideFor } from './Tabs';

const boxes = [
  { id: 'a', left: 0, width: 50, top: 0 },
  { id: 'b', left: 54, width: 50, top: 0 },
  { id: 'c', left: 108, width: 50, top: 0 },
];

describe('tab drag', () => {
  it('lands where the dragged centre passes the others', () => {
    expect(dropIndex(boxes, 'a', 10)).toBe(0);
    expect(dropIndex(boxes, 'a', 60)).toBe(1);
    expect(dropIndex(boxes, 'a', 120)).toBe(2);
    expect(dropIndex(boxes, 'c', -120)).toBe(0);
  });

  it('slides the passed tabs aside by the dragged tab and its gap', () => {
    expect(slideFor(boxes, 0, 2, 1)).toBe(-54);
    expect(slideFor(boxes, 0, 2, 2)).toBe(-54);
    expect(slideFor(boxes, 2, 0, 0)).toBe(54);
    expect(slideFor(boxes, 0, 1, 2)).toBe(0);
  });

  it('stays inside the strip', () => {
    expect(clampDrag(boxes[0], -40, 0, 158)).toBe(0);
    expect(clampDrag(boxes[0], 500, 0, 158)).toBe(108);
  });

  it('commits the new order', () => {
    expect(moveTo(['a', 'b', 'c'], 'a', 2)).toEqual(['b', 'c', 'a']);
  });
});
