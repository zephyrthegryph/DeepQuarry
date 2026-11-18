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
pub(crate) mod work;

use std::any::Any;
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::Arc;

#[cfg(feature="legacy-sem")]
use dreammaker::ast::{Expression, Statement, Term};

#[cfg(feature="legacy-sem")]
use crate::sem::ast::{stmt_blocks, stmt_exprs, walk_expr};
#[cfg(feature="legacy-sem")]
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
    /// Actual native query/admission I/O is never semantic residue.
    Operational(std::io::Error),
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
    pub sem: &'a dyn crate::codemod_facts::FactSource,
    /// What the codemod's `prepare()` built once for the run (`()` for a codemod that has none).
    pub prep: &'a (dyn Any + Send + Sync),
    /// Actual operation loan; None preserves old legacy allocation behavior.
    pub work: Option<&'a dyn crate::policy_finish::admitted::Work>,
}

impl Ctx<'_> {
    pub(crate) fn own_using(&self,text:&str)->std::io::Result<String>{work::own(self.work,text)}
    pub(crate) fn format_using(&self,args:std::fmt::Arguments<'_>)->std::io::Result<String>{work::format(self.work,args)}
    pub(crate) fn singleton_using<T>(&self,value:T)->std::io::Result<Vec<T>>{if let Some(work)=self.work{work.checkpoint()?;work.reserve(std::mem::size_of::<T>().checked_add(std::mem::size_of::<Vec<T>>()).ok_or_else(||work.overflow())?)?;}Ok(vec![value])}
    pub(crate) fn row_using<T>(&self,rows:&mut Vec<T>)->std::io::Result<()>{work::row(self.work,rows)}
    pub(crate) fn origin_using(&self)->std::io::Result<String>{self.format_using(format_args!("{}:{}",self.rel,self.line))}
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
    /// A legacy form that is a macro: `(name the parser sees in the expansion, name the text writes, argument count of the expansion)`.
    /// The parser reports the expanded call, so the site is found by the first and read, and rewritten, as the second. The count tells
    /// macros that expand to the same call apart (`sparse_get(D, x)` and `sparse_get_or(D, x, d)` are both `_sparse_get`, with 2 and 3
    /// arguments); a macro whose text has the expansion's own arguments in the same number is checked against the scan, others (count 0) are not.
    fn ast_alias(&self) -> &'static [(&'static str, &'static str, usize)] {
        &[]
    }
    /// Facts the rewrite of every site shares, built once from the whole tree.
    fn prepare(&self, _tree: &Tree, _sem: &dyn crate::codemod_facts::FactSource) -> Arc<dyn Any + Send + Sync> {
        Arc::new(())
    }
    /// TRUE for a codemod that also inserts declarations (its output adds lines, so the "no line added" gate does not apply to it).
    fn declares(&self) -> bool {
        false
    }
    /// The edits that declare what the rewritten sites asked for, as (file, edits) in each file's own coordinates.
    /// The edits for the definitions the kept sites asked to follow (`Rewrite::follows`), as (file, edits).
    fn follow_edits(&self, _root: &Path, _tree: &Tree, _sem: &dyn crate::codemod_facts::FactSource, _prep: &(dyn Any + Send + Sync), _follows: &[String]) -> Vec<(String, Vec<Edit>)> {
        Vec::new()
    }
    /// Same empty default as follow_edits; a producer that follows handlers
    /// implements this admitted ingress over actual per-file loans as well.
    fn follow_edits_admitted(&self,_root:&Path,_lexical:&dyn LexicalFiles,_sem:&dyn crate::codemod_facts::FactSource,_prep:&(dyn Any+Send+Sync),_follows:&[String],work:&dyn crate::policy_finish::admitted::Work)->std::io::Result<Vec<(String,Vec<Edit>)>>{work.checkpoint()?;Ok(Vec::new())}
    fn declaration_edits_admitted(&self, _root:&Path,_sem:&dyn crate::codemod_facts::FactSource,_prep:&(dyn Any+Send+Sync),_physical:&dyn PhysicalFiles,_needs:&[Need],_work:&dyn crate::policy_finish::admitted::Work)->std::io::Result<Vec<(String,Vec<Edit>)>>{Err(std::io::Error::new(std::io::ErrorKind::Unsupported,"codemod has no admitted declaration producer"))}
    fn declaration_edits(&self, _root: &Path, _tree: &Tree, _sem: &dyn crate::codemod_facts::FactSource, _prep: &(dyn Any + Send + Sync), _physical:&dyn PhysicalFiles, _needs: &[Need]) -> std::io::Result<Vec<(String, Vec<Edit>)>> {
        Ok(Vec::new())
    }
}

