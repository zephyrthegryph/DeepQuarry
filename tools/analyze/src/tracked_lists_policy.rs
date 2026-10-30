//! Exact tracked-list declaration/lookalike selection and output policy.
//! Shared by legacy and captured producers; semantic ownership stays external.
use crate::{tree::SourceFile,pat_match,sparse_slots_policy::Output};
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

/// The procs and the version var for one list var.
pub fn emit(out: &mut Output, d: &Decl) {
    let (t, v) = (&d.ty, &d.var);
    let tail = |out: &mut Output| {
        out.line_fmt(format_args!("\t{}_version++", v));
        out.line_fmt(format_args!("\ttracked_changed(src, \"{}\")",d.var));
        out.line("\treturn TRUE");
    };
    out.doc_fmt(format_args!("TRACKED({}, {}) at {}:{}: the list's version, bumped by every change through add_{}, include_{}, remove_{}, set_{}_at, clear_{}, insert_{}, swap_{} and cut_{}.", t, v, d.rel, d.line, v, v, v, v, v, v, v, v));
    out.line_fmt(format_args!("{}/var/{}_version = 0 // ALLOW(base_vars): a tracked list's version counter (TRACKED, tools/analyze/src/gens/tracked_lists.rs)", t, v));
    out.line_fmt(format_args!("{}/proc/add_{}(x)", t, v));
    out.line_fmt(format_args!("\tif(isnull({}))", v));
    out.line_fmt(format_args!("\t\t{} = list()", v));
    out.line_fmt(format_args!("\t{} += x", v));
    tail(out);
    out.line_fmt(format_args!("{}/proc/include_{}(x)", t, v));
    out.line_fmt(format_args!("\tvar/was_null = isnull({})", v));
    out.line_fmt(format_args!("\tvar/before = length({})", v));
    out.line("\tif(was_null)");
    out.line_fmt(format_args!("\t\t{} = list()", v));
    out.line_fmt(format_args!("\t{} |= x", v));
    out.line_fmt(format_args!("\tif(length({}) == before)", v));
    out.line("\t\tif(was_null)");
    out.line_fmt(format_args!("\t\t\t{} = null", v));
    out.line("\t\treturn FALSE");
    tail(out);
    out.line_fmt(format_args!("{}/proc/remove_{}(x)", t, v));
    out.line_fmt(format_args!("\tvar/before = length({})", v));
    out.line("\tif(!before)");
    out.line("\t\treturn FALSE");
    out.line_fmt(format_args!("\t{} -= x", v));
    out.line_fmt(format_args!("\tif(length({}) == before)", v));
    out.line("\t\treturn FALSE");
    tail(out);
    out.line_fmt(format_args!("{}/proc/set_{}_at(index, x)", t, v));
    out.line_fmt(format_args!("\tif(isnull({}))", v));
    out.line_fmt(format_args!("\t\t{} = list()", v));
    out.line_fmt(format_args!("\tvar/had = isnum(index) || (index in {})", v));
    out.line_fmt(format_args!("\tif(had && TRACKED_UNCHANGED({}[index], x))", v));
    out.line("\t\treturn FALSE");
    out.line_fmt(format_args!("\t{}[index] = x", v));
    tail(out);
    out.line_fmt(format_args!("{}/proc/insert_{}(index, x)", t, v));
    out.line_fmt(format_args!("\tif(isnull({}))", v));
    out.line_fmt(format_args!("\t\t{} = list()", v));
    out.line_fmt(format_args!("\t{}.Insert(index, x)", v));
    tail(out);
    out.line_fmt(format_args!("{}/proc/swap_{}(a, b)", t, v));
    out.line_fmt(format_args!("\tif(a == b || !length({}))", v));
    out.line("\t\treturn FALSE");
    out.line_fmt(format_args!("\t{}.Swap(a, b)", v));
    tail(out);
    out.line_fmt(format_args!("{}/proc/cut_{}(start = 1, end = 0)", t, v));
    out.line_fmt(format_args!("\tvar/before = length({})", v));
    out.line("\tif(!before)");
    out.line("\t\treturn FALSE");
    out.line_fmt(format_args!("\t{}.Cut(start, end)", v));
    out.line_fmt(format_args!("\tif(length({}) == before)", v));
    out.line("\t\treturn FALSE");
    tail(out);
    out.line_fmt(format_args!("{}/proc/clear_{}()", t, v));
    out.line_fmt(format_args!("\tif(!length({}))", v));
    out.line("\t\treturn FALSE");
    out.line_fmt(format_args!("\t{}.Cut()", v));
    tail(out);
    out.blank();
}

/// A proc definition whose name looks generated (`add_x`, `set_x_at`, ...), by file: `(line, type if written on the line, name)`.
pub fn lookalikes(f: &SourceFile) -> Vec<(u32, String, String)> {
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
