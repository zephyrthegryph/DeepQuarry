//! Port of `tools/ci/ownership_lint.py` `main()` (doc/rewrite/ownership.md sec 7-8): the static half
//! of own / shared / proto / relation. The structure index (`Index`, `proc_scopes`, the write
//! regexes) is `dm::ownership_index`; this file builds the accessor-usage map and runs the checks:
//!
//! * `unknown_var`  an accessor naming a var the receiver's type does not have
//! * `string_name`  an accessor naming its var with a string literal (`nameof()` instead)
//! * `kinds`        one kind per var across the hierarchy
//! * `matrix`       OWN / REL of a registry type, SHARED of a non-registry type, a gas mixture written
//!                  as a relation, SPILL / CONTAINED on a non-movable var type
//! * `contradiction` one var written as owned and as a relation, or against its declaration
//! * `removed`      the deleted declaration forms
//! * `callback`     `CALLBACK(` outside the core
//! * `handle`       `om_handle()` / `om_resolve()` / a `*_handle` var outside the core
//! * `raw_write`    an entity var written outside the ownership accessors
//!
//! Every problem fails (`Policy::Hard`; the check name is the rule). Paths under the `[lint.ownership]`
//! exemptions of `lint_scopes.toml` (unit tests, benchmarks, vendored TGS: `allow_annotations.exempt_path`)
//! are skipped by `string_name`, `removed`, `callback`, `handle` and `raw_write` only: the index, the
//! usage map, `unknown_var`, `kinds`, `matrix` and `contradiction` read every file.
//!
//! Quirks kept (the Python is the oracle):
//! * `ACCESSOR` / `TRANSFER_DEST` and the string-name check read the RAW line at the CODE view's line
//!   number (a trailing comment on a proc-body line still counts; an unbalanced `'` in the code view
//!   drifts the numbers, exactly as in the Python);
//! * `unknown_var` has no ALLOW and no exemption;
//! * SUSPECTED BUGS in the Python, kept: the `string_name` confirmation regex and `OBJ_TOKEN` were committed
//!   with a literal backspace byte where `\b` was meant. The first makes `string_name` fire only on a line
//!   with a U+0008 before the call name (see `file_checks`); the second is harmless (`new\x08` never matches,
//!   the identifier alternative matches `new` instead, the same token the shared index gets from `new`);
//! * a receiver type that is `""` (an untyped member) is as good as None everywhere the Python tests
//!   its truthiness, so both are stored as `""`;
//! * the Python keeps the usage as hash-ordered sets, so which of several `rel_*` sites a `contradiction`
//!   is reported at (the first match, then `break`) is not stable between Python runs; here the sets are
//!   sorted by `(receiver type, file, line)`.

use std::collections::{BTreeSet, HashMap};
use std::sync::{Arc, RwLock};

use serde::{Deserialize, Serialize};

use crate::dm::ownership_index::{self as oi,
    creates_entity, proc_scopes, puts_object, receiver_type, related, Index, OrdMap, ACCESSOR, CALLBACK, CALLBACK_OK, CORE_DIRS, ENTITY_ROOTS, HANDLE_CALL,
    HANDLE_OK, HANDLE_VAR, OBJLIST_WRITES, OWN_FUNCS, PROTO_FUNCS, REL_FUNCS, REL_WRITERS, REMOVED, STRING_NAME, TRANSFER_DEST, WRITE_ASSIGN, WRITE_INDEX,
    WRITE_MACRO, WRITE_METHOD,
};
use crate::incr;
use crate::lint::{AllowUse, Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::pat;
use crate::tree::{SourceFile, CODE_DM};
use crate::util::{before_slashes, py_lstrip, py_rstrip, py_strip, starts_with_any, under};

const LINT: &str = "ownership";

const H_RAW_WRITE: &str = "write it through own_* / rel_* / proto_* (doc/rewrite/ownership.md), or keep with // ALLOW(ownership): <reason>";
const H_CONTRADICTION: &str = "one var is one kind: write it through one accessor family that matches its declaration";
const H_KINDS: &str = "related types must declare the same kind for a var";
const H_MATRIX: &str = "a registry type is SHARED, a per-holder copy is PROTO, and a holder owns its gas mixture";
const H_CALLBACK: &str = "defer with om_after(), which holds arguments as handles";
const H_HANDLE: &str = "a content var naming an entity is a relation view: use rel_set()";
const H_UNKNOWN_VAR: &str = "name a var the receiver's type declares, with nameof()";
const H_STRING_NAME: &str = "name the var with nameof(var), nameof(x.var) or nameof(/type::var)";
const H_REMOVED: &str = "use the ownership() / relations() declarations (doc/rewrite/ownership.md)";

static META: Meta = Meta {
    name: crate::allow_registry_fields::ownership::SCOPE_META_0.name,
    group: crate::allow_registry_fields::ownership::SCOPE_META_0.group,
    label: "ownership",
    legacy: "tools/ci/ownership_lint.py",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "raw_write", hint: H_RAW_WRITE },
        RuleMeta { name: "contradiction", hint: H_CONTRADICTION },
        RuleMeta { name: "kinds", hint: H_KINDS },
        RuleMeta { name: "matrix", hint: H_MATRIX },
        RuleMeta { name: "callback", hint: H_CALLBACK },
        RuleMeta { name: "handle", hint: H_HANDLE },
        RuleMeta { name: "unknown_var", hint: H_UNKNOWN_VAR },
        RuleMeta { name: "string_name", hint: H_STRING_NAME },
        RuleMeta { name: "removed", hint: H_REMOVED },
    ],
    allow: crate::allow_registry_fields::ownership::ALLOW_0,
    lists: crate::allow_registry_fields::ownership::SCOPE_META_0.lists,
};

