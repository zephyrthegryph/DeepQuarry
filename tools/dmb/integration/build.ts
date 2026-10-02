import fs from 'node:fs';
import path from 'node:path';
import Juke from '../../build/juke/index.js';
import { canFallback, compilerMode, integrationArguments } from './policy';

type Options = {
  defines?: string[];
  warningsAsErrors?: boolean;
  ignoreWarningCodes?: string[];
};
export type NativeFallback = { kind: 'internal'; reason: string };

function reportFallback(project: string, fallback: NativeFallback, ok: boolean): void {
  const destination = path.join(path.dirname(project), '.dm-native', path.basename(project), 'integration.json');
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.writeFileSync(destination, `${JSON.stringify({ version: 1, mode: 'native', selected_backend: 'byond', producing_compiler: ok ? 'byond' : null, native_gate_passed: false, ok, fallback })}\n`);
}

/** A missing executable is a proven infrastructure failure. Source failures from
 * the native process are handled there and never trigger an adapter fallback. */
export async function nativeDreamMaker(
  project: string,
  byond: string,
  options: Options,
): Promise<{ handled: boolean; fallback?: NativeFallback }> {
  const mode = compilerMode(process.env.DQ_COMPILER);
  if (mode === 'byond') return { handled: false };
  const strict = process.env.DQ_COMPILER_STRICT === '1';
  const suffix = process.platform === 'win32' ? '.exe' : '';
  const candidates = process.env.DQ_NATIVE_COMPILER
    ? [process.env.DQ_NATIVE_COMPILER]
    : [`tools/dmb/target/release/dm-compile${suffix}`, `tools/dmb/target/debug/dm-compile${suffix}`];
  const compiler = candidates.find((candidate) => fs.existsSync(candidate) && fs.statSync(candidate).isFile());
  if (!compiler) {
    const reason = `native compiler executable is missing (${candidates.join(', ')})`;
    if (mode === 'native' && canFallback('internal', strict)) {
      Juke.logger.warn(`${project}:1:warning: ${reason}; using BYOND`);
      const fallback: NativeFallback = { kind: 'internal', reason };
      reportFallback(project, fallback, false);
      return { handled: false, fallback };
    }
    Juke.logger.error(`${project}:1:error: ${reason}`);
    throw new Juke.ExitCode(1);
  }
  const args = integrationArguments(project, mode, byond,
    process.env.DQ_NATIVE_BUILTINS ?? 'tools/dmb/fixtures/native_template.bin',
    options.defines ?? [], process.env.DQ_NATIVE_DAEMON);
  const result = await Juke.exec(compiler, args, { throw: false });
  if (result.code !== 0) throw new Juke.ExitCode(result.code ?? 1);
  if (options.warningsAsErrors) {
    const ignored = options.ignoreWarningCodes ?? [];
    const warnings = result.combined.split(/\r?\n/).filter((line) => /\d+:warning(?: \([a-z_]*\))?:/.test(line));
    if (warnings.some((line) => !ignored.some((code) => line.includes(code)))) {
      Juke.logger.error('Compile warnings treated as errors');
      throw new Juke.ExitCode(2);
    }
  }
  return { handled: true };
}

export function completeNativeFallback(project: string, fallback: NativeFallback): void {
  reportFallback(project, fallback, true);
}
