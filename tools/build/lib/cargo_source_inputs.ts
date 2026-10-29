import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';

// Deliberately feature-conservative: optional/dev/target/build path dependencies
// are inputs too. No Cargo subprocess, feature resolver, or compiler invocation.
// External local include/build inputs require package/workspace metadata
// dq-source-key.inputs; arbitrary undeclared dynamic reads are unsupported.
type Table = Record<string, unknown>;
const table = (v: unknown): Table => {
  if (v === undefined) return {};
  if (!v || typeof v !== 'object' || Array.isArray(v)) throw new Error('expected Cargo table');
  return v as Table;
};
const SKIP = new Set(['.git', 'target', 'node_modules', '.cache']);
// Bun 1.3.14's TOML parser accepts malformed input such as "[package\ninvalid".
// Use Python's strict, complete TOML implementation for the actual values, not
// merely for a syntax check followed by another parser with different behavior.
// Python is already a build prerequisite. Stdin owns the exact bytes just read;
// this process never opens a manifest or a second filesystem source snapshot.
function strictCargoDocuments(documents: Record<string,string>): Record<string,Table> {
  const python=process.platform==='win32'?'python':'python3';
  const script='import sys,json,tomllib\nfrom datetime import date,time\ndef temporal(v):\n if isinstance(v,(date,time)): return {"__toml_temporal__":v.isoformat()}\n raise TypeError(type(v).__name__)\ndocs=json.load(sys.stdin)\njson.dump({k:tomllib.loads(v) for k,v in docs.items()},sys.stdout,default=temporal)';
  const result=spawnSync(python,['-c',script],{input:JSON.stringify(documents),encoding:'utf8',maxBuffer:16*1024*1024,windowsHide:true});
  if(result.error||result.status!==0) throw new Error(`strict Cargo TOML parsing failed: ${result.error?.message||result.stderr.trim()}`);
  return table(JSON.parse(result.stdout)) as Record<string,Table>;
}
export function parseCargoToml(text: string): Table {
  return strictCargoDocuments({document:text}).document;
}
function canonical(value:unknown):string {
  if(Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if(value&&typeof value==='object') return `{${Object.keys(value).sort().map(k=>`${JSON.stringify(k)}:${canonical((value as Table)[k])}`).join(',')}}`;
  const encoded=JSON.stringify(value);
  if(encoded===undefined) throw new Error('unrepresentable Cargo TOML value');
  return encoded;
}
export function cargoSourceInputs(repository: string, manifest: string): { files: string[]; directories: string[]; missingPaths: string[] } {
  const root = fs.realpathSync(repository);
  const files = new Set<string>();
  const directories = new Set<string>();
  const visited = new Set<string>();
  const missingPaths=new Set<string>();
  const parsed=new Map<string,Table>();
  const documents:Record<string,string>=Object.create(null);
  function admitted(p: string): string {
    const real = fs.realpathSync(p); // missing inputs are fatal, never '<missing>'
    const rel = path.relative(root, real);
    if (rel === '..' || rel.startsWith(`..${path.sep}`) || path.isAbsolute(rel)) throw new Error(`Cargo input outside repository: ${p}`);
    for(let at=real;at!==root;at=path.dirname(at)) {
      const name=path.basename(at),parent=path.dirname(at);
      if(name==='.git'||(SKIP.has(name)&&fs.existsSync(path.join(parent,'Cargo.toml')))) throw new Error(`Cargo input points into build/cache output: ${p}`);
    }
    return real;
  }
  function walk(p: string): void {
    p = admitted(p);
    const stat = fs.statSync(p);
    if (stat.isFile()) { files.add(p); return; }
    if (!stat.isDirectory()) throw new Error(`unsupported Cargo source input: ${p}`);
    const packageRoot=fs.existsSync(path.join(p,'Cargo.toml'));
    // Cargo's directory watches recurse into build outputs. Watch source
    // subdirectories, not package roots which also contain target/.
    if(!packageRoot) directories.add(p);
    for (const entry of fs.readdirSync(p, { withFileTypes: true }).sort((a,b)=>a.name.localeCompare(b.name, 'en'))) {
      if (entry.name==='.git'||(packageRoot&&SKIP.has(entry.name))) continue;
      // Following junctions could accidentally ingest build caches or another
      // checkout. A source symlink needs an explicit source-input contract.
      if (entry.isSymbolicLink()) throw new Error(`symlink in Cargo source inputs: ${path.join(p, entry.name)}`);
      walk(path.join(p, entry.name));
    }
  }
  function read(p: string): Table {
    p = admitted(p); files.add(p);
    const cached=parsed.get(p);if(cached) return cached;
    const text=new TextDecoder('utf-8',{fatal:true,ignoreBOM:true}).decode(fs.readFileSync(p));documents[p]=text;
    // Discovery is provisional only. A single strict batch below must prove
    // both syntax and exact semantic agreement before any identity is issued.
    const value=table(Bun.TOML.parse(text));parsed.set(p,value);return value;
  }
  function workspace(dir: string, own: Table): { dir: string; cargo: Table } | undefined {
    const explicit = table(own.package).workspace;
    if (explicit !== undefined) {
      if (typeof explicit !== 'string') throw new Error('package.workspace must be a path');
      const d = admitted(path.resolve(dir, explicit));
      const cargo = read(path.join(d, 'Cargo.toml'));
      if (!cargo.workspace) throw new Error('explicit workspace has no workspace table');
      return { dir: d, cargo };
    }
    for (let d = dir; ; d = path.dirname(d)) {
      const p = path.join(d, 'Cargo.toml');
      if (fs.existsSync(p)) {
        const cargo = read(p);
        if (cargo.workspace) return { dir: d, cargo };
      }
      if (d === root || path.dirname(d) === d) return undefined;
    }
  }
  function visit(p: string): void {
    p = admitted(p);
    if (visited.has(p)) return;
    visited.add(p);
    const cargo = read(p), dir = path.dirname(p), ws = workspace(dir, cargo);
    walk(dir);
    // Parent workspace lock and config influence resolution even when the
    // analyzer has its own workspace and a dependency belongs to another one.
    for (const d of new Set([dir, ...(ws ? [ws.dir] : [])])) {
      const lock = path.join(d, 'Cargo.lock'); if (fs.existsSync(lock)) files.add(admitted(lock)); else missingPaths.add(lock);
    }
    for (let at=dir;;at=path.dirname(at)) {
      const config=path.join(at,'.cargo');
      if(fs.existsSync(config)) walk(config);
      for(const name of ['config','config.toml']) {
          const file=path.join(config,name); if(!fs.existsSync(file)) {missingPaths.add(file);continue;}
          const settings=read(file);
          dependencies({patch:settings.patch,replace:settings.replace},at);
          if(settings.paths!==undefined) {
            if(!Array.isArray(settings.paths)||settings.paths.some(x=>typeof x!=='string')) throw new Error('Cargo config paths must be strings');
            for(const override of settings.paths as string[]) visit(path.resolve(at,override,'Cargo.toml'));
          }
      }
      if(at===root||path.dirname(at)===at) break;
    }
    for (const [base, owner] of [[dir, cargo], ...(ws && ws.dir !== dir ? [[ws.dir, ws.cargo]] : [])] as [string, Table][]) {
      const metadata = table(table(owner.package).metadata);
      const workspaceMetadata = table(table(owner.workspace).metadata);
      for (const md of [metadata, workspaceMetadata]) {
        const inputs = table(md['dq-source-key']).inputs;
        if (inputs !== undefined) {
          if (!Array.isArray(inputs) || inputs.some(x=>typeof x !== 'string')) throw new Error('dq-source-key.inputs must be path strings');
          for (const item of inputs as string[]) walk(path.resolve(base, item));
        }
      }
    }
    function dependency(name: string, value: unknown, base: string): void {
      if (typeof value === 'string') return;
      let spec = table(value);
      if (spec.workspace === true) {
        if (!ws) throw new Error(`inherited dependency ${name} has no workspace`);
        const inherited = table(table(ws.cargo.workspace).dependencies)[name];
        if (inherited === undefined) throw new Error(`missing workspace dependency ${name}`);
        if (typeof inherited === 'string') return;
        spec = table(inherited); base = ws.dir;
      }
      if (spec.path !== undefined) {
        if (typeof spec.path !== 'string') throw new Error(`invalid dependency path ${name}`);
        visit(path.resolve(base, spec.path, 'Cargo.toml'));
      }
    }
    function dependencies(owner: Table, base: string): void {
      for (const key of ['dependencies','dev-dependencies','build-dependencies']) {
        for (const [name,value] of Object.entries(table(owner[key]))) dependency(name,value,base);
      }
      for (const target of Object.values(table(owner.target))) dependencies(table(target),base);
      for (const patch of Object.values(table(owner.patch))) for (const [name,value] of Object.entries(table(patch))) dependency(name,value,base);
      for (const [name,value] of Object.entries(table(owner.replace))) dependency(name,value,base);
    }
    dependencies(cargo,dir);
    if (ws && ws.dir !== dir) {
      // Workspace patches/replace are effective even without an inherited dep.
      dependencies({ patch: ws.cargo.patch, replace: ws.cargo.replace },ws.dir);
    }
  }
  visit(manifest);
  const strict=strictCargoDocuments(documents);
  for(const [file,provisional] of parsed) {
    if(canonical(strict[file])!==canonical(provisional)) throw new Error(`Cargo TOML parser disagreement; source identity refused: ${file}`);
  }
  const relative = (p: string) => path.relative(root,p).split(path.sep).join('/');
  return { files: [...files].map(relative).sort(), directories: [...directories].map(relative).sort(), missingPaths:[...missingPaths].map(relative).sort() };
}
export function cargoSourceKey(repository: string, manifest: string, salt: string): string {
  const closure = cargoSourceInputs(repository, manifest);
  const hash = createHash('sha256');
  const frame = (bytes: string | Buffer) => { const b=typeof bytes==='string'?Buffer.from(bytes):bytes; hash.update(`${b.length}:`); hash.update(b); };
  frame('cargo-source-closure-v1'); frame(salt);
  for (const missing of closure.missingPaths) { frame('absent'); frame(missing); }
  for (const file of closure.files) { frame(file); frame(fs.readFileSync(path.resolve(repository,file))); }
  return hash.digest('hex').slice(0,32);
}
