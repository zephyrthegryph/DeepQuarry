/** Full relative filesystem capsule, not proof of unrestricted compiler reads. */
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
export type NamespaceLimits = { files: number; directories: number; bytes: number; depth: number };
export const defaultNamespaceLimits: NamespaceLimits = { files: 100_000, directories: 20_000, bytes: 8 * 1024 ** 3, depth: 64 };
export type NamespaceConfiguration = {
  orderedDefines: readonly string[];
  byondExecutableSha256: string;
  byondVersion: string;
  nativeExecutableSha256: string;
  nativeTemplateSha256: string;
};
export type NamespaceFailure = { kind: 'bound' | 'unsupported_namespace' | 'changed' | 'io'; reason: string };
export type NamespaceCapture = {
  schema: 'relative-snapshot-namespace-v1'; root: string; relativeManifest: string;
  configuration: NamespaceConfiguration;
  directories: { relative: string; entries: readonly string[] }[];
  files: { relative: string; bytes: number; sha256: string }[];
  namespace_closed: true; compile_access_complete: false;
  incompleteReasons: readonly string[];
};
class Failure extends Error {
  constructor(readonly kind: NamespaceFailure['kind'], message: string) { super(message); }
}
function normalRelative(value: string) {
  if (path.isAbsolute(value) || !value || value.split(/[\\/]/).some(part => !part || part === '.' || part === '..') || /^[A-Za-z]:/.test(value)) throw new Failure('unsupported_namespace', 'Manifest requires normal contained relative spelling.');
}
function hashFile(file: string, remaining: number) {
  const descriptor = fs.openSync(file, 'r');
  try {
    const before = fs.fstatSync(descriptor);
    if (!before.isFile() || before.size > remaining) throw new Failure('bound', 'Namespace byte bound exceeded.');
    const hash = createHash('sha256');
    const buffer = Buffer.allocUnsafe(64 * 1024);
    let bytes = 0;
    for (;;) {
      const length = fs.readSync(descriptor, buffer, 0, buffer.length, null);
      if (!length) break;
      bytes += length;
      if (bytes > remaining) throw new Failure('bound', 'Namespace byte bound exceeded.');
      hash.update(buffer.subarray(0, length));
    }
    const after = fs.fstatSync(descriptor);
    if (bytes !== before.size || before.size !== after.size || before.mtimeMs !== after.mtimeMs || before.ctimeMs !== after.ctimeMs) throw new Failure('changed', 'Input changed during capture.');
    return { bytes, sha256: hash.digest('hex') };
  } finally { fs.closeSync(descriptor); }
}
/** Destination must be nonexistent and outside source. No exclusions hide negatives. */
export function captureSnapshotNamespace(source: string, manifest: string, destination: string, configuration: NamespaceConfiguration, limits = defaultNamespaceLimits): { capture?: NamespaceCapture; failure?: NamespaceFailure } {
  const ownedFiles: string[] = [];
  const ownedDirectories: string[] = [];
  try {
    normalRelative(manifest);
    for (const value of Object.values(limits)) if (!Number.isSafeInteger(value) || value < 1) throw new Failure('bound', 'Invalid namespace limits.');
    const root = fs.realpathSync(source);
    const target = path.resolve(destination);
    if (target === root || target.startsWith(root + path.sep)) throw new Failure('unsupported_namespace', 'Capsule destination must be outside source.');
    if (fs.lstatSync(source).isSymbolicLink()) throw new Failure('unsupported_namespace', 'Source root is a link.');
    fs.mkdirSync(target); ownedDirectories.push(target);
    const directories: NamespaceCapture['directories'] = [];
    const files: NamespaceCapture['files'] = [];
    let total = 0;
    const pending = [{ relative: '', depth: 0 }];
    while (pending.length) {
      const current = pending.pop()!;
      if (current.depth > limits.depth || directories.length >= limits.directories) throw new Failure('bound', 'Namespace directory/depth bound exceeded.');
      const folder = path.join(root, current.relative);
      const entries = fs.readdirSync(folder).sort();
      directories.push({ relative: current.relative, entries });
      for (const name of entries) {
        const relative = path.join(current.relative, name);
        const input = path.join(root, relative);
        const metadata = fs.lstatSync(input);
        // Reject links/junctions; no recursion or implicit physical-root escape.
        if (metadata.isSymbolicLink() || fs.realpathSync(input) !== input) throw new Failure('unsupported_namespace', `Link or noncanonical entry: ${relative}`);
        const output = path.join(target, relative);
        if (metadata.isDirectory()) {
          fs.mkdirSync(output); ownedDirectories.push(output); pending.push({ relative, depth: current.depth + 1 });
        } else if (metadata.isFile()) {
          if (files.length >= limits.files) throw new Failure('bound', 'Namespace file bound exceeded.');
          const before = hashFile(input, limits.bytes - total);
          // The fresh capsule owns this path even if a copy leaves partial bytes.
          ownedFiles.push(output);
          fs.copyFileSync(input, output, fs.constants.COPYFILE_EXCL);
          const copied = hashFile(output, limits.bytes - total);
          const after = hashFile(input, limits.bytes - total);
          if (before.sha256 !== copied.sha256 || before.sha256 !== after.sha256) throw new Failure('changed', `Input changed: ${relative}`);
          total += copied.bytes; files.push({ relative, ...copied });
          fs.chmodSync(output, 0o444);
        } else throw new Failure('unsupported_namespace', `Nonregular entry: ${relative}`);
      }
    }
    for (const folder of directories) {
      if (JSON.stringify(fs.readdirSync(path.join(root, folder.relative)).sort()) !== JSON.stringify(folder.entries)) throw new Failure('changed', 'Directory namespace changed during capture.');
    }
    if (!files.some(file => file.relative === path.normalize(manifest))) throw new Failure('unsupported_namespace', 'Manifest is absent from captured namespace.');
    return { capture: { schema: 'relative-snapshot-namespace-v1', root: target, relativeManifest: manifest,
      configuration: { ...configuration, orderedDefines: [...configuration.orderedDefines] }, directories, files,
      namespace_closed: true, compile_access_complete: false,
      incompleteReasons: ['Active paths must be validated by existing dm-preprocess over this capsule.', 'Unrestricted DreamMaker external reads are not contained.', 'Effective compiler configuration authority is not issued by this filesystem producer.'],
    } };
  } catch (error) {
    // Remove only exact paths created in this attempt; never recurse through
    // an externally supplied path or remove a pre-existing destination.
    const cleanupFailures: string[] = [];
    for (const file of ownedFiles.reverse()) {
      try { if (fs.existsSync(file)) { fs.chmodSync(file, 0o666); fs.unlinkSync(file); } }
      catch (cleanupError) { cleanupFailures.push(String(cleanupError)); }
    }
    for (const directory of ownedDirectories.reverse()) {
      try { fs.rmdirSync(directory); }
      catch (cleanupError) { cleanupFailures.push(String(cleanupError)); }
    }
    return { failure: { kind: error instanceof Failure ? error.kind : 'io', reason: `${error}${cleanupFailures.length ? '; owned cleanup incomplete: ' + cleanupFailures.join('; ') : ''}` } };
  }
}
