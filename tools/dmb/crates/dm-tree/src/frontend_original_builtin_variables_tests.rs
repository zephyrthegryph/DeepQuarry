//! Actual original diagnostic builder: fixed builtin declarations remain DATA.
use super::*;
use dm_ir::{SymbolId,ResolveQuery as Q,ResolvedMeaning as M,Resolver};
struct Source{raw:Vec<u8>,acquired:dm_preprocess::AcquiredSource,environment:dm_preprocess::InitialEnvironment}
impl dm_preprocess::SourceProvider for Source{
 fn initial_environment(&self)->dm_preprocess::InitialEnvironment{self.environment}
 fn read(&self,_:&std::path::Path)->Result<String,String>{Err("actual acquisition required".into())}
 fn acquired_source(&self,_:&std::path::Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(Some(self.acquired.clone()))}
 fn source_acquisition(&self,_:&std::path::Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{self.acquired.lease().source_text().same_view(text).then(||self.acquired.clone())}
 fn original_raw_source_open_admitted(&self,_:&std::path::Path,_:usize,work:&dyn dm_preprocess::source_arena_credit::SourceArenaWork,after_open:&mut dyn FnMut()->std::io::Result<dm_preprocess::OriginalRawOpenDecision>,_:&mut dyn FnMut(usize)->std::io::Result<()>,before_decode:&mut dyn FnMut(dm_preprocess::OriginalRawAllocationPlan<'_>)->std::io::Result<()>,acquired:&mut dyn FnMut(&dm_preprocess::SourceAcquisitionLease)->std::io::Result<()>)->std::io::Result<dm_preprocess::OriginalRawReadOutcome>{
  work.checkpoint()?;
  if after_open()?==dm_preprocess::OriginalRawOpenDecision::Suppress{return Ok(dm_preprocess::OriginalRawReadOutcome::Suppressed)}
  before_decode(dm_preprocess::OriginalRawAllocationPlan::new(&[],0,0,0,false,false))?;
  acquired(self.acquired.lease())?;
  Ok(dm_preprocess::OriginalRawReadOutcome::Acquired(self.acquired.lease().clone()))
 }
 fn original_source_bytes<'a>(&'a self,lease:&'a dm_preprocess::SourceAcquisitionLease)->std::io::Result<Option<&'a[u8]>>{
  if !lease.same_binding(self.acquired.lease()){return Err(std::io::ErrorKind::InvalidInput.into())}
  Ok(Some(&self.raw))
 }
}
fn source(text:&str,environment:dm_preprocess::InitialEnvironment)->Source{Source{raw:text.as_bytes().to_vec(),acquired:dm_preprocess::AcquiredSource::from_original_bytes(text.as_bytes().to_vec(),()),environment}}
fn build(text:&str)->DiagnosticFrontend{
 let test_original_host=crate::frontend::declaration_checked_tests::original_test_host();
 build_using(text,&test_original_host)
}
fn build_using(text:&str,test_original_host:&std::sync::Arc<SettingExpressionQueriesDyn>)->DiagnosticFrontend{
 let source=source(text,dm_preprocess::InitialEnvironment::OriginalChecker0290);let seed=crate::checker_builtins::original_analysis_seed().unwrap();assert!(seed.frontend_seed().fields.is_empty());assert!(seed.frontend_seed().intrinsics.is_empty());let executor=dm_exec::BuildExecutor::new(1).unwrap();let mut state=RetainedSemanticTree::new();
 super::super::build_for_checker_diagnostics_with_state_checked(std::path::Path::new("builtin-vars.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,Some(&mut state),test_original_host).unwrap()
}
type SettingExpressionQueriesDyn = dyn crate::frontend::SettingExpressionQueries;

#[test]
fn original_compiled_source_body_keeps_assign_into_and_float_mod_assign() {
    use crate::frontend::{BodySyntax, BodySyntaxFailure, BodySyntaxInput, BodySyntaxQueries};
    use dm_syntax::{ExprKind, StatementKind};
    use std::sync::Arc;
    #[derive(Debug)]
    struct BodyHost(Arc<SettingExpressionQueriesDyn>);
    impl BodySyntaxQueries for BodyHost {
        fn syntax(&self, input: &Arc<BodySyntaxInput>) -> Result<Arc<BodySyntax>, crate::frontend::Diagnostic> {
            input.parse().map(Arc::new)
        }

        fn syntax_checked(&self, input: &Arc<BodySyntaxInput>) -> Result<Arc<BodySyntax>, BodySyntaxFailure> {
            let mut result = None;
            self.0.with_declaration_admission(&mut |admission| {
                result = Some(input.parse_with_setting_admission(admission)?);
                Ok(())
            })?;
            Ok(Arc::new(result.expect("actual native body result")))
        }
    }
    let host = crate::frontend::declaration_checked_tests::original_test_host();
    let front = build_using(concat!(
        "/proc/assignment_probe(image/left, image/right, value, extra)\n",
        "    left.dir:=right.dir %%= value + extra\n",
        "    left.dir%%=value\n",
        "    return (left.dir %%= right.dir := value)\n",
    ), &host).with_body_queries(Arc::new(BodyHost(host))).unwrap();
    let view = front.source_view().unwrap();
    view.require_original_analysis_seed().unwrap();
    assert!(view.receipt().errors().is_empty(), "{:?}", view.receipt().errors());
    let archive = view.archive();
    let ordinal = archive.occurrences().iter().position(|body| {
        archive.callables().identity_for_member(body.member)
            .is_some_and(|identity| identity.name == SymbolId::of("assignment_probe"))
    }).unwrap();
    let body = archive.parse_checked(ordinal).unwrap();
    assert!(body.belongs_to(archive));
    assert!(std::ptr::eq(body.occurrence(), &archive.occurrences()[ordinal]));
    assert!(body.statement_body().original_literal_syntax_complete(),
        "{:?}", body.statement_body().parsed().diagnostics);

    let [into, float_mod, result] = body.statement_body().parsed().statements.as_slice()
    else { panic!("expected exact complete original statement roster") };
    let StatementKind::Assign { target, op, value } = &into.kind
    else { panic!("typed assign-into statement") };
    assert_eq!(op, ":=");
    assert!(matches!(&target.kind, ExprKind::Member { selector, via_colon: false, .. } if selector == "dir"));
    let ExprKind::Binary { op, lhs, rhs } = &value.kind
    else { panic!("assignment binds on the right") };
    assert_eq!(op, "%%=");
    assert!(matches!(&lhs.kind, ExprKind::Member { selector, .. } if selector == "dir"));
    assert!(matches!(&rhs.kind, ExprKind::Binary { op, .. } if op == "+"));

    assert!(matches!(&float_mod.kind, StatementKind::Assign { op, .. } if op == "%%="));
    let StatementKind::Return(Some(group)) = &result.kind
    else { panic!("original return expression") };
    let ExprKind::Group(expression) = &group.kind
    else { panic!("original grouped assignment expression") };
    let ExprKind::Binary { op, rhs, .. } = &expression.kind
    else { panic!("float-mod assignment in an expression") };
    assert_eq!(op, "%%=");
    assert!(matches!(&rhs.kind, ExprKind::Binary { op, .. } if op == ":="));
    for (statement, line) in [(into, 2), (float_mod, 3), (result, 4)] {
        assert_eq!(archive.original_policy_line(statement.span.start).unwrap().line, line);
    }
    drop(body);
    drop(view);
    assert!(front.try_into_compilable().is_err());
}

#[test]
fn original_assignment_syntax_does_not_expand_the_ordinary_expression_grammar() {
    for text in ["left.dir:=value", "left.dir%%=value"] {
        assert!(!dm_syntax::parse_expression(text).diagnostics.is_empty(), "{text}");
    }
}

fn own<'a>(tree:&'a crate::SemanticTree,owner:&str,name:&str)->&'a crate::MemberNode{tree.members().iter().find(|member|tree.type_node(member.owner).unwrap().path==SymbolId::of(owner)&&member.name==SymbolId::of(name)&&member.kind==crate::MemberKind::Var).unwrap()}
fn catalog(owner:&str,name:&str)->std::sync::Arc<dm_ir::DeclarationMeaning>{crate::checker_builtins::pinned_catalog().unwrap().declarations.iter().find(|row|row.owner==SymbolId::of(owner)&&row.name==SymbolId::of(name)&&row.kind==crate::MemberKind::Var).unwrap().metadata.clone()}
fn same_formal(actual:&dm_ir::DeclarationMeaning,base:&dm_ir::DeclarationMeaning){assert_eq!(actual.declared_type,base.declared_type);assert_eq!(actual.list_element_type,base.list_element_type);assert_eq!(actual.flags,base.flags);assert_eq!(actual.array,base.array);assert_eq!(actual.declared_initializer,base.declared_initializer);assert!(actual.inherited_opaque.is_none());assert!(actual.procedure.is_none());}
#[test]fn original_builtin_variable_overrides_use_real_catalog_metadata_and_actual_source_parent(){
 let front=build("/atom\n    name=\"own\"\n    alpha=12\n/datum\n    vars=null\n    type=/datum\n/obj/bridge_child\n    name=\"child\"\n");let view=front.source_view().unwrap();assert!(view.receipt().errors().is_empty());assert!(view.receipt().has_original_variable_declarations());let tree=view.tree();
 for(owner,name)in[("/atom","name"),("/atom","alpha"),("/datum","vars"),("/datum","type"),("/obj/bridge_child","name")]{let row=own(tree,owner,name);let base=catalog(if owner=="/obj/bridge_child"{"/atom"}else{owner},name);same_formal(&row.metadata,&base);assert!(row.metadata.initializer.is_some());}
 assert!(catalog("/datum","vars").declared_type.is_some());assert_ne!(catalog("/datum","type").flags,0);assert!(catalog("/atom","alpha").resolved_constant.is_some());assert!(catalog("/datum","type").resolved_constant.is_none());
 let atom=own(tree,"/atom","name");let child=own(tree,"/obj/bridge_child","name");let previous=tree.member(child.previous.expect("actual authored parent override must be retained")).unwrap();assert!(std::ptr::eq(previous,atom));assert!(atom.previous.is_none(),"catalog declarations have no fabricated source member id");assert_ne!(child.metadata.initializer,atom.metadata.initializer);
 assert!(tree.intrinsic_fields.is_empty());assert_eq!(tree.parent(tree.lookup_type(SymbolId::of("/obj/bridge_child")).unwrap()).map(|id|tree.type_node(id).unwrap().path),Some(SymbolId::of("/obj")));
 assert!(front.try_into_compilable().is_err());let front=build("/obj/bridge_only\n    name=\"inherited\"\n");let view=front.source_view().unwrap();let tree=view.tree();let base=catalog("/atom","name");let M::Member{owner,data,..}=Resolver::resolve(tree.as_ref(),Q::CheckerBuiltinVar{profile:crate::checker_builtins::pinned_catalog().unwrap().profile,owner:SymbolId::of("/obj/bridge_only"),name:SymbolId::of("name")})else{panic!("actual original builtin declaration lookup failed")};assert_eq!(owner,SymbolId::of("/atom"));assert!(std::sync::Arc::ptr_eq(&data,&base));let mut state=RetainedSemanticTree::new();assert!(front.try_into_compilable_retained(&mut state).is_err());
}
#[test]fn original_builtin_variable_bridge_does_not_accept_nonexistent_fields_or_ordinary_compiler_overrides(){
 let test_original_host=crate::frontend::declaration_checked_tests::original_test_host();

 let original=source("/obj/bridge_missing\n    __not_a_pinned_original_field=1\n",dm_preprocess::InitialEnvironment::OriginalChecker0290);let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();
 assert!(super::super::build_for_checker_diagnostics_with_state_checked(std::path::Path::new("missing.dme"),&original,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None,&test_original_host).is_err());
 for environment in [dm_preprocess::InitialEnvironment::Native5161687,dm_preprocess::InitialEnvironment::OriginalChecker0290]{let input=source("/obj/bridge_strict\n    name=\"strict must refuse without diagnostic permit\"\n",environment);assert!(super::super::build_with_executor(std::path::Path::new("strict.dme"),&input,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor).is_err());}
}

#[test]fn actual_macro_callable_policy_line_is_bound_without_certifying_a_byte_column(){
 let source="#define MAKE(T) ##T/proc/made() { return 1 }\nMAKE(/datum/line_only)\n";let front=build(source);let view=front.source_view().unwrap();let tree=view.tree();let member=tree.members().iter().enumerate().find_map(|(index,node)|(node.kind==crate::MemberKind::Proc&&node.name==SymbolId::of("made")).then_some(crate::MemberId(index as u32))).unwrap();let headers=view.archive().callable_header_source();let line=headers.reported_policy_line(member).unwrap();assert_eq!(line.line,2);assert!(line.path.ends_with("builtin-vars.dme"));let opening=headers.reported_span(member).unwrap();assert!(view.mapping().original_note_origin(opening.start).is_err(),"a line-only macro receipt must not gain physical byte/column authority");if let Ok(existing)=headers.reported_point(member){assert_eq!(existing.reported_coordinates().1,line.line,"an independently issued checker token point stays distinct from physical layout");}assert_eq!(view.archive().callable_header_policy_line(member).unwrap(),line);
 let foreign=build("/datum/other\n    proc/plain()\n        return 1\n");let other=foreign.source_view().unwrap();let bad=crate::MemberId(u32::MAX);assert!(other.archive().callable_header_source().reported_policy_line(bad).is_err());
}

