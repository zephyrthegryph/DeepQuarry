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
use crate::sem::reads::{Annotations, LookupArgument, LookupRead, ReadKind, ReadsEngine};

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

    fn stage(&self) -> u8 {
        1
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
                for marker in decls.markers_named("READ_LOOKUP") {
                    let name = marker.args.first().and_then(|p| p.strip_prefix("/proc/"));
                    let Some(decl) = name.and_then(|n| ann.lookups.get(n)) else {
                        out.diag(&marker.rel, marker.line, "READ_LOOKUP needs a global proc, registry/key GLOBAL_PROC_REFs, positive argument index and result=/datum/type");
                        continue;
                    };
                    for proc_name in [decl.registry.as_str(), decl.identity_key.as_str(), name.unwrap()] {
                        if sem.global_proc(proc_name).is_none() {
                            out.diag(&marker.rel, marker.line, format!("READ_LOOKUP provider {proc_name} does not exist"));
                            continue;
                        }
                        let body = ReadsEngine::new(&sem, &decls, &ann).analyze("/", proc_name);
                        for effect in body.effects {
                            out.diag(&marker.rel, marker.line, format!("READ_LOOKUP provider {proc_name} is not pure: {} {}", effect.kind, effect.name));
                        }
                    }
                }
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
        let mut entries: Vec<String> = Vec::new();
        for (id, reads) in &rows {
            // A handler runs after every derived value it reads: one more than the deepest.
            let rank = reads.iter().filter(|r| r.1 == ReadKind::Var).filter_map(|r| ranks.get(&format!("{}::{}", r.4, r.2)).map(|k| k + 1)).max().unwrap_or(0);
            let mut entry = format!("\t\t\"{}\" = list({}", id, rank);
            for (root, kind, var, hops, _owner) in reads {
                let kind_id = match kind {
                    ReadKind::Var => 0,
                    ReadKind::Accessor => 1,
                    ReadKind::Native => 2,
                    ReadKind::System => 3,
                    ReadKind::Lookup(_) => 4,
                };
                let mut parts = vec![roots.id(root).to_string(), kind_id.to_string(), names.id(&canonical_read_key(kind, var, &capability_keys, &defines)).to_string()];
                for h in hops {
                    parts.push(names.id(h).to_string());
                }
                entry.push_str(&format!(",\n\t\tlist({})", parts.join(", ")));
            }
            entry.push(')');
            entries.push(entry);
        }
        out.line("#define READ_ROOT_HOLDER 1");
        out.line("#define READ_ROOT_ACTOR 2");
        out.line("#define READ_ROOT_HELD 3");
        out.line("#define READ_ROOT_TARGET 4");
        out.line("#define READ_KIND_VAR 0");
        out.line("#define READ_KIND_ACCESSOR 1");
        out.line("#define READ_KIND_NATIVE 2");
        out.line("#define READ_KIND_SYSTEM 3");
        out.line("#define READ_KIND_LOOKUP 4");
        out.blank();
        out.doc("Every interned name a read uses (a var, a relation hop, an accessor key). Id = index in this list.");
        out.line("GLOBAL_LIST_INIT(generated_read_names, list(");
        for (i, n) in names.names.iter().enumerate() {
            out.line(format!("\t\"{}\"{}", literal_read_name(n), if i + 1 < names.names.len() { "," } else { "" }));
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
        out.doc("Chunked read rows; one global initializer assembles the complete table.");
        out.line(read_table_initializer(&entries));
        emit_lookup_methods(out, &rows, &crate::sem::gen::test_only_types(cx.tree));
    }
}

