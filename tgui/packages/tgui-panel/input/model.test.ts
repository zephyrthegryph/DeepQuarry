import { describe, expect, it } from 'bun:test';
import {
  ChatInputModel,
  COMMON_OPTION,
  HISTORY_LIMIT,
  INPUT_CHANNELS,
  type InputChannel,
  InputHistory,
  keyAction,
  nextChannel,
  nextRadioOption,
  parseRadioPrefix,
  type RadioOption,
  TYPING_THROTTLE_MS,
} from './model';

function setup() {
  const sent: [string, any][] = [];
  let clock = 0;
  const model = new ChatInputModel(
    (type, payload) => sent.push([type, payload]),
    () => clock,
  );
  return {
    sent,
    model,
    advance: (ms: number) => {
      clock += ms;
    },
  };
}

describe('chat input row', () => {
  it('maps keys', () => {
    expect(keyAction('Enter', false)).toBe('send');
    expect(keyAction('Enter', true)).toBeNull();
    expect(keyAction('Escape', false)).toBe('escape');
    expect(keyAction('Tab', false)).toBe('next');
    expect(keyAction('Tab', true)).toBe('prev');
    expect(keyAction('a', false)).toBeNull();
  });

  it('cycles channels and tells the server only while open', () => {
    const { model, sent } = setup();
    model.step(1);
    expect(model.channel).toBe('Radio');
    expect(sent).toEqual([]);
    model.open();
    model.step(1);
    expect(model.channel).toBe('Me');
    model.step(-1);
    model.step(-1);
    expect(model.channel).toBe('Say');
    model.step(-1);
    expect(model.channel).toBe('LOOC');
    expect(sent.at(-1)).toEqual([
      'thinking',
      { visible: false, channel: 'LOOC' },
    ]);
  });

  it('sends the entry in the chosen channel and closes', () => {
    const { model, sent } = setup();
    model.setChannel('Me');
    model.open();
    model.type('waves');
    expect(model.submit()).toBe(true);
    expect(sent).toEqual([
      ['open', { channel: 'Me' }],
      ['typing', { channel: 'Me' }],
      ['entry', { channel: 'Me', entry: 'waves' }],
      ['close', {}],
    ]);
    expect(model.value).toBe('');
    expect(model.isOpen).toBe(false);
  });

  it('sends nothing for an empty entry', () => {
    const { model, sent } = setup();
    expect(model.submit()).toBe(false);
    expect(sent).toEqual([]);
  });

  it('warns instead of sending an overlong entry', () => {
    const { model, sent } = setup();
    model.type('x'.repeat(5000));
    expect(model.submit()).toBe(false);
    expect(sent.at(-1)).toEqual(['lenwarn', { length: 5000, maxlength: 4096 }]);
  });

  it('throttles typing like the popup and stays quiet in OOC', () => {
    const { model, sent, advance } = setup();
    model.type('h');
    model.type('hi');
    advance(TYPING_THROTTLE_MS);
    model.type('hi!');
    expect(sent.filter(([t]) => t === 'typing').length).toBe(2);
    model.setChannel('OOC');
    advance(TYPING_THROTTLE_MS);
    model.type('hi!!');
    expect(sent.filter(([t]) => t === 'typing').length).toBe(2);
  });

  it('closes on escape or blur once', () => {
    const { model, sent } = setup();
    model.open();
    model.close();
    model.close();
    expect(sent).toEqual([
      ['open', { channel: 'Say' }],
      ['close', {}],
    ]);
  });
});

describe('channel toggle', () => {
  it('cycles forward through every channel and wraps', () => {
    let channel: InputChannel = INPUT_CHANNELS[0];
    const seen: InputChannel[] = [channel];
    for (let i = 1; i < INPUT_CHANNELS.length; i++) {
      channel = nextChannel(channel);
      seen.push(channel);
    }
    expect(seen).toEqual([...INPUT_CHANNELS]);
    expect(nextChannel(channel)).toBe(INPUT_CHANNELS[0]);
  });

  it('goes back with a negative direction and wraps', () => {
    expect(nextChannel('Say', -1)).toBe('LOOC');
    expect(nextChannel('Radio', -1)).toBe('Say');
  });

  it('starts at Say and steps the same way a click does', () => {
    const { model } = setup();
    expect(model.channel).toBe('Say');
    model.step(1);
    expect(model.channel).toBe(nextChannel('Say'));
  });
});

