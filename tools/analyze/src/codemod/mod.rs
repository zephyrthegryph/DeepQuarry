//! The codemod framework (doc/rewrite/final_api.html section 19, phase 2.5).
//!
//! A codemod is an AST-aware rewriter: one file in `src/codemods/`, one `Codemod` impl, a directory
//! `tools/analyze/codemods/<name>/` holding its fixtures and its committed `residue.json`.
//!
//! ```text
//! analyze codemod list
//! analyze codemod NAME [--check] [--path PREFIX...] [--write-residue]
//! analyze codemod NAME --apply [--path PREFIX...]
//! analyze codemod NAME --revert
//! ```
//!
//! How a rewrite is found. The dreammaker parse (through [`crate::sem::Sem`]) reports every call of
//! the codemod's legacy forms with its line and column, and how many arguments it has. That decides
//! WHAT is a call: a name in a comment, a string or a `PROC_REF(...)` is not one, and neither is
//! a method with the same name. [`scan`] then finds the byte spans of the callee and each argument on
//! the file's own text, and the AST's argument count has to agree with the scan or the site is
//! residue. The codemod turns the node into [`Edit`]s: small span replacements and insertions, so a
//! comment, a line break or an indent outside the rewritten tokens is never touched. Edits compose
//! (an `om_after` nested in the argument of another is rewritten by the same pass) and apply from the
//! end of the file backwards.
//!
//! What it guarantees (the 2.5 gate): deterministic (files, sites and edits are sorted; no clocks, no
//! hash-map order), idempotent (the output holds none of the forms the codemod reads), local (only
//! the named spans change), reversible (`--apply` records the inverse of every edit with the hash of
//! each file before and after), and honest about what it cannot do: every site it does not rewrite is
//! residue with a reason code, and every legacy mention it cannot see in the AST (a macro body, an
//! inactive `#if`, a `PROC_REF(name)`) is residue too.

pub mod helpers;
pub mod keys;
pub mod own_decl;
pub mod report;
pub mod scan;

use std::any::Any;
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::Arc;

use dreammaker::ast::{Expression, Statement, Term};

use crate::sem::ast::{stmt_blocks, stmt_exprs, walk_expr};
use crate::sem::Sem;
use crate::tree::{Plan, Tree};
use scan::{CallNode, Span};

/// One change to a file: replace `start..end` with `text` (an insertion has `start == end`).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Edit {
    pub start: usize,
    pub end: usize,
    pub text: String,
}

impl Edit {
    pub fn replace(span: Span, text: impl Into<String>) -> Edit {
        Edit { start: span.start, end: span.end, text: text.into() }
    }
    pub fn insert(at: usize, text: impl Into<String>) -> Edit {
        Edit { start: at, end: at, text: text.into() }
    }
    pub fn delete(span: Span) -> Edit {
        Edit { start: span.start, end: span.end, text: String::new() }
    }
}

/// A key a codemod put on (or kept on) an entry, for the key-collision report ([`keys`]).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KeyUse {
    /// The type that owns the keyed thing (`/obj/machinery/x`), or the text of the owner expression when
    /// the codemod cannot tell its type.
    pub owner: String,
    pub key: String,
    /// `file:line` of the site.
    pub origin: String,
    /// The handler the key is attached to, as written.
    pub handler: String,
    /// TRUE when the codemod made the key up; FALSE when the old form already carried it.
    pub synthesized: bool,
}

/// A declaration a rewritten site needs: `holder.var` has to be declared (`owns_one` / `owns_many`) on the type that declares the var, or
/// the new form would not know the var. The codemod asks for it and the framework inserts it once per (type, var), in that type's
/// `CAPABILITIES` block (made when there is none).
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Need {
    /// The type that declares the var.
    pub holder: String,
    pub var: String,
    /// A list var (`owns_many`) rather than a single value (`owns_one`).
    pub many: bool,
    /// The var's declared type (the element type of a list).
    pub vtype: String,
    /// `file:line` of the first site that needs it.
    pub origin: String,
}

#[derive(Default)]
pub struct Rewrite {
    pub edits: Vec<Edit>,
    pub keys: Vec<KeyUse>,
    pub needs: Vec<Need>,
    /// Keys of definitions elsewhere that must change with this site (a handler whose signature changes); the codemod's
    /// `follow_edits()` turns the distinct keys of the kept sites into edits.
    pub follows: Vec<String>,
}

