//! Canonical BODY expression adapter for the unique pooled-context judge.
//! This observes borrowed DATA only. The enclosing captured partial-purpose
//! owner remains responsible for current source, candidate and BODY availability.
use crate::{sem_handlers_escape_policy as judge,key_policy_control::{self as kc,Control},reactive_reads_native::Failure};
use dm_syntax::{Expr,ExprKind,Span,Statement,StatementKind,VisitDecision};
use std::collections::BTreeSet;
fn ungroup(mut e:&Expr)->&Expr{while let ExprKind::Group(inner)=&e.kind{e=inner}e}
fn bare(e:&Expr)->Option<&str>{if let ExprKind::Ident(name)=&ungroup(e).kind{Some(name)}else{None}}
impl judge::Expression for Expr{
 fn bare_name(&self)->Option<&str>{bare(self)}
 fn named_rhs(&self)->Option<&Self>{if let ExprKind::Binary{op,rhs,..}=&self.kind{if op=="="{return Some(rhs)}}None}
}
struct Visitor<'a,C,F>{acts:&'a BTreeSet<String>,locals:&'a BTreeSet<String>,control:&'a mut C,emit:&'a mut F,named:Vec<usize>,error:Option<Failure>}
impl<C:Control<Error=Failure>,F:FnMut(Span,String)->Result<(),Failure>> Visitor<'_,C,F>{
 fn fail(&mut self,e:Failure)->VisitDecision{if self.error.is_none(){self.error=Some(e)}VisitDecision::Stop}
 fn store(&mut self,lhs:&Expr,rhs:&Expr,named:bool,at:Span)->Result<(),Failure>{judge::store_using(bare(lhs),bare(rhs),named,self.acts,self.locals,self.control,&mut|message|(self.emit)(at,message))}
 fn statement_inner(&mut self,node:&Statement)->Result<(),Failure>{self.control.checkpoint()?;if let StatementKind::Assign{target,op,value}=&node.kind{if dm_analysis::checker_original_expression_debug::original_assignment_operator(op){self.store(target,value,false,node.header_span)?;}}Ok(())}
 fn expression_inner(&mut self,node:&Expr,chain_child:bool,at:Span)->Result<(),Failure>{
  self.control.checkpoint()?;
  if let ExprKind::Binary{op,lhs,rhs}=&node.kind{if dm_analysis::checker_original_expression_debug::original_assignment_operator(op){let marked=self.named.contains(&(node as*const Expr as usize));self.store(lhs,rhs,marked,at)?;}}
  if chain_child{return Ok(())}
  let mut calls=Vec::new();let mut cursor=node;
  loop{
   self.control.checkpoint()?;
   let call=match &cursor.kind{
    ExprKind::Call{callee,args}=>match &callee.kind{
     ExprKind::Ident(name)if name=="list"||name=="alist"=>Some(judge::Call{kind:judge::CallKind::List,args:args.as_slice()}),
     ExprKind::Ident(name)if name=="new"=>Some(judge::Call{kind:judge::CallKind::New,args:args.as_slice()}),
     ExprKind::Ident(name)if dm_analysis::original_base_terms::ordinary_call_name(name)=>Some(judge::Call{kind:judge::CallKind::Ordinary(name),args:args.as_slice()}),
     ExprKind::Member{selector,..}|ExprKind::SafeMember{selector,..}=>Some(judge::Call{kind:judge::CallKind::Follow(selector),args:args.as_slice()}),
     // StaticMember is a proc-reference, not the old Follow::Call.
     _=>None,
    },
    ExprKind::Unary{op,value}if op=="new"=>if let ExprKind::Call{args,..}=&value.kind{Some(judge::Call{kind:judge::CallKind::New,args:args.as_slice()})}else{None},
    _=>None,
   };
   if let Some(call)=call{kc::row(self.control,&mut calls)?;calls.push(call);}
   let Some(next)=dm_analysis::original_base_terms::base_child(cursor)else{break};cursor=next;
  }
  calls.reverse();
  // Unique judge invokes mark callbacks before report callbacks. Admit every
  // possible new mark BEFORE borrowing the shared control into that judge.
  let additional=calls.iter().filter(|call|!matches!(call.kind,judge::CallKind::List)).try_fold(0usize,|n,call|n.checked_add(call.args.len())).ok_or_else(||self.control.overflow())?;
  let required=self.named.len().checked_add(additional).ok_or_else(||self.control.overflow())?;
  if required>self.named.capacity(){kc::reserve(self.control,||required.checked_mul(std::mem::size_of::<usize>())?.checked_mul(2)?.checked_add(64))?;self.named.try_reserve_exact(required-self.named.len()).map_err(|_|self.control.allocation_failed())?;if self.named.capacity()>required.saturating_mul(2).max(8){return Err(self.control.allocation_failed())}}
  let named=&mut self.named;let emit=&mut self.emit;
  judge::base_using(&calls,self.acts,self.control,&mut|arg|{named.push(arg as*const Expr as usize);Ok(())},&mut|message|emit(at,message))
 }
}
impl<C:Control<Error=Failure>,F:FnMut(Span,String)->Result<(),Failure>> dm_analysis::policy_body_observation::BaseChainVisitor for Visitor<'_,C,F>{
 fn statement(&mut self,node:&Statement)->VisitDecision{if self.error.is_some(){return VisitDecision::Stop}match self.statement_inner(node){Ok(())=>VisitDecision::Descend,Err(e)=>self.fail(e)}}
 fn expression(&mut self,_:&Expr,_:bool)->VisitDecision{self.fail("context escape requires actual statement-coordinate callbacks".into())}
 fn expression_at(&mut self,node:&Expr,chain:bool,at:Span)->VisitDecision{if self.error.is_some(){return VisitDecision::Stop}match self.expression_inner(node,chain,at){Ok(())=>VisitDecision::Descend,Err(e)=>self.fail(e)}}
 fn projected_expression(&mut self,_:dm_syntax::ProjectedExprView<'_>,_:bool)->VisitDecision{self.fail("context escape requires actual projected coordinate callbacks".into())}
 fn projected_expression_at(&mut self,node:dm_syntax::ProjectedExprView<'_>,chain:bool,at:Span)->VisitDecision{self.expression_at(node.original(),chain,at)}
 fn frame_capacity(&mut self,n:usize)->Result<(),&'static str>{match self.control.reserve(n){Ok(())=>Ok(()),Err(e)=>{self.fail(e);Err("context escape frame admission refused")}}}
 fn frame_overflow(&mut self)->&'static str{let e=self.control.overflow();self.fail(e);"context escape frame overflow"}
 fn frame_allocation_failed(&mut self)->&'static str{let e=self.control.allocation_failed();self.fail(e);"context escape frame allocation failed"}
}
pub(crate) fn collect_using<C:Control<Error=Failure>>(body:dm_syntax::StatementView<'_>,acts:&BTreeSet<String>,locals:&BTreeSet<String>,control:&mut C,mut emit:impl FnMut(Span,String)->Result<(),Failure>)->Result<(),Failure>{
 control.checkpoint()?;let mut visitor=Visitor{acts,locals,control,emit:&mut emit,named:Vec::new(),error:None};
 let coverage=dm_analysis::policy_body_observation::observe_base_chains(body,&mut visitor);
 if let Some(actual)=visitor.error{return Err(actual)}coverage.map_err(Failure::from)?;visitor.control.checkpoint()?;Ok(())
}
#[cfg(all(test,feature="legacy-sem"))]#[path="../fixtures/native-sem-handlers/oracle.rs"]mod immutable;
#[cfg(all(test,feature="legacy-sem"))]mod old_source_controls{
 use super::*;
 #[test]fn canonical_native_escape_observer_matches_frozen_old_body_including_named_list_and_follow_order(){
  for written in ["saved = A","f(with = A)","list(A)","list(with = A)","items.Insert(A, with = A)","new /datum(with = A)","f(with = A).Insert(A, with = A)","alias = A","target::reference(ignored = A)"]{
   let text=format!("/datum/probe\n    var/saved\n    var/list/items\n    proc/p(datum/act/A)\n        {written}\n");
   let tree=crate::tree::Tree::from_files(vec![crate::tree::SourceFile::from_text("code/escape.dm",&text)]);let old=crate::sem::sem_for(&tree).unwrap();let call=old.proc_ref("/datum/probe","p").unwrap();let old_body=old.proc_body(call);let mut expected=Vec::new();let acts=BTreeSet::from(["A".to_owned()]);let locals=BTreeSet::from(["A".to_owned(),"alias".to_owned()]);immutable::checks::context_escape(old_body.code.unwrap(),&acts,&locals,&mut expected);
   let syntax=dm_syntax::parse(&text);let proc=&syntax.items[0].children.iter().find(|item|matches!(item.kind,dm_syntax::ItemKind::Proc)).unwrap();let body=dm_syntax::parse_proc_body(proc);assert!(body.diagnostics.is_empty(),"{written}: {:?}",body.diagnostics);
   let budget=crate::captured_generator_budget::Budget::new(8*1024*1024).unwrap();let mut c=crate::captured_allow_annotations::Operation{budget:&budget,poll:&||Ok(())};let mut actual=Vec::new();collect_using(dm_syntax::StatementView::from_parsed(&body),&acts,&locals,&mut c,|at,message|{let line=text[..at.start].bytes().filter(|b|*b==b'\n').count()as u32+1;actual.push((line,message));Ok(())}).unwrap();assert_eq!(actual,expected.into_iter().map(|row|(row.line,row.msg)).collect::<Vec<_>>(),"{written}");
  }
 }
}
