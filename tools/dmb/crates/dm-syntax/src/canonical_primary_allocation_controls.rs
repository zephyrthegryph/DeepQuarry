use super::*;
use crate::{SettingAdmission,SettingChargeCounter,SharedParameterSignature,Span,TokenWindow};
use std::{cell::Cell,sync::atomic::Ordering};
fn input(source:&str,a:&SettingAdmission<'_>)->(crate::DeclarationSkeleton,SharedParameterSignature){
 let ast=crate::parse_declaration_skeleton(source);let header=ast.items[0].header_span;
 let lease=a.reserve((header.end-header.start)*512+8192+SharedParameterSignature::retention_envelope()).unwrap();
 let signature=crate::parameter_signature_original_with_default_roots(source,&ast.tokens,header,0,&mut None);
 (ast,SharedParameterSignature::retained_using(signature,lease,a).unwrap())
}
fn item_bytes(item:&crate::Item)->usize{item.header.capacity()+item.children.capacity()*std::mem::size_of::<crate::Item>()+item.children.iter().map(item_bytes).sum::<usize>()}
#[test]fn canonical_primary_allocation_only_preserves_same_semantic_none_and_exact_item_payload(){
 for source in ["/proc/p(v)\n    if(v)\n        return v\n    else\n        return null\n","/proc/p(v){var/a=1,b=2;return v}","/datum/example/p(v){return new /datum/value}","/proc/p(v)\n    var/list/x=list(1,2)\n    return x\n"]{
  let used=SettingChargeCounter::try_new(SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,4<<20,&||Ok(()));let(ast,parameters)=input(source,&a);let baseline=used.load(Ordering::Acquire);let span=ast.items[0].span;
  let(expected,expected_complete)=parse_proc_with_native_consumption_from_window(source,span,TokenWindow::from_slice(&ast.tokens),0,None,true,Some(parameters.clone()),None);let expected=expected.unwrap();
  let credit;let mut owner=parse_proc_with_native_consumption_from_window_admitted(source,span,TokenWindow::from_slice(&ast.tokens),0,None,true,Some(parameters.clone()),None,&a).unwrap();assert_eq!(owner.complete(),expected_complete);let actual=owner.take_result().unwrap();credit=owner.into_credit();
  assert_eq!(actual.item,expected.item);assert_eq!(actual.opening_parenthesis,expected.opening_parenthesis);assert_eq!(actual.parameters,expected.parameters);assert!(matches!(&actual.parameters,crate::ProcedureParameters::Shared(p)if p.same_owner(&parameters)));assert_eq!(crate::parse_proc_body(&actual.item),crate::parse_proc_body(&expected.item));assert_eq!(credit.bytes(),item_bytes(&actual.item));assert_eq!(used.load(Ordering::Acquire),baseline+credit.bytes());drop(actual);drop(credit);assert_eq!(used.load(Ordering::Acquire),baseline);
 }
}
#[test]fn canonical_primary_rejection_retains_only_actual_diagnostic_payload_and_retires_scratch(){
 let source="/proc/p(v)\n    return\n        value\n";let used=SettingChargeCounter::try_new(SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,4<<20,&||Ok(()));let(ast,parameters)=input(source,&a);let baseline=used.load(Ordering::Acquire);
 let (expected,expected_complete)=parse_proc_with_native_consumption_from_window(source,ast.items[0].span,TokenWindow::from_slice(&ast.tokens),0,None,true,Some(parameters.clone()),None);let expected=expected.err().expect("same unowned primary parser must reject this unchanged fixture");assert!(!expected.message.is_empty(),"actual unowned diagnostic must explain the rejection");
 let credit;let mut owner=parse_proc_with_native_consumption_from_window_admitted(source,ast.items[0].span,TokenWindow::from_slice(&ast.tokens),0,None,true,Some(parameters.clone()),None,&a).unwrap();assert_eq!(owner.complete(),expected_complete);let actual=owner.take_result().err().expect("same admitted primary parser must reject the unchanged fixture");credit=owner.into_credit();assert_eq!(credit.bytes(),actual.message.capacity());assert_eq!(actual,expected,"same actual unowned parser diagnostic kind/span/message");assert_eq!(used.load(Ordering::Acquire),baseline+actual.message.capacity());drop(actual);drop(credit);assert_eq!(used.load(Ordering::Acquire),baseline);
}
#[test]fn canonical_primary_allocation_preserves_actual_first_io_hard_refusal_and_same_input_retry(){
 let source="/proc/p(v)\n    if(v)\n        return v\n    return null\n";let used=SettingChargeCounter::try_new(SettingChargeCounter::root_allocation_bytes()).unwrap();let healthy=SettingAdmission::new(&used,4<<20,&||Ok(()));let(ast,parameters)=input(source,&healthy);let base=used.load(Ordering::Acquire);let calls=Cell::new(0usize);let count=||{calls.set(calls.get()+1);Ok(())};let a=SettingAdmission::new(&used,4<<20,&count);let output=parse_proc_with_native_consumption_from_window_admitted(source,ast.items[0].span,TokenWindow::from_slice(&ast.tokens),0,None,true,Some(parameters.clone()),None,&a).unwrap();drop(output);assert_eq!(used.load(Ordering::Acquire),base);let total=calls.get();assert!(total>8);
 for stop in [1,total/2,total]{calls.set(0);let fail=||{calls.set(calls.get()+1);if calls.get()==stop{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}};let a=SettingAdmission::new(&used,4<<20,&fail);let actual=parse_proc_with_native_consumption_from_window_admitted(source,ast.items[0].span,TokenWindow::from_slice(&ast.tokens),0,None,true,Some(parameters.clone()),None,&a).err().expect("actual checkpoint failure");assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),base);}
 let denied=SettingAdmission::new(&used,base,&||Ok(()));assert_eq!(parse_proc_with_native_consumption_from_window_admitted(source,ast.items[0].span,TokenWindow::from_slice(&ast.tokens),0,None,true,Some(parameters.clone()),None,&denied).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),base);
 let fresh=SettingAdmission::new(&used,4<<20,&||Ok(()));let output=parse_proc_with_native_consumption_from_window_admitted(source,ast.items[0].span,TokenWindow::from_slice(&ast.tokens),0,None,true,Some(parameters),None,&fresh).unwrap();assert!(output.complete());drop(output);
}
#[test]fn canonical_primary_layout_uses_body_window_not_whole_translation_unit_bytes(){
 let mut source=String::from("// ");source.extend(std::iter::repeat_n('x',1<<20));source.push_str("\n/proc/p(v)\n    return v\n");let used=SettingChargeCounter::try_new(SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,4<<20,&||Ok(()));let(ast,parameters)=input(&source,&a);let base=used.load(Ordering::Acquire);let bounded=SettingAdmission::new(&used,base+(128<<10),&||Ok(()));let output=parse_proc_with_native_consumption_from_window_admitted(&source,ast.items[0].span,TokenWindow::from_slice(&ast.tokens),0,None,true,Some(parameters.clone()),None,&bounded).unwrap();assert!(output.complete());drop(output);assert_eq!(used.load(Ordering::Acquire),base);
}

