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
export const TYPES_DM = 'code/__defines/verdigris/_bindings_types.dm';
export const ABI_RS = 'verdigris/ffi/src/abi.rs';
const SCAN_ROOTS = [
  'verdigris/core',
  'verdigris/domains',
  'verdigris/ffi/src',
  'verdigris/verdigris/src',
];
// Every `.dm` file, for the "the DM type exists" generator check (§12).
const DM_ROOT = 'code';

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
    // `target*`: build output (also covers worktree-specific CARGO_TARGET_DIR
    // names like `target-wt`). `tests`: integration tests are never scanned
    // for binds or components — a fixture type is not a real DM binding.
    if (entry.name === 'target' || entry.name.startsWith('target-') || entry.name === 'tests') continue;
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

// --- Components (doc/rewrite/rust_bindings.md §2, §3): #[vg::component],
// #[vg::query] and #[vg::events]. Everything DM-facing this scan produces
// (kind defines, init_* vars, get_*/set_*/push_* wrappers, query and event
// dispatch, and the class-3 integrity hook) goes into TYPES_DM. ------------

type FieldRole = 'config' | 'state' | 'input';

type ComponentField = {
  name: string;
  role: FieldRole;
  unit: string | null;
  min: number | null;
  max: number | null;
  default: string | null;
  onInvalid: 'clamp' | 'reject';
  from: string[];
};

type QueryGroup = { name: string; fields: string[] };

type EventDecl = { name: string; variants: string[] };

type Component = {
  domain: string;
  kind: number;
  dmType: string;
  structName: string;
  fields: ComponentField[];
  queries: QueryGroup[];
  events: EventDecl[];
  file: string;
};

/** `key = value, key2 = value2, ...` (top-level commas only) -> map of raw value text. */
function parseKeyValueArgs(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const part of splitTopLevel(text)) {
    const eq = part.indexOf('=');
    if (eq === -1) throw new Error(`expected \`key = value\` in \`${part}\``);
    out[part.slice(0, eq).trim()] = part.slice(eq + 1).trim();
  }
  return out;
}

function stripQuotes(s: string): string {
  const m = /^"(.*)"$/.exec(s.trim());
  if (!m) throw new Error(`expected a quoted string, got \`${s}\``);
  return m[1];
}

function stripBrackets(s: string): string[] {
  const m = /^\[(.*)\]$/.exec(s.trim());
  if (!m) throw new Error(`expected a bracketed list, got \`${s}\``);
  if (!m[1].trim()) return [];
  return splitTopLevel(m[1]).map((x) => x.trim());
}

function parseFieldAttr(argsText: string, name: string, at: string): ComponentField {
  const args = splitTopLevel(argsText);
  const role = args.shift() as FieldRole | undefined;
  if (role !== 'config' && role !== 'state' && role !== 'input') {
    throw new Error(`${at}: field \`${name}\`: unknown role \`${role}\` (expected config, state or input)`);
  }
  const kv = parseKeyValueArgs(args.join(','));
  let min: number | null = null;
  let max: number | null = null;
  if (kv.range) {
    const m = /^(-?[0-9.]+)\s*\.\.=?\s*(-?[0-9.]+)$/.exec(kv.range);
    if (!m) throw new Error(`${at}: field \`${name}\`: cannot parse range \`${kv.range}\` (need literal numbers)`);
    [min, max] = [Number(m[1]), Number(m[2])];
  }
  return {
    name,
    role,
    unit: kv.unit ? stripQuotes(kv.unit) : null,
    min,
    max,
    default: kv.default ?? null,
    onInvalid: (kv.on_invalid as 'clamp' | 'reject' | undefined) ?? 'clamp',
    from: kv.from ? stripBrackets(kv.from) : [],
  };
}

