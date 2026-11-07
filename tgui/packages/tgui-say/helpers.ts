import type { Channel } from './ChannelIterator';
import { RADIO_PREFIXES, WindowSize } from './constants';
import { cachedMap, dockPosition, dockWindow, placedPosition } from './dock';
import { clampCssSize } from './placement';

/**
 * Once byond signals this via keystroke, it
 * ensures window size, visibility, and focus.
 */
export function windowOpen(
  channel: Channel,
  width: number,
  height: number,
  scale: boolean,
): void {
  setWindowVisibility(true, width, height, scale);
  Byond.sendMessage('open', { channel });
}

/**
 * Resets the state of the window and hides it from user view.
 * Sending "close" logs it server side.
 */
export function windowClose(
  width: number,
  height: number,
  scale: boolean,
): void {
  setWindowVisibility(false, width, height, scale);
  Byond.winset('map', {
    focus: true,
  });
  Byond.sendMessage('close');
}

/**
 * Modifies the window size.
 */
export function windowSet(
  width = WindowSize.Width,
  size = WindowSize.Small,
  scale: boolean,
): void {
  const pixelRatio = scale ? window.devicePixelRatio : 1;
  ({ w: width, h: size } = clampCssSize(width, size));

  const sizeStr = `${width * pixelRatio}x${size * pixelRatio}`;

  Byond.winset(null, {
    'tgui_say.size': sizeStr,
    'tgui_say.browser.size': sizeStr,
  });
  void dockWindow(width * pixelRatio, size * pixelRatio);
}

/** Helper function to set window size and visibility */
function setWindowVisibility(
  visible: boolean,
  width: number,
  height: number,
  scale: boolean,
): void {
  const pixelRatio = scale ? window.devicePixelRatio : 1;
  ({ w: width, h: height } = clampCssSize(width, height));

  const sizeStr = `${width * pixelRatio}x${height * pixelRatio}`;

  const props: Record<string, string | boolean> = {
    'tgui_say.is-visible': visible,
    'tgui_say.size': sizeStr,
    'tgui_say.browser.size': sizeStr,
  };
  if (visible) {
    // Where the player left it, else docked from the last measure, at once, then measured again for a map that changed.
    const placed = placedPosition();
    const map = cachedMap();
    if (placed) {
      props['tgui_say.pos'] = `${placed.x},${placed.y}`;
    } else if (map) {
      const pos = dockPosition(map, {
        w: width * pixelRatio,
        h: height * pixelRatio,
      });
      props['tgui_say.pos'] = `${pos.x},${pos.y}`;
    }
    void dockWindow(width * pixelRatio, height * pixelRatio);
  }
  Byond.winset(null, props);
}

const CHANNEL_REGEX = /^[:.]\w\s|^,b\s/;

/** Tests for a channel prefix, returning it or none */
export function getPrefix(
  value: string,
): keyof typeof RADIO_PREFIXES | undefined {
  if (!value || value.length < 3 || !CHANNEL_REGEX.test(value)) {
    return;
  }

  const adjusted = value
    .slice(0, 3)
    ?.toLowerCase()
    ?.replace('.', ':') as keyof typeof RADIO_PREFIXES;

  if (!RADIO_PREFIXES[adjusted]) {
    return;
  }

  return adjusted;
}

/** Typed first in Say or Radio, ';' speaks on the common channel. */
export const COMMON_PREFIX = ';';

/** What a change of the input text does to the channel selection. */
export type PrefixResult = {
  /** The text with the prefix removed (or untouched when nothing switched). */
  value: string;
  /** Whether a prefix was consumed. */
  switched: boolean;
  /** The radio prefix now selected (null for none). */
  prefix: keyof typeof RADIO_PREFIXES | null;
  /** The channel to select, when a prefix switches it. */
  channel?: Channel;
};

/**
 * A prefix typed at the start of the text is removed and becomes the selected
 * channel, so the message sent is the one the prefix would have produced.
 * `:x ` / `.x ` / `,b ` pick a radio prefix (sent ahead of the text in Say);
 * ';' picks the Radio channel, which the server speaks as ";" + text.
 */
export function resolvePrefix(
  raw: string,
  currentPrefix: keyof typeof RADIO_PREFIXES | null,
  channel: Channel,
): PrefixResult {
  const typed = getPrefix(raw);
  if (typed && typed !== currentPrefix) {
    return {
      value: raw.slice(typed.length),
      switched: true,
      prefix: typed,
      channel: 'Say',
    };
  }
  if (
    !typed &&
    raw.startsWith(COMMON_PREFIX) &&
    (channel === 'Say' || channel === 'Radio')
  ) {
    return {
      value: raw.slice(COMMON_PREFIX.length),
      switched: true,
      prefix: null,
      channel: 'Radio',
    };
  }
  return { value: raw, switched: false, prefix: currentPrefix };
}
