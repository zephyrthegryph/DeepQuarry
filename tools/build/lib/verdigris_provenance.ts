// A copied Verdigris library must match the Rust inputs in this checkout. The
// generated bind-set ABI checks only exported signatures, not implementation.

import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export const VERDIGRIS_PROVENANCE_VERSION = 1;

export type VerdigrisProvenance = {
  version: number;
  target: string;
  rustflags: string;
  inputHash: string;
  libraryHash: string;
};

function rustInputs(root: string): string[] {
  const files: string[] = [];
  const walk = (relative: string) => {
    const absolute = path.join(root, relative);
    if (!fs.existsSync(absolute)) return;
    for (const entry of fs.readdirSync(absolute, { withFileTypes: true })) {
      if (
        entry.name === 'target' ||
        entry.name.startsWith('target-') ||
        entry.name === '.git'
      )
        continue;
      const child = path.posix.join(relative.replaceAll('\\', '/'), entry.name);
      if (entry.isDirectory()) walk(child);
      else if (entry.isFile() && /\.(?:rs|toml|lock|c|h|sh)$/.test(entry.name))
        files.push(child);
    }
  };
  walk('verdigris');
  files.push(
    'code/__defines/verdigris/_bindings.dm',
    'code/__defines/verdigris/_bindings_types.dm',
    'code/__defines/verdigris/_component_schemas.dm',
    'tools/build/lib/verdigris_bindings.ts',
    // Embedded by vg-layout's include_str! at compile time.
    'tools/generated_station/southern_cross_reference.json',
  );
  return files.sort();
}

export function verdigrisInputHash(root: string): string {
  const hash = createHash('sha256');
  for (const relative of rustInputs(root)) {
    const absolute = path.join(root, relative);
    // Include path and length to make boundaries unambiguous.
    const contents = fs.readFileSync(absolute);
    hash.update(`${relative}\0${contents.length}\0`);
    hash.update(contents);
  }
  return hash.digest('hex');
}

export function verdigrisLibraryHash(library: string): string {
  return createHash('sha256').update(fs.readFileSync(library)).digest('hex');
}

export function verdigrisCompiledInputHash(library: string): string | null {
  const bytes = fs.readFileSync(library);
  const match = bytes
    .toString('latin1')
    .match(/VERDIGRIS_SOURCE_HASH:([0-9a-f]{64})/);
  return match?.[1] || null;
}

function windowsExports(library: string): Set<string> {
  const bytes = fs.readFileSync(library);
  const pe = bytes.readUInt32LE(0x3c);
  if (bytes.toString('ascii', pe, pe + 4) !== 'PE\0\0')
    throw new Error('Verdigris library is not a PE DLL');
  const sections = bytes.readUInt16LE(pe + 6);
  const optional = pe + 24;
  const optionalSize = bytes.readUInt16LE(pe + 20);
  const format = bytes.readUInt16LE(optional);
  const directory = optional + (format === 0x10b ? 96 : 112);
  const sectionTable = optional + optionalSize;
  const offset = (rva: number): number => {
    for (let i = 0; i < sections; i++) {
      const entry = sectionTable + i * 40;
      const size = Math.max(
        bytes.readUInt32LE(entry + 8),
        bytes.readUInt32LE(entry + 16),
      );
      const start = bytes.readUInt32LE(entry + 12);
      if (rva >= start && rva < start + size)
        return bytes.readUInt32LE(entry + 20) + rva - start;
    }
    throw new Error(`Unmapped Verdigris DLL RVA ${rva}`);
  };
  const readName = (at: number): string => {
    const end = bytes.indexOf(0, at);
    if (end < 0) throw new Error('Unterminated Verdigris export name');
    return bytes.toString('ascii', at, end);
  };
  const exportRva = bytes.readUInt32LE(directory);
  if (!exportRva) return new Set();
  const exportTable = offset(exportRva);
  const count = bytes.readUInt32LE(exportTable + 24);
  const names = offset(bytes.readUInt32LE(exportTable + 32));
  const exports = new Set<string>();
  for (let i = 0; i < count; i++)
    exports.add(readName(offset(bytes.readUInt32LE(names + i * 4))));
  return exports;
}

