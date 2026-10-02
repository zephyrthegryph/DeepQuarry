//! The parse-aware layer, behind a trait so it can be replaced.
//!
//! Rules that need real structure (a type tree, the vars and procs a type declares, where they
//! are) ask a [`Frontend`] for a [`Program`] instead of scanning text. Two implementations:
//!
//! * [`TextFrontend`]: the engine's own line scanner (`dm::dx`), the same approximation the old
//!   Python lints used. Instant, runs on the already-loaded tree, and what the ported lints that
//!   need structure use today so their findings stay identical.
//! * [`DreamMakerFrontend`]: the SpacemanDMM `dreammaker` crate (the parser DreamChecker uses),
//!   run over `deepquarry.dme`. Exact (preprocessor, macros, `parent_type`), but a whole-program
//!   parse, so it is opt-in (`analyze frontend-diff`, or a rule that asks for it).
//!
//! A future incremental compiler/analysis API plugs in by implementing [`Frontend`]; no rule
//! changes. `analyze frontend-diff` compares two frontends on the same tree, which is how the
//! text scanner's blind spots are found.

use std::collections::BTreeMap;
use std::path::Path;

use crate::tree::Tree;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct VarInfo {
    pub name: String,
    /// Declared type path (`/obj/item`), "" when untyped.
    pub declared: String,
    pub is_static: bool,
    pub is_const: bool,
    pub is_tmp: bool,
    pub file: String,
    pub line: u32,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ProcInfo {
    pub name: String,
    pub is_verb: bool,
    pub params: Vec<String>,
    pub file: String,
    pub line: u32,
}

#[derive(Clone, Debug, Default)]
pub struct TypeInfo {
    pub path: String,
    pub vars: Vec<VarInfo>,
    pub procs: Vec<ProcInfo>,
}

/// What a frontend knows about the program.
#[derive(Clone, Debug, Default)]
pub struct Program {
    pub frontend: &'static str,
    pub types: BTreeMap<String, TypeInfo>,
    /// Diagnostics the frontend itself raised (parse errors).
    pub diagnostics: Vec<String>,
}

impl Program {
    pub fn var(&self, ty: &str, name: &str) -> Option<&VarInfo> {
        self.types.get(ty)?.vars.iter().find(|v| v.name == name)
    }

    pub fn proc(&self, ty: &str, name: &str) -> Option<&ProcInfo> {
        self.types.get(ty)?.procs.iter().find(|p| p.name == name)
    }

    pub fn proc_count(&self) -> usize {
        self.types.values().map(|t| t.procs.len()).sum()
    }

    pub fn var_count(&self) -> usize {
        self.types.values().map(|t| t.vars.len()).sum()
    }
}

pub trait Frontend: Send + Sync {
    fn name(&self) -> &'static str;
    /// Builds the program model. `tree` is the engine's loaded tree (frontends that read files
    /// themselves may ignore it); `root` the repo root.
    fn analyze(&self, root: &Path, tree: &Tree) -> Result<Program, String>;
}

/// Which frontend a parse-aware rule asks for.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FrontendKind {
    /// The engine's own line scanner: instant, approximate (what the ported lints use).
    Text,
    /// The SpacemanDMM parser over `deepquarry.dme`: exact, a whole-program parse (a few seconds).
    DreamMaker,
}

impl crate::lint::Cx<'_> {
    /// The program model from a frontend, built once per run and shared by every rule that asks.
    /// A frontend failure yields an empty program whose `diagnostics` say why (a rule should treat
    /// that as "no information", not as a finding).
    pub fn program(&self, kind: FrontendKind) -> std::sync::Arc<Program> {
        let (key, fe): (&str, Box<dyn Frontend>) = match kind {
            FrontendKind::Text => ("program/text", Box::new(TextFrontend)),
            FrontendKind::DreamMaker => ("program/dreammaker", Box::new(DreamMakerFrontend::default())),
        };
        self.tree.memo(key, || {
            fe.analyze(&self.tree.root, self.tree).unwrap_or_else(|e| Program {
                frontend: fe.name(),
                diagnostics: vec![e],
                ..Default::default()
            })
        })
    }
}

