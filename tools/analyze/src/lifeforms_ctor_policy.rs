//! Exact ctor_args judge on SAME authenticated canonical bodies and declarations.
//! The compiler's existing old-policy walk owns traversal and current geometry.
use crate::{reactive_global_source::{Source,Body},reactive_original_source::ReadSource,captured_reactive_reads::Failure,captured_generator_budget::Budget,lifeforms_policy::Declared,captured_allow_annotations::Operation,key_policy_control::{self as kc,Control}};
use dm_syntax::{Expr,ExprKind,Span,VisitDecision};
use std::{collections::{BTreeMap,HashMap,HashSet},cell::RefCell,io};
#[derive(Debug,Eq,PartialEq,Ord,PartialOrd)]pub(crate) struct DeadArg{pub rel:String,pub line:u32,pub ty:String,pub passed:usize,pub dead:Vec<usize>}
#[derive(Debug,Eq,PartialEq,Ord,PartialOrd)]pub(crate) struct ForwardOnly{pub rel:String,pub line:u32,pub owner:String,pub name:String,pub params:Vec<String>}
fn framework(owner:&str)->bool{matches!(owner,"/"|"/datum"|"/atom"|"/atom/movable")}
const CTORS:&[&str]=&["New","Initialize"];
fn overflow(source:&dyn Source)->Failure{source.budget().deny();Failure::Operational(io::ErrorKind::OutOfMemory.into())}
fn charge(source:&dyn Source,n:Option<usize>)->Result<(),Failure>{source.checkpoint()?;source.budget().charge(n.ok_or_else(||overflow(source))?).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))}
fn copy(source:&dyn Source,s:&str)->Result<String,Failure>{kc::own(&mut Operation{budget:source.budget(),poll:&||source.checkpoint()},s)}
fn reserve<T>(source:&dyn Source,out:&mut Vec<T>)->Result<(),Failure>{kc::row(&mut Operation{budget:source.budget(),poll:&||source.checkpoint()},out)}
fn bare_ident(e:&Expr)->Option<&str>{match &e.kind{ExprKind::Ident(name)=>Some(name),_=>None}}
struct Reads<'a>{source:&'a dyn Source,name:&'a str,uses:usize,forwards:usize,error:Option<Failure>}
impl Reads<'_>{
 fn observe(&mut self,e:&Expr,chain_child:bool)->Result<(),Failure>{
  self.source.checkpoint()?;if chain_child{return Ok(())}
  let term=dm_analysis::original_base_terms::leaf_using(e,&mut||self.source.checkpoint())?;
  match &term.kind{
   ExprKind::Ident(name)if name==self.name=>self.uses=self.uses.checked_add(1).ok_or_else(||overflow(self.source))?,
   ExprKind::Call{callee,args}if matches!(&callee.kind,ExprKind::Ident(name)if name=="..")=>{for arg in args{self.source.checkpoint()?;if bare_ident(arg)==Some(self.name){self.forwards=self.forwards.checked_add(1).ok_or_else(||overflow(self.source))?;}}},_=>{}
  }Ok(())
 }
 fn event(&mut self,e:&Expr,chain:bool)->VisitDecision{if self.error.is_some(){return VisitDecision::Stop}match self.observe(e,chain){Ok(())=>VisitDecision::Descend,Err(actual)=>{self.error=Some(actual);VisitDecision::Stop}}}
}
impl dm_analysis::policy_body_observation::BaseChainVisitor for Reads<'_>{
 fn statement(&mut self,_:&dm_syntax::Statement)->VisitDecision{if self.error.is_some(){return VisitDecision::Stop}match self.source.checkpoint(){Ok(())=>VisitDecision::Descend,Err(e)=>{self.error=Some(Failure::Operational(e));VisitDecision::Stop}}}
 fn expression(&mut self,e:&Expr,chain:bool)->VisitDecision{self.event(e,chain)}
 fn projected_expression(&mut self,e:dm_syntax::ProjectedExprView<'_>,chain:bool)->VisitDecision{self.event(e.original(),chain)}
 fn frame_capacity(&mut self,bytes:usize)->Result<(),&'static str>{if self.error.is_some(){return Err("ctor read visitor failed")}match charge(self.source,Some(bytes)){Ok(())=>Ok(()),Err(e)=>{self.error=Some(e);Err("ctor read visitor admission failed")}}}
 fn frame_overflow(&mut self)->&'static str{if self.error.is_none(){self.error=Some(overflow(self.source));}"ctor read visitor frame overflow"}
 fn frame_allocation_failed(&mut self)->&'static str{if self.error.is_none(){self.error=Some(overflow(self.source));}"ctor read visitor frame allocation failed"}
}
fn with_read_scratch(parent:&std::sync::Arc<Budget>,operation:impl FnOnce(&std::sync::Arc<Budget>)->Result<bool,Failure>)->Result<bool,Failure>{
 let scratch=Budget::scoped_temporaries(parent).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
 let pending=operation(&scratch);if pending.is_err(){scratch.keep_failed_scratch();}pending
}
fn reads_outside_parent_call(source:&dyn Source,body:&dyn Body,name:&str,parent:&std::sync::Arc<Budget>)->Result<bool,Failure>{
 // The declaration/memo source may already be phase scratch. Each read walk
 // is a sibling loan from the SAME actual root while that metadata stays live.
 with_read_scratch(parent,|scratch|{let mut result=None;
  source.with_budget(scratch,&mut|local|{let mut reads=Reads{source:local,name,uses:0,forwards:0,error:None};let coverage=dm_analysis::policy_body_observation::observe_base_chains(body.statement_body().view(),&mut reads);if let Some(actual)=reads.error{return Err(actual)}coverage.map_err(Failure::from)?;local.checkpoint()?;result=Some(reads.uses>reads.forwards);Ok(())})?;
  result.ok_or_else(||Failure::from("ctor current scoped body observation omitted result"))
 })
}

