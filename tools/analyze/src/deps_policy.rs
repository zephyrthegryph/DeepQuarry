//! Exact original dependency emitter over completed borrowed analysis rows.
//! This module grants no source/query authority and performs no parsing.
use std::collections::{BTreeMap,BTreeSet};
use crate::reactive_facts::DepsAnalysis;
pub use crate::sparse_slots_policy::Output;
fn emit_table(out: &mut Output, name: &str, rows: &[String]) {
    let chunks: Vec<&[String]> = rows.chunks(300).collect();
    for (n, chunk) in chunks.iter().enumerate() {
        out.line(format!("/proc/{}_chunk_{}()", name, n));
        out.line("	. = list()");
        for r in chunk.iter() {
            let r = r.trim_start_matches('\t');
            let (key, value) = r.split_once(" = ").unwrap_or((r, "TRUE"));
            out.line(format!("	.[{}] = {}", key, value));
        }
    }
    out.line(format!("/proc/{}_build()", name));
    out.line("	. = list()");
    for n in 0..chunks.len() {
        out.line(format!("	var/list/c{} = {}_chunk_{}()", n, name, n));
        out.line(format!("	for(var/k in c{})", n));
        out.line(format!("		.[k] = c{}[k]", n));
    }
    out.line(format!("GLOBAL_LIST_INIT({}, {}_build())", name, name));
}

/// A published key as DM text: quotes and backslashes escaped, `[` left alone (a define is written `[MOB_KEY_X]` and the compile interpolates it).
fn quote_key(s: &str) -> String {
    format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\""))
}

fn quote(s: &str) -> String {
    // `[` opens an embedded expression in a DM string: a list hop ("parts[].x") is written `\[`.
    format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\"").replace('[', "\\["))
}


pub fn generate(an:&DepsAnalysis,out:&mut Output){generate_view(crate::reactive_dependency_view::Analysis::Owned(an),out)}
pub(crate) fn generate_view(an:crate::reactive_dependency_view::Analysis<'_>,out:&mut Output){
        out.doc("\"<type>::<proc>\" -> what a stat input, condition, requirement, output or draw reads that nothing publishes: an untracked var");
        out.doc("(\"power_area.x\"), ?<rule> for a read the analysis could not resolve, ?opaque:<type>::<proc> for an engine body it does not enter.");
        out.doc("A stat with such an input recomputes on every read instead of caching (stat_value(), code/engine/stats/recompute.dm).");
        let rows: Vec<String> = an.consumers()
            .filter(|(_, u)| !u.is_empty())
            .map(|(id, u)| {
                let whats: BTreeSet<&str> = u.iter().map(|x| x.what.as_str()).collect();
                format!("\t{} = list({})", quote(id), whats.iter().map(|w| quote(w)).collect::<Vec<_>>().join(", "))
            })
            .collect();
        emit_table(out, "generated_untracked_reads", &rows);
        out.blank();
        out.doc("\"<type>\" -> vars its declarations name as a stat input (nameof(v) in contributes(), contributes_to() or a when() around one) that");
        out.doc("nothing publishes: a stat that reads one recomputes on every read.");
        let mut by_type: BTreeMap<&str, BTreeSet<&str>> = BTreeMap::new();
        for l in an.leaves() {
            by_type.entry(l.owner.as_str()).or_default().insert(l.var.as_str());
        }
        let rows: Vec<String> = by_type.iter().map(|(t, vs)| format!("\t{} = list({})", quote(t), vs.iter().map(|v| quote(v)).collect::<Vec<_>>().join(", "))).collect();
        emit_table(out, "generated_untracked_leaves", &rows);
        out.blank();
        // The holder vars and hop reads of each draw() are the change graph's plans now (`gen plans`, GLOB.generated_plans).
        out.doc("\"<type>\" -> the published keys its own draw() (and the parent draws it calls) reads through a READS_AS accessor: a PUBLISH_CHANGE of one");
        out.doc("redraws the thing (publish_key_changed(), code/engine/stats/recompute.dm), so a draw needs no hand-written on_change() for a key it reads.");
        let rows: Vec<String> = an.draw_keys()
            .filter(|(_, ks)| !ks.is_empty())
            .map(|(t, ks)| format!("	{} = list({})", quote(t), ks.iter().map(|k| quote_key(k)).collect::<Vec<_>>().join(", ")))
            .collect();
        emit_table(out, "generated_draw_keys", &rows);
}

