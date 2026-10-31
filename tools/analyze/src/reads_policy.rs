//! Exact original reads table/lookup renderer over source-free emission rows.
use std::collections::{BTreeMap,BTreeSet};
use crate::reactive_read_facts::{ReadKind,LookupArgument,LookupRead};
use crate::sparse_slots_policy::Output as GenOut;
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
pub(crate) type Row = (String, ReadKind, String, Vec<String>, String);


pub(crate) fn generate(rows:&BTreeMap<String,Vec<Row>>,ranks:&BTreeMap<String,u32>,capability_keys:&BTreeSet<String>,defines:&BTreeSet<String>,test_types:&BTreeSet<String>,out:&mut GenOut){
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
pub(crate) fn lookup_descriptor(read: &LookupRead) -> String {
    let (root, path, literal, is_literal) = match &read.binding.argument {
        LookupArgument::Literal(value) => ("holder".to_string(), Vec::new(), value.clone(), "TRUE"),
        LookupArgument::Path { root, path } => (root.clone(), path.clone(), "null".to_string(), "FALSE"),
    };
    format!("list(\"key\" = {}, \"registry\" = GLOBAL_PROC_REF({}), \"identity_key\" = GLOBAL_PROC_REF({}), \"lookup\" = GLOBAL_PROC_REF({}), \"root\" = {}, \"path\" = list({}), \"literal\" = {}, \"is_literal\" = {}, \"field\" = {})",
        dm_text(&read.key()), read.binding.registry, read.binding.identity_key, read.binding.lookup,
        dm_text(&root), path.iter().map(|p| dm_text(p)).collect::<Vec<_>>().join(", "), literal, is_literal, dm_text(&read.field))
}
pub(crate) fn emit_lookup_methods(out: &mut GenOut, rows: &BTreeMap<String, Vec<Row>>, test_types: &BTreeSet<String>) {
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
        if test_only { out.line(crate::generator_test_scope::TEST_GUARD); }
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
pub(crate) fn canonical_read_key(kind:&ReadKind,name:&str,capability_keys:&BTreeSet<String>,defines:&BTreeSet<String>)->String{match crate::reactive_read_key_policy::canonical(&mut crate::key_policy_control::Compatibility,kind,name,capability_keys,defines){Ok(value)=>value,Err(never)=>match never{}}}

/// Keep large lists outside macro arguments and limit each literal to the master's 300-row bound.
pub(crate) fn read_table_initializer(entries: &[String]) -> String {
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
pub(crate) fn literal_read_name(name: &str) -> String {
    match name.strip_suffix("[]") {
        Some(base) => format!("{}\\[\\]", base),
        None => name.to_owned(),
    }
}

#[cfg(feature="native-policy")]
pub(crate) fn generate_admitted(rows:&BTreeMap<String,Vec<Row>>,ranks:&BTreeMap<String,u32>,capability_keys:&BTreeSet<String>,defines:&BTreeSet<String>,test_types:&BTreeSet<String>,budget:&std::sync::Arc<crate::captured_generator_budget::Budget>,checkpoint:&dyn Fn()->std::io::Result<()>)->std::io::Result<GenOut>{
 checkpoint()?;let mut width=0usize;let mut units=64usize;
 let overflow=||{budget.deny();std::io::Error::new(std::io::ErrorKind::OutOfMemory,"reads renderer input width overflow")};
 let mut add=|text:&str|->std::io::Result<()>{width=width.checked_add(text.len()).ok_or_else(&overflow)?;units=units.checked_add(1).ok_or_else(&overflow)?;Ok(())};
 for(id,reads)in rows{checkpoint()?;add(id)?;for(root,kind,name,hops,owner)in reads{add(root)?;add(name)?;add(owner)?;for hop in hops{add(hop)?;}if let ReadKind::Lookup(read)=kind{add(&read.field)?;add(&read.binding.registry)?;add(&read.binding.identity_key)?;add(&read.binding.lookup)?;match &read.binding.argument{LookupArgument::Literal(value)=>add(value)?,LookupArgument::Path{root,path}=>{add(root)?;for part in path{add(part)?}}}}}}
 // Input strings expand by at most2 in DM quotes and at most10 in the
 // transient stable Debug lookup key.32x covers that key, quote/clone/join,
 // interned-name maps and three descriptor/entry overlaps. Per logical name
 // coordination covers row/Vec/BTree metadata; standard allocator/control
 // geometry remains a baseline, not a total-RSS qualification.
 let reserve=width.checked_mul(32).and_then(|n|units.checked_mul(1024).and_then(|m|n.checked_add(m))).ok_or_else(&overflow)?;
 budget.charge(reserve).map_err(|message|std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))?;
 let mut out=GenOut::captured(budget.clone());generate(rows,ranks,capability_keys,defines,test_types,&mut out);checkpoint()?;
 if budget.denied(){return Err(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"reads renderer admission refused"))}Ok(out)
}

#[cfg(test)]mod tests{
 use super::*;
 mod original{include!("reads_policy_reference.rs");}
 fn fixture()->(BTreeMap<String,Vec<Row>>,BTreeMap<String,u32>,BTreeSet<String>,BTreeSet<String>,BTreeSet<String>){
  let mut rows=BTreeMap::new();for i in 0..601{rows.insert(format!("/datum/unit::read{i:04}"),vec![("holder".into(),ReadKind::Var,"parts[]".into(),vec!["nested[]".into()],"/datum/unit".into())]);}
  rows.insert("/datum/test_only::draw".into(),vec![("actor".into(),ReadKind::Accessor,"CAP_KEY".into(),Vec::new(),String::new()),("holder".into(),ReadKind::Lookup(Box::new(LookupRead{binding:crate::reactive_read_facts::LookupBound{registry:"registry".into(),identity_key:"identity".into(),lookup:"lookup".into(),argument:LookupArgument::Path{root:"actor".into(),path:vec!["rack".into(),"cells".into()]}},field:"charge".into()})),"charge".into(),Vec::new(),"/datum/unit".into())]);
  (rows,BTreeMap::from([("/datum/unit::parts[]".into(),2)]),BTreeSet::from(["CAP_KEY".into()]),BTreeSet::from(["CAP_KEY".into()]),BTreeSet::from(["/datum/test_only".into()]))
 }
 #[test]fn read_table_whole_original_template_matches_chunks_lookups_ranks_and_test_guards(){let(rows,ranks,keys,defines,tests)=fixture();let mut old=GenOut::default();original::generate(&rows,&ranks,&keys,&defines,&tests,&mut old);let mut current=GenOut::default();generate(&rows,&ranks,&keys,&defines,&tests,&mut current);assert_eq!(current,old);assert!(current.body.contains("generated_reads_chunk_2"));assert!(current.body.contains("generated_lookup_reads"));assert!(current.body.contains(crate::generator_test_scope::TEST_GUARD));assert!(current.body.contains("parts\\[\\]"));assert!(current.body.contains("[CAP_KEY]"));}
 #[cfg(feature="native-policy")]
 #[test]fn read_table_admitted_render_preserves_bytes_and_actual_io_quota_retry(){let(rows,ranks,keys,defines,tests)=fixture();let fixed=std::mem::size_of::<crate::captured_generator_budget::Budget>()+2*std::mem::size_of::<usize>();let tiny=crate::captured_generator_budget::Budget::new(fixed).unwrap();assert_eq!(generate_admitted(&rows,&ranks,&keys,&defines,&tests,&tiny,&||Ok(())).unwrap_err().kind(),std::io::ErrorKind::OutOfMemory);assert!(tiny.denied());let healthy=crate::captured_generator_budget::Budget::new(32*1024*1024).unwrap();let mut old=GenOut::default();original::generate(&rows,&ranks,&keys,&defines,&tests,&mut old);assert_eq!(generate_admitted(&rows,&ranks,&keys,&defines,&tests,&healthy,&||Ok(())).unwrap(),old);let error=generate_admitted(&rows,&ranks,&keys,&defines,&tests,&healthy,&||Err(std::io::Error::from_raw_os_error(1450))).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));}

 #[test]fn independent_reference_is_exact_frozen_template_projection(){
 let frozen=include_str!("read_emitter_frozen_original.rs");let reference=include_str!("reads_policy_reference.rs");
 fn piece<'a>(s:&'a str,start:&str,end:&str)->&'a str{let at=s.find(start).unwrap();let rest=&s[at..];&rest[..rest.find(end).unwrap()]}
 assert_eq!(piece(frozen,"struct Interner", "impl Generator for Reads").trim(),piece(reference,"struct Interner","pub fn generate").trim());
 let old=piece(frozen,"        let mut names = Interner", "\n    }\n}").replace("in &rows", "in rows").replace("&crate::sem::gen::test_only_types(cx.tree)", "test_types").replace("crate::sem::gen::TEST_GUARD","TEST_GUARD");
 assert_eq!(old.trim(),piece(reference,"        let mut names = Interner","\n}\n").trim());
 let old=&frozen[frozen.find("fn dm_text").unwrap()..frozen.find("#[cfg(test)]").unwrap()];let old=old.replace("pub fn register(reg: &mut Vec<Box<dyn Generator>>) {\n    reg.push(Box::new(Reads));\n}\n\n", "").replace("crate::sem::gen::TEST_GUARD","TEST_GUARD").replace("pub(crate) fn", "fn");let actual=&reference[reference.find("fn dm_text").unwrap()..];assert_eq!(old.trim(),actual.replace("pub(crate) fn","fn").trim());
 }
}
