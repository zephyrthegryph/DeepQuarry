//! Resource-only lifetime census for public IR aliases of the SAME native
//! primary signature products. No source/name/model lookup or semantic answer.
use super::*;
use std::sync::Weak;
use std::io;
use crate::procedure::original_primary_signatures::{allocate_funded_rows,PreparedOriginalSignatures};
// A borrowed enum is used only while traversing the actual immutable graph.
// Stored observations remain typed, with no per-row discriminant or erased pointer.
macro_rules! typed_aliases {
 ($($variant:ident($field:ident, $target:ty)),+ $(,)?) => {
  enum Alias<'a> { $($variant(&'a Arc<$target>)),+ }
  #[derive(Debug, Default, Eq, PartialEq)]
  struct AliasCounts { $($field:usize),+ }
  impl AliasCounts {
   fn note(&mut self, alias: Alias<'_>) -> io::Result<()> {
    let count=match alias { $(Alias::$variant(_)=>&mut self.$field),+ };
    *count=count.checked_add(1).ok_or_else(oom)?;
    Ok(())
   }
  }
  struct TypedAliases { $($field:Vec<Weak<$target>>),+ }
  impl TypedAliases {
   fn allocate(count:&AliasCounts, owner:&mut dm_syntax::SettingRootLease, a:&dm_syntax::SettingAdmission<'_>)->io::Result<Self>{
    Ok(Self{$($field:exact_rows(count.$field,owner,a)?),+})
   }
   fn push(&mut self, alias: Alias<'_>) -> io::Result<()> {
    match alias { $(Alias::$variant(actual)=>{
     let rows=&mut self.$field;
     if rows.len()==rows.capacity(){return Err(oom())}
     rows.push(Arc::downgrade(actual));
    }),+ }
    Ok(())
   }
   fn counts(&self)->AliasCounts{AliasCounts{$($field:self.$field.len()),+}}
   fn len(&self)->usize{0$(+self.$field.len())+}
   fn live(&self)->bool{false$(||self.$field.iter().any(|row|row.strong_count()!=0))+}
   fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){
    $(visit_vec(&self.$field,&mut visit);)+
   }
  }
 };
}
typed_aliases!(
 Member(members,dm_ir::DeclarationMeaning),
 Canonical(canonical,[u8]),
 Metadata(metadata,dm_ir::ProcedureMetadata),
 Settings(settings,[dm_ir::ProcedureSettingNode]),
 Parameters(parameters,[dm_ir::Parameter]),
 ParameterTail(parameter_tails,dm_ir::ParameterTail),
 Array(arrays,dm_ir::ArrayDeclaration),
 Dimensions(dimensions,[Option<dm_ir::SymbolicExpression>]),
 Tokens(tokens,[dm_ir::ExpressionToken]),
 WideItems(wide_items,[dm_syntax::Item]),
);
fn visit_vec<T>(rows:&Vec<T>,visit:&mut impl FnMut(usize,usize,usize)){
 if rows.capacity()!=0{
  visit(rows.as_ptr() as usize,rows.capacity()*std::mem::size_of::<T>(),std::mem::align_of::<T>());
 }
}
/// Public for the existing native resource owner only. Private fields cannot
/// carry source/semantic admission, recreate a graph, or retain an IR payload.
pub struct OriginalSignatureAliasGroup{
 aliases:TypedAliases,spellings:crate::procedure::original_primary_signatures::OriginalSignatureSpellings,reservations:Vec<Arc<dm_syntax::SettingRootLease>>,
 _adapter:Option<dm_syntax::SettingRootLease>,
 _coordination:dm_syntax::SettingRootLease,
}
impl std::fmt::Debug for OriginalSignatureAliasGroup{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("OriginalSignatureAliasGroup").field("weak_observations",&self.aliases.len()).field("signature_reservations",&self.reservations.len()).finish_non_exhaustive()}}
impl OriginalSignatureAliasGroup{
 fn live(&self)->bool{self.aliases.live()||self.spellings.live()}
 fn require_domain(&self,a:&dm_syntax::SettingAdmission<'_>)->io::Result<()>{if !a.matches_lease_domain(&self._coordination)||!self.spellings.admitted_by(a)||self.reservations.iter().any(|row|!a.matches_lease_domain(row))||self._adapter.as_ref().is_some_and(|row|!a.matches_lease_domain(row)){return Err(io::Error::new(io::ErrorKind::InvalidInput,"original signature resource census belongs to another native counter"))}Ok(())}
 pub(super) fn capture(facts:&crate::AdaptedDeclarations,prepared:&mut crate::procedure::original_primary_signatures::PreparedOriginalSignatures,a:&dm_syntax::SettingAdmission<'_>)->io::Result<Arc<Self>>{
  prepared.require_consumed().map_err(|reason|io::Error::new(io::ErrorKind::InvalidData,reason))?;
  let mut alias_count=AliasCounts::default();
  let mut lease_count=0usize;
  // Both traversals borrow the same immutable facts and signature products.
  // The first counts actual Arc fields without constructing transient Weaks.
  visit_aliases(facts,prepared,a,&mut |actual|{checkpoint(a)?;alias_count.note(actual)})?;
  prepared.visit_signature_reservations(|_|lease_count=lease_count.saturating_add(1));
  if lease_count==usize::MAX{return Err(oom())}
  #[cfg(debug_assertions)]
  if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some() {
   eprintln!("ORIGINAL_SIGNATURE_ALIAS_COUNTS retained={} counts={alias_count:?} reservations={lease_count}", a.retained_bytes_for_trace());
  }
  let mut coordination=a.reserve(group_bytes()?).map_err(|error|a.take_operational_error().unwrap_or(error))?;
  let mut aliases=TypedAliases::allocate(&alias_count,&mut coordination,a)?;
  let mut reservations=exact_rows(lease_count,&mut coordination,a)?;
  visit_aliases(facts,prepared,a,&mut|actual|{
   checkpoint(a)?;
   aliases.push(actual)
  })?;
  let mut surplus=false;
  prepared.visit_signature_reservations(|row|{
   if reservations.len()==reservations.capacity(){surplus=true;}else{reservations.push(Arc::clone(row));}
  });
  if aliases.counts()!=alias_count||reservations.len()!=lease_count||surplus{
   return Err(io::Error::new(io::ErrorKind::InvalidData,"actual signature alias roster changed during capture"));
  }
  checkpoint(a)?;
  let group=Arc::new(Self{aliases,spellings:prepared.take_spellings(),reservations,_adapter:prepared.take_adapter_storage(),_coordination:coordination});
  prepared.release_consumed_rows();
  Ok(group)
 }

 pub(super) fn retain_wide_items(&mut self,items:&Arc<[dm_syntax::Item]>,parser:&Arc<dm_syntax::SettingRootLease>,a:&dm_syntax::SettingAdmission<'_>)->io::Result<()>{
  checkpoint(a)?;
  self.require_domain(a)?;
  if !a.matches_lease_domain(parser){return Err(io::Error::new(io::ErrorKind::InvalidInput,"wide primary allocation uses another parser reservation"))}
  reserve_one(&mut self.aliases.wide_items,&mut self._coordination,a)?;
  reserve_one(&mut self.reservations,&mut self._coordination,a)?;
  self.aliases.push(Alias::WideItems(items))?;
  self.reservations.push(Arc::clone(parser));
  checkpoint(a)
 }
 #[cfg(test)]
 pub(super) fn procedure_alias_counts_for_test(&self)->(usize,usize) {
  (self.aliases.metadata.len(),self.aliases.parameters.len())
 }
 #[cfg(test)]
 pub(super) fn coordination_storage_for_test(&self)->(usize,usize){
  let mut physical=group_bytes().unwrap();
  self.aliases.visit_storage(|_,bytes,_|physical+=bytes);
  visit_vec(&self.reservations,&mut|_,bytes,_|physical+=bytes);
  (self._coordination.bytes(),physical)
 }
 pub(super) fn visit_storage(&self,mut f:impl FnMut(usize,usize,usize)){
  self.spellings.visit_storage(&mut f);
  f(self as*const Self as usize,group_bytes().expect("valid Arc group layout"),std::mem::align_of::<Self>());for lease in &self.reservations{f(Arc::as_ptr(lease)as usize,std::mem::size_of::<dm_syntax::SettingRootLease>()+2*std::mem::size_of::<usize>(),std::mem::align_of::<dm_syntax::SettingRootLease>())}
  self.aliases.visit_storage(&mut f);
  visit_vec(&self.reservations,&mut f);
 }
}
fn oom()->io::Error{io::Error::from(io::ErrorKind::OutOfMemory)}
fn checkpoint(a:&dm_syntax::SettingAdmission<'_>)->io::Result<()>{
 a.checkpoint().map_err(|error|a.take_operational_error().unwrap_or(error))
}
fn group_bytes()->io::Result<usize>{
 use std::alloc::Layout;
 Layout::new::<[std::sync::atomic::AtomicUsize;2]>()
  .extend(Layout::new::<OriginalSignatureAliasGroup>())
  .map(|(layout,_)|layout.pad_to_align().size()).map_err(|_|oom())
}
fn exact_rows<T>(capacity:usize,coordination:&mut dm_syntax::SettingRootLease,a:&dm_syntax::SettingAdmission<'_>)->io::Result<Vec<T>>{
 if capacity==0{return Ok(Vec::new())}
 let (rows,mut credit)=allocate_funded_rows(capacity,a)?;
 if let Err(first)=a.absorb(coordination,&mut credit){
  // The exact allocation must die before its not-yet-transferred credit.
  drop(rows);
  drop(credit);
  return Err(first);
 }
 Ok(rows)
}
fn reserve_one<T>(rows:&mut Vec<T>,coordination:&mut dm_syntax::SettingRootLease,a:&dm_syntax::SettingAdmission<'_>)->io::Result<()>{
 if rows.len()<rows.capacity(){return Ok(())}
 let old_bytes=rows.capacity().checked_mul(std::mem::size_of::<T>()).ok_or_else(oom)?;
 let mut next=exact_rows(rows.len().checked_add(1).ok_or_else(oom)?,coordination,a)?;
 next.append(rows);
 drop(std::mem::replace(rows,next));
 if old_bytes!=0{a.shrink(coordination,old_bytes).map_err(|error|a.take_operational_error().unwrap_or(error))?;}
 Ok(())
}
// Exact recent keys scoped to one immutable traversal. A collision forgets
// the old key and may repeat a Weak, but can never omit a distinct owner.
struct RecentAliases<const N: usize> {
 keys: [(usize, usize); N],
}
impl<const N: usize> RecentAliases<N> {
 fn new() -> Self { Self { keys: [(0, 0); N] } }
 fn seen(&mut self, address: usize, extent: usize) -> bool {
  debug_assert_ne!(address, 0);
  let key = (address, extent);
  let hint = (address >> 4) ^ (address >> 13) ^ extent.rotate_left(5);
  std::mem::replace(&mut self.keys[hint % N], key) == key
 }
}
const RECENT_ALIAS_SLOTS: usize = 128;

fn visit_aliases(facts:&crate::AdaptedDeclarations,prepared:&PreparedOriginalSignatures,a:&dm_syntax::SettingAdmission<'_>,f:&mut impl FnMut(Alias<'_>)->io::Result<()>)->io::Result<()>{
 let mut seen=[false;4];
 // Both count and fill start from empty stack tables and traverse the SAME
 // immutable strong owners. An earlier matching key always had a Weak emitted
 // in this pass; no graph owner can be freed and reused between these visits.
 let mut recent_metadata=RecentAliases::<RECENT_ALIAS_SLOTS>::new();
 let mut recent_parameters=RecentAliases::<RECENT_ALIAS_SLOTS>::new();
 for skeleton in &facts.skeletons{let crate::Skeleton::Member{metadata,..}=skeleton else{continue};let Some(procedure)=&metadata.procedure else{continue};
  f(Alias::Member(metadata))?;
  f(Alias::Canonical(metadata.canonical.storage_arc()))?;
  let (metadata_slot,settings_shared,parameters_shared)=prepared.shared_procedure_aliases(procedure);
  for (slot,actual) in [
   (metadata_slot,Alias::Metadata(procedure)),
   (settings_shared.then_some(2),Alias::Settings(&procedure.settings)),
   (parameters_shared.then_some(3),Alias::Parameters(&procedure.signature.parameters)),
  ]{
   let duplicate=match slot {
    Some(slot)=>std::mem::replace(&mut seen[slot],true),
    None=>match &actual {
     Alias::Metadata(owner)=>recent_metadata.seen(Arc::as_ptr(*owner) as usize,0),
     Alias::Parameters(owner)=>recent_parameters.seen(owner.as_ptr() as usize,owner.len()),
     _=>false,
    },
   };
   if duplicate {
    // Preserve the original cancellation/error check for every observed field.
    checkpoint(a)?;
   }else{f(actual)?;}
  }
  for setting in procedure.settings.iter(){
   let dm_ir::ProcedureSettingNode::Setting(setting)=setting else{return Err(io::Error::new(io::ErrorKind::InvalidData,"original prepared settings are not flat"))};
   f(Alias::Tokens(&setting.value.tokens))?;
  }
  for parameter in procedure.signature.parameters.iter(){
   if let Some(tail)=parameter.tail_allocation(){f(Alias::ParameterTail(tail))?;}
   for expression in [&parameter.default,&parameter.input_annotation,&parameter.source_expression].into_iter().flatten(){f(Alias::Tokens(&expression.tokens))?}
   if let Some(array)=&parameter.array{f(Alias::Array(array))?;f(Alias::Dimensions(&array.dimensions))?;for expression in array.dimensions.iter().flatten(){f(Alias::Tokens(&expression.tokens))?}}
  }
  if let Some(expression)=&procedure.signature.return_annotation{f(Alias::Tokens(&expression.tokens))?}
 }
 Ok(())
}
/// Bookkeeping inside the existing QueryDb, not a new model/cache/input store.
/// It retains only reservations and weak resource observations. Groups with
/// live detached aliases continue to consume the SAME original native budget.
#[derive(Default)]pub struct OriginalSignatureAliasCensus{rows:Vec<Arc<OriginalSignatureAliasGroup>>,coordination:Option<dm_syntax::SettingRootLease>}
impl OriginalSignatureAliasCensus{
 pub fn prune(&mut self,a:&dm_syntax::SettingAdmission<'_>)->io::Result<()>{
  if self.coordination.as_ref().is_some_and(|root|!a.matches_lease_domain(root)){return Err(io::Error::new(io::ErrorKind::InvalidInput,"signature census uses another native resource owner"))}
  let mut i=0;while i<self.rows.len(){a.checkpoint()?;if self.rows[i].live(){i+=1}else{self.rows.swap_remove(i);}}if self.rows.is_empty(){self.rows=Vec::new();self.coordination=None;}Ok(())
 }
 pub fn retain(&mut self,row:Arc<OriginalSignatureAliasGroup>,a:&dm_syntax::SettingAdmission<'_>)->io::Result<()>{
  self.prune(a)?;row.require_domain(a)?;if self.rows.iter().any(|old|Arc::ptr_eq(old,&row)){return Ok(())}
  if !row.live(){return Ok(())}
  if self.rows.len()==self.rows.capacity(){
   let count=self.rows.capacity().max(2).checked_mul(2).ok_or_else(oom)?;let bytes=count.checked_mul(std::mem::size_of::<Arc<OriginalSignatureAliasGroup>>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(128)).ok_or_else(oom)?;
   match &mut self.coordination{Some(lease)=>if bytes>lease.bytes(){a.grow(lease,bytes-lease.bytes())?},None=>self.coordination=Some(a.reserve(bytes)?)}
   let mut next=Vec::new();next.try_reserve_exact(count).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if next.capacity()>count.checked_mul(4).ok_or_else(oom)?{return Err(oom())}next.append(&mut self.rows);self.rows=next;
  }
  a.checkpoint()?;self.rows.push(row);Ok(())
 }
 pub fn live_groups(&self)->usize{self.rows.len()}
 pub fn visit_resource_storage(&self,mut visit:impl FnMut(usize,usize,usize)){if self.rows.capacity()!=0{visit(self.rows.as_ptr()as usize,self.rows.capacity()*std::mem::size_of::<Arc<OriginalSignatureAliasGroup>>(),std::mem::align_of::<Arc<OriginalSignatureAliasGroup>>())}for row in &self.rows{row.visit_storage(&mut visit)}}
}

