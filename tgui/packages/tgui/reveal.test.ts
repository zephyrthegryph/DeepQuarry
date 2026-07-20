import { afterEach, describe, expect, mock, test } from 'bun:test';
import { configAtom, store, suspendedAtom } from './events/store';
import type { Config } from './events/types';
import { buildNativeRevealPayload, revealWindow } from './reveal';

const originalWinset = Byond.winset;
const originalSendMessage = Byond.sendMessage;

afterEach(() => {
  Byond.winset = originalWinset;
  Byond.sendMessage = originalSendMessage;
  store.set(suspendedAtom, Date.now());
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

  test('rejects stale generations before touching the native window', async () => {
    const winset = mock(() => {});
    const sendMessage = mock(() => {});
    Byond.winset = winset;
    Byond.sendMessage = sendMessage;
    store.set(configAtom, {
      interface: { name: 'TestInterface' },
      window: { generation: 4, native_shell: 1 },
    } as Config);
    store.set(suspendedAtom, false);

    expect(await revealWindow(3, { size: [400, 600] })).toBe(false);
    expect(winset).not.toHaveBeenCalled();

    expect(await revealWindow(4, { size: [400, 600] })).toBe(true);
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
