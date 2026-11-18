use super::*;
use crate::SettingChargeCounter;
use std::sync::{atomic::{Ordering}};
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
 let source="/proc/p()\n    return \"value [1 + 2]\"\n";let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let healthy=||Ok(());
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
 drop(alias);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes(),"last literal physical free releases the same source-free credit");
}
#[test]
fn body_interpolation_syntax_errors_stay_deferred_identical_to_owned_parser(){
 let source="/proc/p()\n    return \"bad [1 +]\"\n";let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let healthy=||Ok(());let a=SettingAdmission::new(&counter,16*1024*1024,&healthy);
 let prepared=prepare(source,&a).unwrap();let(parsed,admission)=prepared.into_parts();assert!(parsed.diagnostics.is_empty());
 let expected=body(source);assert_eq!(literal(&parsed).parts().unwrap_err(),literal(&expected).parts().unwrap_err());
 drop(expected);drop_body_literal_syntax(parsed,Some(admission));assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
}
#[test]
fn actual_mid_child_parser_io_leaves_no_published_body_or_cached_error_and_recovers(){
 let source="/proc/p()\n    return \"value [1 + 2]\"\n";let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let before=crate::literal::literal_child_parses_for_test();
 let failed=||if crate::literal::literal_child_parses_for_test()>before{Err(io::Error::from_raw_os_error(1450))}else{Ok(())};
 let a=SettingAdmission::new(&counter,16*1024*1024,&failed);
 assert!(prepare(source,&a).is_err());assert!(crate::literal::literal_child_parses_for_test()>before,"failure happened inside the real child parser");
 assert_eq!(a.take_operational_error().unwrap().raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 let healthy=||Ok(());let retry=SettingAdmission::new(&counter,16*1024*1024,&healthy);
 let result=prepare(source,&retry).unwrap();let(parsed,admission)=result.into_parts();assert_eq!(literal(&parsed).parts().unwrap().unwrap().expressions.len(),1);
 drop_body_literal_syntax(parsed,Some(admission));assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
}
#[test]
fn body_compatibility_cached_or_escaped_literal_owner_cannot_be_grafted(){
 let source="/proc/p()\n    return \"value [1 + 2]\"\n";
 for cached in[false,true]{
  let parsed=body(source);if cached{literal(&parsed).parts().unwrap();}
  let alias=literal(&parsed).clone();let before=alias.retained_parts().map(|r|r.map(|v|v.map(|p|p.expressions.as_ptr())));
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let healthy=||Ok(());let a=SettingAdmission::new(&counter,16*1024*1024,&healthy);let cleanup=a.reserve(source.len()*512+8192).unwrap();
  assert!(prepare_body_literal_syntax(parsed,cleanup,&a).is_err());assert_eq!(a.take_operational_error().unwrap().kind(),io::ErrorKind::InvalidInput);
  assert_eq!(alias.retained_parts().map(|r|r.map(|v|v.map(|p|p.expressions.as_ptr()))),before,"legacy live alias is never mutated or leased by native preparation");
  assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());drop(alias);
 }
}
#[test]
fn body_resource_refusal_is_actual_same_counter_and_fresh_input_retries(){
 let source="/proc/p()\n    return \"value [1 + 2]\"\n";let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap(); counter.add_soft_estimate(37);let healthy=||Ok(());
 let low=SettingAdmission::new(&counter,crate::SettingChargeCounter::root_allocation_bytes() + (37),&healthy);assert!(prepare(source,&low).is_err());assert_eq!(low.take_operational_error().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes() + (37));
 let a=SettingAdmission::new(&counter,16*1024*1024,&healthy);drop(prepare(source,&a).unwrap());assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes() + (37));
}

