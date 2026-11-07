use super::*;
fn contribution(source:&str,admission:Option<&dm_syntax::SettingAdmission<'_>>)->(Vec<dm_syntax::Item>,crate::AdaptedDeclarations,AllocationLedger,Arc<crate::procedure::OriginalProcedureHeaders>,dm_preprocess::SourceText){
    let parsed=dm_syntax::parse_declaration_skeleton(source);let tokens=parsed.tokens;let ast=dm_syntax::AstFile{items:parsed.items,diagnostics:parsed.diagnostics,..dm_syntax::AstFile::default()};
    let original:dm_preprocess::SourceText=source.into();
    let headers=match admission{Some(a)=>crate::procedure::OriginalProcedureHeaders::from_primary_admitted(original.clone(),&ast.items,0,tokens,a).ok().unwrap(),None=>crate::procedure::OriginalProcedureHeaders::from_primary(original.clone(),&ast.items,0,tokens).unwrap()};
    let(mut facts,receipt)=match admission{Some(a)=>crate::adapter::from_ast_with_source_headers_checked(&ast,SymbolTable::default(),FileId(0),0,0,source,&headers,0,a).unwrap().unwrap(),None=>crate::adapter::from_ast_with_source_headers(&ast,SymbolTable::default(),FileId(0),0,0,source,&headers,0).unwrap()};
    let ledger=crate::allocation_ledger::capture_with_header_receipt(&ast.items,"/",&mut facts.symbols,&receipt).unwrap();drop(receipt);(ast.items,facts,ledger,headers,original)
}
#[test]
fn checked_declaration_same_table_declines_old_header_and_fresh_publish_stays_warm_in_local_and_shared_modes(){
    let source="var/const/value=1+2\n";
    for shared in[false,true]{
        let state=if shared{DeclarationClaims::with_shared_authored(Arc::new(crate::SharedNormalizedDeclarations::default()))}else{DeclarationClaims::default()};let key=RetainedDeclarations::original_header_key(source);
        let(items,facts,ledger,headers,original)=contribution(source,None);let mut old=state.capture_source_headers(&key,original,0,items,facts,ledger,Some(headers)).unwrap();if !old.stored{state.values.publish(&key,&mut old).unwrap();}
        let old_owner=Arc::clone(&old.value);let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let checkpoint=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,4*1024*1024,&checkpoint);
        assert!(state.get_shared_checked(&key,source,0,&a).unwrap().is_none(),"equal source ledger cannot certify original initializer producer");
        let(items,facts,ledger,headers,original)=contribution(source,Some(&a));let mut fresh=state.capture_source_headers_checked(&key,original,0,items,facts,ledger,headers,&a).unwrap().unwrap();
        state.adopt_authored_checked(std::iter::once(&mut fresh),&a,None).unwrap().unwrap();
        assert!(!Arc::ptr_eq(&old_owner,&fresh.value));assert!(fresh.value.syntax.initializer_admission_matches(&a).unwrap());assert!(!old_owner.syntax.initializer_admission_matches(&a).unwrap(),"old escaped owner is never grafted/promoted");
        let warm=state.get_shared_checked(&key,source,0,&a).unwrap().expect("same actual admitted producer reused");assert!(Arc::ptr_eq(&fresh.value,&warm.value));assert!(Arc::ptr_eq(&fresh.value.syntax,&warm.value.syntax));
        let foreign_counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let foreign=dm_syntax::SettingAdmission::new(&foreign_counter,4*1024*1024,&checkpoint);assert!(state.get_shared_checked(&key,source,0,&foreign).unwrap().is_none());
        let(items,facts,ledger,headers,original)=contribution(source,Some(&foreign));let mut other=state.capture_source_headers_checked(&key,original,0,items,facts,ledger,headers,&foreign).unwrap().unwrap();state.adopt_authored_checked(std::iter::once(&mut other),&foreign,None).unwrap().unwrap();assert!(!Arc::ptr_eq(&fresh.value.syntax,&other.value.syntax));
        // This same lease deliberately adopted B: current-roster stores may
        // retire its unclaimed A candidate. Escaped owners remain immutable;
        // keeping an Arc alive does not create a separate publication claim.
        assert!(state.get_shared_checked(&key,source,0,&a).unwrap().is_none(),"unclaimed foreign-domain candidate is not promoted from equal source");
        assert!(Arc::ptr_eq(&fresh.value,&warm.value));
        assert!(fresh.value.syntax.initializer_admission_matches(&a).unwrap(),"escaped A keeps its original completed producer and counter");
        assert!(!fresh.value.syntax.initializer_admission_matches(&foreign).unwrap(),"replacing this lease's claim cannot mutate escaped A into B");
        let current_b=state.get_shared_checked(&key,source,0,&foreign).unwrap().expect("current B claim remains warm after refused A lookup");
        assert!(Arc::ptr_eq(&other.value,&current_b.value));
        assert!(Arc::ptr_eq(&old_owner.syntax,&old.value.syntax));
    }
}
#[test]
fn checked_declaration_lookup_actual_io_is_not_a_miss_or_successful_hit_and_empty_key_still_checks(){
    let source="var/const/value=1+2\n";let state=DeclarationClaims::default();let key=RetainedDeclarations::original_header_key(source);let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let checkpoint=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,4*1024*1024,&checkpoint);let(items,facts,ledger,headers,original)=contribution(source,Some(&a));let fresh=state.capture_source_headers_checked(&key,original,0,items,facts,ledger,headers,&a).unwrap().unwrap();let before=state.hits.load(Ordering::Relaxed);
    for key in[key.as_slice(),b"not-an-existing-key".as_slice()]{let failure=||Err(std::io::Error::from_raw_os_error(1450));let failed=dm_syntax::SettingAdmission::new(&counter,4*1024*1024,&failure);let actual=state.get_shared_checked(key,source,0,&failed).err().expect("actual lookup operation is not a cache miss");assert_eq!(actual.raw_os_error(),Some(1450));}
    assert_eq!(state.hits.load(Ordering::Relaxed),before);let warm=state.get_shared_checked(&key,source,0,&a).unwrap().unwrap();assert!(Arc::ptr_eq(&fresh.value,&warm.value));
}

#[test]
fn checked_declaration_retired_request_is_operational_not_a_fresh_miss(){
    let state=RetainedDeclarations::default();
    let request=state.begin_request(true);drop(request);
    let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let checkpoint=||Ok(());
    let admission=dm_syntax::SettingAdmission::new(&counter,4*1024*1024,&checkpoint);
    let actual=state.get_shared_checked(b"missing", "",0,&admission).err().expect("retired checked request cannot fall through to a producer");
    assert_eq!(actual.kind(),std::io::ErrorKind::NotConnected);
}