/// The directories the count method leaves out: the engine, the legacy object model, defines, unit tests
/// and benchmarks, the vendored TGS DMAPI.
pub const FRAMEWORK_PREFIXES: &[&str] = &["code/engine/", "code/datums/om/", "code/__defines/", "code/defines/engine/", "code/defines/library/", "code/defines/host/", "code/defines/base/", "code/defines/content/", "code/tests/", "code/tests/unit_tests/", "code/tests/benchmarks/", "code/world/tgs/"];

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
pub struct Cand {
    pub rel: String,
    pub line: u32,
    pub col: u32,
    pub callee: String,
    pub argc: usize,
    pub owner: String,
    pub proc_name: String,
    pub stmt_level: bool,
}

/// Every unscoped call of one of `names` in a proc body, with where the parser saw it.
#[cfg(feature="legacy-sem")]
fn candidates(sem: &Sem, names: &[&str]) -> Vec<Cand> {
    let mut out: Vec<Cand> = Vec::new();
    for ty in sem.objtree.iter_types() {
        let t = ty.get();
        let owner = if t.path.is_empty() { "/".to_string() } else { t.path.clone() };
        for (pname, p) in &t.procs {
            for value in &p.value {
                let Some(code) = &*value.code else { continue };
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
#[cfg(feature="legacy-sem")]
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

fn line_starts_using(text:&str,work:Option<&dyn crate::policy_finish::admitted::Work>)->std::io::Result<Vec<usize>>{
 let count=work::size(work,text.bytes().filter(|byte|*byte==b'\n').count().checked_add(1))?;
 let mut rows=work::vec_capacity(work,count)?;rows.push(0);
 for(index,byte)in text.bytes().enumerate(){if index%1024==0{work::checkpoint(work)?;}if byte==b'\n'{rows.push(index+1);}}
 Ok(rows)
}
fn residue_using(work:Option<&dyn crate::policy_finish::admitted::Work>,relative:&str,line:u32,reason:&str,text:&str,off:usize)->std::io::Result<ResidueSite>{
 let start=text[..off].rfind('\n').map_or(0,|p|p+1);let end=text[off..].find('\n').map_or(text.len(),|p|off+p);
 let mut normalized=work::string_capacity(work,end-start)?;
 for word in text[start..end].split_whitespace(){work::checkpoint(work)?;if !normalized.is_empty(){normalized.push(' ');}normalized.push_str(word);}
 let snippet=if normalized.chars().count()>160{let end=normalized.char_indices().nth(157).map_or(normalized.len(),|(byte,_)|byte);work::format(work,format_args!("{}...",&normalized[..end]))?}else{normalized};
 Ok(ResidueSite{file:work::own(work,relative)?,line,reason:work::own(work,reason)?,text:snippet})
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
fn locate(text: &str, clean: &str, starts: &[usize], c: &Cand, claimed: &[usize], work:Option<&dyn crate::policy_finish::admitted::Work>) -> std::io::Result<Option<usize>> {
    if c.line == 0 || c.line as usize > starts.len() {
        return Ok(None);
    }
    let ls = starts[c.line as usize - 1];
    let le = line_end(text, starts, c.line as usize);
    let line_text = &text[ls..le];
    let at = |idx: usize| line_text.char_indices().nth(idx).map(|(b, _)| ls + b);
    for idx in [c.col as usize, (c.col as usize).saturating_sub(1)] {
        if let Some(off) = at(idx) {
            if claimed.binary_search(&off).is_err() && scan::scan_call_using(text, clean, off, &c.callee,work)?.is_ok() {
                return Ok(Some(off));
            }
        }
    }
    let mut occurrences=scan::call_offsets_iter(&clean[ls..le],&c.callee).map(|offset|ls+offset).filter(|offset|claimed.binary_search(offset).is_err());
    let first=occurrences.next();
    Ok(if occurrences.next().is_none(){first}else{None})
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
#[cfg(feature="legacy-sem")]
pub fn run(root: &Path, cm: &dyn Codemod, opts: &RunOpts) -> Result<RunResult, String> {
    let mut plan = Plan::default();
    plan.add("code", "dm");
    plan.add("maps", "dm");
    let (tree, _meta) = Tree::load(root, &plan, &Default::default(), false);
    let sem = crate::sem::sem_for(&tree).ok_or_else(|| "the semantic model did not build".to_string())?;
    let names = cm.callees();
    let alias = cm.ast_alias();
    let mut ast_names: Vec<&str> = names.to_vec();
    ast_names.extend(alias.iter().map(|(a, _, _)| *a));
    let mut cands = candidates(&sem, &ast_names);
    for c in &mut cands{let(text,argc)=normalized_candidate(&c.callee,c.argc,cm.ast_alias());if text!=c.callee{c.callee=text.to_owned();}c.argc=argc;}
    let prep = cm.prepare(&tree, sem.as_ref());
    run_prepared(root,&tree,cm,opts,sem.as_ref(),&*prep,&LegacyPhysicalFiles(root),&cands).map_err(|actual|actual.to_string())
}

/// Exact original AST-macro-to-authored-call normalization over borrowed DATA.
pub fn normalized_candidate<'a>(callee:&'a str,argc:usize,aliases:&'a[(&str,&str,usize)])->(&'a str,usize){
    match aliases.iter().find(|(actual,_,count)|*actual==callee&&(*count==0||*count==argc)){
        Some((_,text,count))=>(*text,if *count==0{usize::MAX}else{argc}),None=>(callee,argc),
    }
}
/// Physical bytes supplied by the actual pre-final recorder loan. Implementors
/// retain/admit returned backing through the resulting plan's lifetime. This
/// DATA port issues no source/currentness or physical-write permission.
pub trait PhysicalFiles{
    fn read(&self,relative:&str)->std::io::Result<Option<Vec<u8>>>;
    /// A native issuer must preadmit the returned copy against SAME retained
    /// output work before allocating it. Captured inputs alone are not enough.
    fn read_using(&self,relative:&str,work:Option<&dyn crate::policy_finish::admitted::Work>)->std::io::Result<Option<Vec<u8>>>{
        if let Some(work)=work{work.checkpoint()?;return Err(std::io::Error::new(std::io::ErrorKind::Unsupported,"native physical copy issuer must supply explicit admission"))}
        self.read(relative)
    }
}
#[cfg(feature="legacy-sem")]
struct LegacyPhysicalFiles<'a>(&'a Path);
#[cfg(feature="legacy-sem")]
impl PhysicalFiles for LegacyPhysicalFiles<'_>{
    fn read(&self,relative:&str)->std::io::Result<Option<Vec<u8>>>{Ok(std::fs::read(self.0.join(relative)).ok())}
}
fn physical_text(files:&dyn PhysicalFiles,relative:&str)->std::io::Result<Option<String>>{physical_text_using(files,relative,None)}
fn physical_text_using(files:&dyn PhysicalFiles,relative:&str,work:Option<&dyn crate::policy_finish::admitted::Work>)->std::io::Result<Option<String>>{Ok(files.read_using(relative,work)?.and_then(|bytes|String::from_utf8(bytes).ok()))}

/// SAME original edit kernel over genuine native call DATA and captured bytes.
/// The caller holds the model/ledger, preparation scratch, and output work; this
/// function never crawls, parses a Model, or writes a physical file.
pub fn run_prepared(root:&Path,tree:&Tree,cm:&dyn Codemod,opts:&RunOpts,sem:&dyn crate::codemod_facts::FactSource,prep:&(dyn Any+Send+Sync),physical:&dyn PhysicalFiles,cands:&[Cand])->std::io::Result<RunResult>{run_prepared_using(root,Some(tree),&TreeLexical(tree),cm,opts,sem,prep,physical,cands,None)}
pub(crate) fn run_prepared_with_work(root:&Path,tree:&Tree,cm:&dyn Codemod,opts:&RunOpts,sem:&dyn crate::codemod_facts::FactSource,prep:&(dyn Any+Send+Sync),physical:&dyn PhysicalFiles,cands:&[Cand],work:&dyn crate::policy_finish::admitted::Work)->std::io::Result<RunResult>{run_prepared_using(root,Some(tree),&TreeLexical(tree),cm,opts,sem,prep,physical,cands,Some(work))}
fn run_prepared_using(root:&Path,tree:Option<&Tree>,lexical:&dyn LexicalFiles,cm:&dyn Codemod,opts:&RunOpts,sem:&dyn crate::codemod_facts::FactSource,prep:&(dyn Any+Send+Sync),physical:&dyn PhysicalFiles,cands:&[Cand],work:Option<&dyn crate::policy_finish::admitted::Work>)->std::io::Result<RunResult>{
    let names=cm.callees();
    work::checkpoint(work)?;
    let mut res = RunResult { name: work::own(work,cm.name())?, ..Default::default() };
    // Files to look at: the parser's, and every file whose text names a callee.
    let mut files:Vec<String>=Vec::new();
    for candidate in cands{work::set_insert(work,&mut files,work::own(work,&candidate.rel)?)?;}
    lexical.for_each(&mut|file|{
        work::checkpoint(work)?;
        if crate::tree::CODE_MAPS_DM.matches(file)&&names.iter().any(|name|file.text().contains(name)){work::set_insert(work,&mut files,work::own(work,&file.rel)?)?;}
        Ok(())
    })?;
    let mut file_edits: Vec<(String,(String, Vec<Edit>, usize))> = Vec::new();
    let mut needs: Vec<Need> = Vec::new();
    let mut follows: Vec<String> = Vec::new();
    for relative in files {
        let rel=relative.as_str();work::checkpoint(work)?;
        let Some(bytes)=physical.read_using(rel,work)?else{continue};
        let in_scope = !cm.excluded(rel);
        let selected = opts.paths.is_empty() || opts.paths.iter().any(|p| rel.starts_with(p.as_str()));
        let Ok(text) = String::from_utf8(bytes) else {
            if in_scope {
                work::row(work,&mut res.residue)?;res.residue.push(ResidueSite{file:work::own(work,rel)?,line:0,reason:work::own(work,"not_utf8")?,text:String::new()});
            }
            continue;
        };
        lexical.with_physical_clean(rel,&text,&mut|clean|{
        let starts=line_starts_using(&text,work)?;
        if !in_scope {
            for n in names {
                res.excluded += scan::call_offsets_iter(&clean,n).count()+scan::mention_offsets_iter(&clean,n).count();
            }
            return Ok(());
        }
        let mut file_cands=Vec::new();
        for candidate in cands.iter().filter(|candidate|candidate.rel==rel){work::row(work,&mut file_cands)?;file_cands.push(candidate);}
        let mut pending: Vec<ResidueSite> = Vec::new();
        let mut sites: Vec<(usize, Vec<Edit>, Vec<KeyUse>, Vec<Need>, Vec<String>)> = Vec::new();
        let mut claimed:Vec<usize>=Vec::new();
        let mut matched:Vec<(usize,(&Cand,bool))>=Vec::new();
        let mut ordered=file_cands;
        if let Some(work)=work{work.reserve(ordered.len().checked_mul(std::mem::size_of::<&Cand>()).ok_or_else(||work.overflow())?)?;}
        ordered.sort_by(|a,b|(a.line,a.col,a.callee.as_str()).cmp(&(b.line,b.col,b.callee.as_str())));
        for c in ordered {
            match locate(&text, &clean, &starts, c, &claimed,work)? {
                Some(off) => {
                    // The same call reached by two expansions of a macro is one site; it is a statement only if it is one in all.
                    work::set_insert(work,&mut claimed,off)?;
                    if let Some((_,whole))=work::map_get_mut(&mut matched,&off){*whole &= c.stmt_level}else{work::map_insert(work,&mut matched,off,(c,c.stmt_level))?;}
                }
                None => {
                    // A second parse of an already claimed position (a macro expanded twice) is not residue.
                    let ls = starts[(c.line as usize).saturating_sub(1).min(starts.len() - 1)];
                    let line_has_claimed = claimed.iter().any(|o| *o >= ls && *o <= line_end(&text, &starts, c.line as usize) && text[*o..].starts_with(&c.callee));
                    if !line_has_claimed {
                        work::row(work,&mut pending)?;pending.push(residue_using(work,rel,c.line,"location_unresolved",&text,ls)?);
                        res.ast_sites += 1;
                    }
                }
            }
        }
        for (off, (c, stmt)) in &matched {
            res.ast_sites += 1;
            let line = text[..*off].bytes().filter(|b| *b == b'\n').count() as u32 + 1;
            let node = match scan::scan_call_using(&text,&clean,*off,&c.callee,work)? {
                Ok(n) => n,
                Err(_) => {
                    work::row(work,&mut pending)?;pending.push(residue_using(work,rel,line,"scan_failed",&text,*off)?);
                    continue;
                }
            };
            if c.argc != usize::MAX && node.args.len() != c.argc {
                work::row(work,&mut pending)?;pending.push(residue_using(work,rel,line,"arg_count_mismatch",&text,*off)?);
                continue;
            }
            let cx = Ctx { rel, line, text: &text, clean: &clean, node: &node, callee: &c.callee, owner: &c.owner, proc_name: &c.proc_name, stmt_level: *stmt, sem, prep, work };
            match cm.rewrite(&cx) {
                Outcome::Rewrite(r) => {work::row(work,&mut sites)?;sites.push((*off,r.edits,r.keys,r.needs,r.follows));},
                Outcome::Residue(reason,_why)=>{work::row(work,&mut pending)?;pending.push(residue_using(work,rel,line,reason,&text,*off)?);},
                Outcome::Operational(actual) => return Err(actual),
            }
        }
        // Text the parser did not return as a call, and names used as values.
        for n in names {
            for off in scan::call_offsets_iter(&clean,n) {
                if claimed.binary_search(&off).is_err() {
                    // The definition of a macro form (`#define om_ask(...)`) is the form itself, not a use of it.
                    let ls = text[..off].rfind('\n').map(|p| p + 1).unwrap_or(0);
                    if text[ls..off].trim_start().strip_prefix("#define").map(|r| r.trim().is_empty()).unwrap_or(false) {
                        continue;
                    }
                    let line = text[..off].bytes().filter(|b| *b == b'\n').count() as u32 + 1;
                    work::row(work,&mut pending)?;pending.push(residue_using(work,rel,line,"not_in_ast",&text,off)?);
                }
            }
            for off in scan::mention_offsets_iter(&clean,n) {
                let line = text[..off].bytes().filter(|b| *b == b'\n').count() as u32 + 1;
                work::row(work,&mut pending)?;pending.push(residue_using(work,rel,line,"reference",&text,off)?);
            }
        }
        // Overlapping edits: keep the earlier site, the later one is residue.
        work::stable_sort_by(work,&mut sites,|a,b|a.0.cmp(&b.0))?;
        let mut kept: Vec<(usize, Vec<Edit>, Vec<KeyUse>, Vec<Need>, Vec<String>)> = Vec::new();
        let mut taken: Vec<(usize, usize)> = Vec::new();
        for (off, edits, keys, needs, follows) in sites {
            let overlaps = edits.iter().any(|e| taken.iter().any(|(s, t)| if e.start == e.end { e.start > *s && e.start < *t } else { e.start < *t && e.end > *s }));
            if overlaps {
                let line = text[..off].bytes().filter(|b| *b == b'\n').count() as u32 + 1;
                work::row(work,&mut pending)?;pending.push(residue_using(work,rel,line,"edit_conflict",&text,off)?);
                continue;
            }
            for e in &edits {
                work::row(work,&mut taken)?;taken.push((e.start,e.end));
            }
            work::row(work,&mut kept)?;kept.push((off,edits,keys,needs,follows));
        }
        if !selected {
            res.outside_filter += kept.len() + pending.len();
            // Residue and keys still count for the whole-tree report; only the edits are withheld.
            work::extend(work,&mut res.residue,pending)?;
            for (_, _, k, _, _) in kept {
                work::extend(work,&mut res.keys,k)?;
            }
            return Ok(());
        }
        work::extend(work,&mut res.residue,pending)?;
        let mut all_edits: Vec<Edit> = Vec::new();
        let kept_count=kept.len();
        for(_,edits,keys,new_needs,new_follows)in kept{
            work::extend(work,&mut all_edits,edits)?;
            work::extend(work,&mut res.keys,keys)?;
            work::extend(work,&mut needs,new_needs)?;
            work::extend(work,&mut follows,new_follows)?;
        }
        res.rewrites+=kept_count;
        if all_edits.is_empty(){return Ok(())}
        work::map_insert(work,&mut file_edits,work::own(work,rel)?,(work::own(work,&text)?,all_edits,kept_count))?;
        Ok(())
        })?;
    }
    work::stable_sort_by(work,&mut follows,Ord::cmp)?;
    follows.dedup();
    if !follows.is_empty(){
        let additions=match work{Some(work)=>cm.follow_edits_admitted(root,lexical,sem,prep,&follows,work)?,None=>cm.follow_edits(root,tree.ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidInput,"legacy follow-edit context absent"))?,sem,prep,&follows)};
        for(rel,edits)in additions{
            work::checkpoint(work)?;if edits.is_empty(){continue}
            match work::map_get_mut(&mut file_edits,rel.as_str()){
                Some(entry)=>{
                    let mut spans=Vec::new();for edit in &entry.1{work::checkpoint(work)?;if edit.end>edit.start{work::row(work,&mut spans)?;spans.push((edit.start,edit.end));}}
                    for edit in edits{work::checkpoint(work)?;if !spans.iter().any(|(start,end)|*start<=edit.start&&edit.end<=*end&&edit.end>edit.start){work::row(work,&mut entry.1)?;entry.1.push(edit);}}
                },None=>if let Some(text)=physical_text_using(physical,&rel,work)?{work::map_insert(work,&mut file_edits,rel,(text,edits,0))?;},
            }
            res.followed+=1;
        }
    }
    // The declarations the rewritten sites asked for: once per (type, var), in whichever file the type's block lives.
    work::stable_sort_by(work,&mut needs,Ord::cmp)?;
    needs.dedup_by(|a, b| a.holder == b.holder && a.var == b.var);
    if !needs.is_empty() {
        let declarations=match work{Some(work)=>cm.declaration_edits_admitted(root,sem,prep,physical,&needs,work)?,None=>cm.declaration_edits(root,tree.ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidInput,"legacy declaration context absent"))?,sem,prep,physical,&needs)?};
        for(rel,edits)in declarations{
            if edits.is_empty() {
                continue;
            }
            match work::map_get_mut(&mut file_edits,rel.as_str()) {
                Some(entry)=>{work::extend(work,&mut entry.1,edits)?;},
                None => {
                    if let Some(text) = physical_text(physical,&rel)? {
                        work::map_insert(work,&mut file_edits,rel,(text,edits,0))?;
                    }
                }
            }
        }
        res.declared = needs;
    }
    for (rel, (text, mut edits, n_sites)) in file_edits {
        work::stable_sort_by(work,&mut edits,|a,b|(a.start,a.end).cmp(&(b.start,b.end)))?;
        for w in edits.windows(2) {
            if w[1].start < w[0].end {
                return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,work::format(work,format_args!("{}: two edits overlap ({}..{} and {}..{}): a definition rewrite met a call-site rewrite",rel,w[0].start,w[0].end,w[1].start,w[1].end))?));
            }
        }
        let (after, inverse) = apply_edits_using(&text, edits,work)?;
        if after != text {
            work::row(work,&mut res.changes)?;res.changes.push(FileChange{rel,before:text,after,inverse,sites:n_sites});
        }
    }
    work::stable_sort_by(work,&mut res.residue,Ord::cmp)?;
    res.residue.dedup();
    work::stable_sort_by(work,&mut res.keys,|a,b|(a.owner.as_str(),a.key.as_str(),a.origin.as_str()).cmp(&(b.owner.as_str(),b.key.as_str(),b.origin.as_str())))?;
    Ok(res)
}

