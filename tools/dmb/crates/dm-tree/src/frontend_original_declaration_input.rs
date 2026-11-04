//! SAME current primary source/parser products for Original Analyze preparation.
//! This stage owns no graph and cannot turn diagnostics into Sem=None.
use super::*;
use std::io;
#[derive(Clone,Copy)]pub(super) enum OriginalPrimaryFatal{Comma(dm_syntax::OriginalDeclarationFatal),Parameter(crate::OriginalParameterFatal),Input(crate::OriginalInputParameterFatal)}
pub(super) struct CurrentOriginalDeclarations{
 source:dm_preprocess::SourceText,
 ast:AstFile,
 headers:Arc<crate::procedure::OriginalProcedureHeaders>,
 fatal:Option<OriginalPrimaryFatal>,
 symbols:Option<SymbolTable>,
 prepared:crate::procedure::original_primary_signatures::PreparedOriginalSignatures,
 offset:usize,
 _lease:Arc<dm_syntax::SettingRootLease>,
}
impl CurrentOriginalDeclarations{
 pub(super) fn parse(source:dm_preprocess::SourceText,offset:usize,admission:&dm_syntax::SettingAdmission<'_>)->io::Result<Self>{
  if offset.checked_add(source.len()).is_none_or(|end|end>u32::MAX as usize){return Err(io::Error::new(io::ErrorKind::InvalidInput,"original declaration source span exceeds current native geometry"))}
  let actual=original_operation(admission,||crate::procedure::original_primary_signatures::parse_original_signatures_using(source.clone(),admission).map_err(|error|match error{crate::procedure::header_input::OriginalHeaderFailure::Operational(actual)=>actual,crate::procedure::header_input::OriginalHeaderFailure::Source(message)=>io::Error::new(io::ErrorKind::Unsupported,message)}))?;
  Self::from_actual_signature_input(actual,offset,admission)
 }
 /// Consume SAME streamed primary/header/default products. No expanded-text
 /// parse, header rescan, fabricated SymbolTable or source-availability guess.
 pub(super) fn from_actual_signature_input(mut actual:crate::procedure::original_primary_signatures::OriginalSignatureInput,offset:usize,admission:&dm_syntax::SettingAdmission<'_>)->io::Result<Self>{
  original_operation(admission,||admission.checkpoint())?;
  if offset.checked_add(actual.source.len()).is_none_or(|end|end>u32::MAX as usize){return Err(io::Error::new(io::ErrorKind::InvalidInput,"streamed original declaration source span exceeds current native geometry"))}
  if !admission.matches_lease_domain(&actual.primary_lease){return Err(io::Error::new(io::ErrorKind::InvalidInput,"current original primary input uses another native resource owner"))}
  if let Some(reason)=actual.unavailable{return Err(io::Error::new(io::ErrorKind::Unsupported,format!("Original primary parser state is not issued: {reason}")))}
  if let Some(reason)=actual.signature_unsupported{return Err(io::Error::new(io::ErrorKind::Unsupported,format!("Original primary header state is not issued: {reason}")))}
  let parameter_fatal=match actual.signature_failure{Some(error)=>{if let Some(reason)=error.original_input_fatal{if error.original_fatal.is_some(){return Err(io::ErrorKind::InvalidData.into())}actual.prepared.retain_input_failure_message(reason,error.message)?;Some(OriginalPrimaryFatal::Input(reason))}else{Some(OriginalPrimaryFatal::Parameter(error.original_fatal.ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,format!("Original primary signature failure has no genuine fatal receipt: {}",error.message)))?))}},None=>None};
  if parameter_fatal.is_some()!=actual.observer_stop.is_some()||parameter_fatal.is_some()&&actual.comma_fatal.is_some(){return Err(io::Error::new(io::ErrorKind::InvalidData,"original primary stop/fatal producers disagree"))}
  let fatal=actual.comma_fatal.map(OriginalPrimaryFatal::Comma).or(parameter_fatal);
  // SAME actual native prefix items and local SymbolTable from the primary
  // signature observer; no parse_signature_views call is repeated in adapter.
  let mut parser_lease=actual.primary_lease;let holder_bytes=std::mem::size_of::<dm_syntax::SettingRootLease>()+2*std::mem::size_of::<usize>();original_operation(admission,||admission.grow(&mut parser_lease,holder_bytes))?;let parser_lease=Arc::new(parser_lease);
  original_operation(admission,||actual.headers.retain_original_primary_resource(Arc::clone(&parser_lease),admission).map_err(|error|match error{crate::procedure::header_input::OriginalHeaderFailure::Operational(actual)=>actual,crate::procedure::header_input::OriginalHeaderFailure::Source(reason)=>io::Error::new(io::ErrorKind::Unsupported,reason)}))?;
  let items=super::compact_declarations(actual.items,offset);
  let mut diagnostics=actual.diagnostics;
  // The lexer inventories the whole SAME expanded arena eagerly, but the
  // actual original parser has not consumed tokens beyond this fatal. This
  // projects diagnostic DATA only; declaration Items already came truncated
  // from the genuine primary parser and are never filtered by span here.
  if let Some(fatal)=fatal{let end=match fatal{OriginalPrimaryFatal::Comma(receipt)=>receipt.token_span().end,OriginalPrimaryFatal::Parameter(receipt)=>receipt.token_span().end,OriginalPrimaryFatal::Input(receipt)=>receipt.token_span().end};diagnostics.retain(|row|row.span.start<end);}
  let ast=AstFile{items,diagnostics,..AstFile::default()};
  Ok(Self{source:actual.source,ast,headers:actual.headers,fatal,offset,_lease:parser_lease,symbols:Some(actual.symbols),prepared:actual.prepared})
 }
 pub(super) fn fatal(&self)->Option<OriginalPrimaryFatal>{self.fatal}
 pub(super) fn source(&self)->&dm_preprocess::SourceText{&self.source}
 pub(super) fn ast(&self)->&AstFile{&self.ast}
 pub(super) fn headers(&self)->&Arc<crate::procedure::OriginalProcedureHeaders>{&self.headers}
 /// No source-const folding until the global genuine primary frontier is known.
 /// Parent assignment remains a separate structural finish even on fatal.
 pub(super) fn adapt_before_constant_stage(&mut self,expanded:&str,admission:&dm_syntax::SettingAdmission<'_>)->io::Result<crate::adapter::DeclarationAdapterProgress>{self.adapt_with_global_constant_stage(expanded,admission,true)}
 fn adapt_with_global_constant_stage(&mut self,expanded:&str,admission:&dm_syntax::SettingAdmission<'_>,skip_constants:bool)->io::Result<crate::adapter::DeclarationAdapterProgress>{
  if !admission.matches_lease_domain(&self._lease){return Err(io::Error::new(io::ErrorKind::InvalidInput,"current original primary adapter uses another native resource owner"))}
  let end=self.offset.checked_add(self.source.len()).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
  if expanded.get(self.offset..end)!=Some(self.source.as_str()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"original primary source differs from actual expanded source region"))}
  let symbols=self.symbols.take().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"actual original primary products were already adapted"))?;
  let progress=crate::adapter::from_original_primary_progress_checked(&self.ast,symbols,FileId(0),0,0,expanded,&self.headers,self.offset,admission,skip_constants,&mut self.prepared)?;
  if let Some(error)=progress.errors().first(){return Err(io::Error::new(io::ErrorKind::Unsupported,format!("Original primary adapter outcome is not issued: {}",error.message)))}
  Ok(progress)
 }

}
#[cfg(test)]mod tests{
 use super::*;use std::sync::atomic::AtomicUsize;
 fn member<'a>(facts:&'a crate::AdaptedDeclarations,name:&str)->Option<&'a crate::MemberMetadata>{facts.skeletons.iter().find_map(|s|match s{crate::Skeleton::Member{name:n,metadata,..}if facts.symbols.text(*n)==Some(name)=>Some(metadata.as_ref()),_=>None})}
 #[test]fn real_original_primary_prefix_keeps_first_field_not_future_parent_symbols_or_source_constants(){
  let text="/datum/prior\n    var/const/value = 1 + 2\n/datum/prefix\n    var/datum/first, second\n    parent_type = /datum/future\n/proc/later()\n    return\n";let source:dm_preprocess::SourceText=text.into();let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,8*1024*1024,&poll);let mut input=CurrentOriginalDeclarations::parse(source.clone(),0,&a).unwrap();assert!(input.source().same_view(&source));assert!(input.fatal().is_some());let progress=input.adapt_before_constant_stage(text,&a).unwrap();assert!(progress.errors().is_empty());let facts=progress.facts();assert!(member(facts,"first").is_some());assert!(member(facts,"second").is_none());assert!(member(facts,"later").is_none());assert_eq!(facts.symbols.text(dm_ir::SymbolId::of("/datum/future")),None);let value=member(facts,"value").unwrap();assert!(value.initializer.is_some()||value.declared_initializer.is_some(),"retain actual original initializer, not a fake default");assert!(value.resolved_constant.is_none(),"general source constant evaluation is skipped, not eagerly folded then erased");assert!(facts.skeletons.iter().any(|s|matches!(s,crate::Skeleton::Type{path,explicit_parent:None}if facts.symbols.text(*path)==Some("/datum/prefix"))));
 }
 #[test]fn original_primary_progress_rejects_foreign_counter_expansion_and_unissued_state_without_model_none(){let text="/datum/prefix\n    var/datum/first, second\n";let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,8*1024*1024,&poll);let mut input=CurrentOriginalDeclarations::parse(text.into(),0,&a).unwrap();let other=Arc::new(AtomicUsize::new(0));let foreign=dm_syntax::SettingAdmission::new(&other,8*1024*1024,&poll);assert_eq!(input.adapt_before_constant_stage(text,&foreign).err().unwrap().kind(),io::ErrorKind::InvalidInput);assert_eq!(input.adapt_before_constant_stage("foreign source bytes",&a).err().unwrap().kind(),io::ErrorKind::InvalidInput);let unissued=CurrentOriginalDeclarations::parse("/datum/prefix\n    var/first = 1, second = 2\n".into(),0,&a).err().unwrap();assert_eq!(unissued.kind(),io::ErrorKind::Unsupported);}
}

