use super::*;
use std::sync::atomic::{Ordering};
fn parsed(source:&str)->(AstFile,Vec<dm_syntax::SpanToken>){let parsed=dm_syntax::parse_declaration_skeleton(source);let tokens=parsed.tokens;let ast=AstFile{items:parsed.items,diagnostics:parsed.diagnostics,..AstFile::default()};(ast,tokens)}
#[test]
fn checked_adapter_original_rhs_matches_all_old_metadata_and_reuses_one_early_root(){
    for rhs in ["1+2","(1+2)*3","unknown+1","list(1)","1 +","\"plain literal\"","\"[unknown]\""]{
        let source=format!("var/const/value={rhs} as num\n");let(ast,tokens)=parsed(&source);let old=from_ast(&ast,SymbolTable::default(),FileId(0),0,0).unwrap();
        let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let checkpoint=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,4*1024*1024,&checkpoint);
        let headers=crate::procedure::OriginalProcedureHeaders::from_primary_admitted(source.clone().into(),&ast.items,0,tokens,&a).ok().expect("original admitted header inventory");
        assert!(!headers.initializer_admission_matches(&a).unwrap(),"coordinates alone are not completed producer evidence");
        let(current,_receipt)=from_ast_with_source_headers_checked(&ast,SymbolTable::default(),FileId(0),0,0,&source,&headers,0,&a).unwrap().unwrap();
        assert_eq!(current.skeletons,old.skeletons,"exact old scalar/flags/type/canonical metadata: {rhs}");assert_eq!(current.origins,old.origins);assert!(headers.initializer_admission_matches(&a).unwrap());
        let normalized=crate::normalize::declarations_in_scope(&ast.items,"/");let item=&normalized[0];let parts=headers.variable_parts(item.header_span,0,item.header.trim()).unwrap();let mut symbols=current.symbols.clone();let symbolic=parts.symbolic(&mut symbols).unwrap().unwrap();
        let prepared=headers.prepare_initializer(item.header_span,0,true,&symbolic,&symbols,&a).ok().unwrap();
        if let Ok(first)=prepared{let next=headers.prepare_initializer(item.header_span,0,true,&symbolic,&symbols,&a).ok().unwrap().unwrap();assert!(first.same_root(&next));assert!(headers.initializer_admission_matches(&a).unwrap());}
    }
}
#[test]
fn checked_adapter_actual_quota_and_os_failure_never_complete_producer_and_retry_same_owner(){
    let source="var/const/value=1+2\n";let(ast,tokens)=parsed(source);let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let checkpoint=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,4*1024*1024,&checkpoint);
    let headers=crate::procedure::OriginalProcedureHeaders::from_primary_admitted(source.into(),&ast.items,0,tokens,&a).ok().unwrap();
    let quota=dm_syntax::SettingAdmission::new(&counter,counter.load(Ordering::Acquire),&checkpoint);
    let actual=from_ast_with_source_headers_checked(&ast,SymbolTable::default(),FileId(0),0,0,source,&headers,0,&quota).err().expect("root storage denied before metadata publication");assert_eq!(actual.kind(),std::io::ErrorKind::OutOfMemory);assert!(!headers.initializer_admission_matches(&a).unwrap());
    let calls=std::cell::Cell::new(0);let failure=||{calls.set(calls.get()+1);if calls.get()==3{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}};let failed=dm_syntax::SettingAdmission::new(&counter,4*1024*1024,&failure);
    let actual=from_ast_with_source_headers_checked(&ast,SymbolTable::default(),FileId(0),0,0,source,&headers,0,&failed).err().expect("actual original worker IO before source/fact cache");assert_eq!(actual.raw_os_error(),Some(1450));assert!(!headers.initializer_admission_matches(&a).unwrap());
    assert!(from_ast_with_source_headers_checked(&ast,SymbolTable::default(),FileId(0),0,0,source,&headers,0,&a).unwrap().is_ok());assert!(headers.initializer_admission_matches(&a).unwrap());
    let foreign_counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let foreign=dm_syntax::SettingAdmission::new(&foreign_counter,4*1024*1024,&checkpoint);assert!(!headers.initializer_admission_matches(&foreign).unwrap());
    let actual=from_ast_with_source_headers_checked(&ast,SymbolTable::default(),FileId(0),0,0,source,&headers,0,&foreign).err().unwrap();assert_eq!(actual.kind(),std::io::ErrorKind::InvalidInput);assert!(headers.initializer_admission_matches(&a).unwrap());
}
#[test]
fn checked_adapter_native_override_rhs_preserves_current_original_token_geometry(){
    let source="/datum/probe\n    var/num/value=1\n    value=2+3\n";let(ast,tokens)=parsed(source);let old=from_ast(&ast,SymbolTable::default(),FileId(0),0,0).unwrap();let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let checkpoint=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,4*1024*1024,&checkpoint);let headers=crate::procedure::OriginalProcedureHeaders::from_primary_admitted(source.into(),&ast.items,0,tokens,&a).ok().unwrap();let(current,_)=from_ast_with_source_headers_checked(&ast,SymbolTable::default(),FileId(0),0,0,source,&headers,0,&a).unwrap().unwrap();assert_eq!(current.skeletons,old.skeletons);assert_eq!(current.origins,old.origins);
}

#[test]
fn actual_checked_initializer_var_unknown_statement_metadata_matches_without_callable_slots(){
 let source="/proc/before()\n    return 9\n/datum/probe\n    var\n        value=1+2\n        array[2]\n    value=3+4\n    proc/ordinary()\n        return 5\n";
 let(ast,tokens)=parsed(source);assert!(ast.diagnostics.is_empty());
 fn declaration_kinds(items:&[dm_syntax::Item],out:&mut Vec<dm_syntax::ItemKind>){for item in items{out.push(item.kind);if !matches!(item.kind,dm_syntax::ItemKind::Proc|dm_syntax::ItemKind::Verb){declaration_kinds(&item.children,out)}}}
 let mut kinds=Vec::new();declaration_kinds(&ast.items,&mut kinds);assert!(kinds.contains(&dm_syntax::ItemKind::Unknown),"real original array declarator exercises Unknown input kind");assert!(kinds.contains(&dm_syntax::ItemKind::Statement));
 let old=from_ast(&ast,SymbolTable::default(),FileId(0),0,0).unwrap();let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=dm_syntax::SettingAdmission::new(&counter,4<<20,&||Ok(()));
 let headers=crate::procedure::OriginalProcedureHeaders::from_primary_admitted(source.into(),&ast.items,0,tokens,&a).ok().unwrap();
 let(current,_)=from_ast_with_source_headers_checked(&ast,SymbolTable::default(),FileId(0),0,0,source,&headers,0,&a).unwrap().unwrap();assert_eq!(current.skeletons,old.skeletons);assert_eq!(current.origins,old.origins);assert!(headers.initializer_admission_matches(&a).unwrap());
}
