//! A private allocation envelope around the SAME live macro environment.
//! No source role, parser, second dictionary, snapshot cache or counter.
use super::{MacroEnvironment, OriginalDefinitionProduct, Binding, original_poll};
use crate::{Macro, macro_expansion::OriginalMacroRows, regions::DefinitionOrigin};
use dm_syntax::{SettingAdmission, SettingRootLease};
use std::{alloc::Layout,io,mem,sync::Arc};

// This bound is tied to Cargo.lock's im15.1.0 /sized-chunks0.6.5:
// nodes/btree.rs Node has Chunk<(K,V),U64> and Chunk<Option<PoolRef<Node>>,U65>;
// sized_chunk::Chunk has two usize indices plus an inline MaybeUninit array.
// fakepool::Arc is a one-Arc wrapper. Extra alignment covers both chunks and
// the node; optional pool references reserve pointer plus a full discriminant
// word without assuming niche layout. This is an admission bound, NOT measured heap.
fn node_bytes()->io::Result<usize>{
 let word=mem::size_of::<usize>();
 64usize.checked_mul(mem::size_of::<(Arc<str>,Arc<Binding>)>())
  .and_then(|n|n.checked_add(65*2*word))
  .and_then(|n|n.checked_add(8*word)).ok_or(io::ErrorKind::OutOfMemory.into())
}
fn map_peak(names:usize)->io::Result<usize>{
 // Every completed nonroot node contains >=31 keys. A mutation can hold the
 // old and new trees and <=8 node-sized temporaries per level (the pinned
 // insert/split/remove/rotate paths); root replacement adds <=16 nodes.
 // Binary height is a conservative upper bound on the actual B-tree height.
 let live=names/31+1;let height=(usize::BITS-names.leading_zeros())as usize+1;
 live.checked_mul(2).and_then(|n|n.checked_add(height.checked_mul(8)?))
  .and_then(|n|n.checked_add(16)).and_then(|n|n.checked_mul(node_bytes().ok()?))
  .ok_or(io::ErrorKind::OutOfMemory.into())
}
fn add(total:&mut usize,n:usize)->io::Result<()>{*total=total.checked_add(n).ok_or(io::ErrorKind::OutOfMemory)?;Ok(())}
fn text_bound(bytes:usize)->io::Result<usize>{bytes.checked_mul(4).and_then(|n|n.checked_add(32)).ok_or(io::ErrorKind::OutOfMemory.into())}
#[cfg(test)]std::thread_local!{static METADATA_COPIES:std::cell::Cell<usize>=const{std::cell::Cell::new(0)};}
fn owned_text(value:&str)->io::Result<String>{#[cfg(test)]METADATA_COPIES.with(|n|n.set(n.get()+1));let mut text=String::new();text.try_reserve_exact(value.len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if text.capacity()>text_bound(value.len())?{return Err(io::ErrorKind::OutOfMemory.into())}text.push_str(value);Ok(text)}

fn metadata_fixed_bound(name:&str)->io::Result<usize>{
 let mut bytes=mem::size_of::<Binding>()+mem::size_of::<Macro>()+8*mem::size_of::<usize>();
 add(&mut bytes,text_bound(name.len())?)?;
 Ok(bytes)
}

fn retained_metadata_bound(name:&str,definition:&Macro)->io::Result<usize>{
 let mut bytes=metadata_fixed_bound(name)?;
 add(&mut bytes,definition.replacement.capacity())?;
 if let Some(parameters)=&definition.parameters{
  add(&mut bytes,parameters.capacity().checked_mul(mem::size_of::<String>()).ok_or(io::ErrorKind::OutOfMemory)?)?;
  for name in parameters{add(&mut bytes,name.capacity())?;}
 }
 Ok(bytes)
}

/// Sorted current bindings after expansion, with no mutable environment,
/// previous binding chain, copied macro text, or authority over source.
pub(crate) struct OriginalFinalMacros {
    rows: OriginalMacroRows<(Arc<str>, Arc<Macro>)>,
    credit: SettingRootLease,
}

fn arc_bytes(payload: Layout) -> io::Result<usize> {
    Layout::new::<[usize; 2]>()
        .extend(payload)
        .map(|(layout, _)| layout.pad_to_align().size())
        .map_err(|_| io::ErrorKind::OutOfMemory.into())
}

impl OriginalFinalMacros {
    #[cfg(test)]
    pub(crate) fn empty(a: &SettingAdmission<'_>) -> io::Result<Self> {
        Ok(Self {
            rows: OriginalMacroRows::new(a)?,
            credit: a.reserve(0).map_err(|e| a.take_operational_error().unwrap_or(e))?,
        })
    }

    pub(crate) fn is_admitted_by(&self, a: &SettingAdmission<'_>) -> bool {
        a.matches_lease_domain(&self.credit)
    }

    pub(crate) fn get(&self, name: &str) -> Option<&Macro> {
        let rows = self.rows.as_slice();
        let index = rows.binary_search_by(|(key, _)| key.as_ref().cmp(name)).ok()?;
        Some(rows[index].1.as_ref())
    }

    pub(crate) fn iter(&self) -> impl ExactSizeIterator<Item = (&str, &Macro)> {
        self.rows.as_slice().iter().map(|(name, value)| (name.as_ref(), value.as_ref()))
    }

    pub(crate) fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        let logical = mem::size_of_val(self.rows.as_slice());
        self.rows.visit_allocation(|address, capacity| visit(address, logical, capacity));
        self.credit.visit_counter_storage(|address, bytes| visit(address, bytes, bytes));
        for (key, value) in self.rows.as_slice() {
            let name_bytes = arc_bytes(Layout::for_value(key.as_ref())).expect("live macro name layout");
            visit(Arc::as_ptr(key) as *const u8 as usize, key.len(), name_bytes);
            let macro_bytes = arc_bytes(Layout::new::<Macro>()).expect("live macro layout");
            visit(Arc::as_ptr(value) as usize, mem::size_of::<Macro>(), macro_bytes);
            let mut text = |value: &String| {
                if value.capacity() != 0 {
                    visit(value.as_ptr() as usize, value.len(), value.capacity());
                }
            };
            text(&value.replacement);
            if let Some(parameters) = &value.parameters {
                if parameters.capacity() != 0 {
                    let entry_bytes = mem::size_of::<String>();
                    visit(parameters.as_ptr() as usize, parameters.len() * entry_bytes,
                        parameters.capacity() * entry_bytes);
                }
                for parameter in parameters {
                    if parameter.capacity() != 0 {
                        visit(parameter.as_ptr() as usize, parameter.len(), parameter.capacity());
                    }
                }
            }
        }
    }
}

