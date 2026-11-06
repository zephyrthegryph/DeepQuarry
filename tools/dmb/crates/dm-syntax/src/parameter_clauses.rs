//! One scalar clause partition shared by native metadata and original roots.
//! No lexer, AST, symbol table, token copy or source authority is created here.
use crate::parameter_syntax::ParameterToken;
use crate::{Span, SpanToken, TokenKind, TokenWindow};
use std::borrow::Borrow;
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ParameterClauseSpans {
    pub parameter: Span,
    pub assignment: Option<Span>,
    pub annotation: Option<Span>,
    pub source: Option<Span>,
    /// Actual second (ignored) as after the source expression; first as remains annotation.
    pub post_source_annotation: Option<Span>,
}
impl ParameterClauseSpans {
    pub fn declaration_end(self) -> usize {
        [self.assignment, self.annotation, self.source]
            .into_iter()
            .flatten()
            .map(|s| s.start)
            .min()
            .unwrap_or(self.parameter.end)
    }
    pub fn after_original(self,marker:Span)->Span{let mut after=self.after(marker);if let Some(post)=self.post_source_annotation{if post.start>marker.start&&post.start<after.end{after.end=post.start}}after}
    pub fn after(self, marker: Span) -> Span {
        let end = [self.assignment, self.annotation, self.source]
            .into_iter()
            .flatten()
            .map(|s| s.start)
            .filter(|p| *p > marker.start)
            .min()
            .unwrap_or(self.parameter.end);
        Span::new(marker.end, end)
    }
}
pub fn parameter_clause_spans(
    source: &str,
    tokens: &[SpanToken],
    span: Span,
) -> Result<ParameterClauseSpans, &'static str> {
    clause_spans(source, tokens, span)
}
pub fn parameter_clause_spans_in_window(
    source: &str,
    tokens: TokenWindow<'_>,
    span: Span,
) -> Result<ParameterClauseSpans, &'static str> {
    clause_spans_using::<SpanToken, _>(source, tokens.iter(), span)
}
pub(crate) fn clause_spans<T: ParameterToken>(
    source: &str,
    tokens: &[T],
    span: Span,
) -> Result<ParameterClauseSpans, &'static str> {
    clause_spans_using::<T, _>(source, tokens.iter(), span)
}
fn clause_spans_using<T: ParameterToken, B: Borrow<T>>(
    source: &str,
    tokens: impl IntoIterator<Item = B>,
    span: Span,
) -> Result<ParameterClauseSpans, &'static str> {
    source
        .get(span.range())
        .ok_or("parameter clause span outside original source")?;
    let mut cursor=ParameterClauseCursor::new(span.start);
    for token in tokens{
     let t = token.borrow();
     if t.span().start<span.start||t.span().end>span.end||source.get(t.span().range()).is_none(){return Err("parameter clause token escaped original range")}
     cursor.push(t.kind(),t.span(),t.text(source));
    }
    Ok(cursor.finish(span.end))
}

/// Actual native parameter-clause transition, shared by complete views and
/// token demand. It retains only scalar delimiter/marker DATA, never text/AST.
#[derive(Clone,Copy,Debug)]pub struct ParameterClauseCursor{out:ParameterClauseSpans,top:i128,assign:usize}
impl ParameterClauseCursor{
 pub fn new(start:usize)->Self{Self{out:ParameterClauseSpans{parameter:Span::new(start,start),assignment:None,annotation:None,source:None,post_source_annotation:None},top:0,assign:0}}
 pub fn is_top_level(&self)->bool{self.top==0}
 pub fn spans(&self)->ParameterClauseSpans{self.out}
 pub fn push(&mut self,kind:TokenKind,span:Span,text:&str){self.push_using(kind,span,text,true)}
 pub fn push_expression(&mut self,kind:TokenKind,span:Span,text:&str){self.push_using(kind,span,text,false)}
 fn push_using(&mut self,kind:TokenKind,span:Span,text:&str,markers:bool){
        match text {
            "(" | "[" | "{" => self.top += 1,
            ")" | "]" | "}" => self.top -= 1,
            "as" if markers && self.top == 0 => {if self.out.source.is_some()&&self.out.post_source_annotation.is_none(){self.out.post_source_annotation=Some(span)}if self.out.annotation.is_none(){self.out.annotation=Some(span)}},
            "in" if markers && self.top == 0 && self.out.source.is_none() => self.out.source = Some(span),
            _ => (),
        }
        if matches!(kind, TokenKind::Operator | TokenKind::Punctuation) {
            match text {
                "(" | "[" | "{" => self.assign += 1,
                ")" | "]" | "}" => self.assign = self.assign.saturating_sub(1),
                "=" if markers && self.assign == 0 && self.out.assignment.is_none() => self.out.assignment = Some(span),
                _ => (),
            }
        }
  self.out.parameter.end=span.end;
 }
 pub fn finish(mut self,end:usize)->ParameterClauseSpans{self.out.parameter.end=end;self.out}
}

