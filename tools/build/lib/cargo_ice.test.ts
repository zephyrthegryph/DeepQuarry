import { describe, expect, test } from 'bun:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { cargoIncrementalEnv, cargoTargetDir, clearIncremental, compilerPanicSignature, incrementalDirs } from './cargo_ice';

describe('cargo ICE handling', () => {
  test('gate builds are non-incremental unless a dev build opts in', () => {
    expect(cargoIncrementalEnv({})).toEqual({ CARGO_INCREMENTAL: '0' });
    expect(cargoIncrementalEnv({ DQ_CARGO_INCREMENTAL: '1' })).toEqual({});
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
