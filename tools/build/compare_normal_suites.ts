/** Preliminary result comparison. Evidence hashes authenticate receipt bytes,
 * never a complete compiler source/resource closure or runtime baseline. */
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { compareNormalSuiteResults, type ComparableNormalSuite } from './lib/normal_suite_compare';
import { bindNormalPlan, normalSuiteBatches, sameSuiteRuntime, type IssuedNormalInventory, type RuntimeIdentity } from './lib/normal_suite_plan';
import type { CompilerProvenance } from './lib/compiler_provenance';
import type { UnitTestEntry } from './lib/bench';

type Run = {
  compilation: CompilerProvenance; killedByWatchdog: boolean; clean: boolean;
  runtimeIdentity: RuntimeIdentity; results: Record<string, UnitTestEntry> | null;
  inventory?: IssuedNormalInventory;
};
type Evidence = {
  schema: number; status: string; batchSize: number; compilation: CompilerProvenance;
  inventory: Run; plan: { sha256: string | null; eligibleOrder: string[]; observedOrderDiffers: boolean };
  batches: { requested: string[]; run: Run }[];
};
const SHA256 = /^[0-9a-f]{64}$/;
const HEX128 = /^[0-9a-f]{32}$/;
const equal = (left: unknown, right: unknown) => JSON.stringify(left) === JSON.stringify(right);

function compiler(value: CompilerProvenance, backend: 'byond' | 'native') {
  if (!value || value.actualBackend !== backend || value.requestedBackend !== backend || value.fallback !== null
      || !value.compiler || typeof value.compiler.executable !== 'string' || !path.isAbsolute(value.compiler.executable)
      || typeof value.compiler.sha256 !== 'string' || !SHA256.test(value.compiler.sha256)
      || !Array.isArray(value.orderedDefines) || value.orderedDefines.some(item => typeof item !== 'string')) {
    throw new Error(`missing authenticated ${backend} compiler identity or fallback present`);
  }
  if (backend === 'byond') {
    if (value.nativePair !== null || !Number.isInteger(value.compiler.version) || !Number.isInteger(value.compiler.build)) {
      throw new Error('BYOND compiler version/build evidence missing');
    }
  } else {
    const pair = value.nativePair;
    if (!pair || ![pair.pairId, pair.dmbHash, pair.rscHash].every(item => typeof item === 'string' && HEX128.test(item))
        || ![pair.dmbBytes, pair.rscBytes].every(item => Number.isSafeInteger(item) && item >= 0)) {
      throw new Error('native acquired pair identity missing');
    }
  }
}

function runtime(value: RuntimeIdentity) {
  if (!value || !path.isAbsolute(value.executable) || !SHA256.test(value.sha256)
      || value.version !== null || !['-trusted', '-safe', '-ultrasafe'].includes(value.security)) {
    throw new Error('missing or unsupported observed DreamDaemon identity/security');
  }
  if (value.library && (!path.isAbsolute(value.library.source) || !path.isAbsolute(value.library.hosted)
      || !SHA256.test(value.library.sha256) || !Number.isSafeInteger(value.library.bytes) || value.library.bytes < 0)) {
    throw new Error('invalid runtime library evidence');
  }
}

function admitted(value: Evidence, backend: 'byond' | 'native'): ComparableNormalSuite {
  if (!value || value.schema !== 1 || !['passed', 'failed'].includes(value.status) || !value.plan
      || typeof value.plan.observedOrderDiffers !== 'boolean' || !value.inventory?.inventory || !Array.isArray(value.batches)) {
    throw new Error('suite has no completed issued inventory/plan');
  }
  if (value.inventory.clean !== true) throw new Error('inventory boot was not clean');
  compiler(value.compilation, backend);
  runtime(value.inventory.runtimeIdentity);
  const plan = bindNormalPlan(value.inventory.inventory, { ...value.inventory.inventory, eligible: value.plan.eligibleOrder });
  const expected = normalSuiteBatches(plan, value.batchSize);
  if (!equal(expected, value.batches.map(batch => batch.requested))) throw new Error('batch boundaries/order differ from issued plan');
  if (value.plan.observedOrderDiffers !== !equal(value.plan.eligibleOrder, value.inventory.inventory.eligible)) {
    throw new Error('observed inventory order disclosure differs');
  }
  for (const run of [value.inventory, ...value.batches.map(batch => batch.run)]) {
    if (!run || typeof run.clean !== 'boolean' || run.killedByWatchdog !== false || !equal(run.compilation, value.compilation)) {
      throw new Error('incomplete/timed-out run or compiled output identity changed');
    }
    runtime(run.runtimeIdentity);
    if (!sameSuiteRuntime(run.runtimeIdentity, value.inventory.runtimeIdentity)) throw new Error('runtime identity changed within suite');
  }
  return { inventory: plan, runtime: value.inventory.runtimeIdentity,
    batches: value.batches.map(({ requested, run }) => ({ requested, results: run.results })) };
}

function read(file: string, expected: string) {
  if (!SHA256.test(expected)) throw new Error('expected receipt SHA256 must be lowercase 64-digit hex');
  const bytes = fs.readFileSync(file);
  if (createHash('sha256').update(bytes).digest('hex') !== expected) throw new Error(`receipt SHA256 mismatch: ${file}`);
  return JSON.parse(bytes.toString('utf8')) as Evidence;
}

export function compareEvidence(referenceFile: string, referenceSha256: string, nativeFile: string, nativeSha256: string) {
  const reference = read(referenceFile, referenceSha256), native = read(nativeFile, nativeSha256);
  const left = admitted(reference, 'byond'), right = admitted(native, 'native');
  if (native.plan.sha256 !== referenceSha256 || reference.batchSize !== native.batchSize
      || !equal(reference.plan.eligibleOrder, native.plan.eligibleOrder)
      || !equal(reference.compilation.orderedDefines, native.compilation.orderedDefines)) {
    throw new Error('native suite does not authenticate the same reference plan/batch size/configuration');
  }
  return { schema: 1, kind: 'preliminary_normal_suite_comparison', inputClosureAuthenticated: false,
    acceptedRuntimeBaseline: false, evidence: {
      reference: { path: path.resolve(referenceFile), sha256: referenceSha256 },
      native: { path: path.resolve(nativeFile), sha256: nativeSha256 },
    }, observedOrderDiffers: { reference: reference.plan.observedOrderDiffers, native: native.plan.observedOrderDiffers },
    ...compareNormalSuiteResults(left, right) };
}

if (import.meta.main) {
  try {
    const args = process.argv.slice(2);
    const flags = ['--reference', '--reference-sha256', '--native', '--native-sha256'];
    const values = new Map<string, string>();
    for (let index = 0; index < args.length; index += 2) {
      if (!flags.includes(args[index]) || values.has(args[index]) || !args[index + 1]) throw new Error('invalid/duplicate CLI argument');
      values.set(args[index], args[index + 1]);
    }
    if (values.size !== flags.length) throw new Error('required: --reference PATH --reference-sha256 HEX --native PATH --native-sha256 HEX');
    const result = compareEvidence(...flags.map(flag => values.get(flag)!) as [string, string, string, string]);
    console.log(JSON.stringify(result, null, 2));
    process.exitCode = result.matches ? 0 : 1;
  } catch (error) {
    console.error(JSON.stringify({ schema: 1, kind: 'preliminary_normal_suite_comparison',
      inputClosureAuthenticated: false, acceptedRuntimeBaseline: false, error: String(error) }));
    process.exitCode = 2;
  }
}
