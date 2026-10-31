//! Full original CODE_DM read/dependency jobs in SAME Kind12 and family gate.
//! Completion/source authority remains host-private; Analyze returns data only.
use super::*;use super::reactive_read_policy::{self as finite,Request,Value};
use dq_analyze::{captured_generator_budget::Budget,captured_reactive_reads::{self as reads,Failure,GlobalResult,UnsealedReadData,UnsealedDependencyData}};
use crate::runner_host::{workspace_capture::WorkspaceCapture,query_snapshot::workspace_native_guard::WorkspaceQueryScope};
use super::workspace::{WorkspaceCodeReader,WorkspaceCodeWitness};use std::cell::RefCell;
pub(super) struct Params{generator:Option<generator_policy::GeneratorName>,policy:bool,key:Key,issuance:u64,evidence:u64,locator:(bool,u128),configuration:Key,configuration_path:PathBuf,root:PathBuf,request:Request}
pub(super) struct Read{data:UnsealedReadData,witness:WorkspaceCodeWitness}
pub(super) struct Dependencies{data:UnsealedDependencyData,witness:WorkspaceCodeWitness}
pub(super) struct Policy{data:reads::UnsealedPolicyFacts,witness:WorkspaceCodeWitness}
impl Policy{pub(super) fn retained_charge(&self)->Option<usize>{self.data.retained_charge()?.checked_add(witness_charge(&self.witness)?)}pub(super) fn fingerprint(&self,poll:&dyn Fn()->io::Result<()>)->io::Result<u128>{match self.data.fingerprint(poll){Ok(hash)=>Ok(hash),Err(Failure::Operational(actual))=>Err(actual),Err(Failure::Unsupported(message))=>Err(io::Error::new(io::ErrorKind::Unsupported,message))}}}
fn witness_charge(witness:&WorkspaceCodeWitness)->Option<usize>{let mut sum=Some(std::mem::size_of::<WorkspaceCodeWitness>());witness.visit_storage(|_,bytes|sum=sum.and_then(|n|n.checked_add(bytes)));sum}
impl Read{pub(super) fn retained_charge(&self)->Option<usize>{self.data.retained_charge()?.checked_add(witness_charge(&self.witness)?)}pub(super) fn facts(&self)->&reads::FrozenReadSet{self.data.facts()}}
impl Dependencies{pub(super) fn retained_charge(&self)->Option<usize>{self.data.retained_charge()?.checked_add(witness_charge(&self.witness)?)}pub(super) fn serialize_facts<S:serde::Serializer>(&self,serializer:S)->Result<S::Ok,S::Error>{self.data.serialize_facts(serializer)}}
fn split<T>(result:Result<T,Failure>)->io::Result<Result<T,String>>{match result{Ok(value)=>Ok(Ok(value)),Err(Failure::Operational(actual))=>Err(actual),Err(Failure::Unsupported(message))=>Ok(Err(message))}}
fn flatten<T>(result:io::Result<Result<T,String>>)->Result<T,Failure>{match result{Ok(Ok(value))=>Ok(value),Ok(Err(message))=>Err(Failure::Unsupported(message)),Err(actual)=>Err(Failure::Operational(actual))}}
fn actual(value:&Value,p:&Params,loan:&super::reactive_workspace_operation::Loan,scope:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>)->Result<bool,Failure>{if p.policy{return match value{Value::PolicyFacts(value)=>Ok(value.data.matches_compiled(loan.capture.policy())&&value.witness.matches(&loan.workspace,scope,loan.capture.policy())?),_=>Ok(false)}}if let Some(name)=p.generator{return match value{Value::FullArtifact(value)=>value.matches(name,loan,scope),_=>Ok(false)}}match(value,&p.request){
 (Value::Globals(value),Request::Globals)=>Ok(value.matches(loan.capture.policy())),
 (Value::RawReads(value),Request::Read{receiver,procedure,context,flavor})=>Ok(value.data.matches_compiled(loan.capture.policy())&&value.data.matches_request(receiver,procedure,context.as_deref(),*flavor)&&value.witness.matches(&loan.workspace,scope,loan.capture.policy())?),
 (Value::RawDependencies(value),Request::Dependencies)=>Ok(value.data.matches_compiled(loan.capture.policy())&&value.witness.matches(&loan.workspace,scope,loan.capture.policy())?),_=>Ok(false)}}
