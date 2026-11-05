//! Declared half of sem/handlers on SAME current source and targeted Reads children.
//! Structural candidate partial-TU outcome and standard outputs are NOT issued here.
use crate::{sem_handlers_policy as policy,reactive_global_source::{Source,Body,SelectedCallable},reactive_original_source::ReadSource,reactive_reads_native::Failure,captured_reactive_reads::{ReadProvider,RawPolicyReadProvider,Flavor,with_read_facts,with_raw_read_facts,FrozenReadSet},captured_allow_annotations::Operation,key_policy_control::{self as kc,Control},reactive_hooks_policy::{self as hooks,Role}};
use dm_syntax::{Expr,ExprKind,Statement,StatementKind,VisitDecision,OriginalTokenValue};
/// Stack-only DATA consumer port: a full-family unsealed child never becomes a
/// finite ReadResult. BOTH variants authenticate original archive/request first.
#[derive(Clone,Copy)]
enum ReadPort<'a>{Finite(&'a dyn ReadProvider),CurrentRaw(&'a dyn RawPolicyReadProvider)}
impl ReadPort<'_>{
 fn with_facts<T>(&self,inputs:&dm_analysis::policy_inputs::PolicyInputs,receiver:&str,procedure:&str,context:Option<&str>,flavor:Flavor,poll:&dyn Fn()->io::Result<()>,consume:impl FnOnce(&FrozenReadSet)->Result<T,Failure>)->Result<T,Failure>{match self{Self::Finite(provider)=>with_read_facts(*provider,inputs,receiver,procedure,context,flavor,poll,consume),Self::CurrentRaw(provider)=>with_raw_read_facts(*provider,inputs,receiver,procedure,context,flavor,poll,consume)}}
}

