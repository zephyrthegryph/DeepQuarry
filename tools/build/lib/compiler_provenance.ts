/** Observed compilation metadata; this does not certify a complete input closure. */
import fs from 'node:fs';
import path from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import type { ByondCompilationResult } from './byond';
import type { CompiledOutput, PairIdentity } from './native_pair';

export type CompilerProvenance = {
  requestedBackend: 'byond' | 'native' | 'shadow';
  actualBackend: 'byond' | 'native';
  compiler: { executable: string | null; sha256: string | null; version: number | null; build: number | null };
  orderedDefines: readonly string[];
  fallback: 'internal_error_70' | null;
  nativePair: PairIdentity | null;
};

export function observedExecutable(executable: string): { executable: string; sha256: string | null } {
  if (!path.isAbsolute(executable) && !/[\\/]/.test(executable)) return { executable, sha256: null };
  const resolved = fs.realpathSync.native(path.resolve(executable));
  return { executable: resolved, sha256: createHash('sha256').update(fs.readFileSync(resolved)).digest('hex') };
}

export function byondProvenance(requestedBackend: CompilerProvenance['requestedBackend'], defines: readonly string[], result: ByondCompilationResult | void, fallback: CompilerProvenance['fallback'] = null): CompilerProvenance {
  const invocation = result ? result.invocation : undefined;
  const identity = invocation?.compilerIdentity;
  return { requestedBackend, actualBackend: 'byond', orderedDefines: [...defines], fallback, nativePair: null,
    compiler: { executable: identity?.executable ?? invocation?.command[0] ?? null,
      sha256: identity?.status === 'observed' ? identity.sha256 : null,
      version: invocation?.version ?? null, build: invocation?.build ?? null } };
}

export function nativeProvenance(output: CompiledOutput, defines: readonly string[], identity: ReturnType<typeof observedExecutable>): CompilerProvenance {
  if (output.kind !== 'native_pair') throw new Error('Native provenance requires a native pair.');
  return { requestedBackend: 'native', actualBackend: 'native', orderedDefines: [...defines], fallback: null,
    // Native executable version is not issued by the pair receipt; do not substitute target BYOND version.
    compiler: { ...identity, version: null, build: null },
    nativePair: { pairId: output.pairId, dmbHash: output.dmbHash, rscHash: output.rscHash, dmbBytes: output.dmbBytes, rscBytes: output.rscBytes } };
}

export class CompilerProvenanceError extends Error {}

/** Persistent attempt evidence survives missing test results or a failed boot.
 * Atomic file replacement, not a filesystem crash durability guarantee. */
export function beginCompilerReceipt(directory: string, output: CompiledOutput) {
  const compilation = output.provenance ?? null;
  if (compilation) {
    if (compilation.actualBackend !== (output.kind === 'native_pair' ? 'native' : 'byond')) {
      throw new CompilerProvenanceError('Actual compiler provenance disagrees with compiled output.');
    }
    if (output.kind === 'native_pair') {
      for (const field of ['pairId', 'dmbHash', 'rscHash', 'dmbBytes', 'rscBytes'] as const) {
        if (compilation.nativePair?.[field] !== output[field]) {
          throw new CompilerProvenanceError(`Compiler provenance disagrees with acquired pair: ${field}.`);
        }
      }
    }
  }
  fs.mkdirSync(directory, { recursive: true });
  const file = path.resolve(directory, `compiler-${randomUUID()}.json`);
  const receipt = { schema_version: 1, compilation,
    actual_backend: output.kind === 'native_pair' ? 'native' : 'byond',
    pair: output.kind === 'native_pair' ? {
      pairId: output.pairId, dmbHash: output.dmbHash, rscHash: output.rscHash,
      dmbBytes: output.dmbBytes, rscBytes: output.rscBytes,
    } : null,
    created_at: new Date().toISOString(), prepared_at: null as string | null,
    hosted_dmb: null as string | null, finalized_at: null as string | null,
    runtime: null as { resultsAvailable: boolean; killedByWatchdog: boolean; error: string | null } | null,
  };
  const persist = () => {
    const temporary = `${file}.${randomUUID()}.tmp`;
    try {
      fs.writeFileSync(temporary, `${JSON.stringify(receipt, null, 2)}\n`, { flag: 'wx' });
      fs.renameSync(temporary, file);
    } catch (error) {
      throw new CompilerProvenanceError(`Cannot persist compiler attempt evidence: ${error}`);
    }
  };
  persist();
  return { file,
    prepared(dmb: string) {
      receipt.hosted_dmb = path.resolve(dmb);
      receipt.prepared_at = new Date().toISOString();
      persist();
    },
    finalize(runtime: NonNullable<typeof receipt.runtime>) {
      receipt.runtime = runtime;
      receipt.finalized_at = new Date().toISOString();
      persist();
    },
  };
}
