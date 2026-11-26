import { describe, expect, it } from 'bun:test';
import { markSeen, seenCount } from './handlers';

describe('chat duplicate check', () => {
  it('holds a bounded window of sequence numbers, not every message of the session', () => {
    for (let i = 0; i < 20000; i++) markSeen(i);
    expect(seenCount()).toBe(4096);
  });
});
