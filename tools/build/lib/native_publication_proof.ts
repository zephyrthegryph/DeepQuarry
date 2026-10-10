/** Native admission metadata only; this does not establish BYOND input access. */
import path from 'node:path';

export type NativePublicationProof = {
  schema_version: 1;
  kind: 'native_publication_inputs';
  native_inputs_admitted: true;
  shared_input_closure_complete: false;
  pair_id: string;
  document: string;
  document_bytes: number;
  document_xxh3_128: string;
  snapshot_bytes: number;
  snapshot_xxh3_128: string;
};

/** Validate the issued reference, without replacing the Rust admission path. */
export function parseNativePublicationProof(value: unknown, pairId: string, store: string): NativePublicationProof | undefined {
  if (value === undefined) return undefined;
  if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid native publication proof.');
  const proof = value as Record<string, unknown>;
  if (proof.schema_version !== 1 || proof.kind !== 'native_publication_inputs'
      || proof.native_inputs_admitted !== true || proof.shared_input_closure_complete !== false
      || proof.pair_id !== pairId) throw new Error('Native publication proof scope or generation differs.');
  for (const field of ['document_xxh3_128', 'snapshot_xxh3_128']) {
    if (typeof proof[field] !== 'string' || !/^[0-9a-f]{32}$/.test(proof[field] as string)) throw new Error(`Invalid native publication proof ${field}.`);
  }
  for (const field of ['document_bytes', 'snapshot_bytes']) {
    if (typeof proof[field] !== 'number' || !Number.isSafeInteger(proof[field]) || (proof[field] as number) <= 0) throw new Error(`Invalid native publication proof ${field}.`);
  }
  if (typeof proof.document !== 'string' || !path.isAbsolute(proof.document)) throw new Error('Native publication proof path must be absolute.');
  const document = path.resolve(proof.document);
  const expected = path.resolve(store, 'publication-proofs');
  const normalize = (file: string) => process.platform === 'win32' ? file.toLowerCase() : file;
  if (normalize(path.dirname(document)) !== normalize(expected)) throw new Error('Native publication proof escaped its store.');
  return { schema_version: 1, kind: 'native_publication_inputs', native_inputs_admitted: true,
    shared_input_closure_complete: false, pair_id: pairId, document,
    document_bytes: proof.document_bytes as number, document_xxh3_128: proof.document_xxh3_128 as string,
    snapshot_bytes: proof.snapshot_bytes as number, snapshot_xxh3_128: proof.snapshot_xxh3_128 as string };
}