/// Preserve the actual host error payload (including OS1450), not the leaf's
/// lightweight stopped-kind marker. No error is translated into model absence.
fn original_operation<T>(a:&dm_syntax::SettingAdmission<'_>,run:impl FnOnce()->io::Result<T>)->io::Result<T>{let result=run();if let Some(actual)=a.take_operational_error(){Err(actual)}else{result}}
fn reserve_slot<T>(rows:&mut Vec<T>,lease:&mut dm_syntax::SettingRootLease,a:&dm_syntax::SettingAdmission<'_>)->io::Result<()>{
 if rows.len()<rows.capacity(){return original_operation(a,||a.checkpoint())}
 let capacity=rows.capacity().max(2).checked_mul(2).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
 // Fund actual replacement growth/copy peak before creating its Vec. The old
 // buffer remains separately funded by this same owner-lived aggregate lease.
 let admitted_capacity=capacity.checked_mul(4).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
 let peak=admitted_capacity.checked_mul(std::mem::size_of::<T>()).and_then(|bytes|bytes.checked_add(128)).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
 original_operation(a,||a.grow(lease,peak))?;let mut next=Vec::new();next.try_reserve_exact(capacity).map_err(|_|io::Error::from(io::ErrorKind::OutOfMemory))?;
 if next.capacity()>admitted_capacity{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"native original row buffer exceeded admitted capacity"))}
 next.append(rows);*rows=next;Ok(())
}
/// One grammar scan, then ONE primary parse of each actual root chunk up to the
/// first genuine fatal. Only after that frontier is known may adaptation begin.
/// This preparation is neither a tree nor a statement of semantic completeness.
pub(super) struct OrderedOriginalDeclarations{
 expanded:dm_preprocess::SourceText,
 inputs:Vec<CurrentOriginalDeclarations>,
 frontier:Option<(usize,OriginalPrimaryFatal)>,
 lease:dm_syntax::SettingRootLease,
}
impl OrderedOriginalDeclarations{
 pub(super) fn expanded(&self)->&dm_preprocess::SourceText{&self.expanded}
 /// Adopt one actual stream-issued primary result. The genuine primary
 /// already owns every declaration up to its fatal stop; do not descriptor-
 /// scan, chunk/reparse, or decide availability from the expanded string.
 pub(super) fn from_actual_signature_input(actual:crate::procedure::original_primary_signatures::OriginalSignatureInput,a:&dm_syntax::SettingAdmission<'_>)->io::Result<Self>{
  let expanded=actual.source.clone();let current=CurrentOriginalDeclarations::from_actual_signature_input(actual,0,a)?;
  let frontier=current.fatal().map(|fatal|(0,fatal));
  let mut lease=original_operation(a,||a.reserve(std::mem::size_of::<Self>()))?;let mut inputs=Vec::new();
  reserve_slot(&mut inputs,&mut lease,a)?;inputs.push(current);
  original_operation(a,||a.checkpoint())?;Ok(Self{expanded,inputs,frontier,lease})
 }
 pub(super) fn parse(expanded:dm_preprocess::SourceText,a:&dm_syntax::SettingAdmission<'_>)->io::Result<Self>{Self::parse_grouped(expanded,32,a)}
 fn parse_grouped(expanded:dm_preprocess::SourceText,group:usize,a:&dm_syntax::SettingAdmission<'_>)->io::Result<Self>{
  let mut result=Self{expanded:expanded.clone(),inputs:Vec::new(),frontier:None,lease:original_operation(a,||a.reserve(std::mem::size_of::<Self>()))?};
  let scan=dm_syntax::scan_stable_source_chunks_from(expanded.as_str(),dm_syntax::BoundaryCheckpoint::default(),expanded.len().max(1),group,|text,offset,_|{
   let prepare=||->io::Result<CurrentOriginalDeclarations>{
    let end=offset.checked_add(text.len()).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
    let source=expanded.checked_view(offset..end).filter(|view|view.as_str()==text).ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"original root descriptor differs from current expanded owner"))?;
    CurrentOriginalDeclarations::parse(source,offset,a)
   };
   if let Err(error)=reserve_slot(&mut result.inputs,&mut result.lease,a){return std::ops::ControlFlow::Break(Err(error))}
   match prepare(){Err(error)=>std::ops::ControlFlow::Break(Err(error)),Ok(input)=>{
    let fatal=input.fatal().map(|fatal|(offset,fatal));result.inputs.push(input);
    if let Some(fatal)=fatal{result.frontier=Some(fatal);std::ops::ControlFlow::Break(Ok(()))}else{std::ops::ControlFlow::Continue(())}
   }}
  }).map_err(|error|io::Error::new(io::ErrorKind::InvalidData,format!("current original grammar descriptor scan failed: {error:?}")))?;
  if scan.0.skipped_declarations!=0{return Err(io::Error::new(io::ErrorKind::InvalidData,"current original grammar scan omitted a declaration"))}
  if let std::ops::ControlFlow::Break(done)=scan.1{done?}
  original_operation(a,||a.checkpoint())?;Ok(result)
 }
 pub(super) fn frontier(&self)->Option<(usize,OriginalPrimaryFatal)>{self.frontier}
 pub(super) fn inputs(&self)->&[CurrentOriginalDeclarations]{&self.inputs}
 /// Both complete and prefix preparations leave constants as actual source
 /// initializers here. A distinct later finish must run general constants only
 /// for a complete original parse; structural parent assignment always runs.
 pub(super) fn adapt_before_constant_stage(self,a:&dm_syntax::SettingAdmission<'_>)->io::Result<OriginalDeclarationProducts>{self.adapt_with_constant_stage(a,true)}
 pub(super) fn adapt_for_original_outcome(self,a:&dm_syntax::SettingAdmission<'_>)->io::Result<OriginalDeclarationProducts>{let skip=self.frontier.is_some();self.adapt_with_constant_stage(a,skip)}
 fn adapt_with_constant_stage(mut self,a:&dm_syntax::SettingAdmission<'_>,skip:bool)->io::Result<OriginalDeclarationProducts>{
  if !a.matches_lease_domain(&self.lease){return Err(io::Error::new(io::ErrorKind::InvalidInput,"original declaration batch uses a foreign native resource owner"))}
  let mut rows=Vec::new();let mut lease=original_operation(a,||a.reserve(std::mem::size_of::<OriginalDeclarationProducts>()))?;
  for input in &mut self.inputs{reserve_slot(&mut rows,&mut lease,a)?;rows.push(input.adapt_with_global_constant_stage(self.expanded.as_str(),a,skip)?)}
  original_operation(a,||a.checkpoint())?;Ok(OriginalDeclarationProducts{primary:self,rows,_lease:lease})
 }
}
/// Same products and owners, held together until the frontend transfers actual
/// syntax/ledgers to its current snapshot. This cannot certify a complete tree,
/// a compiled artifact, a semantic-none result, or a foreign/current revision.
pub(super) struct OriginalDeclarationProducts{
 primary:OrderedOriginalDeclarations,
 rows:Vec<crate::adapter::DeclarationAdapterProgress>,
 _lease:dm_syntax::SettingRootLease,
}
impl OriginalDeclarationProducts{
 pub(super) fn primary(&self)->&OrderedOriginalDeclarations{&self.primary}
 pub(super) fn rows(&self)->&[crate::adapter::DeclarationAdapterProgress]{&self.rows}
 pub(super) fn into_parts(self)->(OrderedOriginalDeclarations,Vec<crate::adapter::DeclarationAdapterProgress>,dm_syntax::SettingRootLease){(self.primary,self.rows,self._lease)}
}
#[cfg(test)]mod ordered_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]fn late_actual_fatal_prevents_early_chunk_constants_and_all_later_chunk_parses(){
  let text="/datum/early\n    parent_type = /datum\n    var/const/early_constant = 1 + 2\n/datum/prefix\n    var/datum/first, second\n/datum/future\n    var/third\n";
  let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,16*1024*1024,&poll);
  let input=OrderedOriginalDeclarations::parse_grouped(text.into(),1,&a).unwrap();assert!(input.frontier().is_some());assert_eq!(input.inputs().len(),2,"future root not parsed or adapted");
  let products=input.adapt_before_constant_stage(&a).unwrap();assert_eq!(products.rows().len(),2);assert!(products.primary().frontier().is_some());
  let early=products.rows()[0].facts();assert!(early.skeletons.iter().any(|s|matches!(s,crate::Skeleton::Type{path,explicit_parent:Some(parent)}if early.symbols.text(*path)==Some("/datum/early")&&early.symbols.text(*parent)==Some("/datum"))),"earlier structural parent is retained even though general constants skip");
  let value=early.skeletons.iter().find_map(|s|match s{crate::Skeleton::Member{name,metadata,..}if early.symbols.text(*name)==Some("early_constant")=>Some(metadata),_=>None}).unwrap();assert!(value.resolved_constant.is_none());assert!(value.initializer.is_some()||value.declared_initializer.is_some());
  for row in products.rows(){assert!(row.facts().symbols.text(dm_ir::SymbolId::of("/datum/future")).is_none())}
  drop(products);assert_eq!(counter.load(Ordering::Acquire),0,"same native parser/header/batch leases drain with actual owner");
 }
 #[test]fn operational_failure_is_not_partial_success_or_model_absence_and_retained_products_drain(){
  let counter=Arc::new(AtomicUsize::new(0));let poll=||Err(io::Error::from_raw_os_error(1450));let a=dm_syntax::SettingAdmission::new(&counter,1024*1024,&poll);
  let failure=OrderedOriginalDeclarations::parse("/datum/a\n".into(),&a).err().unwrap();assert_eq!(failure.raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),0);
  let good_poll=||Ok(());let good=dm_syntax::SettingAdmission::new(&counter,1024*1024,&good_poll);let input=OrderedOriginalDeclarations::parse("/datum/a\n    var/b\n".into(),&good).unwrap();assert!(input.frontier().is_none());
  let other=Arc::new(AtomicUsize::new(0));let foreign=dm_syntax::SettingAdmission::new(&other,1024*1024,&good_poll);assert_eq!(input.adapt_before_constant_stage(&foreign).err().unwrap().kind(),io::ErrorKind::InvalidInput);assert_eq!(counter.load(Ordering::Acquire),0);
 }
}

