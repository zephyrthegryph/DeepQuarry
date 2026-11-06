import { describe, expect, test } from 'bun:test';
import {
  chipText,
  chipTone,
  inspectSubtitle,
  panelWidth,
  placeTopRight,
} from './InspectPanelLogic';

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

describe('placement', () => {
  test('sits in the top right corner', () => {
    expect(placeTopRight(400, 1100, 10)).toEqual([690, 10]);
  });
  test('a panel as wide as the map hugs the left edge', () => {
    expect(placeTopRight(500, 500, 10)).toEqual([0, 10]);
  });
  test('width is capped by the map', () => {
    expect(panelWidth(400, 1.5, 1100)).toBe(600);
    expect(panelWidth(400, 1.5, 300)).toBe(300);
  });
});
