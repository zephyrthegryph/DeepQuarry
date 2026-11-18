//! Actual original diagnostic builder: fixed builtin declarations remain DATA.
use super::*;
use dm_ir::{SymbolId,ResolveQuery as Q,ResolvedMeaning as M,Resolver};
pub(super) struct Source{raw:Vec<u8>,acquired:dm_preprocess::AcquiredSource,environment:dm_preprocess::InitialEnvironment}
impl dm_preprocess::SourceProvider for Source{
 fn initial_environment(&self)->dm_preprocess::InitialEnvironment{self.environment}
 fn original_batch_source(&self)->std::io::Result<Option<&(dyn dm_preprocess::SourceProvider+Sync)>>{Ok(Some(self))}
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
pub(super) fn source(text:&str,environment:dm_preprocess::InitialEnvironment)->Source{Source{raw:text.as_bytes().to_vec(),acquired:dm_preprocess::AcquiredSource::from_original_bytes(text.as_bytes().to_vec(),()),environment}}
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
fn actual_original_client_parent_accepts_profile_and_resolves_through_authored_parent() {
    let front = build("/client\n    parent_type = /datum\n");
    let view = front.source_view().unwrap();
    view.require_original_analysis_seed().unwrap();
    let tree = view.tree();
    let client = SymbolId::of("/client");
    let datum = SymbolId::of("/datum");
    let actual_parent = tree.parent(tree.lookup_type(client).unwrap()).unwrap();
    assert_eq!(tree.type_node(actual_parent).unwrap().path, datum);
    let profile = tree.checker_builtin_profile().expect("actual authored client parent preserves the pinned profile");
    assert_eq!(profile, crate::checker_builtins::original_analysis_seed().unwrap().profile());
    let actual = Resolver::resolve(tree.as_ref(), Q::CheckerIntrinsicCallable {
        profile, owner: client, name: SymbolId::of("Read"), verb: false,
    });
    assert!(matches!(actual, M::Presence(true)), "{actual:?}");
}

#[derive(Debug)]
struct BodyHost(std::sync::Arc<SettingExpressionQueriesDyn>);
impl crate::frontend::BodySyntaxQueries for BodyHost {
    fn syntax(&self, input: &std::sync::Arc<crate::frontend::BodySyntaxInput>) -> Result<std::sync::Arc<crate::frontend::BodySyntax>, crate::frontend::Diagnostic> {
        input.parse().map(std::sync::Arc::new)
    }

