//! Actual native commit-product and final-adoption controls, not CLI parity.
use std::{path::Path,sync::{Arc,atomic::{AtomicBool,Ordering}}};
use dm_tree::frontend::{self,BodySyntaxQueries,SettingExpressionQueries,BodySyntaxInput,BodySyntax,BodySyntaxFailure,OriginalBodySyntaxProduct};
use dmbc::query_db::QueryDb;
#[global_allocator]static ALLOC:mimalloc::MiMalloc=mimalloc::MiMalloc;
#[path="../../../shared/test_scratch.rs"]mod scratch;
use dmbc::input_snapshot::{RecordingInputs,FileSystemInputs};
use dm_preprocess::{SourceProvider,SourceAcquisitionLease,source_arena_credit::SourceArenaWork};
struct Source{inputs:RecordingInputs<FileSystemInputs>,path:std::path::PathBuf}
impl Source{
 fn new(text:&str)->Self{
  let root=std::fs::canonicalize(scratch::dir("actual-committed-products")).unwrap();
  let path=root.join("actual-committed.dme");std::fs::write(&path,text.as_bytes()).unwrap();Self::at(path)
 }
 fn at(path:std::path::PathBuf)->Self{Self{inputs:RecordingInputs::new(FileSystemInputs,0).with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290),path}}
}
// SAME actual filesystem open/read/decode/acquired operation and recorder,
// exactly as the existing public Original diagnostics/mapping fixtures use.
impl SourceProvider for Source{
 fn original_batch_source(&self)->std::io::Result<Option<&(dyn SourceProvider+Sync)>>{Ok(Some(self))}
 fn initial_environment(&self)->dm_preprocess::InitialEnvironment{self.inputs.initial_environment()}
 fn read(&self,p:&Path)->Result<String,String>{SourceProvider::read(&self.inputs,p)}
 fn path_presence_admitted(&self,p:&Path,w:&dyn SourceArenaWork)->std::io::Result<bool>{self.inputs.path_presence_admitted(p,w)}
 fn original_raw_source_open_admitted(&self,p:&Path,max:usize,w:&dyn SourceArenaWork,after:&mut dyn FnMut()->std::io::Result<dm_preprocess::OriginalRawOpenDecision>,before:&mut dyn FnMut(usize)->std::io::Result<()>,decode:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->std::io::Result<()>,acquired:&mut dyn FnMut(&SourceAcquisitionLease)->std::io::Result<()>)->std::io::Result<dm_preprocess::OriginalRawReadOutcome>{self.inputs.original_raw_source_open_admitted(p,max,w,after,before,decode,acquired)}
 fn original_source_bytes<'a>(&'a self,l:&'a SourceAcquisitionLease)->std::io::Result<Option<&'a[u8]>>{self.inputs.original_source_bytes(l)}
}
fn build(text:&str,db:&Arc<QueryDb>,bodies:&Arc<dyn BodySyntaxQueries>)->Result<frontend::DiagnosticFrontend,frontend::FrontendBuildFailure>{build_source(&Source::new(text),db,bodies)}
fn build_source(source:&Source,db:&Arc<QueryDb>,bodies:&Arc<dyn BodySyntaxQueries>)->Result<frontend::DiagnosticFrontend,frontend::FrontendBuildFailure>{let seed=dm_tree::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let settings=Arc::clone(db)as Arc<dyn SettingExpressionQueries>;frontend::build_for_committed_body_syntax_checked(&source.path,source,&Default::default(),frontend::FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,&settings,bodies)}
fn computed(db:&QueryDb)->u64{db.db().stats(dm_query::Kind(4)).computed}
#[test]fn actual_commit_product_adopts_the_same_input_code_parameters_and_setting_first_writer(){
 let db=Arc::new(QueryDb::default());let bodies=Arc::clone(&db)as Arc<dyn BodySyntaxQueries>;
 let front=build("/proc/p(value=1)\n    set name=\"actual\"\n    return value\n/proc/q();\n",&db,&bodies).unwrap();assert_eq!(front.original_committed_body_counts().unwrap(),(2,0));assert_eq!(computed(&db),2);
 let archive=Arc::clone(front.source_view().unwrap().archive());let inputs=archive.syntax_inputs().unwrap();for(index,input)in inputs.iter().enumerate(){assert_eq!(input.key(),front.original_committed_body_input_key(index).unwrap());let product=db.syntax_product_checked(input).unwrap();input.require_product_issuance(&product).unwrap();}
 assert_eq!(computed(&db),2,"final source adoption must not force another BODY parse");let keys=inputs.iter().map(|input|input.key()).collect::<Vec<_>>();drop(archive);
 let front=front.with_body_queries(Arc::clone(&bodies)).unwrap();let archive=Arc::clone(front.source_view().unwrap().archive());assert_eq!(archive.syntax_inputs().unwrap().iter().map(|input|input.key()).collect::<Vec<_>>(),keys);assert_eq!(computed(&db),2);
}
#[test]fn actual_commit_local_bad_body_retains_first_error_and_continues_to_the_next_proc(){
 let db=Arc::new(QueryDb::default());let bodies=Arc::clone(&db)as Arc<dyn BodySyntaxQueries>;let front=build("/proc/bad(value)\n    return (value+)\n/proc/good()\n    return 1\n",&db,&bodies).unwrap();assert_eq!(front.original_committed_body_counts().unwrap(),(1,1));assert_eq!(computed(&db),2);
 let mut errors=0;front.visit_original_committed_body_diagnostics(&||Ok(()),&mut|row|{errors+=1;assert_eq!(row.point().reported_coordinates().1,2);assert!(!row.native().message.is_empty());row.reader_registration().compare_same_source(row.reader_registration())?;Ok(())}).unwrap();assert_eq!(errors,1,"pinned local BODY parse stops at its first real registered error");
}
#[test]fn actual_commit_product_evicts_then_recomputes_from_the_same_settled_input(){
 let db=Arc::new(QueryDb::default());let bodies=Arc::clone(&db)as Arc<dyn BodySyntaxQueries>;let front=build("/proc/first(value)\n    return value\n/proc/second()\n    return 2\n",&db,&bodies).unwrap();let archive=Arc::clone(front.source_view().unwrap().archive());let weak_input=Arc::downgrade(&archive.syntax_inputs().unwrap()[0]);let key=front.original_committed_body_input_key(0).unwrap();let product=db.syntax_product_checked(&archive.syntax_inputs().unwrap()[0]).unwrap();let weak_product=Arc::downgrade(&product);drop(product);assert_eq!(computed(&db),2);
 let settings=Arc::clone(&db)as Arc<dyn SettingExpressionQueries>;settings.with_declaration_admission(&mut|a|{let pressure=a.reserve(128*1024*1024-512*1024).map_err(BodySyntaxFailure::Operational)?;db.prepare_syntax_product_input(&archive.syntax_inputs().unwrap()[1])?;assert!(weak_product.upgrade().is_none(),"real existing pressure must retire the unloaned canonical value");drop(pressure);Ok(())}).unwrap();
 assert_eq!(weak_input.upgrade().unwrap().key(),key);let next=db.syntax_product_checked(&archive.syntax_inputs().unwrap()[0]).unwrap();archive.syntax_inputs().unwrap()[0].require_product_issuance(&next).unwrap();assert_eq!(computed(&db),3,"normal registered Kind4 must recompute through the settled original weak Params");assert_eq!(front.original_committed_body_input_key(0).unwrap(),key);drop(next);drop(archive);drop(front);assert!(weak_input.upgrade().is_none(),"Header weak column and graph Params must not retain the Input strongly");
}
struct FailFirst{db:Arc<QueryDb>,fail:AtomicBool}
impl BodySyntaxQueries for FailFirst{
 fn begin_revision(&self){self.db.begin_revision()}
 fn begin_revision_inputs(&self,inputs:&[Arc<BodySyntaxInput>]){self.db.begin_revision_inputs(inputs)}
 fn prepare_syntax_product_input(&self,input:&Arc<BodySyntaxInput>)->Result<(),BodySyntaxFailure>{self.db.prepare_syntax_product_input(input)}
 fn syntax_product_checked(&self,input:&Arc<BodySyntaxInput>)->Result<Arc<OriginalBodySyntaxProduct>,BodySyntaxFailure>{self.db.syntax_product_checked(input)}
 fn syntax_product_at_committed_input(&self,input:&Arc<BodySyntaxInput>,a:&dm_syntax::SettingAdmission<'_>,produce:&mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->Result<OriginalBodySyntaxProduct,BodySyntaxFailure>)->Result<Arc<OriginalBodySyntaxProduct>,BodySyntaxFailure>{if self.fail.swap(false,Ordering::SeqCst){a.record_operational_error(std::io::Error::from_raw_os_error(1450));let _=a.checkpoint();return Err(BodySyntaxFailure::Operational(a.take_operational_error().expect("same actual first IO")))}self.db.syntax_product_at_committed_input(input,a,produce)}
 fn syntax(&self,input:&Arc<BodySyntaxInput>)->Result<Arc<BodySyntax>,frontend::Diagnostic>{self.db.syntax(input)}
 fn syntax_checked(&self,input:&Arc<BodySyntaxInput>)->Result<Arc<BodySyntax>,BodySyntaxFailure>{self.db.syntax_checked(input)}
}
impl std::fmt::Debug for FailFirst{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("actual native first-error boundary")}}
#[test]fn actual_commit_first_io_refunds_unpublished_inputs_and_same_host_recovers(){
 let db=Arc::new(QueryDb::default());let bodies=Arc::new(FailFirst{db:Arc::clone(&db),fail:AtomicBool::new(true)})as Arc<dyn BodySyntaxQueries>;let source=Source::new("/proc/p()\n    return 1\n");
 let error=build_source(&source,&db,&bodies).err().expect("actual first BODY callback must fail");let frontend::FrontendBuildFailure::Operational(actual)=error else{panic!("actual native IO cannot become source diagnostics")};assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(computed(&db),0);let source_path=source.path.clone();drop(source);
 let settings=Arc::clone(&db)as Arc<dyn SettingExpressionQueries>;settings.with_declaration_admission(&mut|a|{let exact=a.reserve(128*1024*1024-dm_syntax::SettingChargeCounter::root_allocation_bytes()).map_err(BodySyntaxFailure::Operational)?;drop(exact);Ok(())}).unwrap();
 let source=Source::at(source_path);let front=build_source(&source,&db,&bodies).unwrap();assert_eq!(front.original_committed_body_counts().unwrap(),(1,0));assert_eq!(computed(&db),1);
}

