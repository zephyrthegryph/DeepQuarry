//! Engine dependency provenance. Unlike reads analysis, this walks effects and all calls too.
use std::collections::{BTreeMap, BTreeSet};
use std::sync::OnceLock;
use dm_syntax::{Expr, Statement};
use super::Sem;
use crate::model::expr::{Chain, Form, Hop, Root};
use crate::model::walk::{stmt_blocks, stmt_exprs, stmts, walk_block, walk_expr, ForInit, Stmt};

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct Finding { pub rule: &'static str, pub file: String, pub line: u32, pub message: String }

/// code/host/ is the neutral layer the engine calls: held to the engine's own boundary, so it names nothing external.
fn host(file: &str) -> bool { file.starts_with("code/host/") }
fn engine(file: &str) -> bool { file.starts_with("code/engine/") || host(file) }
fn generated(file: &str) -> bool { file.starts_with("code/engine/_generated/") }
/// The layer a scanned file sits in: what it may not name (`external`) and what authorizes a shared type or virtual proc (`lawful`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Layer {
    /// code/engine/ and code/host/: names nothing in library, content or the old trees.
    Engine,
    /// code/library/: names nothing in content or the old trees. The engine, library itself and code/domains/world_model/ (the base
    /// type declarations) all authorize a shared type.
    Library,
}
impl Layer {
    fn external(self, file: &str) -> bool {
        let roots: &[&str] = match self {
            Layer::Engine => &["code/library/", "code/content/", "code/game/", "code/modules/", "code/datums/"],
            Layer::Library => &["code/content/", "code/game/", "code/modules/", "code/datums/"],
        };
        roots.iter().any(|root| file.starts_with(root))
    }
    fn lawful(self, file: &str) -> bool {
        match self {
            Layer::Engine => engine(file),
            Layer::Library => engine(file) || file.starts_with("code/library/") || file.starts_with("code/domains/world_model/"),
        }
    }
}
// The exact intrinsic types are the ones BYOND's builtin table (`model::builtins`) puts a var or proc on: reopening a
// builtin changes its source location, but does not make its type downstream-only. The root is not a type a path names.
fn builtin_type(path: &str) -> bool {
    static TYPES: OnceLock<BTreeSet<String>> = OnceLock::new();
    TYPES.get_or_init(|| {
        let table = crate::model::builtins::get();
        table.vars.keys().chain(table.procs.keys()).filter(|p| p.as_str() != "/").cloned().collect()
    }).contains(path)
}
/// A declared type path (`/obj/item`), none when untyped.
fn type_path(declared: String) -> Option<String> {
    (!declared.is_empty()).then_some(declared)
}