#[test]
fn body_failure_cleanup_reuses_only_same_counter_cleanup_bytes() {
 let source="/proc/p()\n    return value + value\n";
 let initial=64*1024;
 let base=crate::SettingChargeCounter::root_allocation_bytes();
 let counter=crate::SettingChargeCounter::try_new(base).unwrap();
 let high=std::cell::Cell::new(base);
 let poll=||{high.set(high.get().max(counter.load(Ordering::Acquire)));Ok(())};
 let a=SettingAdmission::new(&counter,1<<20,&poll);
 let prepared=prepare_body_literal_syntax(body(source),a.reserve(initial).unwrap(),&a).unwrap();
 let (parsed,admission)=prepared.into_parts();
 let final_bytes=admission.anchor.bytes();
 assert_eq!(counter.load(Ordering::Acquire),base+final_bytes);
 let max=high.get();
 assert!(max<base+initial+final_bytes,"old simultaneous cleanup and final grant would be denied");
 drop_body_literal_syntax(parsed,Some(admission));
 assert_eq!(counter.load(Ordering::Acquire),base);

 let healthy=||Ok(());
 // A checkpoint sample can miss a shorter-lived allocation between polls.
 // Use a strict bound that demonstrably refuses the old overlap instead.
 let tight=SettingAdmission::new(&counter,base+initial+final_bytes-1,&healthy);
 let prepared=prepare_body_literal_syntax(body(source),tight.reserve(initial).unwrap(),&tight).unwrap();
 let (parsed,admission)=prepared.into_parts();
 assert_eq!(admission.anchor.bytes(),final_bytes);
 drop_body_literal_syntax(parsed,Some(admission));
 assert_eq!(counter.load(Ordering::Acquire),base);

 let foreign=crate::SettingChargeCounter::try_new(base).unwrap();
 let donor=SettingAdmission::new(&foreign,1<<20,&healthy);
 let limited=SettingAdmission::new(&counter,base+final_bytes-1,&healthy);
 let error=prepare_body_literal_syntax(body(source),donor.reserve(initial).unwrap(),&limited).err().unwrap();
 assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);
 assert_eq!(counter.load(Ordering::Acquire),base);
 assert_eq!(foreign.load(Ordering::Acquire),base);
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
  let expected=body(&source);let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let healthy=||Ok(());
  let a=SettingAdmission::with_stack_allowance(&counter,32*1024*1024,1024*1024,&healthy);
  let prepared=prepare_native(&source,&a).unwrap();let(parsed,admission)=prepared.into_parts();
  assert_eq!(parsed,expected,"same local classifier/result for {rhs}");
  assert_eq!(parsed.diagnostics,expected.diagnostics,"no eager interpolation diagnostic for {rhs}");
  drop(expected);drop_body_literal_syntax(parsed,Some(admission));assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}