#[test]
fn canonical_primary_panic_foreign_owner_and_transferred_credit_keep_exact_drop_custody(){
 let source="/proc/p(v)\n    if(v)\n        return v\n    return null\n";
 let used=SettingChargeCounter::try_new(SettingChargeCounter::root_allocation_bytes()).unwrap();
 let healthy=SettingAdmission::new(&used,4<<20,&||Ok(()));
 let(ast,parameters)=input(source,&healthy);let span=ast.items[0].span;let base=used.load(Ordering::Acquire);
 let foreign=SettingChargeCounter::try_new(SettingChargeCounter::root_allocation_bytes()).unwrap();
 let other=SettingAdmission::new(&foreign,4<<20,&||Ok(()));
 for signature in [None,Some(parameters.clone())]{
  let error=parse_proc_with_native_consumption_from_window_admitted(source,span,TokenWindow::from_slice(&ast.tokens),0,None,true,signature,None,&other).err().expect("missing or foreign shared owner must refuse before storage");
  assert_eq!(error.kind(),std::io::ErrorKind::InvalidInput);
  assert_eq!(used.load(Ordering::Acquire),base);
  assert_eq!(foreign.load(Ordering::Acquire),SettingChargeCounter::root_allocation_bytes());
 }
 let calls=Cell::new(0usize);let count=||{calls.set(calls.get()+1);Ok(())};
 let counted=SettingAdmission::new(&used,4<<20,&count);
 drop(parse_proc_with_native_consumption_from_window_admitted(source,span,TokenWindow::from_slice(&ast.tokens),0,None,true,Some(parameters.clone()),None,&counted).unwrap());
 assert_eq!(used.load(Ordering::Acquire),base);let midpoint=calls.get()/2;assert!(midpoint>1);calls.set(0);
 let panic_checkpoint=||{calls.set(calls.get()+1);assert_ne!(calls.get(),midpoint,"intentional actual parser checkpoint unwind");Ok(())};
 let panicking=SettingAdmission::new(&used,4<<20,&panic_checkpoint);
 let unwound=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||{
  let _output=parse_proc_with_native_consumption_from_window_admitted(source,span,TokenWindow::from_slice(&ast.tokens),0,None,true,Some(parameters.clone()),None,&panicking).unwrap();
 }));
 assert!(unwound.is_err());assert_eq!(calls.get(),midpoint);assert_eq!(used.load(Ordering::Acquire),base,"all partially constructed Items and scratch unwind before their leases");
 let output=parse_proc_with_native_consumption_from_window_admitted(source,span,TokenWindow::from_slice(&ast.tokens),0,None,true,Some(parameters.clone()),None,&healthy).unwrap();
 assert!(used.load(Ordering::Acquire)>base);
 let unwound=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||{let _credit=output.into_credit();}));
 assert!(unwound.is_err(),"cannot detach credit while the wrapper still owns its result");assert_eq!(used.load(Ordering::Acquire),base);
 let credit;let mut output=parse_proc_with_native_consumption_from_window_admitted(source,span,TokenWindow::from_slice(&ast.tokens),0,None,true,Some(parameters.clone()),None,&healthy).unwrap();
 let actual=output.take_result().unwrap();credit=output.into_credit();let retained=item_bytes(&actual.item);assert_eq!(credit.bytes(),retained);
 drop(actual);assert_eq!(used.load(Ordering::Acquire),base+retained,"transferred credit remains caller-owned after result destruction");
 drop(credit);assert_eq!(used.load(Ordering::Acquire),base);
 drop(parameters);assert_eq!(used.load(Ordering::Acquire),SettingChargeCounter::root_allocation_bytes());
}