struct Ctors<'a>{scratch_parent:&'a std::sync::Arc<Budget>,source:&'a dyn Source,declared:&'a Declared,memo:RefCell<HashMap<(String,usize),bool>>}
impl Ctors<'_>{
 fn taken(&self,ty:&str,pos:usize)->Result<bool,Failure>{
  self.source.checkpoint()?;let key=(copy(self.source,ty)?,pos);if let Some(&answer)=self.memo.borrow().get(&key){return Ok(answer)}
  let mut answer=false;let mut cursor=Some(copy(self.source,ty)?);let mut seen=HashSet::new();
  while let Some(owner)=cursor{
   self.source.checkpoint()?;if framework(&owner){break}
   if seen.contains(&owner){return Err("actual ctor parent graph contains a cycle".into())}kc::set_room(&mut Operation{budget:self.source.budget(),poll:&||self.source.checkpoint()},&mut seen)?;seen.insert(copy(self.source,&owner)?);
   if self.declared.positions.get(&owner).is_some_and(|rows|rows.contains_key(&pos)){answer=true;break}
   let inputs=self.source.complete_inputs().ok_or("ctor own-group source lacks actual complete model")?;let mut work=GroupWork{source:self.source,peak:0};
   for name in CTORS{if answer{break}dm_analysis::setter_publication_native::visit_own_values_using(inputs,&owner,name,&mut work,&mut|ordinal,_,_|{if answer{return Ok(())}self.source.with_body(ordinal,&mut|body|{if reads_outside_parent_call(self.source,body,"args",self.scratch_parent)?{answer=true;return Ok(())}let parameters=body.source_parameters()?;if let Some(p)=parameters.entries()?.get(pos){if reads_outside_parent_call(self.source,body,parameters.name(p)?,self.scratch_parent)?{answer=true;}}Ok(())})})?;}
   if answer{break}cursor=self.source.parent_type(&owner)?.map(|name|copy(self.source,name)).transpose()?;
  }
  let mut memo=self.memo.borrow_mut();kc::hash_room(&mut Operation{budget:self.source.budget(),poll:&||self.source.checkpoint()},&mut memo)?;memo.insert(key,answer);Ok(answer)
 }
}
fn absolute_path(target:&Expr)->Option<&str>{match &target.kind{ExprKind::TypePath(path)if path.starts_with('/')&&!path.contains(['.',':'])=>Some(path),ExprKind::ObjectInitializer{object,fields}if fields.is_empty()=>absolute_path(object),_=>None}}
fn arguments(e:&Expr)->Option<(&str,&[Expr])>{let term=e;match &term.kind{ExprKind::Unary{op,value}if op=="new"=>{let ExprKind::Call{callee,args}=&value.kind else{return None};absolute_path(callee).map(|ty|(ty,args.as_slice()))},_=>None}}
fn is_null(e:&Expr)->bool{dm_analysis::original_base_terms::is_null_term(e)}
struct News<'a,'f>{source:&'a dyn Source,body:&'a dyn Body,emit:&'f mut dyn FnMut(Span,&str,&[Expr])->Result<(),Failure>,error:Option<Failure>}
impl News<'_,'_>{fn event(&mut self,e:&Expr,current:Span,chain:bool)->VisitDecision{
 if self.error.is_some(){return VisitDecision::Stop}let result=(||{self.source.checkpoint()?;if chain{return Ok(())}let leaf=dm_analysis::original_base_terms::leaf_using(e,&mut||self.source.checkpoint())?;if let Some((ty,args))=arguments(leaf){(self.emit)(current,ty,args)?;}Ok(())})();match result{Ok(())=>VisitDecision::Descend,Err(e)=>{self.error=Some(e);VisitDecision::Stop}}
}}
impl dm_analysis::policy_body_observation::BaseChainVisitor for News<'_,'_>{
 fn statement(&mut self,_:&dm_syntax::Statement)->VisitDecision{if self.error.is_some(){return VisitDecision::Stop}match self.source.checkpoint(){Ok(())=>VisitDecision::Descend,Err(e)=>{self.error=Some(Failure::Operational(e));VisitDecision::Stop}}}
 fn after_variable(&mut self,s:&dm_syntax::Statement)->VisitDecision{
  if self.error.is_some(){return VisitDecision::Stop}let result=(||{self.source.checkpoint()?;if let dm_syntax::StatementKind::Var{value:Some(value),..}=&s.kind{let ExprKind::Call{callee,args}=&value.kind else{return Ok(())};if !matches!(&callee.kind,ExprKind::Ident(name)if name=="new"){return Ok(())}if value.span.end==callee.span.end{return Ok(())}let locals=self.body.source_locals()?;let rows=locals.in_current_span(s.header_span)?;if rows.len()!=1{return Err("ctor implicit new needs exact original grouped-local owner".into())}let fact=&rows[0];charge(self.source,locals.type_path_width(fact)?.checked_mul(4).and_then(|n|n.checked_add(128)))?;if let Some(ty)=locals.type_path(fact)?{if !ty.is_empty(){(self.emit)(value.span,&ty,args)?;}}}Ok(())})();match result{Ok(())=>VisitDecision::Descend,Err(e)=>{self.error=Some(e);VisitDecision::Stop}}
 }
 fn expression(&mut self,e:&Expr,chain:bool)->VisitDecision{let leaf=match dm_analysis::original_base_terms::leaf_using(e,&mut||self.source.checkpoint()){Ok(leaf)=>leaf,Err(actual)=>{if self.error.is_none(){self.error=Some(Failure::Operational(actual))}return VisitDecision::Stop}};self.event(e,leaf.span,chain)}
 fn projected_expression(&mut self,e:dm_syntax::ProjectedExprView<'_>,chain:bool)->VisitDecision{let leaf=match dm_analysis::original_base_terms::leaf_using(e.original(),&mut||self.source.checkpoint()){Ok(leaf)=>leaf,Err(actual)=>{if self.error.is_none(){self.error=Some(Failure::Operational(actual))}return VisitDecision::Stop}};let Some(current)=e.current_span_of(leaf)else{self.error=Some("ctor projected new term lacks exact current origin".into());return VisitDecision::Stop};self.event(e.original(),current,chain)}
 fn frame_capacity(&mut self,bytes:usize)->Result<(),&'static str>{match charge(self.source,Some(bytes)){Ok(())=>Ok(()),Err(e)=>{if self.error.is_none(){self.error=Some(e)}Err("ctor new visitor admission failed")}}}
 fn frame_overflow(&mut self)->&'static str{if self.error.is_none(){self.error=Some(overflow(self.source));}"ctor new visitor frame overflow"}
 fn frame_allocation_failed(&mut self)->&'static str{if self.error.is_none(){self.error=Some(overflow(self.source));}"ctor new visitor allocation failed"}
}
pub(crate) fn observe(source:&ReadSource<'_>,declared:&Declared,scratch_parent:&std::sync::Arc<Budget>)->Result<(Vec<DeadArg>,Vec<ForwardOnly>),Failure>{
 source.checkpoint()?;source.require()?;let ctors=Ctors{scratch_parent,source,declared,memo:Default::default()};let mut dead=BTreeMap::new();let mut forward=Vec::new();
 let inputs=source.inputs();let archive=inputs.archive();let mut work=GroupWork{source,peak:0};
 dm_analysis::original_callable_groups::visit_source_values_using(inputs,&mut work,&mut|ordinal,_,_|{Source::with_body(source,ordinal,&mut|body|{
  let mut emit=|span:Span,ty:&str,args:&[Expr]|->Result<(),Failure>{source.checkpoint()?;if args.len()<2||!source.is_subtype(ty,"/atom")?{return Ok(())}let mut positions=Vec::new();for pos in 1..args.len(){source.checkpoint()?;if !is_null(&args[pos])&&!ctors.taken(ty,pos)?{reserve(source,&mut positions)?;positions.push(pos);}}if positions.is_empty(){return Ok(())}let(rel,line)=source.site(ordinal,span.start)?;charge(source,rel.len().checked_add(ty.len()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(1024)))?;let ty=copy(source,ty)?;dead.insert((copy(source,&rel)?,line,copy(source,&ty)?),DeadArg{rel,line,ty,passed:args.len()-1,dead:positions});Ok(())};
  let mut news=News{source,body,emit:&mut emit,error:None};let coverage=dm_analysis::policy_body_observation::observe_base_chains(body.statement_body().view(),&mut news);if let Some(actual)=news.error{return Err(actual)}coverage.map_err(Failure::from)?;Ok(())
 })})?;
 for ty in source.tree().types(){source.checkpoint()?;let owner=source.tree().symbols().text(ty.path).ok_or("ctor forward owner spelling absent")?;if framework(owner)||!source.is_subtype(owner,"/atom")?{continue}
  for name in CTORS{source.checkpoint()?;dm_analysis::setter_publication_native::visit_own_values_using(inputs,owner,name,&mut work,&mut|ordinal,_,_|{Source::with_body(source,ordinal,&mut|body|{
   let parameters=body.source_parameters()?;let rows=parameters.entries()?;if rows.len()<2||reads_outside_parent_call(source,body,"args",scratch_parent)?{return Ok(())}let mut drop=Vec::new();for row in rows.iter().skip(1).rev(){source.checkpoint()?;let parameter=parameters.name(row)?;if parameter=="..."||reads_outside_parent_call(source,body,parameter,scratch_parent)?{break}reserve(source,&mut drop)?;drop.push(copy(source,parameter)?);}if drop.is_empty(){return Ok(())}drop.reverse();let(rel,line)=source.callable_header_site(ordinal)?;reserve(source,&mut forward)?;forward.push(ForwardOnly{rel,line,owner:copy(source,owner)?,name:copy(source,name)?,params:drop});Ok(())
  })})?;}
 }
 let mut output=Vec::new();for(_,row)in dead{reserve(source,&mut output)?;output.push(row);}kc::sort_data(&mut forward,&mut|a,b|->Result<std::cmp::Ordering,Failure>{source.checkpoint()?;Ok(a.cmp(b))})?;source.require()?;source.checkpoint()?;Ok((output,forward))
}

struct GroupWork<'a>{source:&'a dyn Source,peak:usize}
impl dm_analysis::policy_body_demand::WorkspaceWork for GroupWork<'_>{type Error=Failure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Failure>{self.source.budget().require().map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;self.source.checkpoint()?;self.source.budget().require().map_err(|m|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,m)))?;self.source.require()}fn retain(&mut self,bytes:usize)->Result<(),Failure>{charge(self.source,Some(bytes))}fn temporary(&mut self,bytes:usize)->Result<(),Failure>{if bytes>self.peak{charge(self.source,Some(bytes-self.peak))?;self.peak=bytes;}Ok(())}fn overflow(&mut self)->Failure{overflow(self.source)}fn allocation_failed(&mut self)->Failure{overflow(self.source)}fn body<'a>(&mut self,_:&'a dm_tree::frontend::BodyArchive,_:usize)->Result<dm_tree::frontend::ArchivedBody<'a>,Failure>{Err("ctor group metadata cannot issue a body; SAME active Source borrower required".into())}}

#[cfg(test)]mod sibling_read_scratch_tests{
 use super::*;
 #[test]fn canonical_null_is_bare_keyword_not_group_string_or_identifier(){
  for(source,expected)in [("null",true),("(null)",false),("\"null\"",false),("value",false)]{
   let parsed=dm_syntax::parse_expression(source);assert!(parsed.diagnostics.is_empty(),"{source}: {:?}",parsed.diagnostics);
   assert_eq!(dm_analysis::original_base_terms::is_null_term(parsed.expr.as_ref().unwrap()),expected,"{source}");
  }
 }

 #[test]fn ctor_read_scratch_dies_without_refunding_live_phase_metadata(){let root=Budget::new(64*1024).unwrap();let before=root.used();let fixed=std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>();let phase=Budget::scoped_temporaries(&root).unwrap();phase.charge(4096).unwrap();let live=root.used();assert!(with_read_scratch(&root,|read|{read.charge(8192).unwrap();phase.require().unwrap();Ok(true)}).unwrap());assert_eq!(root.used(),live+fixed);drop(phase);assert_eq!(root.used(),before+2*fixed);}
 #[test]fn ctor_read_failure_keeps_original_error_and_funded_payload(){let root=Budget::new(64*1024).unwrap();let phase=Budget::scoped_temporaries(&root).unwrap();phase.charge(4096).unwrap();let live=root.used();let failure=with_read_scratch(&root,|read|{read.charge(8192).unwrap();Err(Failure::Operational(io::Error::from_raw_os_error(1450)))}).unwrap_err();assert!(matches!(failure,Failure::Operational(error)if error.raw_os_error()==Some(1450)));assert!(root.used()>=live+8192);phase.require().unwrap();}
}
