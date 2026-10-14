import fs from 'node:fs';
import path from 'node:path';
import { assertDirectoryChain } from './native_pair';
import { CompilerProvenanceError } from './compiler_provenance';

function canonicalPath(file: string): string {
  const resolved = fs.existsSync(file) ? fs.realpathSync.native(file)
    : path.join(fs.realpathSync.native(path.dirname(file)), path.basename(file));
  return process.platform === 'win32' ? resolved.toLowerCase() : resolved;
}

/** Caller owns both destination leaves through its acquired run-slot/private-base
 * lifecycle. Never change permissions through a hard link to a captured input.
 * DreamDaemon may mutate its resource archive, so each world gets a fresh copy.
 */
export function copyWritableRuntimePair(source: { dmb: string; rsc: string }, ownedBase: string): void {
  const targets = { dmb: path.resolve(`${ownedBase}.dmb`), rsc: path.resolve(`${ownedBase}.rsc`) };
  const inputs = { dmb: path.resolve(source.dmb), rsc: path.resolve(source.rsc) };
  try {
    for (const target of Object.values(targets)) {
      assertDirectoryChain(path.dirname(target));
      if (Object.values(inputs).some(input => canonicalPath(input) === canonicalPath(target))) {
        throw new Error('Runtime target aliases captured input path.');
      }
    }
    for (const kind of ['dmb', 'rsc'] as const) {
      const input = inputs[kind], target = targets[kind];
      assertDirectoryChain(path.dirname(input));
      const sourceStat = fs.lstatSync(input);
      if (!sourceStat.isFile() || sourceStat.isSymbolicLink()) throw new Error('Runtime input is not a regular file.');
      // A stale shared leaf is declined: Windows unlink may clear a shared
      // READONLY attribute. Never change its source's permissions indirectly.
      try {
        const old = fs.lstatSync(target);
        if (!old.isFile() || old.isSymbolicLink() || old.nlink !== 1) throw new Error('Invalid or shared owned runtime target.');
        fs.unlinkSync(target);
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
      }
      fs.copyFileSync(input, target, fs.constants.COPYFILE_EXCL);
      const copied = fs.lstatSync(target);
      if (!copied.isFile() || copied.isSymbolicLink() || copied.nlink !== 1 || copied.size !== sourceStat.size) {
        throw new Error('Runtime target is not an independent complete copy.');
      }
      // Windows CopyFile may inherit READONLY. Clear it on this new owner only.
      fs.chmodSync(target, 0o600);
      const descriptor = fs.openSync(target, 'r+');
      fs.closeSync(descriptor);
    }
  } catch (error) {
    throw new CompilerProvenanceError(`Cannot stage independent writable runtime pair: ${error}`);
  }
}