    fn syntax_checked(&self, input: &std::sync::Arc<crate::frontend::BodySyntaxInput>) -> Result<std::sync::Arc<crate::frontend::BodySyntax>, crate::frontend::BodySyntaxFailure> {
        let mut result = None;
        self.0.with_declaration_admission(&mut |admission| {
            result = Some(input.parse_with_setting_admission(admission)?);
            Ok(())
        })?;
        Ok(std::sync::Arc::new(result.expect("actual native body result")))
    }
}
#[test]
fn original_compiled_source_body_keeps_assign_into_and_float_mod_assign() {
    use dm_syntax::{ExprKind, StatementKind};
    use std::sync::Arc;
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
fn same_formal(actual:&dm_ir::DeclarationMeaning,base:&dm_ir::DeclarationMeaning){assert_eq!(actual.declared_type(),base.declared_type());assert_eq!(actual.list_element_type(),base.list_element_type());assert_eq!(actual.flags,base.flags);assert_eq!(actual.array,base.array);assert_eq!(actual.declared_initializer,base.declared_initializer);assert!(actual.inherited_opaque().is_none());assert!(actual.procedure.is_none());}
#[test]fn original_builtin_variable_overrides_use_real_catalog_metadata_and_actual_source_parent(){
 let front=build("/atom\n    name=\"own\"\n    alpha=12\n/datum\n    vars=null\n    type=/datum\n/obj/bridge_child\n    name=\"child\"\n");let view=front.source_view().unwrap();assert!(view.receipt().errors().is_empty());assert!(view.receipt().has_original_variable_declarations());let tree=view.tree();
 for(owner,name)in[("/atom","name"),("/atom","alpha"),("/datum","vars"),("/datum","type"),("/obj/bridge_child","name")]{let row=own(tree,owner,name);let base=catalog(if owner=="/obj/bridge_child"{"/atom"}else{owner},name);same_formal(&row.metadata,&base);assert!(row.metadata.initializer.is_some());}
 assert!(catalog("/datum","vars").declared_type().is_some());assert_ne!(catalog("/datum","type").flags,0);assert!(catalog("/atom","alpha").resolved_constant.is_some());assert!(catalog("/datum","type").resolved_constant.is_none());
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

#[test]
fn original_diagnostic_formal_defaults_publish_across_pending_pages_in_source_order() {
    use std::fmt::Write as _;

    let mut text = String::new();
    for ordinal in 0..70 {
        writeln!(text, "/proc/page_default_{ordinal}(value={ordinal}, secondary=3, selected as num in list(4))")
            .unwrap();
        text.push_str("    return value\n");
    }
    let front = build(&text);
    let view = front.source_view().unwrap();
    assert!(view.receipt().errors().is_empty());
    let archive = view.archive();
    assert_eq!(archive.occurrences().len(), 70);
    for ordinal in 0..70 {
        assert_eq!(archive.callables().identity(ordinal).unwrap().name,
            SymbolId::of(&format!("page_default_{ordinal}")));
        let parameters = archive.header_parameters_using(ordinal, &|| Ok(())).unwrap();
        let expressions = parameters.header_expressions().unwrap();
        assert_eq!(expressions.len(), 3);
        let root = expressions.default(0).unwrap().unwrap();
        let dm_syntax::ExprKind::Literal(value) = &root.kind else {
            panic!("actual numeric default is a literal");
        };
        assert_eq!(value.as_str(), ordinal.to_string());
        assert!(expressions.default(1).unwrap().is_some());
        assert!(expressions.in_source(2).unwrap().is_some());
    }
}

#[test]
fn shared_image_dir_proof_uses_the_actual_archive_after_frontend_drop() {
    let host = crate::frontend::declaration_checked_tests::original_test_host();
    let text = "/datum/image_loan_base/proc/image_loan_pick()
    return new /image
/datum/image_loan_base/child
";
    let first = build_using(text, &host);
    let view = first.source_view().unwrap();
    let proof = view.clean_original_image_dir_proof().unwrap();
    let archive = Arc::clone(view.archive());
    let foreign = build_using(text, &host);
    assert!(proof.bind(foreign.source_view().unwrap().archive()).is_err());
    drop(first);
    let loan = proof.bind(&archive).unwrap();
    assert!(Arc::ptr_eq(loan.archive(), &archive));
    let selected = loan.callable(
        SymbolId::of("/datum/image_loan_base/child"),
        SymbolId::of("image_loan_pick"),
        &mut || Ok(()),
    ).unwrap();
    assert_eq!(selected.value, Some(archive.occurrences()[selected.body.unwrap()].member));

    let duplicate = build_using(
        "/proc/image_loan_repeat()
    return new /image
/proc/image_loan_repeat()
    return new /mutable_appearance
",
        &host,
    );
    let view = duplicate.source_view().unwrap();
    assert!(!view.receipt().is_clean());
    assert!(view.clean_original_image_dir_proof().is_err());
}


#[test]
fn actual_original_body_cleanup_geometry_uses_only_square_duplication_on_real_loans(){
 for text in [
  "/proc/p(value)\n    return (value + 1)\n/proc/q()\n    return 2\n",
  "/proc/p(value)\n    return \"head[value + 1]tail\"\n/proc/q()\n    return 2\n",
  "/proc/p(value)\n    return list(value,1)[1]\n/proc/q()\n    return 2\n",
 ]{
  let front=build(text);let view=front.source_view().unwrap();let archive=view.archive();assert_eq!(archive.len(),2);
  for ordinal in 0..archive.len(){
   let body=archive.parse_checked(ordinal).unwrap();let loan=body.original_body_tokens().unwrap();let span=archive.occurrences()[ordinal].expanded_span;assert_eq!(loan.current_span(),span);
   let fixed=dm_syntax::SettingChargeCounter::root_allocation_bytes();let counter=dm_syntax::SettingChargeCounter::try_new(fixed).unwrap();let a=dm_syntax::SettingAdmission::new(&counter,1<<20,&||Ok(()));
   let mut significant=0usize;let mut cleanup=0usize;let mut inline=0usize;let mut depth=0usize;let mut squares=0usize;
   for(kind,_,spelling)in loan.tokens(span).unwrap(){
    if matches!(kind,dm_syntax::TokenKind::Whitespace|dm_syntax::TokenKind::Newline|dm_syntax::TokenKind::Comment){continue}
    significant+=1;
    let leaf=kind==dm_syntax::TokenKind::Number||kind==dm_syntax::TokenKind::Ident&&matches!(spelling,"proc"|"p"|"q"|"value"|"null");
    if !leaf{cleanup+=1;}
    // Independent expected scalar accounting on the SAME actual output loan.
    // Interpolation fragments are real typed values, not syntax delimiters.
    let was=depth!=0;
    if matches!(kind,dm_syntax::TokenKind::Punctuation|dm_syntax::TokenKind::Operator){match spelling{"["|"?["=>depth+=1,"]"=>{assert!(depth>0,"actual complete loan has no stray square closer");depth-=1;},_=>()}}
    if !leaf&&(was||depth!=0){squares+=1;}
    if matches!(spelling,","|";"|":"|"if"|"else"|"for"|"while"|"do"|"spawn"|"switch"|"try"|"catch"|"var"){inline+=1;}
   }
   assert_eq!(depth,0,"actual native loan square windows complete");
   let actual=dm_syntax::body_cleanup_startup_geometry(&[],loan.tokens(span).unwrap(),&a).unwrap();
   let slot=4*(std::mem::size_of::<dm_syntax::Expr>()+std::mem::size_of::<dm_syntax::SharedSettingRetention>());
   let expected=8192+inline*4*std::mem::size_of::<Vec<dm_syntax::Statement>>()+(cleanup+squares)*slot;
   assert_eq!(actual.bytes(),expected,"real production loan must use nonleaf+square accounting, not silently fall back2N: {actual:?}");
   assert!(cleanup<significant,"real Original Ident leaves must not enter cleanup coordination");assert!(squares<significant);assert!(actual.bytes()<8192+inline*4*std::mem::size_of::<Vec<dm_syntax::Statement>>()+2*significant*slot);
   // Borrow a REAL owner subwindow containing only a closing parenthesis.
   // This is deliberately incomplete grammar DATA, never a production source
   // grant; unrelated group imbalance cannot duplicate a dimension expression.
   if let Some((_,closing,_))=loan.tokens(span).unwrap().find(|(kind,_,s)|matches!(kind,dm_syntax::TokenKind::Punctuation|dm_syntax::TokenKind::Operator)&&*s==")"){
    let sub=dm_syntax::body_cleanup_startup_geometry(&[],loan.tokens(closing).unwrap(),&a).unwrap();assert_eq!(sub.bytes(),8192+slot);
   }
   assert_eq!(counter.load(std::sync::atomic::Ordering::Acquire),fixed,"same counter scratch physically refunds");
  }
 }
}


#[test]
fn actual_original_large_opaque_parameter_default_fits_fixed_headroom_and_keeps_native_aliases(){
 use std::sync::atomic::Ordering;
 crate::frontend::declaration_checked_tests::with_original_test_host_controls(|raw,limit,_fail,counter|{
  let literal="x".repeat(96*1024);let text=format!("/proc/p(value=\"{literal}\")\n    return value\n/proc/q()\n    return 2\n");
  let front=build_using(&text,&raw);let view=front.source_view().unwrap();let archive=view.archive();let mut pointer=None;
  let baseline=counter.load(Ordering::Acquire);let cap=baseline+64*1024;limit.store(cap,Ordering::Release);
  assert!(text.len()*512>cap-baseline,"old source-byte prepayment cannot fit actual remaining headroom");
  for _ in 0..2{archive.with_header_parameters_using(0,&||Ok(()),|parameters|{
   let entries=parameters.entries().unwrap();assert_eq!(entries.len(),1);let root=entries[0].expressions().unwrap().unwrap().default_root().unwrap();
   let actual=root.original_expression()as *const dm_syntax::Expr as usize;
   if let Some(prior)=pointer{assert_eq!(prior,actual,"default remains the same independently admitted root");}pointer=Some(actual);
   assert!(matches!(&root.original_expression().kind,dm_syntax::ExprKind::Literal(value)if value.as_str().contains(&literal)));
   assert!(counter.load(Ordering::Acquire)<=cap);Ok(())
  }).unwrap();assert_eq!(counter.load(Ordering::Acquire),baseline,"temporary signature metadata retires before refund");}
  let actual_io=||Err(std::io::Error::from_raw_os_error(1450));
  let error=archive.with_header_parameters_using(0,&actual_io,|_|Ok(())).unwrap_err();
  let crate::frontend::BodySyntaxFailure::Operational(error)=error else{panic!("actual operation failure")};assert_eq!(error.raw_os_error(),Some(1450));
  assert_eq!(counter.load(Ordering::Acquire),baseline);
  archive.with_header_parameters_using(0,&||Ok(()),|p|{assert_eq!(p.entries().unwrap().len(),1);Ok(())}).unwrap();
  let foreign=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=dm_syntax::SettingAdmission::new(&foreign,1<<20,&||Ok(()));
  assert!(archive.with_header_parameters_admitted(0,&a,|_|Ok(())).is_err(),"equal source does not authorize foreign child funding");assert_eq!(foreign.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 });
}

#[test]
fn actual_original_parameter_metadata_paths_dimensions_variadic_preserve_native_counts(){
 for text in[
  "/proc/p(datum/a/x,datum/b/y,...)\n    return x\n",
  "/proc/p(value[1][2], selected as num in list(3))\n    return value\n",
 ]{
  let raw=crate::frontend::declaration_checked_tests::original_test_host();let front=build_using(text,&raw);let view=front.source_view().unwrap();let archive=view.archive();
  archive.with_header_parameters_using(0,&||Ok(()),|p|{assert!(!p.entries().unwrap().is_empty());for entry in p.entries().unwrap(){assert!(entry.expressions().is_ok());}Ok(())}).unwrap();
 }
}

#[test]fn actual_original_scalar_literal_loan_reduces_real_cleanup_with_fixed_headroom(){
 use std::sync::atomic::Ordering;
 crate::frontend::declaration_checked_tests::with_original_test_host_controls(|raw,limit,_fail,counter|{
  let values=std::iter::repeat_n("\"static_leaf\"",1500).collect::<Vec<_>>().join(",");let text=format!("/proc/p()\n    return list({values})\n");
  let headroom={let front=build_using(&text,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();let archive=view.archive();let body=archive.parse_checked(0).unwrap();let loan=body.original_body_tokens().unwrap();let span=archive.occurrences()[0].expanded_span;let input=archive.syntax_input_checked(0,&||Ok(())).unwrap();let syntax=archive.body_query_host().unwrap().syntax_checked(&input).unwrap();assert!(!syntax.item.children.is_empty(),"canonical admitted body preserves real input headers; archive presentation clone may trim them");
   let mut measured=None;raw.with_declaration_admission(&mut|a|{
    let old=dm_syntax::body_cleanup_startup_geometry(&syntax.item.children,loan.tokens(span).unwrap(),a).map_err(crate::frontend::BodySyntaxFailure::Operational)?;let actual=dm_syntax::original_body_cleanup_startup_geometry(&syntax.item.children,loan.tokens(span).unwrap(),a).map_err(crate::frontend::BodySyntaxFailure::Operational)?;
    let static_tokens=loan.tokens(span).unwrap().filter(|(kind,_,_)|matches!(kind,dm_syntax::TokenKind::String|dm_syntax::TokenKind::Resource)).count();assert_eq!(static_tokens,1500);
    let slot=4*(std::mem::size_of::<dm_syntax::Expr>()+std::mem::size_of::<dm_syntax::SharedSettingRetention>());assert_eq!(old.bytes()-actual.bytes(),static_tokens*slot,"only genuine statically typed scalar tokens remove their duplicated cleanup reservation");measured=Some(old.bytes());Ok(())
   }).unwrap();measured.unwrap()
  };
  let front=build_using(&text,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();let archive=view.archive();let baseline=counter.load(Ordering::Acquire);let cap=baseline+headroom;limit.store(cap,Ordering::Release);
  assert!(text.len()*512>headroom,"old coarse source-byte cleanup prepayment cannot fit the fixed remaining headroom");
  {let body=archive.parse_checked(0).unwrap();let parsed=body.statement_body().parsed();assert!(body.statement_body().original_literal_syntax_complete(),"{:?}",body.statement_body().parsed());assert!(!parsed.statements.is_empty());let dm_syntax::StatementKind::Return(Some(expression))=&parsed.statements[0].kind else{panic!("actual native return")};let dm_syntax::ExprKind::Call{args,..}=&expression.kind else{panic!("actual native list call")};assert_eq!(args.len(),1500);assert!(args.iter().all(|arg|matches!(&arg.kind,dm_syntax::ExprKind::Literal(value)if value.original_data().is_some()&&!value.owns_template_syntax())));assert!(counter.load(Ordering::Acquire)<=cap);let loan=body.original_body_tokens().unwrap();assert_eq!(loan.tokens(archive.occurrences()[0].expanded_span).unwrap().filter(|(kind,_,_)|*kind==dm_syntax::TokenKind::String).count(),1500);}
  assert!(counter.load(Ordering::Acquire)<=cap);
 });
}

#[test]fn actual_original_many_literal_roots_fit_one_mib_by_serialized_header_peak(){
 use std::sync::atomic::Ordering;
 crate::frontend::declaration_checked_tests::with_original_test_host_controls(|raw,limit,_fail,counter|{
  let args=std::iter::repeat_n("\"typed_leaf\"",60).collect::<Vec<_>>().join(",");let rows=std::iter::repeat_n(format!("    return list({args})\n"),40).collect::<String>();let source=format!("/proc/p()\n{rows}");
  {let front=build_using(&source,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();let archive=view.archive();let body=archive.parse_checked(0).unwrap();let loan=body.original_body_tokens().unwrap();let span=archive.occurrences()[0].expanded_span;let input=archive.syntax_input_checked(0,&||Ok(())).unwrap();let syntax=archive.body_query_host().unwrap().syntax_checked(&input).unwrap();assert!(!syntax.item.children.is_empty(),"canonical admitted body preserves real input headers; archive presentation clone may trim them");
   raw.with_declaration_admission(&mut|a|{
    let old=dm_syntax::original_body_cleanup_startup_geometry(&syntax.item.children,loan.tokens(span).unwrap(),a).map_err(crate::frontend::BodySyntaxFailure::Operational)?;let peak=dm_syntax::original_body_cleanup_peak_geometry(&syntax.item.children,loan.tokens(span).unwrap(),a).map_err(crate::frontend::BodySyntaxFailure::Operational)?;
    assert!(old.bytes()>1<<20,"old whole-body roots/commas reservation cannot fit this unchanged test headroom");assert!(peak.bytes()<1<<20,"actual Original peak {peak:?}; aggregate {old:?}; body={:?}; headers={:?}",span,syntax.item.children.iter().map(|i|i.header_span).collect::<Vec<_>>());Ok(())
   }).unwrap();
  }
  let front=build_using(&source,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();let archive=view.archive();let baseline=counter.load(Ordering::Acquire);let cap=baseline+(1<<20);limit.store(cap,Ordering::Release);
  {let body=archive.parse_checked(0).unwrap();assert!(body.statement_body().original_literal_syntax_complete(),"{:?}",body.statement_body().parsed());assert_eq!(body.statement_body().parsed().statements.len(),40);let mut leaves=0;
   for statement in &body.statement_body().parsed().statements{let dm_syntax::StatementKind::Return(Some(expression))=&statement.kind else{panic!("actual original return")};let dm_syntax::ExprKind::Call{args,..}=&expression.kind else{panic!("actual original list")};assert_eq!(args.len(),60);for arg in args{assert!(matches!(&arg.kind,dm_syntax::ExprKind::Literal(value)if value.original_data().is_some()&&!value.owns_template_syntax()));leaves+=1;}}
   assert_eq!(leaves,2400);assert!(counter.load(Ordering::Acquire)<=cap);
  }assert!(counter.load(Ordering::Acquire)<=cap);
 });
}

#[test]fn actual_original_template_private_child_survives_real_frontend_body_and_last_alias_retirement(){
 use std::sync::atomic::Ordering;
 crate::frontend::declaration_checked_tests::with_original_test_host_controls(|raw,_limit,_fail,counter|{
  let name="n".repeat(32*1024);let source=format!("/proc/p()\n    return \"head[call({name})]tail\"\n");
  let(alias,pointer,child_capacity)={
   let front=build_using(&source,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();let body=view.archive().parse_checked(0).unwrap();assert!(body.statement_body().original_literal_syntax_complete(),"{:?}",body.statement_body().parsed());
   let dm_syntax::StatementKind::Return(Some(dm_syntax::Expr{kind:dm_syntax::ExprKind::Literal(value),..}))=&body.statement_body().parsed().statements[0].kind else{panic!("actual Original template return")};
   let parts=value.prepared_syntax_parts().unwrap().unwrap().unwrap();let dm_syntax::ExprKind::Call{args,..}=&parts.expressions[0].kind else{panic!("actual consumed child call")};let dm_syntax::ExprKind::Ident(name)=&args[0].kind else{panic!("actual child payload")};assert!(name.capacity()>=32*1024);(value.clone(),parts.expressions.as_ptr(),name.capacity())
  };
  // Physical Source/AST identity is real. The typed builder controls separately
  // prove exact quota ownership: this counter lower bound alone is necessary,
  // not sufficient, because other genuine frontend owners may also be alive.
  assert_eq!(alias.prepared_syntax_parts().unwrap().unwrap().unwrap().expressions.as_ptr(),pointer);assert!(counter.load(Ordering::Acquire)>=child_capacity);
  let second=alias.clone();drop(alias);assert_eq!(second.prepared_syntax_parts().unwrap().unwrap().unwrap().expressions.as_ptr(),pointer);drop(second);
 });
}

#[test]fn actual_original_owned_interpolation_flat_children_qualify_mixed_peak_and_unproved_headers_stay_aggregate(){
 use std::sync::atomic::Ordering;
 crate::frontend::declaration_checked_tests::with_original_test_host_shared_counter_controls(|raw,limit,counter|{
  let source="/proc/p()\n    return \"outer[call(1+2,\"nested[3+4]\")]tail\"\n    return call(5+6,7+8)\n    return \"last[call(9+10)]tail\"\n";
  let front=build_using(source,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();let archive=view.archive();let input=archive.syntax_input_checked(0,&||Ok(())).unwrap();
  {let body=archive.parse_checked(0).unwrap();assert!(body.statement_body().original_literal_syntax_complete(),"{:?}",body.statement_body().parsed());let loan=body.original_body_tokens().unwrap();let span=archive.occurrences()[0].expanded_span;let syntax=archive.body_query_host().unwrap().syntax_checked(&input).unwrap();
   raw.with_declaration_admission(&mut|a|{
    let tokens=||loan.tokens(span).unwrap();assert!(tokens().filter(|(kind,_,_)|*kind==dm_syntax::TokenKind::Interpolation).count()>=6,"genuine outer/nested typed fragments remain in the actual loan");assert!(tokens().filter(|(_,_,text)|*text=="+").count()>=5,"actual child Pratt tokens have not been collapsed to a marker");
    let old=dm_syntax::original_body_cleanup_startup_geometry(&syntax.item.children,tokens(),a).map_err(crate::frontend::BodySyntaxFailure::Operational)?;let peak=dm_syntax::original_body_cleanup_peak_geometry(&syntax.item.children,tokens(),a).map_err(crate::frontend::BodySyntaxFailure::Operational)?;assert!(peak.bytes()<old.bytes(),"actual independent mixed roots should share native cleanup peak: old={old:?} peak={peak:?}");
    let mut foreign=syntax.item.children.clone();for item in &mut foreign{item.header_span.start+=span.end+1;item.header_span.end+=span.end+1;}
    for headers in[&[][..],foreign.as_slice()]{let old=dm_syntax::original_body_cleanup_startup_geometry(headers,tokens(),a).map_err(crate::frontend::BodySyntaxFailure::Operational)?;let unproved=dm_syntax::original_body_cleanup_peak_geometry(headers,tokens(),a).map_err(crate::frontend::BodySyntaxFailure::Operational)?;assert_eq!(unproved.bytes(),old.bytes(),"same tokens cannot authenticate missing/foreign header partitions");}
    Ok(())
   }).unwrap();
  }
  // Fault the SAME real Original BodySyntaxInput, with actual same-counter
  // permits. A complete successful probe primes lazy metadata before every
  // fault, so missing-warm-state allocation is not mistaken for a leaked AST.
  let calls=std::cell::Cell::new(0usize);let stop=std::cell::Cell::new(usize::MAX);let checkpoint=||{let next=calls.get()+1;calls.set(next);if next==stop.get(){Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}};
  for fraction in 0..3{
   stop.set(usize::MAX);calls.set(0);let a=dm_syntax::SettingAdmission::new(counter,limit.load(Ordering::Acquire),&checkpoint);let syntax=input.parse_with_setting_admission(&a).unwrap();assert!(syntax.statement_storage().original_literal_syntax_complete());let count=calls.get();assert!(count>6);drop(syntax);let baseline=counter.load(Ordering::Acquire);
   calls.set(0);stop.set(match fraction{0=>1,1=>count/2,_=>count});let a=dm_syntax::SettingAdmission::new(counter,limit.load(Ordering::Acquire),&checkpoint);let error=input.parse_with_setting_admission(&a).unwrap_err();let crate::frontend::BodySyntaxFailure::Operational(error)=error else{panic!("actual native operational stop")};assert_eq!(error.raw_os_error(),Some(1450),"fraction={fraction} successful_checkpoints={count} actual={error:?}");stop.set(usize::MAX);assert_eq!(counter.load(Ordering::Acquire),baseline,"early/partial/later failed native parse retires its actual private AST before credit");
  }
 });
}

#[test]fn actual_original_canonical_token_plan_fits_long_scalar_and_keeps_owned_interpolation(){
 use std::sync::atomic::Ordering;
 for interpolation in [false,true]{
  crate::frontend::declaration_checked_tests::with_original_test_host_controls(|raw,limit,_fail,counter|{
   let value=if interpolation{format!("{}[1+2]tail","x".repeat(8192))}else{"x".repeat(8192)};let text=format!("/proc/p()\n    return \"{value}\"\n");
   let front=build_using(&text,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();let archive=view.archive();let input=archive.syntax_input_checked(0,&||Ok(())).unwrap();let baseline=counter.load(Ordering::Acquire);let cap=baseline+(1<<20);limit.store(cap,Ordering::Release);assert!(text.len()*512+8192>1<<20);
   raw.with_declaration_admission(&mut|a|{
    let product=input.parse_original_product_with_setting_admission(a)?;let parsed=product.parsed().expect("actual canonical native producer");assert!(parsed.statements.original_literal_syntax_complete());let statements=&parsed.statements.parsed().statements;assert_eq!(statements.len(),1);
    let dm_syntax::StatementKind::Return(Some(value))=&statements[0].kind else{panic!("actual return literal")};let dm_syntax::ExprKind::Literal(value)=&value.kind else{panic!("actual scalar/template literal")};assert_eq!(value.owns_template_syntax(),interpolation,"native Original builder custody remains independent");assert!(counter.load(Ordering::Acquire)<=cap);Ok(())
   }).unwrap();assert!(counter.load(Ordering::Acquire)<=cap);
  });
 }
}
#[test]fn actual_original_canonical_token_plan_preserves_real_first_io_and_retry(){
 use std::sync::atomic::Ordering;
 crate::frontend::declaration_checked_tests::with_original_test_host_controls(|raw,_limit,fail,counter|{
  let front=build_using("/proc/p()\n    return 1\n",&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();let input=view.archive().syntax_input_checked(0,&||Ok(())).unwrap();let before=counter.load(Ordering::Acquire);fail.store(true,Ordering::Release);
  let pending=raw.with_declaration_admission(&mut|a|input.parse_original_product_with_setting_admission(a).map(|_|()));let Err(crate::frontend::BodySyntaxFailure::Operational(actual))=pending else{panic!("actual caller fault")};assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),before);fail.store(false,Ordering::Release);
  raw.with_declaration_admission(&mut|a|{assert!(input.parse_original_product_with_setting_admission(a)?.parsed().is_some());Ok(())}).unwrap();
 });
}

#[test]fn actual_original_dense_call_token_plan_counts_logical_roots_not_expression_tokens(){
 use std::sync::atomic::Ordering;
 crate::frontend::declaration_checked_tests::with_original_test_host_controls(|raw,limit,_fail,counter|{
  let expression=std::iter::repeat_n("value",600).collect::<Vec<_>>().join(",");let text=format!("/proc/p(value)\n    return f({expression})\n");let front=build_using(&text,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();let archive=view.archive();let input=archive.syntax_input_checked(0,&||Ok(())).unwrap();let body=archive.parse_checked(0).unwrap();let tokens=body.original_body_tokens().unwrap();let span=archive.occurrences()[0].expanded_span;let baseline=counter.load(Ordering::Acquire);let cap=baseline+(2<<20);limit.store(cap,Ordering::Release);
  raw.with_declaration_admission(&mut|a|{
   let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().expect("real canonical dense call");assert!(syntax.statements.original_literal_syntax_complete());assert_eq!(syntax.statements.parsed().statements.len(),1);
   let significant=tokens.tokens(span).unwrap().filter(|(kind,_,_)|!matches!(kind,dm_syntax::TokenKind::Whitespace|dm_syntax::TokenKind::Newline|dm_syntax::TokenKind::Comment)).count();assert!(significant>1000);
   let actual=dm_syntax::original_body_token_cleanup_geometry(tokens.tokens(span).unwrap(),a).map_err(crate::frontend::BodySyntaxFailure::Operational)?;let old_statement_only=significant.checked_mul(4*std::mem::size_of::<dm_syntax::Statement>()).unwrap();assert!(actual.bytes()<old_statement_only,"real token-only bound must remove the all-expression-tokens Statement reservation");assert!(counter.load(Ordering::Acquire)<=cap);Ok(())
  }).unwrap();
 });
}

#[test]fn actual_original_token_statement_bound_covers_real_layout_boundary_cohort(){
 fn count(rows:&[dm_syntax::Statement])->usize{rows.iter().map(|row|1+match &row.kind{
  dm_syntax::StatementKind::If{then_branch,else_branch,..}=>count(then_branch)+count(else_branch),
  dm_syntax::StatementKind::While{body,..}|dm_syntax::StatementKind::DoWhile{body,..}|dm_syntax::StatementKind::For{body,..}|dm_syntax::StatementKind::Spawn{body,..}|dm_syntax::StatementKind::Label{body,..}=>count(body),
  dm_syntax::StatementKind::Try{body,catch_body,..}=>count(body)+count(catch_body),
  dm_syntax::StatementKind::Switch{cases,else_branch,..}=>cases.iter().map(|case|count(&case.body)).sum::<usize>()+count(else_branch),_=>0,
 }).sum()}
 for text in [
  "/proc/p(){ return 1; return 2 }",
  "/proc/p()\n    if(1) return 2\n    else return 3\n",
  "/proc/p()\n    var/a=1,b=2,c=3\n    return 4\n",
  "/proc/p()\n    /* comment first\n       comment second */\n    return 1\n    return 2",
  "/proc/p()\n    return 1",
 ]{
  crate::frontend::declaration_checked_tests::with_original_test_host_controls(|raw,_limit,_fail,_counter|{
   let front=build_using(text,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();let archive=view.archive();let body=archive.parse_checked(0).unwrap();let tokens=body.original_body_tokens().unwrap();let span=archive.occurrences()[0].expanded_span;let actual=count(&body.statement_body().parsed().statements);assert!(actual>0);
   raw.with_declaration_admission(&mut|a|{let bound=dm_syntax::original_body_token_cleanup_geometry(tokens.tokens(span).unwrap(),a).map_err(crate::frontend::BodySyntaxFailure::Operational)?;assert!(actual*4*std::mem::size_of::<Vec<dm_syntax::Statement>>()<=bound.bytes()-8192,"real layout boundary statement cleanup exceeds authentic token bound: {text}");Ok(())}).unwrap();
  });
 }
}

#[test]fn actual_original_guarded_body_has_complete_safe_member_key_and_typed_anything_loop(){
 const SOURCE:&str=concat!(
  "/proc/guarded(datum/E, key)\n",
  "    if(!E)\n        return FALSE\n",
  "    var/datum/rx_table/T = GLOB.rx_tables?[E.type]\n",
  "    if(isnull(T))\n        T = rx_table_build(E)\n",
  "    if(T && T.before_keyed[key])\n        return TRUE\n",
  "    for(var/datum/rx_listener/L as anything in E.rx?.listeners)\n",
  "        var/datum/reaction/R = L.trigger\n",
  "        if(R.kind == RXN_BEFORE_OP && R.key == key)\n            return TRUE\n",
  "    return FALSE\n",
 );
 let raw=crate::frontend::declaration_checked_tests::original_test_host();let front=build_using(SOURCE,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();view.require_original_analysis_seed().unwrap();let archive=view.archive();let input=archive.syntax_input_checked(0,&||Ok(())).unwrap();
 raw.with_declaration_admission(&mut|a|{
  let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().expect("actual canonical guarded BODY");let bound=input.bind_original_product_checked(syntax,a)?;
  assert!(matches!(bound.original_code_disposition()?,crate::frontend::OriginalBodyDisposition::Available(_)),"exact real guarded body needs native Original consumption, not a skip");
  let parsed=syntax.statements.parsed();assert!(parsed.diagnostics.is_empty());assert_eq!(parsed.statements.len(),6);
  let dm_syntax::StatementKind::For{control:dm_syntax::ForControl::Each{source_binding,binding,iterable},body}=&parsed.statements[4].kind else{panic!("actual typed for-as-anything production")};assert!(source_binding.is_some());assert_eq!(binding,"var/datum/rx_listener/L");assert!(matches!(&iterable.kind,dm_syntax::ExprKind::SafeMember{via_colon:false,..}));assert_eq!(body.len(),2);
  let rows=parsed.local_variables.entries().unwrap();let loop_rows=rows.iter().filter(|row|row.source_kind==dm_syntax::LocalSourceKind::ForBinding).collect::<Vec<_>>();assert_eq!(loop_rows.len(),1);assert_eq!(loop_rows[0].type_components.len(),2,"datum/rx_listener remains the actual declared loop type");Ok(())
 }).unwrap();
}
#[test]fn actual_original_typed_anything_safe_member_iterable_keeps_its_own_header_binding(){
 let raw=crate::frontend::declaration_checked_tests::original_test_host();let front=build_using("/proc/guarded(datum/E)\n    for(var/datum/rx_listener/L as anything in E.rx?.listeners)\n        return L\n",&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();let input=view.archive().syntax_input_checked(0,&||Ok(())).unwrap();
 raw.with_declaration_admission(&mut|a|{let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().unwrap();let bound=input.bind_original_product_checked(syntax,a)?;assert!(matches!(bound.original_code_disposition()?,crate::frontend::OriginalBodyDisposition::Available(_)));let rows=syntax.statements.parsed().local_variables.entries().unwrap();assert_eq!(rows.iter().filter(|row|row.source_kind==dm_syntax::LocalSourceKind::ForBinding).count(),1);Ok(())}).unwrap();
}

#[test]fn actual_original_canonical_primary_item_owner_fits_full_forest_peak_and_retains_real_payload(){
 use std::sync::atomic::Ordering;
 fn item_bytes(item:&dm_syntax::Item)->usize{item.header.capacity()+item.children.capacity()*std::mem::size_of::<dm_syntax::Item>()+item.children.iter().map(item_bytes).sum::<usize>()}
 crate::frontend::declaration_checked_tests::with_original_test_host_controls(|raw,limit,_fail,counter|{
  let args=std::iter::repeat_n("\"typed_leaf\"",60).collect::<Vec<_>>().join(",");let rows=std::iter::repeat_n(format!("    return list({args})\n"),40).collect::<String>();let source=format!("/proc/p()\n{rows}");
  let old_statement_only=source.bytes().filter(|&byte|byte==b',').count()*4*std::mem::size_of::<dm_syntax::Statement>();assert!(old_statement_only>1<<20,"the earlier all-comma aggregate cannot fit this unchanged headroom");
  let front=build_using(&source,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();let archive=view.archive();archive.with_header_parameters_using(0,&||Ok(()),|_|Ok(())).unwrap();let input=archive.syntax_input_checked(0,&||Ok(())).unwrap();let baseline=counter.load(Ordering::Acquire);let cap=baseline+(1<<20);limit.store(cap,Ordering::Release);
  let mut kept=None;let mut primary_bytes=0;
  raw.with_declaration_admission(&mut|a|{
   let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().expect("actual canonical owned primary");let credit=syntax._primary_credit.as_ref().expect("genuine shared-parameter canonical entry must retain actual Item credit");assert!(a.matches_lease_domain(credit));primary_bytes=credit.bytes();assert_eq!(primary_bytes,item_bytes(&syntax.item),"temporary masks/line/root buffers and independent parameters cannot remain in Item credit");
   assert_eq!(syntax.statements.parsed().statements.len(),40);for row in &syntax.statements.parsed().statements{let dm_syntax::StatementKind::Return(Some(dm_syntax::Expr{kind:dm_syntax::ExprKind::Call{args,..},..}))=&row.kind else{panic!("actual broad shallow return")};assert_eq!(args.len(),60);}
   let before=counter.load(Ordering::Acquire);let width=archive.occurrences()[0].expanded_span.end-archive.occurrences()[0].expanded_span.start;let soft=(width*64+4096).saturating_sub(primary_bytes)+syntax.parameters.retained_bytes()+syntax.statements.parsed().local_variables.retained_admission();assert!(syntax.paid_canonical_payload);assert_eq!(syntax.budget_charge(),4096);assert!(soft>syntax.budget_charge(),"old width/parameters/local estimate duplicates actual retained native payload");assert_eq!(counter.load(Ordering::Acquire),before,"soft overlap settlement cannot refund physical lease bytes");assert!(before<=cap);kept=Some(std::sync::Arc::clone(syntax));Ok(())
  }).unwrap();let held=counter.load(Ordering::Acquire);let alias=kept.take().unwrap();assert_eq!(counter.load(Ordering::Acquire),held,"escaped actual Item alias retains its exact primary funding");
  limit.store(held,Ordering::Release);let denied=raw.with_declaration_admission(&mut|a|a.reserve(1).map(|_|()).map_err(crate::frontend::BodySyntaxFailure::Operational));assert!(matches!(denied,Err(crate::frontend::BodySyntaxFailure::Operational(ref error))if error.kind()==std::io::ErrorKind::OutOfMemory));assert_eq!(counter.load(Ordering::Acquire),held);drop(alias);assert!(counter.load(Ordering::Acquire).checked_add(primary_bytes).is_some_and(|released|released<=held),"real Item allocation retires before its lease refunds");
 });
}

#[test]fn actual_original_paid_payload_keeps_metadata_estimate_and_current_binding_inside_same_hard_cap(){
 use std::sync::atomic::Ordering;
 crate::frontend::declaration_checked_tests::with_original_test_host_controls(|raw,limit,_fail,counter|{
  let args=std::iter::repeat_n("\"typed_leaf\"",60).collect::<Vec<_>>().join(",");let rows=std::iter::repeat_n(format!("    return list({args})\n"),40).collect::<String>();let source=format!("/proc/p()\n{rows}");
  let front=build_using(&source,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();let archive=view.archive();archive.with_header_parameters_using(0,&||Ok(()),|_|Ok(())).unwrap();let input=archive.syntax_input_checked(0,&||Ok(())).unwrap();let baseline=counter.load(Ordering::Acquire);let cap=baseline+(1<<20);limit.store(cap,Ordering::Release);
  raw.with_declaration_admission(&mut|a|{
   let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().unwrap();assert!(syntax.paid_canonical_payload);assert!(crate::frontend::BodySyntax::canonical_payload_admitted(syntax._primary_credit.as_ref(),syntax.parameter_storage(),syntax.statement_storage(),a));
   let before=counter.load(Ordering::Acquire);let width=archive.occurrences()[0].expanded_span.end-archive.occurrences()[0].expanded_span.start;let old=(width*64+4096).saturating_sub(syntax._primary_credit.as_ref().unwrap().bytes())+syntax.parameters.retained_bytes()+syntax.statements.parsed().local_variables.retained_admission();assert!(before.checked_add(old).unwrap()>cap,"old duplicate payload estimate crosses unchanged hard cap after actual parse");
   for _ in 0..8{assert_eq!(syntax.budget_charge(),4096);assert_eq!(counter.load(Ordering::Acquire),before,"an estimate cannot refund real owner allocations");}
   struct Soft<'a>(&'a dm_syntax::SettingChargeCounter,usize);impl Drop for Soft<'_>{fn drop(&mut self){self.0.release_soft_estimate(self.1)}}
   counter.add_soft_estimate(syntax.budget_charge());let soft=Soft(counter,syntax.budget_charge());let bound=input.bind_original_product_checked(syntax,a)?;assert_eq!(bound.statements().iter().count(),40);assert!(counter.load(Ordering::Acquire)<=cap);drop(bound);drop(soft);assert_eq!(counter.load(Ordering::Acquire),before);
   let alias=std::sync::Arc::clone(syntax);assert_eq!(alias.budget_charge(),4096);drop(alias);assert_eq!(counter.load(Ordering::Acquire),before);
   let foreign=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let other=dm_syntax::SettingAdmission::new(&foreign,1<<20,&||Ok(()));assert!(!crate::frontend::BodySyntax::canonical_payload_admitted(syntax._primary_credit.as_ref(),syntax.parameter_storage(),syntax.statement_storage(),&other));assert!(!crate::frontend::BodySyntax::canonical_payload_admitted(None,syntax.parameter_storage(),syntax.statement_storage(),a));
   let ordinary_syntax=dm_syntax::parse_declaration_skeleton(&source);let ordinary=dm_syntax::SharedParameterSignature::ordinary(dm_syntax::parameter_signature_original_with_default_roots(&source,&ordinary_syntax.tokens,ordinary_syntax.items[0].header_span,0,&mut None));assert!(!crate::frontend::BodySyntax::canonical_payload_admitted(syntax._primary_credit.as_ref(),&ordinary,syntax.statement_storage(),a));drop(ordinary);assert_eq!(counter.load(Ordering::Acquire),before);Ok(())
  }).unwrap();
 });
}
#[test]fn actual_original_stored_local_and_unissued_compatibility_keep_original_soft_admission(){
 use std::sync::atomic::Ordering;
 crate::frontend::declaration_checked_tests::with_original_test_host_controls(|raw,_limit,_fail,counter|{
  let front=build_using("/proc/p()\n    var/static/kept = 1\n    return kept\n",&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();let archive=view.archive();archive.with_header_parameters_using(0,&||Ok(()),|_|Ok(())).unwrap();let input=archive.syntax_input_checked(0,&||Ok(())).unwrap();
  raw.with_declaration_admission(&mut|a|{let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().unwrap();assert!(syntax.statements.stored_candidates);assert!(!syntax.paid_canonical_payload);let before=counter.load(Ordering::Acquire);let width=archive.occurrences()[0].expanded_span.end-archive.occurrences()[0].expanded_span.start;let old=(width*64+4096).saturating_sub(syntax._primary_credit.as_ref().unwrap().bytes())+syntax.parameters.retained_bytes()+syntax.statements.parsed().local_variables.retained_admission();assert_eq!(syntax.budget_charge(),old);assert_eq!(counter.load(Ordering::Acquire),before);Ok(())}).unwrap();
  let ordinary=input.parse().unwrap();assert!(!ordinary.paid_canonical_payload);assert_eq!(ordinary.budget_charge(),((archive.occurrences()[0].expanded_span.end-archive.occurrences()[0].expanded_span.start)*64+4096)+ordinary.parameters.retained_bytes()+ordinary.statements.parsed().local_variables.retained_admission());
 });
}

#[test]fn actual_original_link_get_body_keeps_chained_safe_member_index_and_conditional_return(){
 const SOURCE:&str="/proc/link_get(datum/holder,key)\n    var/value=holder?.rx?.link_ends?[key]\n    return istype(value, /list) ?null:slot_datum(value)\n";
 let raw=crate::frontend::declaration_checked_tests::original_test_host();let front=build_using(SOURCE,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();view.require_original_analysis_seed().unwrap();let input=view.archive().syntax_input_checked(0,&||Ok(())).unwrap();
 raw.with_declaration_admission(&mut|a|{
  let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().expect("actual canonical link_get BODY");let bound=input.bind_original_product_checked(syntax,a)?;assert!(matches!(bound.original_code_disposition()?,crate::frontend::OriginalBodyDisposition::Available(_)),"exact actual link_get source needs native consumption, not an unavailable skip");
  let parsed=syntax.statements.parsed();assert!(parsed.diagnostics.is_empty());assert!(parsed.pending_bodies.is_empty());assert_eq!(parsed.statements.len(),2);
  let dm_syntax::StatementKind::Var{value:Some(dm_syntax::Expr{kind:dm_syntax::ExprKind::SafeIndex{object,index},..}),..}=&parsed.statements[0].kind else{panic!("actual safe-index local initializer")};assert!(matches!(&index.kind,dm_syntax::ExprKind::Ident(name)if name=="key"));let dm_syntax::ExprKind::SafeMember{object,selector,via_colon:false}=&object.kind else{panic!("outer actual safe member")};assert_eq!(selector,"link_ends");let dm_syntax::ExprKind::SafeMember{object,selector,via_colon:false}=&object.kind else{panic!("inner actual safe member")};assert_eq!(selector,"rx");assert!(matches!(&object.kind,dm_syntax::ExprKind::Ident(name)if name=="holder"));
  assert!(matches!(&parsed.statements[1].kind,dm_syntax::StatementKind::Return(Some(dm_syntax::Expr{kind:dm_syntax::ExprKind::Conditional{..},..}))));Ok(())
 }).unwrap();
}
#[test]fn actual_original_link_get_safe_initializer_has_its_own_native_body_receipt(){
 let raw=crate::frontend::declaration_checked_tests::original_test_host();let front=build_using("/proc/link_get(datum/holder,key)\n    var/value=holder?.rx?.link_ends?[key]\n",&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();let input=view.archive().syntax_input_checked(0,&||Ok(())).unwrap();
 raw.with_declaration_admission(&mut|a|{let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().unwrap();let bound=input.bind_original_product_checked(syntax,a)?;assert!(matches!(bound.original_code_disposition()?,crate::frontend::OriginalBodyDisposition::Available(_)));let parsed=syntax.statements.parsed();assert_eq!(parsed.statements.len(),1);assert!(parsed.diagnostics.is_empty()&&parsed.pending_bodies.is_empty());assert!(matches!(&parsed.statements[0].kind,dm_syntax::StatementKind::Var{value:Some(dm_syntax::Expr{kind:dm_syntax::ExprKind::SafeIndex{..},..}),..}));Ok(())}).unwrap();
}
#[test]fn actual_original_link_get_conditional_return_has_its_own_native_body_receipt(){
 let raw=crate::frontend::declaration_checked_tests::original_test_host();let front=build_using("/proc/link_get(value)\n    return istype(value, /list) ?null:slot_datum(value)\n",&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();let input=view.archive().syntax_input_checked(0,&||Ok(())).unwrap();
 raw.with_declaration_admission(&mut|a|{let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().unwrap();let bound=input.bind_original_product_checked(syntax,a)?;assert!(matches!(bound.original_code_disposition()?,crate::frontend::OriginalBodyDisposition::Available(_)));let parsed=syntax.statements.parsed();assert_eq!(parsed.statements.len(),1);assert!(parsed.diagnostics.is_empty()&&parsed.pending_bodies.is_empty());let dm_syntax::StatementKind::Return(Some(dm_syntax::Expr{kind:dm_syntax::ExprKind::Conditional{condition,then_value,else_value},..}))=&parsed.statements[0].kind else{panic!("real conditional return")};assert!(matches!(&condition.kind,dm_syntax::ExprKind::Call{..}));assert!(matches!(&then_value.kind,dm_syntax::ExprKind::Literal(value)if value.as_str()=="null"));assert!(matches!(&else_value.kind,dm_syntax::ExprKind::Call{..}));Ok(())}).unwrap();
}

#[test]fn actual_original_abstract_type_table_body_keeps_for_static_comparison_and_indexed_write(){
 const SOURCE:&str="/proc/build_get_abstract_types()\n    var/list/abstracts\n    abstracts=list()\n    for(var/datum/sometype as anything in subtypesof(/datum))\n        if(sometype==sometype::abstract_type)\n            abstracts[sometype::abstract_type]=TRUE\n    return abstracts\n";
 let raw=crate::frontend::declaration_checked_tests::original_test_host();let front=build_using(SOURCE,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();view.require_original_analysis_seed().unwrap();let input=view.archive().syntax_input_checked(0,&||Ok(())).unwrap();
 raw.with_declaration_admission(&mut|a|{let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().unwrap();let bound=input.bind_original_product_checked(syntax,a)?;assert!(matches!(bound.original_code_disposition()?,crate::frontend::OriginalBodyDisposition::Available(_)),"actual complete abstract-type table body must have native Original consumption");let parsed=syntax.statements.parsed();assert!(parsed.diagnostics.is_empty()&&parsed.pending_bodies.is_empty());assert_eq!(parsed.statements.len(),4);let dm_syntax::StatementKind::For{control:dm_syntax::ForControl::Each{..},body}=&parsed.statements[2].kind else{panic!("actual typed subtype loop")};let dm_syntax::StatementKind::If{condition,then_branch,..}=&body[0].kind else{panic!("actual static-member equality")};assert!(matches!(&condition.kind,dm_syntax::ExprKind::Binary{op,rhs,..}if op=="=="&&matches!(&rhs.kind,dm_syntax::ExprKind::StaticMember{..})));assert!(matches!(&then_branch[0].kind,dm_syntax::StatementKind::Assign{target,..}if matches!(&target.kind,dm_syntax::ExprKind::Index{index,..}if matches!(&index.kind,dm_syntax::ExprKind::StaticMember{..}))));Ok(())}).unwrap();
}
#[test]fn actual_original_abstract_type_subtypes_iteration_has_its_own_native_receipt(){
 let raw=crate::frontend::declaration_checked_tests::original_test_host();let front=build_using("/proc/probe()\n    for(var/datum/sometype as anything in subtypesof(/datum))\n        return sometype\n",&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();let input=view.archive().syntax_input_checked(0,&||Ok(())).unwrap();
 raw.with_declaration_admission(&mut|a|{let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().unwrap();let bound=input.bind_original_product_checked(syntax,a)?;assert!(matches!(bound.original_code_disposition()?,crate::frontend::OriginalBodyDisposition::Available(_)));let parsed=syntax.statements.parsed();assert_eq!(parsed.statements.len(),1);assert!(parsed.diagnostics.is_empty()&&parsed.pending_bodies.is_empty());let dm_syntax::StatementKind::For{control:dm_syntax::ForControl::Each{binding,iterable,..},body}=&parsed.statements[0].kind else{panic!("actual subtype iterator")};assert_eq!(binding,"var/datum/sometype");assert!(matches!(&iterable.kind,dm_syntax::ExprKind::Call{..}));assert_eq!(body.len(),1);Ok(())}).unwrap();
}
#[test]fn actual_original_abstract_type_static_equality_has_its_own_native_receipt(){
 let raw=crate::frontend::declaration_checked_tests::original_test_host();let front=build_using("/proc/probe(datum/sometype)\n    if(sometype==sometype::abstract_type)\n        return sometype\n",&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();let input=view.archive().syntax_input_checked(0,&||Ok(())).unwrap();
 raw.with_declaration_admission(&mut|a|{let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().unwrap();let bound=input.bind_original_product_checked(syntax,a)?;assert!(matches!(bound.original_code_disposition()?,crate::frontend::OriginalBodyDisposition::Available(_)));let parsed=syntax.statements.parsed();assert_eq!(parsed.statements.len(),1);assert!(parsed.diagnostics.is_empty()&&parsed.pending_bodies.is_empty());let dm_syntax::StatementKind::If{condition,..}=&parsed.statements[0].kind else{panic!("actual static equality")};assert!(matches!(&condition.kind,dm_syntax::ExprKind::Binary{op,rhs,..}if op=="=="&&matches!(&rhs.kind,dm_syntax::ExprKind::StaticMember{..})));Ok(())}).unwrap();
}
#[test]fn actual_original_abstract_type_static_index_assignment_has_its_own_native_receipt(){
 let raw=crate::frontend::declaration_checked_tests::original_test_host();let front=build_using("/proc/probe(list/abstracts, datum/sometype)\n    abstracts[sometype::abstract_type]=TRUE\n",&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();let input=view.archive().syntax_input_checked(0,&||Ok(())).unwrap();
 raw.with_declaration_admission(&mut|a|{let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().unwrap();let bound=input.bind_original_product_checked(syntax,a)?;assert!(matches!(bound.original_code_disposition()?,crate::frontend::OriginalBodyDisposition::Available(_)));let parsed=syntax.statements.parsed();assert_eq!(parsed.statements.len(),1);assert!(parsed.diagnostics.is_empty()&&parsed.pending_bodies.is_empty());let dm_syntax::StatementKind::Assign{target,..}=&parsed.statements[0].kind else{panic!("actual index write")};let dm_syntax::ExprKind::Index{object,index}=&target.kind else{panic!("actual ordinary bracket target")};assert!(matches!(&object.kind,dm_syntax::ExprKind::Ident(name)if name=="abstracts"));assert!(matches!(&index.kind,dm_syntax::ExprKind::StaticMember{selector,..}if selector=="abstract_type"));Ok(())}).unwrap();
}

// Actual Source57 grammar-census middle cohort; full bodies and independent statements.
#[test]fn actual_original_load_whitelist_full_body_keeps_world_call_and_inline_reset(){
 const SOURCE:&str="/proc/load_whitelist()\n    GLOB.whitelist=world.file2list(\"data/whitelist.txt\")\n    if(!GLOB.whitelist.len)GLOB.whitelist=null\n";
 let raw=crate::frontend::declaration_checked_tests::original_test_host();let front=build_using(SOURCE,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();view.require_original_analysis_seed().unwrap();let input=view.archive().syntax_input_checked(0,&||Ok(())).unwrap();
 raw.with_declaration_admission(&mut|a|{let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().unwrap();let bound=input.bind_original_product_checked(syntax,a)?;assert!(matches!(bound.original_code_disposition()?,crate::frontend::OriginalBodyDisposition::Available(_)),"actual census statement must have native Original consumption");let parsed=syntax.statements.parsed();assert_eq!(parsed.statements.len(),2);assert!(parsed.diagnostics.is_empty()&&parsed.pending_bodies.is_empty());assert!(matches!(&parsed.statements[0].kind,dm_syntax::StatementKind::Assign{value,..}if matches!(&value.kind,dm_syntax::ExprKind::Call{..})));let dm_syntax::StatementKind::If{then_branch,..}=&parsed.statements[1].kind else{panic!("actual inline reset")};assert_eq!(then_branch.len(),1);Ok(())}).unwrap();
}
#[test]fn actual_original_load_whitelist_world_file_call_assignment_has_native_receipt(){
 const SOURCE:&str="/proc/load_whitelist()\n    GLOB.whitelist=world.file2list(\"data/whitelist.txt\")\n";
 let raw=crate::frontend::declaration_checked_tests::original_test_host();let front=build_using(SOURCE,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();view.require_original_analysis_seed().unwrap();let input=view.archive().syntax_input_checked(0,&||Ok(())).unwrap();
 raw.with_declaration_admission(&mut|a|{let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().unwrap();let bound=input.bind_original_product_checked(syntax,a)?;assert!(matches!(bound.original_code_disposition()?,crate::frontend::OriginalBodyDisposition::Available(_)),"actual census statement must have native Original consumption");let parsed=syntax.statements.parsed();assert_eq!(parsed.statements.len(),1);assert!(parsed.diagnostics.is_empty()&&parsed.pending_bodies.is_empty());assert!(matches!(&parsed.statements[0].kind,dm_syntax::StatementKind::Assign{value,..}if matches!(&value.kind,dm_syntax::ExprKind::Call{callee,..}if matches!(&callee.kind,dm_syntax::ExprKind::Member{..}))));Ok(())}).unwrap();
}
#[test]fn actual_original_load_whitelist_inline_negated_member_reset_has_native_receipt(){
 const SOURCE:&str="/proc/load_whitelist()\n    if(!GLOB.whitelist.len)GLOB.whitelist=null\n";
 let raw=crate::frontend::declaration_checked_tests::original_test_host();let front=build_using(SOURCE,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();view.require_original_analysis_seed().unwrap();let input=view.archive().syntax_input_checked(0,&||Ok(())).unwrap();
 raw.with_declaration_admission(&mut|a|{let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().unwrap();let bound=input.bind_original_product_checked(syntax,a)?;assert!(matches!(bound.original_code_disposition()?,crate::frontend::OriginalBodyDisposition::Available(_)),"actual census statement must have native Original consumption");let parsed=syntax.statements.parsed();assert_eq!(parsed.statements.len(),1);assert!(parsed.diagnostics.is_empty()&&parsed.pending_bodies.is_empty());let dm_syntax::StatementKind::If{condition,then_branch,..}=&parsed.statements[0].kind else{panic!("actual inline reset")};assert!(matches!(&condition.kind,dm_syntax::ExprKind::Unary{op,..}if op=="!"));assert_eq!(then_branch.len(),1);assert!(matches!(&then_branch[0].kind,dm_syntax::StatementKind::Assign{..}));Ok(())}).unwrap();
}
#[test]fn actual_original_frame_type_copy_full_body_keeps_dynamic_member_constructor(){
 const SOURCE:&str="/proc/frame_type_copy(value)\n    var/datum/frame/frame_types/source=value\n    if(!istype(source))\n        return value\n    var/datum/frame/frame_types/copy=new source.type\n    copy.set_icon_override(source.icon_override)\n    copy.set_name(source.name)\n    copy.frame_size=source.frame_size\n    copy.frame_class=source.frame_class\n    copy.circuit=source.circuit\n    copy.frame_style=source.frame_style\n    copy.x_offset=source.x_offset\n    copy.y_offset=source.y_offset\n    return copy\n";
 let raw=crate::frontend::declaration_checked_tests::original_test_host();let front=build_using(SOURCE,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();view.require_original_analysis_seed().unwrap();let input=view.archive().syntax_input_checked(0,&||Ok(())).unwrap();
 raw.with_declaration_admission(&mut|a|{let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().unwrap();let bound=input.bind_original_product_checked(syntax,a)?;assert!(matches!(bound.original_code_disposition()?,crate::frontend::OriginalBodyDisposition::Available(_)),"actual census statement must have native Original consumption");let parsed=syntax.statements.parsed();assert_eq!(parsed.statements.len(),12);assert!(parsed.diagnostics.is_empty()&&parsed.pending_bodies.is_empty());assert!(matches!(&parsed.statements[2].kind,dm_syntax::StatementKind::Var{value:Some(dm_syntax::Expr{kind:dm_syntax::ExprKind::Unary{op,value},..}),..}if op=="new"&&matches!(&value.kind,dm_syntax::ExprKind::Member{selector,..}if selector=="type")));Ok(())}).unwrap();
}
#[test]fn actual_original_frame_dynamic_member_constructor_has_native_receipt(){
 const SOURCE:&str="/proc/probe(datum/frame/frame_types/source)\n    var/datum/frame/frame_types/copy=new source.type\n";
 let raw=crate::frontend::declaration_checked_tests::original_test_host();let front=build_using(SOURCE,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();view.require_original_analysis_seed().unwrap();let input=view.archive().syntax_input_checked(0,&||Ok(())).unwrap();
 raw.with_declaration_admission(&mut|a|{let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().unwrap();let bound=input.bind_original_product_checked(syntax,a)?;assert!(matches!(bound.original_code_disposition()?,crate::frontend::OriginalBodyDisposition::Available(_)),"actual census statement must have native Original consumption");let parsed=syntax.statements.parsed();assert_eq!(parsed.statements.len(),1);assert!(parsed.diagnostics.is_empty()&&parsed.pending_bodies.is_empty());assert!(matches!(&parsed.statements[0].kind,dm_syntax::StatementKind::Var{value:Some(dm_syntax::Expr{kind:dm_syntax::ExprKind::Unary{op,value},..}),..}if op=="new"&&matches!(&value.kind,dm_syntax::ExprKind::Member{selector,..}if selector=="type")));Ok(())}).unwrap();
}
#[test]fn actual_original_pipe_init_dirs_full_body_keeps_dynamic_new_and_return_slot(){
 const SOURCE:&str="/proc/build_pipe_init_dirs(type,dir)\n    var/obj/machinery/atmospherics/temp=new type(null,dir)\n    .=temp.get_init_dirs()\n    spent(temp)\n";
 let raw=crate::frontend::declaration_checked_tests::original_test_host();let front=build_using(SOURCE,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();view.require_original_analysis_seed().unwrap();let input=view.archive().syntax_input_checked(0,&||Ok(())).unwrap();
 raw.with_declaration_admission(&mut|a|{let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().unwrap();let bound=input.bind_original_product_checked(syntax,a)?;assert!(matches!(bound.original_code_disposition()?,crate::frontend::OriginalBodyDisposition::Available(_)),"actual census statement must have native Original consumption");let parsed=syntax.statements.parsed();assert_eq!(parsed.statements.len(),3);assert!(parsed.diagnostics.is_empty()&&parsed.pending_bodies.is_empty());assert!(matches!(&parsed.statements[0].kind,dm_syntax::StatementKind::Var{value:Some(dm_syntax::Expr{kind:dm_syntax::ExprKind::Unary{op,value},..}),..}if op=="new"&&matches!(&value.kind,dm_syntax::ExprKind::Call{args,..}if args.len()==2)));assert!(matches!(&parsed.statements[1].kind,dm_syntax::StatementKind::Assign{target,..}if matches!(&target.kind,dm_syntax::ExprKind::Ident(name)if name==".")));Ok(())}).unwrap();
}
#[test]fn actual_original_pipe_dynamic_constructor_arguments_have_native_receipt(){
 const SOURCE:&str="/proc/probe(type,dir)\n    var/obj/machinery/atmospherics/temp=new type(null,dir)\n";
 let raw=crate::frontend::declaration_checked_tests::original_test_host();let front=build_using(SOURCE,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();view.require_original_analysis_seed().unwrap();let input=view.archive().syntax_input_checked(0,&||Ok(())).unwrap();
 raw.with_declaration_admission(&mut|a|{let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().unwrap();let bound=input.bind_original_product_checked(syntax,a)?;assert!(matches!(bound.original_code_disposition()?,crate::frontend::OriginalBodyDisposition::Available(_)),"actual census statement must have native Original consumption");let parsed=syntax.statements.parsed();assert_eq!(parsed.statements.len(),1);assert!(parsed.diagnostics.is_empty()&&parsed.pending_bodies.is_empty());assert!(matches!(&parsed.statements[0].kind,dm_syntax::StatementKind::Var{value:Some(dm_syntax::Expr{kind:dm_syntax::ExprKind::Unary{op,value},..}),..}if op=="new"&&matches!(&value.kind,dm_syntax::ExprKind::Call{args,..}if args.len()==2)));Ok(())}).unwrap();
}
#[test]fn actual_original_pipe_return_slot_method_call_has_native_receipt(){
 const SOURCE:&str="/proc/probe(obj/machinery/atmospherics/temp)\n    .=temp.get_init_dirs()\n";
 let raw=crate::frontend::declaration_checked_tests::original_test_host();let front=build_using(SOURCE,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();view.require_original_analysis_seed().unwrap();let input=view.archive().syntax_input_checked(0,&||Ok(())).unwrap();
 raw.with_declaration_admission(&mut|a|{let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().unwrap();let bound=input.bind_original_product_checked(syntax,a)?;assert!(matches!(bound.original_code_disposition()?,crate::frontend::OriginalBodyDisposition::Available(_)),"actual census statement must have native Original consumption");let parsed=syntax.statements.parsed();assert_eq!(parsed.statements.len(),1);assert!(parsed.diagnostics.is_empty()&&parsed.pending_bodies.is_empty());assert!(matches!(&parsed.statements[0].kind,dm_syntax::StatementKind::Assign{target,value,..}if matches!(&target.kind,dm_syntax::ExprKind::Ident(name)if name==".")&&matches!(&value.kind,dm_syntax::ExprKind::Call{..})));Ok(())}).unwrap();
}

// Diagnostic regression cohort from actual Source57 checker-rank census.
// The source goes through the genuine Original frontend and same BODY owner.
fn census_material_power_body(source:&str,roots:usize,inspect:impl Fn(&[dm_syntax::Statement])){
 let raw=crate::frontend::declaration_checked_tests::original_test_host();let front=build_using(source,&raw).with_body_queries(std::sync::Arc::new(BodyHost(raw.clone()))).unwrap();let view=front.source_view().unwrap();view.require_original_analysis_seed().unwrap();assert_eq!(view.archive().len(),1);let input=view.archive().syntax_input_checked(0,&||Ok(())).unwrap();
 raw.with_declaration_admission(&mut|a|{let product=input.parse_original_product_with_setting_admission(a)?;let syntax=product.parsed().expect("actual census body parses before grammar availability");let parsed=syntax.statements.parsed();assert!(parsed.diagnostics.is_empty()&&parsed.pending_bodies.is_empty(),"source={source}; diagnostics={:?}; pending={}",parsed.diagnostics,parsed.pending_bodies.len());assert_eq!(parsed.statements.len(),roots,"source={source}");inspect(&parsed.statements);let bound=input.bind_original_product_checked(syntax,a)?;assert!(matches!(bound.original_code_disposition()?,crate::frontend::OriginalBodyDisposition::Available(_)),"genuine census body remains unissued: {source}");Ok(())}).unwrap();
}

#[test]fn actual_original_census_resolve_fiftyspawner_keeps_macro_value_and_runtime_constructor(){
 census_material_power_body("#define MAP_VAR(P, VAREDITS, NAME) ((VAREDITS && (#NAME in VAREDITS)) ? VAREDITS[#NAME] : initial(P.NAME))\n/proc/resolve_fiftyspawner(atom/loc, path, list/varedits)\n\tvar/obj/fiftyspawner/P = path\n\tvar/stack_type = MAP_VAR(P, varedits, type_to_spawn)\n\tif(!stack_type)\n\t\t// Made with a variant key (a compiled map, variant_new()): the resolver runs before the row is applied, so it reads the row itself.\n\t\tvar/list/row = dq_variant_vars(path, MAP_VAR(P, varedits, variant))\n\t\tstack_type = row?[\"type_to_spawn\"]\n\tif(!stack_type)\n\t\treturn TRUE\n\tvar/obj/item/stack/M = new stack_type(map_spawn_container(loc), -1)\n\tif(varedits && (\"pixel_y\" in varedits))\n\t\tM.set_pixel_y(varedits[\"pixel_y\"])\n\treturn TRUE\n",7,|rows|{assert!(matches!(&rows[4].kind,dm_syntax::StatementKind::Var{value:Some(dm_syntax::Expr{kind:dm_syntax::ExprKind::Unary{op,value},..}),..}if op=="new"&&matches!(&value.kind,dm_syntax::ExprKind::Call{args,..}if args.len()==2)));});
}

#[test]fn actual_original_census_material_template_application_keeps_subtracted_type_iterable(){
 census_material_power_body("/proc/material_template_for_application(application) as /datum/material_template\n\tvar/static/list/by_application\n\tif(isnull(by_application))\n\t\tby_application = list()\n\t\tfor(var/path in subtypesof(/datum/material_template) - typesof(/datum/material_template/product) - typesof(/datum/material_template/mix) - /datum/material_template/pump)\n\t\t\tvar/datum/material_template/template = path\n\t\t\tvar/app = initial(template.application)\n\t\t\tif(app && !by_application[app])\n\t\t\t\tby_application[app] = path\n\tvar/path = by_application[application]\n\treturn material_template_singleton(path || /datum/material_template/generic)\n",4,|rows|{let dm_syntax::StatementKind::If{then_branch,..}=&rows[1].kind else{panic!("actual initialization if")};assert!(matches!(&then_branch[1].kind,dm_syntax::StatementKind::For{control:dm_syntax::ForControl::Each{iterable,..},..}if matches!(&iterable.kind,dm_syntax::ExprKind::Binary{op,..}if op=="-")));});
}

