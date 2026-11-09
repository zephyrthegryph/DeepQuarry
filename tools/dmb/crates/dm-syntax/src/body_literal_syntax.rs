//! Canonical literal children of one ACTUALLY demanded native body.
//! Same ParsedBody/Expr/LiteralText owners; no AST or source is cloned.
use crate::{admitted_worklist::Worklist,Expr,ExprKind,ForControl,ForInitializer,ParsedBody,SettingAdmission,SettingRootLease,SharedSettingRetention,Statement,StatementKind,SwitchAlternative};
use std::{io,mem::size_of};
#[derive(Debug)]
pub struct BodyLiteralAdmission{anchor:SharedSettingRetention}
impl BodyLiteralAdmission{
 pub fn is_admitted_by(&self,a:&SettingAdmission<'_>)->bool{self.anchor.is_admitted_by(a)}
 pub fn visit_storage(&self,visit:impl FnMut(usize,usize)){self.anchor.visit_storage(visit)}
}
/// Opaque completed storage preparation, never standalone source authority.
pub struct PreparedBodyLiteralSyntax{body:Option<ParsedBody>,admission:Option<BodyLiteralAdmission>}
impl PreparedBodyLiteralSyntax{pub fn into_parts(mut self)->(ParsedBody,BodyLiteralAdmission){(self.body.take().unwrap(),self.admission.take().unwrap())}}
impl Drop for PreparedBodyLiteralSyntax{fn drop(&mut self){if let Some(body)=self.body.take(){drop_body_literal_syntax(body,self.admission.take());}}}
fn stop(a:&SettingAdmission<'_>,kind:io::ErrorKind,text:&'static str)->io::Error{a.record_operational_error(io::Error::new(kind,text));kind.into()}
fn add(a:&SettingAdmission<'_>,x:usize,y:usize)->io::Result<usize>{x.checked_add(y).ok_or_else(||stop(a,io::ErrorKind::OutOfMemory,"body literal storage overflow"))}
fn payload<T>(a:&SettingAdmission<'_>,v:&Vec<T>)->io::Result<usize>{v.capacity().checked_mul(size_of::<T>()).ok_or_else(||stop(a,io::ErrorKind::OutOfMemory,"body literal vector storage overflow"))}
struct Pending<'a,'op>{body:Option<ParsedBody>,anchor:Option<SharedSettingRetention>,peaks:Option<Worklist<'a,'op,SettingRootLease>>,cleanup:SettingRootLease}
impl Drop for Pending<'_,'_>{fn drop(&mut self){if let Some(body)=self.body.take(){drop_body_inner(body,self.anchor.take());}}}
struct Collected<'a,'op,'body>{roots:Worklist<'a,'op,&'body Expr>,bytes:usize,statements:usize}
fn collect<'a,'op,'body>(body:&'body ParsedBody,a:&'a SettingAdmission<'op>)->io::Result<Collected<'a,'op,'body>>{
 let mut roots=Worklist::new(a)?;let mut pending=Worklist::new(a)?;let mut bytes=0;let mut count=0;
 macro_rules! charge{($n:expr)=>{bytes=add(a,bytes,$n)?}}
 macro_rules! vec{($v:expr)=>{charge!(payload(a,$v)?);pending.extend($v.iter())?}}
 macro_rules! root{($v:expr)=>{roots.push($v)?}}
 charge!(payload(a,&body.control_origins)?);charge!(payload(a,&body.pending_bodies)?);charge!(payload(a,&body.diagnostics)?);
 for d in &body.diagnostics{charge!(d.message.capacity());}
 charge!(payload(a,body.local_variables.storage())?);
 for row in body.local_variables.storage(){
  charge!(row.type_components.len()*size_of::<crate::Span>());
  if let Some(array)=&row.array_syntax{
   charge!(array.root.brackets.len()*size_of::<crate::Span>());charge!(array.root.dimension_slots.len()*size_of::<Option<usize>>());charge!(array.root.dimensions.len()*size_of::<Expr>());
   for e in &array.root.dimensions{root!(e);}
  }
 }
 vec!(&body.statements);
 while let Some(st)=pending.pop(){
  a.checkpoint()?;count=add(a,count,1)?;charge!(st.raw_header.capacity());
  match &st.kind{
   StatementKind::If{condition,then_branch,else_branch}=>{root!(condition);vec!(then_branch);vec!(else_branch);},
   StatementKind::While{condition,body}|StatementKind::DoWhile{condition,body}=>{root!(condition);vec!(body);},
   StatementKind::Spawn{delay,body}=>{for e in delay{root!(e);}vec!(body);},
   StatementKind::Set{attribute,relation,value}=>{charge!(attribute.capacity());charge!(relation.capacity());root!(value);},
   // Existing canonical Set roots ALREADY own their literal preparation and
   // anchor. Do not parse, shift, graft, remeasure or re-anchor those roots.
   StatementKind::ProjectedSet{attribute,relation,..}=>{charge!(attribute.capacity());charge!(relation.capacity());},
   StatementKind::For{control,body}=>{
    vec!(body);match control{
     ForControl::All{declaration, ..}=>charge!(declaration.capacity()),
     ForControl::Each{binding,iterable, ..}=>{charge!(binding.capacity());root!(iterable);},
     ForControl::Pair{key_binding,value_binding,iterable}=>{charge!(key_binding.capacity());charge!(value_binding.capacity());root!(iterable);},
     ForControl::Range{binding,start,end,step}=>{charge!(binding.capacity());root!(start);root!(end);for e in step{root!(e);}},
     ForControl::RangeImplicitArray{binding,end,step}=>{charge!(binding.capacity());root!(end);for e in step{root!(e);}},
     ForControl::CStyle{initializer,condition,step}=>{
      match initializer{Some(ForInitializer::Declare{declaration,value})=>{charge!(declaration.capacity());for e in value{root!(e);}},Some(ForInitializer::Expr(e))=>root!(e),None=>()}
      for e in condition.iter().chain(step.iter()){root!(e);}
     }
    }
   }
   StatementKind::Switch{selector,cases,else_branch,..}=>{
    root!(selector);vec!(else_branch);charge!(payload(a,cases)?);
    for case in cases{vec!(&case.body);charge!(payload(a,&case.alternatives)?);for alt in &case.alternatives{match alt{SwitchAlternative::Exact(e)=>root!(e),SwitchAlternative::Range(x,y)=>{root!(x);root!(y);}}}}
   }
   StatementKind::Try{body,catch_binding,catch_body,..}=>{vec!(body);vec!(catch_body);if let Some(s)=catch_binding{charge!(s.capacity());}},
   StatementKind::Label{name,body}=>{charge!(name.capacity());vec!(body);},
   StatementKind::Goto(n)|StatementKind::BreakLabel(n)|StatementKind::ContinueLabel(n)=>charge!(n.capacity()),
   StatementKind::Return(value)=>{for e in value{root!(e);}},
   StatementKind::Var{declaration,value}=>{charge!(declaration.capacity());for e in value{root!(e);}},
   StatementKind::Assign{target,op,value}=>{charge!(op.capacity());root!(target);root!(value);},
   StatementKind::Throw(e)|StatementKind::Call(e)|StatementKind::Expression(e)=>root!(e),
   StatementKind::Break|StatementKind::Continue|StatementKind::Unsupported=>(),
  }
 }
 Ok(Collected{roots,bytes,statements:count})
}
fn input_peak(root:&Expr,a:&SettingAdmission<'_>)->io::Result<usize>{
 let mut pending=Worklist::new(a)?;pending.push(root)?;let mut peak=0;
 while let Some(e)=pending.pop(){
  a.checkpoint()?;
  if let ExprKind::Literal(literal)=&e.kind {
   if literal.require_fresh_body_owner(a)? {
    // No parser is entered for this owner. Any existing child can still
    // contain fresh ordinary literals, which need their own peak.
    if let Some(Ok(Some(parts))) = literal.prepared_syntax_parts() {
     pending.extend(parts.expressions.iter())?;
    }
   } else if literal.shared_storage().is_some() {
    peak = add(a, peak, crate::setting_prepare::literal_parser_peak(literal.as_str(),a)?)?;
   }
   continue;
  }
  // This shared child iterator is called ONLY on nonliteral nodes here: no
  // deferred literal parser/cache is entered during resource preflight.
  let mut failed=None;
  crate::for_each_expression_child(e,|_,child|{if failed.is_none(){if let Err(e)=pending.push(child){failed=Some(e);}}});
  if let Some(e)=failed{return Err(e);}
 }
 Ok(peak)
}
/// Parent reserves cleanup BEFORE the original body parser creates the AST.
/// Its source-width envelope covers only failure-cleanup coordination, not a
/// claim that all existing native parser/input allocations are globally capped.
pub fn prepare_body_literal_syntax<'a,'op>(body:ParsedBody,cleanup:SettingRootLease,a:&'a SettingAdmission<'op>)->io::Result<PreparedBodyLiteralSyntax>{
 let mut guard=Pending{body:Some(body),anchor:None,peaks:None,cleanup};
 guard.peaks=Some(Worklist::new(a)?);
 let result:io::Result<BodyLiteralAdmission>=(||{
  let collected=collect(guard.body.as_ref().unwrap(),a)?;let mut bytes=collected.bytes;let mut nodes=collected.statements;
  for root in collected.roots.as_slice(){
   let peak=input_peak(root,a)?;if peak!=0{guard.peaks.as_mut().unwrap().push(a.reserve(peak)?)?;}
   let measured=crate::setting_prepare::prepare_body_measure(root,a)?;
   bytes=add(a,bytes,measured.bytes)?;nodes=add(a,nodes,measured.nodes)?;
  }
  // Final aliases may die after this operation; cleanup capacity is therefore
  // retained with the actual literal buffers, not credited at query return.
  let cleanup_bytes=nodes.checked_mul(4*(size_of::<Expr>()+size_of::<SharedSettingRetention>()+size_of::<Statement>())).ok_or_else(||stop(a,io::ErrorKind::OutOfMemory,"body literal cleanup envelope overflow"))?;
  let retained=add(a,add(a,bytes,cleanup_bytes)?,crate::setting_expression::root_storage_envelope())?;
  // Both cleanup envelopes protect the same destructive walk. A body
  // being unwound has its Pending guard; after publication only the final
  // anchor is needed. The AST payload and other worklists are separate.
  let reusable=if a.matches_lease_domain(&guard.cleanup){guard.cleanup.bytes().min(cleanup_bytes)}else{0};
  let lease=if reusable==0{
   a.reserve(retained)?
  }else{
   // Grow before splitting: denial or cancellation must leave the entire
   // old cleanup allowance alive until Pending has destroyed the body.
   a.grow(&mut guard.cleanup,retained-reusable)?;
   a.split(&mut guard.cleanup,retained)?
  };
  let anchor=SharedSettingRetention::new(lease);guard.anchor=Some(anchor.clone());
  for root in collected.roots.as_slice(){crate::setting_prepare::attach(root,&anchor,a)?;}
  drop(collected);
  crate::statements::complete_body_literal_normalization(guard.body.as_mut().unwrap(),a)?;
  a.checkpoint()?;
  Ok(BodyLiteralAdmission{anchor})
 })();
 let admission=result?;
 let body=guard.body.take().unwrap();Ok(PreparedBodyLiteralSyntax{body:Some(body),admission:Some(admission)})
}
/// Stack-safe original ownership destruction, used before any credit release.
/// This helper creates no syntax, calls no parser and clones no AST/root/source.
pub fn drop_body_literal_syntax(body:ParsedBody,admission:Option<BodyLiteralAdmission>){drop_body_inner(body,admission.map(|a|a.anchor));}
fn drop_body_inner(body:ParsedBody,anchor:Option<SharedSettingRetention>){
 let ParsedBody{mut statements,control_origins,local_variables,diagnostics,pending_bodies,original_grammar:_}=body;
 drop(control_origins);drop(diagnostics);drop(pending_bodies);
 local_variables.drop_dimension_expressions(|e|crate::setting_drop::drop_expression(e,anchor.clone()));
 while let Some(st)=statements.pop(){
  drop(st.raw_header);
  match st.kind{
   StatementKind::If{condition,mut then_branch,mut else_branch}=>{crate::setting_drop::drop_expression(condition,anchor.clone());statements.append(&mut then_branch);statements.append(&mut else_branch);},
   StatementKind::While{condition,mut body}|StatementKind::DoWhile{condition,mut body}=>{crate::setting_drop::drop_expression(condition,anchor.clone());statements.append(&mut body);},
   StatementKind::Spawn{delay,mut body}=>{for e in delay{crate::setting_drop::drop_expression(e,anchor.clone());}statements.append(&mut body);},
   StatementKind::Set{value,..}=>crate::setting_drop::drop_expression(value,anchor.clone()),
   StatementKind::ProjectedSet{value,..}=>drop(value),
   StatementKind::For{control,mut body}=>{
    statements.append(&mut body);
    match control{
     ForControl::All{..}=>(),
     ForControl::Each{iterable,..}|ForControl::Pair{iterable,..}=>crate::setting_drop::drop_expression(iterable,anchor.clone()),
     ForControl::Range{start,end,step,..}=>{crate::setting_drop::drop_expression(start,anchor.clone());crate::setting_drop::drop_expression(end,anchor.clone());for e in step{crate::setting_drop::drop_expression(e,anchor.clone());}},
     ForControl::RangeImplicitArray{end,step,..}=>{crate::setting_drop::drop_expression(end,anchor.clone());for e in step{crate::setting_drop::drop_expression(e,anchor.clone());}},
     ForControl::CStyle{initializer,condition,step}=>{
      match initializer{Some(ForInitializer::Declare{value,..})=>{for e in value{crate::setting_drop::drop_expression(e,anchor.clone());}},Some(ForInitializer::Expr(e))=>crate::setting_drop::drop_expression(e,anchor.clone()),None=>()}
      for e in condition.into_iter().chain(step){crate::setting_drop::drop_expression(e,anchor.clone());}
     }
    }
   }
   StatementKind::Switch{selector,cases,mut else_branch,..}=>{
    crate::setting_drop::drop_expression(selector,anchor.clone());statements.append(&mut else_branch);
    for mut case in cases{statements.append(&mut case.body);for alt in case.alternatives{match alt{SwitchAlternative::Exact(e)=>crate::setting_drop::drop_expression(e,anchor.clone()),SwitchAlternative::Range(x,y)=>{crate::setting_drop::drop_expression(x,anchor.clone());crate::setting_drop::drop_expression(y,anchor.clone());}}}}
   }
   StatementKind::Try{mut body,mut catch_body,..}=>{statements.append(&mut body);statements.append(&mut catch_body);},
   StatementKind::Label{mut body,..}=>statements.append(&mut body),
   StatementKind::Return(value)|StatementKind::Var{value,..}=>{for e in value{crate::setting_drop::drop_expression(e,anchor.clone());}},
   StatementKind::Assign{target,value,..}=>{crate::setting_drop::drop_expression(target,anchor.clone());crate::setting_drop::drop_expression(value,anchor.clone());},
   StatementKind::Throw(e)|StatementKind::Call(e)|StatementKind::Expression(e)=>crate::setting_drop::drop_expression(e,anchor.clone()),
   StatementKind::Goto(_)|StatementKind::BreakLabel(_)|StatementKind::ContinueLabel(_)|StatementKind::Break|StatementKind::Continue|StatementKind::Unsupported=>(),
  }
 }
 drop(statements);drop(anchor);
}

#[cfg(test)]
#[path="body_literal_syntax_tests.rs"]mod tests;
