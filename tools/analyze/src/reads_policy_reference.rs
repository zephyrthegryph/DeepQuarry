// Independent original template projection for tests; no shared renderer calls.
use std::collections::{BTreeMap,BTreeSet};
use crate::reactive_read_facts::{ReadKind,LookupArgument,LookupRead};
use crate::sparse_slots_policy::Output as GenOut;
const TEST_GUARD:&str="#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)";
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


pub fn generate(rows:&BTreeMap<String,Vec<Row>>,ranks:&BTreeMap<String,u32>,capability_keys:&BTreeSet<String>,defines:&BTreeSet<String>,test_types:&BTreeSet<String>,out:&mut GenOut){
        let mut names = Interner { names: Vec::new(), index: BTreeMap::new() };
        let mut roots = Interner { names: Vec::new(), index: BTreeMap::new() };
        // The fixed roots keep their ids across builds.
        for r in ["holder", "actor", "held", "target"] {
            roots.id(r);
        }
        let mut entries: Vec<String> = Vec::new();
        for (id, reads) in rows {
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
        emit_lookup_methods(out, &rows, test_types);
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
        if test_only { out.line(TEST_GUARD); }
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


/// A declared capability accessor reads the actual numeric key published by capability_key_changed.
/// Keep its define as DM interpolation so the generated name uses the authoritative compile-time ID.
fn canonical_read_key(kind:&ReadKind,name:&str,capability_keys:&BTreeSet<String>,defines:&BTreeSet<String>)->String{match crate::reactive_read_key_policy::canonical(&mut crate::key_policy_control::Compatibility,kind,name,capability_keys,defines){Ok(value)=>value,Err(never)=>match never{}}}

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
