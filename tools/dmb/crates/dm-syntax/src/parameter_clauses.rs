//! One scalar clause partition shared by native metadata and original roots.
//! No lexer, AST, symbol table, token copy or source authority is created here.
use crate::parameter_syntax::ParameterToken;
use crate::{Span, SpanToken, TokenKind};
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
pub(crate) fn clause_spans<T: ParameterToken>(
    source: &str,
    tokens: &[T],
    span: Span,
) -> Result<ParameterClauseSpans, &'static str> {
    source
        .get(span.range())
        .ok_or("parameter clause span outside original source")?;
    let mut cursor=ParameterClauseCursor::new(span.start);
    for t in tokens{
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
 pub fn take_boundary(&mut self)->Option<crate::Token>{self.boundary.take()}
}
impl crate::NativeExpressionTokenDemand for ParameterExpressionDemand<'_>{
 fn begin_expression(&mut self)->std::io::Result<()>{self.source.begin_expression()}
 fn next_token(&mut self)->std::io::Result<Option<crate::Token>>{
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
 fn original_close_colon(&self,occurrence:crate::NativeExpressionTokenOccurrence)->std::io::Result<Option<bool>>{self.source.original_close_colon(occurrence)}
 fn original_template_source(&self,span:crate::Span)->std::io::Result<Option<&str>>{self.source.original_template_source(span)}
 fn original_value(&self,occurrence:crate::NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::OriginalTokenValue<&str>>>{self.source.original_value(occurrence)}
 fn take_token_credit(&mut self,occurrence:crate::NativeExpressionTokenOccurrence)->std::io::Result<Option<crate::SettingRootLease>>{self.source.take_token_credit(occurrence)}
 fn original_literal_data(&self,occurrence:crate::NativeExpressionTokenOccurrence)->std::io::Result<Option<&crate::OriginalLiteralData>>{self.source.original_literal_data(occurrence)}
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