/// A native parameter clause lends its real expression tokens to the SAME
/// Pratt machine. It stops only on a real top-level formal/annotation boundary;
/// the consumed boundary remains owned here for the native formal producer.
/// No temporary physical pause can be represented as end-of-expression.
#[derive(Clone,Copy)]enum FormalExpressionBoundary{Default,Source,Dimension}
pub struct ParameterExpressionDemand<'a>{level:i128,boundary_kind:FormalExpressionBoundary,original:bool,primitive_mode:crate::NativePrimitiveClauseMode,source:&'a mut dyn crate::NativeExpressionTokenDemand,clauses:&'a mut ParameterClauseCursor,boundary:Option<crate::Token>,ended:bool,failed:bool,pulled:usize,interpolation_depth:usize}
impl<'a> ParameterExpressionDemand<'a>{
 pub fn new(source:&'a mut dyn crate::NativeExpressionTokenDemand,clauses:&'a mut ParameterClauseCursor)->Self{Self{level:clauses.top,boundary_kind:FormalExpressionBoundary::Default,original:false,primitive_mode:crate::NativePrimitiveClauseMode::default(),source,clauses,boundary:None,ended:false,failed:false,pulled:0,interpolation_depth:0}}
 /// The SAME Pratt input cursor with the authentic source-clause boundary.
 pub fn for_source(source:&'a mut dyn crate::NativeExpressionTokenDemand,clauses:&'a mut ParameterClauseCursor)->Self{let mut input=Self::new(source,clauses);input.boundary_kind=FormalExpressionBoundary::Source;input}
 /// Caller has already consumed the actual '[' through the SAME clause
 /// cursor. Nested expression brackets are ordinary Pratt tokens; only the
 /// matching current formal dimension delimiter ends this loan.
 pub fn for_dimension(source:&'a mut dyn crate::NativeExpressionTokenDemand,clauses:&'a mut ParameterClauseCursor)->Self{let mut input=Self::new(source,clauses);input.boundary_kind=FormalExpressionBoundary::Dimension;input}
 pub fn original(mut self)->Self{self.original=true;self}
 pub fn take_boundary(&mut self)->Option<crate::Token>{let token=self.boundary.take();if token.is_some(){self.ended=true;}token}
 fn legacy_next_token(&mut self)->std::io::Result<Option<crate::Token>>{
  if self.failed{return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"native parameter expression demand already failed"))}if self.ended{return Ok(None)}let token=match self.source.next_token(){Ok(Some(token))=>token,Ok(None)=>{self.ended=true;return Ok(None)},Err(actual)=>{self.failed=true;return Err(actual)}};
  let ordinal=self.pulled;self.pulled=self.pulled.checked_add(1).ok_or(std::io::ErrorKind::OutOfMemory)?;
  if token.kind==TokenKind::Interpolation{
   let occurrence=crate::NativeExpressionTokenOccurrence::issued(ordinal,token.span);
   match self.source.original_value(occurrence)?{Some(crate::OriginalTokenValue::InterpBegin(_))=>self.interpolation_depth=self.interpolation_depth.checked_add(1).ok_or(std::io::ErrorKind::OutOfMemory)?,Some(crate::OriginalTokenValue::InterpPart(_))if self.interpolation_depth>0=>(),Some(crate::OriginalTokenValue::InterpEnd(_))if self.interpolation_depth>0=>self.interpolation_depth-=1,_=>{self.failed=true;return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"actual interpolation boundary lacks its same produced kind"))}}
  }
  let boundary=self.interpolation_depth==0&&token.kind!=TokenKind::Interpolation&&self.clauses.top==self.level&&match self.boundary_kind{
   FormalExpressionBoundary::Default=>match token.kind{TokenKind::Punctuation=>matches!(token.text.as_str(),","|")"|";"),TokenKind::Ident=>(token.text=="as"&&!self.primitive_mode.as_clause)||(token.text=="in"&&!self.original&&!self.primitive_mode.in_clause),_=>false},
   FormalExpressionBoundary::Source=>match token.kind{TokenKind::Punctuation=>matches!(token.text.as_str(),","|")"|";"),TokenKind::Ident=>token.text=="as"&&!self.primitive_mode.as_clause,_=>false},
   FormalExpressionBoundary::Dimension=>token.kind==TokenKind::Punctuation&&token.text=="]",
  };
  if boundary{self.boundary=Some(token);self.ended=true;return Ok(None)}
  self.clauses.push_expression(token.kind,token.span,&token.text);Ok(Some(token))
 }

}
impl crate::NativeExpressionTokenDemand for ParameterExpressionDemand<'_>{
 fn begin_expression(&mut self)->std::io::Result<()>{self.source.begin_expression()}
 fn next_token(&mut self)->std::io::Result<Option<crate::Token>>{if !self.original{return self.legacy_next_token()}self.read_for_role(crate::NativeExpressionReadRole::Follower).map(|read|match read{crate::NativeExpressionRead::Token(token)=>Some(token),crate::NativeExpressionRead::Boundary(_)|crate::NativeExpressionRead::End=>None})}
 fn read_for_role(&mut self,role:crate::NativeExpressionReadRole)->std::io::Result<crate::NativeExpressionRead>{
  use crate::{NativeExpressionRead as Read,NativeExpressionReadRole as Role};
  if !self.original{return self.legacy_next_token().map(|token|match token{Some(token)=>Read::Token(token),None=>Read::End})}
  if self.failed{return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"native parameter expression demand already failed"))}if self.ended{return Ok(Read::End)}
  if let Some(token)=self.boundary.as_ref(){
   if token.kind!=TokenKind::Ident||!role.accepts_parameter_ident(token.span){return Ok(Read::Boundary(SpanToken{kind:token.kind,span:token.span}))}
   let token=self.boundary.take().unwrap();self.clauses.push_expression(token.kind,token.span,&token.text);return Ok(Read::Token(token))
  }
  let token=match self.source.next_token(){Ok(Some(token))=>token,Ok(None)=>{self.ended=true;return Ok(Read::End)},Err(actual)=>{self.failed=true;return Err(actual)}};
  let ordinal=self.pulled;self.pulled=self.pulled.checked_add(1).ok_or(std::io::ErrorKind::OutOfMemory)?;
  if token.kind==TokenKind::Interpolation{let occurrence=crate::NativeExpressionTokenOccurrence::issued(ordinal,token.span);match self.source.original_value(occurrence)?{Some(crate::OriginalTokenValue::InterpBegin(_))=>self.interpolation_depth=self.interpolation_depth.checked_add(1).ok_or(std::io::ErrorKind::OutOfMemory)?,Some(crate::OriginalTokenValue::InterpPart(_))if self.interpolation_depth>0=>(),Some(crate::OriginalTokenValue::InterpEnd(_))if self.interpolation_depth>0=>self.interpolation_depth-=1,_=>{self.failed=true;return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"actual interpolation boundary lacks its same produced kind"))}}}
  let boundary=self.interpolation_depth==0&&token.kind!=TokenKind::Interpolation&&self.clauses.top==self.level&&match self.boundary_kind{
   FormalExpressionBoundary::Default|FormalExpressionBoundary::Source=>match token.kind{TokenKind::Punctuation=>matches!(token.text.as_str(),","|")"|";"),TokenKind::Ident=>token.text=="as"&&!self.primitive_mode.as_clause&&!role.accepts_parameter_ident(token.span),_=>false},
   FormalExpressionBoundary::Dimension=>token.kind==TokenKind::Punctuation&&token.text=="]",
  };
  if boundary{let actual=SpanToken{kind:token.kind,span:token.span};self.boundary=Some(token);return Ok(Read::Boundary(actual))}
  self.clauses.push_expression(token.kind,token.span,&token.text);Ok(Read::Token(token))
 }
 /// The hidden delimiter was actually pulled/owned here, not EOF. Preserve
 /// its genuine underlying occurrence for a consumer that can retain notices.
 fn original_missing_member(&mut self,separator:crate::NativeExpressionTokenOccurrence,following:Option<crate::NativeExpressionTokenOccurrence>)->std::io::Result<bool>{let following=match following{Some(at)=>Some(at),None=>match self.boundary.as_ref(){Some(token)=>Some(crate::NativeExpressionTokenOccurrence::issued(self.pulled.checked_sub(1).ok_or(std::io::ErrorKind::InvalidData)?,token.span)),None=>None}};self.source.original_missing_member(separator,following)}
 fn original_primitive_notice(&mut self,at:crate::NativeExpressionTokenOccurrence,kind:crate::OriginalInputNoticeKind)->std::io::Result<()>{self.source.original_primitive_notice(at,kind)}
 fn original_close_colon(&self,occurrence:crate::NativeExpressionTokenOccurrence)->std::io::Result<Option<bool>>{self.source.original_close_colon(occurrence)}
 fn original_template_source(&self,span:crate::Span)->std::io::Result<Option<&str>>{self.source.original_template_source(span)}
 fn original_value(&self,occurrence:crate::NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{self.source.original_value(occurrence)}
 fn take_token_credit(&mut self,occurrence:crate::NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::SettingRootLease>>{self.source.take_token_credit(occurrence)}
 fn original_literal_data(&self,occurrence:crate::NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalLiteralRef<'_>>>{self.source.original_literal_data(occurrence)}
 fn requires_original_values(&self)->bool{self.source.requires_original_values()}
 fn set_original_primitive_clause_mode(&mut self,mode:crate::NativePrimitiveClauseMode)->std::io::Result<crate::NativePrimitiveClauseMode>{let previous=self.primitive_mode;self.primitive_mode=mode;Ok(previous)}
}

#[cfg(test)]mod demanded_clause_role_tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 #[test]fn same_pratt_dimension_cursor_consumes_nested_brackets_and_stops_before_future_formal(){
  let text="list(1)[2]] BAD(1)";let counter=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&counter,4<<20,&||Ok(()));let mut clauses=ParameterClauseCursor::new(0);clauses.push(TokenKind::Punctuation,Span::new(0,1),"[");let mut tokens=crate::lex(text).tokens.into_iter();let mut pull=||{let next=tokens.next();assert!(next.as_ref().is_none_or(|token|token.text!="BAD"));Ok(next)};let mut cursor=ParameterExpressionDemand::for_dimension(&mut pull,&mut clauses);let root=crate::parse_expression_demanded(&mut cursor,&a).unwrap();assert!(root.parsed().diagnostics.is_empty());let boundary=cursor.take_boundary().unwrap();assert_eq!(boundary.text,"]");assert_eq!(boundary.span,Span::new(10,11));drop(root);drop(cursor);drop(pull);assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn same_source_cursor_keeps_nested_calls_and_returns_actual_as_boundary_without_future_pull(){
  let text="list(1)[2] as BAD(1)";let counter=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&counter,4<<20,&||Ok(()));let mut clauses=ParameterClauseCursor::new(0);let mut tokens=crate::lex(text).tokens.into_iter();let mut pull=||{let next=tokens.next();assert!(next.as_ref().is_none_or(|token|token.text!="BAD"));Ok(next)};let mut cursor=ParameterExpressionDemand::for_source(&mut pull,&mut clauses);let root=crate::parse_expression_demanded(&mut cursor,&a).unwrap();assert!(root.parsed().diagnostics.is_empty());assert_eq!(cursor.take_boundary().unwrap().text,"as");drop(root);drop(cursor);drop(pull);assert_eq!(counter.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]mod original_input_specifier_partition_controls{use super::*;
 #[test]fn actual_shared_clause_cursor_retains_optional_pre_and_post_in_as_without_rewriting_native_partition(){let source="value as mob|obj in list(1) as text";let tokens=crate::lex_spans(source).tokens;let parts=parameter_clause_spans(source,&tokens,Span::new(0,source.len())).unwrap();let first=source.find("as").unwrap();let post=source.rfind("as").unwrap();assert_eq!(parts.annotation,Some(Span::new(first,first+2)));assert_eq!(parts.post_source_annotation,Some(Span::new(post,post+2)));let marker=parts.source.unwrap();assert_eq!(source.get(parts.after_original(marker).range()).unwrap().trim(),"list(1)");assert_eq!(source.get(parts.after(marker).range()).unwrap().trim(),"list(1) as text");assert_eq!(source.get(parts.after_original(parts.annotation.unwrap()).range()).unwrap().trim(),"mob|obj");}
 #[test]fn post_only_as_is_the_same_actual_ignored_annotation_and_third_as_is_not_another_issued_slot(){for source in["value in list(1) as text","value as mob in list(1) as text as obj"]{let tokens=crate::lex_spans(source).tokens;let parts=parameter_clause_spans(source,&tokens,Span::new(0,source.len())).unwrap();let post=parts.post_source_annotation.unwrap();assert_eq!(post.start,source.find("as text").unwrap());if source.starts_with("value in"){assert_eq!(parts.annotation,Some(post));}else{assert_ne!(parts.annotation,Some(post));assert_ne!(post.start,source.rfind("as").unwrap());}}}
}

#[cfg(test)]mod actual_original_default_extent_controls{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 struct Feed{tokens:std::vec::IntoIter<crate::Token>,pulls:usize}
 impl crate::NativeExpressionTokenDemand for Feed{fn next_token(&mut self)->std::io::Result<Option<crate::Token>>{self.pulls+=1;let next=self.tokens.next();assert!(next.as_ref().is_none_or(|token|token.text!="BAD"),"actual Pratt grammar demanded a future formal after its consumed boundary/failure");Ok(next)}}
 fn default(text:&str,a:&crate::SettingAdmission<'_>)->(crate::DemandedExpression,Option<crate::Token>,ParameterClauseSpans,usize){let mut source=Feed{tokens:crate::lex(text).tokens.into_iter(),pulls:0};let mut clauses=ParameterClauseCursor::new(0);let mut input=ParameterExpressionDemand::new(&mut source,&mut clauses).original();let root=crate::parse_original_expression_demanded(&mut input,a).unwrap();let boundary=input.take_boundary();drop(input);let pulls=source.pulls;(root,boundary,clauses.spans(),pulls)}
 #[test]fn actual_original_default_binary_in_is_owned_by_pratt_before_formal_as_without_source_marker(){let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let(root,boundary,parts,_)=default("1 in choices as num, BAD(1)",&a);assert!(root.parsed().diagnostics.is_empty());assert!(matches!(&root.parsed().expr.as_ref().unwrap().kind,crate::ExprKind::Binary{op,..}if op=="in"));assert_eq!(boundary.unwrap().text,"as");assert!(parts.source.is_none());assert!(parts.annotation.is_none());assert!(root.parsed().original_input_notices().unwrap().as_slice().is_empty());drop(root);assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]fn actual_input_primitive_consumes_its_pre_in_ignored_post_before_outer_formal_as(){let text="input() as text in choices as obj as num, BAD(1)";let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let(root,boundary,parts,_)=default(text,&a);assert!(root.parsed().diagnostics.is_empty(),"{:?}",root.parsed().diagnostics);let expression=root.parsed().expr.as_ref().unwrap();assert_eq!(boundary.unwrap().span.start,text.rfind("as num").unwrap());assert_eq!(expression.span.end,text.find("obj").unwrap()+3);let crate::ExprKind::Binary{op,lhs,..}=&expression.kind else{panic!("actual input in-clause")};assert_eq!(op,"in");assert!(matches!(&lhs.kind,crate::ExprKind::TypeFilter{types,..}if types==&["text"]));let notices=root.parsed().original_input_notices().unwrap().as_slice();assert_eq!(notices.len(),1);assert_eq!(notices[0].kind(),crate::OriginalInputNoticeKind::InPrecedesAs);assert_eq!(notices[0].span().start,text.find("as obj").unwrap());assert!(parts.source.is_none());assert!(parts.annotation.is_none());drop(root);assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]fn actual_original_locate_container_uses_full_expression_precedence_inside_prefix(){let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let(root,boundary,_,_)=default("!locate(1) in choices || other as num, BAD(1)",&a);assert!(root.parsed().diagnostics.is_empty());let crate::ExprKind::Unary{op,value}=&root.parsed().expr.as_ref().unwrap().kind else{panic!("prefix must remain outside complete Locate term")};assert_eq!(op,"!");let crate::ExprKind::Binary{op,rhs,..}=&value.kind else{panic!("actual Locate in clause")};assert_eq!(op,"in");assert!(matches!(&rhs.kind,crate::ExprKind::Binary{op,..}if op=="||"));assert_eq!(boundary.unwrap().text,"as");drop(root);assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]fn actual_native_input_events_recover_unknown_type_and_group_failure_stops_before_future_tokens(){let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let(root,boundary,_,_)=default("input() as unknown_name as num, BAD(1)",&a);assert!(root.parsed().diagnostics.is_empty());assert_eq!(root.parsed().original_input_notices().unwrap().as_slice()[0].kind(),crate::OriginalInputNoticeKind::BadInputType);assert_eq!(boundary.unwrap().text,"as");drop(root);let(root,_,_,_)=default("input() as (mob) BAD(1)",&a);assert!(!root.parsed().diagnostics.is_empty());let failure=root.parsed().original_input_failure().unwrap();assert_eq!(failure.expected(),crate::OriginalInputExpected::RightParen);assert_eq!(failure.token_span(),Some(Span::new(12,15)));drop(root);assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]fn ordinary_compiler_default_cursor_keeps_existing_in_boundary(){let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut source=Feed{tokens:crate::lex("1 in choices as num, BAD(1)").tokens.into_iter(),pulls:0};let mut clauses=ParameterClauseCursor::new(0);let mut input=ParameterExpressionDemand::new(&mut source,&mut clauses);let root=crate::parse_expression_demanded(&mut input,&a).unwrap();assert!(matches!(&root.parsed().expr.as_ref().unwrap().kind,crate::ExprKind::Literal(_)));assert_eq!(input.take_boundary().unwrap().text,"in");assert!(root.parsed().original_input_notices().is_none());drop(root);drop(input);drop(source);assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]fn nested_input_lookahead_remains_owned_by_enclosing_primitive_before_formal_boundary(){let text="input() in input() as text as obj as num, BAD(1)";let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let(root,boundary,parts,_)=default(text,&a);assert!(root.parsed().diagnostics.is_empty(),"{:?}",root.parsed().diagnostics);assert_eq!(boundary.unwrap().span.start,text.rfind("as num").unwrap());assert_eq!(root.parsed().expr.as_ref().unwrap().span.end,text.find("obj").unwrap()+3);let rows=root.parsed().original_input_notices().unwrap().as_slice();assert_eq!(rows.len(),1);assert_eq!(rows[0].kind(),crate::OriginalInputNoticeKind::InPrecedesAs);assert!(parts.source.is_none());drop(root);assert_eq!(used.load(Ordering::Acquire),0);}

}

#[cfg(test)]mod actual_formal_member_boundary_forwarding_controls{
 use super::*;use crate::{NativeExpressionTokenDemand,NativeExpressionTokenOccurrence,OriginalInputNoticeKind};use std::{io,sync::{Arc,atomic::{AtomicUsize,Ordering}}};
 struct Audit{rows:Vec<crate::Token>,at:usize,following:Option<usize>,primitive:usize}
 impl NativeExpressionTokenDemand for Audit{fn next_token(&mut self)->io::Result<Option<crate::Token>>{let next=self.rows.get(self.at).cloned();if let Some(token)=&next{assert_ne!(token.text,"BAD");self.at+=1}Ok(next)}fn original_missing_member(&mut self,separator:NativeExpressionTokenOccurrence,following:Option<NativeExpressionTokenOccurrence>)->io::Result<bool>{assert_eq!(self.rows[separator.ordinal()].span,separator.span());assert_eq!(self.rows[separator.ordinal()].text,".");let next=following.expect("genuine hidden formal boundary must not become EOF");assert_eq!(self.rows[next.ordinal()].span,next.span());assert!(matches!(self.rows[next.ordinal()].text.as_str(),")"|","));self.following=Some(next.ordinal());Ok(true)}fn original_primitive_notice(&mut self,at:NativeExpressionTokenOccurrence,kind:OriginalInputNoticeKind)->io::Result<()>{assert_eq!(self.rows[at.ordinal()].span,at.span());assert_eq!(kind,OriginalInputNoticeKind::BadInputType);self.primitive+=1;Ok(())}}
 #[test]fn genuine_hidden_rightparen_and_comma_forward_their_actual_occurrence_without_future_pull(){for text in["x.) BAD(","x., BAD("]{let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut source=Audit{rows:crate::lex(text).tokens,at:0,following:None,primitive:0};let mut clauses=ParameterClauseCursor::new(0);{let mut demand=ParameterExpressionDemand::new(&mut source,&mut clauses).original();let root=crate::parse_original_expression_demanded(&mut demand,&a).unwrap();assert!(root.parsed().diagnostics.is_empty());assert!(matches!(&root.parsed().expr.as_ref().unwrap().kind,crate::ExprKind::Member{selector,..}if selector.is_empty()));assert!(matches!(demand.take_boundary().unwrap().text.as_str(),")"|","));drop(root);}assert_eq!(source.following,Some(2));assert_eq!(source.at,3);drop(source);assert_eq!(used.load(Ordering::Acquire),0);}}
}

