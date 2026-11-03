//! Kind12: unique read/global policy work in the compiler's SAME Db.
//! Explicit bounded captures only; no installation or external gate reentry.
use super::*;
use dq_analyze::{captured_generator_budget::Budget,captured_reactive_reads::{self,Failure,Flavor,FrozenReadSet,ReadResult,GlobalResult,DependencyResult}};
use std::cell::RefCell;
pub(super) const REACTIVE_RESULT:Kind=Kind(12);
#[derive(Clone,Debug,serde::Serialize)]
pub(crate) enum Request{Globals,Dependencies,Read{receiver:String,procedure:String,context:Option<String>,flavor:Flavor}}
#[derive(Clone)]
pub(super) struct Params{
 pub(super) locator:(bool,u128),pub(super) capture:Weak<CapturedPolicyInputs>,pub(super) evidence:u64,pub(super) configuration:Key,
 pub(super) configuration_path:PathBuf,pub(super) files:Vec<Key>,pub(super) root:PathBuf,
 pub(super) result:Key,pub(super) request:Request,
}
pub(crate) enum Value{SemanticPolicy(super::reactive_workspace_policy::SemanticPolicy),Globals(GlobalResult),Reads(ReadResult),Dependencies(DependencyResult),RawReads(super::reactive_workspace_policy::Read),RawDependencies(super::reactive_workspace_policy::Dependencies),PolicyFacts(super::reactive_workspace_policy::Policy),FullArtifact(super::reactive_workspace_policy::FullArtifact)}
impl Value{
 pub(super) fn charge(&self)->Option<usize>{let payload=match self{Self::SemanticPolicy(v)=>v.retained_charge()?,Self::Globals(v)=>v.retained_charge()?,Self::Reads(v)=>v.retained_charge()?,Self::Dependencies(v)=>v.retained_charge()?,Self::RawReads(v)=>v.retained_charge()?,Self::RawDependencies(v)=>v.retained_charge()?,Self::PolicyFacts(v)=>v.retained_charge()?,Self::FullArtifact(v)=>v.retained_charge()?};payload.checked_add(std::mem::size_of::<Result<Self,String>>()+2*std::mem::size_of::<usize>())}
 pub(super) fn fingerprint(&self,poll:&dyn Fn()->io::Result<()>)->io::Result<u128>{
  struct HashWriter<'a>{hash:xxhash_rust::xxh3::Xxh3,poll:&'a dyn Fn()->io::Result<()>,first:Option<io::Error>}
  impl io::Write for HashWriter<'_>{fn write(&mut self,s:&[u8])->io::Result<usize>{if self.first.is_some(){return Err(io::Error::other("reactive hash stopped"))}if let Err(actual)=(self.poll)(){self.first=Some(actual);return Err(io::Error::other("reactive hash stopped"))}self.hash.update(s);Ok(s.len())}fn flush(&mut self)->io::Result<()>{Ok(())}}
  let mut writer=HashWriter{hash:xxhash_rust::xxh3::Xxh3::new(),poll,first:None};writer.hash.update(b"native-reactive-result-v1\0");
  let result=match self{Self::SemanticPolicy(v)=>{writer.hash.update(b"full-current-context-semantic-policy");v.serialize_data(&mut serde_json::Serializer::new(&mut writer))},Self::Globals(v)=>{writer.hash.update(b"globals");let mut serializer=serde_json::Serializer::new(&mut writer);v.serialize_dependency_facts(&mut serializer)},Self::Reads(v)=>{writer.hash.update(b"reads");serde_json::to_writer(&mut writer,v.facts())},Self::Dependencies(v)=>{writer.hash.update(b"dependencies");v.serialize_facts(&mut serde_json::Serializer::new(&mut writer))},Self::RawReads(v)=>{writer.hash.update(b"full-code-reads");serde_json::to_writer(&mut writer,v.facts())},Self::RawDependencies(v)=>{writer.hash.update(b"full-code-dependencies");v.serialize_facts(&mut serde_json::Serializer::new(&mut writer))},Self::FullArtifact(v)=>{writer.hash.update(b"full-workspace-generator");writer.hash.update(&v.fingerprint().to_le_bytes());Ok(())},Self::PolicyFacts(v)=>{writer.hash.update(b"shared-source-policy");writer.hash.update(&v.fingerprint(poll)?.to_le_bytes());Ok(())}};
  if let Some(actual)=writer.first.take(){return Err(actual)}result.map_err(io::Error::other)?;poll()?;Ok(writer.hash.digest128())
 }
}
#[derive(Debug)]struct ReactiveGraphFailure(QueryError);
impl std::fmt::Display for ReactiveGraphFailure{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{write!(f,"reactive dependency failed: {:?}",self.0)}}
impl std::error::Error for ReactiveGraphFailure{}
pub(super) fn graph_failure(error:QueryError)->Failure{Failure::Operational(match error.into_operational(){Ok(actual)=>actual.into_io(),Err(error)=>io::Error::other(ReactiveGraphFailure(error))})}
/// Existing parser-input issuance keys are LOCATORS only. Hash the whole
/// original roster without copying it; every answer still needs the upgraded
/// original owner witness and current semantic acquisition evidence.
pub(super) fn source_locator(capture:&CapturedPolicyInputs)->io::Result<(bool,u128)>{
 let Some(inputs)=capture.policy().archive().syntax_inputs().filter(|v|!v.is_empty())else{return Ok((false,capture.semantic_source_evidence().key() as u128))};
 let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"reactive-original-body-input-roster-v1\0");hash.update(&(inputs.len() as u64).to_le_bytes());for input in inputs{crate::daemon::control::checkpoint()?;hash.update(&input.key().to_le_bytes());}Ok((true,hash.digest128()))
}
/// SAME canonical metadata bytes as key(), streamed without an intermediate
/// JSON Vec. Actual first IO is restored outside serde's retrying Write adapter.
pub(super) fn metadata_key(value:&impl serde::Serialize)->io::Result<Key>{
 struct Sink{hash:xxhash_rust::xxh3::Xxh3,first:Option<io::Error>}
 impl io::Write for Sink{fn write(&mut self,bytes:&[u8])->io::Result<usize>{if self.first.is_some(){return Err(io::Error::other("reactive metadata hash stopped"))}if let Err(actual)=crate::daemon::control::checkpoint(){self.first=Some(actual);return Err(io::Error::other("reactive metadata hash stopped"))}self.hash.update(bytes);Ok(bytes.len())}fn flush(&mut self)->io::Result<()>{Ok(())}}
 let mut sink=Sink{hash:xxhash_rust::xxh3::Xxh3::new(),first:None};let result=serde_json::to_writer(&mut sink,value);if let Some(actual)=sink.first.take(){return Err(actual)}result.map_err(io::Error::other)?;Ok(Key::new(REACTIVE_RESULT,sink.hash.digest128()))
}
/// Borrowed key namespace/id tuples for BOTH prepared triples and key slices.
/// The iterator is cloned, never its source rows or backing storage.
struct KeyRows<I>(I);
impl<'a,I> serde::Serialize for KeyRows<I> where I:Clone+ExactSizeIterator<Item=&'a Key>{
 fn serialize<S:serde::Serializer>(&self,serializer:S)->Result<S::Ok,S::Error>{use serde::ser::SerializeSeq;let mut sequence=serializer.serialize_seq(Some(self.0.len()))?;for key in self.0.clone(){sequence.serialize_element(&(key.kind.0,key.id))?;}sequence.end()}
}
fn param_charge(p:&Params)->Option<usize>{
 let mut bytes=std::mem::size_of::<Params>().checked_add(512)?.checked_add(p.files.capacity().checked_mul(std::mem::size_of::<Key>())?)?;
 for path in [&p.root,&p.configuration_path]{bytes=bytes.checked_add(path.as_os_str().len().checked_mul(4)?)?;}
 if let Request::Read{receiver,procedure,context,..}=&p.request{bytes=bytes.checked_add(receiver.capacity())?.checked_add(procedure.capacity())?.checked_add(context.as_ref().map_or(0,String::capacity))?;}Some(bytes)
}
fn matches_current(value:&Result<Value,String>,capture:&CapturedPolicyInputs,request:&Request)->bool{match(value,request){(Ok(Value::Globals(v)),Request::Globals)=>v.matches(capture.policy()),(Ok(Value::Dependencies(v)),Request::Dependencies)=>v.matches(capture.policy()),(Ok(Value::Reads(v)),Request::Read{receiver,procedure,context,flavor})=>v.matches(capture.policy())&&v.matches_request(receiver,procedure,context.as_deref(),*flavor),_=>false}}
fn child_current(ctx:&mut dm_query::Ctx<'_>,capture:&Arc<CapturedPolicyInputs>,params:Params,parent:&Budget,charge:&AtomicUsize,admission:&Admission,metadata:usize)->Result<Arc<Result<Value,String>>,Failure>{
 let key=params.result;admission.admit_child(Arc::downgrade(capture),key,metadata).map_err(graph_failure)?;
 let fresh=params.clone();let value=admission.with_child(parent,charge,key,||ctx.get::<Result<Value,String>>(key,Arc::new(params))).map_err(graph_failure)?;
 if matches_current(value.as_ref(),capture,&fresh.request){return Ok(value)}
 // Same-code current mappings may legitimately reissue around old parser input
 // keys. They are source-foreign until freshly computed under ACTUAL evidence.
 let mut fresh=fresh;let key=metadata_key(&("current-evidence-recompute",key.id,capture.semantic_source_evidence().key()))?;fresh.result=key;
 admission.admit_child(Arc::downgrade(capture),key,metadata).map_err(graph_failure)?;
 let fresh=Arc::new(fresh);let value=admission.with_child(parent,charge,key,||ctx.get::<Result<Value,String>>(key,Arc::<Params>::clone(&fresh))).map_err(graph_failure)?;
 if !matches_current(value.as_ref(),capture,&fresh.request){return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"fresh reactive result failed actual original source witness")))}Ok(value)
}
pub(super) fn register(db:&Db,charge:Arc<AtomicUsize>,admission:Arc<Admission>){
 db.define(REACTIVE_RESULT,"native-reactive-unique-policy",move|ctx,params|{
  // SAME Kind12/Db dispatcher: a sealed UI request keeps its actual raw
  // owner evaluator, never the semantic mapping-dependent parameter path.
  if let Some(p)=params.downcast_ref::<super::reactive_ui_actions::Params>(){return super::reactive_ui_actions::compute(ctx,p,&charge,&admission)}
  if let Some(p)=params.downcast_ref::<super::reactive_workspace_policy::Params>(){return super::reactive_workspace_policy::compute(ctx,p,&charge,&admission)}
  let p=params.downcast_ref::<Params>().expect("reactive params");admission.abort.before_outcome(p.result)?;
  let capture=p.capture.upgrade().ok_or(QueryError::Missing(p.result))?;let config=ctx.input::<ConfigData>(p.configuration)?;
  let available=admission.limit.load(Ordering::Acquire).saturating_sub(charge.load(Ordering::Acquire));
  let budget=Budget::new(available).map_err(|message|{admission.denied.store(true,Ordering::Release);QueryError::operational(p.result,io::Error::new(io::ErrorKind::OutOfMemory,message))})?;
  let fixed=p.files.len().checked_mul(std::mem::size_of::<Arc<FileData>>()+std::mem::size_of::<Arc<File>>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(8192));
  let fixed=fixed.ok_or_else(||{budget.deny();admission.denied.store(true,Ordering::Release);QueryError::operational(p.result,io::Error::new(io::ErrorKind::OutOfMemory,"reactive fixed source coordination overflow"))})?;
  budget.charge(fixed).map_err(|message|{admission.denied.store(true,Ordering::Release);QueryError::operational(p.result,io::Error::new(io::ErrorKind::OutOfMemory,message))})?;
  let sources=p.files.iter().map(|k|ctx.input::<FileData>(*k)).collect::<Result<Vec<_>,_>>()?;
  let context=RefCell::new(ctx);
  let poll=||crate::daemon::control::checkpoint();
  let body=|input:&Arc<dm_tree::frontend::BodySyntaxInput>|super::super::body_syntax::obtain(&mut context.borrow_mut(),input);
  let produced=(||->Result<Value,Failure>{
   if capture.semantic_source_evidence().key()!=p.evidence{return Err("reactive source evidence issuance differs".into())}
   capture.semantic_source_evidence().check(capture.policy().mapping())?;generator_policy::manifest(&capture,&p.root)?;
   config.require_original(capture.configuration_bytes(&p.configuration_path)?)?;
   budget.charge(sources.iter().try_fold(0usize,|n,s|n.checked_add(s.file.path().as_os_str().len().checked_mul(16)?.checked_add(1024)?)).ok_or_else(||{budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reactive source coordination overflow"))})?)?;
   match &p.request{
    Request::Globals=>captured_reactive_reads::globals_native(capture.policy(),&p.root,&budget,&poll,&body).map(Value::Globals),
    Request::Read{..}|Request::Dependencies=>{
     let files=sources.iter().map(|s|Arc::clone(&s.file)).collect::<Vec<_>>();
     let raw=dq_analyze::captured_raw_policy::CapturedRawPolicy::from_shared_files(&p.root,capture.policy(),&config.config,&files)?;
     // This is an operation-local loan of an ORIGINAL Db value, not a new
     // retained cache. A root that asks no global/write question never gets it.
     let held=RefCell::new(None::<Arc<Result<Value,String>>>);
     let provider=|consume:&mut dyn FnMut(&GlobalResult)->Result<bool,Failure>|->Result<bool,Failure>{
      if held.borrow().is_none(){
       let metadata=param_charge(p).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(1024)).ok_or_else(||{budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reactive child params overflow"))})?;
       budget.charge(metadata)?;
       let child_key=metadata_key(&(p.locator,capture.policy_revision(),&p.root,&p.configuration_path,KeyRows(p.files.iter()),Request::Globals))?;
       admission.admit_child(Arc::downgrade(&capture),child_key,metadata).map_err(|_|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reactive child lease admission refused")))?;
       let mut child=p.clone();child.result=child_key;child.request=Request::Globals;
       let globals=child_current(&mut context.borrow_mut(),&capture,child,&budget,&charge,&admission,metadata)?;
       *held.borrow_mut()=Some(globals);
      }
      let loan=held.borrow();let value=loan.as_ref().expect("actual child obtained").as_ref().as_ref().map_err(|message|Failure::Unsupported(message.clone()))?;
      let Value::Globals(globals)=value else{return Err("reactive globals query returned wrong payload role".into())};consume(globals)
     };
     match &p.request{
      Request::Read{receiver,procedure,context:binding,flavor}=>captured_reactive_reads::reads(&raw,capture.policy(),&budget,&provider,receiver,procedure,binding.as_deref(),*flavor,&poll,&body).map(Value::Reads),
      Request::Dependencies=>{
       let reads=|receiver:&str,procedure:&str,binding:Option<&str>,flavor:Flavor,consume:&mut dyn FnMut(&ReadResult)->Result<(),Failure>|->Result<(),Failure>{
        // End the actual mutable context loan before classification can lazily
        // ask the sibling Globals question through the SAME original context.
        let loan={let mut ctx=context.borrow_mut();obtain_read_result(&mut ctx,&capture,p.configuration,&p.configuration_path,&p.root,&p.files,p.locator,receiver,procedure,binding,flavor,&budget,&charge,&admission)?};
        loan.with_value(|value|consume(value))
       };
       captured_reactive_reads::dependencies(&raw,capture.policy(),&budget,&provider,&reads,&poll,&body).map(Value::Dependencies)
      },Request::Globals=>unreachable!("native semantic-only branch selected above"),
     }
    }
   }
  })();
  let view_denied=sources.iter().any(|s|s.file.require_view_budget().is_err());if view_denied{admission.view_denied.store(true,Ordering::Release);admission.denied.store(true,Ordering::Release);}
  let result:Result<Value,String>=match produced{Err(Failure::Operational(actual))=>return Err(QueryError::operational(p.result,actual)),Err(Failure::Unsupported(message))=>{if view_denied||budget.denied(){admission.denied.store(true,Ordering::Release);return Err(QueryError::Missing(p.result))}return Err(QueryError::operational(p.result,io::Error::new(io::ErrorKind::Unsupported,message)))},Ok(value)=>Ok(value)};
  if !matches_current(&result,&capture,&p.request){return Err(QueryError::operational(p.result,io::Error::new(io::ErrorKind::InvalidData,"fresh reactive result does not match its actual requested root")))}
  admission.abort.before_outcome(p.result)?;if view_denied||budget.denied(){admission.denied.store(true,Ordering::Release);return Err(QueryError::Missing(p.result))}
  let(hash,bytes)=match &result{Ok(value)=>{let bytes=value.charge().ok_or_else(||{admission.denied.store(true,Ordering::Release);QueryError::Missing(p.result)})?;budget.charge(bytes).map_err(|_|{admission.denied.store(true,Ordering::Release);QueryError::Missing(p.result)})?;let hash=value.fingerprint(&poll).map_err(|actual|QueryError::operational(p.result,actual))?;(hash,bytes)},Err(error)=>(error_hash(error),result_error_charge::<Value>(error))};
  retain_derived(&charge,bytes,&admission,p.result)?;admission.abort.before_outcome(p.result)?;Ok(Outcome::new(result,hash,bytes))
 });
}

/// Native Kind11 consumers borrow a Kind12 read under their already-held family
/// gate. Every metadata allocation is covered by the caller's live budget.
pub(super) fn with_read<T>(ctx:&mut dm_query::Ctx<'_>,capture:&Arc<CapturedPolicyInputs>,configuration:Key,configuration_path:&Path,root:&Path,files:&[Key],locator:(bool,u128),receiver:&str,procedure:&str,binding:Option<&str>,flavor:Flavor,parent:&Budget,charge:&AtomicUsize,admission:&Admission,consume:impl FnOnce(&FrozenReadSet)->Result<T,Failure>)->Result<T,Failure>{
 with_read_result(ctx,capture,configuration,configuration_path,root,files,locator,receiver,procedure,binding,flavor,parent,charge,admission,|value|consume(value.facts()))
}

/// Exact actual child result for aggregate factories; SAME query/current-source
/// algorithm and active context, no second get or external family gate.
pub(super) fn with_read_result<T>(ctx:&mut dm_query::Ctx<'_>,capture:&Arc<CapturedPolicyInputs>,configuration:Key,configuration_path:&Path,root:&Path,files:&[Key],locator:(bool,u128),receiver:&str,procedure:&str,binding:Option<&str>,flavor:Flavor,parent:&Budget,charge:&AtomicUsize,admission:&Admission,consume:impl FnOnce(&ReadResult)->Result<T,Failure>)->Result<T,Failure>{
 let loan=obtain_read_result(ctx,capture,configuration,configuration_path,root,files,locator,receiver,procedure,binding,flavor,parent,charge,admission)?;loan.with_value(consume)
}

/// Operation-local actual result owner. Aggregate callers release their Ctx
/// RefMut BEFORE invoking the callback, allowing lazy sibling Globals questions
/// without reentrant RefCell borrows or a second Db.get.
pub(super) struct ReadLoan{value:Arc<Result<Value,String>>}
impl ReadLoan{pub(super) fn with_value<T>(&self,consume:impl FnOnce(&ReadResult)->Result<T,Failure>)->Result<T,Failure>{let value=self.value.as_ref().as_ref().map_err(|message|Failure::Unsupported(message.clone()))?;let Value::Reads(value)=value else{return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"original read loan payload role differs")))};consume(value)}}
pub(super) fn obtain_read_result(ctx:&mut dm_query::Ctx<'_>,capture:&Arc<CapturedPolicyInputs>,configuration:Key,configuration_path:&Path,root:&Path,files:&[Key],locator:(bool,u128),receiver:&str,procedure:&str,binding:Option<&str>,flavor:Flavor,parent:&Budget,charge:&AtomicUsize,admission:&Admission)->Result<ReadLoan,Failure>{
 let width=receiver.len().checked_add(procedure.len()).and_then(|n|n.checked_add(binding.map_or(0,str::len))).ok_or_else(||{parent.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reactive read request width overflow"))})?;
 let value=obtain_current_result(ctx,capture,configuration,configuration_path,root,files,locator,width,||Request::Read{receiver:receiver.to_owned(),procedure:procedure.to_owned(),context:binding.map(str::to_owned),flavor},parent,charge,admission)?;Ok(ReadLoan{value})
}
/// SAME actual Kind12 dependency child under existing Kind11 caller context.
/// No gate reentry, bare data import, second query, or source role conversion.
pub(super) fn with_dependencies<T>(ctx:&mut dm_query::Ctx<'_>,capture:&Arc<CapturedPolicyInputs>,configuration:Key,configuration_path:&Path,root:&Path,files:&[Key],parent:&Budget,charge:&AtomicUsize,admission:&Admission,consume:impl FnOnce(&DependencyResult)->Result<T,Failure>)->Result<T,Failure>{
 let locator=source_locator(capture)?;let loan=obtain_current_result(ctx,capture,configuration,configuration_path,root,files,locator,0,||Request::Dependencies,parent,charge,admission)?;
 let value=loan.as_ref().as_ref().map_err(|message|Failure::Unsupported(message.clone()))?;let Value::Dependencies(value)=value else{return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"dependency child payload role differs")))};consume(value)
}
fn obtain_current_result(ctx:&mut dm_query::Ctx<'_>,capture:&Arc<CapturedPolicyInputs>,configuration:Key,configuration_path:&Path,root:&Path,files:&[Key],locator:(bool,u128),request_width:usize,make_request:impl FnOnce()->Request,parent:&Budget,charge:&AtomicUsize,admission:&Admission)->Result<Arc<Result<Value,String>>,Failure>{
 capture.semantic_source_evidence().check(capture.policy().mapping())?;generator_policy::manifest(capture,root)?;
 let current_config=ctx.input::<ConfigData>(configuration).map_err(graph_failure)?;current_config.require_original(capture.configuration_bytes(configuration_path)?)?;
 let metadata=files.len().checked_mul(std::mem::size_of::<Key>()).and_then(|n|n.checked_add(root.as_os_str().len().checked_mul(4)?)).and_then(|n|n.checked_add(configuration_path.as_os_str().len().checked_mul(4)?)).and_then(|n|n.checked_add(request_width)).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(std::mem::size_of::<Params>()+4096)).ok_or_else(||{parent.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reactive request metadata overflow"))})?;
 parent.charge(metadata)?;
 let request=make_request();
 let evidence=capture.semantic_source_evidence().key();
 let result=metadata_key(&(locator,capture.policy_revision(),root,configuration_path,KeyRows(files.iter()),&request))?;
 admission.admit_child(Arc::downgrade(capture),result,metadata).map_err(graph_failure)?;
 let params=Params{locator,capture:Arc::downgrade(capture),evidence,configuration,configuration_path:configuration_path.to_owned(),files:files.to_vec(),root:root.to_owned(),result,request};
 // child_current checks actual current owner AND this exact request before returning.
 child_current(ctx,capture,params,parent,charge,admission,metadata)
}

impl QueryDb{
 /// Explicit finite proof endpoint. No native CLI/default installation. The
 /// payload is borrowed under the original raw-family gate and never escapes.
 pub(crate) fn with_reactive_fixture<T>(&self,cohort:&Arc<Cohort>,request:Request,consume:impl FnOnce(&Value)->io::Result<T>)->io::Result<T>{self.with_reactive_fixture_limit(cohort,request,None,consume)}
 fn with_reactive_fixture_limit<T>(&self,cohort:&Arc<Cohort>,request:Request,limit:Option<usize>,consume:impl FnOnce(&Value)->io::Result<T>)->io::Result<T>{
  crate::daemon::control::checkpoint()?;
  if cohort.issuer!=self.id||!cohort.capture.policy().archive().uses_body_queries(self){return Err(invalid("foreign reactive cohort"))}
  let evidence=cohort.capture.semantic_source_evidence();evidence.check(cohort.capture.policy().mapping())?;generator_policy::manifest(&cohort.capture,&cohort.root)?;
  let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());let now=Instant::now();self.raw_prune_locked(now);
  let prepared=match self.raw_prepare_locked(cohort,&[],now){Ok(value)=>value,Err(error)=>{self.discard_poisoned_generator_files_locked(cohort);return Err(error)}};
  // Existing source/config key roster is finite and admitted by raw_prepare.
  // Reserve the request metadata before allocating its key/owned Params.
  let width=match &request{Request::Globals|Request::Dependencies=>0,Request::Read{receiver,procedure,context,..}=>receiver.len().checked_add(procedure.len()).and_then(|n|n.checked_add(context.as_ref().map_or(0,String::len))).ok_or_else(||invalid("reactive request metadata overflow"))?};
  let metadata=width.checked_add(cohort.root.as_os_str().len().checked_mul(4).ok_or_else(||invalid("reactive root width overflow"))?).and_then(|n|n.checked_add(cohort.configuration.as_os_str().len().checked_mul(4)?)).and_then(|n|n.checked_add(prepared.sources.len().checked_mul(std::mem::size_of::<Key>())?)).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(std::mem::size_of::<Params>()+4096)).filter(|n|*n<=INPUT_BUDGET).ok_or_else(||invalid("reactive request metadata exceeds unchanged input budget"))?;
  let locator=source_locator(&cohort.capture)?;
  let result=metadata_key(&(locator,cohort.capture.policy_revision(),&cohort.root,&cohort.configuration,KeyRows(prepared.sources.iter().map(|(key,_,_)|key)),&request))?;
  self.begin_result_admission_locked()?;self.raw_policy.admission.admit_child(Arc::downgrade(&cohort.capture),result,metadata).map_err(|error|self.derived_query_error("reactive input metadata admission",error))?;
  let files=prepared.sources.iter().map(|(key,_,_)|*key).collect::<Vec<_>>();if let Some(limit)=limit{self.raw_policy.admission.limit.fetch_min(limit,Ordering::AcqRel);}
  let params=Arc::new(Params{locator,capture:Arc::downgrade(&cohort.capture),evidence:evidence.key(),configuration:prepared.configuration,configuration_path:cohort.configuration.clone(),files,root:cohort.root.clone(),result,request});
  let computed=self.db.get::<Result<Value,String>>(result,Arc::<Params>::clone(&params));
  let mut value=match computed{Ok(value)=>value,Err(error)=>{
   if self.raw_policy.admission.view_denied.load(Ordering::Acquire){self.discard_poisoned_generator_files_locked(cohort);}
   return Err(self.derived_query_error("native reactive query",error));
  }};
  if !matches_current(value.as_ref(),&cohort.capture,&params.request){
   let mut fresh=(*params).clone();let fresh_key=metadata_key(&("current-evidence-recompute",result.id,evidence.key()))?;fresh.result=fresh_key;
   self.raw_policy.admission.admit_child(Arc::downgrade(&cohort.capture),fresh_key,metadata).map_err(|error|self.derived_query_error("reactive fallback metadata admission",error))?;
   value=self.db.get::<Result<Value,String>>(fresh_key,Arc::new(fresh)).map_err(|error|self.derived_query_error("native reactive current-source recomputation",error))?;
   if !matches_current(value.as_ref(),&cohort.capture,&params.request){return Err(invalid("fresh reactive result failed actual source witness"))}
  }
  if self.raw_retained_view_bytes_locked()?>INPUT_BUDGET||self.raw_policy.charge.load(Ordering::Acquire)>RESULT_BUDGET{return Err(invalid("native reactive retained budget exhausted"))}
  if self.raw_policy.charge.load(Ordering::Acquire)>self.raw_policy.admission.limit.load(Ordering::Acquire){return Err(io::Error::new(io::ErrorKind::OutOfMemory,"reactive cached result exceeds current operation headroom"))}
  let value=value.as_ref().as_ref().map_err(|message|invalid(message.clone()))?;
  let matches=match(value,&params.request){(Value::Globals(v),Request::Globals)=>v.matches(cohort.capture.policy()),(Value::Dependencies(v),Request::Dependencies)=>v.matches(cohort.capture.policy()),(Value::Reads(v),Request::Read{receiver,procedure,context,flavor})=>v.matches(cohort.capture.policy())&&v.matches_request(receiver,procedure,context.as_deref(),*flavor),_=>false};
  if !matches{return Err(invalid("reactive result original source owner differs"))}
  crate::daemon::control::checkpoint()?;let output=consume(value)?;crate::daemon::control::checkpoint()?;Ok(output)
 }
}

#[cfg(test)]
#[path="reactive_read_tests.rs"]mod tests;

#[cfg(test)]mod same_kind_dispatch_tests{
 use super::*;
 #[test]fn existing_legacy_kind12_payload_keeps_its_real_capture_refusal_without_borrowing_ui_control(){let db=QueryDb::default();let key=Key::new(REACTIVE_RESULT,0x1200_0001);let p=Params{locator:(false,0),capture:Weak::new(),evidence:0,configuration:Key::new(RAW_CONFIG,0),configuration_path:PathBuf::new(),files:Vec::new(),root:PathBuf::new(),result:key,request:Request::Globals};let error=match db.db.get::<Result<Value,String>>(key,Arc::new(p)){Err(error)=>error,Ok(_)=>panic!("missing actual semantic owner cannot become UI/raw success")};assert!(matches!(error,QueryError::Missing(actual)if actual==key));assert!(db.db.retained_value::<Result<Value,String>>(key).is_none());}
}
