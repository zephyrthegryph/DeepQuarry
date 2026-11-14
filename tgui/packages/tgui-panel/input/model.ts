/**
 * The chat input row state and its messages to the server: the one place a
 * player types speech (the say popup is gone). The server end is the chat
 * panel (code/library/ui/tgui_panel/speech.dm): `open`/`close` bracket the
 * typing, `typing`/`thinking` drive the bubble over the head and `entry` speaks.
 */

export const INPUT_CHANNELS = [
  'Say',
  'Radio',
  'Me',
  'Whis',
  'Subtle',
  'OOC',
  'LOOC',
] as const;

export type InputChannel = (typeof INPUT_CHANNELS)[number];

/** Channels that show no typing bubble. */
const QUIET_CHANNELS: readonly InputChannel[] = ['OOC', 'LOOC'];

/** The server MAX_MESSAGE_LEN. */
export const MAX_LENGTH = 4096;

/** `typing` goes out at most once per 4 seconds. */
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

/** A ';' typed first in Say or Radio speaks on the common channel: the text after it. */
export function parseCommonPrefix(
  value: string,
  channel: InputChannel,
): string | null {
  if ((channel === 'Say' || channel === 'Radio') && value.startsWith(';')) {
    return value.slice(1);
  }
  return null;
}

/** The radio colour (tgui/styles/radio-colors.scss) of a department prefix key; Common and unknown keys are common. */
export const RADIO_KEY_COLOR: Readonly<Record<string, string>> = {
  ':c': 'command',
  ':e': 'engineering',
  ':m': 'medical',
  ':n': 'science',
  ':s': 'security',
  ':u': 'supply',
  ':v': 'service',
  ':p': 'ai',
  ':x': 'syndicate',
  ':t': 'syndicate',
  ':k': 'centcom',
  ':y': 'exploration',
};

export function radioColorName(key: string): string {
  return RADIO_KEY_COLOR[key] ?? 'common';
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

/** Sent messages, newest first, bounded; one list for every channel. */
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
  available: readonly InputChannel[] = INPUT_CHANNELS,
): InputChannel {
  // Only what the server says the speaker can use now, in the row's order.
  const usable = INPUT_CHANNELS.filter((c) => available.includes(c));
  if (!usable.length) return channel;
  const at = usable.indexOf(channel);
  if (at < 0) return usable[direction === 1 ? 0 : usable.length - 1];
  return usable[(at + direction + usable.length) % usable.length];
}

/** The server's channel list, kept to the ones the row knows; OOC when none is left. */
export function parseAvailableChannels(value: unknown): InputChannel[] {
  const rows = Array.isArray(value) ? value : [];
  const known = INPUT_CHANNELS.filter((c) => rows.includes(c));
  return known.length ? known : ['OOC'];
}

/** What the row shows and whether the player picked it: the pair `settleChannel` works on. */
export type ChannelState = { channel: InputChannel; chosen: boolean };

/**
 * The row's state after the server's channel list changed. Until the player picks a channel themselves the row follows the server: Say
 * whenever it is usable (the round started, the player spawned), else the lobby's OOC. It does not depend on which lists came before, so
 * a repeated list, a list that arrives with the first message, or a row mounted after the spawn all end on Say. A pick stands until Say
 * goes away again (back to the lobby, a new round), and is then dropped if its channel is gone.
 */
export function settleChannel(
  state: ChannelState,
  available: readonly InputChannel[],
): ChannelState {
  const canSay = available.includes('Say');
  if (!canSay) {
    // The lobby: the next time Say appears the row follows the server again.
    const channel = available.includes(state.channel)
      ? state.channel
      : (available[0] ?? 'OOC');
    return { channel, chosen: false };
  }
  if (!state.chosen) {
    return { channel: 'Say', chosen: false };
  }
  return {
    channel: available.includes(state.channel) ? state.channel : 'Say',
    chosen: true,
  };
}

export function isChannel(value: unknown): value is InputChannel {
  return INPUT_CHANNELS.includes(value as InputChannel);
}

export function isQuiet(channel: InputChannel): boolean {
  return QUIET_CHANNELS.includes(channel);
}

/** The text the server will speak, as the preview parses it: a radio key ahead of the text in Radio. */
export function previewEntry(
  channel: InputChannel,
  radio: RadioOption,
  value: string,
): string {
  if (channel === 'Radio') {
    return `${radio.key || ';'} ${value}`;
  }
  return value;
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

  step(direction: 1 | -1, available?: readonly InputChannel[]): void {
    this.setChannel(nextChannel(this.channel, direction, available));
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
    // A department prefix goes out in Say, ahead of the text (the server reads it as a radio key).
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
