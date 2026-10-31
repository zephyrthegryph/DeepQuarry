//! Exact plans emitter/unique reader-key policy shared by original producers.
//! Borrowed rows are projections, NOT native source or evaluation authority.
use std::collections::{BTreeMap,BTreeSet,HashMap,HashSet};
use crate::{reactive_facts::DepsAnalysis,tree::SourceFile,key_policy_control as kc};
pub use crate::sparse_slots_policy::Output;
const CAP_ENTRIES:&str="CAP_ENTRIES";
pub struct MarkerRow<'a>{pub name:&'a str,pub args:&'a [String],pub body:&'a str}
pub struct ReaderProc<'a>{pub owner:&'a str,pub name:&'a str,pub source:&'a str,pub header:u32}
pub struct PlansInput<'a>{
 pub analysis:&'a DepsAnalysis,
 pub markers:&'a [MarkerRow<'a>],
 pub defines:&'a HashSet<String>,
 pub tracked:&'a HashMap<String,HashSet<String>>,
 pub output_defining_owners:&'a [&'a str],
 pub reader_procs:&'a [ReaderProc<'a>],
 pub files:&'a [&'a SourceFile],
}
/// Readonly policy inputs shared by owned/frozen dependency result renderers.
/// The source-bound caller supplies genuine marker/procedure/file loans.
pub(crate) struct MetadataInput<'a>{
 pub markers:&'a[MarkerRow<'a>],pub defines:&'a HashSet<String>,pub tracked:&'a HashMap<String,HashSet<String>>,
 pub output_defining_owners:&'a[&'a str],pub reader_procs:&'a[ReaderProc<'a>],pub files:&'a[&'a SourceFile],
}
pub(crate) fn quote(s: &str) -> String {
    format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\"").replace('[', "\\["))
}

/// A var name that can be a `KEY_<name>` define.
pub(crate) fn key_ident(s: &str) -> bool {
    !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') && !s.starts_with(|c: char| c.is_ascii_digit())
}

fn emit_table(out: &mut Output, name: &str, rows: &[(String, String)]) {
    for (n, chunk) in rows.chunks(300).enumerate() {
        out.line_fmt(format_args!("/proc/{}_chunk_{}()", name, n));
        out.line("\t. = list()");
        for (k, v) in chunk {
            out.line_fmt(format_args!("\t.[{}] = {}", k, v));
        }
    }
    out.line_fmt(format_args!("/proc/{}_build()", name));
    out.line("\t. = list()");
    for n in 0..rows.chunks(300).count() {
        out.line_fmt(format_args!("\tvar/list/c{} = {}_chunk_{}()", n, name, n));
        out.line_fmt(format_args!("\tfor(var/k in c{})", n));
        out.line_fmt(format_args!("\t\t.[k] = c{}[k]", n));
    }
    out.line_fmt(format_args!("GLOBAL_LIST_INIT({}, {}_build())", name, name));
}