#[test]fn actual_commit_structural_collection_is_explicitly_unqualified_and_ordinary_headers_cannot_issue_it(){
 let db=Arc::new(QueryDb::default());let bodies=Arc::clone(&db)as Arc<dyn BodySyntaxQueries>;
 let refused=build("/proc/p()\n    return ([)]\n",&db,&bodies).err().expect("crossed TT groups cannot be a local-bad completion");let frontend::FrontendBuildFailure::Operational(actual)=refused else{panic!("unqualified TT cannot be a completed syntax diagnostic")};assert_eq!(actual.kind(),std::io::ErrorKind::Unsupported);
 let source=Source::new("/proc/p()\n    return 1\n");let seed=dm_tree::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let settings=Arc::clone(&db)as Arc<dyn SettingExpressionQueries>;let ordinary=frontend::build_for_checker_diagnostics_with_state_checked(&source.path,&source,&Default::default(),frontend::FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None,&settings).unwrap();assert_eq!(ordinary.original_committed_body_counts().unwrap_err().kind(),std::io::ErrorKind::Unsupported,"ordinary reader EOF is not actual BODY syntax consumption");
}

struct FailAfterParams{db:Arc<QueryDb>,tails:std::sync::Mutex<Option<(frontend::BodyCodeWeak,std::sync::Weak<frontend::BodySyntaxInputWeak>)>>}
impl std::fmt::Debug for FailAfterParams{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("actual after-Params first IO")}}
impl BodySyntaxQueries for FailAfterParams{
 fn begin_revision(&self){self.db.begin_revision()}
 fn begin_revision_inputs(&self,x:&[Arc<BodySyntaxInput>]){self.db.begin_revision_inputs(x)}
 fn prepare_syntax_product_input(&self,x:&Arc<BodySyntaxInput>)->Result<(),BodySyntaxFailure>{self.db.prepare_syntax_product_input(x)}
 fn syntax_product_checked(&self,x:&Arc<BodySyntaxInput>)->Result<Arc<OriginalBodySyntaxProduct>,BodySyntaxFailure>{self.db.syntax_product_checked(x)}
 fn syntax(&self,x:&Arc<BodySyntaxInput>)->Result<Arc<BodySyntax>,frontend::Diagnostic>{self.db.syntax(x)}
 fn syntax_checked(&self,x:&Arc<BodySyntaxInput>)->Result<Arc<BodySyntax>,BodySyntaxFailure>{self.db.syntax_checked(x)}
 fn syntax_product_at_committed_input(&self,x:&Arc<BodySyntaxInput>,a:&dm_syntax::SettingAdmission<'_>,_:&mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->Result<OriginalBodySyntaxProduct,BodySyntaxFailure>)->Result<Arc<OriginalBodySyntaxProduct>,BodySyntaxFailure>{
  self.db.syntax_product_at_committed_input(x,a,&mut|actual|{
   *self.tails.lock().unwrap()=Some((frontend::BodyCodeIdentity::downgrade(x.original_code_owner().unwrap()),Arc::downgrade(&x.weak_allocation_owner())));
   actual.record_operational_error(std::io::Error::from_raw_os_error(1450));let _=actual.checkpoint();Err(BodySyntaxFailure::Operational(actual.take_operational_error().expect("same actual first error")))
  })
 }
}
#[test]fn actual_commit_after_params_io_keeps_both_internal_weak_tails_until_real_prune_then_refunds(){
 let db=Arc::new(QueryDb::default());let failing=Arc::new(FailAfterParams{db:Arc::clone(&db),tails:Default::default()});let bodies=Arc::clone(&failing)as Arc<dyn BodySyntaxQueries>;
 let source=Source::new("/proc/p()\n    return 1\n");let source_path=source.path.clone();let error=build_source(&source,&db,&bodies).err().expect("actual scoped callback first IO");drop(source);let frontend::FrontendBuildFailure::Operational(actual)=error else{panic!("actual first IO cannot be a source diagnostic")};assert_eq!(actual.raw_os_error(),Some(1450));
 let(code,input)=failing.tails.lock().unwrap().take().expect("callback ran after actual Params registration");
 // Db::run's fresh-error path calls drop_fresh: no failed Params/strong Code
 // result is cached. The genuine weak resource locator still funds its shell.
 assert!(code.upgrade().is_none(),"fresh failed computation must drop its Params and strong Code owner");assert_eq!(code.strong_count(),0);
 assert!(input.upgrade().is_some(),"existing body_inputs registry still owns its actual weak allocation tail");
 drop(input);db.begin_revision();
 let settings=Arc::clone(&db)as Arc<dyn SettingExpressionQueries>;
 settings.with_declaration_admission(&mut|a|{let missing=a.try_reserve_optimization(128*1024*1024-dm_syntax::SettingChargeCounter::root_allocation_bytes()).map_err(BodySyntaxFailure::Operational)?;assert!(missing.is_none(),"actual dead Code weak locator must keep its SAME-counter shell paid after real registry prune");Ok(())}).unwrap();
 drop(code);
