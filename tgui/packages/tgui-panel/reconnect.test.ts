// The reconnect poller keeps the server's address (reconnect.tsx): an answer that is not an address leaves it as it was and never
// throws out of the poll's timer, where it once surfaced as the failure of whatever test ran at that moment.
import { describe, expect, it } from 'bun:test';

const { noteServerUrl, serverUrl } = await import('./reconnect');

describe('the reconnect address poll', () => {
  it('keeps a real address and ignores anything else', () => {
    noteServerUrl('byond://127.0.0.1:1337');
    expect(serverUrl()).toBe('byond://127.0.0.1:1337');
    for (const junk of [{}, null, undefined, 42, '', 'byond://10.0.0.1:0']) {
      expect(() => noteServerUrl(junk)).not.toThrow();
    }
    expect(serverUrl()).toBe('byond://127.0.0.1:1337');
  });
});
