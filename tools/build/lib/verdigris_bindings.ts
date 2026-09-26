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

type FieldRole = 'config' | 'state' | 'input' | 'computed';

type ComponentField = {
  name: string;
  role: FieldRole;
  unit: string | null;
  min: number | null;
  max: number | null;
  default: string | null;
  onInvalid: 'clamp' | 'reject';
  from: string[];
  /** A fixed-size, enum-keyed array (`[T; N]`): crosses one element at a
   * time (`get_<f>(index)`/`set_<f>(index, value)`) and is never a bind
   * argument (it starts at its default). */
  array: boolean;
  /** The field id `#[vg::component]` assigns: declaration order, computed
   * readouts after the stored fields. */
  id: number;
  /** `conserve = "..."`: the field takes `adjust_<f>()` (take reconciliation). */
  conserve: string | null;
};

type QueryGroup = { name: string; fields: string[] };

type EventVariant = { name: string; fields: string[] };

type EventDecl = { name: string; variants: EventVariant[] };

type Component = {
  domain: string;
  kind: number;
  /// The DM type this component binds to, or `null` for a bare-entity
  /// component with no natural DM owner (a pipe device's flow/valve row):
  /// that generates free-function `vg_bind_<lower>`/`get_*`/`set_*` procs
  /// taking the entity number directly, instead of per-type ones.
  dmType: string | null;
  structName: string;
  owner: 'main' | 'worker';
  fields: ComponentField[];
  queries: QueryGroup[];
  events: EventDecl[];
  file: string;
};

/** `#[vg::events(domain = power)]`: events about a region or the domain,
 * dispatched to `SSvg` handlers instead of an atom. */
type DomainEvents = { domain: string; decl: EventDecl; file: string };

/** Numeric domain ids, from `vg_core::component::domains`. */
const DOMAINS_RS = 'verdigris/core/src/component.rs';

function domainIds(root: string): Map<string, number> {
  const src = fs.readFileSync(path.join(root, DOMAINS_RS), 'utf8');
  const consts = new Map<string, number>();
  for (const m of src.matchAll(/pub const ([A-Z_]+): u8 = (\d+);/g)) consts.set(m[1], Number(m[2]));
  const out = new Map<string, number>();
  for (const m of src.matchAll(/\("([a-z_]+)",\s*([A-Z_]+)\)/g)) {
    const id = consts.get(m[2]);
    if (id === undefined) throw new Error(`${DOMAINS_RS}: domain ${m[1]} names unknown const ${m[2]}`);
    out.set(m[1], id);
  }
  if (!out.size) throw new Error(`${DOMAINS_RS}: no domains table found`);
  return out;
}

/** `domain << 8 | kind`: the code the generic `vg_component_*` binds take. */
function kindCode(ids: Map<string, number>, domain: string, kind: number): number {
  const d = ids.get(domain);
  if (d === undefined) throw new Error(`unknown domain \`${domain}\` (add it to ${DOMAINS_RS})`);
  return (d << 8) | (kind & 0xff);
}

/** An event record's header: `domain << 16 | kind << 8 | variant`. */
function eventHeader(ids: Map<string, number>, domain: string, kind: number, variant: number): number {
  const d = ids.get(domain);
  if (d === undefined) throw new Error(`unknown domain \`${domain}\``);
  return (d << 16) | ((kind & 0xff) << 8) | variant;
}

/** Parses an event enum body (`{ A, B { x: f32, y: f32 }, }`) into variants. */
function parseEventBody(body: string): EventVariant[] {
  const clean = body.replace(/\/\/[^\n]*/g, '').replace(/#\[[^\]]*\]/g, '');
  const out: EventVariant[] = [];
  let depth = 0;
  let cur = '';
  for (const ch of clean) {
    if (ch === '{') depth++;
    if (ch === '}') depth--;
    if (ch === ',' && depth === 0) {
      if (cur.trim()) out.push(parseVariant(cur));
      cur = '';
    } else cur += ch;
  }
  if (cur.trim()) out.push(parseVariant(cur));
  return out;
}

function parseVariant(text: string): EventVariant {
  const m = /^\s*(\w+)\s*(?:\{([^}]*)\})?\s*$/.exec(text);
  if (!m) throw new Error(`cannot parse event variant \`${text.trim()}\``);
  const fields = (m[2] ?? '')
    .split(',')
    .map((f) => f.trim())
    .filter(Boolean)
    .map((f) => f.split(':')[0].trim());
  return { name: m[1], fields };
}