/// Applies `edits` (non-overlapping) to `text`. Returns the new text and the inverse of every edit in the
/// new text's coordinates, in file order. Insertions at one offset keep their given order.
pub fn apply_edits(text:&str,edits:Vec<Edit>)->(String,Vec<Inverse>){apply_edits_using(text,edits,None).expect("original codemod edits must have valid ordered spans")}
pub fn revert_edits(after:&str,inverse:&[Inverse])->String{revert_edits_using(after,inverse,None).expect("original codemod inverse must have valid ordered spans")}
fn apply_edits_using(text:&str,mut edits:Vec<Edit>,work:Option<&dyn crate::policy_finish::admitted::Work>)->std::io::Result<(String,Vec<Inverse>)>{
    work::checkpoint(work)?;
    // Stable sorting preserves same-offset insertion order. The standard
    // slice sort's possible scratch has at most one slot per actual row.
    if let Some(work)=work{work.reserve(edits.len().checked_mul(std::mem::size_of::<Edit>()).ok_or_else(||work.overflow())?)?;}
    edits.sort_by_key(|e|(e.start,e.end));
    let(mut at,mut length)=(0usize,text.len());
    for e in &edits{
        work::checkpoint(work)?;
        if e.start<at||e.start>e.end||e.end>text.len()||!text.is_char_boundary(e.start)||!text.is_char_boundary(e.end){return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"codemod edit spans overlap or escape the original UTF-8 text"))}
        length=work::size(work,length.checked_sub(e.end-e.start).and_then(|n|n.checked_add(e.text.len())))?;
        at=e.end;
    }
    let mut out=work::string_capacity(work,length)?;
    let mut inverse=work::vec_capacity(work,edits.len())?;
    at=0;
    for e in edits{
        work::checkpoint(work)?;
        out.push_str(&text[at..e.start]);
        let original=work::own(work,&text[e.start..e.end])?;
        inverse.push(Inverse{start:out.len(),len:e.text.len(),text:original});
        out.push_str(&e.text);at=e.end;
    }
    out.push_str(&text[at..]);
    work::checkpoint(work)?;
    Ok((out,inverse))
}
pub(crate) fn revert_edits_using(after:&str,inverse:&[Inverse],work:Option<&dyn crate::policy_finish::admitted::Work>)->std::io::Result<String>{
    work::checkpoint(work)?;
    let(mut at,mut length)=(0usize,after.len());
    for row in inverse{
        let end=work::size(work,row.start.checked_add(row.len))?;
        if row.start<at||end>after.len()||!after.is_char_boundary(row.start)||!after.is_char_boundary(end){return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"codemod inverse spans overlap or escape the rewritten UTF-8 text"))}
        length=work::size(work,length.checked_sub(row.len).and_then(|n|n.checked_add(row.text.len())))?;at=end;
    }
    let mut out=work::string_capacity(work,length)?;at=0;
    for row in inverse{work::checkpoint(work)?;out.push_str(&after[at..row.start]);out.push_str(&row.text);at=row.start+row.len;}
    out.push_str(&after[at..]);work::checkpoint(work)?;Ok(out)
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
#[cfg(feature="legacy-sem")]
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
#[cfg(feature="legacy-sem")]
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

