import { describe, expect, it } from 'bun:test';
import { createMainPage, createPage, unreadAfterBatch } from './model';

function pages() {
  const main = createMainPage();
  const radio = createPage({ name: 'Radio' });
  radio.acceptedTypes = { radio: true };
  return { main, radio, byId: { [main.id]: main, [radio.id]: radio } };
}

describe('unread counts', () => {
  it('a message the viewed tab showed is not unread on another tab', () => {
    const { main, radio, byId } = pages();
    const added = unreadAfterBatch(
      [main.id, radio.id],
      byId,
      main.id,
      true,
      { radio: 2 },
      false,
    );
    expect(added).toEqual({});
  });

  it('a message the viewed tab does not show counts where it shows', () => {
    const { main, radio, byId } = pages();
    const added = unreadAfterBatch(
      [main.id, radio.id],
      byId,
      radio.id,
      true,
      { localchat: 3, radio: 1 },
      false,
    );
    expect(added).toEqual({ [main.id]: 3 });
  });

  it('the viewed tab counts its own messages only while scrolled up', () => {
    const { main, radio, byId } = pages();
    expect(
      unreadAfterBatch([main.id, radio.id], byId, main.id, false, { localchat: 2 }, false),
    ).toEqual({ [main.id]: 2 });
  });
});
