//! `analyze gen reads` -> `code/engine/_generated/reads.dm`.
//!
//! "Generation: a query in the analysis engine, run incrementally before the DM compile. It writes
//! code/engine/_generated/reads.dm, which is never edited by hand. Keys are interned to integers at
//! build time. Evaluation is one generated typed accessor call, and nothing uses vars[], call() or
//! text keys at runtime." (doc/rewrite/final_api.html section 7)
//!
//! Coverage is every output, condition, requirement and contribution a declaration names
//! (`sem::hooks::discover`). The file is three global lists:
//!
//! ```text
//! GLOB.generated_read_names   list of every interned name: a var, a hop or an accessor key (id = index)
//! GLOB.generated_read_roots   list of the roots a read starts from (id = index; see READ_ROOT_*)
//! GLOB.generated_reads_table assoc "<type>::<proc>" = list(rank, <read>, <read>, ...)
//!                          a <read> is list(root id, kind, name id, hop name id, hop name id, ...)
//! ```
//!
//! A kind is READ_KIND_VAR (0), READ_KIND_ACCESSOR (1), READ_KIND_NATIVE (2) or READ_KIND_SYSTEM (3).
//! `rank` is the evaluation order of the handler's derived reads (0 = reads only base state).

use std::collections::{BTreeMap, BTreeSet};

use crate::sem::decls::Decls;
use crate::sem::gen::{GenCx, GenOut, Generator};
use crate::sem::graph::DepGraph;
use crate::sem::reads::{Annotations, ReadKind, ReadsEngine};

/// Engine-internal directories the walk does not enter. The Verdigris bindings (code/__defines/verdigris/) read Rust-owned values: a condition that
/// asks one (a SMES's charge) is re-asked when a requirement is checked or a gate is polled, never subscribed.
pub const OPAQUE: &[&str] = &["code/datums/sys/", "code/datums/om/", "code/modules/tgui/", "code/datums/capabilities/", "code/datums/reactions/", "code/datums/ownership/", "code/engine/", "code/__defines/verdigris/"];

struct Reads;

struct Interner {
    names: Vec<String>,
    index: BTreeMap<String, usize>,
}

impl Interner {
    fn id(&mut self, s: &str) -> usize {
        if let Some(i) = self.index.get(s) {
            return *i;
        }
        self.names.push(s.to_string());
        self.index.insert(s.to_string(), self.names.len());
        self.names.len()
    }
}

/// (root, kind, name, hops, owner type)
type Row = (String, ReadKind, String, Vec<String>, String);

impl Generator for Reads {
    fn name(&self) -> &'static str {
        "reads"
    }

    fn output(&self) -> &'static str {
        "reads.dm"
    }

    fn generate(&self, cx: &GenCx, out: &mut GenOut) {
        let handlers: Vec<_> = cx.handlers().into_iter().filter(|h| h.role.reads_covered() && !h.owner.is_empty()).collect();
        let mut rows: BTreeMap<String, Vec<Row>> = BTreeMap::new();
        let mut ranks: BTreeMap<String, u32> = BTreeMap::new();
        let mut capability_keys = BTreeSet::new();
        let defines = Decls::get(cx.tree).defines.iter().cloned().collect();
        if !handlers.is_empty() {
            if let Some(sem) = cx.sem() {
                let decls = Decls::get(cx.tree);
                let ann = Annotations::get(&sem, &decls);
                capability_keys.extend(ann.capkey_accessors.values().cloned());
                let eng = ReadsEngine::new(&sem, &decls, &ann).with_opaque(OPAQUE);
                for h in &handlers {
                    let id = format!("{}::{}", h.owner, h.proc);
                    if rows.contains_key(&id) {
                        continue;
                    }
                    if sem.proc_ref(&h.owner, &h.proc).is_none() {
                        out.diag(&h.rel, h.line, format!("handler `{}` is not a proc of {}", h.proc, h.owner));
                        continue;
                    }
                    let set = eng.analyze_handler(&h.owner, &h.proc, h.ctx.type_path());
                    for d in &set.diags {
                        if matches!(d.rule, "unannotated_global" | "dynamic_read") {
                            out.diag(&d.rel, d.line, format!("{}: {}", d.rule, d.msg));
                        }
                    }
                    let mut v: Vec<Row> = set.reads.iter().map(|r| (r.root.clone(), r.kind.clone(), r.var.clone(), r.hops.clone(), r.owner.clone())).collect();
                    v.sort();
                    rows.insert(id, v);
                }
                let graph = DepGraph::from_derives(&sem, &eng);
                match graph.ranks() {
                    Ok(r) => ranks = r,
                    Err(cycles) => {
                        for c in cycles {
                            let first = graph.nodes.get(&c[0]);
                            out.diag(first.map(|n| n.rel.as_str()).unwrap_or(""), first.map(|n| n.line).unwrap_or(0), format!("condition_cycle: {}", c.join(" -> ")));
                        }
                    }
                }
            } else {
                out.diag("deepquarry.dme", 1, "the semantic model could not be built; reads cannot be generated");
            }
        }

        let mut names = Interner { names: Vec::new(), index: BTreeMap::new() };
        let mut roots = Interner { names: Vec::new(), index: BTreeMap::new() };
        // The fixed roots keep their ids across builds.
        for r in ["holder", "actor", "held", "target"] {
            roots.id(r);
        }
        let mut table = String::new();
        for (id, reads) in &rows {
            // A handler runs after every derived value it reads: one more than the deepest.
            let rank = reads.iter().filter(|r| r.1 == ReadKind::Var).filter_map(|r| ranks.get(&format!("{}::{}", r.4, r.2)).map(|k| k + 1)).max().unwrap_or(0);
            table.push_str(&format!("\t\"{}\" = list({}", id, rank));
            for (root, kind, var, hops, _owner) in reads {
                let kind_id = match kind {
                    ReadKind::Var => 0,
                    ReadKind::Accessor => 1,
                    ReadKind::Native => 2,
                    ReadKind::System => 3,
                };
                let mut parts = vec![roots.id(root).to_string(), kind_id.to_string(), names.id(&canonical_read_key(kind, var, &capability_keys, &defines)).to_string()];
                for h in hops {
                    parts.push(names.id(h).to_string());
                }
                table.push_str(&format!(",\n\t\tlist({})", parts.join(", ")));
            }
            table.push_str("),\n");
        }
        out.line("#define READ_ROOT_HOLDER 1");
        out.line("#define READ_ROOT_ACTOR 2");
        out.line("#define READ_ROOT_HELD 3");
        out.line("#define READ_ROOT_TARGET 4");
        out.line("#define READ_KIND_VAR 0");
        out.line("#define READ_KIND_ACCESSOR 1");
        out.line("#define READ_KIND_NATIVE 2");
        out.line("#define READ_KIND_SYSTEM 3");
        out.blank();
        out.doc("Every interned name a read uses (a var, a relation hop, an accessor key). Id = index in this list.");
        out.line("GLOBAL_LIST_INIT(generated_read_names, list(");
        for (i, n) in names.names.iter().enumerate() {
            out.line(format!("\t\"{}\"{}", n, if i + 1 < names.names.len() { "," } else { "" }));
        }
        out.line("))");
        out.blank();
        out.doc("The roots a read starts from (READ_ROOT_*): the holder, or a context hop. Id = index in this list.");
        out.line("GLOBAL_LIST_INIT(generated_read_roots, list(");
        for (i, n) in roots.names.iter().enumerate() {
            out.line(format!("\t\"{}\"{}", n, if i + 1 < roots.names.len() { "," } else { "" }));
        }
        out.line("))");
        out.blank();
        out.doc("\"<type>::<proc>\" = list(rank, list(root id, kind, name id, hop name ids...), ...). Never edited by hand.");
        out.line(read_table_initializer(&table));
    }
}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(Reads));
}

