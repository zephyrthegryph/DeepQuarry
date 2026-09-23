// Generates the DM side of the verdigris bridge from the Rust sources.
//
// Every DM-callable Rust function is declared with `#[auxmacros::bind(...)]` or
// `#[auxmacros::bind_raw_args(...)]`. This scans for those attributes and
// writes:
//   code/__defines/verdigris/_bindings.dm  one `/proc/vg_<fn>(args)` per bind,
//                                          with a cached load_ext handle, the
//                                          `@dm-define` numeric registry and
//                                          VERDIGRIS_ABI;
//   verdigris/ffi/src/abi.rs               the same ABI string for the DLL.
// `verdigris_init(VERDIGRIS_ABI)` compares the two at boot.
//
// Usage: bun tools/build/lib/verdigris_bindings.ts [--check]
// --check writes nothing and exits 1 when either file is stale.

import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export const BINDINGS_DM = 'code/__defines/verdigris/_bindings.dm';
export const ABI_RS = 'verdigris/ffi/src/abi.rs';
const SCAN_ROOTS = [
  'verdigris/core',
  'verdigris/domains',
  'verdigris/ffi/src',
  'verdigris/verdigris/src',
];

type Bind = {
  name: string;
  path: string;
  args: string[] | null; // null = variadic
  docs: string[];
  file: string;
};
// Cargo features are only used by the gas crate. The DLL enables the ones listed
// on its vg-gas dependency; binds (or whole modules) behind any other feature are
// not exported, so they get no DM binding.
const GAS_CRATE = 'verdigris/domains/gas/';
const DLL_MANIFEST = 'verdigris/verdigris/Cargo.toml';

function enabledGasFeatures(root: string): Set<string> {
  const manifest = fs.readFileSync(path.join(root, DLL_MANIFEST), 'utf8');
  const line = /^vg-gas\s*=.*$/m.exec(manifest);
  const list = line && /features\s*=\s*\[([^\]]*)\]/.exec(line[0]);
  if (!list) throw new Error(`${DLL_MANIFEST}: cannot read the vg-gas features`);
  return new Set([...list[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]));
}

/** `#[cfg(feature = "x")]` attributes directly above line `at`. */
function cfgFeatures(lines: string[], at: number): string[] {
  const out: string[] = [];
  for (let i = at; i >= 0; i--) {
    const line = lines[i].trim();
    const m = /^#\[cfg\(feature\s*=\s*"([^"]+)"\)\]$/.exec(line);
    if (m) out.push(m[1]);
    else if (line.startsWith('#[') || line.startsWith('///')) continue;
    else break;
  }
  return out;
}

/** Gas-crate module paths whose `mod` declaration is behind a disabled feature. */
function disabledModules(root: string, files: string[], enabled: Set<string>): string[] {
  const disabled: string[] = [];
  for (const file of files) {
    const rel = path.relative(root, file).replace(/\\/g, '/');
    if (!rel.startsWith(GAS_CRATE)) continue;
    const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
    const base = /\/(lib|mod|main)\.rs$/.test(rel) ? path.posix.dirname(rel) : rel.replace(/\.rs$/, '');
    lines.forEach((line, i) => {
      const m = /^\s*(?:pub(?:\([a-z]+\))?\s+)?mod\s+([a-z0-9_]+)\s*;/.exec(line);
      if (m && cfgFeatures(lines, i - 1).some((f) => !enabled.has(f))) {
        disabled.push(`${base}/${m[1]}.rs`, `${base}/${m[1]}/`);
      }
    });
  }
  return disabled;
}

type Define = { name: string; value: string; docs: string[]; file: string };

function listRs(dir: string, out: string[]) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'target') continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) listRs(full, out);
    else if (entry.name.endsWith('.rs')) out.push(full);
  }
}

function splitTopLevel(text: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let cur = '';
  for (const ch of text) {
    if ('(<['.includes(ch)) depth++;
    if (')>]'.includes(ch)) depth--;
    if (ch === ',' && depth === 0) {
      parts.push(cur);
      cur = '';
    } else cur += ch;
  }
  if (cur.trim()) parts.push(cur);
  return parts.map((p) => p.trim()).filter(Boolean);
}

