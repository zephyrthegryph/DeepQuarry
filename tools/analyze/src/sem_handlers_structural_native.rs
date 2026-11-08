//! Whole structural half of sem/handlers over its distinct partial purpose.
//! No full-tree filter, source grant, private model cache or second parser.
use crate::{reactive_reads_native::Failure,key_policy_control::{self as kc,Control},captured_generator_budget::Budget};
use std::sync::Arc;
use dm_tree::frontend::{CurrentArchivedBody,BodySyntaxFailure,OriginalBodyDisposition};
/// Mandatory host ports. The real retained partial-source owner supplies exact
/// candidate membership, current closure and the SAME active Kind4 dependency.
/// There are deliberately no default/empty-success methods.
pub trait Source{
 fn inputs(&self)->&dm_analysis::policy_inputs::HandlersStructuralInputs;
 fn require(&self)->Result<(),Failure>;
 fn checkpoint(&self)->std::io::Result<()>;
 fn budget(&self)->&Arc<Budget>;
 fn definition_relative(&self,ordinal:usize,scratch:&Budget)->Result<String,Failure>;
 fn candidate(&self,relative:&str)->Result<bool,Failure>;
 fn line_at(&self,current:dm_syntax::Span)->Result<u32,Failure>;
 fn with_current_body<'a>(&'a self,ordinal:usize,consume:&mut dyn for<'p>FnMut(CurrentArchivedBody<'a,'p>,&dm_syntax::SettingAdmission<'_>)->Result<(),Failure>)->Result<(),Failure>;
}
fn failure(e:BodySyntaxFailure)->Failure{match e{BodySyntaxFailure::Operational(actual)=>Failure::Operational(actual),BodySyntaxFailure::Syntax(actual)=>Failure::Unsupported(actual.message)}}
fn policy_failure(e:dm_analysis::policy_body_demand::PolicyFailure)->Failure{match e{dm_analysis::policy_body_demand::PolicyFailure::Operational(actual)=>Failure::Operational(actual),dm_analysis::policy_body_demand::PolicyFailure::Unsupported(actual)=>Failure::Unsupported(actual.0)}}
fn oom(source:&dyn Source)->Failure{source.budget().deny();Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"handler structural original source work overflow"))}
struct Group<'a>{source:&'a dyn Source,peak:usize}
impl dm_analysis::policy_body_demand::WorkspaceWork for Group<'_>{
 type Error=Failure;const CHECKED:bool=true;
 fn checkpoint(&mut self)->Result<(),Failure>{self.source.checkpoint()?;self.source.require()}
 fn retain(&mut self,n:usize)->Result<(),Failure>{self.source.budget().charge(n).map_err(|message|Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))}
 fn temporary(&mut self,n:usize)->Result<(),Failure>{if n>self.peak{self.retain(n-self.peak)?;self.peak=n;}Ok(())}
 fn overflow(&mut self)->Failure{oom(self.source)}fn allocation_failed(&mut self)->Failure{oom(self.source)}
 fn body<'a>(&mut self,_:&'a dm_tree::frontend::BodyArchive,_:usize)->Result<dm_tree::frontend::ArchivedBody<'a>,Failure>{Err("handler own-value roster cannot parse any BODY".into())}
}
struct BodyScratch {
 budget: Arc<Budget>,
 complete: bool,
}
impl Drop for BodyScratch {
 fn drop(&mut self){
  if !self.complete { self.budget.keep_failed_scratch(); }
 }
}
/// Findings remain unsealed DATA. The caller deduplicates the full policy tuple
/// BEFORE ALLOW lookup and alone issues the actual selected complete report.
pub fn collect(source:&dyn Source,try_calls:&[&str],mut emit:impl FnMut(&'static str,&str,u32,String)->Result<(),Failure>)->Result<(),Failure>{
 source.checkpoint()?;source.require()?;let mut group=Group{source,peak:0};
 dm_analysis::original_callable_groups::visit_handlers_source_values_using(source.inputs(),&mut group,&mut|ordinal,_,_|{
  source.checkpoint()?;source.require()?;
  let mut scratch=BodyScratch{
   budget:Budget::scoped_temporaries(source.budget()).map_err(|message|Failure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))?,
   complete:false,
  };
  let result=(||{
   let relative=source.definition_relative(ordinal,&scratch.budget)?;
   if !source.candidate(&relative)?{return Ok(())}
  let mut calls=0;source.with_current_body(ordinal,&mut|body,admission|{
   calls+=1;if calls!=1{return Err("handler actual current BODY callback repeated".into())}if !body.belongs_to(source.inputs().archive()){return Err("handler BODY belongs to another structural source owner".into())}
   match body.syntax().original_code_disposition().map_err(failure)?{OriginalBodyDisposition::Skipped(grant)=>{if !grant.belongs_to(body.syntax()){return Err("handler skipped BODY grant belongs to another current result".into())}return Ok(())},OriginalBodyDisposition::Available(grant)=>if !grant.belongs_to(body.syntax()){return Err("handler available BODY grant belongs to another current result".into())}}
   let mut c=crate::captured_allow_annotations::Operation{budget:&scratch.budget,poll:&||source.checkpoint()};
   let names=crate::sem_handlers_context_names_native::collect_using(&body,admission,try_calls,&mut c)?;let storage=body.syntax().canonical_statement_storage();let view=storage.view();
   // Old traversal emits every context escape before pairing for this value.
   crate::sem_handlers_escape_native::collect_using(view,&names.acts,&names.locals,&mut c,|canonical,message|{let current=body.syntax().projection().span(canonical).ok_or("handler escape statement escapes actual current projection")?;let line=source.line_at(current)?;emit("context_escape",&relative,line,message)})?;
   let line=|canonical|{let current=body.syntax().projection().span(canonical).ok_or("handler pair statement escapes actual current projection")?;source.line_at(current)};
   let refusal_debug=|expression:&dm_syntax::Expr|{let identity=body.archive_owner().callables().identity_for_member(body.occurrence().member).ok_or("handler current original callable identity absent")?;body.with_initial_setting_prefix(identity,admission,|prefix|dm_analysis::checker_original_expression_debug::source_expression_debug_contains(prefix.source_body(),expression,"act_refusal",&||source.checkpoint())).map_err(failure)?.map_err(policy_failure)};
   let syntax=crate::sem_handlers_pair_native::Syntax{view,locals:body.source_locals(admission).map_err(failure)?,try_calls,line,refusal_debug};
   let rows=crate::sem_handlers_pair_policy::collect_using(&syntax,view.statements(),&mut c)?;for row in rows{source.checkpoint()?;emit("act_try_unpaired",&relative,row.line,row.msg)?;}
   source.checkpoint()?;source.require()
   })?;if calls!=1{return Err("handler actual current BODY callback omitted".into())}Ok(())
  })();
  // The relative path, names and pair/escape buffers are now gone. Only
  // the host's independently admitted finding payload may have escaped.
  scratch.complete=result.is_ok();
  result
 })?;source.checkpoint()?;source.require()
}