#[cfg(test)]mod original_read_role_controls{
 use super::*;use crate::{NativeExpressionTokenDemand,NativeExpressionRead as Read,NativeExpressionReadRole as Role};use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
 struct ActualFeed{rows:std::vec::IntoIter<crate::Token>,pulls:usize,credited:Vec<usize>}
 impl NativeExpressionTokenDemand for ActualFeed{
  fn next_token(&mut self)->std::io::Result<Option<crate::Token>>{self.pulls+=1;let next=self.rows.next();assert!(next.as_ref().is_none_or(|t|t.text!="BAD"),"a role may not pull a future formal/body");Ok(next)}
  fn take_token_credit(&mut self,at:crate::NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::SettingRootLease>>{assert!(!self.credited.contains(&at.ordinal()),"same token credit transferred twice");self.credited.push(at.ordinal());Ok(None)}
 }
 fn feed(text:&str)->ActualFeed{
  let mut source=crate::lex(text).tokens.into_iter().peekable();
  let mut rows=Vec::new();
  while let Some(mut token)=source.next(){
   // Original scalar transport issues the adjacent safe selector as one token.
   if token.text=="?"&&source.peek().is_some_and(|next|next.text=="."&&next.span.start==token.span.end){
    token.text.push('.');token.span.end=source.next().unwrap().span.end;
   }
   rows.push(token);
  }
  ActualFeed{rows:rows.into_iter(),pulls:0,credited:Vec::new()}
 }
 #[test]fn original_consuming_roles_keep_member_global_and_path_as_inside_same_default(){
  for(text,expected,boundary)in[("x.as) BAD(","member",")"),("x?.as, BAD(","safe",","),("::as) BAD(","global",")"),("/datum/as as BAD(","path","as"),("x+as) BAD(","binary",")")]{
   let used=Arc::new(AtomicUsize::new(0));let a=crate::SettingAdmission::new(&used,8<<20,&||Ok(()));let mut source=feed(text);let mut clauses=ParameterClauseCursor::new(0);
   {let mut demand=ParameterExpressionDemand::new(&mut source,&mut clauses).original();let root=crate::parse_original_expression_demanded(&mut demand,&a).unwrap();assert!(root.parsed().diagnostics.is_empty(),"{text}: {:?}",root.parsed().diagnostics);let expr=root.parsed().expr.as_ref().unwrap();match expected{
    "member"=>assert!(matches!(&expr.kind,crate::ExprKind::Member{selector,..}if selector=="as")),
    "safe"=>assert!(matches!(&expr.kind,crate::ExprKind::SafeMember{selector,..}if selector=="as")),
    "global"=>assert!(matches!(&expr.kind,crate::ExprKind::Unary{op,value}if op=="::"&&matches!(&value.kind,crate::ExprKind::Ident(name)if name=="as"))),
    "path"=>assert!(matches!(&expr.kind,crate::ExprKind::TypePath(path)if path=="/datum/as")),
    "binary"=>assert!(matches!(&expr.kind,crate::ExprKind::Binary{rhs,..}if matches!(&rhs.kind,crate::ExprKind::Ident(name)if name=="as"))),_=>unreachable!()}
    assert_eq!(demand.take_boundary().unwrap().text,boundary);assert!(matches!(demand.read_for_role(Role::Term).unwrap(),Read::End));drop(root);}
   assert!(clauses.spans().annotation.is_none(),"expression-role names cannot become lexical annotation markers");drop(source);assert_eq!(used.load(Ordering::Acquire),0);
  }
 }
 #[test]fn held_ident_acceptance_moves_once_without_repull_and_punctuation_cannot_resume(){
  let mut source=feed("as) BAD(");let mut clauses=ParameterClauseCursor::new(0);{let mut input=ParameterExpressionDemand::new(&mut source,&mut clauses).original();let span=match input.read_for_role(Role::Follower).unwrap(){Read::Boundary(at)=>at.span,_=>panic!("actual held as")};assert!(matches!(input.read_for_role(Role::Follower).unwrap(),Read::Boundary(at)if at.span==span));assert!(matches!(input.read_for_role(Role::Identifier).unwrap(),Read::Token(t)if t.text=="as"&&t.span==span));let close=match input.read_for_role(Role::Follower).unwrap(){Read::Boundary(at)=>at.span,_=>panic!("actual held close")};for role in[Role::Term,Role::Identifier,Role::PathName{adjacent_to:close.start}]{assert!(matches!(input.read_for_role(role).unwrap(),Read::Boundary(at)if at.span==close));}assert_eq!(input.take_boundary().unwrap().text,")");assert!(matches!(input.read_for_role(Role::Term).unwrap(),Read::End));}assert_eq!(source.pulls,2);
 }
 #[test]fn real_end_is_terminal_and_path_role_does_not_eat_nonadjacent_annotation(){
  let mut source=feed("");let mut clauses=ParameterClauseCursor::new(0);{let mut input=ParameterExpressionDemand::new(&mut source,&mut clauses).original();assert!(matches!(input.read_for_role(Role::Term).unwrap(),Read::End));assert!(matches!(input.read_for_role(Role::Identifier).unwrap(),Read::End));}assert_eq!(source.pulls,1);
  let mut source=feed("as BAD(");let mut clauses=ParameterClauseCursor::new(0);{let mut input=ParameterExpressionDemand::new(&mut source,&mut clauses).original();assert!(matches!(input.read_for_role(Role::PathName{adjacent_to:99}).unwrap(),Read::Boundary(_)));assert_eq!(input.take_boundary().unwrap().text,"as");}assert_eq!(source.pulls,1);
 }
}
