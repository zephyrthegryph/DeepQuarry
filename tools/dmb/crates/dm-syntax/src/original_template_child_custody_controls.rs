//! Resource custody of the actual typed builder, never source/completeness authority.
use super::*;
use std::sync::atomic::Ordering;
fn prepared_builder(a:&crate::SettingAdmission<'_>,source:&str)->(OriginalTemplateBuilder<'static,'static>,String,usize){
 let prefix="\"outer [";let suffix="]tail\"";let raw=format!("{prefix}{source}{suffix}");let split=prefix.len()+source.len();
 let mut child=crate::parse_expression(source).expr.expect("actual shared parser child");let measured=crate::setting_prepare::prepare_body_measure(&child,a).unwrap();
 crate::shift_expression(&mut child,prefix.len());let mut tokens=crate::lex(source).tokens;for token in &mut tokens{token.span.start+=prefix.len();token.span.end+=prefix.len();}
 let mut b=OriginalTemplateBuilder::new(a).unwrap();
 b.push(crate::OriginalLiteralData::from_value_with_mode_using(prefix.into(),crate::OriginalTokenValue::InterpBegin("outer "),crate::OriginalStringMode::Normal,a).unwrap(),Span::new(0,prefix.len()),None,&[],a).unwrap();
 b.push(crate::OriginalLiteralData::from_value_with_mode_using(suffix.into(),crate::OriginalTokenValue::InterpEnd("tail"),crate::OriginalStringMode::Normal,a).unwrap(),Span::new(split,raw.len()),Some(child),&tokens,a).unwrap();
 (b,raw,measured.bytes)
}
fn containing_body(value:LiteralText,span:Span)->crate::ParsedBody{
 let source="/proc/p()\n    return 0\n";let ast=crate::parse(source);let mut body=crate::parse_body_items_with_context(&ast.items[0].children,source,&|_|None);
 body.statements[0].kind=crate::StatementKind::Return(Some(Expr{kind:ExprKind::Literal(value),span}));body
}
#[test]fn original_template_owns_actual_private_child_payload_through_last_alias_and_repeated_body_admission(){
 let fixed=crate::SettingChargeCounter::root_allocation_bytes();let counter=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&counter,32<<20,&||Ok(()));
 let source=format!("call({})","n".repeat(64*1024));let(b,raw,child_bytes)=prepared_builder(&a,&source);assert!(child_bytes>=64*1024);
 let value=b.finish(&raw,0,&a).unwrap();let span=Span::new(0,raw.len());
 let independent=match &value.0{Backing::Text(owner)=>owner.retention.get().unwrap().bytes(),_=>panic!("actual typed template")};
 assert!(independent>=child_bytes+value.raw_storage().capacity(),"template's own lease must include real incoming child payload in addition to its own raw buffer");
 let baseline=counter.load(Ordering::Acquire);let ptr=value.prepared_syntax_parts().unwrap().unwrap().unwrap().expressions.as_ptr();
 for _ in 0..2{let prepared=crate::prepare_body_literal_syntax(containing_body(value.clone(),span),a.reserve(2<<20).unwrap(),&a).unwrap();let(body,admission)=prepared.into_parts();crate::drop_body_literal_syntax(body,Some(admission));assert_eq!(counter.load(Ordering::Acquire),baseline,"independent child owner is not rebound to or duplicated by either enclosing body");}
 assert_eq!(value.prepared_syntax_parts().unwrap().unwrap().unwrap().expressions.as_ptr(),ptr);let alias=value.clone();drop(value);assert_eq!(counter.load(Ordering::Acquire),baseline);drop(alias);assert_eq!(counter.load(Ordering::Acquire),fixed);
}
#[test]fn original_template_completed_children_are_not_remeasured_or_grafted_to_foreign_parent_credit(){
 let fixed=crate::SettingChargeCounter::root_allocation_bytes();let counter=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&counter,32<<20,&||Ok(()));let(b,raw,_)=prepared_builder(&a,"call(alpha+beta)");let value=b.finish(&raw,0,&a).unwrap();
 let root=Expr{kind:ExprKind::Literal(value),span:Span::new(0,raw.len())};let baseline=counter.load(Ordering::Acquire);let measured=crate::setting_prepare::prepare_body_measure(&root,&a).unwrap();assert_eq!(measured.bytes,0);assert_eq!(measured.cleanup_nodes,1,"outer worklist still schedules this literal wrapper");
 let foreign=crate::SettingChargeCounter::try_new(fixed).unwrap();let b=crate::SettingAdmission::new(&foreign,32<<20,&||Ok(()));assert_eq!(crate::setting_prepare::prepare_body_measure(&root,&b).err().unwrap().kind(),io::ErrorKind::InvalidInput);assert_eq!(foreign.load(Ordering::Acquire),fixed);assert_eq!(counter.load(Ordering::Acquire),baseline);drop(root);assert_eq!(counter.load(Ordering::Acquire),fixed);
}
#[test]fn original_template_child_custody_early_and_last_attach_checkpoint_preserve_first_1450_and_refund(){
 use std::cell::Cell;
 let fixed=crate::SettingChargeCounter::root_allocation_bytes();let counter=crate::SettingChargeCounter::try_new(fixed).unwrap();let count=Cell::new(0usize);let stop=Cell::new(usize::MAX);
 let checkpoint=||{let next=count.get()+1;count.set(next);if next==stop.get(){Err(io::Error::from_raw_os_error(1450))}else{Ok(())}};
 let a=crate::SettingAdmission::new(&counter,32<<20,&checkpoint);let(b,raw,_)=prepared_builder(&a,"call(alpha+beta)");count.set(0);let value=b.finish(&raw,0,&a).unwrap();let calls=count.get();assert!(calls>4);drop(value);assert_eq!(counter.load(Ordering::Acquire),fixed);
 // The last successful finish checkpoint is in the real final child attach:
 // no checkpoint or fallible step follows it before returning LiteralText.
 for fail_at in[1,calls/2,calls]{stop.set(usize::MAX);let a=crate::SettingAdmission::new(&counter,32<<20,&checkpoint);let(b,raw,_)=prepared_builder(&a,"call(alpha+beta)");count.set(0);stop.set(fail_at);let error=b.finish(&raw,0,&a).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));stop.set(usize::MAX);assert_eq!(counter.load(Ordering::Acquire),fixed,"all real private AST is destroyed before its owned credit");}
}
#[test]fn original_template_child_payload_denial_never_publishes_owner_and_refunds_guarded_input(){
 let fixed=crate::SettingChargeCounter::root_allocation_bytes();let counter=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&counter,32<<20,&||Ok(()));let source=format!("call({})","n".repeat(64*1024));let(b,raw,child)=prepared_builder(&a,&source);let before=counter.load(Ordering::Acquire);
 let tight=crate::SettingAdmission::new(&counter,before+child/2,&||Ok(()));assert_eq!(b.finish(&raw,0,&tight).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert_eq!(counter.load(Ordering::Acquire),fixed);
}

