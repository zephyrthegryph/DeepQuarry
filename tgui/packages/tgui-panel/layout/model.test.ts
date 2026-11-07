import { describe, expect, it } from 'bun:test';
import {
  clampShare,
  clientRect,
  columnRect,
  dockTarget,
  dragPosition,
  fitSize,
  isMode,
  looseFit,
  MIN_WINDOW_SIZE,
  poppedOut,
  resizeSize,
  SHARE_DEFAULT,
  shareFromHeights,
  shareMoved,
  splitterFor,
  trustedArea,
  windowUnderPointer,
} from './model';

describe('pin layout math', () => {
  it('knows the modes', () => {
    expect(isMode('top')).toBe(true);
    expect(isMode('bottom')).toBe(true);
    expect(isMode('float')).toBe(true);
    expect(isMode('left')).toBe(false);
    expect(isMode(undefined)).toBe(false);
  });

  it('holds the share to what the column can show', () => {
    expect(clampShare(5)).toBe(20);
    expect(clampShare(99)).toBe(80);
    expect(clampShare(40.4)).toBe(40);
    expect(clampShare(Number.NaN)).toBe(SHARE_DEFAULT);
  });

  it('puts the chat first at the top and second at the bottom (as chat_splitter_for)', () => {
    expect(splitterFor('top', 40)).toBe(40);
    expect(splitterFor('bottom', 40)).toBe(60);
    expect(splitterFor('bottom', 90)).toBe(20);
    expect(splitterFor('float', 40)).toBe(60);
  });

  it('measures the share from the pane and the column heights', () => {
    expect(shareFromHeights(400, 1000)).toBe(40);
    expect(shareFromHeights(10, 1000)).toBe(20);
    expect(shareFromHeights(0, 1000)).toBeNull();
    expect(shareFromHeights(400, 0)).toBeNull();
    expect(shareFromHeights(1200, 1000)).toBeNull();
  });

  it('reports a share only when the player moved the splitter', () => {
    expect(shareMoved(40, 41)).toBe(false);
    expect(shareMoved(40, 43)).toBe(true);
    expect(shareMoved(40, 35)).toBe(true);
    expect(shareMoved(40, null)).toBe(false);
  });
});

describe('window drag math', () => {
  it('moves the window by the mouse delta in physical pixels', () => {
    const start = { x: 100, y: 80 };
    const mouse = { x: 500, y: 300 };
    expect(dragPosition(start, mouse, { x: 530, y: 290 })).toEqual({
      x: 130,
      y: 70,
    });
    expect(dragPosition(start, mouse, { x: 530, y: 290 }, 1.5)).toEqual({
      x: 145,
      y: 65,
    });
    expect(dragPosition(start, mouse, mouse)).toEqual(start);
  });

  it('resizes by the delta and stops at the minimum size', () => {
    const size = { x: 560, y: 420 };
    const mouse = { x: 900, y: 700 };
    expect(resizeSize(size, mouse, { x: 950, y: 740 })).toEqual({
      x: 610,
      y: 460,
    });
    expect(resizeSize(size, mouse, { x: 0, y: 0 })).toEqual(MIN_WINDOW_SIZE);
  });
});

