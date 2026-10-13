import { failedCompileOutcome, observedCompileOutcome, type CompileOutcome } from './compile_outcome';
/** One build entry point for BYOND, native compilation and isolated shadow checks. */
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import Juke from '../juke/index.js';
import { classifyResourceReport } from './shadow_resources';
import { captureShadowOutputPair } from './shadow_output';
import { sharedCompilerConfiguration } from './shared_compiler_configuration';
import type { ByondCompilationResult, DreamMakerOptions, PreparedDreamMaker } from './byond';
import { conventionalOutput, createNativeRequestDirectory, parseCompileResult, readNativeResult, withCompiledOutput, type CompiledOutput, type NativePairOutput } from './native_pair';

import { bindCompilerInvocation, type CompilerInvocation } from './compiler_invocation';
import { byondProvenance, nativeProvenance, observedExecutable } from './compiler_provenance';

type CompilerMode = 'byond' | 'native' | 'shadow';
const structuralCategories = ['type_set', 'type_headers', 'variable_defaults', 'procedure_table', 'procedure_flags', 'globals', 'strings_by_use', 'bytecode', 'other'];
export type ShadowAdmission = { status: 'parity' | 'invalid_report' | 'incomplete' | 'differences'; reason: string };
/** Issued configuration prerequisites do not authenticate compilation inputs. */
export function shadowSnapshotContract(): { status: 'incomplete'; reason: string } {
  return { status: 'incomplete', reason: 'Shared source/resource closure and complete implicit compiler configuration remain unissued; shared compilation snapshot is unproven' };
}
function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}
function count(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
}
/** Strict shadow parity; this does not admit a historical divergence baseline. */
export function classifyShadowReport(value: unknown, snapshot: string): ShadowAdmission {
  const invalid = (reason: string): ShadowAdmission => ({ status: 'invalid_report', reason });
  if (!object(value) || value.schema_version !== 1 || value.snapshot_id !== snapshot) return invalid('unsupported schema or mismatched comparison snapshot');
  if (typeof value.traversal_complete !== 'boolean' || typeof value.tool_complete !== 'boolean' || typeof value.complete !== 'boolean' || (value.semantic_coverage !== 'complete' && value.semantic_coverage !== 'incomplete')) return invalid('missing comparison completion fields');
  if (!count(value.total_discrepancies) || !count(value.unexplained_discrepancies) || value.unexplained_discrepancies > value.total_discrepancies || !object(value.categories) || !object(value.uncovered)) return invalid('missing or invalid discrepancy/coverage counts');
  let total = 0;
  for (const category of structuralCategories) {
    if (!object(value.categories[category])) return invalid(`missing category ${category}`);
  }
  for (const category of Object.values(value.categories)) {
    if (!object(category) || !count(category.discrepancy_count)) return invalid('invalid category count');
    total += category.discrepancy_count;
    if (!Number.isSafeInteger(total)) return invalid('category total exceeds exact numeric range');
  }
  if (total !== value.total_discrepancies) return invalid('category counts disagree with total');
  let uncovered = 0;
  for (const coverage of Object.values(value.uncovered)) {
    if (!object(coverage) || !count(coverage.occurrence_count)) return invalid('invalid uncovered count');
    uncovered += coverage.occurrence_count;
    if (!Number.isSafeInteger(uncovered)) return invalid('coverage total exceeds exact numeric range');
  }
  if (value.complete !== (value.semantic_coverage === 'complete') || (value.complete && uncovered !== 0)) return invalid('semantic coverage fields contradict uncovered evidence');
  if (!value.traversal_complete || !value.tool_complete || !value.complete) return { status: 'incomplete', reason: `comparison coverage incomplete (${uncovered} uncovered occurrences)` };
  if (total !== 0 || value.unexplained_discrepancies !== 0) return { status: 'differences', reason: `${total} structural discrepancies (${value.unexplained_discrepancies} unexplained)` };
  return { status: 'parity', reason: 'complete named structural comparison with zero discrepancies' };
}
export type CompilerExecutor = (executable: string, args: string[], options?: { throw?: boolean; cwd?: string }) => Promise<{ code: number | null; combined: string; signal?: string | null }>;
export function compilerMode(): CompilerMode {
  const mode = process.env.DQ_COMPILER ?? 'byond';
  if (mode !== 'byond' && mode !== 'native' && mode !== 'shadow') {
    throw new Error(`Unknown DQ_COMPILER=${mode}; expected byond, native or shadow.`);
  }
  return mode;
}
function nativeNoDaemon(): boolean {
  const value = process.env.DQ_NATIVE_NO_DAEMON ?? '0';
  if (value !== '0' && value !== '1') throw new Error('DQ_NATIVE_NO_DAEMON must be 0 or 1.');
  return value === '1';
}
/** Native-only gates preserve internal failures instead of running DreamMaker. */
function nativeStrict(): boolean {
  const value = process.env.DQ_COMPILER_STRICT ?? '0';
  if (value !== '0' && value !== '1') throw new Error('DQ_COMPILER_STRICT must be 0 or 1.');
  return value === '1';
}
/** Include backend configuration and actual binaries in derived-build admission. */
export function compilerCacheIdentity(): string {
  const mode = compilerMode();
  if (mode === 'byond') return mode;
  const noDaemon = nativeNoDaemon();
  const strict = mode === 'native' && nativeStrict();
  const hash = createHash('sha256');
  hash.update(mode);
  for (const variable of ['DQ_NATIVE_COMPILER', 'DQ_NATIVE_ENGINE_TEMPLATE', 'DQ_DMB_INSPECT']) {
    const value = process.env[variable] ?? '';
    hash.update(variable);
    hash.update(value);
    if (value) {
      try { hash.update(fs.readFileSync(value)); }
      catch { hash.update('<unavailable>'); }
    }
  }
  hash.update(process.env.DQ_NATIVE_WORKERS ?? '8');
  // Unset and explicit zero preserve the existing default configuration identity.
  if (noDaemon) hash.update('DQ_NATIVE_NO_DAEMON=1');
  // A prior automatic BYOND fallback cannot satisfy a native-only request.
  if (strict) hash.update('DQ_COMPILER_STRICT=1');
  return hash.digest('hex');
}
function nativeCommand(dme: string, options: DreamMakerOptions, artifacts?: string, invocation?: CompilerInvocation): [string, string[]] {
  // The native CLI has no equivalent version selector. Never turn a successful
  // native process into silent policy loss. Warning policy maps to dmbc flags.
  const unsupported = [
    options.namedDmVersion != null ? 'namedDmVersion' : null,
  ].filter((value): value is string => value !== null);
  if (unsupported.length) {
    throw new Error(`Native compiler does not support requested DreamMaker options: ${unsupported.join(', ')}.`);
  }
  const configuredExecutable = process.env.DQ_NATIVE_COMPILER;
  const template = process.env.DQ_NATIVE_ENGINE_TEMPLATE;
  if (!configuredExecutable || !template) {
    throw new Error('Native compiler requires DQ_NATIVE_COMPILER and DQ_NATIVE_ENGINE_TEMPLATE.');
  }
  // Resolve path-bearing configuration in the caller's cwd, before the child
  // switches to its captured namespace. PATH commands stay explicitly unobserved.
  const executable = path.isAbsolute(configuredExecutable) || /[\\/]/.test(configuredExecutable)
    ? fs.realpathSync.native(path.resolve(configuredExecutable)) : configuredExecutable;
  const workers = process.env.DQ_NATIVE_WORKERS ?? '8';
  if (!/^[1-9][0-9]*$/.test(workers) || !Number.isSafeInteger(Number(workers))) {
    throw new Error('DQ_NATIVE_WORKERS must be a positive integer.');
  }
  // Existing stage events stream through Juke while the child is running, so
  // an external watchdog retains the last observed stage even without a result.
  const args = ['compile', invocation?.relativeManifest ?? path.resolve(dme), '--progress', '--engine-template', path.resolve(template), '--bootstrap-catalog', '--workers', workers];
  if (nativeNoDaemon()) args.push('--no-daemon');
  for (const define of options.defines ?? []) args.push(`-D${define}`);
  if (options.warningsAsErrors) args.push('--warnings-as-errors');
  for (const code of options.ignoreWarningCodes ?? []) args.push('--ignore-warning', code);
  if (artifacts) args.push('--artifact-directory', artifacts, '--output-store', path.join(artifacts, 'store'), '--record-inputs', path.join(artifacts, 'inputs'), '--exact-inputs', '--no-cache');
  return [executable, args];
}
class NativeResultError extends Error {}
const issuedNativeOutputs = new WeakMap<NativePairOutput, {
  configuration: NonNullable<NonNullable<NativePairOutput['publicationProof']>['target_configuration']> | undefined;
  compiler: Readonly<{ executable: string; sha256: string | null }>;
}>();
export function currentNativeTargetConfiguration(output: NativePairOutput) {
  const issued = issuedNativeOutputs.get(output);
  if (!issued) throw new Error('Native target configuration requires current compiler-issued output.');
  const { configuration, compiler } = issued;
  if (!configuration) throw new Error('Native output has no issued target configuration receipt.');
  if (!compiler.sha256 || observedExecutable(compiler.executable).sha256 !== compiler.sha256) {
    throw new Error('Native target configuration executable identity is unavailable or changed.');
  }
  return { configuration, compiler };
}
async function nativeCompile(dme: string, options: DreamMakerOptions, execute: CompilerExecutor, artifacts?: string, invocation?: CompilerInvocation): Promise<{ code: number | null; combined: string; signal?: string | null; output?: NativePairOutput }> {
  const [executable, args] = nativeCommand(dme, options, artifacts, invocation);
  const compilerIdentity = observedExecutable(executable);
  const owned = createNativeRequestDirectory('compile-result');
  const receipt = path.join(owned, 'result.json');
  args.push('--compile-result-file', receipt);
  if (!artifacts && process.env.DQ_NATIVE_OUTPUT_STORE) args.push('--output-store', path.resolve(process.env.DQ_NATIVE_OUTPUT_STORE));
  try {
    const result = await execute(executable, args, { throw: false, ...(invocation ? { cwd: invocation.root } : {}) });
    const currentIdentity = observedExecutable(executable);
    if (JSON.stringify(currentIdentity) !== JSON.stringify(compilerIdentity)) throw new NativeResultError('Native executable changed during compilation.');
    if (result.code !== 0 || result.signal) return result;
    const outputProject = artifacts ? path.join(artifacts, path.basename(invocation?.relativeManifest ?? dme)) : invocation ? path.join(invocation.root, invocation.relativeManifest) : dme;
    try {
      const output = parseCompileResult(readNativeResult(receipt), executable, outputProject);
      output.provenance = nativeProvenance(output, options.defines ?? [], compilerIdentity);
      issuedNativeOutputs.set(output, { configuration: output.publicationProof?.target_configuration, compiler: Object.freeze({ ...compilerIdentity }) });
      return { ...result, output };
    }
    catch (error) { throw new NativeResultError(`Native compile succeeded without an authenticated pair result: ${error}`); }
  } finally {
    // Housekeeping cannot turn a successful native publication into a second
    // compiler invocation. Preserve/report a cleanup limitation instead.
    try {
      try { fs.unlinkSync(receipt); } catch (error) { if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error; }
      fs.rmdirSync(owned);
    } catch (error) { Juke.logger.warn(`Native result cleanup preserved ${owned}: ${error}`); }
  }
}
function recordShadowCompileComparison(artifacts: string, native: CompileOutcome, byond: CompileOutcome, error?: unknown) {
  try {
    fs.writeFileSync(path.join(artifacts, 'shadow-compile-comparison.json'), JSON.stringify({
      schema: 1, requestedBackend: 'shadow', actualBackends: ['native', 'byond'],
      fallback: null, inputClosure: shadowSnapshotContract(), native, byond,
      buildExitAgrees: native.buildExit !== null && byond.buildExit !== null
        ? native.buildExit === byond.buildExit : null,
      diagnosticsAgree: native.diagnosticsCaptured && byond.diagnosticsCaptured
        ? JSON.stringify(native.diagnostics) === JSON.stringify(byond.diagnostics) : null,
      ...(error === undefined ? {} : { error: String(error) }),
    }, null, 2));
  } catch (reportError) {
    Juke.logger.warn(`Shadow compile report unavailable: ${reportError}`);
  }
}
export async function selectedCompiler(dme: string, options: DreamMakerOptions, byond: (capturedProject?: string, prepared?: PreparedDreamMaker, invocation?: CompilerInvocation) => Promise<ByondCompilationResult | void>, execute: CompilerExecutor = Juke.exec, prepareByond?: () => Promise<PreparedDreamMaker>, capturedInvocation?: CompilerInvocation): Promise<CompiledOutput> {
  const mode = compilerMode();
  const invocation = bindCompilerInvocation(capturedInvocation, options.defines ?? []);
  const outputProject = invocation ? path.join(invocation.root, invocation.relativeManifest) : dme;
  if (mode === 'byond') {
    const result = await byond(invocation?.relativeManifest, undefined, invocation);
    return { ...conventionalOutput(outputProject), provenance: byondProvenance(mode, options.defines ?? [], result) };
  }
  if (mode === 'native') {
    const strict = nativeStrict();
    const result = await nativeCompile(dme, options, execute, undefined, invocation);
    if (result.code === 0 && !result.signal) return result.output!;
    // Only the typed compiler internal failure status admits fallback.
    // Setup, transport, source, cancellation and infrastructure failures retain
    // their original error/status and never invoke another compiler.
    if (result.code !== 70 || result.signal) throw new Juke.ExitCode(result.code || 1, result.signal ?? null);
    if (strict) {
      Juke.logger.warn('Native compiler exited 70; DreamMaker fallback disabled by DQ_COMPILER_STRICT=1. Diagnostics are above.');
      throw new Juke.ExitCode(70, result.signal ?? null);
    }
    Juke.logger.warn('Native fallback to DreamMaker: native compiler exited 70; diagnostics are above.');
    const fallback = await byond(invocation?.relativeManifest, undefined, invocation);
    return { ...conventionalOutput(outputProject), provenance: byondProvenance(mode, options.defines ?? [], fallback, 'internal_error_70') };
  }
  // Validate native option admission before any BYOND version/preparation child.
  nativeCommand(dme, options, undefined, invocation);
  const preparedByond = prepareByond ? await prepareByond() : undefined;
  const root = path.resolve(process.env.DQ_SHADOW_ROOT ?? 'E:/dq-cache/dmb-shadow');
  fs.mkdirSync(root, { recursive: true });
  const artifacts = fs.mkdtempSync(path.join(root, 'shadow-'));
  const stem = path.basename(outputProject).replace(/\.dme$/i, '');
  const nativeDmb = path.join(artifacts, `${stem}.dmb`);
  const nativeRsc = path.join(artifacts, `${stem}.rsc`);
  try {
    // Native publishes into this private artifact namespace; DreamMaker retains
    // the captured manifest's conventional namespace. Inspect only owned copies.
    const native = await nativeCompile(dme, options, execute, artifacts, invocation);
    fs.writeFileSync(path.join(artifacts, 'native.log'), native.combined);
    // Cancellation ends the request before any comparison compiler or inspector.
    if (native.code === 75 || native.signal) throw new Juke.ExitCode(native.code || 1, native.signal ?? null);
    // Configuration is a prerequisite, not a source/resource closure proof.
    // Preserve rejection evidence even when the reference compiler later fails.
    let configurationPrerequisite;
    try {
      if (native.code !== 0 || !native.output) throw new Error('Native compilation issued no successful output configuration.');
      if (!preparedByond) throw new Error('DreamMaker preparation issued no configuration.');
      configurationPrerequisite = sharedCompilerConfiguration(preparedByond, options.defines ?? [], native.output);
    } catch (error) {
      configurationPrerequisite = { schema: 1, status: 'incomplete', inputClosureAuthenticated: false,
        nativeTargetProfileAuthenticated: false, reason: error instanceof Error ? error.message : String(error) };
    }
    fs.writeFileSync(path.join(artifacts, 'configuration-prerequisite.json'), JSON.stringify(configurationPrerequisite, null, 2));
    let byondResult: ByondCompilationResult | void;
    try {
      byondResult = await byond(invocation?.relativeManifest, preparedByond, invocation);
    } catch (error) {
      const reference = failedCompileOutcome(error);
      const candidate = observedCompileOutcome(native.code, native.combined, native.code, native.signal ?? null);
      // This evidence is diagnostic only. Preserve the exact original failure,
      // even if report publication itself is unavailable.
      recordShadowCompileComparison(artifacts, candidate, reference, error);
      throw error;
    }
    if (native.code !== 0) {
      const reference = (byondResult ? byondResult.outcome : undefined) ?? failedCompileOutcome(undefined);
      recordShadowCompileComparison(artifacts, observedCompileOutcome(native.code, native.combined, native.code, native.signal ?? null), reference);
      Juke.logger.error(`Shadow compiler disagreement: native exited ${native.code}, DreamMaker succeeded. See ${artifacts}.`);
      throw new Juke.ExitCode(1);
    }
    const byondOutput = captureShadowOutputPair(path.resolve(outputProject), artifacts);
    fs.writeFileSync(path.join(artifacts, 'byond-output-capture.json'), JSON.stringify(byondOutput.proof, null, 2));
    const inspector = process.env.DQ_DMB_INSPECT;
    if (!inspector) throw new Error('Shadow mode requires DQ_DMB_INSPECT for named per-procedure comparison.');
    return await withCompiledOutput(native.output!, execute, async acquiredDmb => {
      const acquiredRsc = acquiredDmb.replace(/\.dmb$/i, '.rsc');
      const report = path.join(artifacts, 'structural-diff.json');
      const expected = byondOutput.dmb;
      // A comparison label identifies this evidence, never proves both compilers
      // consumed the same complete source/resource snapshot. DreamMaker currently
      // returns no authenticated read roster or effective-version receipt.
      const comparisonContext = {
        schema: 'unverified-shadow-comparison-context-v1',
        // Core-issued native observed-demand evidence stays explicitly narrower
        // than shared source/resource closure and cannot admit shadow parity.
        nativeResourceJournalAdmission: native.output!.publicationProof?.resource_journal_admission ?? null,
        project: path.resolve(outputProject), manifestSha256: createHash('sha256').update(fs.readFileSync(outputProject)).digest('hex'),
        capturedInvocation: invocation ?? null,
        requestedDefines: options.defines ?? [], requestedNamedDmVersion: options.namedDmVersion ?? null,
        requestedWarningsAsErrors: options.warningsAsErrors ?? false,
        requestedIgnoredWarningCodes: options.ignoreWarningCodes ?? [],
        nativeCompilerIdentity: compilerCacheIdentity(),
        expectedDmbSha256: createHash('sha256').update(fs.readFileSync(expected)).digest('hex'),
        nativeDmbSha256: createHash('sha256').update(fs.readFileSync(acquiredDmb)).digest('hex'),
      };
      const sourceSnapshot = shadowSnapshotContract();
      const snapshot = createHash('sha256').update(JSON.stringify(comparisonContext)).digest('hex');
      // Invocation metadata is useful evidence but cannot issue snapshot authority.
      // Even a supplied future receipt needs an authenticated producer/consumer
      // protocol before admission; no callback boolean or cast is trusted here.
      fs.writeFileSync(path.join(artifacts, 'source-snapshot-contract.json'), JSON.stringify({ comparisonContext, comparisonLabel: snapshot, sourceSnapshot, configurationPrerequisite, preparedByondCompiler: preparedByond ?? null, byondInvocation: byondResult ? byondResult.invocation : null }, null, 2));
      const inspected = await execute(inspector, ['structural-diff', expected, acquiredDmb, report, snapshot], { throw: false });
      if (inspected.code !== 0) {
        Juke.logger.error(`Shadow comparison failed: inspector exited ${inspected.code}. See ${artifacts}.`);
        throw new Juke.ExitCode(1);
      }
      const resourceReport = path.join(artifacts, 'resource-diff.json');
      const resourceCompared = await execute(inspector, ['rsc-diff', byondOutput.rsc, acquiredRsc, resourceReport, snapshot], { throw: false });
      let resourceAdmission: ReturnType<typeof classifyResourceReport>;
      if (resourceCompared.code !== 0) {
        resourceAdmission = { status: 'incomplete', reason: `resource inspector failed or exceeded its 32MiB entry bound (${resourceCompared.code})` };
      } else {
        try { resourceAdmission = classifyResourceReport(JSON.parse(fs.readFileSync(resourceReport, 'utf8')), snapshot); }
        catch (error) { resourceAdmission = { status: 'invalid_report', reason: String(error) }; }
      }
      fs.writeFileSync(path.join(artifacts, 'resource-admission.json'), JSON.stringify(resourceAdmission, null, 2));
      let admission: ShadowAdmission;
      try { admission = classifyShadowReport(JSON.parse(fs.readFileSync(report, 'utf8')), snapshot); }
      catch (error) { admission = { status: 'invalid_report', reason: String(error) }; }
      const structuralAdmission = admission;
      if (admission.status === 'parity' && resourceAdmission.status !== 'parity') admission = resourceAdmission;
      if (admission.status === 'parity') admission = sourceSnapshot;
      fs.writeFileSync(path.join(artifacts, 'structural-admission.json'), JSON.stringify({ ...admission, structuralAdmission, resourceAdmission, sourceSnapshot, outputCapture: byondOutput.proof }, null, 2));
      if (admission.status !== 'parity') {
        Juke.logger.error(`Shadow ${admission.status}: ${admission.reason}. See ${report}.`);
        throw new Juke.ExitCode(1);
      }
      Juke.logger.info(`Shadow structural parity: ${report}`);
      return { ...conventionalOutput(outputProject), provenance: byondProvenance(mode, options.defines ?? [], byondResult) };
    });
  } finally {
    // Preserve small diagnostics/receipts, remove only this invocation's bulky outputs.
    const store = path.resolve(artifacts, 'store');
    if (path.dirname(store) === path.resolve(artifacts) && path.dirname(path.resolve(artifacts)) === root) {
      try { fs.rmSync(store, { recursive: true, force: true }); }
      catch (error) { Juke.logger.warn(`Shadow store cleanup: ${store}: ${error}`); }
    }
    for (const file of [nativeDmb, nativeRsc, path.join(artifacts, 'byond-captured.dmb'), path.join(artifacts, 'byond-captured.rsc')]) {
      try { if (fs.existsSync(file)) fs.chmodSync(file, 0o666); fs.unlinkSync(file); } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== 'ENOENT') Juke.logger.warn(`Shadow cleanup: ${file}: ${error}`);
      }
    }
  }
}
