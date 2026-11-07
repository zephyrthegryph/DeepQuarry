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

export type KeyAction =
  | 'send'
  | 'escape'
  | 'next'
  | 'prev'
  | 'older'
  | 'newer'
  | null;

/** A department prefix the speaker's radios offer, from the server (key ':m', label 'Medical'). */
export type RadioOption = { key: string; label: string };

/** The common channel: no prefix (the server adds the ';'). */
export const COMMON_OPTION: RadioOption = { key: '', label: 'Common' };

/** How many sent messages the arrow keys recall. */
export const HISTORY_LIMIT = 20;

const PREFIX_REGEX = /^[:.](\S)\s/;

/**
 * A `:x ` (or `.x `) typed at the start of the text, when x is one of the
 * speaker's radio keys: the option it names and the text after it.
 */
export function parseRadioPrefix(
  value: string,
  options: readonly RadioOption[],
): { option: RadioOption; rest: string } | null {
  const match = PREFIX_REGEX.exec(value);
  if (!match) {
    return null;
  }
  const key = `:${match[1].toLowerCase()}`;
  const option = options.find((candidate) => candidate.key === key);
  if (!option) {
    return null;
  }
  return { option, rest: value.slice(3) };
}

/** The option after this one in the list headed by Common, wrapping; backwards with -1. */
export function nextRadioOption(
  current: RadioOption,
  options: readonly RadioOption[],
  direction: 1 | -1 = 1,
): RadioOption {
  const all = [COMMON_OPTION, ...options];
  const at = Math.max(
    0,
    all.findIndex((option) => option.key === current.key),
  );
  return all[(at + direction + all.length) % all.length];
}

/** Sent messages, newest first, bounded; one list for every channel like the say popup. */
export class InputHistory {
  private messages: string[] = [];
  private index = -1;
  private draft = '';

  constructor(private readonly limit: number = HISTORY_LIMIT) {}

  get size(): number {
    return this.messages.length;
  }

  add(message: string): void {
    this.index = -1;
    this.draft = '';
    if (!message || this.messages[0] === message) {
      return;
    }
    this.messages.unshift(message);
    if (this.messages.length > this.limit) {
      this.messages.pop();
    }
  }

  /** Up: the next older message, keeping what was typed for the way back. Null when there is none. */
  older(current: string): string | null {
    if (this.index >= this.messages.length - 1) {
      return null;
    }
    if (this.index === -1) {
      this.draft = current;
    }
    this.index++;
    return this.messages[this.index];
  }

  /** Down: the next newer message, then the draft. Null when already at the draft. */
  newer(): string | null {
    if (this.index === -1) {
      return null;
    }
    this.index--;
    return this.index === -1 ? this.draft : this.messages[this.index];
  }

  /** Typing over a recalled message makes it the draft again. */
  reset(): void {
    this.index = -1;
    this.draft = '';
  }
}

/** The channel a click on the toggle (or Tab) switches to: the next one, wrapping; backwards with shift. */
export function nextChannel(
  channel: InputChannel,
  direction: 1 | -1 = 1,
): InputChannel {
  const count = INPUT_CHANNELS.length;
  const at = INPUT_CHANNELS.indexOf(channel);
  return INPUT_CHANNELS[(at + direction + count) % count];
}

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
    case 'ArrowUp':
    case 'PageUp':
      return 'older';
    case 'ArrowDown':
    case 'PageDown':
      return 'newer';
    default:
      return null;
  }
}

export class ChatInputModel {
  channel: InputChannel = 'Say';
  value = '';
  /** The radio prefix used while the channel is Radio (Common is none). */
  radio: RadioOption = COMMON_OPTION;
  readonly history = new InputHistory();
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

  setRadio(option: RadioOption): void {
    this.radio = option;
  }

  /** The prefixes the speaker has changed: a chosen one that is gone falls back to Common. */
  syncRadio(options: readonly RadioOption[]): void {
    if (this.radio.key && !options.some((o) => o.key === this.radio.key)) {
      this.radio = COMMON_OPTION;
    }
  }

  /** Up or down in the sent messages. Returns the text to show, or null when there is nowhere to go. */
  recall(direction: 'older' | 'newer'): string | null {
    const text =
      direction === 'older'
        ? this.history.older(this.value)
        : this.history.newer();
    if (text !== null) {
      this.value = text;
    }
    return text;
  }

  step(direction: 1 | -1): void {
    this.setChannel(nextChannel(this.channel, direction));
  }

  /** The text changed: tell the server the player is typing, at most every few seconds. */
  type(value: string): void {
    this.value = value;
    this.history.reset();
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
    // A department prefix goes out the way the say popup sends it: in Say, ahead of the text.
    if (this.channel === 'Radio' && this.radio.key) {
      this.send('entry', {
        channel: 'Say',
        entry: `${this.radio.key} ${entry}`,
      });
    } else {
      this.send('entry', { channel: this.channel, entry });
    }
    this.history.add(entry);
    this.value = '';
    this.lastTypingAt = Number.NEGATIVE_INFINITY;
    this.close();
    return true;
  }
}
