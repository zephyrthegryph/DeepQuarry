import { describe, expect, it } from 'bun:test';
import {
  flavorPreviewText,
  shownText,
  splitSpoilers,
  storedText,
} from './TextSwitcher';

describe('verb defaults', () => {
  it('shows the default for an unset verb and the verb when set', () => {
    expect(shownText('', 'says')).toBe('says');
    expect(shownText('hisses', 'says')).toBe('hisses');
  });
  it('stores the default, or nothing typed, as unset', () => {
    expect(storedText('says', 'says')).toBe('');
    expect(storedText('  ', 'says')).toBe('');
    expect(storedText('hisses', 'says')).toBe('hisses');
  });
  it('keeps text as typed where there is no default', () => {
    expect(storedText('  a note ')).toBe('  a note ');
    expect(storedText('')).toBe('');
  });
});

describe('flavorPreviewText', () => {
  it('joins filled entries in order and strips the examine markers', () => {
    expect(
      flavorPreviewText(['general', 'face', 'body'], {
        body: 'Tall',
        general: 'A ||person',
        face: '',
      }),
    ).toBe('A person\n\nTall');
  });
});

describe('splitSpoilers', () => {
  it('marks every second part as a spoiler, like examine', () => {
    expect(splitSpoilers('a ||secret|| b')).toEqual([
      ['a ', false],
      ['secret', true],
      [' b', false],
    ]);
    expect(splitSpoilers('plain')).toEqual([['plain', false]]);
  });
});
