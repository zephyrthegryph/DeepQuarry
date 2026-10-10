/** Exact compiler configuration contribution to a derived build cache key. */
import type { Hash } from 'node:crypto';

export function updateDerivedCompileConfiguration(
  hash: Pick<Hash, 'update'>,
  defines: readonly string[],
  dmVersion: string | null,
  compilerIdentity: string,
): void {
  // Preserve duplicate definitions and their order, matching actual -D arguments.
  hash.update(JSON.stringify(defines));
  hash.update(dmVersion ?? '');
  hash.update(compilerIdentity);
}
