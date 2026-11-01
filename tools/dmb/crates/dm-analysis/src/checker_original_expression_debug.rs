//! Source-bound original Debug diagnostic projection over actual archived roots.
//! The pure formatting core is shared with test-only original-AST observations.
#[path="checker_original_expression_debug_core.rs"]mod core;
use core::*;
use dm_syntax::{Expr,ExprKind,Span};
use std::fmt::Write;
// Actual source adapter: constructor remains private to this module. A caller
// must supply the SAME existing native host admission, never a fresh counter.
use crate::policy_body_demand::PolicyFailure;
struct ArchiveSource<'a,'owner,'op>{
 admission:&'a dm_syntax::SettingAdmission<'op>,
 registry:&'a dm_tree::frontend::OriginalCheckerSourceRegistry<'owner>,
 tokens:dm_tree::frontend::OriginalBodyTokens<'owner>,
 current_offset:usize,
}
struct FragmentSource<'s,'a,'owner,'op>{parent:&'s ArchiveSource<'a,'owner,'op>,fragment:&'s dm_syntax::literal::PinnedLiteralFragment<'s>}
fn actual_frame<'a,'op>(admission:&'a dm_syntax::SettingAdmission<'op>)->Result<dm_syntax::SettingEvaluationFrame<'a,'op>,PolicyFailure>{let pending=admission.evaluation_frame();if let Some(actual)=admission.take_operational_error(){return Err(PolicyFailure::Operational(actual))}pending.map_err(PolicyFailure::Operational)}
fn physical_punctuation<'s>(admission:&dm_syntax::SettingAdmission<'_>,expected:&str,tokens:impl Iterator<Item=Result<(dm_syntax::TokenKind,Span,&'s str),PolicyFailure>>)->Result<usize,PolicyFailure>{
 let mut at=0;let mut first=None;for token in tokens{
  let pending=admission.checkpoint();if let Some(actual)=admission.take_operational_error(){return Err(PolicyFailure::Operational(actual))}pending.map_err(PolicyFailure::Operational)?;
  let(kind,span,text)=token?;if matches!(kind,dm_syntax::TokenKind::Whitespace|dm_syntax::TokenKind::Newline|dm_syntax::TokenKind::Comment){continue}
  if first.is_none(){first=Some(span.start)}let remaining=expected.get(at..).ok_or("original punctuation projection overflow")?;if !remaining.starts_with(text){return Err("original primary punctuation differs from actual node".into())}at+=text.len();if at==expected.len(){return first.ok_or_else(||"original primary punctuation absent".into())}
 }Err("original primary punctuation absent".into())
}
impl<'a,'owner,'op> Source for ArchiveSource<'a,'owner,'op>{
 type Error=PolicyFailure;type Frame<'frame>=dm_syntax::SettingEvaluationFrame<'frame,'op> where Self:'frame;type Scratch<'frame>=dm_syntax::SettingRootLease where Self:'frame;
 fn scratch(&self,bytes:usize)->Result<Self::Scratch<'_>,Self::Error>{admitted(self.admission,self.admission.reserve(bytes))}
 fn literal_checkpoint(&self)->std::fmt::Result{self.admission.checkpoint().map_err(|_|std::fmt::Error)}
 fn frame(&self)->Result<Self::Frame<'_>,Self::Error>{actual_frame(self.admission)}
 fn location(&self,offset:usize,out:&mut DebugSink<'_>)->Result<(),Self::Error>{let offset=offset.checked_add(self.current_offset).ok_or("current original expression coordinate overflow")?;let point=self.registry.location(offset)?;write!(out,"Location {{ file: FileId({}), line: {}, column: {} }}",point.file,point.line,point.byte_column).map_err(|_|PolicyFailure::from("original Debug output failed"))?;Ok(())}
 fn punctuation(&self,span:Span,spelling:&str)->Result<usize,Self::Error>{let current=Span::new(span.start.checked_add(self.current_offset).ok_or("current token coordinate overflow")?,span.end.checked_add(self.current_offset).ok_or("current token coordinate overflow")?);let tokens=self.tokens.tokens(current)?;let offset=self.current_offset;physical_punctuation(self.admission,spelling,tokens.map(move|(kind,span,text)|Ok((kind,Span::new(span.start-offset,span.end-offset),text))))}
 fn path(&self,path:&Expr,out:&mut DebugSink<'_>)->Result<(),Self::Error>{path_debug(self,path,out)}
 fn fragment_expression(&self,fragment:&dm_syntax::literal::PinnedLiteralFragment<'_>,out:&mut DebugSink<'_>)->Result<(),Self::Error>{let expression_node=fragment.expression().ok_or("original literal child absent")?;expression(&FragmentSource{parent:self,fragment},expression_node,out)}
}
impl<'s,'a,'owner,'op> Source for FragmentSource<'s,'a,'owner,'op>{
 type Error=PolicyFailure;type Frame<'frame>=dm_syntax::SettingEvaluationFrame<'frame,'op> where Self:'frame;type Scratch<'frame>=dm_syntax::SettingRootLease where Self:'frame;
 fn scratch(&self,bytes:usize)->Result<Self::Scratch<'_>,Self::Error>{self.parent.scratch(bytes)}
 fn literal_checkpoint(&self)->std::fmt::Result{self.parent.literal_checkpoint()}
 fn frame(&self)->Result<Self::Frame<'_>,Self::Error>{actual_frame(self.parent.admission)}
 fn location(&self,offset:usize,out:&mut DebugSink<'_>)->Result<(),Self::Error>{self.parent.location(offset,out)}
 fn punctuation(&self,span:Span,spelling:&str)->Result<usize,Self::Error>{let tokens=self.fragment.tokens_between(span).map_err(|_|"original literal token interval unavailable")?;physical_punctuation(self.parent.admission,spelling,tokens.map(|token|{let(kind,span)=token.map_err(|_|"original literal token coordinate unavailable")?;let text=self.fragment.token_text(span).map_err(|_|"original literal token spelling unavailable")?;Ok((kind,span,text))}))}
 fn path(&self,path:&Expr,out:&mut DebugSink<'_>)->Result<(),Self::Error>{path_debug(self,path,out)}
 fn fragment_expression(&self,fragment:&dm_syntax::literal::PinnedLiteralFragment<'_>,out:&mut DebugSink<'_>)->Result<(),Self::Error>{let child=fragment.expression().ok_or("original nested literal child absent")?;expression(&FragmentSource{parent:self.parent,fragment},child,out)}
}

/// Storage only: the actual String/Vec buffers are destroyed before their
/// original setting-counter reservations. This grants no source role.
struct StoredDiagnostic { value:crate::checks::Diagnostic, _lease:dm_syntax::SettingRootLease }
pub struct OriginalDiagnosticRows { rows:Vec<StoredDiagnostic>, lease:dm_syntax::SettingRootLease }
impl OriginalDiagnosticRows {
 pub(crate) fn new(a:&dm_syntax::SettingAdmission<'_>)->Result<Self,PolicyFailure>{let lease=admitted(a,a.reserve(std::mem::size_of::<Self>()))?;Ok(Self{rows:Vec::new(),lease})}
 pub fn iter(&self)->impl ExactSizeIterator<Item=&crate::checks::Diagnostic>{self.rows.iter().map(|row|&row.value)}
 pub(crate) fn push_setting(&mut self,body:&dm_tree::frontend::ArchivedBody<'_>,ordinal:usize,severity:crate::checks::Severity,a:&dm_syntax::SettingAdmission<'_>)->Result<(),PolicyFailure>{self.push_with(a,||render_archived_setting_using(body,ordinal,severity,a))}
 fn push_with(&mut self,a:&dm_syntax::SettingAdmission<'_>,make:impl FnOnce()->Result<StoredDiagnostic,PolicyFailure>)->Result<(),PolicyFailure>{
  if !a.matches_lease_domain(&self.lease){return Err(PolicyFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"original diagnostic rows belong to another admission")))}
  if self.rows.len()==self.rows.capacity(){
   let capacity=self.rows.capacity().max(4).checked_mul(2).ok_or_else(output_oom)?;
   let bound=capacity.checked_mul(std::mem::size_of::<StoredDiagnostic>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(std::mem::size_of::<Self>())).ok_or_else(output_oom)?;
   let additional_bound=bound.saturating_sub(self.lease.bytes());admitted(a,a.grow(&mut self.lease,additional_bound))?;
   let additional=capacity-self.rows.len();self.rows.try_reserve_exact(additional).map_err(|_|output_oom())?;
   if self.rows.capacity()>capacity.checked_mul(2).ok_or_else(output_oom)?{return Err(output_oom())}
  }
  let row=make()?;self.rows.push(row);Ok(())
 }
}
fn output_oom()->PolicyFailure{PolicyFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"original diagnostic output admission denied"))}
fn admitted<T>(a:&dm_syntax::SettingAdmission<'_>,result:std::io::Result<T>)->Result<T,PolicyFailure>{result.map_err(|proxy|PolicyFailure::Operational(a.take_operational_error().unwrap_or(proxy)))}
fn rendered(result:Result<(),PolicyFailure>,sink:&DebugSink<'_>)->Result<(),PolicyFailure>{match result{Err(PolicyFailure::Operational(actual))=>Err(PolicyFailure::Operational(actual)),pending=>{if sink.denied(){return Err(output_oom())}pending}}}
fn render_message(source:&impl Source<Error=PolicyFailure>,value:&Expr,out:&mut DebugSink<'_>)->Result<(),PolicyFailure>{out.push_str("invalid value for set ");let pending=expression(source,value,out);rendered(pending,out)}

/// No caller expression is accepted: actual top-level statement ordinal selects
/// the exact root from the privately issued ArchivedBody. The supplied counter
/// must already admit that physical syntax owner and (for ProjectedSet) root.
fn render_archived_setting_using(body:&dm_tree::frontend::ArchivedBody<'_>,ordinal:usize,severity:crate::checks::Severity,a:&dm_syntax::SettingAdmission<'_>)->Result<StoredDiagnostic,PolicyFailure>{
 let pending=(||{
  let _frame=actual_frame(a)?;let syntax=body.statement_body();
  if !syntax.has_native_literal_syntax(){return Err(PolicyFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"original statement syntax has no native admission")))}
  if !syntax.is_native_literal_syntax_admitted_by(a){return Err(PolicyFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"original statement syntax belongs to another native admission")))}
  let statement=syntax.parsed().statements.get(ordinal).ok_or("original setting ordinal absent")?;let setting=statement.setting().ok_or("actual original statement is not a setting")?;
  let offset=match setting.value{dm_syntax::SettingValueView::Owned(_)=>0,dm_syntax::SettingValueView::Projected(root)=>{if !root.is_retained_in(a){return Err(PolicyFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"original setting root belongs to another native admission")))}root.current_offset()}};
  let mapping=body.archive_owner().source_mapping();let registry=mapping.original_checker_source_registry(a).map_err(PolicyFailure::Operational)?;
  if !registry.matches_mapping(mapping){return Err(PolicyFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"original checker registry belongs to another source mapping")))}
  let source=ArchiveSource{admission:a,registry:&registry,tokens:body.original_body_tokens()?,current_offset:offset};
  let mut count=DebugSink::count();render_message(&source,setting.value.original(),&mut count)?;let length=count.len();
  let bound=length.checked_mul(4).and_then(|n|n.checked_add(std::mem::size_of::<String>()+64)).ok_or_else(output_oom)?;
  let lease=admitted(a,a.reserve(bound))?;let mut output=String::new();output.try_reserve_exact(length).map_err(|_|output_oom())?;
  if output.capacity().checked_add(std::mem::size_of::<String>()+64).is_none_or(|actual|actual>bound){return Err(output_oom())}
  let mut sink=DebugSink::fixed(&mut output,length);render_message(&source,setting.value.original(),&mut sink)?;if sink.len()!=length{return Err("original diagnostic count and encoding differ".into())}drop(sink);
  let value=crate::checks::Diagnostic{family:"invalid_lint_directive_value",severity,span:statement.header_span,expression_span:setting.value.current_span(),message:output,notes:Vec::new()};Ok(StoredDiagnostic{value,_lease:lease})
 })();
 if let Some(actual)=a.take_operational_error(){return Err(PolicyFailure::Operational(actual))}if matches!(&pending,Err(PolicyFailure::Operational(_))){return pending}let final_poll=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(PolicyFailure::Operational(actual))}final_poll.map_err(PolicyFailure::Operational)?;pending
}

