//! SAME consumed Original template parts and Pratt children, not a bracket parser.
use super::*;use std::{io,mem::size_of};
fn poll(a:&crate::SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|error|a.take_operational_error().unwrap_or(error))}
struct Part{data:crate::OriginalLiteralData,span:Span,expression:Option<Expr>,tokens:Vec<crate::SpanToken>}
pub(crate) struct OriginalTemplateBuilder{rows:Vec<Part>,credit:Option<crate::SettingRootLease>}
impl Drop for OriginalTemplateBuilder{fn drop(&mut self){for mut row in self.rows.drain(..){if let Some(expr)=row.expression.take(){crate::setting_drop::drop_expression(expr,None)}}}}
struct PendingParts(Option<LiteralParts>);
impl Drop for PendingParts{fn drop(&mut self){if let Some(parts)=self.0.take(){crate::setting_drop::drop_literal_parts(parts,None)}}}
impl OriginalTemplateBuilder{
 pub(crate) fn new(a:&crate::SettingAdmission<'_>)->io::Result<Self>{poll(a)?;Ok(Self{rows:Vec::new(),credit:Some(a.reserve(size_of::<Self>())?)})}
 fn grow(&mut self,n:usize,a:&crate::SettingAdmission<'_>)->io::Result<()>{a.grow(self.credit.as_mut().ok_or(io::ErrorKind::InvalidInput)?,n)}
 pub(crate) fn push(&mut self,data:crate::OriginalLiteralData,span:Span,expression:Option<Expr>,tokens:&[crate::Token],a:&crate::SettingAdmission<'_>)->io::Result<()>{
  // Own the AST on ALL fallible paths; its iterative release precedes credit.
  let mut part=Part{data,span,expression,tokens:Vec::new()};
  let result=(||{poll(a)?;let n=tokens.len().checked_mul(size_of::<crate::SpanToken>()).and_then(|n|n.checked_mul(4)).ok_or(io::ErrorKind::OutOfMemory)?;self.grow(n,a)?;part.tokens.try_reserve_exact(tokens.len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if part.tokens.capacity()>tokens.len().saturating_mul(4){return Err(io::ErrorKind::OutOfMemory.into())}for t in tokens{part.tokens.push(crate::SpanToken{kind:t.kind,span:t.span});}
   if self.rows.len()==self.rows.capacity(){let n=self.rows.len().checked_add(1).and_then(usize::checked_next_power_of_two).ok_or(io::ErrorKind::OutOfMemory)?;self.grow(n.checked_mul(4*size_of::<Part>()).ok_or(io::ErrorKind::OutOfMemory)?,a)?;self.rows.try_reserve_exact(n-self.rows.len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if self.rows.capacity()>n*4{return Err(io::ErrorKind::OutOfMemory.into())}}poll(a)?;Ok(())})();
  if let Err(error)=result{if let Some(expr)=part.expression.take(){crate::setting_drop::drop_expression(expr,None)}return Err(error)}self.rows.push(part);Ok(())
 }
 pub(crate) fn finish(mut self,raw:&str,origin:usize,a:&crate::SettingAdmission<'_>)->io::Result<LiteralText>{
  poll(a)?;if self.rows.len()<2{return Err(io::ErrorKind::InvalidInput.into())}
  let last=self.rows.len()-1;let mut previous=origin;let mut nonempty=false;
  for(i,row)in self.rows.iter().enumerate(){poll(a)?;let text=match(i,row.data.value()){(0,crate::OriginalTokenValue::InterpBegin(s))=>s,(i,crate::OriginalTokenValue::InterpEnd(s))if i==last=>s,(i,crate::OriginalTokenValue::InterpPart(s))if i>0&&i<last=>s,_=>return Err(io::ErrorKind::InvalidInput.into())};if row.span.start<previous||row.span.end>origin.checked_add(raw.len()).ok_or(io::ErrorKind::InvalidInput)?||row.span.start>=row.span.end{return Err(io::ErrorKind::InvalidInput.into())}let local=Span::new(row.span.start-origin,row.span.end-origin);if raw.get(local.range())!=Some(row.data.raw()){return Err(io::Error::new(io::ErrorKind::InvalidData,"actual template fragment differs from its producer source range"))}if i==0&&row.expression.is_some(){return Err(io::ErrorKind::InvalidInput.into())}previous=row.span.end;nonempty|=!text.is_empty();}
  if self.rows[0].span.start!=origin||previous!=origin+raw.len(){return Err(io::ErrorKind::InvalidInput.into())}
  // Exact consumed literal width bounds eager child/cleanup/storage; it grants
  // neither unseen BODY demand nor a second parser. Ordinary literals skip it.
  let peak=crate::setting_prepare::literal_parser_peak(raw,a)?;self.grow(peak.checked_add(2*size_of::<LiteralState>()).ok_or(io::ErrorKind::OutOfMemory)?,a)?;
  let mut pending=PendingParts(Some(LiteralParts{runtime_error:Some("Original typed template runtime byte decoding is not yet issued".into()),fragments:Vec::new(),template:Vec::new(),expressions:Vec::new(),lexical:Ok(LiteralLexicalShape{interpolated:true,pinned_segment_nonempty:nonempty})}));
  let parts=pending.0.as_mut().unwrap();parts.fragments.try_reserve_exact(self.rows.len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;parts.expressions.try_reserve_exact(self.rows.len()-1).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
  if parts.fragments.capacity()>self.rows.len()*4||parts.expressions.capacity()>self.rows.len()*4{return Err(io::ErrorKind::OutOfMemory.into())}
  for mut row in self.rows.drain(..){let expression=row.expression.take().map(|expr|{let index=parts.expressions.len();parts.expressions.push(expr);index});for token in &mut row.tokens{token.span.start=token.span.start.checked_sub(origin).ok_or(io::ErrorKind::InvalidInput)?;token.span.end=token.span.end.checked_sub(origin).ok_or(io::ErrorKind::InvalidInput)?;}parts.fragments.push(LiteralFragment{range:Span::new(row.span.start-origin,row.span.end-origin),expression,tokens:row.tokens,original:Some(row.data)});}
  decode_actual_template_runtime(parts,a)?;
  let raw=crate::admitted_message_using(a,self.credit.as_mut().unwrap(),|out|out.write_str(raw))?;poll(a)?;
  let retention=OnceLock::new();let _=retention.set(crate::SharedSettingRetention::new(self.credit.take().unwrap()));
  let prepared=OnceLock::new();let _=prepared.set(Ok(pending.0.take()));
  Ok(LiteralText(Backing::Text(LiteralOwner::new(LiteralState{raw,origin,parts:prepared,retention,original_prepared:true}))))
 }
}

#[cfg(test)]mod tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 #[test]fn actual_typed_template_owner_keeps_same_children_and_fragment_values_without_relex(){
  let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let raw="\"head[x.y]tail\"";let mut builder=OriginalTemplateBuilder::new(&a).unwrap();
  let begin=crate::OriginalLiteralData::from_value_with_mode_using("\"head[".into(),crate::OriginalTokenValue::InterpBegin("[typed, not grammar]"),crate::OriginalStringMode::Normal,&a).unwrap();
  let end=crate::OriginalLiteralData::from_value_with_mode_using("]tail\"".into(),crate::OriginalTokenValue::InterpEnd("tail"),crate::OriginalStringMode::Normal,&a).unwrap();
  builder.push(begin,Span::new(0,6),None,&[],&a).unwrap();let mut child=crate::parse_expression("x.y").expr.unwrap();shift_expression(&mut child,6);let mut tokens=crate::lex("x.y").tokens;for token in &mut tokens{token.span.start+=6;token.span.end+=6;}
  let before=literal_child_parses_for_test();builder.push(end,Span::new(9,15),Some(child),&tokens,&a).unwrap();let value=builder.finish(raw,0,&a).unwrap();assert_eq!(literal_child_parses_for_test(),before);
  assert!(value.parts().unwrap().is_some());let parts=value.syntax_parts().unwrap().unwrap();assert_eq!(parts.expressions.len(),1);assert!(matches!(parts.expressions[0].kind,ExprKind::Member{..}));let address=&parts.expressions[0]as*const Expr;
  let alias=value.clone();let mut texts=Vec::new();for part in alias.pinned_fragments().unwrap().unwrap(){let mut text=String::new();part.unwrap().write_text(&mut text).unwrap();texts.push(text)}assert_eq!(texts,["[typed, not grammar]","tail"]);assert_eq!(alias.syntax_parts().unwrap().unwrap().expressions.as_ptr(),address);drop(value);assert!(used.load(Ordering::Acquire)>0);assert_eq!(alias.syntax_parts().unwrap().unwrap().expressions.as_ptr(),address);drop(alias);assert_eq!(used.load(Ordering::Acquire),0);assert_eq!(literal_child_parses_for_test(),before);
 }
 #[test]fn template_part_never_masquerades_as_complete_static_or_empty_default(){let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let part=crate::OriginalLiteralData::from_value_using("\"x[".into(),crate::OriginalTokenValue::InterpBegin("x"),&a).unwrap();assert_eq!(LiteralText::from_original_data(&part,0,&a).unwrap_err().kind(),io::ErrorKind::Unsupported);let mut b=OriginalTemplateBuilder::new(&a).unwrap();b.push(part,Span::new(0,3),None,&[],&a).unwrap();assert_eq!(b.finish("\"x[",0,&a).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]fn eager_template_failure_preserves_first_io_and_releases_actual_payload_before_credit(){let used=Arc::new(AtomicUsize::new(0));let good=||Ok(());let a=crate::SettingAdmission::new(&used,8<<20,&good);let mut b=OriginalTemplateBuilder::new(&a).unwrap();for(raw,value,span)in[("\"[",crate::OriginalTokenValue::InterpBegin(""),Span::new(0,2)),("]\"",crate::OriginalTokenValue::InterpEnd(""),Span::new(2,4))]{b.push(crate::OriginalLiteralData::from_value_using(raw.into(),value,&a).unwrap(),span,None,&[],&a).unwrap()}
  let stopped=||Err(io::Error::from_raw_os_error(1450));let fail=crate::SettingAdmission::new(&used,8<<20,&stopped);assert_eq!(b.finish("\"[]\"",0,&fail).unwrap_err().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),0);
  let tiny=crate::SettingAdmission::new(&used,0,&good);assert_eq!(OriginalTemplateBuilder::new(&tiny).err().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),0);
 }
}

