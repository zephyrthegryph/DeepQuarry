import { describe, expect, it } from 'bun:test';
import { SNAP_DISTANCE, snapToScreen } from './snap';

const size: [number, number] = [500, 600];
const screen: [number, number] = [2560, 1440];

describe('snapToScreen', () => {
  it('leaves a window away from every edge where it is', () => {
    expect(snapToScreen([900, 400], size, screen)).toEqual([900, 400]);
  });

  it('sticks to one edge on one axis only', () => {
    expect(snapToScreen([10, 400], size, screen)).toEqual([0, 400]);
    expect(snapToScreen([900, 830], size, screen)).toEqual([900, 840]);
  });

  it('sticks to both edges of a corner, from either side', () => {
    expect(snapToScreen([-12, -5], size, screen)).toEqual([0, 0]);
    expect(snapToScreen([2070, 850], size, screen)).toEqual([2060, 840]);
  });

  it('stops at the snap distance', () => {
    expect(snapToScreen([SNAP_DISTANCE + 1, 400], size, screen)[0]).toBe(
      SNAP_DISTANCE + 1,
    );
  });

  it('snaps to the edges of a screen that does not start at zero', () => {
    const origin: [number, number] = [-1920, 40];
    expect(
      snapToScreen([-1910, 50], size, screen, SNAP_DISTANCE, origin),
    ).toEqual([-1920, 40]);
    expect(
      snapToScreen([135, 400], size, screen, SNAP_DISTANCE, origin)[0],
    ).toBe(140);
  });

  it('has a generous snap distance', () => {
    expect(SNAP_DISTANCE).toBeGreaterThanOrEqual(48);
  });

  it("rests flush against the right-hand panel's left edge", () => {
    // The panel starts at x 1900: a 500 wide window's right edge meets it at x 1400.
    expect(
      snapToScreen([1430, 400], size, screen, SNAP_DISTANCE, [0, 0], [1900]),
    ).toEqual([1400, 400]);
    expect(
      snapToScreen([1360, 400], size, screen, SNAP_DISTANCE, [0, 0], [1900])[0],
    ).toBe(1400);
    expect(
      snapToScreen([1300, 400], size, screen, SNAP_DISTANCE, [0, 0], [1900])[0],
    ).toBe(1300);
  });
});
