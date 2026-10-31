//! Actual bounded contribution-page query in the EXISTING purity ledger.
//! Page jobs depend on the original whole program input plus actual Kind4
//! bodies, so source mode needs no per-resolver semantic model/query roster.
use super::*;
use dm_analysis::checker_effects::{EffectPageFacts,EffectSource};
use dm_tree::frontend::{BodySyntax,BodySyntaxFailure,BodySyntaxInput};
pub(super) const PAGE:Kind=Kind(23);
struct PageParams{base:Params,start:usize,width:usize,old_edges:usize,dependencies:std::sync::atomic::AtomicUsize}
fn page_key(input:&EffectInput,start:usize,width:usize)->Key{key(PAGE,input,((start as u128)<<64)|(width as u128))}
/// Begin with its own window +project/program; callee prefix reads extend
/// this actual read-set reservation before ctx.note.
/// Reserve old/new dynamic-edge overlap before ctx.note can allocate. After
/// Db::get returns/unwinds, the old/new temporary Ctx has physically gone and
/// only one bounded immutable dependency set remains. No cumulative retry leak.
struct PageDependencyPeak{ledger:Arc<Mutex<Ledger>>,key:Key,old:usize,actual:usize,committed:bool}
impl PageDependencyPeak{fn commit(&mut self,actual:usize){self.actual=actual;self.committed=true}}
impl Drop for PageDependencyPeak{fn drop(&mut self){let actual=self.actual;if let Some(node)=self.ledger.lock().unwrap_or_else(|e|e.into_inner()).nodes.get_mut(&self.key){node.observed_edges=if self.committed&&actual!=0{actual}else{self.old};}}}
fn reserve_dependencies(ledger:&Arc<Mutex<Ledger>>,key:Key,count:usize)->Result<PageDependencyPeak,String>{
 let minimum=count.checked_add(2).ok_or("effect page dependency count overflow")?;let mut l=ledger.lock().unwrap_or_else(|e|e.into_inner());let old=l.nodes.get(&key).ok_or("effect page node was not reserved")?.observed_edges;let peak=old.checked_add(minimum.checked_mul(2).ok_or("effect page dependency peak overflow")?).ok_or("effect page dependency overlap overflow")?;
 l.admit(peak.saturating_sub(old).checked_mul(EDGE_BOUND).ok_or("effect page dependency admission overflow")?)?;l.nodes.get_mut(&key).unwrap().observed_edges=peak;Ok(PageDependencyPeak{ledger:Arc::clone(ledger),key,old,actual:0,committed:false})
}
/// Callee settings/return proofs can demand additional ORIGINAL Kind4 inputs.
/// Reserve actual old/new Ctx overlap BEFORE the next unique dynamic read.
fn reserve_actual_dependency(ledger:&Arc<Mutex<Ledger>>,key:Key,old:usize,next:usize,live:&ExecutionAdmission,initial:usize)->std::io::Result<()>{
 #[cfg(not(test))]let _=initial;
 crate::daemon::control::checkpoint()?;let mut l=ledger.lock().unwrap_or_else(|e|e.into_inner());let requested=old.checked_add(next.checked_mul(2).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect page dynamic dependency overflow"))?).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect page dynamic dependency overlap overflow"))?;let current=l.nodes.get(&key).ok_or_else(||std::io::Error::other("effect page dynamic node unavailable"))?.observed_edges;
 let delta=requested.saturating_sub(current).checked_mul(EDGE_BOUND).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect page dynamic edge admission overflow"))?;
 #[cfg(test)]if delta!=0{PAGE_EXTRA_EDGE_TRACE.with(|trace|if trace.get().is_none(){trace.set(Some((initial,live.available(),delta)))});}
 live.reserve_external(delta)?;
 l.admit(delta).map_err(|_|std::io::Error::new(std::io::ErrorKind::OutOfMemory,"effect page dynamic edge admission exhausted"))?;l.nodes.get_mut(&key).unwrap().observed_edges=current.max(requested);Ok(())
}
pub(super) fn page_execution_admission(ledger:&Arc<Mutex<Ledger>>)->Result<ExecutionAdmission,String>{
 let mut l=ledger.lock().unwrap_or_else(|e|e.into_inner());let occupied=l.live_bytes().checked_add(l.metadata()).ok_or("effect page live family capacity overflow")?;let headroom=BUDGET.checked_sub(occupied).ok_or_else(||{l.denied=true;"effect page family admission exhausted".to_string()})?;
 #[cfg(test)]let headroom=headroom.min(l.storage_test_limit.unwrap_or(BUDGET));
 Ok(ExecutionAdmission::with_limit(headroom))
}
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
  ctx.observe_input(PROJECT_KEY)?;ctx.get::<u128>(PROGRAM_KEY,Arc::<Vec<Key>>::clone(&p.base.sources))?;
  let source=EffectSource::new(input.archive(),input.profile()).map_err(|failure|match policy_read_failure(p.base.key,failure){ReadFailure::Query(error)=>error,ReadFailure::Semantic(_)=>QueryError::Missing(p.base.key)})?;
  let admission=page_execution_admission(&ledger).map_err(|_|QueryError::Missing(p.base.key))?;
  let context=Mutex::new(ctx);
  let body=|syntax:&Arc<BodySyntaxInput>,live:&ExecutionAdmission|->Result<Arc<BodySyntax>,BodySyntaxFailure>{let mut context=context.lock().unwrap_or_else(|e|e.into_inner());let child=Key::new(body_syntax::BODY_SYNTAX,syntax.key().into());if !context.has_dependency(child){reserve_actual_dependency(&ledger,p.base.key,p.old_edges,context.dependency_count()+1,live,admission.available()).map_err(BodySyntaxFailure::Operational)?;}body_syntax::obtain(&mut context,syntax)};
  let validated=input.archive().tree().validated_checker_profile(input.profile()).map_err(|_|QueryError::Missing(p.base.key))?;
  let computed=EffectPageFacts::compute_checked(&source,p.start,p.width,&validated,&admission,&mut crate::daemon::control::checkpoint,&body).map(Arc::new).map_err(|failure|policy_read_failure(p.base.key,failure));latch_transient_denial(&ledger,&admission);
  p.dependencies.store(context.lock().unwrap_or_else(|e|e.into_inner()).dependency_count(),std::sync::atomic::Ordering::Release);
  let value=split_transport(computed)?;let bytes=size_error(&value,|page|page.retained_charge().unwrap_or(usize::MAX));finish_using(&ledger,p.base.key,value,bytes,typed_publication,|key,actual|QueryError::operational(key,std::io::Error::new(std::io::ErrorKind::OutOfMemory,actual)))
 });
}
impl QueryDb{
 pub(crate) fn native_effect_source_page(&self,input:&Arc<EffectInput>,scope:&crate::runner_host::query_snapshot::PurityScope<'_>,start:usize,width:usize)->std::io::Result<Arc<EffectPageFacts>>{
  crate::daemon::control::checkpoint()?;scope.validate(self,input).map_err(std::io::Error::other)?;self.prune_purity();let _gate=self.purity.gate.lock().unwrap_or_else(|e|e.into_inner());scope.validate(self,input).map_err(std::io::Error::other)?;
  {let mut l=self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner());l.denied=false;l.aborted=None;}
  let result=(||->Result<Arc<EffectPageFacts>,ReadFailure>{
   if !input.is_source_page_context(){return Err("effect page query needs original source-page context".into())}
   let source=EffectSource::new(input.archive(),input.profile()).map_err(|failure|policy_read_failure(page_key(input,start,width),failure))?;
   if width==0||width>dm_analysis::checker_effects::MAX_EVENTS||start>=source.len(){return Err("effect page query range outside original source roster".into())}let count=width.min(source.len()-start);let k=page_key(input,start,width);let sources=self.purity_sources_using::<ReadFailure>(input,|keys|checked_sources_using::<ReadFailure>(input,keys,&self.sources,||crate::daemon::control::checkpoint().map_err(|actual|ReadFailure::Query(QueryError::operational(k,actual)))),|actual|ReadFailure::Query(QueryError::operational(k,std::io::Error::new(std::io::ErrorKind::OutOfMemory,actual))))?;
   let _reservation=node_admission(&self.purity.ledger,input,k,std::mem::size_of::<PageParams>())?;
   let mut dependencies=reserve_dependencies(&self.purity.ledger,k,count)?;
   let params=Arc::new(PageParams{base:Params{input:Arc::downgrade(input),key:k,ordinal:0,sources,policy:Weak::new()},start,width,old_edges:dependencies.old,dependencies:std::sync::atomic::AtomicUsize::new(0)});remember_params(&self.purity.ledger,input,k,&params);
   let result=self.db.get::<Result<Arc<EffectPageFacts>,String>>(k,params.clone()).map_err(ReadFailure::Query)?;dependencies.commit(params.dependencies.load(std::sync::atomic::Ordering::Acquire));
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
pub(super) fn obtain(ctx:&mut dm_query::Ctx<'_>,ledger:&Arc<Mutex<Ledger>>,input:&Arc<EffectInput>,sources:&Arc<Vec<Key>>,start:usize,width:usize)->Result<Arc<EffectPageFacts>,ReadFailure>{
 let source=EffectSource::new(input.archive(),input.profile()).map_err(|error|policy_read_failure(page_key(input,start,width),error))?;
 if width==0||width>dm_analysis::checker_effects::MAX_EVENTS||start>=source.len(){return Err("nested effect page range outside original source".into())}
 let key=page_key(input,start,width);let count=width.min(source.len()-start);let _node=node_admission(ledger,input,key,std::mem::size_of::<PageParams>())?;let mut peak=reserve_dependencies(ledger,key,count)?;
 let params=Arc::new(PageParams{base:Params{input:Arc::downgrade(input),key,ordinal:0,sources:sources.clone(),policy:Weak::new()},start,width,old_edges:peak.old,dependencies:std::sync::atomic::AtomicUsize::new(0)});remember_params(ledger,input,key,&params);
 let value=ctx.get::<Result<Arc<EffectPageFacts>,String>>(key,params.clone()).map_err(ReadFailure::Query)?;peak.commit(params.dependencies.load(std::sync::atomic::Ordering::Acquire));let value=value.as_ref().clone().map_err(ReadFailure::Semantic)?;
 crate::daemon::control::checkpoint().map_err(|actual|ReadFailure::Query(QueryError::operational(key,actual)))?;value.validate(&source).map_err(|error|policy_read_failure(key,error))?;
 if value.start()!=start||value.len()==0||value.len()>count{return Err("nested effect page returned another original range".into())}Ok(value)
}
pub(super) fn restore_graph_error(ledger:&Arc<Mutex<Ledger>>,error:QueryError)->std::io::Error{match error.into_operational(){Ok(actual)=>actual.into_io(),Err(error)=>{if let Err(actual)=crate::daemon::control::checkpoint(){return actual}if ledger.lock().unwrap_or_else(|e|e.into_inner()).denied{return std::io::Error::new(std::io::ErrorKind::OutOfMemory,"native effect graph family admission exhausted")}std::io::Error::other(PageGraphFailure(error))}}}