/// `decl_kind_of`: an old declaration macro name -> the kind it declares (ANNOTATE and the rest: none).
fn decl_kind_of(macro_name: &str) -> Option<&'static str> {
    match macro_name {
        "OWN" | "OWN_POLICY" | "OWN_IF" => Some("OWN"),
        "SHARED" => Some("SHARED"),
        "PROTO" => Some("PROTO"),
        "REL" | "REL_LIST" | "REL_PAIR" | "REL_PAIR_LIST" | "REL_SET" | "REL_KEYED" | "REL_KEYED_LIST" => Some("REL"),
        _ => None,
    }
}

/// `"entity"` (a single entity var) or `"list"` (an entity list).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Vk {
    Entity,
    List,
}

/// `(receiver type or "", file, line)`: one accessor write. An unknown receiver type is `""`.
pub(crate) type Loc = (String, String, usize);

#[derive(Default)]
pub(crate) struct UsageKinds {
    pub(crate) own: BTreeSet<Loc>,
    /// `rel_link` / `rel_unlink`: a true relation write.
    pub(crate) rel: BTreeSet<Loc>,
    /// `rel_set` / `rel_add` / `rel_remove` / `rel_clear`: the writers that replace `own_*`. They count as
    /// an owner's write (no contradiction with `own_*`, no gas-mixture matrix hit) and are also accepted on a REL var.
    pub(crate) relw: BTreeSet<Loc>,
    pub(crate) proto: BTreeSet<Loc>,
    pub(crate) shared: BTreeSet<Loc>,
}

pub(crate) struct Problem {
    pub(crate) check: &'static str,
    pub(crate) rel: String,
    pub(crate) line: usize,
    pub(crate) msg: String,
}

/// Check names a cached per-line result stores by index.
pub(crate) const LINE_CHECKS: [&str; 3] = ["removed", "callback", "handle"];

/// What the accessor-usage pass finds in one file (kinds: 0 OWN, 1 REL link, 2 PROTO, 3 SHARED, 4 REL writer).
#[derive(Serialize, Deserialize, Default, PartialEq)]
pub(crate) struct UsageScan {
    /// `(var name, kind index, receiver type or "", line)` in discovery order
    pub(crate) events: Vec<(String, u8, String, u32)>,
    /// `unknown_var` reports `(line, message)`
    pub(crate) unknown: Vec<(u32, String)>,
}

/// One file's index-independent per-line results (`string_name`, `removed`, `callback`, `handle`).
#[derive(Serialize, Deserialize, Default, PartialEq)]
pub(crate) struct Content {
    pub(crate) string_name: Vec<(u32, String)>,
    /// `(LINE_CHECKS index, line, message)`
    pub(crate) lines: Vec<(u8, u32, String)>,
    pub(crate) uses: Vec<AllowUse>,
}

/// One file's `raw_write` results.
#[derive(Serialize, Deserialize, Default, PartialEq)]
pub(crate) struct RawOut {
    pub(crate) lines: Vec<(u32, String)>,
    pub(crate) uses: Vec<AllowUse>,
}

fn allowed_using<C:crate::key_policy_control::Control>(uses:&mut Vec<AllowUse>,file:&SourceFile,line:usize,c:&mut C)->Result<bool,C::Error>{c.checkpoint()?;let Some(keep)=crate::allow::kept_using(file,line,LINT,c)?else{return Ok(false)};let code=keep.code.unwrap_or_default();for used in uses.iter(){c.checkpoint()?;if used.rel==file.rel&&used.line as usize==keep.line&&used.name==LINT&&used.code==code{return Ok(true)}}crate::key_policy_control::row(c,uses)?;crate::key_policy_control::reserve(c,||code.capacity().checked_add(64))?;uses.push(AllowUse{rel:crate::key_policy_control::own(c,&file.rel)?,line:keep.line as u32,name:crate::key_policy_control::own(c,LINT)?,code});Ok(true)}