#[test]fn original_template_nested_owner_retires_outer_without_unfunding_escaped_inner(){
 let fixed=crate::SettingChargeCounter::root_allocation_bytes();let counter=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&counter,32<<20,&||Ok(()));let source=format!("call({})","n".repeat(32*1024));let(b,raw,_)=prepared_builder(&a,&source);let inner=b.finish(&raw,0,&a).unwrap();let baseline=counter.load(Ordering::Acquire);let ptr=inner.prepared_syntax_parts().unwrap().unwrap().unwrap().expressions.as_ptr();
 let prefix="\"parent [";let suffix="]end\"";let outer_raw=format!("{prefix}{raw}{suffix}");let split=prefix.len()+raw.len();let mut outer=OriginalTemplateBuilder::new(&a).unwrap();
 outer.push(crate::OriginalLiteralData::from_value_with_mode_using(prefix.into(),crate::OriginalTokenValue::InterpBegin("parent "),crate::OriginalStringMode::Normal,&a).unwrap(),Span::new(0,prefix.len()),None,&[],&a).unwrap();
 outer.push(crate::OriginalLiteralData::from_value_with_mode_using(suffix.into(),crate::OriginalTokenValue::InterpEnd("end"),crate::OriginalStringMode::Normal,&a).unwrap(),Span::new(split,outer_raw.len()),Some(Expr{kind:ExprKind::Literal(inner.clone()),span:Span::new(prefix.len(),split)}),&[],&a).unwrap();
 let value=outer.finish(&outer_raw,0,&a).unwrap();let before=counter.load(Ordering::Acquire);assert!(before>baseline);drop(value);assert_eq!(counter.load(Ordering::Acquire),baseline,"outer quota never adopts, duplicates or releases the independent inner payload");assert_eq!(inner.prepared_syntax_parts().unwrap().unwrap().unwrap().expressions.as_ptr(),ptr);drop(inner);assert_eq!(counter.load(Ordering::Acquire),fixed);
}
