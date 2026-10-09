//! The generator API: how the other engines write their generated DM.
//!
//! A generator is a query on the semantic layer whose answer is a DM file under
//! `code/engine/_generated/`. E1 (the table builder), E3 (stats), E4 (actions: `ACTION()` to
//! `/datum/act/x`, `act_x()` and the notice) and E6 write theirs the same way E5 writes `reads`
//! and `system_accessors`: one file in `src/gens/<name>.rs` (found by `build.rs`, no registry to
//! edit) that implements [`Generator`].
//!
//! ```text
//! analyze gen [NAME...]            write every (or the named) generated file
//! analyze gen --check [NAME...]    fail when a file is stale or not #included in deepquarry.dme
//! ```
//!
//! A generator asks a [`GenCx`] for what it needs and writes lines into a [`GenOut`]:
//!
//! * `cx.markers("STAT")`: the declaration markers of a family, with arguments split and lines kept;
//! * `cx.keys()`: the declared stat, source, stage, capability and op ids;
//! * `cx.sem()`: the full semantic model (type, proc and var resolution) when the generator needs
//!   structure; a generator that does not call it costs no parse;
//! * `cx.text_program()`: the cheap text scanner's type and var table;
//! * `cx.handlers()`: the procs declarations name as handlers, with their hook form and context;
//! * `out.diag(rel, line, msg)`: a finding in the engine's diagnostics format (`gen/<name>`), the
//!   same `file:line: [rule] message -- hint` the lints print; any diagnostic fails the run.
//!
//! Output is deterministic (sorted by the generator) and ends in a newline; `--check` compares
//! bytes, so a generator must never write a timestamp or an absolute path.

use std::path::{Path, PathBuf};
use std::sync::Arc;

use crate::frontend::Program;
use crate::tree::Tree;

use super::decls::{Decls, Marker};
use super::hooks::HandlerRef;
use super::keys::KeyIndex;
use super::SemHandle;

pub const OUT_DIR: &str = "code/engine/_generated";

/// The directories whose files .dme compiles only in a test build (`#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)`
/// in code/tests/_tests.dm and code/modules/unit_tests/_unit_tests.dm).
pub const TEST_ONLY_DIRS: &[&str] = &["code/tests/", "code/modules/unit_tests/"];

/// The guard a generator wraps test-only declarations in.
pub const TEST_GUARD: &str = "#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)";

/// Whether a source file is compiled only in a test build, so whatever a generator writes for it must sit inside [`TEST_GUARD`].
pub fn test_only(rel: &str) -> bool {
    TEST_ONLY_DIRS.iter().any(|d| rel.starts_with(d))
}

/// The type a top-level definition line names: `/datum/x` of `/datum/x`, `/datum/x/var/y = 1`, `/datum/x/proc/f()` or `/datum/x/f()`.
fn defined_type(line: &str) -> Option<&str> {
    if !line.starts_with('/') || line.starts_with("//") {
        return None;
    }
    let end = line.find(|c: char| !(c.is_ascii_alphanumeric() || c == '_' || c == '/')).unwrap_or(line.len());
    let mut path = line[..end].trim_end_matches('/');
    for kw in ["/var/", "/proc/", "/verb/"] {
        if let Some(i) = path.find(kw) {
            path = &path[..i];
        }
    }
    if line[end..].trim_start().starts_with('(') {
        path = path.rsplit_once('/').map(|(a, _)| a).unwrap_or(path);
    }
    (path.len() > 1).then_some(path)
}

/// The types only test-only files ([`test_only`]) define: a generated line that names one outside [`TEST_GUARD`] breaks the production build.
pub fn test_only_types(tree: &Tree) -> std::collections::BTreeSet<String> {
    let mut test = std::collections::BTreeSet::new();
    let mut prod = std::collections::HashSet::new();
    for f in tree.files.iter().filter(|f| f.rel.ends_with(".dm")) {
        if f.rel.starts_with(OUT_DIR) || f.rel.starts_with("code/_generated/") {
            continue;
        }
        let is_test = test_only(&f.rel);
        for line in f.text().lines() {
            if let Some(t) = defined_type(line) {
                if is_test {
                    test.insert(t.to_string());
                } else {
                    prod.insert(t.to_string());
                }
            }
        }
    }
    test.retain(|t| !prod.contains(t));
    test
}

