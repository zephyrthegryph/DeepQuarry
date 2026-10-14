import { expect, test } from 'bun:test';
import fs from 'node:fs';
import path from 'node:path';
import { validateBuildRoots } from './build_root';

test('checkout admission accepts matching roots and rejects either sibling authority', () => {
  // These directories stand for Git's already-resolved toplevel answers.
  const root = fs.mkdtempSync(path.join(process.env.DQ_NATIVE_RUN_ROOT ?? 'E:/dq-cache', 'build-root-test-'));
  const own = path.join(root, 'own');
  const sibling = path.join(root, 'sibling');
  fs.mkdirSync(own);
  fs.mkdirSync(sibling);
  try {
    expect(() => validateBuildRoots(own, own, own, '0')).not.toThrow();
    expect(() => validateBuildRoots(sibling, own, own, '0')).toThrow('sibling-worktree');
    expect(() => validateBuildRoots(own, own, sibling, '0')).toThrow('sibling-worktree');
    expect(() => validateBuildRoots(own, undefined, own, '0')).toThrow('Enter through');
    expect(() => validateBuildRoots(own, own, own, undefined)).toThrow('Enter through');
  } finally {
    fs.rmdirSync(own);
    fs.rmdirSync(sibling);
    fs.rmdirSync(root);
  }
});
