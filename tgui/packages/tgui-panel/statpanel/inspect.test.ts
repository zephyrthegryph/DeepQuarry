import { describe, expect, test } from 'bun:test';
import { chipText, chipTone, inspectSubtitle, portraitScale } from './inspect';

describe('inspectSubtitle', () => {
  test('joins the parts it was given, upper case', () => {
    expect(inspectSubtitle('Human', 'Site Manager', 'Adjacent')).toBe(
      'HUMAN · SITE MANAGER · ADJACENT',
    );
  });
  test('leaves out missing parts', () => {
    expect(inspectSubtitle('Object', null, '3 tiles')).toBe('OBJECT · 3 TILES');
    expect(inspectSubtitle()).toBe('');
  });
});

describe('chips', () => {
  test('text is label and state', () => {
    expect(chipText({ label: 'R ARM', state: 'MISSING', tone: 'danger' })).toBe(
      'R ARM: MISSING',
    );
  });
  test('unknown tones read as info', () => {
    expect(chipTone('danger')).toBe('danger');
    expect(chipTone('warning')).toBe('warning');
    expect(chipTone('whatever')).toBe('info');
  });
});

describe('portraitScale', () => {
  test('scales by whole multiples that fit the budget', () => {
    expect(portraitScale(32, 32)).toBe(5);
    expect(portraitScale(32, 64)).toBe(2);
    expect(portraitScale(64, 32, 200)).toBe(3);
  });
  test('never below 1 and never fractional', () => {
    expect(portraitScale(500, 500)).toBe(1);
    expect(portraitScale(0, 0)).toBe(1);
  });
});