/// A declared capability accessor reads the actual numeric key published by capability_key_changed.
/// Keep its define as DM interpolation so the generated name uses the authoritative compile-time ID.
fn canonical_read_key(kind: &ReadKind, name: &str, capability_keys: &BTreeSet<String>, defines: &BTreeSet<String>) -> String {
    if *kind == ReadKind::Accessor && capability_keys.contains(name) {
        format!("capkey:[{name}]")
    } else if *kind == ReadKind::Accessor && defines.contains(name) {
        format!("[{name}]")
    } else {
        name.to_string()
    }
}

/// Keep the potentially large table out of a macro argument: BYOND truncates the expanded
/// GLOBAL_MANAGED initializer once its replacement exceeds the preprocessor limit.
fn read_table_initializer(table: &str) -> String {
    let rows = table.trim_end_matches(",\n");
    format!(
        "GLOBAL_LIST(generated_reads_table)\n/datum/controller/global_vars/InitGlobalgenerated_reads_table()\n\tgenerated_reads_table = list(\n{}\n\t)\n\tgvars_datum_init_order += \"generated_reads_table\"",
        rows,
    )
}

#[cfg(test)]
mod tests {
    use super::{canonical_read_key, read_table_initializer};
    use crate::sem::reads::ReadKind;
    use std::collections::BTreeSet;
    #[test]
    fn declared_capability_accessor_uses_its_actual_published_key() {
        let keys = BTreeSet::from(["EMAG_EMAGGED".to_string()]);
        let defines = BTreeSet::from(["OP_KEY_CAP_STATE".to_string()]);
        assert_eq!(canonical_read_key(&ReadKind::Accessor, "EMAG_EMAGGED", &keys, &defines), "capkey:[EMAG_EMAGGED]");
        assert_eq!(canonical_read_key(&ReadKind::Accessor, "cap_state", &keys, &defines), "cap_state");
        assert_eq!(canonical_read_key(&ReadKind::Accessor, "OP_KEY_CAP_STATE", &keys, &defines), "[OP_KEY_CAP_STATE]");
        assert_eq!(canonical_read_key(&ReadKind::Var, "EMAG_EMAGGED", &keys, &defines), "EMAG_EMAGGED");
        assert_eq!(canonical_read_key(&ReadKind::Accessor, "UNKNOWN_STATE", &keys, &defines), "UNKNOWN_STATE");
    }


    #[test]
    fn large_read_table_avoids_macro_argument_and_registers_initialization() {
        let rows = (0..3000).map(|i| format!("\t\"/datum/fixture::read_{i}\" = list(0, list(1, 0, {i})),\n")).collect::<String>();
        assert!(rows.len() > 65536);
        let text = read_table_initializer(&rows);
        assert!(!text.contains("GLOBAL_LIST_INIT("));
        assert!(text.contains("GLOBAL_LIST(generated_reads_table)"));
        assert!(text.contains("/datum/controller/global_vars/InitGlobalgenerated_reads_table()"));
        assert!(text.contains("gvars_datum_init_order += \"generated_reads_table\""));
        assert!(text.contains("\"/datum/fixture::read_2999\" = list(0, list(1, 0, 2999))\n\t)"));
        assert_eq!(text.matches(" = list(0, list(1, 0,").count(), 3000);
    }
}
