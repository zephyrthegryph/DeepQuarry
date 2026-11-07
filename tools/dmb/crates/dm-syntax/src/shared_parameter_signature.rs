//! No-Weak shared parser DATA. Source/current-owner authority stays at the caller.
use crate::{ParameterSignature, SettingAdmission, SettingRootLease};
use std::{alloc::Layout, ops::Deref, sync::{Arc, atomic::AtomicUsize}};

struct Payload {
    // Drop the last signature and its child allocations before returning
    // the credit stored in this same Arc.
    signature: ParameterSignature,
    retention: Option<SettingRootLease>,
}
/// Every alias keeps the SAME payload and credit. No Arc/Weak escapes this owner.
pub struct SharedParameterSignature{owner:Option<Arc<Payload>>}
impl SharedParameterSignature{
 pub fn ordinary(signature:ParameterSignature)->Self{Self{owner:Some(Arc::new(Payload{signature,retention:None}))}}
 /// `lease` must have been reserved BEFORE constructing signature metadata.
 /// Only the finished payload and its owners stay charged after publication.
 /// This is storage DATA only: a quota lease cannot issue source authority.
 pub fn retained_using(signature:ParameterSignature,mut lease:SettingRootLease,a:&SettingAdmission<'_>)->std::io::Result<Self>{
  let validation=(||->std::io::Result<()>{
   a.checkpoint().map_err(|proxy|a.take_operational_error().unwrap_or(proxy))?;
   if !a.matches_lease_domain(&lease){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"parameter metadata credit belongs to another resource owner"))}
   let denied=||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"parameter metadata exceeded its prior reservation");
   // Each same-domain child has a live independent credit that its alias
   // keeps until the last drop. Foreign and unfunded children still count.
   let retained=Self::retention_envelope()
    .checked_add(signature.retained_children_bytes(Some(a))).ok_or_else(denied)?;
   let unused=lease.bytes().checked_sub(retained).ok_or_else(denied)?;
   if unused!=0{a.shrink(&mut lease,unused).map_err(|proxy|a.take_operational_error().unwrap_or(proxy))?;}
   Ok(())
  })();
  if let Err(actual)=validation{
   // Function argument drop order must not release this construction credit
   // while the unshared parameter metadata still owns its boxes/root aliases.
   drop(signature);drop(lease);return Err(actual)
  }
  Ok(Self{owner:Some(Arc::new(Payload{signature,retention:Some(lease)}))})
 }

 /// Exact fixed allocation, including the signature inline and Arc counts.
 pub fn retention_envelope() -> usize {
    let (layout, _) = Layout::new::<[AtomicUsize; 2]>()
        .extend(Layout::new::<Payload>())
        .expect("fixed parameter signature Arc layout");
    layout.pad_to_align().size()
 }

 /// Gross footprint without credit for independently admitted children.
 pub fn retained_allocation_bytes(signature: &ParameterSignature) -> Option<usize> {
    Self::retention_envelope().checked_add(signature.retained_children_bytes(None))
 }
 pub fn same_owner(&self,other:&Self)->bool{Arc::ptr_eq(self.owner.as_ref().unwrap(),other.owner.as_ref().unwrap())}
 pub fn is_admitted_by(&self,a:&SettingAdmission<'_>)->bool{self.payload().retention.as_ref().is_some_and(|lease|a.matches_lease_domain(lease))}
 fn payload(&self)->&Payload{self.owner.as_deref().expect("live parameter signature owner")}
 pub fn visit_owner_storage(&self,mut visit:impl FnMut(usize,usize,usize)){
  let bytes = Self::retention_envelope();
  visit(Arc::as_ptr(self.owner.as_ref().unwrap()) as usize, bytes, bytes);
  if let Some(lease) = &self.payload().retention {
   lease.visit_counter_storage(|p, n| visit(p, n, n));
  }
 }
}
impl Clone for SharedParameterSignature{fn clone(&self)->Self{Self{owner:self.owner.as_ref().map(Arc::clone)}}}
impl Deref for SharedParameterSignature{type Target=ParameterSignature;fn deref(&self)->&ParameterSignature{&self.payload().signature}}
impl AsRef<ParameterSignature>for SharedParameterSignature{fn as_ref(&self)->&ParameterSignature{self}}
impl std::fmt::Debug for SharedParameterSignature{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{std::fmt::Debug::fmt(self.deref(),f)}}
impl PartialEq for SharedParameterSignature{fn eq(&self,other:&Self)->bool{self.deref()==other.deref()}}impl Eq for SharedParameterSignature{}
impl Drop for SharedParameterSignature{fn drop(&mut self){if let Some(owner)=self.owner.take(){if let Some(payload)=Arc::into_inner(owner){drop(payload)}}}}
/// Ordinary syntax paths remain value producers; only actual preissued Original
/// headers adopt a shared owner. No new ordinary syntax-only Arc allocation.
#[derive(Debug)]pub enum ProcedureParameters{Owned(ParameterSignature),Shared(SharedParameterSignature)}
impl ProcedureParameters{
 pub fn into_shared(self)->SharedParameterSignature{match self{Self::Owned(signature)=>SharedParameterSignature::ordinary(signature),Self::Shared(signature)=>signature}}
 pub fn admit_optional_expressions(&mut self,allowance:usize){if let Self::Owned(signature)=self{signature.admit_optional_expressions(allowance)}}
}
impl Deref for ProcedureParameters{type Target=ParameterSignature;fn deref(&self)->&ParameterSignature{match self{Self::Owned(signature)=>signature,Self::Shared(signature)=>signature}}}
impl PartialEq for ProcedureParameters{fn eq(&self,other:&Self)->bool{self.deref()==other.deref()}}impl Eq for ProcedureParameters{}