pub enum Outcome {
    Rewrite(Rewrite),
    /// A site the codemod will not rewrite: a reason code from [`Codemod::reasons`] and what to do about it.
    Residue(&'static str, String),
}

impl Outcome {
    pub fn edits(edits: Vec<Edit>) -> Outcome {
        Outcome::Rewrite(Rewrite { edits, ..Default::default() })
    }
}

/// Everything a codemod may look at for one call.
pub struct Ctx<'a> {
    pub rel: &'a str,
    pub line: u32,
    pub text: &'a str,
    pub clean: &'a str,
    pub node: &'a CallNode,
    pub callee: &'a str,
    /// The type whose proc holds the call (`/` for a global proc) and that proc's name.
    pub owner: &'a str,
    pub proc_name: &'a str,
    /// The call is a whole statement (its value is unused).
    pub stmt_level: bool,
    pub sem: &'a Sem,
    /// What the codemod's `prepare()` built once for the run (`()` for a codemod that has none).
    pub prep: &'a (dyn Any + Send + Sync),
}

impl Ctx<'_> {
    pub fn arg_text(&self, i: usize) -> &str {
        self.node.args.get(i).map(|a| a.span.text(self.text)).unwrap_or("")
    }
    /// The comment-free text of argument `i` (what the scanner saw).
    pub fn arg_clean(&self, i: usize) -> &str {
        self.node.args.get(i).map(|a| &self.clean[a.span.start..a.span.end]).unwrap_or("")
    }
    pub fn origin(&self) -> String {
        format!("{}:{}", self.rel, self.line)
    }
}

pub trait Codemod: Send + Sync {
    /// What `analyze codemod NAME` selects; also the directory under `tools/analyze/codemods/`.
    fn name(&self) -> &'static str;
    /// One line: the old form and what it becomes.
    fn about(&self) -> &'static str;
    /// The legacy callees it reads (calls, by name).
    fn callees(&self) -> &'static [&'static str];
    /// Reason codes this codemod can give for residue, with the fix each one needs. The framework's own
    /// codes ([`FRAMEWORK_REASONS`]) are not repeated here.
    fn reasons(&self) -> &'static [(&'static str, &'static str)];
    /// Files the codemod leaves alone because they are the framework the legacy form lives in, or unit
    /// tests (the count method counts game code only). Counted as `excluded`, never as residue.
    fn excluded(&self, rel: &str) -> bool {
        default_excluded(rel)
    }
    fn rewrite(&self, cx: &Ctx) -> Outcome;
    /// A legacy form that is a macro: `(name the parser sees in the expansion, name the text writes)`. The parser reports the expanded
    /// call, so the site is found by the first and read, and rewritten, as the second; its argument count is the text's own.
    fn ast_alias(&self) -> &'static [(&'static str, &'static str)] {
        &[]
    }
    /// Facts the rewrite of every site shares, built once from the whole tree.
    fn prepare(&self, _tree: &Tree, _sem: &Sem) -> Arc<dyn Any + Send + Sync> {
        Arc::new(())
    }
    /// TRUE for a codemod that also inserts declarations (its output adds lines, so the "no line added" gate does not apply to it).
    fn declares(&self) -> bool {
        false
    }
    /// The edits that declare what the rewritten sites asked for, as (file, edits) in each file's own coordinates.
    /// The edits for the definitions the kept sites asked to follow (`Rewrite::follows`), as (file, edits).
    fn follow_edits(&self, _root: &Path, _tree: &Tree, _sem: &Sem, _prep: &(dyn Any + Send + Sync), _follows: &[String]) -> Vec<(String, Vec<Edit>)> {
        Vec::new()
    }
    fn declaration_edits(&self, _root: &Path, _tree: &Tree, _sem: &Sem, _prep: &(dyn Any + Send + Sync), _needs: &[Need]) -> Vec<(String, Vec<Edit>)> {
        Vec::new()
    }
}

/// The directories the count method leaves out: the engine, the legacy object model, defines, unit tests
/// and benchmarks, the vendored TGS DMAPI.
pub const FRAMEWORK_PREFIXES: &[&str] = &["code/engine/", "code/datums/om/", "code/__defines/", "code/tests/", "code/modules/unit_tests/", "code/modules/benchmarks/", "code/modules/tgs/"];

pub fn default_excluded(rel: &str) -> bool {
    FRAMEWORK_PREFIXES.iter().any(|p| rel.starts_with(p))
}

/// Reason codes the framework itself gives.
pub const FRAMEWORK_REASONS: &[(&str, &str)] = &[
    ("not_in_ast", "the call is in text the parser did not return as a call: a macro body, an inactive #if, or a file the .dme does not include; convert by hand"),
    ("reference", "the name is passed around, not called (PROC_REF(x), a list of procs); convert by hand with its caller"),
    ("scan_failed", "the call's parentheses do not balance on the file's text; convert by hand"),
    ("arg_count_mismatch", "the scan and the parser disagree on the argument count; convert by hand"),
    ("location_unresolved", "the parser's position for the call does not match one call on that line; convert by hand"),
    ("edit_conflict", "two rewrites overlap; the outer one is residue, the inner converted"),
    ("not_utf8", "the file is not valid UTF-8"),
];

