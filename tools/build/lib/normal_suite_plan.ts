/** Pure planning over an inventory issued by the compiled runtime.
 * This module neither discovers tests nor authenticates the compiler receipt.
 * The caller must bind inventory and all batches to the same CompiledOutput.
 */
export type IssuedNormalInventory = {
  schema: 1;
  tier: 'normal';
  eligible: string[];
  automaticRows: string[];
  excluded: { name: string; reason: 'abstract' | 'focus_only' | 'exhaustive' }[];
};

export function normalSuiteBatches(inventory: IssuedNormalInventory, batchSize: number): string[][] {
  if (inventory.schema !== 1 || inventory.tier !== 'normal') throw new Error('unsupported runtime inventory');
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 32) throw new Error('batch size must be1..32');
  const seen = new Set<string>();
  for (const name of inventory.eligible) {
    if (!name.startsWith('/datum/unit_test/') || seen.has(name)) throw new Error(`invalid/duplicate eligible test: ${name}`);
    seen.add(name);
  }
  if (seen.size === 0) throw new Error('runtime issued an empty normal inventory');
  for (const row of inventory.excluded) {
    if (!row.name.startsWith('/datum/unit_test/') || seen.has(row.name)
      || !['abstract', 'focus_only', 'exhaustive'].includes(row.reason)) throw new Error('invalid/overlapping exclusion');
    seen.add(row.name);
  }
  for (const name of inventory.automaticRows) {
    if (!name || seen.has(name)) throw new Error('invalid/overlapping automatic row');
    seen.add(name);
  }
  const batches: string[][] = [];
  for (let start = 0; start < inventory.eligible.length; start += batchSize) {
    batches.push(inventory.eligible.slice(start, start + batchSize));
  }
  return batches;
}

export type BatchRows<T> = { requested: readonly string[]; results: Record<string, T> | null };

/** Preserve each original result. Missing, extra or repeated rows cannot pass.
 * Runtime-declared automatic rows are separate and required exactly per world.
 */
export function exactNormalUnion<T>(inventory: IssuedNormalInventory, batches: readonly BatchRows<T>[]): {
  tests: Record<string, T>; frameworkFindings: T[];
} {
  normalSuiteBatches(inventory, 1);
  const expected = new Set(inventory.eligible);
  const requested = new Set<string>();
  const tests: Record<string, T> = Object.create(null);
  const frameworkFindings: T[] = [];
  for (const batch of batches) {
    if (!batch.results) throw new Error('batch has no final results');
    const names = new Set(batch.requested);
    if (names.size !== batch.requested.length || names.size === 0) throw new Error('duplicate/empty batch request');
    for (const name of names) {
      if (!expected.has(name) || requested.has(name)) throw new Error(`unexpected/duplicate requested test: ${name}`);
      requested.add(name);
      if (!Object.prototype.hasOwnProperty.call(batch.results, name)) throw new Error(`missing result: ${name}`);
      tests[name] = batch.results[name];
    }
    for (const name of inventory.automaticRows) {
      if (!Object.prototype.hasOwnProperty.call(batch.results, name)) throw new Error(`missing automatic result: ${name}`);
    }
    for (const [name, result] of Object.entries(batch.results)) {
      if (inventory.automaticRows.includes(name)) frameworkFindings.push(result);
      else if (!names.has(name)) throw new Error(`unexpected result: ${name}`);
    }
  }
  if (requested.size !== expected.size) throw new Error('normal inventory union incomplete');
  return { tests, frameworkFindings };
}

/** Admit a previously runtime-issued plan only against today's full runtime roster. */
export function bindNormalPlan(current: IssuedNormalInventory, previous: IssuedNormalInventory): IssuedNormalInventory {
  normalSuiteBatches(current, 1); normalSuiteBatches(previous, 1);
  const sameSet = (a: string[], b: string[]) => a.length === b.length && a.every(name => b.includes(name));
  if (!sameSet(current.eligible, previous.eligible) || !sameSet(current.automaticRows, previous.automaticRows)) {
    throw new Error('captured normal plan does not match current runtime inventory');
  }
  return { ...current, eligible: [...previous.eligible], automaticRows: [...previous.automaticRows] };
}

export type RuntimeIdentity = {
  executable: string; sha256: string; version: null; security: string;
  library?: { source: string; hosted: string; sha256: string; bytes: number };
};

/** Slot placement is evidence, while library source/content are stable inputs. */
export function sameSuiteRuntime(left: RuntimeIdentity | undefined, right: RuntimeIdentity | undefined): boolean {
  if (!left || !right) return false;
  const stable = (value: RuntimeIdentity) => ({ executable: value.executable, sha256: value.sha256,
    version: value.version, security: value.security, library: value.library ? {
      source: value.library.source, sha256: value.library.sha256, bytes: value.library.bytes,
    } : null });
  return JSON.stringify(stable(left)) === JSON.stringify(stable(right));
}

/** Invalid producer rows fail closed; preserved runtime counts also fail success. */
export function suiteRowSucceeded(row: { status: number; runtimes?: number }): boolean {
  if (!row || ![0, 1, 2].includes(row.status)) throw new Error('invalid unit-test status');
  if (row.runtimes !== undefined && (!Number.isInteger(row.runtimes) || row.runtimes < 0)) throw new Error('invalid unit-test runtime count');
  return row.status !== 1 && (row.runtimes ?? 0) === 0;
}