/// Existing native current-contribution machinery consumes SAME actual
/// adapter/header rows, never reconstructs a declaration or parses a signature.
impl CurrentOriginalDeclarations{
 fn into_current(self,progress:crate::adapter::DeclarationAdapterProgress,a:&dm_syntax::SettingAdmission<'_>)->io::Result<(super::declaration_state::CurrentContribution,OriginalPrimaryRoots)>{
  if !a.matches_lease_domain(&self._lease){return Err(io::Error::new(io::ErrorKind::InvalidInput,"original current contribution belongs to another native resource domain"))}
  let(mut facts,rows,errors)=progress.into_parts();
  if let Some(error)=errors.first(){return Err(io::Error::new(io::ErrorKind::Unsupported,format!("unissued original declaration adapter state: {}",error.message)))}
  let receipt=crate::procedure::HeaderAllocationReceipt::from_rows_checked(&self.ast.items,&self.headers,self.offset,rows).map_err(|error|match error{crate::procedure::header_input::OriginalHeaderFailure::Operational(actual)=>actual,crate::procedure::header_input::OriginalHeaderFailure::Source(message)=>io::Error::new(io::ErrorKind::Unsupported,message)})?;
  let ledger=crate::allocation_ledger::capture_with_header_receipt(&self.ast.items,"/",&mut facts.symbols,&receipt).map_err(|error|io::Error::new(io::ErrorKind::Unsupported,error.message))?;drop(receipt);
  self.prepared.require_consumed().map_err(|reason|io::Error::new(io::ErrorKind::InvalidData,reason))?;
  let mut aliases=super::original_signature_funding::OriginalSignatureAliasGroup::capture(&facts,&self.prepared,a)?;
  let current=super::declaration_state::CurrentContribution::fresh_source_headers(self.source,self.offset,self.ast.items,facts,ledger,Some(self.headers)).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"actual original prefix cannot bind native current contribution"))?;
  if let Some(items)=current.syntax.shared_relative().wide_relative_items(){let group=Arc::get_mut(&mut aliases).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"primary weak alias observations escaped before publication"))?;original_operation(a,||group.retain_wide_items(items,&self._lease,a))?;}
  if !current.syntax.shared_relative().initializer_admission_matches(a)?{return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual original prefix contribution lacks same-counter initializer completion"))}
  original_operation(a,||a.checkpoint())?;Ok((current,OriginalPrimaryRoots{offset:self.offset,parser:self._lease,_signatures:self.prepared,aliases}))
 }
}
/// No compiler-completeness token is issued here. These are the same native
/// CurrentContribution leaves used by the ordinary frontend, with primary
/// allocation roots retained while their transferred syntax remains live.
pub(super) struct OriginalCurrentDeclarations{
 expanded:dm_preprocess::SourceText,
 current:Vec<super::declaration_state::CurrentContribution>,
 diagnostics:Vec<(usize,dm_syntax::Diagnostic)>,
 primary_leases:Vec<OriginalPrimaryRoots>,
 frontier:Option<(usize,OriginalPrimaryFatal)>,
 lease:dm_syntax::SettingRootLease,
}
impl OriginalDeclarationProducts{
 pub(super) fn into_current(self,a:&dm_syntax::SettingAdmission<'_>)->io::Result<OriginalCurrentDeclarations>{
  if !a.matches_lease_domain(&self.primary.lease)||!a.matches_lease_domain(&self._lease){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual original products belong to another native resource owner"))}
  if self.rows.len()!=self.primary.inputs.len(){return Err(io::Error::new(io::ErrorKind::InvalidData,"actual original producer rosters differ"))}
  let mut result=OriginalCurrentDeclarations{expanded:self.primary.expanded,current:Vec::new(),diagnostics:Vec::new(),primary_leases:Vec::new(),frontier:self.primary.frontier,lease:original_operation(a,||a.reserve(std::mem::size_of::<OriginalCurrentDeclarations>()))?};
  for(mut input,row)in self.primary.inputs.into_iter().zip(self.rows){
   for diagnostic in std::mem::take(&mut input.ast.diagnostics){reserve_slot(&mut result.diagnostics,&mut result.lease,a)?;result.diagnostics.push((input.offset,diagnostic));}
   reserve_slot(&mut result.current,&mut result.lease,a)?;reserve_slot(&mut result.primary_leases,&mut result.lease,a)?;
   let(current,primary)=input.into_current(row,a)?;result.current.push(current);result.primary_leases.push(primary);
  }
  original_operation(a,||a.checkpoint())?;Ok(result)
 }
}
impl OriginalCurrentDeclarations{
 pub(super) fn current(&self)->&[super::declaration_state::CurrentContribution]{&self.current}
 pub(super) fn frontier(&self)->Option<(usize,OriginalPrimaryFatal)>{self.frontier}
 pub(super) fn expanded(&self)->&dm_preprocess::SourceText{&self.expanded}
}
#[cfg(test)]mod current_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]fn actual_original_prefix_transfers_through_existing_native_current_leaves_with_same_counter_and_no_future_bodies(){
  let text="/datum/prior\n    var/const/first_constant=1+2\n/proc/prior_body()\n    return 1\n/datum/prefix\n    var/datum/first, second\n/proc/future_body()\n    return 2\n";
  let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,32*1024*1024,&poll);
  let primary=OrderedOriginalDeclarations::parse_grouped(text.into(),1,&a).unwrap();let native=primary.adapt_before_constant_stage(&a).unwrap().into_current(&a).unwrap();assert!(native.frontier().is_some());assert_eq!(native.expanded().as_str(),text);
  assert!(native.current().iter().any(|leaf|leaf.symbols().text(dm_ir::SymbolId::of("prior_body")).is_some()));assert!(native.current().iter().all(|leaf|leaf.symbols().text(dm_ir::SymbolId::of("future_body")).is_none()));
  for leaf in native.current(){assert!(leaf.syntax.shared_relative().initializer_admission_matches(&a).unwrap());assert!(leaf.syntax.items().all(|item|item.header_span().start<text.find("/proc/future_body").unwrap()))}
  assert!(counter.load(Ordering::Acquire)>0);drop(native);assert_eq!(counter.load(Ordering::Acquire),0);
 }
}