settings.with_declaration_admission(&mut|a|{let remaining=a.reserve(128*1024*1024-dm_syntax::SettingChargeCounter::root_allocation_bytes()).map_err(BodySyntaxFailure::Operational)?;drop(remaining);Ok(())}).unwrap();
 let healthy=Arc::clone(&db)as Arc<dyn BodySyntaxQueries>;assert_eq!(build_source(&Source::at(source_path),&db,&healthy).unwrap().original_committed_body_counts().unwrap(),(1,0));
}

/// Test-only external consumer loan of ONE actual produced value, never an
/// alternate producer, memo family, AST copy or source/current authority.
struct CaptureActualProduct{db:Arc<QueryDb>,actual:std::sync::Mutex<Option<(Arc<OriginalBodySyntaxProduct>,frontend::BodyCodeWeak,std::sync::Weak<frontend::BodySyntaxInputWeak>)>>}
impl std::fmt::Debug for CaptureActualProduct{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("actual external canonical product loan")}}
impl BodySyntaxQueries for CaptureActualProduct{
 fn begin_revision(&self){self.db.begin_revision()}
 fn begin_revision_inputs(&self,x:&[Arc<BodySyntaxInput>]){self.db.begin_revision_inputs(x)}
 fn prepare_syntax_product_input(&self,x:&Arc<BodySyntaxInput>)->Result<(),BodySyntaxFailure>{self.db.prepare_syntax_product_input(x)}
 fn syntax_product_checked(&self,x:&Arc<BodySyntaxInput>)->Result<Arc<OriginalBodySyntaxProduct>,BodySyntaxFailure>{self.db.syntax_product_checked(x)}
 fn syntax(&self,x:&Arc<BodySyntaxInput>)->Result<Arc<BodySyntax>,frontend::Diagnostic>{self.db.syntax(x)}
 fn syntax_checked(&self,x:&Arc<BodySyntaxInput>)->Result<Arc<BodySyntax>,BodySyntaxFailure>{self.db.syntax_checked(x)}
 fn syntax_product_at_committed_input(&self,x:&Arc<BodySyntaxInput>,a:&dm_syntax::SettingAdmission<'_>,produce:&mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->Result<OriginalBodySyntaxProduct,BodySyntaxFailure>)->Result<Arc<OriginalBodySyntaxProduct>,BodySyntaxFailure>{let product=self.db.syntax_product_at_committed_input(x,a,produce)?;*self.actual.lock().unwrap()=Some((Arc::clone(&product),frontend::BodyCodeIdentity::downgrade(x.original_code_owner().unwrap()),Arc::downgrade(&x.weak_allocation_owner())));Ok(product)}
}
#[test]fn actual_external_parsed_and_rejected_products_keep_only_their_code_tail_after_frontend_prune(){
 for(source,rejected)in[("/proc/p()\n    return 1\n",false),("/proc/p()\n    return\n        return 1\n",true)]{
  let db=Arc::new(QueryDb::default());let consumer=Arc::new(CaptureActualProduct{db:Arc::clone(&db),actual:Default::default()});let bodies=Arc::clone(&consumer)as Arc<dyn BodySyntaxQueries>;
  // Return-with-block is the actual canonical primary Statement diagnostic;
  // typed TT/whole-line consumption remains complete. Existing primary
  // diagnostics may independently refuse the overall frontend. This control
  // claims the actual captured product/credit tail, never frontend success.
  let frontend_result=build(source,&db,&bodies);let(product,code,input)=consumer.actual.lock().unwrap().take().expect("actual same Kind4 producer must have run");assert_eq!(matches!(&*product,OriginalBodySyntaxProduct::Rejected(_)),rejected,"fixture must exercise the actual requested product variant");drop(frontend_result);assert!(input.upgrade().is_some(),"actual registry weak owner retains Input allocation credit");drop(input);db.begin_revision();{let actual=code.upgrade().expect("external actual Parsed/Rejected retains CodeArc");assert!(actual.committed_allocation_credit().is_some());}drop(code);drop(product);
  let settings=Arc::clone(&db)as Arc<dyn SettingExpressionQueries>;settings.with_declaration_admission(&mut|a|{let all=a.reserve(128*1024*1024-dm_syntax::SettingChargeCounter::root_allocation_bytes()).map_err(BodySyntaxFailure::Operational)?;drop(all);Ok(())}).unwrap();
 }
}