/// The actual stream must not clone the borrowed environment or let a native
/// shared_definition Arc escape. Finalization transfers just the current
/// definitions and their funding, after dropping the old expansion graph.
/// During expansion the aggregate covers every admitted epoch through undef
/// (a stack or shared binding may still own it).
pub(crate) struct OriginalEnvironment{
 environment:MacroEnvironment,
 allowance:SettingRootLease,
 metadata:usize,
 map_high_water:usize,
}
impl OriginalEnvironment{
 pub(crate) fn new(a:&SettingAdmission<'_>)->io::Result<Self>{
  original_poll(a)?;let map=map_peak(0)?;
  let allowance=a.reserve(map).map_err(|e|a.take_operational_error().unwrap_or(e))?;
  original_poll(a)?;Ok(Self{environment:MacroEnvironment::default(),allowance,metadata:0,map_high_water:map})
 }
 #[cfg(debug_assertions)]
 pub(crate) fn trace_reservations(&self) -> (usize, usize, usize) {
  (self.environment.len(), self.metadata, self.map_high_water)
 }
 /// An operation-scoped read loan, not an exported snapshot/owner.
 pub(crate) fn environment(&self)->&MacroEnvironment{&self.environment}
 pub(crate) fn len(&self)->usize{self.environment.len()}
 fn admit(&mut self,extra_metadata:usize,names:usize,a:&SettingAdmission<'_>)->io::Result<()>{
  original_poll(a)?;if !a.matches_lease_domain(&self.allowance){return Err(io::Error::new(io::ErrorKind::InvalidInput,"macro coordination belongs to another resource operation"))}
  let metadata=self.metadata.checked_add(extra_metadata).ok_or(io::ErrorKind::OutOfMemory)?;
  let map=self.map_high_water.max(map_peak(names)?);let target=metadata.checked_add(map).ok_or(io::ErrorKind::OutOfMemory)?;
  let extra=target.checked_sub(self.allowance.bytes()).ok_or(io::ErrorKind::InvalidInput)?;
  if extra!=0{a.grow(&mut self.allowance,extra).map_err(|e|a.take_operational_error().unwrap_or(e))?;}
  self.metadata=metadata;self.map_high_water=map;original_poll(a)
 }
 fn insert_measured_using(&mut self,name:&str,definition:Macro,origin:Option<DefinitionOrigin>,product:Arc<OriginalDefinitionProduct>,bound:usize,a:&SettingAdmission<'_>)->io::Result<()>{
  let retained=retained_metadata_bound(name,&definition)?;
  let refund=bound.checked_sub(retained).ok_or(io::ErrorKind::OutOfMemory)?;
  let adjusted=self.metadata.checked_sub(refund).ok_or(io::ErrorKind::InvalidData)?;
  // Strings and the parameter Vec move unchanged into the new Binding. Its
  // fixed/key allowance, previous bindings, product leases and map peak stay
  // intact. Any checked release failure occurs before the epoch is installed.
  let allowance=&mut self.allowance;
  let metadata=&mut self.metadata;
  self.environment.insert_original_stacked_before_commit_using(name,definition,origin,product,a,||{
   if refund!=0{
    a.shrink(allowance,refund).map_err(|e|a.take_operational_error().unwrap_or(e))?;
    *metadata=adjusted;
   }
   Ok(())
  })
 }
 pub(crate) fn insert_borrowed_using(&mut self,name:&str,metadata:&Macro,origin:Option<DefinitionOrigin>,product:Arc<OriginalDefinitionProduct>,a:&SettingAdmission<'_>)->io::Result<()>{
  original_poll(a)?;
  let count=metadata.parameters.as_ref().map_or(0,Vec::len);
  let mut bound=metadata_fixed_bound(name)?;
  add(&mut bound,text_bound(metadata.replacement.len())?)?;
  add(&mut bound,count.checked_mul(4*mem::size_of::<String>()).ok_or(io::ErrorKind::OutOfMemory)?)?;
  if let Some(names)=&metadata.parameters{for name in names{original_poll(a)?;add(&mut bound,text_bound(name.len())?)?;}}
  self.admit(bound,self.environment.len().checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?,a)?;
  // No metadata clone or key/Binding/Macro Arc allocation occurs before admit.
  let parameters=match &metadata.parameters{None=>None,Some(names)=>{let mut values=Vec::new();values.try_reserve_exact(count).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if values.capacity()>count.saturating_mul(4){return Err(io::ErrorKind::OutOfMemory.into())}for name in names{original_poll(a)?;values.push(owned_text(name)?);}Some(values)}};
  let definition=Macro{parameters,variadic:metadata.variadic,replacement:owned_text(&metadata.replacement)?};
  self.insert_measured_using(name,definition,origin,product,bound,a)
 }
 /// Raw directive supplies already-admitted grammar text; no native Macro
 /// temporary is allocated before this same operation's metadata pregrant.
 pub(crate) fn insert_product_using(&mut self,name:&str,replacement:&str,origin:Option<DefinitionOrigin>,product:Arc<OriginalDefinitionProduct>,a:&SettingAdmission<'_>)->io::Result<()>{
  original_poll(a)?;let params=product.definition.parameters.as_ref();let count=params.map_or(0,|p|p.len());
  let mut bound=metadata_fixed_bound(name)?;add(&mut bound,text_bound(replacement.len())?)?;add(&mut bound,count.checked_mul(4*mem::size_of::<String>()).ok_or(io::ErrorKind::OutOfMemory)?)?;
  if let Some(names)=params{for name in names.as_slice(){original_poll(a)?;add(&mut bound,text_bound(name.as_str().len())?)?;}}
  self.admit(bound,self.environment.len().checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?,a)?;
  let parameters=match params{None=>None,Some(names)=>{let mut values=Vec::new();values.try_reserve_exact(count).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if values.capacity()>count.saturating_mul(4){return Err(io::ErrorKind::OutOfMemory.into())}for name in names.as_slice(){original_poll(a)?;values.push(owned_text(name.as_str())?);}Some(values)}};
  let definition=Macro{parameters,variadic:product.definition.variadic,replacement:owned_text(replacement)?};self.insert_measured_using(name,definition,origin,product,bound,a)
 }
 /// Publish the current macro definitions by transferring their existing
 /// owners. The persistent map orders them already; keep only a funded
 /// sorted row table and no copy of the names or definition payloads.
 pub(crate) fn into_final_macros_using(self, a: &SettingAdmission<'_>) -> io::Result<OriginalFinalMacros> {
  original_poll(a)?;
  if !a.matches_lease_domain(&self.allowance) {
   return Err(io::Error::new(io::ErrorKind::InvalidInput, "final macros belong to another operation"));
  }
  let mut rows = OriginalMacroRows::new(a)?;
  rows.ensure(self.environment.len(), a)?;
  let mut retained = 0usize;
  for (name, binding) in &self.environment.bindings {
   original_poll(a)?;
   let definition = &binding.definition;
   add(&mut retained, arc_bytes(Layout::for_value(name.as_ref()))?)?;
   add(&mut retained, arc_bytes(Layout::new::<Macro>())?)?;
   add(&mut retained, definition.replacement.capacity())?;
   if let Some(parameters) = &definition.parameters {
    add(&mut retained, mem::size_of::<String>().checked_mul(parameters.capacity()).ok_or(io::ErrorKind::OutOfMemory)?)?;
    for parameter in parameters {
     original_poll(a)?;
     add(&mut retained, parameter.capacity())?;
    }
   }
   rows.push((Arc::clone(name), Arc::clone(definition)), a)?;
  }
  let refund = self.allowance.bytes().checked_sub(retained).ok_or(io::ErrorKind::InvalidData)?;
  let Self { environment, allowance: credit, .. } = self;
  drop(environment);
  // Construct the owner before the fallible refund so alias fields always
  // drop before their matching credit, including cancellation.
  let mut result = OriginalFinalMacros { rows, credit };
  a.shrink(&mut result.credit, refund).map_err(|e| a.take_operational_error().unwrap_or(e))?;
  Ok(result)
 }
 /// Pinned Original DefineMap::remove pops one current epoch, restoring the
 /// preceding authored/builtin binding when one remains.
 pub(crate) fn remove_using(&mut self,name:&str,a:&SettingAdmission<'_>)->io::Result<()>{self.remove_stacked_using(name,a)}
 pub(crate) fn remove_stacked_using(&mut self,name:&str,a:&SettingAdmission<'_>)->io::Result<()>{
  // Restoration allocates a fresh key Arc in the existing implementation.
  self.admit(text_bound(name.len())?,self.environment.len(),a)?;
  self.environment.remove_stacked(name);Ok(())
 }
 /// Build the SAME final initial binding recipe directly from borrowed
 /// configuration. Only one temporary Macro exists at a time; no second map,
 /// unfunded initial table, hidden binding history or lookup-time tokenization.
 /// The lexical factory is called once per final name, in BTreeMap order.
 pub(crate) fn install_initial_definitions_using(&mut self,initial:crate::InitialEnvironment,caller:&std::collections::BTreeMap<String,String>,a:&SettingAdmission<'_>,factory:&mut dyn FnMut(crate::initial_environment::OriginalInitialDefinition<'_>,&SettingAdmission<'_>)->io::Result<crate::macro_expansion::OriginalMacroDefinition<'static>>)->io::Result<()>{
  original_poll(a)?;
  if initial!=crate::InitialEnvironment::OriginalChecker0290||!self.environment.is_empty(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"direct Original initial issuance requires its actual empty environment"))}
  let mut next=Self::new(a)?;
  let mut previous:Option<&str>=None;
  let mut caller_names=caller.keys().peekable();
  loop{
   original_poll(a)?;
   // The pinned tables are small immutable DATA. Select the next final key
   // without allocating an ordering buffer or cloning any metadata.
   let mut chosen:Option<&str>=None;
   // Explicit loops keep the borrowed key tied to static DATA or actual caller
   // storage, rather than to a transient iterator-owned String.
   for &(name,_) in crate::InitialEnvironment::original_constants(){if previous.is_none_or(|p|name>p)&&chosen.is_none_or(|p|name<p){chosen=Some(name)}}
   for &(name,_,_) in crate::InitialEnvironment::original_functions(){if previous.is_none_or(|p|name>p)&&chosen.is_none_or(|p|name<p){chosen=Some(name)}}
   if let Some(key)=caller_names.peek().copied(){let name=key.as_str();if chosen.is_none_or(|p|name<p){chosen=Some(name)}}
   let Some(name)=chosen else{break};
   let (parameters,replacement)=if let Some(value)=caller.get(name){(None,value.as_str())}
    else if let Some(&(_,value))=crate::InitialEnvironment::original_constants().iter().find(|(key,_)|*key==name){(None,value)}
    else{let &(_,parameters,value)=crate::InitialEnvironment::original_functions().iter().find(|(key,_,_)|*key==name).ok_or(io::ErrorKind::InvalidData)?;(Some(parameters),value)};
   let count=parameters.map_or(0,|p|p.len());
   let mut bytes=mem::size_of::<Macro>();add(&mut bytes,text_bound(replacement.len())?)?;
   add(&mut bytes,count.checked_mul(4*mem::size_of::<String>()).ok_or(io::ErrorKind::OutOfMemory)?)?;
   if let Some(names)=parameters{for name in names{original_poll(a)?;add(&mut bytes,text_bound(name.len())?)?;}}
   // This lease precedes every temporary String/Vec allocation and outlives
   // their physical destruction on success, quota refusal or actual IO error.
   let temporary=a.reserve(bytes).map_err(|e|a.take_operational_error().unwrap_or(e))?;
   let result=(||{
    let parameters=match parameters{None=>None,Some(names)=>{let mut values=Vec::new();values.try_reserve_exact(count).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if values.capacity()>count.saturating_mul(4){return Err(io::ErrorKind::OutOfMemory.into())}for name in names{original_poll(a)?;values.push(owned_text(name)?);}Some(values)}};
    let metadata=Macro{parameters,variadic:false,replacement:owned_text(replacement)?};
    crate::initial_environment::with_original_initial_definition_using(initial,name,&metadata,caller,a,|input|{
     let definition=factory(input,a)?;
     for token in definition.replacement.as_slice(){original_poll(a)?;if token.lexical_frame.is_some()||token.lexical_span.is_some()||token.origin.invocation{return Err(io::Error::new(io::ErrorKind::InvalidInput,"initial definition contains fabricated physical token provenance"))}}
     let product=OriginalDefinitionProduct::from_actual_product_using(definition,a)?;
     next.insert_borrowed_using(name,&metadata,None,product,a)
    })
   })();
   drop(temporary);result?;if caller_names.peek().copied().is_some_and(|key|key.as_str()==name){caller_names.next();}previous=Some(name);
  }
  original_poll(a)?;*self=next;Ok(())
 }
 pub(crate) fn install_initial_using(&mut self,initial:crate::InitialEnvironment,final_macros:&std::collections::BTreeMap<String,Macro>,caller:&std::collections::BTreeMap<String,String>,a:&SettingAdmission<'_>,factory:&mut dyn FnMut(crate::initial_environment::OriginalInitialDefinition<'_>,&SettingAdmission<'_>)->io::Result<crate::macro_expansion::OriginalMacroDefinition<'static>>)->io::Result<()>{
  original_poll(a)?;if !self.environment.is_empty(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"initial macros require the actual empty environment"))}
  let mut next=Self::new(a)?;
  crate::initial_environment::visit_original_bootstrap_using(initial,final_macros,caller,a,&mut|input|{
   let name=input.name();let metadata=input.metadata();let definition=factory(input,a)?;
   for token in definition.replacement.as_slice(){original_poll(a)?;if token.lexical_frame.is_some()||token.lexical_span.is_some()||token.origin.invocation{return Err(io::Error::new(io::ErrorKind::InvalidInput,"initial definition contains fabricated physical token provenance"))}}
   let product=OriginalDefinitionProduct::from_actual_product_using(definition,a)?;
   next.insert_borrowed_using(name,metadata,None,product,a)
  })?;original_poll(a)?;*self=next;Ok(())
 }
}

