//! `analyze gen sparse_slots` -> `code/engine/_generated/sparse_slots.dm`.
//!
//! `sparse(/type, name, type = kind)` (code/__defines/engine/sparse_slots.dm) declares a sparse slot and expands to nothing. This is the
//! registry of those declarations: `sparse_slot_rows()` returns one `list(/type, "name", "kind")` row per declaration, which View Variables,
//! mass edit and SDQL read to list and resolve a slot by name (code/engine/declare/sparse_vv.dm).

use crate::sem::gen::{GenCx, GenOut, Generator};

struct SparseSlots;

impl Generator for SparseSlots {
    fn name(&self) -> &'static str {
        "sparse_slots"
    }

    fn output(&self) -> &'static str {
        "sparse_slots.dm"
    }

    fn generate(&self, cx: &GenCx, out: &mut GenOut) {
        let mut builder = crate::sparse_slots_policy::Builder::default();
        for m in cx.markers("sparse") {
            builder.push(&m.rel, m.line, &m.args);
        }
        let generated = builder.finish();
        for diag in generated.diags {
            out.diag(&diag.rel, diag.line, diag.msg);
        }
        for line in generated.body.split_terminator('\n') {
            out.line(line);
        }
    }
}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(SparseSlots));
}
