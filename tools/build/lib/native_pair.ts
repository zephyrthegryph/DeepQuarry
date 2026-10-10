/** Native generation results and independently owned writable hosted outputs. */
import fs from 'node:fs';
import path from 'node:path';

export type PairIdentity = {
  pairId: string; dmbHash: string; rscHash: string; dmbBytes: number; rscBytes: number;
};
export type NativePairOutput = PairIdentity & {
  kind: 'native_pair'; compiler: string; store: string; outputProject: string;
};
export type CompiledOutput = NativePairOutput | {
  kind: 'conventional'; backend: 'byond'; dmb: string; rsc: string;
};
export type PairExecutor = (executable: string, args: string[], options?: { throw?: boolean }) => Promise<{ code: number | null; combined: string }>;

const HEX = /^[0-9a-f]{32}$/;
function samePath(left: string, right: string): boolean {
  if (process.platform === 'win32') return path.toNamespacedPath(left).toLowerCase() === path.toNamespacedPath(right).toLowerCase();
  return left === right;
}
function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}
function absolute(value: unknown): string {
  if (typeof value !== 'string' || !path.isAbsolute(value)) throw new Error('Native receipt path must be absolute.');
  return path.resolve(value);
}
function identity(value: Record<string, unknown>): PairIdentity {
  for (const field of ['pair_id', 'dmb_hash', 'rsc_hash']) {
    if (typeof value[field] !== 'string' || !HEX.test(value[field] as string)) throw new Error(`Native receipt requires lowercase 128-bit hex ${field}.`);
  }
  for (const field of ['dmb_bytes', 'rsc_bytes']) {
    if (typeof value[field] !== 'number' || !Number.isSafeInteger(value[field]) || (value[field] as number) < 0) throw new Error(`Native receipt requires exact ${field}.`);
  }
  return { pairId: value.pair_id as string, dmbHash: value.dmb_hash as string, rscHash: value.rsc_hash as string, dmbBytes: value.dmb_bytes as number, rscBytes: value.rsc_bytes as number };
}
export function conventionalOutput(dme: string): CompiledOutput {
  const stem = path.resolve(dme).replace(/\.dme$/i, '');
  return { kind: 'conventional', backend: 'byond', dmb: `${stem}.dmb`, rsc: `${stem}.rsc` };
}
export function parseCompileResult(value: unknown, compiler: string, project: string): NativePairOutput {
  if (!object(value) || value.schema_version !== 1 || value.kind !== 'native_pair') throw new Error('Missing or unsupported native compile result.');
  const outputProject = absolute(value.output_project);
  const expected = fs.existsSync(project) ? fs.realpathSync.native(project) : path.resolve(project);
  if (!samePath(outputProject, expected)) throw new Error('Native compile result names another output project.');
  return { kind: 'native_pair', compiler, store: absolute(value.store), outputProject, ...identity(value) };
}