pub fn registry() -> Vec<Box<dyn Codemod>> {
    let mut v: Vec<Box<dyn Codemod>> = Vec::new();
    crate::codemods::register(&mut v);
    v.sort_by_key(|c| c.name());
    v
}

pub fn find(name: &str) -> Option<Box<dyn Codemod>> {
    registry().into_iter().find(|c| c.name() == name)
}

// ---------------------------------------------------------------------------------------------------------
// discovery on the AST

/// A call the parser reported.
#[derive(Clone, Debug)]
struct Cand {
    rel: String,
    line: u32,
    col: u32,
    callee: String,
    argc: usize,
    owner: String,
    proc_name: String,
    stmt_level: bool,
}

/// Every unscoped call of one of `names` in a proc body, with where the parser saw it.
fn candidates(sem: &Sem, names: &[&str]) -> Vec<Cand> {
    let mut out: Vec<Cand> = Vec::new();
    for ty in sem.objtree.iter_types() {
        let t = ty.get();
        let owner = if t.path.is_empty() { "/".to_string() } else { t.path.clone() };
        for (pname, p) in &t.procs {
            for value in &p.value {
                let Some(code) = &value.code else { continue };
                let mut found: Vec<(dreammaker::Location, String, usize, bool)> = Vec::new();
                walk_stmts(code, &mut |e, stmt_level| {
                    if let Expression::Base { term, .. } = e {
                        if let Term::Call(n, args) = &term.elem {
                            if names.contains(&n.as_str()) {
                                found.push((term.location, n.to_string(), args.len(), stmt_level));
                            }
                        }
                    }
                });
                for (loc, callee, argc, stmt_level) in found {
                    let Some(rel) = sem.file_of(loc) else { continue };
                    out.push(Cand { rel: rel.to_string(), line: loc.line, col: loc.column as u32, callee, argc, owner: owner.clone(), proc_name: pname.clone(), stmt_level });
                }
            }
        }
    }
    out
}

/// Every expression of a block with whether it is a whole expression statement (`foo(...)` on its own).
fn walk_stmts<'a>(b: &'a dreammaker::ast::Block, f: &mut dyn FnMut(&'a Expression, bool)) {
    for st in b.iter() {
        let whole = matches!(&st.elem, Statement::Expr(e) if matches!(e, Expression::Base { follow, .. } if follow.is_empty()));
        for e in stmt_exprs(&st.elem) {
            let top = e as *const Expression;
            walk_expr(e, &mut |x| f(x, whole && std::ptr::eq(x as *const Expression, top)));
        }
        if let Statement::ForLoop { init, inc, .. } = &st.elem {
            for s in [init, inc].into_iter().flatten() {
                for e in stmt_exprs(s) {
                    walk_expr(e, &mut |x| f(x, false));
                }
            }
        }
        for nb in stmt_blocks(&st.elem) {
            walk_stmts(nb, f);
        }
    }
}

/// Byte offset of the start of each line (1-based line `n` starts at `starts[n - 1]`).
fn line_starts(text: &str) -> Vec<usize> {
    let mut v = vec![0usize];
    for (i, b) in text.bytes().enumerate() {
        if b == b'\n' {
            v.push(i + 1);
        }
    }
    v
}

fn line_end(text: &str, starts: &[usize], line: usize) -> usize {
    if line < starts.len() {
        starts[line] - 1
    } else {
        text.len()
    }
}

/// The offset of the call the parser located at `(line, col)`: the column as given, or one less (the
/// parser's columns are 1-based when it counts the token and 0-based when it counts what precedes it),
/// else the one unclaimed call of that name on the line.
fn locate(text: &str, clean: &str, starts: &[usize], c: &Cand, claimed: &BTreeSet<usize>) -> Option<usize> {
    if c.line == 0 || c.line as usize > starts.len() {
        return None;
    }
    let ls = starts[c.line as usize - 1];
    let le = line_end(text, starts, c.line as usize);
    let line_text = &text[ls..le];
    let at = |idx: usize| line_text.char_indices().nth(idx).map(|(b, _)| ls + b);
    for idx in [c.col as usize, (c.col as usize).saturating_sub(1)] {
        if let Some(off) = at(idx) {
            if !claimed.contains(&off) && scan::scan_call(text, clean, off, &c.callee).is_ok() {
                return Some(off);
            }
        }
    }
    let occ: Vec<usize> = scan::call_offsets(&clean[ls..le], &c.callee).into_iter().map(|o| ls + o).filter(|o| !claimed.contains(o)).collect();
    if occ.len() == 1 {
        return Some(occ[0]);
    }
    None
}

