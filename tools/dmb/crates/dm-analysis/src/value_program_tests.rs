use super::*;
#[path = "../examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;

fn build<P: dm_preprocess::SourceProvider>(
    project: &std::path::Path,
    provider: &P,
    defines: &std::collections::BTreeMap<String, String>,
    workers: usize,
) -> Result<dm_tree::frontend::ColdFrontend, Vec<dm_tree::frontend::Diagnostic>> {
    dm_tree::frontend::build_with_config(
        project,
        provider,
        defines,
        dm_tree::frontend::FrontendConfig {
            workers,
            engine: Some(&reference_hierarchy::seed()),
            observer: None,
        },
    )
}

use std::path::Path;

struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn returns(source: &'static str) -> BTreeMap<String, bool> {
    let front = build(Path::new("p.dme"), &Source(source), &Default::default(), 1).unwrap();
    let bodies = BodyArena::new_typed(&front, |_| true);
    let values = Values::build(&front, &bodies, front.snapshot.tree.as_ref(), &[]).unwrap();
    values
        .index
        .procedures
        .keys()
        .map(|&id| {
            let symbols = front.snapshot.tree.symbols();
            (
                format!(
                    "{}/{}#{}",
                    symbols.text(id.owner).unwrap(),
                    symbols.text(id.name).unwrap(),
                    id.occurrence
                ),
                values.is_value(&Key::Return(id)),
            )
        })
        .collect()
}
#[test]
fn native_program_infers_cross_file_style_calls_and_recursive_exits() {
    let values = returns("/proc/a()\n    return b()\n/proc/b()\n    return a()\n/proc/object()\n    return new /datum\n/proc/forward()\n    return object()\n");
    assert_eq!(values["//a#0"], true);
    assert_eq!(values["//b#0"], true);
    assert_eq!(values["//object#0"], false);
    assert_eq!(values["//forward#0"], false);
}
#[test]
fn all_callers_narrow_parameters_and_local_transfers() {
    let values =
        returns("/proc/pass(x)\n    var/y = x\n    return y\n/proc/caller()\n    return pass(1)\n");
    assert!(values["//pass#0"] && values["//caller#0"]);
    let values = returns(
        "/proc/pass(x)\n    var/y = x\n    return y\n/proc/caller()\n    return pass(new /datum)\n",
    );
    assert!(!values["//pass#0"] && !values["//caller#0"]);
}
#[test]
fn native_field_proofs_include_writes_from_other_procedures() {
    let values = returns(
        "var/shared = 1\n/proc/read()\n    return shared\n/proc/write()\n    shared = new /datum\n",
    );
    assert!(!values["//read#0"]);
    let values =
        returns("var/shared = 1\n/proc/read()\n    return shared\n/proc/write()\n    shared = 7\n");
    assert!(values["//read#0"]);
}
#[test]
fn builtin_spelling_cannot_hide_a_source_override() {
    let values = returns("/proc/rand()\n    return new /datum\n/proc/test()\n    return rand()\n");
    assert!(!values["//rand#0"] && !values["//test#0"]);
    let values = returns("/proc/test()\n    return rand()\n");
    assert!(values["//test#0"]);
}
#[test]
fn named_arguments_arglist_and_proc_references_block_parameter_proofs() {
    for source in [
        "/proc/pass(x)\n    return x\n/proc/test()\n    return pass(x = 1)\n",
        "/proc/pass(x)\n    return x\n/proc/test()\n    return pass(arglist(list(1)))\n",
        "/proc/pass(x)\n    return x\n/proc/test()\n    return /proc/pass\n",
    ] {
        assert!(!returns(source)["//pass#0"], "{source}");
    }
}
#[test]
fn declared_scalar_return_does_not_skip_argument_constraints() {
    let values = returns("/proc/pass(x)\n    return x\n/proc/declared() as num\n    pass(new /datum)\n    return new /datum\n");
    assert!(!values["//pass#0"]);
    assert!(values["//declared#0"]);
}

