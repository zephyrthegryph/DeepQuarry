import { describe, expect, it } from 'bun:test';

import table from '../../../code/tests/unit_tests/data/language_parse_cases.json';
import {
  applyHiss,
  buildPreview,
  emphasize,
  type LanguageInfo,
  type LanguageRules,
  parseLanguages,
} from './parseLanguages';

const language = (extra: Partial<LanguageInfo> = {}): LanguageInfo => ({
  verbs: ['says', 'asks', 'exclaims'],
  whisperVerb: '',
  spoken: true,
  whole: false,
  innate: false,
  noHiss: false,
  ...extra,
});

/** The same setup as inline_language_setup() on the DM side. */
const rules: LanguageRules = {
  prefixes: [',', '#', '-'],
  mode: 'Default',
  name: 'Tester',
  defaultLanguage: 'default',
  gibberish: 'gibberish',
  noise: 'n',
  keys: { s: 's', k: 'k', '5': 'k', q: 'q', n: 'n', h: 'h' },
  languages: {
    default: language(),
    s: language(),
    k: language(),
    q: language({ spoken: false }),
    n: language({ innate: true }),
    h: language({ whole: true }),
    gibberish: language(),
  },
  order: ['default', 's', 'k'],
  markers: { '|': 'i', '+': 'b', _: 'u' },
  radioKeys: [':s', ':w', '.s'],
  autopunctuation: false,
  customVerbs: { say: '', ask: '', exclaim: '', whisper: '' },
  hiss: null,
};

describe('parseLanguages, the table shared with the server', () => {
  for (const testCase of table.cases as any[]) {
    it(testCase.name, () => {
      const parsed = parseLanguages(testCase.message, rules);
      if (testCase.whole) {
        expect(parsed.whole).toBe(true);
        expect(parsed.pieces).toEqual([
          { language: testCase.whole, text: testCase.text },
        ]);
      } else {
        expect(parsed.whole).toBe(false);
        expect(
          parsed.pieces.map((piece) => [piece.language, piece.text]),
        ).toEqual(testCase.pieces);
      }
    });
  }
});

describe('modes', () => {
  it('single language reads only the message start', () => {
    const parsed = parseLanguages(',s a ,k b', {
      ...rules,
      mode: 'Single Language',
    });
    expect(parsed.pieces).toEqual([{ language: 's', text: 'a ,k b' }]);
  });
  it('space mode needs a space after the key', () => {
    const spaced = { ...rules, mode: 'Space' };
    expect(parseLanguages(',s a', spaced).pieces[0].language).toBe('s');
    expect(parseLanguages(',sa', spaced).pieces[0].language).toBe('default');
  });
  it('double delimiter needs a second prefix', () => {
    const doubled = { ...rules, mode: 'Double Delimiter' };
    expect(parseLanguages(',s,a', doubled).pieces).toEqual([
      { language: 's', text: 'a' },
    ]);
  });
});

describe('applyHiss', () => {
  const hissing = {
    ...rules,
    hiss: {
      basic: { s: ['ss', 'sss'] },
      extra: null,
      exempt: ['k'],
    },
  };
  it('hisses by language, keeping case', () => {
    expect(applyHiss('so Sass', 's', hissing)).toBe('sso Ssassss');
    expect(applyHiss('so', 'k', hissing)).toBe('so');
  });
  it('honours the no-hiss flag', () => {
    const quiet = {
      ...hissing,
      languages: { ...rules.languages, s: language({ noHiss: true }) },
    };
    expect(applyHiss('so', 's', quiet)).toBe('so');
  });
});

describe('emphasize', () => {
  it('uses the markers it is given', () => {
    expect(emphasize(['a +b+ c'], rules)[0]).toEqual([
      { text: 'a ', tags: [] },
      { text: 'b', tags: ['b'] },
      { text: ' c', tags: [] },
    ]);
  });
  it('lets a span cross pieces as chat does', () => {
    const segments = emphasize(['+a', 'b+'], rules);
    expect(segments[0]).toEqual([{ text: 'a', tags: ['b'] }]);
    expect(segments[1]).toEqual([{ text: 'b', tags: ['b'] }]);
  });
  it('leaves an unmatched marker as text', () => {
    expect(emphasize(['a + b'], rules)[0]).toEqual([
      { text: 'a + b', tags: [] },
    ]);
  });
});

describe('buildPreview', () => {
  it('stays hidden for a plain message', () => {
    expect(buildPreview('Hello, friend 3,5', 'Say', rules)).toBeNull();
    expect(buildPreview('', 'Say', rules)).toBeNull();
  });
  it('stays hidden off speech channels', () => {
    expect(buildPreview(',s Hello ,k friend', 'OOC', rules)).toBeNull();
    expect(buildPreview(',s Hello ,k friend', 'Me', rules)).toBeNull();
  });
  it('shows each piece with its language', () => {
    const preview = buildPreview(',s hello ,k friend!', 'Say', rules);
    expect(preview?.verb).toBe('exclaims');
    expect(preview?.pieces.map((piece) => piece.language)).toEqual(['s', 'k']);
    expect(preview?.pieces[0].segments[0].text).toBe('Hello');
  });
  it('reads past a radio key without taking it for a language', () => {
    const preview = buildPreview(':s hello ,k friend', 'Say', rules);
    expect(preview?.pieces.map((piece) => piece.language)).toEqual([
      'default',
      'k',
    ]);
  });
  it('shows formatting, whispers and whole-message languages', () => {
    expect(
      buildPreview('+hi+', 'Say', rules)?.pieces[0].segments[0].tags,
    ).toEqual(['b']);
    expect(buildPreview(',s hi', 'Whis', rules)?.verb).toBe('says quietly');
    expect(buildPreview('hello ,h there', 'Say', rules)?.whole).toBe(true);
  });
});
