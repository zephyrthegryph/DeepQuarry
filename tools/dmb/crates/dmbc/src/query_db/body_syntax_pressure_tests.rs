use super::*;use dm_preprocess::{SourceProvider,SourceText};use std::{io,path::Path};
struct Original(dm_preprocess::AcquiredSource);impl SourceProvider for Original{fn read(&self,_:&Path)->Result<String,String>{Err("actual original acquisition required".into())}fn acquired_source(&self,_:&Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(Some(self.0.clone()))}fn source_acquisition(&self,_:&Path,text:&SourceText)->Option<dm_preprocess::AcquiredSource>{self.0.lease().source_text().same_view(text).then(||self.0.clone())}}
fn fixture(count:usize,db:&Arc<QueryDb>)->dm_tree::frontend::ColdFrontend{use std::fmt::Write;let mut text=String::new();for i in 0..count{writeln!(&mut text,"/proc/pressure_{i}()\n    set SpacemanDMM_should_be_pure=1\n    return \"value [1 + 2]\"").unwrap();}let source=Original(dm_preprocess::AcquiredSource::from_original_bytes(text.into_bytes(),()));dm_tree::frontend::build(Path::new("actual-body-pressure.dme"),&source,&Default::default(),1).unwrap().with_body_queries(db.clone())}
#[test]fn actual_syntax_pressure_retires_consumed_values_preserves_active_warm_root_and_dependency_hashes(){let db=Arc::new(QueryDb::default());let front=fixture(65,&db);let archive=front.body_archive().unwrap();let inputs=archive.syntax_inputs().unwrap();for input in &inputs[..64]{drop(db.syntax_checked(input).unwrap());}let protected=db.syntax_checked(&inputs[0]).unwrap();let children=inputs[..64].to_vec();let parent=Key::new(Kind(249),1);db.db.define(parent.kind,"actual syntax pressure parent",move|ctx,_|{let mut total=0usize;for input in &children{let key=Key::new(BODY_SYNTAX,input.key().into());let value=ctx.get::<BodyQueryValue>(key,Arc::new(Params{input:Arc::downgrade(input),key,code:None}))?;total+=usize::from(value.issued().is_ok());}Ok(Outcome::new(total,17,std::mem::size_of::<usize>()))});let parent_value=db.db.get::<usize>(parent,Arc::new(())).unwrap();assert_eq!(*parent_value,64);let computed=db.db.stats(BODY_SYNTAX).computed;let evicted=db.db.stats(BODY_SYNTAX).evicted;let used=db.body_charge.load(Ordering::Acquire);let held=dm_syntax::SettingRootLease::reserve(&db.body_charge,BUDGET,BUDGET.checked_sub(used).unwrap().checked_sub(64*1024).unwrap()).unwrap();let warm=db.syntax_checked(&inputs[0]).unwrap();assert!(Arc::ptr_eq(&protected,&warm));assert_eq!(db.db.stats(BODY_SYNTAX).computed,computed);assert!(db.db.stats(BODY_SYNTAX).evicted>evicted,"the real pre-get pressure path retired consumed cached values");let retired=inputs[1..64].iter().map(|input|Key::new(BODY_SYNTAX,input.key().into())).find(|key|db.db.value_bytes_at(*key)==0).expect("at least one genuine consumed syntax retired");assert!(db.db.dependants(&[retired]).contains(&parent));drop(db.syntax_checked(&inputs[64]).unwrap());assert_eq!(db.db.stats(BODY_SYNTAX).computed,computed+1);drop(held);let revision=Key::new(Kind(250),1);db.db.define_input(revision.kind,"pressure unrelated revision");db.db.set_input(revision,1usize,1);let before=db.db.stats(BODY_SYNTAX).computed;assert!(Arc::ptr_eq(&parent_value,&db.db.get::<usize>(parent,Arc::new(())).unwrap()));assert_eq!(db.db.stats(BODY_SYNTAX).computed,before,"preserved child hashes revalidate without reparsing evicted payloads");assert!(Arc::ptr_eq(&protected,&db.syntax_checked(&inputs[0]).unwrap()));}
#[test]fn actual_pressure_preparation_preserves_cancel_and_first_kind4_operational_failure_then_same_input_retry(){let db=Arc::new(QueryDb::default());let front=fixture(65,&db);let archive=front.body_archive().unwrap();let inputs=archive.syntax_inputs().unwrap();for input in &inputs[..64]{drop(db.syntax_checked(input).unwrap());}let used=db.body_charge.load(Ordering::Acquire);let held=dm_syntax::SettingRootLease::reserve(&db.body_charge,BUDGET,BUDGET.checked_sub(used).unwrap().checked_sub(64*1024).unwrap()).unwrap();let evicted=db.db.stats(BODY_SYNTAX).evicted;let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();let Err(BodySyntaxFailure::Operational(actual))=db.syntax_checked(&inputs[64])else{panic!("cancelled actual preparation")};assert_eq!(actual.kind(),io::ErrorKind::Interrupted);assert_eq!(db.db.stats(BODY_SYNTAX).evicted,evicted);drop(binding);let failure=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));let Err(BodySyntaxFailure::Operational(actual))=db.syntax_checked(&inputs[64])else{panic!("actual Kind4 IO")};assert_eq!(actual.raw_os_error(),Some(1450));drop(failure);drop(held);let recovered=db.syntax_checked(&inputs[64]).unwrap();assert!(Arc::ptr_eq(&recovered,&db.syntax_checked(&inputs[64]).unwrap()));}

