export type CompilerMode = 'byond' | 'native' | 'shadow';
export type FailureKind = 'source' | 'internal' | 'configuration' | 'comparison';

export function compilerMode(value: string | undefined): CompilerMode {
  const mode = value ?? 'byond';
  if (mode !== 'byond' && mode !== 'native' && mode !== 'shadow') {
    throw new Error(`DQ_COMPILER must be byond, native, or shadow; got ${JSON.stringify(mode)}`);
  }
  return mode;
}

export function canFallback(kind: FailureKind, strict: boolean): boolean {
  return kind === 'internal' && !strict;
}

export function integrationArguments(
  project: string,
  mode: CompilerMode,
  byond: string,
  builtins: string,
  defines: readonly string[],
  daemon?: string,
): string[] {
  return [
    'integrated-build', project, '--mode', mode, '--byond', byond,
    '--builtins', builtins, ...(daemon ? ['--daemon', daemon] : []),
    ...defines.map((define) => `-D${define}`),
  ];
}
