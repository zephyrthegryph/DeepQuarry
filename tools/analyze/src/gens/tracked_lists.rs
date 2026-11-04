//! `analyze gen tracked_lists` -> `code/engine/_generated/tracked_lists.dm`.
//!
//! A list var declared `TRACKED(T, v)` is mutated in place (`LAZYADD`, `Add`, `[]=`), which no setter
//! sees: `set_v()` compares list references, so an in-place edit published nothing. This writes, for each such var, the procs
//! that mutate it and publish through the same path as the setter (`tracked_changed`):
//!
//! ```text
//! add_v(x)         append (LAZYADD, Add, += )
//! include_v(x)     append what is absent (LAZYOR, LAZYDISTINCTADD, |= )
//! remove_v(x)      remove (LAZYREMOVE, Remove, -= )
//! set_v_at(i, x)   v[i] = x (LAZYSET, [] = )
//! clear_v()        empty it (LAZYCLEARLIST, Cut)
//! insert_v(i, x)   Insert
//! swap_v(a, b)     Swap
//! cut_v(from, to)  Cut(start, end)
//! ```
//!
//! and a per-list version counter `v_version`, bumped on every change, that a reader compares to know whether the list it holds
//! a copy of has moved. Each proc returns TRUE when the list changed. A list is created on the first add and then kept (an emptied
//! list stays an empty list, which is how `Cut()`/`Remove()` left it: a reader that calls `.Find()` on it after a removal is safe).
//!
//! A list declared `per_type(nameof(v), PROC_REF(build), copy_on_write = TRUE)` is a shared starting list: every instance holds the type's one
//! table until it first writes. Its mutators begin with the unshare step (`cow_table()`, code/engine/lifeforms/per_type.dm): while the version
//! is still 0 and the var is the type's table, the var is replaced by its copy, so a write never reaches the table or another instance.
//!
//! The `tracked` lint (rule `list_mutation`) bans the in-place forms outside these procs, and `analyze fix` rewrites them.

use std::collections::{BTreeMap, BTreeSet};

use crate::sem::gen::{GenCx, GenOut, Generator};
use crate::tree::{SourceFile, CODE_DM};
use crate::pat_match;

/// One TRACKED list var: the type that declares it and the var.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, serde::Serialize, serde::Deserialize, Default)]
pub struct Decl {
    pub ty: String,
    pub var: String,
    pub rel: String,
    pub line: u32,
}

/// The `TRACKED(T, v)` declaration lines of one file.
pub fn declarations_in(f: &SourceFile) -> Vec<Decl> {
    let mut out = Vec::new();
    let text = f.text();
    if !text.contains("TRACKED") {
        return out;
    }
    for (i, line) in f.raw().lines().enumerate() {
        let t = line.trim_start();
        if t.starts_with('#') || t.starts_with("//") {
            continue;
        }
        if let Some(m) = pat_match!(r"TRACKED\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\)").captures(t) {
            out.push(Decl { ty: m.s(1).trim_end_matches('/').to_string(), var: m.s(2).to_string(), rel: f.rel.clone(), line: i as u32 + 1 });
        }
    }
    out
}

/// Every TRACKED declaration in the tree, sorted.
pub fn declarations(tree: &crate::tree::Tree) -> Vec<Decl> {
    let files = tree.select(&CODE_DM);
    let facts: Vec<Vec<Decl>> = crate::incr::facts("tracked-list-decls", &files, declarations_in);
    let mut all: Vec<Decl> = facts.into_iter().flatten().collect();
    all.sort();
    all.dedup();
    all
}

/// The TRACKED vars that are lists (`var/list/v`), by (type, var).
pub fn list_vars(sem: &crate::sem::Sem, decls: &[Decl]) -> BTreeMap<(String, String), Decl> {
    let mut out = BTreeMap::new();
    for d in decls {
        let Some(sig) = sem.var_decl(&d.ty, &d.var) else { continue };
        if sig.is_list() {
            out.entry((d.ty.clone(), d.var.clone())).or_insert_with(|| d.clone());
        }
    }
    out
}

fn publish(d: &Decl) -> String {
    format!("tracked_changed(src, \"{}\")", d.var)
}

/// The `(declaring type, var)` of every list a CAPABILITIES block declares `per_type(nameof(v), ..., copy_on_write = TRUE)`.
pub fn cow_vars(tree: &crate::tree::Tree, sem: &crate::sem::Sem) -> BTreeSet<(String, String)> {
    let decls = crate::sem::decls::Decls::get(tree);
    let mut out = BTreeSet::new();
    for m in decls.markers_named("CAPABILITIES") {
        let Some(owner) = m.args.first().filter(|o| o.starts_with('/')) else { continue };
        for name in cow_names(&m.body) {
            if let Some(declaring) = sem.var_owner(owner, &name) {
                out.insert((declaring, name));
            }
        }
    }
    out
}

/// The vars `body` declares as copy_on_write per_type tables.
pub fn cow_names(body: &str) -> Vec<String> {
    crate::pat!(r"\bper_type\(\s*nameof\(\s*(\w+)\s*\)(?:(?!\bper_type\()[^\n])*?\bcopy_on_write\s*=\s*(?:TRUE|1)\b").captures_iter(body).into_iter().map(|c| c.s(1).to_string()).collect()
}

