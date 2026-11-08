// Where the stored chat log stands in the server's history (log.ts): a chat window asks for exactly what follows the log, and a page
// whose chat is behind the stored log (the column page after the chat floated a while) loads the log again first.
import { describe, expect, it, mock } from 'bun:test';

const stored = new Map<string, unknown>();
mock.module('common/storage', () => ({
  storage: {
    get: async (key: string) => stored.get(key) ?? null,
    set: async (key: string, value: unknown) => {
      stored.set(key, value);
    },
  },
}));

const log = await import('./log');
const { chatMessage, lastShownSequence } = await import('./handlers');

const line = (sequence: number) =>
  JSON.stringify({
    sequence,
    content: { type: 'info', html: `line ${sequence}` },
  });

describe('the stored chat log and the server history', () => {
  it('saves the last line with the log, and asks only for what follows it', async () => {
    log.setChatSession('conn-1');
    let loads = 0;
    log.registerLogLoader(async () => {
      loads++;
    });
    expect(log.claimLogLoad()).toBe(true);
    expect(log.claimLogLoad()).toBe(false);
    log.logLoadedNow();
    const base = (lastShownSequence() ?? -1) + 1;
    for (const n of [0, 1, 2]) chatMessage(line(base + n));
    log.saveLogMark();
    await Promise.resolve();
    expect(stored.get('chat-mark')).toEqual({
      session: 'conn-1',
      sequence: base + 2,
    });
    // This page showed everything the log holds: it asks for what follows its own last line, and loads nothing.
    let cleared = 0;
    expect(await log.chatResumeAfter(() => cleared++)).toBe(base + 2);
    expect(loads).toBe(0);
    // Another window (the floating chat) saved a log that runs further: this page loads it again, then asks after its end.
    stored.set('chat-mark', { session: 'conn-1', sequence: base + 40 });
    expect(await log.chatResumeAfter(() => cleared++)).toBe(base + 40);
    expect(cleared).toBe(1);
    expect(loads).toBe(1);
    expect(lastShownSequence()).toBe(base + 40);
    // A mark from another connection says nothing about this one's history.
    stored.set('chat-mark', { session: 'conn-0', sequence: base + 900 });
    expect(await log.chatResumeAfter(() => cleared++)).toBe(base + 40);
    expect(loads).toBe(1);
  });
});
