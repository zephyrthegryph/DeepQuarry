import { describe, expect, it } from 'bun:test';
import {
  clientRect,
  columnRect,
  fitBrowserSize,
  intersect,
  MAP_SPLIT_MAX,
  MAP_SPLIT_MIN,
  mainRects,
  mapSplitFromX,
} from './model';

const screen = { x: 0, y: 0, w: 2560, h: 1440 };

describe('the main window and the column on the screen', () => {
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
    expect(main?.client).toEqual({ x: 0, y: 32, w: 2560, h: 1408 });
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
    expect(main?.client).toEqual({ x: 108, y: 81, w: 1920, h: 1008 });
  });

  it('knows nothing of a window without a size or a place', () => {
    const none = { pos: null, outerSize: null, size: null, innerSize: null };
    expect(mainRects({ ...none, maximized: false }, screen)).toBeNull();
  });

  it('finds the client area inside the frame and the column against its right edge', () => {
    const client = clientRect(
      { x: 0, y: 0, w: 2016, h: 1047 },
      { x: 2000, y: 1000 },
    );
    expect(client).toEqual({ x: 8, y: 39, w: 2000, h: 1000 });
    expect(columnRect(client, { x: 600, y: 1000 })).toEqual({
      x: 1408,
      y: 39,
      w: 600,
      h: 1000,
    });
    expect(intersect(client, { x: 0, y: 0, w: 100, h: 100 })).toEqual({
      x: 8,
      y: 39,
      w: 92,
      h: 61,
    });
  });

  it('turns a pointer x into the map percent and keeps it in range', () => {
    const client = { x: 0, y: 0, w: 2000, h: 1000 };
    expect(mapSplitFromX(client, 2000, 1400)).toBe(70);
    expect(mapSplitFromX(client, 2000, 0)).toBe(MAP_SPLIT_MIN);
    expect(mapSplitFromX(client, 2000, 2000)).toBe(MAP_SPLIT_MAX);
  });

  it('never gives the page browser more than its pane has', () => {
    expect(fitBrowserSize({ x: 700, y: 1400 }, { x: 600, y: 1000 })).toEqual({
      x: 600,
      y: 1000,
    });
    expect(fitBrowserSize({ x: 500, y: 900 }, null)).toEqual({
      x: 500,
      y: 900,
    });
  });
});