use std::{io,collections::{HashSet,BTreeSet}};
impl policy::ReturnExpression<Failure> for Expr{
 fn group(&self)->Option<&Self>{if let ExprKind::Group(inner)=&self.kind{Some(inner)}else{None}}
 fn base<C:Control<Error=Failure>>(&self,c:&mut C)->Result<Option<policy::BaseReturn>,Failure>{
  c.checkpoint()?;if matches!(&self.kind,ExprKind::Binary{..}|ExprKind::Conditional{..}){return Ok(None)}
  let mut cursor=self;let mut not=false;while let Some(next)=dm_analysis::original_base_terms::base_child(cursor){c.checkpoint()?;if let ExprKind::Unary{op,..}=&cursor.kind{not|=op=="!";}cursor=next;}
  use policy::ReturnTerm as T;
  // Original checks stop on a Not follow BEFORE inspecting term/value shape.
  if not{return Ok(Some(policy::BaseReturn{not,term:T::Other}))}
  let term=match &cursor.kind{
   _ if dm_analysis::original_base_terms::is_null_term(cursor)=>T::Null,
   ExprKind::Literal(text)=>{if let Some(value)=text.original_value(){match value{OriginalTokenValue::Int(i)=>T::Int(i),OriginalTokenValue::Float(_)=>T::Float,OriginalTokenValue::String(_)|OriginalTokenValue::InterpBegin(_)|OriginalTokenValue::InterpPart(_)|OriginalTokenValue::InterpEnd(_)=>T::Text,OriginalTokenValue::Resource(_)=>T::Other,_=>return Err("handler return literal carries a nonliteral Original value".into())}}else{
    // SAME valid-number classifier, only after genuine existing BODY grammar.
    // Invalid/recovery tokens require actual typed Int0, never guessed raw truth.
    let raw=text.as_str();if raw.as_bytes().first().is_some_and(|b|b.is_ascii_digit()||*b==b'.'){kc::reserve(c,||raw.len().checked_mul(8)?.checked_add(512))?;match dm_syntax::numeric_form::numeric_form(raw).map_err(Failure::from)?{dm_syntax::numeric_form::NumericForm::Integer(i)=>T::Int(i),dm_syntax::numeric_form::NumericForm::Float=>T::Float}}
    else if matches!(text.prepared_syntax_parts(),Some(Ok(Some(_)))){T::Text}
    else{return Err("handler return lexical value is not issued by actual Original literal owner".into())}
   }},
   ExprKind::Ident(name)if name=="null"=>T::Null,
   ExprKind::TypePath(path)=>{if !path.starts_with('/'){return Err("handler returned relative prefab needs actual Original path-component receipt".into())}let path=path.trim_start_matches('/');if path=="datum/msg"||path.starts_with("datum/msg/"){T::RefusalPath}else{T::OtherPath}},
   ExprKind::ObjectInitializer{object,..}if matches!(object.kind,ExprKind::TypePath(_))=>{return object.base(c).map(|value|value.map(|mut v|{v.not|=not;v}));},
   ExprKind::Call{callee,..}if matches!(&callee.kind,ExprKind::Ident(name)if name=="list")=>T::List,
   _=>T::Other,
  };Ok(Some(policy::BaseReturn{not,term}))
 }
 fn comparison(&self)->bool{matches!(&self.kind,ExprKind::Binary{op,..}if op=="=="||op=="!=")}
 fn arms(&self)->Option<(&Self,&Self)>{if let ExprKind::Conditional{then_value,else_value,..}=&self.kind{Some((then_value,else_value))}else{None}}
}
struct Returns<'a>{source:&'a dyn Source,ordinal:usize,protocol:policy::ReturnProtocol,rows:Vec<policy::Found>,error:Option<Failure>}
impl Returns<'_>{fn statement_inner(&mut self,s:&Statement)->Result<(),Failure>{self.source.checkpoint()?;let StatementKind::Return(value)=&s.kind else{return Ok(())};let mut c=Operation{budget:self.source.budget(),poll:&||self.source.checkpoint()};if let Some(msg)=policy::return_message_using(value.as_ref(),self.protocol,&mut c)?{let(_,line)=self.source.site(self.ordinal,s.header_span.start)?;kc::row(&mut c,&mut self.rows)?;self.rows.push(policy::Found{rule:"requirement_return",line,msg});}Ok(())}}
impl dm_analysis::policy_body_observation::BaseChainVisitor for Returns<'_>{
 fn statement(&mut self,s:&Statement)->VisitDecision{if self.error.is_some(){return VisitDecision::Stop}match self.statement_inner(s){Ok(())=>VisitDecision::Descend,Err(e)=>{self.error=Some(e);VisitDecision::Stop}}}
 fn expression(&mut self,_:&Expr,_:bool)->VisitDecision{VisitDecision::Skip}
 fn projected_expression(&mut self,_:dm_syntax::ProjectedExprView<'_>,_:bool)->VisitDecision{VisitDecision::Skip}
 fn frame_capacity(&mut self,n:usize)->Result<(),&'static str>{let result=self.source.reserve(Some(n));if let Err(e)=result{if self.error.is_none(){self.error=Some(e)}return Err("handler return walk admission refused")}Ok(())}
 fn frame_overflow(&mut self)->&'static str{if self.error.is_none(){self.source.budget().deny();self.error=Some(Failure::Operational(io::ErrorKind::OutOfMemory.into()));}"handler return frame overflow"}
 fn frame_allocation_failed(&mut self)->&'static str{self.frame_overflow()}
}
pub(crate) fn returns(source:&dyn Source,body:&dyn Body,ordinal:usize,protocol:policy::ReturnProtocol)->Result<Vec<policy::Found>,Failure>{let mut visitor=Returns{source,ordinal,protocol,rows:Vec::new(),error:None};let coverage=dm_analysis::policy_body_observation::observe_base_chains(body.statement_body().view(),&mut visitor);if let Some(e)=visitor.error{return Err(e)}coverage.map_err(Failure::from)?;source.checkpoint()?;Ok(visitor.rows)}
fn add(c:&mut Operation<'_>,out:&mut Vec<(String,String,u32)>,what:&str,rel:&str,line:u32)->Result<(),Failure>{kc::row(c,out)?;out.push((kc::own(c,what)?,kc::own(c,rel)?,line));Ok(())}
/// Internal incomplete-policy DATA. No report factory/witness/selection stamp can
/// be minted by this function. Source scope/current owner remains caller-bound.
/// Provider must be the existing active Kind12 children, exact Targeted flavor.
fn with_handler_scratch(parent:&std::sync::Arc<crate::captured_generator_budget::Budget>,operation:impl FnOnce(&std::sync::Arc<crate::captured_generator_budget::Budget>)->Result<(),Failure>)->Result<(),Failure>{
 let local=crate::captured_generator_budget::Budget::scoped_temporaries(parent).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
 let result=operation(&local);if result.is_err(){local.keep_failed_scratch();}result
}
fn declared_inner(source:&ReadSource<'_>,handler_parent:&std::sync::Arc<crate::captured_generator_budget::Budget>,reads:ReadPort<'_>,mut emit:impl FnMut(&'static str,&str,u32,String)->Result<(),Failure>)->Result<(),Failure>{
 let pending=(||{let mut c=Operation{budget:source.budget(),poll:&||source.checkpoint()};c.checkpoint()?;let rows=source.handler_marker_rows_checked(&||source.checkpoint())?;let mut markers=Vec::new();for m in &rows.markers{kc::row(&mut c,&mut markers)?;markers.push(crate::declare_policy::Marker{name:&m.name,rel:&m.rel,line:m.line,body:&m.body,args:&m.args,body_offset:m.body_offset,line_starts:&m.line_starts});}
 let refs=hooks::discover_admitted(&markers,&mut c)?;if refs.is_empty(){return Ok(())}
 let facts=crate::reactive_policy_facts_native::PolicyFacts::capture(source,&mut||source.checkpoint())?;
 let mut action_fields=BTreeSet::new();for m in markers.iter().filter(|m|m.name=="ACTION"){for arg in m.args.iter().skip(1).filter(|arg|arg.as_str()!="FIXED"&&!arg.contains('=')){c.checkpoint()?;kc::reserve(&mut c,||Some(256))?;action_fields.insert(kc::own(&mut c,arg.rsplit('/').next().unwrap_or(arg).trim())?);}}
 let mut seen=HashSet::new();
 for h in &refs{c.checkpoint()?;let on=if h.cap_proc{&h.cap_type}else{&h.owner};if on.is_empty(){continue}let key=(kc::own(&mut c,on)?,kc::own(&mut c,&h.proc)?,h.form,kc::own(&mut c,&h.rel)?,h.line);if seen.contains(&key){continue}kc::set_room(&mut c,&mut seen)?;seen.insert(key);
  // Metadata source scratch and this one-handler scratch coexist. They are
  // sibling loans of the SAME admitted parent, not nested budget domains.
  with_handler_scratch(handler_parent,|local|source.with_budget(local,|work|one_handler(work,reads,h,&action_fields,&facts,&mut emit)))?;

 }
 c.checkpoint()?;source.require()?;Ok(())})();
 // Do not replace real callback/query1450 with a later synthetic failure.
 if matches!(&pending,Err(Failure::Operational(_))){return pending}source.budget().require().map_err(|e|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,e)))?;source.checkpoint()?;pending
}

