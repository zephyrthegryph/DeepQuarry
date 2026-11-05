//! Real productive Original frontend -> existing once BODY contribution.
//! Scalar SCC controls use actual emitted call identities, never grant a model.
use dm_tree::frontend::{SettingExpressionQueries,SettingExpressionInput,OriginalInitializerExpressionInput,OriginalInitializerExpression,BodySyntaxFailure,OriginalSignatureAliasCensus,OriginalSignatureAliasGroup,BodySyntaxQueries,BodySyntaxInput,BodySyntax};
use std::{sync::Arc,path::PathBuf};
#[path="../../../shared/test_scratch.rs"]mod scratch;
#[path="../../../shared/original_analysis_test_host.rs"]mod original_host;
#[path="../../../../analyze/fixtures/original_policy_source.rs"]mod policy_source;
impl BodySyntaxQueries for original_host::Host{
 fn syntax(&self,_:&Arc<BodySyntaxInput>)->Result<Arc<BodySyntax>,dm_tree::frontend::Diagnostic>{panic!("exact original calls must not use compatibility body parsing")}
 fn syntax_checked(&self,input:&Arc<BodySyntaxInput>)->Result<Arc<BodySyntax>,BodySyntaxFailure>{let mut answer=None;self.with_declaration_admission(&mut|a|{answer=Some(Arc::new(input.parse_with_setting_admission(a)?));Ok(())})?;Ok(answer.unwrap())}
}
struct Case{frontend:dm_tree::frontend::DiagnosticFrontend,input:Arc<dm_analysis::checker_effects::EffectInput>,host:Arc<original_host::Host>,_root:PathBuf}
fn case(label:&str,source:&str)->Case{
 let root=scratch::dir(label);std::fs::write(root.join("probe.dm"),source).unwrap();std::fs::write(root.join("project.dme"),"#include \"probe.dm\"\n").unwrap();let provider=policy_source::Provider::new();let host=original_host::Host::new();let settings=host.clone()as Arc<dyn SettingExpressionQueries>;let seed=dm_tree::checker_builtins::original_analysis_seed().unwrap();let executor=dm_exec::BuildExecutor::new(1).unwrap();
 let frontend=dm_tree::frontend::build_for_original_analysis_with_state_checked(&root.join("project.dme"),&provider,&Default::default(),dm_tree::frontend::FrontendConfig{workers:1,engine:Some(seed.frontend_seed()),observer:None},None,&executor,None,&settings).unwrap().with_body_queries(host.clone()as Arc<dyn BodySyntaxQueries>).unwrap();
 let view=frontend.source_view().unwrap();assert!(view.receipt().errors().is_empty());let input=dm_analysis::checker_effects::EffectInput::original_checker_source(Arc::clone(view.archive()),view.tree().checker_builtin_profile().unwrap(),view.receipt(),host.as_ref()).unwrap();Case{frontend,input,host,_root:root}
}
fn body(case:&Case,owner:&str,name:&str)->(usize,Arc<dm_analysis::checker_effects::BodyEffects>){let tree=case.input.archive().tree();let ordinal=case.input.archive().callables().source_order().iter().copied().find(|i|case.input.archive().callables().identity(*i).is_some_and(|id|id.owner==dm_ir::SymbolId::of(owner)&&id.name==dm_ir::SymbolId::of(name))).unwrap();let a=dm_analysis::checker_effects::ExecutionAdmission::default();let product=case.input.compute_original_body_checked_using_admitted_controlled(ordinal,tree,&a,&|input,_|case.host.syntax_checked(input),&||Ok(())).unwrap();assert_eq!(product.original_evaluation_count(),1);(ordinal,product)}
#[test]fn original_exact_parent_dynamic_return_and_self_constant_return_use_selected_occurrence(){
 let source="/datum/returned\n    var/valid\n/datum/base/proc/f(datum/returned/value)\n    set SpacemanDMM_return_type = value.type\n    return null\n/datum/child\n    parent_type = /datum/base\n/datum/child/f(datum/returned/value)\n    set SpacemanDMM_return_type = /list\n    var/parent_value = ..(value).missing_parent\n    var/self_value = .(value).missing_self\n/datum/grandchild\n    parent_type = /datum/child\n/datum/grandchild/f(datum/returned/value)\n    set SpacemanDMM_return_type = /world\n    return null\n";
 let case=case("original-exact-parent-self-type",source);let(_,product)=body(&case,"/datum/child","f");let rows=product.with_original_diagnostics(&case.input,|rows|rows.iter().map(|row|row.diagnostic().message.clone()).collect::<Vec<_>>()).unwrap();
 assert!(rows.iter().any(|s|s=="undefined field: \"missing_parent\" on /datum/returned"),"parent must evaluate actual parent return_type against already-evaluated parameter: {rows:?}");assert!(rows.iter().any(|s|s=="undefined field: \"missing_self\" on /list"),"self must use this actual occurrence, not grandchild/parent/virtual winner: {rows:?}");assert!(rows.iter().all(|s|!s.contains("on /world")));
}
fn graph(case:&Case)->(Vec<dm_ir::ProcedureIdentity>,Vec<Vec<usize>>,Vec<bool>){
 use dm_analysis::checker_effects::{EffectSource,ExecutionAdmission};let archive=case.input.archive();let source=EffectSource::new(archive,case.input.profile()).unwrap();let a=ExecutionAdmission::default();let ids=archive.callables().source_order().iter().map(|i|archive.callables().identity(*i).unwrap()).collect::<Vec<_>>();let mut edges=vec![Vec::new();ids.len()];let mut direct=vec![false;ids.len()];
 let pending=source.with_original_body_page_checked(&case.input,0,source.len(),&a,&mut||Ok(()),&mut|ordinal,admission|case.input.compute_original_body_checked_using_admitted_controlled(ordinal,archive.tree(),admission,&|input,_|case.host.syntax_checked(input),&||Ok(())),|page|{for i in 0..page.len(){let row=page.contribution(i)?.unwrap();let own=ids.iter().position(|id|*id==row.procedure()).unwrap();direct[own]=row.has_direct_effect();row.visit_source_calls(|id,exact,new_context|{assert!(exact,"this fixture has only exact self/parent calls");assert!(!new_context);edges[own].push(ids.iter().position(|known|*known==id).unwrap());});}Ok(())});pending.map_err(|failure|{use dm_analysis::checker_effects::OriginalBodyReadFailure::{Policy,Body};match failure{Policy(error)|Body(error)=>error}}).expect("actual page cannot refuse the exact-call cohort");(ids,edges,direct)
}
#[test]fn actual_exact_parent_self_edges_feed_global_scc_and_retract_when_body_or_parent_effect_changes(){
 fn source(impure:bool,parent_call:bool)->String{format!("var/global_sink=0\n/datum/base/proc/f()\n    {}\n/datum/child\n    parent_type = /datum/base\n/datum/child/f()\n    {}\n/datum/grandchild\n    parent_type = /datum/child\n/datum/grandchild/f()\n    global_sink=2\n",if impure{"global_sink=1"}else{"return null"},if parent_call{"..()\n    .()"}else{"return null"})}
 let mut retained=Vec::new();for(n,(impure,parent_call,want))in[(false,true,false),(true,true,true),(true,false,false)].into_iter().enumerate(){let case=case(&format!("original-exact-scc-{n}"),&source(impure,parent_call));let(ids,edges,direct)=graph(&case);let child=ids.iter().position(|id|id.owner==dm_ir::SymbolId::of("/datum/child")).unwrap();let parent=ids.iter().position(|id|id.owner==dm_ir::SymbolId::of("/datum/base")).unwrap();let grandchild=ids.iter().position(|id|id.owner==dm_ir::SymbolId::of("/datum/grandchild")).unwrap();if parent_call{assert!(edges[child].contains(&child));assert!(edges[child].contains(&parent));assert!(!edges[child].contains(&grandchild),"exact source calls do not dispatch to override child")}
 let a=dm_analysis::checker_effects::ExecutionAdmission::default();let scc=dm_analysis::checker_effects::CompactEffectScc::compute_checked(ids.len(),&a,|i,n,_|Ok(edges[i].get(n).copied()),&mut||Ok(())).unwrap();let summary=scc.summarize_checked(&a,|i,_|Ok(direct[i]),|i,n,_|Ok(edges[i].get(n).copied()),&mut||Ok(())).unwrap();assert_eq!(summary.node_has_effect(child),Some(want));retained.push(case);}
 assert_eq!(retained.len(),3,"earlier genuine owners remain alive; edits do not mutate them or reuse their body artifacts as new source proof");
}
#[test]fn actual_original_exact_call_body_preserves_first_io_and_foreign_owner_refuses(){let source="/datum/base/proc/f()\n    return null\n/datum/child\n    parent_type=/datum/base\n/datum/child/f()\n    ..()\n";let case=case("original-exact-call-first-io",source);let ordinal=case.input.archive().callables().source_order()[0];let a=dm_analysis::checker_effects::ExecutionAdmission::default();let error=case.input.compute_original_body_checked_using_admitted_controlled(ordinal,case.input.archive().tree(),&a,&|_,_|Err(BodySyntaxFailure::Operational(std::io::Error::from_raw_os_error(1450))),&||Ok(())).err().unwrap();assert!(matches!(error,dm_analysis::policy_body_demand::PolicyFailure::Operational(error)if error.raw_os_error()==Some(1450)));let(_,product)=body(&case,"/datum/child","f");let other=self::case("original-exact-call-foreign",source);assert!(product.with_original_diagnostics(&other.input,|_|()).is_err());assert!(case.frontend.source_view().is_ok());}