function assertRegular(file: string): void {
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink()) throw new Error(`Expected regular owned native file: ${file}`);
}
function assertDirectoryChain(directory: string): void {
  let current = path.resolve(directory);
  for (;;) {
    const stat = fs.lstatSync(current);
    if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error(`Native output directory has a reparse/symlink ancestor: ${current}`);
    const parent = path.dirname(current);
    if (parent === current) break;
    current = parent;
  }
}
export function createNativeRequestDirectory(prefix: string): string {
  const root = path.resolve(process.env.DQ_NATIVE_RUN_ROOT ?? 'E:/dq-cache/dmb-build-integration');
  if (!/^e:[\\/]/i.test(root)) throw new Error('Native integration scratch must be on E:.');
  fs.mkdirSync(root, { recursive: true });
  assertDirectoryChain(root);
  return fs.mkdtempSync(path.join(root, `${prefix}-`));
}
export function readNativeResult(file: string): unknown {
  assertRegular(file);
  if (fs.statSync(file).size > 64 * 1024) throw new Error('Native machine result exceeds bounded receipt size.');
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

export type AcquiredPair = { slot: string; dmb: string; rsc: string; pairId: string };
export function parseAcquiredResult(value: unknown, expected: NativePairOutput, ownedRoot: string): AcquiredPair {
  if (!object(value) || value.schema_version !== 1 || value.kind !== 'acquired_pair') throw new Error('Missing or unsupported native acquisition result.');
  const actual = identity(value);
  for (const field of ['pairId', 'dmbHash', 'rscHash', 'dmbBytes', 'rscBytes'] as const) {
    if (actual[field] !== expected[field]) throw new Error(`Acquired generation differs: ${field}.`);
  }
  if (!samePath(absolute(value.store), expected.store)) throw new Error('Acquisition names another store.');
  const slot = absolute(value.slot);
  if (!samePath(path.dirname(slot), path.resolve(ownedRoot))) throw new Error('Acquisition escaped its owned run root.');
  assertDirectoryChain(slot);
  const dmb = absolute(value.dmb);
  const rsc = absolute(value.rsc);
  if (!samePath(dmb, path.join(slot, 'deepquarry.dmb')) || !samePath(rsc, path.join(slot, 'deepquarry.rsc'))) throw new Error('Acquisition has unexpected artifact paths.');
  for (const [file, bytes] of [[dmb, expected.dmbBytes], [rsc, expected.rscBytes]] as const) {
    assertRegular(file);
    const stat = fs.statSync(file);
    if (stat.size !== bytes || stat.nlink !== 1) throw new Error('Native run files must be complete independent copies.');
  }
  assertRegular(path.join(slot, 'slot-complete'));
  if (fs.readFileSync(path.join(slot, 'slot-complete'), 'utf8') !== expected.pairId) throw new Error('Acquired slot is not complete for this generation.');
  return { slot, dmb, rsc, pairId: expected.pairId };
}

/** The caller owns this fresh root. Never clean a path named by an unchecked receipt. */
function removeOwnedOutputs(root: string, acquired: AcquiredPair | undefined): void {
  assertDirectoryChain(root);
  if (acquired) {
    assertDirectoryChain(acquired.slot);
    for (const name of ['deepquarry.dmb', 'deepquarry.rsc', 'deepquarry.dyn.rsc', 'pair.json', 'slot-complete']) {
      const file = path.join(acquired.slot, name);
      if (!fs.existsSync(file)) continue;
      assertRegular(file);
      fs.unlinkSync(file);
    }
    // Unknown/runtime diagnostic leaves stay intact. In particular -logself
    // evidence is preserved even if copying it to the normal log path failed.
    if (fs.readdirSync(acquired.slot).length === 0) {
      fs.rmdirSync(acquired.slot);
      fs.unlinkSync(path.join(root, 'acquisition.json'));
    }
  }
  if (fs.readdirSync(root).length === 0) fs.rmdirSync(root);
  else console.warn(`Native run evidence retained: ${root}`);
}

/** Copies stay alive until the child callback has exited/reaped, including failure. */
export class NativeAcquisitionError extends Error {}
export async function withCompiledOutput<T>(output: CompiledOutput, execute: PairExecutor, child: (dmb: string) => Promise<T>): Promise<T> {
  if (output.kind === 'conventional') return child(output.dmb);
  let root: string;
  try { root = createNativeRequestDirectory('run'); }
  catch (error) { throw new NativeAcquisitionError(`Cannot allocate native run ownership: ${error}`); }
  const receipt = path.join(root, 'acquisition.json');
  let acquired: AcquiredPair | undefined;
  let failed = false;
  try {
    try {
      const result = await execute(output.compiler, ['acquire', '--output-store', output.store, '--pair-id', output.pairId, '--slots', root, '--result-file', receipt], { throw: false });
      if (result.code !== 0) throw new Error(`Native pair acquisition failed (${result.code}): ${result.combined}`);
      acquired = parseAcquiredResult(readNativeResult(receipt), output, root);
    } catch (error) { throw new NativeAcquisitionError(`Cannot host the requested native generation: ${error}`); }
    return await child(acquired.dmb);
  } catch (error) {
    failed = true;
    throw error;
  } finally {
    try { removeOwnedOutputs(root, acquired); }
    catch (error) {
      if (failed) {
        // Preserve the hosted child's typed status, including cancellation.
        // The cleanup limitation leaves owned evidence for inspection.
        console.warn(`Native owned run cleanup preserved ${root}: ${error}`);
      } else {
        throw new NativeAcquisitionError(`Native owned run cleanup failed: ${error}`);
      }
    }
  }
}

// This registry is process-local successful build output, never a mutable marker
// inferred from conventional paths. Native targets must compile in this invocation.
const outputs = new Map<string, CompiledOutput>();
export function rememberCompiledOutput(dme: string, output: CompiledOutput): void {
  outputs.set(path.resolve(dme).replace(/\.dme$/i, '.dmb'), output);
}
export function currentCompiledOutput(dmb: string, nativeRequired: boolean): CompiledOutput {
  const known = outputs.get(path.resolve(dmb));
  if (known) return known;
  if (nativeRequired) throw new Error('Native hosted world has no successful pair result in this build invocation.');
  return { kind: 'conventional', backend: 'byond', dmb: path.resolve(dmb), rsc: path.resolve(dmb).replace(/\.dmb$/i, '.rsc') };
}
