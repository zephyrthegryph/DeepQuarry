//! Sealed UI raw input facts and dynamic C2 children in existing Kind7/Kind12.
//! No native semantic scope, source model, secondary cache, or nested raw gate.
use super::*;
use dq_analyze::{captured_ui_actions::{self as ui,Roots,C2Sources,SignatureFile,UiProc},captured_generator_budget::Budget,captured_reactive_reads::Failure,dm::dx::Proc};
use crate::runner_host::{workspace_capture::WorkspaceCapture,query_snapshot::workspace_native_guard::NativeReadGuard};
use std::cell::RefCell;
const RECIPE:&str="original-ui-actions-c2-name-groups-v1";
const BLOCK_FILES:usize=64;
struct Roster{blocks:Vec<Key>}
struct Block{files:Vec<SignatureFile>}
#[derive(Clone)]enum Request{Named(String),Root{root:UiProc,param:String}}
pub(super) struct Params{key:Key,namespace:u128,roster:Key,request:Request}
enum UiValue{Named(Vec<UiProc>),Root(Option<usize>)}
fn actual_io(failure:Failure)->io::Error{match failure{Failure::Operational(actual)=>actual,Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)}}
fn failure(error:QueryError)->Failure{super::reactive_read_policy::graph_failure(error)}
fn budget_error(message:String)->Failure{Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message))}
fn fund(b:&Budget,n:Option<usize>)->Result<usize,Failure>{let n=n.ok_or_else(||{b.deny();budget_error("UI coordination size overflow".into())})?;b.charge(n).map_err(budget_error)?;Ok(n)}
fn own(b:&Budget,text:&str)->Result<String,Failure>{fund(b,text.len().checked_add(64))?;let mut out=String::new();out.try_reserve_exact(text.len()).map_err(|_|budget_error("UI metadata allocation refused".into()))?;out.push_str(text);Ok(out)}
fn row<T>(b:&Budget,rows:&mut Vec<T>)->Result<(),Failure>{checkpoint(b)?;if rows.len()<rows.capacity(){return Ok(())}let capacity=rows.capacity().checked_mul(2).map(|n|n.max(4)).ok_or_else(||budget_error("UI metadata growth overflow".into()))?;fund(b,capacity.checked_mul(std::mem::size_of::<T>()).and_then(|n|n.checked_add(64)))?;rows.try_reserve_exact(capacity-rows.len()).map_err(|_|budget_error("UI metadata growth refused".into()))}
fn checkpoint(b:&Budget)->Result<(),Failure>{crate::daemon::control::checkpoint()?;b.require().map_err(budget_error)}
fn hashed(kind:Kind,value:&impl serde::Serialize)->io::Result<Key>{let k=super::reactive_read_policy::metadata_key(value)?;Ok(Key::new(kind,k.id))}
fn namespace(workspace:&WorkspaceCapture)->io::Result<u128>{if workspace.has_authored_doc_ui_capture(){return Ok(hashed(RAW_FILE,&(RECIPE,"authored-doc-ui",workspace.root(),workspace.configuration().0))?.id)}Ok(hashed(RAW_FILE,&(RECIPE,workspace.root(),workspace.configuration().0))?.id)}
fn roster_key(namespace:u128)->io::Result<Key>{hashed(RAW_FILE,&(RECIPE,"ordered-visible-dm-roster",namespace))}
fn group_key(namespace:u128,name:&str)->io::Result<Key>{hashed(super::reactive_read_policy::REACTIVE_RESULT,&(RECIPE,"helper-name-group",namespace,name))}
fn root_key(namespace:u128,root:&UiProc,param:&str)->io::Result<Key>{hashed(super::reactive_read_policy::REACTIVE_RESULT,&(RECIPE,"root-proc-and-param",namespace,root.hash,param))}
fn metadata(p:&Params)->Option<usize>{let extra=match &p.request{Request::Named(name)=>name.capacity(),Request::Root{root,param}=>root.retained_charge()?.checked_add(param.capacity())?};std::mem::size_of::<Params>().checked_add(extra)?.checked_add(512)}
fn publish<T:Send+Sync+'static>(queries:&QueryDb,workspace:&Arc<WorkspaceCapture>,key:Key,value:T,hash:u128,bytes:usize)->Result<(),Failure>{queries.raw_policy.admission.admit_ui(Arc::downgrade(workspace),key,bytes).map_err(failure)?;queries.db.set_input(key,value,hash);Ok(())}
/// Request-local coordinator only; reusable values live solely in existing Db.
pub(in crate::query_db) fn bind<'a>(queries:&'a QueryDb,b:&Arc<Budget>,workspace:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,proof:&Arc<super::workspace::UiInputProof>)->io::Result<super::reactive_workspace_operation::Guard<'a>>{queries.raw_policy.admission.bind_ui_operation(scope.queries_owner(),b,workspace,scope,proof)}
pub(in crate::query_db) struct Session<'a,'scope>{queries:&'a QueryDb,workspace:&'a Arc<WorkspaceCapture>,scope:&'a NativeReadGuard<'scope>,namespace:u128,roster:Key,ready:bool,proof:Arc<super::workspace::UiInputProof>}
impl<'a,'scope> Session<'a,'scope>{pub(in crate::query_db) fn new(queries:&'a QueryDb,workspace:&'a Arc<WorkspaceCapture>,scope:&'a NativeReadGuard<'scope>,proof:Arc<super::workspace::UiInputProof>)->Result<Self,Failure>{workspace.require_scope(scope)?;if !scope.uses_queries(queries){return Err("UI session has another actual QueryDb".into())}if !workspace.has_authored_doc_ui_capture(){scope.ui_raw_operation_owner(workspace)?;}proof.require_owner(workspace)?;let namespace=namespace(workspace)?;Ok(Self{queries,workspace,scope,namespace,roster:roster_key(namespace)?,ready:false,proof})}}
impl Roots for Session<'_,'_>{
 fn sources(&mut self,files:Vec<SignatureFile>,b:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<(),Failure>{
  if self.ready{return Err("UI facts roster was published twice".into())}self.proof.require(self.workspace)?;poll()?;self.workspace.require_scope(self.scope)?;
  let mut remaining=files.into_iter();let mut keys=Vec::new();let mut ordinal=0usize;
  loop{checkpoint(b)?;let mut chunk=Vec::new();fund(b,BLOCK_FILES.checked_mul(std::mem::size_of::<SignatureFile>()).and_then(|n|n.checked_add(128)))?;chunk.try_reserve_exact(BLOCK_FILES).map_err(|_|budget_error("UI block allocation refused".into()))?;for _ in 0..BLOCK_FILES{let Some(file)=remaining.next()else{break};chunk.push(file)}if chunk.is_empty(){break}
   let key=hashed(RAW_FILE,&(RECIPE,"ordered-current-file-name-block",self.namespace,ordinal))?;let mut bytes=std::mem::size_of::<Block>().checked_add(chunk.capacity().checked_mul(std::mem::size_of::<SignatureFile>()).ok_or_else(||budget_error("UI block capacity overflow".into()))?).ok_or_else(||budget_error("UI block size overflow".into()))?;for file in &chunk{checkpoint(b)?;bytes=bytes.checked_add(file.retained_charge().ok_or_else(||budget_error("UI file facts size overflow".into()))?).ok_or_else(||budget_error("UI block facts overflow".into()))?;}
   let hash=hashed(RAW_FILE,&(RECIPE,"current-name-facts",&chunk))?.id;publish(self.queries,self.workspace,key,Block{files:chunk},hash,bytes.checked_add(1024).ok_or_else(||budget_error("UI block lease overflow".into()))?)?;row(b,&mut keys)?;keys.push(key);ordinal+=1;
  }
  fund(b,keys.capacity().checked_mul(std::mem::size_of::<Key>()).and_then(|n|n.checked_add(std::mem::size_of::<Roster>()+128)))?;let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(RECIPE.as_bytes());for key in &keys{checkpoint(b)?;hash.update(&key.id.to_le_bytes())}let bytes=keys.capacity().checked_mul(std::mem::size_of::<Key>()).and_then(|n|n.checked_add(std::mem::size_of::<Roster>()+1024)).ok_or_else(||budget_error("UI roster retained size overflow".into()))?;publish(self.queries,self.workspace,self.roster,Roster{blocks:keys},hash.digest128(),bytes)?;self.proof.mark_published(self.workspace)?;self.ready=true;poll()?;Ok(())
 }
 fn bad_offset(&mut self,root:&UiProc,param:&str,b:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<Option<usize>,Failure>{
  if !self.ready{return Err("UI root asked before complete productive facts".into())}self.proof.require(self.workspace)?;poll()?;self.workspace.require_scope(self.scope)?;let rebound=current_proc(&self.queries.db,self.roster,root,b)?;if rebound.proc!=root.proc||rebound.hash!=root.hash{return Err("UI root differs from actual current source/header geometry".into())}
  let key=root_key(self.namespace,root,param)?;let bound=root.retained_charge().and_then(|n|n.checked_add(param.len())).and_then(|n|n.checked_add(std::mem::size_of::<Params>()+256));let bytes=fund(b,bound)?;let params=Params{key,namespace:self.namespace,roster:self.roster,request:Request::Root{root:rebound,param:own(b,param)?}};self.queries.raw_policy.admission.admit_ui(Arc::downgrade(self.workspace),key,bytes).map_err(failure)?;
  let value=self.queries.db.get::<Result<UiValue,String>>(key,Arc::new(params)).map_err(failure)?;poll()?;self.workspace.require_scope(self.scope)?;let current=current_proc(&self.queries.db,self.roster,root,b)?;if current.proc!=root.proc||current.hash!=root.hash{return Err("UI root current source changed before delivery".into())}match value.as_ref(){Ok(UiValue::Root(offset))=>Ok(*offset),Ok(_)=>Err("UI root received helper payload".into()),Err(message)=>Err(Failure::Unsupported(own(b,message)?))}
 }
}
fn matches(candidate:&UiProc,old:&UiProc)->bool{candidate.proc.rel==old.proc.rel&&candidate.proc.path==old.proc.path&&candidate.proc.name==old.proc.name&&candidate.proc.params==old.proc.params&&candidate.hash==old.hash}
fn current_proc(db:&Db,roster:Key,old:&UiProc,budget:&Arc<Budget>)->Result<UiProc,Failure>{let roster=db.input::<Roster>(roster).ok_or("UI actual facts roster expired")?;let mut fallback=None;for key in &roster.blocks{crate::daemon::control::checkpoint()?;let block=db.input::<Block>(*key).ok_or("UI current facts block expired")?;for file in &block.files{checkpoint(budget)?;if file.relative!=old.proc.rel{continue}for p in &file.procs{checkpoint(budget)?;if matches(p,old){if p.proc==old.proc{return ui::copy_proc(p,budget,&crate::daemon::control::checkpoint)}if fallback.is_none(){fallback=Some(ui::copy_proc(p,budget,&crate::daemon::control::checkpoint)?)}}}}}fallback.ok_or_else(||"UI cached helper has no actual current header/body identity".into())}
fn group_hash(values:&[UiProc])->io::Result<u128>{// Coordinates/ordinals are rebound, not semantic cache identity.
 let mut h=xxhash_rust::xxh3::Xxh3::new();h.update(RECIPE.as_bytes());for v in values{crate::daemon::control::checkpoint()?;let stable=(&v.proc.rel,&v.proc.path,&v.proc.name,&v.proc.params,v.hash);h.update(&hashed(RAW_FILE,&stable)?.id.to_le_bytes());}Ok(h.digest128())}
fn get_group(ctx:&RefCell<&mut dm_query::Ctx<'_>>,p:&Params,name:&str,loan:&super::reactive_workspace_operation::UiLoan,admission:&Admission)->Result<Vec<UiProc>,Failure>{
 let key=group_key(p.namespace,name)?;fund(&loan.budget,name.len().checked_add(std::mem::size_of::<Params>()+256))?;let child=Params{key,namespace:p.namespace,roster:p.roster,request:Request::Named(own(&loan.budget,name)?)};admission.admit_ui(Arc::downgrade(&loan.workspace),key,metadata(&child).ok_or_else(||budget_error("UI helper metadata overflow".into()))?).map_err(failure)?;
 // SAME budget already funds every allocation. with_child delta transfer would
 // double-charge shared operation allocations; use the existing direct ctx.get.
 let value=ctx.borrow_mut().get::<Result<UiValue,String>>(key,Arc::new(child)).map_err(failure)?;let Ok(UiValue::Named(values))=value.as_ref()else{return match value.as_ref(){Err(message)=>Err(Failure::Unsupported(own(&loan.budget,message)?)),_=>Err("UI helper received root payload".into())}};let mut out=Vec::new();for old in values{checkpoint(&loan.budget)?;let current=current_proc(&loan.queries.db,p.roster,old,&loan.budget)?;row(&loan.budget,&mut out)?;out.push(current)}Ok(out)
}
struct Sources<'a,'ctx>{ctx:RefCell<&'a mut dm_query::Ctx<'ctx>>,params:&'a Params,loan:&'a super::reactive_workspace_operation::UiLoan,admission:&'a Admission}
impl C2Sources for Sources<'_,'_>{
 fn named(&self,name:&str,_:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<Vec<UiProc>,Failure>{poll()?;get_group(&self.ctx,self.params,name,self.loan,self.admission)}
 fn lines(&self,proc:&Proc,b:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,visit:&mut dyn FnMut(usize,&str)->Result<bool,Failure>)->Result<(),Failure>{
  poll()?;let roster=self.loan.queries.db.input::<Roster>(self.params.roster).ok_or("UI current body roster missing")?;let mut actual=None;for key in &roster.blocks{checkpoint(b)?;let block=self.loan.queries.db.input::<Block>(*key).ok_or("UI current body facts missing")?;for file in &block.files{checkpoint(b)?;if file.relative!=proc.rel{continue}for p in &file.procs{checkpoint(b)?;if p.proc==*proc{actual=Some(ui::copy_proc(p,b,&crate::daemon::control::checkpoint)?);break}}}}let actual=actual.ok_or("UI body geometry is not current issued metadata")?;
  self.loan.with_guard(|guard|self.loan.queries.with_workspace_code_pages_budget_locked(&self.loan.workspace,guard,b,|reader|reader.with_ui_proc_lines(&actual,visit)))?;poll()?;Ok(())
 }
}
pub(super) fn compute(ctx:&mut dm_query::Ctx<'_>,p:&Params,charge:&AtomicUsize,admission:&Admission)->Result<Outcome,QueryError>{
 admission.abort.before_outcome(p.key)?;let loan=admission.current_ui_operation().map_err(|actual|QueryError::operational(p.key,actual))?;let io=|f:Failure|QueryError::operational(p.key,actual_io(f));
 if namespace(&loan.workspace).map_err(|e|QueryError::operational(p.key,e))?!=p.namespace||roster_key(p.namespace).map_err(|e|QueryError::operational(p.key,e))?!=p.roster{return Err(QueryError::operational(p.key,io::Error::new(io::ErrorKind::InvalidData,"UI child namespace differs from current raw recipe")))}
 let budget=&loan.budget;checkpoint(budget).map_err(io)?;
 let pending=(||->Result<UiValue,Failure>{match &p.request{Request::Named(name)=>{let roster=ctx.input::<Roster>(p.roster).map_err(failure)?;let mut selected=Vec::new();for key in &roster.blocks{checkpoint(budget)?;let block=ctx.input::<Block>(*key).map_err(failure)?;for file in &block.files{for proc in &file.procs{checkpoint(budget)?;if proc.proc.name==*name{row(budget,&mut selected)?;selected.push(ui::copy_proc(proc,budget,&crate::daemon::control::checkpoint)?)}}}}Ok(UiValue::Named(selected))},Request::Root{root,param}=>{let current=current_proc(&loan.queries.db,p.roster,root,budget)?;let source=Sources{ctx:RefCell::new(ctx),params:p,loan:&loan,admission};Ok(UiValue::Root(ui::first_bad_offset(&source,&current,param,budget,&crate::daemon::control::checkpoint)?))}}})();
 let value=match pending{Ok(value)=>Ok(value),Err(Failure::Operational(actual))=>return Err(QueryError::operational(p.key,actual)),Err(Failure::Unsupported(message))=>Err(message)};
 let(bytes,hash)=match &value{Ok(UiValue::Root(offset))=>(std::mem::size_of::<Result<UiValue,String>>()+2*std::mem::size_of::<usize>(),hashed(super::reactive_read_policy::REACTIVE_RESULT,&(RECIPE,"root-answer",offset)).map_err(|e|QueryError::operational(p.key,e))?.id),Ok(UiValue::Named(group))=>{let fixed=group.capacity().checked_mul(std::mem::size_of::<UiProc>()).and_then(|n|n.checked_add(std::mem::size_of::<Result<UiValue,String>>()+2*std::mem::size_of::<usize>())).ok_or_else(||QueryError::operational(p.key,io::Error::new(io::ErrorKind::OutOfMemory,"UI group fixed size overflow")))?;let bytes=group.iter().try_fold(fixed,|n,p|n.checked_add(p.retained_charge()?)).ok_or_else(||QueryError::operational(p.key,io::Error::new(io::ErrorKind::OutOfMemory,"UI group retained charge overflow")))?;(bytes,group_hash(group).map_err(|e|QueryError::operational(p.key,e))?)},Err(message)=>(result_error_charge::<UiValue>(message),error_hash(message))};
 retain_derived(charge,bytes,admission,p.key)?;admission.abort.before_outcome(p.key)?;checkpoint(budget).map_err(io)?;Ok(Outcome::new(value,hash,bytes))
}

#[cfg(test)]impl QueryDb{
 /// Test-only passage of time through the actual existing pruner, not eviction
 /// by a new path or result/source authority. Test QueryDb is exclusively owned.
 pub(crate) fn ui_actions_test_age_cache(&self){let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());self.raw_prune_locked(Instant::now()+MAX_AGE+Duration::from_secs(1));}
}
#[cfg(test)]mod lease_tests{
 use super::*;
 #[test]fn ui_expired_weak_data_is_charged_until_real_eviction_and_never_grants_operation(){
  let db=QueryDb::default();let key=hashed(RAW_FILE,&(RECIPE,"weak-metadata-control")).unwrap();db.raw_policy.admission.admit_ui(Weak::new(),key,1024).unwrap();db.db.set_input(key,Roster{blocks:Vec::new()},1);let now=Instant::now();db.raw_prune_locked(now);assert!(db.db.input::<Roster>(key).is_some());assert!(db.raw_policy.admission.leases.lock().unwrap().get(&key).unwrap().bytes>=1024);assert!(db.raw_policy.admission.current_ui_operation().is_err(),"weak metadata is never a source or operation grant");db.raw_prune_locked(now+MAX_AGE+Duration::from_secs(1));assert!(db.db.input::<Roster>(key).is_none());assert!(db.raw_policy.admission.leases.lock().unwrap().is_empty());assert!(LeaseOwner::Semantic(Weak::new()).expires_without_owner());assert!(!LeaseOwner::UiRaw(Weak::new()).expires_without_owner());
 }
}

