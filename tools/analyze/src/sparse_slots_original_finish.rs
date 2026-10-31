use super::*;
pub fn finish(builder:Builder) -> Output {
        let Builder { mut rows, mut out } = builder;
        rows.sort();
        for w in rows.windows(2) {
            if w[0].0 == w[1].0 && w[0].1 == w[1].1 {
                out.diag_fmt(
                    &w[1].3,
                    w[1].4,
                    format_args!(
                        "sparse slot `{}` of {} is declared twice (also {}:{})",
                        w[1].1, w[1].0, w[0].3, w[0].4
                    ),
                );
            }
        }
        rows.dedup_by(|a, b| a.0 == b.0 && a.1 == b.1);
        out.doc("Every sparse() slot declaration: list(owner type, slot name, value kind). Read by code/engine/declare/sparse_vv.dm.");
        out.line("/proc/sparse_slot_rows()");
        out.line("	var/static/list/rows = list(");
        let last = rows.len().saturating_sub(1);
        for (i, (owner, name, kind, _, _)) in rows.iter().enumerate() {
            let comma = if i == last { "" } else { "," };
            out.line_fmt(format_args!(
                "		list({}, \"{}\", \"{}\"){}",
                owner, name, kind, comma
            ));
        }
        out.line("	)");
        out.line("	return rows");
        out
    }
