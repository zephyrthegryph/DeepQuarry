import { describe, expect, test } from 'bun:test';
import { canFallback, compilerMode, integrationArguments } from './policy';

describe('DM compiler integration policy', () => {
  test('keeps BYOND default and rejects unknown selectors', () => {
    expect(compilerMode(undefined)).toBe('byond');
    expect(compilerMode('native')).toBe('native');
    expect(compilerMode('shadow')).toBe('shadow');
    expect(() => compilerMode('unknown')).toThrow();
  });
  test('source and comparison failures cannot be hidden by fallback', () => {
    expect(canFallback('internal', false)).toBe(true);
    expect(canFallback('internal', true)).toBe(false);
    for (const kind of ['source', 'configuration', 'comparison'] as const) {
      expect(canFallback(kind, false)).toBe(false);
    }
  });
  test('passes defines and paths as separate arguments without shell interpolation', () => {
    expect(integrationArguments('a b.dme', 'native', 'dm.exe', 'builtins.bin', ['VALUE=a=b', 'TEST'], 'localhost:1339'))
      .toEqual(['integrated-build', 'a b.dme', '--mode', 'native', '--byond', 'dm.exe', '--builtins', 'builtins.bin', '--daemon', 'localhost:1339', '-DVALUE=a=b', '-DTEST']);
  });
});