pub fn generate(input:&PlansInput<'_>,out:&mut Output){
 let metadata=MetadataInput{markers:input.markers,defines:input.defines,tracked:input.tracked,output_defining_owners:input.output_defining_owners,reader_procs:input.reader_procs,files:input.files};
 generate_with_analysis(&metadata,crate::reactive_dependency_view::Analysis::Owned(input.analysis),out)
}
pub(crate) fn generate_with_analysis(input:&MetadataInput<'_>,an:crate::reactive_dependency_view::Analysis<'_>,out:&mut Output){
 let metadata=match collect_metadata(input,&mut kc::Compatibility){Ok(v)=>v,Err(e)=>match e{}};generate_prepared(an,&metadata,out)
}
pub(crate) fn generate_prepared(an:crate::reactive_dependency_view::Analysis<'_>,metadata:&PreparedMetadata,out:&mut Output){
        // Per type: var -> PLAN bits as DM text.
        let mut plans: BTreeMap<&str, BTreeMap<String, BTreeSet<&str>>> = BTreeMap::new();
        let mut names: BTreeSet<String> = BTreeSet::new();
        for (t, vars) in an.draw_reads() {
            for v in vars {
                plans.entry(t.as_str()).or_default().entry(v.clone()).or_default().insert("PLAN_DRAW");
                names.insert(v.clone());
            }
        }
        for (t, reads) in an.draw_hops() {
            for r in reads {
                plans.entry(t.as_str()).or_default().entry(r.clone()).or_default().insert("PLAN_DRAW_HOP");
                if let Some((_, v)) = r.rsplit_once('.') {
                    names.insert(v.to_string());
                }
            }
        }
        for (t, links) in an.draw_links() {
            for v in links {
                plans.entry(t.as_str()).or_default().entry(v.clone()).or_default().insert("PLAN_DRAW");
                names.insert(v.clone());
            }
        }
        let mut verbs: BTreeMap<&str, BTreeMap<&str, crate::reactive_dependency_view::Names<'_>>> = BTreeMap::new();
        for (id, (vars, _)) in an.verb_reads() {
            if let Some((t, proc_name)) = id.rsplit_once("::") {
                verbs.entry(proc_name).or_default().insert(t, vars);
                for v in vars {
                    names.insert(v.clone());
                }
            }
        }
        for (_, v) in an.reads() {
            names.insert(v.clone());
        }
        let names: Vec<String> = names.into_iter().filter(|n| key_ident(n)).collect();
        out.doc("The change graph's keys (doc/rewrite/proposals/change_graph.md section 2): one int per var name a plan or a reactive read names,");
        out.doc("numbered by sorted name. Hand code writes CGK_<name> (CGK: a KEY_ prefix is taken by other defines), never the int.");
        for (i, n) in names.iter().enumerate() {
            out.line_fmt(format_args!("#define CGK_{} {}", n, i + 1));
        }
        out.line_fmt(format_args!("#define CGK_BUILD_MAX {}", names.len()));
        out.blank();
        out.doc("id -> key name (logs and runtime interning, code/engine/change/plan.dm).");
        out.line("/proc/generated_key_names_build()");
        out.line("\t. = list()");
        for n in &names {
            out.line_fmt(format_args!("\t. += {}", quote(n)));
        }
        out.line("GLOBAL_LIST_INIT(generated_key_names, generated_key_names_build())");
        out.blank();
        out.doc("\"<type>\" -> list(\"<var>\" or \"<hop>.<var>\" = PLAN_* bits): what the type's own draw() (and the parent draws it calls) reads.");
        out.doc("A type with no row inherits the nearest ancestor's (plan_of(), code/engine/change/plan.dm).");
        let rows: Vec<(String, String)> = plans
            .iter()
            .map(|(t, vars)| {
                let body = vars
                    .iter()
                    .map(|(v, bits)| format!("{} = {}", quote(v), bits.iter().copied().collect::<Vec<_>>().join("|")))
                    .collect::<Vec<_>>()
                    .join(", ");
                (quote(t), format!("list({})", body))
            })
            .collect();
        emit_table(out, "generated_plans", &rows);
        out.blank();
        out.doc("\"<type>\" -> TRUE: a draw() whose reads the walk could not resolve (an untracked or unresolved read). D5: until the walk resolves it, a");
        out.doc("write to such a type marks every output (plan_fallback, counted in GLOB.plan_fallbacks).");
        for (proc_name, by_type) in &verbs {
            out.blank();
            out.doc_fmt(format_args!("\"<type>\" -> list(\"<var>\", ...): what the type's own {}() reads on the holder (a hop chain counts by its first link). It", proc_name));
            out.doc("refreshes on the draw's bit (DEP_DRAW), so a write may skip that bit only when neither the draw nor the verb outputs read the var.");
            let rows: Vec<(String, String)> = by_type
                .iter()
                .map(|(t, vars)| (quote(t), format!("list({})", vars.iter().map(|v| quote(v)).collect::<Vec<_>>().join(", "))))
                .collect();
            emit_table(out, &format!("generated_plan_{}", proc_name), &rows);
        }
        let mut fallbacks: BTreeSet<&str> = BTreeSet::new();
        for (id, (_, unresolved)) in an.verb_reads() {
            if unresolved {
                if let Some((t, _)) = id.rsplit_once("::") {
                    fallbacks.insert(t);
                }
            }
        }
        for id in an.draws() {
            if an.consumer(id).is_some_and(|u| !u.is_empty()) {
                if let Some((t, _)) = id.rsplit_once("::") {
                    fallbacks.insert(t);
                }
            }
        }
        let rows: Vec<(String, String)> = fallbacks.iter().map(|t| (quote(t), "TRUE".to_string())).collect();
        emit_table(out, "generated_plan_fallbacks", &rows);
        out.blank();
        out.doc("\"<capability type>\" -> TRUE: a capability that overrides the legacy draw(holder, look) or hidden_verbs(holder): its reads of the holder");
        out.doc("are not in any plan, so a holder carrying one keeps redrawing on every write (plan_spares_build(), code/engine/change/plan.dm).");
        let mut legacy: BTreeSet<String> = BTreeSet::new();
        for owner in &metadata.legacy_outputs {
            if owner.starts_with("/datum/capability/") { legacy.insert(owner.clone()); }
        }
        let rows: Vec<(String, String)> = legacy.iter().map(|t| (quote(t), "TRUE".to_string())).collect();
        emit_table(out, "generated_capability_legacy_outputs", &rows);
        // The stat layer's input names (step 3 of the change graph, the stats fold): over-inclusive by design. Every nameof() and every
        // `reads = list(...)` item of a declaration block can feed a contribution (entry-building procs such as heat_pump() take them as
        // arguments, which no static rule can follow), so all of them are inputs; the runtime adds the holder reads of the generated handler
        // rows (stat_input_names_build(), code/engine/change/plan.dm). dq_stat_index_oracle proves this covers every key the stat builder
        // registers.
        let mut inputs = metadata.stat_inputs.clone();
        for v in an.stat_reads() {
            if key_ident(v) {
                inputs.insert(quote(v));
            }
        }
        out.blank();
        out.doc("The stat layer's declared input names (raw: a var, \"rel.var\", \"sys:system.var\" or a define naming one), over-inclusive: every nameof()");
        out.doc("and reads = list() item of a declaration block. stat_input_names_build() splits them into GLOB.stat_input_keys.");
        out.line("/proc/generated_stat_input_reads_build()");
        out.line("	. = list()");
        for i in &inputs {
            out.line_fmt(format_args!("	. += {}", i));
        }
        out.line("GLOBAL_LIST_INIT(generated_stat_input_reads, generated_stat_input_reads_build())");
        emit_prepared_reader_keys(metadata, out);
}
/// Reader keys by owner: ("" for every type, or a type path whose subtypes inherit the row, name) -> PLAN_READ_* bits.
pub(crate) type ReaderKeys = BTreeMap<(String, String), u8>;