struct Walker<'a> { sem: &'a Sem, file: String, owner: String, line: u32, locals: BTreeMap<String, String>, found: BTreeSet<Finding>, layer: Layer }
impl Walker<'_> {
    fn put(&mut self, rule: &'static str, message: String) {
        self.found.insert(Finding { rule, file: self.file.clone(), line: self.line, message });
    }
    fn provenance(&mut self, symbol: &str, file: &str) {
        if self.layer.external(file) {
            self.put("external_dependency", format!("{} is defined in {}", symbol, file));
        }
    }
    fn ty(&mut self, path: &str) {
        // list/element/type is a collection annotation, not a declared /list subtype.
        let path = path.strip_prefix("/list/").map(|p| format!("/{}", p)).unwrap_or_else(|| path.to_string());
        if builtin_type(&path) { return; }
        let definitions = self.sem.layering_type_defs.get(&path);
        let genuine_headers: Vec<_> = definitions.into_iter().flatten().filter(|file| !generated(file)).collect();
        // A generated reopening cannot authorize a downstream type. Where no
        // genuine bare header exists, actual member definitions establish the
        // implicit type; typed references never enter this fallback index.
        let files: Vec<_> = if genuine_headers.is_empty() {
            self.sem.layering_owner_defs.get(&path).into_iter().flatten().filter(|file| !generated(file)).collect()
        } else { genuine_headers };
        // A neutral reopening (for example in code/library/helpers) is not engine
        // ownership and cannot authorize an application-defined type. Only a
        // genuine, non-generated engine declaration establishes that boundary.
        if !files.iter().any(|file| self.layer.lawful(file)) {
            // One finding per type at a site, not one per file that reopens it: adding another file that declares the type
            // would otherwise multiply every site that names it and fail every baselined site (the baseline fingerprint
            // ignores the message), on the full run and `--changed-only` alike.
            if let Some(file) = files.into_iter().filter(|f| self.layer.external(f)).min() { self.provenance(&path, file); }
        }
    }
    // A virtual interface declared in the engine is lawful even if a descendant overrides it downstream.
    fn method(&mut self, owner: &str, name: &str) {
        if owner == "/" || owner.is_empty() { self.global(name); return; }
        let Some(p) = self.sem.proc_ref(owner, name) else { return; };
        if p.is_builtin() { return; }
        let mut ancestor = Some(owner.to_string());
        while let Some(t) = ancestor {
            if let Some(ty) = self.sem.ty(&t) {
                if ty.proc_definitions(name).iter().any(|v| {
                    let f = self.sem.rel(v.site());
                    self.layer.lawful(&f) && !generated(&f)
                }) { return; }
            }
            ancestor = self.sem.parent_of(&t);
        }
        let body = self.sem.proc_body(p);
        self.provenance(&format!("{}::{}", owner, name), &body.file);
    }
    fn global(&mut self, name: &str) {
        if let Some(p) = self.sem.global_proc(name) {
            if !p.is_builtin() {
                let body = self.sem.proc_body(p);
                self.provenance(&format!("/proc/{}", name), &body.file);
            }
        }
    }
    fn expr(&mut self, e: &Expr) {
        walk_expr(e, &mut |v| if let Form::Chain(c) = &v.form { self.expr_one(c) });
    }
    /// A `var/L[3]` with no value starts as `new /list(3)`: its sizes are expressions of the statement.
    fn sizes(&mut self, d: &crate::model::walk::VarDecl<'_>) {
        if d.value.is_none() {
            for e in &d.suffix_args { self.expr(e); }
        }
    }
    fn expr_one(&mut self, c: &Chain<'_>) {
        let mut receiver = match &c.root {
            Root::Ident("src") => Some(self.owner.clone()),
            Root::Ident(n) => {
                if let Some(local) = self.locals.get(*n) { Some(local.clone()) }
                else if let Some(v) = self.sem.var_decl(&self.owner, n) {
                    if !v.declared.is_empty() { self.ty(&v.declared); }
                    Some(v.declared)
                } else { None }
            },
            Root::Call { name: n, .. } => {
                if self.sem.proc_ref(&self.owner, n).is_some() { let owner = self.owner.clone(); self.method(&owner, n); }
                else { self.global(n); }
                None
            }
            Root::ParentCall(_) => {
                // Parent-call target is checked by the proc walk, using its current method name.
                None
            }
            Root::Prefab { path, .. } => {
                // The path's names, whatever operator joins them.
                let path = path.split(['/', '.', ':']).filter(|n| !n.is_empty()).map(|n| format!("/{}", n)).collect::<String>();
                self.ty(&path); Some(path)
            }
            Root::DynamicCall { .. } => None, // Dynamic callbacks have no statically provable target; not a blanket dynamic-call ban.
            _ => None,
        };
        for f in &c.hops {
            match f {
                Hop::Field { name, .. } => {
                    if let Some(ty) = &receiver {
                        if let Some(v) = self.sem.var_decl(ty, name) {
                            if !v.declared.is_empty() { self.ty(&v.declared); }
                            receiver = Some(v.declared);
                        } else { receiver = None; }
                    }
                }
                Hop::Call { name, .. } => {
                    if let Some(ty) = receiver.as_ref().filter(|t| !t.is_empty()).cloned() { self.method(&ty, name); }
                    // Untyped dynamic receivers are outside this provenance check, not automatically unlawful.
                    receiver = None;
                }
                Hop::ProcRef { name, .. } => {
                    if let Some(ty) = receiver.as_ref().filter(|t| !t.is_empty()).cloned() { self.method(&ty, name); }
                    else if matches!(&c.root, Root::Ident("src")) { let owner = self.owner.clone(); self.method(&owner, name); }
                }
                Hop::Index { .. } => { receiver = None; }
                _ => {}
            }
        }
    }
    fn block(&mut self, block: &[Statement]) {
        for st in stmts(block) {
            self.line = self.sem.line(Some(st.site));
            match &st.stmt {
                Stmt::Vars(vars) => for v in vars {
                    if let Some(t) = type_path(v.declared()) { self.ty(&t); self.locals.insert(v.name.to_string(), t); }
                },
                Stmt::ForList { binding, .. } => {
                    if let Some(t) = binding.decl.as_ref().and_then(|d| type_path(d.declared())) { self.ty(&t); self.locals.insert(binding.name.to_string(), t); }
                }
                Stmt::ForKeyValue { binding, .. } => {
                    if let Some(t) = binding.decl.as_ref().and_then(|d| type_path(d.declared())) { self.ty(&t); self.locals.insert(binding.name.to_string(), t); }
                }
                Stmt::ForLoop { init, inc, .. } => {
                    match init {
                        Some(ForInit::Var(v)) => {
                            if let Some(t) = type_path(v.declared()) { self.ty(&t); self.locals.insert(v.name.to_string(), t); }
                            if let Some(e) = v.value { self.expr(e); }
                            self.sizes(v);
                        }
                        Some(ForInit::Expr(e)) => self.expr(e),
                        None => {}
                    }
                    if let Some(e) = inc { self.expr(e); }
                }
                _ => {}
            }
            for e in stmt_exprs(&st.stmt) { self.expr(e); }
            // An assignment statement has no node of its own: its two sides are the expressions.
            if let Stmt::Expr(Form::Assign { lhs, rhs, .. }, None) = &st.stmt { self.expr(lhs); self.expr(rhs); }
            if let Stmt::Vars(vars) = &st.stmt { for v in vars { self.sizes(v); } }
            for b in stmt_blocks(&st.stmt) { self.block(b); }
        }
    }
}

