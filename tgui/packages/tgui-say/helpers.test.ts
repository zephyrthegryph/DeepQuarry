import { describe, expect, it } from 'bun:test';

import { getPrefix, resolvePrefix } from './helpers';

describe('getPrefix', () => {
  it('reads :x and .x with a trailing space, and ,b', () => {
    expect(getPrefix(':e hello')).toBe(':e ');
    expect(getPrefix('.S hello')).toBe(':s ');
    expect(getPrefix(',b hi')).toBe(',b ');
  });

  it('ignores unknown keys and a missing space', () => {
    expect(getPrefix(':q hello')).toBeUndefined();
    expect(getPrefix(':e')).toBeUndefined();
    expect(getPrefix('hello')).toBeUndefined();
  });
});

describe('resolvePrefix', () => {
  it('strips a radio prefix and selects it in Say', () => {
    expect(resolvePrefix(':m help', null, 'Me')).toEqual({
      value: 'help',
      switched: true,
      prefix: ':m ',
      channel: 'Say',
    });
  });

  it('keeps the text when the prefix is already selected', () => {
    expect(resolvePrefix(':m again', ':m ', 'Say')).toEqual({
      value: ':m again',
      switched: false,
      prefix: ':m ',
    });
  });

  it('strips ; and selects the Radio channel from Say or Radio', () => {
    for (const channel of ['Say', 'Radio'] as const) {
      expect(resolvePrefix(';over here', null, channel)).toEqual({
        value: 'over here',
        switched: true,
        prefix: null,
        channel: 'Radio',
      });
    }
  });

  it('leaves ; alone in channels where it is just text', () => {
    expect(resolvePrefix(';hi', null, 'Me').switched).toBe(false);
    expect(resolvePrefix(';hi', null, 'OOC').value).toBe(';hi');
  });

  it('leaves plain text alone', () => {
    expect(resolvePrefix('hello', null, 'Say')).toEqual({
      value: 'hello',
      switched: false,
      prefix: null,
    });
  });
});