/// The lines (1-based) of generated `text` that name a test-only type outside a [`TEST_GUARD`] block, with the type.
pub fn test_type_leaks(text: &str, test_types: &std::collections::BTreeSet<String>) -> Vec<(u32, String)> {
    let mut leaks = Vec::new();
    let mut guards: Vec<bool> = Vec::new();
    for (i, line) in text.lines().enumerate() {
        let t = line.trim();
        if t.starts_with("#if") {
            guards.push(t.contains("UNIT_TESTS"));
            continue;
        }
        if t.starts_with("#endif") {
            guards.pop();
            continue;
        }
        if t.starts_with("//") || guards.iter().any(|g| *g) {
            continue;
        }
        let b = line.as_bytes();
        let mut j = 0;
        let mut in_text = false;
        while j < b.len() {
            let word = |c: u8| c.is_ascii_alphanumeric() || c == b'_';
            // A text ("/obj/x::f", a reads-table key) names no type the compiler resolves.
            if b[j] == b'"' && (j == 0 || b[j - 1] != b'\\') {
                in_text = !in_text;
                j += 1;
                continue;
            }
            if in_text {
                j += 1;
                continue;
            }
            if b[j] == b'/' && (j == 0 || !(word(b[j - 1]) || b[j - 1] == b'/' || b[j - 1] == b'.')) {
                let mut k = j;
                while k < b.len() && (word(b[k]) || b[k] == b'/') {
                    k += 1;
                }
                let tok = &line[j..k];
                let mut p = tok.trim_end_matches('/');
                loop {
                    if test_types.contains(p) {
                        leaks.push((i as u32 + 1, p.to_string()));
                        break;
                    }
                    match p.rsplit_once('/') {
                        Some((a, _)) if !a.is_empty() => p = a,
                        _ => break,
                    }
                }
                j = k;
            } else {
                j += 1;
            }
        }
    }
    leaks
}

/// The placeholder path of a file-only generator that wrote nothing but has findings to report.
const UI_NO_FILE: &str = "tgui/packages/tgui/interfaces/generated";

/// The template `system_accessors` uses to name a system's singleton: `{system}` is the SYSTEM_ACCESSOR's first argument.
pub const SYSTEM_INSTANCE: &str = "GLOB.{system}_service";

/// The types a system name may live at (`/datum/world_service/<x>`, `/datum/system/<x>`).
pub fn system_types(system: &str) -> Vec<String> {
    vec![format!("/datum/world_service/{}", system), format!("/datum/system/{}", system)]
}

