import { describe, expect, it } from 'bun:test';
import {
  clampShare,
  clientRect,
  columnRect,
  dockTarget,
  dragPosition,
  fitRect,
  fitSize,
  isMode,
  MIN_WINDOW_SIZE,
  mainRects,
  poppedOut,
  resizeSize,
  SHARE_DEFAULT,
  shareFromHeights,
  shareMoved,
  splitterFor,
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

describe('keeping the float window exactly inside the main window', () => {
  const FLOAT = { w: 560, h: 420 };
  const screen = { x: 0, y: 0, w: 2560, h: 1440 };
  // The live report of a maximized main window: pos and size are the restored
  // ones (the skin's 640x440 centred on the screen), outer-size is the real one.
  const maximized = {
    pos: { x: 960, y: 500 },
    outerSize: { x: 2578, y: 1458 },
    size: { x: 640, y: 440 },
    innerSize: { x: 2560, y: 1408 },
    maximized: true,
  };

  it('places a maximized main window by its outer size, not by its restored pos', () => {
    const main = mainRects(maximized, screen);
    expect(main?.outer).toEqual({ x: -9, y: -9, w: 2578, h: 1458 });
    expect(main?.visible).toEqual(screen);
    // The old code took pos 960,500 as the origin: the drag stopped at the middle.
    const stuck = fitRect(
      { x: 0, y: 0, ...FLOAT },
      { x: 960, y: 500, w: 2578, h: 1458 },
    );
    expect(stuck.x).toBe(960);
    expect(stuck.y).toBe(500);
  });

  it('reaches the top left and bottom right corners of a maximized window', () => {
    const area = mainRects(maximized, screen)?.visible ?? null;
    expect(fitRect({ x: -4000, y: -4000, ...FLOAT }, area)).toEqual({
      x: 0,
      y: 0,
      ...FLOAT,
    });
    expect(fitRect({ x: 9000, y: 9000, ...FLOAT }, area)).toEqual({
      x: 2560 - FLOAT.w,
      y: 1440 - FLOAT.h,
      ...FLOAT,
    });
  });

  it('uses the reported pos and outer size of a window that is not maximized', () => {
    const main = mainRects(
      {
        pos: { x: 100, y: 50 },
        outerSize: { x: 1936, y: 1047 },
        size: { x: 1920, y: 1008 },
        innerSize: null,
        maximized: false,
      },
      screen,
    );
    expect(main?.outer).toEqual({ x: 100, y: 50, w: 1936, h: 1047 });
    expect(main?.visible).toEqual(main?.outer);
    expect(main?.client).toEqual({ x: 108, y: 81, w: 1920, h: 1008 });
    expect(fitRect({ x: 0, y: 0, ...FLOAT }, main?.visible ?? null)).toEqual({
      x: 100,
      y: 50,
      ...FLOAT,
    });
  });

  it('knows nothing of a window without a size or a place', () => {
    const none = { pos: null, outerSize: null, size: null, innerSize: null };
    expect(mainRects({ ...none, maximized: false }, screen)).toBeNull();
    expect(
      mainRects(
        { ...none, size: { x: 640, y: 440 }, maximized: false },
        screen,
      ),
    ).toBeNull();
  });

  it('does not limit the drag without an area', () => {
    const win = { x: -300, y: -20, ...FLOAT };
    expect(fitRect(win, null)).toEqual(win);
  });

  it('cuts a window larger than the area and raises a tiny one', () => {
    const area = { x: 100, y: 50, w: 1600, h: 900 };
    expect(fitRect({ x: 0, y: 0, w: 2000, h: 1200 }, area)).toEqual(area);
    expect(fitRect({ x: 100, y: 50, w: 100, h: 100 }, area)).toEqual({
      x: 100,
      y: 50,
      ...{ w: MIN_WINDOW_SIZE.x, h: MIN_WINDOW_SIZE.y },
    });
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
