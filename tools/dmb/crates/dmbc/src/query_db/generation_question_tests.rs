//! Actual missing-output native preparation, common QueryDb and current originals.
use super::*;
#[path="../../../dm-analysis/examples/support/reference_hierarchy.rs"]mod generation_metadata_hierarchy;

use crate::input_snapshot::{RecordingInputs,FileSystemInputs,GenerationBootstrapPreparation,GenerationQuestionBootstrap};
use dm_tree::frontend::{FrontendConfig,SettingExpressionQueries,BodySyntaxFailure};
use std::{io,path::PathBuf,sync::Arc};
fn fixture()->(PathBuf,Arc<RecordingInputs<FileSystemInputs>>,Arc<QueryDb>,Arc<GenerationQuestionBootstrap>){
 let root=crate::test_scratch::dir("generation-native-questions");std::fs::create_dir_all(&root).unwrap();
 let project=root.join("main.dme");
 std::fs::write(&project,"#include \"code/engine/_generated/reads.dm\"\n#include \"code/engine/_generated/tracked_lists.dm\"\n/datum/base\n    var/list/items\n/datum/base/child\n/proc/probe()\n    return \"native [1 + 2]\"\n/proc/unused()\n    return \"unused [3]\"\n").unwrap();
 let inputs=Arc::new(RecordingInputs::new(FileSystemInputs,0));let db=Arc::new(QueryDb::default());let control:Arc<dyn SettingExpressionQueries>=db.clone();let executor=dm_exec::BuildExecutor::new(1).unwrap();
 let parsed=std::cell::Cell::new(0);let observer=|event:dm_tree::frontend::FrontendProgress|{if event.stage==dm_tree::frontend::FrontendStage::DeclarationParsing&&event.kind==dm_tree::frontend::ProgressKind::Completed{parsed.set(parsed.get()+1)}};
 let config=FrontendConfig{workers:1,engine:None,observer:Some(&observer)};
 let frame=match inputs.prepare_generation_question_bootstrap(&project,&Default::default(),config,&executor,&control,&mut |_|Ok(())).unwrap(){GenerationBootstrapPreparation::MissingOutputs(frame)=>frame,GenerationBootstrapPreparation::NotNeeded=>panic!("real registered output negatives require purpose-specific preparation")};
 assert_eq!(parsed.get(),1);
 let frame=Arc::new(frame.into_native_questions(&inputs,config,&executor,&db).unwrap());assert_eq!(parsed.get(),1,"assembly consumes existing native declarations without a second parse");
 (root,inputs,db,frame)
}
fn body_text(body:dm_tree::frontend::GenerationBodyLoan<'_>)->String{let dm_syntax::StatementKind::Return(Some(dm_syntax::Expr{kind:dm_syntax::ExprKind::Literal(text),..}))=&body.statements().parsed().statements[0].kind else{panic!("actual native original return")};text.as_str().to_owned()}
#[test]fn genuine_missing_outputs_resolve_inherited_native_declarations_and_share_same_kind4_body_without_full_frontend(){
 let(_,inputs,db,frame)=fixture();assert_eq!(db.db.stats(Kind(4)).computed,0);
 let result:Result<(),()>=frame.with_questions(&inputs,|q|{assert!(q.omissions().next().is_some());assert_eq!(q.original_sources().count(),1);assert_eq!(q.source_file_count(),1,"omitted includes have no empty source rows or owners");let child=q.tree().lookup_type(dm_ir::SymbolId::of("/datum/base/child")).unwrap();let member=q.tree().resolve(child,dm_ir::SymbolId::of("items"),dm_tree::MemberKind::Var).unwrap();assert_eq!(q.tree().member(member).unwrap().metadata.declared_type(),Some(dm_ir::SymbolId::of("/list")));assert_eq!(q.bodies().len(),2);Ok(Ok(()))}).unwrap();result.unwrap();
 let text:Result<String,()>=frame.with_questions(&inputs,|q|Ok(Ok(q.with_body_checked_using(0,|input,host|host.syntax_checked(input),|loan|Ok(body_text(loan))).unwrap()))).unwrap();assert_eq!(text.unwrap(),"\"native [1 + 2]\"");assert_eq!(db.db.stats(Kind(4)).computed,1);
 let _:Result<(),()>=frame.with_questions(&inputs,|q|{q.with_body_checked_using(0,|input,host|host.syntax_checked(input),|_|Ok(())).unwrap();Ok(Ok(()))}).unwrap();assert_eq!(db.db.stats(Kind(4)).computed,1,"second actual body stays unparsed and the first uses same existing query value");
}
#[test]fn actual_generation_body_context_records_dynamic_kind4_edge_and_foreign_returned_owner_refuses(){
 const SOURCE:Kind=Kind(241);const PARENT:Kind=Kind(242);
 let(_,inputs,db,frame)=fixture();db.db.define_input(SOURCE,"generation-current-question-frame");let source=Key::new(SOURCE,1);let parent=Key::new(PARENT,1);db.db.set_input(source,Arc::downgrade(&frame),1);
 let source_inputs=Arc::clone(&inputs);
 let child=Arc::new(std::sync::atomic::AtomicU64::new(0));let actual=child.clone();
 db.db.define(PARENT,"generation-observed-body",move|ctx,_|{let weak=ctx.input::<std::sync::Weak<GenerationQuestionBootstrap>>(source)?;let frame=weak.upgrade().ok_or(QueryError::Missing(parent))?;let value=frame.with_questions(&inputs,|q|{
  let text=q.with_body_checked_using(0,|input,_|{actual.store(input.key(),std::sync::atomic::Ordering::Relaxed);body_syntax::obtain(ctx,input)},|loan|Ok(body_text(loan))).map_err(|failure|match failure{BodySyntaxFailure::Operational(actual)=>actual,BodySyntaxFailure::Syntax(d)=>io::Error::new(io::ErrorKind::InvalidData,d.message)})?;Ok(Ok::<_,()>(text))
 }).map_err(|e|QueryError::operational(parent,e))?.map_err(|_|QueryError::Missing(parent))?;let hash=dm_query::hash_bytes(value.as_bytes());Ok(dm_query::Outcome::new(value,hash,1024))});
 let first=db.db.get::<String>(parent,Arc::new(())).unwrap();let child=Key::new(Kind(4),child.load(std::sync::atomic::Ordering::Relaxed).into());assert!(db.db.dependants(&[child]).contains(&parent));let warm=db.db.get::<String>(parent,Arc::new(())).unwrap();assert!(Arc::ptr_eq(&first,&warm));assert_eq!(db.db.stats(Kind(4)).computed,1);

 let(_,other_inputs,_other_db,other)=fixture();let foreign=std::cell::RefCell::new(None);
 let _:Result<(),()>=other.with_questions(&other_inputs,|q|{q.with_body_checked_using(0,|input,host|{let value=host.syntax_checked(input)?;*foreign.borrow_mut()=Some(Arc::clone(&value));Ok(value)},|_|Ok(())).unwrap();Ok(Ok(()))}).unwrap();
 let foreign=foreign.into_inner().unwrap(); // The original frame still requires its own recorder; obtain cannot substitute
 // a successfully parsed body from a different genuine native input.
 let result:Result<(),()>=frame.with_questions(&source_inputs,|q|{let error=q.with_body_checked_using(0,|_,_|Ok(Arc::clone(&foreign)),|_|Ok(())).unwrap_err();assert!(matches!(error,BodySyntaxFailure::Syntax(ref d)if d.message.contains("foreign parser issuance")));Ok(Ok(()))}).unwrap();result.unwrap();
}
#[test]fn generation_question_current_recorder_negative_and_actual_body_io_cancel_quota_recover(){
 let(root,inputs,db,frame)=fixture();let other=RecordingInputs::new(FileSystemInputs,0);assert!(frame.with_questions(&other,|_|Ok(Ok::<_,()>(()))).is_err());
 let fail=db.fail_body_syntax_after_for_test(0,io::Error::from_raw_os_error(1450));let error=frame.with_questions(&inputs,|q|{q.with_body_checked_using(0,|input,host|host.syntax_checked(input),|_|Ok(())).map_err(|e|match e{BodySyntaxFailure::Operational(actual)=>actual,BodySyntaxFailure::Syntax(d)=>io::Error::new(io::ErrorKind::InvalidData,d.message)})?;Ok(Ok::<_,()>(()))}).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));drop(fail);
 let token=crate::daemon::control::Cancellation::default();let bound=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(frame.with_questions(&inputs,|_|Ok(Ok::<_,()>(()))).unwrap_err().kind(),io::ErrorKind::Interrupted);drop(bound);
 let counter=body_syntax_counter_for_test(&db);let poll=||Ok(());let permit=dm_syntax::SettingAdmission::new(counter,body_syntax_budget_for_test(),&poll);let used=counter.load(std::sync::atomic::Ordering::Acquire);let held=permit.reserve(body_syntax_budget_for_test()-used).unwrap();
 let error=frame.with_questions(&inputs,|q|{q.with_body_checked_using(0,|input,host|host.syntax_checked(input),|_|Ok(())).map_err(|e|match e{BodySyntaxFailure::Operational(actual)=>actual,BodySyntaxFailure::Syntax(d)=>io::Error::new(io::ErrorKind::InvalidData,d.message)})?;Ok(Ok::<_,()>(()))}).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);drop(held);drop(permit);
 let _:Result<(),()>=frame.with_questions(&inputs,|q|{q.with_body_checked_using(0,|input,host|host.syntax_checked(input),|_|Ok(())).unwrap();Ok(Ok(()))}).unwrap();assert_eq!(db.db.stats(Kind(4)).computed,1);
 let output=root.join("code/engine/_generated/reads.dm");std::fs::create_dir_all(output.parent().unwrap()).unwrap();std::fs::write(output,"// actual generation output installed after loan retirement\n").unwrap();assert_eq!(frame.with_questions(&inputs,|_|Ok(Ok::<_,()>(()))).unwrap_err().kind(),io::ErrorKind::InvalidData,"the recorded negative cannot survive actual writes");
}