#[test]
fn native_membership_child_cancellation_never_publishes_different_normalization(){
 let source="/proc/p()\n    var/x = a in list(\"value [1 + 2]\")\n    return x\n";
 let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let before=crate::literal::literal_child_parses_for_test();
 let fail=||if crate::literal::literal_child_parses_for_test()>before{Err(io::Error::from_raw_os_error(1450))}else{Ok(())};
 let a=SettingAdmission::new(&counter,32*1024*1024,&fail);
 assert!(prepare_native(source,&a).is_err());assert_eq!(a.take_operational_error().unwrap().raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 let healthy=||Ok(());let retry=SettingAdmission::new(&counter,32*1024*1024,&healthy);
 let prepared=prepare_native(source,&retry).unwrap();let(parsed,admission)=prepared.into_parts();assert_eq!(parsed,body(source));
 drop_body_literal_syntax(parsed,Some(admission));assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
}

#[test]
fn body_peak_skips_fully_owned_template_children_and_keeps_foreign_and_first_io_refusal() {
 let fixed = crate::SettingChargeCounter::root_allocation_bytes();
 let counter = crate::SettingChargeCounter::try_new(fixed).unwrap();
 let a = SettingAdmission::new(&counter, 16 << 20, &|| Ok(()));
 let inner = r#""inner [1]""#;
 let prefix = r#""outer ["#;
 let suffix = r#"]tail""#;
 let raw = format!("{prefix}{inner}{suffix}");
 let split = prefix.len() + inner.len();
 let data = |raw: &str, value| {
  crate::OriginalLiteralData::from_value_with_mode_using(
   raw.to_owned(), value, crate::OriginalStringMode::Normal, &a,
  ).unwrap()
 };
 let mut builder = crate::literal::OriginalTemplateBuilder::new(&a).unwrap();
 builder.push(
  data(prefix, crate::OriginalTokenValue::InterpBegin("outer ")),
  crate::Span::new(0, prefix.len()), None, &[], &a,
 ).unwrap();
 let child = Expr {
  span: crate::Span::new(prefix.len(), split),
  kind: ExprKind::Literal(crate::LiteralText::at(inner.to_owned(), prefix.len())),
 };
 builder.push(
  data(suffix, crate::OriginalTokenValue::InterpEnd("tail")),
  crate::Span::new(split, raw.len()), Some(child), &[], &a,
 ).unwrap();
 let value = builder.finish(&raw, 0, &a).unwrap();
 let children = value.prepared_syntax_parts().unwrap().unwrap().unwrap().expressions.as_ptr();
 let root = Expr { kind: ExprKind::Literal(value), span: crate::Span::new(0, raw.len()) };
 let prior_parses = crate::literal::literal_child_parses_for_test();
 let actual = input_peak(&root, &a).unwrap();
 assert!(input_peak_with_contract(&root,&a).unwrap().1,"independent Original templates retain the old final aggregate contract");
 assert_eq!(actual,0,"complete typed builder prepared and owns the nested literal before escape");
 assert_eq!(crate::literal::literal_child_parses_for_test(), prior_parses);

 let foreign_counter = crate::SettingChargeCounter::try_new(fixed).unwrap();
 let foreign = SettingAdmission::new(&foreign_counter, 16 << 20, &|| Ok(()));
 assert_eq!(input_peak(&root, &foreign).unwrap_err().kind(), io::ErrorKind::InvalidInput);
 assert_eq!(foreign_counter.load(Ordering::Acquire), fixed);

 let failed = SettingAdmission::new(&counter, 16 << 20, &|| Err(io::Error::from_raw_os_error(1450)));
 assert!(input_peak(&root, &failed).is_err());
 assert_eq!(failed.take_operational_error().unwrap().raw_os_error(), Some(1450));

 let permit = a.reserve(actual).unwrap();
 crate::setting_prepare::prepare_body_measure(&root, &a).unwrap();
 assert_eq!(crate::literal::literal_child_parses_for_test() - prior_parses, 0,"body never reparses an already owned child");
 let ExprKind::Literal(value) = &root.kind else { panic!("actual Original template"); };
 assert_eq!(value.prepared_syntax_parts().unwrap().unwrap().unwrap().expressions.as_ptr(), children);
 drop(root);
 drop(permit);
 assert_eq!(counter.load(Ordering::Acquire), fixed);
}

#[test]
fn body_measured_cleanup_retires_only_unused_startup_before_final_payload_growth(){
 let source=format!("/proc/p()\n    return {}\n", "x".repeat(64*1024));
 let base=crate::SettingChargeCounter::root_allocation_bytes();
 let counter=crate::SettingChargeCounter::try_new(base).unwrap();let healthy=||Ok(());
 let initial=1024*1024;let limit=base+initial+16*1024;
 let a=SettingAdmission::new(&counter,limit,&healthy);
 let prepared=prepare_body_literal_syntax(body(&source),a.reserve(initial).unwrap(),&a).unwrap();
 let(parsed,admission)=prepared.into_parts();
 assert!(admission.anchor.bytes()>64*1024);
 assert!(initial+admission.anchor.bytes()>limit-base,"the superseded startup/final overlap would not fit");
 assert_eq!(counter.load(Ordering::Acquire),base+admission.anchor.bytes());
 drop_body_literal_syntax(parsed,Some(admission));assert_eq!(counter.load(Ordering::Acquire),base);
 // Retiring startup-only headroom does not make an oversized final payload fit.
 let initial=8192;let low=SettingAdmission::new(&counter,base+initial+16*1024,&healthy);
 let error=prepare_body_literal_syntax(body(&source),low.reserve(initial).unwrap(),&low).err().unwrap();
 assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);assert_eq!(counter.load(Ordering::Acquire),base);
}
#[test]
fn body_cleanup_handoff_split_and_post_retirement_first_io_keep_original_failure_and_refund(){
 use std::cell::{Cell,RefCell};
 let source=format!("/proc/p()\n    return {}\n", "x".repeat(64*1024));
 let base=crate::SettingChargeCounter::root_allocation_bytes();let initial=1024*1024;
 let counter=crate::SettingChargeCounter::try_new(base).unwrap();let armed=Cell::new(false);let trace=RefCell::new(Vec::new());
 let healthy=||{if armed.get(){trace.borrow_mut().push(counter.load(Ordering::Acquire));}Ok(())};
 let a=SettingAdmission::new(&counter,4*1024*1024,&healthy);let cleanup=a.reserve(initial).unwrap();armed.set(true);
 drop(prepare_body_literal_syntax(body(&source),cleanup,&a).unwrap());
 assert_eq!(counter.load(Ordering::Acquire),base);
 let after_retirement=trace.borrow().iter().position(|used|*used<base+initial).expect("first grow checkpoint follows retirement");
 assert!(after_retirement>0);drop(a);
 // The immediately previous checkpoint is the split: it must retain the old
 // complete guarantee on failure. The next is grow with measured cleanup held.
 for stop in [after_retirement-1,after_retirement]{
  let armed=Cell::new(false);let calls=Cell::new(0);let fault_usage=Cell::new(0);
  let fail=||{if !armed.get(){return Ok(())}let n=calls.get();calls.set(n+1);if n==stop{fault_usage.set(counter.load(Ordering::Acquire));Err(io::Error::from_raw_os_error(1450))}else{Ok(())}};
  let a=SettingAdmission::new(&counter,4*1024*1024,&fail);let cleanup=a.reserve(initial).unwrap();armed.set(true);
  let status=prepare_body_literal_syntax(body(&source),cleanup,&a).err().unwrap();
  // grow keeps the real first payload in the existing admission latch;
  // split returns that same payload directly. The host observes either route.
  let error=a.take_operational_error().unwrap_or(status);
  assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(calls.get(),stop+1,"cleanup never polls after first stop");
  if stop==after_retirement-1{assert!(fault_usage.get()>=base+initial)}else{assert!(fault_usage.get()<base+initial)}
  assert_eq!(counter.load(Ordering::Acquire),base);
 }
}