export function scanComponents(root: string): Component[] {
  const files: string[] = [];
  for (const dir of SCAN_ROOTS) listRs(path.join(root, dir), files);
  files.sort();
  const components: Component[] = [];
  const byName = new Map<string, Component>();

  for (const file of files) {
    const rel = path.relative(root, file).replace(/\\/g, '/');
    const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      const cm = /^#\[vg::component\((.*)\)\]\s*$/.exec(lines[i].trim());
      if (cm) {
        const args = parseKeyValueArgs(cm[1]);
        let j = i + 1;
        while (j < lines.length && !/\bstruct\s+\w+/.test(lines[j])) j++;
        const sm = /\bstruct\s+(\w+)/.exec(lines[j] ?? '');
        if (!sm) throw new Error(`${rel}:${i + 1}: #[vg::component] is not followed by a struct`);
        const structName = sm[1];
        const fields: ComponentField[] = [];
        for (let k = j + 1; k < lines.length; k++) {
          if (/^\s*\}\s*$/.test(lines[k])) break;
          const fm = /^\s*#\[vg\((.*)\)\]\s*$/.exec(lines[k]);
          if (!fm) continue;
          const dm = /^\s*(?:pub\s+)?(\w+)\s*:\s*[\w:<>]+\s*,?\s*$/.exec(lines[k + 1] ?? '');
          if (!dm) throw new Error(`${rel}:${k + 2}: expected a field declaration after #[vg(...)]`);
          fields.push(parseFieldAttr(fm[1], dm[1], `${rel}:${k + 1}`));
          k++;
        }
        for (const f of fields) {
          if (f.role === 'config' && f.default === null) {
            throw new Error(`${rel}: component ${structName} field \`${f.name}\`: config needs a default`);
          }
        }
        const comp: Component = {
          domain: args.domain,
          kind: Number(args.kind),
          dmType: stripQuotes(args.dm),
          structName,
          fields,
          queries: [],
          events: [],
          file: rel,
        };
        if (!comp.domain || !Number.isFinite(comp.kind) || !comp.dmType) {
          throw new Error(`${rel}: #[vg::component] needs domain, kind and dm`);
        }
        components.push(comp);
        byName.set(structName, comp);
        continue;
      }

      const qm = /^#\[vg::query\((\w+)\s*,\s*(.*)\)\]\s*$/.exec(lines[i].trim());
      if (qm) {
        const comp = byName.get(qm[1]);
        if (!comp) throw new Error(`${rel}:${i + 1}: #[vg::query] on unknown component \`${qm[1]}\``);
        for (const part of splitTopLevel(qm[2])) {
          const eq = part.indexOf('=');
          if (eq === -1) throw new Error(`${rel}:${i + 1}: expected \`name = [fields...]\``);
          comp.queries.push({
            name: part.slice(0, eq).trim(),
            fields: stripBrackets(part.slice(eq + 1)),
          });
        }
        continue;
      }

      const em = /^#\[vg::events\((\w+)\)\]\s*$/.exec(lines[i].trim());
      if (em) {
        const comp = byName.get(em[1]);
        if (!comp) throw new Error(`${rel}:${i + 1}: #[vg::events] on unknown component \`${em[1]}\``);
        let j = i + 1;
        while (j < lines.length && !/\benum\s+\w+/.test(lines[j])) j++;
        const enumMatch = /\benum\s+(\w+)/.exec(lines[j] ?? '');
        if (!enumMatch) throw new Error(`${rel}:${i + 1}: #[vg::events] is not followed by an enum`);
        let body = '';
        for (let k = j; k < lines.length; k++) {
          body += lines[k];
          if (lines[k].includes('}')) break;
        }
        const inner = /\{([^}]*)\}/.exec(body);
        if (!inner) throw new Error(`${rel}:${i + 1}: could not find the event enum's body`);
        const variants = inner[1]
          .split(',')
          .map((v) => v.trim())
          .filter(Boolean);
        comp.events.push({ name: enumMatch[1], variants });
        continue;
      }
    }
  }

  components.sort((a, b) => `${a.domain}:${a.kind}`.localeCompare(`${b.domain}:${b.kind}`));
  const seenKinds = new Set<string>();
  for (const c of components) {
    const key = `${c.domain}:${c.kind}`;
    if (seenKinds.has(key)) throw new Error(`duplicate kind ${c.kind} in domain ${c.domain} (${c.structName})`);
    seenKinds.add(key);
  }
  return components;
}