#[test]
fn actual_query_db_prepaid_root_does_not_raise_the_existing128mib_admission() {
    let db=QueryDb::default();
    let fixed=dm_syntax::SettingChargeCounter::root_allocation_bytes();
    let held=dm_syntax::SettingRootLease::reserve(&db.body_charge,BUDGET,BUDGET-fixed).unwrap();
    assert_eq!(db.body_charge.load(Ordering::Acquire),BUDGET);
    assert_eq!(db.body_charge.allocation_lease_reserved(),BUDGET);
    assert!(dm_syntax::SettingRootLease::reserve(&db.body_charge,BUDGET,1).is_err());
    db.body_charge.add_soft_estimate(512);
    assert_eq!(db.body_charge.load(Ordering::Acquire),BUDGET+512);
    assert_eq!(db.body_charge.allocation_lease_reserved(),BUDGET);
    db.body_charge.release_soft_estimate(512);
    drop(held);
    assert_eq!(db.body_charge.load(Ordering::Acquire),fixed);
    assert_eq!(db.body_charge.allocation_lease_reserved(),fixed);
}
#[test]
fn actual_cached_body_estimate_is_not_a_physical_lease_and_eviction_preserves_escaped_owner() {
    let db=Arc::new(QueryDb::default());
    let fixed=dm_syntax::SettingChargeCounter::root_allocation_bytes();
    assert_eq!(db.body_charge.load(Ordering::Acquire),fixed);
    assert_eq!(db.body_charge.allocation_lease_reserved(),fixed);
    let front=fixture(1,&db);
    let archive=front.body_archive().unwrap();
    let inputs=archive.syntax_inputs().unwrap();
    let escaped=db.syntax_checked(&inputs[0]).unwrap();
    let key=Key::new(BODY_SYNTAX,inputs[0].key().into());
    let soft=db.db.value_bytes_at(key);
    assert!(soft>0,"real Kind4 graph value has its original soft estimate");
    let leased=db.body_charge.allocation_lease_reserved();
    assert_eq!(db.body_charge.load(Ordering::Acquire),leased+soft);
    let freed=db.db.evict_values(&[BODY_SYNTAX]);
    assert_eq!(freed,soft);
    db.body_charge.release_soft_estimate(freed);
    assert_eq!(db.body_charge.allocation_lease_reserved(),leased,
        "cache estimate eviction cannot refund an escaped real syntax owner");
    assert_eq!(db.body_charge.load(Ordering::Acquire),leased);
    drop(escaped);
    assert_eq!(db.body_charge.load(Ordering::Acquire),db.body_charge.allocation_lease_reserved());
    assert!(db.body_charge.allocation_lease_reserved()>=fixed);
}