function argName(param: string, index: number): string {
  const pat = param.split(':')[0].trim().replace(/^mut\s+/, '');
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(pat) || pat === '_') return `arg${index + 1}`;
  const name = pat.replace(/^_+/, '') || `arg${index + 1}`;
  // DM reserves these as proc-local names.
  if (['src', 'usr', 'args', 'world', 'global'].includes(name)) return `${name}_ref`;
  return name;
}

function precedingDocs(lines: string[], from: number): string[] {
  const docs: string[] = [];
  for (let i = from; i >= 0; i--) {
    const line = lines[i].trim();
    if (line.startsWith('///')) docs.unshift(line.replace(/^\/\/\/ ?/, ''));
    else if (line.startsWith('#[')) continue;
    else break;
  }
  return docs;
}

export function scan(root: string): { binds: Bind[]; defines: Define[] } {
  const files: string[] = [];
  for (const dir of SCAN_ROOTS) listRs(path.join(root, dir), files);
  files.sort();
  const enabled = enabledGasFeatures(root);
  const disabled = disabledModules(root, files, enabled);
  const isDisabled = (rel: string) =>
    disabled.some((d) => rel === d || (d.endsWith('/') && rel.startsWith(d)));
  const binds: Bind[] = [];
  const defines: Define[] = [];
  const attr = /^\s*#\[auxmacros::(bind|bind_raw_args)(?:\(\s*"([^"]*)"\s*\))?\]/;
  for (const file of files) {
    const rel = path.relative(root, file).replace(/\\/g, '/');
    if (isDisabled(rel)) continue;
    const text = fs.readFileSync(file, 'utf8');
    const lines = text.split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      const m = attr.exec(lines[i]);
      if (m) {
        // Find the fn signature after the attribute.
        const rest = lines.slice(i + 1).join('\n');
        const fm = /\bfn\s+([A-Za-z0-9_]+)\s*\(/.exec(rest);
        if (!fm) throw new Error(`${rel}:${i + 1}: bind attribute without a fn`);
        let depth = 1;
        let j = fm.index + fm[0].length;
        const start = j;
        for (; depth > 0 && j < rest.length; j++) {
          if (rest[j] === '(') depth++;
          if (rest[j] === ')') depth--;
        }
        const params = splitTopLevel(rest.slice(start, j - 1));
        const features = cfgFeatures(lines, i - 1);
        if (features.length && !rel.startsWith(GAS_CRATE)) {
          throw new Error(`${rel}:${i + 1}: feature-gated binds are only supported in vg-gas`);
        }
        if (features.some((f) => !enabled.has(f))) continue;
        binds.push({
          name: fm[1],
          path: m[2] ?? `/proc/${fm[1]}`,
          args: m[1] === 'bind_raw_args' ? null : params.map(argName),
          docs: precedingDocs(lines, i - 1),
          file: rel,
        });
        continue;
      }
      const dm = /^\s*\/\/\/\s*@dm-define\s+([A-Z][A-Z0-9_]*)\s*$/.exec(lines[i]);
      if (dm) {
        let k = i + 1;
        while (k < lines.length && /^\s*(\/\/\/|#\[)/.test(lines[k])) k++;
        const cm = /^\s*pub(?:\([a-z]+\))?\s+const\s+[A-Z0-9_]+\s*:\s*[a-z0-9]+\s*=\s*(-?[0-9][0-9_.]*|0x[0-9a-fA-F_]+|0b[01_]+)\s*;/.exec(
          lines[k] ?? '',
        );
        if (!cm) {
          throw new Error(
            `${rel}:${i + 1}: @dm-define must precede a \`pub const NAME: int = <literal>;\``,
          );
        }
        const raw = cm[1].replace(/_/g, '');
        const value = raw.startsWith('0b') ? String(parseInt(raw.slice(2), 2)) : raw;
        defines.push({
          name: dm[1],
          value,
          docs: precedingDocs(lines, i - 1).filter((d) => !d.startsWith('@dm-define')),
          file: rel,
        });
      }
    }
  }
  const seen = new Set<string>();
  for (const b of binds) {
    if (seen.has(b.name)) throw new Error(`duplicate bind name ${b.name} (${b.file})`);
    seen.add(b.name);
  }
  binds.sort((a, b) => a.name.localeCompare(b.name));
  defines.sort((a, b) => a.name.localeCompare(b.name));
  return { binds, defines };
}

function abiOf(binds: Bind[], defines: Define[]): string {
  const canonical = [
    ...binds.map((b) => `${b.name}(${b.args === null ? '...' : b.args.length})`),
    ...defines.map((d) => `${d.name}=${d.value}`),
  ].join('\n');
  return createHash('sha256').update(canonical).digest('hex').slice(0, 16);
}

function docBlock(docs: string[], indent = ''): string {
  return docs.map((d) => `${indent}/// ${d}`.trimEnd() + '\n').join('');
}

export function render(root: string): { dm: string; rs: string; binds: number } {
  const { binds, defines } = scan(root);
  const abi = abiOf(binds, defines);
  let dm = `// THIS FILE IS GENERATED by tools/build/lib/verdigris_bindings.ts from the
// #[auxmacros::bind] functions in verdigris/. Do not edit it by hand: run
// \`tools/build/build.sh verdigris-bindings\`. CI fails when it is stale.
//
// This is the only file allowed to use call_ext for verdigris.

/* This comment bypasses grep checks */ /var/__verdigris

/proc/__detect_verdigris()
	if (world.system_type == UNIX)
		return __verdigris = (fexists("./libverdigris.so") ? "./libverdigris.so" : "libverdigris")
	else
		return __verdigris = "verdigris"

#define VERDIGRIS (__verdigris || __detect_verdigris())

#ifdef BENCHMARK
/// FFI calls made through the vg_* procs. Benchmark builds only; the
/// benchmarks report it per window (code/modules/benchmarks/_benchmark.dm).
/* This comment bypasses grep checks */ /var/__verdigris_ffi_calls = 0
#define VG_COUNT_FFI_CALL __verdigris_ffi_calls++
#else
#define VG_COUNT_FFI_CALL
#endif

/// Bind-set hash shared with verdigris/ffi/src/abi.rs; checked by verdigris_init().
#define VERDIGRIS_ABI "${abi}"

// Numeric registry (@dm-define constants in the Rust sources).
`;
  for (const d of defines) {
    dm += `\n${docBlock(d.docs)}// ${d.file}\n#define ${d.name} ${d.value}\n`;
  }
  dm += '\n// Binds.\n';
  for (const b of binds) {
    dm += `\n${docBlock(b.docs)}// ${b.path} (${b.file})\n`;
    if (b.args === null) {
      dm += `/proc/vg_${b.name}(...)
	var/static/__f = load_ext(VERDIGRIS, "byond:${b.name}_ffi")
	VG_COUNT_FFI_CALL
	return call_ext(__f)(arglist(args))
`;
    } else {
      const a = b.args.join(', ');
      dm += `/proc/vg_${b.name}(${a})
	var/static/__f = load_ext(VERDIGRIS, "byond:${b.name}_ffi")
	VG_COUNT_FFI_CALL
	return call_ext(__f)(${a})
`;
    }
  }
  const rs = `// THIS FILE IS GENERATED by tools/build/lib/verdigris_bindings.ts. Do not edit.
//! The bind-set hash. DM passes its copy (VERDIGRIS_ABI) to \`verdigris_init\`.

pub const ABI: &str = "${abi}";
`;
  return { dm, rs, binds: binds.length };
}

/** Returns the list of stale files; writes them unless check is set. */
export function generateVerdigrisBindings(root: string, check: boolean): string[] {
  const { dm, rs } = render(root);
  const stale: string[] = [];
  for (const [rel, content] of [
    [BINDINGS_DM, dm],
    [ABI_RS, rs],
  ] as const) {
    const full = path.join(root, rel);
    const current = fs.existsSync(full)
      ? fs.readFileSync(full, 'utf8').replace(/\r\n/g, '\n')
      : null;
    if (current === content) continue;
    stale.push(rel);
    if (!check) fs.writeFileSync(full, content);
  }
  return stale;
}

if (import.meta.main) {
  const root = path.resolve(import.meta.dir, '..', '..', '..');
  const check = process.argv.includes('--check');
  const stale = generateVerdigrisBindings(root, check);
  if (check && stale.length) {
    console.error(
      `verdigris bindings are stale: ${stale.join(', ')}\n`
        + 'Run `tools/build/build.sh verdigris-bindings` and commit the result.',
    );
    process.exit(1);
  }
  console.log(stale.length ? `wrote ${stale.join(', ')}` : 'verdigris bindings up to date');
}
