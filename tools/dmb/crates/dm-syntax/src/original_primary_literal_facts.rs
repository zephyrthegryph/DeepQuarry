//! Neutral facts on the SAME primary product. No public constructor, Weak,
//! parser, body cache, current-source grant, or independently rebased roster.
use super::*;use std::{io,sync::Arc};
struct Payload{rows:Vec<(Span,crate::OriginalLiteralData)>,extent:Option<usize>,rows_credit:crate::SettingRootLease,fixed_credit:crate::SettingRootLease}
pub struct OriginalPrimaryLiteralFacts(Option<Arc<Payload>>);
impl Clone for OriginalPrimaryLiteralFacts{fn clone(&self)->Self{Self(Some(self.0.as_ref().expect("live primary facts").clone()))}}
impl Drop for OriginalPrimaryLiteralFacts{fn drop(&mut self){if let Some(owner)=self.0.take(){if let Some(payload)=Arc::into_inner(owner){drop(payload)}}}}
/// DATA projection only. Actual source-view/backing authorization belongs to
/// the sealed preprocessing/header installer, not these numeric bounds.
pub struct OriginalLiteralFactsView<'a>{rows:&'a[(Span,crate::OriginalLiteralData)],origin:usize}
impl<'a>OriginalLiteralFactsView<'a>{pub fn raw_parts(&self)->(&'a[(Span,crate::OriginalLiteralData)],usize){(self.rows,self.origin)}pub fn len(&self)->usize{self.rows.len()}pub fn is_empty(&self)->bool{self.rows.is_empty()}}
impl OriginalPrimaryLiteralFacts{
 fn payload(&self)->&Payload{self.0.as_deref().expect("live primary facts")}
 pub(super) fn new(a:&crate::SettingAdmission<'_>)->io::Result<Self>{let fixed_credit=a.reserve(std::mem::size_of::<Payload>()+2*std::mem::size_of::<usize>()).map_err(|e|a.take_operational_error().unwrap_or(e))?;let rows_credit=a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?;Ok(Self(Some(Arc::new(Payload{rows:Vec::new(),extent:None,rows_credit,fixed_credit}))))}
 pub(super) fn append_actual(&mut self,span:Span,data:crate::OriginalLiteralData,a:&crate::SettingAdmission<'_>)->io::Result<()>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;let owner=Arc::get_mut(self.0.as_mut().ok_or(io::ErrorKind::InvalidInput)?).ok_or(io::ErrorKind::InvalidInput)?;
  if owner.extent.is_some()||!a.matches_lease_domain(&owner.rows_credit)||!a.matches_lease_domain(&owner.fixed_credit)||span.start>=span.end||owner.rows.last().is_some_and(|(prior,_)|prior.end>span.start){return Err(io::ErrorKind::InvalidInput.into())}
  if owner.rows.len()==owner.rows.capacity(){let capacity=owner.rows.capacity().checked_mul(2).unwrap_or(owner.rows.len()+1).max(4);let bytes=capacity.checked_mul(std::mem::size_of::<(Span,crate::OriginalLiteralData)>()).ok_or(io::ErrorKind::OutOfMemory)?;let credit=a.reserve(bytes).map_err(|e|a.take_operational_error().unwrap_or(e))?;let layout=std::alloc::Layout::array::<(Span,crate::OriginalLiteralData)>(capacity).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
   // SAFETY: exact nonzero Global T layout, null checked, zero initialized
   // elements. Ordinary Vec uniquely owns/deallocates the SAME layout/capacity.
   let raw=std::ptr::NonNull::new(unsafe{std::alloc::alloc(layout)}).ok_or(io::ErrorKind::OutOfMemory)?;let mut rows=unsafe{Vec::from_raw_parts(raw.as_ptr().cast::<(Span,crate::OriginalLiteralData)>(),0,capacity)};rows.append(&mut owner.rows);let old_rows=std::mem::replace(&mut owner.rows,rows);let old_credit=std::mem::replace(&mut owner.rows_credit,credit);drop(old_rows);drop(old_credit);
  }owner.rows.push((span,data));Ok(())
 }
 pub(super) fn seal_actual_frontier(&mut self,extent:usize,a:&crate::SettingAdmission<'_>)->io::Result<()>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;if !self.is_admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}let owner=Arc::get_mut(self.0.as_mut().ok_or(io::ErrorKind::InvalidInput)?).ok_or(io::ErrorKind::InvalidInput)?;if owner.extent.is_some()||owner.rows.last().is_some_and(|(span,_)|span.end>extent){return Err(io::ErrorKind::InvalidInput.into())}owner.extent=Some(extent);Ok(())
 }
 pub fn is_admitted_by(&self,a:&crate::SettingAdmission<'_>)->bool{a.matches_lease_domain(&self.payload().rows_credit)&&a.matches_lease_domain(&self.payload().fixed_credit)}
 pub fn consumed_extent(&self)->Option<usize>{self.payload().extent}
 pub fn as_slice(&self)->&[(Span,crate::OriginalLiteralData)]{&self.payload().rows}
 /// Bounds are DATA, not source authorization. Source installer must first
 /// match the SAME real source backing/view, then borrow this no-copy window.
 pub fn checked_data_window(&self,window:Span)->io::Result<OriginalLiteralFactsView<'_>>{
  let owner=self.payload();let extent=owner.extent.ok_or(io::ErrorKind::NotConnected)?;if window.start>window.end||window.end>extent{return Err(io::ErrorKind::InvalidInput.into())}
  let first=owner.rows.partition_point(|(span,_)|span.end<=window.start);let last=owner.rows.partition_point(|(span,_)|span.start<window.end);
  if first<last&&(owner.rows[first].0.start<window.start||owner.rows[last-1].0.end>window.end){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual source view cuts an issued literal occurrence"))}
  Ok(OriginalLiteralFactsView{rows:&owner.rows[first..last],origin:window.start})
 }
 pub fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){
  let owner=self.0.as_ref().expect("live primary facts");let fixed=std::mem::size_of::<Payload>()+2*std::mem::size_of::<usize>();visit(Arc::as_ptr(owner)as usize,fixed,fixed);let bytes=owner.rows.capacity()*std::mem::size_of::<(Span,crate::OriginalLiteralData)>();if bytes!=0{visit(owner.rows.as_ptr()as usize,bytes,bytes)}for(_,data)in &owner.rows{data.visit_storage(&mut visit)}owner.rows_credit.visit_counter_storage(|address,bytes|visit(address,bytes,bytes));owner.fixed_credit.visit_counter_storage(|address,bytes|visit(address,bytes,bytes));
 }
}
#[cfg(test)]mod tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 #[test]fn actual_same_roster_window_never_copies_or_cuts_literals_and_last_alias_keeps_real_credit(){
  let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,1<<20,&||Ok(()));let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();let data=crate::OriginalLiteralData::from_value_using("123".to_owned(),crate::OriginalTokenValue::Int(123),&a).unwrap();facts.append_actual(Span::new(5,8),data,&a).unwrap();assert!(facts.checked_data_window(Span::new(0,10)).is_err());facts.seal_actual_frontier(12,&a).unwrap();let view=facts.checked_data_window(Span::new(4,10)).unwrap();let(rows,origin)=view.raw_parts();assert_eq!(origin,4);assert_eq!(rows.as_ptr(),facts.as_slice().as_ptr());assert_eq!(rows[0].0,Span::new(5,8));assert!(facts.checked_data_window(Span::new(6,10)).is_err());assert!(facts.checked_data_window(Span::new(0,7)).is_err());assert!(facts.checked_data_window(Span::new(0,13)).is_err());let alias=facts.clone();drop(facts);assert!(used.load(Ordering::Acquire)>0);assert_eq!(alias.as_slice().len(),1);drop(alias);assert_eq!(used.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]mod full_slice_parser_tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 fn scalar_facts(raw:&str,value:crate::OriginalTokenValue<&str>,origin:usize,a:&crate::SettingAdmission<'_>)->OriginalPrimaryLiteralFacts{let mut facts=OriginalPrimaryLiteralFacts::new(a).unwrap();let data=crate::OriginalLiteralData::from_value_using(raw.into(),value,a).unwrap();facts.append_actual(Span::new(origin,origin+raw.len()),data,a).unwrap();facts.seal_actual_frontier(origin+raw.len(),a).unwrap();facts}
 #[test]fn actual_full_slice_setting_parser_lends_exact_typed_value_across_checked_tu_window_without_reparse(){
  let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=crate::SettingAdmission::new(&counter,1<<24,&poll);let raw="1.23457";let exact=f32::from_bits(0x3f9e0651);let facts=scalar_facts(raw,crate::OriginalTokenValue::Float(exact),113,&a);let lex=crate::lex_spans(raw);
  let root=crate::prepare_setting_expression_with_original_literal_facts(raw,&lex.tokens,Span::new(0,raw.len()),&a,Some(facts.checked_data_window(Span::new(113,113+raw.len())).unwrap())).unwrap();
  let crate::ExprKind::Literal(literal)=&root.kind else{panic!("literal")};assert!(matches!(literal.original_value(),Some(crate::OriginalTokenValue::Float(value))if value.to_bits()==exact.to_bits()));assert!(literal.original_data().unwrap().same_owner(&facts.as_slice()[0].1));assert_eq!(literal.original_origin(),Some(0));drop(root);assert!(counter.load(Ordering::Acquire)>0);drop(facts);assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn actual_full_slice_static_string_uses_one_lexical_value_without_bracket_child_parse_or_runtime_grant(){
  let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=crate::SettingAdmission::new(&counter,1<<24,&poll);let raw="\"[missing.field]\"";let facts=scalar_facts(raw,crate::OriginalTokenValue::String("[missing.field]"),0,&a);let lex=crate::lex_spans(raw);
  let root=crate::prepare_setting_expression_with_original_literal_facts(raw,&lex.tokens,Span::new(0,raw.len()),&a,Some(facts.checked_data_window(Span::new(0,raw.len())).unwrap())).unwrap();let crate::ExprKind::Literal(literal)=&root.kind else{panic!("literal")};assert!(matches!(literal.original_value(),Some(crate::OriginalTokenValue::String("[missing.field]"))));assert!(literal.syntax_parts().unwrap().is_none());drop(root);drop(facts);assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn actual_full_slice_missing_fact_and_first_io_do_not_publish_raw_spelling_fallback_or_partial_root(){
  let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=crate::SettingAdmission::new(&counter,1<<24,&poll);let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();facts.seal_actual_frontier(1,&a).unwrap();let lex=crate::lex_spans("1");let result=crate::prepare_setting_expression_with_original_literal_facts("1",&lex.tokens,Span::new(0,1),&a,Some(facts.checked_data_window(Span::new(0,1)).unwrap()));assert!(matches!(result,Err(crate::SettingSyntaxFailure::Operational(ref e))if e.kind()==io::ErrorKind::Unsupported));let actual=a.take_operational_error().unwrap();assert_eq!(actual.kind(),io::ErrorKind::Unsupported);drop(facts);assert_eq!(counter.load(Ordering::Acquire),0);
  let fault=||Err(io::Error::from_raw_os_error(1450));let failed=crate::SettingAdmission::new(&counter,1<<24,&fault);let result=crate::prepare_setting_expression_with_original_literal_facts("1",&lex.tokens,Span::new(0,1),&failed,None);assert!(matches!(result,Err(crate::SettingSyntaxFailure::Operational(ref e))if e.kind()==io::Error::from_raw_os_error(1450).kind()));assert_eq!(failed.take_operational_error().unwrap().raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),0);
 }
 struct BodySource<'a>{source:&'a str,tokens:&'a[crate::SpanToken],facts:&'a OriginalPrimaryLiteralFacts,a:&'a crate::SettingAdmission<'a>}
 impl crate::SettingSyntaxProvider for BodySource<'_>{
  fn setting(&self,_:&crate::Item)->Result<crate::SettingStatement,crate::Diagnostic>{panic!("no initial settings in fixture")}
  fn original_expression(&self,source:&str,offset:usize)->io::Result<Option<crate::ParsedExpr>>{
   if self.source.get(offset..offset+source.len())!=Some(source){return Err(io::ErrorKind::InvalidData.into())}let end=offset+source.len();let first=self.tokens.partition_point(|token|token.span.end<=offset);let last=self.tokens.partition_point(|token|token.span.start<end);
   Ok(Some(crate::parse_expression_original_token_view(self.source,&self.tokens[first..last],offset,self.a,Some(self.facts.checked_data_window(Span::new(0,self.source.len()))?))))
  }
 }
 #[test]fn actual_same_body_statement_parser_lends_one_primary_numeric_fact_to_its_original_root_and_coordinates(){
  let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=crate::SettingAdmission::new(&counter,1<<24,&poll);let source="/proc/p()\n    return 1.23457\n";let start=source.find("1.23457").unwrap();let mut facts=OriginalPrimaryLiteralFacts::new(&a).unwrap();let data=crate::OriginalLiteralData::from_value_using("1.23457".into(),crate::OriginalTokenValue::Float(f32::from_bits(0x3f9e0651)),&a).unwrap();facts.append_actual(Span::new(start,start+7),data,&a).unwrap();facts.seal_actual_frontier(source.len(),&a).unwrap();let tokens=crate::lex_spans(source);let ast=crate::parse(source);let provider=BodySource{source,tokens:&tokens.tokens,facts:&facts,a:&a};let parsed=crate::parse_body_items_with_context_and_settings(&ast.items[0].children,source,&|_|None,&provider,&a);assert!(parsed.diagnostics.is_empty(),"{:?}",parsed.diagnostics);
  let crate::StatementKind::Return(Some(root))=&parsed.statements[0].kind else{panic!("return")};assert_eq!(root.span,Span::new(start,start+7));let crate::ExprKind::Literal(literal)=&root.kind else{panic!("literal")};assert!(matches!(literal.original_value(),Some(crate::OriginalTokenValue::Float(value))if value.to_bits()==0x3f9e0651));assert!(literal.original_data().unwrap().same_owner(&facts.as_slice()[0].1));drop(parsed);drop(facts);assert_eq!(counter.load(Ordering::Acquire),0);
 }
}