// ---------------------------------------------------------------------------------------------------------
// the run

#[derive(Clone, Debug, Default)]
pub struct RunOpts {
    pub apply: bool,
    /// Only files whose repo path starts with one of these (empty = the whole tree).
    pub paths: Vec<String>,
}

/// One site that was not rewritten.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct ResidueSite {
    pub file: String,
    pub line: u32,
    pub reason: String,
    pub text: String,
}

/// The inverse of one edit, in the coordinates of the rewritten file.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Inverse {
    pub start: usize,
    pub len: usize,
    pub text: String,
}

#[derive(Clone, Debug)]
pub struct FileChange {
    pub rel: String,
    pub before: String,
    pub after: String,
    pub inverse: Vec<Inverse>,
    pub sites: usize,
}

#[derive(Default)]
pub struct RunResult {
    pub name: String,
    /// Calls the parser reported, in files in scope.
    pub ast_sites: usize,
    pub rewrites: usize,
    pub residue: Vec<ResidueSite>,
    /// Legacy calls and mentions in framework or test files: not part of the count.
    pub excluded: usize,
    /// Rewrites and residue in files the `--path` filter left out.
    pub outside_filter: usize,
    pub keys: Vec<KeyUse>,
    pub changes: Vec<FileChange>,
    /// Declarations inserted for the rewritten sites: (type, var) pairs.
    pub declared: Vec<Need>,
    /// Definitions rewritten to follow the sites (handlers whose signature changed).
    pub followed: usize,
}

impl RunResult {
    pub fn residue_by_reason(&self) -> BTreeMap<String, usize> {
        let mut m = BTreeMap::new();
        for r in &self.residue {
            *m.entry(r.reason.clone()).or_insert(0) += 1;
        }
        m
    }
    pub fn edited_lines(&self) -> usize {
        self.changes.iter().map(|c| changed_lines(&c.before, &c.after)).sum()
    }
}

/// How many lines differ between two versions of a file (the codemods never add or remove a line).
pub fn changed_lines(a: &str, b: &str) -> usize {
    let (la, lb): (Vec<&str>, Vec<&str>) = (a.split('\n').collect(), b.split('\n').collect());
    let n = la.len().max(lb.len());
    (0..n).filter(|&i| la.get(i) != lb.get(i)).count()
}

fn snippet(text: &str, off: usize) -> String {
    let ls = text[..off].rfind('\n').map(|p| p + 1).unwrap_or(0);
    let le = text[off..].find('\n').map(|p| off + p).unwrap_or(text.len());
    let s: String = text[ls..le].split_whitespace().collect::<Vec<_>>().join(" ");
    if s.chars().count() > 160 {
        let cut: String = s.chars().take(157).collect();
        format!("{}...", cut)
    } else {
        s
    }
}