#[test]fn generation_question_selection_refuses_unprepared_role_and_all_present_declines_before_second_parse(){
 let(root,_inputs,db,_frame)=fixture();let executor=dm_exec::BuildExecutor::new(1).unwrap();let control:Arc<dyn SettingExpressionQueries>=db.clone();let config=FrontendConfig{workers:1,engine:None,observer:None};
 let inputs=RecordingInputs::new(FileSystemInputs,0);let raw=match inputs.prepare_generation_bootstrap(&root.join("main.dme"),&Default::default(),config,&executor,&control,&mut |_|Ok(())).unwrap(){GenerationBootstrapPreparation::MissingOutputs(frame)=>frame,_=>panic!("actual absent outputs")};assert!(raw.into_native_questions(&inputs,config,&executor,&db).is_err(),"raw declaration role cannot be upgraded after parse");
 for relative in QueryDb::generation_dm_outputs(){let target=root.join(relative);std::fs::create_dir_all(target.parent().unwrap()).unwrap();std::fs::write(target,"// genuine output on disk\n").unwrap();}
 let count=std::cell::Cell::new(0);let observe=|event:dm_tree::frontend::FrontendProgress|{if event.stage==dm_tree::frontend::FrontendStage::DeclarationParsing{count.set(count.get()+1)}};let config=FrontendConfig{workers:1,engine:None,observer:Some(&observe)};
 assert!(matches!(RecordingInputs::new(FileSystemInputs,0).prepare_generation_question_bootstrap(&root.join("main.dme"),&Default::default(),config,&executor,&control,&mut |_|Ok(())).unwrap(),GenerationBootstrapPreparation::NotNeeded));assert_eq!(count.get(),0,"existing full frontend is required; the bootstrap does not parse or manufacture a complete frame");
}