#[cfg(test)]mod tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 fn produce(source:&str,a:&SettingAdmission<'_>)->(crate::DeclarationSkeleton,SharedParameterSignature){
  let ast=crate::parse_declaration_skeleton(source);assert!(ast.diagnostics.is_empty(),"{:?}",ast.diagnostics);
  let header=ast.items[0].header_span;let lease=a.reserve((header.end-header.start)*512+8192+SharedParameterSignature::retention_envelope()).unwrap();
  let signature=crate::parameter_signature_original_with_default_roots(source,&ast.tokens,header,0,&mut None);
  let shared=SharedParameterSignature::retained_using(signature,lease,a).unwrap();(ast,shared)
 }
 #[test]fn primary_header_selection_precedes_bad_statement_body_and_adopts_same_signature(){
  let source="/proc/p(datum/act/A)\n    return (1 + )\n";let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
  let before=crate::parameter_syntax::PARAMETER_SIGNATURE_ISSUANCES.with(|counter|counter.get());let(ast,shared)=produce(source,&a);assert_eq!(crate::parameter_syntax::PARAMETER_SIGNATURE_ISSUANCES.with(|counter|counter.get()),before+1);let entry=&shared.entries().unwrap()[0];assert_eq!(entry.type_path(source).unwrap().as_deref(),Some("/datum/act"));let entry_ptr=entry as *const crate::ParameterSyntax;
  let issued=crate::parse_original_proc_with_shared_parameters_from_spans(source,ast.items[0].span,&ast.tokens,0,shared.clone()).unwrap();
  assert!(matches!(&issued.parameters,ProcedureParameters::Shared(actual)if actual.same_owner(&shared)));
  assert_eq!(crate::parameter_syntax::PARAMETER_SIGNATURE_ISSUANCES.with(|counter|counter.get()),before+1,"BODY must not reissue parameter signature DATA");
  assert_eq!(&issued.parameters.entries().unwrap()[0]as*const crate::ParameterSyntax,entry_ptr);
  let body=crate::parse_proc_body(&issued.item);assert!(!body.diagnostics.is_empty(),"the later demanded malformed BODY must fail");
  drop((body,issued,ast));assert!(used.load(Ordering::Acquire)>crate::SettingChargeCounter::root_allocation_bytes());drop(shared);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn same_signature_aliases_keep_original_credit_until_last_payload_control_is_freed(){
  for reverse in [false,true]{let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let(ast,shared)=produce("/proc/p(datum/act/A)\n    return A\n",&a);let alias=shared.clone();assert!(shared.same_owner(&alias));let held=used.load(Ordering::Acquire);assert!(held>0);drop((ast,a));let last=if reverse{drop(alias);shared}else{drop(shared);alias};assert_eq!(used.load(Ordering::Acquire),held);assert_eq!(last.entries().unwrap().len(),1);drop(last);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());}
 }
 #[test]
 fn completed_signature_releases_construction_slack_before_admitting_the_next_header() {
  let source = "/proc/p(datum/act/A)\n    return A\n";
  let count = 16;
  let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
  let (ast, first) = produce(source, &a);
  let header = ast.items[0].header_span;
  let envelope = (header.end - header.start) * 512 + 8192 + SharedParameterSignature::retention_envelope();
  let retained = SharedParameterSignature::retained_allocation_bytes(&first).unwrap();
  assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (retained));
  assert!(retained < envelope, "exercise real post-construction slack");
  drop((ast, first));
  assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());

  let limit = envelope + (count - 1) * retained;
  let a = SettingAdmission::new(&used, crate::SettingChargeCounter::root_allocation_bytes() + (limit), &|| Ok(()));
  let mut cohort = Vec::new();
  for i in 1..=count {
   let (ast, next) = produce(source, &a);
   assert_eq!(next.entries().unwrap().len(), 1);
   drop(ast);
   cohort.push(next);
   assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (i * retained));
  }
  let alias = cohort[0].clone();
  drop(cohort);
  assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (retained));
  drop(alias);
  assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]
 fn actual_empty_header_uses_one_funded_allocation_until_its_last_alias() {
  let source = "/proc/probe()\n    return 0\n";
  let ast = crate::parse_declaration_skeleton(source);
  assert!(ast.diagnostics.is_empty());
  let header = ast.items[0].header_span;
  let arg_start = source.find('(').unwrap() + 1;
  let tokens = crate::TokenWindow::from_slice(&ast.tokens);
  let produce = || crate::parameter_signature_original_plain_empty(
      source, tokens, header, arg_start,
  ).unwrap();
  let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let bytes = SharedParameterSignature::retention_envelope();
  assert_eq!(SharedParameterSignature::retained_allocation_bytes(&produce()), Some(bytes));
  let a = SettingAdmission::new(&used, crate::SettingChargeCounter::root_allocation_bytes() + (bytes), &|| Ok(()));
  let signature = SharedParameterSignature::retained_using(produce(), a.reserve(bytes).unwrap(), &a)
      .unwrap();
  let original = &*signature as *const ParameterSignature;
  let alias = signature.clone();
  assert!(alias.same_owner(&signature));
  let mut owner_rows = Vec::new();
  signature.visit_owner_storage(|p, used, cap| owner_rows.push((p, used, cap)));
  assert_eq!(owner_rows.len(), 2, "one owner allocation plus the shared counter");
  assert_eq!((owner_rows[0].1, owner_rows[0].2), (bytes, bytes));
  assert_eq!(owner_rows[1].0, Arc::as_ptr(&used) as usize);
  drop(signature);
  assert_eq!(&*alias as *const ParameterSignature, original);
  assert_eq!(alias.header(), header);
  assert!(alias.is_admitted_by(&a));
  assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (bytes));
  drop(alias);
  assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
 }

 #[test]fn shared_metadata_rejects_foreign_credit_and_keeps_first_real_io(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let foreign=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let b=SettingAdmission::new(&foreign,1<<20,&||Ok(()));
  let source="/proc/p(x)\n    return x\n";let ast=crate::parse_declaration_skeleton(source);let signature=crate::parameter_signature_original_with_default_roots(source,&ast.tokens,ast.items[0].header_span,0,&mut None);let lease=b.reserve(16384).unwrap();assert_eq!(SharedParameterSignature::retained_using(signature,lease,&a).err().unwrap().kind(),std::io::ErrorKind::InvalidInput);assert_eq!(foreign.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let signature=crate::parameter_signature_original_with_default_roots(source,&ast.tokens,ast.items[0].header_span,0,&mut None);let lease=a.reserve(16384).unwrap();let fault=||Err(std::io::Error::from_raw_os_error(1450));let failed=SettingAdmission::new(&used,1<<20,&fault);assert_eq!(SharedParameterSignature::retained_using(signature,lease,&failed).err().unwrap().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let fresh=SettingAdmission::new(&used,1<<20,&||Ok(()));let(_,recovered)=produce(source,&fresh);drop(recovered);assert_eq!(used.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn ordinary_syntax_keeps_owned_parameter_value_until_existing_body_publication(){
  let source="/proc/p(x)\n    return x\n";let ast=crate::parse_declaration_skeleton(source);let issued=crate::parse_proc_with_origins_from_spans(source,ast.items[0].span,&ast.tokens,0).unwrap();assert!(matches!(&issued.parameters,ProcedureParameters::Owned(_)));let shared=issued.parameters.into_shared();assert_eq!(shared.entries().unwrap().len(),1);let alias=shared.clone();assert!(shared.same_owner(&alias));
 }
}