/// Runs `cm` on the tree at `root`. With `opts.apply` the changes are in the result's `changes`; nothing is
/// written here (see [`write_changes`]).
pub fn run(root: &Path, cm: &dyn Codemod, opts: &RunOpts) -> Result<RunResult, String> {
    let mut plan = Plan::default();
    plan.add("code", "dm");
    plan.add("maps", "dm");
    let (tree, _meta) = Tree::load(root, &plan, &Default::default(), false);
    let sem = crate::sem::sem_for(&tree).ok_or_else(|| "the semantic model did not build".to_string())?;
    let names = cm.callees();
    let alias = cm.ast_alias();
    let mut ast_names: Vec<&str> = names.to_vec();
    ast_names.extend(alias.iter().map(|(a, _)| *a));
    let mut cands = candidates(&sem, &ast_names);
    for c in cands.iter_mut() {
        if let Some((_, text_name)) = alias.iter().find(|(a, _)| *a == c.callee) {
            c.callee = text_name.to_string();
            c.argc = usize::MAX;
        }
    }
    let prep = cm.prepare(&tree, &sem);

    let mut res = RunResult { name: cm.name().to_string(), ..Default::default() };
    // Files to look at: the parser's, and every file whose text names a callee.
    let mut files: BTreeSet<String> = cands.iter().map(|c| c.rel.clone()).collect();
    for f in tree.select(&crate::tree::CODE_MAPS_DM) {
        let t = f.text();
        if names.iter().any(|n| t.contains(n)) {
            files.insert(f.rel.clone());
        }
    }
    let mut by_file: BTreeMap<&str, Vec<&Cand>> = BTreeMap::new();
    for c in &cands {
        by_file.entry(c.rel.as_str()).or_default().push(c);
    }

    let mut file_edits: BTreeMap<String, (String, Vec<Edit>, usize)> = BTreeMap::new();
    let mut needs: Vec<Need> = Vec::new();
    let mut follows: Vec<String> = Vec::new();
    for rel in &files {
        let abs = root.join(rel);
        let Ok(bytes) = std::fs::read(&abs) else { continue };
        let in_scope = !cm.excluded(rel);
        let selected = opts.paths.is_empty() || opts.paths.iter().any(|p| rel.starts_with(p.as_str()));
        let Ok(text) = String::from_utf8(bytes) else {
            if in_scope {
                res.residue.push(ResidueSite { file: rel.clone(), line: 0, reason: "not_utf8".into(), text: String::new() });
            }
            continue;
        };
        let clean = crate::strip::sanitize(&text);
        let starts = line_starts(&text);
        if !in_scope {
            for n in names {
                res.excluded += scan::call_offsets(&clean, n).len() + scan::mention_offsets(&clean, n).len();
            }
            continue;
        }
        let empty = Vec::new();
        let file_cands = by_file.get(rel.as_str()).unwrap_or(&empty);
        let mut pending: Vec<ResidueSite> = Vec::new();
        let mut sites: Vec<(usize, Vec<Edit>, Vec<KeyUse>, Vec<Need>, Vec<String>)> = Vec::new();
        let mut claimed: BTreeSet<usize> = BTreeSet::new();
        let mut matched: BTreeMap<usize, (&Cand, bool)> = BTreeMap::new();
        let mut ordered: Vec<&&Cand> = file_cands.iter().collect();
        ordered.sort_by_key(|c| (c.line, c.col, c.callee.clone()));
        for c in ordered {
            match locate(&text, &clean, &starts, c, &claimed) {
                Some(off) => {
                    // The same call reached by two expansions of a macro is one site; it is a statement only if it is one in all.
                    claimed.insert(off);
                    matched.insert(off, (c, c.stmt_level));
                }
                None => {
                    // A second parse of an already claimed position (a macro expanded twice) is not residue.
                    let ls = starts[(c.line as usize).saturating_sub(1).min(starts.len() - 1)];
                    let line_has_claimed = claimed.iter().any(|o| *o >= ls && *o <= line_end(&text, &starts, c.line as usize) && text[*o..].starts_with(&c.callee));
                    if !line_has_claimed {
                        pending.push(ResidueSite { file: rel.clone(), line: c.line, reason: "location_unresolved".into(), text: snippet(&text, ls) });
                        res.ast_sites += 1;
                    }
                }
            }
        }
        for (off, (c, stmt)) in &matched {
            res.ast_sites += 1;
            let line = text[..*off].bytes().filter(|b| *b == b'\n').count() as u32 + 1;
            let node = match scan::scan_call(&text, &clean, *off, &c.callee) {
                Ok(n) => n,
                Err(_) => {
                    pending.push(ResidueSite { file: rel.clone(), line, reason: "scan_failed".into(), text: snippet(&text, *off) });
                    continue;
                }
            };
            if c.argc != usize::MAX && node.args.len() != c.argc {
                pending.push(ResidueSite { file: rel.clone(), line, reason: "arg_count_mismatch".into(), text: snippet(&text, *off) });
                continue;
            }
            let cx = Ctx { rel, line, text: &text, clean: &clean, node: &node, callee: &c.callee, owner: &c.owner, proc_name: &c.proc_name, stmt_level: *stmt, sem: &sem, prep: &*prep };
            match cm.rewrite(&cx) {
                Outcome::Rewrite(r) => sites.push((*off, r.edits, r.keys, r.needs, r.follows)),
                Outcome::Residue(reason, _why) => pending.push(ResidueSite { file: rel.clone(), line, reason: reason.to_string(), text: snippet(&text, *off) }),
            }
        }
        // Text the parser did not return as a call, and names used as values.
        for n in names {
            for off in scan::call_offsets(&clean, n) {
                if !claimed.contains(&off) {
                    // The definition of a macro form (`#define om_ask(...)`) is the form itself, not a use of it.
                    let ls = text[..off].rfind('\n').map(|p| p + 1).unwrap_or(0);
                    if text[ls..off].trim_start().strip_prefix("#define").map(|r| r.trim().is_empty()).unwrap_or(false) {
                        continue;
                    }
                    let line = text[..off].bytes().filter(|b| *b == b'\n').count() as u32 + 1;
                    pending.push(ResidueSite { file: rel.clone(), line, reason: "not_in_ast".into(), text: snippet(&text, off) });
                }
            }
            for off in scan::mention_offsets(&clean, n) {
                let line = text[..off].bytes().filter(|b| *b == b'\n').count() as u32 + 1;
                pending.push(ResidueSite { file: rel.clone(), line, reason: "reference".into(), text: snippet(&text, off) });
            }
        }
        // Overlapping edits: keep the earlier site, the later one is residue.
        sites.sort_by_key(|(off, _, _, _, _)| *off);
        let mut kept: Vec<(usize, Vec<Edit>, Vec<KeyUse>, Vec<Need>, Vec<String>)> = Vec::new();
        let mut taken: Vec<(usize, usize)> = Vec::new();
        for (off, edits, keys, needs, follows) in sites {
            let overlaps = edits.iter().any(|e| taken.iter().any(|(s, t)| if e.start == e.end { e.start > *s && e.start < *t } else { e.start < *t && e.end > *s }));
            if overlaps {
                let line = text[..off].bytes().filter(|b| *b == b'\n').count() as u32 + 1;
                pending.push(ResidueSite { file: rel.clone(), line, reason: "edit_conflict".into(), text: snippet(&text, off) });
                continue;
            }
            for e in &edits {
                taken.push((e.start, e.end));
            }
            kept.push((off, edits, keys, needs, follows));
        }
        if !selected {
            res.outside_filter += kept.len() + pending.len();
            // Residue and keys still count for the whole-tree report; only the edits are withheld.
            res.residue.extend(pending);
            for (_, _, k, _, _) in kept {
                res.keys.extend(k);
            }
            continue;
        }
        res.residue.extend(pending);
        let mut all_edits: Vec<Edit> = Vec::new();
        for (_, e, k, n, fo) in &kept {
            all_edits.extend(e.iter().cloned());
            res.keys.extend(k.iter().cloned());
            needs.extend(n.iter().cloned());
            follows.extend(fo.iter().cloned());
        }
        res.rewrites += kept.len();
        if all_edits.is_empty() {
            continue;
        }
        file_edits.insert(rel.clone(), (text, all_edits, kept.len()));
    }
    follows.sort();
    follows.dedup();
    if !follows.is_empty() {
        for (rel, edits) in cm.follow_edits(root, &tree, &sem, &*prep, &follows) {
            if edits.is_empty() {
                continue;
            }
            match file_edits.get_mut(&rel) {
                Some(entry) => {
                    // A definition edit inside text a call-site edit already replaces (an om_ask in a handler reading the old answer) is the call
                    // site's to translate: it would overlap.
                    let spans: Vec<(usize, usize)> = entry.1.iter().filter(|e| e.end > e.start).map(|e| (e.start, e.end)).collect();
                    entry.1.extend(edits.into_iter().filter(|f| !spans.iter().any(|(s, e)| *s <= f.start && f.end <= *e && f.end > f.start)));
                }
                None => {
                    if let Ok(text) = std::fs::read_to_string(root.join(&rel)) {
                        file_edits.insert(rel, (text, edits, 0));
                    }
                }
            }
            res.followed += 1;
        }
    }
    // The declarations the rewritten sites asked for: once per (type, var), in whichever file the type's block lives.
    needs.sort();
    needs.dedup_by(|a, b| a.holder == b.holder && a.var == b.var);
    if !needs.is_empty() {
        for (rel, edits) in cm.declaration_edits(root, &tree, &sem, &*prep, &needs) {
            if edits.is_empty() {
                continue;
            }
            match file_edits.get_mut(&rel) {
                Some(entry) => entry.1.extend(edits),
                None => {
                    if let Ok(text) = std::fs::read_to_string(root.join(&rel)) {
                        file_edits.insert(rel, (text, edits, 0));
                    }
                }
            }
        }
        res.declared = needs;
    }
    for (rel, (text, mut edits, n_sites)) in file_edits {
        edits.sort_by_key(|e| (e.start, e.end));
        for w in edits.windows(2) {
            if w[1].start < w[0].end {
                return Err(format!("{}: two edits overlap ({}..{} and {}..{}): a definition rewrite met a call-site rewrite", rel, w[0].start, w[0].end, w[1].start, w[1].end));
            }
        }
        let (after, inverse) = apply_edits(&text, edits);
        if after != text {
            res.changes.push(FileChange { rel, before: text, after, inverse, sites: n_sites });
        }
    }
    res.residue.sort();
    res.residue.dedup();
    res.keys.sort_by(|a, b| (a.owner.clone(), a.key.clone(), a.origin.clone()).cmp(&(b.owner.clone(), b.key.clone(), b.origin.clone())));
    Ok(res)
}

