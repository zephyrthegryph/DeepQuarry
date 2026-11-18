import { describe, expect, test } from 'bun:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { cargoIncrementalEnv, cargoTargetDir, cargoWithIceRetry, clearIncremental, compilerPanicSignature, incrementalDirs } from './cargo_ice';

describe('cargo ICE handling', () => {
  test('lane, gate and CI builds force incremental despite profile and caller opt-outs', () => {
    for (const kind of ['lane', 'gate'] as const) {
      for (const env of [{}, { CI: 'true' }, { DQ_CARGO_INCREMENTAL: '0' }, { DQ_CARGO_INCREMENTAL: '1' }, { CARGO_INCREMENTAL: '0', RUSTC_WRAPPER: 'sccache' }]) {
        expect(cargoIncrementalEnv(env, kind)).toEqual({ CARGO_INCREMENTAL: '1', RUSTC_WRAPPER: '' });
      }
    }
  });

  test('actual Cargo execution overrides opt-out and retains workspace instrumentation', async () => {
    const runs: NodeJS.ProcessEnv[] = [];
    await cargoWithIceRetry(['build'], { env: { CI: 'true', CARGO_INCREMENTAL: '0', RUSTC_WRAPPER: 'sccache', RUSTC_WORKSPACE_WRAPPER: 'workspace-instrumentation', CARGO_BUILD_RUSTC_WRAPPER: 'configured-wrapper' } }, {
      kind: 'gate', warn: () => {}, exec: async (_args, env) => { runs.push(env); return { code: 0 }; },
    });
    expect(runs).toHaveLength(1);
    expect(runs[0].CARGO_INCREMENTAL).toBe('1');
    expect(runs[0].RUSTC_WRAPPER).toBe('');
    expect(runs[0].RUSTC_WORKSPACE_WRAPPER).toBe('workspace-instrumentation');
    expect(runs[0].CARGO_BUILD_RUSTC_WRAPPER).toBe('configured-wrapper');
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
      for (const run of runs) { expect(run.env.CARGO_INCREMENTAL).toBe('1'); expect(run.env.RUSTC_WRAPPER).toBe(''); }
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
