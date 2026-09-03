import { afterEach, describe, expect, mock, test } from 'bun:test';
import { configAtom, store, suspendedAtom } from './events/store';
import type { Config } from './events/types';
import {
  browserViewportMatches,
  buildNativeRevealPayload,
  hasRevealed,
  resetReveal,
  revealWindow,
} from './reveal';

const originalWinset = Byond.winset;
const originalWinget = Byond.winget;
const originalSendMessage = Byond.sendMessage;
const originalInnerWidth = window.innerWidth;
const originalInnerHeight = window.innerHeight;

afterEach(() => {
  Byond.winset = originalWinset;
  Byond.winget = originalWinget;
  Byond.sendMessage = originalSendMessage;
  Object.defineProperty(window, 'innerWidth', {
    configurable: true,
    value: originalInnerWidth,
  });
  Object.defineProperty(window, 'innerHeight', {
    configurable: true,
    value: originalInnerHeight,
  });
  store.set(suspendedAtom, Date.now());
  resetReveal();
});

describe('native window reveal', () => {
  test('formats native reveal geometry consistently', () => {
    expect(
      buildNativeRevealPayload({
        pos: [120, 240],
        size: [500, 700],
      }),
    ).toEqual({
      'is-visible': true,
      pos: '120,240',
      size: '500x700',
    });
  });

  test('canonicalizes fractional native geometry to integer pixels', () => {
    expect(
      buildNativeRevealPayload({
        pos: [902.5, 541.25],
        size: [549.6, 700.2],
      }),
    ).toEqual({
      'is-visible': true,
      pos: '903,541',
      size: '550x700',
    });
  });

  test('accepts a CSS viewport scaled from native display pixels', () => {
    expect(browserViewportMatches('400x500', 320, 400, 1.25)).toBe(true);
    expect(browserViewportMatches('550x700', 440, 560, 1.25)).toBe(true);
    expect(browserViewportMatches('310x526', 248, 422, 1.25)).toBe(true);
    expect(browserViewportMatches('550x700', 400, 500, 1.25)).toBe(false);
  });

  test('rejects stale generations before touching the native window', async () => {
    const winset = mock(() => {});
    const sendMessage = mock(() => {});
    Byond.winset = winset;
    Byond.winget = mock(async (_id, property) =>
      property === 'size' ? { x: 400, y: 600 } : { x: 0, y: 0 },
    ) as unknown as typeof Byond.winget;
    Object.defineProperty(window, 'innerWidth', {
      configurable: true,
      value: 400,
    });
    Object.defineProperty(window, 'innerHeight', {
      configurable: true,
      value: 600,
    });
    Byond.sendMessage = sendMessage;
    store.set(configAtom, {
      interface: { name: 'TestInterface' },
      window: { generation: 4, native_shell: 1 },
    } as Config);
    store.set(suspendedAtom, false);

    expect(await revealWindow(3, { size: [400, 600] })).toBe(false);
    expect(winset).not.toHaveBeenCalled();

    expect(await revealWindow(4, { size: [400, 600] })).toBe(true);
    expect(hasRevealed(4)).toBe(true);
    expect(hasRevealed(3)).toBe(false);
    expect(winset).toHaveBeenCalledTimes(3);
    expect(winset).toHaveBeenNthCalledWith(1, 'test-window', {
      alpha: 0,
      'is-visible': true,
    });
    expect(winset).toHaveBeenNthCalledWith(2, 'test-window', {
      alpha: 0,
      size: '400x600',
    });
    expect(winset).toHaveBeenNthCalledWith(3, 'test-window', {
      alpha: 255,
    });
    expect(sendMessage).toHaveBeenCalledTimes(1);
  });
});