pub fn scan(sem: &Sem, included: &BTreeSet<String>) -> Vec<Finding> {
    scan_in(sem, included, Layer::Engine)
}

pub fn scan_in(sem: &Sem, included: &BTreeSet<String>, layer: Layer) -> Vec<Finding> {
    let mut all = BTreeSet::new();
    for ty in sem.m().types() {
        let owner = ty.path().to_string();
        for name in ty.proc_names() {
            for v in ty.proc_definitions(name) {
                let file = sem.rel(v.site());
                if !included.contains(&file) { continue; }
                let mut w = Walker { sem, file, owner: owner.clone(), line: sem.line(v.site()), locals: BTreeMap::new(), found: BTreeSet::new(), layer };
                w.ty(&owner);
                for p in v.parameters().iter() {
                    if let Some(t) = type_path(p.declared()) { w.ty(&t); w.locals.insert(p.name.clone(), t); }
                }
                if let Some(code) = v.body() {
                    // ..() is a dependency on the nearest parent implementation, not on the overriding body.
                    let mut parent_call = false;
                    walk_block(code, &mut |e, _| if let Form::Chain(c) = &e.form { if matches!(c.root, Root::ParentCall(_)) { parent_call = true; } });
                    if parent_call { if let Some(parent) = sem.parent_of(&owner) { w.method(&parent, name); } }
                    w.block(code);
                }
                all.extend(w.found);
            }
        }
        for name in ty.var_names() {
            if !ty.declares_var(&name) { continue; }
            if let Some(d) = ty.var_declaration(&name) {
                let file = sem.rel(d.site);
                if !included.contains(&file) { continue; }
                let mut w = Walker { sem, file, owner: owner.clone(), line: sem.line(d.site), locals: BTreeMap::new(), found: BTreeSet::new(), layer };
                if let Some(t) = type_path(d.declared.clone()) { w.ty(&t); }
                all.extend(w.found);
            }
        }
    }
    all.into_iter().collect()
}

