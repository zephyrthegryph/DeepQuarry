//! Actual bounded contribution-page query in the EXISTING purity ledger.
//! Page jobs depend on the original whole program input plus actual Kind4
//! bodies, so source mode needs no per-resolver semantic model/query roster.
use super::*;
use dm_analysis::checker_effects::{EffectPageFacts,EffectSource};
use dm_tree::frontend::{BodySyntax,BodySyntaxFailure,BodySyntaxInput};
pub(super) const PAGE:Kind=Kind(23);

/// Physical owner of an actual source-produced page. No raw payload Arc/Weak
/// escapes; original diagnostic/effect buffers free before SAME-ledger credit.
pub(crate) struct NativeEffectPage{payload:Option<Arc<PagePayload>>}
struct PagePayload{facts:EffectPageFacts,lease:graph_work::GraphLease,#[cfg(test)]drop_pause:Mutex<Option<(Arc<std::sync::Barrier>,Arc<std::sync::Barrier>)>>}
impl Drop for NativeEffectPage{fn drop(&mut self){if let Some(payload)=self.payload.take().and_then(Arc::into_inner){#[cfg(test)]if let Some((entered,release))=payload.drop_pause.lock().unwrap_or_else(|e|e.into_inner()).take(){entered.wait();release.wait();}let PagePayload{facts,lease,..}=payload;drop(facts);drop(lease);}}}
impl std::ops::Deref for NativeEffectPage{type Target=EffectPageFacts;fn deref(&self)->&EffectPageFacts{&self.payload.as_deref().expect("sealed effect page payload").facts}}
impl dm_analysis::checker_effects::EffectPageRead for NativeEffectPage{fn effect_page(&self)->&EffectPageFacts{self}}
impl NativeEffectPage{
 fn payload(&self)->&PagePayload{self.payload.as_deref().expect("sealed effect page payload")}
 fn coordination_charge()->usize{std::mem::size_of::<PagePayload>().saturating_sub(std::mem::size_of::<EffectPageFacts>())}
 pub(crate) fn retained_charge(&self)->Option<usize>{self.payload().facts.retained_charge()?.checked_add(Self::coordination_charge())}
 pub(crate) fn visit_storage(&self,mut visit:impl FnMut(Storage)){let p=self.payload();p.facts.visit_storage(&mut visit);visit(Storage::Buffer{owner:"purity.page_private_payload",address:p as *const PagePayload as usize,logical:std::mem::size_of::<PagePayload>(),capacity:std::mem::size_of::<PagePayload>()});visit(Storage::Buffer{owner:"purity.page_completion",address:Arc::as_ptr(&p.lease.completion) as usize,logical:std::mem::size_of::<std::sync::atomic::AtomicBool>(),capacity:std::mem::size_of::<std::sync::atomic::AtomicBool>()});}
 #[cfg(test)]pub(crate) fn pause_drop_for_test(&self,entered:Arc<std::sync::Barrier>,release:Arc<std::sync::Barrier>){*self.payload().drop_pause.lock().unwrap_or_else(|e|e.into_inner())=Some((entered,release));}
}
impl graph_work::RetainedHandle for NativeEffectPage{fn fingerprint(&self,_:Key)->u128{self.payload().facts.report_fingerprint()}type Data=EffectPageFacts;fn coordination_charge()->usize{Self::coordination_charge()}fn issue(facts:EffectPageFacts,ledger:Arc<Mutex<Ledger>>,completion:Arc<std::sync::atomic::AtomicBool>)->Arc<Self>{Arc::new(Self{payload:Some(Arc::new(PagePayload{facts,lease:graph_work::GraphLease{ledger,completion},#[cfg(test)]drop_pause:Mutex::new(None)}))})}fn retained_charge(&self)->Option<usize>{Self::retained_charge(self)}}

struct PageParams{base:Params,start:usize,width:usize,old_edges:usize,dependencies:std::sync::atomic::AtomicUsize}
pub(super) fn page_key(input:&EffectInput,start:usize,width:usize)->Key{key(PAGE,input,((start as u128)<<64)|(width as u128))}
/// Begin with its own window +project/program; callee prefix reads extend
/// this actual read-set reservation before ctx.note.
/// Reserve old/new dynamic-edge overlap before ctx.note can allocate. After
/// Db::get returns/unwinds, the old/new temporary Ctx has physically gone and
/// only one bounded immutable dependency set remains. No cumulative retry leak.
pub(super) struct PageDependencyPeak{ledger:Arc<Mutex<Ledger>>,key:Key,pub(super) old:usize,actual:usize,committed:bool}
impl PageDependencyPeak{pub(super) fn commit(&mut self,actual:usize){self.actual=actual;self.committed=true}}
impl Drop for PageDependencyPeak{fn drop(&mut self){let actual=self.actual;if let Some(node)=self.ledger.lock().unwrap_or_else(|e|e.into_inner()).nodes.get_mut(&self.key){node.observed_edges=if self.committed&&actual!=0{actual}else{self.old};}}}
pub(super) fn reserve_dependencies(ledger:&Arc<Mutex<Ledger>>,key:Key,count:usize)->Result<PageDependencyPeak,String>{
 let minimum=count.checked_add(2).ok_or("effect page dependency count overflow")?;let mut l=ledger.lock().unwrap_or_else(|e|e.into_inner());let old=l.nodes.get(&key).ok_or("effect page node was not reserved")?.observed_edges;let peak=old.checked_add(minimum.checked_mul(2).ok_or("effect page dependency peak overflow")?).ok_or("effect page dependency overlap overflow")?;
 l.admit(peak.saturating_sub(old).checked_mul(EDGE_BOUND).ok_or("effect page dependency admission overflow")?)?;l.nodes.get_mut(&key).unwrap().observed_edges=peak;Ok(PageDependencyPeak{ledger:Arc::clone(ledger),key,old,actual:0,committed:false})
}
/// Callee settings/return proofs can demand additional ORIGINAL Kind4 inputs.
/// Reserve actual old/new Ctx overlap BEFORE the next unique dynamic read.
pub(super) fn reserve_actual_dependency(ledger:&Arc<Mutex<Ledger>>,key:Key,old:usize,next:usize,live:&ExecutionAdmission,initial:usize)->std::io::Result<()>{
 #[cfg(not(test))]let _=initial;
 crate::daemon::control::checkpoint()?;let mut l=ledger.lock().unwrap_or_else(|e|e.into_inner());let requested=old.checked_add(next.checked_mul(2).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect page dynamic dependency overflow"))?).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect page dynamic dependency overlap overflow"))?;let current=l.nodes.get(&key).ok_or_else(||std::io::Error::other("effect page dynamic node unavailable"))?.observed_edges;
 let delta=requested.saturating_sub(current).checked_mul(EDGE_BOUND).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect page dynamic edge admission overflow"))?;
 #[cfg(test)]if delta!=0{PAGE_EXTRA_EDGE_TRACE.with(|trace|if trace.get().is_none(){trace.set(Some((initial,live.available(),delta)))});}
 live.reserve_external(delta)?;
 l.admit(delta).map_err(|_|std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect page dynamic edge admission exhausted"))?;l.nodes.get_mut(&key).unwrap().observed_edges=current.max(requested);Ok(())
}
pub(super) fn page_execution_headroom(ledger:&Arc<Mutex<Ledger>>)->Result<usize,String>{
 let mut l=ledger.lock().unwrap_or_else(|e|e.into_inner());let occupied=l.live_bytes().checked_add(l.metadata()).ok_or("effect page live family capacity overflow")?;let headroom=BUDGET.checked_sub(occupied).ok_or_else(||{l.denied=true;"effect page family admission exhausted".to_string()})?;
 #[cfg(test)]let headroom=headroom.min(l.storage_test_limit.unwrap_or(BUDGET));
 Ok(headroom)
}
pub(super) fn page_execution_admission(ledger:&Arc<Mutex<Ledger>>)->Result<ExecutionAdmission,String>{Ok(ExecutionAdmission::with_limit(page_execution_headroom(ledger)?))}

#[derive(Debug)]struct PageGraphFailure(QueryError);
impl std::fmt::Display for PageGraphFailure{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{write!(f,"native effect page graph: {:?}",self.0)}}
impl std::error::Error for PageGraphFailure{}
pub(super) fn typed_publication(_ledger:&Arc<Mutex<Ledger>>,key:Key)->Result<(),QueryError>{
 #[cfg(test)]cancellation_test_checkpoint(key.kind);
 crate::daemon::control::checkpoint().map_err(|actual|QueryError::operational(key,actual))
}
pub(super) fn register(db:&Db,ledger:Arc<Mutex<Ledger>>,registry:SourceRegistry){
 db.define(PAGE,"native-original-effect-page",move|ctx,raw|{
  let p=raw.downcast_ref::<PageParams>().expect("original effect page params");typed_publication(&ledger,p.base.key)?;let input=p.base.input.upgrade().ok_or(QueryError::Missing(p.base.key))?;
  checked_sources_using::<ReadFailure>(&input,&p.base.sources,&registry,||crate::daemon::control::checkpoint().map_err(|actual|ReadFailure::Query(QueryError::operational(p.base.key,actual)))).map_err(|failure|match failure{ReadFailure::Semantic(_)=>QueryError::Missing(p.base.key),ReadFailure::Query(error)=>error})?;
  // These EXACT content inputs dominate every direct original resolver answer.
  // Kind4 reads remain explicit children; no body demand occurs in a resolver.
  if input.is_original_checker_source(){input.require_original_checker_source().map_err(|_|QueryError::Missing(p.base.key))?;}else{ctx.observe_input(PROJECT_KEY)?;ctx.get::<u128>(PROGRAM_KEY,Arc::<Vec<Key>>::clone(&p.base.sources))?;}
  let source=EffectSource::new(input.archive(),input.profile()).map_err(|failure|match policy_read_failure(p.base.key,failure){ReadFailure::Query(error)=>error,ReadFailure::Semantic(_)=>QueryError::Missing(p.base.key)})?;
  let admission=page_execution_admission(&ledger).map_err(|_|QueryError::Missing(p.base.key))?;
  let context=Mutex::new(ctx);
  let body=|syntax:&Arc<BodySyntaxInput>,live:&ExecutionAdmission|->Result<Arc<BodySyntax>,BodySyntaxFailure>{let mut context=context.lock().unwrap_or_else(|e|e.into_inner());let child=Key::new(body_syntax::BODY_SYNTAX,syntax.key().into());if !context.has_dependency(child){reserve_actual_dependency(&ledger,p.base.key,p.old_edges,context.dependency_count()+1,live,admission.available()).map_err(BodySyntaxFailure::Operational)?;}body_syntax::obtain(&mut context,syntax)};
  let validated=input.archive().tree().validated_checker_profile(input.profile()).map_err(|_|QueryError::Missing(p.base.key))?;
  let computed=if input.is_original_checker_source(){
   let mut obtain=|ordinal:usize,live:&ExecutionAdmission|->Result<Arc<BodyEffects>,ReadFailure>{let mut context=context.lock().unwrap_or_else(|e|e.into_inner());let child=key(BODY,&input,ordinal as u128);if !context.has_dependency(child){reserve_actual_dependency(&ledger,p.base.key,p.old_edges,context.dependency_count()+1,live,admission.available()).map_err(|actual|ReadFailure::Query(QueryError::operational(p.base.key,actual)))?;}get_body_with_admission(&mut context,&ledger,&p.base,ordinal,Some(live))};
   EffectPageFacts::compute_from_original_bodies(&source,&input,p.start,p.width,&admission,&mut crate::daemon::control::checkpoint,&mut obtain).map_err(|error|match error{dm_analysis::checker_effects::OriginalBodyReadFailure::Policy(actual)=>policy_read_failure(p.base.key,actual),dm_analysis::checker_effects::OriginalBodyReadFailure::Body(actual)=>actual})
  }else{EffectPageFacts::compute_checked(&source,p.start,p.width,&validated,&admission,&mut crate::daemon::control::checkpoint,&body).map_err(|failure|policy_read_failure(p.base.key,failure))};latch_transient_denial(&ledger,&admission);
  p.dependencies.store(context.lock().unwrap_or_else(|e|e.into_inner()).dependency_count(),std::sync::atomic::Ordering::Release);
  match split_transport(computed)?{Ok(value)=>graph_work::GraphWork::new(Arc::clone(&ledger),p.base.key).publish_data::<NativeEffectPage>(value),Err(message)=>{let bytes=message.capacity();finish_using::<NativeEffectPage>(&ledger,p.base.key,Err(message),bytes,typed_publication,|key,actual|QueryError::operational(key,std::io::Error::new(std::io::ErrorKind::OutOfMemory,actual)))}}
 });
}
impl QueryDb{
 pub(crate) fn native_effect_source_page(&self,input:&Arc<EffectInput>,scope:&crate::runner_host::query_snapshot::PurityScope<'_>,start:usize,width:usize)->std::io::Result<Arc<NativeEffectPage>>{
  crate::daemon::control::checkpoint()?;scope.validate(self,input).map_err(std::io::Error::other)?;self.prune_purity();let _gate=self.purity.gate.lock().unwrap_or_else(|e|e.into_inner());scope.validate(self,input).map_err(std::io::Error::other)?;
  {let mut l=self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner());l.denied=false;l.aborted=None;}
  let result=(||->Result<Arc<NativeEffectPage>,ReadFailure>{
   if !input.is_source_page_context(){return Err("effect page query needs original source-page context".into())}
   let source=EffectSource::new(input.archive(),input.profile()).map_err(|failure|policy_read_failure(page_key(input,start,width),failure))?;
   if width==0||width>dm_analysis::checker_effects::MAX_EVENTS||start>=source.len(){return Err("effect page query range outside original source roster".into())}let count=width.min(source.len()-start);let k=page_key(input,start,width);let sources=self.purity_sources_using::<ReadFailure>(input,|keys|checked_sources_using::<ReadFailure>(input,keys,&self.sources,||crate::daemon::control::checkpoint().map_err(|actual|ReadFailure::Query(QueryError::operational(k,actual)))),|actual|ReadFailure::Query(QueryError::operational(k,std::io::Error::new(std::io::ErrorKind::OutOfMemory,actual))))?;
   let _reservation=node_admission(&self.purity.ledger,input,k,std::mem::size_of::<PageParams>())?;
   let mut dependencies=reserve_dependencies(&self.purity.ledger,k,count)?;
   let params=Arc::new(PageParams{base:Params{body_admission:None,input:Arc::downgrade(input),key:k,ordinal:0,sources,policy:Weak::new()},start,width,old_edges:dependencies.old,dependencies:std::sync::atomic::AtomicUsize::new(0)});remember_params(&self.purity.ledger,input,k,&params);
   let result=self.db.get::<Result<Arc<NativeEffectPage>,String>>(k,params.clone()).map_err(ReadFailure::Query)?;dependencies.commit(params.dependencies.load(std::sync::atomic::Ordering::Acquire));
   crate::daemon::control::checkpoint().map_err(|actual|ReadFailure::Query(QueryError::operational(k,actual)))?;scope.validate(self,input)?;
   let value=result.as_ref().clone().map_err(ReadFailure::Semantic)?;value.validate(&source).map_err(|failure|policy_read_failure(k,failure))?;if value.start()!=start||value.len()==0||value.len()>count{return Err("effect page cache range differs from admitted params".into())}Ok(value)
  })();
  // No output is exposed until all current-source and final cancellation checks.
  match result{Err(ReadFailure::Query(error))=>match error.into_operational(){Ok(actual)=>Err(actual.into_io()),Err(error)=>{crate::daemon::control::checkpoint()?;if self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner()).denied{return Err(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"native effect page retained admission exhausted"))}Err(std::io::Error::other(PageGraphFailure(error)))}},other=>{crate::daemon::control::checkpoint()?;if self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner()).denied{return Err(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"native effect page retained admission exhausted"))}match other{Ok(value)=>Ok(value),Err(ReadFailure::Semantic(message))=>Err(std::io::Error::other(message)),Err(ReadFailure::Query(_))=>unreachable!()}}}
 }
}

#[cfg(test)]thread_local!{static PAGE_EXTRA_EDGE_TRACE:std::cell::Cell<Option<(usize,usize,usize)>>=const{std::cell::Cell::new(None)};}
#[cfg(test)]impl QueryDb{pub(crate) fn take_effect_edge_headroom_for_test(&self)->Option<(usize,usize,usize)>{PAGE_EXTRA_EDGE_TRACE.with(|trace|trace.take())}}

/// Same actual child getter, used under an already-held outer purity gate.
/// No nested public host/get/gate/reset or independent source read occurs.
pub(super) fn obtain(ctx:&mut dm_query::Ctx<'_>,ledger:&Arc<Mutex<Ledger>>,input:&Arc<EffectInput>,sources:&Arc<Vec<Key>>,start:usize,width:usize)->Result<Arc<NativeEffectPage>,ReadFailure>{obtain_using(ctx,ledger,input,sources,start,width,true)}
/// Report readers reuse the SAME detached Kind23 metadata while it fits. The
/// graph consumer still explicitly retires each consumed page as before.
pub(super) fn obtain_retained(ctx:&mut dm_query::Ctx<'_>,ledger:&Arc<Mutex<Ledger>>,input:&Arc<EffectInput>,sources:&Arc<Vec<Key>>,start:usize,width:usize)->Result<Arc<NativeEffectPage>,ReadFailure>{obtain_using(ctx,ledger,input,sources,start,width,false)}
fn obtain_using(ctx:&mut dm_query::Ctx<'_>,ledger:&Arc<Mutex<Ledger>>,input:&Arc<EffectInput>,sources:&Arc<Vec<Key>>,start:usize,width:usize,retire:bool)->Result<Arc<NativeEffectPage>,ReadFailure>{
 let source=EffectSource::new(input.archive(),input.profile()).map_err(|error|policy_read_failure(page_key(input,start,width),error))?;
 if width==0||width>dm_analysis::checker_effects::MAX_EVENTS||start>=source.len(){return Err("nested effect page range outside original source".into())}
 let key=page_key(input,start,width);if !retire{retire_report_pages_under_pressure(ctx,ledger,key).map_err(|actual|ReadFailure::Query(QueryError::operational(key,actual)))?;}let count=width.min(source.len()-start);let _node=node_admission(ledger,input,key,std::mem::size_of::<PageParams>())?;let mut peak=reserve_dependencies(ledger,key,count)?;
 let params=Arc::new(PageParams{base:Params{body_admission:None,input:Arc::downgrade(input),key,ordinal:0,sources:sources.clone(),policy:Weak::new()},start,width,old_edges:peak.old,dependencies:std::sync::atomic::AtomicUsize::new(0)});remember_params(ledger,input,key,&params);
 let retained=ctx.get::<Result<Arc<NativeEffectPage>,String>>(key,params.clone()).map_err(ReadFailure::Query)?;peak.commit(params.dependencies.load(std::sync::atomic::Ordering::Acquire));let value=retained.as_ref().clone().map_err(ReadFailure::Semantic)?;
 crate::daemon::control::checkpoint().map_err(|actual|ReadFailure::Query(QueryError::operational(key,actual)))?;value.validate(&source).map_err(|error|policy_read_failure(key,error))?;
 if value.start()!=start||value.len()==0||value.len()>count{return Err("nested effect page returned another original range".into())}
 // Evict only the actual successfully validated retained child. Its Arc loan
 // keeps the physical page payload/lease funded until this consumer drops it.
 if retire{ctx.evict_value_if_current(key,&retained);}Ok(value)
}
pub(super) fn restore_graph_error(ledger:&Arc<Mutex<Ledger>>,error:QueryError)->std::io::Error{match error.into_operational(){Ok(actual)=>actual.into_io(),Err(error)=>{if let Err(actual)=crate::daemon::control::checkpoint(){return actual}if ledger.lock().unwrap_or_else(|e|e.into_inner()).denied{return std::io::Error::new(std::io::ErrorKind::OutOfMemory,"native effect graph family admission exhausted")}std::io::Error::other(PageGraphFailure(error))}}}

#[cfg(test)]impl QueryDb{pub(crate) fn effect_page_outcome_hash_for_test(&self,input:&EffectInput,start:usize,width:usize)->u128{let key=page_key(input,start,width);let params=self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner()).nodes.get(&key).and_then(|node|node.params.as_ref()).and_then(Weak::upgrade).expect("actual previously issued PAGE params remain in same Db");self.db.hash(key,params).expect("actual current PAGE outcome")}}

/// A soft cache watermark, not an admission limit or promised page capacity.
/// Actual page/scratch/output allocations still use the unchanged SAME64MiB
/// ledger. Retiring a cached value never credits escaped physical page loans.
fn retire_report_pages_under_pressure(ctx:&dm_query::Ctx<'_>,ledger:&Arc<Mutex<Ledger>>,current:Key)->std::io::Result<()>{
 const HEADROOM:usize=BUDGET/16;
 let mut first=None;
 loop{
  crate::daemon::control::checkpoint()?;
  let candidate={let mut l=ledger.lock().unwrap_or_else(|e|e.into_inner());let occupied=l.live_bytes().saturating_add(l.metadata());if occupied.saturating_add(HEADROOM)<=BUDGET{return Ok(())}
   use std::ops::Bound::{Excluded,Included};let low=Key::new(PAGE,0);let high=Key::new(PAGE,u128::MAX);let after=l.page_retirement_cursor.filter(|key|key.kind==PAGE);let next=match after{Some(after)=>l.nodes.range((Excluded(after),Included(high))).next(),None=>l.nodes.range(low..=high).next()}.or_else(||l.nodes.range(low..=high).next()).map(|(&key,_)|key);let Some(next)=next else{return Ok(())};if first==Some(next){return Ok(())}if first.is_none(){first=Some(next)}l.page_retirement_cursor=Some(next);next};
  if candidate==current{continue}
  let Some(retained)=ctx.retained_value::<Result<Arc<NativeEffectPage>,String>>(candidate)else{continue};
  // Alias counts are sampled cache pressure eligibility, never a hard physical
  // no-alias guarantee. Real retained leases survive all concurrent Arc loans.
  let consumed=Arc::strong_count(&retained)==2&&retained.as_ref().as_ref().map_or(true,|page|Arc::strong_count(page)==1);
  if consumed{ctx.evict_value_if_current(candidate,&retained);}
  // NativeEffectPage frees the actual metadata before setting completion. Only
  // the next live_bytes pass may then credit its existing ledger row.
  drop(retained);
 }
}

#[cfg(test)]pub(crate) struct PageCachePressureForTest{_work:graph_work::GraphWork}
#[cfg(test)]impl QueryDb{pub(crate) fn hold_effect_page_cache_pressure_for_test(&self)->std::io::Result<PageCachePressureForTest>{let _gate=self.purity.gate.lock().unwrap_or_else(|e|e.into_inner());let available={let mut l=self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner());BUDGET.saturating_sub(l.live_bytes().saturating_add(l.metadata()))};let mut work=graph_work::GraphWork::new(self.purity.ledger.clone(),Key::new(PAGE,u128::MAX));work.reserve(available.saturating_sub(BUDGET/32))?;Ok(PageCachePressureForTest{_work:work})}}

// This operation borrows the existing family ledger only for resource lifetime;
// it neither constructs EffectInput nor registers a semantic query/Outcome.
impl QueryDb{
 pub(crate) fn with_original_keyword_overrides(&self,archive:&dm_tree::frontend::BodyArchive,resolver:&(impl Resolver+?Sized),profile:dm_ir::PackedU128,mut current:impl FnMut()->std::io::Result<()>,consume:impl FnOnce(&dm_analysis::checks_keyword_overrides::Findings<'_>)->std::io::Result<()>)->std::io::Result<()>{
  use dm_analysis::policy_body_demand::PolicyFailure;
  current()?;crate::daemon::control::checkpoint()?;self.prune_purity();
  let _gate=self.purity.gate.lock().unwrap_or_else(|e|e.into_inner());
  {let mut ledger=self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner());ledger.denied=false;ledger.aborted=None;}
  let validate=||->std::io::Result<()>{crate::daemon::control::checkpoint()?;if !archive.uses_body_queries(self)||resolver.source_owner()!=Some(std::ptr::from_ref(archive.tree()).cast()){return Err(std::io::Error::other("keyword fold requires this actual archive/Db/resolver"))}
   // This is a resource-only loan. Diagnostic source frames do not publish
   // the compiler PROGRAM registry; the caller authenticates the actual
   // captured source/mapping, and the archive joins this exact body-query Db.
   Ok(())};
  current()?;validate()?;
  // Key is coordination for GraphWork's lifetime brand, not a cached answer.
  let mut work=graph_work::GraphWork::new(Arc::clone(&self.purity.ledger),Key::new(PAGE,archive.tree().identity()));
  work.reserve(ExecutionAdmission::fixed_control_charge())?;
  // Issued only after fixed backing is funded; it drops before this work.
  let admission=page_execution_admission(&self.purity.ledger).map_err(|message|std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))?;
  let pending=dm_analysis::checks_keyword_overrides::with_archived(archive,resolver,profile,&admission,&mut work,&validate,|findings|{current().map_err(PolicyFailure::Operational)?;consume(findings).map_err(PolicyFailure::Operational)});
  // The analysis callback owns every ephemeral map/output buffer; it has now
  // physically dropped them. Work remains live until after final validation.
  if let Err(PolicyFailure::Operational(actual))=pending{return Err(actual)}
  current()?;validate()?;pending.map_err(|failure|match failure{PolicyFailure::Operational(actual)=>actual,PolicyFailure::Unsupported(message)=>std::io::Error::other(message.0)})
 }
}

// Per-body untagged diagnostics borrow this same resource family; no semantic
// query, cached answer, source role or alternative body representation is made.
impl QueryDb{pub(crate) fn with_original_call_arguments(&self,archive:&dm_tree::frontend::BodyArchive,body:&dm_tree::frontend::ArchivedBody<'_>,resolver:&(impl Resolver+?Sized),profile:dm_ir::PackedU128,mut current:impl FnMut()->std::io::Result<()>,consume:impl FnOnce(&dm_analysis::checks_proc_visibility::Findings<'_>)->std::io::Result<()>)->std::io::Result<()>{
 self.with_original_call_policy(archive,body,resolver,profile,"call_arguments",current,consume)}
pub(crate) fn with_original_call_policy(&self,archive:&dm_tree::frontend::BodyArchive,body:&dm_tree::frontend::ArchivedBody<'_>,resolver:&(impl Resolver+?Sized),profile:dm_ir::PackedU128,family:&str,mut current:impl FnMut()->std::io::Result<()>,consume:impl FnOnce(&dm_analysis::checks_proc_visibility::Findings<'_>)->std::io::Result<()>)->std::io::Result<()>{
 use dm_analysis::policy_body_demand::PolicyFailure;if !matches!(family,"call_arguments"|"filter_call"|"catch_parameter_count"|"static_reference"|"iteration_range"|"undefined_type"|"switch_case"){return Err(std::io::Error::other("original body policy family differs"))}current()?;crate::daemon::control::checkpoint()?;self.prune_purity();let _gate=self.purity.gate.lock().unwrap_or_else(|e|e.into_inner());{let mut ledger=self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner());ledger.denied=false;ledger.aborted=None;}
 let validate=||->std::io::Result<()>{crate::daemon::control::checkpoint()?;if !archive.uses_body_queries(self)||!body.belongs_to(archive)||resolver.source_owner()!=Some(std::ptr::from_ref(archive.tree()).cast()){return Err(std::io::Error::other("argument findings require actual archive/body/Db/resolver"))}Ok(())};current()?;validate()?;let mut work=graph_work::GraphWork::new(Arc::clone(&self.purity.ledger),Key::new(PAGE,archive.tree().identity()));let pending=if family=="switch_case"{dm_analysis::checks_call_arguments::with_switch_cases_archived_body(archive,body,resolver,profile,&mut work,&validate,|findings|{current().map_err(PolicyFailure::Operational)?;consume(findings).map_err(PolicyFailure::Operational)})}else if family=="undefined_type"{dm_analysis::checks_call_arguments::with_declared_types_archived_body(archive,body,resolver,profile,&mut work,&validate,|findings|{current().map_err(PolicyFailure::Operational)?;consume(findings).map_err(PolicyFailure::Operational)})}else if family=="iteration_range"{dm_analysis::checks_call_arguments::with_iteration_ranges_archived_body(archive,body,resolver,profile,&mut work,&validate,|findings|{current().map_err(PolicyFailure::Operational)?;consume(findings).map_err(PolicyFailure::Operational)})}else if family=="static_reference"{dm_analysis::checks_call_arguments::with_static_references_archived_body(archive,body,resolver,profile,&mut work,&validate,|findings|{current().map_err(PolicyFailure::Operational)?;consume(findings).map_err(PolicyFailure::Operational)})}else if family=="catch_parameter_count"{dm_analysis::checks_call_arguments::with_catch_parameters_archived_body(archive,body,resolver,profile,&mut work,&validate,|findings|{current().map_err(PolicyFailure::Operational)?;consume(findings).map_err(PolicyFailure::Operational)})}else if family=="filter_call"{dm_analysis::checks_call_arguments::with_filter_archived_body(archive,body,resolver,profile,&mut work,&validate,|findings|{current().map_err(PolicyFailure::Operational)?;consume(findings).map_err(PolicyFailure::Operational)})}else{dm_analysis::checks_call_arguments::with_archived_body(archive,body,resolver,profile,&mut work,&validate,|findings|{current().map_err(PolicyFailure::Operational)?;consume(findings).map_err(PolicyFailure::Operational)})};if let Err(PolicyFailure::Operational(actual))=pending{return Err(actual)}current()?;validate()?;pending.map_err(|failure|match failure{PolicyFailure::Operational(actual)=>actual,PolicyFailure::Unsupported(reason)=>std::io::Error::other(reason.0)})
}}

// Test-only real escrow owner. The production ledger limit is unchanged; this
// holds an ordinary pre-allocation reservation while the tested operation runs.
#[cfg(test)]impl QueryDb{pub(crate) fn effect_graph_headroom_for_test(&self,remaining:usize)->std::io::Result<impl Drop>{self.prune_purity();let _gate=self.purity.gate.lock().unwrap_or_else(|e|e.into_inner());let reserve={let mut ledger=self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner());BUDGET.checked_sub(ledger.live_bytes()).and_then(|n|n.checked_sub(ledger.metadata())).and_then(|n|n.checked_sub(remaining)).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"test cannot hold requested actual ledger headroom"))?};let mut held=graph_work::GraphWork::new(Arc::clone(&self.purity.ledger),Key::new(PAGE,0));held.reserve(reserve)?;Ok(held)}}

// Full-purpose keyword finalization borrows the SAME BODY nodes directly under
// the existing gate; it never recursively enters a public page/gate operation.
impl QueryDb{pub(crate) fn with_cached_original_keyword_overrides(&self,input:&Arc<EffectInput>,resolver:&(impl Resolver+?Sized),mut current:impl FnMut()->std::io::Result<()>,consume:impl FnOnce(&dm_analysis::checks_keyword_overrides::Findings<'_>)->std::io::Result<()>)->std::io::Result<()>{
 use dm_analysis::policy_body_demand::PolicyFailure;current()?;crate::daemon::control::checkpoint()?;input.require_original_checker_source().map_err(std::io::Error::other)?;input.validate_current(input.archive(),self).map_err(std::io::Error::other)?;self.prune_purity();let _gate=self.purity.gate.lock().unwrap_or_else(|e|e.into_inner());{let mut ledger=self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner());ledger.denied=false;ledger.aborted=None;}
 let sources=self.purity_sources(input).map_err(std::io::Error::other)?;let validate=||->std::io::Result<()>{crate::daemon::control::checkpoint()?;input.require_original_checker_source().map_err(std::io::Error::other)?;input.validate_current(input.archive(),self).map_err(std::io::Error::other)};validate()?;
 let mut work=graph_work::GraphWork::new(Arc::clone(&self.purity.ledger),Key::new(PAGE,input.archive().tree().identity()));work.reserve(ExecutionAdmission::fixed_control_charge())?;let admission=page_execution_admission(&self.purity.ledger).map_err(|message|std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))?;
 let mut obtain=|ordinal:usize,visit:&mut dyn FnMut(&BodyEffects)->Result<(),PolicyFailure>|->Result<(),PolicyFailure>{validate().map_err(PolicyFailure::Operational)?;let value=self.cached_original_body(input,&sources,&admission,ordinal)?;let body=value.as_ref().as_ref().map_err(|message|PolicyFailure::from(message.clone()))?;visit(body)
 };
 let pending=dm_analysis::checks_keyword_overrides::with_cached_body_uses(input,resolver,&admission,&mut work,&validate,&mut obtain,|findings|{current().map_err(PolicyFailure::Operational)?;consume(findings).map_err(PolicyFailure::Operational)});if let Err(PolicyFailure::Operational(actual))=pending{return Err(actual)}current()?;validate()?;pending.map_err(|failure|match failure{PolicyFailure::Operational(actual)=>actual,PolicyFailure::Unsupported(message)=>std::io::Error::other(message.0)})
}}

impl QueryDb{
 // Unique direct lookup of the SAME actual BODY key, also used by PAGE jobs.
 // Caller owns the existing purity gate and the genuine operation admission.
 fn cached_original_body(&self,input:&Arc<EffectInput>,sources:&Arc<Vec<Key>>,admission:&ExecutionAdmission,ordinal:usize)->Result<Arc<Result<Arc<BodyEffects>,String>>,dm_analysis::policy_body_demand::PolicyFailure>{
  use dm_analysis::policy_body_demand::PolicyFailure;input.require_original_checker_source()?;let actual=key(BODY,input,ordinal as u128);let extra=ExecutionAdmission::fixed_control_charge();let size=std::mem::size_of::<Params>().checked_add(extra).ok_or("cached original BODY parameter backing overflow")?;let _reserved=node_admission(&self.purity.ledger,input,actual,size).map_err(|message|PolicyFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))?;let params=Arc::new(Params{input:Arc::downgrade(input),key:actual,ordinal,sources:Arc::clone(sources),policy:Weak::new(),body_admission:Some(admission.downgrade_for_job())});remember_params_with_backing(&self.purity.ledger,input,actual,&params,extra);self.db.get::<Result<Arc<BodyEffects>,String>>(actual,params).map_err(|error|PolicyFailure::Operational(restore_graph_error(&self.purity.ledger,error)))
 }
 pub(crate) fn visit_cached_original_diagnostics(&self,input:&Arc<EffectInput>,mut current:impl FnMut()->std::io::Result<()>,mut consume:impl FnMut(usize,&dm_analysis::checker_effects::OriginalBodyDiagnostic)->std::io::Result<()>)->std::io::Result<()>{
  use dm_analysis::{policy_body_demand::PolicyFailure,checker_effects::OriginalDiagnosticPhase};current()?;crate::daemon::control::checkpoint()?;input.require_original_checker_source().map_err(std::io::Error::other)?;input.validate_current(input.archive(),self).map_err(std::io::Error::other)?;self.prune_purity();let _gate=self.purity.gate.lock().unwrap_or_else(|e|e.into_inner());{let mut ledger=self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner());ledger.denied=false;ledger.aborted=None;}
  let sources=self.purity_sources(input).map_err(std::io::Error::other)?;let validate=||->std::io::Result<()>{crate::daemon::control::checkpoint()?;input.require_original_checker_source().map_err(std::io::Error::other)?;input.validate_current(input.archive(),self).map_err(std::io::Error::other)};validate()?;let mut work=graph_work::GraphWork::new(Arc::clone(&self.purity.ledger),Key::new(PAGE,input.archive().tree().identity()));work.reserve(ExecutionAdmission::fixed_control_charge())?;let admission=page_execution_admission(&self.purity.ledger).map_err(|message|std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))?;
  let pending=dm_analysis::checker_order::with_archived_order_using(input.archive(),&admission,&mut work,&validate,|order,_work|{for phase in [OriginalDiagnosticPhase::Prelude,OriginalDiagnosticPhase::Body]{for rank in 0..order.len(){validate().map_err(PolicyFailure::Operational)?;let ordinal=order.ordinal(rank).ok_or("original checker order omitted body ordinal")?;let value=self.cached_original_body(input,&sources,&admission,ordinal)?;let body=value.as_ref().as_ref().map_err(|message|PolicyFailure::from(message.clone()))?;body.with_original_diagnostics(input,|rows|{for row in rows.iter().filter(|row|row.phase()==phase){validate().map_err(PolicyFailure::Operational)?;consume(ordinal,row).map_err(PolicyFailure::Operational)?;}Ok::<(),PolicyFailure>(())})??;}}Ok(())});
  if let Err(PolicyFailure::Operational(actual))=pending{return Err(actual)}current()?;validate()?;pending.map_err(|failure|match failure{PolicyFailure::Operational(actual)=>actual,PolicyFailure::Unsupported(message)=>std::io::Error::other(message.0)})
 }
}