pub(crate) fn usage_scan(idx: &Index, f: &SourceFile) -> UsageScan {
    usage_scan_using(idx,f,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{})
}
pub(crate) fn usage_scan_using<C:crate::key_policy_control::Control>(idx:&Index,f:&SourceFile,c:&mut C)->Result<UsageScan,C::Error>{
    let raw = f.raw();
    let mut sc = UsageScan::default();
    oi::proc_scopes_using(f.code(),c,&mut|no,_line,owner,_proc,local_types,c|{
        let rl = raw.line(no);
        for m in ACCESSOR.captures_iter(rl) {c.checkpoint()?;crate::key_policy_control::temporary(c,4,||owner.len().checked_add(local_types.get(m.s(2)).and_then(|t|t.as_ref()).map_or(0,|t|t.len()))?.checked_mul(16)?.checked_add(1024))?;
            let (func, recv, name) = (m.s(1), m.s(2), m.s(3));
            let mut rtype: Option<String> =
                if recv == "src" { Some(owner.to_string()) } else { local_types.get(recv).and_then(|t| t.clone()) };
            if rtype.is_none() && recv != "src" {
                rtype = idx.member_using(owner,recv,c)?.map(|g| g.vtype);
            }
            let rtype = rtype.unwrap_or_default();
            let kind: u8 = if OWN_FUNCS.contains(&func) {
                0
            } else if REL_FUNCS.contains(&func) {
                if REL_WRITERS.contains(&func) {
                    4
                } else {
                    1
                }
            } else if PROTO_FUNCS.contains(&func) {
                2
            } else {
                3
            };
            crate::key_policy_control::row(c,&mut sc.events)?;
            sc.events.push((crate::key_policy_control::own(c,name)?, kind, crate::key_policy_control::own(c,&rtype)?, no as u32));
            // The var named by the string must exist: on the receiver's type when it is known, else
            // on some type (a string var name can't be checked by the compiler).
            if recv == "GLOB" && rtype.is_empty() && !local_types.contains_key(recv) {
                // A global: `GLOB` is the global_vars controller, whose vars are declared by the GLOBAL_* macros.
                if !idx.globals.contains_key(name) {
                    crate::key_policy_control::row(c,&mut sc.unknown)?;sc.unknown.push((no as u32, crate::key_policy_control::format(c,format_args!("{}({}, \"{}\"): {} has no global {}", func, recv, name, oi::GLOB_TYPE, name))?));
                }
            } else if !rtype.is_empty() && under(&rtype, ENTITY_ROOTS) {
                crate::key_policy_control::temporary(c,7,||rtype.len().checked_mul(4)?.checked_add(128))?;let prefix = format!("{}/", rtype);
                let mut on_subtype=false;if let Some(v)=idx.name_decls.get(name){for(t,_,_)in v{c.checkpoint()?;if t.starts_with(&prefix){on_subtype=true;break}}}
                if idx.member_using(&rtype,name,c)?.is_none() && !on_subtype {
                    crate::key_policy_control::row(c,&mut sc.unknown)?;sc.unknown.push((no as u32, crate::key_policy_control::format(c,format_args!("{}({}, \"{}\"): {} has no var {}", func, recv, name, rtype, name))?));
                }
            } else if idx.name_decls.get(name).map(|v| v.is_empty()).unwrap_or(true) {
                crate::key_policy_control::row(c,&mut sc.unknown)?;sc.unknown.push((no as u32, crate::key_policy_control::format(c,format_args!("{}({}, \"{}\"): no type declares a var {}", func, recv, name, name))?));
            }
        }
        for m in TRANSFER_DEST.captures_iter(rl) {c.checkpoint()?;crate::key_policy_control::temporary(c,4,||owner.len().checked_add(local_types.get(m.s(2)).and_then(|t|t.as_ref()).map_or(0,|t|t.len()))?.checked_mul(16)?.checked_add(1024))?;
            let (recv, name) = (m.s(1), m.s(2));
            let rtype: String = if recv == "src" { owner.to_string() } else { local_types.get(recv).and_then(|t| t.clone()).unwrap_or_default() };
            crate::key_policy_control::row(c,&mut sc.events)?;crate::key_policy_control::reserve(c,||rtype.capacity().checked_add(32))?;sc.events.push((crate::key_policy_control::own(c,name)?, 0, rtype, no as u32));
        }
        Ok(())
    })?;
    Ok(sc)
}

/// Everything the per-line checks need, shared across the file workers.
pub(crate) struct Ctx {
    pub(crate) idx: Arc<Index>,
    pub(crate) usage: OrdMap<UsageKinds>,
    vk_cache: RwLock<HashMap<(String, String), (Option<Vk>, Option<String>)>>,
    amb_cache: RwLock<HashMap<String, Option<Vk>>>,
}

impl Ctx{
 pub(crate) fn retained_cache_bound_using<C:crate::key_policy_control::Control>(&self,c:&mut C)->Result<usize,C::Error>{let values=self.vk_cache.read().unwrap();let ambiguous=self.amb_cache.read().unwrap();let mut bytes=values.capacity().checked_mul(4*std::mem::size_of::<((String,String),(Option<Vk>,Option<String>))>()).and_then(|n|n.checked_add(ambiguous.capacity().checked_mul(4*std::mem::size_of::<(String,Option<Vk>)>())?)).and_then(|n|n.checked_add(1024)).ok_or_else(||c.overflow())?;for((owner,name),(_,decl))in values.iter(){c.checkpoint()?;for text in [Some(owner),Some(name),decl.as_ref()].into_iter().flatten(){bytes=bytes.checked_add(text.capacity()).and_then(|n|n.checked_add(64)).ok_or_else(||c.overflow())?;}}for(name,_)in ambiguous.iter(){c.checkpoint()?;bytes=bytes.checked_add(name.capacity()).and_then(|n|n.checked_add(64)).ok_or_else(||c.overflow())?;}Ok(bytes)}