// `#[vg::component]`/`#[vg::query]` generate their own FFI procs at macro
// expansion time (`component.rs`'s `component_glue()`, `query.rs`'s
// `expand()`) — text that exists only inside those macros' `quote!{}`
// templates in `verdigris/ffi/macros/src/`, a directory `scan()` above never
// reads (nor could it usefully: that source is a *template*, not the
// expanded proc DM will actually call). So unlike a hand-written
// `#[auxmacros::bind]` function, a generated one is invisible to `scan()`
// and would silently get no `_bindings.dm` entry at all — a real gap once
// `#[vg::component]` started generating that glue instead of `kind/*.rs`
// writing it by hand (`rust_architecture.md` §5). This synthesizes the
// `Bind` entries `scan()` would have found had that glue been hand-written,
// from the same component scan `renderComponentsDm` already uses to emit
// the DM-side callers — so every name below MUST match those two macros'
// `format_ident!` calls exactly (component.rs's module docs: the
// naming-convention contract), and a change to one side without the other
// either leaves a DM proc calling nothing (a runtime) or a Rust bind no DM
// proc ever calls (dead code) rather than a compile-time mismatch.
function componentBinds(components: Component[]): Bind[] {
  const binds: Bind[] = [];
  for (const c of components) {
    const lower = snake(c.structName);
    const push = (name: string, args: string[], path: string) => {
      binds.push({ name, path, args, docs: [], file: c.file });
    };
    const config = c.fields.filter((f) => f.role === 'config');
    const state = c.fields.filter((f) => f.role === 'state');
    const input = c.fields.filter((f) => f.role === 'input');
    for (const f of config) {
      push(`${lower}_get_${f.name}`, ['entity'], `${c.dmType}/proc/get_${f.name}`);
      push(`${lower}_set_${f.name}`, ['entity', 'value'], `${c.dmType}/proc/set_${f.name}`);
    }
    for (const f of state) {
      push(`${lower}_get_${f.name}`, ['entity'], `${c.dmType}/proc/get_${f.name}`);
    }
    for (const f of input) {
      push(`${lower}_get_${f.name}`, ['entity'], `${c.dmType}/proc/get_${f.name}`);
      push(`${lower}_push_${f.name}`, ['entity', 'value'], `${c.dmType}/proc/push_${f.name}`);
    }
    // `entity, init_<config>..., <input>...`: the exact order
    // `component_glue()`'s `bind_params` builds (config fields first, then
    // input fields, both in declaration order).
    const bindArgs = ['entity', ...config.map((f) => `init_${f.name}`), ...input.map((f) => f.name)];
    push(`${lower}_bind`, bindArgs, `/proc/${lower}_bind`);
    for (const g of c.queries) {
      push(`${lower}_query_${g.name}`, ['entity'], `/proc/${lower}_query_${g.name}`);
    }
  }
  return binds;
}

/** Hand-written binds (`scan()`) plus generated ones (`componentBinds()`),
 * sorted and checked for name collisions across BOTH sources (`scan()`
 * only ever checked hand-written binds against each other). */
function mergeBinds(written: Bind[], generated: Bind[]): Bind[] {
  const binds = [...written, ...generated].sort((a, b) => a.name.localeCompare(b.name));
  const seen = new Set<string>();
  for (const b of binds) {
    if (seen.has(b.name)) {
      throw new Error(
        `duplicate bind name ${b.name} (${b.file}): a hand-written #[auxmacros::bind] collides `
          + 'with a #[vg::component]-generated one, or two components generate the same name',
      );
    }
    seen.add(b.name);
  }
  return binds;
}

let dmSourceCache: string | null = null;
function dmSource(root: string): string {
  if (dmSourceCache === null) {
    const files: string[] = [];
    (function walk(dir: string) {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) walk(full);
        else if (entry.name.endsWith('.dm')) files.push(full);
      }
    })(path.join(root, DM_ROOT));
    dmSourceCache = files.map((f) => fs.readFileSync(f, 'utf8')).join('\n');
  }
  return dmSourceCache;
}

/** Generator check (§12): the DM type a component names must exist. */
function checkDmTypeExists(root: string, comp: Component) {
  const escaped = comp.dmType.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(`(^|\\n)${escaped}(\\s|\\r?\\n|$)`);
  if (!re.test(dmSource(root))) {
    throw new Error(
      `${comp.file}: #[vg::component] names DM type \`${comp.dmType}\`, which no .dm file declares`,
    );
  }
}

const snake = (s: string) => s.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();

/** `from` sources with a known generated hook (§7's classes 1-4). Unknown
 * names are accepted but generate nothing: they rely on the reconciler,
 * exactly like class 5 (documented in the doc comment this emits). */
const HOOKED_SOURCES: Record<string, { proc: string; body: string[] }> = {
  integrity: {
    proc: 'atom_break',
    body: ['. = ..()'],
  },
};

