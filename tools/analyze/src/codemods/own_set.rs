//! `own_set(holder, nameof(holder.var), value)` to `rel_set(holder, nameof(holder.var), value)`
//! (doc/rewrite/api_mapping.tsv, row own_set; the one write verb of doc section 6).
//!
//! `rel_set` is on master (code/engine/declare/relations.dm) and dispatches on the declared kind of the var:
//! for an `owns_one` var (the only kind `own_set` accepts) it calls `own_set`, so the conversion is a
//! rename. The transfer arguments of `own_set` (`user =`, `into =`, `slot =`, `force =`, `log =`) have no
//! counterpart on `rel_set`: a call that passes one stays as residue and becomes a `move_into()` in the
//! wave that owns transfers.

use crate::codemod::own_decl;
use crate::codemod::{Codemod, Ctx, Edit, Need, Outcome};
use crate::sem::Sem;
use crate::tree::Tree;
use std::any::Any;
use std::path::Path;
use std::sync::Arc;

pub struct OwnSet;

impl Codemod for OwnSet {
    fn name(&self) -> &'static str {
        "own_set"
    }
    fn about(&self) -> &'static str {
        "own_set(holder, var, value) -> rel_set(holder, var, value)"
    }
    fn callees(&self) -> &'static [&'static str] {
        &["own_set"]
    }
    fn reasons(&self) -> &'static [(&'static str, &'static str)] {
        &[
            ("too_few_args", "fewer than (holder, var, value): malformed, fix the call"),
            ("dynamic_var", "the var is not written as nameof(x) or a literal, so its type cannot be read"),
            ("unresolved_receiver", "the static type of the holder is unknown (an untyped local, a chain, a call spanning lines): declare the var by hand"),
            ("unknown_var", "the holder's type has no such var"),
            ("untyped_var", "the var has no declared entity type (untyped, or a value type), or its type is declared in the vendored TGS API or the defines: nothing to declare it as"),
            ("list_var", "own_set on a list var: rel_set goes through the list state; convert by hand"),
            ("extra_args", "a transfer argument (rel_set takes none): becomes move_into(holder, slot, item, actor =) in the transfers wave"),
        ]
    }
    fn excluded(&self, rel: &str) -> bool {
        crate::codemod::default_excluded(rel) || rel.starts_with("code/datums/ownership/")
    }
    fn rewrite(&self, cx: &Ctx) -> Outcome {
        own_decl::rewrite(cx, "rel_set", false)
    }
    fn prepare(&self, tree: &Tree, _sem: &Sem) -> Arc<dyn Any + Send + Sync> {
        own_decl::prepare(tree)
    }
    fn declares(&self) -> bool {
        true
    }
    fn declaration_edits(&self, root: &Path, tree: &Tree, sem: &Sem, prep: &(dyn Any + Send + Sync), needs: &[Need]) -> Vec<(String, Vec<Edit>)> {
        own_decl::declaration_edits(root, tree, sem, prep, needs)
    }
}

pub fn register(reg: &mut Vec<Box<dyn Codemod>>) {
    reg.push(Box::new(OwnSet));
}