#[test]
fn canonical_primary_static_header_and_token_boundary_rejections_retain_only_funded_diagnostic(){
 let issued_source="/proc/p(v)\n    return v\n";
 let used=SettingChargeCounter::try_new(SettingChargeCounter::root_allocation_bytes()).unwrap();
 let a=SettingAdmission::new(&used,4<<20,&||Ok(()));let(_,parameters)=input(issued_source,&a);let baseline=used.load(Ordering::Acquire);
 let wrong_header="/proc/longer_name(v)\n    return v\n";let wrong_boundary="proc/p(v)\n    return v\n";
 for(source,broken_boundary,expected)in[(wrong_header,false,"preissued parameter metadata belongs to another actual header"),(wrong_boundary,true,"original procedure token boundaries differ")]{
  let ast=crate::parse_declaration_skeleton(source);assert!(ast.diagnostics.is_empty(),"{:?}",ast.diagnostics);let mut span=ast.items[0].span;
  if broken_boundary{assert_eq!(span.start,0);assert!(ast.tokens.iter().any(|token|token.span.start==0&&token.span.end>1),"actual first primary token must straddle the deliberately wrong boundary");span.start+=1;}
  let credit;let mut owner=parse_proc_with_native_consumption_from_window_admitted(source,span,TokenWindow::from_slice(&ast.tokens),0,None,true,Some(parameters.clone()),None,&a).unwrap();
  let actual=owner.take_result().err().expect("actual canonical static rejection");credit=owner.into_credit();
  assert_eq!(actual.message,expected);assert_eq!(actual.kind,crate::DiagnosticKind::Unsupported);
  assert_eq!(credit.bytes(),actual.message.capacity());assert_eq!(used.load(Ordering::Acquire),baseline+credit.bytes());
  drop(actual);drop(credit);assert_eq!(used.load(Ordering::Acquire),baseline);
 }
 // The boundary diagnostic is produced before layout scratch exists. Exactly
 // the existing Storage initial reserve leaves no room for its message copy.
 let ast=crate::parse_declaration_skeleton(wrong_boundary);let span=Span::new(1,ast.items[0].span.end);
 let denied=SettingAdmission::new(&used,baseline+4096,&||Ok(()));
 let actual=parse_proc_with_native_consumption_from_window_admitted(wrong_boundary,span,TokenWindow::from_slice(&ast.tokens),0,None,true,Some(parameters.clone()),None,&denied).err().expect("static diagnostic copy must be admitted before allocation");
 assert_eq!(actual.kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),baseline);
 drop(parameters);assert_eq!(used.load(Ordering::Acquire),SettingChargeCounter::root_allocation_bytes());
}

