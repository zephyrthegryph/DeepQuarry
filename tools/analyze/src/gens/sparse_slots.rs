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
        let mut rows: Vec<(String, String, String, String, u32)> = Vec::new();
        for m in cx.markers("sparse") {
            let (Some(owner), Some(name)) = (m.args.first(), m.args.get(1)) else {
                out.diag(&m.rel, m.line, "sparse(/type, name, type = kind) needs a type and a slot name");
                continue;
            };
            let owner = owner.trim().to_string();
            let name = name.trim().to_string();
            if !owner.starts_with('/') || name.is_empty() || !name.chars().all(|c| c.is_alphanumeric() || c == '_') {
                out.diag(&m.rel, m.line, format!("sparse: `{}`, `{}` is not a type path and a slot name", owner, name));
                continue;
            }
            let kind = m
                .args
                .iter()
                .skip(2)
                .find_map(|a| a.trim().strip_prefix("type").map(|r| r.trim_start()).and_then(|r| r.strip_prefix('=')).map(|r| r.trim().to_string()))
                .unwrap_or_default();
            rows.push((owner, name, kind, m.rel.clone(), m.line));
        }
        rows.sort();
        for w in rows.windows(2) {
            if w[0].0 == w[1].0 && w[0].1 == w[1].1 {
                out.diag(&w[1].3, w[1].4, format!("sparse slot `{}` of {} is declared twice (also {}:{})", w[1].1, w[1].0, w[0].3, w[0].4));
            }
        }
        rows.dedup_by(|a, b| a.0 == b.0 && a.1 == b.1);
        out.doc("Every sparse() slot declaration: list(owner type, slot name, value kind). Read by code/engine/declare/sparse_vv.dm.");
        out.line("/proc/sparse_slot_rows()");
        out.line("	var/static/list/rows = list(");
        let last = rows.len().saturating_sub(1);
        for (i, (owner, name, kind, _, _)) in rows.iter().enumerate() {
            let comma = if i == last { "" } else { "," };
            out.line(format!("		list({}, \"{}\", \"{}\"){}", owner, name, kind, comma));
        }
        out.line("	)");
        out.line("	return rows");
    }
}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(SparseSlots));
}