// Global declarations are an independent source-only producer. This operation
// does not request a BODY, parse a procedure, or claim a global result cache.
impl QueryDb{
 pub(crate) fn with_original_declarations(&self,input:&Arc<EffectInput>,resolver:&(impl Resolver+?Sized),mut current:impl FnMut()->std::io::Result<()>,consume:impl FnOnce(&dm_analysis::checks_variable_visibility::OriginalDeclarations<'_>)->std::io::Result<()>)->std::io::Result<()>{
  use dm_analysis::policy_body_demand::PolicyFailure;current()?;crate::daemon::control::checkpoint()?;input.require_original_checker_source().map_err(std::io::Error::other)?;input.validate_current(input.archive(),self).map_err(std::io::Error::other)?;self.prune_purity();let _gate=self.purity.gate.lock().unwrap_or_else(|e|e.into_inner());{let mut ledger=self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner());ledger.denied=false;ledger.aborted=None;}
  let validate=||->std::io::Result<()>{crate::daemon::control::checkpoint()?;input.require_original_checker_source().map_err(std::io::Error::other)?;input.validate_current(input.archive(),self).map_err(std::io::Error::other)};validate()?;let mut work=graph_work::GraphWork::new(Arc::clone(&self.purity.ledger),Key::new(PAGE,input.archive().tree().identity()));work.reserve(ExecutionAdmission::fixed_control_charge())?;let admission=page_execution_admission(&self.purity.ledger).map_err(|message|std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))?;
  let pending=dm_analysis::checks_variable_visibility::with_original_declarations(input,resolver,&admission,&mut work,&validate,|findings|{if !findings.belongs_to(input){return Err("global declaration result belongs to another input".into())}current().map_err(PolicyFailure::Operational)?;consume(findings).map_err(PolicyFailure::Operational)});
  if let Err(PolicyFailure::Operational(actual))=pending{return Err(actual)}pending.map_err(|failure|match failure{PolicyFailure::Operational(actual)=>actual,PolicyFailure::Unsupported(reason)=>std::io::Error::other(reason.0)})?;current()?;validate()
 }
}