#[test]fn actual_original_declaration_loan_survives_warm_reissue_but_cloned_seed_cannot_renew_it(){
 let test_original_host=crate::frontend::declaration_checked_tests::original_test_host();

 let input=source("/obj/warm_original_bridge\n    name=\"actual original declaration\"\n",dm_preprocess::InitialEnvironment::OriginalChecker0290);let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let mut state=RetainedSemanticTree::new();let project=std::path::Path::new("warm-original-bridge.dme");
 let first=std::sync::Arc::new(super::super::build_for_checker_diagnostics_with_state_checked(project,&input,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,Some(&mut state),&test_original_host).unwrap());first.source_view().unwrap().require_original_analysis_seed().unwrap();let tree=std::sync::Arc::clone(first.source_view().unwrap().tree());state.remember_analysis_frontend(project,&Default::default(),first).unwrap();
 let warm=super::super::build_for_checker_diagnostics_with_state_checked(project,&input,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,Some(&mut state),&test_original_host).unwrap();assert!(std::sync::Arc::ptr_eq(&tree,warm.source_view().unwrap().tree()));warm.source_view().unwrap().require_original_analysis_seed().unwrap();assert!(warm.try_into_compilable().is_err());
 let clone=seed.frontend_seed().clone();let foreign=super::super::build_for_checker_diagnostics_with_state_checked(project,&input,&Default::default(),FrontendConfig{workers:1,engine:Some(&clone),observer:None},None,&executor,Some(&mut state),&test_original_host);if let Ok(foreign)=foreign{assert!(foreign.source_view().unwrap().require_original_analysis_seed().is_err(),"equal seed data is not the actual singleton declaration-loan issuer");assert!(foreign.try_into_compilable().is_err());}
}

