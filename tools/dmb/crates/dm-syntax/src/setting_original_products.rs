//! First-parser Original VALUE observation and constructor DATA only.
//! This is not a source/current-model/EOF capability or native completeness.
use crate::{Span,SettingAdmission,SettingExpression,OriginalConstructorFacts};
use std::io;
#[derive(Default,Clone)]
pub struct OriginalSettingProducts{constructors:OriginalConstructorFacts,complete:Option<Span>}
impl OriginalSettingProducts{
 pub(crate) fn from_actual(original:Option<crate::expression_parser::OriginalSimpleExpression>,span:Span,native:Option<crate::NativeExpressionParserFacts>,constructors:OriginalConstructorFacts)->Self{
  let complete=original.filter(|p|p.is_original()&&p.kind()==crate::expression_parser::OriginalSimpleKind::Complete&&p.span()==span).filter(|_|native.is_some_and(|n|n.exhausted()&&!n.recovered())).map(|_|span);
  Self{constructors,complete}
 }
 pub(crate) fn from_slot(constructors:OriginalConstructorFacts,span:Span,complete:bool)->Self{Self{constructors,complete:complete.then_some(span)}}
 pub(crate) fn complete_at(&self,span:Span)->bool{self.complete==Some(span)}
 pub fn constructors(&self)->&OriginalConstructorFacts{&self.constructors}
 /// The actual source owner must first bind the SAME returned slot root/input.
 /// Geometry alone is never source identity and never repairs a missing issue.
 pub fn original_value_for(&self,root:&SettingExpression,a:&SettingAdmission<'_>)->io::Result<bool>{
  let pending=(||{a.checkpoint()?;if !root.is_retained_in(a)||!self.constructors.is_admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}Ok(self.complete_at(root.original_expression().span))})();match a.take_operational_error(){Some(first)=>Err(first),None=>pending}
 }
}
