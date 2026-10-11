import { test, expect } from 'bun:test';
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { archiveRuntimeLogs } from './runtime_log_archive';

function fixture(body: (root: string) => void) {
  const base = 'E:/dq-cache/dmb-native-v2/runtime-log-fixtures';
  fs.mkdirSync(base, { recursive: true });
  const root = fs.mkdtempSync(path.join(base, 'case-'));
  try { body(root); } finally {
    const resolved = fs.realpathSync(root);
    const relative = path.relative(fs.realpathSync(base), resolved);
    if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) throw new Error('fixture cleanup escaped owned root');
    fs.rmSync(resolved, { recursive: true });
  }
}

test('world reserved names and separate daemon bytes remain distinct and hash authenticated', () => fixture(root => {
  const source = path.join(root, 'logs'); fs.mkdirSync(source);
  fs.writeFileSync(path.join(source, 'manifest.json'), 'world manifest');
  fs.writeFileSync(path.join(source, 'daemon.log'), 'world daemon');
  const daemon = path.join(root, 'actual.log'); fs.writeFileSync(daemon, 'actual daemon');
  const archive = archiveRuntimeLogs(source, daemon, path.join(root, 'archive'));
  expect(archive.complete).toBe(true);
  const bytes = fs.readFileSync(archive.manifest!);
  expect(createHash('sha256').update(bytes).digest('hex')).toBe(archive.sha256);
  const directory = path.dirname(archive.manifest!);
  expect(fs.readFileSync(path.join(directory, 'world/manifest.json'), 'utf8')).toBe('world manifest');
  expect(fs.readFileSync(path.join(directory, 'world/daemon.log'), 'utf8')).toBe('world daemon');
  expect(fs.readFileSync(path.join(directory, 'daemon.log'), 'utf8')).toBe('actual daemon');
}));

test('missing logs and oversized logs explicitly decline complete archive coverage', () => fixture(root => {
  expect(archiveRuntimeLogs(path.join(root, 'missing'), null, path.join(root, 'archive')).complete).toBe(false);
  const source = path.join(root, 'logs'); fs.mkdirSync(source);
  const fd = fs.openSync(path.join(source, 'oversized.log'), 'wx');
  try { fs.ftruncateSync(fd, 64 * 1024 * 1024 + 1); } finally { fs.closeSync(fd); }
  const archive = archiveRuntimeLogs(source, null, path.join(root, 'archive'));
  const manifest = JSON.parse(fs.readFileSync(archive.manifest!, 'utf8'));
  expect(archive.complete).toBe(false);
  expect(manifest.files).toHaveLength(0);
  expect(manifest.omitted[0].name).toBe('world/oversized.log');
}));

test('an expected missing daemon log is disclosed even when world logs exist', () => fixture(root => {
  const source = path.join(root, 'logs'); fs.mkdirSync(source);
  const archive = archiveRuntimeLogs(source, path.join(root, 'missing-daemon.log'), path.join(root, 'archive'));
  expect(archive.complete).toBe(false);
  const manifest = JSON.parse(fs.readFileSync(archive.manifest!, 'utf8'));
  expect(manifest.omitted).toEqual([{ name: 'daemon.log', reason: 'owned daemon log missing' }]);
}));

test('multi-chunk binary and empty logs preserve exact bytes and hashes', () => fixture(root => {
  const source = path.join(root, 'logs'); fs.mkdirSync(source);
  const bytes = Buffer.alloc(1024 * 1024 + 37);
  for (let index = 0; index < bytes.length; index++) bytes[index] = index % 251;
  fs.writeFileSync(path.join(source, 'binary.log'), bytes);
  fs.writeFileSync(path.join(source, 'empty.log'), '');
  const archive = archiveRuntimeLogs(source, null, path.join(root, 'archive'));
  expect(archive.complete).toBe(true);
  const manifest = JSON.parse(fs.readFileSync(archive.manifest!, 'utf8'));
  const directory = path.dirname(archive.manifest!);
  expect(fs.readFileSync(path.join(directory, 'world/binary.log')).equals(bytes)).toBe(true);
  for (const file of manifest.files) {
    const copied = fs.readFileSync(path.join(directory, file.name));
    expect(copied.length).toBe(file.bytes);
    expect(createHash('sha256').update(copied).digest('hex')).toBe(file.sha256);
  }
}));