/// The names a declaration text can make a reader of: every nameof(), every quoted identifier and every key define it names (a stat id: the
/// runtime resolves it to the stat's name). Over-inclusive by design (see `emit_reader_keys`). The names go on `owner` ("" = every type), except
/// the segments after the first of a dotted path ("terminal.charge"): those are read on the far end of a hop, whatever its type, so they go on "".

/// Membership only; no owned table conversion is needed by native callers.
pub(crate) trait Defines{fn contains(&self,name:&str)->bool;}
impl Defines for HashSet<String>{fn contains(&self,name:&str)->bool{HashSet::contains(self,name)}}
impl Defines for BTreeSet<String>{fn contains(&self,name:&str)->bool{BTreeSet::contains(self,name)}}
#[derive(Default)]pub(crate) struct PreparedMetadata{pub(crate) stat_inputs:BTreeSet<String>,pub(crate) reader_keys:ReaderKeys,pub(crate) tracked_names:BTreeSet<String>,pub(crate) legacy_outputs:BTreeSet<String>}
fn quoted<C:kc::Control>(c:&mut C,text:&str)->Result<String,C::Error>{kc::reserve(c,||text.len().checked_mul(8)?.checked_add(128))?;Ok(quote(text))}
fn set_name<C:kc::Control>(c:&mut C,set:&mut BTreeSet<String>,name:String)->Result<(),C::Error>{if !set.contains(&name){kc::reserve(c,||1024usize.checked_add(std::mem::size_of::<String>()))?;set.insert(name);}Ok(())}
fn add_key<C:kc::Control>(c:&mut C,keys:&mut ReaderKeys,owner:&str,name:String,bits:u8)->Result<(),C::Error>{c.checkpoint()?;let owner=kc::own(c,owner)?;kc::reserve(c,||1024usize.checked_add(std::mem::size_of::<((String,String),u8)>()))?;*keys.entry((owner,name)).or_default()|=bits;Ok(())}
pub(crate) fn reader_names(body:&str,defines:&HashSet<String>,owner:&str,into:&mut ReaderKeys,bits:u8){match reader_names_with(body,defines,owner,into,bits,&mut kc::Compatibility){Ok(())=>{},Err(e)=>match e{}}}
pub(crate) fn reader_names_with<C:kc::Control>(body:&str,defines:&impl Defines,owner:&str,into:&mut ReaderKeys,bits:u8,c:&mut C)->Result<(),C::Error>{

    for capture in crate::pat!(r"\bnameof\(\s*(?:[\w/]+::)?(\w+)\s*\)").captures_iter(body) {
        let name=quoted(c,capture.s(1))?;add_key(c,into,owner,name,bits)?;
    }
    for capture in crate::pat!(r#""([A-Za-z_][A-Za-z0-9_.]*)""#).captures_iter(body) {
        for (i, seg) in capture.s(1).split('.').enumerate() {
            if key_ident(seg) {
                let name=quoted(c,seg)?;add_key(c,into,if i==0{owner}else{""},name,bits)?;
            }
        }
    }
    // A handler gate or a key handed as a proc name (every(when = PROC_REF(work_ready))): the table registers the proc's name.
    for capture in crate::pat!(r"\b(?:TYPE_|GLOBAL_)?PROC_REF\(\s*(?:[\w/]+\s*,\s*)?(\w+)\s*\)").captures_iter(body) {
        let name=quoted(c,capture.s(1))?;add_key(c,into,owner,name,bits)?;
    }
    // A key define: a stat id (STAT_*), a hop (HOP_*) or a named key (*_KEY_*, *_KEY): the runtime evaluates it (a text key, or a stat id it
    // resolves to the stat's name). Function-like macros are not keys.
    for capture in crate::pat!(r"\b((?:STAT|HOP)_[A-Z0-9_]+|[A-Z][A-Z0-9]*_KEY(?:_[A-Z0-9_]+)?)\b(\s*\()?").captures_iter(body) {
        if capture.get(2).is_none() && defines.contains(capture.s(1)) {
            let name=kc::own(c,capture.s(1))?;add_key(c,into,owner,name,bits)?;
        }
    }
 c.checkpoint()?;Ok(())
}

