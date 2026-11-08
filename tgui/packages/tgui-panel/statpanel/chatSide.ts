/**
 * Tells the page which side of it the chat is on (`html[data-chat-side]`), so
 * the panel leaves out its own frame edge there: the chat's frame is the one
 * line between them, the same 3px gap as every other edge, not two frames.
 */
export async function markChatSide(): Promise<void> {
  try {
    const got = await Byond.winget('rpane.rpanewindow', 'left');
    const side = got === 'outputwindow' ? 'top' : 'bottom';
    if (document.documentElement.dataset.chatSide !== side) {
      document.documentElement.dataset.chatSide = side;
      console.log('statpanel: chat side', side);
    }
  } catch {
    // An older client: both frames stay.
  }
}

/** Marks the side now and whenever the panel is resized (the chat moving resizes it). */
export function watchChatSide(): void {
  markChatSide();
  window.addEventListener('resize', () => markChatSide());
}