#[test]fn actual_collected_code_converges_into_the_next_ordinary_source_and_keeps_its_intrinsic_grant(){
 let db=Arc::new(QueryDb::default());let bodies=Arc::clone(&db)as Arc<dyn BodySyntaxQueries>;let settings=Arc::clone(&db)as Arc<dyn SettingExpressionQueries>;let mut state=frontend::RetainedSemanticTree::new();let text="/proc/p(value)\n    return value\n";
 let seed=dm_tree::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let first_source=Source::new(text);
 let first=Arc::new(frontend::build_for_committed_body_syntax_checked(&first_source.path,&first_source,&Default::default(),frontend::FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},Some(&mut state),&executor,&settings,&bodies).unwrap());let first_archive=Arc::clone(first.source_view().unwrap().archive());let code=Arc::clone(first_archive.syntax_inputs().unwrap()[0].original_code_owner().unwrap());let code_credit=frontend::BodyCodeIdentity::downgrade(&code);let original_key=first_archive.syntax_inputs().unwrap()[0].key();
 // Building with semantic state records declarations/callables; the existing
 // predecessor slot is published separately by the actual completed owner.
 assert!(state.with_remembered_analysis_source(|_|()).unwrap().is_none());
 state.remember_analysis_frontend(&first_source.path,&Default::default(),Arc::clone(&first)).unwrap();
 assert_eq!(state.with_remembered_analysis_source(|view|Arc::ptr_eq(view.archive(),&first_archive)).unwrap(),Some(true),"the genuine completed predecessor must be retained before neutral code convergence");
 drop(first_archive);drop(first);
 let next_source=Source::at(first_source.path.clone());let next=frontend::build_for_checker_diagnostics_with_state_checked(&next_source.path,&next_source,&Default::default(),frontend::FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,Some(&mut state),&settings).unwrap().with_body_queries(Arc::clone(&bodies)).unwrap();let archive=Arc::clone(next.source_view().unwrap().archive());let input=&archive.syntax_inputs().unwrap()[0];assert!(Arc::ptr_eq(input.original_code_owner().unwrap(),&code),"actual existing code convergence must retain the same CodeArc, not copy its DATA");assert_ne!(input.key(),original_key,"ordinary next-source Input is independently issued");let product=db.syntax_product_checked(input).unwrap();settings.with_declaration_admission(&mut|a|{input.bind_original_product_checked(product.parsed().unwrap(),a)?;Ok(())}).unwrap();assert!(code_credit.upgrade().is_some());drop(product);drop(archive);drop(next);drop(state);drop(first_source);drop(next_source);drop(code_credit);drop(code);db.begin_revision();settings.with_declaration_admission(&mut|a|{let all=a.reserve(128*1024*1024-dm_syntax::SettingChargeCounter::root_allocation_bytes()).map_err(BodySyntaxFailure::Operational)?;drop(all);Ok(())}).unwrap();
}


