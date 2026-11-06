import { describe, expect, it } from 'bun:test';
import { layerPlacements, makeLimiter } from './helper_components';

describe('makeLimiter', () => {
  it('never runs more than the limit at once and runs everything', async () => {
    const limit = makeLimiter(2);
    let running = 0;
    let peak = 0;
    const results = await Promise.all(
      [1, 2, 3, 4, 5].map((n) =>
        limit(async () => {
          running++;
          peak = Math.max(peak, running);
          await new Promise((r) => setTimeout(r, 1));
          running--;
          return n;
        }),
      ),
    );
    expect(peak).toBe(2);
    expect(results).toEqual([1, 2, 3, 4, 5]);
  });
  it('keeps going after a task fails', async () => {
    const limit = makeLimiter(1);
    await limit(() => Promise.reject(new Error('x'))).catch(() => {});
    expect(await limit(async () => 7)).toBe(7);
  });
});

describe('layerPlacements', () => {
  const body = { width: 32, height: 32 };
  it('draws the body at the same scale beside a 32px or a 64px part', () => {
    const with32 = layerPlacements(64, [body, { width: 32, height: 32 }]);
    const with64 = layerPlacements(64, [body, { width: 64, height: 64 }]);
    expect(with64[0]).toEqual(with32[0]);
    expect(with32[0]).toEqual({ x: 0, y: 0, w: 64, h: 64 });
    // The 64px wing overhangs at the same scale, centred and standing on the bottom.
    expect(with64[1]).toEqual({ x: -32, y: -64, w: 128, h: 128 });
  });
  it('keeps the body scale beside a 64x32 taur sheet', () => {
    const p = layerPlacements(64, [body, { width: 64, height: 32 }]);
    expect(p[0]).toEqual({ x: 0, y: 0, w: 64, h: 64 });
    expect(p[1]).toEqual({ x: -32, y: 0, w: 128, h: 64 });
  });
  it('fills the square with a lone sprite of any size and skips failed loads', () => {
    expect(layerPlacements(64, [{ width: 64, height: 64 }])[0]).toEqual({
      x: 0,
      y: 0,
      w: 64,
      h: 64,
    });
    expect(layerPlacements(64, [null, body])).toEqual([
      null,
      { x: 0, y: 0, w: 64, h: 64 },
    ]);
  });
});
