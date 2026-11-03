//! Exact SetterPublishes consumer of SAME native reactive inference and body facts.
//! No semantic model/parser/cache/producer fallback is constructed by this fold.
use crate::{reactive_original_source::ReadSource,reactive_global_source::Source,reactive_reads_native::Failure,auto_tracking_policy::AutoSet,reactive_policy_facts_native::PolicyFacts,captured_sem_reads::SemanticPolicyData,captured_allow_annotations::Operation,setter_publication_policy as judge,key_policy_control::{self as kc,Control}};
use dm_analysis::{setter_publication_native as native,policy_body_demand::WorkspaceWork};use std::io;
struct Work<'a,'s>{source:&'a ReadSource<'s>,peak:usize}
impl WorkspaceWork for Work<'_,'_>{type Error=Failure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Failure>{self.source.budget().require().map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;self.source.checkpoint()?;self.source.budget().require().map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;self.source.require()?;Ok(())}fn retain(&mut self,n:usize)->Result<(),Failure>{self.source.reserve(Some(n)).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))}fn temporary(&mut self,n:usize)->Result<(),Failure>{if n>self.peak{self.retain(n-self.peak)?;self.peak=n;}Ok(())}fn overflow(&mut self)->Failure{self.source.budget().deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"setter publication observation geometry overflow"))}fn allocation_failed(&mut self)->Failure{self.overflow()}fn body<'a>(&mut self,_:&'a dm_tree::frontend::BodyArchive,_:usize)->Result<dm_tree::frontend::ArchivedBody<'a>,Failure>{Err("setter publication requires SAME active source body borrower".into())}}
pub(crate) fn collect_source(source:&ReadSource<'_>,inferred:&AutoSet,facts:&PolicyFacts,poll:&dyn Fn()->io::Result<()>)->Result<SemanticPolicyData,Failure>{
 let budget=source.budget();let pending=(||{
  let mut control=Operation{budget,poll};control.checkpoint()?;source.require()?;
  let mut judged=judge::Judged::new();
  for(_,var,why)in &inferred.blocked{judge::inferred_judgment(&mut judged,var,why,&mut control)?;}
  for(owner,var)in facts.explicit_tracked(){control.checkpoint()?;let name=kc::format(&mut control,format_args!("set_{var}"))?;if source.own_callable_exists(owner,&name)?{judge::explicit_judgment(&mut judged,owner,var,&mut control)?;}}
  // Actual old rule never consults ALLOW or setter scope exemptions.
  // It consumes completed inference, then emits every own setter finding.
  let mut sites=Vec::new();let mut work=Work{source,peak:0};
  for(definer,name,var,must)in judged{
   control.checkpoint()?;
   native::visit_own_values_using(source.inputs(),&definer,&name,&mut work,&mut|ordinal,verb,work|{
    let(relative,line)=source.callable_header_site(ordinal)?;
    if relative.starts_with("code/engine/_generated/"){return Ok(())}
    let mut flags=None;
    // Old rule observes writes/publishers BEFORE checking the group's Verb
    // declaration. A native rejection must never be silently skipped here.
    Source::with_body(source,ordinal,&mut|body|{if flags.is_some(){return Err("setter body provider repeated original loan".into())}flags=Some(native::observe_statement_body(body.statement_body(),&var,work)?);Ok(())})?;
    let flags=flags.ok_or("setter body provider omitted original loan")?;if verb{return Ok(())}
    if let Some(finding)=judge::judge(flags.writes,flags.publishes,must){let message=finding.message(&definer,&name,&var,&mut control)?;crate::reactive_dependency_fold::row(&mut control,&mut sites)?;sites.push(crate::lint::Site{rule:kc::own(&mut control,finding.rule())?,rel:relative,line,msg:message,key:String::new(),ident:String::new()});}Ok(())
   })?;
  }
  control.checkpoint()?;source.require()?;Ok(SemanticPolicyData::from_setter_sites(sites))
 })();crate::captured_sem_reads::finish(pending,budget,poll)
}