#[test]fn original_partial_diagnostic_warm_reissue_preserves_errors_and_refuses_compiler_promotion(){
 let test_original_host=crate::frontend::declaration_checked_tests::original_test_host();

 let text="/datum/warm_partial/proc/run()\n    return 1\n/datum/warm_partial/child/proc/run()\n    return 2\n";
 let input=source(text,dm_preprocess::InitialEnvironment::OriginalChecker0290);let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let mut state=RetainedSemanticTree::new();let project=std::path::Path::new("warm-partial.dme");
 let prepare=|input:&Source,state:&mut RetainedSemanticTree|super::super::build_for_checker_diagnostics_with_state_checked(project,input,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,Some(state),&test_original_host).unwrap();
 let first=Arc::new(prepare(&input,&mut state));let errors=first.receipt.errors().to_vec();assert!(!errors.is_empty());assert!(errors.iter().any(|error|matches!(error,crate::TreeError::InheritedDuplicate{kind:crate::MemberKind::Proc,..})));let profile=first.receipt.profile();let tree=Arc::clone(&first.inner.snapshot.tree);let error_ptr=first.receipt.errors().as_ptr();let original_receipt=Arc::as_ptr(&first.receipt)as usize;state.remember_analysis_frontend(project,&Default::default(),first).unwrap();
 for _ in 0..3{let hits=state.hits();let warm=prepare(&input,&mut state);assert!(Arc::ptr_eq(&tree,&warm.inner.snapshot.tree));assert_eq!(state.hits(),hits+1,"actual unchanged-program reuse must execute; this fixture has no external body query host");assert_eq!(warm.receipt.errors(),errors);assert_eq!(warm.receipt.errors().as_ptr(),error_ptr);assert_eq!(warm.receipt.profile(),profile);let mut base_seen=false;warm.receipt.visit_error_storage(|address,_,_|{base_seen|=address==original_receipt});assert!(base_seen,"shared original error owner participates in actual retention census");let warm=match warm.try_into_compilable(){Err(warm)=>warm,Ok(_)=>panic!("partial Original frontend promoted")};let mut compiler=RetainedSemanticTree::new();let warm=match warm.try_into_compilable_retained(&mut compiler){Err(warm)=>warm,Ok(_)=>panic!("partial Original frontend adopted compiler records")};assert!(compiler.snapshot_tree().is_none());state.remember_analysis_frontend(project,&Default::default(),Arc::new(warm)).unwrap();}
 let changed=source(&text.replace("return 2","return 3"),dm_preprocess::InitialEnvironment::OriginalChecker0290);let hits=state.hits();let edited=prepare(&changed,&mut state);assert_eq!(state.hits(),hits,"actual changed expanded source cannot take unchanged reuse");assert_ne!(edited.receipt.errors().as_ptr(),error_ptr,"edited source must issue actual new declaration errors");assert_eq!(edited.receipt.errors(),errors);assert!(edited.try_into_compilable().is_err());
 let clone=seed.frontend_seed().clone();let foreign=super::super::build_for_checker_diagnostics_with_state_checked(project,&input,&Default::default(),FrontendConfig{workers:1,engine:Some(&clone),observer:None},None,&executor,Some(&mut state),&test_original_host);if let Ok(foreign)=foreign{assert_ne!(foreign.receipt.errors().as_ptr(),error_ptr);assert!(foreign.source_view().unwrap().require_original_analysis_seed().is_err());assert!(foreign.try_into_compilable().is_err());}
}

