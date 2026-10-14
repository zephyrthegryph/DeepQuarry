import { expect, test } from 'bun:test';
import fs from 'node:fs';
import path from 'node:path';
import { copyWritableRuntimePair } from './runtime_pair_copy';
import { CompilerProvenanceError } from './compiler_provenance';

function fixture() {
  const parent = path.resolve('E:/dq-cache/dmb-protocol-checks');
  fs.mkdirSync(parent, { recursive: true });
  const root = fs.mkdtempSync(path.join(parent, 'writable-runtime-pair-'));
  const source = { dmb: path.join(root, 'capture.dmb'), rsc: path.join(root, 'capture.rsc') };
  fs.writeFileSync(source.dmb, 'immutable compiled DMB');
  fs.writeFileSync(source.rsc, 'immutable compiled RSC');
  for (const file of Object.values(source)) fs.chmodSync(file, 0o444);
  return { root, source, remove() {
    for (const name of fs.readdirSync(root)) {
      const file = path.join(root, name);
      fs.chmodSync(file, 0o600); // Only this fixture's files, after assertions.
      fs.unlinkSync(file);
    }
    fs.rmdirSync(root);
  } };
}

test('read-only captured pair yields writable independent hosted files without source mutation', () => {
  const files = fixture();
  try {
    const modes = Object.values(files.source).map(file => fs.statSync(file).mode);
    const base = path.join(files.root, 'hosted');
    copyWritableRuntimePair(files.source, base);
    for (const kind of ['dmb', 'rsc'] as const) {
      const target = `${base}.${kind}`;
      expect(fs.statSync(target).nlink).toBe(1);
      expect(fs.readFileSync(target).equals(fs.readFileSync(files.source[kind]))).toBe(true);
      fs.writeFileSync(target, `runtime changed ${kind}`);
    }
    expect(fs.readFileSync(files.source.dmb, 'utf8')).toBe('immutable compiled DMB');
    expect(fs.readFileSync(files.source.rsc, 'utf8')).toBe('immutable compiled RSC');
    expect(Object.values(files.source).map(file => fs.statSync(file).mode)).toEqual(modes);
  } finally { files.remove(); }
});

test.skipIf(process.platform !== 'win32')('observe Windows raw copy writeability independently of repaired staging', () => {
  const files = fixture();
  try {
    const raw = path.join(files.root, 'raw-copy.rsc');
    fs.copyFileSync(files.source.rsc, raw, fs.constants.COPYFILE_EXCL);
    let rawWritable = false;
    try { const descriptor = fs.openSync(raw, 'r+'); fs.closeSync(descriptor); rawWritable = true; } catch {}
    console.info(`Windows unmodified fs.copyFileSync read-only source: destinationWritable=${rawWritable}`);
    copyWritableRuntimePair(files.source, path.join(files.root, 'fixed'));
    const descriptor = fs.openSync(path.join(files.root, 'fixed.rsc'), 'r+');
    fs.closeSync(descriptor);
    expect(fs.readFileSync(raw).equals(fs.readFileSync(files.source.rsc))).toBe(true);
  } finally { files.remove(); }
});

test('stale shared targets and source aliases are rejected before changing captured permissions', () => {
  const files = fixture();
  try {
    const sourceMode = fs.statSync(files.source.dmb).mode;
    const base = path.join(files.root, 'shared');
    fs.linkSync(files.source.dmb, `${base}.dmb`);
    expect(() => copyWritableRuntimePair(files.source, base)).toThrow(CompilerProvenanceError);
    expect(fs.statSync(files.source.dmb).mode).toBe(sourceMode);
    expect(fs.readFileSync(files.source.dmb, 'utf8')).toBe('immutable compiled DMB');
    expect(() => copyWritableRuntimePair(files.source, files.source.dmb.slice(0, -4))).toThrow(CompilerProvenanceError);
    expect(fs.readFileSync(files.source.rsc, 'utf8')).toBe('immutable compiled RSC');
  } finally { files.remove(); }
});

test('two shard copies isolate mutable resources from each other and the private captured pair', () => {
  const files = fixture();
  try {
    const first = path.join(files.root, 'shard1'), second = path.join(files.root, 'shard2');
    copyWritableRuntimePair(files.source, first);
    copyWritableRuntimePair(files.source, second);
    fs.writeFileSync(`${first}.rsc`, 'world-one dynamic archive');
    expect(fs.readFileSync(`${second}.rsc`, 'utf8')).toBe('immutable compiled RSC');
    expect(fs.readFileSync(files.source.rsc, 'utf8')).toBe('immutable compiled RSC');
  } finally { files.remove(); }
});