#[test]fn actual_original_census_type_material_mix_keeps_typed_classic_for_and_parent_step(){
 census_material_power_body("/proc/dq_type_material_mix(path) as /datum/material_template/mix\n\tfor(var/datum/T = path; T; T = initial(T.parent_type))\n\t\tif(GLOB_material_mix_registry && (T in GLOB_material_mix_registry))\n\t\t\treturn GLOB_material_mix_registry[T]\n\treturn null\n",2,|rows|{assert!(matches!(&rows[0].kind,dm_syntax::StatementKind::For{control:dm_syntax::ForControl::CStyle{initializer:Some(dm_syntax::ForInitializer::Declare{declaration,value:Some(_)}),step:Some(_),..},..}if declaration=="var/datum/T"));});
}

#[test]fn actual_original_census_power_topology_keeps_conditional_key_compound_write(){
 census_material_power_body("#define CHURN_COUNT(kind, key) GLOB.churn_census.kind[key] += 1\n/proc/power_topology_edited(source)\n\tvar/datum/source_datum = source\n\tCHURN_COUNT(power_edits, istype(source_datum) ? source_datum.type : source)\n\tvar/datum/system/machines/service = SSmachines\n\tif(service)\n\t\tservice.power_regions_stale = TRUE\n",4,|rows|{let dm_syntax::StatementKind::Assign{target,op,..}=&rows[1].kind else{panic!("actual churn write")};assert_eq!(op,"+=");assert!(matches!(&target.kind,dm_syntax::ExprKind::Index{object,index}if matches!(&object.kind,dm_syntax::ExprKind::Member{..})&&matches!(&index.kind,dm_syntax::ExprKind::Conditional{..})));});
}