/// A private actual native declaration preparation. `parsed` is not a graph;
/// the role-aware frontend must retain `retention` with any resulting snapshot.
pub(super) struct PreparedOriginalDeclarations{
 pub(super) parsed:super::declaration_parse::ParsedDeclarations,
 pub(super) retention:Arc<OriginalPrimaryRetention>,
}
pub(crate) struct OriginalPrimaryRetention{
 source:dm_preprocess::SourceText,
 primary_leases:Vec<OriginalPrimaryRoots>,
 frontier:Option<(usize,OriginalPrimaryFatal)>,
 _metadata:dm_syntax::SettingRootLease,
}
impl std::fmt::Debug for OriginalPrimaryRetention{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("OriginalPrimaryRetention").field("source_bytes",&self.source.len()).field("actual_primary_roots",&self.primary_leases.len()).field("partial",&self.frontier.is_some()).finish_non_exhaustive()}}
impl OriginalPrimaryRetention{
 pub(super) fn frontier(&self)->Option<(usize,OriginalPrimaryFatal)>{self.frontier}
 pub(super) fn input_fatal_message(&self,offset:usize,reason:crate::OriginalInputParameterFatal)->io::Result<&str>{for roots in &self.primary_leases{if roots.offset==offset{if let Some(message)=roots._signatures.input_failure_message(reason){return Ok(message)}}}Err(io::Error::new(io::ErrorKind::InvalidData,"actual input fatal message owner is absent"))}
 pub(super) fn source(&self)->&dm_preprocess::SourceText{&self.source}
 pub(super) fn visit_formal_notices<'a>(&'a self,checkpoint:&dyn Fn()->io::Result<()>,mut consume:impl FnMut(crate::OriginalFormalNotice,Option<&'a str>)->io::Result<()>)->io::Result<()>{for roots in &self.primary_leases{checkpoint()?;let headers=roots._signatures.actual_headers();if !headers.formal_source_matches(&self.source,roots.offset){return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual formal notice source differs from retained primary projection"))}for notice in headers.all_formal_notices().map_err(|reason|io::Error::new(io::ErrorKind::Unsupported,reason))?{checkpoint()?;let value=headers.formal_notice_text(notice).map_err(|reason|io::Error::new(io::ErrorKind::Unsupported,reason))?;consume(notice.checked_shift(roots.offset)?,value)?;}}Ok(())}

 pub(super) fn visit_retained_storage(&self,mut visit:impl FnMut(usize,usize,usize)){
  if self.primary_leases.capacity()!=0{visit(self.primary_leases.as_ptr()as usize,self.primary_leases.capacity()*std::mem::size_of::<OriginalPrimaryRoots>(),std::mem::align_of::<OriginalPrimaryRoots>())}
  for roots in &self.primary_leases{roots._signatures.visit_consumed_row_storage(&mut visit);roots.aliases.visit_storage(&mut visit)}
 }
}
impl OriginalCurrentDeclarations{
 pub(super) fn into_prepared(self,engine:Option<&EngineSeed>,a:&dm_syntax::SettingAdmission<'_>)->io::Result<PreparedOriginalDeclarations>{
  if !a.matches_lease_domain(&self.lease)||self.primary_leases.iter().any(|roots|!a.matches_lease_domain(&roots.parser)){return Err(io::Error::new(io::ErrorKind::InvalidInput,"current original merge uses another native resource owner"))}
  let count=self.current.len();let mut metadata=original_operation(a,||a.reserve(std::mem::size_of::<OriginalPrimaryRetention>()+2*std::mem::size_of::<usize>()))?;
  let mut syntax=Vec::new();let mut allocations=Vec::new();
  let mut adapted=crate::SharedAdaptedDeclarations{symbol_catalog:None,symbols:engine.map_or_else(SymbolTable::default,|seed|seed.symbols.clone()),skeletons:Default::default(),origins:Vec::new().into()};
  let mut origins=crate::relative_origins::RelativeOriginRoster::default();
  for current in self.current{
   original_operation(a,||a.checkpoint())?;reserve_slot(&mut syntax,&mut metadata,a)?;reserve_slot(&mut allocations,&mut metadata,a)?;
   // Same existing root-context union, skeleton leaves, original origin leaves
   // and event leaves as the ordinary declaration worker's ordered merge.
   adapted.symbols.merge_from(current.symbols()).map_err(|error|io::Error::new(io::ErrorKind::InvalidData,error.to_string()))?;
   adapted.skeletons.push_leaf(current.skeletons());let(origin,offset)=current.origin_leaf();origins.push(origin,offset).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"current original relative origin overflow"))?;
   allocations.push(current.event_leaf());syntax.push(current.syntax);
  }
  adapted.origins=crate::relative_origins::OriginRoster::Bound(origins);
  let syntax=DeclarationSyntax::new(syntax).map_err(|error|io::Error::new(io::ErrorKind::InvalidData,format!("current original syntax binding failed: {error:?}")))?;
  let events=crate::allocation_ledger::AllocationEvents::bind_leaves(allocations).map_err(|error|io::Error::new(io::ErrorKind::InvalidData,format!("current original event binding failed: {error:?}")))?;
  let parsed=super::declaration_parse::ParsedDeclarations{syntax,diagnostics:self.diagnostics,adapted,allocation_ledger:crate::allocation_ledger::AllocationLedger{events},declaration_errors:Vec::new(),reuse_stats:DeclarationReuseStats{chunks:count,parsed_chunks:count,..Default::default()}};
  let retention=Arc::new(OriginalPrimaryRetention{source:self.expanded,primary_leases:self.primary_leases,frontier:self.frontier,_metadata:metadata});original_operation(a,||a.checkpoint())?;
  Ok(PreparedOriginalDeclarations{parsed,retention})
 }
}
#[cfg(test)]mod assembly_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]fn actual_original_partial_union_reuses_existing_native_tree_builder_and_skips_global_source_constants(){
  let text="/datum/parent\n    var/before\n/datum/child\n    parent_type = /datum/parent\n    var/const/value = 1+2\n    var/datum/first, second\n/datum/future\n    var/after\n";
  let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,64*1024*1024,&poll);
  let current=OrderedOriginalDeclarations::parse_grouped(text.into(),1,&a).unwrap().adapt_for_original_outcome(&a).unwrap().into_current(&a).unwrap();let prepared=current.into_prepared(Some(seed.frontend_seed()),&a).unwrap();assert!(prepared.retention.frontier().is_some());assert!(prepared.parsed.syntax.chunks().iter().all(|chunk|chunk.shared_relative().initializer_admission_matches(&a).unwrap()));
  let variables=crate::checker_builtins::OriginalVariableDeclarations::for_seed(Some(seed.frontend_seed()));let declarations=prepared.parsed.adapted.finish_checker_diagnostic_with_variables(Some(seed.frontend_seed()),|error,_,_|panic!("real original prefix graph must use existing diagnostic builder: {error:?}"),&executor,variables).unwrap();let(snapshot,_receipt)=declarations.into_parts();
  assert!(snapshot.tree.symbols().text(dm_ir::SymbolId::of("/datum/child")).is_some());assert!(snapshot.tree.symbols().text(dm_ir::SymbolId::of("/datum/future")).is_none());assert_eq!(prepared.retention.source().as_str(),text);
  drop(snapshot);drop(prepared.parsed.syntax);drop(prepared.parsed.allocation_ledger);drop(prepared.retention);assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn complete_actual_original_primary_runs_existing_constant_producer_only_after_no_fatal_is_known(){let text="/datum/complete\n    var/const/value = 1 + 2\n";let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,16*1024*1024,&poll);let result=OrderedOriginalDeclarations::parse(text.into(),&a).unwrap().adapt_for_original_outcome(&a).unwrap();assert!(result.primary().frontier().is_none());let facts=result.rows()[0].facts();let value=facts.skeletons.iter().find_map(|row|match row{crate::Skeleton::Member{name,metadata,..}if facts.symbols.text(*name)==Some("value")=>Some(metadata),_=>None}).unwrap();assert!(value.resolved_constant.is_some(),"same unique existing constant producer remains used for complete inputs");drop(result);assert_eq!(counter.load(Ordering::Acquire),0);}
}

