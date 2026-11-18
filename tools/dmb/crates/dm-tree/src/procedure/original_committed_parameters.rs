//! Transient actual primary formal-root loan at callable commit.
//! No public root marker, copied AST or final source/frame is issued here.
use super::*;
use crate::procedure::header_input::{RetainedFormalRoot,retain_completed_formal_root};
use crate::procedure::FormalExpressionRole;
use dm_syntax::{ParameterDefaultSyntaxProvider,ParameterExpressions,SettingExpression,ParameterClauseSpans};
use std::io;
fn invalid(message:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidData,message)}
// Payload drops before its actual temporary directory credit, including errors.
struct RetainedRoots{rows:Vec<RetainedFormalRoot>,_storage:Option<dm_syntax::SettingRootLease>}
struct Loans<'a,'budget>{
 header:Span,argument_offset:usize,clauses:Option<&'a super::super::FormalClauseRows>,
 roots:&'a[RetainedFormalRoot],inputs:&'a[PendingInput],
 notices:Option<&'a super::super::original_formal_notices::FormalNotices>,
 a:&'a SettingAdmission<'budget>,
}
impl Loans<'_,'_>{
 fn clauses_for(&self,parameter:usize)->Result<ParameterClauseSpans,&'static str>{
  let mut parts=self.clauses.and_then(|rows|rows.get(parameter)).ok_or("actual produced committed formal clauses are unissued")?;
  let origin=self.header.start.checked_add(self.argument_offset).ok_or("actual committed formal clause origin overflow")?;
  let shift=|span:Span|->Result<Span,&'static str>{Ok(Span::new(span.start.checked_add(origin).ok_or("actual committed clause coordinate overflow")?,span.end.checked_add(origin).ok_or("actual committed clause coordinate overflow")?))};
  parts.parameter=shift(parts.parameter)?;parts.assignment=parts.assignment.map(shift).transpose()?;parts.annotation=parts.annotation.map(shift).transpose()?;parts.source=parts.source.map(shift).transpose()?;parts.post_source_annotation=parts.post_source_annotation.map(shift).transpose()?;Ok(parts)
 }
 fn root(&self,parameter:usize,role:FormalExpressionRole,marker:Span,enclosure:Option<Span>,expression:Span)->Result<SettingExpression,&'static str>{
  let at=self.roots.binary_search_by_key(&(parameter,role),|row|(row.parameter,row.role)).map_err(|_|"actual committed formal root is unissued")?;let row=&self.roots[at];
  if row.header!=self.header||row.assignment!=marker||row.enclosure!=enclosure||row.root.current_offset()!=0||row.root.original_expression().span!=expression{return Err("committed formal root belongs to another actual occurrence")}
  Ok(row.root.clone())
 }
}
impl ParameterDefaultSyntaxProvider for Loans<'_,'_>{
 fn produced_clauses(&mut self,parameter:usize,span:Span)->Result<ParameterClauseSpans,&'static str>{let mut parts=self.clauses_for(parameter)?;if span.start<parts.parameter.start||span.end>parts.parameter.end{return Err("requested committed formal view escapes actual clause")};for marker in[parts.assignment,parts.annotation,parts.source,parts.post_source_annotation].into_iter().flatten(){if marker.start<span.start||marker.end>span.end{return Err("committed formal view cuts an actual marker")}}parts.parameter=span;Ok(parts)}
 fn default_root(&mut self,parameter:usize,marker:Span,expression:Span)->Result<SettingExpression,&'static str>{self.root(parameter,FormalExpressionRole::Default,marker,None,expression)}
 fn source_root(&mut self,parameter:usize,marker:Span,expression:Span)->Result<SettingExpression,&'static str>{self.root(parameter,FormalExpressionRole::Source,marker,None,expression)}
 fn dimension_root(&mut self,parameter:usize,index:usize,brackets:Span,expression:Span)->Result<SettingExpression,&'static str>{let role=FormalExpressionRole::Dimension(index);let at=self.roots.binary_search_by_key(&(parameter,role),|row|(row.parameter,row.role)).map_err(|_|"actual committed dimension root is unissued")?;self.root(parameter,role,self.roots[at].assignment,Some(brackets),expression)}
 fn trailing_semicolon(&mut self,_:usize,at:Span)->Result<(),&'static str>{let notices=self.notices.ok_or("actual committed semicolon notice owner absent")?;if !notices.for_header(self.header.start).iter().any(|row|row.notice.is_semicolon()&&row.notice.span()==at){return Err("actual committed semicolon was not produced for this header")}Ok(())}
 fn input_annotation(&mut self,parameter:usize,marker:Span,span:Span,after_in:bool)->Result<dm_syntax::RetainedParameterInput,&'static str>{
  let at=self.inputs.binary_search_by_key(&(self.header.start,parameter,marker.start),|row|(row.live.start(),row.parameter,row.marker.start)).map_err(|_|"actual committed input annotation is unissued")?;let row=&self.inputs[at];
  let(actual_span,actual_after)=match &*row.input{dm_syntax::ParameterInputSyntax::EmptyParens{span,after_in}|dm_syntax::ParameterInputSyntax::Union{span,after_in,..}=>(*span,*after_in)};
  if row.marker!=marker||actual_span!=span||actual_after!=after_in||!row.input.is_admitted_by(self.a){return Err("committed annotation belongs to another actual occurrence or resource owner")}Ok(row.input.clone())
 }
 fn native_child_observation(&mut self,parameter:usize,expressions:Option<&ParameterExpressions>)->Result<Option<(bool,bool,bool)>,&'static str>{
  let _actual=self.clauses_for(parameter)?;let first=self.roots.partition_point(|row|row.parameter<parameter);let last=self.roots.partition_point(|row|row.parameter<=parameter);let rows=&self.roots[first..last];let(mut complete,mut recovered,mut deferred,mut count)=(true,false,false,0usize);
  let mut check=|root:&SettingExpression,role:FormalExpressionRole|->Result<(),&'static str>{let mut found=rows.iter().filter(|row|row.header==self.header&&row.parameter==parameter&&row.role==role&&row.root.same_root(root));let row=found.next().ok_or("committed child has no same-occurrence producer observation")?;if found.next().is_some()||row.root.current_offset()!=0||row.root.original_expression().span!=root.original_expression().span{return Err("committed child occurrence is ambiguous or projected")}complete&=row.native_children&1!=0;recovered|=row.native_children&2!=0;deferred|=row.native_children&4!=0||row.native_children&8==0;count+=1;Ok(())};
  if let Some(expressions)=expressions{if let Some(root)=expressions.default_root(){check(root,FormalExpressionRole::Default)?;}if let Some(root)=expressions.source_root(){check(root,FormalExpressionRole::Source)?;}for(index,root)in expressions.dimensions().iter().enumerate(){if let Some(root)=root{check(root,FormalExpressionRole::Dimension(index))?;}}}
  if rows.len()!=count{return Err("committed parameter settlement omitted a produced child")}Ok(Some((complete&&!recovered&&!deferred,recovered,deferred)))
 }
}
impl OriginalSignatureObserver<'_,'_>{
 pub(crate) fn prepare_committed_parameters(&mut self,input:&dm_syntax::OriginalCommittedBodyInput<'_,'_>)->io::Result<dm_syntax::SharedParameterSignature>{
  let a=self.a;checkpoint(a)?;let header=input.item().header_span;
  if !input.literal_facts().admitted_by(a)||self.rows.producers.first_different.is_some()||self.rows.producers.first_unbound.is_some()||self.rows.producers.first.as_ref().is_none_or(|(_,producer)|!input.primary_producer().same_producer(producer)){return Err(invalid("committed parameters lack the same actual primary producer"))}
  let ordinal=self.rows.find(header.start).ok_or_else(||invalid("actual committed header signature absent"))?;let row=self.rows.get(ordinal).ok_or_else(||invalid("actual committed header row absent"))?;let geometry=self.rows.geometry(ordinal,row);if geometry.header!=header{return Err(invalid("committed parameter header differs from its actual completed row"))}
  let parameters=self.rows.parameters(row).ok_or_else(||invalid("actual committed parameter metadata already consumed"))?;
  let clauses=match row.slot.value(){SlotValue::Taken=>return Err(invalid("actual committed header was already consumed")),SlotValue::Trivial(flags,_)=>{if !flags.clauses_complete{return Err(invalid("actual trivial clause production incomplete"))}None},SlotValue::Payload(index)=>{let core=self.rows.payloads.get(index).and_then(Option::as_ref).ok_or_else(||invalid("actual committed clause payload absent"))?;if !core.original_clauses_complete{return Err(invalid("actual committed clause production incomplete"))}Some(&core.original_clauses)}};
  let mut first=self.defaults.find(header.start,|_,pending|pending.live.start()).unwrap_or(self.defaults.len());while first>0&&self.defaults.get(first-1).is_some_and(|pending|pending.live.start()==header.start){checkpoint(a)?;first-=1;}
  let mut last=first;while let Some(pending)=self.defaults.get(last).filter(|pending|pending.live.start()==header.start){checkpoint(a)?;if pending.root.is_none()||!input.primary_producer().same_header_producer(&pending.live){return Err(invalid("committed default was consumed or belongs to another primary epoch"))}last+=1;}
  let count=last.checked_sub(first).ok_or_else(||invalid("committed root range reversed"))?;let mut roots=if count==0{RetainedRoots{rows:Vec::new(),_storage:None}}else{let(rows,credit)=allocate_funded_rows::<RetainedFormalRoot>(count,a)?;RetainedRoots{rows,_storage:Some(credit)}};
  for index in first..last{checkpoint(a)?;let pending=self.defaults.get_mut(index).ok_or_else(||invalid("committed pending root disappeared"))?;let root=pending.root.take().ok_or_else(||invalid("committed root was already moved"))?;let parameter=parameters.get(root.parameter).ok_or_else(||invalid("committed root parameter ordinal absent"))?;let retained=retain_completed_formal_root(input.source(),input.token_window(),||Ok(Some(input.literal_facts())),header,geometry.argument_offset,parameter,&self.symbols,root,pending.native_children,a)?;roots.rows.push(retained);}
  // retain_formal_input authenticates strictly increasing (header,parameter,marker).
  // Borrow only this actual occurrence; no per-proc scan of accumulated inputs.
  let input_first=self.inputs.partition_point(|pending|pending.live.start()<header.start);
  let input_last=self.inputs.partition_point(|pending|pending.live.start()<=header.start);
  let actual_inputs=&self.inputs[input_first..input_last];
  for pending in actual_inputs{checkpoint(a)?;if !input.primary_producer().same_header_producer(&pending.live)||!pending.input.is_admitted_by(a){return Err(invalid("committed annotation belongs to another actual producer"))}}
  let width=header.end.checked_sub(header.start).ok_or_else(||invalid("committed header extent reversed"))?;let allowance=width.checked_mul(128).and_then(|n|n.checked_add(1024)).ok_or(io::ErrorKind::OutOfMemory)?;let envelope=width.checked_mul(512).and_then(|n|n.checked_add(8192)).and_then(|n|n.checked_add(dm_syntax::SharedParameterSignature::retention_envelope())).ok_or(io::ErrorKind::OutOfMemory)?;let lease=a.reserve(envelope).map_err(|proxy|a.take_operational_error().unwrap_or(proxy))?;
  let tape=input.token_window();let start=tape.partition_point(|token|token.span.end<=header.start);let end=tape.partition_point(|token|token.span.start<header.end);let tokens=tape.range(start,end).ok_or_else(||invalid("actual committed header token view absent"))?;
  let mut loans=Loans{header,argument_offset:geometry.argument_offset,clauses,roots:&roots.rows,inputs:actual_inputs,notices:self.notices.as_ref().filter(|_|self.notices_complete),a};
  let mut signature=tokens.with_dense_using(a,|dense|Ok(dm_syntax::parameter_signature_original_with_native_observation(input.source(),dense,header,0,&mut Some(&mut loans))))?;
  checkpoint(a)?;signature.admit_optional_expressions(allowance);if signature.retained_bytes()>allowance{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"actual committed header metadata exceeded its original allowance"))}
  dm_syntax::SharedParameterSignature::retained_using(signature,lease,a)
 }
}
#[cfg(test)]#[test]fn pending_committed_parameter_move_does_not_grow_actual_pending_rows(){#[allow(dead_code)]struct Prior{live:dm_syntax::OriginalPrimaryLiveHeader,root:super::super::CompletedFormalRoot,native_children:u8}let old=std::mem::size_of::<Prior>();let new=std::mem::size_of::<PendingDefault>();eprintln!("COMMITTED_PENDING_DEFAULT_SIZE prior={old} current={new}");assert!(new<=old,"take-once default handoff must not grow every pending row");}
