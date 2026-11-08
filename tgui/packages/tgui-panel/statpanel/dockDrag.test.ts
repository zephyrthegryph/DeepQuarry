import { describe, expect, it } from 'bun:test';
import { type GroupDrag, groupOffset, indexAtY, outOfPanel } from './DockArea';

const boxes = [
  { id: 'g1', start: 0, size: 100 },
  { id: 'g2', start: 100, size: 50 },
  { id: 'g3', start: 150, size: 50 },
];
const drag = (over: Partial<GroupDrag>): GroupDrag => ({
  group: 'g1',
  window: null,
  dy: 80,
  to: 1,
  join: null,
  float: false,
  boxes,
  ...over,
});

describe('dock drag', () => {
  it('moves the dragged entry with the pointer and slides the passed one', () => {
    expect(groupOffset(drag({}), 'g1')).toBe(80);
    expect(groupOffset(drag({}), 'g2')).toBe(-100);
    expect(groupOffset(drag({}), 'g3')).toBe(0);
  });

  it('holds the list still while stacking, floating or pulling a tab', () => {
    expect(groupOffset(drag({ join: 'g3' }), 'g2')).toBe(0);
    expect(groupOffset(drag({ float: true }), 'g1')).toBe(0);
    expect(groupOffset(drag({ window: 'w' }), 'g1')).toBe(0);
  });

  it('floats only past the chat’s pop-out distance, on any side', () => {
    expect(outOfPanel(-5, 50, 300, 600)).toBe(false);
    expect(outOfPanel(-20, 50, 300, 600)).toBe(true);
    expect(outOfPanel(150, 640, 300, 600)).toBe(true);
    expect(outOfPanel(320, 50, 300, 600)).toBe(true);
  });

  it('places a pulled tab against the entries’ middles', () => {
    expect(indexAtY(boxes, 10)).toBe(0);
    expect(indexAtY(boxes, 60)).toBe(1);
    expect(indexAtY(boxes, 190)).toBe(3);
  });
});
