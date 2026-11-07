import { describe, expect, it } from 'bun:test';
import {
  chatHeightInColumn,
  clampShare,
  clientRect,
  columnRect,
  dockShare,
  dockTarget,
  dragPosition,
  fitBrowserSize,
  fitRect,
  fitSize,
  isMode,
  MIN_WINDOW_SIZE,
  mainRects,
  mapSplitFromX,
  poppedOut,
  previewBox,
  resizeRect,
  resizeSize,
  SHARE_DEFAULT,
  shareFromHeights,
  shareFromY,
  shareMoved,
  snapRect,
  splitBorderX,
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
    // The area is the client area (no title bar or menu), cut to the screen.
    expect(main?.client).toEqual({ x: 0, y: 32, w: 2560, h: 1408 });
    expect(main?.visible).toEqual({ x: 0, y: 32, w: 2560, h: 1408 });
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
      y: 32,
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
    expect(main?.visible).toEqual(main?.client);
    expect(main?.client).toEqual({ x: 108, y: 81, w: 1920, h: 1008 });
    // The title bar is not inside the game window: the top of the area is the client's top.
    expect(fitRect({ x: 0, y: 0, ...FLOAT }, main?.visible ?? null)).toEqual({
      x: 108,
      y: 81,
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

describe('corner snapping', () => {
  const area = { x: 100, y: 50, w: 1000, h: 800 };
  const win = { x: 0, y: 0, w: 300, h: 200 };

  it('snaps flush to a near edge', () => {
    expect(snapRect({ ...win, x: 110, y: 400 }, area, 16)).toEqual({
      ...win,
      x: 100,
      y: 400,
    });
    expect(snapRect({ ...win, x: 790, y: 400 }, area, 16).x).toBe(800);
  });

  it('snaps both axes in a corner', () => {
    const got = snapRect({ ...win, x: 795, y: 655 }, area, 16);
    expect(got).toEqual({ ...win, x: 800, y: 650 });
  });

  it('leaves a far window alone and never leaves the area', () => {
    const far = { ...win, x: 400, y: 300 };
    expect(snapRect(far, area, 16)).toEqual(far);
    const got = snapRect({ ...win, x: 105, y: 53 }, area, 16);
    expect(got.x).toBeGreaterThanOrEqual(area.x);
    expect(got.y).toBeGreaterThanOrEqual(area.y);
  });

  it('does nothing without an area', () => {
    expect(snapRect(win, null)).toEqual(win);
  });

  it('takes the dock share from the dropped height', () => {
    expect(dockShare(300, 1000)).toBe(30);
    expect(dockShare(50, 1000)).toBe(20);
    expect(dockShare(900, 1000)).toBe(80);
    expect(dockShare(0, 1000)).toBe(40);
  });
});

describe('snapping along the border between the map and the column', () => {
  const client = { x: 8, y: 31, w: 1920, h: 1008 };
  const border = splitBorderX(client, 1920, 70);
  const win = { x: 0, y: 200, w: 300, h: 200 };

  it('finds the border from the split control and the percent', () => {
    expect(border).toBe(8 + 1344);
  });

  it('snaps the right edge to the border from the map side', () => {
    const got = snapRect({ ...win, x: border - 300 - 10 }, client, 16, {
      x: [border],
    });
    expect(got.x).toBe(border - 300);
  });

  it('snaps the left edge to the border from the column side', () => {
    const got = snapRect({ ...win, x: border + 9 }, client, 16, {
      x: [border],
    });
    expect(got.x).toBe(border);
  });

  it('prefers the nearer of the border and the area edge', () => {
    const got = snapRect({ ...win, x: 14 }, client, 16, { x: [border] });
    expect(got.x).toBe(client.x);
  });

  it('leaves a window far from the border alone', () => {
    const far = { ...win, x: 500 };
    expect(snapRect(far, client, 16, { x: [border] })).toEqual(far);
  });

  it('turns a pointer x into the map percent and keeps it in range', () => {
    expect(mapSplitFromX(client, 1920, 8 + 960)).toBe(50);
    expect(mapSplitFromX(client, 1920, -500)).toBe(10);
    expect(mapSplitFromX(client, 1920, 5000)).toBe(90);
  });
});

describe('resizing from edges and corners', () => {
  const area = { x: 0, y: 32, w: 1000, h: 700 };
  const start = { x: 300, y: 200, w: 400, h: 300 };
  const at = { x: 0, y: 0 };

  it('moves the right and bottom edges without moving the window', () => {
    const got = resizeRect(
      start,
      { right: true, bottom: true },
      at,
      { x: 50, y: 30 },
      1,
      area,
    );
    expect(got).toEqual({ x: 300, y: 200, w: 450, h: 330 });
  });

  it('moves the window with the left and top edges', () => {
    const got = resizeRect(
      start,
      { left: true, top: true },
      at,
      { x: -40, y: -20 },
      1,
      area,
    );
    expect(got).toEqual({ x: 260, y: 180, w: 440, h: 320 });
  });

  it('keeps the opposite edge fixed at the minimum size', () => {
    const got = resizeRect(
      start,
      { left: true },
      at,
      { x: 900, y: 0 },
      1,
      area,
    );
    expect(got.x + got.w).toBe(700);
    expect(got.w).toBe(MIN_WINDOW_SIZE.x);
    const top = resizeRect(start, { top: true }, at, { x: 0, y: 900 }, 1, area);
    expect(top.y + top.h).toBe(500);
    expect(top.h).toBe(MIN_WINDOW_SIZE.y);
  });

  it('stops every edge exactly at the area', () => {
    const got = resizeRect(
      start,
      { left: true, top: true, right: false },
      at,
      { x: -5000, y: -5000 },
      1,
      area,
    );
    expect(got.x).toBe(0);
    expect(got.y).toBe(32);
    const far = resizeRect(
      start,
      { right: true, bottom: true },
      at,
      { x: 5000, y: 5000 },
      1,
      area,
    );
    expect(far.x + far.w).toBe(1000);
    expect(far.y + far.h).toBe(732);
  });

  it('scales the mouse by the pixel ratio and changes only the dragged axis', () => {
    const got = resizeRect(
      start,
      { right: true },
      at,
      { x: 10, y: 99 },
      2,
      area,
    );
    expect(got).toEqual({ ...start, w: 420 });
  });

  it('does not limit the resize without an area', () => {
    const got = resizeRect(start, { left: true }, at, { x: -100, y: 0 });
    expect(got).toEqual({ x: 200, y: 200, w: 500, h: 300 });
  });
});

describe('live split and dock preview math', () => {
  const column = { x: 1400, y: 31, w: 520, h: 1000 };

  it('takes the chat share from the pointer, from the bottom or the top', () => {
    expect(shareFromY('bottom', column, 31 + 600)).toBe(40);
    expect(shareFromY('top', column, 31 + 300)).toBe(30);
    expect(shareFromY('bottom', column, 31)).toBe(80);
    expect(shareFromY('top', column, 31 + 1000)).toBe(80);
    expect(shareFromY('bottom', column, 5000)).toBe(20);
  });

  it('boxes the preview at the dock side with the share', () => {
    expect(previewBox('top', 35)).toEqual({ top: 0, height: 35 });
    expect(previewBox('bottom', 35)).toEqual({ top: 65, height: 35 });
    expect(previewBox('bottom', 5)).toEqual({ top: 80, height: 20 });
  });
});

describe('chat browser fit', () => {
  it('reads the chat height from the column splitter', () => {
    expect(chatHeightInColumn('bottom', 1000, 60)).toBe(400);
    expect(chatHeightInColumn('top', 1000, 35)).toBe(350);
  });

  it('never gives the browser more than its host has', () => {
    expect(fitBrowserSize({ x: 640, y: 480 }, { x: 600, y: 300 })).toEqual({
      x: 600,
      y: 300,
    });
    expect(fitBrowserSize({ x: 500, y: 200 }, { x: 600, y: 300 })).toEqual({
      x: 500,
      y: 200,
    });
  });

  it('uses the report when the host cannot be measured', () => {
    expect(fitBrowserSize({ x: 640, y: 480 }, null)).toEqual({
      x: 640,
      y: 480,
    });
    expect(fitBrowserSize({ x: 640, y: 480 }, { x: 0, y: 0 })).toEqual({
      x: 640,
      y: 480,
    });
  });
});