/** A source hash alone cannot prove Cargo linked every generated bind. */
export function missingVerdigrisExports(
  root: string,
  library: string,
): string[] {
  const bindings = fs.readFileSync(
    path.join(root, 'code/__defines/verdigris/_bindings.dm'),
    'utf8',
  );
  const expected = new Set(
    [
      ...bindings.matchAll(/load_ext\(VERDIGRIS, "byond:([A-Za-z0-9_]+)"\)/g),
    ].map((match) => match[1]),
  );
  if (!expected.size)
    throw new Error('No Verdigris exports found in generated bindings');
  let actual: Set<string>;
  if (process.platform === 'win32') {
    actual = windowsExports(library);
  } else {
    const result = spawnSync('nm', ['-D', '--defined-only', library], {
      encoding: 'utf8',
    });
    if (result.error || result.status !== 0)
      throw new Error(
        `Cannot inspect Verdigris exports with nm: ${result.error?.message || result.stderr}`,
      );
    actual = new Set(
      [...result.stdout.matchAll(/\b([A-Za-z][A-Za-z0-9_]*_ffi)\b/g)].map(
        (match) => match[1],
      ),
    );
  }
  return [...expected].filter((name) => !actual.has(name)).sort();
}

export function writeVerdigrisProvenance(
  root: string,
  library: string,
  target: string,
  rustflags = '',
): void {
  const provenance: VerdigrisProvenance = {
    version: VERDIGRIS_PROVENANCE_VERSION,
    target,
    rustflags,
    inputHash: verdigrisInputHash(root),
    libraryHash: verdigrisLibraryHash(library),
  };
  const sidecar = `${library}.provenance.json`;
  const temporary = `${sidecar}.tmp`;
  fs.writeFileSync(temporary, `${JSON.stringify(provenance, null, 2)}\n`);
  fs.renameSync(temporary, sidecar);
}

/** Publish only after Cargo succeeds. The existing DLL survives build/copy
 * failure; a crash between the two final renames leaves an invalid sidecar,
 * which the next build rejects instead of silently loading a mismatched pair.
 */
export function installVerdigrisLibrary(
  root: string,
  built: string,
  library: string,
  target: string,
  rustflags = '',
): void {
  const staged = `${library}.next`;
  try {
    fs.copyFileSync(built, staged);
    if (verdigrisCompiledInputHash(staged) !== verdigrisInputHash(root))
      throw new Error(
        'Built Verdigris library has a stale or missing source fingerprint',
      );
    const missing = missingVerdigrisExports(root, staged);
    if (missing.length)
      throw new Error(
        `Built Verdigris library lacks generated exports: ${missing.join(', ')}`,
      );
    writeVerdigrisProvenance(root, staged, target, rustflags);
    fs.renameSync(staged, library);
    fs.renameSync(`${staged}.provenance.json`, `${library}.provenance.json`);
  } finally {
    if (fs.existsSync(staged)) fs.unlinkSync(staged);
    if (fs.existsSync(`${staged}.provenance.json`))
      fs.unlinkSync(`${staged}.provenance.json`);
    if (fs.existsSync(`${staged}.provenance.json.tmp`))
      fs.unlinkSync(`${staged}.provenance.json.tmp`);
  }
}

export function checkVerdigrisProvenance(
  root: string,
  library: string,
  target: string,
  rustflags = '',
): string | null {
  if (!fs.existsSync(library)) return 'library is missing';
  const sidecar = `${library}.provenance.json`;
  if (!fs.existsSync(sidecar)) return 'provenance sidecar is missing';
  let provenance: VerdigrisProvenance;
  try {
    provenance = JSON.parse(fs.readFileSync(sidecar, 'utf8'));
  } catch {
    return 'provenance sidecar is invalid';
  }
  if (provenance.version !== VERDIGRIS_PROVENANCE_VERSION)
    return 'provenance format changed';
  if (provenance.target !== target)
    return `target mismatch (${provenance.target} vs ${target})`;
  if (provenance.rustflags !== rustflags) return 'RUSTFLAGS changed';
  if (provenance.inputHash !== verdigrisInputHash(root))
    return 'Rust sources or generated DM bindings changed';
  if (provenance.libraryHash !== verdigrisLibraryHash(library))
    return 'library contents changed';
  if (verdigrisCompiledInputHash(library) !== provenance.inputHash)
    return 'library was compiled from different Rust inputs';
  const missing = missingVerdigrisExports(root, library);
  if (missing.length)
    return `library lacks generated exports: ${missing.join(', ')}`;
  return null;
}
