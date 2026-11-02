import { describe, expect, it } from 'bun:test';

import {
  type LanguageInfo,
  type LanguageRules,
  parseLanguages,
} from './parseLanguages';
import { activeAt, toggleLanguage, toggleMarker } from './shortcuts';

const language = (): LanguageInfo => ({
  verbs: ['says', 'asks', 'exclaims'],
  whisperVerb: '',
  spoken: true,
  whole: false,
  innate: false,
  noHiss: false,
});

const rules: LanguageRules = {
  prefixes: [',', '#', '-'],
  mode: 'Default',
  name: 'Tester',
  defaultLanguage: 'gal',
  gibberish: 'gib',
  noise: 'noise',
  keys: { g: 'gal', s: 'sol', k: 'siik' },
  languages: { gal: language(), sol: language(), siik: language() },
  order: ['gal', 'sol', 'siik'],
  markers: { '|': 'i', '+': 'b', _: 'u' },
  radioKeys: [':s'],
  autopunctuation: false,
  customVerbs: { say: '', ask: '', exclaim: '', whisper: '' },
  hiss: null,
};

const pieces = (value: string) =>
  parseLanguages(value, rules).pieces.map((piece) => [
    piece.language,
    piece.text,
  ]);

describe('toggleMarker', () => {
  it('wraps and unwraps a selection', () => {
    const on = toggleMarker('a word b', 2, 6, '+');
    expect(on).toEqual({ value: 'a +word+ b', start: 3, end: 7 });
    expect(toggleMarker(on.value, on.start, on.end, '+')).toEqual({
      value: 'a word b',
      start: 2,
      end: 6,
    });
    expect(toggleMarker('a +word+ b', 2, 8, '+').value).toBe('a word b');
  });
  it('opens a pair at the cursor, steps out, and drops an empty one', () => {
    const open = toggleMarker('hi ', 3, 3, '|');
    expect(open).toEqual({ value: 'hi ||', start: 4, end: 4 });
    expect(toggleMarker(open.value, 4, 4, '|').value).toBe('hi ');
    expect(toggleMarker('hi |x|', 5, 5, '|')).toEqual({
      value: 'hi |x|',
      start: 6,
      end: 6,
    });
  });
});

describe('toggleLanguage at the cursor', () => {
  it('switches from the cursor on, and back to preferred', () => {
    const on = toggleLanguage('Hello', 5, 5, 3, rules);
    expect(on?.value).toBe('Hello ,k ');
    const text = `${on?.value}friend`;
    expect(pieces(text)).toEqual([
      ['gal', 'Hello'],
      ['siik', 'friend'],
    ]);
    const back = toggleLanguage(text, text.length, text.length, 3, rules);
    expect(back?.value).toBe('Hello ,k friend ,g ');
  });
  it('never stacks switches with no text between', () => {
    const on = toggleLanguage('', 0, 0, 2, rules);
    expect(on?.value).toBe(',s ');
    const other = toggleLanguage(',s ', 3, 3, 3, rules);
    expect(other?.value).toBe(',k ');
    const off = toggleLanguage(',s ', 3, 3, 2, rules);
    expect(off?.value).toBe('');
  });
  it('starts after a radio key', () => {
    expect(toggleLanguage(':s hi', 3, 3, 2, rules)?.value).toBe(':s ,s hi');
  });
  it('ignores a number with no language', () => {
    expect(toggleLanguage('hi', 2, 2, 9, rules)).toBeNull();
  });
});

describe('toggleLanguage on a selection', () => {
  it('covers exactly the selection and restores what follows', () => {
    const edit = toggleLanguage('one two three', 4, 7, 3, rules);
    expect(edit?.value).toBe('one ,k two ,g three');
    expect(pieces(edit?.value ?? '')).toEqual([
      ['gal', 'one'],
      ['siik', 'two'],
      ['gal', 'three'],
    ]);
    expect(edit?.value.slice(edit.start, edit.end)).toBe('two');
    const undone = toggleLanguage(
      edit?.value ?? '',
      edit?.start ?? 0,
      edit?.end ?? 0,
      3,
      rules,
    );
    expect(undone?.value).toBe('one two three');
  });
  it('has nothing to close at the end of the message', () => {
    expect(toggleLanguage('one two', 4, 7, 3, rules)?.value).toBe('one ,k two');
  });
});

describe('single language mode', () => {
  const single = { ...rules, mode: 'Single Language' };
  it('switches the whole message and back', () => {
    const on = toggleLanguage('hi', 2, 2, 2, single);
    expect(on?.value).toBe(',s hi');
    expect(on?.start).toBe(5);
    expect(toggleLanguage(',s hi', 5, 5, 2, single)?.value).toBe('hi');
  });
});

describe('activeAt', () => {
  it('names what the cursor is in', () => {
    expect(activeAt('hello', 5, rules)).toBeNull();
    expect(activeAt('a ,k b', 6, rules)).toBe('siik');
    expect(activeAt('a ,k +b', 7, rules)).toBe('siik b');
    expect(activeAt('a ,k b ,g c', 11, rules)).toBeNull();
    expect(activeAt('|x', 2, null)).toBe('i');
  });
});