/// Parent-output reservation is kept BEFORE metadata scratch drops. This call
/// grants neither whole-policy EOF nor a report; callback still owns Site rows.
pub(crate) fn declared_from_source(source:&ReadSource<'_>,reads:&dyn ReadProvider,emit:impl FnMut(&'static str,&str,u32,String)->Result<(),Failure>)->Result<(),Failure>{declared_from_port(source,ReadPort::Finite(reads),emit)}
pub(crate) fn declared_from_current_raw_source(source:&ReadSource<'_>,reads:&dyn RawPolicyReadProvider,emit:impl FnMut(&'static str,&str,u32,String)->Result<(),Failure>)->Result<(),Failure>{declared_from_port(source,ReadPort::CurrentRaw(reads),emit)}
fn declared_from_port(source:&ReadSource<'_>,reads:ReadPort<'_>,mut emit:impl FnMut(&'static str,&str,u32,String)->Result<(),Failure>)->Result<(),Failure>{
 let budget=source.budget();budget.require().map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;source.checkpoint()?;
 let scratch=crate::captured_generator_budget::Budget::scoped_temporaries(budget).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;
 let pending=source.with_budget(&scratch,|work|declared_inner(work,budget,reads,|rule,rel,line,message|{budget.charge(message.capacity()).map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;emit(rule,rel,line,message)}));
 if pending.is_err(){scratch.keep_failed_scratch();}drop(scratch);if matches!(&pending,Err(Failure::Operational(_))){return pending}budget.require().map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;source.checkpoint()?;pending
}

fn one_handler(source:&ReadSource<'_>,reads:ReadPort<'_>,h:&hooks::HandlerRef,action_fields:&BTreeSet<String>,facts:&crate::reactive_policy_facts_native::PolicyFacts,emit:&mut dyn FnMut(&'static str,&str,u32,String)->Result<(),Failure>)->Result<(),Failure>{
 let mut c=Operation{budget:source.budget(),poll:&||source.checkpoint()};c.checkpoint()?;let on=if h.cap_proc{&h.cap_type}else{&h.owner};let tree=source.tree();let profile=tree.checker_builtin_profile().ok_or("handler source lacks Original builtin profile")?;
  let type_found=tree.checker_source_type_presence(profile,on).map_err(|e|Failure::from(format!("handler original type presence: {e:?}")))?;
  let selected=Source::callable(source,on,&h.proc)?;
  let SelectedCallable::Source(proc)=selected else{policy::declared_using(policy::Declared::<policy::Found>{hook:h,on,proc_found:false,type_found,definition:None,parameters:&[],bad_context:&[],impure:&[],returns:&[]},&mut c,&mut|_,rule,rel,line,msg|emit(rule,rel,line,msg))?;return Ok(())};
  // SAME immutable installed signature loan, also for CAP_PROC effects.
  // Return checks alone need BODY; effect-only capability headers never do.
  let view=source.inputs().archive().header_parameters_using(proc.ordinal,&||source.checkpoint()).map_err(|error|match error{dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>Failure::Operational(actual),dm_tree::frontend::BodySyntaxFailure::Syntax(error)=>Failure::Unsupported(error.message)})?;let header=view.header_span()?;kc::reserve(&mut c,||header.end.checked_sub(header.start)?.checked_mul(16)?.checked_add(1024))?;let mut parameters=Vec::new();for entry in view.entries()?{c.checkpoint()?;let path=view.type_path(entry)?.unwrap_or_default();let mut parts=Vec::new();for part in path.split('/').filter(|part|!part.is_empty()){kc::row(&mut c,&mut parts)?;parts.push(kc::own(&mut c,part)?);}kc::row(&mut c,&mut parameters)?;parameters.push(parts);}let mut found_returns=Vec::new();
  if h.role.boolean()||h.role==Role::Requirement{Source::with_body(source,proc.ordinal,&mut|body|{found_returns=returns(source,body,proc.ordinal,if h.role.boolean(){policy::ReturnProtocol::Boolean}else{policy::ReturnProtocol::Requirement})?;Ok(())})?;}
  let definition=source.callable_header_site(proc.ordinal)?;let mut bad_context=Vec::new();let mut impure=Vec::new();
  if !h.cap_proc{reads.with_facts(source.inputs(),on,&h.proc,Some(h.ctx.type_path()),Flavor::Targeted,&||source.checkpoint(),|read|{
   if h.role.pure(){for effect in read.effects(){c.checkpoint()?;if effect.kind=="assign"&&effect.proc.starts_with("set_")&&effect.proc[4..]==effect.name{continue}let what=match effect.kind{
    "assign" if facts.is_tracked(source,&effect.owner,&effect.name)?||facts.is_relation(source,&effect.owner,&effect.name)?=>Some(kc::format(&mut c,format_args!("assigns the tracked var `{}`",effect.name))?),
    "call" if crate::reactive_read_facts::MESSAGE_CALLS.contains(&effect.name.as_str())=>Some(kc::format(&mut c,format_args!("calls {}(), which talks to a player",effect.name))?),
    "call" if crate::reactive_read_facts::IMPURE_CALLS.contains(&effect.name.as_str())||effect.name.starts_with("rel_")=>Some(kc::format(&mut c,format_args!("calls {}()",effect.name))?),
    "call" if effect.name.starts_with("set_")&&facts.is_tracked(source,&effect.owner,&effect.name[4..])?=>Some(kc::format(&mut c,format_args!("calls the setter {}()",effect.name))?),_=>None};if let Some(what)=what{add(&mut c,&mut impure,&what,&effect.rel,effect.line)?;}}}
   for(field,(rel,line))in read.ctx_fields(){c.checkpoint()?;let action=h.ctx==hooks::Ctx::Action&&action_fields.contains(field);let notice=!h.notice.is_empty()&&Source::variable(source,&h.notice,field)?.is_some();if !action&&!notice&&Source::variable(source,h.ctx.type_path(),field)?.is_none()&&matches!(Source::callable(source,h.ctx.type_path(),field)?,SelectedCallable::Missing){add(&mut c,&mut bad_context,field,rel,*line)?;}}Ok(())})?;}
  policy::declared_using(policy::Declared{hook:h,on,proc_found:true,type_found,definition:Some((&definition.0,definition.1)),parameters:&parameters,bad_context:&bad_context,impure:&impure,returns:&found_returns},&mut c,&mut|_,rule,rel,line,msg|emit(rule,rel,line,msg))?;
 c.checkpoint()?;Ok(())
}

#[cfg(test)]mod sibling_scratch_tests{
 use super::*;use crate::captured_generator_budget::Budget;
 #[test]fn handler_scratch_releases_to_root_while_metadata_remains_funded(){let root=Budget::new(64*1024).unwrap();let before=root.used();let fixed=std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>();let metadata=Budget::scoped_temporaries(&root).unwrap();metadata.charge(4096).unwrap();let live=root.used();with_handler_scratch(&root,|handler|{handler.charge(8192).unwrap();assert!(root.used()>live);metadata.require().unwrap();Ok(())}).unwrap();assert_eq!(root.used(),live+fixed,"one handler payload has ended; its fixed metadata stays conservatively charged");drop(metadata);assert_eq!(root.used(),before+2*fixed,"both payloads ended; fixed scratch metadata is intentionally not refunded");}
 #[test]fn handler_first_operational_error_survives_and_escaping_failure_keeps_reservation(){let root=Budget::new(64*1024).unwrap();let metadata=Budget::scoped_temporaries(&root).unwrap();metadata.charge(4096).unwrap();let live=root.used();let failed=with_handler_scratch(&root,|handler|{handler.charge(8192).unwrap();Err(Failure::Operational(io::Error::from_raw_os_error(1450)))}).unwrap_err();assert!(matches!(failed,Failure::Operational(error)if error.raw_os_error()==Some(1450)));assert!(root.used()>=live+8192,"the failed operation may carry admitted payload outside the scratch callback");}
}