fn build_actual_ordinary_code_demand(source:&Source,db:&Arc<QueryDb>,state:Option<&mut frontend::RetainedSemanticTree>)->frontend::DiagnosticFrontend{
 let seed=dm_tree::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let settings=Arc::clone(db)as Arc<dyn SettingExpressionQueries>;
 frontend::build_for_original_native_body_demand_with_callable_anchors_checked(&source.path,source,&Default::default(),frontend::FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,state,&settings,None).unwrap().with_body_queries_checked(Arc::clone(db)as Arc<dyn BodySyntaxQueries>,settings).unwrap()
}
#[test]fn actual_ordinary_body_demand_cold_headers_then_same_and_different_ordinals_issue_only_real_pairs(){
 let db=Arc::new(QueryDb::default());let source=Source::new("#define ACTUAL_DEMAND_HISTORY 7\n/proc/p(value=1)\n    set name=\"actual\"\n    return value\n/proc/q();\n");let front=build_actual_ordinary_code_demand(&source,&db,None);
 assert_eq!(front.original_analysis_completeness(),Some(frontend::OriginalAnalysisCompleteness::Complete));let view=front.checker_source_view().unwrap();assert!(view.original_plan().final_macro("ACTUAL_DEMAND_HISTORY").unwrap().is_some());let archive=Arc::clone(view.archive());assert_eq!(archive.len(),2);assert!(archive.uses_ordinary_body_demand());assert!(archive.syntax_inputs().is_none(),"a sparse store must never masquerade as a full eager roster");
 archive.callable_header_source().reader_end_registration().unwrap().unwrap().require_after_actual_end().unwrap();for i in 0..archive.len(){assert!(archive.peek_syntax_input(i).is_none());archive.with_header_parameters_using(i,&||Ok(()),|_|Ok::<_,BodySyntaxFailure>(())).unwrap();}assert_eq!(computed(&db),0);assert!((0..archive.len()).all(|i|archive.peek_syntax_input(i).is_none()),"actual formal/header preparation issues no Input");
 let barrier=Arc::new(std::sync::Barrier::new(4));let workers=[0usize,0,1].into_iter().map(|ordinal|{let archive=Arc::clone(&archive);let barrier=Arc::clone(&barrier);std::thread::spawn(move||{barrier.wait();archive.syntax_input_checked(ordinal,&||Ok(())).unwrap()})}).collect::<Vec<_>>();barrier.wait();let mut workers=workers.into_iter();let input=workers.next().unwrap().join().unwrap();let same=workers.next().unwrap().join().unwrap();let other=workers.next().unwrap().join().unwrap();assert!(!Arc::ptr_eq(&input,&other));assert!(!Arc::ptr_eq(input.original_code_owner().unwrap(),other.original_code_owner().unwrap()));assert!(Arc::ptr_eq(&input,&same));assert!(Arc::ptr_eq(input.original_code_owner().unwrap(),same.original_code_owner().unwrap()));assert!(Arc::ptr_eq(&archive.peek_syntax_input(1).unwrap(),&other));assert_eq!(computed(&db),0,"Input/Code resolution never parses BODY");
 let product=db.syntax_product_checked(&input).unwrap();input.require_product_issuance(&product).unwrap();assert!(product.parsed().is_some());assert_eq!(computed(&db),1);let again=db.syntax_product_checked(&same).unwrap();assert!(Arc::ptr_eq(&product,&again));assert_eq!(computed(&db),1);
 let weak=Arc::downgrade(&input);let code=frontend::BodyCodeIdentity::downgrade(input.original_code_owner().unwrap());drop(again);drop(product);drop(other);drop(same);drop(input);drop(archive);drop(view);drop(front);drop(source);db.begin_revision();assert!(weak.upgrade().is_none());assert!(code.upgrade().is_none());drop(code);let settings=Arc::clone(&db)as Arc<dyn SettingExpressionQueries>;settings.with_declaration_admission(&mut|a|{let all=a.reserve(128*1024*1024-dm_syntax::SettingChargeCounter::root_allocation_bytes()).map_err(BodySyntaxFailure::Operational)?;drop(all);Ok(())}).unwrap();
}
#[test]fn actual_ordinary_body_demand_first_io_pressure_and_cancel_leave_no_input_then_fresh_scope_recovers(){
 let db=Arc::new(QueryDb::default());let source=Source::new("/proc/p()\n    return 1\n");let front=build_actual_ordinary_code_demand(&source,&db,None);let archive=Arc::clone(front.source_view().unwrap().archive());
 for expected in [Some(1450),None]{let error=archive.syntax_input_checked(0,&||Err(match expected{Some(raw)=>std::io::Error::from_raw_os_error(raw),None=>std::io::ErrorKind::Interrupted.into()})).err().expect("actual first IO/cancel must refuse");let BodySyntaxFailure::Operational(actual)=error else{panic!("operational ingress cannot become syntax")};if let Some(raw)=expected{assert_eq!(actual.raw_os_error(),Some(raw));}else{assert_eq!(actual.kind(),std::io::ErrorKind::Interrupted);}assert!(archive.peek_syntax_input(0).is_none());}
 let settings=Arc::clone(&db)as Arc<dyn SettingExpressionQueries>;let(mut low,mut high)=(0usize,128*1024*1024usize);while low<high{let probe=low+(high-low).div_ceil(2);let status=settings.with_declaration_admission(&mut|a|{let lease=a.reserve(probe).map_err(BodySyntaxFailure::Operational)?;drop(lease);Ok(())});match status{Ok(())=>low=probe,Err(BodySyntaxFailure::Operational(e))if e.kind()==std::io::ErrorKind::OutOfMemory=>high=probe-1,other=>panic!("actual pressure probe: {other:?}")}}
 assert!(low>1024);let mut pressure=None;settings.with_declaration_admission(&mut|a|{pressure=Some(a.reserve(low-8).map_err(BodySyntaxFailure::Operational)?);Ok(())}).unwrap();let error=archive.syntax_input_checked(0,&||Ok(())).err().expect("actual same-counter pressure must refuse");assert!(matches!(error,BodySyntaxFailure::Operational(ref e)if e.kind()==std::io::ErrorKind::OutOfMemory));assert!(archive.peek_syntax_input(0).is_none());assert_eq!(computed(&db),0);drop(pressure);
 let input=archive.syntax_input_checked(0,&||Ok(())).unwrap();let product=db.syntax_product_checked(&input).unwrap();input.require_product_issuance(&product).unwrap();assert!(product.parsed().is_some());assert_eq!(computed(&db),1);drop(product);drop(input);drop(archive);drop(front);drop(source);db.begin_revision();settings.with_declaration_admission(&mut|a|{let all=a.reserve(128*1024*1024-dm_syntax::SettingChargeCounter::root_allocation_bytes()).map_err(BodySyntaxFailure::Operational)?;drop(all);Ok(())}).unwrap();
}

