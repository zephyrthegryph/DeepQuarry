//! What `own_set` -> `rel_set` and `own_add` -> `rel_add` share: the var has to be declared before the new write verb can dispatch on it.
//!
//! `rel_set` / `rel_add` read the declared kind of the var (`rel_kind`, code/engine/declare/relations.dm): an `owns_one` / `owns_many`
//! var goes through `own_set` / `own_add`, a list var through the list state, an undeclared one becomes a plain view. The old verbs
//! learned an undeclared var as owned on first use, so a bare rename would turn an owned var into a view. Each converted site
//! therefore needs its var declared owned, and the codemod emits the declaration:
//!
//! * the var is already declared (a legacy `OWN`/`ownership()` entry, a `CAPABILITIES` relation entry on the type or an ancestor): the
//!   call is only renamed;
//! * otherwise `owns_one(nameof(var), /declared/type)` (one value) or `owns_many(nameof(var), /element/type)` (a list) is added to
//!   the `CAPABILITIES(T)` block of the type that DECLARES the var, not a subtype; the block is made, after the type's var block, when
//!   the type has none;
//! * a var it cannot type confidently (untyped, a value type, an unresolved receiver, a list written with `own_set`, a scalar written
//!   with `own_add`) keeps its `own_*` call as residue.
//!
//! The declared type is the var's own type, so `own_type_ok()` accepts what the code already stores.

use std::any::Any;
use std::collections::{BTreeMap, HashMap};
use std::path::Path;
use std::sync::Arc;

use super::helpers::rename_exact;
use super::{Ctx, Edit, KeyUse, Need, Outcome, Rewrite};
use crate::dm::ownership_index::{parents, proc_scopes, Index, ACCESSOR};
use crate::sem::decls::Decls;
use crate::sem::Sem;
use crate::tree::{Tree, CODE_DM};

/// One accessor call on a line: which verb, which var, and the static type of its receiver ("" when unknown).
struct Ev {
    func: String,
    var: String,
    rtype: String,
}

pub struct Prep {
    idx: Arc<Index>,
    decls: Arc<Decls>,
    events: HashMap<(String, u32), Vec<Ev>>,
}

impl Prep {
    pub fn build(tree: &Tree) -> Prep {
        let files = tree.select(&CODE_DM);
        let idx = Index::get(tree, &files);
        let decls = Decls::get(tree);
        let mut events: HashMap<(String, u32), Vec<Ev>> = HashMap::new();
        for f in &files {
            let raw = f.raw();
            let rel = f.rel.clone();
            proc_scopes(f.code(), |no, _line, owner, _proc, local_types| {
                let rl = raw.line(no);
                for m in ACCESSOR.captures_iter(rl) {
                    let (func, recv, name) = (m.s(1), m.s(2), m.s(3));
                    let mut rtype: Option<String> = if recv == "src" { Some(owner.to_string()) } else { local_types.get(recv).and_then(|t| t.clone()) };
                    if rtype.is_none() && recv != "src" {
                        rtype = idx.member(owner, recv).map(|g| g.vtype);
                    }
                    events.entry((rel.clone(), no as u32)).or_default().push(Ev { func: func.to_string(), var: name.to_string(), rtype: rtype.unwrap_or_default() });
                }
            });
        }
        Prep { idx, decls, events }
    }
}

pub fn prepare(tree: &Tree) -> Arc<dyn Any + Send + Sync> {
    Arc::new(Prep::build(tree))
}

/// The var an accessor call names (`nameof(x)`, `nameof(src.x)`, `nameof(/type::x)` or `"x"`) and, for the last form, the type it names.
fn var_name(arg: &str) -> Option<(String, Option<String>)> {
    let a = arg.trim();
    if let Some(s) = a.strip_prefix('"').and_then(|s| s.strip_suffix('"')) {
        return Some((s.to_string(), None));
    }
    let inner = a.strip_prefix("nameof(")?.strip_suffix(')')?.trim();
    let name = inner.rsplit(['.', ':']).next()?.trim();
    if name.is_empty() || !name.chars().all(|c| c.is_alphanumeric() || c == '_') {
        return None;
    }
    let ty = inner.strip_prefix('/').and_then(|r| r.split_once("::")).map(|(t, _)| format!("/{}", t.trim()));
    Some((name.to_string(), ty))
}