struct Pages<'reader,'capture,'scope>{reader:&'reader WorkspaceCodeReader<'capture,'scope>,inputs:&'reader dm_analysis::policy_inputs::PolicyInputs,witness:RefCell<Option<WorkspaceCodeWitness>>}
impl dq_analyze::reactive_raw_policy_pages::RawPolicyPages for Pages<'_,'_,'_>{fn for_each(&self,visit:&mut dyn FnMut(&str,dq_analyze::captured_raw_file::RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
 let complete=self.reader.for_each_code_file_completed(self.inputs,visit)?;match complete{super::workspace::WorkspaceCodeTraversal::Stopped=>Ok(false),completed=>{if self.witness.borrow().is_none(){let witness=completed.into_witness()?.ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"completed raw traversal lost receipt")))?;*self.witness.borrow_mut()=Some(witness);}Ok(true)}}
}}
fn key_for(p:&Params,request:&Request)->io::Result<Key>{let metadata=finite::metadata_key(&("full-original-code-policy-v1",p.issuance,p.evidence,p.locator,p.policy,p.generator,p.configuration.kind.0,p.configuration.id,&p.root,&p.configuration_path,request))?;Ok(Key::new(if p.generator.is_some(){generator_policy::GENERATOR_RESULT}else{finite::REACTIVE_RESULT},metadata.id))}
fn metadata(p:&Params,request:&Request)->Option<usize>{let width=match request{Request::Read{receiver,procedure,context,..}=>receiver.len().checked_add(procedure.len())?.checked_add(context.as_ref().map_or(0,String::len))?,_=>0};std::mem::size_of::<Params>().checked_add(1024)?.checked_add(width.checked_mul(4)?)?.checked_add(p.root.as_os_str().len().checked_mul(4)?)?.checked_add(p.configuration_path.as_os_str().len().checked_mul(4)?)}
fn get_current(ctx:&mut dm_query::Ctx<'_>,p:Params,loan:&super::reactive_workspace_operation::Loan,admission:&Admission)->Result<Arc<Result<Value,String>>,Failure>{
 let bytes=metadata(&p,&p.request).ok_or_else(||{loan.budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"full policy parameter capacity overflow"))})?;loan.budget.charge(bytes)?;let key=p.key;admission.admit_child(Arc::downgrade(&loan.capture),key,bytes).map_err(finite::graph_failure)?;
 // SAME root Budget already funds all new child scratch+retention. A second
 // with_child delta transfer here would double charge these same allocations.
 ctx.get::<Result<Value,String>>(key,Arc::new(p)).map_err(finite::graph_failure)
}
fn policy_result(ctx:&mut dm_query::Ctx<'_>,p:&Params,loan:&super::reactive_workspace_operation::Loan,admission:&Admission)->Result<Arc<Result<Value,String>>,Failure>{let bytes=metadata(p,&Request::Globals).and_then(|n|n.checked_mul(4)).ok_or_else(||{loan.budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"shared policy parameters overflow"))})?;loan.budget.charge(bytes)?;let mut child=Params{generator:None,policy:true,key:p.key,issuance:p.issuance,evidence:p.evidence,locator:p.locator,configuration:p.configuration,configuration_path:p.configuration_path.clone(),root:p.root.clone(),request:Request::Globals};child.key=key_for(&child,&child.request)?;get_current(ctx,child,loan,admission)}
pub(super) fn compute(ctx:&mut dm_query::Ctx<'_>,p:&Params,charge:&AtomicUsize,admission:&Admission)->Result<Outcome,QueryError>{
 admission.abort.before_outcome(p.key)?;let loan=admission.current_workspace_operation(p.issuance,p.evidence).map_err(|actual|QueryError::operational(p.key,actual))?;
 let produced=flatten(loan.scope.with_context(ctx,&loan.workspace,loan.capture.policy(),|queries,scope,ctx|split(queries.with_workspace_code_pages_budget_locked(&loan.workspace,scope,&loan.budget,|reader|{
  reader.require_policy_inputs(loan.capture.policy())?;loan.capture.semantic_source_evidence().check(loan.capture.policy().mapping())?;generator_policy::manifest(&loan.capture,&p.root)?;
  if loan.locator!=p.locator||reader.root()!=p.root||reader.configuration().0!=p.configuration_path{return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"full policy current metadata differs")))}
  let config=ctx.input::<ConfigData>(p.configuration).map_err(finite::graph_failure)?;config.require_original(loan.capture.configuration_bytes(&p.configuration_path)?)?;
  if reader.configuration().1!=loan.capture.configuration_bytes(&p.configuration_path)?{return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"workspace/captured configuration differs")))}
  let poll=||crate::daemon::control::checkpoint();let order=reads::scoped_original_include_order(loan.capture.policy(),reader.root(),reader.budget())?;let context=RefCell::new(ctx);let body=|input:&Arc<dm_tree::frontend::BodySyntaxInput>|super::super::body_syntax::obtain(&mut context.borrow_mut(),input);
  let held=RefCell::new(None::<Arc<Result<Value,String>>>);let globals=|consume:&mut dyn FnMut(&GlobalResult)->Result<bool,Failure>|->Result<bool,Failure>{
   if held.borrow().is_none(){let bytes=metadata(p,&Request::Globals).and_then(|n|n.checked_mul(4)).ok_or_else(||{loan.budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"full globals child metadata overflow"))})?;loan.budget.charge(bytes)?;
    let mut child=Params{generator:None,policy:false,key:p.key,issuance:p.issuance,evidence:p.evidence,locator:p.locator,configuration:p.configuration,configuration_path:p.configuration_path.clone(),root:p.root.clone(),request:Request::Globals};child.key=key_for(&child,&child.request)?;
    let value=get_current(&mut context.borrow_mut(),child,&loan,admission)?;*held.borrow_mut()=Some(value);
   }let held=held.borrow();let value=held.as_ref().expect("actual globals child").as_ref().as_ref().map_err(|message|Failure::Unsupported(message.clone()))?;let Value::Globals(value)=value else{return Err("full globals child returned wrong role".into())};consume(value)
  };
  let pages=Pages{reader,inputs:loan.capture.policy(),witness:RefCell::new(None)};
  if p.policy{let data=reads::policy_data_from_pages(loan.capture.policy(),reader.root(),&pages,&order,reader.budget(),&poll)?;let witness=pages.witness.into_inner().ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"shared policy omitted actual raw completion")))?;return Ok(Value::PolicyFacts(Policy{data,witness}))}
  let held_policy=RefCell::new(None::<Arc<Result<Value,String>>>);let policy=|consume:&mut dyn FnMut(&reads::UnsealedPolicyFacts)->Result<(),Failure>|->Result<(),Failure>{if held_policy.borrow().is_none(){let value=policy_result(&mut context.borrow_mut(),p,&loan,admission)?;*held_policy.borrow_mut()=Some(value);}let held=held_policy.borrow();let value=held.as_ref().expect("actual shared policy child").as_ref().as_ref().map_err(|message|Failure::Unsupported(message.clone()))?;let Value::PolicyFacts(value)=value else{return Err("shared policy child payload role differs".into())};if !value.data.matches_compiled(loan.capture.policy())||!value.witness.matches(&loan.workspace,scope,loan.capture.policy())?{return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"shared policy current source differs")))}consume(&value.data)};
  let read_provider=|receiver:&str,procedure:&str,binding:Option<&str>,flavor:reads::Flavor,consume:&mut dyn FnMut(&UnsealedReadData)->Result<(),Failure>|->Result<(),Failure>{
    let bytes=metadata(p,&Request::Read{receiver:String::new(),procedure:String::new(),context:None,flavor}).and_then(|n|n.checked_add(receiver.len().checked_add(procedure.len())?.checked_add(binding.map_or(0,str::len))?.checked_mul(4)?)).ok_or_else(||{loan.budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"full read child parameter overflow"))})?;loan.budget.charge(bytes)?;
    let request=Request::Read{receiver:receiver.to_owned(),procedure:procedure.to_owned(),context:binding.map(str::to_owned),flavor};let mut child=Params{generator:None,policy:false,key:p.key,issuance:p.issuance,evidence:p.evidence,locator:p.locator,configuration:p.configuration,configuration_path:p.configuration_path.clone(),root:p.root.clone(),request};child.key=key_for(&child,&child.request)?;let value={get_current(&mut context.borrow_mut(),child,&loan,admission)?};
    let value=value.as_ref().as_ref().map_err(|message|Failure::Unsupported(message.clone()))?;let Value::RawReads(value)=value else{return Err("full read child returned wrong payload".into())};if !value.data.matches_request(receiver,procedure,binding,flavor)||!value.data.matches_compiled(loan.capture.policy())||!value.witness.matches(&loan.workspace,scope,loan.capture.policy())?{return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"full read child current request/source differs")))}consume(&value.data)
   };
  let dependencies=|consume:&mut dyn FnMut(&Dependencies)->Result<Value,Failure>|->Result<Value,Failure>{let bytes=metadata(p,&Request::Dependencies).and_then(|n|n.checked_mul(4)).ok_or_else(||{loan.budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"full dependency child parameters overflow"))})?;loan.budget.charge(bytes)?;let mut child=Params{generator:None,policy:false,key:p.key,issuance:p.issuance,evidence:p.evidence,locator:p.locator,configuration:p.configuration,configuration_path:p.configuration_path.clone(),root:p.root.clone(),request:Request::Dependencies};child.key=key_for(&child,&child.request)?;let value=get_current(&mut context.borrow_mut(),child,&loan,admission)?;let value=value.as_ref().as_ref().map_err(|message|Failure::Unsupported(message.clone()))?;let Value::RawDependencies(value)=value else{return Err("generator dependency child returned another role".into())};if !value.data.matches_compiled(loan.capture.policy())||!value.witness.matches(&loan.workspace,scope,loan.capture.policy())?{return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"generator dependency child source differs")))}consume(value)};
  if let Some(name)=p.generator{return full_generator::produce_generator(name,p,&loan,reader,scope,&pages,&order,&config.config,&dependencies,&policy,&read_provider,&poll,&body)}
  match &p.request{
   Request::Read{receiver,procedure,context:binding,flavor}=>{let data=reads::read_data_from_pages_with_policy(loan.capture.policy(),reader.root(),&pages,&order,reader.budget(),&globals,&policy,receiver,procedure,binding.as_deref(),*flavor,&poll,&body)?;let held=held_policy.borrow();let value=held.as_ref().expect("policy loan retained while deriving read receipt").as_ref().as_ref().map_err(|message|Failure::Unsupported(message.clone()))?;let Value::PolicyFacts(value)=value else{return Err("read policy child role differs".into())};let witness=value.witness.reissue(&loan.workspace,scope,loan.capture.policy(),&mut|bytes|reader.budget().charge(bytes).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message)))?;Ok(Value::RawReads(Read{data,witness}))},
   Request::Dependencies=>{
    let data=reads::dependency_data_from_pages_with_policy(loan.capture.policy(),reader.root(),&pages,&order,reader.budget(),&globals,&read_provider,&policy,&poll,&body)?;let witness=pages.witness.into_inner().ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"dependency fold omitted actual completed raw traversal")))?;Ok(Value::RawDependencies(Dependencies{data,witness}))},Request::Globals=>reads::globals_native(loan.capture.policy(),reader.root(),reader.budget(),&poll,&body).map(Value::Globals)
  }
 }))));
 let result:Result<Value,String>=match produced{Ok(value)=>Ok(value),Err(Failure::Operational(actual))=>return Err(QueryError::operational(p.key,actual)),Err(Failure::Unsupported(message))=>{crate::daemon::control::checkpoint().map_err(|actual|QueryError::operational(p.key,actual))?;let kind=if loan.budget.denied(){io::ErrorKind::OutOfMemory}else{io::ErrorKind::Unsupported};return Err(QueryError::operational(p.key,io::Error::new(kind,message)))}};
 let checked=loan.scope.with_context(ctx,&loan.workspace,loan.capture.policy(),|_,scope,_|split((||->Result<(),Failure>{match &result{Ok(value)=>if actual(value,p,&loan,scope)?{Ok(())}else{Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"full result current request/source mismatch")))},Err(_)=>Err("full policy unexpected semantic result".into())}})()));flatten(checked).map_err(|failure|match failure{Failure::Operational(actual)=>QueryError::operational(p.key,actual),Failure::Unsupported(message)=>QueryError::operational(p.key,io::Error::new(io::ErrorKind::Unsupported,message))})?;
 let value=result.as_ref().expect("successful full policy");let bytes=value.charge().ok_or_else(||QueryError::operational(p.key,io::Error::new(io::ErrorKind::OutOfMemory,"full result retained capacity overflow")))?;let coordination=std::mem::size_of::<Result<Value,String>>().checked_add(2*std::mem::size_of::<usize>()).and_then(|n|match value{Value::Globals(global)=>n.checked_add(global.owner_coordination_charge()?),Value::RawReads(_)|Value::RawDependencies(_)|Value::PolicyFacts(_)|Value::FullArtifact(_)=>Some(n),_=>None}).ok_or_else(||QueryError::operational(p.key,io::Error::new(io::ErrorKind::OutOfMemory,"full result wrapper capacity overflow")))?;loan.budget.charge(coordination).map_err(|message|QueryError::operational(p.key,io::Error::new(io::ErrorKind::OutOfMemory,message)))?;let hash=value.fingerprint(&crate::daemon::control::checkpoint).map_err(|actual|QueryError::operational(p.key,actual))?;retain_derived(charge,bytes,admission,p.key)?;admission.abort.before_outcome(p.key)?;Ok(Outcome::new(result,hash,bytes))
}