#[test]
fn interpolation_callers_narrow_the_same_parameter_equations() {
    let values =
        returns("/proc/pass(x)\n    return x\n/proc/render()\n    return \"[pass(new /datum)]\"\n");
    assert!(!values["//pass#0"]);
    assert!(values["//render#0"]);
}
#[test]
fn literal_picks_require_values_in_every_arm_and_key() {
    let values = returns("/proc/good()\n    return pick(1, \"small\", /datum)\n/proc/weighted()\n    return pickweight(list(\"a\" = 1))\n/proc/bad()\n    return pick(1, new /datum)\n/proc/opaque(list/L)\n    return pick(L)\n");
    assert!(values["//good#0"] && values["//weighted#0"]);
    assert!(!values["//bad#0"] && !values["//opaque#0"]);
}
#[test]
fn external_calls_have_text_results_but_still_scan_their_arguments() {
    let values = returns("/proc/pass(x)\n    return x\n/proc/external()\n    return call_ext(\"lib\", \"fn\")(pass(new /datum))\n");
    assert!(values["//external#0"]);
    assert!(!values["//pass#0"]);
}
#[test]
fn configuration_subtype_writes_revoke_value_guarantees() {
    let values = returns("/datum/controller/configuration/proc/Get(path)\n    return new /datum\n/datum/config_entry\n    var/config_entry_value\n/datum/config_entry/number/proc/Validate()\n    config_entry_value = 1\n/datum/config_entry/number/good\n/datum/config_entry/number/bad/Validate()\n    config_entry_value = new /datum\n/proc/good(datum/controller/configuration/C)\n    return C.Get(/datum/config_entry/number/good)\n/proc/bad(datum/controller/configuration/C)\n    return C.Get(/datum/config_entry/number/bad)\n");
    assert!(values["//good#0"]);
    assert!(!values["//bad#0"]);
}

#[test]
fn selectors_from_defaults_fields_and_decoded_strings_block_parameters() {
    for source in [
        "/proc/pass(x)\n    return x\nvar/handler = \"pass\"\n/proc/invoke()\n    return call(null, handler)(1)\n",
        "/proc/pass(x)\n    return x\n/proc/invoke(handler = \"pass\")\n    return call(null, handler)(1)\n",
        "/proc/pass(x)\n    return x\n/proc/invoke()\n    return call(null, \"\\x70ass\")(1)\n",
    ] { assert!(!returns(source)["//pass#0"], "{source}"); }
}

#[test]
fn weighted_pick_requires_the_arm_as_well_as_the_weight() {
    let values = returns("/proc/good()\n    return pick(1; \"safe\")\n/proc/bad_arm()\n    return pick(1; new /datum)\n/proc/bad_weight()\n    return pick(new /datum; 1)\n/proc/single()\n    return pick(1)\n/proc/list_arm()\n    return pick(list(1))\n");
    assert!(values["//good#0"] && values["//single#0"]);
    assert!(!values["//bad_arm#0"] && !values["//bad_weight#0"] && !values["//list_arm#0"]);
}
#[test]
fn explicit_receiver_fields_do_not_fall_back_to_a_global_of_the_same_name() {
    let values =
        returns("var/saved = 7\n/datum/empty\n/proc/read(datum/empty/E)\n    return E.saved\n");
    assert!(!values["//read#0"]);
}
#[test]
fn unrelated_proc_and_verb_names_have_separate_dispatch_sets() {
    let values = returns("/datum/base/proc/f()\n    return 1\n/datum/other/verb/f()\n    return new /datum\n/proc/read(datum/base/B)\n    return B.f()\n");
    assert!(values["//read#0"]);
}

