// A window floated out of the column (layouts/Window.tsx, window_dock.dm): it reveals under the pointer and comes to the front, and
// the update that follows (which clears float_at) neither cancels that nor moves it.
(globalThis as any).__TGUI_WINDOW_GEOMETRY_MANIFEST__ ??= {};

import { afterEach, describe, expect, it } from 'bun:test';
import { act, cleanup, render } from '@testing-library/react';

const { configAtom, store, suspendedAtom } = await import('../events/store');
const { resetReveal } = await import('../reveal');
const { Window } = await import('./Window');

const saved = {
  winset: Byond.winset,
  winget: Byond.winget,
  send: Byond.sendMessage,
};
afterEach(() => {
  cleanup();
  Byond.winset = saved.winset;
  Byond.winget = saved.winget;
  Byond.sendMessage = saved.send;
  store.set(suspendedAtom, Date.now());
  resetReveal();
});

let key = 0;
const config = (float_at: string | null, floated: boolean) =>
  ({
    interface: { name: 'Chat', layout: '' },
    title: 'Chat',
    status: 2,
    user: { name: 'Nick', observer: 0 },
    window: {
      key: `float-test-${key}`,
      size: [520, 640],
      fancy: true,
      locked: false,
      scale: false,
      prewarmed: false,
      generation: 3,
      native_shell: true,
      docked: false,
      float_at,
      floated,
      dockable: true,
    },
    client: { ckey: 'n', address: '', computer_id: '', profiling: false },
  }) as any;

async function floatOut(nextUpdateAfterMs: number) {
  // A window never placed before (a stored place would size it).
  key++;
  const sets: Record<string, unknown>[] = [];
  const sentTypes: string[] = [];
  Byond.winset = ((_id: string, props: Record<string, unknown>) =>
    sets.push(props)) as any;
  Byond.winget = (async (_id: string, p: string) =>
    p === 'size'
      ? { x: 520, y: 640 }
      : p === 'pos'
        ? { x: 294, y: 707 }
        : {}) as any;
  Byond.sendMessage = ((type: string) => sentTypes.push(type)) as any;
  store.set(suspendedAtom, false);
  store.set(configAtom, config('554,723', true));
  render(
    <Window title="Chat" width={520} height={640}>
      <Window.Content>chat</Window.Content>
    </Window>,
  );
  await act(async () => {
    await new Promise((r) => setTimeout(r, nextUpdateAfterMs));
  });
  // The server's next update: float_at and floated are cleared.
  act(() => store.set(configAtom, config(null, false)));
  await act(async () => {
    await new Promise((r) => setTimeout(r, 1200));
  });
  return { sets, sentTypes };
}

describe('a window floated out of the column', () => {
  for (const wait of [0, 50]) {
    it(`shows under the pointer and comes to the front (next update after ${wait} ms)`, async () => {
      const { sets, sentTypes } = await floatOut(wait);
      // Opaque at last, placed under the drop point (centred on its width), brought to the front, and reported shown.
      expect(sets.some((s) => s.alpha === 255)).toBe(true);
      expect(sets.some((s) => s.pos === '294,707')).toBe(true);
      expect(sets.some((s) => s.focus === true)).toBe(true);
      expect(sentTypes).toContain('visible');
    });
  }
});