/// The vars a system declares: `(some candidate type exists, its vars)`. Reads only the files that name the
/// system's type, not the whole tree.
pub fn system_vars(tree: &Tree, system: &str) -> (bool, std::collections::HashSet<String>) {
    let types = system_types(system);
    // Which files mention `/datum/world_service/<system>` or `/datum/system/<system>` (as a substring of the
    // comment-stripped text, like `contains`): per-file facts, read once per content change.
    let mentions: Arc<Vec<(String, Vec<(u8, String)>)>> = tree.memo("sem/system_mentions", || {
        let all = tree.select(&crate::tree::CODE_DM);
        let facts: Vec<Vec<(u8, String)>> = crate::incr::facts("system-type-mentions", &all, |f| {
            let text = &f.code().text;
            let mut out: Vec<(u8, String)> = Vec::new();
            for (k, prefix) in ["/datum/world_service/", "/datum/system/"].iter().enumerate() {
                let mut from = 0;
                while let Some(i) = text[from..].find(prefix) {
                    let start = from + i + prefix.len();
                    let run: String = text[start..].chars().take_while(|c| c.is_alphanumeric() || *c == '_').collect();
                    out.push((k as u8, run));
                    from = start;
                }
            }
            out.sort();
            out.dedup();
            out
        });
        all.iter().zip(facts).map(|(f, m)| (f.rel.clone(), m)).collect()
    });
    let plain = !system.is_empty() && system.chars().all(|c| c.is_alphanumeric() || c == '_');
    let files: Vec<&crate::tree::SourceFile> = if plain {
        mentions.iter().filter(|(_, m)| m.iter().any(|(_, run)| run.starts_with(system))).filter_map(|(rel, _)| tree.get(rel)).collect()
    } else {
        tree.select(&crate::tree::CODE_DM).into_iter().filter(|f| types.iter().any(|t| f.code().text.contains(t.as_str()))).collect()
    };
    let table = crate::dm::dx::type_vars(&files);
    let mut vars = std::collections::HashSet::new();
    let mut known = false;
    for t in &types {
        if let Some(v) = table.get(t) {
            known = true;
            vars.extend(v.iter().cloned());
        } else if files.iter().any(|f| f.code().text.lines().any(|l| l.trim_end() == t.as_str())) {
            known = true;
        }
    }
    (known, vars)
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GenDiag {
    pub rel: String,
    pub line: u32,
    pub msg: String,
}

#[derive(Default)]
pub struct GenOut {
    body: String,
    pub diags: Vec<GenDiag>,
}

impl GenOut {
    pub fn line(&mut self, s: impl AsRef<str>) {
        self.body.push_str(s.as_ref());
        self.body.push('\n');
    }

    pub fn blank(&mut self) {
        self.body.push('\n');
    }

    /// A `///` doc line.
    pub fn doc(&mut self, s: impl AsRef<str>) {
        self.line(format!("/// {}", s.as_ref()));
    }

    pub fn diag(&mut self, rel: &str, line: u32, msg: impl Into<String>) {
        self.diags.push(GenDiag { rel: rel.to_string(), line, msg: msg.into() });
    }

    pub fn text(&self) -> &str {
        &self.body
    }
}

/// What a generator can ask for.
pub struct GenCx<'a> {
    pub tree: &'a Tree,
    pub root: &'a Path,
    decls: Arc<Decls>,
    /// The full model, once a generator asked for it (its output is then cached with the semantic record).
    used_sem: std::sync::Mutex<Option<SemHandle>>,
}

impl<'a> GenCx<'a> {
    pub fn new(tree: &'a Tree, root: &'a Path) -> GenCx<'a> {
        GenCx { tree, root, decls: Decls::get(tree), used_sem: std::sync::Mutex::new(None) }
    }

    pub fn decls(&self) -> &Decls {
        &self.decls
    }

    pub fn markers<'b>(&'b self, name: &'b str) -> impl Iterator<Item = &'b Marker> + 'b {
        self.decls.markers_named(name)
    }

    pub fn keys(&self) -> KeyIndex {
        KeyIndex::build(&self.decls)
    }

    pub fn sem(&self) -> Option<SemHandle> {
        let s = super::sem_for(self.tree);
        if let Some(h) = &s {
            *self.used_sem.lock().unwrap() = Some(h.clone());
        }
        s
    }

    pub fn text_program(&self) -> Arc<Program> {
        // The same memoized program `Cx::program(Text)` hands lints.
        self.tree.memo("program/text", || {
            use crate::frontend::{Frontend, TextFrontend};
            TextFrontend.analyze(&self.tree.root, self.tree).unwrap_or_default()
        })
    }

    pub fn handlers(&self) -> Vec<HandlerRef> {
        super::hooks::discover(&self.decls)
    }
}

pub trait Generator: Send + Sync {
    /// The name `analyze gen NAME` takes (and the `[gen/NAME]` tag on its diagnostics).
    fn name(&self) -> &'static str;
    /// The file written, relative to `code/engine/_generated/`; empty for a generator that writes only `files()`.
    fn output(&self) -> &'static str;
    fn generate(&self, cx: &GenCx, out: &mut GenOut);
    /// Files written outside `code/engine/_generated/` (TypeScript types): `(path relative to the repo root, text)`. They are compared byte
    /// for byte like the DM file and are not `#include`d, so the check does not look for them in `deepquarry.dme`. Findings go to `out`.
    fn files(&self, _cx: &GenCx, _out: &mut GenOut) -> Vec<(String, String)> {
        Vec::new()
    }
}