describe('dragging the float window to the top and left', () => {
  const FLOAT = { w: 560, h: 420 };

  // The player's report: the window could not be dragged above or left of the middle of the main window.
  for (const ratio of [1, 1.5]) {
    for (const main of [
      { x: 0, y: 0, w: 1920, h: 1040 },
      { x: 100, y: 50, w: 1920, h: 1040 },
    ]) {
      it(`reaches the top left corner (ratio ${ratio}, main at ${main.x},${main.y})`, () => {
        const startWindow = { x: main.x + 1200, y: main.y + 600 };
        const startMouse = { x: 1500, y: 800 };
        // The pointer goes to the top left corner of the screen (CSS pixels).
        const pos = dragPosition(
          startWindow,
          startMouse,
          { x: 0, y: 0 },
          ratio,
        );
        const rect = looseFit({ x: pos.x, y: pos.y, ...FLOAT }, main);
        expect(rect.x).toBeLessThanOrEqual(main.x);
        expect(rect.y).toBeLessThanOrEqual(main.y);
        expect(rect.x).toBeGreaterThan(main.x - FLOAT.w);
        // The window follows the mouse until it is nearly out of the main window.
        const toCentre = looseFit(
          { x: main.x + main.w / 2 - 1, y: main.y + main.h / 2 - 1, ...FLOAT },
          main,
        );
        expect(toCentre.x).toBe(main.x + main.w / 2 - 1);
      });
    }
  }

  it('keeps a margin of the window reachable on every side', () => {
    const main = { x: 0, y: 0, w: 1920, h: 1040 };
    const far = looseFit({ x: -5000, y: -5000, ...FLOAT }, main);
    expect(far.x + FLOAT.w).toBe(96);
    expect(far.y).toBe(0);
    const right = looseFit({ x: 9000, y: 9000, ...FLOAT }, main);
    expect(right.x).toBe(1920 - 96);
    expect(right.y).toBe(1040 - 96);
  });

  it('does not limit the drag without an area', () => {
    const win = { x: -300, y: -20, ...FLOAT };
    expect(looseFit(win, null)).toEqual(win);
  });

  it('distrusts a main window that does not hold the float window', () => {
    const start = { x: 60, y: 60, ...FLOAT };
    expect(trustedArea({ x: 960, y: 520, w: 960, h: 520 }, start)).toBeNull();
    const main = { x: 0, y: 0, w: 1920, h: 1040 };
    expect(trustedArea(main, start)).toEqual(main);
    expect(trustedArea(main, null)).toEqual(main);
    expect(trustedArea({ x: 0, y: 0, w: 0, h: 0 }, start)).toBeNull();
  });

  it('stops a resize at the area edge and at the minimum', () => {
    const area = { x: 100, y: 50, w: 1600, h: 900 };
    expect(fitSize({ x: 900, y: 900 }, { x: 1000, y: 500 }, area)).toEqual({
      x: 700,
      y: 450,
    });
    expect(fitSize({ x: 10, y: 10 }, { x: 200, y: 100 }, area)).toEqual(
      MIN_WINDOW_SIZE,
    );
    expect(fitSize({ x: 400, y: 300 }, { x: 200, y: 100 }, area)).toEqual({
      x: 400,
      y: 300,
    });
  });
});

describe('docking by dragging', () => {
  const outer = { x: 0, y: 0, w: 1936, h: 1047 };
  const client = clientRect(outer, { x: 1920, y: 1008 });
  const column = columnRect(client, { x: 480, y: 1008 });

  it('finds the client area inside the frame', () => {
    expect(client).toEqual({ x: 8, y: 31, w: 1920, h: 1008 });
  });

  it('puts the column against the right edge of the client area', () => {
    expect(column).toEqual({ x: 1448, y: 31, w: 480, h: 1008 });
  });

  it('docks by the half of the column the pointer is over', () => {
    expect(dockTarget({ x: 1700, y: 200 }, column)).toBe('top');
    expect(dockTarget({ x: 1700, y: 800 }, column)).toBe('bottom');
  });

  it('does not dock outside the column or without one', () => {
    expect(dockTarget({ x: 900, y: 200 }, column)).toBeNull();
    expect(dockTarget({ x: 1700, y: 5 }, column)).toBeNull();
    expect(dockTarget({ x: 1700, y: 200 }, null)).toBeNull();
  });

  it('pops a docked chat out after a small drag only', () => {
    expect(poppedOut({ x: 100, y: 100 }, { x: 104, y: 103 })).toBe(false);
    expect(poppedOut({ x: 100, y: 100 }, { x: 80, y: 100 })).toBe(true);
  });

  it('puts the popped window under the pointer', () => {
    expect(windowUnderPointer({ x: 1700, y: 300 }, { x: 560, y: 420 })).toEqual(
      {
        x: 1420,
        y: 284,
      },
    );
  });
});
