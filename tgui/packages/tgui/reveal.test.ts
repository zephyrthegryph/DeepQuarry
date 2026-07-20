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
  test('combines geometry and visibility into one native transaction', () => {
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

  test('rejects stale generations before touching the native window', () => {
    const winset = mock(() => {});
    const sendMessage = mock(() => {});
    Byond.winset = winset;
    Byond.sendMessage = sendMessage;
    store.set(configAtom, {
      interface: { name: 'TestInterface' },
      window: { generation: 4 },
    } as Config);
    store.set(suspendedAtom, false);

    expect(revealWindow(3, { size: [400, 600] })).toBe(false);
    expect(winset).not.toHaveBeenCalled();

    expect(revealWindow(4, { size: [400, 600] })).toBe(true);
    expect(winset).toHaveBeenCalledTimes(1);
    expect(winset).toHaveBeenCalledWith('test-window', {
      'is-visible': true,
      size: '400x600',
    });
    expect(sendMessage).toHaveBeenCalledTimes(1);
  });
});