/// The procs and the version var for one list var. `cow`: the list is a copy_on_write starting list, so each mutator unshares it first.
pub fn emit(out: &mut GenOut, d: &Decl, cow: bool) {
    let (t, v) = (&d.ty, &d.var);
    let publish = publish(d);
    let unshare = |out: &mut GenOut| {
        if cow {
            out.line(format!("\tif(!{v}_version && {v} && {v} == cow_table(src, \"{v}\"))"));
            out.line(format!("\t\t{v} = {v}.Copy()"));
            out.line("\t\tBOOT_PHASE_COUNT(\"cow list: first write copied the starting list\")");
        }
    };
    let tail = |out: &mut GenOut| {
        out.line(format!("\t{}_version++", v));
        out.line(format!("\t{}", publish));
        out.line("\treturn TRUE");
    };
    out.doc(format!("TRACKED({}, {}) at {}:{}: the list's version, bumped by every change through add_{}, include_{}, remove_{}, set_{}_at, clear_{}, insert_{}, swap_{} and cut_{}.", t, v, d.rel, d.line, v, v, v, v, v, v, v, v));
    out.line(format!("{}/var/{}_version = 0 // ALLOW(base_vars): a tracked list's version counter (TRACKED, tools/analyze/src/gens/tracked_lists.rs)", t, v));
    out.line(format!("{}/proc/add_{}(x)", t, v));
    unshare(out);
    out.line(format!("\tif(isnull({}))", v));
    out.line(format!("\t\t{} = list()", v));
    out.line(format!("\t{} += x", v));
    tail(out);
    out.line(format!("{}/proc/include_{}(x)", t, v));
    unshare(out);
    out.line(format!("\tvar/was_null = isnull({})", v));
    out.line(format!("\tvar/before = length({})", v));
    out.line("\tif(was_null)");
    out.line(format!("\t\t{} = list()", v));
    out.line(format!("\t{} |= x", v));
    out.line(format!("\tif(length({}) == before)", v));
    out.line("\t\tif(was_null)");
    out.line(format!("\t\t\t{} = null", v));
    out.line("\t\treturn FALSE");
    tail(out);
    out.line(format!("{}/proc/remove_{}(x)", t, v));
    unshare(out);
    out.line(format!("\tvar/before = length({})", v));
    out.line("\tif(!before)");
    out.line("\t\treturn FALSE");
    out.line(format!("\t{} -= x", v));
    out.line(format!("\tif(length({}) == before)", v));
    out.line("\t\treturn FALSE");
    tail(out);
    out.line(format!("{}/proc/set_{}_at(index, x)", t, v));
    unshare(out);
    out.line(format!("\tif(isnull({}))", v));
    out.line(format!("\t\t{} = list()", v));
    out.line(format!("\tvar/had = isnum(index) || (index in {})", v));
    out.line(format!("\tif(had && TRACKED_UNCHANGED({}[index], x))", v));
    out.line("\t\treturn FALSE");
    out.line(format!("\t{}[index] = x", v));
    tail(out);
    out.line(format!("{}/proc/insert_{}(index, x)", t, v));
    unshare(out);
    out.line(format!("\tif(isnull({}))", v));
    out.line(format!("\t\t{} = list()", v));
    out.line(format!("\t{}.Insert(index, x)", v));
    tail(out);
    out.line(format!("{}/proc/swap_{}(a, b)", t, v));
    unshare(out);
    out.line(format!("\tif(a == b || !length({}))", v));
    out.line("\t\treturn FALSE");
    out.line(format!("\t{}.Swap(a, b)", v));
    tail(out);
    out.line(format!("{}/proc/cut_{}(start = 1, end = 0)", t, v));
    unshare(out);
    out.line(format!("\tvar/before = length({})", v));
    out.line("\tif(!before)");
    out.line("\t\treturn FALSE");
    out.line(format!("\t{}.Cut(start, end)", v));
    out.line(format!("\tif(length({}) == before)", v));
    out.line("\t\treturn FALSE");
    tail(out);
    out.line(format!("{}/proc/clear_{}()", t, v));
    unshare(out);
    out.line(format!("\tif(!length({}))", v));
    out.line("\t\treturn FALSE");
    out.line(format!("\t{}.Cut()", v));
    tail(out);
    out.blank();
}

/// A proc definition whose name looks generated (`add_x`, `set_x_at`, ...), by file: `(line, type if written on the line, name)`.
fn lookalikes(f: &SourceFile) -> Vec<(u32, String, String)> {
    let mut out = Vec::new();
    if f.rel == "code/engine/_generated/tracked_lists.dm" || !f.text().contains("proc/") && !f.text().contains("_at(") {
        return out;
    }
    let top = crate::pat!(r"^(/[\w/]*?)/(?:proc/)?((?:add|include|remove|clear|insert|swap|cut)_\w+|set_\w+_at)\s*\(");
    let nested = crate::pat!(r"^\s+(?:proc/)((?:add|include|remove|clear|insert|swap|cut)_\w+|set_\w+_at)\s*\(");
    for (i, line) in f.code().text.lines().enumerate() {
        if let Some(m) = top.captures(line) {
            out.push((i as u32 + 1, m.s(1).to_string(), m.s(2).to_string()));
        } else if let Some(m) = nested.captures(line) {
            out.push((i as u32 + 1, String::new(), m.s(1).to_string()));
        }
    }
    out
}