impl std::fmt::Debug for OriginalSignatureAliasCensus{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("OriginalSignatureAliasCensus").field("resource_groups",&self.rows.len()).finish_non_exhaustive()}}

#[cfg(test)]
mod exact_capacity_controls {
 use super::*;
 use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]
 fn recent_aliases_distinguish_pointer_and_extent_and_only_forget_on_collision() {
  let mut recent=RecentAliases::<1>::new();
  assert!(!recent.seen(0x1234,2));
  assert!(recent.seen(0x1234,2));
  assert!(!recent.seen(0x1234,3));
  assert!(recent.seen(0x1234,3));
  assert!(!recent.seen(0x5678,3));
  assert!(!recent.seen(0x1234,3));
  assert!(recent.seen(0x1234,3));
 }

 #[test]
 fn exact_alias_coordination_denial_preserves_the_already_funded_slots(){
  let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let fixed=group_bytes().unwrap();
  let rows=std::mem::size_of::<Weak<dm_ir::DeclarationMeaning>>()
   + 2*std::mem::size_of::<Weak<[u8]>>();
  let lease_row=std::mem::size_of::<Arc<dm_syntax::SettingRootLease>>();
  let admission=dm_syntax::SettingAdmission::new(&counter,dm_syntax::SettingChargeCounter::root_allocation_bytes() + (fixed+rows+lease_row-1),&||Ok(()));
  let mut owner=admission.reserve(fixed).unwrap();
  let counts=AliasCounts{members:1,canonical:2,..AliasCounts::default()};
  let aliases=TypedAliases::allocate(&counts,&mut owner,&admission).unwrap();
  assert_eq!(aliases.members.capacity(),1);
  assert_eq!(aliases.canonical.capacity(),2);
  assert_eq!(aliases.tokens.capacity(),0);
  assert_eq!(owner.bytes(),fixed+rows);
  let error=exact_rows::<Arc<dm_syntax::SettingRootLease>>(1,&mut owner,&admission).err().unwrap();
  assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);
  assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes() + (fixed+rows));
  drop(aliases);
  drop(owner);
  assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
}
