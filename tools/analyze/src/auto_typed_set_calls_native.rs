//! Typed setter call facts from the SAME original admitted bodies and metadata.
//! Exact receiver quirks live in typed_set_calls_policy, shared with legacy.
use crate::{reactive_original_source::ReadSource,reactive_global_source::{Source as GlobalSource,Body as GlobalBody},reactive_reads_native::Failure,key_policy_control::{self as kc,Control},typed_set_calls_policy as policy};
use dm_syntax::{Expr,ExprKind,Statement,StatementKind,ForControl,TypedVisitor,VisitDecision,NodeStep};
use std::{collections::HashMap,io,mem::size_of};
fn denial()->Failure{Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"typed setter-call admission refused"))}
fn require(source:&dyn GlobalSource)->Result<(),Failure>{{let pending=source.require();if matches!(&pending,Err(Failure::Operational(_))){return pending}if source.budget().denied(){return Err(denial())}pending}}
fn reserve(source:&dyn GlobalSource,bytes:Option<usize>)->Result<(),Failure>{bytes.ok_or_else(denial).and_then(|n|source.budget().charge(n).map_err(|_|denial()))}
/// The old map/set meaning, stored once as sorted unique policy rows.
pub(crate) struct TypedSetterCalls{rows:Vec<(String,String)>}
impl TypedSetterCalls{
 pub(crate) fn contains(&self,name:&str,receiver:&str)->bool{self.rows.binary_search_by(|row|row.0.as_str().cmp(name).then_with(||row.1.as_str().cmp(receiver))).is_ok()}
 pub(crate) fn entries(&self)->&[(String,String)]{&self.rows}
 pub(crate) fn visit_storage(&self,mut visit:impl FnMut(usize,usize)){visit(self.rows.as_ptr() as usize,self.rows.capacity()*size_of::<(String,String)>());for(name,receiver)in &self.rows{visit(name.as_ptr() as usize,name.capacity());visit(receiver.as_ptr() as usize,receiver.capacity());}}
 fn push(&mut self,source:&dyn GlobalSource,name:&str,receiver:&str)->Result<(),Failure>{
  source.checkpoint()?;require(source)?;
  reserve(source,name.len().checked_add(receiver.len()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(256)))?;
  if self.rows.len()==self.rows.capacity(){let cap=self.rows.capacity().max(4).checked_mul(2).ok_or_else(denial)?;reserve(source,cap.checked_mul(size_of::<(String,String)>()).and_then(|n|n.checked_mul(4)))?;let mut next=Vec::new();next.try_reserve_exact(cap).map_err(|actual|{source.budget().deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual))})?;if next.capacity()>cap*4{source.budget().deny();return Err(denial())}next.append(&mut self.rows);self.rows=next;}
  self.rows.push((name.to_owned(),receiver.to_owned()));Ok(())
 }
}
impl serde::Serialize for TypedSetterCalls{fn serialize<S:serde::Serializer>(&self,serializer:S)->Result<S::Ok,S::Error>{use serde::ser::{SerializeMap,SerializeSeq};struct Receivers<'a>(&'a[(String,String)]);impl serde::Serialize for Receivers<'_>{fn serialize<S:serde::Serializer>(&self,serializer:S)->Result<S::Ok,S::Error>{let mut values=serializer.serialize_seq(Some(self.0.len()))?;for row in self.0{values.serialize_element(&row.1)?;}values.end()}}let mut map=serializer.serialize_map(None)?;let mut at=0;while at<self.rows.len(){let mut end=at+1;while end<self.rows.len()&&self.rows[end].0==self.rows[at].0{end+=1;}map.serialize_entry(&self.rows[at].0,&Receivers(&self.rows[at..end]))?;at=end;}map.end()}}
impl TypedSetterCalls{pub(crate) fn retained_charge(&self)->Option<usize>{let mut bytes=Some(size_of::<Self>());self.visit_storage(|_,n|bytes=bytes.and_then(|old|old.checked_add(n)));bytes}}
impl crate::auto_tracking_policy::TypedCalls for TypedSetterCalls{fn receivers(&self,name:&str)->Option<crate::auto_tracking_policy::TypedReceivers<'_>>{let start=self.rows.partition_point(|row|row.0.as_str()<name);let end=self.rows.partition_point(|row|row.0.as_str()<=name);(start<end).then(||crate::auto_tracking_policy::TypedReceivers::Rows(self.rows[start..end].iter()))}}
struct Native<'a>{source:&'a dyn GlobalSource,retained:&'a dyn GlobalSource,out:&'a mut TypedSetterCalls}
impl Control for Native<'_>{
 type Error=Failure;const CHECKED:bool=true;
 fn checkpoint(&mut self)->Result<(),Failure>{self.source.checkpoint()?;require(self.source)}
 fn reserve(&mut self,n:usize)->Result<(),Failure>{reserve(self.source,Some(n))}
 fn overflow(&mut self)->Failure{self.source.budget().deny();denial()}
 fn allocation_failed(&mut self)->Failure{self.source.budget().deny();denial()}
}
impl policy::Source for Native<'_>{
 fn variable_type(&mut self,owner:&str,name:&str)->Result<Option<String>,Failure>{let pending=self.source.variable_type(owner,name);if matches!(&pending,Err(Failure::Operational(_))){return pending}self.source.checkpoint()?;require(self.source)?;pending.map_err(Failure::from)}
 fn record(&mut self,name:&str,receiver:&str)->Result<(),Failure>{self.out.push(self.retained,name,receiver)}
}
struct Locals<'a>{source:&'a dyn GlobalSource,body:&'a dyn GlobalBody,types:HashMap<String,String>,error:Option<Failure>}
impl Locals<'_>{
 fn add(&mut self,name:&str,ty:Option<String>)->Result<(),Failure>{if let Some(ty)=ty.filter(|ty|!ty.is_empty()){reserve(self.source,name.len().checked_add(ty.len()).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(1024)))?;self.types.insert(name.to_owned(),ty);}Ok(())}
 fn statement_checked(&mut self,statement:&Statement)->Result<(),Failure>{self.source.checkpoint()?;require(self.source)?;if matches!(&statement.kind,StatementKind::Var{..}|StatementKind::For{control:ForControl::All{..}|ForControl::Each{..},..}){let view=self.body.source_locals()?;for entry in view.in_span(statement.header_span)?{self.source.checkpoint()?;reserve(self.source,view.type_path_width(entry)?.checked_mul(8).and_then(|n|n.checked_add(512)))?;self.add(view.name(entry)?,view.type_path(entry)?)?;}}Ok(())}
}
impl TypedVisitor for Locals<'_>{
 fn statement(&mut self,statement:&Statement,_:&[NodeStep])->VisitDecision{if self.error.is_some(){return VisitDecision::Stop}match self.statement_checked(statement){Ok(())=>VisitDecision::Descend,Err(error)=>{self.error=Some(error);VisitDecision::Stop}}}
 fn expression(&mut self,_:&Expr,_:&[NodeStep])->VisitDecision{VisitDecision::Skip}
 fn projected_expression(&mut self,_:dm_syntax::ProjectedExprView<'_>,_:&[NodeStep])->VisitDecision{VisitDecision::Skip}
}
fn receiver(source:&mut Native<'_>,owner:&str,locals:&HashMap<String,String>,mut expression:&Expr)->Result<Option<String>,Failure>{
 let mut fields=Vec::new();loop{source.checkpoint()?;match &expression.kind{ExprKind::Member{object,selector,..}|ExprKind::SafeMember{object,selector,..}=>{kc::row(source,&mut fields)?;fields.push(selector.as_str());expression=object},_=>break}}
 // No group unwrap, call-result inference, index receiver, static-follow or
 // special usr/global rule: these are exactly the old Base/Follow transitions.
 let base=match &expression.kind{ExprKind::Ident(name)if !matches!(name.as_str(),"null"|"__TYPE__"|"__PROC__"|"__IMPLIED_TYPE__")=>policy::Base::Ident(name),_=>policy::Base::Unknown};
 let mut current=policy::begin(source,owner,locals,base)?;for field in fields.into_iter().rev(){current=policy::field(source,current,field)?;}Ok(current)
}
struct Scan<'a>{source:Native<'a>,owner:&'a str,locals:&'a HashMap<String,String>,error:Option<Failure>}
impl Scan<'_>{fn expression_checked(&mut self,e:&Expr)->Result<(),Failure>{self.source.checkpoint()?;if let ExprKind::Call{callee,..}=&e.kind{match dm_syntax::call_target(callee){dm_syntax::CallTarget::Named(name)=>policy::call(&mut self.source,&None,name,Some(self.owner))?,dm_syntax::CallTarget::Member{object,selector}|dm_syntax::CallTarget::SafeMember{object,selector,..}=>{let current=receiver(&mut self.source,self.owner,self.locals,object)?;policy::call(&mut self.source,&current,selector,None)?;},_=>()}}Ok(())}}
impl TypedVisitor for Scan<'_>{
 fn statement(&mut self,_:&Statement,_:&[NodeStep])->VisitDecision{if self.error.is_some(){VisitDecision::Stop}else{match self.source.checkpoint(){Ok(())=>VisitDecision::Descend,Err(error)=>{self.error=Some(error);VisitDecision::Stop}}}}
 fn expression(&mut self,e:&Expr,_:&[NodeStep])->VisitDecision{if self.error.is_some(){return VisitDecision::Stop}match self.expression_checked(e){Ok(())=>VisitDecision::Descend,Err(error)=>{self.error=Some(error);VisitDecision::Stop}}}
 fn projected_expression(&mut self,e:dm_syntax::ProjectedExprView<'_>,path:&[NodeStep])->VisitDecision{self.expression(e.original(),path)}
}
pub(crate) fn collect(source:&ReadSource<'_>)->Result<TypedSetterCalls,Failure>{collect_from(source)}
pub(crate) fn collect_from(source:&dyn GlobalSource)->Result<TypedSetterCalls,Failure>{
 let pending=(||{
  source.checkpoint()?;require(source)?;let mut out=TypedSetterCalls{rows:Vec::new()};
  source.visit_callables(None,&mut||source.checkpoint().map_err(Failure::from),&mut|call|->Result<(),Failure>{
   let scratch=crate::captured_generator_budget::Budget::scoped_temporaries(source.operation_budget()).map_err(|_|denial())?;
   let result=source.with_budget(&scratch,&mut|page|->Result<(),Failure>{
    page.checkpoint()?;require(page)?;let rel=page.relative_body_file(call.ordinal)?;if matches!(rel.as_str(),crate::auto_setter_calls_policy::AUTO_REL|"code/engine/_generated/tracked_lists.dm"){return Ok(())}
    page.with_body(call.ordinal,&mut|body|{
    if !body.statement_body().original_literal_syntax_complete()||!body.statement_body().has_native_literal_syntax(){return Err("typed setter calls require checked original body/literal syntax".into())}
    let mut locals=Locals{source:page,body,types:HashMap::new(),error:None};let params=body.source_parameters()?;
    for parameter in params.entries()?{page.checkpoint()?;reserve(page,parameter.type_components().iter().try_fold(0usize,|n,span|n.checked_add(span.end.checked_sub(span.start)?)).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(1024)))?;locals.add(params.name(parameter)?,params.type_path(parameter)?)?;}
    dm_analysis::policy_body_observation::observe(body.statement_body().view(),&mut locals)?;if let Some(error)=locals.error.take(){return Err(error)}
    let mut scan=Scan{source:Native{source:page,retained:source,out:&mut out},owner:call.owner,locals:&locals.types,error:None};dm_analysis::policy_body_observation::observe(body.statement_body().view(),&mut scan)?;if let Some(error)=scan.error.take(){return Err(error)}Ok(())
    })
   });if result.is_err(){scratch.keep_failed_scratch();}drop(scratch);result
  })?;
  source.checkpoint()?;require(source)?;out.rows.sort_unstable();out.rows.dedup();source.checkpoint()?;require(source)?;Ok(out)
 })();if matches!(&pending,Err(Failure::Operational(_))){return pending}source.checkpoint()?;require(source)?;pending
}

#[cfg(all(test,feature="legacy-sem"))]
#[path="auto_typed_set_calls_native_tests.rs"]mod tests;