/// The generated proc names some other file already defines on the same type: `(type, name)`.
fn taken(sem: &crate::sem::Sem, tree: &crate::tree::Tree) -> std::collections::BTreeSet<(String, String)> {
    let files = tree.select(&CODE_DM);
    let facts: Vec<Vec<(u32, String, String)>> = crate::incr::facts("tracked-list-lookalikes", &files, lookalikes);
    let mut out = std::collections::BTreeSet::new();
    for (f, rows) in files.iter().zip(facts) {
        for (line, ty, name) in rows {
            if ty.is_empty() {
                for c in sem.owner_candidates(&f.rel, line) {
                    out.insert((c, name.clone()));
                }
            } else {
                out.insert((ty, name));
            }
        }
    }
    out
}

/// A generated name some other file defines on `d`'s type, an ancestor or a subtype (DM refuses the same proc name twice along a type path).
fn clash(sem: &crate::sem::Sem, taken: &std::collections::BTreeSet<(String, String)>, d: &Decl) -> Option<String> {
    let v = &d.var;
    [format!("add_{v}"), format!("include_{v}"), format!("remove_{v}"), format!("set_{v}_at"), format!("clear_{v}"), format!("insert_{v}"), format!("swap_{v}"), format!("cut_{v}")]
        .into_iter()
        .find(|name| taken.iter().any(|(ty, n)| n == name && (sem.is_subtype(ty, &d.ty) || sem.is_subtype(&d.ty, ty))))
}

struct TrackedLists;

impl Generator for TrackedLists {
    fn name(&self) -> &'static str {
        "tracked_lists"
    }

    fn stage(&self) -> u8 {
        1
    }

    fn output(&self) -> &'static str {
        "tracked_lists.dm"
    }

    fn generate(&self, cx: &GenCx, out: &mut GenOut) {
        let decls = declarations(cx.tree);
        let Some(sem) = cx.sem() else { return };
        let lists = list_vars(&sem, &decls);
        let taken = taken(&sem, cx.tree);
        let cow = cow_vars(cx.tree, &sem);
        let test_types = crate::sem::gen::test_only_types(cx.tree);
        let (tests, content): (Vec<_>, Vec<_>) = lists.into_values().partition(|d| crate::sem::gen::test_only(&d.rel) || test_types.contains(&d.ty));
        for d in &content {
            if sem.var_decl(&d.ty, &format!("{}_version", d.var)).is_some_and(|v| v.file != "code/engine/_generated/tracked_lists.dm") {
                out.diag(&d.rel, d.line, format!("tracked list `{}` needs a var `{}_version`, which {} already declares", d.var, d.var, d.ty));
                continue;
            }
            if let Some(clash) = clash(&sem, &taken, d) {
                out.diag(&d.rel, d.line, format!("tracked list `{}`: {} (or a type on its path) already defines the proc `{}` the generator would write; rename that proc", d.var, d.ty, clash));
                continue;
            }
            emit(out, d, cow.contains(&(d.ty.clone(), d.var.clone())));
        }
        if !tests.is_empty() {
            out.line(crate::sem::gen::TEST_GUARD);
            out.blank();
            for d in &tests {
                emit(out, d, cow.contains(&(d.ty.clone(), d.var.clone())));
            }
            out.line("#endif");
        }
    }
}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(TrackedLists));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn copy_on_write_names_are_read_per_entry() {
        let body = "per_type(nameof(a), PROC_REF(build_a), copy_on_write = TRUE)\n\tper_type(nameof(b), PROC_REF(build_b))\n\tper_type(nameof(c), PROC_REF(build_c), copy_on_write = TRUE)";
        assert_eq!(cow_names(body), ["a", "c"]);
        // The same text on one line (a marker body can be joined).
        assert_eq!(cow_names(&body.replace('\n', " ")), ["a", "c"]);
        assert!(cow_names("per_type(nameof(a), PROC_REF(x), copy_on_write = FALSE)").is_empty());
    }

    #[test]
    fn lookalike_procs_are_found_with_and_without_a_type_on_the_line() {
        let f = SourceFile::from_text("code/a.dm", "/turf/simulated/floor/proc/swap_decals()\n\tvar/x\n/obj/thing\n\tproc/add_stamps(x)\n\t\treturn\n/obj/thing/set_items_at(a, b)\n/obj/thing/proc/unrelated()\n\tswap_decals()\n");
        assert_eq!(lookalikes(&f), vec![(1, "/turf/simulated/floor".to_string(), "swap_decals".to_string()), (4, String::new(), "add_stamps".to_string()), (6, "/obj/thing".to_string(), "set_items_at".to_string())]);
    }
}
