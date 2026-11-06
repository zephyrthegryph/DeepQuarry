import { describe, expect, it } from 'bun:test';
import { ChatInputModel, keyAction, TYPING_THROTTLE_MS } from './model';

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