#[test]
fn delete_operand_literal_children_reuse_existing_admission_and_refund(){
 let source="/proc/p()\n    del(\"value [1 + 2]\")\n    return 0\n";let used=SettingChargeCounter::try_new(SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::with_stack_allowance(&used,32<<20,1<<20,&||Ok(()));
 let prepared=prepare(source,&a).unwrap();let(parsed,admission)=prepared.into_parts();let StatementKind::Delete(Expr{kind:ExprKind::Group(value),..})=&parsed.statements[0].kind else{panic!("same canonical grouped delete operand")};let ExprKind::Literal(literal)=&value.kind else{panic!("actual literal")};assert_eq!(literal.parts().unwrap().unwrap().expressions.len(),1);
 drop_body_literal_syntax(parsed,Some(admission));assert_eq!(used.load(Ordering::Acquire),SettingChargeCounter::root_allocation_bytes());
 let tiny=SettingAdmission::new(&used,SettingChargeCounter::root_allocation_bytes(),&||Ok(()));let error=prepare(source,&tiny).err().expect("actual cleanup/resource reservation must refuse");assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),SettingChargeCounter::root_allocation_bytes());
}

#[test]
fn body_cleanup_uses_disjoint_native_worklists_and_refunds_after_physical_drop(){
 for source in ["/proc/p()\n    return call(a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p)\n",
                "/proc/p()\n    call(a+b,c+d)\n    call(e+f,g+h)\n    return call(i+j,k+l)\n",
                "/proc/p()\n    if(a)\n        if(b)\n            if(c)\n                return call(d,e,f)\n"]{
  let fixed=SettingChargeCounter::root_allocation_bytes();let counter=SettingChargeCounter::try_new(fixed).unwrap();
  let a=SettingAdmission::new(&counter,32<<20,&||Ok(()));
  let expected=body(source);
  let (payload,statements,expressions,all_expressions)={let collected=collect(&expected,&a).unwrap();let mut bytes=collected.bytes;let mut expressions=0usize;let mut all_expressions=0;
   for root in collected.roots.as_slice(){let measured=crate::setting_prepare::prepare_body_measure(root,&a).unwrap();bytes+=measured.bytes;expressions=expressions.max(measured.cleanup_nodes);all_expressions+=measured.nodes;}
   (bytes,collected.statements,expressions,all_expressions)
  };
  assert!(statements>0&&expressions>0&&all_expressions>expressions,"real leaves are payload but never enter cleanup worklists");
  assert_eq!(counter.load(Ordering::Acquire),fixed,"measurement scratch physically retired");
  let disjoint=4*(statements*size_of::<Vec<Statement>>()+expressions*(size_of::<Expr>()+size_of::<SharedSettingRetention>()));
  let crossed=4*(statements+all_expressions)*(size_of::<Statement>()+size_of::<Expr>()+size_of::<SharedSettingRetention>());
  assert!(disjoint<crossed);
  let prepared=prepare(source,&a).unwrap();let(parsed,admission)=prepared.into_parts();assert_eq!(parsed,expected);
  let retained=payload+disjoint+crate::setting_expression::root_storage_envelope();
  assert_eq!(counter.load(Ordering::Acquire),fixed+retained,"one measured payload plus its actual cleanup worklists");
  // The retained admission can outlive its caller; no early refund is issued.
  drop(expected);drop_body_literal_syntax(parsed,Some(admission));assert_eq!(counter.load(Ordering::Acquire),fixed);
 }
}

