import { expect, test } from 'bun:test';
import { createHash } from 'node:crypto';
import { updateDerivedCompileConfiguration } from './derived_compile_key';

function key(defines: readonly string[], version: string | null = null, identity = 'byond'): string {
  const hash = createHash('sha256');
  hash.update('same manifest and source bytes');
  updateDerivedCompileConfiguration(hash, defines, version, identity);
  return hash.digest('hex');
}

test('ordered duplicate macro overrides produce distinct derived compile keys', () => {
  const defines = ['FEATURE=1', 'FEATURE=2'];
  expect(key(defines)).not.toBe(key(['FEATURE=2', 'FEATURE=1']));
  expect(key(defines)).not.toBe(key(['FEATURE=2']));
  expect(key(defines)).toBe(key([...defines]));
  expect(defines).toEqual(['FEATURE=1', 'FEATURE=2']);
});

test('derived compile keys retain compiler version and backend identity context', () => {
  const defines = ['CITESTING=1'];
  expect(key(defines, 'stable')).not.toBe(key(defines, 'preview'));
  expect(key(defines, 'stable', 'byond')).not.toBe(key(defines, 'stable', 'native-pinned'));
  expect(key(defines, 'stable', 'byond')).toBe(key(defines, 'stable', 'byond'));
});