/// Source-only markers and explicit type/proc paths lost during macro expansion are resolved against the same model.
pub fn source_paths(sem: &Sem, file: &str, line: u32, text: &str) -> Vec<Finding> {
    source_paths_in(sem, file, line, text, Layer::Engine)
}
pub fn source_paths_in(sem: &Sem, file: &str, line: u32, text: &str, layer: Layer) -> Vec<Finding> {
    if !text.contains('/') { return Vec::new(); }
    let mut w = Walker { sem, file: file.to_string(), owner: "/".to_string(), line, locals: BTreeMap::new(), found: BTreeSet::new(), layer };
    static RE_PATTERN: OnceLock<regex::Regex> = OnceLock::new();
    let re = RE_PATTERN.get_or_init(|| regex::Regex::new(r"(?:^|[^\w])(/(?:[A-Za-z_]\w*/)*[A-Za-z_]\w*)").unwrap());
    for cap in re.captures_iter(text) {
        let mut path = cap[1].to_string();
        if let Some((owner, name)) = path.rsplit_once("/proc/") {
            if owner.is_empty() { w.global(name); } else { w.ty(owner); w.method(owner, name); }
            continue;
        }
        while sem.ty(&path).is_none() {
            let Some(pos) = path.rfind('/') else { break; };
            if pos == 0 { break; }
            path.truncate(pos);
        }
        w.ty(&path);
    }
    w.found.into_iter().collect()
}


/// Generator entries are erased before parsing. Resolve their direct helper names without guessing name prefixes.
pub fn marker_calls(sem: &Sem, file: &str, line: u32, text: &str) -> Vec<Finding> {
    marker_calls_in(sem, file, line, text, Layer::Engine)
}
pub fn marker_calls_in(sem: &Sem, file: &str, line: u32, text: &str, layer: Layer) -> Vec<Finding> {
    if !text.contains('(') { return Vec::new(); }
    let mut w = Walker { sem, file: file.to_string(), owner: "/".to_string(), line, locals: BTreeMap::new(), found: BTreeSet::new(), layer };
    static RE_PATTERN: OnceLock<regex::Regex> = OnceLock::new();
    let re = RE_PATTERN.get_or_init(|| regex::Regex::new(r"\b([A-Za-z_]\w*)\s*\(").unwrap());
    for cap in re.captures_iter(text) {
        let token = cap.get(1).unwrap();
        if text[..token.start()].chars().next_back().is_some_and(|c| c == '.' || c == '/') { continue; }
        let name = &cap[1];
        if let Some((owner, _)) = sem.def_at(file, line) {
            if sem.proc_ref(&owner, name).is_some() { w.method(&owner, name); continue; }
        }
        w.global(name);
    }
    w.found.into_iter().collect()
}