/// Admitted renderer for completed dependency data. This funds only new emitter
/// temporaries/output; the caller must already retain/charge the analysis owner.
#[cfg(feature="native-policy")]
pub(crate) fn generate_admitted(an:&DepsAnalysis,budget:&std::sync::Arc<crate::captured_generator_budget::Budget>,checkpoint:&dyn Fn()->std::io::Result<()>)->std::io::Result<Output>{
 generate_view_admitted(crate::reactive_dependency_view::Analysis::Owned(an),budget,checkpoint)
}
#[cfg(feature="native-policy")]
pub(crate) fn generate_view_admitted(an:crate::reactive_dependency_view::Analysis<'_>,budget:&std::sync::Arc<crate::captured_generator_budget::Budget>,checkpoint:&dyn Fn()->std::io::Result<()>)->std::io::Result<Output>{
 checkpoint()?;
 // Every original row is built at most once in each of three tables. Quoting
 // expands each source byte by at most2; replacement, quote Vec, join and final
 // row overlaps fit32 source bytes. Up to three row Vecs, per-row what sets and
 // the two-level leaf grouping coexist;1024 per logical row/name conservatively
 // covers their exposed coordination and standard container node payloads.
 // Standard allocator/control-block geometry is not a total-RSS qualification.
 let mut width=0usize;let mut units=64usize;
 let overflow=||{budget.deny();std::io::Error::new(std::io::ErrorKind::OutOfMemory,"dependency emitter temporary capacity overflow")};
 for(id,rows)in an.consumers(){checkpoint()?;width=width.checked_add(id.len()).ok_or_else(&overflow)?;units=units.checked_add(1).ok_or_else(&overflow)?;for row in rows{width=width.checked_add(row.what.len()).ok_or_else(&overflow)?;units=units.checked_add(1).ok_or_else(&overflow)?;}}
 for leaf in an.leaves(){checkpoint()?;width=width.checked_add(leaf.owner.len()).and_then(|n|n.checked_add(leaf.var.len())).ok_or_else(&overflow)?;units=units.checked_add(2).ok_or_else(&overflow)?;}
 for(owner,keys)in an.draw_keys(){checkpoint()?;width=width.checked_add(owner.len()).ok_or_else(&overflow)?;units=units.checked_add(1).ok_or_else(&overflow)?;for key in keys.iter(){width=width.checked_add(key.len()).ok_or_else(&overflow)?;units=units.checked_add(1).ok_or_else(&overflow)?;}}
 let reservation=width.checked_mul(32).and_then(|n|units.checked_mul(1024).and_then(|m|n.checked_add(m))).ok_or_else(&overflow)?;
 budget.charge(reservation).map_err(|message|std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))?;
 let mut out=Output::captured(budget.clone());generate_view(an,&mut out);checkpoint()?;
 if budget.denied(){return Err(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"dependency emitter output admission refused"))}Ok(out)
}

#[cfg(test)]mod tests{
 use super::*;
 mod original{
  use super::*;
fn emit_table(out: &mut Output, name: &str, rows: &[String]) {
    let chunks: Vec<&[String]> = rows.chunks(300).collect();
    for (n, chunk) in chunks.iter().enumerate() {
        out.line(format!("/proc/{}_chunk_{}()", name, n));
        out.line("	. = list()");
        for r in chunk.iter() {
            let r = r.trim_start_matches('\t');
            let (key, value) = r.split_once(" = ").unwrap_or((r, "TRUE"));
            out.line(format!("	.[{}] = {}", key, value));
        }
    }
    out.line(format!("/proc/{}_build()", name));
    out.line("	. = list()");
    for n in 0..chunks.len() {
        out.line(format!("	var/list/c{} = {}_chunk_{}()", n, name, n));
        out.line(format!("	for(var/k in c{})", n));
        out.line(format!("		.[k] = c{}[k]", n));
    }
    out.line(format!("GLOBAL_LIST_INIT({}, {}_build())", name, name));
}

/// A published key as DM text: quotes and backslashes escaped, `[` left alone (a define is written `[MOB_KEY_X]` and the compile interpolates it).
fn quote_key(s: &str) -> String {
    format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\""))
}

