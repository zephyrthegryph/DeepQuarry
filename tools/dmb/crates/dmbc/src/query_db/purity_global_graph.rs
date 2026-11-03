//! One global source graph, with actual Kind23 loans and original global IDs.
use super::*;
use dm_analysis::checker_effects::{CompactEffectGraph,EffectSource,RetainedEffectGraph};
pub(super) const GLOBAL_GRAPH:Kind=Kind(24);

/// The public internal Arc owns this handle, never the payload Arc directly.
/// Every private strong payload drop uses into_inner; there are no Weak payload
/// aliases. Payload allocation/graph buffers free BEFORE its SAME-ledger lease.
pub(crate) struct NativeEffectGraph{payload:Option<Arc<GraphPayload>>}
struct GraphPayload{graph:RetainedEffectGraph,lease:graph_work::GraphLease,#[cfg(test)]drop_pause:Mutex<Option<(Arc<std::sync::Barrier>,Arc<std::sync::Barrier>)>>}
impl Drop for NativeEffectGraph{fn drop(&mut self){if let Some(payload)=self.payload.take().and_then(Arc::into_inner){#[cfg(test)]if let Some((entered,release))=payload.drop_pause.lock().unwrap_or_else(|e|e.into_inner()).take(){entered.wait();release.wait();}
let GraphPayload{graph,lease,..}=payload;drop(graph);drop(lease);}}}
impl NativeEffectGraph{
 pub(super) fn original_report_graph(&self)->&RetainedEffectGraph{&self.payload().graph}