#[cfg(test)]mod tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]fn initial_coordination_is_admitted_before_the_actual_empty_map_and_foreign_or_first_io_cannot_mutate(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,4<<20,&||Ok(()));let mut env=OriginalEnvironment::new(&a).unwrap();assert!(used.load(Ordering::Acquire)>0);assert_eq!(env.len(),0);
  let other=Arc::new(AtomicUsize::new(0));let foreign=SettingAdmission::new(&other,4<<20,&||Ok(()));assert_eq!(env.remove_stacked_using("missing",&foreign).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(env.len(),0);
  let fault=||Err(io::Error::from_raw_os_error(1450));let stopped=SettingAdmission::new(&used,4<<20,&fault);assert_eq!(env.remove_stacked_using("missing",&stopped).unwrap_err().raw_os_error(),Some(1450));drop(env);assert_eq!(used.load(Ordering::Acquire),0);
  let tiny=SettingAdmission::new(&used,1,&||Ok(()));assert_eq!(OriginalEnvironment::new(&tiny).err().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),0);
 }
 fn empty_product(a:&SettingAdmission<'_>)->Arc<OriginalDefinitionProduct>{OriginalDefinitionProduct::from_actual_product_using(crate::macro_expansion::OriginalMacroDefinition{parameters:None,variadic:false,replacement:crate::macro_expansion::OriginalMacroRows::new(a).unwrap()},a).unwrap()}
 #[test]fn actual_metadata_quota_precedes_first_clone_and_keeps_same_map_epoch(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,128*1024,&||Ok(()));let mut env=OriginalEnvironment::new(&a).unwrap();let source=Macro{parameters:None,variadic:false,replacement:"x".repeat(128*1024)};let before=METADATA_COPIES.with(|n|n.get());let fingerprint=env.environment().fingerprint();assert_eq!(env.insert_borrowed_using("X",&source,None,empty_product(&a),&a).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert_eq!(METADATA_COPIES.with(|n|n.get()),before,"real clone helper must not run before quota");assert_eq!(env.len(),0);assert_eq!(env.environment().fingerprint(),fingerprint);drop(env);assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]
 fn macro_epoch_funds_actual_parameter_and_replacement_capacity_through_redefine_and_undef(){
  fn function_product(a:&SettingAdmission<'_>)->Arc<OriginalDefinitionProduct>{
   let mut parameters=crate::macro_expansion::OriginalMacroRows::new(a).unwrap();
   for name in ["first","second"]{
    let mut text=crate::macro_expansion::OriginalMacroText::new(a).unwrap();
    text.push_str(name,a).unwrap();
    parameters.push(text,a).unwrap();
   }
   OriginalDefinitionProduct::from_actual_product_using(crate::macro_expansion::OriginalMacroDefinition{
    parameters:Some(parameters),variadic:false,
    replacement:crate::macro_expansion::OriginalMacroRows::new(a).unwrap(),
   },a).unwrap()
  }
  fn expected(definition:&Macro)->usize{
   let parameters=definition.parameters.as_ref().unwrap();
   mem::size_of::<Binding>()+mem::size_of::<Macro>()+8*mem::size_of::<usize>()
    +text_bound("A".len()).unwrap()+definition.replacement.capacity()
    +parameters.capacity()*mem::size_of::<String>()
    +parameters.iter().map(String::capacity).sum::<usize>()
  }
  let used=Arc::new(AtomicUsize::new(0));
  let a=SettingAdmission::new(&used,4<<20,&||Ok(()));
  let mut env=OriginalEnvironment::new(&a).unwrap();
  let original=Macro{
   parameters:Some(vec!["first".into(),"second".into()]),
   variadic:false,replacement:"x".repeat(8192),
  };
  env.insert_borrowed_using("A",&original,None,function_product(&a),&a).unwrap();
  let first=env.environment().shared_definition("A").unwrap();
  assert_eq!(env.metadata,expected(&first));
  assert!(env.metadata<text_bound(original.replacement.len()).unwrap(),
    "the 4x preflight is no longer held by the new epoch");
  assert_eq!(env.allowance.bytes(),env.map_high_water+env.metadata);
  let before=env.metadata;
  let replacement="y".repeat(4096);
  env.insert_product_using("A",&replacement,None,function_product(&a),&a).unwrap();
  let second=env.environment().shared_definition("A").unwrap();
  assert_eq!(env.metadata,before+expected(&second));
  assert_eq!(env.allowance.bytes(),env.map_high_water+env.metadata);
  let stacked=env.metadata;
  env.remove_using("A",&a).unwrap();
  assert!(Arc::ptr_eq(&first,&env.environment().shared_definition("A").unwrap()));
  assert_eq!(second.replacement,replacement,"actual detached metadata still live");
  assert_eq!(env.metadata,stacked+text_bound("A".len()).unwrap());
  env.remove_using("A",&a).unwrap();
  assert!(env.environment().shared_definition("A").is_none());
  assert_eq!(first.replacement,original.replacement);
  assert_eq!(env.metadata,stacked+2*text_bound("A".len()).unwrap(),
    "undef never refunds the actual epoch or opaque key allocation");
  assert!(used.load(Ordering::Acquire)>=env.allowance.bytes());
  drop((first,second,env));
  assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]
 fn actual_final_macros_keep_existing_allocations_and_drop_history_credit() {
  let used = Arc::new(AtomicUsize::new(0));
  let a = SettingAdmission::new(&used, 4 << 20, &|| Ok(()));
  let mut env = OriginalEnvironment::new(&a).unwrap();
  for _ in 0..1000 {
   env.insert_product_using("Z", "final payload", None, empty_product(&a), &a).unwrap();
  }
  env.insert_product_using("A", "", None, empty_product(&a), &a).unwrap();
  let before = used.load(Ordering::Acquire);
  let binding = env.environment.bindings.get("Z").unwrap();
  let definition = Arc::as_ptr(&binding.definition);
  let replacement = binding.definition.replacement.as_ptr();
  let names = env.environment.bindings.iter().map(|(key, _)| key.as_ptr()).collect::<Vec<_>>();
  let values = env.into_final_macros_using(&a).unwrap();
  assert_eq!(values.iter().map(|(name, _)| name).collect::<Vec<_>>(), ["A", "Z"]);
  assert_eq!(values.iter().map(|(name, _)| name.as_ptr()).collect::<Vec<_>>(), names);
  assert_eq!(std::ptr::from_ref(values.get("Z").unwrap()), definition);
  assert_eq!(values.get("Z").unwrap().replacement.as_ptr(), replacement);
  assert_eq!(values.get("Z").unwrap().replacement, "final payload");
  assert!(values.get("missing").is_none());
  assert!(used.load(Ordering::Acquire) < before);
  assert_eq!(used.load(Ordering::Acquire), values.credit.bytes() + values.rows.capacity() * mem::size_of::<(Arc<str>, Arc<Macro>)>());
  drop(values);
  assert_eq!(used.load(Ordering::Acquire), 0);
 }

 #[test]fn pinned_node_geometry_bound_scales_by_actual_btree_capacity_not_one_large_node_per_name(){assert!(map_peak(10_000).unwrap()<4<<20);assert!(map_peak(10_000).unwrap()>map_peak(100).unwrap());assert!(map_peak(usize::MAX).is_err());}
}

