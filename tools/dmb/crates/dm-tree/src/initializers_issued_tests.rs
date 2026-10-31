use super::*;
use std::path::Path;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source { fn read(&self,_:&Path)->Result<String,String>{Ok(self.0.into())} }
fn frontend()->crate::frontend::ColdFrontend {
 crate::frontend::build(Path::new("issued-startup.dme"),&Source("var/a=1\n/proc/work()\n    var/static/local=2\n    return local\nvar/b=3\n/proc/empty()\n    return 1\n"),&Default::default(),1).unwrap()
}
#[test]
fn issued_initializer_plan_keeps_same_original_rows_and_exact_snapshot_without_detached_authority(){
 let front=frontend();let arena=crate::frontend::BodyArena::new(&front);let roster=front.callable_roster().unwrap();
 let receipts:Vec<_>=front.bodies.iter().map(|body|{
  let identity=roster.identity_for_member(body.member).unwrap();
  let receipt=arena.with_parsed(body,|parsed|parsed.capture_stored_declarations(identity)).unwrap().unwrap();
  (body.declaration,receipt)
 }).collect();
 let expected=finish_declaration_draft(capture_declaration_draft(&front.snapshot,&front.emission_order).unwrap(),receipts.iter().map(|(o,p)|(*o,p.plan()))).unwrap();
 let issued=finish_declaration_draft_issued(capture_declaration_draft(&front.snapshot,&front.emission_order).unwrap(),&front,receipts.iter().map(|(o,p)|(*o,p))).unwrap();
 assert_eq!(issued.plan().writes,expected.writes);assert_eq!(issued.plan().origins,expected.origins);assert_eq!(issued.plan().identity,expected.identity);
 assert!(issued.matches_snapshot(&front.snapshot));assert!(issued.matches_frontend(&front));
 let foreign=frontend();assert_eq!(foreign.snapshot.tree.identity(),front.snapshot.tree.identity());
 assert_eq!(issued.matches_snapshot(&foreign.snapshot),Arc::ptr_eq(&front.snapshot.tree,&foreign.snapshot.tree)&&Arc::ptr_eq(&front.snapshot.occurrences,&foreign.snapshot.occurrences));
 let mut detached=issued.plan().clone();Arc::make_mut(&mut detached.writes)[0].value=InitializerValue::NoAuthoredValue;
 assert_ne!(detached.writes,issued.plan().writes,"a public cloned plan cannot mutate the sealed producer result");
 assert!(issued.plan().origins.iter().any(|origin|matches!(origin.kind,InitializerOriginKind::ProcedureStatic{..})));
 let duplicate=finish_declaration_draft_issued(capture_declaration_draft(&front.snapshot,&front.emission_order).unwrap(),&front,receipts.iter().flat_map(|(o,p)|[(*o,p),(*o,p)]));
 assert!(duplicate.is_err(),"same original merge validation still rejects duplicate static producers");
}
#[test]
fn issued_initializer_spelling_overlay_retains_original_dictionary_and_rows_without_new_roster(){
 let front=frontend();let receipt=static_receipt(&front);let mut issued=finish_declaration_draft_issued(capture_declaration_draft(&front.snapshot,&front.emission_order).unwrap(),&front,[(front.bodies[0].declaration,&receipt)]).unwrap();
 let writes=Arc::clone(&issued.plan().writes);let origins=Arc::clone(&issued.plan().origins);let symbols=Arc::clone(&issued.plan().symbols);
 let mut overlay=dm_ir::SymbolTable::overlay(Arc::clone(&symbols));let added=overlay.intern("asset.png").unwrap();
 issued.with_symbol_overlay(Arc::new(overlay)).unwrap();assert_eq!(issued.plan().symbols.text(added),Some("asset.png"));
 assert!(Arc::ptr_eq(&writes,&issued.plan().writes)&&Arc::ptr_eq(&origins,&issued.plan().origins));
 let copied=Arc::new((*issued.plan().symbols).clone());assert!(issued.with_symbol_overlay(copied).is_err(),"an equal detached dictionary is not an original-parent overlay");
 assert_eq!(issued.plan().symbols.text(added),Some("asset.png"));assert!(issued.matches_snapshot(&front.snapshot));assert!(issued.matches_frontend(&front));
}

