//! SAME consumed Original template parts and Pratt children, not a bracket parser.
use super::*;use std::{io,mem::size_of};
fn poll(a:&crate::SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|error|a.take_operational_error().unwrap_or(error))}
fn capacity_bytes<T>(count:usize)->io::Result<usize>{
    count.checked_mul(size_of::<T>()).ok_or(io::ErrorKind::OutOfMemory.into())
}
fn envelope<T>(count:usize)->io::Result<usize>{
    capacity_bytes::<T>(count.checked_mul(4).ok_or(io::ErrorKind::OutOfMemory)?)
}
fn refund(a:&crate::SettingAdmission<'_>,credit:&mut crate::SettingRootLease,bytes:usize)->io::Result<()>{
    a.shrink(credit,bytes).map_err(|error|a.take_operational_error().unwrap_or(error))
}
struct Part{data:crate::OriginalLiteralData,span:Span,expression:Option<Expr>,tokens:Vec<crate::SpanToken>,native:Option<crate::NativeExpressionParserFacts>,native_observed:bool,empty_native:bool}
pub(crate) struct OriginalTemplateBuilder<'a,'op>{rows:Vec<Vec<Part>>,len:usize,credit:Option<crate::SettingRootLease>,cleanup:Option<crate::parser_cleanup::ParserCleanup<'a,'op>>}
fn release_parser_child(expression:Expr,cleanup:Option<&crate::parser_cleanup::ParserCleanup<'_, '_>>){
 if let Some(cleanup)=cleanup{cleanup.drop_expression(expression)}else{crate::setting_drop::drop_expression(expression,None)}
}
// Incoming raw child enters this guard BEFORE the first fallible callback.
// Part/argument/field Vec element layouts remain exactly the existing layouts.
struct IncomingPart<'a,'op>{part:Option<Part>,cleanup:Option<crate::parser_cleanup::ParserCleanup<'a,'op>>}
impl Drop for IncomingPart<'_, '_>{fn drop(&mut self){if let Some(part)=&mut self.part{if let Some(child)=part.expression.take(){release_parser_child(child,self.cleanup.as_ref())}}}}
impl Drop for OriginalTemplateBuilder<'_, '_>{fn drop(&mut self){for block in &mut self.rows{for mut row in block.drain(..){if let Some(expr)=row.expression.take(){release_parser_child(expr,self.cleanup.as_ref())}}}}}
struct PendingParts<'a,'op>{parts:Option<LiteralParts>,anchor:Option<crate::SharedSettingRetention>,parser:Option<crate::SettingRootLease>,cleanup:Option<crate::parser_cleanup::ParserCleanup<'a,'op>>}
impl Drop for PendingParts<'_, '_>{fn drop(&mut self){if let Some(mut parts)=self.parts.take(){
 if let Some(cleanup)=&self.cleanup{for expression in parts.expressions.drain(..){cleanup.drop_expression(expression)}}
 crate::setting_drop::drop_literal_parts(parts,self.anchor.take())
}}}
impl OriginalTemplateBuilder<'static,'static>{
 pub(crate) fn new(a:&crate::SettingAdmission<'_>)->io::Result<Self>{poll(a)?;Ok(Self{rows:Vec::new(),len:0,credit:Some(a.reserve(size_of::<Self>())?),cleanup:None})}
}
impl<'a,'op> OriginalTemplateBuilder<'a,'op>{
 pub(crate) fn new_with_cleanup(a:&'a crate::SettingAdmission<'op>,cleanup:crate::parser_cleanup::ParserCleanup<'a,'op>)->io::Result<Self>{
  cleanup.ensure_nodes(Some(a),0)?;poll(a)?;
  Ok(Self{rows:Vec::new(),len:0,credit:Some(a.reserve(size_of::<Self>())?),cleanup:Some(cleanup)})
 }
 #[track_caller]
 fn grow(&mut self,n:usize,a:&crate::SettingAdmission<'_>)->io::Result<()>{
    a.grow(self.credit.as_mut().ok_or(io::ErrorKind::InvalidInput)?,n)
        .map_err(|error|a.take_operational_error().unwrap_or(error))
 }
 pub(crate) fn push(&mut self,data:crate::OriginalLiteralData,span:Span,expression:Option<Expr>,tokens:&[crate::Token],a:&crate::SettingAdmission<'_>)->io::Result<()>{self.push_inner(data,span,expression,tokens,None,false,false,a)}
 pub(crate) fn push_with_native_facts(&mut self,data:crate::OriginalLiteralData,span:Span,expression:Option<Expr>,tokens:&[crate::Token],native:Option<crate::NativeExpressionParserFacts>,empty_native:bool,a:&crate::SettingAdmission<'_>)->io::Result<()>{self.push_inner(data,span,expression,tokens,native,true,empty_native,a)}
 fn push_inner(&mut self,data:crate::OriginalLiteralData,span:Span,expression:Option<Expr>,tokens:&[crate::Token],native:Option<crate::NativeExpressionParserFacts>,native_observed:bool,empty_native:bool,a:&crate::SettingAdmission<'_>)->io::Result<()>{
  // Own the AST on ALL fallible paths; its iterative release precedes credit.
  let mut incoming=IncomingPart{part:Some(Part{data,span,expression,tokens:Vec::new(),native,native_observed,empty_native}),cleanup:self.cleanup.clone()};
  let part=incoming.part.as_mut().unwrap();
  let result:io::Result<usize>=(||{
    poll(a)?;
    let next_len=self.len.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;
    if empty_native&&(part.expression.is_some()||tokens.iter().any(|token|!matches!(token.kind,crate::TokenKind::Whitespace|crate::TokenKind::Newline|crate::TokenKind::Comment))){return Err(io::ErrorKind::InvalidInput.into())}
    let token_bound=envelope::<crate::SpanToken>(tokens.len())?;
    self.grow(token_bound,a)?;
    part.tokens.try_reserve_exact(tokens.len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
    let actual=capacity_bytes::<crate::SpanToken>(part.tokens.capacity())?;
    refund(a,self.credit.as_mut().unwrap(),token_bound.checked_sub(actual).ok_or(io::ErrorKind::OutOfMemory)?)?;
    for token in tokens {
        part.tokens.push(crate::SpanToken{kind:token.kind,span:token.span});
    }
    if self.rows.last().is_none_or(|block|block.len()==block.capacity().min(64)){
        // Preserve small-template geometry, then cap each real row allocation.
        // Existing blocks stay physically live and paid throughout new growth.
        let count=self.rows.last().map_or(1,|block|block.capacity().saturating_mul(2).min(64));
        if self.rows.len()==self.rows.capacity(){
            let old=capacity_bytes::<Vec<Part>>(self.rows.capacity())?;
            let outer=self.rows.len().checked_add(1).and_then(usize::checked_next_power_of_two).ok_or(io::ErrorKind::OutOfMemory)?;
            let bound=envelope::<Vec<Part>>(outer)?;self.grow(bound,a)?;
            self.rows.try_reserve_exact(outer-self.rows.len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
            let actual=capacity_bytes::<Vec<Part>>(self.rows.capacity())?;
            refund(a,self.credit.as_mut().unwrap(),old.checked_add(bound.checked_sub(actual).ok_or(io::ErrorKind::OutOfMemory)?).ok_or(io::ErrorKind::OutOfMemory)?)?;
        }
        let bound=envelope::<Part>(count)?;self.grow(bound,a)?;
        let mut block=Vec::new();block.try_reserve_exact(count).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
        let actual=capacity_bytes::<Part>(block.capacity())?;
        refund(a,self.credit.as_mut().unwrap(),bound.checked_sub(actual).ok_or(io::ErrorKind::OutOfMemory)?)?;
        self.rows.push(block);
    }
    poll(a)?;Ok(next_len)
  })();
  let next_len=result?;self.rows.last_mut().expect("funded row block").push(incoming.part.take().unwrap());self.len=next_len;Ok(())
 }
 pub(crate) fn finish(mut self,raw:&str,origin:usize,a:&crate::SettingAdmission<'_>)->io::Result<LiteralText>{
  poll(a)?;if self.len<2{return Err(io::ErrorKind::InvalidInput.into())}
  let last=self.len-1;let mut previous=origin;let mut nonempty=false;
  for(i,row)in self.rows.iter().flatten().enumerate(){poll(a)?;let text=match(i,row.data.value()){(0,crate::OriginalTokenValue::InterpBegin(s))=>s,(i,crate::OriginalTokenValue::InterpEnd(s))if i==last=>s,(i,crate::OriginalTokenValue::InterpPart(s))if i>0&&i<last=>s,_=>return Err(io::ErrorKind::InvalidInput.into())};if row.span.start<previous||row.span.end>origin.checked_add(raw.len()).ok_or(io::ErrorKind::InvalidInput)?||row.span.start>=row.span.end{return Err(io::ErrorKind::InvalidInput.into())}let local=Span::new(row.span.start-origin,row.span.end-origin);if raw.get(local.range())!=Some(row.data.raw()){return Err(io::Error::new(io::ErrorKind::InvalidData,"actual template fragment differs from its producer source range"))}if i==0&&row.expression.is_some(){return Err(io::ErrorKind::InvalidInput.into())}previous=row.span.end;nonempty|=!text.is_empty();}
  if self.rows[0][0].span.start!=origin||previous!=origin+raw.len(){return Err(io::ErrorKind::InvalidInput.into())}
  // Move already parsed children and typed fragments. The producer's incoming
  // parse/cleanup guard covers failures before this builder establishes full
  // private-child custody below; no template/alias is exposed before then.
  let(mut native_issued,mut native_complete,mut native_recovered,mut native_deferred)=(true,true,false,false);
  for(i,row)in self.rows.iter().flatten().enumerate(){native_issued&=row.native_observed;if i==0{continue}
   match(&row.expression,row.native){(Some(expression),Some(facts))=>{native_recovered|=facts.recovered();native_deferred|=facts.deferred();native_complete&=facts.is_complete()&&facts.complete_span()==Some(expression.span);},(None,_)if row.empty_native=>(),_=>{native_complete=false;native_deferred=true;}}
  }
  let count=self.len;let expression_count=self.rows.iter().flatten().filter(|row|row.expression.is_some()).count();
  let fragment_bound=envelope::<LiteralFragment>(count)?;
  let expression_bound=envelope::<Expr>(expression_count)?;
  let owners=size_of::<LiteralState>()+2*size_of::<usize>()+crate::setting_expression::root_storage_envelope();
  self.grow(owners,a)?;
  self.grow(fragment_bound,a)?;
  self.grow(expression_bound,a)?;
  let mut pending=PendingParts{parts:Some(LiteralParts{native_parser_facts:crate::expression_parser::NativeExpressionParserState::aggregate(native_issued.then(||crate::NativeExpressionParserFacts::aggregate(native_complete,native_recovered,native_deferred||!native_complete))),runtime_error:None,fragments:Vec::new(),template:Vec::new(),expressions:Vec::new(),lexical:Ok(LiteralLexicalShape{interpolated:true,pinned_segment_nonempty:nonempty})}),anchor:None,parser:None,cleanup:self.cleanup.clone()};
  let parts=pending.parts.as_mut().unwrap();parts.fragments.try_reserve_exact(count).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;parts.expressions.try_reserve_exact(expression_count).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
  let unused_fragments=fragment_bound.checked_sub(capacity_bytes::<LiteralFragment>(parts.fragments.capacity())?).ok_or(io::ErrorKind::OutOfMemory)?;
  let unused_expressions=expression_bound.checked_sub(capacity_bytes::<Expr>(parts.expressions.capacity())?).ok_or(io::ErrorKind::OutOfMemory)?;
  refund(a,self.credit.as_mut().unwrap(),unused_fragments.checked_add(unused_expressions).ok_or(io::ErrorKind::OutOfMemory)?)?;
  // Keep every unvisited row in Builder custody across fallible geometry.
  // Blocks contain at most 64 rows, so removing the first row is bounded and
  // never allocates. A Drain would default-drop remaining raw AST on error.
  for block in &mut self.rows{while !block.is_empty(){
   let mut incoming=IncomingPart{part:Some(block.remove(0)),cleanup:self.cleanup.clone()};
   let row=incoming.part.as_mut().unwrap();
   let expression=row.expression.take().map(|expr|{let index=parts.expressions.len();parts.expressions.push(expr);index});
   for token in &mut row.tokens{token.span.start=token.span.start.checked_sub(origin).ok_or(io::ErrorKind::InvalidInput)?;token.span.end=token.span.end.checked_sub(origin).ok_or(io::ErrorKind::InvalidInput)?;}
   // No child remains in this row; fragment storage was prepaid above.
   let row=incoming.part.take().unwrap();
   parts.fragments.push(LiteralFragment{range:Span::new(row.span.start-origin,row.span.end-origin),expression,tokens:row.tokens,original:Some(row.data)});
  }}
  let mut builder_bytes=capacity_bytes::<Vec<Part>>(self.rows.capacity())?.checked_add(size_of::<Self>()).ok_or(io::ErrorKind::OutOfMemory)?;
  for block in &self.rows{builder_bytes=builder_bytes.checked_add(capacity_bytes::<Part>(block.capacity())?).ok_or(io::ErrorKind::OutOfMemory)?;}
  drop(std::mem::take(&mut self.rows));self.len=0;
  refund(a,self.credit.as_mut().unwrap(),builder_bytes)?;
  decode_actual_template_runtime(parts,a,self.credit.as_mut().unwrap())?;
  if parts.runtime_error.is_some()||parts.lexical.is_err(){if let Some(facts)=parts.native_parser_facts.facts(None){parts.native_parser_facts=crate::expression_parser::NativeExpressionParserState::aggregate(Some(crate::NativeExpressionParserFacts::aggregate(false,facts.recovered(),true)));}}
  // Incoming children are now stable SAME native AST. An already complete
  // nested Original template carries its own exact custody and is not counted
  // twice. All other child payload and actual cleanup work are retained here
  // BEFORE this template or any alias can escape the builder.
  // Reuse the existing body preflight for ordinary nested Text. Genuine
  // Original-prepared children need zero parser work; generic callers retain
  // the SAME real parser permit through measurement, attachment and failure
  // cleanup. Pending releases child AST before this permit on every error.
  let mut parser_bytes=0usize;
  for child in &parts.expressions{let peak=crate::body_literal_syntax::input_peak(child,a).map_err(|proxy|a.take_operational_error().unwrap_or(proxy))?;parser_bytes=parser_bytes.checked_add(peak).ok_or(io::ErrorKind::OutOfMemory)?;}
  pending.parser=Some(a.reserve(parser_bytes).map_err(|proxy|a.take_operational_error().unwrap_or(proxy))?);
  let parts=pending.parts.as_ref().unwrap();
  let(mut child_bytes,mut child_cleanup)=(0usize,1usize);
  for child in &parts.expressions{
   let measured=crate::setting_prepare::prepare_body_measure(child,a).map_err(|proxy|a.take_operational_error().unwrap_or(proxy))?;
   child_bytes=child_bytes.checked_add(measured.bytes).ok_or(io::ErrorKind::OutOfMemory)?;
   child_cleanup=child_cleanup.checked_add(measured.cleanup_nodes).ok_or(io::ErrorKind::OutOfMemory)?;
  }
  let cleanup=child_cleanup.checked_mul(4*(size_of::<Expr>()+size_of::<crate::SharedSettingRetention>())).ok_or(io::ErrorKind::OutOfMemory)?;
  self.grow(child_bytes.checked_add(cleanup).ok_or(io::ErrorKind::OutOfMemory)?,a)?;
  let raw=crate::admitted_message_using(a,self.credit.as_mut().unwrap(),|out|out.write_str(raw))?;poll(a)?;
  // Pending owns this credit throughout every fallible attach; both worklists
  // and real child AST drop under the SAME cleanup lock before credit release.
  pending.anchor=Some(crate::SharedSettingRetention::new(self.credit.take().unwrap()));
  for child in &pending.parts.as_ref().unwrap().expressions{crate::setting_prepare::attach(child,pending.anchor.as_ref().unwrap(),a).map_err(|proxy|a.take_operational_error().unwrap_or(proxy))?;}
  drop(pending.parser.take()); // Real parser scratch is gone; completed own custody remains.
  // Establish the fully paid final owner BEFORE removing Pending's custody.
  // Pending keeps an anchor alias until every child is installed; a failed
  // transfer can never retire credit ahead of its still-owned child payload.
  let retention=OnceLock::new();let _=retention.set(pending.anchor.as_ref().unwrap().clone());
  let owner=LiteralOwner::new(LiteralState{raw,origin,parts:OnceLock::new(),retention,original_prepared:true});
  if let Err(value)=owner.parts.set(Ok(pending.parts.take())){
   pending.parts=value.map_err(|_|io::ErrorKind::InvalidInput)?;
   return Err(io::ErrorKind::InvalidInput.into())
  }
  drop(pending.anchor.take());
  Ok(LiteralText(Backing::Text(owner)))
 }
}

#[cfg(test)]mod tests{
 use super::*;use std::sync::{atomic::{Ordering}};
 #[test]fn actual_typed_template_owner_keeps_same_children_and_fragment_values_without_relex(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let raw="\"head[x.y]tail\"";let mut builder=OriginalTemplateBuilder::new(&a).unwrap();
  let begin=crate::OriginalLiteralData::from_value_with_mode_using("\"head[".into(),crate::OriginalTokenValue::InterpBegin("[typed, not grammar]"),crate::OriginalStringMode::Normal,&a).unwrap();
  let end=crate::OriginalLiteralData::from_value_with_mode_using("]tail\"".into(),crate::OriginalTokenValue::InterpEnd("tail"),crate::OriginalStringMode::Normal,&a).unwrap();
  builder.push(begin,Span::new(0,6),None,&[],&a).unwrap();let mut child=crate::parse_expression("x.y").expr.unwrap();shift_expression(&mut child,6);let mut tokens=crate::lex("x.y").tokens;for token in &mut tokens{token.span.start+=6;token.span.end+=6;}
  let before=literal_child_parses_for_test();builder.push(end,Span::new(9,15),Some(child),&tokens,&a).unwrap();let value=builder.finish(raw,0,&a).unwrap();assert!(value.native_parser_facts().is_none(),"generic caller-built child cannot mint a native parser receipt");assert_eq!(literal_child_parses_for_test(),before);
  assert!(value.parts().unwrap().is_some());let parts=value.syntax_parts().unwrap().unwrap();assert_eq!(parts.expressions.len(),1);assert!(matches!(parts.expressions[0].kind,ExprKind::Member{..}));let address=&parts.expressions[0]as*const Expr;
  let alias=value.clone();let mut texts=Vec::new();for part in alias.pinned_fragments().unwrap().unwrap(){let mut text=String::new();part.unwrap().write_text(&mut text).unwrap();texts.push(text)}assert_eq!(texts,["[typed, not grammar]","tail"]);assert_eq!(alias.syntax_parts().unwrap().unwrap().expressions.as_ptr(),address);drop(value);assert!(used.load(Ordering::Acquire)>crate::SettingChargeCounter::root_allocation_bytes());assert_eq!(alias.syntax_parts().unwrap().unwrap().expressions.as_ptr(),address);drop(alias);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());assert_eq!(literal_child_parses_for_test(),before);
 }
 #[test]
 fn already_parsed_template_finishes_under_actual_storage_headroom(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let build=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));
  let body="\r".to_owned()+&"[".repeat(512);
  let begin=format!("\"{body}[");
  let end="]\"";
  let raw=format!("{begin}{end}");
  let mut builder=OriginalTemplateBuilder::new(&build).unwrap();
  for (text,value,span) in [
    (begin.as_str(),crate::OriginalTokenValue::InterpBegin(body.as_str()),Span::new(0,begin.len())),
    (end,crate::OriginalTokenValue::InterpEnd(""),Span::new(begin.len(),raw.len())),
  ]{
    let data=crate::OriginalLiteralData::from_value_with_mode_using(text.into(),value,crate::OriginalStringMode::Normal,&build).unwrap();
    builder.push(data,span,None,&[],&build).unwrap();
  }
  let before=used.load(Ordering::Acquire);
  let remaining=64<<10;
  assert!(crate::setting_prepare::literal_parser_peak(&raw,&build).unwrap()>remaining);
  let finish=crate::SettingAdmission::new(&used,before+remaining,&||Ok(()));
  let literal=builder.finish(&raw,0,&finish).unwrap();
  let parts=literal.syntax_parts().unwrap().unwrap();
  assert_eq!(&parts.template[..512],&[b'[';512]);
  assert_eq!(&parts.template[512..],&[0xff,1]);
  assert!(used.load(Ordering::Acquire)<before+16*1024);
  let alias=literal.clone();
  let retained=used.load(Ordering::Acquire);
  drop(literal);
  assert_eq!(used.load(Ordering::Acquire),retained);
  drop(alias);
  assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn template_part_never_masquerades_as_complete_static_or_empty_default(){let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let part=crate::OriginalLiteralData::from_value_using("\"x[".into(),crate::OriginalTokenValue::InterpBegin("x"),&a).unwrap();assert_eq!(LiteralText::from_original_data(&part,0,&a).unwrap_err().kind(),io::ErrorKind::Unsupported);let mut b=OriginalTemplateBuilder::new(&a).unwrap();b.push(part,Span::new(0,3),None,&[],&a).unwrap();assert_eq!(b.finish("\"x[",0,&a).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn eager_template_failure_preserves_first_io_and_releases_actual_payload_before_credit(){let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let good=||Ok(());let a=crate::SettingAdmission::new(&used,8<<20,&good);let mut b=OriginalTemplateBuilder::new(&a).unwrap();for(raw,value,span)in[("\"[",crate::OriginalTokenValue::InterpBegin(""),Span::new(0,2)),("]\"",crate::OriginalTokenValue::InterpEnd(""),Span::new(2,4))]{b.push(crate::OriginalLiteralData::from_value_using(raw.into(),value,&a).unwrap(),span,None,&[],&a).unwrap()}
  let stopped=||Err(io::Error::from_raw_os_error(1450));let fail=crate::SettingAdmission::new(&used,8<<20,&stopped);assert_eq!(b.finish("\"[]\"",0,&fail).unwrap_err().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let tiny=crate::SettingAdmission::new(&used,crate::SettingChargeCounter::root_allocation_bytes(),&good);assert_eq!(OriginalTemplateBuilder::new(&tiny).err().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}

/// Decode only actual typed segment VALUE bytes. Child slots are known from
/// Begin/Part/End products, never searched for in the text or reparsed.
fn decode_actual_template_runtime(parts:&mut LiteralParts,a:&crate::SettingAdmission<'_>,credit:&mut crate::SettingRootLease)->io::Result<()>{
 let (text_bytes,normalization)=parts.fragments.iter().try_fold((0usize,0usize),|(n,max_cr),row|{
    poll(a)?;
    let data=row.original.as_ref().ok_or(io::ErrorKind::InvalidInput)?;
    let value=match data.value(){crate::OriginalTokenValue::InterpBegin(s)|crate::OriginalTokenValue::InterpPart(s)|crate::OriginalTokenValue::InterpEnd(s)=>s,_=>return Err(io::ErrorKind::InvalidInput.into())};
    let n=n.checked_add(value.len()).ok_or(io::ErrorKind::OutOfMemory)?;
    Ok::<_,io::Error>((n,if value.contains('\r'){max_cr.max(value.len())}else{max_cr}))
 })?;
 // Preserve the existing output envelope. Every input byte emits at most
 // one literal byte or a fixed escape expansion (at most five bytes), and
 // each fragment adds at most one two-byte interpolation marker.
 let cap=text_bytes.checked_mul(16).and_then(|n|n.checked_add(parts.fragments.len().checked_mul(2)?)).ok_or(io::ErrorKind::OutOfMemory)?;
 let template_bound=envelope::<u8>(cap)?;
 let scratch_bound=envelope::<u8>(normalization)?;
 // One decoder error is kept; its only variable text is an escape name
 // drawn from this input, plus a fixed message. Allow formatter growth.
 let error_bound=envelope::<u8>(text_bytes.checked_add(128).ok_or(io::ErrorKind::OutOfMemory)?)?;
 let bound=template_bound.checked_add(scratch_bound).and_then(|n|n.checked_add(error_bound)).ok_or(io::ErrorKind::OutOfMemory)?;
 a.grow(credit,bound).map_err(|error|a.take_operational_error().unwrap_or(error))?;
 let mut template=Vec::new();
 template.try_reserve_exact(cap).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
 if template.capacity()>template_bound{return Err(io::ErrorKind::OutOfMemory.into())}
 let mut runtime_error=None;let mut next_marker=None;let mut substituted=false;
 for(i,row)in parts.fragments.iter().enumerate(){
  poll(a)?;
  if i>0{substituted=true;let marker=next_marker.take().unwrap_or_else(||if row.expression.is_none(){1}else if interpolation_starts_sentence(&template){2}else{1});template.extend([0xff,marker]);}
  let data=row.original.as_ref().ok_or(io::ErrorKind::InvalidInput)?;let value=match data.value(){crate::OriginalTokenValue::InterpBegin(s)|crate::OriginalTokenValue::InterpPart(s)|crate::OriginalTokenValue::InterpEnd(s)=>s,_=>return Err(io::ErrorKind::InvalidInput.into())};
  if data.string_mode()!=crate::OriginalStringMode::Normal{runtime_error.get_or_insert_with(||"Original interpolation runtime lexical mode is not issued".into());continue}
  let mut normalized=String::new();
  let value=if value.contains('\r'){
    normalized.try_reserve_exact(value.len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
    if normalized.capacity()>scratch_bound{return Err(io::ErrorKind::OutOfMemory.into())}
    for chunk in value.split('\r'){normalized.push_str(chunk);}
    normalized.as_str()
  }else{value};
  let mut at=0;
  while at<value.len(){poll(a)?;let ch=value[at..].chars().next().unwrap();if ch=='\\'{if let Err(error)=decode_text_escape(value,&mut at,&mut template,&mut runtime_error,&mut next_marker,substituted){runtime_error.get_or_insert(error);break}}else{let mut bytes=[0;4];if runtime_error.is_none(){template.extend_from_slice(ch.encode_utf8(&mut bytes).as_bytes());}at+=ch.len_utf8();}}
 }
 let error_capacity=runtime_error.as_ref().map_or(0,String::capacity);
 if error_capacity>error_bound{return Err(io::ErrorKind::OutOfMemory.into())}
 let actual=template.capacity().checked_add(error_capacity).ok_or(io::ErrorKind::OutOfMemory)?;
 refund(a,credit,bound.checked_sub(actual).ok_or(io::ErrorKind::OutOfMemory)?)?;
 poll(a)?;parts.template=template;parts.runtime_error=runtime_error;Ok(())
}

#[cfg(test)]mod runtime_state_controls{
 use super::*;use std::sync::{atomic::{Ordering}};
 fn typed(raw:&str,begin:&str,end:&str,empty:bool,a:&crate::SettingAdmission<'_>)->LiteralText{
  let marker=if empty{"[]"}else{"[x]"};let at=raw.find(marker).unwrap();let child_end=at+marker.len()-1;let mut builder=OriginalTemplateBuilder::new(a).unwrap();let first=crate::OriginalLiteralData::from_value_with_mode_using(raw[..at+1].into(),crate::OriginalTokenValue::InterpBegin(begin),crate::OriginalStringMode::Normal,a).unwrap();builder.push(first,Span::new(0,at+1),None,&[],a).unwrap();let last=crate::OriginalLiteralData::from_value_with_mode_using(raw[child_end..].into(),crate::OriginalTokenValue::InterpEnd(end),crate::OriginalStringMode::Normal,a).unwrap();let child=(!empty).then(||{let mut e=crate::parse_expression("x").expr.unwrap();shift_expression(&mut e,at+1);e});let tokens=if empty{Vec::new()}else{vec![crate::Token{kind:crate::TokenKind::Ident,span:Span::new(at+1,at+2),text:"x".into()}]};builder.push(last,Span::new(child_end,raw.len()),child,&tokens,a).unwrap();builder.finish(raw,0,a).unwrap()
 }
 #[test]fn original_typed_parts_and_ordinary_native_decoder_share_entire_macro_state_without_child_reparse(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,16<<20,&||Ok(()));
  for(raw,begin,end,empty)in[(r#""hello [x].""#,"hello ",".",false),(r#""\the [x] \he""#,r"\the ",r" \he",false),(r#""\ref[x]\th""#,r"\ref",r"\th",false),(r#""\proper[x]""#,r"\proper","",false),(r#""\bold [x]\his""#,r"\bold ",r"\his",false),(r#""\ref[]end""#,r"\ref","end",true),(r#""\bad[x]tail""#,r"\bad","tail",false)]{
   let ordinary=LiteralText::at(raw.into(),0);let old=ordinary.syntax_parts().unwrap().unwrap();let before=literal_child_parses_for_test();let value=typed(raw,begin,end,empty,&a);let native=value.syntax_parts().unwrap().unwrap();assert_eq!(native.template,old.template,"{raw}");assert_eq!(native.runtime_error,old.runtime_error,"{raw}");assert_eq!(native.expressions.len(),old.expressions.len(),"{raw}");assert_eq!(literal_child_parses_for_test(),before);drop(value);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  }
 }
 #[test]fn unpublished_original_geometry_keeps_actual_child_and_raw_allocations_and_credit(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,16<<20,&||Ok(()));let raw=r#""before[x]after""#;
  let value=typed(raw,"before","after",false,&a);let raw_address=value.raw_storage().as_ptr();let child_address=value.syntax_parts().unwrap().unwrap().expressions.as_ptr();let child_span=value.syntax_parts().unwrap().unwrap().expressions[0].span;let credit=used.load(Ordering::Acquire);let parses=literal_child_parses_for_test();
  let mut root=Expr{kind:ExprKind::Literal(value),span:Span::new(0,raw.len())};shift_unpublished_expression_using(&mut root,31,&a).unwrap();assert_eq!(root.span,Span::new(31,raw.len()+31));let ExprKind::Literal(value)=&root.kind else{panic!("literal")};assert_eq!(value.raw_storage().as_ptr(),raw_address);let parts=value.syntax_parts().unwrap().unwrap();assert_eq!(parts.expressions.as_ptr(),child_address);assert_eq!(parts.expressions[0].span,Span::new(child_span.start+31,child_span.end+31));assert_eq!(used.load(Ordering::Acquire),credit);assert_eq!(literal_child_parses_for_test(),parses);drop(root);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn shared_foreign_quota_and_first_io_refuse_before_original_geometry_changes(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,16<<20,&||Ok(()));let raw=r#""before[x]after""#;let value=typed(raw,"before","after",false,&a);let alias=value.clone();let credit=used.load(Ordering::Acquire);let mut root=Expr{kind:ExprKind::Literal(value),span:Span::new(0,raw.len())};
  assert_eq!(shift_unpublished_expression_using(&mut root,31,&a).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(root.span,Span::new(0,raw.len()));assert_eq!(used.load(Ordering::Acquire),credit);drop(alias);
  let other=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let foreign=crate::SettingAdmission::new(&other,16<<20,&||Ok(()));assert_eq!(shift_unpublished_expression_using(&mut root,31,&foreign).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(other.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let low=crate::SettingAdmission::new(&used,credit-1,&||Ok(()));assert_eq!(shift_unpublished_expression_using(&mut root,31,&low).unwrap_err().kind(),io::ErrorKind::OutOfMemory);let stopped=||Err(io::Error::from_raw_os_error(1450));let failed=crate::SettingAdmission::new(&used,16<<20,&stopped);assert_eq!(shift_unpublished_expression_using(&mut root,31,&failed).unwrap_err().raw_os_error(),Some(1450));assert_eq!(root.span,Span::new(0,raw.len()));assert_eq!(used.load(Ordering::Acquire),credit);drop(root);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]fn neutral_static_geometry_can_borrow_independent_value_credit_without_mutating_payload(){
  let source=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let target=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let from=crate::SettingAdmission::new(&source,16<<20,&||Ok(()));let to=crate::SettingAdmission::new(&target,16<<20,&||Ok(()));let raw=r#""value""#;let data=crate::OriginalLiteralData::from_value_using(raw.into(),crate::OriginalTokenValue::String("value"),&from).unwrap();let credit=source.load(Ordering::Acquire);let value=LiteralText::from_original_data(&data,0,&to).unwrap();let mut root=Expr{kind:ExprKind::Literal(value),span:Span::new(0,raw.len())};shift_unpublished_expression_using(&mut root,31,&to).unwrap();let ExprKind::Literal(value)=&root.kind else{panic!("literal")};assert!(value.original_data().unwrap().same_owner(&data));assert_eq!(value.original_origin(),Some(31));assert!(matches!(data.value(),crate::OriginalTokenValue::String("value")));assert_eq!(source.load(Ordering::Acquire),credit);assert_eq!(target.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());drop(root);assert_eq!(source.load(Ordering::Acquire),credit);drop(data);assert_eq!(source.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }

}

#[cfg(test)]mod native_template_child_controls{
 use super::*;use std::sync::atomic::Ordering;
 #[test]fn typed_template_retains_same_actual_parser_child_facts_without_reparse(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let raw="\"head[x.y]tail\"";let mut builder=OriginalTemplateBuilder::new(&a).unwrap();
  let begin=crate::OriginalLiteralData::from_value_with_mode_using("\"head[".into(),crate::OriginalTokenValue::InterpBegin("head"),crate::OriginalStringMode::Normal,&a).unwrap();let end=crate::OriginalLiteralData::from_value_with_mode_using("]tail\"".into(),crate::OriginalTokenValue::InterpEnd("tail"),crate::OriginalStringMode::Normal,&a).unwrap();
  let mut tokens=crate::lex("x.y").tokens;for token in &mut tokens{token.span.start+=6;token.span.end+=6;}let spans=tokens.iter().map(|t|crate::SpanToken{kind:t.kind,span:t.span}).collect::<Vec<_>>();
  let(mut parsed,native)=crate::expression_parser::parse_expression_span_tokens_with_original_literals_and_native_facts(raw,&spans,0,&a,None);assert!(parsed.diagnostics.is_empty());let child=parsed.expr.take().unwrap();assert_eq!(native.unwrap().complete_span(),Some(child.span));let address=child.span;
  builder.push_with_native_facts(begin,Span::new(0,6),None,&[],None,false,&a).unwrap();builder.push_with_native_facts(end,Span::new(9,15),Some(child),&tokens,native,false,&a).unwrap();let before=literal_child_parses_for_test();let literal=builder.finish(raw,0,&a).unwrap();assert!(literal.native_parser_facts().unwrap().is_complete());assert_eq!(literal.syntax_parts().unwrap().unwrap().expressions[0].span,address);let alias=literal.clone();assert_eq!(literal_child_parses_for_test(),before);drop(literal);assert!(used.load(Ordering::Acquire)>crate::SettingChargeCounter::root_allocation_bytes());drop(alias);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}

#[cfg(test)]
#[path="original_template_child_custody_controls.rs"]mod complete_child_custody_controls;

#[cfg(test)]mod growth_callsite_controls{
 use super::*;use std::sync::atomic::Ordering;
 #[test]
 fn actual_original_template_growth_preserves_request_callsite_credit_and_first_io(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let fixed=crate::SettingChargeCounter::root_allocation_bytes();let good=||Ok(());let a=crate::SettingAdmission::new(&used,1<<20,&good);let mut builder=OriginalTemplateBuilder::new(&a).unwrap();let before=used.load(Ordering::Acquire);let owned=builder.credit.as_ref().unwrap().bytes();
  let tight=crate::SettingAdmission::new(&used,before,&good);
  let expected_line=line!()+1;
  let error=builder.grow(1,&tight).unwrap_err();
  assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);let message=error.to_string();assert!(message.contains(&format!("{}:{}:",file!(),expected_line)),"actual request callsite must pass through both track_caller wrappers: {message}");assert!(message.contains("1 requested"));assert!(message.contains(&format!("{before} retained, {before} limit")));assert_eq!(used.load(Ordering::Acquire),before);assert_eq!(builder.credit.as_ref().unwrap().bytes(),owned);
  let fail=||Err(io::Error::from_raw_os_error(1450));let stopped=crate::SettingAdmission::new(&used,1<<20,&fail);let actual=builder.grow(1,&stopped).unwrap_err();assert_eq!(actual.raw_os_error(),Some(1450),"callsite attribution must not replace the actual first operational cause");assert_eq!(used.load(Ordering::Acquire),before);assert_eq!(builder.credit.as_ref().unwrap().bytes(),owned);
  builder.grow(1,&a).unwrap();assert_eq!(used.load(Ordering::Acquire),before+1);drop(builder);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
}

#[cfg(test)]mod empty_template_row_pressure_controls{
 use super::*;use std::sync::atomic::Ordering;
 #[test]fn actual_many_empty_template_parts_fit_bounded_peak_and_keep_same_runtime_owner(){
  let count=256usize;let raw=format!("\"{}\"","[]".repeat(count));
  let oracle=LiteralText::at(raw.clone(),0);let expected=oracle.syntax_parts().unwrap().unwrap();
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&used,256<<10,&||Ok(()));
  let before=literal_child_parses_for_test();let mut builder=OriginalTemplateBuilder::new(&a).unwrap();
  for index in 0..=count{
   let start=if index==0{0}else{index*2};let end=start+2;
   let value=if index==0{crate::OriginalTokenValue::InterpBegin("")}else if index==count{crate::OriginalTokenValue::InterpEnd("")}else{crate::OriginalTokenValue::InterpPart("")};
   let data=crate::OriginalLiteralData::from_value_with_mode_using(raw[start..end].into(),value,crate::OriginalStringMode::Normal,&a).unwrap();
   builder.push_with_native_facts(data,Span::new(start,end),None,&[],None,true,&a).unwrap();
  }
  let value=builder.finish(&raw,0,&a).unwrap();let parts=value.syntax_parts().unwrap().unwrap();
  assert_eq!(parts.fragments.len(),count+1);assert!(parts.expressions.is_empty());assert_eq!(parts.template,expected.template);assert_eq!(parts.runtime_error,expected.runtime_error);assert_eq!(literal_child_parses_for_test(),before,"empty parts never invoke a child parser");
  let retained=used.load(Ordering::Acquire);assert!(retained>crate::SettingChargeCounter::root_allocation_bytes());let alias=value.clone();drop(value);assert_eq!(used.load(Ordering::Acquire),retained,"escaping actual template alias keeps the SAME funded payload");drop(alias);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}


#[cfg(test)]mod parser_cleanup_adapter_controls{
 use super::*;use std::cell::Cell;use std::sync::atomic::Ordering;
 fn deep_child(a:&crate::SettingAdmission<'_>,cleanup:&crate::parser_cleanup::ParserCleanup<'_, '_>,nodes:usize)->(Expr,crate::SettingRootLease){
  cleanup.ensure_nodes(Some(a),nodes).unwrap();
  let credit=a.reserve(nodes.checked_mul(size_of::<Expr>()).unwrap()+1).unwrap();
  let mut child=Expr{span:Span::new(2,3),kind:ExprKind::Ident("x".into())};
  for _ in 1..nodes{child=Expr{span:Span::new(2,3),kind:ExprKind::Group(Box::new(child))};}
  (child,credit)
 }
 #[test]fn template_incoming_deep_child_has_cleanup_before_first_error_or_panic(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();
  for panic_mode in [false,true]{
   let counter=crate::SettingChargeCounter::try_new(fixed).unwrap();let stop=Cell::new(false);let polls=Cell::new(0);
   let poll=||{polls.set(polls.get()+1);if stop.get(){if panic_mode{panic!("actual first template checkpoint panic")};return Err(io::Error::from_raw_os_error(1450))}Ok(())};
   let a=crate::SettingAdmission::new(&counter,32<<20,&poll);let cleanup=crate::parser_cleanup::ParserCleanup::new(Some(&a)).unwrap();
   let mut builder=OriginalTemplateBuilder::new_with_cleanup(&a,cleanup.clone()).unwrap();
   let (child,payload)=deep_child(&a,&cleanup,20_001);
   let data=crate::OriginalLiteralData::from_value_using("]\"".into(),crate::OriginalTokenValue::InterpEnd(""),&a).unwrap();
   let before=polls.get();stop.set(true);
   let result=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||builder.push(data,Span::new(3,5),Some(child),&[],&a)));
   assert_eq!(polls.get(),before+1,"incoming cleanup never polls after first failure");
   if panic_mode{assert!(result.is_err());assert!(!a.is_stopped());}else{assert_eq!(result.unwrap().unwrap_err().raw_os_error(),Some(1450));}
   stop.set(false);drop(builder);drop(cleanup);drop(payload);assert_eq!(counter.load(Ordering::Acquire),fixed);
  }
 }
 #[test]fn template_pending_parts_and_builder_drop_deep_children_without_polling(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let counter=crate::SettingChargeCounter::try_new(fixed).unwrap();
  let stop=Cell::new(false);let polls=Cell::new(0);let poll=||{polls.set(polls.get()+1);if stop.get(){Err(io::Error::from_raw_os_error(1450))}else{Ok(())}};
  let a=crate::SettingAdmission::new(&counter,32<<20,&poll);let cleanup=crate::parser_cleanup::ParserCleanup::new(Some(&a)).unwrap();
  let mut builder=OriginalTemplateBuilder::new_with_cleanup(&a,cleanup.clone()).unwrap();let(child,payload)=deep_child(&a,&cleanup,20_001);
  let data=crate::OriginalLiteralData::from_value_using("]\"".into(),crate::OriginalTokenValue::InterpEnd(""),&a).unwrap();
  builder.push(data,Span::new(3,5),Some(child),&[],&a).unwrap();let before=polls.get();stop.set(true);drop(builder);assert_eq!(polls.get(),before);stop.set(false);drop(payload);
  let(child,payload)=deep_child(&a,&cleanup,20_001);let anchor=crate::SharedSettingRetention::new(a.reserve(512).unwrap());
  let pending=PendingParts{parts:Some(LiteralParts{native_parser_facts:crate::expression_parser::NativeExpressionParserState::aggregate(None),runtime_error:None,fragments:Vec::new(),template:Vec::new(),expressions:vec![child],lexical:Ok(LiteralLexicalShape{interpolated:true,pinned_segment_nonempty:false})}),anchor:Some(anchor),parser:Some(a.reserve(128).unwrap()),cleanup:Some(cleanup.clone())};
  let before=polls.get();stop.set(true);drop(pending);assert_eq!(polls.get(),before,"pending teardown never enters canceled operation");assert!(!a.is_stopped());
  stop.set(false);drop(payload);drop(cleanup);assert_eq!(counter.load(Ordering::Acquire),fixed);
 }
 #[test]fn template_finish_bad_token_geometry_keeps_all_deep_rows_guarded(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let counter=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&counter,32<<20,&||Ok(()));
  let cleanup=crate::parser_cleanup::ParserCleanup::new(Some(&a)).unwrap();let mut builder=OriginalTemplateBuilder::new_with_cleanup(&a,cleanup.clone()).unwrap();
  let(first,first_credit)=deep_child(&a,&cleanup,20_001);let(second,second_credit)=deep_child(&a,&cleanup,20_001);
  let begin=crate::OriginalLiteralData::from_value_using("\"[".into(),crate::OriginalTokenValue::InterpBegin(""),&a).unwrap();
  let middle=crate::OriginalLiteralData::from_value_using("][".into(),crate::OriginalTokenValue::InterpPart(""),&a).unwrap();
  let end=crate::OriginalLiteralData::from_value_using("]\"".into(),crate::OriginalTokenValue::InterpEnd(""),&a).unwrap();
  builder.push(begin,Span::new(10,12),None,&[],&a).unwrap();
  let foreign=[crate::Token{kind:crate::TokenKind::Ident,span:Span::new(0,1),text:"x".into()}];
  builder.push(middle,Span::new(13,15),Some(first),&foreign,&a).unwrap();
  builder.push(end,Span::new(16,18),Some(second),&[],&a).unwrap();
  assert_eq!(builder.finish("\"[x][y]\"",10,&a).unwrap_err().kind(),io::ErrorKind::InvalidInput);
  assert!(!a.is_stopped(),"bad geometry is nominal, not a waived operational error");
  drop(first_credit);drop(second_credit);drop(cleanup);assert_eq!(counter.load(Ordering::Acquire),fixed);
 }
 #[test]fn template_cleanup_custody_reaches_paid_literal_owner_and_last_alias(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let counter=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&counter,16<<20,&||Ok(()));
  let cleanup=crate::parser_cleanup::ParserCleanup::new(Some(&a)).unwrap();cleanup.ensure_nodes(Some(&a),2).unwrap();
  let raw="\"[(x)]\"";let mut child=crate::parse_expression("(x)").expr.unwrap();shift_expression(&mut child,2);
  let mut tokens=crate::lex("(x)").tokens;for token in &mut tokens{token.span.start+=2;token.span.end+=2;}
  let mut builder=OriginalTemplateBuilder::new_with_cleanup(&a,cleanup.clone()).unwrap();
  let begin=crate::OriginalLiteralData::from_value_using("\"[".into(),crate::OriginalTokenValue::InterpBegin(""),&a).unwrap();
  let end=crate::OriginalLiteralData::from_value_using("]\"".into(),crate::OriginalTokenValue::InterpEnd(""),&a).unwrap();
  builder.push(begin,Span::new(0,2),None,&[],&a).unwrap();builder.push(end,Span::new(5,7),Some(child),&tokens,&a).unwrap();
  let value=builder.finish(raw,0,&a).unwrap();assert!(matches!(&value.syntax_parts().unwrap().unwrap().expressions[0].kind,ExprKind::Group(_)));
  let alias=value.clone();drop(value);drop(cleanup);assert!(counter.load(Ordering::Acquire)>fixed);drop(alias);assert_eq!(counter.load(Ordering::Acquire),fixed);
 }
}