#[cfg(test)]mod direct_initial_tests{
 use super::*;use std::collections::BTreeMap;use std::sync::atomic::{AtomicUsize,Ordering};
 fn empty(a:&SettingAdmission<'_>)->io::Result<crate::macro_expansion::OriginalMacroDefinition<'static>>{Ok(crate::macro_expansion::OriginalMacroDefinition{parameters:None,variadic:false,replacement:crate::macro_expansion::OriginalMacroRows::new(a)?})}
 #[test]fn direct_initial_recipe_preserves_all_final_names_overrides_provenance_and_single_factory_order(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let mut env=OriginalEnvironment::new(&a).unwrap();let caller:BTreeMap<String,String>=BTreeMap::from([("TRUE".into(),"7".into()),("ASSERT".into(),"8".into()),("EXTRA".into(),"9".into())]);
  let mut expected=BTreeMap::new();crate::initial_environment::install(crate::InitialEnvironment::OriginalChecker0290,&mut expected);for(name,value)in &caller{expected.insert(name.clone(),Macro{parameters:None,variadic:false,replacement:value.clone()});}
  let mut seen=Vec::new();env.install_initial_definitions_using(crate::InitialEnvironment::OriginalChecker0290,&caller,&a,&mut|input,a|{let key=input.name();assert_eq!(input.metadata(),&expected[key]);assert_eq!(input.provenance(),if caller.contains_key(key){crate::initial_environment::OriginalInitialProvenance::CallerDefinition}else{crate::initial_environment::OriginalInitialProvenance::FixedDefault});seen.push(key.to_owned());let mut definition=empty(a)?;if let Some(names)=&input.metadata().parameters{let mut actual=crate::macro_expansion::OriginalMacroRows::new(a)?;for name in names{let mut text=crate::macro_expansion::OriginalMacroText::new(a)?;text.push_str(name,a)?;actual.push(text,a)?;}definition.parameters=Some(actual);}Ok(definition)}).unwrap();
  assert_eq!(seen,expected.keys().cloned().collect::<Vec<_>>());assert_eq!(env.len(),expected.len());for(name,value)in &expected{assert_eq!(crate::MacroLookup::get_key_value(env.environment(),name).unwrap().1,value);}drop(env);assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn direct_initial_quota_precedes_temporary_metadata_and_first_factory_io_rolls_back_same_empty_map(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,4<<20,&||Ok(()));let mut env=OriginalEnvironment::new(&a).unwrap();let caller=BTreeMap::from([("AAAA".into(),"x".repeat(4*1024*1024))]);let before=METADATA_COPIES.with(|n|n.get());let mut calls=0;
  assert_eq!(env.install_initial_definitions_using(crate::InitialEnvironment::OriginalChecker0290,&caller,&a,&mut|_,a|{calls+=1;empty(a)}).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert_eq!(calls,0);assert_eq!(METADATA_COPIES.with(|n|n.get()),before);assert_eq!(env.len(),0);
  // A quota-refused operation is permanently stopped: recovery is a genuine
  // fresh request over the same counter, never resetting the failed domain.
  assert!(a.is_stopped());drop(env);assert_eq!(used.load(Ordering::Acquire),0);
  let a=SettingAdmission::new(&used,4<<20,&||Ok(()));let mut env=OriginalEnvironment::new(&a).unwrap();let mut reached=0;
  assert_eq!(env.install_initial_definitions_using(crate::InitialEnvironment::OriginalChecker0290,&BTreeMap::new(),&a,&mut|_,_|{reached+=1;Err(io::Error::from_raw_os_error(1450))}).unwrap_err().raw_os_error(),Some(1450));assert_eq!(reached,1);assert_eq!(env.len(),0);drop(env);assert_eq!(used.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]mod ordinary_directive_tests{
 use super::*;use crate::macro_expansion::{OriginalMacroRows as Rows,OriginalMacroToken as Token,OriginalMacroValue as Value,OriginalMacroOrigin as Origin,OriginalMacroDefinition as Definition};use std::sync::atomic::{AtomicUsize,Ordering};
 fn product(value:i32,a:&SettingAdmission<'_>)->Arc<OriginalDefinitionProduct>{let mut replacement=Rows::new(a).unwrap();replacement.push(Token{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,raw_spelling:None,value:Value::Int(value),origin:Origin{physical:dm_syntax::Span::default(),line:1,byte_column:None,occurrence:0,invocation:false}},a).unwrap();OriginalDefinitionProduct::from_actual_product_using(Definition{parameters:None,variadic:false,replacement},a).unwrap()}
 #[test]fn original_redefinition_and_undef_restore_each_prior_file_dir_and_ordinary_binding(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,4<<20,&||Ok(()));let mut env=OriginalEnvironment::new(&a).unwrap();for name in ["FILE_DIR","A"]{
   env.insert_product_using(name,"1",None,product(1,&a),&a).unwrap();env.insert_product_using(name,"2",None,product(2,&a),&a).unwrap();let current=env.environment.actual_original_product(name).unwrap().unwrap();assert!(matches!(current.definition.replacement.as_slice()[0].value,Value::Int(2)));let mut versions=0;env.environment.visit_original_products_while(|key,_,_,_|{if key.as_ref()==name{versions+=1}true});assert_eq!(versions,2,"pinned DefineMap retains both actual epochs");env.remove_using(name,&a).unwrap();assert!(matches!(env.environment.actual_original_product(name).unwrap().unwrap().definition.replacement.as_slice()[0].value,Value::Int(1)));env.remove_using(name,&a).unwrap();assert!(env.environment.actual_original_product(name).unwrap().is_none());assert!(crate::MacroLookup::get_key_value(&env.environment,name).is_none());
  }assert_eq!(env.len(),0);drop(env);assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn ordinary_removal_preserves_first_real_io_and_does_not_mutate_the_current_binding(){
  let used=Arc::new(AtomicUsize::new(0));let good=SettingAdmission::new(&used,4<<20,&||Ok(()));let mut env=OriginalEnvironment::new(&good).unwrap();env.insert_product_using("A","7",None,product(7,&good),&good).unwrap();let fingerprint=env.environment.fingerprint();let io=||Err(io::Error::from_raw_os_error(1450));let failed=SettingAdmission::new(&used,4<<20,&io);assert_eq!(env.remove_using("A",&failed).unwrap_err().raw_os_error(),Some(1450));assert_eq!(env.environment.fingerprint(),fingerprint);assert!(env.environment.actual_original_product("A").unwrap().is_some());env.remove_using("A",&good).unwrap();assert_eq!(env.len(),0);drop(env);assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn native_stack_still_restores_its_prior_actual_product(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,4<<20,&||Ok(()));let mut env=OriginalEnvironment::new(&a).unwrap();let metadata=Macro{parameters:None,variadic:false,replacement:"1".into()};env.insert_borrowed_using("FILE_DIR",&metadata,None,product(1,&a),&a).unwrap();let mut next=metadata.clone();next.replacement="2".into();env.insert_borrowed_using("FILE_DIR",&next,None,product(2,&a),&a).unwrap();env.remove_stacked_using("FILE_DIR",&a).unwrap();assert!(matches!(env.environment.actual_original_product("FILE_DIR").unwrap().unwrap().definition.replacement.as_slice()[0].value,Value::Int(1)));drop(env);assert_eq!(used.load(Ordering::Acquire),0);
 }
}
