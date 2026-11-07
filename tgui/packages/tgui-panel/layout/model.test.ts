import { describe, expect, it } from 'bun:test';
import {
  clampShare,
  dragPosition,
  fitRect,
  fitSize,
  isMode,
  MIN_WINDOW_SIZE,
  pinRequest,
  pointerSnap,
  resizeSize,
  SHARE_DEFAULT,
  shareFromHeights,
  shareMoved,
  snapTarget,
  splitterFor,
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

  it('swaps the side and floats or re-pins', () => {
    expect(pinRequest('bottom', 'side')).toBe('top');
    expect(pinRequest('top', 'side')).toBe('bottom');
    expect(pinRequest('bottom', 'float')).toBe('float');
    expect(pinRequest('top', 'float')).toBe('float');
    expect(pinRequest('float', 'float')).toBe('bottom');
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

describe('snap to the right edge', () => {
  const area = { x: 0, y: 0, w: 1600, h: 900 };

  it('pins top right when the window ends near the right edge in the upper half', () => {
    expect(snapTarget({ x: 1050, y: 40, w: 560, h: 300 }, area)).toBe('top');
  });

  it('pins bottom right in the lower half', () => {
    expect(snapTarget({ x: 1050, y: 500, w: 560, h: 380 }, area)).toBe(
      'bottom',
    );
  });

  it('snaps at the threshold, not past it', () => {
    expect(snapTarget({ x: 1000, y: 40, w: 600, h: 300 }, area, 72)).toBe(
      'top',
    );
    expect(snapTarget({ x: 1000, y: 40, w: 528, h: 300 }, area, 72)).toBe(
      'top',
    );
    expect(snapTarget({ x: 1000, y: 40, w: 527, h: 300 }, area, 72)).toBeNull();
  });

  it('does not snap in the middle of the screen or outside the area', () => {
    expect(snapTarget({ x: 300, y: 40, w: 560, h: 300 }, area)).toBeNull();
    expect(snapTarget({ x: 1050, y: -900, w: 560, h: 300 }, area)).toBeNull();
    expect(
      snapTarget(
        { x: 1050, y: 40, w: 560, h: 300 },
        { x: 0, y: 0, w: 0, h: 0 },
      ),
    ).toBeNull();
  });

  it('splits the halves at the vertical middle of the area', () => {
    expect(snapTarget({ x: 1050, y: 300, w: 560, h: 300 }, area)).toBe(
      'bottom',
    );
    expect(snapTarget({ x: 1050, y: 290, w: 560, h: 300 }, area)).toBe('top');
  });
});

describe('keeping the window inside the main window', () => {
  const area = { x: 100, y: 50, w: 1600, h: 900 };

  it('leaves a window that fits alone', () => {
    const win = { x: 300, y: 200, w: 560, h: 420 };
    expect(fitRect(win, area)).toEqual(win);
  });

  it('pulls a window back from every side', () => {
    expect(fitRect({ x: 0, y: 0, w: 500, h: 400 }, area)).toEqual({
      x: 100,
      y: 50,
      w: 500,
      h: 400,
    });
    expect(fitRect({ x: 1500, y: 800, w: 500, h: 400 }, area)).toEqual({
      x: 1200,
      y: 550,
      w: 500,
      h: 400,
    });
  });

  it('cuts a window larger than the area to the area', () => {
    expect(fitRect({ x: 0, y: 0, w: 2000, h: 1200 }, area)).toEqual(area);
  });

  it('changes nothing without an area', () => {
    const win = { x: -50, y: 9000, w: 500, h: 400 };
    expect(fitRect(win, { x: 0, y: 0, w: 0, h: 0 })).toEqual(win);
  });

  it('stops a resize at the area edge and at the minimum', () => {
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

describe('pin by pointer', () => {
  const area = { x: 0, y: 0, w: 1600, h: 900 };

  it('pins in the right strip by the vertical half', () => {
    expect(pointerSnap({ x: 1550, y: 100 }, area)).toBe('top');
    expect(pointerSnap({ x: 1550, y: 700 }, area)).toBe('bottom');
  });

  it('does not pin elsewhere', () => {
    expect(pointerSnap({ x: 800, y: 100 }, area)).toBeNull();
    expect(pointerSnap({ x: 1550, y: -5 }, area)).toBeNull();
    expect(
      pointerSnap({ x: 1550, y: 100 }, { x: 0, y: 0, w: 0, h: 0 }),
    ).toBeNull();
  });
});