#[test]fn original_include_root_retains_actual_child_type_block_after_previous_proc(){
 let test_original_host=crate::frontend::declaration_checked_tests::original_test_host();

 struct Included(std::collections::BTreeMap<std::path::PathBuf,dm_preprocess::AcquiredSource>);
 impl dm_preprocess::SourceProvider for Included{fn initial_environment(&self)->dm_preprocess::InitialEnvironment{dm_preprocess::InitialEnvironment::OriginalChecker0290}fn read(&self,_:&std::path::Path)->Result<String,String>{Err("actual original include acquisition required".into())}fn acquired_source(&self,path:&std::path::Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(self.0.get(path).cloned())}fn source_acquisition(&self,path:&std::path::Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{self.0.get(path).filter(|source|source.lease().source_text().same_view(text)).cloned()}}
 let source=Included(std::collections::BTreeMap::from([(std::path::PathBuf::from("include-root/project.dme"),dm_preprocess::AcquiredSource::from_original_bytes(include_bytes!("../../../fixtures/native-tracked-include-root/project.dme").to_vec(),())),(std::path::PathBuf::from("include-root/child.dm"),dm_preprocess::AcquiredSource::from_original_bytes(include_bytes!("../../../fixtures/native-tracked-include-root/child.dm").to_vec(),()))]));let seed=crate::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();let front=super::super::build_for_checker_diagnostics_with_state_checked(std::path::Path::new("include-root/project.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None,&test_original_host).unwrap();let view=front.source_view().unwrap();assert!(view.receipt().errors().is_empty());let tree=view.tree();assert!(tree.lookup_type(SymbolId::of("/datum/included_root")).is_some(),"actual included root type must not become the previous procedure's prefab expression");let field=own(tree,"/datum/included_root","value");assert!(field.metadata.initializer.is_some());let ordinal=view.archive().occurrences().iter().enumerate().find_map(|(ordinal,_)|view.archive().callables().identity(ordinal).filter(|identity|identity.name==SymbolId::of("before_include")).map(|_|ordinal)).unwrap();let body=view.archive().parse_checked(ordinal).unwrap();assert!(body.statement_body().original_literal_syntax_complete());assert_eq!(body.statement_body().parsed().statements.len(),1);assert!(matches!(body.statement_body().parsed().statements[0].kind,dm_syntax::StatementKind::Return(_)));
}

#[test]fn native_include_root_preserves_existing_braced_type_extension_after_previous_proc(){
 struct Included(std::collections::BTreeMap<std::path::PathBuf,dm_preprocess::AcquiredSource>);
 impl dm_preprocess::SourceProvider for Included{fn initial_environment(&self)->dm_preprocess::InitialEnvironment{dm_preprocess::InitialEnvironment::Native5161687}fn read(&self,_:&std::path::Path)->Result<String,String>{Err("actual original include acquisition required".into())}fn acquired_source(&self,path:&std::path::Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(self.0.get(path).cloned())}fn source_acquisition(&self,path:&std::path::Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{self.0.get(path).filter(|source|source.lease().source_text().same_view(text)).cloned()}}
 let source=Included(std::collections::BTreeMap::from([(std::path::PathBuf::from("native-include-root/project.dme"),dm_preprocess::AcquiredSource::from_original_bytes(include_bytes!("../../../fixtures/native-tracked-include-root-native-brace/project.dme").to_vec(),())),(std::path::PathBuf::from("native-include-root/child.dm"),dm_preprocess::AcquiredSource::from_original_bytes(include_bytes!("../../../fixtures/native-tracked-include-root-native-brace/child.dm").to_vec(),()))]));let executor=dm_exec::BuildExecutor::new(1).unwrap();
 // Genuine ordinary compiler entry and its existing default no-engine seed.
 // This case is a Native extension, never a successful pinned-old fixture.
 let front=super::super::build_with_executor(std::path::Path::new("native-include-root/project.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:None,observer:None},None,&executor).unwrap();assert_eq!(front.plan.initial_environment(),dm_preprocess::InitialEnvironment::Native5161687);let tree=&front.snapshot.tree;assert!(tree.lookup_type(SymbolId::of("/datum/included_root")).is_some(),"existing native included type declaration must not become an executable prefab");assert!(own(tree,"/datum/included_root","value").metadata.initializer.is_some());let archive=front.body_archive().unwrap();let ordinal=archive.occurrences().iter().enumerate().find_map(|(ordinal,_)|archive.callables().identity(ordinal).filter(|identity|identity.name==SymbolId::of("before_include")).map(|_|ordinal)).unwrap();let body=archive.parse_checked(ordinal).unwrap();assert!(body.statement_body().syntax_complete());assert_eq!(body.statement_body().parsed().statements.len(),1);assert!(matches!(body.statement_body().parsed().statements[0].kind,dm_syntax::StatementKind::Return(_)));
}
