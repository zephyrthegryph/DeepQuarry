import { fitChatBrowser } from './geometry';

/**
 * The server seated the column page's pane, or reports where it is
 * (chat/layout): the page sizes its browser to the pane, again once it
 * settles.
 */
export function chatLayout(_payload: unknown) {
  fitChatBrowser('layout');
  setTimeout(() => fitChatBrowser('layout-settled'), 600);
}