#[cfg(test)]impl QueryDb{
 pub(crate) fn ui_actions_test_age_while_bound(&self)->(usize,usize,usize,usize){
  // Called only from actual with_native_raw_tree delivery while its raw gate
  // and UiRaw guard are live. Do not enter that gate for a second time.
  self.raw_policy.admission.current_ui_operation().expect("actual issued UI operation");let before=self.raw_policy.admission.leases.lock().unwrap().len();let charge=self.raw_policy.charge.load(Ordering::Acquire);self.raw_prune_locked(Instant::now()+MAX_AGE+Duration::from_secs(1));(before,self.raw_policy.admission.leases.lock().unwrap().len(),charge,self.raw_policy.charge.load(Ordering::Acquire))
 }
}

#[cfg(test)]mod same_kind_dispatch_tests{
 use super::*;
 #[test]fn actual_ui_params_dispatch_to_ui_owner_refusal_without_semantic_param_panic_or_cached_success(){let db=QueryDb::default();let namespace=0x12f0_0001;let key=group_key(namespace,"absent-current-owner").unwrap();let roster=roster_key(namespace).unwrap();let params=Params{key,namespace,roster,request:Request::Named("absent-current-owner".into())};let error=match db.db.get::<Result<UiValue,String>>(key,Arc::new(params)){Err(error)=>error,Ok(_)=>panic!("UI facts without the actual raw operation cannot succeed")};let QueryError::Operational{key:actual,error}=error else{panic!("UI payload must reach its real typed owner gate")};assert_eq!(actual,key);let actual=error.into_io();assert_eq!(actual.kind(),io::ErrorKind::InvalidInput);assert!(actual.to_string().contains("UI child has no current sealed raw operation"));assert!(db.db.retained_value::<Result<UiValue,String>>(key).is_none());assert!(db.db.dependants(&[roster]).is_empty(),"owner refusal occurs before any raw facts input read");assert!(db.raw_policy.admission.current_ui_operation().is_err());}
}