pub use crate::codemod_spec::HELP;

#[cfg(feature="legacy-sem")]
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

/// Borrowed lexical DATA only. The caller authenticates the physical roster,
/// source/model owner and final recorder; no parser or source grant is issued.
pub trait LexicalFiles{
 fn for_each(&self,visit:&mut dyn FnMut(&crate::tree::SourceFile)->std::io::Result<()>)->std::io::Result<()>;
 fn with_physical_clean(&self,relative:&str,text:&str,visit:&mut dyn FnMut(&str)->std::io::Result<()>)->std::io::Result<()>;
}
struct TreeLexical<'a>(&'a Tree);
impl LexicalFiles for TreeLexical<'_>{
 fn for_each(&self,visit:&mut dyn FnMut(&crate::tree::SourceFile)->std::io::Result<()>)->std::io::Result<()>{for file in &self.0.files{visit(file)?;}Ok(())}
 fn with_physical_clean(&self,_relative:&str,text:&str,visit:&mut dyn FnMut(&str)->std::io::Result<()>)->std::io::Result<()>{visit(&crate::strip::sanitize(text))}
}
pub(crate) fn run_prepared_streamed(root:&Path,lexical:&dyn LexicalFiles,cm:&dyn Codemod,opts:&RunOpts,sem:&dyn crate::codemod_facts::FactSource,prep:&(dyn Any+Send+Sync),physical:&dyn PhysicalFiles,cands:&[Cand],work:&dyn crate::policy_finish::admitted::Work)->std::io::Result<RunResult>{run_prepared_using(root,None,lexical,cm,opts,sem,prep,physical,cands,Some(work))}
pub fn native_find(name:&str)->Option<&'static dyn Codemod>{
 static AFTER:crate::codemods::om_after::OmAfter=crate::codemods::om_after::OmAfter;
 static SET:crate::codemods::own_set::OwnSet=crate::codemods::own_set::OwnSet;
 static ADD:crate::codemods::own_add::OwnAdd=crate::codemods::own_add::OwnAdd;
 if name==crate::codemod_spec::OM_AFTER.name{Some(&AFTER)}else if name==crate::codemod_spec::OWN_SET.name{Some(&SET)}else if name==crate::codemod_spec::OWN_ADD.name{Some(&ADD)}else{None}
}

