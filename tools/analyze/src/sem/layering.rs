//! Engine dependency provenance. Unlike reads analysis, this walks effects and all calls too.
use std::collections::{BTreeMap, BTreeSet};
use std::sync::OnceLock;
use dreammaker::ast::{Block, Expression, Follow, Statement, Term, VarType};
use super::{Sem, ast::{stmt_blocks, stmt_exprs, walk_expr}};

pub use crate::engine_layering_policy::Finding;

// Derive exact intrinsic types from DreamMaker's builtin table: reopening a
// builtin changes its source location, but does not make its type downstream-only.
fn builtin_type(path: &str) -> bool {
    static TYPES: OnceLock<BTreeSet<String>> = OnceLock::new();
    TYPES.get_or_init(|| {
        let mut builder = dreammaker::objtree::ObjectTreeBuilder::default();
        builder.register_builtins();
        let tree = builder.skip_finish();
        tree.iter_types().map(|ty| ty.get().path.clone()).collect()
    }).contains(path)
}
fn type_path(v: &VarType) -> Option<String> {
    (!v.type_path.is_empty()).then(|| format!("/{}", v.type_path.join("/")))
}

struct SemFacts<'a>(&'a Sem);
impl<'a,C:crate::key_policy_control::Control> crate::engine_layering_policy::Facts<C> for SemFacts<'a>{
 type Call=dreammaker::objtree::ProcRef<'a>;
 fn type_exists(&self,path:&str,c:&mut C)->Result<bool,C::Error>{c.checkpoint()?;Ok(self.0.ty(path).is_some())}
 fn def_at(&self,file:&str,line:u32,c:&mut C)->Result<Option<(String,String)>,C::Error>{c.checkpoint()?;Ok(self.0.def_at(file,line))}
 fn builtin_type(&self,path:&str,c:&mut C)->Result<bool,C::Error>{c.checkpoint()?;Ok(builtin_type(path))}
 fn type_headers(&self,path:&str)->Option<&[String]>{self.0.layering_type_defs.get(path).map(Vec::as_slice)}
 fn owner_definitions(&self,path:&str)->Option<&[String]>{self.0.layering_owner_defs.get(path).map(Vec::as_slice)}
 fn method(&self,owner:&str,name:&str,c:&mut C)->Result<Option<Self::Call>,C::Error>{c.checkpoint()?;Ok(self.0.proc_ref(owner,name))}
 fn global(&self,name:&str,c:&mut C)->Result<Option<Self::Call>,C::Error>{c.checkpoint()?;Ok(self.0.global_proc(name))}
 fn builtin_call(&self,call:&Self::Call,c:&mut C)->Result<bool,C::Error>{c.checkpoint()?;Ok(call.is_builtin())}
 fn callable_file(&self,call:&Self::Call,c:&mut C)->Result<String,C::Error>{c.checkpoint()?;let body=self.0.proc_body(*call);crate::key_policy_control::own(c,&body.file)}
 fn visit_method_declaration_files(&self,owner:&str,name:&str,c:&mut C,emit:&mut dyn FnMut(&str,&mut C)->Result<bool,C::Error>)->Result<(),C::Error>{let mut ancestor=Some(crate::key_policy_control::own(c,owner)?);while let Some(t)=ancestor{c.checkpoint()?;if let Some(local)=self.0.ty(&t).and_then(|ty|ty.get().procs.get(name)){for value in local.value.iter(){c.checkpoint()?;if !emit(self.0.rel(value.location),c)?{return Ok(())}}}ancestor=self.0.parent_of(&t);}Ok(())}
}

