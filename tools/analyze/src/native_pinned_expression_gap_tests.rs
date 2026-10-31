//! Independent observations from the actual pinned original Lexer/Parser.
//! No native formatter or answer participates in the original observations.
use dreammaker::{Context,Location,lexer::{Lexer,Token,Punctuation},ast::{Expression,Term,BinaryOp}};
fn original(text:&str)->Expression{
 let context=Context::default();let file=context.register_file(std::path::Path::new("code/probe.dm"));
 let tokens=Lexer::new(&context,file,text.as_bytes()).filter(|token|!matches!(&token.token,Token::Punct(Punctuation::Space|Punctuation::Tab|Punctuation::Newline)));
 let expression=dreammaker::parser::parse_expression(&context,Location{file,line:1,column:1},tokens).expect("actual original expression");
 assert!(context.errors().is_empty(),"actual original diagnostics: {:?}",context.errors());expression
}
#[test]fn pinned_original_empty_input_type_tuple_and_native_primary_share_actual_as_shape(){
 for text in["as()","as(())","as( ( ) )"]{
  let old=original(text);let Expression::Base{term,follow}=&old else{panic!("original base")};assert!(follow.is_empty());let Term::As(types)=&term.elem else{panic!("actual original as")};assert!(types.is_empty());assert_eq!(format!("{types:?}"),"(empty)");
  let native=dm_syntax::parse_expression(text);assert!(native.diagnostics.is_empty(),"{:?}",native.diagnostics);let dm_syntax::ExprKind::Call{callee,args}=native.expr.unwrap().kind else{panic!("native primitive")};assert!(matches!(callee.kind,dm_syntax::ExprKind::Ident(name)if name=="as"));assert!(args.is_empty());
 }
}
#[test]fn pinned_original_spaceship_and_native_primary_share_exact_operator_precedence(){
 for(text,old_op,native_op)in[("a <=> b",BinaryOp::LessOrGreater,"<=>"),("a <=> b << c",BinaryOp::LShift,"<<"),("a <=> b == c",BinaryOp::Eq,"=="),("a <=> b < c",BinaryOp::Less,"<")]{
  let old=original(text);let Expression::BinaryOp{op,lhs,..}=old else{panic!("original binary")};assert_eq!(op,old_op);if native_op!="<=>"{assert!(matches!(*lhs,Expression::BinaryOp{op:BinaryOp::LessOrGreater,..}));}
  let native=dm_syntax::parse_expression(text);assert!(native.diagnostics.is_empty(),"{:?}",native.diagnostics);let dm_syntax::ExprKind::Binary{op,lhs,..}=native.expr.unwrap().kind else{panic!("native binary")};assert_eq!(op,native_op);if native_op!="<=>"{assert!(matches!(lhs.kind,dm_syntax::ExprKind::Binary{op,..}if op=="<=>"));}
 }
}

#[test]fn pinned_original_reference_global_and_relative_prefab_match_native_primary_shapes(){
 let old=original("&value");let Expression::Base{term,follow}=old else{panic!("original reference base")};assert!(matches!(term.elem,Term::Ident(ref name)if name=="value"));assert_eq!(follow.len(),1);assert!(matches!(follow[0].elem,dreammaker::ast::Follow::Unary(dreammaker::ast::UnaryOp::Reference)));
 let native=dm_syntax::parse_expression("&value");assert!(native.diagnostics.is_empty());assert!(matches!(native.expr.unwrap().kind,dm_syntax::ExprKind::Unary{ref op,..}if op=="&"));
 let old=original("::value");let Expression::Base{term,follow}=old else{panic!("original global base")};assert!(matches!(term.elem,Term::GlobalIdent(ref name)if &**name=="value"));assert!(follow.is_empty());let native=dm_syntax::parse_expression("::value");assert!(native.diagnostics.is_empty());assert!(matches!(native.expr.unwrap().kind,dm_syntax::ExprKind::Unary{ref op,..}if op=="::"));
 let old=original(".child/type");let Expression::Base{term,follow}=old else{panic!("original prefab base")};let Term::Prefab(prefab)=term.elem else{panic!("actual original relative prefab")};assert_eq!(prefab.path,vec![(dreammaker::ast::PathOp::Dot,"child".to_owned()),(dreammaker::ast::PathOp::Slash,"type".to_owned())]);assert!(prefab.vars.is_empty()&&follow.is_empty());let native=dm_syntax::parse_expression(".child/type");assert!(native.diagnostics.is_empty());assert!(matches!(native.expr.unwrap().kind,dm_syntax::ExprKind::TypePath(ref path)if path==".child/type"));
}
