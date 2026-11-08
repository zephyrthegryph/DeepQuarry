// The chunk prefetch: the server ranks the most opened interfaces' chunks first (`priority`); those are fetched first, the rest after them,
// two at a time at low network priority.
import { afterEach, describe, expect, it } from 'bun:test';
// webpack defines the public path global; the module assigns it.
(globalThis as any).__webpack_public_path__ = '';
const { warmChunkPublicPath } = await import('./chunkPublicPath');

const realFetch = globalThis.fetch;
const realTimeout = window.setTimeout;
const realIdle = (window as any).requestIdleCallback;

afterEach(() => {
  globalThis.fetch = realFetch;
  window.setTimeout = realTimeout;
  (window as any).requestIdleCallback = realIdle;
});

describe('chunk prefetch', () => {
  it('fetches the ranked chunks first and the rest at low priority', async () => {
    const calls: { url: string; low: boolean }[] = [];
    const resolvers: (() => void)[] = [];
    globalThis.fetch = ((url: string, init?: any) => {
      calls.push({ url, low: init?.priority === 'low' });
      return new Promise((resolve) => {
        resolvers.push(() =>
          resolve({ ok: true, arrayBuffer: async () => new ArrayBuffer(0) } as any),
        );
      });
    }) as any;
    window.setTimeout = ((fn: () => void) => {
      fn();
      return 0;
    }) as any;
    (window as any).requestIdleCallback = (fn: () => void) => fn();
    const files = Array.from({ length: 10 }, (_, i) => `f${i}.chunk.js`);
    warmChunkPublicPath({ url: 'http://x/', files, priority: 2 });
    // The two ranked ones go out first; the low queue waits until they are all requested.
    expect(calls.slice(0, 2).map((c) => c.url)).toEqual([
      'http://x/f0.chunk.js',
      'http://x/f1.chunk.js',
    ]);
    expect(calls.slice(0, 2).every((c) => !c.low)).toBe(true);
    // Nothing low starts while two requests are already in flight.
    expect(calls.length).toBe(2);
    while (resolvers.length) {
      resolvers.shift()?.();
      await new Promise((r) => realTimeout(r, 0));
    }
    expect(calls.length).toBe(10);
    expect(calls.slice(2).every((c) => c.low)).toBe(true);
  });
});