#[test]fn actual_ordinary_body_demand_rebinds_only_issued_predecessor_before_prune_under_shifted_source(){
 let db=Arc::new(QueryDb::default());let source=Source::new("/proc/p(value)\n    return value\n/proc/q()\n    return 2\n");let mut state=frontend::RetainedSemanticTree::new();let first=Arc::new(build_actual_ordinary_code_demand(&source,&db,Some(&mut state)));let archive=Arc::clone(first.source_view().unwrap().archive());let input=archive.syntax_input_checked(0,&||Ok(())).unwrap();let code=Arc::clone(input.original_code_owner().unwrap());let old_key=input.key();let product=db.syntax_product_checked(&input).unwrap();assert_eq!(computed(&db),1);assert!(archive.peek_syntax_input(1).is_none());state.remember_analysis_frontend(&source.path,&Default::default(),Arc::clone(&first)).unwrap();
 std::fs::write(&source.path,b"\n/proc/p(value)\n    return value\n/proc/q()\n    return 2\n").unwrap();let next_source=Source::at(source.path.clone());let next=build_actual_ordinary_code_demand(&next_source,&db,Some(&mut state));let current=Arc::clone(next.source_view().unwrap().archive());let next_input=current.peek_syntax_input(0).expect("real registered predecessor must acquire its CURRENT locator before prune");assert!(Arc::ptr_eq(next_input.original_code_owner().unwrap(),&code));assert_ne!(next_input.key(),old_key,"same Code does not reuse the old source-bound Input");assert_ne!(current.occurrences()[0].expanded_span,archive.occurrences()[0].expanded_span);assert!(current.peek_syntax_input(1).is_none(),"never-issued predecessor must stay genuinely unissued");assert_eq!(computed(&db),1,"rebind must not run a parser/query");
 let settings=Arc::clone(&db)as Arc<dyn SettingExpressionQueries>;settings.with_declaration_admission(&mut|a|{next_input.bind_original_product_checked(product.parsed().unwrap(),a)?;Ok(())}).unwrap();let reused=db.syntax_product_checked(&next_input).unwrap();assert!(Arc::ptr_eq(&product,&reused));assert_eq!(computed(&db),1);drop(reused);drop(product);drop(next_input);drop(input);drop(archive);drop(current);drop(first);drop(next);drop(state);drop(source);drop(next_source);drop(code);db.begin_revision();settings.with_declaration_admission(&mut|a|{let all=a.reserve(128*1024*1024-dm_syntax::SettingChargeCounter::root_allocation_bytes()).map_err(BodySyntaxFailure::Operational)?;drop(all);Ok(())}).unwrap();
}

#[test]fn actual_optional_call_heads_require_original_body_witness_and_refuse_foreign_root_forms(){
 for(statement,available)in[("value.disassociate()",true),("value?.disassociate()",true),("value.first()?.second().third()",true),("value?.choose(first=1,second=2)",true),("(value)?.disassociate()",false),("value[1]?.disassociate()",false),("value?:disassociate()",false)]{
  let db=Arc::new(QueryDb::default());let source=Source::new(&format!("/proc/p(value)\n    {statement}\n"));let front=build_actual_ordinary_code_demand(&source,&db,None);let archive=Arc::clone(front.source_view().unwrap().archive());let input=archive.syntax_input_checked(0,&||Ok(())).unwrap();let product=db.syntax_product_checked(&input).unwrap();let syntax=product.parsed().expect("ordinary native syntax parse is separate from Original availability");let settings=Arc::clone(&db)as Arc<dyn SettingExpressionQueries>;
  settings.with_declaration_admission(&mut|a|{let bound=input.bind_original_product_checked(syntax,a)?;let disposition=bound.original_code_disposition();if available{let frontend::OriginalBodyDisposition::Available(proof)=disposition.unwrap_or_else(|error|panic!("actual Original call witness failed for {statement}: {error:?}")) else{panic!("actual Original call witness absent: {statement}")};assert!(proof.belongs_to(&bound));}else{let Err(BodySyntaxFailure::Operational(actual))=disposition else{panic!("actual root form must be explicitly unissued: {statement}")};assert!(frontend::CurrentBodySyntax::is_unissued_original_grammar(&actual),"must preserve the actual missing Original witness: {statement}: {actual}");}Ok(())}).unwrap();
 }
}

