import { describe, expect, test } from 'bun:test';
import {
  chipText,
  chipTone,
  clampPanelSize,
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

describe('clampPanelSize', () => {
  test('keeps a dragged size inside the minimum and the map', () => {
    expect(clampPanelSize(50, 50, 1000, 800, 10)).toEqual([300, 200]);
    expect(clampPanelSize(5000, 5000, 1000, 800, 10)).toEqual([980, 780]);
    expect(clampPanelSize(450, 350, 1000, 800, 10)).toEqual([450, 350]);
  });
  test('a map smaller than the minimum still gives the minimum', () => {
    expect(clampPanelSize(400, 400, 200, 100, 10)).toEqual([300, 200]);
  });
});