 pub(crate) fn new(idx:Arc<Index>,usage:OrdMap<UsageKinds>)->Self{Self{idx,usage,vk_cache:RwLock::new(HashMap::new()),amb_cache:RwLock::new(HashMap::new())}}
 fn is_shared_decl(&self,rtype:&str,name:&str)->bool{self.is_shared_decl_using(rtype,name,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{})}
 fn is_shared_decl_using<C:crate::key_policy_control::Control>(&self,rtype:&str,name:&str,c:&mut C)->Result<bool,C::Error>{Ok(match self.idx.decl_using(rtype,name,c)?{Some((_,d))=>decl_kind_of(&d.macro_name)==Some("SHARED"),None=>false})}
 fn var_kind(&self,owner:&str,name:&str)->(Option<Vk>,Option<String>){self.var_kind_using(owner,name,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{})}
 fn var_kind_using<C:crate::key_policy_control::Control>(&self,owner:&str,name:&str,c:&mut C)->Result<(Option<Vk>,Option<String>),C::Error>{c.checkpoint()?;crate::key_policy_control::temporary(c,6,||owner.len().checked_add(name.len())?.checked_mul(8)?.checked_add(512))?;let key=(owner.to_owned(),name.to_owned());if let Some(value)=self.vk_cache.read().unwrap().get(&key){crate::key_policy_control::temporary(c,6,||owner.len().checked_add(name.len())?.checked_add(value.1.as_ref().map_or(0,|s|s.len()))?.checked_mul(8)?.checked_add(512))?;return Ok(value.clone())}let value=self.var_kind_uncached_using(owner,name,c)?;oi::map_room(&*self.vk_cache.read().unwrap(),c)?;crate::key_policy_control::reserve(c,||owner.len().checked_add(name.len())?.checked_add(value.1.as_ref().map_or(0,|s|s.len()))?.checked_add(96))?;self.vk_cache.write().unwrap().insert(key,value.clone());Ok(value)}

 fn var_kind_uncached(&self,owner:&str,name:&str)->(Option<Vk>,Option<String>){self.var_kind_uncached_using(owner,name,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{})}
 fn var_kind_uncached_using<C:crate::key_policy_control::Control>(&self,owner:&str,name:&str,c:&mut C)->Result<(Option<Vk>,Option<String>),C::Error>{let idx=&self.idx;let Some(got)=idx.member_using(owner,name,c)?else{return Ok((None,None))};let(dtype,vtype,is_list)=(got.declared_on,got.vtype,got.is_list);let dkind=idx.decl_using(owner,name,c)?.and_then(|(_,d)|decl_kind_of(&d.macro_name));if dkind==Some("SHARED"){return Ok((None,Some(dtype)))}if matches!(dkind,Some("OWN")|Some("REL")|Some("PROTO")){return Ok((Some(if is_list||vtype.is_empty(){Vk::List}else{Vk::Entity}),Some(dtype)))}if let Some(used)=self.usage.get(name){for set in[&used.own,&used.rel,&used.relw,&used.proto]{for(t,_,_)in set{c.checkpoint()?;crate::key_policy_control::temporary(c,7,||t.len().checked_add(owner.len())?.checked_mul(4)?.checked_add(128))?;if !t.is_empty()&&related(t,owner){if let Some(member)=idx.member_using(t,name,c)?{if member.declared_on==dtype{return Ok((Some(if is_list{Vk::List}else{Vk::Entity}),Some(dtype)))}}}}}}if is_list{return Ok((if idx.is_entity_using(&vtype,c)?{Some(Vk::List)}else{None},Some(dtype)))}Ok((if idx.is_entity_using(&vtype,c)?{Some(Vk::Entity)}else{None},Some(dtype)))}
 fn unknown_receiver_kind(&self,name:&str)->Option<Vk>{self.unknown_receiver_kind_using(name,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{})}
 fn unknown_receiver_kind_using<C:crate::key_policy_control::Control>(&self,name:&str,c:&mut C)->Result<Option<Vk>,C::Error>{c.checkpoint()?;if let Some(value)=self.amb_cache.read().unwrap().get(name){return Ok(*value)}let mut kinds=Vec::new();if let Some(decls)=self.idx.name_decls.get(name){for(owner,_,_)in decls{c.checkpoint()?;let(kind,_)=self.var_kind_using(owner,name,c)?;if !kinds.contains(&kind){crate::key_policy_control::row(c,&mut kinds)?;kinds.push(kind)}}}let value=if kinds.len()==1{kinds[0]}else{None};oi::map_room(&*self.amb_cache.read().unwrap(),c)?;crate::key_policy_control::reserve(c,||name.len().checked_add(32))?;self.amb_cache.write().unwrap().insert(name.to_owned(),value);Ok(value)}
}

