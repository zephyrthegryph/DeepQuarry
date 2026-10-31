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
//! The rows come from the closed walk (`ReadsEngine::closed`): engine bodies are entered and a virtual call is the union of its overrides.
//! `rank` is the evaluation order of the handler's derived reads (0 = reads only base state).

use std::collections::{BTreeMap, BTreeSet};

use crate::sem::decls::Decls;
use crate::sem::gen::{GenCx, GenOut, Generator};
use crate::sem::graph::DepGraph;
use crate::sem::reads::{Annotations, ReadKind, ReadsEngine};

use crate::sem::reads::ENGINE_DIRS;

struct Reads;

type Row=crate::reads_policy::Row;

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
                let ann = Annotations::shared(cx.tree, &sem, &decls);
                capability_keys.extend(ann.capkey_accessors.values().cloned());
                let eng = ReadsEngine::new(&sem, &decls, &ann).closed_shared(cx.tree);
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
                // Each handler's closed walk is independent and is the cost of this generator: walk the distinct ones in parallel, then
                // fold them in declaration order (diagnostics keep the order a sequential pass gave them).
                let mut jobs: Vec<usize> = Vec::new();
                {
                    let mut queued = BTreeSet::new();
                    for (i, h) in handlers.iter().enumerate() {
                        let id = format!("{}::{}", h.owner, h.proc);
                        if queued.contains(&id) || sem.proc_ref(&h.owner, &h.proc).is_none() {
                            continue;
                        }
                        queued.insert(id);
                        jobs.push(i);
                    }
                }
                let walked = crate::sem::par_map_deep(&jobs, |&i| eng.analyze_handler_shared(&handlers[i].owner, &handlers[i].proc, handlers[i].ctx.type_path()));
                let mut walked_by_handler: std::collections::HashMap<usize, std::sync::Arc<crate::sem::reads::ReadSet>> = jobs.into_iter().zip(walked).collect();
                for (i, h) in handlers.iter().enumerate() {
                    let id = format!("{}::{}", h.owner, h.proc);
                    if rows.contains_key(&id) {
                        continue;
                    }
                    if sem.proc_ref(&h.owner, &h.proc).is_none() {
                        out.diag(&h.rel, h.line, format!("handler `{}` is not a proc of {}", h.proc, h.owner));
                        continue;
                    }
                    let set = match walked_by_handler.remove(&i) {
                        Some(set) => set,
                        None => eng.analyze_handler_shared(&h.owner, &h.proc, h.ctx.type_path()),
                    };
                    for d in &set.diags {
                        // The closed walk enters the engine's own bodies. What it cannot resolve there (a `vars[]` dispatcher, an unannotated engine
                        // helper, a Verdigris FFI call) is the engine's to declare with PROC_SUMMARY, and is listed by `analyze sem closure`;
                        // it fails a build only where it sits in the handler's own code, not in an override only a virtual call reaches.
                        if matches!(d.rule, "unannotated_global" | "dynamic_read") && !d.closed_only && !ENGINE_DIRS.iter().any(|prefix| d.rel.starts_with(prefix)) {
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

        let mut rendered=crate::sparse_slots_policy::Output::default();
        crate::reads_policy::generate(&rows,&ranks,&capability_keys,&defines,&crate::sem::gen::test_only_types(cx.tree),&mut rendered);
        append_policy_output(out,rendered);
    }
}

/// Actual implicit output definitions need lookup metadata even without a declared callback.
/// Ordinary output reads/diagnostics stay with their existing generators; only declared
/// lookup descriptors and structured lookup-contract failures are handled here.
fn extend_lookup_outputs(rows: &mut BTreeMap<String, Vec<Row>>, sem: &crate::sem::Sem, eng: &ReadsEngine<'_>, out: &mut GenOut) {
    let outputs = crate::sem::procs::proc_defs(sem, &["draw", "ui_data", "tgui_data", "hidden_verbs", "push_to_rust", "should_run"]);
    let mut seen = BTreeSet::new();
    for output in outputs {
        if output.owner == "/" || ENGINE_DIRS.iter().any(|prefix| output.rel.starts_with(prefix)) { continue; }
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

pub(crate) use crate::reads_policy::canonical_read_key;
#[cfg(test)]use crate::reads_policy::{read_table_initializer,literal_read_name,lookup_descriptor};
/// Both writer APIs emit whole newline-terminated lines; retain every byte,
/// including embedded blank lines/CR, and every ordered diagnostic field.
fn append_policy_output(out:&mut GenOut,rendered:crate::sparse_slots_policy::Output){for line in rendered.body.split_terminator('\n'){out.line(line);}for diagnostic in rendered.diags{out.diag(&diagnostic.rel,diagnostic.line,diagnostic.msg);}}
#[cfg(test)]fn emit_lookup_methods(out:&mut GenOut,rows:&BTreeMap<String,Vec<Row>>,tests:&BTreeSet<String>){let mut rendered=crate::sparse_slots_policy::Output::default();crate::reads_policy::emit_lookup_methods(&mut rendered,rows,tests);append_policy_output(out,rendered);}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(Reads));
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

#[cfg(test)]#[test]fn legacy_read_policy_output_adapter_keeps_body_blank_lines_and_all_ordered_diagnostics(){let mut policy=crate::sparse_slots_policy::Output::default();policy.body="\nfirst\n\nsecond\r\n".into();policy.diag("code/b.dm",9,"first");policy.diag("code/a.dm",0,"second");let mut old=GenOut::default();old.line("prefix");append_policy_output(&mut old,policy);assert_eq!(old.text(),"prefix\n\nfirst\n\nsecond\r\n");assert_eq!(old.diags.iter().map(|d|(d.rel.as_str(),d.line,d.msg.as_str())).collect::<Vec<_>>(),[("code/b.dm",9,"first"),("code/a.dm",0,"second")]);}
