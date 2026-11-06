//! Actual primary/formal token-demand adapter, not a parser or token cache.
//! Every source loan ends before the next pull. The existing accumulator and
//! Pratt/default producer own syntax/metadata; this only preserves cadence.
use super::OriginalSignatureObserver;
use super::super::DemandedFormalDefault;
use dm_preprocess::regions::{OriginalPrimaryStreamConsumer,OriginalFormalTokenStream};
use dm_syntax::{OriginalPrimaryLiveHeader,OriginalHeaderFlow,ParameterClauseCursor,Span,SpanToken,TokenKind};
use std::io;
fn unsupported(message:&'static str)->io::Error{io::Error::new(io::ErrorKind::Unsupported,message)}
fn invalid(message:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidData,message)}
fn formal_boundary(kind:TokenKind,text:&str)->bool{kind==TokenKind::Punctuation&&matches!(text,","|")")}
impl OriginalSignatureObserver<'_,'_>{
 /// The SAME actual consumed boundary is copied as scalar geometry only. The
 /// default retains its one original Token/value allocation; no String clone.
 fn complete_from_stream(&mut self,source:&mut dyn OriginalFormalTokenStream,start:usize,following:SpanToken,default:Option<DemandedFormalDefault>,clauses:dm_syntax::ParameterClauseSpans)->io::Result<OriginalHeaderFlow>{
  let span=Span::new(start,following.span.start);let mut pending=Some(default);let mut completed=None;
  source.with_current_source(&mut |text,tokens|{
   if completed.is_some(){return Err(invalid("formal source-loan callback repeated"))}
   let default=pending.take().ok_or_else(||invalid("formal source loan repeated after its first failure"))?;
   let first=tokens.partition_point(|token|token.span.end<=span.start);
   let last=tokens.partition_point(|token|token.span.start<span.end);
   let window=tokens.range(first,last).ok_or_else(||invalid("actual formal source loan reverses primary token range"))?;
   for token in window.iter(){super::checkpoint(self.a)?;if token.span.start<span.start||token.span.end>span.end{return Err(invalid("actual formal source loan cuts a primary token"))}}
   completed=Some(window.with_dense_using(self.a,|tokens|self.complete_formal_produced(text,tokens,span,following,default,clauses)).inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=complete_formal {error:?}");}})?);Ok(())
  })?;
  completed.ok_or_else(||invalid("formal source-loan callback omitted"))
 }
}
impl OriginalSignatureObserver<'_,'_>{
 /// Validate/intern the actual head once before asking the RHS producer for
 /// any future raw token. The retained native head is consumed by completion.
 fn admit_head_from_stream(&mut self,source:&mut dyn OriginalFormalTokenStream,start:usize,assignment:SpanToken)->io::Result<OriginalHeaderFlow>{
  let span=Span::new(start,assignment.span.start);let mut completed=None;
  source.with_current_source(&mut |text,tokens|{
   if completed.is_some(){return Err(invalid("formal-head source-loan callback repeated"))}
   let first=tokens.partition_point(|token|token.span.end<=span.start);
   let last=tokens.partition_point(|token|token.span.start<span.end);
   let window=tokens.range(first,last).ok_or_else(||invalid("actual formal-head source loan reverses primary token range"))?;
   for token in window.iter(){super::checkpoint(self.a)?;if token.span.start<span.start||token.span.end>span.end{return Err(invalid("actual formal-head source loan cuts a primary token"))}}
   completed=Some(window.with_dense_using(self.a,|tokens|self.admit_formal_head(text,tokens,span,assignment))?);Ok(())
  })?;
  completed.ok_or_else(||invalid("formal-head source-loan callback omitted"))
 }
}
impl OriginalPrimaryStreamConsumer for OriginalSignatureObserver<'_,'_>{
 fn callable(&mut self,live:OriginalPrimaryLiveHeader,source:&mut dyn OriginalFormalTokenStream)->io::Result<OriginalHeaderFlow>{
  if self.stream_failed{return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual formal stream already failed"))}
  let result=self.consume_callable(live,source).inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=formal_consume {error:?}");}});if result.is_err(){self.stream_failed=true}result
 }
}
impl OriginalSignatureObserver<'_,'_>{
 fn reject_first_head_from_stream(&mut self,source:&mut dyn OriginalFormalTokenStream,start:usize,token:SpanToken)->io::Result<OriginalHeaderFlow>{
  let data=if token.kind==TokenKind::Number{source.current_header_literal(token)?}else{None};let mut outcome=None;
  source.with_current_source(&mut |text,tokens|{
   if outcome.is_some(){return Err(invalid("first formal token loan repeated"))}
   let first=tokens.partition_point(|part|part.span.end<=start);let last=tokens.partition_point(|part|part.span.start<token.span.end);
   let window=tokens.range(first,last).ok_or_else(||invalid("first formal token loan reverses actual occurrence range"))?;
   outcome=Some(window.with_dense_using(self.a,|tokens|self.reject_first_formal_head(text,tokens,token,data))?);Ok(())
  })?;outcome.ok_or_else(||invalid("first formal token loan omitted"))
 }
 fn consume_callable(&mut self,live:OriginalPrimaryLiveHeader,source:&mut dyn OriginalFormalTokenStream)->io::Result<OriginalHeaderFlow>{
  if self.failure.is_some()||self.unsupported.is_some(){return Err(io::ErrorKind::InvalidInput.into())}
  let mut start=live.argument_start();self.begin_formals(live)?;let mut clauses=ParameterClauseCursor::new(start);let mut head_seen=false;let mut dimension=0usize;let mut pending=None;let mut after_input=false;let mut trailing_semicolon=None;
  loop{
   super::checkpoint(self.a)?;let token=match pending.take(){
    Some(actual)=>actual,
    None=>match source.next_header_token()?{
     Some(actual)=>actual,
     None=>return match trailing_semicolon{
      Some(actual)=>self.reject_end_after_semicolon(source,actual),
      None=>Err(unsupported("Original formal EOF recovery is not issued")),
     },
    },
   };
   if clauses.is_top_level()&&formal_boundary(token.kind,&token.text){
    let following=SpanToken{kind:token.kind,span:token.span};let closed=token.text==")";let next=token.span.end;drop(token);
    let flow=self.complete_from_stream(source,start,following,None,clauses.finish(following.span.start))?;if flow==OriginalHeaderFlow::Stop||closed{return Ok(flow)}start=next;clauses=ParameterClauseCursor::new(start);head_seen=false;dimension=0;after_input=false;trailing_semicolon=None;continue
   }
   if clauses.is_top_level()&&token.kind==TokenKind::Punctuation&&token.text==";"{if trailing_semicolon.is_some(){return Err(unsupported("actual Original repeated semicolon failure is not issued"))}let marker=SpanToken{kind:token.kind,span:token.span};if self.admit_head_from_stream(source,start,marker)?==OriginalHeaderFlow::Stop{return Ok(OriginalHeaderFlow::Stop)}self.observed_trailing_semicolon(marker.span)?;clauses.push(token.kind,token.span,&token.text);drop(token);trailing_semicolon=Some(marker);continue}
   if trailing_semicolon.is_some()&&!matches!(token.kind,TokenKind::Whitespace|TokenKind::Newline|TokenKind::Comment){return Err(unsupported("actual Original following-semicolon failure provenance is not issued"))}
   if after_input&&!matches!(token.kind,TokenKind::Whitespace|TokenKind::Newline|TokenKind::Comment)&&!(clauses.is_top_level()&&((token.text=="in"&&clauses.spans().source.is_none())||(token.text=="as"&&clauses.spans().source.is_some()&&clauses.spans().post_source_annotation.is_none()))){return Err(unsupported("actual Original input continuation requires its genuine following-delimiter failure producer"))}
   if !head_seen&&!matches!(token.kind,TokenKind::Whitespace|TokenKind::Newline|TokenKind::Comment){
    if token.kind==TokenKind::Number||(matches!(token.kind,TokenKind::Punctuation|TokenKind::Operator)&&token.text=="="){let actual=SpanToken{kind:token.kind,span:token.span};drop(token);return self.reject_first_head_from_stream(source,start,actual)}head_seen=true;
   }
   if clauses.is_top_level()&&token.kind==TokenKind::Punctuation&&token.text=="["{
    let opening=SpanToken{kind:token.kind,span:token.span};if self.admit_head_from_stream(source,start,opening)?==OriginalHeaderFlow::Stop{return Ok(OriginalHeaderFlow::Stop)}clauses.push(token.kind,token.span,&token.text);drop(token);
    let outcome=self.formal_dimension_using(source,&mut clauses,opening.span,dimension)?;match &outcome{super::super::DemandedFormalDimension::Complete{root,..}=>self.observe_stream_expression_notices(source,&root.syntax)?,super::super::DemandedFormalDimension::Failure(actual)=>self.observe_formal_outcome_notices(source,actual)?,super::super::DemandedFormalDimension::Empty{..}=>()}let boundary=match outcome{
     super::super::DemandedFormalDimension::Complete{root,boundary}=>{self.retain_formal_expression(root)?;boundary},super::super::DemandedFormalDimension::Empty{boundary}=>boundary,
     super::super::DemandedFormalDimension::Failure(actual)=>return self.reject_expression_input_failure_using(source,actual)?.ok_or_else(||unsupported("actual Original dimension Pratt failure provenance is not issued")),
    };
    clauses.push(boundary.kind,boundary.span,&boundary.text);drop(boundary);dimension=dimension.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;continue
   }
   if clauses.is_top_level()&&token.kind==TokenKind::Ident&&token.text=="as"{
    let marker=SpanToken{kind:token.kind,span:token.span};if self.admit_head_from_stream(source,start,marker)?==OriginalHeaderFlow::Stop{return Ok(OriginalHeaderFlow::Stop)}let after_in=clauses.spans().source.is_some();if after_in{self.observed_input_after_source(marker.span)?}clauses.push(token.kind,token.span,&token.text);drop(token);
    let mut input=dm_syntax::ParameterInputCursor::new(self.a,after_in)?;
    loop{super::checkpoint(self.a)?;let token=source.next_header_token()?.ok_or_else(||unsupported("Original input annotation EOF recovery is not issued"))?;
     match input.feed(token.kind,token.span,&token.text){
      Ok(dm_syntax::ParameterInputFlow::Boundary)=>{pending=Some(token);break},
      Ok(dm_syntax::ParameterInputFlow::ConsumedIdentifier)=>{self.observed_input_identifier(token.span,&token.text)?;clauses.push(token.kind,token.span,&token.text);},
      Ok(dm_syntax::ParameterInputFlow::Consumed)=>clauses.push(token.kind,token.span,&token.text),
      Err(dm_syntax::ParameterInputFailure::Operational(actual))=>return Err(actual),
      Err(dm_syntax::ParameterInputFailure::Syntax{receipt,..})=>{let actual=SpanToken{kind:token.kind,span:token.span};drop(token);drop(input);return self.reject_input_failure_using(source,receipt,actual)},
     }
    }
    let input=input.finish().map_err(|failure|match failure{dm_syntax::ParameterInputFailure::Operational(actual)=>actual,dm_syntax::ParameterInputFailure::Syntax{..}=>unsupported("actual Original unfinished input annotation fatal provenance is not issued")})?;self.retain_formal_input(marker.span,input)?;after_input=true;continue
   }
   let source_marker=clauses.is_top_level()&&matches!(token.kind,TokenKind::Ident|TokenKind::Punctuation)&&token.text=="in";
   let assignment=clauses.is_top_level()&&clauses.spans().assignment.is_none()&&matches!(token.kind,TokenKind::Punctuation|TokenKind::Operator)&&token.text=="=";
   let marker=SpanToken{kind:token.kind,span:token.span};
   if assignment||source_marker{if self.admit_head_from_stream(source,start,marker)?==OriginalHeaderFlow::Stop{return Ok(OriginalHeaderFlow::Stop)}}
   clauses.push(token.kind,token.span,&token.text);drop(token);if !assignment&&!source_marker{continue}
   let actual=if source_marker{self.formal_source_using(source,&mut clauses)?}else{self.formal_default_using(source,&mut clauses).inspect_err(|error|{#[cfg(debug_assertions)]if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some(){eprintln!("ORIGINAL_FATAL_STAGE=formal_default {error:?}");}})?};self.observe_formal_outcome_notices(source,&actual)?;if match &actual{DemandedFormalDefault::Complete{root,..}=>root.syntax.parsed().original_input_failure().is_some(),DemandedFormalDefault::ExpectedTerm(failure)=>failure.syntax.parsed().original_input_failure().is_some(),DemandedFormalDefault::NativeSyntax{syntax,..}=>syntax.parsed().original_input_failure().is_some()}{return self.reject_expression_input_failure_using(source,actual)?.ok_or_else(||invalid("actual input failure receipt disappeared"))}
   match actual{
    DemandedFormalDefault::Complete{root,boundary}=>{self.retain_formal_expression(root)?;pending=Some(boundary.ok_or_else(||unsupported("Original formal expression EOF recovery is not issued"))?);},
    DemandedFormalDefault::ExpectedTerm(failure)if assignment&&failure.expected.token_span().is_none()&&failure.syntax.tokens().is_empty()=>{
     if failure.boundary.as_ref().is_some_and(|token|token.text==";"){
      return self.reject_empty_semicolon_default(source,&failure)
     }
     let following=failure.boundary.as_ref().map(|token|SpanToken{kind:token.kind,span:token.span}).ok_or_else(||unsupported("Original empty default EOF recovery is not issued"))?;
     return self.complete_from_stream(source,start,following,Some(DemandedFormalDefault::ExpectedTerm(failure)),clauses.finish(following.span.start))
    },
    _=>return Err(unsupported("actual Original formal expression failure provenance is not issued")),
   }
  }
 }
}