/// The index-independent checks of one file (`string_name`, `removed`, `callback`, `handle`).
pub(crate) fn content_checks(f: &SourceFile) -> Content {
    content_checks_using(f,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{})
}
pub(crate) fn content_checks_using<C:crate::key_policy_control::Control>(f:&SourceFile,c:&mut C)->Result<Content,C::Error>{
    let mut res = Content::default();
    let raw = f.raw();
    let code = f.code();
    let rel = f.rel.as_str();

    // string_name: code_only() blanks string contents, so match the raw line where the code line has a call.
    for(no,line)in code.numbered(){c.checkpoint()?;
        if !line.contains('(') {
            continue;
        }
        let Some(hit) = STRING_NAME.captures(before_slashes(raw.line(no))) else { continue };
        let name = if hit.s(1).is_empty() { hit.s(2) } else { hit.s(1) };
        // The call itself must be code (a name inside a string or comment is blanked in `line`).
        // SUSPECTED BUG, kept: the Python's `re.search(r"\b%s\(" % name, line)` was committed with a literal
        // backspace byte (0x08) where `\b` belongs, so it needs a U+0008 right before the name and
        // string_name fires only on a line that carries one (never, in the real tree).
        crate::key_policy_control::temporary(c,2,||name.len().checked_mul(4)?.checked_add(128))?;
        if line.contains(&format!("\u{8}{}(", name)) && !allowed_using(&mut res.uses,f,no,c)? {
            crate::key_policy_control::row(c,&mut res.string_name)?;res.string_name.push((no as u32, crate::key_policy_control::format(c,format_args!("{}(): name the var with nameof(), not a string", name))?));
        }
    }

    // removed / callback / handle
    for no in 1..=raw.num_lines(){c.checkpoint()?;
        let current = code.line(no);
        if let Some(m) = REMOVED.find(current) {
            if !rel.starts_with("tools/") && !allowed_using(&mut res.uses,f,no,c)? {
                crate::key_policy_control::row(c,&mut res.lines)?;res.lines.push((0, no as u32, crate::key_policy_control::format(c,format_args!("{} was removed (doc/rewrite/ownership.md)", m.as_str()))?));
            }
        }
        if CALLBACK.is_match(current) && !starts_with_any(rel, CALLBACK_OK) && !allowed_using(&mut res.uses,f,no,c)? {
            crate::key_policy_control::row(c,&mut res.lines)?;res.lines.push((1, no as u32, crate::key_policy_control::own(c,"CALLBACK outside the core: use om_after() (arguments held as handles)")?));
        }
        if !starts_with_any(rel, HANDLE_OK) {
            if let Some(m) = HANDLE_CALL.captures(current) {
                if !allowed_using(&mut res.uses,f,no,c)? {
                    crate::key_policy_control::row(c,&mut res.lines)?;res.lines.push((2, no as u32, crate::key_policy_control::format(c,format_args!("om_{}() in content: a var naming an entity is a relation view (rel_set)", m.s(1)))?));
                }
            }
            if let Some(hm) = HANDLE_VAR.captures(current) {
                if !allowed_using(&mut res.uses,f,no,c)? {
                    let var = if hm.s(1).is_empty() { hm.s(3) } else { hm.s(1) };
                    crate::key_policy_control::row(c,&mut res.lines)?;res.lines.push((2, no as u32, crate::key_policy_control::format(c,format_args!("var {}: a content var naming an entity is a relation view, not a handle", var))?));
                }
            }
        }
    }
    Ok(res)
}

/// The `raw_write` check of one file (outside the core directories).
pub(crate) fn raw_checks(cx: &Ctx, f: &SourceFile) -> RawOut {
    raw_checks_using(cx,f,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{})
}
pub(crate) fn raw_checks_using<C:crate::key_policy_control::Control>(cx:&Ctx,f:&SourceFile,c:&mut C)->Result<RawOut,C::Error>{
    let mut res = RawOut::default();
    if starts_with_any(f.rel.as_str(), CORE_DIRS) {
        return Ok(res);
    }
    let mut problems: Vec<Problem> = Vec::new();
    raw_writes_using(cx,f,&mut res.uses,&mut problems,c)?;
    crate::key_policy_control::reserve(c,||problems.len().checked_mul(std::mem::size_of::<(u32,String)>())?.checked_add(64))?;
    res.lines = problems.into_iter().map(|p| (p.line as u32, p.msg)).collect();
    Ok(res)
}

/// One candidate write found on a proc-body line: `(receiver chain, var, how, text after it)`.
struct Hit {
    chain: String,
    name: String,
    how: String,
    rhs: String,
}