#[test]
fn lint_call_source_proofs_do_not_borrow_internal_value_local_candidates() {
    let frontend = build(
        Path::new("p.dme"),
        &Source(
            "/proc/test()\n    var/n = 1\n    var/x = pickweight(list(\"a\" = n))\n    return x\n",
        ),
        &Default::default(),
        1,
    )
    .unwrap();
    let bodies = BodyArena::new_typed(&frontend, |_| true);
    let values = Values::build(&frontend, &bodies, frontend.snapshot.tree.as_ref(), &[]).unwrap();
    let id = frontend.callable_roster().unwrap().identity(0).unwrap();
    // Whole-program return inference may prove the local transfer scalar.
    assert!(values.is_value(&Key::Return(id)));
    // The legacy untyped policy deliberately treats that local as carrying a
    // call source when the call proof itself needs another local's value.
    bodies
        .with_parsed(&frontend.bodies[0], |body| {
            assert!(values.local_holds_call(&frontend, body, "x").unwrap());
            let statement = &body.statement_body().unwrap().parsed().statements[1];
            let StatementKind::Var {
                value: Some(call), ..
            } = &statement.kind
            else {
                panic!()
            };
            assert!(!values.call_is_value(&frontend, body, call, &[]).unwrap());
        })
        .unwrap();
}

#[test]
fn interpolated_parameter_defaults_are_not_literal_entry_points() {
    let values = returns("/proc/pass(x = \"[1]\")\n    return x\n");
    // The reference's literal-default gate excludes InterpString even though
    // the rendered result is text. Preserve the external-entry barrier.
    assert!(!values["//pass#0"]);
}

#[test]
fn scope_operator_proc_references_bar_unobserved_parameter_callers() {
    let values = returns(
        "/datum/proc/pass(x)\n    return x\n/proc/reference(datum/D)\n    return D::pass()\n",
    );
    assert!(!values["/datum/pass#0"]);
}

#[test]
fn implicit_constructors_are_not_unknown_procedure_call_sources() {
    let frontend = build(
        Path::new("p.dme"),
        &Source("/proc/test()\n    var/value = new()\n    return value\n"),
        &Default::default(),
        1,
    )
    .unwrap();
    let bodies = BodyArena::new_typed(&frontend, |_| true);
    let values = Values::build(&frontend, &bodies, frontend.snapshot.tree.as_ref(), &[]).unwrap();
    bodies
        .with_parsed(&frontend.bodies[0], |body| {
            let StatementKind::Var {
                value: Some(constructor),
                ..
            } = &body.statement_body().unwrap().parsed().statements[0].kind
            else {
                panic!()
            };
            assert!(!is_call_result(constructor));
            assert!(!values.local_holds_call(&frontend, body, "value").unwrap());
        })
        .unwrap();
}

#[test]
fn archived_program_reuses_semantic_owners_and_matches_live_equations_after_frontend_drop() {
    let source = "/datum/item\n/datum/holder\n    var/saved\n/proc/scalar(x)\n    return x + 1\n/proc/object()\n    return new /datum/item\n/datum/holder/proc/test()\n    var/local = object()\n    saved = local\n    saved = scalar(1)\n";
    let (archive, expected_equations, expected_values, ordinal, expected_calls) = {
        let frontend = build(Path::new("p.dme"), &Source(source), &Default::default(), 1).unwrap();
        let archive = frontend.body_archive().unwrap();
        let bodies = BodyArena::new_typed(&frontend, |_| true);
        let values =
            Values::build(&frontend, &bodies, frontend.snapshot.tree.as_ref(), &[]).unwrap();
        let ordinal = archive
            .occurrences()
            .iter()
            .position(|body| {
                archive.tree().member(body.member).unwrap().name == SymbolId::of("test")
            })
            .unwrap();
        let calls = bodies
            .with_parsed(&frontend.bodies[ordinal], |body| {
                let StatementKind::Assign { value: call, .. } =
                    &body.statement_body().unwrap().parsed().statements[2].kind
                else {
                    panic!()
                };
                (
                    values.local_holds_call(&frontend, body, "local").unwrap(),
                    values.call_is_value(&frontend, body, call, &[]).unwrap(),
                )
            })
            .unwrap();
        (
            archive,
            values.equations.clone(),
            values.solution.values.clone(),
            ordinal,
            calls,
        )
    };
    let values = Values::build_archive(&archive, archive.tree(), &[]).unwrap();
    assert!(std::ptr::eq(values.index.tree, archive.tree()));
    assert!(matches!(
        values.index.origin,
        crate::native_program::Origin::Archive(_)
    ));
    assert_eq!(values.equations, expected_equations);
    assert_eq!(values.solution.values, expected_values);
    assert!(values.archive_has_field_name(&archive, "saved").unwrap());
    assert!(!values
        .archive_has_field_name(&archive, "not_declared")
        .unwrap());
    let body = archive.parse(ordinal).unwrap();
    let StatementKind::Assign { value: call, .. } =
        &body.statement_body().parsed().statements[2].kind
    else {
        panic!()
    };
    let actual_calls = (
        values.archive_local_holds_call(&body, "local").unwrap(),
        values.archive_call_is_value(&body, call, &[]).unwrap(),
    );
    assert_eq!(actual_calls, expected_calls);
    assert_eq!(actual_calls, (true, true));
}