// Same productive fixture and existing once-evaluated BodyEffects owner as the
// exact-call controls; no secondary parse/model or mocked scalar input.
#[test]fn original_compound_assignments_visit_both_sides_once_in_pinned_order(){
 let source="/datum/widget\n    var/valid\n/proc/left()\n    set SpacemanDMM_return_type = /datum/widget\n    return null\n/proc/right()\n    set SpacemanDMM_return_type = /datum/widget\n    return null\n/proc/probe()\n    return (left().missing_lhs += right().missing_rhs)\n";
 let c=case("original-compound-order",source);let(_,p)=body(&c,"/","probe");let rows=p.with_original_diagnostics(&c.input,|rows|rows.iter().map(|r|r.diagnostic().message.clone()).collect::<Vec<_>>()).unwrap();let selected=rows.iter().filter(|s|s.contains("missing_lhs")||s.contains("missing_rhs")).collect::<Vec<_>>();assert_eq!(selected.len(),2,"lhs and rhs are evaluated once, no arithmetic rewrite: {rows:?}");assert!(selected[0].contains("missing_lhs"));assert!(selected[1].contains("missing_rhs"));
}
#[test]fn original_compound_spellings_keep_rhs_type_and_global_impurity_without_binary_shift_effect(){
 for(n,op)in["+=","-=","*=","/=","%=","|=","&=","^=","<<=",">>=","||=","&&="].into_iter().enumerate(){let source=format!("var/global_sink=0\n/datum/widget\n    var/valid\n/proc/probe(datum/widget/value)\n    return (global_sink {op} value).missing_after\n");let c=case(&format!("original-compound-all-{n}"),&source);let(_,p)=body(&c,"/","probe");let rows=p.with_original_diagnostics(&c.input,|rows|rows.iter().map(|r|r.diagnostic().message.clone()).collect::<Vec<_>>()).unwrap();assert_eq!(rows.iter().filter(|s|s.as_str()=="undefined field: \"missing_after\" on /datum/widget").count(),1,"{op}: compound returns RHS analysis under pinned AssignOp: {rows:?}");assert!(p.source_contribution().has_direct_effect(),"{op}: global lhs is impure");}
}
#[test]fn original_compound_rhs_gets_lhs_basic_type_and_nested_return_binding(){
 let source="var/global_sink=0\n/datum/widget\n    var/valid\n/datum/widget/New()\n    return null\n/proc/echo(datum/widget/value)\n    set SpacemanDMM_return_type = value.type\n    return null\n/proc/probe(datum/widget/value)\n    var/datum/widget/local\n    local += new(bad=1)\n    return echo(global_sink += value).missing_nested\n";
 let c=case("original-compound-hint-return",source);let(_,p)=body(&c,"/","probe");let rows=p.with_original_diagnostics(&c.input,|rows|rows.iter().map(|r|r.diagnostic().message.clone()).collect::<Vec<_>>()).unwrap();assert!(rows.iter().any(|s|s.contains("bad keyword argument")&&s.contains("bad")&&s.contains("New")),"RHS implicit New must use actual lhs basic type: {rows:?}");assert!(rows.iter().any(|s|s=="undefined field: \"missing_nested\" on /datum/widget"),"already evaluated compound RHS must reach nested genuine return binding: {rows:?}");
}

