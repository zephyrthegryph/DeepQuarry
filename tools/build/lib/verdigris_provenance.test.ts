import { strict as assert } from 'node:assert';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import {
  checkVerdigrisProvenance,
  installVerdigrisLibrary,
  verdigrisInputHash,
  writeVerdigrisProvenance,
} from './verdigris_provenance';

function testDll(hash: string, exportName = 'example_ffi'): Buffer {
  const bytes = Buffer.alloc(1024);
  bytes.writeUInt32LE(0x80, 0x3c);
  bytes.write('PE\0\0', 0x80, 'ascii');
  bytes.writeUInt16LE(1, 0x86);
  bytes.writeUInt16LE(0xe0, 0x94);
  bytes.writeUInt16LE(0x10b, 0x98);
  bytes.writeUInt32LE(0x1000, 0x98 + 96);
  const section = 0x98 + 0xe0;
  bytes.writeUInt32LE(0x200, section + 8);
  bytes.writeUInt32LE(0x1000, section + 12);
  bytes.writeUInt32LE(0x200, section + 16);
  bytes.writeUInt32LE(0x200, section + 20);
  bytes.writeUInt32LE(1, 0x200 + 24);
  bytes.writeUInt32LE(0x1040, 0x200 + 32);
  bytes.writeUInt32LE(0x1050, 0x240);
  bytes.write(`${exportName}\0`, 0x250, 'ascii');
  bytes.write(`VERDIGRIS_SOURCE_HASH:${hash}\0`, 0x300, 'ascii');
  return bytes;
}

test('Verdigris prebuilt provenance detects stale inputs, platform and DLL contents', {
  skip: process.platform !== 'win32',
}, () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'verdigris-provenance-'));
  try {
    const rust = path.join(root, 'verdigris', 'ffi', 'src', 'lib.rs');
    const bindings = path.join(
      root,
      'code',
      '__defines',
      'verdigris',
      '_bindings.dm',
    );
    const library = path.join(root, 'verdigris.dll');
    fs.mkdirSync(path.dirname(rust), { recursive: true });
    fs.mkdirSync(path.dirname(bindings), { recursive: true });
    fs.writeFileSync(rust, 'pub fn example() {}\n');
    fs.writeFileSync(bindings, 'load_ext(VERDIGRIS, "byond:example_ffi")\n');
    for (const relative of [
      'code/__defines/verdigris/_bindings_types.dm',
      'code/__defines/verdigris/_component_schemas.dm',
      'tools/build/lib/verdigris_bindings.ts',
      'tools/generated_station/southern_cross_reference.json',
    ]) {
      const file = path.join(root, relative);
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, 'fixture');
    }
    fs.writeFileSync(library, testDll(verdigrisInputHash(root)));
    const target = 'i686-pc-windows-msvc';
    assert.equal(
      checkVerdigrisProvenance(root, library, target),
      'provenance sidecar is missing',
    );
    writeVerdigrisProvenance(root, library, target);
    assert.equal(checkVerdigrisProvenance(root, library, target), null);
    assert.match(
      checkVerdigrisProvenance(root, library, 'i686-unknown-linux-gnu') || '',
      /target mismatch/,
    );
    assert.equal(
      checkVerdigrisProvenance(root, library, target, '-C opt-level=2'),
      'RUSTFLAGS changed',
    );
    fs.writeFileSync(rust, 'pub fn example() { /* edited */ }\n');
    assert.equal(
      checkVerdigrisProvenance(root, library, target),
      'Rust sources or generated DM bindings changed',
    );
    writeVerdigrisProvenance(root, library, target);
    assert.equal(
      checkVerdigrisProvenance(root, library, target),
      'library was compiled from different Rust inputs',
    );
    fs.writeFileSync(library, testDll(verdigrisInputHash(root)));
    writeVerdigrisProvenance(root, library, target);
    fs.writeFileSync(
      bindings,
      'load_ext(VERDIGRIS, "byond:example_ffi") // edited\n',
    );
    assert.equal(
      checkVerdigrisProvenance(root, library, target),
      'Rust sources or generated DM bindings changed',
    );
    fs.writeFileSync(library, testDll(verdigrisInputHash(root)));
    writeVerdigrisProvenance(root, library, target);
    fs.writeFileSync(library, 'different library');
    assert.equal(
      checkVerdigrisProvenance(root, library, target),
      'library contents changed',
    );
    assert.throws(() =>
      installVerdigrisLibrary(
        root,
        path.join(root, 'missing.dll'),
        library,
        target,
      ),
    );
    assert.equal(
      fs.readFileSync(library, 'utf8'),
      'different library',
      'failed install must preserve the prior DLL',
    );
    const built = path.join(root, 'built.dll');
    fs.writeFileSync(built, testDll(verdigrisInputHash(root)));
    installVerdigrisLibrary(root, built, library, target);
    assert.deepEqual(
      fs.readFileSync(library),
      testDll(verdigrisInputHash(root)),
    );
    assert.equal(checkVerdigrisProvenance(root, library, target), null);
    fs.writeFileSync(built, testDll(verdigrisInputHash(root), 'other_ffi'));
    assert.throws(
      () => installVerdigrisLibrary(root, built, library, target),
      /lacks generated exports/,
    );
    assert.deepEqual(
      fs.readFileSync(library),
      testDll(verdigrisInputHash(root)),
    );
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