pub fn registry() -> Vec<Box<dyn Generator>> {
    let mut v: Vec<Box<dyn Generator>> = Vec::new();
    crate::gens::register(&mut v);
    v
}

/// The file text a generator produces, header included.
pub fn render(g: &dyn Generator, cx: &GenCx) -> (String, Vec<GenDiag>) {
    let mut out = GenOut::default();
    // A generator that needed the full model: reuse its stored output while the semantic record is valid.
    if let Some(c) = super::incremental::cached_gen(cx.tree, g.name()) {
        if std::env::var("DQ_ANALYZE_TRACE").is_ok() {
            eprintln!("analyze: gen {} served from the semantic record", g.name());
        }
        out.body = c.text;
        out.diags = c.diags.into_iter().map(|(rel, line, msg)| GenDiag { rel, line, msg }).collect();
    } else {
        g.generate(cx, &mut out);
        let used = cx.used_sem.lock().unwrap().take();
        if std::env::var("DQ_ANALYZE_TRACE").is_ok() {
            eprintln!("analyze: gen {} generated (full model used: {})", g.name(), used.is_some());
        }
        if let Some(sem) = used {
            super::incremental::capture(cx.tree, &sem, sem.footprint());
            super::incremental::store_gen(
                cx.tree,
                g.name(),
                super::incremental::GenCache { text: out.body.clone(), diags: out.diags.iter().map(|d| (d.rel.clone(), d.line, d.msg.clone())).collect() },
            );
        }
    }
    let mut text = format!(
        "// GENERATED by tools/analyze: `analyze gen {}`. Do not edit by hand; edit the declarations it reads.\n// Written to code/engine/_generated/{}; not committed: every build regenerates it (`analyze gen`).\n\n",
        g.name(),
        g.output()
    );
    text.push_str(out.text());
    if !text.ends_with('\n') {
        text.push('\n');
    }
    (text, out.diags)
}

#[derive(Debug, PartialEq, Eq)]
pub enum State {
    Written,
    Fresh,
    Stale,
    NotIncluded,
}

pub struct GenResult {
    pub name: &'static str,
    pub path: PathBuf,
    pub state: State,
    pub diags: Vec<GenDiag>,
}

fn norm(s: &str) -> String {
    s.replace("\r\n", "\n")
}