#[test]fn original_compound_body_preserves_first_io_and_rejects_foreign_same_bytes_owner(){
 let source="var/global_sink=0\n/proc/probe()\n    return (global_sink += 1)\n";let c=case("original-compound-first-io",source);let ordinal=c.input.archive().callables().source_order()[0];let a=dm_analysis::checker_effects::ExecutionAdmission::default();let calls=std::cell::Cell::new(0);let e=c.input.compute_original_body_checked_using_admitted_controlled(ordinal,c.input.archive().tree(),&a,&|_,_|{calls.set(calls.get()+1);Err(BodySyntaxFailure::Operational(std::io::Error::from_raw_os_error(1450)))},&||Ok(())).err().unwrap();assert_eq!(calls.get(),1);assert!(matches!(e,dm_analysis::policy_body_demand::PolicyFailure::Operational(e)if e.raw_os_error()==Some(1450)));let(_,product)=body(&c,"/","probe");let foreign=case("original-compound-same-bytes-foreign",source);assert!(product.with_original_diagnostics(&foreign.input,|_|()).is_err());assert!(product.source_contribution().has_direct_effect());
}

#[test]fn original_crash_statement_evaluates_optional_expression_once_then_stops_real_flow(){
 let source="/datum/widget\n    var/valid\n/proc/probe(datum/widget/value)\n    CRASH(value.missing_before)\n    value.missing_after\n";let c=case("original-crash-flow",source);let(_,p)=body(&c,"/","probe");let rows=p.with_original_diagnostics(&c.input,|rows|rows.iter().map(|r|r.diagnostic().message.clone()).collect::<Vec<_>>()).unwrap();assert_eq!(rows.iter().filter(|s|s.as_str()=="undefined field: \"missing_before\" on /datum/widget").count(),1,"Crash expression once: {rows:?}");assert!(rows.iter().all(|s|!s.contains("missing_after")),"genuine return flow skips later statement: {rows:?}");let mut calls=0;p.source_contribution().visit_source_calls(|_,_,_|calls+=1);assert_eq!(calls,0,"CRASH is a statement, never an invented source proc edge");assert!(!p.source_contribution().has_direct_effect());
}
#[test]fn original_crash_statement_empty_is_pure_but_assignment_argument_retains_its_real_effect(){
 for(n,(argument,want))in[("",false),("global_sink=1",true)].into_iter().enumerate(){let source=format!("var/global_sink=0\n/proc/probe()\n    CRASH({argument})\n    global_sink=2\n");let c=case(&format!("original-crash-argument-{n}"),&source);let(_,p)=body(&c,"/","probe");assert_eq!(p.source_contribution().has_direct_effect(),want,"CRASH itself adds no impurity; actual assignment arg is not a skipped keyword");let mut calls=0;p.source_contribution().visit_source_calls(|_,_,_|calls+=1);assert_eq!(calls,0);}
}
#[test]fn original_crash_statement_preserves_first_io_and_same_bytes_foreign_body_refuses(){
 let source="/proc/probe()\n    CRASH()\n";let c=case("original-crash-first-io",source);let ordinal=c.input.archive().callables().source_order()[0];let a=dm_analysis::checker_effects::ExecutionAdmission::default();let calls=std::cell::Cell::new(0);let error=c.input.compute_original_body_checked_using_admitted_controlled(ordinal,c.input.archive().tree(),&a,&|_,_|{calls.set(calls.get()+1);Err(BodySyntaxFailure::Operational(std::io::Error::from_raw_os_error(1450)))},&||Ok(())).err().unwrap();assert_eq!(calls.get(),1);assert!(matches!(error,dm_analysis::policy_body_demand::PolicyFailure::Operational(error)if error.raw_os_error()==Some(1450)));let(_,p)=body(&c,"/","probe");let foreign=case("original-crash-foreign",source);assert!(p.with_original_diagnostics(&foreign.input,|_|()).is_err());
}