// ---- text frontend -----------------------------------------------------------------------------

pub struct TextFrontend;

impl Frontend for TextFrontend {
    fn name(&self) -> &'static str {
        "text"
    }

    fn analyze(&self, _root: &Path, tree: &Tree) -> Result<Program, String> {
        let files: Vec<&crate::tree::SourceFile> = tree.select(&crate::tree::CODE_DM);
        let mut program = Program { frontend: "text", ..Default::default() };
        let table = crate::dm::dx::type_vars(&files);
        for (path, vars) in table {
            let t = program.types.entry(path.clone()).or_insert_with(|| TypeInfo { path, ..Default::default() });
            let mut names: Vec<&String> = vars.iter().collect();
            names.sort();
            for v in names {
                t.vars.push(VarInfo { name: v.clone(), ..Default::default() });
            }
        }
        for f in &files {
            for p in crate::dm::dx::procs_in(f) {
                let t = program.types.entry(p.path.clone()).or_insert_with(|| TypeInfo { path: p.path.clone(), ..Default::default() });
                t.procs.push(ProcInfo { name: p.name, is_verb: false, params: p.params, file: p.rel, line: p.line as u32 });
            }
        }
        Ok(program)
    }
}

// ---- dreammaker frontend -----------------------------------------------------------------------

pub struct DreamMakerFrontend {
    /// The environment file, relative to the repo root.
    pub dme: String,
}

impl Default for DreamMakerFrontend {
    fn default() -> Self {
        DreamMakerFrontend { dme: "deepquarry.dme".to_string() }
    }
}

impl Frontend for DreamMakerFrontend {
    fn name(&self) -> &'static str {
        "dreammaker"
    }

    fn analyze(&self, root: &Path, _tree: &Tree) -> Result<Program, String> {
        use dreammaker::ast::VarTypeFlags;
        let ctx = dreammaker::Context::default();
        let dme = root.join(&self.dme);
        let objtree = ctx.parse_environment(&dme).map_err(|e| format!("{}: {}", dme.display(), e))?;
        let rel = |loc: dreammaker::Location| -> String {
            let p = ctx.file_path(loc.file).to_path_buf();
            crate::util::rel_slash(&p, root)
        };
        let mut program = Program { frontend: "dreammaker", ..Default::default() };
        for ty in objtree.iter_types() {
            let t = ty.get();
            let path = if t.path.is_empty() { "/".to_string() } else { t.path.clone() };
            let mut info = TypeInfo { path: path.clone(), ..Default::default() };
            for (name, v) in &t.vars {
                let Some(decl) = &v.declaration else { continue };
                let flags = decl.var_type.flags;
                let declared = decl.var_type.type_path.iter().map(|s| s.as_str()).collect::<Vec<_>>();
                info.vars.push(VarInfo {
                    name: name.clone(),
                    declared: if declared.is_empty() { String::new() } else { format!("/{}", declared.join("/")) },
                    is_static: flags.contains(VarTypeFlags::STATIC),
                    is_const: flags.contains(VarTypeFlags::CONST),
                    is_tmp: flags.contains(VarTypeFlags::TMP),
                    file: rel(decl.location),
                    line: decl.location.line,
                });
            }
            for (name, p) in &t.procs {
                let Some(value) = p.value.first() else { continue };
                info.procs.push(ProcInfo {
                    name: name.clone(),
                    is_verb: p.declaration.as_ref().map(|d| matches!(d.kind, dreammaker::ast::ProcDeclKind::Verb)).unwrap_or(false),
                    params: value.parameters.iter().map(|p| p.name.clone()).collect(),
                    file: rel(value.location),
                    line: value.location.line,
                });
            }
            if !info.vars.is_empty() || !info.procs.is_empty() {
                program.types.insert(path, info);
            }
        }
        for e in ctx.errors().iter() {
            if matches!(e.severity(), dreammaker::Severity::Error) {
                program.diagnostics.push(format!("{}", e));
            }
        }
        Ok(program)
    }
}