/// Statically named callback references are dependencies even though nameof() erases them to strings.
pub fn source_proc_refs(sem: &Sem, file: &str, line: u32, text: &str, marker_owner: Option<&str>) -> Vec<Finding> {
    source_proc_refs_in(sem, file, line, text, marker_owner, Layer::Engine)
}
pub fn source_proc_refs_in(sem: &Sem, file: &str, line: u32, text: &str, marker_owner: Option<&str>, layer: Layer) -> Vec<Finding> {
    if !text.contains("PROC_REF") { return Vec::new(); }
    let owner = marker_owner.map(str::to_string).or_else(|| sem.def_at(file, line).map(|(owner, _)| owner)).unwrap_or_else(|| "/".to_string());
    let mut w = Walker { sem, file: file.to_string(), owner: owner.clone(), line, locals: BTreeMap::new(), found: BTreeSet::new(), layer };
    static TYPED_PATTERN: OnceLock<regex::Regex> = OnceLock::new();
    let typed = TYPED_PATTERN.get_or_init(|| regex::Regex::new(r"\bTYPE_PROC_REF\s*\(\s*(/[A-Za-z_][\w/]*)\s*,\s*([A-Za-z_]\w*)\s*\)").unwrap());
    for cap in typed.captures_iter(text) { w.ty(&cap[1]); w.method(&cap[1], &cap[2]); }
    static OWN_PATTERN: OnceLock<regex::Regex> = OnceLock::new();
    let own = OWN_PATTERN.get_or_init(|| regex::Regex::new(r"\bPROC_REF\s*\(\s*([A-Za-z_]\w*)\s*\)").unwrap());
    for cap in own.captures_iter(text) { w.method(&owner, &cap[1]); }
    w.found.into_iter().collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tree::{SourceFile, Tree};

    fn fixture(engine_source: &str, library: &str) -> (tempfile::TempDir, Sem) {
        fixture_sources(&[("code/engine/probe.dm", engine_source), ("code/library/not_a_prefix.dm", library)])
    }
    fn fixture_sources(sources: &[(&str, &str)]) -> (tempfile::TempDir, Sem) {
        let root = tempfile::tempdir().unwrap();
        let mut files = Vec::new();
        for &(rel, text) in sources {
            let abs = root.path().join(rel);
            std::fs::create_dir_all(abs.parent().unwrap()).unwrap();
            std::fs::write(abs, text).unwrap();
            files.push(SourceFile::from_text(rel, text));
        }
        let tree = Tree::from_files(files);
        let sem = Sem::build(root.path(), &tree).unwrap();
        assert!(sem.errors.is_empty(), "fixture parse errors: {:?}", sem.errors);
        (root, sem)
    }
    fn findings(sem: &Sem) -> Vec<Finding> {
        scan(sem, &["code/engine/probe.dm".to_string()].into_iter().collect())
    }
    #[test]
    fn arbitrary_external_global_is_not_hidden_by_name() {
        let (_root, sem) = fixture("/proc/engine_entry()\n\tordinary_name()\n", "/proc/ordinary_name()\n\treturn 1\n");
        assert!(findings(&sem).iter().any(|f| f.message.contains("/proc/ordinary_name") && f.message.contains("code/library/")));
    }
    #[test]
    fn signatures_and_locals_use_type_definition_provenance() {
        let (_root, sem) = fixture("/proc/engine_entry(datum/innocent_name/input)\n\tvar/datum/innocent_name/local\n\treturn local\n", "/datum/innocent_name\n");
        let found = findings(&sem);
        assert!(found.iter().any(|f| f.line == 1 && f.message.contains("/datum/innocent_name")));
        assert!(found.iter().any(|f| f.line == 2 && f.message.contains("/datum/innocent_name")));
    }
    #[test]
    fn inherited_external_method_is_detected_on_engine_receiver() {
        let (_root, sem) = fixture("/datum/engine_parent\n/datum/engine_child\n\tparent_type = /datum/engine_parent\n/datum/engine_child/proc/check()\n\thelper()\n", "/datum/engine_parent/proc/helper()\n\treturn 1\n");
        assert!(findings(&sem).iter().any(|f| f.message.contains("::helper") && f.message.contains("code/library/")));
    }
    #[test]
    fn genuine_engine_virtual_hook_accepts_downstream_override() {
        let (_root, sem) = fixture("/datum/interface\n/datum/interface/proc/hook()\n\treturn null\n/proc/engine_entry(datum/implementation/x)\n\tx.hook()\n", "/datum/implementation\n\tparent_type = /datum/interface\n/datum/implementation/hook()\n\treturn 1\n");
        assert!(!findings(&sem).iter().any(|f| f.message.contains("::hook")), "engine virtual declaration authorizes callback dispatch");
        assert!(findings(&sem).iter().any(|f| f.message.contains("/datum/implementation")), "the content-specific signature itself remains unlawful");
    }
    #[test]
    fn macro_paths_and_helpers_are_not_lost_to_empty_expansion() {
        let (_root, sem) = fixture("/proc/engine_entry()\n\treturn 1\n", "/datum/plain_name\n/proc/plain_helper()\n\treturn 1\n");
        let found = source_paths(&sem, "code/engine/probe.dm", 3, "CAPABILITIES(/datum/plain_name)");
        assert!(found.iter().any(|f| f.message.contains("/datum/plain_name")));
        let found = marker_calls(&sem, "code/engine/probe.dm", 4, "ordinary_part(plain_helper())");
        assert!(found.iter().any(|f| f.message.contains("/proc/plain_helper")));
    }
    #[test]
    fn builtin_and_engine_helpers_do_not_trigger() {
        let (_root, sem) = fixture("/proc/engine_helper()\n\treturn 1\n/proc/engine_entry()\n\treturn max(engine_helper(), 1)\n", "");
        assert!(findings(&sem).is_empty(), "{:?}", findings(&sem));
    }
    #[test]
    fn scalar_external_field_is_not_a_type_or_proc_dependency() {
        let (_root, sem) = fixture("/datum/interface\n/datum/interface/proc/engine_read()\n\treturn downstream_value + src.downstream_value\n", "/datum/interface/var/downstream_value = 1\n");
        assert!(findings(&sem).is_empty(), "{:?}", findings(&sem));
    }
    #[test]
    fn external_typed_field_dependency_is_detected() {
        let (_root, sem) = fixture("/datum/interface\n/datum/interface/proc/engine_read()\n\treturn downstream_value\n", "/datum/foreign_payload\n/datum/interface/var/datum/foreign_payload/downstream_value\n");
        assert!(findings(&sem).iter().any(|f| f.message.contains("/datum/foreign_payload")));
    }
    #[test]
    fn reopened_builtin_types_keep_intrinsic_provenance() {
        let (_root, sem) = fixture("/proc/engine_entry(area/a, turf/t, mob/m)\n\tvar/area/local_area = a\n\treturn local_area\n", "/area\n/turf\n/mob\n/area/foreign_area\n");
        assert!(findings(&sem).is_empty(), "{:?}", findings(&sem));
        let found = source_paths(&sem, "code/engine/probe.dm", 1, "/area/foreign_area");
        assert!(found.iter().any(|f| f.message.contains("/area/foreign_area")));
    }
    #[test]
    fn initializer_helpers_use_global_definition_provenance() {
        let (_root, sem) = fixture("/proc/engine_entry()\n\tvar/value = foreign_factory()\n\treturn value\n", "/proc/foreign_factory()\n\treturn 1\n");
        let found = marker_calls(&sem, "code/engine/probe.dm", 2, "var/value = foreign_factory()");
        assert!(found.iter().any(|f| f.message.contains("/proc/foreign_factory")));
    }

    #[test]
    fn typed_list_elements_are_checked_even_when_empty() {
        let (_root, sem) = fixture("/proc/engine_entry(list/datum/not_named_content/input)\n\treturn input\n", "/datum/not_named_content\n");
        assert!(findings(&sem).iter().any(|f| f.message.contains("/datum/not_named_content")));
    }

    #[test]
    fn callback_references_resolve_foreign_member_implementations() {
        let (_root, sem) = fixture("/datum/interface\n/datum/interface/proc/engine_entry()\n\treturn 1\n", "/datum/interface/proc/foreign_callback()\n\treturn 1\n");
        let own = source_proc_refs(&sem, "code/engine/probe.dm", 3, "after(src, 1, PROC_REF(foreign_callback))", None);
        assert!(own.iter().any(|f| f.message.contains("::foreign_callback") && f.message.contains("code/library/")));
        let typed = source_proc_refs(&sem, "code/engine/probe.dm", 3, "TYPE_PROC_REF(/datum/interface, foreign_callback)", None);
        assert!(typed.iter().any(|f| f.message.contains("::foreign_callback")));
        let marker = source_proc_refs(&sem, "code/engine/probe.dm", 1, "then(PROC_REF(foreign_callback))", Some("/datum/interface"));
        assert!(marker.iter().any(|f| f.message.contains("::foreign_callback")));
    }

    #[test]
    fn implicit_member_only_types_are_external_dependencies() {
        let (_root, sem) = fixture("/proc/engine_entry(datum/implicit_proc/p, datum/implicit_var/v)\n\treturn p\n", "/datum/implicit_proc/proc/helper()\n\treturn 1\n/datum/implicit_var/var/value\n");
        let found = findings(&sem);
        assert!(found.iter().any(|f| f.message.contains("/datum/implicit_proc")));
        assert!(found.iter().any(|f| f.message.contains("/datum/implicit_var")),
            "findings={:?}; headers={:?}; owner_defs={:?}; type={:?}", found,
            sem.layering_type_defs, sem.layering_owner_defs,
            sem.ty("/datum/implicit_var").map(|ty| (ty.path().to_string(), ty.var_names())));
    }
    #[test]
    fn engine_hook_does_not_authorize_downstream_item_type() {
        let (_root, sem) = fixture(
            "/obj/item/proc/engine_hook()\n\treturn null\n/proc/engine_entry(obj/item/held)\n\treturn held.engine_hook()\n",
            "/obj/item\n\tname = \"item\"\n",
        );
        assert!(!builtin_type("/obj/item"), "item is application-defined, not a BYOND intrinsic");
        let found = findings(&sem);
        assert!(found.iter().any(|f| f.message.starts_with("/obj/item is defined in code/library/")),
            "findings={:?}; headers={:?}; owner_defs={:?}", found, sem.layering_type_defs, sem.layering_owner_defs);
        assert!(!found.iter().any(|f| f.message.contains("::engine_hook")));
    }

    #[test]
    fn host_layer_is_held_to_the_engine_boundary() {
        let (_root, sem) = fixture_sources(&[
            ("code/host/probe.dm", "/proc/host_entry(obj/item/held)\n\treturn held\n/proc/host_other()\n\treturn engine_helper()\n"),
            ("code/engine/caller.dm", "/proc/engine_helper()\n\treturn host_entry(null)\n"),
            ("code/library/not_a_prefix.dm", "/obj/item\n\tname = \"item\"\n"),
        ]);
        let scanned = scan(&sem, &["code/host/probe.dm".to_string(), "code/engine/caller.dm".to_string()].into_iter().collect());
        assert!(scanned.iter().any(|f| f.file == "code/host/probe.dm" && f.message.starts_with("/obj/item is defined in code/library/")));
        assert!(!scanned.iter().any(|f| f.message.contains("/proc/host_entry")), "the engine may call host");
    }

    #[test]
    fn neutral_helper_reopening_does_not_authorize_downstream_item() {
        let (_root, sem) = fixture_sources(&[
            ("code/engine/probe.dm", "/obj/item/proc/engine_hook()\n\treturn null\n/proc/engine_entry(obj/item/held)\n\treturn held.engine_hook()\n"),
            ("code/library/not_a_prefix.dm", "/obj/item\n\tname = \"item\"\n"),
            ("code/_helpers/globals.dm", "/obj/item\n\tvar/helper_value\n"),
        ]);
        assert!(findings(&sem).iter().any(|f| f.message.starts_with("/obj/item is defined in code/library/")));
        assert!(!findings(&sem).iter().any(|f| f.message.contains("::engine_hook")));
    }

    #[test]
    fn genuine_engine_header_authorizes_shared_reopening() {
        let (_root, sem) = fixture_sources(&[
            ("code/engine/probe.dm", "/datum/interface\n\tvar/engine_value\n/proc/engine_entry(datum/interface/input)\n\treturn input\n"),
            ("code/library/not_a_prefix.dm", "/datum/interface\n\tvar/world_value\n"),
            ("code/_helpers/globals.dm", "/datum/interface\n\tvar/helper_value\n"),
        ]);
        assert!(!findings(&sem).iter().any(|f| f.message.contains("/datum/interface is defined")));
    }

    #[test]
    fn generated_reopening_does_not_authorize_external_type() {
        let (_root, sem) = fixture_sources(&[
            ("code/engine/probe.dm", "/proc/engine_entry(datum/foreign/input)\n\treturn input\n"),
            ("code/library/not_a_prefix.dm", "/datum/foreign\n"),
            ("code/engine/_generated/probe.dm", "/datum/foreign\n"),
        ]);
        assert!(findings(&sem).iter().any(|f| f.message.contains("/datum/foreign")));
    }

    #[test]
    fn erased_capability_markers_define_external_type_identity() {
        let (_root, sem) = fixture(
            "#define CAPABILITY_TYPE(name, id, type, args...)\n#define CAPABILITY_DEF(name, id, args...)\n/proc/engine_entry(datum/marker_only/a, datum/capability/def/marker_bundle/b)\n\treturn a\n",
            "CAPABILITY_TYPE(marker_only, CAP_MARKER, /datum/marker_only)\nCAPABILITY_DEF(marker_bundle, CAP_BUNDLE)\n",
        );
        let found = findings(&sem);
        assert!(found.iter().any(|f| f.message.contains("/datum/marker_only")));
        assert!(found.iter().any(|f| f.message.contains("/datum/capability/def/marker_bundle")));
    }

    #[test]
    fn inherited_value_override_defines_an_implicit_external_type() {
        let (_root, sem) = fixture(
            "/datum/message\n\tvar/text\n/proc/engine_entry(datum/message/foreign/input)\n\treturn input\n",
            "/datum/message/foreign/text = \"downstream message\"\n",
        );
        assert!(findings(&sem).iter().any(|f| f.message.contains("/datum/message/foreign")));
    }

    /// A type reopened by several content files is one finding per site, so adding another reopening does not change the count at every
    /// site that names the type (the baseline fingerprint ignores the message; the count would read as new sites on a full and a
    /// `--changed-only` run alike).
    #[test]
    fn reopening_a_content_type_in_more_files_adds_no_findings() {
        let count = |extra: bool| {
            let mut sources = vec![
                ("code/library/probe.dm", "/proc/library_entry(datum/foreign/f)\n\treturn f\n"),
                ("code/content/a.dm", "/datum/foreign\n"),
                ("code/content/b.dm", "/datum/foreign\n"),
            ];
            if extra { sources.push(("code/content/c.dm", "/datum/foreign\n")); }
            let (_root, sem) = fixture_sources(&sources);
            let included = ["code/library/probe.dm".to_string()].into_iter().collect();
            scan_in(&sem, &included, Layer::Library).len()
        };
        assert_eq!(count(false), count(true));
        assert!(count(false) > 0);
    }

    #[test]
    fn library_layer_names_engine_library_and_world_model_but_not_content() {
        let (_root, sem) = fixture_sources(&[
            ("code/library/probe.dm", "/proc/library_entry(obj/item/held, datum/shared/s, datum/foreign/f)\n\treturn held\n"),
            ("code/domains/world_model/item.dm", "/obj/item\n\tname = \"item\"\n"),
            ("code/library/shared.dm", "/datum/shared\n"),
            ("code/content/foreign.dm", "/datum/foreign\n"),
        ]);
        let included = ["code/library/probe.dm".to_string()].into_iter().collect();
        let found = scan_in(&sem, &included, Layer::Library);
        assert!(found.iter().any(|f| f.message.starts_with("/datum/foreign is defined in code/content/")), "{:?}", found);
        assert!(!found.iter().any(|f| f.message.contains("/obj/item") || f.message.contains("/datum/shared")), "{:?}", found);
        let engine = scan_in(&sem, &included, Layer::Engine);
        assert!(engine.iter().any(|f| f.message.contains("/datum/shared")), "the engine layer may not name the library: {:?}", engine);
    }

}
