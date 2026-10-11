/** Source-qualified ordinary Rust build evidence for an explicitly captured world. */
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { assertDirectoryChain } from './native_pair';
export type LibraryPin = { path: string; sha256: string; bytes: number };
export type CapturedRuntimeLibrary = {
  buildReceipt: LibraryPin; sourcePin: LibraryPin; library: LibraryPin;
  pair: { dmb: LibraryPin; rsc: LibraryPin };
};
function checked(pin: LibraryPin): Buffer {
  if (!path.isAbsolute(pin.path) || !/^[0-9a-f]{64}$/.test(pin.sha256)) throw new Error('Invalid captured runtime pin');
  assertDirectoryChain(path.dirname(pin.path));
  const stat = fs.lstatSync(pin.path);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1 || stat.size !== pin.bytes || stat.size > 64 * 1024 * 1024) throw new Error('Unsafe captured runtime input');
  const bytes = fs.readFileSync(pin.path);
  if (createHash('sha256').update(bytes).digest('hex') !== pin.sha256) throw new Error('Captured runtime input changed');
  return bytes;
}
export function verifyCapturedRuntimeLibrary(proof: CapturedRuntimeLibrary): string {
  const build = JSON.parse(checked(proof.buildReceipt).toString('utf8'));
  const source = JSON.parse(checked(proof.sourcePin).toString('utf8'));
  const snapshotBytes = checked(build.snapshot);
  const closureBytes = checked(build.closure);
  const snapshot = JSON.parse(snapshotBytes.toString('utf8'));
  const closure = JSON.parse(closureBytes.toString('utf8'));
  const sourceRows = Object.fromEntries(closure.filter((row: any) => row.tree === 'source').map((row: any) => [row.path, row.sha256]));
  const ordered = (value: Record<string, string>) => JSON.stringify(Object.entries(value).sort(([a], [b]) => a.localeCompare(b)));
  if (build.schema !== 'captured-verdigris-build-v1' || build.exit !== 0 || build.timeout !== false || build.error != null
      || build.owned_job_cleanup?.reaped !== true || build.workers !== 1
      || build.child_watchdog_seconds !== 300 || build.job_memory_bytes !== 4_000_000_000
      || build.sourceSnapshotSha256 !== source.snapshot_id
      || build.sourceClosureSha256 !== source.source_closure_manifest_sha256
      || !build.inputsBefore || JSON.stringify(build.inputsBefore) !== JSON.stringify(build.inputsAfter)
      || ordered(build.inputsBefore) !== ordered(snapshot.files) || ordered(sourceRows) !== ordered(snapshot.files)
      || build.snapshot.sha256 !== build.sourceSnapshotSha256 || build.closure.sha256 !== build.sourceClosureSha256
      || !Object.keys(build.inputsBefore).length
      || build.library?.sha256 !== proof.library.sha256 || build.library?.bytes !== proof.library.bytes
      || path.resolve(build.library?.path ?? '') !== proof.library.path
      || !/^[0-9a-f]+$/.test(build.abi ?? '')) throw new Error('Unqualified captured runtime build');
  const command = build.command;
  if (!Array.isArray(command) || command[1] !== 'build' || !command.includes('--locked')
      || !command.includes('-j1') || !command.includes('--release')
      || command[command.indexOf('--target') + 1] !== 'i686-pc-windows-msvc'
      || command[command.indexOf('--package') + 1] !== 'verdigris' || !command.includes('--lib')) throw new Error('Captured runtime was not built by the ordinary bounded Cargo route');
  checked(build.cargo);
  const dmAbi = checked(build.bindings).toString('utf8');
  const rustAbi = checked(build.rustAbi).toString('utf8');
  if (dmAbi.match(/^#define VERDIGRIS_ABI "([0-9a-f]+)"/m)?.[1] !== build.abi
      || rustAbi.match(/pub const ABI: &str = "([0-9a-f]+)";/)?.[1] !== build.abi
      || build.bindings.sha256 !== build.inputsBefore['code/__defines/verdigris/_bindings.dm']
      || build.rustAbi.sha256 !== build.inputsBefore['verdigris/ffi/src/abi.rs']
      || build.bindings.path !== path.join(build.sourceRoot, 'code', '__defines', 'verdigris', '_bindings.dm')
      || build.rustAbi.path !== path.join(build.sourceRoot, 'verdigris', 'ffi', 'src', 'abi.rs')) throw new Error('Captured generated ABI authority differs');
  if (command[0] !== build.cargo.path || path.resolve(build.cwd) !== path.join(path.resolve(build.sourceRoot), 'verdigris')
      || !path.resolve(build.targetDirectory).toLowerCase().startsWith('e:\\dq-cache\\')
      || proof.library.path !== path.join(path.resolve(build.targetDirectory), 'i686-pc-windows-msvc', 'release', 'verdigris.dll')) throw new Error('Captured runtime build paths differ');
  let configurations: any[] | undefined;
  for (const evidence of [...source.configuration_evidence, source.byond_version_evidence]) {
    assertDirectoryChain(path.dirname(evidence.path));
    const stat = fs.lstatSync(evidence.path);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1 || stat.size > 1024 * 1024) throw new Error('Unsafe captured compiler evidence');
    const bytes = fs.readFileSync(evidence.path);
    if (createHash('sha256').update(bytes).digest('hex') !== evidence.sha256) throw new Error('Captured compilation source pin changed');
    if (source.configuration_evidence.includes(evidence)) configurations = JSON.parse(bytes.toString('utf8'));
  }
  if (!configurations || !['byond', 'native'].every(backend => configurations!.some(row => row.producer === backend && path.resolve(row.cwd ?? '') === path.resolve(build.sourceRoot)))) throw new Error('Runtime build and captured compiler source roots differ');
  const dll = checked(proof.library);
  if (path.basename(proof.library.path).toLowerCase() !== 'verdigris.dll' || !dll.includes(Buffer.from(build.abi, 'ascii'))) throw new Error('Captured runtime ABI mismatch');
  return proof.library.path;
}
