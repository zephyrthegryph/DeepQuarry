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
    let files: Vec<&crate::tree::SourceFile> = tree.select(&crate::tree::CODE_DM).into_iter().filter(|f| types.iter().any(|t| f.code().text.contains(t.as_str()))).collect();
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
}

impl<'a> GenCx<'a> {
    pub fn new(tree: &'a Tree, root: &'a Path) -> GenCx<'a> {
        GenCx { tree, root, decls: Decls::get(tree) }
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
        super::sem_for(self.tree)
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
    g.generate(cx, &mut out);
    let mut text = format!(
        "// GENERATED by tools/analyze: `analyze gen {}`. Do not edit by hand; edit the declarations it reads.\n// Written to code/engine/_generated/{}; CI fails when this file is stale (`analyze gen --check`).\n\n",
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
    let cx = GenCx::new(tree, root);
    let dme = std::fs::read_to_string(root.join("deepquarry.dme")).unwrap_or_default();
    let mut out = Vec::new();
    for g in registry() {
        if !names.is_empty() && !names.iter().any(|n| n == g.name()) {
            continue;
        }
        let (text, diags) = render(g.as_ref(), &cx);
        let mut file_out = GenOut::default();
        let files = g.files(&cx, &mut file_out);
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
                println!("{}:1: [gen/{}] stale -- run `analyze gen {}` and commit the result", r.path.display(), r.name, r.name);
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