 #[cfg(test)]pub(crate) fn pause_drop_for_test(&self,entered:Arc<std::sync::Barrier>,release:Arc<std::sync::Barrier>){*self.payload().drop_pause.lock().unwrap_or_else(|e|e.into_inner())=Some((entered,release));}
 fn payload(&self)->&GraphPayload{self.payload.as_deref().expect("sealed native effect graph payload")}
 pub(super) fn issue(graph:RetainedEffectGraph,ledger:Arc<Mutex<Ledger>>,completion:Arc<std::sync::atomic::AtomicBool>)->Arc<Self>{Arc::new(Self{payload:Some(Arc::new(GraphPayload{graph,lease:graph_work::GraphLease{ledger,completion},#[cfg(test)]drop_pause:Mutex::new(None)}))})}
 pub(super) fn coordination_charge()->usize{std::mem::size_of::<GraphPayload>().saturating_sub(std::mem::size_of::<RetainedEffectGraph>())}
 pub(crate) fn current<'view,'source>(&'view self,source:&'view EffectSource<'source>)->Result<dm_analysis::checker_effects::CurrentEffectGraph<'view,'source>,dm_analysis::policy_body_demand::PolicyFailure>{self.payload().graph.current(source)}
 pub(crate) fn retained_charge(&self)->Option<usize>{self.payload().graph.retained_charge()?.checked_add(Self::coordination_charge())}
 pub(crate) fn visit_storage(&self,mut visit:impl FnMut(Storage)){
  let payload=self.payload();payload.graph.visit_storage(&mut visit);
  visit(Storage::Buffer{owner:"purity.graph_private_payload",address:payload as *const GraphPayload as usize,logical:std::mem::size_of::<GraphPayload>(),capacity:std::mem::size_of::<GraphPayload>()});
  visit(Storage::Buffer{owner:"purity.graph_shared_ledger",address:Arc::as_ptr(&payload.lease.ledger) as usize,logical:std::mem::size_of::<Mutex<Ledger>>(),capacity:std::mem::size_of::<Mutex<Ledger>>()});
  visit(Storage::Buffer{owner:"purity.graph_completion",address:Arc::as_ptr(&payload.lease.completion) as usize,logical:std::mem::size_of::<std::sync::atomic::AtomicBool>(),capacity:std::mem::size_of::<std::sync::atomic::AtomicBool>()});
  // Existing ledger census owns nested key/node geometry. Standard Arc/control
  // and caller-owned outer handle coordination remain the typed baseline.
 }
}

struct GraphParams{base:Params,width:usize}
fn graph_key(input:&EffectInput,width:usize)->Key{key(GLOBAL_GRAPH,input,width as u128)}
fn dependency_peak(ledger:&Arc<Mutex<Ledger>>,key:Key)->Result<(),String>{
 // Every child page is an existing purity node, under unchanged MAX_NODES.
 // Include project/program and old/new Ctx overlap before the first read.
 let bound=MAX_NODES.checked_add(2).and_then(|n|n.checked_mul(2)).ok_or("effect graph dependency envelope overflow")?;let mut ledger=ledger.lock().unwrap_or_else(|e|e.into_inner());let old=ledger.nodes.get(&key).ok_or("effect graph node unreserved")?.observed_edges;
 ledger.admit(bound.saturating_sub(old).checked_mul(EDGE_BOUND).ok_or("effect graph edge admission overflow")?)?;ledger.nodes.get_mut(&key).unwrap().observed_edges=old.max(bound);Ok(())
}
fn failure(ledger:&Arc<Mutex<Ledger>>,error:ReadFailure)->dm_analysis::policy_body_demand::PolicyFailure{match error{ReadFailure::Semantic(message)=>message.into(),ReadFailure::Query(error)=>dm_analysis::policy_body_demand::PolicyFailure::Operational(pages::restore_graph_error(ledger,error))}}
pub(super) fn register(db:&Db,ledger:Arc<Mutex<Ledger>>,registry:SourceRegistry){
 db.define(GLOBAL_GRAPH,"native-original-global-effect-graph",move|ctx,raw|{
  let params=raw.downcast_ref::<GraphParams>().expect("global effect graph params");pages::typed_publication(&ledger,params.base.key)?;
  let input=params.base.input.upgrade().ok_or(QueryError::Missing(params.base.key))?;
  checked_sources_using::<ReadFailure>(&input,&params.base.sources,&registry,||crate::daemon::control::checkpoint().map_err(|actual|ReadFailure::Query(QueryError::operational(params.base.key,actual)))).map_err(|error|match error{ReadFailure::Query(error)=>error,ReadFailure::Semantic(_)=>QueryError::Missing(params.base.key)})?;
  ctx.observe_input(PROJECT_KEY)?;ctx.get::<u128>(PROGRAM_KEY,params.base.sources.clone())?;
  let source=EffectSource::new(input.archive(),input.profile()).map_err(|error|match policy_read_failure(params.base.key,error){ReadFailure::Query(error)=>error,ReadFailure::Semantic(_)=>QueryError::Missing(params.base.key)})?;
  let admission=pages::page_execution_admission(&ledger).map_err(|_|QueryError::Missing(params.base.key))?;
  let mut work=graph_work::GraphWork::new(Arc::clone(&ledger),params.base.key);
  let mut read=|start,width,_child:&ExecutionAdmission,_checkpoint:&mut fn()->std::io::Result<()>|{
   let page=pages::obtain(ctx,&ledger,&input,&params.base.sources,start,width).map_err(|error|failure(&ledger,error))?;
   // Retain hashes/dependencies while releasing derived page payloads. The
   // returned Arc loan remains funded until this graph iteration drops it.
   Ok(page)
  };
  let mut checkpoint:fn()->std::io::Result<()>=crate::daemon::control::checkpoint;
  let computed=CompactEffectGraph::build_pages_reserved_checked(&source,params.width,input.archive().tree(),&admission,&mut checkpoint,&mut read,&mut|bytes|work.reserve(bytes)).and_then(|graph|graph.into_retained_checked(&mut crate::daemon::control::checkpoint,&mut|bytes|work.reserve(bytes))).map_err(|error|policy_read_failure(params.base.key,error));
  latch_transient_denial(&ledger,&admission);
  match split_transport(computed)?{Ok(graph)=>work.publish(graph),Err(message)=>{drop(work);let bytes=message.capacity();finish_using::<NativeEffectGraph>(&ledger,params.base.key,Err(message),bytes,pages::typed_publication,|key,actual|QueryError::operational(key,std::io::Error::new(std::io::ErrorKind::OutOfMemory,actual)))} }
 });
}
impl QueryDb{
 pub(crate) fn native_effect_source_graph(&self,input:&Arc<EffectInput>,scope:&crate::runner_host::query_snapshot::PurityScope<'_>,width:usize)->std::io::Result<Arc<NativeEffectGraph>>{
  crate::daemon::control::checkpoint()?;scope.validate(self,input).map_err(std::io::Error::other)?;self.prune_purity();let _gate=self.purity.gate.lock().unwrap_or_else(|e|e.into_inner());scope.validate(self,input).map_err(std::io::Error::other)?;
  {let mut ledger=self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner());ledger.denied=false;ledger.aborted=None;}
  let result=(||->Result<Arc<NativeEffectGraph>,ReadFailure>{
   if !input.is_source_page_context()||width==0||width>dm_analysis::checker_effects::MAX_EVENTS{return Err("effect global graph requires original source-page context/window".into())}
   let key=graph_key(input,width);let sources=self.purity_sources_using::<ReadFailure>(input,|keys|checked_sources_using::<ReadFailure>(input,keys,&self.sources,||crate::daemon::control::checkpoint().map_err(|actual|ReadFailure::Query(QueryError::operational(key,actual)))),|actual|ReadFailure::Query(QueryError::operational(key,std::io::Error::new(std::io::ErrorKind::OutOfMemory,actual))))?;
   let _node=node_admission(&self.purity.ledger,input,key,std::mem::size_of::<GraphParams>())?;dependency_peak(&self.purity.ledger,key)?;
   let params=Arc::new(GraphParams{base:Params{body_admission:None,input:Arc::downgrade(input),key,ordinal:0,sources,policy:Weak::new()},width});remember_params(&self.purity.ledger,input,key,&params);
   let value=self.db.get::<Result<Arc<NativeEffectGraph>,String>>(key,params).map_err(ReadFailure::Query)?.as_ref().clone().map_err(ReadFailure::Semantic)?;
   crate::daemon::control::checkpoint().map_err(|actual|ReadFailure::Query(QueryError::operational(key,actual)))?;scope.validate(self,input)?;let source=EffectSource::new(input.archive(),input.profile()).map_err(|error|policy_read_failure(key,error))?;value.current(&source).map_err(|error|policy_read_failure(key,error))?;Ok(value)
  })();
  match result{Err(ReadFailure::Query(error))=>Err(pages::restore_graph_error(&self.purity.ledger,error)),other=>{crate::daemon::control::checkpoint()?;if self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner()).denied{return Err(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"native effect global graph retained admission exhausted"))}match other{Ok(value)=>Ok(value),Err(ReadFailure::Semantic(message))=>Err(std::io::Error::other(message)),Err(ReadFailure::Query(_))=>unreachable!()}}}
 }
}

impl graph_work::RetainedHandle for NativeEffectGraph{fn fingerprint(&self,_:Key)->u128{self.payload().graph.report_fingerprint()}type Data=RetainedEffectGraph;fn coordination_charge()->usize{Self::coordination_charge()}fn issue(data:RetainedEffectGraph,ledger:Arc<Mutex<Ledger>>,completion:Arc<std::sync::atomic::AtomicBool>)->Arc<Self>{Self::issue(data,ledger,completion)}fn retained_charge(&self)->Option<usize>{Self::retained_charge(self)}}
/// Nested SAME Db child loan, while the actual outer gate remains held.
pub(super) fn obtain(ctx:&mut dm_query::Ctx<'_>,ledger:&Arc<Mutex<Ledger>>,input:&Arc<EffectInput>,sources:&Arc<Vec<Key>>,width:usize)->Result<Arc<NativeEffectGraph>,ReadFailure>{let key=graph_key(input,width);let _node=node_admission(ledger,input,key,std::mem::size_of::<GraphParams>())?;dependency_peak(ledger,key)?;let params=Arc::new(GraphParams{base:Params{body_admission:None,input:Arc::downgrade(input),key,ordinal:0,sources:sources.clone(),policy:Weak::new()},width});remember_params(ledger,input,key,&params);let value=ctx.get::<Result<Arc<NativeEffectGraph>,String>>(key,params).map_err(ReadFailure::Query)?.as_ref().clone().map_err(ReadFailure::Semantic)?;let source=EffectSource::new(input.archive(),input.profile()).map_err(|error|policy_read_failure(key,error))?;value.current(&source).map_err(|error|policy_read_failure(key,error))?;Ok(value)}