#[cfg(test)]mod admitted_edit_tests{
 use super::*;use crate::policy_finish::admitted::Work;use std::cell::Cell;
 struct Quota{left:Cell<usize>}
 impl Work for Quota{fn checkpoint(&self)->std::io::Result<()>{Ok(())}fn reserve(&self,n:usize)->std::io::Result<()>{let remaining=self.left.get().checked_sub(n).ok_or_else(||self.overflow())?;self.left.set(remaining);Ok(())}fn overflow(&self)->std::io::Error{std::io::ErrorKind::OutOfMemory.into()}}
 #[test]fn admitted_edit_kernel_preserves_stable_same_offset_insertions_and_utf8_inverse(){let old="\u{3b1} original \u{3a9}";let edits=vec![Edit::insert(3,"one"),Edit::insert(3,"two"),Edit::replace(Span{start:3,end:11},"new")];let expected=apply_edits(old,edits.clone());let work=Quota{left:Cell::new(65536)};let actual=apply_edits_using(old,edits,Some(&work)).unwrap();assert_eq!(actual,expected);assert_eq!(actual.0,"\u{3b1} onetwonew \u{3a9}");assert_eq!(revert_edits_using(&actual.0,&actual.1,Some(&work)).unwrap(),old);}
 #[test]fn admitted_edit_kernel_rejects_before_returning_partial_output_when_capacity_is_unfunded(){let work=Quota{left:Cell::new(0)};let error=apply_edits_using("x",vec![Edit::insert(0,"new")],Some(&work)).unwrap_err();assert_eq!(error.kind(),std::io::ErrorKind::OutOfMemory);}
 #[test]fn invalid_inverse_geometry_is_an_operational_failure_not_an_unchecked_string_slice(){let work=Quota{left:Cell::new(1024)};let error=revert_edits_using("\u{3b1}",&[Inverse{start:1,len:0,text:"x".into()}],Some(&work)).unwrap_err();assert_eq!(error.kind(),std::io::ErrorKind::InvalidData);}
}
