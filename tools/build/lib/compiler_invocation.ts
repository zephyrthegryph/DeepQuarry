/** Invocation configuration only; this does not certify filesystem containment. */
import path from 'node:path';
export type CompilerInvocation = Readonly<{
  root: string;
  relativeManifest: string;
  orderedDefines: readonly string[];
}>;
export function compilerInvocation(root: string, relativeManifest: string, orderedDefines: readonly string[]): CompilerInvocation {
  if (!path.isAbsolute(root) || !relativeManifest || path.isAbsolute(relativeManifest)
    // A colon anywhere in a Windows relative name can select an alternate data
    // stream. NUL is rejected by filesystem APIs, but must fail before a child
    // is launched so all backends receive the same invocation contract.
    || /[:\0]/.test(relativeManifest) || root.includes('\0')
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
