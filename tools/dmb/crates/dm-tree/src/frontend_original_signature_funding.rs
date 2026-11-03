//! Resource-only lifetime census for public IR aliases of the SAME native
//! primary signature products. No source/name/model lookup or semantic answer.
use super::*;
use std::sync::Weak;
use std::io;
enum Alias{
 Metadata(Weak<dm_ir::ProcedureMetadata>),Parameters(Weak<[dm_ir::Parameter]>),
 Array(Weak<dm_ir::ArrayDeclaration>),Dimensions(Weak<[Option<dm_ir::SymbolicExpression>]>),
 Tokens(Weak<[dm_ir::ExpressionToken]>),WideItems(Weak<[dm_syntax::Item]>),
}
impl Alias{fn live(&self)->bool{match self{Self::Metadata(x)=>x.strong_count()!=0,Self::Parameters(x)=>x.strong_count()!=0,Self::Array(x)=>x.strong_count()!=0,Self::Dimensions(x)=>x.strong_count()!=0,Self::Tokens(x)=>x.strong_count()!=0,Self::WideItems(x)=>x.strong_count()!=0}}}
/// Public for the existing native resource owner only. Private fields cannot
/// carry source/semantic admission, recreate a graph, or retain an IR payload.
pub struct OriginalSignatureAliasGroup{
 aliases:Vec<Alias>,reservations:Vec<Arc<dm_syntax::SettingRootLease>>,
 _coordination:dm_syntax::SettingRootLease,
}
impl std::fmt::Debug for OriginalSignatureAliasGroup{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("OriginalSignatureAliasGroup").field("weak_observations",&self.aliases.len()).field("signature_reservations",&self.reservations.len()).finish_non_exhaustive()}}
impl OriginalSignatureAliasGroup{
 fn live(&self)->bool{self.aliases.iter().any(Alias::live)}
 fn require_domain(&self,a:&dm_syntax::SettingAdmission<'_>)->io::Result<()>{if !a.matches_lease_domain(&self._coordination)||self.reservations.iter().any(|row|!a.matches_lease_domain(row)){return Err(io::Error::new(io::ErrorKind::InvalidInput,"original signature resource census belongs to another native counter"))}Ok(())}
 pub(super) fn capture(facts:&crate::AdaptedDeclarations,prepared:&crate::procedure::original_primary_signatures::PreparedOriginalSignatures,a:&dm_syntax::SettingAdmission<'_>)->io::Result<Arc<Self>>{
  prepared.require_consumed().map_err(|reason|io::Error::new(io::ErrorKind::InvalidData,reason))?;
  let mut alias_count=0usize;let mut lease_count=0usize;
  visit_aliases(facts,&mut |_|{a.checkpoint()?;alias_count=alias_count.checked_add(1).ok_or_else(oom)?;Ok(())})?;
  prepared.visit_signature_reservations(|_|{lease_count=lease_count.saturating_add(1)});
  if lease_count==usize::MAX{return Err(oom())}
  let bytes=alias_count.checked_mul(std::mem::size_of::<Alias>()).and_then(|n|lease_count.checked_mul(std::mem::size_of::<Arc<dm_syntax::SettingRootLease>>()).and_then(|m|n.checked_add(m))).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(std::mem::size_of::<Self>()+256)).ok_or_else(oom)?;
  let coordination=a.reserve(bytes)?;let mut aliases=Vec::new();aliases.try_reserve_exact(alias_count).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;let mut reservations=Vec::new();reservations.try_reserve_exact(lease_count).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;
  if aliases.capacity()>alias_count.saturating_mul(4).saturating_add(1)||reservations.capacity()>lease_count.saturating_mul(4).saturating_add(1){return Err(oom())}
  visit_aliases(facts,&mut|row|{a.checkpoint()?;if aliases.len()==aliases.capacity(){return Err(oom())}aliases.push(row);Ok(())})?;
  prepared.visit_signature_reservations(|row|reservations.push(Arc::clone(row)));
  a.checkpoint()?;Ok(Arc::new(Self{aliases,reservations,_coordination:coordination}))
 }