#[test]
fn archived_value_queries_reject_an_equal_source_different_archive_issuance() {
    let frontend = build(Path::new("p.dme"), &Source("/datum/holder\n    var/saved\n    proc/test()\n        var/local = object()\n        saved = local\n/proc/object()\n    return new /datum\n"), &Default::default(), 1).unwrap();
    let archive = frontend.body_archive().unwrap();
    let foreign = frontend.body_archive().unwrap();
    let values = Values::build_archive(&archive, archive.tree(), &[]).unwrap();
    assert!(values.archive_has_field_name(&foreign, "saved").is_err());
    let ordinal = foreign
        .occurrences()
        .iter()
        .position(|body| foreign.tree().member(body.member).unwrap().name == SymbolId::of("test"))
        .unwrap();
    let body = foreign.parse(ordinal).unwrap();
    let StatementKind::Var {
        value: Some(call), ..
    } = &body.statement_body().parsed().statements[0].kind
    else {
        panic!()
    };
    assert!(values.archive_local_holds_call(&body, "local").is_err());
    assert!(values.archive_call_is_value(&body, call, &[]).is_err());
}

#[test]
fn uncertified_builtin_ancestry_cannot_omit_runtime_override() {
    let source = "/atom/proc/result()\n    return 1\n/obj/result()\n    return new /datum\n/proc/read(atom/x)\n    return x.result()\n";
    let frontend =
        dm_tree::frontend::build(Path::new("p.dme"), &Source(source), &Default::default(), 1)
            .unwrap();
    let bodies = BodyArena::new_typed(&frontend, |_| true);
    let error = match Values::build(&frontend, &bodies, frontend.snapshot.tree.as_ref(), &[]) {
        Ok(_) => panic!("incomplete ancestry falsely admitted a scalar proof"),
        Err(error) => error,
    };
    assert!(error.0.contains("ancestry is incomplete"));
    let seeded = returns(source);
    assert!(
        !seeded["//read#0"],
        "/obj runtime override returns an object"
    );
    assert!(seeded["/atom/result#0"]);
    assert!(!seeded["/obj/result#0"]);
}

#[test]
fn certified_explicit_parent_preserves_real_negative_dispatch_relation() {
    let values = returns("/atom/proc/result()\n    return 1\n/obj/not_atom\n    parent_type = /datum\n    proc/result()\n        return new /datum\n/proc/read(atom/x)\n    return x.result()\n");
    assert!(
        values["//read#0"],
        "lexical /obj prefix does not override explicit ancestry"
    );
    assert!(!values["/obj/not_atom/result#0"]);
}

#[test]
fn explicit_global_calls_use_root_value_and_parameter_equations() {
    let values = returns("/proc/chosen(x)\n    return x\n/datum/proc/chosen(x)\n    return new /datum\n/datum/proc/use_global()\n    return ::chosen(1)\n/datum/proc/use_member()\n    return chosen(1)\n");
    assert!(values["//chosen#0"]);
    assert!(values["/datum/use_global#0"]);
    assert!(!values["/datum/use_member#0"]);
    let values = returns(
        "/proc/chosen(x)\n    return x\n/proc/unsafe_argument()\n    return ::chosen(new /datum)\n",
    );
    assert!(!values["//chosen#0"]);
    assert!(!values["//unsafe_argument#0"]);
}

