/** Native admission metadata only; this does not establish BYOND input access. */
import path from 'node:path';
export type NativeTargetConfiguration = {
  schema_version: 1; version: 516; build: 1687; engine_template_sha256: string;
  effective_defines: Readonly<Record<string, string>>; implicit_predefines_complete: false;
};

export type NativePublicationProof = {
  target_configuration?: NativeTargetConfiguration;
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
  let target: NativeTargetConfiguration | undefined;
  if (proof.target_configuration !== undefined) {
    const config = proof.target_configuration as Record<string, unknown>;
    if (!config || typeof config !== 'object' || Array.isArray(config)
        || config.schema_version !== 1 || config.version !== 516 || config.build !== 1687
        || config.implicit_predefines_complete !== false
        || typeof config.engine_template_sha256 !== 'string' || !/^[0-9a-f]{64}$/.test(config.engine_template_sha256)
        || !config.effective_defines || typeof config.effective_defines !== 'object' || Array.isArray(config.effective_defines)
        || Object.entries(config.effective_defines).some(([name, value]) => !/^[A-Za-z_][A-Za-z0-9_]*$/.test(name) || typeof value !== 'string')) {
      throw new Error('Invalid native target configuration receipt.');
    }
    const defines = config.effective_defines as Record<string, string>;
    if (defines.DM_VERSION !== '516' || defines.DM_BUILD !== '1687') throw new Error('Native target version defines disagree.');
    target = Object.freeze({ schema_version: 1, version: 516, build: 1687,
      engine_template_sha256: config.engine_template_sha256, effective_defines: Object.freeze({ ...defines }), implicit_predefines_complete: false });
  }
  return { schema_version: 1, kind: 'native_publication_inputs', native_inputs_admitted: true,
    ...(target ? { target_configuration: target } : {}),
    shared_input_closure_complete: false, pair_id: pairId, document,
    document_bytes: proof.document_bytes as number, document_xxh3_128: proof.document_xxh3_128 as string,
    snapshot_bytes: proof.snapshot_bytes as number, snapshot_xxh3_128: proof.snapshot_xxh3_128 as string };
}