/// Decode only actual typed segment VALUE bytes. Child slots are known from
/// Begin/Part/End products, never searched for in the text or reparsed.
fn decode_actual_template_runtime(parts:&mut LiteralParts,a:&crate::SettingAdmission<'_>)->io::Result<()>{
 let text_bytes=parts.fragments.iter().try_fold(0usize,|n,row|{let data=row.original.as_ref().ok_or(io::ErrorKind::InvalidInput)?;let s=match data.value(){crate::OriginalTokenValue::InterpBegin(s)|crate::OriginalTokenValue::InterpPart(s)|crate::OriginalTokenValue::InterpEnd(s)=>s,_=>return Err(io::ErrorKind::InvalidInput)};n.checked_add(s.len()).ok_or(io::ErrorKind::OutOfMemory)}).map_err(io::Error::from)?;
 let cap=text_bytes.checked_mul(16).and_then(|n|n.checked_add(parts.fragments.len().checked_mul(2)?)).ok_or(io::ErrorKind::OutOfMemory)?;
 let mut template=Vec::new();template.try_reserve_exact(cap).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if template.capacity()>cap.saturating_mul(4){return Err(io::ErrorKind::OutOfMemory.into())}
 let mut runtime_error=None;let mut next_marker=None;let mut substituted=false;
 for(i,row)in parts.fragments.iter().enumerate(){
  poll(a)?;
  if i>0{substituted=true;let marker=next_marker.take().unwrap_or_else(||if row.expression.is_none(){1}else if interpolation_starts_sentence(&template){2}else{1});template.extend([0xff,marker]);}
  let data=row.original.as_ref().ok_or(io::ErrorKind::InvalidInput)?;let value=match data.value(){crate::OriginalTokenValue::InterpBegin(s)|crate::OriginalTokenValue::InterpPart(s)|crate::OriginalTokenValue::InterpEnd(s)=>s,_=>return Err(io::ErrorKind::InvalidInput.into())};
  if data.string_mode()!=crate::OriginalStringMode::Normal{runtime_error.get_or_insert_with(||"Original interpolation runtime lexical mode is not issued".into());continue}
  let normalized=value.contains('\r').then(||without_cr(value).0);let value=normalized.as_deref().unwrap_or(value);let mut at=0;
  while at<value.len(){poll(a)?;let ch=value[at..].chars().next().unwrap();if ch=='\\'{if let Err(error)=decode_text_escape(value,&mut at,&mut template,&mut runtime_error,&mut next_marker,substituted){runtime_error.get_or_insert(error);break}}else{let mut bytes=[0;4];if runtime_error.is_none(){template.extend_from_slice(ch.encode_utf8(&mut bytes).as_bytes());}at+=ch.len_utf8();}}
 }
 poll(a)?;parts.template=template;parts.runtime_error=runtime_error;Ok(())
}