/// Runs the named generators (all when empty). With `check`, nothing is written.
pub fn run(root: &Path, tree: &Tree, names: &[String], check: bool) -> Vec<GenResult> {
    let trace = std::env::var("DQ_ANALYZE_TRACE").is_ok();
    let began = std::time::Instant::now();
    let cx = GenCx::new(tree, root);
    let dme = std::fs::read_to_string(root.join("deepquarry.dme")).unwrap_or_default();
    let mut out = Vec::new();
    let test_types = test_only_types(tree);
    if trace {
        eprintln!("analyze: gen test-only types {} ms (cumulative {} ms)", began.elapsed().as_millis(), began.elapsed().as_millis());
    }
    for g in registry() {
        if !names.is_empty() && !names.iter().any(|n| n == g.name()) {
            continue;
        }
        let step = std::time::Instant::now();
        let (text, diags) = render(g.as_ref(), &cx);
        let rendered = step.elapsed().as_millis();
        let mut file_out = GenOut::default();
        let files = g.files(&cx, &mut file_out);
        if trace {
            eprintln!("analyze: gen {}: render {} ms, files() {} ms (cumulative {} ms)", g.name(), rendered, step.elapsed().as_millis() - rendered, began.elapsed().as_millis());
        }
        let mut diags = diags;
        diags.extend(file_out.diags);
        for (rel, file_text) in files {
            let file_path = root.join(&rel);
            let current = std::fs::read_to_string(&file_path).map(|t| norm(&t));
            let fresh = current.as_ref().map(|c| c == &file_text).unwrap_or(false);
            let mut state = if fresh { State::Fresh } else { State::Stale };
            if !check && !fresh {
                if let Some(dir) = file_path.parent() {
                    let _ = std::fs::create_dir_all(dir);
                }
                if std::fs::write(&file_path, &file_text).is_ok() {
                    state = State::Written;
                }
            }
            out.push(GenResult { name: g.name(), path: file_path, state, diags: Vec::new() });
        }
        if g.output().is_empty() {
            if let Some(first) = out.iter_mut().rev().find(|r| r.name == g.name()) {
                first.diags = diags;
            } else if !diags.is_empty() {
                out.push(GenResult { name: g.name(), path: root.join(UI_NO_FILE), state: State::Fresh, diags });
            }
            continue;
        }
        let path = root.join(OUT_DIR).join(g.output());
        let current = std::fs::read_to_string(&path).map(|t| norm(&t));
        let fresh = current.as_ref().map(|c| c == &text).unwrap_or(false);
        let mut state = if fresh { State::Fresh } else { State::Stale };
        if !check && !fresh {
            if let Some(dir) = path.parent() {
                let _ = std::fs::create_dir_all(dir);
            }
            if std::fs::write(&path, &text).is_ok() {
                state = State::Written;
            }
        }
        // The file only counts when the build compiles it.
        let include = format!("{}\\{}", OUT_DIR.replace('/', "\\"), g.output());
        if dme.contains("#include") && !dme.replace('/', "\\").contains(&include) && matches!(state, State::Fresh | State::Written) {
            state = State::NotIncluded;
        }
        // A test-only type outside the guard compiles in a test build and breaks the production one (`build.sh dm`).
        let rel = format!("{}/{}", OUT_DIR, g.output());
        let mut diags = diags;
        for (line, ty) in test_type_leaks(&text, &test_types) {
            diags.push(GenDiag { rel: rel.clone(), line, msg: format!("{} is defined only in test-only files; emit it inside `{}` (see sem::gen::test_only)", ty, TEST_GUARD) });
        }
        out.push(GenResult { name: g.name(), path, state, diags });
    }
    out
}

/// Prints results; returns whether everything is clean.
pub fn report(results: &[GenResult]) -> bool {
    let mut ok = true;
    for r in results {
        for d in &r.diags {
            println!("{}:{}: [gen/{}] {}", d.rel, d.line, r.name, d.msg);
            ok = false;
        }
        match r.state {
            State::Written => println!("wrote {}", r.path.display()),
            State::Fresh => println!("fresh {}", r.path.display()),
            State::Stale => {
                println!("{}:1: [gen/{}] stale -- run `analyze gen {}` (every build.sh target that compiles DM does; the file is not committed)", r.path.display(), r.name, r.name);
                ok = false;
            }
            State::NotIncluded => {
                println!("deepquarry.dme:1: [gen/{}] {} is generated but not #included -- add it to deepquarry.dme", r.name, r.path.display());
                ok = false;
            }
        }
    }
    ok
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unit_test_files_are_test_only() {
        assert!(test_only("code/tests/engine/fixtures.dm"));
        assert!(test_only("code/modules/unit_tests/clothing_tests.dm"));
        assert!(!test_only("code/game/objects/items.dm"));
    }

    #[test]
    fn a_test_only_type_outside_the_guard_is_a_leak() {
        let tree = Tree::from_files(vec![
            crate::tree::SourceFile::from_text("code/modules/unit_tests/a.dm", "/datum/probe\n\tvar/x\n/datum/probe/proc/f()\n/obj/shared\n"),
            crate::tree::SourceFile::from_text("code/game/b.dm", "/obj/shared\n"),
        ]);
        let types = test_only_types(&tree);
        assert!(types.contains("/datum/probe") && !types.contains("/obj/shared"), "{:?}", types);
        let text = "/datum/probe/declared_entries(list/into)\n\tinto += \"/datum/probe::f\"\n/obj/shared/x()\n#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)\n/datum/probe/declared_entries()\n#endif\n";
        assert_eq!(test_type_leaks(text, &types), vec![(1, "/datum/probe".to_string())]);
    }
}