#[path="body_cleanup_startup_geometry_tests.rs"]
mod startup_geometry_controls;

#[test]fn actual_escaped_literal_roots_share_one_serialized_cleanup_peak_and_refund(){
 let fixed=SettingChargeCounter::root_allocation_bytes();let counter=SettingChargeCounter::try_new(fixed).unwrap();let a=SettingAdmission::new(&counter,64<<20,&||Ok(()));
 for concurrent_body in[false,true]{
  let source="/proc/p()\n    return \"first [call(1+2)]\"\n    return \"second [call(3+4)]\"\n";
  let prepared=prepare_native(source,&a).unwrap();let(body,admission)=prepared.into_parts();let aliases=body.statements.iter().map(|statement|{let StatementKind::Return(Some(root))=&statement.kind else{panic!("actual return")};let ExprKind::Literal(value)=&root.kind else{panic!("actual template")};value.clone()}).collect::<Vec<_>>();assert_eq!(aliases.len(),2);
  let barrier=std::sync::Arc::new(std::sync::Barrier::new(if concurrent_body{3}else{2}));
  if !concurrent_body{drop_body_literal_syntax(body,Some(admission));counter.reset_cleanup_peak();let mut threads=Vec::new();for alias in aliases{let barrier=barrier.clone();threads.push(std::thread::spawn(move||{barrier.wait();drop(alias)}));}for thread in threads{thread.join().unwrap();}}
  else{counter.reset_cleanup_peak();let mut threads=Vec::new();for alias in aliases{let barrier=barrier.clone();threads.push(std::thread::spawn(move||{barrier.wait();drop(alias)}));}let gate=barrier.clone();threads.push(std::thread::spawn(move||{gate.wait();drop_body_literal_syntax(body,Some(admission))}));for thread in threads{thread.join().unwrap();}}
  assert_eq!(counter.cleanup_activity(),(0,1));assert_eq!(counter.load(Ordering::Acquire),fixed);
 }
}
#[test]fn actual_cleanup_gate_poison_unwind_recovers_without_polling_or_credit_loss(){
 let fixed=SettingChargeCounter::root_allocation_bytes();let counter=SettingChargeCounter::try_new(fixed).unwrap();let a=SettingAdmission::new(&counter,32<<20,&||Ok(()));
 let result=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||{let _guard=counter.cleanup_guard();panic!("actual cleanup gate unwind");}));assert!(result.is_err());
 let source="/proc/p()\n    return call(alpha,beta)\n";let prepared=prepare_native(source,&a).unwrap();let(body,admission)=prepared.into_parts();counter.reset_cleanup_peak();drop_body_literal_syntax(body,Some(admission));assert_eq!(counter.cleanup_activity(),(0,1));assert_eq!(counter.load(Ordering::Acquire),fixed);
}

