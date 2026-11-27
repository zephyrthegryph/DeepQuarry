//! The parse-aware layer, behind a trait so it can be replaced.
//!
//! Rules that need real structure (a type tree, the vars and procs a type declares, where they
//! are) ask a [`Frontend`] for a [`Program`] instead of scanning text. Two implementations:
//!
//! * [`TextFrontend`]: the engine's own line scanner (`dm::dx`), the same approximation the old
//!   Python lints used. Instant, runs on the already-loaded tree, and what the ported lints that
//!   need structure use today so their findings stay identical.
//! * [`ModelFrontend`]: the compiler's front end (the semantic model's, `crate::model`) over
//!   `deepquarry.dme`. Exact (preprocessor, macros, `parent_type`), but a whole-program front end,
//!   so it is opt-in (`analyze frontend-diff`, or a rule that asks for it).
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
    /// The compiler's front end over `deepquarry.dme` (the semantic model's): exact, a whole-program front end.
    Model,
}

impl crate::lint::Cx<'_> {
    /// The program model from a frontend, built once per run and shared by every rule that asks.
    /// A frontend failure yields an empty program whose `diagnostics` say why (a rule should treat
    /// that as "no information", not as a finding).
    pub fn program(&self, kind: FrontendKind) -> std::sync::Arc<Program> {
        let (key, fe): (&str, Box<dyn Frontend>) = match kind {
            FrontendKind::Text => ("program/text", Box::new(TextFrontend)),
            FrontendKind::Model => ("program/model", Box::new(ModelFrontend)),
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
        let table = crate::dm::dx::type_vars_in(tree, &files);
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

// ---- compiler frontend ---------------------------------------------------------------------------

/// The compiler's front end over `deepquarry.dme` (`crate::model`, the semantic model's): exact (preprocessor, macros, `parent_type`), a
/// whole-program front end.
#[derive(Default)]
pub struct ModelFrontend;

impl Frontend for ModelFrontend {
    fn name(&self) -> &'static str {
        "compiler"
    }

    fn analyze(&self, _root: &Path, tree: &Tree) -> Result<Program, String> {
        let sem = crate::sem::sem_for(tree).ok_or("the semantic model is unavailable")?;
        let mut program = Program { frontend: "compiler", ..Default::default() };
        for ty in sem.m().types() {
            let path = ty.path().to_string();
            let mut info = TypeInfo { path: path.clone(), ..Default::default() };
            for m in ty.vars().filter(|m| m.declares()) {
                let Some((file, line)) = m.site().and_then(|s| sem.m().line(s)) else { continue };
                let bits = m.flags();
                info.vars.push(VarInfo {
                    name: m.name().to_string(),
                    declared: m.declared_type(),
                    is_static: bits & (1 | 8) != 0,
                    is_const: bits & 2 != 0,
                    is_tmp: bits & 4 != 0,
                    file,
                    line,
                });
            }
            for m in ty.procs() {
                let Some((file, line)) = m.site().and_then(|s| sem.m().line(s)) else { continue };
                info.procs.push(ProcInfo {
                    name: m.name().to_string(),
                    is_verb: m.kind() == dm_tree::MemberKind::Verb,
                    params: m.parameters().iter().map(|q| q.name.clone()).collect(),
                    file,
                    line,
                });
            }
            if !info.vars.is_empty() || !info.procs.is_empty() {
                program.types.insert(path, info);
            }
        }
        Ok(program)
    }
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
}