#[test]fn actual_original_census_map_var_macro_has_independent_complete_value(){
 census_material_power_body("#define MAP_VAR(P, VAREDITS, NAME) ((VAREDITS && (#NAME in VAREDITS)) ? VAREDITS[#NAME] : initial(P.NAME))\n/proc/probe(obj/fiftyspawner/P,list/varedits)\n    var/stack_type=MAP_VAR(P,varedits,type_to_spawn)\n    return stack_type\n",2,|rows|{assert!(matches!(&rows[0].kind,dm_syntax::StatementKind::Var{value:Some(dm_syntax::Expr{kind:dm_syntax::ExprKind::Group(_),..}),..}));});
}

#[test]fn actual_original_census_runtime_constructor_positional_children_have_independent_receipt(){
 census_material_power_body("/proc/probe(stack_type,atom/loc)\n    var/obj/item/stack/M=new stack_type(map_spawn_container(loc),-1)\n    return M\n",2,|rows|{assert!(matches!(&rows[0].kind,dm_syntax::StatementKind::Var{value:Some(dm_syntax::Expr{kind:dm_syntax::ExprKind::Unary{op,value},..}),..}if op=="new"&&matches!(&value.kind,dm_syntax::ExprKind::Call{args,..}if args.len()==2)));});
}