#[test]fn unqualified_body_keeps_original_template_aggregate_cleanup_despite_complete_private_custody(){
 let fixed=crate::SettingChargeCounter::root_allocation_bytes();let counter=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=SettingAdmission::new(&counter,16<<20,&||Ok(()));let raw="\"outer[]tail\"";let mut builder=crate::literal::OriginalTemplateBuilder::new(&a).unwrap();
 for(text,value,span)in[("\"outer[",crate::OriginalTokenValue::InterpBegin("outer"),crate::Span::new(0,7)),("]tail\"",crate::OriginalTokenValue::InterpEnd("tail"),crate::Span::new(7,13))]{builder.push(crate::OriginalLiteralData::from_value_with_mode_using(text.into(),value,crate::OriginalStringMode::Normal,&a).unwrap(),span,None,&[],&a).unwrap();}
 let value=builder.finish(raw,0,&a).unwrap();let source="/proc/p()\n    return 0\n    return 0\n";let ast=crate::parse(source);let mut body=crate::parse_body_items_with_context(&ast.items[0].children,source,&|_|None);assert!(body.original_grammar.is_none());
 for statement in &mut body.statements{statement.kind=crate::StatementKind::Return(Some(Expr{kind:ExprKind::Literal(value.clone()),span:crate::Span::new(0,raw.len())}));}
 let collected=collect(&body,&a).unwrap();let bytes=collected.bytes;let statements=collected.statements;drop(collected);let slot=4*(std::mem::size_of::<Expr>()+std::mem::size_of::<SharedSettingRetention>());let expected=bytes+statements*4*std::mem::size_of::<Vec<crate::Statement>>()+2*slot+crate::setting_expression::root_storage_envelope();
 let prepared=prepare_body_literal_syntax(body,a.reserve(2<<20).unwrap(),&a).unwrap();let(body,admission)=prepared.into_parts();assert_eq!(admission.anchor.bytes(),expected,"missing native grammar cannot convert the previous SUM of two template wrappers to MAX");drop_body_literal_syntax(body,Some(admission));drop(value);assert_eq!(counter.load(Ordering::Acquire),fixed);
}

