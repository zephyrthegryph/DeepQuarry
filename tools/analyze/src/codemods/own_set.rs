//! `own_set(holder, nameof(holder.var), value)` to `rel_set(holder, nameof(holder.var), value)`
//! (doc/rewrite/api_mapping.tsv, row own_set; the one write verb of doc section 6).
//!
//! `rel_set` is on master (code/engine/declare/relations.dm) and dispatches on the declared kind of the var:
//! for an `owns_one` var (the only kind `own_set` accepts) it calls `own_set`, so the conversion is a
//! rename. The transfer arguments of `own_set` (`user =`, `into =`, `slot =`, `force =`, `log =`) have no
//! counterpart on `rel_set`: a call that passes one stays as residue and becomes a `move_into()` in the
//! wave that owns transfers.

use crate::codemod::helpers::rename_exact;
use crate::codemod::{Codemod, Ctx, Outcome};

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
            ("extra_args", "a transfer argument (rel_set takes none): becomes move_into(holder, slot, item, actor =) in the transfers wave"),
        ]
    }
    fn excluded(&self, rel: &str) -> bool {
        crate::codemod::default_excluded(rel) || rel.starts_with("code/datums/ownership/")
    }
    fn rewrite(&self, cx: &Ctx) -> Outcome {
        rename_exact(cx, "rel_set", 3)
    }
}

pub fn register(reg: &mut Vec<Box<dyn Codemod>>) {
    reg.push(Box::new(OwnSet));
}
