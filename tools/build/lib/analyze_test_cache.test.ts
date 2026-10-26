import { describe, expect, test } from 'bun:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { runAnalyzeTests, type TestCommand } from './analyze_test_cache';

function fixtureRoot(): string {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'analyze-tests-'));
  fs.mkdirSync(path.join(root, 'tools/analyze/target/dev/incremental/session'), { recursive: true });
  return root;
}

describe('analyze test cargo runs', () => {
  test('a rustc panic clears the incremental cache and retries once, non-incrementally', async () => {
    const root = fixtureRoot();
    const calls: { env: NodeJS.ProcessEnv }[] = [];
    const run: TestCommand = async (_command, _args, options) => {
      calls.push({ env: options.env });
      return calls.length === 1 ? { code: 101, stdout: '', stderr: 'error: the compiler unexpectedly panicked. this is a bug.' } : { code: 0, stdout: '', stderr: '' };
    };
    const logs: string[] = [];
    try {
      await runAnalyzeTests({ root, cache: null, run, log: (m) => logs.push(m) });
      expect(calls).toHaveLength(2);
      expect(calls[0].env.CARGO_INCREMENTAL).toBe('0');
      expect(calls[1].env.RUSTC_WRAPPER).toBe('');
      expect(fs.existsSync(path.join(root, 'tools/analyze/target/dev/incremental'))).toBe(false);
      expect(logs.some((m) => m.includes('rustc panicked'))).toBe(true);
    } finally {
      fs.rmSync(root, { recursive: true, force: true });
    }
  });

  test('an ordinary failure is not retried', async () => {
    const root = fixtureRoot();
    let count = 0;
    const run: TestCommand = async () => { count++; return { code: 101, stdout: '', stderr: 'error[E0308]: mismatched types' }; };
    try {
      await expect(runAnalyzeTests({ root, cache: null, run, log: () => {} })).rejects.toThrow('failed');
      expect(count).toBe(1);
    } finally {
      fs.rmSync(root, { recursive: true, force: true });
    }
  });
});
