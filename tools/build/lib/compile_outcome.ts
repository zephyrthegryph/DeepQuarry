/** Exact observed compiler output; not a source-closure or parity certificate. */
import Juke from '../juke/index.js';
export type CompileOutcome = {
  processExit: number | null;
  signal: string | null;
  buildExit: number | null;
  diagnosticsCaptured: boolean;
  output: string | null;
  diagnostics: string[];
};
export function observedCompileOutcome(processExit: number | null, output: string, buildExit = processExit, signal: string | null = null): CompileOutcome {
  return { processExit, buildExit, signal, diagnosticsCaptured: true, output,
    diagnostics: output.split(/\r?\n/).filter(line => /:\d+:(?:error|warning)(?: \([^)]*\))?:/.test(line)) };
}
export class ByondCompileFailure extends Juke.ExitCode {
  readonly outcome: CompileOutcome;
  constructor(code: number | null, outcome: CompileOutcome, signal: string | null = null) { super(code, signal); this.outcome = outcome; }
}
export function failedCompileOutcome(error: unknown): CompileOutcome {
  if (error instanceof ByondCompileFailure) return error.outcome;
  return { processExit: null, signal: error instanceof Juke.ExitCode ? error.signal : null, buildExit: error instanceof Juke.ExitCode ? error.code : null,
    diagnosticsCaptured: false, output: null, diagnostics: [] };
}
