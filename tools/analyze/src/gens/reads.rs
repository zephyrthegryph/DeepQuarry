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
        if !handlers.is_empty() || cx.markers("READ_LOOKUP").next().is_some() {
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
                extend_lookup_outputs(&mut rows, &sem, &eng, out);
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

/// Actual implicit output definitions need lookup metadata even without a declared callback.
/// Ordinary output reads/diagnostics stay with their existing generators; only declared
/// lookup descriptors and structured lookup-contract failures are handled here.
fn extend_lookup_outputs(rows: &mut BTreeMap<String, Vec<Row>>, sem: &crate::sem::Sem, eng: &ReadsEngine<'_>, out: &mut GenOut) {
    let outputs = crate::sem::procs::proc_defs(sem, &["draw", "ui_data", "tgui_data", "hidden_verbs", "push_to_rust", "should_run"]);
    let mut seen = BTreeSet::new();
    for output in outputs {
        if output.owner == "/" || OPAQUE.iter().any(|prefix| output.rel.starts_with(prefix)) { continue; }
        let id = format!("{}::{}", output.owner, output.name);
        if !seen.insert(id.clone()) || rows.contains_key(&id) { continue; }
        let set = eng.analyze_handler(&output.owner, &output.name, "/datum/act/eval");
        for diagnostic in &set.lookup_diags {
            out.diag(&diagnostic.rel, diagnostic.line, format!("{}: {}", diagnostic.rule, diagnostic.msg));
        }
        let mut lookups: Vec<Row> = set.reads.iter()
            .filter(|read| matches!(&read.kind, ReadKind::Lookup(_)))
            .map(|read| (read.root.clone(), read.kind.clone(), read.var.clone(), read.hops.clone(), read.owner.clone()))
            .collect();
        if lookups.is_empty() { continue; }
        lookups.sort();
        rows.insert(id, lookups);
    }
}

fn dm_text(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
}
fn lookup_descriptor(read: &LookupRead) -> String {
    let (root, path, literal, is_literal, provider) = match &read.binding.argument {
        LookupArgument::Literal(value) => ("holder".to_string(), Vec::new(), value.clone(), "TRUE", String::new()),
        LookupArgument::Path { root, path } => (root.clone(), path.clone(), "null".to_string(), "FALSE", String::new()),
        LookupArgument::Provider { root, path, owner, proc, keys } => (root.clone(), path.clone(), "null".to_string(), "FALSE", format!(", \"argument_owner\" = {owner}, \"argument_proc\" = TYPE_PROC_REF({owner}, {proc}), \"argument_keys\" = list({})", keys.iter().map(|key| dm_text(key)).collect::<Vec<_>>().join(", "))),
    };
    format!("list(\"key\" = {}, \"registry\" = GLOBAL_PROC_REF({}), \"identity_key\" = GLOBAL_PROC_REF({}), \"lookup\" = GLOBAL_PROC_REF({}), \"root\" = {}, \"path\" = list({}), \"literal\" = {}, \"is_literal\" = {}, \"field\" = {}{})",
        dm_text(&read.key()), read.binding.registry, read.binding.identity_key, read.binding.lookup,
        dm_text(&root), path.iter().map(|p| dm_text(p)).collect::<Vec<_>>().join(", "), literal, is_literal, dm_text(&read.field), provider)
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

    #[test]
    fn lookup_argument_provider_encodes_actual_accessor_and_tracked_receiver_dependencies() {
        use crate::sem::reads::{LookupArgument, LookupBound, LookupRead};
        let read = LookupRead { binding: LookupBound {
            registry: "registry".into(), identity_key: "identity".into(), lookup: "lookup".into(),
            argument: LookupArgument::Provider { root: "holder".into(), path: vec!["mixture".into()],
                owner: "/datum/mixture".into(), proc: "numeric_id".into(), keys: vec!["native_handle".into()] },
        }, field: "pressure".into() };
        let text = super::lookup_descriptor(&read);
        assert!(text.contains("\"path\" = list(\"mixture\")"));
        assert!(text.contains("\"argument_owner\" = /datum/mixture"));
        assert!(text.contains("\"argument_proc\" = TYPE_PROC_REF(/datum/mixture, numeric_id)"));
        assert!(text.contains("\"argument_keys\" = list(\"native_handle\")"));
        assert!(!text.contains("\"path\" = list(\"mixture\", \"native_handle\")"), "the getter must run rather than substitute its raw field");
    }

    #[test]
    fn standalone_and_declared_outputs_get_real_lookup_metadata_and_invalid_contracts_fail() {
        use crate::tree::{SourceFile, Tree};
        use crate::sem::Sem;
        use crate::sem::decls::Decls;
        use crate::sem::reads::{Annotations, ReadsEngine};
        let root = std::env::temp_dir().join(format!("dq-output-lookup-{}", std::process::id()));
        std::fs::create_dir_all(root.join("code/content")).unwrap();
        let source = r#"#define READ_LOOKUP(P,A...)
#define TRACKED(T,V)
/datum/grid
    var/avail = 0
TRACKED(/datum/grid, avail)
READ_LOOKUP(/proc/grid_lookup, registry = GLOBAL_PROC_REF(grid_registry), key = GLOBAL_PROC_REF(grid_key), argument = 1, result = /datum/grid)
/proc/grid_registry()
    return null
/proc/grid_key(id)
    return id
/proc/grid_lookup(id)
    return null
/datum/act/eval
/datum/fixture
    var/grid_id = 1
TRACKED(/datum/fixture, grid_id)
/datum/fixture/proc/ready(datum/act/eval/A)
    var/datum/grid/G = grid_lookup(grid_id)
    return G.avail >= 100
/datum/fixture/proc/draw(datum/act/eval/A)
    var/datum/grid/G = grid_lookup(grid_id)
    return G.avail
/datum/fixture/proc/ui_data(datum/act/eval/A)
    var/datum/grid/G = grid_lookup(grid_id)
    return list("avail" = G.avail)
/datum/standalone
    var/grid_id = 2
TRACKED(/datum/standalone, grid_id)
/datum/standalone/proc/supply()
    var/datum/grid/G = grid_lookup(grid_id)
    return G.avail
/datum/standalone/proc/draw(datum/act/eval/A)
    return supply()
/datum/standalone/proc/ui_data(datum/act/eval/A)
    return list("avail" = supply())
/datum/invalid_output
    var/grid_id = 3
TRACKED(/datum/invalid_output, grid_id)
/datum/invalid_output/proc/draw(datum/act/eval/A)
    var/datum/grid/G = grid_lookup(grid_id + 1)
    return G.avail
/proc/unannotated_unrelated_global()
    return 42
/datum/irrelevant/proc/draw()
    return unannotated_unrelated_global()
"#;
        std::fs::write(root.join("code/content/probe.dm"), source).unwrap();
        let mut tree = Tree::from_files(vec![SourceFile::from_text("code/content/probe.dm", source)]);
        tree.root = root.clone();
        let sem = Sem::build(&root, &tree).unwrap();
        let decls = Decls::get(&tree);
        let annotations = Annotations::get(&sem, &decls);
        let eng = ReadsEngine::new(&sem, &decls, &annotations);
        let ready = eng.analyze_handler("/datum/fixture", "ready", "/datum/act/eval");
        let mut rows = std::collections::BTreeMap::new();
        rows.insert("/datum/fixture::ready".to_string(), ready.reads.iter().map(|read| (read.root.clone(),read.kind.clone(),read.var.clone(),read.hops.clone(),read.owner.clone())).collect());
        let mut out = crate::sem::gen::GenOut::default();
        super::extend_lookup_outputs(&mut rows, &sem, &eng, &mut out);
        for name in ["draw", "ui_data"] {
            assert!(rows[&format!("/datum/fixture::{name}")].iter().any(|read| matches!(&read.1, ReadKind::Lookup(bound) if bound.field == "avail")));
        }
        assert!(!rows.contains_key("/datum/irrelevant::draw"), "unrelated output types must not trigger a global scan");
        for name in ["draw", "ui_data"] {
            assert!(rows[&format!("/datum/standalone::{name}")].iter().any(|read| matches!(&read.1, ReadKind::Lookup(bound) if bound.field == "avail")));
        }
        assert!(out.diags.iter().any(|diagnostic| diagnostic.msg.contains("lookup grid_lookup argument")), "invalid standalone lookup argument must fail generation");
        assert!(!out.diags.iter().any(|diagnostic| diagnostic.msg.contains("unannotated_unrelated_global")), "ordinary unrelated output diagnostics remain outside this generator");
        super::emit_lookup_methods(&mut out, &rows, &BTreeSet::new());
        assert!(out.text().contains("/datum/fixture/generated_lookup_output_reads()"));
        assert!(out.text().contains("/datum/standalone/generated_lookup_output_reads()"));
        assert!(out.text().contains(". += drawn_from(\"lookup_read_"));
        assert!(out.text().contains(". += ui_from(\"lookup_read_"));
        std::fs::remove_dir_all(root).unwrap();
    }

}
