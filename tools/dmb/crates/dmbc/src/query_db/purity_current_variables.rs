//! First real semantic consumer of the canonical current BODY, in the EXISTING
//! compiler Db + purity ledger. Not a default complete-checker cutover.
//! Parent owns source-neutral rows. Lookup leaves alone observe the actual
//! current model input, so unchanged lookup answers cut off semantic work.
use super::*;
use dm_analysis::checks_undefined_variable::{self as variables,CurrentUndefinedProduct,CurrentUndefinedDisposition,CurrentUndefinedRow};
use dm_tree::frontend::{BodyCodeIdentity,BodySyntaxFailure};
use std::io;
pub(super) const CURRENT_VARIABLES:Kind=Kind(28);
pub(super) const CURRENT_LOOKUP:Kind=Kind(29);
const CURRENT_MODEL:Kind=Kind(30);
struct Driver{input:Weak<EffectInput>}
struct CurrentParams{key:Key,driver:Key,input:Weak<EffectInput>,code:Weak<BodyCodeIdentity>,caller:dm_ir::ProcedureIdentity,syntax_charge:Arc<dm_syntax::SettingChargeCounter>,old_edges:usize,dependencies:std::sync::atomic::AtomicUsize}
struct LookupParams{key:Key,driver:Key,caller:dm_ir::ProcedureIdentity,code:Weak<BodyCodeIdentity>,query:ResolveQuery}
fn invalid(message:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidData,message)}
fn unsupported(message:&'static str)->io::Error{io::Error::new(io::ErrorKind::Unsupported,message)}
fn oom(message:&'static str)->io::Error{io::Error::new(io::ErrorKind::OutOfMemory,message)}
fn failure(error:dm_analysis::policy_body_demand::PolicyFailure)->io::Error{match error{dm_analysis::policy_body_demand::PolicyFailure::Operational(actual)=>actual,dm_analysis::policy_body_demand::PolicyFailure::Unsupported(actual)=>io::Error::new(io::ErrorKind::Unsupported,actual.0)}}
fn syntax_io(error:BodySyntaxFailure)->io::Error{match error{BodySyntaxFailure::Operational(actual)=>actual,BodySyntaxFailure::Syntax(actual)=>io::Error::new(io::ErrorKind::Unsupported,actual.message)}}
fn product_key(code:&Arc<BodyCodeIdentity>,caller:dm_ir::ProcedureIdentity,profile:dm_ir::PackedU128)->Key{let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"current-original-body-v2\0");hash.update(&(Arc::as_ptr(code)as usize).to_le_bytes());hash.update(&caller.owner.bits().to_le_bytes());hash.update(&caller.name.bits().to_le_bytes());hash.update(&[caller.verb as u8]);hash.update(&caller.occurrence.to_le_bytes());hash.update(&profile.to_le_bytes());Key::new(CURRENT_VARIABLES,hash.digest128())}
fn lookup_key(parent:Key,query:ResolveQuery)->Key{let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(&parent.id.to_le_bytes());hash.update(&query_id(&query).to_le_bytes());Key::new(CURRENT_LOOKUP,hash.digest128())}
fn code_from_lease(key:Key,lease:&NodeLease)->Option<Weak<BodyCodeIdentity>>{let params=lease.params.as_ref()?.upgrade()?;if key.kind==CURRENT_VARIABLES{Some(params.downcast_ref::<CurrentParams>()?.code.clone())}else if key.kind==CURRENT_LOOKUP{Some(params.downcast_ref::<LookupParams>()?.code.clone())}else{None}}
pub(super) fn is_current_node(key:Key)->bool{key.kind==CURRENT_VARIABLES||key.kind==CURRENT_LOOKUP}
pub(super) fn retains(key:Key,lease:&NodeLease,db:&Db,current_driver:Option<Key>)->bool{
 let Some(params)=lease.params.as_ref().and_then(Weak::upgrade)else{return false};let(driver,caller,code)=if key.kind==CURRENT_VARIABLES{let Some(params)=params.downcast_ref::<CurrentParams>()else{return false};(params.driver,params.caller,&params.code)}else if key.kind==CURRENT_LOOKUP{let Some(params)=params.downcast_ref::<LookupParams>()else{return false};(params.driver,params.caller,&params.code)}else{return false};
 // Before a new driver is authenticated, the previous request input may
 // already be gone even though the canonical code and its answer are live.
 // Only the newly selected profile can prove exact archive membership.
 if current_driver != Some(driver) { return code.strong_count() > 0; }
 // Resource membership only. The actual private scoped entry selected this
 // existing driver; old escaped archives/CodeIDs cannot select themselves.
 let Some(driver)=db.input::<Driver>(driver)else{return false};let Some(input)=driver.input.upgrade()else{return false};let Some(ordinal)=input.archive().callables().ordinal_for_identity(caller)else{return false};input.archive().syntax_inputs().and_then(|rows|rows.get(ordinal)).and_then(|syntax|syntax.original_code_owner()).is_some_and(|actual|Weak::ptr_eq(code,&Arc::downgrade(actual)))
}
// This weak allocation lease prevents pointer ABA without retaining an old
// model/source/AST. Only the actual current published archive keeps code live.
fn reserve_node(ledger:&Arc<Mutex<Ledger>>,input:&Arc<EffectInput>,key:Key,code:Option<&Weak<BodyCodeIdentity>>,bytes:usize)->io::Result<ParamReservation>{
 crate::daemon::control::checkpoint()?;let mut ledger_guard=ledger.lock().unwrap_or_else(|e|e.into_inner());
 if let Some(old)=ledger_guard.nodes.get(&key){if let Some(code)=code{if let Some(prior)=code_from_lease(key,old){if !Weak::ptr_eq(&prior,code){return Err(invalid("current semantic code-key collision"))}}else if old.params.as_ref().is_some_and(|old|old.strong_count()>0)||!old.input.ptr_eq(&Arc::downgrade(input)){return Err(invalid("current semantic existing node lacks its actual code lease"))}}ledger_guard.admit(bytes).map_err(|_|oom("current semantic Params admission refused"))?;ledger_guard.update_node(&key,|old|{old.input=Arc::downgrade(input);old.param_reserved=old.param_reserved.checked_add(bytes).ok_or_else(||oom("current semantic parameter overlap overflow"))?;Ok::<(),io::Error>(())}).unwrap()?;return Ok(ParamReservation{ledger:ledger.clone(),key,bytes})}
 if ledger_guard.nodes.len()>=MAX_NODES{return Err(oom("current semantic existing ledger node bound exhausted"))}ledger_guard.admit(NODE_BOUND.checked_add(bytes).ok_or_else(||oom("current semantic node bound overflow"))?).map_err(|_|oom("current semantic node admission refused"))?;ledger_guard.insert_node(key,NodeLease{input:Arc::downgrade(input),params:None,param_size:bytes,param_reserved:0,observed_edges:0});Ok(ParamReservation{ledger:ledger.clone(),key,bytes:0})
}
struct SharedWork<'a>(&'a Mutex<graph_work::GraphWork>);
impl dm_analysis::checker_effects::EffectReportWork for SharedWork<'_>{type Mark=graph_work::ReportScopeMark;fn reserve(&mut self,bytes:usize)->io::Result<()>{self.0.lock().unwrap_or_else(|e|e.into_inner()).reserve(bytes)}fn mark(&mut self)->io::Result<Self::Mark>{dm_analysis::checker_effects::EffectReportWork::mark(&mut*self.0.lock().unwrap_or_else(|e|e.into_inner()))}fn reconcile(&mut self,mark:Self::Mark,bytes:usize)->io::Result<()>{dm_analysis::checker_effects::EffectReportWork::reconcile(&mut*self.0.lock().unwrap_or_else(|e|e.into_inner()),mark,bytes)}}
impl dm_ir::CanonicalWork for SharedWork<'_>{fn poll(&mut self)->io::Result<()>{crate::daemon::control::checkpoint()}fn reserve(&mut self,bytes:usize)->io::Result<()>{self.0.lock().unwrap_or_else(|e|e.into_inner()).reserve(bytes)}}
impl dm_ir::CanonicalWork for graph_work::GraphWork{fn poll(&mut self)->io::Result<()>{crate::daemon::control::checkpoint()}fn reserve(&mut self,bytes:usize)->io::Result<()>{graph_work::GraphWork::reserve(self,bytes)}}
// One selected contribution in the EXISTING Kind28 node, not per-family caches.
pub(crate) struct CurrentContribution{variables:CurrentUndefinedProduct,settings:dm_analysis::checks_directive_binding::CurrentSettingPrelude}
impl CurrentContribution{
 fn visit_storage(&self,mut visit:impl FnMut(Storage)){self.variables.visit_storage(&mut visit);self.settings.visit_storage(&mut visit);}
 fn retained_charge(&self)->Option<usize>{self.variables.retained_charge()?.checked_add(self.settings.retained_charge()?).and_then(|n|n.checked_add(std::mem::size_of::<Self>()))}
 fn fingerprint_parts(&self,mut part:impl FnMut(&[u8])){part(b"current-selected-contribution-v2");self.settings.fingerprint_parts(&mut part);self.variables.fingerprint_parts(&mut part);}
}
pub(crate) enum CurrentSelectedDiagnostic<'a>{Prelude(&'a dm_analysis::checks::Diagnostic),Body(CurrentUndefinedRow<'a>)}
pub(crate) struct NativeCurrentVariables{product:CurrentContribution,lease:graph_work::GraphLease}
impl NativeCurrentVariables{pub(super) fn visit_storage(&self,visit:&mut impl FnMut(Storage)){self.product.visit_storage(visit)}fn charge(&self)->Option<usize>{self.product.retained_charge()?.checked_add(std::mem::size_of::<Self>())}}
impl graph_work::RetainedHandle for NativeCurrentVariables{type Data=CurrentContribution;fn coordination_charge()->usize{std::mem::size_of::<Self>()}fn issue(product:Self::Data,ledger:Arc<Mutex<Ledger>>,completion:Arc<std::sync::atomic::AtomicBool>)->Arc<Self>{Arc::new(Self{product,lease:graph_work::GraphLease::new(ledger, completion)})}fn retained_charge(&self)->Option<usize>{self.charge()}fn fingerprint(&self,_:Key)->u128{let mut hash=xxhash_rust::xxh3::Xxh3::new();self.product.fingerprint_parts(|bytes|hash.update(bytes));hash.digest128()}}
// The actual native resolver/sole canonical encoder funds demanded container
// and byte growth before allocation. No source-wide metadata estimate remains.
// Scalar answer hashes stream directly; declaration chains use one funded
// SAME native canonical byte buffer, with no nested child Vecs or copied AST.
// Member fingerprint is issued by the actual native resolver from all metadata.
fn meaning_hash(answer:&ResolvedMeaning,work:&mut dyn dm_ir::CanonicalWork)->io::Result<u128>{work.poll()?;use dm_ir::ResolvedMeaning as M;let mut hash=xxhash_rust::xxh3::Xxh3::new();match answer{M::Members(rows)=>{for row in rows.iter(){crate::daemon::control::checkpoint()?;if !matches!(row,M::Declaration{..}){return Err(unsupported("current callable actual chain contains an unqualified answer"))}}return Ok(dm_query::hash_bytes(&answer.canonical_bytes_using(work)?))},M::Unsupported(query)if matches!(query,ResolveQuery::Type(_))=>{hash.update(&[4]);hash.update(&query_id(query).to_le_bytes())},M::Missing=>hash.update(&[0]),M::Presence(present)=>hash.update(&[5, u8::from(*present)]),M::Symbol(symbol)=>{hash.update(&[1]);hash.update(&symbol.bits().to_le_bytes())},M::Symbols(rows)=>{hash.update(&[2]);hash.update(&(rows.len()as u64).to_le_bytes());for row in rows.iter(){crate::daemon::control::checkpoint()?;hash.update(&row.bits().to_le_bytes())}},M::Member{owner,name,fingerprint,..}=>{hash.update(&[3]);hash.update(&owner.bits().to_le_bytes());hash.update(&name.bits().to_le_bytes());hash.update(&fingerprint.to_le_bytes())},_=>return Err(unsupported("actual native current variable answer is not a qualified structural shape"))}Ok(hash.digest128())}
// Source-free CodeID owners guard pointer ABA only. Actual current roster
// membership below remains authoritative, even if an old source archive lives.
pub(super) struct CurrentLookupData{hash:u128,codes:Vec<Arc<BodyCodeIdentity>>}
impl CurrentLookupData{
 fn charge(&self)->Option<usize>{self.codes.capacity().checked_mul(std::mem::size_of::<Arc<BodyCodeIdentity>>()).and_then(|n|n.checked_add(self.codes.len().checked_mul(std::mem::size_of::<BodyCodeIdentity>()+128)?)).and_then(|n|n.checked_add(std::mem::size_of::<Self>()))}
}
pub(super) struct NativeCurrentLookup{data:CurrentLookupData,lease:graph_work::GraphLease}
impl NativeCurrentLookup{
 pub(super) fn visit_storage(&self,visit:&mut impl FnMut(Storage)){visit(Storage::Buffer{owner:"current_lookup.completion",address:Arc::as_ptr(&self.lease.completion)as usize,logical:std::mem::size_of::<std::sync::atomic::AtomicBool>(),capacity:std::mem::size_of::<std::sync::atomic::AtomicBool>()});visit(Storage::Buffer{owner:"current_lookup.value",address:self as *const Self as usize,logical:std::mem::size_of::<Self>(),capacity:std::mem::size_of::<Self>()});visit(Storage::Buffer{owner:"current_lookup.code_locators",address:self.data.codes.as_ptr()as usize,logical:self.data.codes.len()*std::mem::size_of::<Arc<BodyCodeIdentity>>(),capacity:self.data.codes.capacity()*std::mem::size_of::<Arc<BodyCodeIdentity>>()});for code in &self.data.codes{visit(Storage::Buffer{owner:"current_lookup.code_identity",address:Arc::as_ptr(code)as usize,logical:std::mem::size_of::<BodyCodeIdentity>(),capacity:std::mem::size_of::<BodyCodeIdentity>()});}}
}
impl graph_work::RetainedHandle for NativeCurrentLookup{type Data=CurrentLookupData;fn coordination_charge()->usize{std::mem::size_of::<Self>()+128}fn issue(data:Self::Data,ledger:Arc<Mutex<Ledger>>,completion:Arc<std::sync::atomic::AtomicBool>)->Arc<Self>{Arc::new(Self{data,lease:graph_work::GraphLease::new(ledger, completion)})}fn retained_charge(&self)->Option<usize>{self.data.charge()?.checked_add(std::mem::size_of::<Self>()+128)}fn fingerprint(&self,_:Key)->u128{self.data.hash}}
fn retain_actual_code(codes:&mut Vec<Arc<BodyCodeIdentity>>,code:&Arc<BodyCodeIdentity>,work:&mut dyn dm_ir::CanonicalWork)->io::Result<()>{
 work.poll()?;if codes.len()==codes.capacity(){let capacity=codes.len().checked_add(1).and_then(usize::checked_next_power_of_two).ok_or_else(||oom("actual callee code locator capacity overflow"))?;let bound=capacity.checked_mul(4).ok_or_else(||oom("actual callee code locator allocation bound overflow"))?;work.reserve(bound.checked_mul(std::mem::size_of::<Arc<BodyCodeIdentity>>()).and_then(|n|n.checked_add(128)).ok_or_else(||oom("actual callee code locator allocation geometry overflow"))?)?;codes.try_reserve_exact(capacity-codes.len()).map_err(|e|io::Error::new(io::ErrorKind::OutOfMemory,e))?;if codes.capacity()>bound{return Err(oom("actual callee code locator allocator exposed excess capacity"))}}
 // This funds the tiny issued object's retained coordination before extending
 // its lifetime. Private Arc allocator layout is not an exposed-capacity claim.
 work.reserve(std::mem::size_of::<BodyCodeIdentity>()+128)?;codes.push(Arc::clone(code));Ok(())
}
// This EXISTING SourceVarDeclaration leaf owns both its native metadata answer
// and the exact selected formal's actual Original property byte. The byte is
// read from the archive producer, never inferred from its header or native flags.
pub(super) fn current_answer_hash(input:&EffectInput,query:ResolveQuery,answer:&ResolvedMeaning,work:&mut dyn dm_ir::CanonicalWork,mut retain:Option<&mut Vec<Arc<BodyCodeIdentity>>>)->io::Result<u128>{
 let native=meaning_hash(answer,work)?;
 if matches!(query,ResolveQuery::SourceDeclarationChain{..}){
  let ResolvedMeaning::Members(rows)=answer else{return Ok(native)};let archive=input.archive();let inputs=archive.syntax_inputs().ok_or_else(||unsupported("actual current source callable inputs are unissued"))?;
  let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"current-native-source-chain-and-current-code-choice-v1\0");hash.update(&native.to_le_bytes());hash.update(&(rows.len()as u64).to_le_bytes());
  for row in rows.iter(){work.poll()?;let ResolvedMeaning::Declaration{identity,..}=row else{return Err(invalid("actual current source callable chain row is not a declaration"))};let ordinal=archive.callables().ordinal_for_identity_using(*identity,&mut||work.poll())?.ok_or_else(||unsupported("actual source callable has no current archive membership"))?;let code=inputs.get(ordinal).and_then(|input|input.original_code_owner()).ok_or_else(||unsupported("actual source callable code choice has not been issued"))?;
   hash.update(&identity.owner.bits().to_le_bytes());hash.update(&identity.name.bits().to_le_bytes());hash.update(&[identity.verb as u8]);hash.update(&identity.occurrence.to_le_bytes());hash.update(&(Arc::as_ptr(code)as usize).to_le_bytes());if let Some(codes)=&mut retain{retain_actual_code(codes,code,work)?;}
  }return Ok(hash.digest128())
 }
 let ResolveQuery::SourceVarDeclaration{..}=query else{return Ok(native)};
 let ResolvedMeaning::Member{owner,name,data,..}=answer else{return Ok(native)};
 let archive=input.archive();let tree=archive.tree();work.poll()?;
 let formal=tree.source_formal_variable_member(*owner,*name).map_err(unsupported)?.ok_or_else(||invalid("current source-property answer lacks its actual formal"))?;
 if !Arc::ptr_eq(&tree.member(formal).ok_or_else(||invalid("current source-property formal vanished"))?.metadata,data){return Err(invalid("current source-property selected metadata differs from actual formal"))}
 let flags=archive.checker_variable_qualifiers_admitted(formal,input.profile())?;work.poll()?;
 let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"current-native-source-var-and-original-qualifiers-v1\0");hash.update(&native.to_le_bytes());hash.update(&owner.bits().to_le_bytes());hash.update(&name.bits().to_le_bytes());hash.update(&[flags]);Ok(hash.digest128())
}
struct Recording<'a,'loan,'ctx>{ctx:&'a Mutex<&'loan mut dm_query::Ctx<'ctx>>,input:&'a Arc<EffectInput>,params:&'a CurrentParams,ledger:Arc<Mutex<Ledger>>,work:&'a Mutex<graph_work::GraphWork>,admission:&'a ExecutionAdmission,error:Mutex<Option<QueryError>>}
impl Recording<'_,'_,'_>{fn finish(&self)->Result<(),QueryError>{self.error.lock().unwrap_or_else(|e|e.into_inner()).take().map_or(Ok(()),Err)}fn latch(&self,error:QueryError){let mut first=self.error.lock().unwrap_or_else(|e|e.into_inner());if first.is_none(){*first=Some(error)}}}
impl Resolver for Recording<'_,'_,'_>{fn source_owner(&self)->Option<*const ()>{Resolver::source_owner(self.input.archive().tree())}fn resolve(&self,query:ResolveQuery)->ResolvedMeaning{
 let key=lookup_key(self.params.key,query);let result=(||{
  let _reservation=reserve_node(&self.ledger,self.input,key,Some(&self.params.code),std::mem::size_of::<LookupParams>()).map_err(|actual|QueryError::operational(key,actual))?;
  let params=Arc::new(LookupParams{key,driver:self.params.driver,caller:self.params.caller,code:self.params.code.clone(),query});remember_params(&self.ledger,self.input,key,&params);let mut context=self.ctx.lock().unwrap_or_else(|e|e.into_inner());if !context.has_dependency(key){pages::reserve_actual_dependency(&self.ledger,self.params.key,self.params.old_edges,context.dependency_count()+1,self.admission,self.admission.available()).map_err(|actual|QueryError::operational(key,actual))?;}let proof=context.get::<Result<Arc<NativeCurrentLookup>,String>>(key,params)?;let proof=proof.as_ref().as_ref().map_err(|message|QueryError::operational(key,io::Error::other(message.clone())))?;
  let mut encoding=SharedWork(self.work);let answer=self.input.archive().tree().resolve_with_canonical_work(query,&mut encoding).map_err(|actual|QueryError::operational(key,actual))?;let actual=current_answer_hash(self.input.as_ref(),query,&answer,&mut encoding,None).map_err(|actual|QueryError::operational(key,actual))?;if actual!=proof.data.hash{return Err(QueryError::operational(key,invalid("current variable dependency answer differs from same native resolver")))}Ok(answer)
 })();match result{Ok(answer)=>answer,Err(actual)=>{self.latch(actual);ResolvedMeaning::Unsupported(query)}}}}