/// Applies `edits` (non-overlapping) to `text`. Returns the new text and the inverse of every edit in the
/// new text's coordinates, in file order. Insertions at one offset keep their given order.
pub fn apply_edits(text: &str, mut edits: Vec<Edit>) -> (String, Vec<Inverse>) {
    edits.sort_by_key(|e| (e.start, e.end));
    let mut out = String::with_capacity(text.len() + 64);
    let mut inv = Vec::new();
    let mut at = 0usize;
    for e in &edits {
        out.push_str(&text[at..e.start]);
        inv.push(Inverse { start: out.len(), len: e.text.len(), text: text[e.start..e.end].to_string() });
        out.push_str(&e.text);
        at = e.end;
    }
    out.push_str(&text[at..]);
    (out, inv)
}

/// Undoes [`apply_edits`].
pub fn revert_edits(after: &str, inverse: &[Inverse]) -> String {
    let mut out = String::with_capacity(after.len());
    let mut at = 0usize;
    for i in inverse {
        out.push_str(&after[at..i.start]);
        out.push_str(&i.text);
        at = i.start + i.len;
    }
    out.push_str(&after[at..]);
    out
}

fn hash_hex(s: &str) -> String {
    blake3::hash(s.as_bytes()).to_hex().to_string()
}

pub fn data_dir(root: &Path, name: &str) -> PathBuf {
    root.join("data").join("codemod").join(name)
}