#[test]
fn absolute_header_type_declaration_keeps_value_program_real_formal_roster() {
    let values = returns("/proc/probe(datum/M,/datum/marker/A,actual_power=1)\n    return 1\n");
    assert_eq!(values.len(), 1);
    assert!(values["//probe#0"]);
}

#[test]
fn controlled_nested_pick_pickweight_and_unknown_calls_codegen_without_callback_type_growth(){
 let source=concat!("/proc/scalar()\n    return 7\n","/proc/nested_ok()\n    return pick(pickweight(list(\"a\" = pick(1, 2))), pick(3; scalar()))\n","/proc/nested_unknown()\n    return pick(pick(1), pickweight(list(\"a\" = completely_unresolved())))\n");
 let frontend=build(Path::new("p.dme"),&Source(source),&Default::default(),1).unwrap();let archive=frontend.body_archive().unwrap();let resolver=archive.tree();let values=Values::build_archive(&archive,resolver,&[]).unwrap();
 for(name,expected)in[("nested_ok",true),("nested_unknown",false)]{
  let ordinal=archive.occurrences().iter().position(|body|archive.tree().member(body.member).unwrap().name==SymbolId::of(name)).unwrap();let body=archive.parse(ordinal).unwrap();let StatementKind::Return(Some(expression))=&body.statement_body().parsed().statements[0].kind else{panic!("actual issued return expression")};let scope=untyped::archived_scope(&body,resolver,&[]).unwrap();let current=values.archive_body_identity(&body).unwrap();let host=Host{index:&values.index,scope:&scope,resolver,current,local_values:false};let legacy=value_expressions::expression(expression,&host).unwrap();assert_eq!(legacy.admissible,expected,"{name}");let events=std::cell::RefCell::new(Vec::<(u8,usize)>::new());let proof=controlled_expression(expression,&host,&mut||{events.borrow_mut().push((0,0));Ok::<(),crate::policy_body_demand::PolicyFailure>(())},&mut|bytes|{events.borrow_mut().push((1,bytes));Ok(())}).unwrap();assert_eq!(proof,legacy,"same policy proof and exact requirements");let expected_events=events.into_inner();assert!(expected_events.iter().filter(|(tag,bytes)|*tag==1&&*bytes==4096).count()>=2,"real nested pick recursion must reserve each arm");
  let mid_poll=expected_events.iter().enumerate().filter(|(_,e)|e.0==0).nth(expected_events.iter().filter(|e|e.0==0).count()/2).unwrap().0;let mid_reserve=expected_events.iter().enumerate().filter(|(_,e)|e.0==1).nth(expected_events.iter().filter(|e|e.0==1).count()/2).unwrap().0;
  for(fail_at,kind)in[(mid_poll,std::io::ErrorKind::Other),(mid_reserve,std::io::ErrorKind::OutOfMemory)]{let actual_events=std::cell::RefCell::new(Vec::<(u8,usize)>::new());let append=|event|->Result<(),crate::policy_body_demand::PolicyFailure>{let mut seen=actual_events.borrow_mut();seen.push(event);if seen.len()==fail_at+1{Err(crate::policy_body_demand::PolicyFailure::Operational(if kind==std::io::ErrorKind::Other{std::io::Error::from_raw_os_error(1450)}else{kind.into()}))}else{Ok(())}};let error=controlled_expression(expression,&host,&mut||append((0,0)),&mut|bytes|append((1,bytes))).unwrap_err();match error{crate::policy_body_demand::PolicyFailure::Operational(error)=>if kind==std::io::ErrorKind::Other{assert_eq!(error.raw_os_error(),Some(1450))}else{assert_eq!(error.kind(),kind)},crate::policy_body_demand::PolicyFailure::Unsupported(error)=>panic!("typed first actual failure was converted: {error}")};assert_eq!(actual_events.into_inner(),expected_events[..=fail_at],"no later poll/reserve or algorithm step after actual failure");}
  let recovered=controlled_expression(expression,&host,&mut||Ok::<(),crate::policy_body_demand::PolicyFailure>(()),&mut|_|Ok(())).unwrap();assert_eq!(recovered,legacy);
 }
}
