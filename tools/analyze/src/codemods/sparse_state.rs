//! `sparse_get` / `sparse_get_or` / `sparse_set` / `sparse_set_or` to the lazy owned state of the slot's feature (the storage contract,
//! doc/rewrite/storage_contract.md):
//!
//! ```text
//! sparse_get(M, omen_damage)                       ->  STATE_GET(M, omen, omen_damage)
//! sparse_get_or(M, omen_damage, 1)                 ->  STATE_GET(M, omen, omen_damage)        (the state var's default is the 1)
//! sparse_set(M, omen_damage, 2)                    ->  omen_of(M).set_omen_damage(2)
//! sparse_set_or(M, omen_damage, v, 1)              ->  omen_of(M).set_omen_damage(v)
//! sparse_set(M, omen_damage, null)                 ->  if(M.omen) M.omen.set_omen_damage(1)   (a reset writes the default; nothing is made)
//! ```
//!
//! The grouping is `tools/analyze/codemods/sparse_state/groups.tsv` (holder, slot, feature, kind, default, wave; written by groups.py), and
//! only slots of wave 1 are converted. A site stays residue, with a reason, when it cannot be converted without a decision: the receiver is not
//! a plain var or `src` of a known type, the type is wider than the slot's holder (the feature var would not exist on it), the call's value is used,
//! or the default a call site gives is not the state var's.

use crate::codemod::{Codemod, Ctx, Edit, Outcome};
use crate::dm::ownership_index::proc_scopes;
use crate::sem::Sem;
use crate::tree::{Tree, CODE_DM};
use std::any::Any;
use std::collections::HashMap;
use std::sync::Arc;

pub struct SparseState;

#[derive(Clone, Debug)]
struct Row {
    holder: String,
    feature: String,
    default: String,
    wave: u32,
}

struct Prep {
    /// slot name -> the rows that declare it (one per holder)
    slots: HashMap<String, Vec<Row>>,
    /// (file, line) -> the declared types of the locals in scope on that line
    locals: HashMap<(String, u32), HashMap<String, Option<String>>>,
}

fn norm(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join("")
}