pub fn codemod_dir(root: &Path, name: &str) -> PathBuf {
    root.join("tools").join("analyze").join("codemods").join(name)
}

/// Writes the changed files and the revert record (`data/codemod/<name>/revert.json`).
pub fn write_changes(root: &Path, res: &RunResult) -> Result<(), String> {
    for c in &res.changes {
        std::fs::write(root.join(&c.rel), c.after.as_bytes()).map_err(|e| format!("{}: {}", c.rel, e))?;
    }
    let dir = data_dir(root, &res.name);
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    std::fs::write(dir.join("revert.json"), report::revert_json(&res.name, &res.changes, hash_hex)).map_err(|e| e.to_string())?;
    Ok(())
}

/// Restores the files `--apply` changed, verifying each is still exactly what it wrote.
pub fn revert(root: &Path, name: &str) -> Result<usize, String> {
    let path = data_dir(root, name).join("revert.json");
    let text = std::fs::read_to_string(&path).map_err(|e| format!("{}: {} (nothing to revert: --apply writes it)", path.display(), e))?;
    let files = report::parse_revert(&text)?;
    let mut plan: Vec<(PathBuf, String)> = Vec::new();
    for f in &files {
        let abs = root.join(&f.file);
        let cur = std::fs::read_to_string(&abs).map_err(|e| format!("{}: {}", f.file, e))?;
        if hash_hex(&cur) != f.after_hash {
            return Err(format!("{} changed since the codemod wrote it; revert it with git instead", f.file));
        }
        let back = revert_edits(&cur, &f.inverse);
        if hash_hex(&back) != f.before_hash {
            return Err(format!("{}: the inverse does not reproduce the original (hash mismatch)", f.file));
        }
        plan.push((abs, back));
    }
    for (abs, back) in &plan {
        std::fs::write(abs, back.as_bytes()).map_err(|e| e.to_string())?;
    }
    let _ = std::fs::remove_file(&path);
    Ok(plan.len())
}

// ---------------------------------------------------------------------------------------------------------
// CLI

const HELP: &str = "analyze codemod: AST-aware rewriters (doc/rewrite/final_api.html, phase 2.5)

USAGE
  analyze codemod list
      The registered codemods, the legacy form each reads and what it becomes.
  analyze codemod NAME [--check] [--path PREFIX...] [--write-residue] [--sites] [--root DIR]
      Dry run on the tree: rewrites, residue by reason, the key-collision report. Exit 1 when there is
      residue not in the committed tools/analyze/codemods/NAME/residue.json (a new site that needs a human),
      when that file is missing, or when a key collision is unresolved. --write-residue writes
      residue.json (and keys.json when the codemod keys anything); it refuses with --path.
      --sites lists every residue site.
  analyze codemod NAME --apply [--path PREFIX...]
      Rewrite the files in place (no --path = the whole tree: phase 3 only, in a freeze window) and write
      data/codemod/NAME/revert.json.
  analyze codemod NAME --revert
      Undo the last --apply (each file must still be exactly what the codemod wrote).";