/// `analyze frontend-diff`: type/var/proc names the two programs disagree on (a text-scanner blind
/// spot, or a DreamMaker parse gap). Returns human-readable lines.
pub fn diff(a: &Program, b: &Program, limit: usize) -> Vec<String> {
    let mut out = Vec::new();
    let mut push = |s: String| {
        if out.len() < limit {
            out.push(s);
        }
    };
    for (path, ta) in &a.types {
        let Some(tb) = b.types.get(path) else {
            push(format!("type {} only in {}", path, a.frontend));
            continue;
        };
        for p in &ta.procs {
            if !tb.procs.iter().any(|q| q.name == p.name) {
                push(format!("proc {}/{} only in {} ({}:{})", path, p.name, a.frontend, p.file, p.line));
            }
        }
        for p in &tb.procs {
            if p.file == "(builtins)" {
                continue;
            }
            if !ta.procs.iter().any(|q| q.name == p.name) {
                push(format!("proc {}/{} only in {} ({}:{})", path, p.name, b.frontend, p.file, p.line));
            }
        }
    }
    for (path, tb) in &b.types {
        let builtin_only = tb.procs.iter().all(|p| p.file == "(builtins)") && tb.vars.iter().all(|v| v.file == "(builtins)");
        if !a.types.contains_key(path) && !builtin_only {
            push(format!("type {} only in {}", path, b.frontend));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tree::SourceFile;

    #[test]
    fn text_frontend_lists_procs_and_vars() {
        let tree = Tree::from_files(vec![SourceFile::from_text(
            "code/a.dm",
            "/obj/thing\n\tvar/a = 1\n/obj/thing/proc/poke(mob/user)\n\treturn\n",
        )]);
        let p = TextFrontend.analyze(Path::new("."), &tree).unwrap();
        assert!(p.var("/obj/thing", "a").is_some());
        assert_eq!(p.proc("/obj/thing", "poke").unwrap().params, vec!["user"]);
    }

    #[test]
    fn a_parse_aware_rule_asks_the_context_for_a_program() {
        use crate::lint::{Cx, Meta, Policy, RuleMeta, ScanKind};
        static META: Meta = Meta {
            name: "probe",
            group: "",
            label: "probe",
            legacy: "",
            select: crate::tree::CODE_DM,
            scan: ScanKind::Tree,
            policy: Policy::Hard,
            rules: &[RuleMeta { name: "r", hint: "" }],
            allow: &[],
            lists: &[],
        };
        let tree = Tree::from_files(vec![SourceFile::from_text("code/a.dm", "/obj/thing/proc/poke()\n\treturn\n")]);
        let scope = crate::scopes::LintScope::default();
        let cx = Cx { tree: &tree, meta: &META, scope: &scope };
        let p = cx.program(FrontendKind::Text);
        assert!(p.proc("/obj/thing", "poke").is_some());
        // memoized: the second call is the same allocation
        assert!(std::sync::Arc::ptr_eq(&p, &cx.program(FrontendKind::Text)));
    }

    #[test]
    fn dreammaker_frontend_parses_a_small_environment() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("t.dme"), "#include \"a.dm\"\n").unwrap();
        std::fs::write(
            dir.path().join("a.dm"),
            "/obj/thing\n\tvar/a = 1\n\tvar/tmp/b = 2\n/obj/thing/proc/poke(mob/user)\n\treturn\n",
        )
        .unwrap();
        let fe = DreamMakerFrontend { dme: "t.dme".to_string() };
        let tree = Tree::from_files(vec![]);
        let p = fe.analyze(dir.path(), &tree).unwrap();
        let a = p.var("/obj/thing", "a").expect("var a");
        assert_eq!(a.line, 2);
        assert!(p.var("/obj/thing", "b").unwrap().is_tmp);
        assert_eq!(p.proc("/obj/thing", "poke").unwrap().params, vec!["user"]);
    }
}
