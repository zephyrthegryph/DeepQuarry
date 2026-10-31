use super::*;
use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
fn body(source:&str)->ParsedBody{
 let ast=crate::parse(source);assert!(ast.diagnostics.is_empty(),"{:?}",ast.diagnostics);
 crate::parse_body_items_with_context(&ast.items[0].children,source,&|_|None)
}
fn literal(parsed:&ParsedBody)->&crate::LiteralText{
 let StatementKind::Return(Some(Expr{kind:ExprKind::Literal(l),..}))=&parsed.statements[0].kind else{panic!("actual return literal")};l
}
fn prepare(source:&str,a:&SettingAdmission<'_>)->io::Result<PreparedBodyLiteralSyntax>{
 let cleanup=a.reserve(source.len()*512+8192)?;
 let parsed=body(source);prepare_body_literal_syntax(parsed,cleanup,a)
}
#[test]
fn body_header_context_never_demands_interpolation_children(){
 let source="/proc/p()\n    return \"value [1 + 2]\"\n";
 let before=crate::literal::literal_child_parses_for_test();let parsed=body(source);
 assert_eq!(crate::literal::literal_child_parses_for_test(),before);
 assert!(literal(&parsed).retained_parts().is_none(),"a loop-header receipt is not an interpolation demand");
}
#[test]
fn admitted_body_children_are_original_once_and_literal_alias_keeps_physical_credit(){
 let source="/proc/p()\n    return \"value [1 + 2]\"\n";let counter=Arc::new(AtomicUsize::new(0));let healthy=||Ok(());
 let a=SettingAdmission::with_stack_allowance(&counter,32*1024*1024,1024*1024,&healthy);
 let before=crate::literal::literal_child_parses_for_test();let prepared=prepare(source,&a).unwrap();
 assert_eq!(crate::literal::literal_child_parses_for_test()-before,1);
 let(parsed,admission)=prepared.into_parts();assert!(admission.is_admitted_by(&a));
 let native=literal(&parsed);let parts=native.parts().unwrap().unwrap();let pointer=parts.expressions.as_ptr();
 // Distinct actual consumer algorithms both borrow the retained syntax.
 struct Read{count:usize}impl crate::TypedVisitor for Read{
  fn projected_expression(&mut self,_:crate::ProjectedExprView<'_>,_:&[crate::NodeStep])->crate::VisitDecision{crate::VisitDecision::Descend}
  fn expression(&mut self,_:&Expr,_:&[crate::NodeStep])->crate::VisitDecision{self.count+=1;crate::VisitDecision::Descend}
 }
 let mut read=Read{count:0};crate::visit_statements(&parsed.statements,&mut read);assert!(read.count>=4);
 assert_eq!(native.parts().unwrap().unwrap().expressions.as_ptr(),pointer);
 assert_eq!(crate::literal::literal_child_parses_for_test()-before,1,"every consumer shares the issuing child's parser result");
 let expected=body(source);assert_eq!(native.parts(),literal(&expected).parts());drop(expected);
 let alias=native.clone();let retained=counter.load(Ordering::Acquire);assert!(retained>0);
 drop_body_literal_syntax(parsed,Some(admission));assert_eq!(counter.load(Ordering::Acquire),retained);
 drop(alias);assert_eq!(counter.load(Ordering::Acquire),0,"last literal physical free releases the same source-free credit");
}
#[test]
fn body_interpolation_syntax_errors_stay_deferred_identical_to_owned_parser(){
 let source="/proc/p()\n    return \"bad [1 +]\"\n";let counter=Arc::new(AtomicUsize::new(0));let healthy=||Ok(());let a=SettingAdmission::new(&counter,16*1024*1024,&healthy);
 let prepared=prepare(source,&a).unwrap();let(parsed,admission)=prepared.into_parts();assert!(parsed.diagnostics.is_empty());
 let expected=body(source);assert_eq!(literal(&parsed).parts().unwrap_err(),literal(&expected).parts().unwrap_err());
 drop(expected);drop_body_literal_syntax(parsed,Some(admission));assert_eq!(counter.load(Ordering::Acquire),0);
}
#[test]
fn actual_mid_child_parser_io_leaves_no_published_body_or_cached_error_and_recovers(){
 let source="/proc/p()\n    return \"value [1 + 2]\"\n";let counter=Arc::new(AtomicUsize::new(0));let before=crate::literal::literal_child_parses_for_test();
 let failed=||if crate::literal::literal_child_parses_for_test()>before{Err(io::Error::from_raw_os_error(1450))}else{Ok(())};
 let a=SettingAdmission::new(&counter,16*1024*1024,&failed);
 assert!(prepare(source,&a).is_err());assert!(crate::literal::literal_child_parses_for_test()>before,"failure happened inside the real child parser");
 assert_eq!(a.take_operational_error().unwrap().raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),0);
 let healthy=||Ok(());let retry=SettingAdmission::new(&counter,16*1024*1024,&healthy);
 let result=prepare(source,&retry).unwrap();let(parsed,admission)=result.into_parts();assert_eq!(literal(&parsed).parts().unwrap().unwrap().expressions.len(),1);
 drop_body_literal_syntax(parsed,Some(admission));assert_eq!(counter.load(Ordering::Acquire),0);
}
#[test]
fn body_compatibility_cached_or_escaped_literal_owner_cannot_be_grafted(){
 let source="/proc/p()\n    return \"value [1 + 2]\"\n";
 for cached in[false,true]{
  let parsed=body(source);if cached{literal(&parsed).parts().unwrap();}
  let alias=literal(&parsed).clone();let before=alias.retained_parts().map(|r|r.map(|v|v.map(|p|p.expressions.as_ptr())));
  let counter=Arc::new(AtomicUsize::new(0));let healthy=||Ok(());let a=SettingAdmission::new(&counter,16*1024*1024,&healthy);let cleanup=a.reserve(source.len()*512+8192).unwrap();
  assert!(prepare_body_literal_syntax(parsed,cleanup,&a).is_err());assert_eq!(a.take_operational_error().unwrap().kind(),io::ErrorKind::InvalidInput);
  assert_eq!(alias.retained_parts().map(|r|r.map(|v|v.map(|p|p.expressions.as_ptr()))),before,"legacy live alias is never mutated or leased by native preparation");
  assert_eq!(counter.load(Ordering::Acquire),0);drop(alias);
 }
}
#[test]
fn body_resource_refusal_is_actual_same_counter_and_fresh_input_retries(){
 let source="/proc/p()\n    return \"value [1 + 2]\"\n";let counter=Arc::new(AtomicUsize::new(37));let healthy=||Ok(());
 let low=SettingAdmission::new(&counter,37,&healthy);assert!(prepare(source,&low).is_err());assert_eq!(low.take_operational_error().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_eq!(counter.load(Ordering::Acquire),37);
 let a=SettingAdmission::new(&counter,16*1024*1024,&healthy);drop(prepare(source,&a).unwrap());assert_eq!(counter.load(Ordering::Acquire),37);
}

struct NoSettings;
impl crate::SettingSyntaxProvider for NoSettings{
 fn setting(&self,_:&crate::Item)->Result<crate::SettingStatement,crate::Diagnostic>{panic!("fixture contains no setting")}
}
fn prepare_native(source:&str,a:&SettingAdmission<'_>)->io::Result<PreparedBodyLiteralSyntax>{
 let cleanup=a.reserve(source.len()*512+8192)?;
 let ast=crate::parse(source);assert!(ast.diagnostics.is_empty(),"{:?}",ast.diagnostics);
 crate::parse_body_items_with_admitted_literals(&ast.items[0].children,source,&|_|None,&NoSettings,a,cleanup)
}
#[test]
fn native_local_membership_normalization_preserves_written_ast_and_deferred_errors(){
 for rhs in ["list(1, 2)","list(outer())","list(\"value [1 + 2]\")","list(\"value [outer()]\")","list(\"bad [1 +]\")"]{
  let source=format!("/proc/p()\n    var/x = a in {rhs}\n    return x\n");
  let expected=body(&source);let counter=Arc::new(AtomicUsize::new(0));let healthy=||Ok(());
  let a=SettingAdmission::with_stack_allowance(&counter,32*1024*1024,1024*1024,&healthy);
  let prepared=prepare_native(&source,&a).unwrap();let(parsed,admission)=prepared.into_parts();
  assert_eq!(parsed,expected,"same local classifier/result for {rhs}");
  assert_eq!(parsed.diagnostics,expected.diagnostics,"no eager interpolation diagnostic for {rhs}");
  drop(expected);drop_body_literal_syntax(parsed,Some(admission));assert_eq!(counter.load(Ordering::Acquire),0);
 }
}
#[test]
fn native_membership_child_cancellation_never_publishes_different_normalization(){
 let source="/proc/p()\n    var/x = a in list(\"value [1 + 2]\")\n    return x\n";
 let counter=Arc::new(AtomicUsize::new(0));let before=crate::literal::literal_child_parses_for_test();
 let fail=||if crate::literal::literal_child_parses_for_test()>before{Err(io::Error::from_raw_os_error(1450))}else{Ok(())};
 let a=SettingAdmission::new(&counter,32*1024*1024,&fail);
 assert!(prepare_native(source,&a).is_err());assert_eq!(a.take_operational_error().unwrap().raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),0);
 let healthy=||Ok(());let retry=SettingAdmission::new(&counter,32*1024*1024,&healthy);
 let prepared=prepare_native(source,&retry).unwrap();let(parsed,admission)=prepared.into_parts();assert_eq!(parsed,body(source));
 drop_body_literal_syntax(parsed,Some(admission));assert_eq!(counter.load(Ordering::Acquire),0);
}
