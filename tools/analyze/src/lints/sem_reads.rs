//! `sem/reads`: what generated reads cannot cover is a build error (E5, doc/rewrite/final_api.html
//! section 7, "Generated reads").
//!
//! Over every output, condition, requirement and contribution a declaration names:
//!
//! * `unknown_read`: a read of a var that is not tracked, a relation, a stat, a derived value or
//!   constant (never written after init). The hint lists the four fixes.
//! * `untracked_global`: global state that changes after boot (`GLOB.x`, `SSx.y`, a real global var) read by reactive code. Constant-after-init
//!   globals (written only while the world boots, `sem/globals.rs`) read like constants; a tracked var of a system is a system read.
//! * `dynamic_read`: `vars[]` or `call()` in a handler.
//! * `hop_not_relation`: a read through a var that is not a declared relation.
//! * `unknown_field`: a var that the receiver's type does not have.
//! * `condition_cycle`: a cycle in the condition and stat graph, with the chain.
//! * `reads_as_uncovered`: a `READS_AS(proc, key)` accessor that reads untracked state nobody
//!   publishes under `key`.
//!
//! Nothing here parses the tree until a declaration names a handler.

use crate::lint::{Cx,Lint,Meta,Registry,Sink};
use crate::sem::handlers;

struct SemReads;

impl Lint for SemReads {
    fn meta(&self) -> &Meta {
        crate::sem_reads_policy::metadata()
    }

    fn scan_tree(&self,cx:&Cx,out:&mut Sink){
        if let Some(rec)=crate::sem::incremental::lookup(cx.tree){if let Some(saved)=rec.sinks.get("sem/reads"){out.sites.extend(saved.sites.iter().cloned());out.allow_used.extend(saved.allow_used.iter().cloned());out.notes.extend(saved.notes.iter().cloned());return}}
        let Some(an)=handlers::analyzed(cx.tree)else{return};let sem=crate::sem::sem_for(cx.tree);let mut report=Legacy{cx,sem:sem.as_deref(),out,seen:Default::default()};let mut control=crate::key_policy_control::Compatibility;
        for a in &an.handlers{if !a.h.role.reads_covered(){continue}let Some(set)=&a.closed else{continue};for(key,var,owner,rel,line)in &a.unknown{crate::sem_reads_policy::unknown(&mut report,crate::sem_reads_policy::Handler{owner:&a.on,procedure:&a.h.proc,form:a.h.form},key,var,owner,rel,*line,&mut control).unwrap();}for diagnostic in &set.diags{crate::sem_reads_policy::diagnostic(&mut report,crate::sem_reads_policy::Handler{owner:&a.on,procedure:&a.h.proc,form:a.h.form},diagnostic.rule,&diagnostic.rel,diagnostic.line,&diagnostic.msg,&mut control).unwrap();}}
        for cycle in &an.cycles{let first=an.graph.as_ref().and_then(|graph|graph.nodes.get(&cycle[0]));let(rel,line)=first.map(|node|(node.rel.as_str(),node.line)).unwrap_or(("",0));crate::sem_reads_policy::cycle(&mut report,cycle,rel,line,&mut control).unwrap();}
        for gap in &an.accessor_gaps{crate::sem_reads_policy::accessor_gap(&mut report,&gap.ty,&gap.proc,&gap.key,&gap.vars,&gap.rel,gap.line,&mut control).unwrap();}
        crate::sem::incremental::store(cx.tree,"sem/reads",report.out);
    }

}

pub fn register(reg: &mut Registry) {
    reg.add(SemReads);
}

struct Legacy<'cx,'tree,'out>{cx:&'cx Cx<'tree>,sem:Option<&'cx crate::sem::Sem>,out:&'out mut Sink,seen:std::collections::HashSet<(String,String,u32,String)>}
impl crate::sem_reads_policy::Reporter<crate::key_policy_control::Compatibility> for Legacy<'_,'_,'_>{
 fn reader(&mut self,rel:&str,line:u32,_:&mut crate::key_policy_control::Compatibility)->Result<String,std::convert::Infallible>{Ok(self.sem.map(|sem|sem.reader_ident(rel,line)).unwrap_or_else(||"?".to_owned()))}
 fn put(&mut self,rule:&'static str,rel:&str,line:u32,key:String,ident:String,message:String,_:&mut crate::key_policy_control::Compatibility)->Result<(),std::convert::Infallible>{if rel.is_empty()||!self.seen.insert((rule.to_owned(),rel.to_owned(),line,key)){return Ok(())}if self.cx.tree.get(rel).is_some_and(|file|self.out.allowed(file,line as usize,"reads")){return Ok(())}self.out.site_decl(rule,rel,line as usize,message,ident);Ok(())}
}
