//! `own_add(holder, nameof(holder.var), value)` to `rel_add(holder, nameof(holder.var), value)`
//! (doc/rewrite/api_mapping.tsv, row own_add; the one write verb of doc section 6).
//!
//! `rel_add` is on master (code/engine/declare/relations.dm) and dispatches on the declared kind of the var:
//! for an `owns_many` var (the only kind `own_add` accepts) it calls `own_add`, so the conversion is a
//! rename. The transfer arguments of `own_add` (`user =`, `into =`, `slot =`, `force =`, `log =`) have no
//! counterpart on `rel_add`: a call that passes one stays as residue and becomes a `move_into()` in the
//! wave that owns transfers.

use crate::codemod::own_decl;
use crate::codemod::{Codemod, Ctx, Edit, Need, Outcome};
use crate::codemod_facts::FactSource;
use crate::tree::Tree;
use std::any::Any;
use std::path::Path;
use std::sync::Arc;

pub struct OwnAdd;

impl Codemod for OwnAdd {
    fn name(&self) -> &'static str {
        crate::codemod_spec::OWN_ADD.name

    }
    fn about(&self) -> &'static str {
        crate::codemod_spec::OWN_ADD.about

    }
    fn callees(&self) -> &'static [&'static str] {
        crate::codemod_spec::OWN_ADD.callees

    }
    fn reasons(&self) -> &'static [(&'static str, &'static str)] {
        crate::codemod_spec::OWN_ADD.reasons

    }
    fn excluded(&self, rel: &str) -> bool {
        crate::codemod::default_excluded(rel) || rel.starts_with("code/library/ownership/")
    }
    fn rewrite(&self, cx: &Ctx) -> Outcome {
        own_decl::rewrite(cx, "rel_add", true)
    }
    fn prepare(&self, tree: &Tree, _sem: &dyn FactSource) -> Arc<dyn Any + Send + Sync> {
        own_decl::prepare(tree)
    }
    fn declares(&self) -> bool {
        true
    }
    fn declaration_edits_admitted(&self,root:&Path,sem:&dyn FactSource,prep:&(dyn Any+Send+Sync),physical:&dyn crate::codemod::PhysicalFiles,needs:&[Need],work:&dyn crate::policy_finish::admitted::Work)->std::io::Result<Vec<(String,Vec<Edit>)>>{own_decl::declaration_edits_using(root,sem,prep,physical,needs,Some(work))}
    fn declaration_edits(&self, root: &Path, tree: &Tree, sem: &dyn FactSource, prep: &(dyn Any + Send + Sync), physical:&dyn crate::codemod::PhysicalFiles, needs: &[Need]) -> std::io::Result<Vec<(String, Vec<Edit>)>> {
        own_decl::declaration_edits(root, tree, sem, prep, physical, needs)
    }
}

pub fn register(reg: &mut Vec<Box<dyn Codemod>>) {
    reg.push(Box::new(OwnAdd));
}