fn hit_room<C:crate::key_policy_control::Control>(hits:&mut Vec<Hit>,payload:&mut usize,width:Option<usize>,c:&mut C)->Result<(),C::Error>{if !C::CHECKED{return Ok(())}*payload=payload.checked_add(width.ok_or_else(||c.overflow())?).and_then(|n|n.checked_mul(1)).and_then(|n|n.checked_add(4*32)).ok_or_else(||c.overflow())?;let cap=if hits.len()==hits.capacity(){hits.capacity().checked_mul(2).map(|n|n.max(4)).ok_or_else(||c.overflow())?}else{hits.capacity()};crate::key_policy_control::temporary(c,3,||cap.checked_mul(2*std::mem::size_of::<Hit>())?.checked_add(payload.checked_mul(2)?)?.checked_add(128))?;if hits.len()==hits.capacity(){hits.try_reserve_exact(cap-hits.len()).map_err(|_|c.allocation_failed())?;}Ok(())}
fn raw_writes(cx: &Ctx, f: &SourceFile, sink: &mut Sink, problems: &mut Vec<Problem>) {
    let mut uses=Vec::new();raw_writes_using(cx,f,&mut uses,problems,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{});for used in uses{sink.replay_allow(used);}
}
pub(crate) fn raw_writes_using<C:crate::key_policy_control::Control>(cx:&Ctx,f:&SourceFile,uses:&mut Vec<AllowUse>,problems:&mut Vec<Problem>,c:&mut C)->Result<(),C::Error>{
    let idx = &*cx.idx;
    let rel = f.rel.as_str();
    oi::proc_scopes_using(f.code(),c,&mut|no,line,owner,proc,local_types,c|{c.checkpoint()?;
        let mut hits: Vec<Hit> = Vec::new();
        let mut hit_bytes=0usize;
        for m in WRITE_ASSIGN.captures_iter(line) {c.checkpoint()?;
            let (chain, name, op) = (m.s(1), m.s(2), m.s(3));
            let (start, end) = (m.start(0), m.end(0));
            let before = py_rstrip(&line[..start]);
            if before.ends_with("var") || pat!(r"var/(?:[\w/]+/)?$").is_match(&line[..start]) {
                continue;
            }
            if chain.is_empty() && (before.ends_with('(') || before.ends_with(',')) {
                continue; // a named argument or an assoc key in list(...)
            }
            if chain.is_empty() && local_types.contains_key(name) {
                continue;
            }
            if op == "=" && py_lstrip(&line[end..]).starts_with('=') {
                continue;
            }
            hit_room(&mut hits,&mut hit_bytes,chain.len().checked_add(name.len()).and_then(|n|n.checked_add(op.len())).and_then(|n|n.checked_add(line[end..].len())),c)?;
            hits.push(Hit { chain: chain.to_string(), name: name.to_string(), how: op.to_string(), rhs: line[end..].to_string() });
        }
        for m in WRITE_INDEX.captures_iter(line) {c.checkpoint()?;
            if m.s(1).is_empty() && local_types.contains_key(m.s(2)) {
                continue;
            }
            let whole = &line[m.start(0)..m.end(0)];
            let (a, b) = (whole.find('[').map(|i| i + 1).unwrap_or(0), whole.rfind(']').unwrap_or(whole.len()));
            let inner = if a <= b { &whole[a..b] } else { "" };
            hit_room(&mut hits,&mut hit_bytes,m.s(1).len().checked_add(m.s(2).len()).and_then(|n|n.checked_add(inner.len())).and_then(|n|n.checked_add(line[m.end(0)..].len())).and_then(|n|n.checked_add(4)),c)?;
            hits.push(Hit {
                chain: m.s(1).to_string(),
                name: m.s(2).to_string(),
                how: "[]=".to_string(),
                rhs: format!("{} {}", inner, &line[m.end(0)..]),
            });
        }
        for m in WRITE_METHOD.captures_iter(line) {c.checkpoint()?;
            if m.s(1).is_empty() && local_types.contains_key(m.s(2)) {
                continue;
            }
            hit_room(&mut hits,&mut hit_bytes,m.s(1).len().checked_add(m.s(2).len()).and_then(|n|n.checked_add(m.s(3).len())).and_then(|n|n.checked_add(line[m.end(0)..].len())).and_then(|n|n.checked_add(1)),c)?;
            hits.push(Hit { chain: m.s(1).to_string(), name: m.s(2).to_string(), how: format!(".{}", m.s(3)), rhs: line[m.end(0)..].to_string() });
        }
        for m in WRITE_MACRO.captures_iter(line) {c.checkpoint()?;
            if m.s(2).is_empty() && local_types.contains_key(m.s(3)) {
                continue;
            }
            hit_room(&mut hits,&mut hit_bytes,m.s(1).len().checked_add(m.s(2).len()).and_then(|n|n.checked_add(m.s(3).len())).and_then(|n|n.checked_add(line[m.end(0)..].len())),c)?;
            hits.push(Hit { chain: m.s(2).to_string(), name: m.s(3).to_string(), how: m.s(1).to_string(), rhs: line[m.end(0)..].to_string() });
        }
        for h in &hits {c.checkpoint()?;
            if matches!(
                h.name.as_str(),
                "src" | "usr" | "loc" | "contents" | "vars" | "overlays" | "underlays" | "vis_contents" | "verbs" | "screen" | "images"
            ) {
                continue;
            }
            let rtype = oi::receiver_type_using(idx,&h.chain,owner,local_types,c)?.filter(|t| !t.is_empty());
            let mut kind = match &rtype {
                Some(rt) => cx.var_kind_using(rt,&h.name,c)?.0,
                None if !h.chain.is_empty() => cx.unknown_receiver_kind_using(&h.name,c)?,
                None => continue,
            };
            if kind.is_none() && h.how == "=" && creates_entity(&h.rhs) {
                if let Some(rt) = &rtype {
                    // A member var assigned a new entity: whatever its declared type, the holder made
                    // it, so it owns it (own_set), unless declared otherwise.
                    if idx.member_using(rt,&h.name,c)?.is_some() && !cx.is_shared_decl_using(rt,&h.name,c)? {
                        kind = Some(Vk::Entity);
                    }
                }
            }
            if kind.is_none() && OBJLIST_WRITES.contains(&h.how.as_str()) && oi::puts_object_using(&h.rhs,local_types,&idx.registry,c)? {
                if let Some(rt) = &rtype {
                    // An untyped list var collecting entities (src, a new object, an entity-typed local):
                    // an object-keyed roster, which is an owned or relation list.
                    if let Some(g) = idx.member_using(rt,&h.name,c)? {
                        if g.is_list && !cx.is_shared_decl_using(rt,&h.name,c)? {
                            kind = Some(Vk::List);
                        }
                    }
                }
            }
            let Some(kind) = kind else { continue };
            if allowed_using(uses,f,no,c)? {
                continue;
            }
            crate::key_policy_control::row(c,problems)?;problems.push(Problem {
                check: "raw_write",
                rel: crate::key_policy_control::own(c,rel)?,
                line: no,
                msg: crate::key_policy_control::format(c,format_args!(
                    "{}{} {} in {}/{}: {} var; use the ownership accessors (own_*/rel_*)",
                    h.chain,
                    h.name,
                    h.how,
                    owner,
                    proc,
                    if kind == Vk::Entity { "an entity" } else { "an entity list" }
                ))?,
            });
        }
        Ok(())
    })?;
    c.checkpoint()
}

