import { describe, expect, it } from 'bun:test';
import { makeLimiter } from './helper_components';

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