#[cfg(test)]mod primary_signature_consumer_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]fn real_formal_fatal_stops_before_proc_and_future_parent_prescan_and_same_prepared_signature_is_not_parsed_again(){
  let text="/datum/early\n    var/const/value=1+2\n/proc/good(obj/argument)\n    return argument\n/proc/bad(value=)\n    return 7\n/datum/future\n    parent_type=/datum/missing\n";
  let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,64*1024*1024,&poll);
  let before=crate::procedure::signature_interpretations();let primary=OrderedOriginalDeclarations::parse_grouped(text.into(),1,&a).unwrap();assert!(matches!(primary.frontier(),Some((_,OriginalPrimaryFatal::Parameter(_)))));assert_eq!(crate::procedure::signature_interpretations(),before+2);
  let products=primary.adapt_for_original_outcome(&a).unwrap();assert_eq!(crate::procedure::signature_interpretations(),before+2,"adapter consumes exact native primary signature/SymbolTable rather than reparsing a formal");
  assert!(products.rows().iter().any(|row|row.facts().symbols.text(dm_ir::SymbolId::of("good")).is_some()));assert!(products.rows().iter().all(|row|row.facts().symbols.text(dm_ir::SymbolId::of("bad")).is_none()&&row.facts().symbols.text(dm_ir::SymbolId::of("/datum/future")).is_none()));
  let native=products.into_current(&a).unwrap();assert!(native.current().iter().all(|current|current.syntax.items().all(|item|item.header_span().start<text.find("/proc/bad").unwrap())));drop(native);assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn prepared_primary_input_is_once_consumed_and_foreign_admission_cannot_consume_real_signature(){
  let text="/proc/good(argument=1)\n    return argument\n";let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,64*1024*1024,&poll);let mut input=CurrentOriginalDeclarations::parse(text.into(),0,&a).unwrap();let other=Arc::new(AtomicUsize::new(0));let foreign=dm_syntax::SettingAdmission::new(&other,64*1024*1024,&poll);
  assert_eq!(input.adapt_before_constant_stage(text,&foreign).err().unwrap().kind(),io::ErrorKind::InvalidInput);let first=input.adapt_before_constant_stage(text,&a).unwrap();assert!(first.errors().is_empty());assert_eq!(input.adapt_before_constant_stage(text,&a).err().unwrap().kind(),io::ErrorKind::InvalidInput);drop(first);drop(input);assert_eq!(counter.load(Ordering::Acquire),0);
 }
}