/// Splits a declared type path into (is_list, element or value type).
fn split_type(declared: &str) -> (bool, String) {
    match declared.strip_prefix("/list") {
        Some("") => (true, String::new()),
        Some(rest) if rest.starts_with('/') => (true, rest.to_string()),
        _ => (false, declared.to_string()),
    }
}

/// The rewrite of one `own_set` (`many = false`) or `own_add` (`many = true`) call.
pub fn rewrite(cx: &Ctx, new: &str, many: bool) -> Outcome {
    let renamed = rename_exact(cx, new, 3);
    let Outcome::Rewrite(Rewrite { edits, keys, .. }) = renamed else { return renamed };
    let Some(prep) = cx.prep.downcast_ref::<Prep>() else { return renamed_without_prep(edits, keys) };
    let Some((var, named_type)) = var_name(cx.arg_text(1)) else {
        return Outcome::Residue("dynamic_var", "the var is not nameof(x) or a literal".into());
    };
    // `nameof(/type::var)` says the type itself; otherwise the holder's static type comes from the line's accessor scan.
    let src_holder = cx.arg_text(0).trim() == "src" && cx.owner != "/";
    let rtype = named_type.or_else(|| src_holder.then(|| cx.owner.to_string())).unwrap_or_else(|| {
        prep.events
            .get(&(cx.rel.to_string(), cx.line))
            .and_then(|evs| evs.iter().find(|e| e.func == cx.callee && e.var == var))
            .map(|e| e.rtype.clone())
            .unwrap_or_default()
    });
    if rtype.is_empty() {
        return Outcome::Residue("unresolved_receiver", "the static type of the holder is unknown: declare the var by hand".into());
    }
    let Some(owner) = cx.sem.var_owner(&rtype, &var) else {
        return Outcome::Residue("unknown_var", format!("{} has no var {}", rtype, var));
    };
    // Already declared on the type or an ancestor: the call only changes its name.
    if prep.idx.decl(&rtype, &var).is_some() || parents(&rtype).iter().any(|p| prep.decls.is_relation(p, &var)) || prep.decls.is_relation(&owner, &var) {
        return Outcome::Rewrite(Rewrite { edits, keys, needs: Vec::new() });
    }
    let Some(sig) = cx.sem.var_decl(&owner, &var) else {
        return Outcome::Residue("unknown_var", format!("{} has no declared var {}", owner, var));
    };
    let (is_list, vtype) = split_type(&sig.declared);
    if many && !is_list {
        return Outcome::Residue("scalar_var", "own_add on a var that is not a list".into());
    }
    if !many && is_list {
        return Outcome::Residue("list_var", "own_set on a list var: rel_set goes through the list state; convert by hand".into());
    }
    if vtype.is_empty() && !many {
        return Outcome::Residue("untyped_var", "the var has no declared type, so owns_one() has none to say".into());
    }
    if !vtype.is_empty() && !prep.idx.is_entity(&vtype) {
        return Outcome::Residue("untyped_var", format!("{} is not an entity type: nothing to own", vtype));
    }
    Outcome::Rewrite(Rewrite { edits, keys, needs: vec![Need { holder: owner, var, many, vtype, origin: cx.origin() }] })
}

fn renamed_without_prep(edits: Vec<Edit>, keys: Vec<KeyUse>) -> Outcome {
    Outcome::Rewrite(Rewrite { edits, keys, needs: Vec::new() })
}

/// The newline a file uses.
fn nl_of(text: &str) -> &'static str {
    if text.contains("\r\n") {
        "\r\n"
    } else {
        "\n"
    }
}