pub(super) fn register(db:&Db,ledger:Arc<Mutex<Ledger>>){
 db.define_input(CURRENT_MODEL,"current-variable-authenticated-model-context");
 let owners=ledger.clone();db.define(CURRENT_LOOKUP,"current-variable-actual-native-lookup",move|ctx,raw|{
  let params=raw.downcast_ref::<LookupParams>().expect("current lookup Params");pages::typed_publication(&owners,params.key)?;if params.code.strong_count()==0{return Err(QueryError::Missing(params.key))}{let mut ledger=owners.lock().unwrap_or_else(|e|e.into_inner());let old=ledger.nodes.get(&params.key).ok_or(QueryError::Missing(params.key))?.observed_edges;let peak=3usize;ledger.admit(peak.saturating_sub(old)*EDGE_BOUND).map_err(|_|QueryError::operational(params.key,oom("current lookup old/new dependency geometry exhausted")))?;ledger.update_node(&params.key,|node|node.observed_edges=old.max(peak)).unwrap();}let driver=ctx.input::<Driver>(params.driver)?;let input=driver.input.upgrade().ok_or(QueryError::Missing(params.key))?;input.require_original_checker_source().map_err(|message|QueryError::operational(params.key,io::Error::other(message)))?;
  let mut work=graph_work::GraphWork::new(owners.clone(),params.key);let answer=input.archive().tree().resolve_with_canonical_work(params.query,&mut work).map_err(|actual|QueryError::operational(params.key,actual))?;let mut codes=Vec::new();let hash=current_answer_hash(input.as_ref(),params.query,&answer,&mut work,Some(&mut codes)).map_err(|actual|QueryError::operational(params.key,actual))?;drop(answer);work.publish_data::<NativeCurrentLookup>(CurrentLookupData{hash,codes})
 });
 db.define(CURRENT_VARIABLES,"current-variable-same-evaluated-body",move|ctx,raw|{
  let params=raw.downcast_ref::<CurrentParams>().expect("current variable Params");pages::typed_publication(&ledger,params.key)?;let input=params.input.upgrade().ok_or(QueryError::Missing(params.key))?;input.require_original_checker_source().map_err(|message|QueryError::operational(params.key,io::Error::other(message)))?;
  let ordinal=input.archive().callables().ordinal_for_identity_using(params.caller,&mut||crate::daemon::control::checkpoint()).map_err(|actual|QueryError::operational(params.key,actual))?.ok_or(QueryError::Missing(params.key))?;
  let work=Mutex::new(graph_work::GraphWork::new(ledger.clone(),params.key));let admission=execution_admission(&ledger);
  let computed=setting_syntax::with_setting_admission(&params.syntax_charge,|syntax_admission|input.archive().with_current_body_checked_in(ordinal,syntax_admission,ctx,|ctx,syntax|{body_syntax::obtain_product(ctx,syntax)},|ctx,body|{
   if !Weak::ptr_eq(&params.code,&Arc::downgrade(body.syntax().original_code_owner())){return Err(BodySyntaxFailure::Operational(invalid("current semantic Params code differs from actual current archive")))}
   let context=Mutex::new(ctx);let resolver=Recording{ctx:&context,input:&input,params,ledger:ledger.clone(),work:&work,admission:&admission,error:Mutex::new(None)};
   let prefix_loan=|syntax:&Arc<dm_tree::frontend::BodySyntaxInput>|{let mut context=context.lock().unwrap_or_else(|e|e.into_inner());pages::reserve_actual_dependency(&ledger,params.key,params.old_edges,context.dependency_count()+1,&admission,admission.available()).map_err(BodySyntaxFailure::Operational)?;body_syntax::obtain_product(&mut context,syntax)};
   let mut shared=SharedWork(&work);let result=(||{let settings=dm_analysis::checks_directive_binding::current_setting_prelude(&body,&resolver,syntax_admission,&mut shared,&||crate::daemon::control::checkpoint())?;let variables=variables::current_using_with_prefix(&body,&resolver,input.profile(),syntax_admission,&admission,&mut shared,&||crate::daemon::control::checkpoint(),&prefix_loan)?;Ok::<_,dm_analysis::policy_body_demand::PolicyFailure>(CurrentContribution{variables,settings})})();resolver.finish().map_err(|actual|BodySyntaxFailure::Operational(pages::restore_graph_error(&ledger,actual)))?;result.map_err(|actual|BodySyntaxFailure::Operational(failure(actual)))
  }));params.dependencies.store(ctx.dependency_count(),std::sync::atomic::Ordering::Release);latch_transient_denial(&ledger,&admission);let product=computed.map_err(|actual|QueryError::operational(params.key,syntax_io(actual)))?;work.into_inner().unwrap_or_else(|e|e.into_inner()).publish_data::<NativeCurrentVariables>(product)
 });
}
impl QueryDb{
 fn with_current_contribution<T>(&self,input:&Arc<EffectInput>,scope:&crate::runner_host::query_snapshot::PurityScope<'_>,ordinal:usize,consume:impl FnOnce(&NativeCurrentVariables,Key)->io::Result<T>)->io::Result<T>{
  crate::daemon::control::checkpoint()?;scope.validate(self,input).map_err(io::Error::other)?;input.require_original_checker_source().map_err(io::Error::other)?;
  let _gate=self.purity.gate.lock().unwrap_or_else(|e|e.into_inner());scope.validate(self,input).map_err(io::Error::other)?;{let mut ledger=self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner());ledger.denied=false;ledger.aborted=None;}
  let driver=Key::new(CURRENT_MODEL,input.profile().get());let _driver=reserve_node(&self.purity.ledger,input,driver,None,std::mem::size_of::<Driver>())?;self.db.set_input(driver,Driver{input:Arc::downgrade(input)},input.key()as u128);
  self.prune_purity_under_gate(Some(driver));
  let syntax=input.archive().syntax_inputs().and_then(|rows|rows.get(ordinal)).ok_or_else(||invalid("current variable actual body input absent"))?;let code=syntax.original_code_owner().ok_or_else(||unsupported("current variable actual code identity unissued"))?;let caller=input.archive().callables().identity(ordinal).ok_or_else(||invalid("current variable callable occurrence absent"))?;let key=product_key(code,caller,input.profile());
  let code=Arc::downgrade(code);let _reservation=reserve_node(&self.purity.ledger,input,key,Some(&code),std::mem::size_of::<CurrentParams>())?;let mut peak=pages::reserve_dependencies(&self.purity.ledger,key,0).map_err(io::Error::other)?;let params=Arc::new(CurrentParams{key,driver,input:Arc::downgrade(input),code,caller,syntax_charge:self.body_charge.clone(),old_edges:peak.old,dependencies:std::sync::atomic::AtomicUsize::new(0)});remember_params(&self.purity.ledger,input,key,&params);
  let result=self.db.get::<Result<Arc<NativeCurrentVariables>,String>>(key,params.clone()).map_err(|actual|pages::restore_graph_error(&self.purity.ledger,actual))?;peak.commit(params.dependencies.load(std::sync::atomic::Ordering::Acquire));let value=result.as_ref().as_ref().map_err(|message|io::Error::other(message.clone()))?;scope.validate(self,input).map_err(io::Error::other)?;
  let delivered=consume(value,key)?;scope.validate(self,input).map_err(io::Error::other)?;Ok(delivered)
 }

 pub(crate) fn visit_current_variable_diagnostics(&self,input:&Arc<EffectInput>,scope:&crate::runner_host::query_snapshot::PurityScope<'_>,ordinal:usize,mut consume:impl FnMut(CurrentUndefinedRow<'_>)->io::Result<()>)->io::Result<CurrentUndefinedDisposition>{
  self.with_current_contribution(input,scope,ordinal,|value,_|self.with_setting_admission(|admission|input.archive().with_current_body_checked(ordinal,admission,|body|value.product.variables.visit_current(&body,|row|{crate::daemon::control::checkpoint()?;consume(row)}).map_err(BodySyntaxFailure::Operational))).map_err(syntax_io))
 }
 /// Per-body selected view only. Complete aggregate ALL-preludes-before-ALL-
 /// bodies phase ownership stays unchanged; no default checker cutover here.
 pub(crate) fn visit_current_selected_diagnostics(&self,input:&Arc<EffectInput>,scope:&crate::runner_host::query_snapshot::PurityScope<'_>,ordinal:usize,mut consume:impl FnMut(CurrentSelectedDiagnostic<'_>)->io::Result<()>)->io::Result<CurrentUndefinedDisposition>{
  self.with_current_contribution(input,scope,ordinal,|value,key|{
   let mut work=graph_work::GraphWork::new(self.purity.ledger.clone(),key);
   self.with_setting_admission(|admission|input.archive().with_current_body_checked(ordinal,admission,|body|{
    value.product.settings.visit_current(&body,admission,&mut work,&||crate::daemon::control::checkpoint(),|row|consume(CurrentSelectedDiagnostic::Prelude(row))).map_err(|actual|BodySyntaxFailure::Operational(failure(actual)))?;
    value.product.variables.visit_current(&body,|row|{crate::daemon::control::checkpoint()?;consume(CurrentSelectedDiagnostic::Body(row))}).map_err(BodySyntaxFailure::Operational)
   })).map_err(syntax_io)
  })
 }
}