/// Funding follows the real signature metadata after the row is moved into
/// native member metadata; consuming a prepared row does not release its lease.
struct OriginalPrimaryRoots{offset:usize,_signatures:crate::procedure::original_primary_signatures::PreparedOriginalSignatures,aliases:Arc<super::original_signature_funding::OriginalSignatureAliasGroup>,parser:Arc<dm_syntax::SettingRootLease>}

impl OriginalPrimaryRetention{
 pub(crate) fn visit_resource_storage(&self,mut visit:impl FnMut(usize,usize,usize)){
  self.visit_retained_storage(&mut visit);
 }
}

#[cfg(test)]mod actual_future_lexical_tests{
 use super::*;use std::sync::atomic::AtomicUsize;
 #[test]fn future_lexical_records_in_same_expanded_arena_cannot_prevent_real_original_fatal_prefix(){
  let text="/datum/prefix\n    var/datum/first, second\n/proc/later()\n    return \"unterminated\n";let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,32*1024*1024,&poll);
  let primary=OrderedOriginalDeclarations::parse(text.into(),&a).unwrap();assert!(primary.frontier().is_some());let products=primary.adapt_for_original_outcome(&a).unwrap();assert!(products.rows().iter().all(|row|row.errors().is_empty()));assert!(products.rows().iter().any(|row|row.facts().symbols.text(dm_ir::SymbolId::of("first")).is_some()));assert!(products.rows().iter().all(|row|row.facts().symbols.text(dm_ir::SymbolId::of("later")).is_none()));
 }
}