fn build_parse_only(text:&str,db:&Arc<QueryDb>)->Result<frontend::DiagnosticFrontend,frontend::FrontendBuildFailure>{let source=Source::new(text);let seed=dm_tree::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let settings=Arc::clone(db)as Arc<dyn SettingExpressionQueries>;let bodies=Arc::clone(db)as Arc<dyn BodySyntaxQueries>;frontend::build_for_parse_only_syntax_checked(&source.path,&source,&Default::default(),frontend::FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},&executor,&settings,&bodies)}
#[test]fn actual_parse_only_formal_fatal_keeps_prior_local_error_order_counts_and_non_eof(){
 let db=Arc::new(QueryDb::default());let front=build_parse_only("#warn BEFORE_PREFIX\n/proc/local_bad(value=1)\n    return (value+)\n/proc/good(value=2)\n    return value\n/proc/fatal(value=)\n#error FUTURE_UNPULLED\n/proc/later()\n    return 3\n",&db).unwrap();
 assert_eq!(front.preparation_purpose(),frontend::DiagnosticPreparationPurpose::OriginalAnalyzePrefix);assert_eq!(front.parse_only_body_counts().unwrap(),(1,1));assert_eq!(computed(&db),2,"same actual committed BODY producer, fatal formal never commits a BODY");
 assert!(front.checker_source_view().is_err());assert!(front.original_committed_body_counts().is_err());assert!(front.original_committed_body_input_key(0).is_err());
 let view=front.source_view().unwrap();assert_eq!(view.bodies().len(),2);assert!(view.tree().symbols().text(dm_ir::SymbolId::of("later")).is_none());
 let end=view.archive().callable_header_source().reader_end_registration().unwrap().expect("actual fatal reader frontier");assert!(end.require_after_actual_end().is_err(),"fatal prefix is never AfterActualEnd");
 let mut local=0;front.visit_parse_only_body_diagnostics(&||Ok(()),&mut|row|{local+=1;assert_eq!(row.point().reported_coordinates().1,3);assert!(row.reader_registration().compare_same_source(&end)?!=std::cmp::Ordering::Greater);assert!(!row.native().message.is_empty());Ok(())}).unwrap();assert_eq!(local,1);
 let notices=view.original_preprocess_notices().unwrap();let notices=notices.iter().map(|notice|notice.unwrap()).collect::<Vec<_>>();assert_eq!(notices.len(),1);assert!(notices[0].message.contains("BEFORE_PREFIX"));assert!(!notices.iter().any(|notice|notice.message.contains("FUTURE_UNPULLED")));
 drop(notices);drop(front);db.begin_revision();let settings=Arc::clone(&db)as Arc<dyn SettingExpressionQueries>;settings.with_declaration_admission(&mut|a|{let all=a.reserve(128*1024*1024-dm_syntax::SettingChargeCounter::root_allocation_bytes()).map_err(BodySyntaxFailure::Operational)?;drop(all);Ok(())}).unwrap();
}
#[test]fn actual_parse_only_balanced_local_bad_continues_and_real_complete_end_stays_distinct(){
 let db=Arc::new(QueryDb::default());let front=build_parse_only("/proc/local_bad(value)\n    return (value+)\n/proc/good()\n    return 2\n",&db).unwrap();assert_eq!(front.parse_only_body_counts().unwrap(),(1,1));assert_eq!(front.original_committed_body_counts().unwrap(),(1,1));assert_eq!(computed(&db),2);let view=front.source_view().unwrap();view.archive().callable_header_source().reader_end_registration().unwrap().unwrap().require_after_actual_end().unwrap();let mut errors=0;front.visit_parse_only_body_diagnostics(&||Ok(()),&mut|_|{errors+=1;Ok(())}).unwrap();assert_eq!(errors,1);
}
#[test]fn actual_parse_only_structural_collection_remains_refused_without_a_local_bad_grant(){
 let db=Arc::new(QueryDb::default());let Err(frontend::FrontendBuildFailure::Operational(actual))=build_parse_only("/proc/p()\n    return (1\n",&db)else{panic!("unmatched actual TT cannot become a locally rejected completed BODY")};assert_eq!(actual.kind(),std::io::ErrorKind::Unsupported);
}
#[path="../../../shared/test_scratch.rs"]mod prefix_scratch;
fn parse_only_request(name:&str,text:&str)->(dmbc::native_checker::Request,std::path::PathBuf){let root=prefix_scratch::dir(name);let project=root.join("project.dme");std::fs::write(&project,text).unwrap();let project=std::fs::canonicalize(project).unwrap();let cache=prefix_scratch::dir(&format!("{name}-cache"));(dmbc::native_checker::Request{project:project.clone(),configuration:None,cache_root:cache,workers:1,timeout_seconds:60},project)}
#[test]fn actual_parse_only_moved_recorder_prefix_rechecks_source_and_recovers_same_host(){
 let text="/proc/good(value=1)\n    return value\n/proc/fatal(value=)\n";let(request,project)=parse_only_request("actual-prefix-ledger",text);let mut host=dmbc::runner_host::BuildHost::default();
 dmbc::native_checker::observe_parse_only_syntax(request.clone(),&mut host,|front|{assert_eq!(front.parse_only_body_counts()?,(1,0));assert!(front.checker_source_view().is_err());Ok(())}).unwrap();
 let actual=dmbc::native_checker::observe_parse_only_syntax(request.clone(),&mut host,|front|{assert_eq!(front.parse_only_body_counts()?,(1,0));std::fs::write(&project,"/proc/changed()\n    return 2\n")?;Ok(())}).unwrap_err();assert_eq!(actual.downcast_ref::<std::io::Error>().unwrap().kind(),std::io::ErrorKind::Interrupted);
 std::fs::write(&project,text).unwrap();dmbc::native_checker::observe_parse_only_syntax(request,&mut host,|front|{assert_eq!(front.parse_only_body_counts()?,(1,0));Ok(())}).unwrap();
}
#[test]fn actual_parse_only_report_callback_preserves_first_1450_before_later_source_change(){
 let(request,project)=parse_only_request("actual-prefix-first-io","/proc/good()\n    return 1\n/proc/fatal(value=)\n");let mut host=dmbc::runner_host::BuildHost::default();let actual=dmbc::native_checker::observe_parse_only_syntax::<()>(request,&mut host,|front|{assert_eq!(front.parse_only_body_counts()?,(1,0));std::fs::write(&project,"changed after genuine callback entry")?;Err(std::io::Error::from_raw_os_error(1450))}).unwrap_err();assert_eq!(actual.downcast_ref::<std::io::Error>().unwrap().raw_os_error(),Some(1450));
}