pub fn cli(args: &[String], root: &Path) -> ExitCode {
    let sub = args.first().map(|s| s.as_str()).unwrap_or("help");
    if sub == "help" || sub == "--help" {
        println!("{}", HELP);
        return ExitCode::SUCCESS;
    }
    if sub == "list" {
        for c in registry() {
            println!("{:<12} {}", c.name(), c.about());
        }
        return ExitCode::SUCCESS;
    }
    let Some(cm) = find(sub) else {
        eprintln!("analyze codemod: no codemod named {:?}; `analyze codemod list`", sub);
        return ExitCode::from(2);
    };
    let mut paths: Vec<String> = Vec::new();
    let (mut apply, mut do_revert, mut write_residue, mut list_sites) = (false, false, false, false);
    let mut it = args.iter().skip(1);
    while let Some(a) = it.next() {
        match a.as_str() {
            "--apply" => apply = true,
            "--check" => {}
            "--revert" => do_revert = true,
            "--write-residue" => write_residue = true,
            "--sites" => list_sites = true,
            "--path" => match it.next() {
                Some(p) => paths.push(p.replace('\\', "/")),
                None => {
                    eprintln!("analyze codemod: --path needs a prefix");
                    return ExitCode::from(2);
                }
            },
            other => {
                eprintln!("analyze codemod: unknown argument {:?}", other);
                return ExitCode::from(2);
            }
        }
    }
    if do_revert {
        return match revert(root, cm.name()) {
            Ok(n) => {
                println!("reverted {} files", n);
                ExitCode::SUCCESS
            }
            Err(e) => {
                eprintln!("analyze codemod: {}", e);
                ExitCode::from(1)
            }
        };
    }
    if write_residue && !paths.is_empty() {
        eprintln!("analyze codemod: --write-residue describes the whole tree; drop --path");
        return ExitCode::from(2);
    }
    let t = std::time::Instant::now();
    let opts = RunOpts { apply, paths: paths.clone() };
    let res = match run(root, cm.as_ref(), &opts) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("analyze codemod: {}", e);
            return ExitCode::from(2);
        }
    };
    let key_report = keys::analyze(&res.keys);
    println!("{}", report::summary(cm.as_ref(), &res, &key_report, t.elapsed()));
    if list_sites {
        for r in &res.residue {
            println!("  {}:{}: [{}] {}", r.file, r.line, r.reason, r.text);
        }
    }
    if apply {
        if data_dir(root, cm.name()).join("revert.json").exists() {
            eprintln!("analyze codemod: data/codemod/{}/revert.json exists: an earlier --apply is not reverted; run --revert (or delete it) first", cm.name());
            return ExitCode::from(2);
        }
        if let Err(e) = write_changes(root, &res) {
            eprintln!("analyze codemod: {}", e);
            return ExitCode::from(2);
        }
        println!("{}", report::revert_recipe(cm.name(), &res));
        return ExitCode::SUCCESS;
    }
    let dir = codemod_dir(root, cm.name());
    if write_residue {
        if let Err(e) = std::fs::create_dir_all(&dir).and_then(|_| std::fs::write(dir.join("residue.json"), report::residue_json(cm.as_ref(), &res))) {
            eprintln!("analyze codemod: {}", e);
            return ExitCode::from(2);
        }
        if !res.keys.is_empty() {
            let _ = std::fs::write(dir.join("keys.json"), report::keys_json(&key_report, &res.keys));
        }
        println!("wrote {}", dir.join("residue.json").display());
        return ExitCode::SUCCESS;
    }
    // The gate.
    let mut fail = false;
    match std::fs::read_to_string(dir.join("residue.json")) {
        Err(_) => {
            eprintln!("analyze codemod: {} has no committed residue.json; run --write-residue", cm.name());
            fail = true;
        }
        Ok(text) => match report::parse_residue(&text) {
            Err(e) => {
                eprintln!("analyze codemod: residue.json: {}", e);
                fail = true;
            }
            Ok(committed) => {
                let known: BTreeSet<String> = committed.iter().map(report::fingerprint).collect();
                let fresh: Vec<&ResidueSite> = res.residue.iter().filter(|r| !known.contains(&report::fingerprint(r))).collect();
                if !fresh.is_empty() {
                    eprintln!("analyze codemod: {} residue sites not in residue.json:", fresh.len());
                    for r in fresh.iter().take(25) {
                        eprintln!("  {}:{}: [{}] {}", r.file, r.line, r.reason, r.text);
                    }
                    fail = true;
                }
            }
        },
    }
    if key_report.unresolved > 0 {
        eprintln!("analyze codemod: {} unresolved key collisions", key_report.unresolved);
        fail = true;
    }
    if fail {
        ExitCode::from(1)
    } else {
        ExitCode::SUCCESS
    }
}
