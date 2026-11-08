/**
 * Whether this page's chat is a guest: a floating chat window
 * (tgui/interfaces/Chat.tsx). A guest shows the server's history ring
 * (SSchat.replay) and neither loads nor saves the stored chat log, which
 * belongs to the column page; the column page's chat is never a guest.
 */
let guest = false;

export function setChatGuest(value: boolean): void {
  guest = value;
}

export function isChatGuest(): boolean {
  return guest;
}