fn entry_line(n: &Need) -> String {
    let verb = if n.many { "owns_many" } else { "owns_one" };
    if n.vtype.is_empty() {
        format!("{}(nameof({}))", verb, n.var)
    } else {
        format!("{}(nameof({}), {})", verb, n.var, n.vtype)
    }
}

/// The edits that declare `needs`: into each holder's existing `CAPABILITIES` block, else a new block after the type's var block.
pub fn declaration_edits(root: &Path, _tree: &Tree, sem: &Sem, prep: &(dyn Any + Send + Sync), needs: &[Need]) -> Vec<(String, Vec<Edit>)> {
    let Some(prep) = prep.downcast_ref::<Prep>() else { return Vec::new() };
    let mut by_holder: BTreeMap<&str, Vec<&Need>> = BTreeMap::new();
    for n in needs {
        by_holder.entry(n.holder.as_str()).or_default().push(n);
    }
    let mut out: BTreeMap<String, Vec<Edit>> = BTreeMap::new();
    for (holder, ns) in by_holder {
        let existing = prep.decls.markers.iter().find(|m| m.name == "CAPABILITIES" && m.args.first().map(|a| a == holder).unwrap_or(false));
        let (rel, offset, newline, prefix): (String, usize, &str, String) = if let Some(m) = existing {
            let Ok(text) = std::fs::read_to_string(root.join(&m.rel)) else { continue };
            let nl = nl_of(&text);
            // The end of the block: the end of its last entry line, or the header's closing parenthesis when it has no entries.
            let body_end = m.body_offset + m.body.len();
            let end = if m.args.len() >= 2 { body_end } else { body_end + 1 };
            // The marker's offsets are in the file with LF line ends; a CRLF file has one more byte per line before it.
            let end = if nl == "\r\n" {
                let lf = text.replace("\r\n", "\n");
                end + lf.as_bytes()[..end.min(lf.len())].iter().filter(|b| **b == b'\n').count()
            } else {
                end
            };
            (m.rel.clone(), end, nl, String::new())
        } else {
            let Some(sig) = sem.var_decl(holder, &ns[0].var) else { continue };
            let Ok(text) = std::fs::read_to_string(root.join(&sig.file)) else { continue };
            let nl = nl_of(&text);
            // After the type's block: the declaration line, and every indented or blank line that follows it up to the next top-level line.
            let lines: Vec<&str> = text.split('\n').collect();
            let mut starts: Vec<usize> = Vec::with_capacity(lines.len());
            let mut at = 0usize;
            for l in &lines {
                starts.push(at);
                at += l.len() + 1;
            }
            let decl_idx = (sig.line as usize).saturating_sub(1).min(lines.len().saturating_sub(1));
            let mut last = decl_idx;
            if lines[decl_idx].starts_with(|c: char| c.is_whitespace()) {
                let mut j = decl_idx + 1;
                while j < lines.len() {
                    let l = lines[j].trim_end_matches('\r');
                    // A block comment at column 0 (`/* ... */`) does not end the type's block either.
                    if l.starts_with("/*") {
                        while j < lines.len() && !lines[j].contains("*/") {
                            j += 1;
                        }
                        j += 1;
                        continue;
                    }
                    // A blank line, a comment or a preprocessor line at column 0 does not end the type's block: more vars may follow it.
                    if l.trim().is_empty() || l.starts_with("//") || l.starts_with('#') {
                        j += 1;
                        continue;
                    }
                    if !l.starts_with(|c: char| c.is_whitespace()) {
                        break;
                    }
                    last = j;
                    j += 1;
                }
            }
            let end = starts[last] + lines[last].trim_end_matches('\r').len();
            (sig.file.clone(), end, nl, format!("{nl}{nl}CAPABILITIES({holder})"))
        };
        let mut text = prefix;
        for n in ns {
            text.push_str(newline);
            text.push('\t');
            text.push_str(&entry_line(n));
        }
        out.entry(rel).or_default().push(Edit::insert(offset, text));
    }
    out.into_iter().collect()
}
