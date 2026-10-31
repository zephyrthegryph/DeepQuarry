//! Independent original lexer vs prepared primary-literal spelling; no Sem/model.
use std::error::Error;
fn main()->Result<(),Box<dyn Error>>{
 let cases=[r#""plain""#,r#""é\n\[escaped]""#,"\"before\\\r\n  after\"","\"before\\\n\n\t after\"","{\"first\nsecond\"}","@\"[raw]\\n\"","@'é[raw]'","@{\"é\r\n[raw]\"}"];
 for source in cases{
  let context=dreammaker::Context::default();let original:Vec<_>=dreammaker::lexer::Lexer::new(&context,Default::default(),source.as_bytes()).collect();
  assert!(context.errors().is_empty(),"original lexer diagnostics for {source:?}: {:?}",context.errors());
  let [dreammaker::lexer::LocatedToken{token:dreammaker::lexer::Token::String(expected),..},dreammaker::lexer::LocatedToken{token:dreammaker::lexer::Token::Punct(dreammaker::lexer::Punctuation::Newline),..}]=original.as_slice()else{panic!("actual old literal token required: {original:?}")};
  let parsed=dm_syntax::parse_expression(source);assert!(parsed.diagnostics.is_empty(),"primary diagnostics for {source:?}: {:?}",parsed.diagnostics);
  let dm_syntax::Expr{kind:dm_syntax::ExprKind::Literal(value),..}=parsed.expr.unwrap()else{panic!("actual primary literal required")};
  value.parts().unwrap();let mut text=String::new();assert!(value.write_pinned_static_text(&mut text).unwrap());assert_eq!(&text,expected,"complete original token spelling: {source:?}");
 }
 println!("independent original lexical String spelling: {} complete cases matched",cases.len());Ok(())
}