fn dm_text(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
}
fn lookup_descriptor(read: &LookupRead) -> String {
    let (root, path, literal, is_literal) = match &read.binding.argument {
        LookupArgument::Literal(value) => ("holder".to_string(), Vec::new(), value.clone(), "TRUE"),
        LookupArgument::Path { root, path } => (root.clone(), path.clone(), "null".to_string(), "FALSE"),
    };
    format!("list(\"key\" = {}, \"registry\" = GLOBAL_PROC_REF({}), \"identity_key\" = GLOBAL_PROC_REF({}), \"lookup\" = GLOBAL_PROC_REF({}), \"root\" = {}, \"path\" = list({}), \"literal\" = {}, \"is_literal\" = {}, \"field\" = {})",
        dm_text(&read.key()), read.binding.registry, read.binding.identity_key, read.binding.lookup,
        dm_text(&root), path.iter().map(|p| dm_text(p)).collect::<Vec<_>>().join(", "), literal, is_literal, dm_text(&read.field))
}
fn emit_lookup_methods(out: &mut GenOut, rows: &BTreeMap<String, Vec<Row>>, test_types: &BTreeSet<String>) {
    let mut owners: BTreeMap<String, BTreeMap<String, Vec<String>>> = BTreeMap::new();
    for (id, reads) in rows {
        let Some((owner, name)) = id.rsplit_once("::") else { continue };
        let descriptors: Vec<_> = reads.iter().filter_map(|r| match &r.1 {
            ReadKind::Lookup(read) => Some(lookup_descriptor(read)),
            _ => None,
        }).collect();
        if !descriptors.is_empty() {
            owners.entry(owner.to_string()).or_default().insert(name.to_string(), descriptors);
        }
    }
    for (owner, methods) in owners {
        let test_only = test_types.contains(&owner);
        if test_only { out.line(crate::sem::gen::TEST_GUARD); }
        out.blank();
        out.line(format!("{owner}/generated_lookup_reads(proc_name = null)"));
        out.line("\tif(isnull(proc_name))");
        out.line("\t\t. = ..()");
        let all: Vec<_> = methods.values().flatten().cloned().collect();
        out.line(format!("\t\t. += list({})", all.join(", ")));
        out.line("\t\treturn");
        out.line("\tswitch(proc_name)");
        for (name, descriptors) in &methods {
            out.line(format!("\t\tif({})", dm_text(&name)));
            out.line(format!("\t\t\treturn list({})", descriptors.join(", ")));
        }
        out.line("\treturn ..()");
        let mut output_entries = Vec::new();
        for (name, descriptors) in &methods {
            let call = match name.as_str() {
                "draw" | "hidden_verbs" => Some("drawn_from"),
                "ui_data" | "tgui_data" => Some("ui_from"),
                "push_to_rust" => Some("rust_push"),
                "should_run" => Some("runs_while"),
                _ => None,
            };
            if let Some(call) = call {
                let keys: Vec<_> = rows[&format!("{owner}::{name}")].iter().filter_map(|r| match &r.1 { ReadKind::Lookup(read) => Some(dm_text(&read.key())), _ => None }).collect();
                output_entries.push(format!("\t. += {call}({})", keys.join(", ")));
            } else if let Some(var) = name.strip_prefix("derive_") {
                let keys: Vec<_> = rows[&format!("{owner}::{name}")].iter().filter_map(|r| match &r.1 { ReadKind::Lookup(read) => Some(dm_text(&read.key())), _ => None }).collect();
                output_entries.push(format!("\t. += derive(nameof({var}), {})", keys.join(", ")));
            }
            let _ = descriptors;
        }
        if !output_entries.is_empty() {
            out.line(format!("{owner}/generated_lookup_output_reads()"));
            out.line("\t. = ..()");
            for line in output_entries { out.line(line); }
        }
        if test_only { out.line("#endif"); }
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

/// Keep large lists outside macro arguments and limit each literal to the master's 300-row bound.
fn read_table_initializer(entries: &[String]) -> String {
    let chunks: Vec<_> = entries.chunks(300).collect();
    let mut lines = Vec::new();
    for (i, chunk) in chunks.iter().enumerate() {
        lines.push(format!("/proc/generated_reads_chunk_{i}()"));
        lines.push("\treturn list(".to_string());
        lines.push(chunk.join(",\n"));
        lines.push("\t)".to_string());
    }
    lines.push("/proc/generated_reads_assemble()".to_string());
    lines.push("\t. = list()".to_string());
    lines.push("\tvar/list/chunks = list(".to_string());
    for i in 0..chunks.len() {
        lines.push(format!("\t\tgenerated_reads_chunk_{}(){}", i, if i + 1 < chunks.len() { "," } else { "" }));
    }
    lines.push("\t)".to_string());
    lines.push("\tfor(var/list/chunk as anything in chunks)".to_string());
    lines.push("\t\tfor(var/key in chunk)".to_string());
    lines.push("\t\t\t.[key] = chunk[key]".to_string());
    lines.push("GLOBAL_LIST_INIT(generated_reads_table, generated_reads_assemble())".to_string());
    lines.join("\n")
}

// A list-hop suffix is literal metadata, unlike intentionally interpolated capability keys.
fn literal_read_name(name: &str) -> String {
    match name.strip_suffix("[]") {
        Some(base) => format!("{}\\[\\]", base),
        None => name.to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::{canonical_read_key, read_table_initializer, literal_read_name};
    use crate::sem::reads::ReadKind;
    use std::collections::BTreeSet;

    #[test]
    fn list_hop_metadata_is_literal_without_breaking_interpolated_accessors() {
        assert_eq!(literal_read_name("members[]"), "members\\[\\]");
        assert_eq!(literal_read_name("members"), "members");
        // These canonical accessor keys intentionally interpolate a declared key constant.
        assert_eq!(literal_read_name("capkey:[EMAG_EMAGGED]"), "capkey:[EMAG_EMAGGED]");
        assert_eq!(literal_read_name("[OP_KEY_CAP_STATE]"), "[OP_KEY_CAP_STATE]");
    }

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
    fn large_read_table_has_bounded_chunks_and_one_real_initializer() {
        let rows = (0..3000).map(|i| format!("\t\t\"/datum/fixture::read_{i}\" = list(0, list(1, 0, {i}))")).collect::<Vec<_>>();
        assert!(rows.iter().map(String::len).sum::<usize>() > 65536);
        let text = read_table_initializer(&rows);
        assert_eq!(text.matches("/proc/generated_reads_chunk_").count(), 10);
        assert_eq!(text.matches("GLOBAL_LIST_INIT(generated_reads_table,").count(), 1);
        assert!(text.contains("GLOBAL_LIST_INIT(generated_reads_table, generated_reads_assemble())"));
        assert!(!text.contains("GLOBAL_LIST(generated_reads_table)"));
        assert_eq!(text.matches(" = list(0, list(1, 0,").count(), 3000);
        for chunk in text.split("/proc/generated_reads_chunk_").skip(1) {
            assert_eq!(chunk.matches(" = list(0, list(1, 0,").count(), 300);
        }
    }
    #[test]
    fn lookup_descriptor_preserves_actual_root_literal_and_registry_identity_contract() {
        use crate::sem::reads::{LookupArgument, LookupBound, LookupRead};
        let make = |argument| LookupRead { binding: LookupBound { registry: "grid_registry".into(), identity_key: "grid_identity".into(), lookup: "grid_lookup".into(), argument }, field: "load".into() };
        for root in ["holder", "actor", "target", "held", "authority"] {
            let read = make(LookupArgument::Path { root: root.into(), path: vec!["terminal".into(), "power_region".into()] });
            let text = super::lookup_descriptor(&read);
            assert!(text.contains(&format!("\"root\" = \"{root}\"")));
            assert!(text.contains("\"path\" = list(\"terminal\", \"power_region\")"));
            assert!(text.contains("\"registry\" = GLOBAL_PROC_REF(grid_registry)"));
            assert!(text.contains("\"identity_key\" = GLOBAL_PROC_REF(grid_identity)"));
            assert!(text.contains("\"is_literal\" = FALSE"));
            assert!(!read.key().contains('.') && !read.key().contains(':'));
            assert_eq!(read.key(), read.clone().key());
        }
        let literal = make(LookupArgument::Literal("-5".into()));
        assert!(super::lookup_descriptor(&literal).contains("\"literal\" = -5, \"is_literal\" = TRUE"));
        let another = make(LookupArgument::Literal("-6".into()));
        assert_ne!(literal.key(), another.key(), "distinct literal grids must not share a computed key");
        let mut field = literal.clone();
        field.field = "avail".into();
        assert_ne!(literal.key(), field.key(), "supply and load are distinct actual producers");
    }

}