struct Dynamic(String);
impl dm_preprocess::SourceProvider for Dynamic {fn read(&self,_:&Path)->Result<String,String>{Ok(self.0.clone())}}
fn static_receipt(front:&crate::frontend::ColdFrontend)->Arc<crate::frontend::IssuedStaticPlan>{
 let body=&front.bodies[0];let identity=front.callable_roster().unwrap().identity_for_member(body.member).unwrap();
 crate::frontend::BodyArena::new(front).with_parsed(body,|parsed|parsed.capture_stored_declarations(identity)).unwrap().unwrap()
}
#[test]
fn issued_initializer_rejects_foreign_static_receipt_before_original_complete_plan_mint(){
 let first=frontend();
 let other=crate::frontend::build(Path::new("issued-startup.dme"),&Dynamic("var/a=1\n/proc/work()\n    var/static/local=9\n    return local\nvar/b=3\n/proc/empty()\n    return 1\n".into()),&Default::default(),1).unwrap();
 let foreign=static_receipt(&other);let occurrence=first.bodies[0].declaration;
 assert_eq!(foreign.plan().procedure,static_receipt(&first).plan().procedure);
 // Old compatibility intentionally accepts caller-supplied plain semantics.
 assert!(finish_declaration_draft(capture_declaration_draft(&first.snapshot,&first.emission_order).unwrap(),[(occurrence,foreign.plan())]).is_ok());
 let failed=finish_declaration_draft_issued(capture_declaration_draft(&first.snapshot,&first.emission_order).unwrap(),&first,[(occurrence,&foreign)]);
 assert!(failed.is_err(),"a sealed static from a different current source is not source authority for this draft");
 assert!(finish_declaration_draft_issued(capture_declaration_draft(&first.snapshot,&first.emission_order).unwrap(),&first,std::iter::empty()).is_err(),"a complete source receipt cannot omit a real stored-declaration candidate");
 let current=static_receipt(&first);assert!(finish_declaration_draft_issued(capture_declaration_draft(&first.snapshot,&first.emission_order).unwrap(),&first,[(occurrence,&current)]).is_ok());
}
#[test]
fn issued_initializer_rejects_actual_warm_same_length_body_edit_with_reused_semantic_tree(){
 let mut state=crate::frontend::RetainedSemanticTree::default();let executor=dm_exec::BuildExecutor::new(1).unwrap();
 let build=|state:&mut crate::frontend::RetainedSemanticTree,value|crate::frontend::build_with_executor_and_semantic_state(
  Path::new("warm-issued-startup.dme"),&Dynamic(format!("var/a=1\n/proc/work()\n    var/static/local={value}\n    return local\nvar/b=3\n")),&Default::default(),
  crate::frontend::FrontendConfig{workers:1,engine:None,observer:None},None,&executor,Some(state)).unwrap();
 let first=build(&mut state,2);let old=static_receipt(&first);
 let issued=finish_declaration_draft_issued(capture_declaration_draft(&first.snapshot,&first.emission_order).unwrap(),&first,[(first.bodies[0].declaration,&old)]).unwrap();
 let current=build(&mut state,9);
 assert!(Arc::ptr_eq(&first.snapshot.tree,&current.snapshot.tree),"real body-only edit must exercise shared semantic owner");
 // The actual frontend may reissue source occurrences even at identical byte width.
 // Body-code/frame proof is required independently of that additional protection.
 assert_eq!(first.bodies[0].expanded_span,current.bodies[0].expanded_span);
 assert!(!Arc::ptr_eq(first.body_code(&first.bodies[0]).unwrap().identity(),current.body_code(&current.bodies[0]).unwrap().identity()));
 assert_eq!(issued.matches_snapshot(&current.snapshot),Arc::ptr_eq(&first.snapshot.occurrences,&current.snapshot.occurrences));
 assert!(!issued.matches_frontend(&current),"actual issued body/code frame is additionally required");
 assert!(finish_declaration_draft_issued(capture_declaration_draft(&current.snapshot,&current.emission_order).unwrap(),&current,[(current.bodies[0].declaration,&old)]).is_err());
 let fresh=static_receipt(&current);let freshplan=finish_declaration_draft_issued(capture_declaration_draft(&current.snapshot,&current.emission_order).unwrap(),&current,[(current.bodies[0].declaration,&fresh)]).unwrap();
 assert!(freshplan.matches_frontend(&current));assert_ne!(freshplan.plan().writes,issued.plan().writes);
}

#[test]
fn issued_initializer_weak_frame_and_static_backing_remains_in_census_after_source_drop(){
 let (issued,before)={
  let front=frontend();let receipt=static_receipt(&front);
  let issued=finish_declaration_draft_issued(capture_declaration_draft(&front.snapshot,&front.emission_order).unwrap(),&front,[(front.bodies[0].declaration,&receipt)]).unwrap();
  let mut regions=Vec::new();issued.visit_frame_storage(|pointer,payload,capacity|regions.push((pointer,payload,capacity)));
  assert!(regions.iter().all(|(_,payload,capacity)|*capacity>0&&payload==capacity));
  let ordinal=issued.plan().origins.iter().position(|origin|matches!(origin.kind,InitializerOriginKind::ProcedureStatic{..})).unwrap();
  assert!(Arc::ptr_eq(&issued.static_receipt(ordinal).unwrap(),&receipt));
  (issued,regions)
 };
 let mut after=Vec::new();issued.visit_frame_storage(|pointer,payload,capacity|after.push((pointer,payload,capacity)));
 assert_eq!(before.iter().map(|(pointer,_,capacity)|(*pointer,*capacity)).collect::<Vec<_>>(),after.iter().map(|(pointer,_,capacity)|(*pointer,*capacity)).collect::<Vec<_>>());
 assert!(after.iter().all(|(_,payload,capacity)|*payload==0&&*capacity>0),"weak-only actual backing is inventoried without reading dropped owners");
 let ordinal=issued.plan().origins.iter().position(|origin|matches!(origin.kind,InitializerOriginKind::ProcedureStatic{..})).unwrap();
 assert!(issued.static_receipt(ordinal).is_none(),"an unavailable producer is not reconstructed from old row meaning");
}

#[test]
fn issued_initializer_requires_actual_current_source_mapping_before_plan_mint(){
 let mut front=frontend();let receipt=static_receipt(&front);
 assert!(!front.plan.regions.is_empty());front.plan.regions.clear();
 assert!(front.source_export_mapping().is_none(),"publicly modified source planning must lose original mapping authority");
 assert!(finish_declaration_draft_issued(capture_declaration_draft(&front.snapshot,&front.emission_order).unwrap(),&front,[(front.bodies[0].declaration,&receipt)]).is_err());
}