#[test]fn generation_original_qualifiers_definition_points_and_typed_local_parameter_views_are_same_native_issuers(){
 let root=crate::test_scratch::dir("generation-original-question-metadata");std::fs::create_dir_all(&root).unwrap();let project=root.join("main.dme");
 std::fs::write(&project,"#include \"code/engine/_generated/tracked_lists.dm\"\n/datum/base\n    var/list/items\n    var/SpacemanDMM_private/list/guarded\n/datum/base/child\n/proc/probe(datum/base/arg)\n    return 1\n    var/datum/base/local = arg\n").unwrap();
 let inputs=RecordingInputs::new(FileSystemInputs,0);let db=Arc::new(QueryDb::default());let control:Arc<dyn SettingExpressionQueries>=db.clone();let executor=dm_exec::BuildExecutor::new(1).unwrap();let seed=generation_metadata_hierarchy::seed();let config=FrontendConfig{workers:1,engine:Some(&seed),observer:None};
 let frame=match inputs.prepare_generation_question_bootstrap(&project,&Default::default(),config,&executor,&control,&mut |_|Ok(())).unwrap(){GenerationBootstrapPreparation::MissingOutputs(frame)=>frame,_=>panic!("real missing generated list output")};let frame=frame.into_native_questions(&inputs,config,&executor,&db).unwrap();
 let _:Result<(),()>=frame.with_questions(&inputs,|q|{let profile=q.tree().checker_builtin_profile().unwrap();let proof=q.tree().validated_checker_profile(profile).unwrap();let mut seen=false;
 q.visit_definition_points(&mut||Ok::<_,String>(()),&mut|point|{assert_eq!(point.path,project);if point.name=="guarded"{let props=q.variable_properties_original_at(point.member,point.ordinal,profile,&proof)?;assert_eq!(props.qualifiers,dm_syntax::CHECKER_VAR_PRIVATE);assert_eq!(props.declared_hint(),Some("/list"));assert_eq!(point.line,4);seen=true;}Ok::<_,String>(())}).unwrap();assert!(seen);assert_eq!(db.db.stats(Kind(4)).computed,0,"original metadata/qualifiers never demand a body");
 q.with_body_checked_using(0,|input,host|host.syntax_checked(input),|loan|{let params=loan.source_parameters().unwrap();let rows=params.entries().unwrap();assert_eq!(rows.len(),1);assert_eq!(params.name(&rows[0]).unwrap(),"arg");assert_eq!(params.type_path(&rows[0]).unwrap().as_deref(),Some("/datum/base"));let header=loan.statements().parsed().statements[1].header_span;let locals=loan.source_locals().unwrap();let rows=locals.in_span(header).unwrap();assert_eq!(rows.len(),1);assert_eq!(locals.name(&rows[0]).unwrap(),"local");assert_eq!(locals.type_path(&rows[0]).unwrap().as_deref(),Some("/datum/base"));Ok(())}).unwrap();Ok(Ok(()))}).unwrap();assert_eq!(db.db.stats(Kind(4)).computed,1);
}