#[test]fn original_unweighted_pick_visits_actual_choices_once_in_order_without_fake_call(){
 let source="/datum/widget\n    var/valid\n/proc/left()\n    set SpacemanDMM_return_type = /datum/widget\n    return null\n/proc/right()\n    set SpacemanDMM_return_type = /datum/widget\n    return null\n/proc/probe()\n    return pick(left().missing_left, right().missing_right)\n";let c=case("original-pick-order",source);let(_,p)=body(&c,"/","probe");let rows=p.with_original_diagnostics(&c.input,|rows|rows.iter().map(|r|r.diagnostic().message.clone()).collect::<Vec<_>>()).unwrap();let selected=rows.iter().filter(|s|s.contains("missing_left")||s.contains("missing_right")).collect::<Vec<_>>();assert_eq!(selected.len(),2,"choices evaluated once: {rows:?}");assert!(selected[0].contains("missing_left"));assert!(selected[1].contains("missing_right"));let mut calls=Vec::new();p.source_contribution().visit_source_calls(|id,_,_|calls.push(id.name));assert_eq!(calls,[dm_ir::SymbolId::of("left"),dm_ir::SymbolId::of("right")],"no synthetic pick proc edge");
}
#[test]fn original_unweighted_pick_assignment_choice_keeps_effect_but_result_does_not_inherit_type(){
 let source="var/global_sink=0\n/datum/widget\n    var/valid\n/proc/probe(datum/widget/value)\n    return pick(global_sink=value).missing_result\n";let c=case("original-pick-assignment",source);let(_,p)=body(&c,"/","probe");assert!(p.source_contribution().has_direct_effect(),"assignment choice is evaluated, never a skipped named argument");let rows=p.with_original_diagnostics(&c.input,|rows|rows.iter().map(|r|r.diagnostic().message.clone()).collect::<Vec<_>>()).unwrap();assert_eq!(rows,["field access requires static type: \"missing_result\""],"Pick's empty Analysis does not retain the choice's type");
}
#[test]fn original_unweighted_pick_keeps_actual_first_io_and_foreign_body_refusal(){
 let source="/proc/probe()\n    return pick(1,2)\n";let c=case("original-pick-first-io",source);let ordinal=c.input.archive().callables().source_order()[0];let a=dm_analysis::checker_effects::ExecutionAdmission::default();let error=c.input.compute_original_body_checked_using_admitted_controlled(ordinal,c.input.archive().tree(),&a,&|_,_|Err(BodySyntaxFailure::Operational(std::io::Error::from_raw_os_error(1450))),&||Ok(())).err().unwrap();assert!(matches!(error,dm_analysis::policy_body_demand::PolicyFailure::Operational(error)if error.raw_os_error()==Some(1450)));let(_,p)=body(&c,"/","probe");let foreign=case("original-pick-foreign",source);assert!(p.with_original_diagnostics(&foreign.input,|_|()).is_err());
}

