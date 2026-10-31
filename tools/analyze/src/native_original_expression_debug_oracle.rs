#[path="../../dmb/crates/dm-analysis/src/checker_original_expression_debug_core.rs"]mod core;
use core::*;
use dm_syntax::{Expr,ExprKind,Span};
use std::fmt::Write;
mod projection_tests{
 use super::*;
 use dm_syntax::{TokenKind,SpanToken};
 use dreammaker::{Context,Location,lexer::{Lexer,Token,Punctuation}};
 struct Root<'a>{source:&'a str,tokens:&'a[SpanToken]}
 struct Child<'a,'b>{root:&'a Root<'b>,fragment:&'a dm_syntax::literal::PinnedLiteralFragment<'a>}
 fn point(source:&str,offset:usize,out:&mut DebugSink<'_>)->Result<(),String>{let prefix=source.get(..offset).ok_or("coordinate outside original source")?;let line=prefix.bytes().filter(|byte|*byte==b'\n').count()+1;let column=offset-prefix.rfind('\n').map_or(0,|at|at+1)+1;write!(out,"Location {{ file: FileId(1), line: {line}, column: {column} }}").unwrap();Ok(())}
 fn punctuation<'a>(expected:&str,tokens:impl Iterator<Item=Result<(TokenKind,Span,&'a str),String>>)->Result<usize,String>{let mut start=None;let mut at=0;for token in tokens{let(kind,span,text)=token?;if matches!(kind,TokenKind::Comment|TokenKind::Whitespace|TokenKind::Newline){continue}if start.is_none(){start=Some(span.start)}let rest=expected.get(at..).ok_or("punctuation width differs")?;if !rest.starts_with(text){return Err(format!("actual primary punctuation {text:?} differs from {expected:?}"))}at+=text.len();if at==expected.len(){return start.ok_or("punctuation absent".into())}}Err("actual primary punctuation absent".into())}
 impl Source for Root<'_>{type Error=String;type Frame<'a>=()where Self:'a;type Scratch<'a>=()where Self:'a;fn scratch(&self,_:usize)->Result<(),String>{Ok(())}
  fn frame(&self)->Result<(),String>{Ok(())}
  fn location(&self,offset:usize,out:&mut DebugSink<'_>)->Result<(),String>{point(self.source,offset,out)}
  fn punctuation(&self,span:Span,spelling:&str)->Result<usize,String>{let first=self.tokens.partition_point(|token|token.span.end<=span.start);let last=self.tokens.partition_point(|token|token.span.start<span.end);punctuation(spelling,self.tokens[first..last].iter().map(|token|Ok((token.kind,token.span,token.text(self.source)))))}
  fn path(&self,path:&Expr,out:&mut DebugSink<'_>)->Result<(),String>{path_debug(self,path,out)}
  fn fragment_expression(&self,fragment:&dm_syntax::literal::PinnedLiteralFragment<'_>,out:&mut DebugSink<'_>)->Result<(),String>{let child=fragment.expression().ok_or("actual primary interpolation child absent")?;expression(&Child{root:self,fragment},child,out)}
 }
 impl Source for Child<'_,'_>{type Error=String;type Frame<'a>=()where Self:'a;type Scratch<'a>=()where Self:'a;fn scratch(&self,_:usize)->Result<(),String>{Ok(())}
  fn frame(&self)->Result<(),String>{Ok(())}
  fn location(&self,offset:usize,out:&mut DebugSink<'_>)->Result<(),String>{self.root.location(offset,out)}
  fn punctuation(&self,span:Span,spelling:&str)->Result<usize,String>{let tokens=self.fragment.tokens_between(span).map_err(|error|format!("{error:?}"))?;punctuation(spelling,tokens.map(|token|{let(kind,span)=token.map_err(|error|format!("{error:?}"))?;let text=self.fragment.token_text(span).map_err(|error|format!("{error:?}"))?;Ok((kind,span,text))}))}
  fn path(&self,path:&Expr,out:&mut DebugSink<'_>)->Result<(),String>{path_debug(self,path,out)}
  fn fragment_expression(&self,fragment:&dm_syntax::literal::PinnedLiteralFragment<'_>,out:&mut DebugSink<'_>)->Result<(),String>{let child=fragment.expression().ok_or("actual primary nested interpolation child absent")?;expression(&Child{root:self.root,fragment},child,out)}
 }
 fn original_result(text:&str)->Result<String,String>{let context=Context::default();let file=context.register_file(std::path::Path::new("code/probe.dm"));let tokens=Lexer::new(&context,file,text.as_bytes()).filter(|token|!matches!(&token.token,Token::Punct(Punctuation::Space|Punctuation::Tab|Punctuation::Newline)));let old=dreammaker::parser::parse_expression(&context,Location{file,line:1,column:1},tokens).map_err(|error|format!("{text}: original primary parser: {error:?}"))?;assert!(context.errors().iter().all(|error|error.severity()!=dreammaker::Severity::Error),"{:?}",context.errors());Ok(format!("{old:?}"))}
 fn original(text:&str)->String{original_result(text).unwrap_or_else(|error|panic!("{error}"))}
 fn native(text:&str)->Result<String,String>{let lexical=dm_syntax::lex_spans(text);assert!(lexical.diagnostics.is_empty());let counter=std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));let checkpoint=||Ok(());let admission=dm_syntax::SettingAdmission::new(&counter,8*1024*1024,&checkpoint);let root=dm_syntax::prepare_setting_expression(text,&lexical.tokens,Span::new(0,text.len()),&admission).map_err(|error|format!("actual primary root refused: {error:?}"))?;let source=Root{source:text,tokens:&lexical.tokens};let mut count=DebugSink::count();let pending=expression(&source,root.original_expression(),&mut count);if count.denied(){return Err("count overflow".into())}pending?;let mut out=String::new();out.try_reserve_exact(count.len()).map_err(|_|"actual output allocation refused")?;let mut fixed=DebugSink::fixed(&mut out,count.len());let pending=expression(&source,root.original_expression(),&mut fixed);if fixed.denied()||fixed.len()!=count.len(){return Err("fixed output mismatch".into())}pending?;drop(fixed);Ok(out)}
 #[test]fn complete_original_debug_words_match_direct_primary_nodes_for_scalar_operator_call_and_prefab_shapes(){
  for text in["value","null","1","1.0","1.#INF","1.#IND","0x64","0144","2147483648","-x","&x",".relative/type","::global_value","!~x","++x","x--","a+b*c","a=b=c","a ? b : c","(x)","foo(1,bar(2))","foo(,1,,null)","list(1,a=2)","alist(1)",".()","..()","::foo(1)","object.field","object:field","object?.field","object?:field","object[1]","object?[1]","object.foo(1)","object::field","object::proc(1)","new","new()","new /datum/item","new /datum/item(1)","new prototype.field(1)","/datum/item{value=1}","pick(1,2;3)","call(src,\"probe\")(1)","call_ext(\"lib\",\"fn\")(1)","input(\"prompt\") as null|mob in values","locate(1) in values","as(())"]{let expected=original(text);let actual=native(text).unwrap_or_else(|error|panic!("{text}: {error}"));assert_eq!(actual,expected,"{text}");}
 }
 #[test]fn complete_original_literal_debug_words_match_primary_fragments_without_child_reparse(){for text in["\"plain\"","\"a\\n\\q\\\"b\"","@\"raw\\n\"","\"a[ ]b[x+1]c\"","\"a[/*empty*/]b[x /*dot*/ . value]c\"","'a\\n\\q\\\'b'"]{assert_eq!(native(text).unwrap_or_else(|error|panic!("{text}: {error}")),original(text),"{text}");}}
 #[test]fn pinned_compact_ternary_is_an_explicit_negative_while_spaced_ternary_remains_positive(){
  let rejected=original_result("a?b:c").expect_err("the pinned lexer/parser consumes compact b:c as a member follow, leaving no ternary colon");assert!(rejected.contains("original primary parser"));assert!(rejected.contains("a?b:c"));assert_eq!(native("a ? b : c").unwrap(),original("a ? b : c"));
 }

}