fn large_canonical_phase_source()->String{
 let mut source=String::from("/proc/generated_native_allocation()\n");
 for index in 0..600{source.push_str(&format!("    consume(row_{index})\n"));}
 source
}
#[test]
fn canonical_primary_large_body_retires_layout_before_items_at_same_one_mib_cap(){
 let source=large_canonical_phase_source();let used=SettingChargeCounter::try_new(SettingChargeCounter::root_allocation_bytes()).unwrap();let healthy=SettingAdmission::new(&used,4<<20,&||Ok(()));let(ast,parameters)=input(&source,&healthy);let baseline=used.load(Ordering::Acquire);let span=ast.items[0].span;
 let(expected,expected_complete)=parse_proc_with_native_consumption_from_window(&source,span,TokenWindow::from_slice(&ast.tokens),0,None,true,Some(parameters.clone()),None);let expected=expected.unwrap();assert!(expected_complete);assert_eq!(expected.item.children.len(),600);
 let peak=Cell::new(baseline);let retired_before_items=Cell::new(false);let poll=||{let actual=used.load(Ordering::Acquire);peak.set(peak.get().max(actual));if peak.get()>baseline+(512<<10)&&actual<baseline+(128<<10){retired_before_items.set(true);}Ok(())};let bounded=SettingAdmission::new(&used,baseline+(1<<20),&poll);
 let credit;let mut owner=parse_proc_with_native_consumption_from_window_admitted(&source,span,TokenWindow::from_slice(&ast.tokens),0,None,true,Some(parameters.clone()),None,&bounded).unwrap();assert!(owner.complete());let escaped=owner.take_result().unwrap();credit=owner.into_credit();
 assert_eq!(escaped.item,expected.item,"same existing producer, tokens, headers and child order");assert!(matches!(&escaped.parameters,crate::ProcedureParameters::Shared(actual)if actual.same_owner(&parameters)));
 assert_eq!(credit.bytes(),item_bytes(&escaped.item));assert_eq!(used.load(Ordering::Acquire),baseline+credit.bytes());assert!(peak.get()<=baseline+(1<<20));assert!(retired_before_items.get(),"actual large layout grant retires before final600-Item payload (itself over128KiB) is built");
 let held=credit.bytes();drop(escaped);assert_eq!(used.load(Ordering::Acquire),baseline+held,"caller still owns the escaped payload's exact allocation lease");drop(credit);assert_eq!(used.load(Ordering::Acquire),baseline);drop(expected);drop(parameters);assert_eq!(used.load(Ordering::Acquire),SettingChargeCounter::root_allocation_bytes());
}
#[test]
fn canonical_primary_large_phase_retirement_preserves_quota_first_io_cancel_and_retry(){
 let source=large_canonical_phase_source();let used=SettingChargeCounter::try_new(SettingChargeCounter::root_allocation_bytes()).unwrap();let healthy=SettingAdmission::new(&used,4<<20,&||Ok(()));let(ast,parameters)=input(&source,&healthy);let baseline=used.load(Ordering::Acquire);let span=ast.items[0].span;let calls=Cell::new(0usize);
 let count=||{calls.set(calls.get()+1);Ok(())};let bounded=SettingAdmission::new(&used,baseline+(1<<20),&count);drop(parse_proc_with_native_consumption_from_window_admitted(&source,span,TokenWindow::from_slice(&ast.tokens),0,None,true,Some(parameters.clone()),None,&bounded).unwrap());let total=calls.get();assert!(total>8);assert_eq!(used.load(Ordering::Acquire),baseline);
 for stop in[1,total/2,total]{for cancel in[false,true]{calls.set(0);let fail=||{let at=calls.get()+1;calls.set(at);if at==stop{Err(if cancel{std::io::Error::new(std::io::ErrorKind::Interrupted,"actual canonical phase cancellation")}else{std::io::Error::from_raw_os_error(1450)})}else{Ok(())}};let a=SettingAdmission::new(&used,baseline+(1<<20),&fail);let error=parse_proc_with_native_consumption_from_window_admitted(&source,span,TokenWindow::from_slice(&ast.tokens),0,None,true,Some(parameters.clone()),None,&a).err().expect("actual first checkpoint failure");if cancel{assert_eq!(error.kind(),std::io::ErrorKind::Interrupted);assert_eq!(error.to_string(),"actual canonical phase cancellation");}else{assert_eq!(error.raw_os_error(),Some(1450));}assert_eq!(calls.get(),stop);assert_eq!(used.load(Ordering::Acquire),baseline);}}
 let low=SettingAdmission::new(&used,baseline+(64<<10),&||Ok(()));assert_eq!(parse_proc_with_native_consumption_from_window_admitted(&source,span,TokenWindow::from_slice(&ast.tokens),0,None,true,Some(parameters.clone()),None,&low).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),baseline);
 let fresh=SettingAdmission::new(&used,baseline+(1<<20),&||Ok(()));let output=parse_proc_with_native_consumption_from_window_admitted(&source,span,TokenWindow::from_slice(&ast.tokens),0,None,true,Some(parameters.clone()),None,&fresh).unwrap();assert!(output.complete());drop(output);assert_eq!(used.load(Ordering::Acquire),baseline);drop(parameters);assert_eq!(used.load(Ordering::Acquire),SettingChargeCounter::root_allocation_bytes());
}