#[test]
fn original_weighted_pick_visits_each_weight_before_its_choice_once() {
    let source = "\
/datum/widget\n    var/valid\n\
/proc/weight()\n    set SpacemanDMM_return_type = /datum/widget\n    return null\n\
/proc/weighted()\n    set SpacemanDMM_return_type = /datum/widget\n    return null\n\
/proc/plain()\n    set SpacemanDMM_return_type = /datum/widget\n    return null\n\
/proc/probe()\n    return pick(weight().missing_weight; weighted().missing_weighted, plain().missing_plain)\n";
    let case = case("original-weighted-pick-order", source);
    let (_, product) = body(&case, "/", "probe");
    let rows = product.with_original_diagnostics(&case.input, |rows| {
        rows.iter().map(|row| row.diagnostic().message.clone()).collect::<Vec<_>>()
    }).unwrap();
    let messages = rows.iter().map(String::as_str).filter(|row| row.contains("missing_")).collect::<Vec<_>>();
    assert_eq!(messages, [
        "undefined field: \"missing_weight\" on /datum/widget",
        "undefined field: \"missing_weighted\" on /datum/widget",
        "undefined field: \"missing_plain\" on /datum/widget",
    ]);
    let mut calls = Vec::new();
    product.source_contribution().visit_source_calls(|id, _, _| calls.push(id.name));
    assert_eq!(calls, ["weight", "weighted", "plain"].map(dm_ir::SymbolId::of));
}