struct Walker<'a> { sem: &'a Sem, file: String, owner: String, line: u32, locals: BTreeMap<String, String>, found: BTreeSet<Finding> }
impl Walker<'_> {
    fn ty(&mut self, path: &str) { crate::engine_layering_policy::ty(&SemFacts(self.sem),&mut self.found,&self.file,self.line,path,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{}) }

    fn method(&mut self, owner: &str, name: &str) { crate::engine_layering_policy::method(&SemFacts(self.sem),&mut self.found,&self.file,self.line,owner,name,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{}) }

    fn global(&mut self, name: &str) { crate::engine_layering_policy::global(&SemFacts(self.sem),&mut self.found,&self.file,self.line,name,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{}) }

    fn expr(&mut self, e: &Expression) {
        walk_expr(e, &mut |e| self.expr_one(e));
    }
    fn expr_one(&mut self, e: &Expression) {
        let Expression::Base { term, follow } = e else { return; };
        let mut receiver = match &term.elem {
            Term::Ident(n) if n == "src" => Some(self.owner.clone()),
            Term::Ident(n) => {
                if let Some(local) = self.locals.get(n) { Some(local.clone()) }
                else if let Some(v) = self.sem.var_decl(&self.owner, n) {
                    if !v.declared.is_empty() { self.ty(&v.declared); }
                    Some(v.declared)
                } else { None }
            },
            Term::Call(n, _) => {
                if self.sem.proc_ref(&self.owner, n).is_some() { let owner = self.owner.clone(); self.method(&owner, n); }
                else { self.global(n); }
                None
            }
            Term::GlobalCall(n, _) => { self.global(n); None }
            Term::ParentCall(_) => {
                // Parent-call target is checked by the proc walk, using its current method name.
                None
            }
            Term::Prefab(p) => {
                let path = p.path.iter().map(|(_, n)| format!("/{}", n)).collect::<String>();
                self.ty(&path); Some(path)
            }
            Term::DynamicCall(_, _) => None, // Dynamic callbacks have no statically provable target; not a blanket dynamic-call ban.
            _ => None,
        };
        for f in follow {
            match &f.elem {
                Follow::Field(_, name) => {
                    if let Some(ty) = &receiver {
                        if let Some(v) = self.sem.var_decl(ty, name) {
                            if !v.declared.is_empty() { self.ty(&v.declared); }
                            receiver = Some(v.declared);
                        } else { receiver = None; }
                    }
                }
                Follow::Call(_, name, _) => {
                    if let Some(ty) = receiver.as_ref().filter(|t| !t.is_empty()).cloned() { self.method(&ty, name); }
                    // Untyped dynamic receivers are outside this provenance check, not automatically unlawful.
                    receiver = None;
                }
                Follow::ProcReference(name) => {
                    if let Some(ty) = receiver.as_ref().filter(|t| !t.is_empty()).cloned() { self.method(&ty, name.as_str()); }
                    else if matches!(&term.elem, Term::Ident(n) if n == "src") { let owner = self.owner.clone(); self.method(&owner, name.as_str()); }
                }
                Follow::Index(_, _) => { receiver = None; }
                _ => {}
            }
        }
    }
    fn block(&mut self, block: &Block) {
        for st in block {
            self.line = st.location.line;
            match &st.elem {
                Statement::Var(v) => {
                    if let Some(t) = type_path(&v.var_type) { self.ty(&t); self.locals.insert(v.name.to_string(), t); }
                }
                Statement::Vars(vars) => for v in vars {
                    if let Some(t) = type_path(&v.var_type) { self.ty(&t); self.locals.insert(v.name.to_string(), t); }
                },
                Statement::ForList(v) => {
                    if let Some(t) = v.var_type.as_ref().and_then(type_path) { self.ty(&t); self.locals.insert(v.name.to_string(), t); }
                }
                Statement::ForKeyValue(v) => {
                    if let Some(t) = v.var_type.as_ref().and_then(type_path) { self.ty(&t); self.locals.insert(v.key.to_string(), t); }
                }
                Statement::ForLoop { init, inc, .. } => {
                    for stmt in [init, inc].into_iter().flatten() {
                        if let Statement::Var(v) = stmt.as_ref() {
                            if let Some(t) = type_path(&v.var_type) { self.ty(&t); self.locals.insert(v.name.to_string(), t); }
                        }
                        for e in stmt_exprs(stmt) { self.expr(e); }
                    }
                }
                _ => {}
            }
            for e in stmt_exprs(&st.elem) { self.expr(e); }
            for b in stmt_blocks(&st.elem) { self.block(b); }
        }
    }
}

pub fn scan(sem: &Sem, included: &BTreeSet<String>) -> Vec<Finding> {
    let mut all = BTreeSet::new();
    for ty in std::iter::once(sem.objtree.root()).chain(sem.objtree.iter_types()) {
        let owner = if ty.get().path.is_empty() { "/".to_string() } else { ty.get().path.clone() };
        for (name, proc) in &ty.get().procs {
            for v in &proc.value {
                let file = sem.rel(v.location).to_string();
                if !included.contains(&file) { continue; }
                let mut w = Walker { sem, file, owner: owner.clone(), line: v.location.line, locals: BTreeMap::new(), found: BTreeSet::new() };
                w.ty(&owner);
                for p in &v.parameters {
                    if let Some(t) = type_path(&p.var_type) { w.ty(&t); w.locals.insert(p.name.clone(), t); }
                }
                if let Some(code) = &*v.code {
                    // ..() is a dependency on the nearest parent implementation, not on the overriding body.
                    let mut parent_call = false;
                    super::ast::walk_block(code, &mut |e, _| if let Expression::Base { term, .. } = e { if matches!(term.elem, Term::ParentCall(_)) { parent_call = true; } });
                    if parent_call { if let Some(parent) = sem.parent_of(&owner) { w.method(&parent, name); } }
                    w.block(code);
                }
                all.extend(w.found);
            }
        }
        for (_name, var) in &ty.get().vars {
            if let Some(d) = &var.declaration {
                let file = sem.rel(d.location).to_string();
                if !included.contains(&file) { continue; }
                let mut w = Walker { sem, file, owner: owner.clone(), line: d.location.line, locals: BTreeMap::new(), found: BTreeSet::new() };
                if let Some(t) = type_path(&d.var_type) { w.ty(&t); }
                all.extend(w.found);
            }
        }
    }
    all.into_iter().collect()
}

/// Source-only markers and explicit type/proc paths lost during macro expansion are resolved against the same model.
pub fn source_paths(sem:&Sem,file:&str,line:u32,text:&str)->Vec<Finding>{let mut found=BTreeSet::new();crate::engine_layering_policy::source_paths(&SemFacts(sem),&mut found,file,line,text,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{});found.into_iter().collect()}
pub fn marker_calls(sem:&Sem,file:&str,line:u32,text:&str)->Vec<Finding>{let mut found=BTreeSet::new();crate::engine_layering_policy::marker_calls(&SemFacts(sem),&mut found,file,line,text,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{});found.into_iter().collect()}
pub fn source_proc_refs(sem:&Sem,file:&str,line:u32,text:&str,marker_owner:Option<&str>)->Vec<Finding>{let mut found=BTreeSet::new();crate::engine_layering_policy::source_proc_refs(&SemFacts(sem),&mut found,file,line,text,marker_owner,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{});found.into_iter().collect()}

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
            sem.ty("/datum/implicit_var").map(|ty| (ty.get().path.clone(), ty.get().vars.clone())));
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

}