/// The owner a declaration's names belong to: its type, or "" (every type) for a capability (its entries and reactions fold into whichever
/// holder carries it) and for the root.
pub(crate) fn reader_owner(t: &str) -> &str {
    let t = t.trim();
    if t.is_empty() || t == "/" || t.starts_with("/datum/capability") || !t.starts_with('/') {
        ""
    } else {
        t
    }
}

/// The body lines of the proc whose header is at `header` (1-based) in `text`: the indented lines that follow it.
pub(crate) fn proc_body(text:&str,header:u32)->String{match proc_body_with(text,header,&mut kc::Compatibility){Ok(v)=>v,Err(e)=>match e{}}}

/// The reader keys of the change graph's plan (step 3d, change_graph.md section 11): which names a static reader of each class may read, so that
/// a tracked write consults the reaction tables, the on_change() hook index and the lifecycle forms only for a name one of them can read.
/// Over-inclusive like the stat inputs: every name a declaration block (hooks, forms, sequences, stats) can name is PLAN_READ_ALL, every name a
/// reactions() or derived() body names is PLAN_READ_REACT, and the runtime adds the names of the generated handler reads (plan_reader_keys_build(),
/// code/engine/change/plan.dm). dq_change_reader_plan_oracle proves it covers every key the runtime tables register.
fn emit_prepared_reader_keys(metadata:&PreparedMetadata,out:&mut Output){
    out.blank();
    out.doc("The change graph's reader keys (step 3d/3e): list(name, PLAN_READ_* bits, owner) rows; owner null = every type, else a type path whose");
    out.doc("subtypes inherit the row (a define is a stat id the runtime resolves to its name). Over-inclusive: a name absent from E's type chain and");
    out.doc("the null rows is read by no reaction, on_change() hook or lifecycle form of E's type.");
    // Chunked: one proc body holds at most 300 rows (the native compiler caps a proc's constant list sizes).
    let rows: Vec<(&(String, String), &u8)> = metadata.reader_keys.iter().collect();
    for (n, chunk) in rows.chunks(300).enumerate() {
        out.line_fmt(format_args!("/proc/generated_reader_keys_chunk_{}()", n));
        out.line("\t. = list()");
        for ((o, k), b) in chunk {
            let owner = if o.is_empty() { "null".to_string() } else { quote(o) };
            out.line_fmt(format_args!("\t. += list(list({}, {}, {}))", k, b, owner));
        }
    }
    out.line("/proc/generated_reader_keys_build()");
    out.line("\t. = list()");
    for n in 0..rows.chunks(300).count() {
        out.line_fmt(format_args!("\t. += generated_reader_keys_chunk_{}()", n));
    }
    // The names the plan answers for: the tracked vars (declared or inferred). Only their writes are narrowed; any other key (an engine key a
    // producer publishes, a hand-written setter's var) keeps every class.
    let rows: Vec<&String> = metadata.tracked_names.iter().collect();
    out.blank();
    out.doc("The tracked var names (declared and inferred): the keys the reader plan narrows (plan_reader_bits(), code/engine/change/plan.dm).");
    for (n, chunk) in rows.chunks(300).enumerate() {
        out.line_fmt(format_args!("/proc/generated_tracked_names_chunk_{}()", n));
        out.line("\t. = list()");
        for v in chunk {
            out.line_fmt(format_args!("\t.[{}] = TRUE", quote(v)));
        }
    }
    out.line("/proc/generated_tracked_names_build()");
    out.line("\t. = list()");
    for n in 0..rows.chunks(300).count() {
        out.line_fmt(format_args!("\t. |= generated_tracked_names_chunk_{}()", n));
    }
}