 pub(super) fn retain_wide_items(&mut self,items:&Arc<[dm_syntax::Item]>,parser:&Arc<dm_syntax::SettingRootLease>,a:&dm_syntax::SettingAdmission<'_>)->io::Result<()>{
  a.checkpoint()?;self.require_domain(a)?;if !a.matches_lease_domain(parser){return Err(io::Error::new(io::ErrorKind::InvalidInput,"wide primary allocation uses another parser reservation"))}
  let alias_count=self.aliases.len().checked_add(1).ok_or_else(oom)?;let lease_count=self.reservations.len().checked_add(1).ok_or_else(oom)?;
  let alias_peak=if self.aliases.len()==self.aliases.capacity(){alias_count.checked_mul(4).and_then(|n|n.checked_mul(std::mem::size_of::<Alias>())).ok_or_else(oom)?}else{0};let lease_peak=if self.reservations.len()==self.reservations.capacity(){lease_count.checked_mul(4).and_then(|n|n.checked_mul(std::mem::size_of::<Arc<dm_syntax::SettingRootLease>>())).ok_or_else(oom)?}else{0};let extra=alias_peak.checked_add(lease_peak).ok_or_else(oom)?;if extra!=0{a.grow(&mut self._coordination,extra)?}
  self.aliases.try_reserve_exact(1).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;self.reservations.try_reserve_exact(1).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if self.aliases.capacity()>alias_count.checked_mul(4).ok_or_else(oom)?||self.reservations.capacity()>lease_count.checked_mul(4).ok_or_else(oom)?{return Err(oom())}
  self.aliases.push(Alias::WideItems(Arc::downgrade(items)));self.reservations.push(Arc::clone(parser));a.checkpoint()?;Ok(())
 }
 pub(super) fn visit_storage(&self,mut f:impl FnMut(usize,usize,usize)){
  f(self as*const Self as usize,std::mem::size_of::<Self>()+2*std::mem::size_of::<usize>(),std::mem::align_of::<Self>());for lease in &self.reservations{f(Arc::as_ptr(lease)as usize,std::mem::size_of::<dm_syntax::SettingRootLease>()+2*std::mem::size_of::<usize>(),std::mem::align_of::<dm_syntax::SettingRootLease>())}
  if self.aliases.capacity()!=0{f(self.aliases.as_ptr()as usize,self.aliases.capacity()*std::mem::size_of::<Alias>(),std::mem::align_of::<Alias>())}
  if self.reservations.capacity()!=0{f(self.reservations.as_ptr()as usize,self.reservations.capacity()*std::mem::size_of::<Arc<dm_syntax::SettingRootLease>>(),std::mem::align_of::<Arc<dm_syntax::SettingRootLease>>())}
 }
}
fn oom()->io::Error{io::Error::from(io::ErrorKind::OutOfMemory)}
fn visit_aliases(facts:&crate::AdaptedDeclarations,f:&mut impl FnMut(Alias)->io::Result<()>)->io::Result<()>{
 for skeleton in &facts.skeletons{let crate::Skeleton::Member{metadata,..}=skeleton else{continue};let Some(procedure)=&metadata.procedure else{continue};
  f(Alias::Metadata(Arc::downgrade(procedure)))?;f(Alias::Parameters(Arc::downgrade(&procedure.signature.parameters)))?;
  for parameter in procedure.signature.parameters.iter(){
   for expression in [&parameter.default,&parameter.input_annotation,&parameter.source_expression].into_iter().flatten(){f(Alias::Tokens(Arc::downgrade(&expression.tokens)))?}
   if let Some(array)=&parameter.array{f(Alias::Array(Arc::downgrade(array)))?;f(Alias::Dimensions(Arc::downgrade(&array.dimensions)))?;for expression in array.dimensions.iter().flatten(){f(Alias::Tokens(Arc::downgrade(&expression.tokens)))?}}
  }
  if let Some(expression)=&procedure.signature.return_annotation{f(Alias::Tokens(Arc::downgrade(&expression.tokens)))?}
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