impl QueryDb{
 pub(crate) fn visit_original_reader_declarations(&self,input:&Arc<EffectInput>,mut current:impl FnMut()->std::io::Result<()>,mut consume:impl FnMut(dm_analysis::checks_proc_visibility::Finding<'_>)->std::io::Result<()>)->std::io::Result<()>{
  use dm_analysis::policy_body_demand::PolicyFailure;current()?;input.require_original_checker_source().map_err(std::io::Error::other)?;input.validate_current(input.archive(),self).map_err(std::io::Error::other)?;self.prune_purity();let _gate=self.purity.gate.lock().unwrap_or_else(|e|e.into_inner());{let mut ledger=self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner());ledger.denied=false;ledger.aborted=None;}
  let validate=||->std::io::Result<()>{crate::daemon::control::checkpoint()?;input.require_original_checker_source().map_err(std::io::Error::other)?;input.validate_current(input.archive(),self).map_err(std::io::Error::other)};
  let mut work=graph_work::GraphWork::new(Arc::clone(&self.purity.ledger),Key::new(PAGE,input.archive().tree().identity()));work.reserve(ExecutionAdmission::fixed_control_charge())?;let admission=page_execution_admission(&self.purity.ledger).map_err(|message|std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))?;
  let pending=dm_analysis::checks_proc_visibility::visit_original_declaration_redeclarations(input,&admission,&mut work,&validate,|row|consume(row).map_err(PolicyFailure::Operational));if let Err(PolicyFailure::Operational(actual))=pending{return Err(actual)}pending.map_err(|failure|match failure{PolicyFailure::Operational(actual)=>actual,PolicyFailure::Unsupported(reason)=>std::io::Error::other(reason.0)})?;current()?;validate()
 }
}
