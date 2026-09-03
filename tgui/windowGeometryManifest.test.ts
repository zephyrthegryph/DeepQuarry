import { describe, expect, test } from 'bun:test';
import path from 'node:path';
import { buildWindowGeometryManifest } from './windowGeometryManifest';

describe('window geometry manifest', () => {
  const manifest = buildWindowGeometryManifest(
    path.resolve(import.meta.dirname, 'packages', 'tgui', 'interfaces'),
  );

  test('covers the complete routed interface catalog', () => {
    expect(Object.keys(manifest).length).toBeGreaterThan(400);
    expect(manifest.RpgDice).toEqual({
      width: 900,
      height: 450,
      exact: true,
    });
  });

  test('extracts static dimensions and safely represents dynamic dimensions', () => {
    expect(manifest.APC).toEqual({ width: 450, height: 475, exact: true });
    expect(manifest.AirAlarm).toEqual({
      width: 440,
      height: 650,
      exact: true,
    });
    expect(manifest.Radio).toEqual({
      width: 310,
      height: 600,
      exact: false,
    });
  });
});