#[cfg(test)]mod diagnostic_storage_tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 fn stored(a:&dm_syntax::SettingAdmission<'_>)->Result<StoredDiagnostic,PolicyFailure>{
  let lease=admitted(a,a.reserve(1024))?;let mut message=String::new();message.try_reserve_exact(32).map_err(|_|output_oom())?;assert!(message.capacity()<=1024);message.push_str("invalid value for set Int(2)");
  Ok(StoredDiagnostic{value:crate::checks::Diagnostic{family:"invalid_lint_directive_value",severity:crate::checks::Severity::Warning,span:Span::new(0,1),expression_span:Span::new(0,1),message,notes:Vec::new()},_lease:lease})
 }
 #[test]fn diagnostic_rows_keep_same_counter_funded_until_strings_and_vector_physically_drop(){
  let counter=Arc::new(AtomicUsize::new(0));let checkpoint=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,1<<20,&checkpoint);
  let mut rows=OriginalDiagnosticRows::new(&a).unwrap();for _ in 0..17{rows.push_with(&a,||stored(&a)).unwrap()}
  let live=counter.load(Ordering::Acquire);assert!(live>=17*1024+rows.rows.capacity()*std::mem::size_of::<StoredDiagnostic>());assert_eq!(rows.iter().len(),17);assert!(rows.iter().all(|row|row.message=="invalid value for set Int(2)"));drop(rows);assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn diagnostic_row_growth_denial_precedes_constructor_and_foreign_domain_cannot_spend(){
  let counter=Arc::new(AtomicUsize::new(0));let checkpoint=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,4096,&checkpoint);let mut rows=OriginalDiagnosticRows::new(&a).unwrap();let before=counter.load(Ordering::Acquire);
  let tiny=dm_syntax::SettingAdmission::new(&counter,before,&checkpoint);let result=rows.push_with(&tiny,||panic!("denial must precede constructor"));assert!(matches!(result,Err(PolicyFailure::Operational(ref e))if e.kind()==std::io::ErrorKind::OutOfMemory));assert_eq!(counter.load(Ordering::Acquire),before);
  let other=Arc::new(AtomicUsize::new(0));let foreign=dm_syntax::SettingAdmission::new(&other,1<<20,&checkpoint);let result=rows.push_with(&foreign,||panic!("foreign constructor must not run"));assert!(matches!(result,Err(PolicyFailure::Operational(ref e))if e.kind()==std::io::ErrorKind::InvalidInput));assert_eq!(counter.load(Ordering::Acquire),before);drop(rows);assert_eq!(counter.load(Ordering::Acquire),0);assert_eq!(other.load(Ordering::Acquire),0);
 }
 #[test]fn diagnostic_row_make_actual_io_and_unwind_drop_work_without_publication(){
  let counter=Arc::new(AtomicUsize::new(0));let checkpoint=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,1<<20,&checkpoint);
  {let mut rows=OriginalDiagnosticRows::new(&a).unwrap();let result=rows.push_with(&a,||Err(PolicyFailure::Operational(std::io::Error::from_raw_os_error(1450))));assert!(matches!(result,Err(PolicyFailure::Operational(ref e))if e.raw_os_error()==Some(1450)));assert_eq!(rows.iter().len(),0);}assert_eq!(counter.load(Ordering::Acquire),0);
  let unwind=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||{let mut rows=OriginalDiagnosticRows::new(&a).unwrap();rows.push_with(&a,||stored(&a)).unwrap();let _=rows.push_with(&a,||{let _held=admitted(&a,a.reserve(512))?;panic!("actual unwind after owned reservation")});}));assert!(unwind.is_err());assert_eq!(counter.load(Ordering::Acquire),0);
  let mut healthy=OriginalDiagnosticRows::new(&a).unwrap();healthy.push_with(&a,||stored(&a)).unwrap();drop(healthy);assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn counting_overflow_and_fixed_refusal_never_grow_or_expose_partial_completion(){let mut count=DebugSink::count();count.used=usize::MAX;count.push('x');assert!(count.denied());let mut bytes=String::with_capacity(4);let original=bytes.capacity();let mut fixed=DebugSink::fixed(&mut bytes,4);fixed.push_str("abcd");fixed.push_str("overflow");assert!(fixed.denied());assert_eq!(fixed.len(),4);drop(fixed);assert_eq!(bytes,"abcd");assert_eq!(bytes.capacity(),original);}
}