impl PreparedMetadata{
 pub(crate) fn legacy_output<C:kc::Control>(&mut self,owner:&str,c:&mut C)->Result<(),C::Error>{if owner.starts_with("/datum/capability/"){let name=kc::own(c,owner)?;set_name(c,&mut self.legacy_outputs,name)?;}Ok(())}
 pub(crate) fn tracked<C:kc::Control>(&mut self,name:&str,c:&mut C)->Result<(),C::Error>{if key_ident(name){let name=kc::own(c,name)?;set_name(c,&mut self.tracked_names,name)?;}Ok(())}
 pub(crate) fn marker<C:kc::Control>(&mut self,m:&MarkerRow<'_>,defines:&impl Defines,c:&mut C)->Result<(),C::Error>{c.checkpoint()?;
 if matches!(m.name,"CAPABILITIES"|CAP_ENTRIES|"STAT"){
 for value in crate::raw_marker_policy::marker_named_vars_admitted(m.body,c)?{let name=quoted(c,&value)?;set_name(c,&mut self.stat_inputs,name)?;}
 for capture in crate::pat!(r"\breads\s*=\s*list\(([^)]*)\)").captures_iter(m.body){for item in capture.s(1).split(','){c.checkpoint()?;let item=item.trim();if item.len()>2&&item.starts_with('"')&&item.ends_with('"')&&!item[1..item.len()-1].contains('[')||defines.contains(item){let name=kc::own(c,item)?;set_name(c,&mut self.stat_inputs,name)?;}}}
 }
 if m.name=="STAT"{if let Some(n)=m.args.get(1){let n=n.trim();if key_ident(n){let name=quoted(c,n)?;add_key(c,&mut self.reader_keys,"",name,7)?;}}return Ok(())}
 let owner=if m.name=="CAPABILITIES"{reader_owner(m.args.first().map(String::as_str).unwrap_or(""))}else{""};
 if matches!(m.name,"CAPABILITIES"|"CAPABILITY_DEF"|"CAPABILITY_TYPE"|"STATE_GRAPH"|"ENTRY_PROC"|"RUNTIME_OBSERVE")||m.name==CAP_ENTRIES{reader_names_with(m.body,defines,owner,&mut self.reader_keys,7,c)?;for arg in m.args.iter().skip(if m.name=="CAPABILITIES"{1}else{0}){reader_names_with(arg,defines,owner,&mut self.reader_keys,7,c)?;}}c.checkpoint()?;Ok(())}
 pub(crate) fn reader<C:kc::Control>(&mut self,text:&str,header:u32,owner:&str,name:&str,defines:&impl Defines,c:&mut C)->Result<(),C::Error>{let body=proc_body_slice(text,header);reader_names_with(body,defines,reader_owner(owner),&mut self.reader_keys,if name=="generated_reads"{3}else{1},c)}
 pub(crate) fn file<C:kc::Control>(&mut self,text:&str,defines:&impl Defines,c:&mut C)->Result<(),C::Error>{let mut in_global_proc=false;for line in text.lines(){c.checkpoint()?;if !line.starts_with('\t')&&!line.starts_with(' ')&&!line.trim().is_empty(){in_global_proc=line.starts_with("/proc/");}let t=line.trim_start();if t.contains("seq_step(")||t.starts_with("#define")&&t.contains("nameof("){reader_names_with(t,defines,"",&mut self.reader_keys,1,c)?;}else if in_global_proc&&["on_change(","on_cross(","adjacency(","registry(","radio_listen(","derives(","lives_while("].iter().any(|needle|t.contains(needle)){reader_names_with(t,defines,"",&mut self.reader_keys,7,c)?;}}c.checkpoint()?;Ok(())}
}
fn collect_metadata<C:kc::Control>(input:&MetadataInput<'_>,c:&mut C)->Result<PreparedMetadata,C::Error>{let mut out=PreparedMetadata::default();for owner in input.output_defining_owners{out.legacy_output(owner,c)?;}for marker in input.markers{out.marker(marker,input.defines,c)?;}for row in input.reader_procs{out.reader(row.source,row.header,row.owner,row.name,input.defines,c)?;}for file in input.files{out.file(file.text(),input.defines,c)?;}for names in input.tracked.values(){for name in names{out.tracked(name,c)?;}}c.checkpoint()?;Ok(out)}
/// SAME line bounds as the original owned body. Canonical raw file loans use
/// universal newlines; the old synthesized final newline adds no token to any
/// of the unanchored reader-name patterns. No body text escapes the loan.
fn proc_body_slice(text:&str,header:u32)->&str{let mut chunks=text.split_inclusive('\n');let mut start=0;for _ in 0..header{let Some(chunk)=chunks.next()else{return &text[text.len()..]};start+=chunk.len();}let mut end=start;for chunk in chunks{let line=if let Some(line)=chunk.strip_suffix('\n'){line.strip_suffix('\r').unwrap_or(line)}else{chunk};if !line.trim().is_empty()&&!line.starts_with('\t')&&!line.starts_with(' '){break}end+=chunk.len();}&text[start..end]}
fn proc_body_with<C:kc::Control>(text:&str,header:u32,c:&mut C)->Result<String,C::Error>{struct Body<'a>(&'a str);impl std::fmt::Display for Body<'_>{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{for line in self.0.lines(){f.write_str(line)?;f.write_str("\n")?;}Ok(())}}kc::format(c,format_args!("{}",Body(proc_body_slice(text,header))))}

#[cfg(feature="native-policy")]
pub(crate) fn generate_prepared_admitted(an:crate::reactive_dependency_view::Analysis<'_>,metadata:&PreparedMetadata,budget:&std::sync::Arc<crate::captured_generator_budget::Budget>,checkpoint:&dyn Fn()->std::io::Result<()>)->std::io::Result<Output>{checkpoint()?;let mut width=0usize;let mut units=64usize;let overflow=||{budget.deny();std::io::Error::new(std::io::ErrorKind::OutOfMemory,"Plans emitter capacity overflow")};let mut add=|s:&str|->std::io::Result<()>{width=width.checked_add(s.len()).ok_or_else(&overflow)?;units=units.checked_add(1).ok_or_else(&overflow)?;Ok(())};
 for rows in [an.draw_reads(),an.draw_hops(),an.draw_links()]{for(owner,names)in rows{checkpoint()?;add(owner)?;for name in names{add(name)?;}}}
 for(id,(names,_))in an.verb_reads(){checkpoint()?;add(id)?;for name in names{add(name)?;}}
 for id in an.draws(){add(id)?;}for name in an.stat_reads(){add(name)?;}for(owner,name)in an.reads(){add(owner)?;add(name)?;}
 for name in metadata.stat_inputs.iter().chain(&metadata.tracked_names).chain(&metadata.legacy_outputs){checkpoint()?;add(name)?;}
 for((owner,name),_)in &metadata.reader_keys{checkpoint()?;add(owner)?;add(name)?;}
 let bytes=width.checked_mul(32).and_then(|n|units.checked_mul(1024).and_then(|u|n.checked_add(u))).ok_or_else(overflow)?;budget.charge(bytes).map_err(|e|std::io::Error::new(std::io::ErrorKind::OutOfMemory,e))?;let mut out=Output::captured(budget.clone());generate_prepared(an,metadata,&mut out);checkpoint()?;budget.require().map_err(|e|std::io::Error::new(std::io::ErrorKind::OutOfMemory,e))?;Ok(out)
}

#[cfg(test)]#[path="plans_policy_frozen_original.rs"]mod plans_original_policy;
#[cfg(test)]mod native_policy_tests{use super::*;use std::io;
 struct Probe{left:usize,fail:bool}impl kc::Control for Probe{type Error=io::Error;const CHECKED:bool=true;fn checkpoint(&mut self)->io::Result<()>{if self.fail{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}}fn reserve(&mut self,n:usize)->io::Result<()>{self.left=self.left.checked_sub(n).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;Ok(())}fn overflow(&mut self)->io::Error{io::ErrorKind::OutOfMemory.into()}fn allocation_failed(&mut self)->io::Error{self.overflow()}}
 #[test]fn original_plans_borrowed_reader_projection_matches_exact_owned_body_policy_and_errors(){let defines=HashSet::from(["STAT_POWER".to_owned(),"MOB_KEY_READER".to_owned()]);for source in ["/obj/probe/reactions()\n\treturn on_change(\"terminal.power\", then(PROC_REF(refresh)))\n/obj/next\n", "/obj/probe\r\n    reactions()\r\n        return nameof(charge)\r\n    proc/next()\r\n        return MOB_KEY_READER\r\n", "/obj/probe/generated_reads()\n\treturn list(nameof(\n\tcharge), STAT_POWER)","/obj/probe/reactions()\n\treturn \"quoted space\"\n"]{let mut old=ReaderKeys::new();let owned=plans_original_policy::proc_body(source,1);plans_original_policy::reader_names(&owned,&defines,"/obj/probe",&mut old,3);let mut metadata=PreparedMetadata::default();metadata.reader(source,1,"/obj/probe","generated_reads",&defines,&mut Probe{left:65536,fail:false}).unwrap();assert_eq!(metadata.reader_keys,old);let mut exact=ReaderKeys::new();reader_names_with(&owned,&defines,"/obj/probe",&mut exact,3,&mut Probe{left:65536,fail:false}).unwrap();assert_eq!(exact,old);}let mut metadata=PreparedMetadata::default();assert_eq!(metadata.reader("/x()\n\treturn nameof(value)",1,"/obj/probe","reactions",&defines,&mut Probe{left:0,fail:false}).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert_eq!(metadata.file("seq_step(reads = list(nameof(value)))",&defines,&mut Probe{left:65536,fail:true}).unwrap_err().raw_os_error(),Some(1450));}
 #[cfg(feature="native-policy")]
 #[test]fn admitted_plans_emitter_matches_entire_original_rows_chunks_and_quota_io_recovery(){let mut analysis=crate::reactive_dependency_fold::Fold::default().analysis;for i in 0..601{let owner=format!("/obj/owner_{i}");let value=format!("value_{i}");analysis.draw_reads.entry(owner.clone()).or_default().insert(value.clone());analysis.draw_hops.entry(owner.clone()).or_default().insert(format!("loc.{value}"));analysis.draw_links.entry(owner.clone()).or_default().insert("cell".to_owned());analysis.verb_reads.insert(format!("{owner}::hidden_verbs"),(BTreeSet::from([value.clone()]),i%2==0));analysis.reads.insert((owner,value));}analysis.draws.insert("/obj/unknown::draw".into());analysis.consumers.insert("/obj/unknown::draw".into(),vec![crate::reactive_facts::Untracked{what:"?unknown".into(),owner:String::new(),rel:"code/probe.dm".into(),line:3}]);
 let args=vec!["/obj/probe".to_owned(),"on_change(nameof(charge), PROC_REF(refresh))".to_owned()];let markers=[MarkerRow{name:"CAPABILITIES",args:&args,body:"on_change(nameof(charge), PROC_REF(refresh))"}];let old_markers=[plans_original_policy::MarkerRow{name:"CAPABILITIES",args:&args,body:markers[0].body}];let defines=HashSet::new();let tracked=HashMap::from([("/obj/probe".to_owned(),HashSet::from(["charge".to_owned()]))]);let file=crate::tree::SourceFile::from_text("code/probe.dm","#define HELPER_READS nameof(leaf)\n/proc/helper()\n\treturn adjacency(nameof(other))\n");let files=[&file];let input=MetadataInput{markers:&markers,defines:&defines,tracked:&tracked,output_defining_owners:&["/datum/capability/powered"],reader_procs:&[],files:&files};let old_input=plans_original_policy::PlansInput{analysis:&analysis,markers:&old_markers,defines:&defines,tracked:&tracked,output_defining_owners:&["/datum/capability/powered"],reader_procs:&[],files:&files};let mut expected=Output::default();plans_original_policy::generate(&old_input,&mut expected);let metadata=collect_metadata(&input,&mut Probe{left:4*1024*1024,fail:false}).unwrap();let view=crate::reactive_dependency_view::Analysis::Owned(&analysis);let budget=crate::captured_generator_budget::Budget::new(64*1024*1024).unwrap();assert_eq!(generate_prepared_admitted(view,&metadata,&budget,&||Ok(())).unwrap(),expected);let tiny=crate::captured_generator_budget::Budget::new(1024).unwrap();assert_eq!(generate_prepared_admitted(view,&metadata,&tiny,&||Ok(())).unwrap_err().kind(),io::ErrorKind::OutOfMemory);let healthy=crate::captured_generator_budget::Budget::new(64*1024*1024).unwrap();assert_eq!(generate_prepared_admitted(view,&metadata,&healthy,&||Err(io::Error::from_raw_os_error(1450))).unwrap_err().raw_os_error(),Some(1450));assert_eq!(generate_prepared_admitted(view,&metadata,&healthy,&||Ok(())).unwrap(),expected);}
}