pub fn metadata()->&'static Meta{&META}

pub(crate) fn judge_global_using<C:crate::key_policy_control::Control>(idx:&Index,cxt:&Ctx,c:&mut C)->Result<Vec<Problem>,C::Error>{
                let mut problems: Vec<Problem> = Vec::new();
            // ---- kinds: one kind per var across the hierarchy
            struct Entry {
                t: String,
                kind: &'static str,
                rel: String,
                line: usize,
            }
            let mut by_name: OrdMap<Vec<Entry>> = OrdMap::new();
            for (t, vs) in idx.decls.iter() {c.checkpoint()?;
                for (v, d) in vs.iter() {c.checkpoint()?;
                    if let Some(kind) = decl_kind_of(&d.macro_name) {
                        oi::ord_room(&by_name,v,c)?;let rows=by_name.entry_or_insert_with(v,Vec::new);crate::key_policy_control::row(c,rows)?;rows.push(Entry{t:crate::key_policy_control::own(c,t)?,kind,rel:crate::key_policy_control::own(c,&d.rel)?,line:d.line});
                    }
                }
            }
            for (v, entries) in by_name.iter() {c.checkpoint()?;
                for (i, e1) in entries.iter().enumerate() {c.checkpoint()?;
                    for e2 in &entries[i + 1..] {c.checkpoint()?;crate::key_policy_control::temporary(c,7,||e1.t.len().checked_add(e2.t.len())?.checked_mul(4)?.checked_add(128))?;
                        if e1.kind != e2.kind && related(&e1.t, &e2.t) {
                            problem_room(c,&mut problems,idx)?;problems.push(Problem {
                                check: "kinds",
                                rel: crate::key_policy_control::own(c,&e2.rel)?,
                                line: e2.line,
                                msg: crate::key_policy_control::format(c,format_args!("{}.{} is {} here but {} on {} ({}:{}): one kind per var", e2.t, v, e2.kind, e1.kind, e1.t, e1.rel, e1.line))?,
                            });
                        }
                    }
                }
            }

            // ---- matrix
            for (t, vs) in idx.decls.iter() {c.checkpoint()?;
                for (v, d) in vs.iter() {c.checkpoint()?;
                    let Some(got) = idx.member_using(t,v,c)? else { continue };
                    let vtype = got.vtype.as_str();
                    let kind = decl_kind_of(&d.macro_name);
                    let a = d.opts.as_str();
                    if matches!(kind, Some("OWN") | Some("REL")) && idx.is_registry_using(vtype,c)? {
                        problem_room(c,&mut problems,idx)?;problems.push(Problem {
                            check: "matrix",
                            rel: crate::key_policy_control::own(c,&d.rel)?,
                            line: d.line,
                            msg: crate::key_policy_control::format(c,format_args!("{}.{} is typed {}, a registry type: it is SHARED (a per-holder copy is PROTO)", t, v, vtype))?,
                        });
                    }
                    if kind == Some("SHARED") && !vtype.is_empty() && under(vtype, ENTITY_ROOTS) && !idx.is_registry_using(vtype,c)? {
                        problem_room(c,&mut problems,idx)?;problems.push(Problem {
                            check: "matrix",
                            rel: crate::key_policy_control::own(c,&d.rel)?,
                            line: d.line,
                            msg: crate::key_policy_control::format(c,format_args!("{}.{} is SHARED but typed {}, which is not a REGISTRY_TYPE", t, v, vtype))?,
                        });
                    }
                    if d.macro_name == "OWN"
                        && (a.contains("OWN_SPILL") || a.contains("OWN_CONTAINED"))
                        && !vtype.is_empty()
                        && !under(vtype, &["/atom/movable", "/obj", "/mob"])
                    {
                        problem_room(c,&mut problems,idx)?;problems.push(Problem {
                            check: "matrix",
                            rel: crate::key_policy_control::own(c,&d.rel)?,
                            line: d.line,
                            msg: crate::key_policy_control::format(c,format_args!("{}.{}: {} needs a movable var type (got {})", t, v, py_strip(a), vtype))?,
                        });
                    }
                }
            }

            // ---- contradictions (usage vs usage, usage vs declaration, resources)
            for (name, kinds) in cxt.usage.iter() {c.checkpoint()?;
                for (t1, r1, n1) in &kinds.own {c.checkpoint()?;
                    for (t2, r2, n2) in &kinds.rel {c.checkpoint()?;crate::key_policy_control::temporary(c,7,||t1.len().checked_add(t2.len())?.checked_mul(4)?.checked_add(128))?;
                        if !t1.is_empty() && !t2.is_empty() && related(t1, t2) {
                            let m1 = idx.member_using(t1,name,c)?;
                            if m1.is_some() && m1 == idx.member_using(t2,name,c)? {
                                problem_room(c,&mut problems,idx)?;problems.push(Problem {
                                    check: "contradiction",
                                    rel: crate::key_policy_control::own(c,&r2)?,
                                    line: *n2,
                                    msg: crate::key_policy_control::format(c,format_args!("{}.{} is written as a relation here and as owned at {}:{}", t2, name, r1, n1))?,
                                });
                                break;
                            }
                        }
                    }
                }
                for (t, r, n) in &kinds.rel {c.checkpoint()?;
                    if t.is_empty() {
                        continue;
                    }
                    if let Some(got) = idx.member_using(t,name,c)? {
                        if got.vtype == "/datum/gas_mixture" {
                            problem_room(c,&mut problems,idx)?;problems.push(Problem {
                                check: "matrix",
                                rel: crate::key_policy_control::own(c,&r)?,
                                line: *n,
                                msg: crate::key_policy_control::format(c,format_args!("{}.{} holds a gas mixture: a holder owns its mixture (own_set), a network's is PROTO", t, name))?,
                            });
                        }
                    }
                    if let Some((_, d)) = idx.decl_using(t,name,c)? {
                        if !matches!(decl_kind_of(&d.macro_name), None | Some("REL")) {
                            problem_room(c,&mut problems,idx)?;problems.push(Problem {
                                check: "contradiction",
                                rel: crate::key_policy_control::own(c,&r)?,
                                line: *n,
                                msg: crate::key_policy_control::format(c,format_args!("{}.{} is declared {} but written with rel_*", t, name, d.macro_name))?,
                            });
                        }
                    }
                }
                for (t, r, n) in kinds.own.iter().chain(kinds.relw.iter()) {c.checkpoint()?;crate::key_policy_control::temporary(c,7,||t.len().checked_add(r.len())?.checked_mul(4)?.checked_add(128))?;
                    if t.is_empty() {
                        continue;
                    }
                    let is_relw = kinds.relw.contains(&(t.clone(), r.clone(), *n));
                    let d = idx.decl_using(t,name,c)?;
                    if let Some((_, dd)) = &d {
                        let ok = matches!(decl_kind_of(&dd.macro_name), None | Some("OWN")) || (is_relw && decl_kind_of(&dd.macro_name) == Some("REL"));
                        if !ok {
                            problem_room(c,&mut problems,idx)?;problems.push(Problem {
                                check: "contradiction",
                                rel: crate::key_policy_control::own(c,&r)?,
                                line: *n,
                                msg: crate::key_policy_control::format(c,format_args!("{}.{} is declared {} but written with {}", t, name, dd.macro_name, if is_relw { "rel_*" } else { "own_*" }))?,
                            });
                        }
                    }
                    if let Some(got) = idx.member_using(t,name,c)? {
                        let proto = matches!(&d, Some((_, dd)) if dd.macro_name == "PROTO");
                        // A rel_* writer of a registry-typed var is a view of the shared entry, not an owner (as before).
                        if idx.is_registry_using(&got.vtype,c)? && !proto && !is_relw {
                            problem_room(c,&mut problems,idx)?;problems.push(Problem {
                                check: "matrix",
                                rel: crate::key_policy_control::own(c,&r)?,
                                line: *n,
                                msg: crate::key_policy_control::format(c,format_args!("{}.{} is typed {}, a registry type: it is SHARED, not owned", t, name, got.vtype))?,
                            });
                        }
                    }
                }
            }

Ok(problems)
}

fn problem_room<C:crate::key_policy_control::Control>(c:&mut C,rows:&mut Vec<Problem>,_idx:&Index)->Result<(),C::Error>{crate::key_policy_control::row(c,rows)}