#[cfg(test)]mod streamed_literal_io_tests{
 use super::*;use std::sync::{Arc,atomic::AtomicUsize};
 struct Poll<'a,'op>{a:&'a dm_syntax::SettingAdmission<'op>}
 impl Source for Poll<'_,'_>{
  type Error=PolicyFailure;type Frame<'a>=()where Self:'a;type Scratch<'a>=dm_syntax::SettingRootLease where Self:'a;
  fn scratch(&self,bytes:usize)->Result<Self::Scratch<'_>,Self::Error>{admitted(self.a,self.a.reserve(bytes))}
  fn frame(&self)->Result<(),Self::Error>{Ok(())}
  fn literal_checkpoint(&self)->std::fmt::Result{self.a.checkpoint().map_err(|_|std::fmt::Error)}
  fn location(&self,_:usize,_:&mut DebugSink<'_>)->Result<(),Self::Error>{panic!("literal byte stream has no location demand")}
  fn punctuation(&self,_:Span,_:&str)->Result<usize,Self::Error>{panic!("literal byte stream has no punctuation demand")}
  fn path(&self,_:&Expr,_:&mut DebugSink<'_>)->Result<(),Self::Error>{panic!("literal byte stream has no path demand")}
  fn fragment_expression(&self,_:&dm_syntax::literal::PinnedLiteralFragment<'_>,_:&mut DebugSink<'_>)->Result<(),Self::Error>{panic!("static literal has no child")}
 }
 #[test]fn streamed_literal_fmt_boundary_keeps_first_actual_checkpoint_io_for_outer_restoration(){
  let counter=Arc::new(AtomicUsize::new(0));let raw=format!("\"{}\"","x".repeat(2048));let tokens=dm_syntax::lex_spans(&raw);let healthy=||Ok(());let before=dm_syntax::SettingAdmission::new(&counter,1<<20,&healthy);let root=dm_syntax::prepare_setting_expression(&raw,&tokens.tokens,Span::new(0,raw.len()),&before).unwrap();let ExprKind::Literal(value)=&root.original_expression().kind else{panic!("actual prepared literal root")};let checkpoint=||Err(std::io::Error::from_raw_os_error(1450));let a=dm_syntax::SettingAdmission::new(&counter,1<<20,&checkpoint);let source=Poll{a:&a};let mut sink=DebugSink::count();assert!(source.literal(value,&mut sink).is_err());let actual=a.take_operational_error().expect("fmt proxy must not consume actual checkpoint IO");assert_eq!(actual.raw_os_error(),Some(1450));
 }
}