#[test]
fn original_weighted_pick_assignment_weight_keeps_effect_without_inheriting_choice_type() {
    let source = "\
var/global_sink=0\n/datum/widget\n    var/valid\n\
/proc/probe(datum/widget/value)\n    return pick((global_sink=value); value, value).missing_result\n";
    let case = case("original-weighted-pick-assignment", source);
    let (_, product) = body(&case, "/", "probe");
    assert!(product.source_contribution().has_direct_effect());
    let rows = product.with_original_diagnostics(&case.input, |rows| {
        rows.iter().map(|row| row.diagnostic().message.clone()).collect::<Vec<_>>()
    }).unwrap();
    assert_eq!(rows, ["field access requires static type: \"missing_result\""]);
    let mut calls = 0;
    product.source_contribution().visit_source_calls(|_, _, _| calls += 1);
    assert_eq!(calls, 0);
}

#[test]
fn original_chained_dispatch_visits_targets_then_arguments_once_without_dispatcher_edge() {
    for dispatcher in ["call", "call_ext"] {
        let source = format!("\
/datum/widget\n    var/valid\n\
/proc/first()\n    set SpacemanDMM_return_type = /datum/widget\n    return null\n\
/proc/second()\n    set SpacemanDMM_return_type = /datum/widget\n    return null\n\
/proc/third()\n    set SpacemanDMM_return_type = /datum/widget\n    return null\n\
/proc/probe()\n    return {dispatcher}(first().missing_first, second().missing_second)(named=third().missing_third).missing_result\n");
        let case = case(&format!("original-chained-order-{dispatcher}"), &source);
        let (_, product) = body(&case, "/", "probe");
        let rows = product.with_original_diagnostics(&case.input, |rows| {
            rows.iter().map(|row| row.diagnostic().message.clone()).collect::<Vec<_>>()
        }).unwrap();
        let messages = rows.iter().map(String::as_str).filter(|row| row.contains("missing_")).collect::<Vec<_>>();
        assert_eq!(messages, [
            "undefined field: \"missing_first\" on /datum/widget",
            "undefined field: \"missing_second\" on /datum/widget",
            "undefined field: \"missing_third\" on /datum/widget",
            "field access requires static type: \"missing_result\"",
        ], "{dispatcher}: {rows:?}");
        assert!(rows.iter().all(|row| !row.contains("named")), "{rows:?}");
        let mut calls = Vec::new();
        product.source_contribution().visit_source_calls(|id, _, _| calls.push(id.name));
        assert_eq!(calls, ["first", "second", "third"].map(dm_ir::SymbolId::of));
    }
}

#[test]
fn original_chained_external_targets_are_expressions_but_dynamic_targets_are_arguments() {
    for (dispatch, expected_effect) in [
        ("call(global_sink=1)(global_sink=2)", false),
        ("call_ext(global_sink=1)(global_sink=2)", true),
    ] {
        let source = format!("var/global_sink=0\n/proc/probe()\n    return {dispatch}\n");
        let case = case(&format!("original-chained-assignment-{expected_effect}"), &source);
        let (_, product) = body(&case, "/", "probe");
        assert_eq!(product.source_contribution().has_direct_effect(), expected_effect, "{dispatch}");
        let mut calls = 0;
        product.source_contribution().visit_source_calls(|_, _, _| calls += 1);
        assert_eq!(calls, 0);
    }
}

#[test]
fn original_chained_dispatch_refuses_native_shape_outside_external_target_arity() {
    let case = case("original-chained-external-arity", "/proc/probe()\n    return call_ext(1,2,3)()\n");
    let ordinal = case.input.archive().callables().source_order()[0];
    let admission = dm_analysis::checker_effects::ExecutionAdmission::default();
    let failure = case.input.compute_original_body_checked_using_admitted_controlled(
        ordinal, case.input.archive().tree(), &admission,
        &|input, _| case.host.syntax_checked(input), &|| Ok(()),
    ).err().expect("external target arity is unsupported");
    assert!(matches!(failure, dm_analysis::policy_body_demand::PolicyFailure::Unsupported(_)));
    assert!(failure.to_string().contains("external dispatch requires one or two target expressions"));
}