#[cfg(test)]impl QueryDb{
 pub(crate) fn current_variable_keys_for_test(&self,input:&Arc<EffectInput>,ordinal:usize,query:ResolveQuery)->(Key,Key,Key){let syntax=&input.archive().syntax_inputs().unwrap()[ordinal];let code=syntax.original_code_owner().unwrap();let caller=input.archive().callables().identity(ordinal).unwrap();let parent=product_key(code,caller,input.profile());(parent,lookup_key(parent,query),Key::new(CURRENT_MODEL,input.profile().get()))}
}

#[cfg(test)]impl QueryDb{
 pub(crate) fn current_variable_actual_property_for_test(&self,input:&EffectInput,owner:dm_ir::SymbolId,name:dm_ir::SymbolId)->io::Result<u8>{let archive=input.archive();let formal=archive.tree().source_formal_variable_member(owner,name).map_err(unsupported)?.ok_or_else(||invalid("test actual property formal absent"))?;archive.checker_variable_qualifiers_admitted(formal,input.profile())}
}


#[cfg(test)]
#[test]
fn current_structural_fingerprint_distinguishes_presence_from_missing_and_unissued() {
    struct Scalars;
    impl dm_ir::CanonicalWork for Scalars {
        fn poll(&mut self) -> io::Result<()> { Ok(()) }
        fn reserve(&mut self, _: usize) -> io::Result<()> {
            panic!("scalar presence hashing should not reserve storage")
        }
    }
    let mut work = Scalars;
    let missing = meaning_hash(&ResolvedMeaning::Missing, &mut work).unwrap();
    let absent = meaning_hash(&ResolvedMeaning::Presence(false), &mut work).unwrap();
    let present = meaning_hash(&ResolvedMeaning::Presence(true), &mut work).unwrap();
    assert_ne!(missing, absent);
    assert_ne!(missing, present);
    assert_ne!(absent, present);

    let foreign_intrinsic = ResolveQuery::CheckerIntrinsicCallable {
        profile: 0u128.into(),
        owner: dm_ir::SymbolId::of("/datum"),
        name: dm_ir::SymbolId::of("New"),
        verb: false,
    };
    assert_eq!(
        meaning_hash(&ResolvedMeaning::Unsupported(foreign_intrinsic), &mut work)
            .unwrap_err().kind(),
        io::ErrorKind::Unsupported,
    );
}
