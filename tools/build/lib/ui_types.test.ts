// Unit tests for the declared-UI TS generator. Run with `bun test tools/build/lib/ui_types.test.ts`.
import { describe, expect, test } from 'bun:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { argType, renderUiTypes, typeName, type UiHost, writeUiTypes } from './ui_types';

const hosts: UiHost[] = [
  {
    host: '/obj/machinery/recharger',
    interfaces: ['Recharger'],
    fields: [
      { key: 'on', kind: 1, type: 'bool' },
      { key: 'charge_percent', kind: 2, type: 'num' },
    ],
    acts: {
      toggle: { action: 'toggle', args: [] },
      set_rate: { action: 'set_rate', args: [{ name: 'rate', kind: 1 }] },
      'set_attribute:size': {
        action: 'set_attribute',
        args: [
          { name: 'attribute', kind: 5, choices: ['size'] },
          { name: 'val', kind: 2 },
        ],
      },
      'set_attribute:name': {
        action: 'set_attribute',
        args: [
          { name: 'attribute', kind: 5, choices: ['name'] },
          { name: 'val', kind: 3 },
        ],
      },
    },
  },
  {
    host: '/obj/machinery/recharger/wall',
    interfaces: ['Recharger'],
    fields: [{ key: 'mounted', kind: 1, type: 'unknown' }],
    acts: { rotate: { action: 'rotate', args: [{ name: 'dir', kind: 5, choices: [1, 2] }] } },
  },
  { host: '/datum/nothing', interfaces: [], fields: [], acts: {} },
];

describe('ui_types', () => {
  test('arg kinds map to TS types', () => {
    expect(argType({ name: 'a', kind: 1 })).toBe('number');
    expect(argType({ name: 'a', kind: 3 })).toBe('string');
    expect(argType({ name: 'a', kind: 5, choices: ['x', 'y'] })).toBe("'x' | 'y'");
    expect(argType({ name: 'a', kind: 8 })).toBe('unknown[] | Record<string, unknown>');
  });

  test('interface names become identifiers', () => {
    expect(typeName('Fabrication/Lathe')).toBe('Fabrication_Lathe');
  });

  test('hosts sharing an interface merge into one file', () => {
    const out = renderUiTypes(hosts);
    expect([...out.keys()]).toEqual(['Recharger']);
    const text = out.get('Recharger') ?? '';
    expect(text).toContain('export type RechargerData = {');
    expect(text).toContain('  charge_percent?: number;');
    expect(text).toContain('  mounted?: unknown;');
    expect(text).toContain('  toggle: Record<string, never>;');
    expect(text).toContain('  set_rate: { rate?: number };');
    expect(text).toContain('  rotate: { dir?: 1 | 2 };');
    expect(text).toContain("{ attribute?: 'name'; val?: string } | { attribute?: 'size'; val?: number }");
  });

  test('writing is idempotent and prunes stale files', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ui-types-'));
    const json = path.join(dir, 'dump.json');
    fs.writeFileSync(json, JSON.stringify(hosts));
    const out = path.join(dir, 'generated');
    fs.mkdirSync(out);
    fs.writeFileSync(path.join(out, 'Gone.d.ts'), 'stale');
    expect(writeUiTypes(json, out).length).toBe(2);
    expect(fs.existsSync(path.join(out, 'Gone.d.ts'))).toBe(false);
    expect(writeUiTypes(json, out, true)).toEqual([]);
    fs.rmSync(dir, { recursive: true, force: true });
  });
});
