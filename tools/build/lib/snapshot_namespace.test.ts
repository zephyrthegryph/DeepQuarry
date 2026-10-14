import { test, expect } from 'bun:test';
import fs from 'node:fs';
import path from 'node:path';
import { captureSnapshotNamespace } from './snapshot_namespace';
const configuration = { orderedDefines: ['X=1', 'X=2'], byondExecutableSha256: 'a'.repeat(64), byondVersion: '516.1687', nativeExecutableSha256: 'b'.repeat(64), nativeTemplateSha256: 'c'.repeat(64) };
test('namespace includes nested sources, resource directories and absent directory answers without claiming compiler closure', () => {
  const owned = fs.mkdtempSync('E:/dq-cache/namespace-fixture-');
  const source = path.join(owned, 'source');
  fs.mkdirSync(source); fs.mkdirSync(path.join(source, 'nested')); fs.mkdirSync(path.join(source, 'assets')); fs.mkdirSync(path.join(source, 'empty'));
  fs.writeFileSync(path.join(source, 'probe.dme'), '#define FILE_DIR "assets"\n#include "nested/leaf.dm"\n');
  fs.writeFileSync(path.join(source, 'nested/leaf.dm'), '/var/file = __FILE__\n/var/asset = \'marker.txt\'\n');
  fs.writeFileSync(path.join(source, 'assets/marker.txt'), 'payload');
  try {
    const result = captureSnapshotNamespace(source, 'probe.dme', path.join(owned, 'capsule'), configuration);
    expect(result.failure).toBeUndefined();
    expect(result.capture!.compile_access_complete).toBe(false);
    expect(result.capture!.configuration.orderedDefines).toEqual(['X=1', 'X=2']);
    expect(result.capture!.directories.find(row => row.relative === 'empty')!.entries).toEqual([]);
    expect(result.capture!.files.length).toBe(3);
    fs.writeFileSync(path.join(source, 'assets/marker.txt'), 'later');
    expect(fs.readFileSync(path.join(result.capture!.root, 'assets/marker.txt'), 'utf8')).toBe('payload');
    expect(captureSnapshotNamespace(source, '../probe.dme', path.join(owned, 'escape'), configuration).failure!.kind).toBe('unsupported_namespace');
    expect(captureSnapshotNamespace(source, 'probe.dme', path.join(owned, 'bounded'), configuration, { files: 1, directories: 100, bytes: 10000, depth: 10 }).failure!.kind).toBe('bound');
    expect(fs.existsSync(path.join(owned, 'bounded'))).toBe(false);
    const collision = captureSnapshotNamespace(source, 'probe.dme', source, configuration);
    expect(collision.failure!.kind).toBe('unsupported_namespace');
    expect(fs.readFileSync(path.join(source, 'assets/marker.txt'), 'utf8')).toBe('later');
  } finally {
    // Test owns this exact temporary subtree; chmod only its created capsule files.
    for (const directory of ['capsule', 'bounded']) {
      const root = path.join(owned, directory);
      if (!fs.existsSync(root)) continue;
      const pending = [root];
      while (pending.length) for (const entry of fs.readdirSync(pending.pop()!, { withFileTypes: true })) {
        const file = path.join(entry.parentPath, entry.name);
        if (entry.isDirectory()) pending.push(file); else fs.chmodSync(file, 0o666);
      }
    }
    fs.rmSync(owned, { recursive: true, force: true });
  }
});