#[test]fn generation_tracked_metadata_has_same_counter_owner_capacity_census_and_physical_drop(){
 let (_root,inputs,db,frame)=fixture();
 let counter=Arc::clone(body_syntax_counter_for_test(&db));
 let used=counter.load(std::sync::atomic::Ordering::Acquire);
 let charge=frame.with_questions(&inputs,|q|{let mut bytes=0usize;let mut rows=0usize;q.visit_generation_metadata(|_,size|{bytes=bytes.checked_add(size).unwrap();rows+=1});let charge=q.generation_metadata_charge();assert!(q.generation_definition_lookup_is_binary(),"actual native recipe order uses O(log bodies) lookups");assert!(charge>=bytes&&bytes>0);assert!(rows>=4);assert!(used>=charge);let mut definitions=0;q.visit_definition_points(&mut||Ok::<_,String>(()),&mut|_|{definitions+=1;Ok::<_,String>(())}).unwrap();assert!(definitions>0);Ok(Ok::<_,()>(charge))}).unwrap().unwrap();
 assert_eq!(counter.load(std::sync::atomic::Ordering::Acquire),used,"borrowed metadata does not mint another owner or roster");
 drop(frame);let after=counter.load(std::sync::atomic::Ordering::Acquire);assert!(used-after>=charge,"span Vec drops before same-counter metadata lease credit");
}

#[test]fn generation_retained_metadata_denies_before_projection_and_fresh_same_recorder_recovers(){
 let(root,inputs,db,old)=fixture();drop(old);
 let project=root.join("main.dme");let executor=dm_exec::BuildExecutor::new(1).unwrap();let control:Arc<dyn SettingExpressionQueries>=db.clone();let config=FrontendConfig{workers:1,engine:None,observer:None};
 let prepared=match inputs.prepare_generation_question_bootstrap(&project,&Default::default(),config,&executor,&control,&mut |_|Ok(())).unwrap(){GenerationBootstrapPreparation::MissingOutputs(frame)=>frame,_=>panic!("actual output still absent")};
 let counter=body_syntax_counter_for_test(&db);let poll=||Ok(());let admission=dm_syntax::SettingAdmission::new(counter,body_syntax_budget_for_test(),&poll);let before=counter.load(std::sync::atomic::Ordering::Acquire);let held=admission.reserve(body_syntax_budget_for_test()-before).unwrap();
 match prepared.into_native_questions(&inputs,config,&executor,&db){Err(crate::input_snapshot::GenerationBootstrapFailure::Operational(actual))=>assert_eq!(actual.kind(),io::ErrorKind::OutOfMemory),_=>panic!("new retained span reservation must fail before projection/assembly")}
 drop(held);drop(admission);
 let prepared=match inputs.prepare_generation_question_bootstrap(&project,&Default::default(),config,&executor,&control,&mut |_|Ok(())).unwrap(){GenerationBootstrapPreparation::MissingOutputs(frame)=>frame,_=>panic!("same real negatives")};
 let frame=prepared.into_native_questions(&inputs,config,&executor,&db).unwrap();let _:Result<(),()>=frame.with_questions(&inputs,|q|{assert!(q.generation_metadata_charge()>0);Ok(Ok(()))}).unwrap();assert_eq!(db.db.stats(Kind(4)).computed,0);
}
