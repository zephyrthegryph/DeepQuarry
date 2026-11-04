import { describe, expect, test } from 'bun:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { cargoIncrementalEnv, cargoTargetDir, cargoWithIceRetry, clearIncremental, compilerPanicSignature, incrementalDirs } from './cargo_ice';

describe('cargo ICE handling', () => {
  test('gate builds are non-incremental unless a dev build opts in', () => {
    expect(cargoIncrementalEnv({})).toEqual({ CARGO_INCREMENTAL: '0' });
    expect(cargoIncrementalEnv({ DQ_CARGO_INCREMENTAL: '1' })).toEqual({});
  });

  test('lane builds leave incremental to the profile unless CI or the opt-out says otherwise', () => {
    expect(cargoIncrementalEnv({}, 'lane')).toEqual({});
    expect(cargoIncrementalEnv({ CI: 'true' }, 'lane')).toEqual({ CARGO_INCREMENTAL: '0' });
    expect(cargoIncrementalEnv({ DQ_CARGO_INCREMENTAL: '0' }, 'lane')).toEqual({ CARGO_INCREMENTAL: '0' });
    expect(cargoIncrementalEnv({ DQ_CARGO_INCREMENTAL: '1', CI: 'true' }, 'lane')).toEqual({});
  });

  test('a rustc panic clears the incremental directories and retries once without the rustc wrapper', async () => {
    const target = fs.mkdtempSync(path.join(os.tmpdir(), 'cargo-ice-retry-'));
    try {
      fs.mkdirSync(path.join(target, 'i686-pc-windows-msvc/lane/incremental/a'), { recursive: true });
      const runs: { env: NodeJS.ProcessEnv }[] = [];
      const warnings: string[] = [];
      await cargoWithIceRetry(['build', '--profile', 'lane'], { env: { CARGO_TARGET_DIR: target } }, {
        warn: (m) => warnings.push(m),
        exec: async (_args, env) => {
          runs.push({ env });
          return runs.length === 1 ? { code: 101, combined: 'error: the compiler unexpectedly panicked. this is a bug.' } : { code: 0 };
        },
      });
      expect(runs).toHaveLength(2);
      expect(runs[1].env.RUSTC_WRAPPER).toBe('');
      expect(incrementalDirs(target)).toHaveLength(0);
      expect(warnings[0]).toContain('removed 1 incremental dir');
    } finally {
      fs.rmSync(target, { recursive: true, force: true });
    }
  });

  test('a source error is not retried, and a second panic fails', async () => {
    let calls = 0;
    const deps = { warn: () => {}, exec: async () => { calls++; return { code: 101, combined: 'error[E0308]: mismatched types' }; } };
    await expect(cargoWithIceRetry(['build'], { env: { CARGO_TARGET_DIR: fs.mkdtempSync(path.join(os.tmpdir(), 'cargo-ice-1-')) } }, deps)).rejects.toThrow('failed (exit 101)');
    expect(calls).toBe(1);
    calls = 0;
    const panics = { warn: () => {}, exec: async () => { calls++; return { code: 101, combined: 'internal compiler error' }; } };
    await expect(cargoWithIceRetry(['build'], { env: { CARGO_TARGET_DIR: fs.mkdtempSync(path.join(os.tmpdir(), 'cargo-ice-2-')) } }, panics)).rejects.toThrow('failed');
    expect(calls).toBe(2);
  });

  test('recognises a compiler panic but not a source error', () => {
    expect(compilerPanicSignature('error: the compiler unexpectedly panicked. this is a bug.')).toBe(true);
    expect(compilerPanicSignature('error[E0308]: mismatched types')).toBe(false);
  });

  test('clears every incremental directory and nothing else', () => {
    const target = fs.mkdtempSync(path.join(os.tmpdir(), 'cargo-ice-'));
    try {
      for (const dir of ['dev-fast/incremental/a', 'debug/incremental/b', 'x86_64-pc-windows-msvc/release/incremental/c', 'debug/deps']) fs.mkdirSync(path.join(target, dir), { recursive: true });
      expect(incrementalDirs(target)).toHaveLength(3);
      expect(clearIncremental(target)).toHaveLength(3);
      expect(incrementalDirs(target)).toHaveLength(0);
      expect(fs.existsSync(path.join(target, 'debug/deps'))).toBe(true);
    } finally {
      fs.rmSync(target, { recursive: true, force: true });
    }
  });

  test('finds the target directory', () => {
    expect(cargoTargetDir([], { CARGO_TARGET_DIR: '/t' }, '/w')).toBe(path.resolve('/t'));
    expect(cargoTargetDir(['build', '--manifest-path', 'tools/analyze/Cargo.toml'], {}, '/w')).toBe(path.resolve('/w/tools/analyze/target'));
    expect(cargoTargetDir(['test'], {}, '/w/tools/analyze')).toBe(path.resolve('/w/tools/analyze/target'));
  });
});