function renderComponentsDm(components: Component[]): string {
  let dm = `// THIS FILE IS GENERATED by tools/build/lib/verdigris_bindings.ts from the
// #[vg::component]/#[vg::query]/#[vg::events] declarations in verdigris/.
// Do not edit it by hand: run \`tools/build/build.sh verdigris-bindings\`.
// CI fails when it is stale. See doc/rewrite/rust_bindings.md.

`;
  const byDomain = new Map<string, Component[]>();
  for (const c of components) {
    if (!byDomain.has(c.domain)) byDomain.set(c.domain, []);
    byDomain.get(c.domain)!.push(c);
  }

  // Base vars every bound atom needs (rust_bindings.md §1, §13): one
  // `vg_entity` (the entity handle) and one `vg_<domain>` per domain that
  // has landed a component (which kind, or 0/unset). Type-level constants
  // cost no per-instance memory unless a subtype overrides them.
  dm += `/atom/movable\n\t/// The entity handle (rust_bindings.md §1). 0: unbound.\n\tvar/tmp/vg_entity = 0\n`;
  for (const domain of [...byDomain.keys()].sort()) {
    dm += `\t/// Which ${domain} component kind (a VG_${domain.toUpperCase()}_* define), or 0.\n\tvar/tmp/vg_${domain} = 0\n`;
  }
  dm += '\n';

  // One bind and one reconcile dispatch proc per domain, overridden per
  // bound type (like vg_bind_gas() below), so there is no switch to keep in
  // sync by hand as kinds are added.
  for (const domain of byDomain.keys()) {
    dm += `/// Binds this atom's ${domain} component (if the type declares one) and\n`;
    dm += `/// returns the (possibly newly created) entity handle. Overridden per\n`;
    dm += `/// bound type below.\n`;
    dm += `/atom/movable/proc/vg_bind_${domain}(entity)\n\treturn entity\n\n`;
    dm += `/// Reconciler (§7): mismatches between this atom's declared inputs and\n`;
    dm += `/// what Rust has stored for its ${domain} component, repairing as it goes.\n`;
    dm += `/// Overridden per bound type below.\n`;
    dm += `/atom/movable/proc/vg_reconcile_${domain}()\n\treturn list()\n\n`;
    dm += `/// Dispatches one drained ${domain} event (§8) to its named handler.\n`;
    dm += `/// Overridden per bound type below (only on types that declare events).\n`;
    dm += `/atom/movable/proc/vg_dispatch_${domain}_event(event_id)\n\treturn\n\n`;
  }

  for (const comp of components) {
    const { domain, structName, dmType } = comp;
    const lower = snake(structName);
    const kindDefine = `VG_${domain.toUpperCase()}_${structName.toUpperCase()}`;
    const domainVar = `vg_${domain}`;

    dm += `// ---- ${structName} (${domain} kind ${comp.kind}; ${comp.file}) ----\n\n`;
    dm += `#define ${kindDefine} ${comp.kind}\n\n`;
    dm += `${dmType}\n\t${domainVar} = ${kindDefine}\n\n`;

    const configFields = comp.fields.filter((f) => f.role === 'config');
    const stateFields = comp.fields.filter((f) => f.role === 'state');
    const inputFields = comp.fields.filter((f) => f.role === 'input');

    for (const f of configFields) {
      const dmDefault = f.default === 'true' ? 'TRUE' : f.default === 'false' ? 'FALSE' : f.default;
      dm += `${dmType}/var/tmp/init_${f.name} = ${dmDefault}\n`;
    }
    if (configFields.length) dm += '\n';

    for (const f of configFields) {
      if (f.min === null || f.max === null) continue;
      dm += `#define VG_${structName.toUpperCase()}_${f.name.toUpperCase()}_MIN ${f.min}\n`;
      dm += `#define VG_${structName.toUpperCase()}_${f.name.toUpperCase()}_MAX ${f.max}\n`;
    }
    dm += '\n';

    const unitComment = (f: ComponentField) => (f.unit ? ` // ${f.unit}` : '');
    for (const f of configFields) {
      const range =
        f.min !== null && f.max !== null
          ? ` ${f.onInvalid === 'clamp' ? 'clamped' : 'rejected'} to VG_${structName.toUpperCase()}_${f.name.toUpperCase()}_MIN..MAX.`
          : '.';
      dm += `/// ${f.unit ?? 'unitless'};${range}\n`;
      dm += `${dmType}/proc/get_${f.name}()\n\treturn vg_${lower}_get_${f.name}(vg_entity)${unitComment(f)}\n\n`;
      dm += `/// Returns the stored value.\n`;
      dm += `${dmType}/proc/set_${f.name}(value)\n\treturn vg_${lower}_set_${f.name}(vg_entity, value)\n\n`;
    }
    for (const f of stateFields) {
      dm += `/// ${f.unit ?? 'unitless'}, read-only (state).\n`;
      dm += `${dmType}/proc/get_${f.name}()\n\treturn vg_${lower}_get_${f.name}(vg_entity)${unitComment(f)}\n\n`;
    }

    for (const f of inputFields) {
      dm += `/// Pure proc over ${structName}'s declared input sources (${f.from.join(', ') || 'none'}).\n`;
      dm += `/// Override per subtype if the default doesn't apply.\n`;
      dm += `${dmType}/proc/${lower}_input_${f.name}()\n\treturn FALSE\n\n`;
      dm += `/// What Rust currently has stored, for the reconciler (§7). Compare\n`;
      dm += `/// against ${lower}_input_${f.name}(); never used for game logic.\n`;
      dm += `${dmType}/proc/get_${f.name}()\n\treturn vg_${lower}_get_${f.name}(vg_entity)\n\n`;
    }

    for (const g of comp.queries) {
      dm += `/// ${g.fields.join(', ')} in one call.\n`;
      dm += `${dmType}/proc/${lower}_query_${g.name}()\n\treturn vg_${lower}_query_${g.name}(vg_entity)\n\n`;
    }

    const inputArgs = inputFields.map((f) => `${lower}_input_${f.name}()`);
    const initArgs = configFields.map((f) => `init_${f.name}`);
    dm += `${dmType}/vg_bind_${domain}(entity)\n\treturn vg_${lower}_bind(entity, ${[...initArgs, ...inputArgs].join(', ')})\n\n`;

    if (inputFields.length) {
      dm += `/// Compares every declared input against what Rust has stored (§7);\n`;
      dm += `/// repairs any mismatch and returns "field: expected=.. actual=.." for\n`;
      dm += `/// each one (empty: no divergence).\n`;
      dm += `${dmType}/proc/${lower}_reconcile()\n\tvar/list/mismatches = list()\n`;
      for (const f of inputFields) {
        dm += `\tvar/expected_${f.name} = ${lower}_input_${f.name}()\n`;
        dm += `\tvar/actual_${f.name} = get_${f.name}()\n`;
        dm += `\tif(!expected_${f.name} != !actual_${f.name})\n`;
        dm += `\t\tmismatches += "${f.name}: expected=[expected_${f.name}] actual=[actual_${f.name}]"\n`;
        dm += `\t\tvg_${lower}_push_${f.name}(vg_entity, expected_${f.name})\n`;
      }
      dm += `\treturn mismatches\n\n`;
      dm += `${dmType}/vg_reconcile_${domain}()\n\treturn ${lower}_reconcile()\n\n`;
    }

    for (const f of inputFields) {
      for (const source of f.from) {
        const hook = HOOKED_SOURCES[source];
        if (!hook) continue;
        const fix = hook.proc === 'atom_break' ? 'atom_fix' : null;
        dm += `// ${source} (class 3): pushes ${structName}'s ${f.name} when it changes.\n`;
        dm += `${dmType}/${hook.proc}(damage_flag)\n\t${hook.body.join('\n\t')}\n\tif(vg_entity)\n\t\tvg_${lower}_push_${f.name}(vg_entity, ${lower}_input_${f.name}())\n\n`;
        if (fix) {
          dm += `${dmType}/${fix}()\n\t. = ..()\n\tif(vg_entity)\n\t\tvg_${lower}_push_${f.name}(vg_entity, ${lower}_input_${f.name}())\n\n`;
        }
      }
    }

    for (const e of comp.events) {
      e.variants.forEach((v, id) => {
        const evName = snake(v);
        dm += `#define VG_${structName.toUpperCase()}_EVENT_${evName.toUpperCase()} ${id}\n`;
      });
    }
    if (comp.events.length) dm += '\n';
    for (const e of comp.events) {
      for (const v of e.variants) {
        dm += `/// Generated no-op default. Override to react to the event.\n`;
        dm += `${dmType}/proc/on_${lower}_${snake(v)}()\n\treturn\n\n`;
      }
    }

    const allVariants = comp.events.flatMap((e) => e.variants);
    if (allVariants.length) {
      dm += `/// Dispatches one drained event (§8) to its named handler.\n`;
      dm += `${dmType}/proc/${lower}_dispatch_event(event_id)\n\tswitch(event_id)\n`;
      allVariants.forEach((v, id) => {
        dm += `\t\tif(${id})\n\t\t\ton_${lower}_${snake(v)}()\n`;
      });
      dm += '\n';
      dm += `${dmType}/vg_dispatch_${domain}_event(event_id)\n\t${lower}_dispatch_event(event_id)\n\n`;
    }
  }

  dm += `// ---- One entry point per bound atom -------------------------------------\n\n`;
  dm += `/// Binds every component this atom's type declares (base on_materialize(), L2).\n`;
  dm += `/atom/movable/proc/vg_bind()\n`;
  dm += `\tvar/entity = 0\n`;
  for (const domain of byDomain.keys()) {
    dm += `\tif(vg_${domain})\n\t\tentity = vg_bind_${domain}(entity)\n`;
  }
  dm += `\tvg_entity = entity\n\n`;
  dm += `/// Every declared-input mismatch across every bound domain (§7). SSvg's\n`;
  dm += `/// sweep and the test sandbox teardown call this per atom.\n`;
  dm += `/atom/movable/proc/vg_reconcile()\n`;
  dm += `\tif(!vg_entity)\n\t\treturn list()\n`;
  dm += `\tvar/list/mismatches = list()\n`;
  for (const domain of byDomain.keys()) {
    dm += `\tif(vg_${domain})\n\t\tmismatches += vg_reconcile_${domain}()\n`;
  }
  dm += `\treturn mismatches\n\n`;

  dm += `/// Drains and dispatches every domain's events (§8). SSvg calls this once\n`;
  dm += `/// per tick; one \`entity_drain_domain_events()\` FFI call per domain.\n`;
  dm += `/proc/vg_drain_events()\n`;
  for (const domain of byDomain.keys()) {
    dm += `\tvg_drain_${domain}_events()\n`;
  }
  dm += '\n';
  for (const domain of byDomain.keys()) {
    dm += `/proc/vg_drain_${domain}_events()\n`;
    dm += `\tvar/list/flat = vg_entity_drain_domain_events(VG_DOMAIN_${domain.toUpperCase()})\n`;
    dm += `\tfor(var/i = 1; i <= length(flat); i += 3)\n`;
    dm += `\t\tvar/entity = flat[i + 1]\n`;
    dm += `\t\tvar/event_id = flat[i + 2]\n`;
    dm += `\t\tvar/atom/movable/mover = SSvg.entity_lookup(entity)\n`;
    dm += `\t\tif(mover && mover.vg_entity == entity)\n`;
    dm += `\t\t\tmover.vg_dispatch_${domain}_event(event_id)\n\n`;
  }
  return dm;
}

