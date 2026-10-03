//! `own_add(holder, nameof(holder.var), value)` to `rel_add(holder, nameof(holder.var), value)`
//! (doc/rewrite/api_mapping.tsv, row own_add; the one write verb of doc section 6).
//!
//! `rel_add` is on master (code/engine/declare/relations.dm) and dispatches on the declared kind of the var:
//! for an `owns_many` var (the only kind `own_add` accepts) it calls `own_add`, so the conversion is a
//! rename. The transfer arguments of `own_add` (`user =`, `into =`, `slot =`, `force =`, `log =`) have no
//! counterpart on `rel_add`: a call that passes one stays as residue and becomes a `move_into()` in the
//! wave that owns transfers.

use crate::codemod::helpers::rename_exact;
use crate::codemod::{Codemod, Ctx, Outcome};

pub struct OwnAdd;

impl Codemod for OwnAdd {
    fn name(&self) -> &'static str {
        "own_add"
    }
    fn about(&self) -> &'static str {
        "own_add(holder, var, value) -> rel_add(holder, var, value)"
    }
    fn callees(&self) -> &'static [&'static str] {
        &["own_add"]
    }
    fn reasons(&self) -> &'static [(&'static str, &'static str)] {
        &[
            ("too_few_args", "fewer than (holder, var, value): malformed, fix the call"),
            ("extra_args", "a transfer argument (rel_add takes none): becomes move_into(holder, slot, item, actor =) in the transfers wave"),
        ]
    }
    fn excluded(&self, rel: &str) -> bool {
        crate::codemod::default_excluded(rel) || rel.starts_with("code/datums/ownership/")
    }
    fn rewrite(&self, cx: &Ctx) -> Outcome {
        rename_exact(cx, "rel_add", 3)
    }
}

pub fn register(reg: &mut Vec<Box<dyn Codemod>>) {
    reg.push(Box::new(OwnAdd));
}
