// The chat as a tgui interface (tgui/interfaces/Chat.tsx, code/content/client/chat_ui.dm) in a native window of its own, floated out of
// the column: its window's messages feed the chat, it asks the server for what it has not shown, and it keeps its draft on the server.
import './requireContext.testing';
import { afterAll, beforeAll, describe, expect, it } from 'bun:test';
import { act, cleanup, render, waitFor } from '@testing-library/react';

const { Chat, chatBusMessage } = await import('tgui/interfaces/Chat');
const { lastShownSequence } = await import('../chat/handlers');
const { isChatGuest } = await import('../chat/guest');
const { store } = await import('../events/store');
const { chatDraftAtom } = await import('../input/atoms');

const byond = (globalThis as any).Byond;
const saved = { sendMessage: byond.sendMessage, subscribe: byond.subscribe };
const sent: { type: string; payload: any }[] = [];
const listeners: ((type: string, payload: any) => void)[] = [];

beforeAll(() => {
  byond.sendMessage = (type: string, payload: unknown) =>
    sent.push({ type, payload });
  byond.subscribe = (listener: (type: string, payload: any) => void) =>
    listeners.push(listener);
});
afterAll(() => {
  cleanup();
  // The page's draft is module state: leave none for the next file.
  store.set(chatDraftAtom, '');
  byond.sendMessage = saved.sendMessage;
  byond.subscribe = saved.subscribe;
});

/** A server message to the chat's own window. */
const deliver = (type: string, payload: unknown) =>
  act(() => {
    for (const listener of listeners) listener(type, payload);
  });

const chatLine = (sequence: number, text: string) =>
  JSON.stringify({ sequence, content: { type: 'info', html: text } });

describe('a floating chat window', () => {
  it("passes only the chat's messages to the chat, and its config as the panel's update", () => {
    expect(chatBusMessage('chat/message', 'x')).toEqual({
      type: 'chat/message',
      payload: 'x',
    });
    expect(chatBusMessage('chat/config', { a: 1 })).toEqual({
      type: 'update',
      payload: { a: 1 },
    });
    // The window's own tgui traffic is not the chat's.
    expect(chatBusMessage('update', {})).toBeNull();
    expect(chatBusMessage('ping', {})).toBeNull();
  });

  it('asks for the history, shows what its window is sent, and keeps its draft on the server', async () => {
    // It asks for everything after the last message this page showed (none in a fresh window).
    const after = lastShownSequence() ?? -1;
    render(<Chat />);
    // A floating chat is a guest: the server's history, not the column page's stored log.
    expect(isChatGuest()).toBe(true);
    expect(sent).toContainEqual({ type: 'chat/ready', payload: { after } });
    deliver('chat/message', chatLine(after + 41, 'the replayed history'));
    deliver('chat/message', chatLine(after + 42, 'a new line'));
    expect(lastShownSequence()).toBe(after + 42);
    // A resent copy is shown once.
    deliver('chat/message', chatLine(after + 42, 'a new line'));
    expect(lastShownSequence()).toBe(after + 42);
    // The draft goes to the server once typing pauses.
    act(() => store.set(chatDraftAtom, 'half a sen'));
    act(() => store.set(chatDraftAtom, 'half a sentence'));
    await waitFor(
      () =>
        expect(sent.filter((m) => m.type === 'chat/draft')).toEqual([
          { type: 'chat/draft', payload: { draft: 'half a sentence' } },
        ]),
      { timeout: 2000 },
    );
  });
});

describe('moving the chat: docked, floating, docked again', () => {
  it("the column page catches up from the server's history with no gap, no copy and no resend", async () => {
    const { chatMessage } = await import('../chat/handlers');
    // The server's ring (chat_history.dm): every message the client was sent, by sequence; since(after) is what replay() sends.
    const ring: number[] = [];
    const since = (after: number) => ring.filter((s) => s > after);
    const base = lastShownSequence() ?? -1;
    const send = (seq: number) => {
      ring.push(seq);
      return chatLine(seq, `line ${seq}`);
    };
    sent.length = 0;
    // Docked: the column page shows three lines.
    for (const n of [1, 2, 3]) chatMessage(send(base + n));
    const left = lastShownSequence()!;
    expect(left).toBe(base + 3);
    // Floating: two more lines go to the floating window, not to the page.
    send(base + 4);
    send(base + 5);
    // Docked again: the page asks for what follows the last line it showed, and the server replays exactly those.
    const replay = since(left);
    expect(replay).toEqual([base + 4, base + 5]);
    for (const seq of replay) chatMessage(chatLine(seq, `line ${seq}`));
    expect(lastShownSequence()).toBe(base + 5);
    // A replay that overlaps what the page already showed adds nothing, and nothing was missing, so nothing is asked again.
    for (const seq of since(base)) chatMessage(chatLine(seq, `line ${seq}`));
    expect(lastShownSequence()).toBe(base + 5);
    expect(sent.filter((m) => m.type === 'chat/resend')).toEqual([]);
  });
});