fn quote(s: &str) -> String {
    // `[` opens an embedded expression in a DM string: a list hop ("parts[].x") is written `\[`.
    format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\"").replace('[', "\\["))
}


  pub fn generate(an:&DepsAnalysis,out:&mut Output){
        out.doc("\"<type>::<proc>\" -> what a stat input, condition, requirement, output or draw reads that nothing publishes: an untracked var");
        out.doc("(\"power_area.x\"), ?<rule> for a read the analysis could not resolve, ?opaque:<type>::<proc> for an engine body it does not enter.");
        out.doc("A stat with such an input recomputes on every read instead of caching (stat_value(), code/engine/stats/recompute.dm).");
        let rows: Vec<String> = an
            .consumers
            .iter()
            .filter(|(_, u)| !u.is_empty())
            .map(|(id, u)| {
                let whats: BTreeSet<&str> = u.iter().map(|x| x.what.as_str()).collect();
                format!("\t{} = list({})", quote(id), whats.iter().map(|w| quote(w)).collect::<Vec<_>>().join(", "))
            })
            .collect();
        emit_table(out, "generated_untracked_reads", &rows);
        out.blank();
        out.doc("\"<type>\" -> vars its declarations name as a stat input (nameof(v) in contributes(), contributes_to() or a when() around one) that");
        out.doc("nothing publishes: a stat that reads one recomputes on every read.");
        let mut by_type: BTreeMap<&str, BTreeSet<&str>> = BTreeMap::new();
        for l in &an.leaves {
            by_type.entry(l.owner.as_str()).or_default().insert(l.var.as_str());
        }
        let rows: Vec<String> = by_type.iter().map(|(t, vs)| format!("\t{} = list({})", quote(t), vs.iter().map(|v| quote(v)).collect::<Vec<_>>().join(", "))).collect();
        emit_table(out, "generated_untracked_leaves", &rows);
        out.blank();
        // The holder vars and hop reads of each draw() are the change graph's plans now (`gen plans`, GLOB.generated_plans).
        out.doc("\"<type>\" -> the published keys its own draw() (and the parent draws it calls) reads through a READS_AS accessor: a PUBLISH_CHANGE of one");
        out.doc("redraws the thing (publish_key_changed(), code/engine/stats/recompute.dm), so a draw needs no hand-written on_change() for a key it reads.");
        let rows: Vec<String> = an
            .draw_keys
            .iter()
            .filter(|(_, ks)| !ks.is_empty())
            .map(|(t, ks)| format!("	{} = list({})", quote(t), ks.iter().map(|k| quote_key(k)).collect::<Vec<_>>().join(", ")))
            .collect();
        emit_table(out, "generated_draw_keys", &rows);
  }
 }
 fn fixture()->DepsAnalysis{
  let mut an=DepsAnalysis{consumers:BTreeMap::new(),draws:BTreeSet::new(),leaves:Vec::new(),draw_reads:BTreeMap::new(),draw_keys:BTreeMap::new(),draw_hops:BTreeMap::new(),draw_links:BTreeMap::new(),verb_reads:BTreeMap::new(),stat_reads:BTreeSet::new(),reads:BTreeSet::new(),candidates:BTreeSet::new(),sampled:BTreeMap::new()};
  for i in 0..601{let id=format!("/datum/test_{i:04}::read");an.consumers.insert(id,vec![crate::reactive_facts::Untracked{what:format!("charge_{i}"),owner:"/datum/base".into(),rel:"code/probe.dm".into(),line:2},crate::reactive_facts::Untracked{what:format!("charge_{i}"),owner:String::new(),rel:String::new(),line:0}]);}
  an.consumers.insert("/datum/no_gaps::read".into(),Vec::new());
  an.leaves=vec![crate::reactive_facts::Leaf{owner:"/datum/z".into(),var:"quoted\"and[hop]".into(),rel:"z.dm".into(),line:8},crate::reactive_facts::Leaf{owner:"/datum/a".into(),var:"plain".into(),rel:"a.dm".into(),line:1},crate::reactive_facts::Leaf{owner:"/datum/z".into(),var:"quoted\"and[hop]".into(),rel:"z.dm".into(),line:9}];
  an.draw_keys.insert("/datum/z".into(),BTreeSet::from(["[KEY_DEFINE]".into(),"quoted\"slash\\".into()]));an.draw_keys.insert("/datum/empty".into(),BTreeSet::new());an
 }
 #[test]fn full_original_emitter_bytes_preserve_chunking_dedup_grouping_and_escaping(){let an=fixture();let mut old=Output::default();original::generate(&an,&mut old);let mut shared=Output::default();generate(&an,&mut shared);assert_eq!(shared,old);assert!(shared.body.contains("generated_untracked_reads_chunk_2()"));assert!(shared.body.contains(".["));assert!(!shared.body.contains("no_gaps"));assert!(shared.diags.is_empty());}
 #[cfg(feature="native-policy")]
 #[test]fn actual_emitter_quota_refusal_and_fresh_same_data_recovery_match_frozen_policy(){let an=fixture();let fixed=std::mem::size_of::<crate::captured_generator_budget::Budget>()+2*std::mem::size_of::<usize>();let tiny=crate::captured_generator_budget::Budget::new(fixed).unwrap();let denied=generate_admitted(&an,&tiny,&||Ok(())).unwrap_err();assert_eq!(denied.kind(),std::io::ErrorKind::OutOfMemory);assert!(tiny.denied());let large=crate::captured_generator_budget::Budget::new(8*1024*1024).unwrap();let shared=generate_admitted(&an,&large,&||Ok(())).unwrap();let mut old=Output::default();original::generate(&an,&mut old);assert_eq!(shared,old);let stopped=generate_admitted(&an,&large,&||Err(std::io::Error::from_raw_os_error(1450))).unwrap_err();assert_eq!(stopped.raw_os_error(),Some(1450));}
}
