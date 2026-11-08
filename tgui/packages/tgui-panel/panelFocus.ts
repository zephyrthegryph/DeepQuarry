/**
 * Basically, hacks from goonchat which try to keep the map focused at all
 * times, except for when some meaningful action happens o
 *
 * @file
 * @copyright 2020 Aleksej Komarov
 * @license MIT
 */

import { focusMap } from 'tgui/focus';
import { canStealFocus, globalEvents } from 'tgui-core/events';
import { vecLength, vecSubtract } from 'tgui-core/vector';

// Empyrically determined number for the smallest possible
// text you can select with the mouse.
const MIN_SELECTION_DISTANCE = 10;

/** The chat input row keeps focus while the player types in it. */
function isChatInputFocused(): boolean {
  return !!document.activeElement?.hasAttribute('data-chat-input');
}

/**
 * A text field has the keyboard: the chat input, the stat panel's search, or
 * an input in a docked interface (the column holds them all, section 12).
 * Keys go to it; anything else hands them back to the map.
 */
function isTyping(): boolean {
  const active = document.activeElement as HTMLElement | null;
  if (!active) return false;
  return (
    active.tagName === 'INPUT' ||
    active.tagName === 'TEXTAREA' ||
    active.isContentEditable
  );
}

function deferredFocusMap(): void {
  setTimeout(focusMap);
}

export function setupPanelFocusHacks(): void {
  let focusStolen: boolean = false;
  let clickStartPos: number[] | null = null;

  window.addEventListener('focusin', (e) => {
    focusStolen = canStealFocus(e.target as HTMLElement);
  });

  window.addEventListener('mousedown', (e) => {
    clickStartPos = [e.screenX, e.screenY];
  });

  window.addEventListener('mouseup', (e) => {
    if (clickStartPos) {
      const clickEndPos = [e.screenX, e.screenY];
      const dist = vecLength(vecSubtract(clickEndPos, clickStartPos));
      if (dist >= MIN_SELECTION_DISTANCE) {
        focusStolen = true;
      }
      if (document.activeElement?.className.includes('Button')) {
        focusStolen = true;
      }
    }
    if (!focusStolen && !isChatInputFocused() && !isTyping()) {
      deferredFocusMap();
    }
  });

  globalEvents.on('keydown', (key) => {
    if (key.isModifierKey() || isChatInputFocused() || isTyping()) {
      return;
    }
    deferredFocusMap();
  });
}