#[cfg(test)]mod runtime_state_controls{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 fn typed(raw:&str,begin:&str,end:&str,empty:bool,a:&crate::SettingAdmission<'_>)->LiteralText{
  let marker=if empty{"[]"}else{"[x]"};let at=raw.find(marker).unwrap();let child_end=at+marker.len()-1;let mut builder=OriginalTemplateBuilder::new(a).unwrap();let first=crate::OriginalLiteralData::from_value_with_mode_using(raw[..at+1].into(),crate::OriginalTokenValue::InterpBegin(begin),crate::OriginalStringMode::Normal,a).unwrap();builder.push(first,Span::new(0,at+1),None,&[],a).unwrap();let last=crate::OriginalLiteralData::from_value_with_mode_using(raw[child_end..].into(),crate::OriginalTokenValue::InterpEnd(end),crate::OriginalStringMode::Normal,a).unwrap();let child=(!empty).then(||{let mut e=crate::parse_expression("x").expr.unwrap();shift_expression(&mut e,at+1);e});let tokens=if empty{Vec::new()}else{vec![crate::Token{kind:crate::TokenKind::Ident,span:Span::new(at+1,at+2),text:"x".into()}]};builder.push(last,Span::new(child_end,raw.len()),child,&tokens,a).unwrap();builder.finish(raw,0,a).unwrap()
 }
 #[test]fn original_typed_parts_and_ordinary_native_decoder_share_entire_macro_state_without_child_reparse(){
  let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,16<<20,&||Ok(()));
  for(raw,begin,end,empty)in[(r#""hello [x].""#,"hello ",".",false),(r#""\the [x] \he""#,r"\the ",r" \he",false),(r#""\ref[x]\th""#,r"\ref",r"\th",false),(r#""\proper[x]""#,r"\proper","",false),(r#""\bold [x]\his""#,r"\bold ",r"\his",false),(r#""\ref[]end""#,r"\ref","end",true),(r#""\bad[x]tail""#,r"\bad","tail",false)]{
   let ordinary=LiteralText::at(raw.into(),0);let old=ordinary.syntax_parts().unwrap().unwrap();let before=literal_child_parses_for_test();let value=typed(raw,begin,end,empty,&a);let native=value.syntax_parts().unwrap().unwrap();assert_eq!(native.template,old.template,"{raw}");assert_eq!(native.runtime_error,old.runtime_error,"{raw}");assert_eq!(native.expressions.len(),old.expressions.len(),"{raw}");assert_eq!(literal_child_parses_for_test(),before);drop(value);assert_eq!(used.load(Ordering::Acquire),0);
  }
 }
 #[test]fn unpublished_original_geometry_keeps_actual_child_and_raw_allocations_and_credit(){
  let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,16<<20,&||Ok(()));let raw=r#""before[x]after""#;
  let value=typed(raw,"before","after",false,&a);let raw_address=value.raw_storage().as_ptr();let child_address=value.syntax_parts().unwrap().unwrap().expressions.as_ptr();let child_span=value.syntax_parts().unwrap().unwrap().expressions[0].span;let credit=used.load(Ordering::Acquire);let parses=literal_child_parses_for_test();
  let mut root=Expr{kind:ExprKind::Literal(value),span:Span::new(0,raw.len())};shift_unpublished_expression_using(&mut root,31,&a).unwrap();assert_eq!(root.span,Span::new(31,raw.len()+31));let ExprKind::Literal(value)=&root.kind else{panic!("literal")};assert_eq!(value.raw_storage().as_ptr(),raw_address);let parts=value.syntax_parts().unwrap().unwrap();assert_eq!(parts.expressions.as_ptr(),child_address);assert_eq!(parts.expressions[0].span,Span::new(child_span.start+31,child_span.end+31));assert_eq!(used.load(Ordering::Acquire),credit);assert_eq!(literal_child_parses_for_test(),parses);drop(root);assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn shared_foreign_quota_and_first_io_refuse_before_original_geometry_changes(){
  let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,16<<20,&||Ok(()));let raw=r#""before[x]after""#;let value=typed(raw,"before","after",false,&a);let alias=value.clone();let credit=used.load(Ordering::Acquire);let mut root=Expr{kind:ExprKind::Literal(value),span:Span::new(0,raw.len())};
  assert_eq!(shift_unpublished_expression_using(&mut root,31,&a).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(root.span,Span::new(0,raw.len()));assert_eq!(used.load(Ordering::Acquire),credit);drop(alias);
  let other=Arc::new(AtomicUsize::new(0));let foreign=crate::SettingAdmission::new(&other,16<<20,&||Ok(()));assert_eq!(shift_unpublished_expression_using(&mut root,31,&foreign).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(other.load(Ordering::Acquire),0);
  let low=crate::SettingAdmission::new(&used,credit-1,&||Ok(()));assert_eq!(shift_unpublished_expression_using(&mut root,31,&low).unwrap_err().kind(),io::ErrorKind::OutOfMemory);let stopped=||Err(io::Error::from_raw_os_error(1450));let failed=crate::SettingAdmission::new(&used,16<<20,&stopped);assert_eq!(shift_unpublished_expression_using(&mut root,31,&failed).unwrap_err().raw_os_error(),Some(1450));assert_eq!(root.span,Span::new(0,raw.len()));assert_eq!(used.load(Ordering::Acquire),credit);drop(root);assert_eq!(used.load(Ordering::Acquire),0);
 }

 #[test]fn neutral_static_geometry_can_borrow_independent_value_credit_without_mutating_payload(){
  let source=Arc::new(AtomicUsize::new(0));let target=Arc::new(AtomicUsize::new(0));let from=crate::SettingAdmission::new(&source,16<<20,&||Ok(()));let to=crate::SettingAdmission::new(&target,16<<20,&||Ok(()));let raw=r#""value""#;let data=crate::OriginalLiteralData::from_value_using(raw.into(),crate::OriginalTokenValue::String("value"),&from).unwrap();let credit=source.load(Ordering::Acquire);let value=LiteralText::from_original_data(&data,0,&to).unwrap();let mut root=Expr{kind:ExprKind::Literal(value),span:Span::new(0,raw.len())};shift_unpublished_expression_using(&mut root,31,&to).unwrap();let ExprKind::Literal(value)=&root.kind else{panic!("literal")};assert!(value.original_data().unwrap().same_owner(&data));assert_eq!(value.original_origin(),Some(31));assert!(matches!(data.value(),crate::OriginalTokenValue::String("value")));assert_eq!(source.load(Ordering::Acquire),credit);assert_eq!(target.load(Ordering::Acquire),0);drop(root);assert_eq!(source.load(Ordering::Acquire),credit);drop(data);assert_eq!(source.load(Ordering::Acquire),0);
 }

}