/** The body of the `{ ... }` block that starts at or after `lines[from]`
 * (brace matched), without the outer braces. */
function braceBody(lines: string[], from: number): string {
  let text = '';
  let depth = 0;
  let started = false;
  for (let k = from; k < lines.length; k++) {
    const code = lines[k].replace(/\/\/.*$/, '');
    for (const ch of code) {
      if (ch === '{') {
        depth++;
        if (!started) {
          started = true;
          continue;
        }
      }
      if (ch === '}') {
        depth--;
        if (started && depth === 0) return text;
      }
      if (started) text += ch;
    }
    if (started) text += '\n';
  }
  throw new Error('unterminated brace block');
}

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

function parseFieldAttr(argsText: string, name: string, array: boolean, at: string): ComponentField {
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
    array,
    id: -1,
    conserve: kv.conserve ? stripQuotes(kv.conserve) : null,
  };
}

export function scanComponents(root: string): { components: Component[]; domainEvents: DomainEvents[] } {
  const files: string[] = [];
  for (const dir of SCAN_ROOTS) listRs(path.join(root, dir), files);
  files.sort();
  const components: Component[] = [];
  const domainEvents: DomainEvents[] = [];
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
          const dm = /^\s*(?:pub\s+)?(\w+)\s*:\s*([\w:<>]+|\[\s*[\w:<>]+\s*;\s*\w+\s*\])\s*,?\s*$/.exec(lines[k + 1] ?? '');
          if (!dm) throw new Error(`${rel}:${k + 2}: expected a field declaration after #[vg(...)]`);
          fields.push(parseFieldAttr(fm[1], dm[1], dm[2].startsWith('['), `${rel}:${k + 1}`));
          k++;
        }
        for (const f of fields) {
          if (f.role === 'config' && f.default === null) {
            throw new Error(`${rel}: component ${structName} field \`${f.name}\`: config needs a default`);
          }
        }
        for (const c of args.computed ? stripBrackets(args.computed) : []) {
          fields.push({
            name: c,
            role: 'computed',
            unit: null,
            min: null,
            max: null,
            default: null,
            onInvalid: 'clamp',
            from: [],
            array: false,
            id: -1,
            conserve: null,
          });
        }
        fields.forEach((f, id) => {
          f.id = id;
        });
        const comp: Component = {
          domain: args.domain,
          kind: Number(args.kind),
          dmType: args.dm ? stripQuotes(args.dm) : null,
          structName,
          owner: args.owner === 'main' ? 'main' : 'worker',
          fields,
          queries: [],
          events: [],
          file: rel,
        };
        if (!comp.domain || !Number.isFinite(comp.kind)) {
          throw new Error(`${rel}: #[vg::component] needs domain and kind`);
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

      const em = /^#\[vg::events\((?:domain\s*=\s*(\w+)|(\w+))\)\]\s*$/.exec(lines[i].trim());
      if (em) {
        let j = i + 1;
        while (j < lines.length && !/\benum\s+\w+/.test(lines[j])) j++;
        const enumMatch = /\benum\s+(\w+)/.exec(lines[j] ?? '');
        if (!enumMatch) throw new Error(`${rel}:${i + 1}: #[vg::events] is not followed by an enum`);
        const decl = { name: enumMatch[1], variants: parseEventBody(braceBody(lines, j)) };
        if (em[1]) {
          domainEvents.push({ domain: em[1], decl, file: rel });
        } else {
          const comp = byName.get(em[2]);
          if (!comp) throw new Error(`${rel}:${i + 1}: #[vg::events] on unknown component \`${em[2]}\``);
          comp.events.push(decl);
        }
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
  domainEvents.sort((a, b) => `${a.domain}:${a.decl.name}`.localeCompare(`${b.domain}:${b.decl.name}`));
  return { components, domainEvents };
}

// Components have no binds of their own: every generated DM accessor below
// calls the generic `vg_component_*` binds (verdigris/ffi/src/world.rs, found
// by scan() like any hand-written bind) with the kind code and field ids
// `#[vg::component]` assigns (declaration order, computed readouts last).

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
    // Our own output must not count as a declaration (it would make every
    // generated proc look inherited from itself).
    const own = new Set([BINDINGS_DM, TYPES_DM].map((f) => path.resolve(root, f)));
    files.splice(0, files.length, ...files.filter((f) => !own.has(path.resolve(f))));
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

/** DM ancestors of a type path, nearest first: /obj/item/x -> /obj/item, /obj,
 * /atom/movable, /atom, /datum. Builtin parents are hardcoded because DM
 * doesn't spell them in paths. */
function dmAncestors(dmType: string): string[] {
  const out: string[] = [];
  const parts = dmType.split('/').filter(Boolean);
  for (let i = parts.length - 1; i >= 1; i--) out.push('/' + parts.slice(0, i).join('/'));
  const top = '/' + parts[0];
  if (top === '/obj' || top === '/mob') out.push('/atom/movable', '/atom');
  else if (top === '/turf' || top === '/area') out.push('/atom');
  else if (dmType.startsWith('/atom/movable/')) out.push('/atom');
  if (top !== '/datum') out.push('/datum');
  return out;
}

/**
 * Header for a generated accessor proc on `dmType`. DM refuses a second
 * `proc/` definition of a name an ancestor already declares, so when a
 * hand-written ancestor proc exists (e.g. `/atom/proc/get_temperature()`,
 * heat.dm) the accessor is emitted as an override instead. A hand-written
 * `proc/` of the same name on the type itself is a real clash: error.
 */
function procHeader(root: string, dmType: string, name: string, args: string): string {
  const src = dmSource(root);
  const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const declares = (t: string) => new RegExp(`(^|\\n)${esc(t)}/proc/${esc(name)}\\(`).test(src);
  if (declares(dmType)) {
    throw new Error(`${dmType}/proc/${name}() is hand-written in DM but also generated from a #[vg::component] field; remove one`);
  }
  const inherited = dmAncestors(dmType).some(declares);
  return `${dmType}/${inherited ? '' : 'proc/'}${name}(${args})`;
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

function renderComponentsDm(root: string, components: Component[], domainEvents: DomainEvents[]): string {
  const ids = domainIds(root);
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

  // Base vars every bound type needs (rust_bindings.md §1, §13): one
  // `vg_entity` (the entity handle) and one `vg_<domain>` per domain that
  // has landed a component (which kind, or 0/unset). Declared on `/datum`,
  // not `/atom/movable`: most bound types are atoms (the atom auto-bind
  // lifecycle in atoms_movable.dm -- on_materialize()/vg_bind() -- needs
  // `/atom/movable` specifically), but a component with no natural DM
  // owner (a pipe device's flow/valve row, gen/layout's own "no DM type"
  // case below) binds a bare, non-atom `/datum` instead; declaring the
  // base plumbing on `/datum` lets both kinds share it, with atoms
  // inheriting it exactly as before.
  dm += `/datum\n\t/// The entity handle (rust_bindings.md §1). 0: unbound.\n\tvar/tmp/vg_entity = 0\n`;
  for (const domain of [...byDomain.keys()].sort()) {
    dm += `\t/// Which ${domain} component kind (a VG_${domain.toUpperCase()}_* define), or 0.\n\tvar/tmp/vg_${domain} = 0\n`;
  }
  dm += '\n';

  for (const domain of byDomain.keys()) {
    dm += `/// Binds this datum's ${domain} component (if the type declares one) and\n`;
    dm += `/// returns the (possibly newly created) entity handle. Overridden per\n`;
    dm += `/// bound type below.\n`;
    dm += `/datum/proc/vg_bind_${domain}(entity)\n\treturn entity\n\n`;
    dm += `/// Reconciler (§7): mismatches between this datum's declared inputs and\n`;
    dm += `/// what Rust has stored for its ${domain} component, repairing as it goes.\n`;
    dm += `/// Overridden per bound type below.\n`;
    dm += `/datum/proc/vg_reconcile_${domain}()\n\treturn list()\n\n`;
  }

  for (const comp of components) {
    const { domain, structName, dmType } = comp;
    const lower = snake(structName);
    const upper = structName.toUpperCase();
    const kindDefine = `VG_${domain.toUpperCase()}_${upper}`;
    const codeDefine = `VG_KIND_${upper}`;
    const code = kindCode(ids, domain, comp.kind);
    const domainVar = `vg_${domain}`;

    dm += `// ---- ${structName} (${domain} kind ${comp.kind}, owner ${comp.owner}; ${comp.file}) ----\n\n`;
    dm += `#define ${kindDefine} ${comp.kind}\n`;
    dm += `/// The code the generic vg_component_* binds take for ${structName}.\n`;
    dm += `#define ${codeDefine} ${code}\n`;
    dm += `/// ${structName}'s watch domain for REACT_ON/REACT_WHEN (cells are vg_entity handles).\n`;
    dm += `#define REACT_DOMAIN_${upper} (VG_WORLD_KIND_BASE | ${codeDefine})\n`;
    for (const f of comp.fields) {
      dm += `#define VG_${upper}_FIELD_${f.name.toUpperCase()} ${f.id}\n`;
    }
    dm += '\n';

    const configFields = comp.fields.filter((f) => f.role === 'config');
    const stateFields = comp.fields.filter((f) => f.role === 'state');
    const inputFields = comp.fields.filter((f) => f.role === 'input');
    const computedFields = comp.fields.filter((f) => f.role === 'computed');
    const fid = (f: ComponentField) => `VG_${upper}_FIELD_${f.name.toUpperCase()}`;

    if (dmType === null) {
      // A bare-entity component with no DM owner (a pipe device's flow/
      // valve row, `ffi/src/pipes.rs`): free-function `vg_bind_<lower>`/
      // `get_*`/`set_*` procs taking the entity number directly, instead
      // of the per-type instance vars/overrides below. Config fields only
      // -- state/computed/input/conserve/queries/events all read or push
      // through a bound atom's own vars, which a bare entity doesn't have.
      const other = [...stateFields, ...computedFields, ...inputFields, ...comp.queries, ...comp.events];
      if (other.length || configFields.some((f) => f.array)) {
        throw new Error(`${comp.file}: component ${structName} has no \`dm\` type, so it must be config-only, non-array fields`);
      }
      const bindArgs = configFields.map((f) => f.name).join(', ');
      const initList = configFields.map((f) => `${fid(f)}, ${f.name}`).join(', ');
      dm += `/// Creates (\`entity\` 0) or replaces (otherwise) a bare ${structName}\n`;
      dm += `/// row and returns its entity handle -- never a DM object (this\n`;
      dm += `/// component declares no \`dm\` type).\n`;
      dm += `/proc/vg_bind_${lower}(entity, ${bindArgs})\n\treturn vg_component_bind(entity, ${codeDefine}, list(${initList}))\n\n`;
      for (const f of configFields) {
        const range =
          f.min !== null && f.max !== null
            ? ` ${f.onInvalid === 'clamp' ? 'clamped' : 'rejected'} to VG_${upper}_${f.name.toUpperCase()}_MIN..MAX.`
            : '.';
        if (f.min !== null && f.max !== null) {
          dm += `#define VG_${upper}_${f.name.toUpperCase()}_MIN ${f.min}\n`;
          dm += `#define VG_${upper}_${f.name.toUpperCase()}_MAX ${f.max}\n`;
        }
        dm += `/// ${f.unit ?? 'unitless'};${range}\n`;
        dm += `/proc/get_${lower}_${f.name}(entity)\n\treturn vg_component_get(entity, ${codeDefine}, ${fid(f)}, 0)${f.unit ? ` // ${f.unit}` : ''}\n\n`;
        dm += `/// Returns the stored value.\n`;
        dm += `/proc/set_${lower}_${f.name}(entity, value)\n\treturn vg_component_set(entity, ${codeDefine}, ${fid(f)}, -1, value)\n\n`;
      }
      continue;
    }

    dm += `${dmType}\n\t${domainVar} = ${kindDefine}\n\n`;

    for (const f of configFields) {
      if (f.array) continue;
      const dmDefault = f.default === 'true' ? 'TRUE' : f.default === 'false' ? 'FALSE' : f.default;
      dm += `${dmType}/var/tmp/init_${f.name} = ${dmDefault}\n`;
    }
    if (configFields.length) dm += '\n';

    for (const f of configFields) {
      if (f.min === null || f.max === null) continue;
      dm += `#define VG_${upper}_${f.name.toUpperCase()}_MIN ${f.min}\n`;
      dm += `#define VG_${upper}_${f.name.toUpperCase()}_MAX ${f.max}\n`;
    }
    dm += '\n';

    const unitComment = (f: ComponentField) => (f.unit ? ` // ${f.unit}` : '');
    const getter = (f: ComponentField, index: string) =>
      `vg_component_get(vg_entity, ${codeDefine}, ${fid(f)}, ${index})${unitComment(f)}`;
    for (const f of configFields) {
      const range =
        f.min !== null && f.max !== null
          ? ` ${f.onInvalid === 'clamp' ? 'clamped' : 'rejected'} to VG_${upper}_${f.name.toUpperCase()}_MIN..MAX.`
          : '.';
      dm += `/// ${f.unit ?? 'unitless'};${range}\n`;
      if (f.array) {
        dm += `${procHeader(root, dmType, `get_${f.name}`, 'index')}\n\treturn ${getter(f, 'index')}\n\n`;
        dm += `/// Returns the stored value.\n`;
        dm += `${procHeader(root, dmType, `set_${f.name}`, 'index, value')}\n\treturn vg_component_set(vg_entity, ${codeDefine}, ${fid(f)}, index, value)\n\n`;
        continue;
      }
      dm += `${procHeader(root, dmType, `get_${f.name}`, '')}\n\treturn ${getter(f, '0')}\n\n`;
      dm += `/// Returns the stored value.\n`;
      dm += `${procHeader(root, dmType, `set_${f.name}`, 'value')}\n\treturn vg_component_set(vg_entity, ${codeDefine}, ${fid(f)}, -1, value)\n\n`;
    }
    for (const f of [...stateFields, ...computedFields]) {
      const what = f.role === 'computed' ? 'computed readout' : 'state';
      dm += `/// ${f.unit ?? 'unitless'}, read-only (${what}).\n`;
      if (f.array) {
        dm += `${procHeader(root, dmType, `get_${f.name}`, 'index')}\n\treturn ${getter(f, 'index')}\n\n`;
      } else {
        dm += `${procHeader(root, dmType, `get_${f.name}`, '')}\n\treturn ${getter(f, '0')}\n\n`;
      }
    }
    for (const f of comp.fields.filter((x) => x.conserve)) {
      dm += `/// Take reconciliation (${f.conserve}): adds \`delta\` to what Rust holds now;\n`;
      dm += `/// returns the part of a removal that was not there.\n`;
      const args = f.array ? 'index, delta' : 'delta';
      const index = f.array ? 'index' : '0';
      dm += `${procHeader(root, dmType, `adjust_${f.name}`, args)}\n\treturn vg_component_adjust(vg_entity, ${codeDefine}, ${fid(f)}, ${index}, delta)\n\n`;
    }

    for (const f of inputFields) {
      dm += `/// Pure proc over ${structName}'s declared input sources (${f.from.join(', ') || 'none'}).\n`;
      dm += `/// Override per subtype if the default doesn't apply.\n`;
      dm += `${dmType}/proc/${lower}_input_${f.name}()\n\treturn FALSE\n\n`;
      dm += `/// What Rust currently has stored, for the reconciler (§7). Compare\n`;
      dm += `/// against ${lower}_input_${f.name}(); never used for game logic.\n`;
      dm += `${procHeader(root, dmType, `get_${f.name}`, '')}\n\treturn ${getter(f, '0')}\n\n`;
      dm += `/// Pushes the input's current value to Rust.\n`;
      dm += `${dmType}/proc/push_${f.name}(value)\n\treturn vg_component_set(vg_entity, ${codeDefine}, ${fid(f)}, -1, value)\n\n`;
    }

    for (const g of comp.queries) {
      const idsList = g.fields
        .map((name) => {
          const f = comp.fields.find((x) => x.name === name);
          if (!f) throw new Error(`${comp.file}: query ${g.name} names unknown field ${name}`);
          return fid(f);
        })
        .join(', ');
      dm += `/// ${g.fields.join(', ')} in one call.\n`;
      dm += `${dmType}/proc/${lower}_query_${g.name}()\n\treturn vg_component_get_many(vg_entity, ${codeDefine}, list(${idsList}))\n\n`;
    }

    const init = [
      ...configFields.filter((f) => !f.array).map((f) => `${fid(f)}, init_${f.name}`),
      ...inputFields.map((f) => `${fid(f)}, ${lower}_input_${f.name}()`),
    ];
    dm += `${dmType}/vg_bind_${domain}(entity)\n\treturn vg_component_bind(entity, ${codeDefine}, list(${init.join(', ')}))\n\n`;

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
        dm += `\t\tpush_${f.name}(expected_${f.name})\n`;
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
        dm += `${dmType}/${hook.proc}(damage_flag)\n\t${hook.body.join('\n\t')}\n\tif(vg_entity)\n\t\tpush_${f.name}(${lower}_input_${f.name}())\n\n`;
        if (fix) {
          dm += `${dmType}/${fix}()\n\t. = ..()\n\tif(vg_entity)\n\t\tpush_${f.name}(${lower}_input_${f.name}())\n\n`;
        }
      }
    }

    const variants = comp.events.flatMap((e) => e.variants);
    variants.forEach((v, id) => {
      dm += `#define VG_${upper}_EVENT_${snake(v.name).toUpperCase()} ${id}\n`;
    });
    if (variants.length) dm += '\n';
    for (const v of variants) {
      dm += `/// Generated no-op default. Override to react to the event.\n`;
      dm += `${dmType}/proc/on_${lower}_${snake(v.name)}(${v.fields.join(', ')})\n\treturn\n\n`;
    }
  }

  for (const de of domainEvents) {
    for (const v of de.decl.variants) {
      dm += `/// ${de.domain} event (${de.file}). Generated no-op default; override on SSvg.\n`;
      dm += `/datum/controller/subsystem/vg/proc/on_${de.domain}_${snake(v.name)}(${v.fields.join(', ')})\n\treturn\n\n`;
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

  // The one event path (rust_architecture.md §4.8): one FFI call returns
  // every typed event of the step as `header, entity, len, payload...`.
  dm += `/// Drains and dispatches every typed event since the last call (§4.8).\n`;
  dm += `/// SSvg calls this once per tick after vg_world_tick(). Component events\n`;
  dm += `/// go to the bound atom (checked against vg_entity: a detached component's\n`;
  dm += `/// late event is dropped); domain events go to SSvg's handlers.\n`;
  dm += `/proc/vg_drain_events()\n`;
  dm += `\tvar/list/flat = vg_world_events()\n`;
  dm += `\tvar/i = 1\n`;
  dm += `\twhile(i + 2 <= length(flat))\n`;
  dm += `\t\tvar/header = flat[i]\n`;
  dm += `\t\tvar/entity = flat[i + 1]\n`;
  dm += `\t\tvar/len = flat[i + 2]\n`;
  dm += `\t\tvar/p = i + 3\n`;
  dm += `\t\ti = p + len\n`;
  const arms: string[] = [];
  for (const comp of components) {
    const lower = snake(comp.structName);
    comp.events
      .flatMap((e) => e.variants)
      .forEach((v, id) => {
        const header = eventHeader(ids, comp.domain, comp.kind, id);
        const args = v.fields.map((_, k) => `flat[p + ${k}]`).join(', ');
        arms.push(
          `\t\t\tif(${header})\n\t\t\t\tvar/atom/movable/mover = SSvg.entity_lookup(entity)\n\t\t\t\tif(mover && mover.vg_entity == entity)\n\t\t\t\t\tvar${comp.dmType}/target = mover\n\t\t\t\t\ttarget.on_${lower}_${snake(v.name)}(${args})\n`,
        );
      });
  }
  for (const de of domainEvents) {
    de.decl.variants.forEach((v, id) => {
      const header = eventHeader(ids, de.domain, 0, id);
      const args = v.fields.map((_, k) => `flat[p + ${k}]`).join(', ');
      arms.push(`\t\t\tif(${header})\n\t\t\t\tSSvg.on_${de.domain}_${snake(v.name)}(${args})\n`);
    });
  }
  if (arms.length) {
    dm += `\t\tswitch(header)\n${arms.join('')}`;
  }
  dm += '\n';
  return dm;
}

function componentCanonical(c: Component): string {
  const fields = c.fields
    .map((f) => `${f.id}:${f.name}:${f.role}:${f.unit ?? ''}:${f.min ?? ''}:${f.max ?? ''}:${f.onInvalid}:${f.conserve ?? ''}`)
    .join(',');
  const events = c.events
    .flatMap((e) => e.variants)
    .map((v) => `${v.name}(${v.fields.join(' ')})`)
    .join(',');
  return `${c.domain}/${c.structName}#${c.kind}:${c.owner}=${c.dmType}[${fields}]{${events}}`;
}

function domainEventsCanonical(d: DomainEvents): string {
  return `${d.domain}!${d.decl.name}{${d.decl.variants.map((v) => `${v.name}(${v.fields.join(' ')})`).join(',')}}`;
}

function abiOf(binds: Bind[], defines: Define[], components: Component[], domainEvents: DomainEvents[]): string {
  const canonical = [
    ...binds.map((b) => `${b.name}(${b.args === null ? '...' : b.args.length})`),
    ...defines.map((d) => `${d.name}=${d.value}`),
    ...components.map(componentCanonical),
    ...domainEvents.map(domainEventsCanonical),
  ].join('\n');
  return createHash('sha256').update(canonical).digest('hex').slice(0, 16);
}

function docBlock(docs: string[], indent = ''): string {
  return docs.map((d) => `${indent}/// ${d}`.trimEnd() + '\n').join('');
}

export function render(root: string): { dm: string; typesDm: string; rs: string; binds: number } {
  const { binds, defines } = scan(root);
  const { components, domainEvents } = scanComponents(root);
  for (const c of components) {
    if (c.dmType) checkDmTypeExists(root, c);
  }
  const abi = abiOf(binds, defines, components, domainEvents);
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

#if defined(BENCHMARK) || defined(UNIT_TESTS)
/// FFI calls made through the vg_* procs. Benchmark and unit-test builds
/// only: the benchmarks report it per window (code/modules/benchmarks/_benchmark.dm)
/// and tests assert that DM-only paths make none.
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
  const typesDm = renderComponentsDm(root, components, domainEvents);
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
