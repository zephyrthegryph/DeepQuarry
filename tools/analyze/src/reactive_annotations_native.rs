//! Native source callbacks for the UNIQUE shared reactive annotation policy.
//! Working DATA; not registered/published before complete read closure tests.
use crate::{reactive_original_source::ReadSource,reactive_reads_native::Failure,reactive_annotations_policy::{self,Annotations,Marker,Source}};
use dm_syntax::{Expr,ExprKind};
use std::{cell::{RefCell,Cell},io};
const MAX_POLICY_VISITS:usize=512;
struct Original<'s,'a,'op>{source:&'s ReadSource<'a>,rows:&'s crate::captured_marker_rows::Rows<'a>,checkpoint:RefCell<&'op mut dyn FnMut()->io::Result<()>>}
impl Original<'_,'_,'_>{
 fn classify(&self,error:String)->Failure{if self.source.budget().denied(){Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,error))}else{Failure::Unsupported(error)}}
 fn poll(&self)->Result<(),Failure>{(self.checkpoint.borrow_mut())()?;self.source.require().map_err(|e|self.classify(e))}
 fn reserve(&self,n:Option<usize>)->Result<(),Failure>{self.source.reserve(n).map_err(|e|self.classify(e))}
}
// Native Member/Index/Unary/Call nodes split an old Base's follow chain. Only
// its FIRST continuation child is a base fragment; Group starts a real nested
// old expression. The existing policy walker always visits that child first.
// This scalar never owns/retains an Expr, source, pointer index or new model.
pub(crate) fn continuation(e:&Expr)->Option<&Expr>{
 let child=match &e.kind{
  ExprKind::Call{callee,..}=>callee.as_ref(),
  ExprKind::Member{object,..}|ExprKind::SafeMember{object,..}|ExprKind::StaticMember{object,..}|ExprKind::Index{object,..}|ExprKind::SafeIndex{object,..}=>object.as_ref(),
  ExprKind::Unary{op,value}if op!="new"=>value.as_ref(),
  ExprKind::TypeFilter{value,..}=>value.as_ref(),
  _=>return None,
 };
 (!matches!(child.kind,ExprKind::Group(_))).then_some(child)
}
impl Source for Original<'_,'_,'_>{
 type Error=Failure;
 fn markers_named(&self,name:&'static str)->impl Iterator<Item=Marker<'_>>{
  self.rows.markers.iter().filter(move|m|m.name==name).map(|m|Marker{name:&m.name,rel:&m.rel,line:m.line,args:&m.args})
 }
 fn owner_candidates(&self,rel:&str,line:u32)->Result<Vec<String>,Failure>{
  self.poll()?;let(before,after)=self.source.definition_neighbors(rel,line,||self.poll())?;
  let bytes=before.map_or(0,|p|p.1.len()).checked_add(after.map_or(0,|p|p.1.len()));self.reserve(bytes.and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(256)))?;
  let mut owners=Vec::new();owners.try_reserve_exact(2).map_err(|e|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,e)))?;
  if let Some((_,owner,_))=before{owners.push(owner.to_owned());}
  if let Some((_,owner,_))=after{if !owners.iter().any(|p|p==owner){owners.push(owner.to_owned());}}
  Ok(owners)
 }
 fn has_own_callable(&self,owner:&str,name:&str)->Result<bool,Failure>{self.poll()?;self.source.own_callable_exists(owner,name).map_err(|e|self.classify(e))}
 fn def_at(&self,rel:&str,line:u32)->Result<Option<(String,String)>,Failure>{
  self.poll()?;let(before,_)=self.source.definition_neighbors(rel,line,||self.poll())?;
  let Some((_,owner,name))=before else{return Ok(None)};
  self.reserve(owner.len().checked_add(name.len()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(256)))?;Ok(Some((owner.to_owned(),name.to_owned())))
 }
 fn admit_marker(&self,m:&Marker<'_>)->Result<(),Failure>{
  self.poll()?;
  // Cross-marker cap-name prefixes are bounded by the SAME original raw roster
  // width. Charge every repeated output prefix, not merely current arg bytes.
  // This intentionally conservative fixture frontier will need count tightening
  // for main; no quota increase or wholeworkspace availability claim.
  let own=m.args.iter().try_fold(0usize,|n,s|n.checked_add(s.len()));let raw_width=self.source.raw_width_checked()?;
  self.reserve(own.and_then(|n|n.checked_add(raw_width)).and_then(|n|n.checked_mul(32)).and_then(|n|n.checked_add(2048)).and_then(|n|n.checked_mul(m.args.len().checked_add(1)?)))
 }
 fn admit_relation(&self,owner:&str,name:&str)->Result<(),Failure>{self.poll()?;self.reserve(owner.len().checked_add(name.len()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(1024)))}
 fn relations(&self,emit:&mut dyn FnMut(&str,&str)->Result<(),Failure>)->Result<(),Failure>{
  for(proc,calls)in[("relations",&["rel_one","rel_many"][..]),("ownership",&["owns","rel_one","rel_many"][..])]{
   self.source.visit_callables(&[proc],||self.poll(),|callable|{
    self.poll()?;let archive=self.source.inputs().archive();
    let body=self.source.parse_body(callable.ordinal).map_err(|e|match e{dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>Failure::Operational(actual),dm_tree::frontend::BodySyntaxFailure::Syntax(error)=>Failure::Unsupported(error.message)})?;
    if !body.statement_body().has_native_literal_syntax(){return Err("reactive annotation needs actual admitted Kind4, not a compatibility owner".into());}
    if !body.statement_body().syntax_complete(){return Err("reactive annotation original body grammar incomplete".into());}
    // Stops BEFORE deep policy recursion can exceed this explicitly bounded
    // port's admitted work. Existing compatibility walker has no new limit.
    self.reserve(Some(MAX_POLICY_VISITS*1024+4096))?;let visits=Cell::new(0usize);
    let mut next_fragment=None;
    let result=dm_analysis::untyped::try_policy_expressions(body.statement_body().view(),&mut ||{
     self.poll()?;let next=visits.get()+1;if next>MAX_POLICY_VISITS{self.source.budget().deny();return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reactive annotation body exceeds bounded policy visits")));}visits.set(next);Ok(())
    },&mut |view,_|{
     let e=view.original();let fragment=next_fragment.take()==Some(e as *const Expr as usize);next_fragment=continuation(e).map(|e|e as *const Expr as usize);
     if fragment{return Ok(())}
     let ExprKind::Call{callee,args}=&e.kind else{return Ok(())};let ExprKind::Ident(name)=&callee.kind else{return Ok(())};if !calls.contains(&name.as_str()){return Ok(())}
     let Some(Expr{kind:ExprKind::Call{callee,args},..})=args.first()else{return Ok(())};
     if !matches!(&callee.kind,ExprKind::Ident(name)if name=="nameof"){return Ok(())}
     if let Some(Expr{kind:ExprKind::Ident(name),..})=args.first(){emit(callable.owner,name)?;}
     Ok(())
    });
    match result{Ok(())=>Ok(()),Err(dm_analysis::untyped::PolicyVisitFailure::Callback(e))=>Err(e),Err(dm_analysis::untyped::PolicyVisitFailure::Unsupported(e))=>Err(e.into())}
   })?;
  }
  self.poll()
 }
}
pub(crate) fn original_annotations(source:&ReadSource<'_>,checkpoint:&mut dyn FnMut()->io::Result<()>)->Result<Annotations,Failure>{
 checkpoint()?;source.require()?;let rows=source.marker_rows_checked(checkpoint)?;
 original_annotations_from_rows(source,&rows,checkpoint)
}
pub(crate) fn original_annotations_from_rows<'a>(source:&ReadSource<'a>,rows:&crate::captured_marker_rows::Rows<'a>,checkpoint:&mut dyn FnMut()->io::Result<()>)->Result<Annotations,Failure>{
 let original=Original{source,rows,checkpoint:RefCell::new(checkpoint)};
 let result=reactive_annotations_policy::build(&original);
 if matches!(&result,Err(Failure::Operational(_))){return result;}
 original.poll()?;result
}
