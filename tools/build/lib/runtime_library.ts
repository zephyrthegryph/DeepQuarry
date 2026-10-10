/** Runtime libraries are inputs to a hosted world, not members of its DMB/RSC pair. */
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { assertDirectoryChain } from './native_pair';

export type HostedLibraryIdentity = { source: string; hosted: string; sha256: string; bytes: number };
function readRegular(file: string): Buffer {
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1) throw new Error(`Runtime library is not an independent regular file: ${file}`);
  return fs.readFileSync(file);
}
function sha(bytes: Buffer): string { return createHash('sha256').update(bytes).digest('hex'); }

/** Observe the current conventional runtime input; this does not authenticate earlier runs. */
export function observeRuntimeLibrary(source: string): HostedLibraryIdentity {
  source = path.resolve(source);
  assertDirectoryChain(path.dirname(source));
  const captured = readRegular(source);
  return { source, hosted: source, sha256: sha(captured), bytes: captured.length };
}

/** A current observation may certify this run only while its input stays fixed. */
export function verifyObservedRuntimeLibrary(identity: HostedLibraryIdentity): void {
  const current = observeRuntimeLibrary(identity.hosted);
  if (current.sha256 !== identity.sha256 || current.bytes !== identity.bytes) {
    throw new Error('Observed runtime library changed during hosted world execution.');
  }
}

/** Destination must be an already authenticated acquired slot. Never overwrite a leaf. */
export function stageRuntimeLibrary(source: string, slot: string): { identity: HostedLibraryIdentity; remove: () => void } {
  source = path.resolve(source);
  slot = path.resolve(slot);
  assertDirectoryChain(path.dirname(source));
  assertDirectoryChain(slot);
  const destination = path.join(slot, path.basename(source));
  const captured = readRegular(source);
  const expected = sha(captured);
  fs.writeFileSync(destination, captured, { flag: 'wx' });
  const identity = { source, hosted: destination, sha256: expected, bytes: captured.length };
  const remove = () => {
    assertDirectoryChain(slot);
    if (sha(readRegular(destination)) !== expected) throw new Error('Hosted runtime library changed; preserving it for inspection.');
    fs.unlinkSync(destination);
  };
  try {
    if (sha(readRegular(source)) !== expected || sha(readRegular(destination)) !== expected) {
      throw new Error('Runtime library moved during capture.');
    }
  } catch (error) {
    remove();
    throw error;
  }
  return { identity, remove };
}
