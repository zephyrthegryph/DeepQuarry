import { test, expect } from 'bun:test';
import fs from 'node:fs';
import path from 'node:path';
import { stageRuntimeLibrary } from './runtime_library';

function fixture(body: (source: string, slot: string) => void) {
  const base = 'E:/dq-cache/dmb-native-v2/runtime-library-fixtures';
  fs.mkdirSync(base, { recursive: true });
  const root = fs.mkdtempSync(path.join(base, 'case-'));
  const source = path.join(root, 'verdigris.dll');
  const slot = path.join(root, 'slot');
  fs.mkdirSync(slot);
  fs.writeFileSync(source, 'authenticated current worktree library');
  try { body(source, slot); }
  finally { fs.rmSync(root, { recursive: true }); }
}
test('isolated hosted library has exact bytes and is removed independently of pair outputs', () => fixture((source, slot) => {
  const dmb = path.join(slot, 'deepquarry.dmb');
  fs.writeFileSync(dmb, 'pair');
  const staged = stageRuntimeLibrary(source, slot);
  expect(fs.readFileSync(staged.identity.hosted)).toEqual(fs.readFileSync(source));
  expect(staged.identity.sha256).toHaveLength(64);
  staged.remove();
  expect(fs.existsSync(staged.identity.hosted)).toBe(false);
  expect(fs.readFileSync(dmb, 'utf8')).toBe('pair');
}));
test('existing slot leaf is never overwritten', () => fixture((source, slot) => {
  const destination = path.join(slot, 'verdigris.dll');
  fs.writeFileSync(destination, 'foreign');
  expect(() => stageRuntimeLibrary(source, slot)).toThrow();
  expect(fs.readFileSync(destination, 'utf8')).toBe('foreign');
}));
test('changed hosted library is preserved on cleanup failure', () => fixture((source, slot) => {
  const staged = stageRuntimeLibrary(source, slot);
  fs.writeFileSync(staged.identity.hosted, 'changed');
  expect(() => staged.remove()).toThrow('changed');
  expect(fs.readFileSync(staged.identity.hosted, 'utf8')).toBe('changed');
}));