impl Codemod for SparseState {
    fn name(&self) -> &'static str {
        "sparse_state"
    }
    fn about(&self) -> &'static str {
        "sparse_get/_or, sparse_set/_or -> STATE_GET(M, feature, field) and feature_of(M).set_field(v)"
    }
    fn callees(&self) -> &'static [&'static str] {
        &["sparse_get", "sparse_get_or", "sparse_set", "sparse_set_or"]
    }
    fn ast_alias(&self) -> &'static [(&'static str, &'static str, usize)] {
        &[("_sparse_get", "sparse_get", 2), ("_sparse_get", "sparse_get_or", 3), ("_sparse_set", "sparse_set", 3), ("_sparse_set", "sparse_set_or", 4)]
    }
    fn reasons(&self) -> &'static [(&'static str, &'static str)] {
        &[
            ("dynamic_slot", "the slot is not a plain name"),
            ("unknown_slot", "no sparse() declaration (or no row in groups.tsv) for this slot"),
            ("not_in_wave", "the slot is not in the wave being converted (a list or weak slot, or a holder waiting on a decision)"),
            ("complex_receiver", "the receiver is not `src` or a plain var: STATE_GET evaluates it twice, so hoist it into a typed local"),
            ("unresolved_receiver", "the static type of the receiver is unknown: type the var or hoist it"),
            ("receiver_too_wide", "the receiver's type is wider than the slot's holder, so the feature var may not exist on it: narrow it with a typed local or istype()"),
            ("value_used", "the value of the write is used; write it as a statement and read the field after"),
            ("default_mismatch", "the default this call gives is not the state var's default (see groups.tsv): decide which is right"),
            ("get_default_differs", "sparse_get (no default) on a slot whose state var has a default reads the default now, not null: use the state var's default or test presence"),
            ("named_args", "a named argument: not a form the macros take"),
        ]
    }
    /// Unit tests are callers too (they read and write the slots they test); only the framework the old form lives in is left out.
    fn excluded(&self, rel: &str) -> bool {
        rel.starts_with("code/engine/") || rel.starts_with("code/defines/") || rel.starts_with("code/world/tgs/")
    }
    fn prepare(&self, tree: &Tree, _sem: &Sem) -> Arc<dyn Any + Send + Sync> {
        let mut slots: HashMap<String, Vec<Row>> = HashMap::new();
        let path = tree.root.join("tools/analyze/codemods/sparse_state/groups.tsv");
        if let Ok(text) = std::fs::read_to_string(&path) {
            for line in text.lines() {
                let c: Vec<&str> = line.split('\t').collect();
                if c.len() == 6 {
                    slots.entry(c[1].to_string()).or_default().push(Row { holder: c[0].to_string(), feature: c[2].to_string(), default: c[4].to_string(), wave: c[5].parse().unwrap_or(0) });
                }
            }
        }
        let mut locals = HashMap::new();
        for f in tree.select(&CODE_DM) {
            if !f.text().contains("sparse_") {
                continue;
            }
            let raw = f.raw();
            let rel = f.rel.clone();
            proc_scopes(f.code(), |no, _line, _owner, _proc, local_types| {
                if raw.line(no).contains("sparse_") {
                    locals.insert((rel.clone(), no as u32), local_types.clone());
                }
            });
        }
        Arc::new(Prep { slots, locals })
    }
    fn rewrite(&self, cx: &Ctx) -> Outcome {
        let Some(prep) = cx.prep.downcast_ref::<Prep>() else { return Outcome::Residue("unknown_slot", "no preparation".into()) };
        let n = cx.node.args.len();
        let (is_get, has_default) = match cx.callee {
            "sparse_get" => (true, false),
            "sparse_get_or" => (true, true),
            "sparse_set" => (false, false),
            _ => (false, true),
        };
        if crate::codemod::helpers::any_named(&cx.node.args) || n != 2 + usize::from(!is_get) + usize::from(has_default) {
            return Outcome::Residue("named_args", "unexpected arguments".into());
        }
        let slot = cx.arg_clean(1).trim();
        if slot.is_empty() || !slot.chars().all(|c| c.is_alphanumeric() || c == '_') {
            return Outcome::Residue("dynamic_slot", slot.to_string());
        }
        let Some(rows) = prep.slots.get(slot) else { return Outcome::Residue("unknown_slot", slot.to_string()) };
        // DQ_SPARSE_UNTYPED=1 (the second pass of a wave): a receiver whose type the scan cannot tell, or a dotted chain of vars, takes the slot's one holder;
        // the compiler then checks every typed receiver, and an untyped one was handed to a mob-only slot already.
        let loose = std::env::var("DQ_SPARSE_UNTYPED").is_ok();
        let recv = cx.arg_clean(0).trim();
        let plain = !recv.is_empty() && recv.chars().all(|c| c.is_alphanumeric() || c == '_');
        let chain = !recv.is_empty() && recv.split('.').all(|p| !p.is_empty() && p.chars().all(|c| c.is_alphanumeric() || c == '_'));
        if !plain && !(loose && chain) {
            return Outcome::Residue("complex_receiver", recv.to_string());
        }
        let rtype = if recv == "src" {
            (cx.owner != "/").then(|| cx.owner.to_string())
        } else {
            prep.locals.get(&(cx.rel.to_string(), cx.line)).and_then(|l| l.get(recv)).and_then(|t| t.clone())
        };
        let rtype = if plain { rtype } else { None };
        let row = match &rtype {
            Some(t) => rows.iter().find(|r| cx.sem.is_subtype(t, &r.holder)),
            None if loose && rows.len() == 1 => rows.first(),
            None => return Outcome::Residue("unresolved_receiver", recv.to_string()),
        };
        let rtype = rtype.unwrap_or_default();
        let row = row.or_else(|| if loose { rows.iter().find(|r| cx.sem.is_subtype(&r.holder, &rtype)) } else { None });
        let Some(row) = row else {
            let wider = rows.iter().any(|r| cx.sem.is_subtype(&r.holder, &rtype));
            return Outcome::Residue(
                if wider { "receiver_too_wide" } else { "unknown_slot" },
                format!("{} is a {}, the slot is on {}", recv, rtype, rows.iter().map(|r| r.holder.as_str()).collect::<Vec<_>>().join("/")),
            );
        };
        // DQ_SPARSE_WAVE picks the wave (default 1: the mob holders, whose state is a var; 2: the atom and object holders, whose state is a table row).
        let wave: u32 = std::env::var("DQ_SPARSE_WAVE").ok().and_then(|w| w.parse().ok()).unwrap_or(1);
        if row.wave != wave {
            return Outcome::Residue("not_in_wave", slot.to_string());
        }
        let table = !row.holder.starts_with("/mob");
        let whole = cx.node.whole();
        if is_get {
            if has_default && norm(cx.arg_text(2)) != norm(&row.default) {
                return Outcome::Residue("default_mismatch", format!("{} gives {}, the state var starts as {}", cx.callee, cx.arg_text(2), row.default));
            }
            if !has_default && !row.default.is_empty() {
                return Outcome::Residue("get_default_differs", format!("{} starts as {}", slot, row.default));
            }
            let read = if table { "STATE_PEEK" } else { "STATE_GET" };
            return Outcome::edits(vec![Edit::replace(whole, format!("{}({}, {}, {})", read, recv, row.feature, slot))]);
        }
        if !cx.stmt_level {
            return Outcome::Residue("value_used", slot.to_string());
        }
        if has_default && norm(cx.arg_text(3)) != norm(&row.default) && !(row.default.is_empty() && norm(cx.arg_text(3)) == "null") {
            return Outcome::Residue("default_mismatch", format!("{} gives {}, the state var starts as {}", cx.callee, cx.arg_text(3), row.default));
        }
        let value = cx.arg_text(2).trim();
        // A null write is a reset: STATE_SET with the field's default (a default write with no state does nothing).
        let value = if norm(cx.arg_clean(2)) == "null" && !row.default.is_empty() { row.default.clone() } else { value.to_string() };
        Outcome::edits(vec![Edit::replace(whole, format!("STATE_SET({}, {}, {}, {})", recv, row.feature, slot, value))])
    }
}

pub fn register(reg: &mut Vec<Box<dyn Codemod>>) {
    reg.push(Box::new(SparseState));
}