#[test]
fn donor_statement_cleanup_physically_reuses_wide_parser_vectors_under_same_tight_cap(){
 let mut source=String::from("/proc/p()\n");for _ in 0..1000{source.push_str("    return 1\n");}
 let parsed=body(&source);assert!(parsed.diagnostics.is_empty());assert_eq!(parsed.statements.len(),1000);
 let counter=SettingChargeCounter::try_new(SettingChargeCounter::root_allocation_bytes()).unwrap();let fixed=SettingChargeCounter::root_allocation_bytes();let healthy=||Ok(());let a=SettingAdmission::new(&counter,1<<20,&healthy);
 let c=collect(&parsed,&a).unwrap();let old=c.statements*4*size_of::<Statement>();let new=c.statements*4*size_of::<Vec<Statement>>();let payload=c.bytes;drop(c);
 assert!(old+payload>1<<20,"old full-Statement scratch cannot fit this unchanged cap");assert!(new+payload<1<<20);
 let prepared=prepare_body_literal_syntax(parsed,a.reserve(new+8192).unwrap(),&a).unwrap();let(parsed,credit)=prepared.into_parts();let held=counter.load(Ordering::Acquire);assert!(held<=1<<20);assert!(held>=fixed+payload+new);
 drop_body_literal_syntax(parsed,Some(credit));assert_eq!(DONOR_QUEUE_PEAK.with(|p|p.get()),1,"wide root donor is moved once, never flattened/copied");assert_eq!(counter.load(Ordering::Acquire),fixed);
}
#[test]
fn donor_statement_cleanup_keeps_empty_switch_vectors_out_of_queue_and_all_branches_stack_safe(){
 let mut source=String::from("/proc/p()\n    switch(value)\n");for i in 0..128{source.push_str(&format!("        if({i})\n"));}source.push_str("    return 1\n");
 let parsed=body(&source);assert!(parsed.diagnostics.is_empty(),"{:?}",parsed.diagnostics);let StatementKind::Switch{cases,else_branch,..}=&parsed.statements[0].kind else{panic!("real switch")};assert_eq!(cases.len(),128);assert!(cases.iter().all(|c|c.body.is_empty())&&else_branch.is_empty());
 let counter=SettingChargeCounter::try_new(SettingChargeCounter::root_allocation_bytes()).unwrap();let fixed=SettingChargeCounter::root_allocation_bytes();let a=SettingAdmission::new(&counter,8<<20,&||Ok(()));let prepared=prepare_body_literal_syntax(parsed,a.reserve(1<<20).unwrap(),&a).unwrap();drop(prepared);assert_eq!(DONOR_QUEUE_PEAK.with(|p|p.get()),1);assert_eq!(counter.load(Ordering::Acquire),fixed);
 let mut branch=body("/proc/p()\n    return 1\n").statements.pop().unwrap();for _ in 0..2048{branch=Statement{kind:StatementKind::Label{name:String::new(),body:vec![branch]},span:crate::Span::new(0,0),header_span:crate::Span::new(0,0),raw_header:String::new()};}
 let mut deep=body("/proc/p()\n    return 1\n");deep.statements=vec![branch];let prepared=prepare_body_literal_syntax(deep,a.reserve(1<<20).unwrap(),&a).unwrap();drop(prepared);assert_eq!(DONOR_QUEUE_PEAK.with(|p|p.get()),1);assert_eq!(counter.load(Ordering::Acquire),fixed);
}
#[test]
fn donor_statement_cleanup_first_io_and_checkpoint_panic_release_payload_before_credit(){
 for panic_mode in [false,true]{
  let counter=SettingChargeCounter::try_new(SettingChargeCounter::root_allocation_bytes()).unwrap();let fixed=SettingChargeCounter::root_allocation_bytes();let calls=std::cell::Cell::new(0usize);
  let checkpoint=||{calls.set(calls.get()+1);if calls.get()==2{if panic_mode{panic!("actual body preflight checkpoint")}return Err(io::Error::from_raw_os_error(1450))}Ok(())};
  let a=SettingAdmission::new(&counter,8<<20,&checkpoint);let parsed=body("/proc/p()\n    if(value)\n        return 1\n    else\n        return 2\n");let cleanup=a.reserve(1<<20).unwrap();
  let result=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||prepare_body_literal_syntax(parsed,cleanup,&a)));
  if panic_mode{assert!(result.is_err());}else{assert_eq!(result.unwrap().err().unwrap().raw_os_error().or_else(||a.take_operational_error().and_then(|e|e.raw_os_error())),Some(1450));}
  assert_eq!(counter.load(Ordering::Acquire),fixed);let retry=SettingAdmission::new(&counter,8<<20,&||Ok(()));let done=prepare("/proc/p()\n    return 1\n",&retry).unwrap();drop(done);assert_eq!(counter.load(Ordering::Acquire),fixed);
 }
}
