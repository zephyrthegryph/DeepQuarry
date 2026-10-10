/** Invocation configuration only; this does not certify filesystem containment. */
import path from 'node:path';
export type CompilerInvocation = Readonly<{
  root: string;
  relativeManifest: string;
  orderedDefines: readonly string[];
}>;
export function compilerInvocation(root: string, relativeManifest: string, orderedDefines: readonly string[]): CompilerInvocation {
  if (!path.isAbsolute(root) || !relativeManifest || path.isAbsolute(relativeManifest)
    || /^[A-Za-z]:/.test(relativeManifest)
    || relativeManifest.split(/[\\/]/).some(part => !part || part === '.' || part === '..')) {
    throw new Error('Captured invocation requires an absolute root and normal contained relative manifest.');
  }
  return Object.freeze({ root: path.resolve(root), relativeManifest, orderedDefines: Object.freeze([...orderedDefines]) });
}
export function bindCompilerInvocation(invocation: CompilerInvocation | undefined, defines: readonly string[]) {
  if (!invocation) return undefined;
  const bound = compilerInvocation(invocation.root, invocation.relativeManifest, invocation.orderedDefines);
  if (JSON.stringify(bound.orderedDefines) !== JSON.stringify(defines)) throw new Error('Captured invocation ordered defines differ from compilation request.');
  return bound;
}
