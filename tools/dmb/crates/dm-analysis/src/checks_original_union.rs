//! One ordered diagnostic sink for the actual original body evaluation.
//! Reuses existing judges; no per-family body evaluation or result concatenation.
use super::*;
use crate::checker_expression_visit::{self as visit,ArgumentObserver,KeywordObserver,TypeIssueObserver,IterationObserver,StaticObserver,CatchObserver,CaseObserver,OriginalObserver,OriginalArguments,NamedArguments,TypeFact};
struct Combined<'a,'loan,'w,'k,W,R:?Sized>{inner:Option<Arguments<'a,'w,W,R>>,body:&'loan dyn dm_tree::frontend::InitialSettingSource,keywords:&'k mut dyn KeywordObserver<PolicyFailure>,evaluations:usize}
impl<'a,'loan,'w,W:EffectReportWork,R:Resolver+?Sized> Combined<'a,'loan,'w,'_,W,R>{
 fn inner(&mut self)->&mut Arguments<'a,'w,W,R>{self.inner.as_mut().expect("actual combined sink")}
 fn fund_follow_note(&mut self, variable_bytes: usize) -> Result<(), PolicyFailure> {
    let inner = self.inner();
    inner.poll()?;
    // Covers the retained note row, lossy display of the original registered
    // path and its coordinates before formatting can allocate.
    let bytes = variable_bytes.checked_mul(8).and_then(|n| n.checked_add(1024)).ok_or_else(oom)?;
    reserve(inner.work, bytes)
 }
 fn with_filter<T>(&mut self,f:impl FnOnce(&mut filter::Filter<'a,'loan,'w,W,R>)->Result<T,PolicyFailure>)->Result<T,PolicyFailure>{let mut adapter=filter::Filter{inner:self.inner.take().expect("actual combined sink"),body:self.body};let result=f(&mut adapter);self.inner=Some(adapter.inner);result}
 fn with_iteration<T>(&mut self,f:impl FnOnce(&mut iteration_ranges::Iteration<'a,'w,W,R>)->Result<T,PolicyFailure>)->Result<T,PolicyFailure>{let mut adapter=iteration_ranges::Iteration{inner:self.inner.take().expect("actual combined sink")};let result=f(&mut adapter);self.inner=Some(adapter.inner);result}
 fn with_types<T>(&mut self,f:impl FnOnce(&mut declared_types::Types<'a,'w,W,R>)->Result<T,PolicyFailure>)->Result<T,PolicyFailure>{let mut adapter=declared_types::Types{inner:self.inner.take().expect("actual combined sink")};let result=f(&mut adapter);self.inner=Some(adapter.inner);result}
 fn with_static<T>(&mut self,f:impl FnOnce(&mut static_references::Static<'a,'loan,'w,W,R>)->Result<T,PolicyFailure>)->Result<T,PolicyFailure>{let mut adapter=static_references::Static{inner:self.inner.take().expect("actual combined sink"),body:self.body};let result=f(&mut adapter);self.inner=Some(adapter.inner);result}
 fn with_catch<T>(&mut self,f:impl FnOnce(&mut catch_parameters::Catch<'a,'w,W,R>)->Result<T,PolicyFailure>)->Result<T,PolicyFailure>{let mut adapter=catch_parameters::Catch{inner:self.inner.take().expect("actual combined sink")};let result=f(&mut adapter);self.inner=Some(adapter.inner);result}
 fn with_cases<T>(&mut self,f:impl FnOnce(&mut switch_cases::Cases<'a,'w,W,R>)->Result<T,PolicyFailure>)->Result<T,PolicyFailure>{let mut adapter=switch_cases::Cases{inner:self.inner.take().expect("actual combined sink")};let result=f(&mut adapter);self.inner=Some(adapter.inner);result}
}
impl<W:EffectReportWork,R:Resolver+?Sized> ArgumentObserver<PolicyFailure> for Combined<'_,'_,'_,'_,W,R>{
 fn reserve(&mut self,n:usize)->Result<(),PolicyFailure>{reserve(self.inner().work,n)}fn original_values(&self)->bool{true}
 fn begin_call(&mut self,tree:&dm_tree::SemanticTree,fact:&CallableFact,name:&str)->Result<(),PolicyFailure>{ArgumentObserver::begin_call(self.inner(),tree,fact,name)}
 fn argument(&mut self,tree:&dm_tree::SemanticTree,fact:&CallableFact,name:&str,key:Option<&Expr>,after:bool,at:Option<Span>,expression:Span)->Result<(),PolicyFailure>{let at=at.map(|at|self.body.source_point(at)).transpose()?;let expression=self.body.source_point(expression)?;ArgumentObserver::argument(self.inner(),tree,fact,name,key,after,at,expression)}
 fn finished(&mut self,tree:&dm_tree::SemanticTree,fact:&CallableFact,name:&str,args:&[Expr],named:&NamedArguments<'_>,values:OriginalArguments<'_>,at:Option<Span>,expression:Span)->Result<(),PolicyFailure>{let at=at.map(|at|self.body.source_point(at)).transpose()?;let expression=self.body.source_point(expression)?;self.with_filter(|filter|ArgumentObserver::finished(filter,tree,fact,name,args,named,values,at,expression))}
}
impl<W:EffectReportWork,R:Resolver+?Sized> KeywordObserver<PolicyFailure> for Combined<'_,'_,'_,'_,W,R>{fn begin_call(&mut self,tree:&dm_tree::SemanticTree,fact:&CallableFact,name:&str)->Result<(),PolicyFailure>{self.keywords.begin_call(tree,fact,name)}fn accepted_argument(&mut self,tree:&dm_tree::SemanticTree,fact:&CallableFact,receiver:SymbolId,name:&str,key:&Expr,at:Span)->Result<(),PolicyFailure>{self.keywords.accepted_argument(tree,fact,receiver,name,key,self.body.source_point(at)?)}}
impl<W:EffectReportWork,R:Resolver+?Sized> TypeIssueObserver<PolicyFailure> for Combined<'_,'_,'_,'_,W,R>{fn undefined_type(&mut self,path:&str,at:Span)->Result<(),PolicyFailure>{let at=self.body.source_point(at)?;self.with_types(|types|types.undefined_type(path,at))}}
impl<W:EffectReportWork,R:Resolver+?Sized> IterationObserver<PolicyFailure> for Combined<'_,'_,'_,'_,W,R>{fn iterable(&mut self,ty:TypeFact,at:Span)->Result<(),PolicyFailure>{let at=self.body.source_point(at)?;self.with_iteration(|iteration|iteration.iterable(ty,at))}fn invalid_range(&mut self,at:Span)->Result<(),PolicyFailure>{let at=self.body.source_point(at)?;self.with_iteration(|iteration|iteration.invalid_range(at))}}
impl<W:EffectReportWork,R:Resolver+?Sized> StaticObserver<PolicyFailure> for Combined<'_,'_,'_,'_,W,R>{fn failure(&mut self,failure:crate::checker_static_reference::Failure<'_>,name:&str,procedure:bool,at:Span,expression:Span)->Result<(),PolicyFailure>{let at=self.body.source_point(at)?;let expression=self.body.source_point(expression)?;self.with_static(|references|references.failure(failure,name,procedure,at,expression))}}
impl<W:EffectReportWork,R:Resolver+?Sized> CatchObserver<PolicyFailure> for Combined<'_,'_,'_,'_,W,R>{fn parameters(&mut self,count:usize,at:Span,expression:Span)->Result<(),PolicyFailure>{let at=self.body.source_point(at)?;let expression=self.body.source_point(expression)?;self.with_catch(|catch|catch.parameters(count,at,expression))}}
impl<W:EffectReportWork,R:Resolver+?Sized> CaseObserver<PolicyFailure> for Combined<'_,'_,'_,'_,W,R>{fn switch_started(&mut self,selector:&Expr,cases:&[dm_syntax::SwitchCase],default_present:bool,at:Span)->Result<(),PolicyFailure>{let body=self.body;self.with_cases(|adapter|adapter.rand_range(body,selector,cases,default_present,at))}fn logical_or(&mut self,site:dm_syntax::OriginalCaseSite,expression:Span)->Result<(),PolicyFailure>{let cursor=self.body.original_switch_case_cursor(site).map_err(syntax_failure)?.map_err(PolicyFailure::from)?;let expression=self.body.source_point(expression)?;self.with_cases(|cases|cases.logical_or_expanded(cursor,expression))}fn do_while_unreachable(&mut self,at:Span,condition:Span)->Result<(),PolicyFailure>{let at=self.body.source_point(at)?;let condition=self.body.source_point(condition)?;self.with_cases(|cases|cases.do_while_unreachable(at,condition))}}

impl<W:EffectReportWork,R:Resolver+?Sized> Combined<'_,'_,'_,'_,W,R>{
 fn emit(&mut self,mut diagnostic:Diagnostic,tag:Option<&'static str>,level:crate::check_policy::DiagnosticSeverity)->Result<(),PolicyFailure>{
  diagnostic.span=self.body.source_point(diagnostic.span)?;
  diagnostic.expression_span=self.body.source_point(diagnostic.expression_span)?;
  self.emit_expanded(diagnostic,tag,level)
 }
 fn emit_expanded(&mut self,diagnostic:Diagnostic,tag:Option<&'static str>,level:crate::check_policy::DiagnosticSeverity)->Result<(),PolicyFailure>{
  let inner=self.inner();
  push(inner.work,&mut inner.rows,Row{registration:Some((tag,level)),diagnostic,synthetic:false,reported:None})
 }
}
impl<'a,W:EffectReportWork,R:Resolver+?Sized> OriginalObserver<'a> for Combined<'a,'_,'_,'_,W,R>{
 fn access_levels(&self)->[Severity;5]{[Severity::Error,Severity::Error,Severity::Error,Severity::Error,Severity::Warning]}
 fn immediate_row(&mut self,diagnostic:Diagnostic)->Result<(),PolicyFailure>{let level=match diagnostic.severity{Severity::Error=>crate::check_policy::DiagnosticSeverity::Error,Severity::Warning=>crate::check_policy::DiagnosticSeverity::Warning,Severity::Disabled=>return Err("actual fixed body diagnostic cannot be disabled".into())};self.emit(diagnostic,None,level)}
 fn binary_warning(
  &mut self,warning:visit::BinaryWarning<'a>,expression_span:Span,
  at:Option<crate::checker_evaluated_observer::ExpressionOrigin>,
 )->Result<(),PolicyFailure>{
  use crate::checker_evaluated_observer::ExpressionOrigin;
  self.inner().poll()?;
  let (family,message,notes)=match warning {
   visit::BinaryWarning::Membership(lhs)=>{
    let inner=self.inner();
    let checkpoint=inner.checkpoint;
    let Some((message,notes))=crate::checks_ambiguous_in::wording_using(lhs,
     ||checkpoint().map_err(PolicyFailure::Operational),|bytes|reserve(inner.work,bytes))?
    else{return Ok(())};
    ("ambiguous_in_lhs",message,notes.into_iter().map(|message|Note{message,source:None}).collect())
   }
   visit::BinaryWarning::NegatedBitwise{op,lhs}=>{
    let Some(boolean)=crate::checks::negated_bitwise(op,lhs,||self.inner().poll())? else{return Ok(())};
    reserve(self.inner().work,1024)?;
    let (message,notes)=crate::checks::negated_bitwise_wording(op,boolean);
    ("ambiguous_not_bitwise",message,notes.into_iter().map(|message|Note{message,source:None}).collect())
   }
  };
  let body=self.body;
  let expression_span=body.source_point(expression_span)?;
  let inner=self.inner();
  let (span,point)=match at.ok_or("Original binary warning has no authored evaluation anchor")? {
   ExpressionOrigin::Source(span)=>(body.source_point(span)?,None),
   ExpressionOrigin::Case(site)=>match body.original_switch_case_cursor(site).map_err(syntax_failure)?.map_err(PolicyFailure::from)?{
    dm_syntax::OriginalCaseCursor::Token(span)=>{
     let point=if inner.archive.borrowed_source_note_point(span.start).is_ok(){None}else{
      inner.archive.source_mapping().borrowed_case_end_point_using(span.end,span,&mut||inner.poll())?
     };
     (span,point)
    }
    dm_syntax::OriginalCaseCursor::SourceEnd{offset,fallback}=>{
     let point=inner.archive.source_mapping().borrowed_case_end_point_using(offset,fallback,&mut||inner.poll())?;
     (fallback,point)
    }
   }
  };
  let diagnostic=Diagnostic{family,severity:Severity::Warning,span,expression_span,message,notes};
  push(inner.work,&mut inner.rows,Row{
   diagnostic,registration:Some((Some(family),crate::check_policy::DiagnosticSeverity::Warning)),
   synthetic:false,reported:point.map(crate::checks_proc_visibility::OriginalReported::Source),
  })
 }
 fn body_started(&mut self)->Result<(),PolicyFailure>{self.evaluations=self.evaluations.checked_add(1).ok_or("actual combined evaluation count overflow")?;if self.evaluations!=1{return Err("combined body evaluator entered more than once".into())}Ok(())}
 fn access_row(&mut self,row:Row<'a>)->Result<(),PolicyFailure>{let inner=self.inner();push(inner.work,&mut inner.rows,row)}
 fn flow_event(&mut self,event:crate::checker_reachable::Event<'a>)->Result<(),PolicyFailure>{use crate::checks_control_policies::Family;use crate::checker_reachable::Event;let family=match event{Event::ControlCondition{..}=>Family::Static,Event::Unreachable{..}=>Family::Unreachable,Event::LoopCondition{..}=>Family::LoopDeterminate,Event::IfDeterminate{..}=>Family::IfDeterminate,Event::SettingOutsidePrefix{..}=>Family::SettingPlacement,Event::DoWhileUnreachable{..}=>return Ok(())};crate::checks_control_policies::visit_events(std::iter::once(event),&[(family,Severity::Error)],|diagnostic|self.emit(diagnostic,Some(family.name()),crate::check_policy::DiagnosticSeverity::Error))}
 fn expression_event(&mut self,event:visit::Event<'a>)->Result<(),PolicyFailure>{
  let archive=self.inner.as_ref().expect("combined sink").archive;
  let body=self.body;
  match event{
   event@visit::Event::MissingVariable{..}|event@visit::Event::MissingField{..}=>crate::checks_undefined_variable::visit_events(archive.tree(),std::iter::once(event),|diagnostic|self.emit(diagnostic,None,crate::check_policy::DiagnosticSeverity::Error)),
   event@visit::Event::MissingCall{..}=>crate::checks_undefined_proc::visit_events(archive.tree(),std::iter::once(event),|diagnostic|self.emit(diagnostic,None,crate::check_policy::DiagnosticSeverity::Error)),
   event@visit::Event::FieldWithoutStaticType{..}=>{
    if let Some(diagnostic) = crate::checks_field_static::diagnostic_using(archive, Severity::Warning, event, |span| body.source_point(span), |n| self.fund_follow_note(n))? {
     self.emit_expanded(diagnostic, Some("field_access_static_type"), crate::check_policy::DiagnosticSeverity::Warning)?;
    }
    Ok(())
   },
   event@visit::Event::UnknownReceiverCall{..}=>{
    if let Some(diagnostic) = crate::checks_proc_static::diagnostic_using(archive, Severity::Warning, event, |span| body.source_point(span), |n| self.fund_follow_note(n))? {
     self.emit_expanded(diagnostic, Some("proc_call_static_type"), crate::check_policy::DiagnosticSeverity::Warning)?;
    }
    Ok(())
   },
   event@visit::Event::MissingImplicitNewHint{..}=>{if let Some(diagnostic)=crate::checks_implicit_new::diagnostic(event,Severity::Error){self.emit(diagnostic,Some(crate::checks_implicit_new::FAMILY),crate::check_policy::DiagnosticSeverity::Error)?;}Ok(())},
   visit::Event::MissingParent{expression,at,display}=>self.emit(crate::checks_parent_call::missing_parent_diagnostic(at,expression.span,&display,Severity::Error),Some("proc_has_no_parent"),crate::check_policy::DiagnosticSeverity::Error),
   event@visit::Event::ResolvedField{..}=>{let body=self.body;let profile=self.inner.as_ref().expect("combined sink").profile;let checkpoint=self.inner.as_ref().expect("combined sink").checkpoint;crate::checks_variable_visibility::visit_field_events(archive,body,profile,std::iter::once(event),&crate::check_policy::CheckerPolicy::default(),&mut||checkpoint().map_err(PolicyFailure::Operational),|row|{let(diagnostic,tag,level)=row.into_original_parts();self.emit_expanded(diagnostic,tag,level)})},
   visit::Event::ResolvedCall{..}|visit::Event::ResolvedImplicitListConstructor{..}|visit::Event::DynamicMemberCall{..}=>Ok(())
  }
 }
}

/// Same-body union used by the existing BODY contribution. No family may ask
/// for another Walker; all rows are consumed while the actual body loan lives.
pub(crate) fn with_body_using<'a,W:EffectReportWork,R:Resolver+?Sized,D:crate::checker_prefix_demand::Demand<Error=PolicyFailure>>(
 archive:&'a BodyArchive,body:&'a ArchivedBody<'a>,resolver:&R,profile:PackedU128,loan:crate::checker_effects::DraftLoan<'_>,prefix_demand:D,work:&mut W,checkpoint:&dyn Fn()->io::Result<()>,keywords:&mut dyn KeywordObserver<PolicyFailure>,consume:impl FnOnce(Findings<'a>,usize)->Result<(),PolicyFailure>
)->Result<(),PolicyFailure>{
 with_union_using(archive,visit::UnionBody::Archived(body),body,resolver,profile,loan,prefix_demand,work,checkpoint,keywords,consume)
}

/// A complete current expression/flow/effects traversal over the supplied
/// live canonical BODY loan. Prelude preparation remains the caller's phase.
pub(crate) fn with_current_body_using<'a,W:EffectReportWork,R:Resolver+?Sized,D:crate::checker_prefix_demand::Demand<Error=PolicyFailure>>(
 archive:&'a BodyArchive,body:&'a dm_tree::frontend::CurrentArchivedBody<'_,'_>,admission:&dm_syntax::SettingAdmission<'_>,resolver:&R,profile:PackedU128,loan:crate::checker_effects::DraftLoan<'_>,prefix_demand:D,work:&mut W,checkpoint:&dyn Fn()->std::io::Result<()>,keywords:&mut dyn KeywordObserver<PolicyFailure>,consume:impl FnOnce(Findings<'a>,usize)->Result<(),PolicyFailure>,
)->Result<(),PolicyFailure>{
 checkpoint().map_err(PolicyFailure::Operational)?;
 match body.syntax().original_code_disposition().map_err(syntax_failure)?{
  dm_tree::frontend::OriginalBodyDisposition::Available(_)=>{},
  dm_tree::frontend::OriginalBodyDisposition::Skipped(_)=>return Err("current full Original evaluator requires available body code".into()),
 }
 let pending=body.with_original_body_source(admission,|source|{
  with_union_using(archive,visit::UnionBody::Current(body,admission),source,resolver,profile,loan,prefix_demand,work,checkpoint,keywords,consume)
 }).map_err(syntax_failure)?;
 if matches!(&pending,Err(PolicyFailure::Operational(_))){return pending}
 if let Some(actual)=admission.take_operational_error(){return Err(PolicyFailure::Operational(actual))}
 checkpoint().map_err(PolicyFailure::Operational)?;pending
}

pub(super) fn syntax_failure(actual:dm_tree::frontend::BodySyntaxFailure)->PolicyFailure{
 match actual{
  dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>PolicyFailure::Operational(actual),
  dm_tree::frontend::BodySyntaxFailure::Syntax(actual)=>actual.message.into(),
 }
}

fn with_union_using<'a,W:EffectReportWork,R:Resolver+?Sized,D:crate::checker_prefix_demand::Demand<Error=PolicyFailure>>(
 archive:&'a BodyArchive,body:visit::UnionBody<'a,'_,'_,'_,'_>,source:&dyn dm_tree::frontend::InitialSettingSource,resolver:&R,profile:PackedU128,loan:crate::checker_effects::DraftLoan<'_>,prefix_demand:D,work:&mut W,checkpoint:&dyn Fn()->std::io::Result<()>,keywords:&mut dyn KeywordObserver<PolicyFailure>,consume:impl FnOnce(Findings<'a>,usize)->Result<(),PolicyFailure>,
)->Result<(),PolicyFailure>{
 let mut combined=Combined{inner:Some(Arguments{archive,profile,work,checkpoint,resolver,rows:Vec::new()}),body:source,keywords,evaluations:0};
 let pending=(||{visit::original_union_using(archive,body,source,resolver,profile,loan,prefix_demand,checkpoint,&mut combined)?;if combined.evaluations!=1{return Err("original contribution did not evaluate its actual body exactly once".into())}let rows=std::mem::take(&mut combined.inner().rows);consume(Findings::from_rows(archive,rows),combined.evaluations)})();
 if matches!(&pending,Err(PolicyFailure::Operational(_))){return pending}checkpoint().map_err(PolicyFailure::Operational)?;pending
}