function componentCanonical(c: Component): string {
  const fields = c.fields
    .map((f) => `${f.name}:${f.role}:${f.unit ?? ''}:${f.min ?? ''}:${f.max ?? ''}:${f.onInvalid}`)
    .join(',');
  const events = c.events.flatMap((e) => e.variants).join(',');
  return `${c.domain}/${c.structName}#${c.kind}=${c.dmType}[${fields}]{${events}}`;
}

function abiOf(binds: Bind[], defines: Define[], components: Component[]): string {
  const canonical = [
    ...binds.map((b) => `${b.name}(${b.args === null ? '...' : b.args.length})`),
    ...defines.map((d) => `${d.name}=${d.value}`),
    ...components.map(componentCanonical),
  ].join('\n');
  return createHash('sha256').update(canonical).digest('hex').slice(0, 16);
}

function docBlock(docs: string[], indent = ''): string {
  return docs.map((d) => `${indent}/// ${d}`.trimEnd() + '\n').join('');
}

export function render(root: string): { dm: string; typesDm: string; rs: string; binds: number } {
  const { binds: writtenBinds, defines } = scan(root);
  const components = scanComponents(root);
  for (const c of components) checkDmTypeExists(root, c);
  // Every #[auxmacros::bind] proc gets a _bindings.dm entry, whether it was
  // scanned from hand-written source or synthesized from a #[vg::component]
  // declaration (componentBinds() above) — from here on there is no
  // distinction between the two.
  const binds = mergeBinds(writtenBinds, componentBinds(components));
  const abi = abiOf(binds, defines, components);
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
  const typesDm = renderComponentsDm(components);
  return { dm, typesDm, rs, binds: binds.length };
}

/** Returns the list of stale files; writes them unless check is set. */
export function generateVerdigrisBindings(root: string, check: boolean): string[] {
  const { dm, typesDm, rs } = render(root);
  const stale: string[] = [];
  for (const [rel, content] of [
    [BINDINGS_DM, dm],
    [TYPES_DM, typesDm],
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