fn configuration_input(queries:&QueryDb,reader:&WorkspaceCodeReader<'_,'_>,capture:&Arc<CapturedPolicyInputs>)->Result<Key,Failure>{
 let(path,bytes)=reader.configuration();let current=capture.configuration_bytes(path)?;if current!=bytes{return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"workspace configuration does not match actual compiler capture")))}
 let charge=bytes.map_or(0,<[u8]>::len).checked_mul(64).and_then(|n|n.checked_add(4096)).ok_or_else(||{reader.budget().deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"workspace configuration capacity overflow"))})?;reader.budget().charge(charge)?;
 let key=Key::new(RAW_CONFIG,finite::metadata_key(&(reader.root(),path))?.id);let hash=match bytes{None=>dm_query::hash_bytes(b"proven-missing"),Some(_)=>{let content=capture.facts().files().find(|file|file.path==path).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"workspace config has no original recorded digest")))?.content;let mut fixed=[0u8;24];fixed[..8].copy_from_slice(b"present\0");fixed[8..].copy_from_slice(&content.to_le_bytes());dm_query::hash_bytes(&fixed)}};
 let config=match queries.db.input::<ConfigData>(key){Some(old)if old.hash==hash=>{old.require_original(bytes)?;Arc::clone(&old.config)},_=>Arc::new(Config::capture(match bytes{Some(bytes)=>Configuration::Captured(bytes),None=>Configuration::ProvenMissing})?)};
 queries.raw_policy.admission.admit_child(Arc::downgrade(capture),key,config.budget_charge()).map_err(finite::graph_failure)?;queries.db.set_input(key,ConfigData{config,hash,original:capture.configuration_owner(path)?},hash);Ok(key)
}
impl QueryDb{
 /// Explicit source-complete CODE_DM result loan. No installation/default CLI
 /// switch. Scope and full traversal proof are required on every warm delivery.
 pub(crate) fn with_workspace_reactive<T>(&self,workspace:&Arc<WorkspaceCapture>,scope:&Arc<WorkspaceQueryScope>,capture:&Arc<CapturedPolicyInputs>,request:Request,consume:impl FnOnce(&Value)->io::Result<T>)->io::Result<T>{
  self.with_workspace_reactive_limit(workspace,scope,capture,request,None,consume)
 }
 fn with_workspace_reactive_limit<T>(&self,workspace:&Arc<WorkspaceCapture>,scope:&Arc<WorkspaceQueryScope>,capture:&Arc<CapturedPolicyInputs>,request:Request,limit:Option<usize>,consume:impl FnOnce(&Value)->io::Result<T>)->io::Result<T>{
  self.with_workspace_job_limit(workspace,scope,capture,request,None,limit,consume)
 }
 fn with_workspace_job_limit<T>(&self,workspace:&Arc<WorkspaceCapture>,scope:&Arc<WorkspaceQueryScope>,capture:&Arc<CapturedPolicyInputs>,request:Request,generator:Option<generator_policy::GeneratorName>,limit:Option<usize>,consume:impl FnOnce(&Value)->io::Result<T>)->io::Result<T>{
  crate::daemon::control::checkpoint()?;scope.with_guard(self,workspace,capture.policy(),|_|Ok(Ok::<(),String>(())))?.map_err(|message|io::Error::new(io::ErrorKind::Unsupported,message))?;let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());self.raw_prune_locked(Instant::now());self.begin_result_admission_locked()?;if let Some(limit)=limit{self.raw_policy.admission.limit.fetch_min(limit,Ordering::AcqRel);}
  let pending=scope.with_guard(self,workspace,capture.policy(),|guard|split(self.with_workspace_code_pages_limit_locked(workspace,guard,limit,|reader|{
   self.with_workspace_job_reader(workspace,scope,capture,request,generator,reader,guard,consume)
  })));
  match pending{Ok(Ok(value))=>Ok(value),Ok(Err(message))=>Err(io::Error::new(io::ErrorKind::Unsupported,message)),Err(actual)=>Err(actual)}
 }
 fn with_workspace_job_reader<T>(&self,workspace:&Arc<WorkspaceCapture>,scope:&Arc<WorkspaceQueryScope>,capture:&Arc<CapturedPolicyInputs>,request:Request,generator:Option<generator_policy::GeneratorName>,reader:&WorkspaceCodeReader<'_,'_>,guard:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,consume:impl FnOnce(&Value)->io::Result<T>)->Result<T,Failure>{
  let produced=(||->Result<T,Failure>{
   reader.require_policy_inputs(capture.policy())?;capture.semantic_source_evidence().check(capture.policy().mapping())?;generator_policy::manifest(capture,reader.root())?;
   let _operation=self.raw_policy.admission.bind_workspace_operation(reader.budget(),scope,workspace,capture)?;let loan=self.raw_policy.admission.current_workspace_operation(workspace.issuance(),capture.semantic_source_evidence().key())?;
   let configuration=configuration_input(self,reader,capture)?;let width=match &request{Request::Read{receiver,procedure,context,..}=>receiver.len().checked_add(procedure.len()).and_then(|n|n.checked_add(context.as_ref().map_or(0,String::len))),_=>Some(0)}.ok_or_else(||{reader.budget().deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"workspace request width overflow"))})?;let bytes=width.checked_add(reader.root().as_os_str().len().checked_mul(4).ok_or_else(||Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"workspace root width overflow")))?).and_then(|n|n.checked_add(reader.configuration().0.as_os_str().len().checked_mul(4)?)).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(std::mem::size_of::<Params>()+4096)).ok_or_else(||{reader.budget().deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"workspace parameter capacity overflow"))})?;reader.budget().charge(bytes)?;
   let mut p=Params{generator,policy:false,key:Key::new(finite::REACTIVE_RESULT,0),issuance:workspace.issuance(),evidence:capture.semantic_source_evidence().key(),locator:loan.locator,configuration,configuration_path:reader.configuration().0.to_owned(),root:reader.root().to_owned(),request};p.key=key_for(&p,&p.request)?;let key=p.key;
   self.raw_policy.admission.admit_child(Arc::downgrade(capture),key,bytes).map_err(finite::graph_failure)?;let p=Arc::new(p);
   let value=self.db.get::<Result<Value,String>>(key,Arc::<Params>::clone(&p)).map_err(|error|if matches!(&error,QueryError::Operational{..}){finite::graph_failure(error)}else if self.raw_policy.admission.denied.load(Ordering::Acquire){Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"workspace reactive family admission exhausted"))}else{finite::graph_failure(error)})?;
   let value=value.as_ref().as_ref().map_err(|message|Failure::Unsupported(message.clone()))?;if !actual(value,&p,&loan,guard)?{return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"warm workspace result failed actual request/source witnesses")))}
   let result=consume(value).map_err(Failure::Operational);if matches!(&result,Err(Failure::Operational(_))){return result}crate::daemon::control::checkpoint()?;reader.budget().require().map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;result
  })();
  if matches!(&produced,Err(Failure::Operational(_))){return produced}
  if reader.budget().denied(){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"generator operation admission exhausted")))}
  produced
 }
 /// The actual snapshot guard enters before any ephemeral query-scope owner is
 /// allocated. Its existing reader mints the one operation Budget first.
 pub(crate) fn with_workspace_generator_guard<T>(&self,workspace:&Arc<WorkspaceCapture>,guard:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,capture:&Arc<CapturedPolicyInputs>,name:generator_policy::GeneratorName,consume:impl FnOnce(&generator_policy::Artifact)->io::Result<T>)->io::Result<T>{
  self.with_workspace_generator_guard_limit(workspace,guard,capture,name,None,consume)
 }
 /// Borrow the actual current operation control for final serialization only.
 /// Temporary buffers must be freed before this callback returns; never cache
 /// the Budget or source scope, or use this control as source authority.
 pub(crate) fn with_workspace_generator_guard_budget<T>(&self,workspace:&Arc<WorkspaceCapture>,guard:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,capture:&Arc<CapturedPolicyInputs>,name:generator_policy::GeneratorName,consume:impl FnOnce(&generator_policy::Artifact,&Arc<Budget>)->io::Result<T>)->io::Result<T>{
  self.with_workspace_generator_guard_limit_budget(workspace,guard,capture,name,None,consume)
 }
 fn with_workspace_generator_guard_limit<T>(&self,workspace:&Arc<WorkspaceCapture>,guard:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,capture:&Arc<CapturedPolicyInputs>,name:generator_policy::GeneratorName,limit:Option<usize>,consume:impl FnOnce(&generator_policy::Artifact)->io::Result<T>)->io::Result<T>{
  self.with_workspace_generator_guard_limit_budget(workspace,guard,capture,name,limit,|artifact,_|consume(artifact))
 }
 fn with_workspace_generator_guard_limit_budget<T>(&self,workspace:&Arc<WorkspaceCapture>,guard:&crate::runner_host::query_snapshot::workspace_native_guard::NativeReadGuard<'_>,capture:&Arc<CapturedPolicyInputs>,name:generator_policy::GeneratorName,limit:Option<usize>,consume:impl FnOnce(&generator_policy::Artifact,&Arc<Budget>)->io::Result<T>)->io::Result<T>{
  use generator_policy::GeneratorName as G;
  if !matches!(name,G::Reads|G::DerivedReads|G::AutoTracked|G::Deps|G::SparseSlots|G::DeclareIds|G::UiTypes|G::Stats|G::Actions|G::SystemAccessors){return Err(io::Error::new(io::ErrorKind::Unsupported,"full original generator is not selected"))}
  crate::daemon::control::checkpoint()?;workspace.require_scope(guard)?;
  if !guard.uses_queries(self){return Err(io::Error::new(io::ErrorKind::InvalidData,"generator guard belongs to another QueryDb"))}
  let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());
  self.raw_prune_locked(Instant::now());self.begin_result_admission_locked()?;if let Some(limit)=limit{self.raw_policy.admission.limit.fetch_min(limit,Ordering::AcqRel);}
  let pending=self.with_workspace_code_pages_limit_locked(workspace,guard,limit,|reader|{
   // query_receipt funds its fixed Weak payloads before downgrade; fund the
   // scope's own Arc coordination before Arc::new. The Arc never escapes.
   reader.budget().charge(2*std::mem::size_of::<usize>()).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
   let scope=guard.query_receipt(&mut|bytes|reader.budget().charge(bytes).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
   let scope=Arc::new(scope);
   let produced=flatten(scope.with_guard(self,workspace,capture.policy(),|current|split(self.with_workspace_job_reader(workspace,&scope,capture,Request::Dependencies,Some(name),reader,current,|value|{let Value::FullArtifact(value)=value else{return Err(io::Error::new(io::ErrorKind::InvalidData,"full generator returned another role"))};consume(value.output(),reader.budget())}))));
   // Actual callback/child IO is first. A known quota refusal must be typed
   // before the reader's final semantic/success cancellation poll.
   if matches!(&produced,Err(Failure::Operational(_))){return produced}
   if reader.budget().denied(){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"generator operation admission exhausted")))}
   produced
  });
  pending.map_err(|failure|match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)})
 }

}

#[cfg(test)]#[path="reactive_workspace_policy_tests.rs"]mod tests;

#[path="reactive_workspace_generators.rs"]mod full_generator;
pub(super) use full_generator::Artifact as FullArtifact;
