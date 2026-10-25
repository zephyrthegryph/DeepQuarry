import { expect, test } from 'bun:test';
import fs from 'node:fs';
import path from 'node:path';
import { probeToplevel, validateBuildRoots } from './build_root';

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

test('toplevel probe retries timeouts but treats a clean failure as final', () => {
  const quiet = console.error;
  console.error = () => {};
  try {
    const timeout = Object.assign(new Error('timed out'), { code: 'ETIMEDOUT' });
    let calls = 0;
    const flaky = () => (++calls < 3 ? { error: timeout, status: null, stdout: '' } : { status: 0, stdout: 'E:/x\n' });
    expect(probeToplevel('.', flaky, () => {})).toBe('E:/x');
    expect(calls).toBe(3);

    calls = 0;
    const never = () => { calls++; return { error: timeout, status: null, stdout: '' }; };
    expect(() => probeToplevel('.', never, () => {})).toThrow('overloaded');
    expect(calls).toBe(3);

    calls = 0;
    const notRepo = () => { calls++; return { status: 128, stdout: '' }; };
    expect(() => probeToplevel('.', notRepo, () => {})).toThrow('must start inside');
    expect(calls).toBe(1);
  } finally {
    console.error = quiet;
  }
});