impl OriginalCurrentDeclarations{
 pub(super) fn converge_previous_code(mut self,previous:Option<&DeclarationSyntax>,a:&dm_syntax::SettingAdmission<'_>)->io::Result<Self>{
  let Some(previous)=previous else{return Ok(self)};original_operation(a,||a.checkpoint())?;
  let mut candidates=super::relative_declarations::BodyCodeCandidates::new(a)?;for chunk in previous.chunks().iter(){candidates.capture(chunk.shared_relative(),a)?}candidates.finish(a)?;
  let old=std::mem::take(&mut self.current);for current in old{reserve_slot(&mut self.current,&mut self.lease,a)?;self.current.push(current.converge_original_code(&candidates,a)?)}
  original_operation(a,||a.checkpoint())?;dm_profile::request_mark("frontend.original_primary_body_code_convergence");Ok(self)
 }
}

impl OriginalCurrentDeclarations{pub(super) fn retain_signature_aliases(&self,host:&dyn SettingExpressionQueries,a:&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>{for roots in &self.primary_leases{host.retain_original_signature_aliases(Arc::clone(&roots.aliases),a)?;}Ok(())}}

#[cfg(test)]mod detached_original_signature_resource_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 enum Detached{Metadata(Arc<dm_ir::ProcedureMetadata>),Parameters(Arc<[dm_ir::Parameter]>),Tokens(Arc<[dm_ir::ExpressionToken]>),Array(Arc<dm_ir::ArrayDeclaration>),Dimensions(Arc<[Option<dm_ir::SymbolicExpression>]>)}
 #[test]fn actual_original_signature_metadata_parameter_array_and_token_aliases_keep_same_counter_after_all_graph_roots_drop(){
  for choice in 0..6{
   let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&poll);let source="/proc/probe(argument[2]=1)\n    return argument\n";
   let native=OrderedOriginalDeclarations::parse(source.into(),&a).unwrap().adapt_for_original_outcome(&a).unwrap().into_current(&a).unwrap();
   let skeletons=native.current[0].skeletons();let metadata=skeletons.iter().find_map(|row|match row{crate::Skeleton::Member{metadata,..}=>metadata.procedure.clone(),_=>None}).unwrap();
   let detached=match choice{0=>Detached::Metadata(Arc::clone(&metadata)),1=>Detached::Parameters(Arc::clone(&metadata.signature.parameters)),2=>Detached::Tokens(Arc::clone(&metadata.signature.parameters[0].default.as_ref().unwrap().tokens)),3=>Detached::Array(Arc::clone(metadata.signature.parameters[0].array.as_ref().unwrap())),4=>Detached::Dimensions(Arc::clone(&metadata.signature.parameters[0].array.as_ref().unwrap().dimensions)),_=>Detached::Tokens(Arc::clone(&metadata.signature.parameters[0].array.as_ref().unwrap().dimensions[0].as_ref().unwrap().tokens))};
   let mut census=OriginalSignatureAliasCensus::default();let group=Arc::clone(&native.primary_leases[0].aliases);census.retain(Arc::clone(&group),&a).unwrap();census.retain(group,&a).unwrap();assert_eq!(census.live_groups(),1,"same reservation resource group is not registered twice");drop(metadata);drop(skeletons);drop(native);census.prune(&a).unwrap();assert_eq!(census.live_groups(),1,"detached IR allocation remains physically live choice={choice}");assert!(counter.load(Ordering::Acquire)>0,"detached alias retains SAME producer reservation");drop(detached);census.prune(&a).unwrap();assert_eq!(census.live_groups(),0);assert_eq!(counter.load(Ordering::Acquire),0,"actual last alias releases signature+observer/census credit after resource prune");
  }
 }
 #[test]fn actual_original_signature_alias_census_rejects_foreign_counter_and_never_retains_semantic_payload(){
  let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&poll);let native=OrderedOriginalDeclarations::parse("/proc/probe(argument=1)\n    return argument\n".into(),&a).unwrap().adapt_for_original_outcome(&a).unwrap().into_current(&a).unwrap();let group=Arc::clone(&native.primary_leases[0].aliases);let foreign=Arc::new(AtomicUsize::new(0));let other=dm_syntax::SettingAdmission::new(&foreign,32<<20,&poll);let mut census=OriginalSignatureAliasCensus::default();assert_eq!(census.retain(Arc::clone(&group),&other).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(census.live_groups(),0);assert_eq!(foreign.load(Ordering::Acquire),0);drop(group);drop(native);assert_eq!(counter.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]mod original_primary_detached_syntax_resource_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]fn actual_detached_relative_syntax_and_header_owner_keep_same_primary_parser_credit_until_last_owner(){
  let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&poll);let native=OrderedOriginalDeclarations::parse("/datum/kept\n    var/value=1\n".into(),&a).unwrap().adapt_for_original_outcome(&a).unwrap().into_current(&a).unwrap();
  let original=Arc::downgrade(&native.primary_leases[0].parser);let relative=Arc::clone(native.current[0].syntax.shared_relative());assert!(relative.wide_relative_items().is_none());let primary_bytes=original.upgrade().unwrap().bytes();drop(native);assert!(original.upgrade().is_some(),"public detached RelativeSyntax keeps the actual header/parser resource root");assert!(counter.load(Ordering::Acquire)>=primary_bytes);drop(relative);assert!(original.upgrade().is_none());assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn actual_resource_wide_fallback_alias_is_observed_without_minting_a_semantic_or_source_grant(){
  let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&poll);let mut primary=CurrentOriginalDeclarations::parse("/datum/kept\n    var/value=1\n".into(),0,&a).unwrap();let progress=primary.adapt_before_constant_stage("/datum/kept\n    var/value=1\n",&a).unwrap();
  // Existing Arena wide fallback is otherwise unreachable inside admitted
  // Original u32 source geometry. Alter only this RESOURCE-test indentation
  // scalar, moving SAME native Item allocations; never issue a model/view.
  primary.ast.items[0].indent=usize::MAX;let(current,roots)=primary.into_current(progress,&a).unwrap();let wide=Arc::clone(current.syntax.shared_relative().wide_relative_items().expect("actual existing wide storage fallback"));let original=Arc::downgrade(&roots.parser);let mut census=OriginalSignatureAliasCensus::default();census.retain(Arc::clone(&roots.aliases),&a).unwrap();drop(current);drop(roots);census.prune(&a).unwrap();assert!(original.upgrade().is_some());assert_eq!(census.live_groups(),1);drop(wide);census.prune(&a).unwrap();assert!(original.upgrade().is_none());assert_eq!(counter.load(Ordering::Acquire),0);
 }
 #[test]fn actual_header_resource_root_cannot_rebind_foreign_reservation_or_replace_current_owner(){
  let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,32<<20,&poll);let primary=CurrentOriginalDeclarations::parse("/datum/kept\n".into(),0,&a).unwrap();let foreign=Arc::new(AtomicUsize::new(0));let b=dm_syntax::SettingAdmission::new(&foreign,32<<20,&poll);let root=Arc::new(b.reserve(64).unwrap());assert!(matches!(primary.headers.retain_original_primary_resource(root,&b),Err(crate::procedure::header_input::OriginalHeaderFailure::Operational(ref error))if error.kind()==io::ErrorKind::InvalidInput));assert_eq!(foreign.load(Ordering::Acquire),0);let other=Arc::new(a.reserve(64).unwrap());assert!(primary.headers.retain_original_primary_resource(other,&a).is_err());drop(primary);assert_eq!(counter.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]mod streamed_actual_input_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]fn actual_primary_handoff_retains_source_owner_fatal_notices_and_consumes_signatures_once(){
  for text in ["/proc/p(var/static/A)\n    return A\n", "/proc/p(var/A=)\n/proc/unreached()\n    return\n"]{
   let counter=Arc::new(AtomicUsize::new(0));let a=dm_syntax::SettingAdmission::new(&counter,16<<20,&||Ok(()));let source:dm_preprocess::SourceText=text.into();
   let actual=crate::procedure::original_primary_signatures::parse_original_signatures_using(source.clone(),&a).unwrap();
   let fatal=actual.signature_failure.is_some();let headers=Arc::clone(&actual.headers);
   let input=OrderedOriginalDeclarations::from_actual_signature_input(actual,&a).unwrap();
   assert!(input.expanded.same_view(&source));assert_eq!(input.frontier().is_some(),fatal);assert_eq!(input.inputs().len(),1);assert!(Arc::ptr_eq(input.inputs()[0].headers(),&headers));
   let products=input.adapt_for_original_outcome(&a).unwrap();assert_eq!(products.rows().len(),1);
   assert!(products.primary().inputs()[0].prepared.require_consumed().is_ok());
   assert!(products.rows().iter().all(|row|row.facts().symbols.text(dm_ir::SymbolId::of("unreached")).is_none()));
   drop(products);drop(headers);drop(source);assert_eq!(counter.load(Ordering::Acquire),0);
  }
 }
 #[test]fn actual_primary_handoff_rejects_foreign_admission_without_reparsing(){
  let counter=Arc::new(AtomicUsize::new(0));let a=dm_syntax::SettingAdmission::new(&counter,16<<20,&||Ok(()));
  let actual=crate::procedure::original_primary_signatures::parse_original_signatures_using("/proc/p(A)\n    return A\n".into(),&a).unwrap();
  let foreign=Arc::new(AtomicUsize::new(0));let b=dm_syntax::SettingAdmission::new(&foreign,16<<20,&||Ok(()));
  assert_eq!(OrderedOriginalDeclarations::from_actual_signature_input(actual,&b).err().unwrap().kind(),io::ErrorKind::InvalidInput);assert_eq!(counter.load(Ordering::Acquire),0);
 }
}
