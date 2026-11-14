// The chat's scroll across a pop out or pop in (scrollState.ts), and the renderer moving into a new element (renderer.tsx mount()).
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

const state = await import('./scrollState');
const { chatRenderer } = await import('./renderer');

describe('chat scroll state', () => {
  it('keeps the position and whether the chat was pinned, in memory and in storage', async () => {
    expect(await state.recallChatScroll()).toBeNull();
    state.rememberChatScroll({ top: 120.4, tracking: false });
    expect(await state.recallChatScroll()).toEqual({
      top: 120,
      tracking: false,
    });
    await new Promise((resolve) => setTimeout(resolve, 250));
    expect(stored.get('chat-scroll')).toEqual({ top: 120, tracking: false });
    // A fresh page (a floating window) has no memory: it reads the client's storage.
    state.forgetChatScroll();
    expect(await state.recallChatScroll()).toEqual({
      top: 120,
      tracking: false,
    });
  });

  it('moves the messages into a new chat element instead of nesting the old one', () => {
    const first = document.createElement('div');
    first.className = 'Chat';
    chatRenderer.mount(first);
    const message = document.createElement('div');
    first.appendChild(message);
    // The chat is popped out and back in: React makes a new .Chat element.
    const second = document.createElement('div');
    second.className = 'Chat';
    chatRenderer.mount(second);
    expect(chatRenderer.rootNode).toBe(second);
    expect(second.contains(message)).toBe(true);
    expect(second.querySelector('.Chat')).toBeNull();
    expect(first.childNodes.length).toBe(0);
    // Mounting the same element again changes nothing.
    chatRenderer.mount(second);
    expect(second.contains(message)).toBe(true);
  });
});
