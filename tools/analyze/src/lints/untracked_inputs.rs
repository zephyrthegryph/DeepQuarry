//! `untracked_inputs`: a read the dependency graph cannot see change, by a consumer whose value the runtime would like to keep.
//!
//! A stat input (a contribution, a when() condition around one, a STAT formula), a requirement, an output or a draw() is re-run when a key it
//! reads publishes (doc/rewrite/final_api.html section 7, "Generated reads"). A read of a var that nothing publishes (not tracked, a relation, a
//! stat, derived or constant), a read the walk cannot resolve, or a call into an engine body it does not enter leaves that consumer's inputs
//! incomplete: a stat that has one recomputes on every read instead of caching (code/engine/stats/recompute.dm), and a draw that has one can
//! show a stale look. The facts are `gen deps`' (`code/engine/_generated/deps.dm` lists the same consumers for the runtime).
//!
//! * `stat_input_untracked`: a condition, requirement, output or contribution handler reads untracked state.
//! * `draw_untracked`: a draw() reads untracked state.
//! * `sampled_in_look`: a draw, a stat contribution or a STAT formula (or a proc one reaches) wraps a read in `read_once()`. A sample is taken
//!   once and never follows, so a look or a stat built from it goes stale: track the var, declare the relation or publish the key instead.
//! * `leaf_untracked`: a CAPABILITIES block names an untracked var as a stat input (`nameof(v)` in contributes()/contributes_to() or a when()
//!   around one).
//!
//! The reads are the closed walk's (`ReadsEngine::closed`): engine bodies are entered, a virtual call is the union of its overrides, a global
//! proc is walked like any proc, and global state that changes after boot is an untracked input (`untracked_global` in `sem/reads`). A site is
//! counted once however many consumers reach it. The baseline was re-seeded when the lint moved to this walk (a change of measurement:
//! `doc/rewrite/reads_closure_newly_visible.md` compares the two).
//!
//! A hard ban: any site fails, there is no baseline. Make the var TRACKED and write it through its setter, declare the relation, or publish a
//! READS_AS key where it changes. A read that genuinely cannot be tracked (global config a requirement asks, a clock, a profile record) is
//! sampled with `read_once(...)` (code/engine/parts/cond.dm), which the walk mutes and which rebuilds a menu that asked; the runtime treats
//! any consumer with an untracked read as untracked.

use crate::gens::deps;
use crate::lint::{Cx,Lint,Meta,Registry,Sink};

struct UntrackedInputs;

impl Lint for UntrackedInputs {
    fn meta(&self) -> &Meta {
        crate::untracked_inputs_policy::metadata()
    }

    fn scan_tree(&self,cx:&Cx,out:&mut Sink){let analyzed=deps::analyzed(cx.tree);let Some(analysis)=analyzed.as_ref().as_ref()else{return};let sem=crate::sem::sem_for(cx.tree);let mut report=Legacy{cx,sem:sem.as_deref(),out,seen:Default::default()};crate::untracked_inputs_policy::scan(crate::reactive_dependency_view::Analysis::Owned(analysis),&mut report,&mut crate::key_policy_control::Compatibility).unwrap();}

}

pub fn register(reg: &mut Registry) {
    reg.add(UntrackedInputs);
}

struct Legacy<'cx,'tree,'out>{cx:&'cx Cx<'tree>,sem:Option<&'cx crate::sem::Sem>,out:&'out mut Sink,seen:std::collections::HashSet<(&'static str,String,u32,String)>}
impl crate::sem_reads_policy::Reporter<crate::key_policy_control::Compatibility> for Legacy<'_,'_,'_>{fn reader(&mut self,rel:&str,line:u32,_:&mut crate::key_policy_control::Compatibility)->Result<String,std::convert::Infallible>{Ok(self.sem.map(|sem|sem.reader_ident(rel,line)).unwrap_or_else(||"?".to_owned()))}fn put(&mut self,rule:&'static str,rel:&str,line:u32,key:String,ident:String,message:String,_:&mut crate::key_policy_control::Compatibility)->Result<(),std::convert::Infallible>{if rel.is_empty()||line==0||self.cx.exempt(rel)||!self.seen.insert((rule,rel.to_owned(),line,key)){return Ok(())}if self.cx.tree.get(rel).is_some_and(|file|self.out.allowed(file,line as usize,"untracked_inputs")){return Ok(())}self.out.site_decl(rule,rel,line as usize,message,ident);Ok(())}}