/// Private evaluated-call adapter. The expression/value is borrowed directly
/// from the SAME archived visitor; this function grants no source/call receipt.
pub(crate) enum CallDebug<'a>{Term(&'a Expr),Value(Option<crate::checker_expression_visit::OriginalValue<'a>>),Display(crate::checker_expression_visit::OriginalValue<'a>)}
pub(crate) fn with_call_debug<T>(body:&dm_tree::frontend::ArchivedBody<'_>,value:CallDebug<'_>,checkpoint:&dyn Fn()->std::io::Result<()>,consume:impl FnOnce(&str)->Result<T,PolicyFailure>)->Result<T,PolicyFailure>{
 checkpoint().map_err(PolicyFailure::Operational)?;
 let pending=body.with_original_syntax_admission(|a|{let pending=(||{
  if !body.statement_body().is_native_literal_syntax_admitted_by(a){return Err("original call syntax belongs to another native admission".into())}
  let mapping=body.archive_owner().source_mapping();let registry=mapping.original_checker_source_registry(a).map_err(PolicyFailure::Operational)?;if !registry.matches_mapping(mapping){return Err("original call registry belongs to another mapping".into())}
  let source=ArchiveSource{admission:a,registry:&registry,tokens:body.original_body_tokens()?,current_offset:0};

  let render=|out:&mut DebugSink<'_>|->Result<(),PolicyFailure>{match &value{CallDebug::Term(expr)=>core::term_debug(&source,expr,out),CallDebug::Value(value)=>core::constant_debug(&source,value.map(|value|call_constant(body.archive_owner().tree(),value)).transpose()?,out),CallDebug::Display(value)=>core::constant_display(&source,call_constant(body.archive_owner().tree(),*value)?,out)}};
  let mut count=DebugSink::count();rendered(render(&mut count),&count)?;let length=count.len();let bound=length.checked_mul(4).and_then(|n|n.checked_add(std::mem::size_of::<String>()+64)).ok_or_else(output_oom)?;let lease=admitted(a,a.reserve(bound))?;let mut output=String::new();output.try_reserve_exact(length).map_err(|_|output_oom())?;if output.capacity().checked_add(std::mem::size_of::<String>()+64).is_none_or(|n|n>bound){return Err(output_oom())}let mut sink=DebugSink::fixed(&mut output,length);rendered(render(&mut sink),&sink)?;if sink.len()!=length{return Err("original call Debug count differs".into())}drop(sink);let pending=consume(&output);drop(output);drop(lease);pending
 })();if let Some(actual)=a.take_operational_error(){return Err(dm_tree::frontend::BodySyntaxFailure::Operational(actual))}match pending{Err(PolicyFailure::Operational(actual))=>Err(dm_tree::frontend::BodySyntaxFailure::Operational(actual)),other=>Ok(other)}});
 let pending=match pending{Ok(value)=>value,Err(dm_tree::frontend::BodySyntaxFailure::Operational(actual))=>Err(PolicyFailure::Operational(actual)),Err(dm_tree::frontend::BodySyntaxFailure::Syntax(error))=>Err(error.message.into())};if matches!(&pending,Err(PolicyFailure::Operational(_))){return pending}checkpoint().map_err(PolicyFailure::Operational)?;pending
}

fn call_constant<'a>(tree:&'a dm_tree::SemanticTree,value:crate::checker_expression_visit::OriginalValue<'a>)->Result<core::ConstantView<'a>,PolicyFailure>{use crate::checker_expression_visit::OriginalValue;Ok(match value{OriginalValue::Null=>core::ConstantView::Null,OriginalValue::Literal(value)=>core::ConstantView::Literal(value),OriginalValue::PrefabPath(path)=>core::ConstantView::Prefab(path),OriginalValue::PrefabOwner(owner)=>core::ConstantView::Prefab(tree.symbols().text(owner).ok_or("original constant owner spelling absent")?),OriginalValue::ProcedurePath{owner,kind,name}=>core::ConstantView::Procedure{owner:tree.symbols().text(owner).ok_or("original proc constant owner spelling absent")?,kind,name}})}
