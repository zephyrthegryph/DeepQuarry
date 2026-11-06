/**
 * The chat input row state and its messages to the server. The server end is
 * the say modal (`/datum/tgui_say` receives what the panel forwards, see
 * code/library/ui/tgui_panel/tgui_panel.dm), so the messages are the popup ones:
 * `open`/`close` bracket the typing, `typing`/`thinking` drive the bubble over
 * the head and `entry` speaks.
 */

export const INPUT_CHANNELS = ['Say', 'Radio', 'Me', 'OOC', 'LOOC'] as const;

export type InputChannel = (typeof INPUT_CHANNELS)[number];

/** Channels that show no typing bubble (the popup "quiet" list). */
const QUIET_CHANNELS: readonly InputChannel[] = ['OOC', 'LOOC'];

/** The server MAX_MESSAGE_LEN. */
export const MAX_LENGTH = 4096;

/** The popup throttles `typing` to one message per 4 seconds. */
export const TYPING_THROTTLE_MS = 4000;

export type Send = (type: string, payload: Record<string, unknown>) => void;

export type KeyAction = 'send' | 'escape' | 'next' | 'prev' | null;

export function isChannel(value: unknown): value is InputChannel {
  return INPUT_CHANNELS.includes(value as InputChannel);
}

export function isQuiet(channel: InputChannel): boolean {
  return QUIET_CHANNELS.includes(channel);
}

/** What a key press in the text field means. */
export function keyAction(key: string, shiftKey: boolean): KeyAction {
  switch (key) {
    case 'Enter':
      return shiftKey ? null : 'send';
    case 'Escape':
      return 'escape';
    case 'Tab':
      return shiftKey ? 'prev' : 'next';
    default:
      return null;
  }
}

export class ChatInputModel {
  channel: InputChannel = 'Say';
  value = '';
  /** Whether the server has been told the player is typing (the popup being open). */
  isOpen = false;
  private lastTypingAt = Number.NEGATIVE_INFINITY;

  constructor(
    private readonly send: Send,
    private readonly now: () => number = Date.now,
  ) {}

  /** The field was focused, by hotkey or click: the server starts "thinking". */
  open(channel: InputChannel = this.channel): void {
    this.channel = channel;
    if (this.isOpen) {
      return;
    }
    this.isOpen = true;
    this.send('open', { channel });
  }

  /** Focus left the field: the server drops the bubble. */
  close(): void {
    if (!this.isOpen) {
      return;
    }
    this.isOpen = false;
    this.send('close', {});
  }

  setChannel(channel: InputChannel): void {
    this.channel = channel;
    if (this.isOpen) {
      this.send('thinking', { visible: !isQuiet(channel), channel });
    }
  }

  step(direction: 1 | -1): void {
    const count = INPUT_CHANNELS.length;
    const at = INPUT_CHANNELS.indexOf(this.channel);
    this.setChannel(INPUT_CHANNELS[(at + direction + count) % count]);
  }

  /** The text changed: tell the server the player is typing, at most every few seconds. */
  type(value: string): void {
    this.value = value;
    if (!this.isOpen) {
      this.open();
    }
    if (isQuiet(this.channel) || !value) {
      return;
    }
    const now = this.now();
    if (now - this.lastTypingAt >= TYPING_THROTTLE_MS) {
      this.lastTypingAt = now;
      this.send('typing', { channel: this.channel });
    }
  }

  /** Speaks the text. Returns whether anything was sent. */
  submit(): boolean {
    const entry = this.value;
    if (!entry.length) {
      return false;
    }
    if (entry.length > MAX_LENGTH) {
      this.send('lenwarn', { length: entry.length, maxlength: MAX_LENGTH });
      return false;
    }
    this.send('entry', { channel: this.channel, entry });
    this.value = '';
    this.lastTypingAt = Number.NEGATIVE_INFINITY;
    this.close();
    return true;
  }
}