const MED: RadioOption = { key: ':m', label: 'Medical' };
const SEC: RadioOption = { key: ':s', label: 'Security' };

describe('chat input history', () => {
  it('maps the arrow keys', () => {
    expect(keyAction('ArrowUp', false)).toBe('older');
    expect(keyAction('ArrowDown', false)).toBe('newer');
    expect(keyAction('PageUp', false)).toBe('older');
  });

  it('recalls older then newer and restores the draft', () => {
    const history = new InputHistory();
    history.add('one');
    history.add('two');
    expect(history.older('draft')).toBe('two');
    expect(history.older('two')).toBe('one');
    expect(history.older('one')).toBeNull();
    expect(history.newer()).toBe('two');
    expect(history.newer()).toBe('draft');
    expect(history.newer()).toBeNull();
  });

  it('is bounded and skips empties and immediate repeats', () => {
    const history = new InputHistory();
    history.add('');
    history.add('a');
    history.add('a');
    expect(history.size).toBe(1);
    for (let i = 0; i < HISTORY_LIMIT + 5; i++) {
      history.add(`m${i}`);
    }
    expect(history.size).toBe(HISTORY_LIMIT);
    expect(history.older('')).toBe(`m${HISTORY_LIMIT + 4}`);
  });

  it('the model records sent messages and recalls them', () => {
    const { model } = setup();
    model.open();
    model.type('hello');
    model.submit();
    model.type('typing');
    expect(model.recall('older')).toBe('hello');
    expect(model.value).toBe('hello');
    expect(model.recall('newer')).toBe('typing');
    expect(model.recall('newer')).toBeNull();
  });

  it('typing over a recalled message starts a new draft', () => {
    const { model } = setup();
    model.open();
    model.type('a');
    model.submit();
    model.recall('older');
    model.type('ab');
    expect(model.recall('newer')).toBeNull();
    expect(model.recall('older')).toBe('a');
  });
});

describe('chat input radio prefix', () => {
  const options = [MED, SEC];

  it('parses a typed prefix for a channel the speaker has', () => {
    expect(parseRadioPrefix(':m hello', options)).toEqual({
      option: MED,
      rest: 'hello',
    });
    expect(parseRadioPrefix('.S go', options)?.option).toBe(SEC);
  });

  it('ignores unknown keys and prefixes not followed by a space', () => {
    expect(parseRadioPrefix(':q hi', options)).toBeNull();
    expect(parseRadioPrefix(':m', options)).toBeNull();
    expect(parseRadioPrefix(':mx hi', options)).toBeNull();
    expect(parseRadioPrefix('hi :m there', options)).toBeNull();
    expect(parseRadioPrefix(':m hi', [])).toBeNull();
  });

  it('cycles common and the options, wrapping', () => {
    expect(nextRadioOption(COMMON_OPTION, options)).toBe(MED);
    expect(nextRadioOption(MED, options)).toBe(SEC);
    expect(nextRadioOption(SEC, options)).toBe(COMMON_OPTION);
    expect(nextRadioOption(COMMON_OPTION, options, -1)).toBe(SEC);
  });

  it('sends a department message in Say with its prefix', () => {
    const { model, sent } = setup();
    model.setChannel('Radio');
    model.setRadio(MED);
    model.open();
    model.type('need a doctor');
    model.submit();
    expect(sent.at(-2)).toEqual([
      'entry',
      { channel: 'Say', entry: ':m need a doctor' },
    ]);
  });

  it('sends common radio as Radio and falls back when the channel is gone', () => {
    const { model, sent } = setup();
    model.setChannel('Radio');
    model.open();
    model.type('hi');
    model.submit();
    expect(sent.at(-2)).toEqual(['entry', { channel: 'Radio', entry: 'hi' }]);
    model.setRadio(MED);
    model.syncRadio([SEC]);
    expect(model.radio).toBe(COMMON_OPTION);
    model.setRadio(SEC);
    model.syncRadio([SEC]);
    expect(model.radio).toBe(SEC);
  });
});
