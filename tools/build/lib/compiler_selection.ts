/** One build entry point for BYOND, native compilation and isolated shadow checks. */
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import Juke from '../juke/index.js';
import type { ByondCompilationResult, DreamMakerOptions } from './byond';

type CompilerMode = 'byond' | 'native' | 'shadow';
const structuralCategories = ['type_set', 'type_headers', 'variable_defaults', 'procedure_table', 'procedure_flags', 'globals', 'strings_by_use', 'bytecode', 'other'];
export type ShadowAdmission = { status: 'parity' | 'invalid_report' | 'incomplete' | 'differences'; reason: string };
/** Current DreamMaker adapter issues no authenticated compilation-input receipt. */
export function shadowSnapshotContract(): { status: 'incomplete'; reason: string } {
  return { status: 'incomplete', reason: 'DreamMaker callback supplies no authenticated source/resource closure or effective compiler configuration receipt; shared compilation snapshot is unproven' };
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
export type CompilerExecutor = (executable: string, args: string[], options?: { throw?: boolean }) => Promise<{ code: number | null; combined: string }>;
export function compilerMode(): CompilerMode {
  const mode = process.env.DQ_COMPILER ?? 'byond';
  if (mode !== 'byond' && mode !== 'native' && mode !== 'shadow') {
    throw new Error(`Unknown DQ_COMPILER=${mode}; expected byond, native or shadow.`);
  }
  return mode;
}
/** Include backend configuration and actual binaries in derived-build admission. */
export function compilerCacheIdentity(): string {
  const mode = compilerMode();
  if (mode === 'byond') return mode;
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
  return hash.digest('hex');
}
function nativeCommand(dme: string, options: DreamMakerOptions, artifacts?: string): [string, string[]] {
  const executable = process.env.DQ_NATIVE_COMPILER;
  const template = process.env.DQ_NATIVE_ENGINE_TEMPLATE;
  if (!executable || !template) {
    throw new Error('Native compiler requires DQ_NATIVE_COMPILER and DQ_NATIVE_ENGINE_TEMPLATE.');
  }
  const workers = process.env.DQ_NATIVE_WORKERS ?? '8';
  if (!/^[1-9][0-9]*$/.test(workers) || !Number.isSafeInteger(Number(workers))) {
    throw new Error('DQ_NATIVE_WORKERS must be a positive integer.');
  }
  const args = ['compile', path.resolve(dme), '--engine-template', path.resolve(template), '--bootstrap-catalog', '--workers', workers];
  for (const define of options.defines ?? []) args.push(`-D${define}`);
  if (artifacts) args.push('--artifact-directory', artifacts, '--output-store', path.join(artifacts, 'store'), '--exact-inputs', '--no-cache');
  return [executable, args];
}
async function nativeCompile(dme: string, options: DreamMakerOptions, execute: CompilerExecutor, artifacts?: string): Promise<{ code: number | null; combined: string }> {
  const [executable, args] = nativeCommand(dme, options, artifacts);
  return execute(executable, args, { throw: false });
}
export async function selectedCompiler(dme: string, options: DreamMakerOptions, byond: (capturedProject?: string) => Promise<ByondCompilationResult | void>, execute: CompilerExecutor = Juke.exec): Promise<void> {
  const mode = compilerMode();
  if (mode === 'byond') { await byond(); return; }
  if (mode === 'native') {
    let reason: string;
    try {
      const result = await nativeCompile(dme, options, execute);
      if (result.code === 0) return;
      // Typed CLI source and cancellation errors must never invoke another compiler.
      if (result.code === 2 || result.code === 75) throw new Juke.ExitCode(result.code);
      if (result.code !== 1 && result.code !== 70) throw new Juke.ExitCode(result.code ?? 1);
      reason = `native compiler exited ${result.code}; diagnostics are above`;
    } catch (error) {
      if (error instanceof Juke.ExitCode) throw error;
      reason = String(error);
    }
    // Explicit internal/unsupported and infrastructure failure statuses allow fallback.
    Juke.logger.warn(`Native fallback to DreamMaker: ${reason}.`);
    await byond();
    return;
  }
  const root = path.resolve(process.env.DQ_SHADOW_ROOT ?? 'E:/dq-cache/dmb-shadow');
  fs.mkdirSync(root, { recursive: true });
  const artifacts = fs.mkdtempSync(path.join(root, 'shadow-'));
  const stem = path.basename(dme).replace(/\.dme$/i, '');
  const nativeDmb = path.join(artifacts, `${stem}.dmb`);
  const nativeRsc = path.join(artifacts, `${stem}.rsc`);
  try {
    const native = await nativeCompile(dme, options, execute, artifacts);
    fs.writeFileSync(path.join(artifacts, 'native.log'), native.combined);
    const byondResult = await byond();
    if (native.code !== 0) {
      Juke.logger.error(`Shadow compiler disagreement: native exited ${native.code}, DreamMaker succeeded. See ${artifacts}.`);
      throw new Juke.ExitCode(1);
    }
    const inspector = process.env.DQ_DMB_INSPECT;
    if (!inspector) throw new Error('Shadow mode requires DQ_DMB_INSPECT for named per-procedure comparison.');
    const report = path.join(artifacts, 'structural-diff.json');
    const expected = path.resolve(dme.replace(/\.dme$/i, '.dmb'));
    // A comparison label identifies this evidence, never proves both compilers
    // consumed the same complete source/resource snapshot. DreamMaker currently
    // returns no authenticated read roster or effective-version receipt.
    const comparisonContext = {
      schema: 'unverified-shadow-comparison-context-v1',
      project: path.resolve(dme), manifestSha256: createHash('sha256').update(fs.readFileSync(dme)).digest('hex'),
      requestedDefines: options.defines ?? [], requestedNamedDmVersion: options.namedDmVersion ?? null,
      requestedWarningsAsErrors: options.warningsAsErrors ?? false,
      requestedIgnoredWarningCodes: options.ignoreWarningCodes ?? [],
      nativeCompilerIdentity: compilerCacheIdentity(),
      expectedDmbSha256: createHash('sha256').update(fs.readFileSync(expected)).digest('hex'),
      nativeDmbSha256: createHash('sha256').update(fs.readFileSync(nativeDmb)).digest('hex'),
    };
    const sourceSnapshot = shadowSnapshotContract();
    const snapshot = createHash('sha256').update(JSON.stringify(comparisonContext)).digest('hex');
    // Invocation metadata is useful evidence but cannot issue snapshot authority.
    // Even a supplied future receipt needs an authenticated producer/consumer
    // protocol before admission; no callback boolean or cast is trusted here.
    fs.writeFileSync(path.join(artifacts, 'source-snapshot-contract.json'), JSON.stringify({ comparisonContext, comparisonLabel: snapshot, sourceSnapshot, byondInvocation: byondResult ? byondResult.invocation : null }, null, 2));
    const inspected = await execute(inspector, ['structural-diff', expected, nativeDmb, report, snapshot], { throw: false });
    if (inspected.code !== 0) {
      Juke.logger.error(`Shadow comparison failed: inspector exited ${inspected.code}. See ${artifacts}.`);
      throw new Juke.ExitCode(1);
    }
    let admission: ShadowAdmission;
    try { admission = classifyShadowReport(JSON.parse(fs.readFileSync(report, 'utf8')), snapshot); }
    catch (error) { admission = { status: 'invalid_report', reason: String(error) }; }
    const structuralAdmission = admission;
    if (admission.status === 'parity') admission = sourceSnapshot;
    fs.writeFileSync(path.join(artifacts, 'structural-admission.json'), JSON.stringify({ ...admission, structuralAdmission, sourceSnapshot }, null, 2));
    if (admission.status !== 'parity') {
      Juke.logger.error(`Shadow ${admission.status}: ${admission.reason}. See ${report}.`);
      throw new Juke.ExitCode(1);
    }
    Juke.logger.info(`Shadow structural parity: ${report}`);
  } finally {
    // Preserve small diagnostics/receipts, remove only this invocation's bulky outputs.
    const store = path.resolve(artifacts, 'store');
    if (path.dirname(store) === path.resolve(artifacts) && path.dirname(path.resolve(artifacts)) === root) {
      try { fs.rmSync(store, { recursive: true, force: true }); }
      catch (error) { Juke.logger.warn(`Shadow store cleanup: ${store}: ${error}`); }
    }
    for (const file of [nativeDmb, nativeRsc]) {
      try { fs.unlinkSync(file); } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== 'ENOENT') Juke.logger.warn(`Shadow cleanup: ${file}: ${error}`);
      }
    }
  }
}