#[test]fn actual_original_census_declared_for_subtracted_calls_and_typepath_has_independent_receipt(){
 census_material_power_body("/proc/probe()\n    for(var/path in subtypesof(/datum/material_template)-typesof(/datum/material_template/product)-typesof(/datum/material_template/mix)-/datum/material_template/pump)\n        return path\n",1,|rows|{assert!(matches!(&rows[0].kind,dm_syntax::StatementKind::For{control:dm_syntax::ForControl::Each{iterable,..},..}if matches!(&iterable.kind,dm_syntax::ExprKind::Binary{op,..}if op=="-")));});
}

#[test]fn actual_original_census_typed_classic_for_header_has_independent_receipt(){
 census_material_power_body("/proc/probe(path)\n    for(var/datum/T=path;T;T=initial(T.parent_type))\n        return T\n",1,|rows|{assert!(matches!(&rows[0].kind,dm_syntax::StatementKind::For{control:dm_syntax::ForControl::CStyle{initializer:Some(dm_syntax::ForInitializer::Declare{declaration,..}),..},..}if declaration=="var/datum/T"));});
}

#[test]fn actual_original_census_churn_conditional_index_key_has_independent_write_receipt(){
 census_material_power_body("#define CHURN_COUNT(kind, key) GLOB.churn_census.kind[key] += 1\n/proc/probe(datum/source_datum,source)\n    CHURN_COUNT(power_edits, istype(source_datum) ? source_datum.type : source)\n",1,|rows|{assert!(matches!(&rows[0].kind,dm_syntax::StatementKind::Assign{target,..}if matches!(&target.kind,dm_syntax::ExprKind::Index{index,..}if matches!(&index.kind,dm_syntax::ExprKind::Conditional{..}))));});
}

include!("frontend_census_first_group_controls.rs");