#[test]fn actual_parse_only_first_formal_fatal_has_zero_commits_without_an_empty_complete_grant(){
 let db=Arc::new(QueryDb::default());let front=build_parse_only("/proc/fatal(value=)\n/proc/unreached()\n    return 1\n",&db).unwrap();assert_eq!(front.preparation_purpose(),frontend::DiagnosticPreparationPurpose::OriginalAnalyzePrefix);assert_eq!(front.parse_only_body_counts().unwrap(),(0,0));assert_eq!(computed(&db),0);assert!(front.checker_source_view().is_err());assert!(front.original_committed_body_counts().is_err());assert!(front.original_committed_body_input_key(0).is_err());let view=front.source_view().unwrap();assert!(view.bodies().is_empty());assert!(view.tree().symbols().text(dm_ir::SymbolId::of("unreached")).is_none());assert!(view.archive().callable_header_source().reader_end_registration().unwrap().unwrap().require_after_actual_end().is_err());let mut rows=0;front.visit_parse_only_body_diagnostics(&||Ok(()),&mut|_|{rows+=1;Ok(())}).unwrap();assert_eq!(rows,0);
}

#[test]fn actual_report_only_prefix_owned_builder_refuses_attach_parse_and_compiler_escapes(){
 let db=Arc::new(QueryDb::default());let front=build_parse_only("/proc/good(value=1)\n    return value\n/proc/fatal(value=)\n",&db).unwrap();let archive=Arc::clone(front.source_view().unwrap().archive());assert!(archive.syntax_inputs().is_none());let before=computed(&db);assert!(archive.parse(0).is_err());assert!(archive.parse_checked(0).is_err());assert!(archive.parse_checked_using(0,|_|panic!("report-only prefix cannot invoke a query getter")).is_err());assert_eq!(computed(&db),before);
 let front=match front.try_into_compilable(){Err(front)=>front,Ok(_)=>panic!("report-only prefix cannot become a compiler frontend")};let mut state=frontend::RetainedSemanticTree::new();let front=match front.try_into_compilable_retained(&mut state){Err(front)=>front,Ok(_)=>panic!("report-only prefix cannot publish compiler state")};assert!(state.snapshot_tree().is_none());let bodies=Arc::clone(&db)as Arc<dyn BodySyntaxQueries>;assert!(front.with_body_queries(bodies).is_err(),"owned public builder must not mint fresh settled identities");assert!(archive.syntax_inputs().is_none());assert_eq!(computed(&db),before);
}

#[test]fn actual_issued_body_long_literal_uses_same_token_geometry_under_unchanged_syntax_cap(){
 // A genuine ordinary BODY issue, not an invented token list or hand-built
 // StatementBody. Its old width-only cleanup grant alone exceeded the actual
 // 128MiB syntax cap, despite one ordinary literal + one return statement.
 let text=format!("/proc/p()\n    return \"{}\"\n","x".repeat(300*1024));
 assert!(text.len().checked_mul(512).unwrap()+8192>128*1024*1024);
 let db=Arc::new(QueryDb::default());let source=Source::new(&text);let front=build_actual_ordinary_code_demand(&source,&db,None);let archive=Arc::clone(front.source_view().unwrap().archive());assert!(archive.peek_syntax_input(0).is_none());
 let input=archive.syntax_input_checked(0,&||Ok(())).unwrap();let product=db.syntax_checked(&input).unwrap();let statements=product.statement_storage();assert!(statements.has_native_literal_syntax());assert!(statements.parsed().diagnostics.is_empty());let [dm_syntax::Statement{kind:dm_syntax::StatementKind::Return(Some(dm_syntax::Expr{kind:dm_syntax::ExprKind::Literal(value),..})),..}]=statements.parsed().statements.as_slice()else{panic!("actual issued return literal required")};assert_eq!(value.as_str().len(),300*1024+2);assert_eq!(computed(&db),1);
 let repeated=db.syntax_checked(&input).unwrap();assert!(Arc::ptr_eq(&product,&repeated));assert_eq!(computed(&db),1,"same actual product, no fallback parser");
 drop(repeated);drop(product);drop(input);drop(archive);drop(front);drop(source);db.begin_revision();
 let settings=Arc::clone(&db)as Arc<dyn SettingExpressionQueries>;settings.with_declaration_admission(&mut|a|{let all=a.reserve(128*1024*1024-dm_syntax::SettingChargeCounter::root_allocation_bytes()).map_err(BodySyntaxFailure::Operational)?;drop(all);Ok(())}).unwrap();
}
