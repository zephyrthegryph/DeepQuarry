import { expect, test } from 'bun:test';
import { currentDreamMakerConfiguration, type PreparedDreamMaker } from './byond';
import { currentNativeTargetConfiguration } from './compiler_selection';
import type { NativePairOutput } from './native_pair';

test('configuration authority rejects caller objects even with plausible pinned fields', () => {
  const prepared: PreparedDreamMaker = { executable: 'E:/fixture/dm.exe',
    identity: { status: 'observed', executable: 'E:/fixture/dm.exe', sha256: '1'.repeat(64) },
    version: 516, build: 1687, defines: [], namedDmVersion: null };
  expect(() => currentDreamMakerConfiguration(prepared, [])).toThrow('not issued');
  expect(() => currentNativeTargetConfiguration({ kind: 'native_pair' } as NativePairOutput)).toThrow('current compiler-issued');
});
