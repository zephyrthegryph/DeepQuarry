//! End-to-end real current callee prefix and negative type lookup controls.
use super::*;
use super::super::analysis_context_tests::{checker_fixture as fixture,run,current};
use dm_ir::{ResolveQuery,SymbolId};use dm_query::Kind;
const MISSING_TYPE:&str="/proc/choose()\n    set SpacemanDMM_return_type=/datum/result\n    return null\n/proc/probe()\n    return choose().field\n";
const PRESENT_TYPE:&str="/datum/result\n/proc/choose()\n    set SpacemanDMM_return_type=/datum/result\n    return null\n/proc/probe()\n    return choose().field\n";
fn current_callee_fixture(source: &str) -> (crate::runner_host::BuildHost, crate::request::BuildRequest, std::path::PathBuf) {
    let (host, mut request, root) = fixture(source);
    std::fs::write(root.join("SpacemanDMM.toml"), b"").unwrap();
    request.policy_inputs.as_mut().unwrap().files.push(crate::policy_request::PolicyInputFile {
        path: root.join("code/probe.dm"),
        role: crate::policy_request::PolicyInputRole::DmSource,
        required: true,
    });
    (host, request, root)
}

fn observed(host: &crate::runner_host::BuildHost, root: &Path) -> (Vec<(usize, usize, String)>, usize) {
    current(host, |snapshot| {
        let archive = snapshot.body_archive.as_ref().unwrap();
        assert_eq!(archive.len(), 2);
        let source = archive.expanded_source();
        // Original capture can add trivia between punctuation occurrences.
        // Locate the field token and verify its dot against authored geometry.
        let field = source.rfind("field").expect("expanded probe field token");
        let before_field = source[..field].trim_end();
        let dot = before_field.strip_suffix('.').expect("probe field has a preceding dot").len();
        let environment = root.join("code/probe.dm");
        let authored = std::fs::read_to_string(&environment).unwrap();
        let (line, text) = authored.lines().enumerate().find(|(_, line)| line.contains("choose().field")).unwrap();
        let point = archive.source_note_point(dot).unwrap();
        assert_eq!((point.line, point.byte_column), (line + 1, text.find(".field").unwrap() + 1));
        let mut rows = Vec::new();
        let result = snapshot.visit_current_variable_diagnostics(1, &environment, Some(&root.join("SpacemanDMM.toml")), &snapshot.tree, |row| {
            rows.push((row.span.start, row.span.end, row.diagnostic.message.clone()));
            Ok(())
        });
        println!("CURRENT_CALLABLE_NATIVE={:?}", (&result, &rows, dot));
        assert_eq!(result.unwrap(), dm_analysis::checks_undefined_variable::CurrentUndefinedDisposition::Evaluated);
        (rows, dot)
    })
}
#[test]fn current_callable_actual_rejected_return_type_absence_is_a_dependency_before_eval_and_rebinds_on_type_add(){
 let(mut host,request,root)=current_callee_fixture(MISSING_TYPE);let queries=host.query_db().clone();run(&mut host,&request);let first=observed(&host,&root);assert!(first.0.is_empty(),"selected variable error family excludes the separately owned return-compile error/warning prelude");let syntax=queries.db().stats(Kind(4)).computed;assert_eq!(syntax,2,"caller and callee use their two canonical products, no issued absolute sibling parse");let semantics=queries.db().stats(Kind(28)).computed;
 let(parent,type_lookup,_)=current(&host,|snapshot|{let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap();queries.current_variable_keys_for_test(input.input(),1,ResolveQuery::Type(SymbolId::of("/datum/result")))});assert!(queries.db().dependants(&[type_lookup]).contains(&parent),"compile-rejected Type lookup must exist even when Eval did not execute");
 std::fs::write(root.join("code/probe.dm"),PRESENT_TYPE).unwrap();run(&mut host,&request);let present=observed(&host,&root);assert_eq!(present.0,[(present.1,present.1+1,"undefined field: \"field\" on /datum/result".to_owned())]);assert_eq!(queries.db().stats(Kind(28)).computed,semantics+1,"a real missing->present type changes return binding while both code identities stay equal");assert_eq!(queries.db().stats(Kind(4)).computed,syntax);
 let shifted=format!("/datum/unrelated_shift\n// α both unchanged bodies shift\n{PRESENT_TYPE}// later file shift\n");std::fs::write(root.join("code/probe.dm"),shifted).unwrap();run(&mut host,&request);let shifted=observed(&host,&root);assert_eq!(shifted.0,[(shifted.1,shifted.1+1,"undefined field: \"field\" on /datum/result".to_owned())]);assert_ne!(present.1,shifted.1);assert_eq!(queries.db().stats(Kind(28)).computed,semantics+1,"unchanged actual callee/type answers must cut off semantic reevaluation");assert_eq!(queries.db().stats(Kind(4)).computed,syntax);
}
#[test]fn current_callable_actual_callee_setting_edit_retracts_old_type_dependency_and_changes_caller_receiver(){
 let(mut host,request,root)=current_callee_fixture(PRESENT_TYPE);let queries=host.query_db().clone();run(&mut host,&request);let first=observed(&host,&root);assert_eq!(first.0.len(),1);let(old_parent,old_type,_)=current(&host,|snapshot|{let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap();queries.current_variable_keys_for_test(input.input(),1,ResolveQuery::Type(SymbolId::of("/datum/result")))});assert!(queries.db().dependants(&[old_type]).contains(&old_parent));let semantics=queries.db().stats(Kind(28)).computed;
 let changed="/datum/result\n/datum/other\n/proc/choose()\n    set SpacemanDMM_return_type=/datum/other\n    return null\n/proc/probe()\n    return choose().field\n";std::fs::write(root.join("code/probe.dm"),changed).unwrap();run(&mut host,&request);let changed=observed(&host,&root);assert_eq!(changed.0,[(changed.1,changed.1+1,"undefined field: \"field\" on /datum/other".to_owned())]);assert_eq!(queries.db().stats(Kind(28)).computed,semantics+1);assert!(!queries.db().dependants(&[old_type]).contains(&old_parent),"changing the actual callee directive retracts the caller's previous return-type edge");let(parent,new_type,_)=current(&host,|snapshot|{let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap();queries.current_variable_keys_for_test(input.input(),1,ResolveQuery::Type(SymbolId::of("/datum/other")))});assert_eq!(parent,old_parent,"caller code is unchanged; only actual source meaning changed");assert!(queries.db().dependants(&[new_type]).contains(&parent));
}

#[test]fn current_callable_same_metadata_body_choice_is_current_even_with_old_archive_retained(){
 fn read(host:&crate::runner_host::BuildHost,root:&Path)->(dm_analysis::checks_undefined_variable::CurrentUndefinedDisposition,Vec<(usize,usize,String)>){current(host,|snapshot|{let mut rows=Vec::new();let actual=snapshot.visit_current_variable_diagnostics(1,&root.join("code/probe.dm"),Some(&root.join("SpacemanDMM.toml")),&snapshot.tree,|row|{rows.push((row.span.start,row.span.end,row.diagnostic.message.clone()));Ok(())});println!("CURRENT_CALLEE_CODE_CHOICE={actual:?} rows={rows:?}");(actual.unwrap(),rows)})}
 fn native_chain(host:&crate::runner_host::BuildHost)->Vec<u8>{current(host,|snapshot|{dm_ir::Resolver::resolve(snapshot.tree.as_ref(),ResolveQuery::SourceDeclarationChain{owner:SymbolId::of("/"),name:SymbolId::of("choose"),verb:false}).canonical_bytes()})}
 let(mut host,request,root)=current_callee_fixture(PRESENT_TYPE);let queries=host.query_db().clone();run(&mut host,&request);let first=read(&host,&root);assert_eq!(first.1.len(),1);let metadata=native_chain(&host);let semantic=queries.db().stats(Kind(28)).computed;let syntax=queries.db().stats(Kind(4)).computed;
 let retained_old=current(&host,|snapshot|{let owner=snapshot.original_checker_request_input(&snapshot.tree).unwrap();Arc::clone(owner.input())});
 let old_callee=Arc::downgrade(retained_old.archive().syntax_inputs().unwrap()[0].original_code_owner().unwrap());let old_caller=Arc::downgrade(retained_old.archive().syntax_inputs().unwrap()[1].original_code_owner().unwrap());
 let(parent,chain,_)=current(&host,|snapshot|{let owner=snapshot.original_checker_request_input(&snapshot.tree).unwrap();queries.current_variable_keys_for_test(owner.input(),1,ResolveQuery::SourceDeclarationChain{owner:SymbolId::of("/"),name:SymbolId::of("choose"),verb:false})});assert!(queries.db().dependants(&[chain]).contains(&parent));
 for(index,body)in ["return 1","return 1 +","return null"].into_iter().enumerate(){
  let source=PRESENT_TYPE.replace("return null",body);std::fs::write(root.join("code/probe.dm"),&source).unwrap();run(&mut host,&request);assert_eq!(native_chain(&host),metadata,"this control changes actual BODY choice while native signature/settings metadata is byte-identical");
  let incremental=read(&host,&root);let(mut fresh,fresh_request,fresh_root)=current_callee_fixture(&source);run(&mut fresh,&fresh_request);let independent=read(&fresh,&fresh_root);assert_eq!(incremental,independent,"complete current selected rows must match genuine fresh execution for {body}");
  assert_eq!(queries.db().stats(Kind(28)).computed,semantic+index as u64+1,"the actual current callee code choice invalidates the existing caller contribution");assert_eq!(queries.db().stats(Kind(4)).computed,syntax+index as u64+1,"only the edited callee parses; unchanged caller uses its SAME canonical product");
  current(&host,|snapshot|{let inputs=snapshot.body_archive.as_ref().unwrap().syntax_inputs().unwrap();assert!(std::sync::Weak::ptr_eq(&old_caller,&Arc::downgrade(inputs[1].original_code_owner().unwrap())));if index==0{assert!(!std::sync::Weak::ptr_eq(&old_callee,&Arc::downgrade(inputs[0].original_code_owner().unwrap())));}});
 }
 assert_eq!(retained_old.archive().len(),2,"genuine old input/source/archive stayed live through all edits; old child liveness cannot authorize its current choice");assert_eq!(queries.effect_graph_work_for_test(),0);
 let stable=queries.db().stats(Kind(28)).computed;let parses=queries.db().stats(Kind(4)).computed;std::fs::write(root.join("code/probe.dm"),format!("/datum/unrelated_shift\n// α source-only shift\n{PRESENT_TYPE}")).unwrap();run(&mut host,&request);let shifted=read(&host,&root);assert_eq!(shifted.1.len(),first.1.len());assert_eq!(shifted.1[0].2,first.1[0].2);assert_ne!(shifted.1[0].0,first.1[0].0);assert_eq!(queries.db().stats(Kind(28)).computed,stable,"actual unchanged code-choice answers cut off semantic work");assert_eq!(queries.db().stats(Kind(4)).computed,parses);
}


#[test]
fn current_callable_actual_parent_switch_retracts_previous_target_dependencies() {
    const SOURCE: &str = concat!(
        "/datum/result_a\n/datum/result_b\n",
        "/datum/base_a/proc/probe()\n",
        "    set SpacemanDMM_return_type=/datum/result_a\n    return null\n",
        "/datum/base_b/proc/probe()\n",
        "    set SpacemanDMM_return_type=/datum/result_b\n    return null\n",
        "/datum/child\n    parent_type = /datum/base_a\n",
        "/datum/child/probe()\n    return ..().field\n",
    );

    let child = SymbolId::of("/datum/child");
    let probe = SymbolId::of("probe");
    let chain = |owner| ResolveQuery::SourceDeclarationChain { owner, name: probe, verb: false };
    let ancestry = ResolveQuery::Ancestry(child);
    let child_chain = chain(child);
    let old_target = [ResolveQuery::Type(SymbolId::of("/datum/result_a")), chain(SymbolId::of("/datum/base_a"))];
    let new_target = [ResolveQuery::Type(SymbolId::of("/datum/result_b")), chain(SymbolId::of("/datum/base_b"))];

    let ordinal = |snapshot: &SourceSnapshot| {
        let archive = snapshot.body_archive.as_ref().unwrap();
        (0..archive.len())
            .find(|&ordinal| archive.callables().identity(ordinal).is_some_and(|id| id.owner == child && id.name == probe))
            .expect("actual child override is in the archived source")
    };
    let observe = |host: &crate::runner_host::BuildHost, root: &Path, receiver: &str| {
        current(host, |snapshot| {
            let archive = snapshot.body_archive.as_ref().unwrap();
            let mut rows = Vec::new();
            let disposition = snapshot.visit_current_variable_diagnostics(
                ordinal(snapshot), &root.join("deepquarry.dme"), None, &snapshot.tree, |row| {
                    rows.push((row.span.start, row.span.end, row.diagnostic.message.clone()));
                    Ok(())
                },
            ).unwrap();
            assert_eq!(disposition, dm_analysis::checks_undefined_variable::CurrentUndefinedDisposition::Evaluated);
            let [(start, end, message)] = rows.as_slice() else { panic!("expected exactly one member diagnostic: {rows:?}") };
            assert_eq!(message, &format!("undefined field: \"field\" on {receiver}"));
            assert_eq!(archive.expanded_source().get(*start..*end), Some("."));
            let point = archive.source_note_point(*start).unwrap();
            let (line, original) = SOURCE.lines().enumerate().find(|(_, line)| line.contains("..().field")).unwrap();
            assert_eq!((point.line, point.byte_column), (line + 1, original.find(".field").unwrap() + 1));
            [ancestry, child_chain].map(|query| dm_ir::Resolver::resolve(snapshot.tree.as_ref(), query).canonical_bytes())
        })
    };

    let (mut host, request, root) = fixture(SOURCE);
    let queries = host.query_db().clone();
    let keys = |host: &crate::runner_host::BuildHost, query| {
        current(host, |snapshot| {
            let input = snapshot.original_checker_request_input(&snapshot.tree).unwrap();
            queries.current_variable_keys_for_test(input.input(), ordinal(snapshot), query)
        })
    };

    run(&mut host, &request);
    let original_answers = observe(&host, &root, "/datum/result_a");
    let (parent, ancestry_leaf, driver) = keys(&host, ancestry);
    let (_, child_chain_leaf, _) = keys(&host, child_chain);
    let old_leaves = old_target.map(|query| keys(&host, query).1);
    for leaf in [ancestry_leaf, child_chain_leaf].into_iter().chain(old_leaves) {
        assert!(queries.db().dependants(&[leaf]).contains(&parent), "missing initial edge to {leaf:?}");
    }
    let semantic = queries.db().stats(Kind(28)).computed;

    let changed = SOURCE.replace("parent_type = /datum/base_a", "parent_type = /datum/base_b");
    std::fs::write(root.join("code/probe.dm"), &changed).unwrap();
    run(&mut host, &request);
    let changed_answers = observe(&host, &root, "/datum/result_b");
    for (before, after) in original_answers.iter().zip(changed_answers.iter()) {
        assert_ne!(before, after, "actual child ancestry/declaration-chain answer must change");
    }
    assert_eq!(keys(&host, ancestry), (parent, ancestry_leaf, driver));
    assert_eq!(keys(&host, child_chain).1, child_chain_leaf);
    assert_eq!(queries.db().stats(Kind(28)).computed, semantic + 1);
    for leaf in old_leaves {
        assert!(!queries.db().dependants(&[leaf]).contains(&parent), "old target edge was not retracted: {leaf:?}");
    }
    let new_leaves = new_target.map(|query| keys(&host, query).1);
    for leaf in [ancestry_leaf, child_chain_leaf].into_iter().chain(new_leaves) {
        assert!(queries.db().dependants(&[leaf]).contains(&parent), "missing current edge to {leaf:?}");
    }
    let (mut fresh, fresh_request, fresh_root) = fixture(&changed);
    run(&mut fresh, &fresh_request);
    assert_eq!(changed_answers, observe(&fresh, &fresh_root, "/datum/result_b"));
}

#[test]
fn current_full_body_consumes_ordinary_call_witness_and_reports_original_missing_proc(){
 use dm_analysis::checker_effects::OriginalDiagnosticPhase;
 let(mut host,request,_)=fixture("/proc/probe()\n    missing_statement_target()\n    return 0\n");
 let db=host.query_db().clone();
 run(&mut host,&request);
 let observed=current(&host,|snapshot|{
  let owner=snapshot.original_checker_request_input(&snapshot.tree).unwrap();
  db.original_current_body_bytes_for_test(owner.input(),0,|rows|{
   let rows:Vec<_>=rows.iter().filter(|row|row.phase()==OriginalDiagnosticPhase::Body).collect();
   assert_eq!(rows.len(),1);
   let diagnostic=rows[0].diagnostic();
   let at=snapshot.body_archive.as_ref().unwrap().source_note_point(diagnostic.span.start).unwrap();
   assert_eq!((at.line,at.byte_column),(2,5));
   assert_eq!(diagnostic.family,"undefined_proc");
   assert_eq!(diagnostic.severity,dm_analysis::checks::Severity::Error);
   assert!(diagnostic.notes.is_empty());
   diagnostic.message.as_bytes().to_vec()
  }).unwrap()
 });
 assert_eq!(observed,b"undefined proc: \"missing_statement_target\" on (global)");
}

#[test]
fn opt_in_original_kind17_reuses_canonical_callees_and_matches_absolute_graph_bytes(){
 const SOURCE:&str=concat!(
  "/proc/leaf()\n    return sleep()\n",
  "/proc/probe(item)\n",
  "    set SpacemanDMM_should_not_sleep = 1\n",
  "    set SpacemanDMM_made_up = 1\n",
  "    return leaf()\n",
  "/proc/note(item)\n    return item.field\n",
 );
 assert_current_graph_matches_absolute(SOURCE);
}

#[test]
fn opt_in_original_kind17_mixed_setting_scope_matches_absolute_graph_bytes(){
 const SOURCE:&str=concat!(
  "/proc/leaf()\n    return sleep()\n",
  "/proc/probe(item)\n",
  "    set SpacemanDMM_should_not_sleep = 1\n",
  "    set SpacemanDMM_made_up = 1\n",
  "    var/value = item\n",
  "    if(value)\n        leaf()\n",
  "    return value\n",
  "/proc/note(item)\n    return item.field\n",
 );
 assert_current_graph_matches_absolute(SOURCE);
}

fn assert_current_graph_matches_absolute(source:&str){
 use dm_analysis::checker_effects::EffectInput;
 let(mut host,mut request,root)=fixture(source);
 let env=root.join("code/probe.dm");
 request.policy_inputs.as_mut().unwrap().files.push(crate::policy_request::PolicyInputFile{path:env.clone(),role:crate::policy_request::PolicyInputRole::DmSource,required:true});
 let configuration=root.join("SpacemanDMM.toml");
 std::fs::write(&configuration,b"").unwrap();
 let db=host.query_db().clone();run(&mut host,&request);
 current(&host,|snapshot|{
  let absolute=snapshot.original_checker_request_input(&snapshot.tree).unwrap();
  let receipt=snapshot.diagnostic_declarations.as_ref().unwrap();
  let archive=Arc::clone(absolute.input().archive());
  let selected=EffectInput::original_checker_source_with_current_bodies(archive,absolute.input().profile(),receipt,db.as_ref()).unwrap();
  let before=db.db().stats(Kind(4)).computed;
  let render=|input:&Arc<EffectInput>|{
   let mut bytes=Vec::new();
   let clean=snapshot.write_original_ordered_checker_using(input,&env,Some(&configuration),&snapshot.tree,&mut bytes).unwrap();
   assert!(!clean);
   bytes
  };
  let canonical=render(&selected);
  let syntax=db.db().stats(Kind(4)).computed;
  assert_eq!(syntax-before,3,"one canonical syntax owner for each actual body; no absolute sibling");
  assert_eq!(render(&selected),canonical);
  assert_eq!(db.db().stats(Kind(4)).computed,syntax);
  let rows:serde_json::Value=serde_json::from_slice(&canonical).unwrap();
  let tags:Vec<_>=rows["diagnostics"].as_array().unwrap().iter().filter_map(|row|row["registration_tag"].as_str()).collect();
  assert!(tags.contains(&"unknown_linter_setting"),"{rows}");
  assert!(tags.contains(&"field_access_static_type"),"{rows}");
  assert!(tags.contains(&"must_not_sleep"),"{rows}");
  assert_eq!(canonical,render(absolute.input()),"same complete ordered production wire, including the actual effect graph");
 });
}

#[test]
fn opt_in_original_kind17_retracts_edited_callee_sleep_and_matches_fresh_canonical_report(){
 use dm_analysis::checker_effects::EffectInput;
 use dm_tree::frontend::BodyCodeIdentity;
 use std::sync::Weak;
 const BEFORE:&str=concat!(
  "/proc/leaf()\n    return sleep()\n",
  "/proc/probe(item)\n",
  "    set SpacemanDMM_should_not_sleep = 1\n",
  "    set SpacemanDMM_made_up = 1\n",
  "    return leaf()\n",
  "/proc/note(item)\n    return item.field\n",
 );

 fn prepare(source:&str)->(crate::runner_host::BuildHost,crate::request::BuildRequest,std::path::PathBuf){
  use crate::policy_request::{PolicyInputFile,PolicyInputRole};
  let(host,mut request,root)=fixture(source);
  request.policy_inputs.as_mut().unwrap().files.push(PolicyInputFile{path:root.join("code/probe.dm"),role:PolicyInputRole::DmSource,required:true});
  std::fs::write(root.join("SpacemanDMM.toml"),b"").unwrap();
  (host,request,root)
 }

 fn render(host:&crate::runner_host::BuildHost,root:&Path)->(Vec<serde_json::Value>,[Weak<BodyCodeIdentity>;3]){
  let db=host.query_db();
  let env=root.join("code/probe.dm");
  let config=root.join("SpacemanDMM.toml");
  current(host,|snapshot|{
   let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap();
   let receipt=snapshot.diagnostic_declarations.as_ref().unwrap();
   let canonical=EffectInput::original_checker_source_with_current_bodies(
    Arc::clone(input.input().archive()),input.input().profile(),receipt,db.as_ref(),
   ).unwrap();
   let archive=canonical.archive();
   let codes=["leaf","probe","note"].map(|name|{
    let ordinal=(0..archive.len()).find(|&ordinal|archive.callables().identity(ordinal).is_some_and(|id|id.name==SymbolId::of(name))).unwrap();
    Arc::downgrade(archive.syntax_inputs().unwrap()[ordinal].original_code_owner().unwrap())
   });
   let mut bytes=Vec::new();
   assert!(!snapshot.write_original_ordered_checker_using(&canonical,&env,Some(&config),&snapshot.tree,&mut bytes).unwrap());
   let mut report:serde_json::Value=serde_json::from_slice(&bytes).unwrap();
   let rows=report["diagnostics"].as_array_mut().unwrap();
   for row in rows.iter_mut(){
    let file=Path::new(row["file"].as_str().unwrap());
    if file.is_absolute(){
     assert_eq!(dm_preprocess::regions::canonical_path(file),dm_preprocess::regions::canonical_path(&env));
    }else{
     assert!(file.ends_with(Path::new("code/probe.dm")),"unexpected original registration: {file:?}");
    }
    // Independent scratch roots legitimately differ. Every remaining field,
    // including registration tag, order, physical coordinates and note bytes,
    // is compared without normalization.
    row["file"]="code/probe.dm".into();
   }
   (std::mem::take(rows),codes)
  })
 }

 let changed=BEFORE.replace("return sleep()","return null");
 let(mut host,request,root)=prepare(BEFORE);
 let db=host.query_db().clone();
 run(&mut host,&request);
 let (before,old_codes)=render(&host,&root);
 let syntax=db.db().stats(Kind(4)).computed;
 assert_eq!(before.iter().filter(|row|row["registration_tag"]=="must_not_sleep").count(),1,"{before:?}");
 let unaffected:Vec<_>=before.into_iter().filter(|row|row["registration_tag"]!="must_not_sleep").collect();
 assert!(unaffected.iter().any(|row|row["registration_tag"]=="unknown_linter_setting"));
 assert!(unaffected.iter().any(|row|row["registration_tag"]=="field_access_static_type"));

 std::fs::write(root.join("code/probe.dm"),&changed).unwrap();
 run(&mut host,&request);
 let (after,new_codes)=render(&host,&root);
 assert_eq!(after,unaffected,"only the graph row whose callee changed should retract");
 assert!(!Weak::ptr_eq(&old_codes[0],&new_codes[0]),"edited leaf needs a new native body");
 for ordinal in [1,2]{
  assert!(Weak::ptr_eq(&old_codes[ordinal],&new_codes[ordinal]),"unchanged caller/unrelated body retains its syntax identity");
 }
 assert_eq!(db.db().stats(Kind(4)).computed,syntax+1,"only the edited callee is parsed");

 let(mut fresh,fresh_request,fresh_root)=prepare(&changed);
 run(&mut fresh,&fresh_request);
 assert_eq!(render(&fresh,&fresh_root).0,after,"retained output equals independent cold canonical output");
}

#[test]
fn current_original_statement_call_evaluates_actual_positional_arguments_in_source_order(){
 use dm_analysis::checker_effects::OriginalDiagnosticPhase;
 let(mut host,request,_)=fixture("/proc/sink(a,b)\n    return null\n/proc/probe()\n    sink(missing_first, missing_second)\n    return null\n");
 let db=host.query_db().clone();
 run(&mut host,&request);
 current(&host,|snapshot|{
  let owner=snapshot.original_checker_request_input(&snapshot.tree).unwrap();
  let archive=owner.input().archive();
  let bytes=db.original_current_body_bytes_for_test(owner.input(),1,|rows|{
   let rows:Vec<_>=rows.iter().filter(|row|row.phase()==OriginalDiagnosticPhase::Body).collect();
   assert_eq!(rows.len(),2);
   for (row,(name,column)) in rows.into_iter().zip([("missing_first",10),("missing_second",25)]){
    let diagnostic=row.diagnostic();
    let at=archive.source_note_point(diagnostic.span.start).unwrap();
    assert_eq!((at.line,at.byte_column),(4,column));
    assert_eq!(diagnostic.family,"undefined_variable");
    assert_eq!(diagnostic.message,format!("undefined var: {name:?}"));
    assert!(diagnostic.notes.is_empty());
   }
   b"observed".to_vec()
  }).unwrap();
  assert_eq!(bytes,b"observed");
 });
}

#[test]
fn current_original_single_local_visits_initializer_before_binding_and_return() {
 use dm_analysis::checker_effects::OriginalDiagnosticPhase;
 let source = "/proc/probe()\n    var/local = missing_initializer\n    return local\n";
 let (mut host, request, _) = fixture(source);
 let db = host.query_db().clone();
 run(&mut host, &request);
 current(&host, |snapshot| {
  let owner = snapshot.original_checker_request_input(&snapshot.tree).unwrap();
  db.original_current_body_bytes_for_test(owner.input(), 0, |rows| {
   let rows: Vec<_> = rows.iter().filter(|row| row.phase() == OriginalDiagnosticPhase::Body).collect();
   assert_eq!(rows.len(), 1);
   let diagnostic = rows[0].diagnostic();
   let point = snapshot.body_archive.as_ref().unwrap().source_note_point(diagnostic.span.start).unwrap();
   assert_eq!((point.line, point.byte_column), (2, 17));
   assert_eq!(diagnostic.family, "undefined_variable");
   assert_eq!(diagnostic.severity, dm_analysis::checks::Severity::Error);
   assert_eq!(diagnostic.message, "undefined var: \"missing_initializer\"");
   assert!(diagnostic.notes.is_empty());
   Vec::new()
  }).unwrap();
 });
}

#[test]
fn current_original_simple_assignment_visits_lhs_then_rhs_and_matches_absolute_bytes() {
 use dm_analysis::checker_effects::{ExecutionAdmission, OriginalBodyDiagnostic, OriginalDiagnosticPhase};
 fn encode(rows: &[OriginalBodyDiagnostic]) -> Vec<u8> {
  format!("{:?}", rows.iter().map(|row| (row.phase(), row.location(), row.registration_tag(), row.diagnostic())).collect::<Vec<_>>()).into_bytes()
 }
 let mut source = String::from("/proc/probe()\n    missing_left += missing_right\n    var/value = 1\n");
 for op in ["+=", "-=", "*=", "/=", "%=", "|=", "&=", "^=", "<<=", ">>="] {
  source.push_str(&format!("    value {op} 1\n"));
 }
 source.push_str("    return null\n");
 let (mut host, request, _) = fixture(&source);
 let db = host.query_db().clone();
 run(&mut host, &request);
 current(&host, |snapshot| {
  let owner = snapshot.original_checker_request_input(&snapshot.tree).unwrap();
  let input = owner.input();
  let current = db.original_current_body_bytes_for_test(input, 0, |rows| {
   let body: Vec<_> = rows.iter().filter(|row| row.phase() == OriginalDiagnosticPhase::Body).collect();
   assert_eq!(body.len(), 2);
   for (row, (name, column)) in body.into_iter().zip([("missing_left", 5), ("missing_right", 21)]) {
    let diagnostic = row.diagnostic();
    let point = input.archive().source_note_point(diagnostic.span.start).unwrap();
    assert_eq!((point.line, point.byte_column), (2, column));
    assert_eq!(diagnostic.family, "undefined_variable");
    assert_eq!(diagnostic.message, format!("undefined var: {name:?}"));
   }
   encode(rows)
  }).unwrap();
  let absolute = input.compute_body_checked_controlled(0, snapshot.tree.as_ref(), &ExecutionAdmission::default(), &|| Ok(())).unwrap();
  assert_eq!(current, absolute.with_original_diagnostics(input, encode).unwrap());
 });
}

#[test]
fn current_original_while_block_visits_condition_body_and_post_loop_in_pinned_order() {
 use dm_analysis::checker_effects::{ExecutionAdmission, OriginalBodyDiagnostic, OriginalDiagnosticPhase};
 fn encode(rows: &[OriginalBodyDiagnostic]) -> Vec<u8> {
  format!("{:?}", rows.iter().map(|row| (row.phase(), row.location(), row.registration_tag(), row.diagnostic())).collect::<Vec<_>>()).into_bytes()
 }
 let source = concat!(
  "/proc/probe()\n",
  "    while(missing_condition)\n",
  "        return missing_body\n",
  "    return missing_after\n",
 );
 let (mut host, request, _) = fixture(source);
 let db = host.query_db().clone();
 run(&mut host, &request);
 current(&host, |snapshot| {
  let owner = snapshot.original_checker_request_input(&snapshot.tree).unwrap();
  let input = owner.input();
  let canonical = db.original_current_body_bytes_for_test(input, 0, |rows| {
   assert_eq!(rows.len(), 3);
   let expected = [("missing_condition", 2, 11), ("missing_body", 3, 16), ("missing_after", 4, 12)];
   for (row, (name, line, column)) in rows.iter().zip(expected) {
    assert_eq!(row.phase(), OriginalDiagnosticPhase::Body);
    let diagnostic = row.diagnostic();
    let point = input.archive().source_note_point(diagnostic.span.start).unwrap();
    assert_eq!((point.line, point.byte_column), (line, column));
    assert_eq!(diagnostic.family, "undefined_variable");
    assert_eq!(diagnostic.message, format!("undefined var: {name:?}"));
   }
   encode(rows)
  }).unwrap();
  let absolute = input.compute_body_checked_controlled(0, snapshot.tree.as_ref(), &ExecutionAdmission::default(), &|| Ok(())).unwrap();
  assert_eq!(canonical, absolute.with_original_diagnostics(input, encode).unwrap());
 });
}

#[test]
fn current_original_decimal_switch_reissues_case_cursors_and_matches_absolute_body() {
 use dm_analysis::checker_effects::{ExecutionAdmission, OriginalBodyDiagnostic, OriginalDiagnosticPhase};
 use dm_tree::frontend::SettingExpressionQueries;
 fn encode(rows: &[OriginalBodyDiagnostic]) -> Vec<u8> {
  format!("{:?}", rows.iter().map(|row| (row.phase(), row.location(), row.registration_tag(), row.diagnostic())).collect::<Vec<_>>()).into_bytes()
 }
 let source = concat!(
  "/proc/probe()\n",
  "    switch(missing_selector)\n",
  "        if(1)\n            return missing_first\n",
  "        if(2)\n            return missing_second\n",
  "    return missing_after\n",
 );
 let (mut host, request, _) = fixture(source);
 let db = host.query_db().clone();
 run(&mut host, &request);
 current(&host, |snapshot| {
  let owner = snapshot.original_checker_request_input(&snapshot.tree).unwrap();
  let input = owner.input();
  let archive = input.archive();
  let canonical = db.original_current_body_bytes_for_test(input, 0, |rows| {
   assert_eq!(rows.len(), 4);
   let expected = [("missing_selector", 2, 12), ("missing_first", 4, 20), ("missing_second", 6, 20), ("missing_after", 7, 12)];
   for (row, (name, line, column)) in rows.iter().zip(expected) {
    assert_eq!(row.phase(), OriginalDiagnosticPhase::Body);
    let diagnostic = row.diagnostic();
    let point = archive.source_note_point(diagnostic.span.start).unwrap();
    assert_eq!((point.line, point.byte_column), (line, column));
    assert_eq!(diagnostic.family, "undefined_variable");
    assert_eq!(diagnostic.message, format!("undefined var: {name:?}"));
   }
   encode(rows)
  }).unwrap();
  let mut cursors = Vec::new();
  SettingExpressionQueries::with_declaration_admission(db.as_ref(), &mut |admission| {
   archive.with_current_body_checked(0, admission, |body| {
    let statements = body.syntax().canonical_statement_storage();
    let dm_syntax::StatementKind::Switch { cases, .. } = &statements.parsed().statements[0].kind else { panic!("actual current switch"); };
    body.with_original_body_source(admission, |source| {
     for case in cases {
      cursors.push(source.original_switch_case_cursor(case.original_site)?.unwrap());
     }
     Ok(())
    })?
   })
  }).unwrap();
  let absolute_syntax = archive.parse_checked(0).unwrap();
  let dm_syntax::StatementKind::Switch { cases, .. } = &absolute_syntax.statement_body().parsed().statements[0].kind else { panic!("actual absolute switch"); };
  assert_eq!(cursors, cases.iter().map(|case| case.original_site.cursor.unwrap()).collect::<Vec<_>>());
  let absolute = input.compute_body_checked_controlled(0, snapshot.tree.as_ref(), &ExecutionAdmission::default(), &|| Ok(())).unwrap();
  assert_eq!(canonical, absolute.with_original_diagnostics(input, encode).unwrap());
 });
}

#[test]
fn current_original_blocks_do_not_borrow_an_opener_across_an_authored_semicolon() {
 use dm_tree::frontend::BodySyntaxFailure;
 let source = concat!(
  "/proc/bad_while(argument)\n    while(argument) ;\n        return 0\n",
  "/proc/bad_switch(argument)\n    switch(argument)\n        if(1) ;\n            return 0\n",
 );
 let (mut host, request, _) = fixture(source);
 let db = host.query_db().clone();
 run(&mut host, &request);
 current(&host, |snapshot| {
  let owner = snapshot.original_checker_request_input(&snapshot.tree).unwrap();
  let archive = owner.input().archive();
  for name in ["bad_while", "bad_switch"] {
   let ordinal = (0..archive.len()).find(|&ordinal| {
    archive.callables().identity(ordinal).is_some_and(|id| id.name == SymbolId::of(name))
   }).expect("actual bad block callable");
   let error = db.original_current_body_bytes_for_test(owner.input(), ordinal, |_| {
    panic!("{name} published a report despite its authored semicolon")
   }).unwrap_err();
   match error {
    BodySyntaxFailure::Syntax(_) => (),
    BodySyntaxFailure::Operational(actual) => assert_eq!(actual.kind(), std::io::ErrorKind::Unsupported, "{name}: {actual}"),
   }
  }
 });
}

#[test]
fn current_original_compact_chunk_records_real_kind4_and_negative_model_reads() {
 use dm_analysis::checker_effects::EffectInput;
 const SOURCE: &str = concat!(
  "/datum/result\n",
  "/proc/leaf()\n    set SpacemanDMM_return_type = /datum/result\n    return null\n",
  "/proc/probe()\n    return leaf().field\n",
  "/proc/negative()\n    return missing_value\n",
 );
 let (mut host, request, root) = fixture(SOURCE);
 let db = host.query_db().clone();
 let observe = |host: &crate::runner_host::BuildHost| current(host, |snapshot| {
  let absolute = snapshot.original_checker_request_input(&snapshot.tree).unwrap();
  let input = EffectInput::original_checker_source_with_current_bodies(
   Arc::clone(absolute.input().archive()), absolute.input().profile(),
   snapshot.diagnostic_declarations.as_ref().unwrap(), db.as_ref(),
  ).unwrap();
  let roster = input.archive().callables();
  let order = roster.source_order();
  assert_eq!(order.len(), 3);
  for (&ordinal, expected) in order.iter().zip(["leaf", "probe", "negative"]) {
   assert_eq!(roster.identity(ordinal).unwrap().name, SymbolId::of(expected));
  }
  let body_runs = db.db().stats(Kind(17)).computed;
  let lookup_runs = db.db().stats(Kind(21)).computed;
  let (chunk, model, rows) = db.compact_original_chunk_proof_for_test(&input, 1, 2).unwrap();
  assert!(db.db().dependants(&[model]).contains(&chunk));
  for &ordinal in order {
   let key = crate::query_db::QueryDb::compact_original_chunk_body_key_for_test(&input, ordinal);
   assert!(db.db().dependants(&[key]).contains(&chunk), "missing real canonical syntax edge for {ordinal}");
  }
  assert_eq!(db.db().stats(Kind(17)).computed, body_runs);
  assert_eq!(db.db().stats(Kind(21)).computed, lookup_runs);
  let ran = db.db().stats(Kind(32)).computed;
  let (_, _, warm) = db.compact_original_chunk_proof_for_test(&input, 1, 2).unwrap();
  assert_eq!(warm, rows);
  assert_eq!(db.db().stats(Kind(32)).computed, ran);
  let field = ResolveQuery::SourceVarDeclaration { owner: SymbolId::of("/datum/result"), name: SymbolId::of("field") };
  let negative = ResolveQuery::SourceVarDeclaration { owner: SymbolId::of("/"), name: SymbolId::of("missing_value") };
  assert!(rows.contains(&(negative, true)));
  (model, rows.into_iter().find(|(query, _)| *query == field).expect("actual field lookup").1)
 });
 run(&mut host, &request);
 let (first_model, missing) = observe(&host);
 assert!(missing);
 std::fs::write(root.join("code/probe.dm"), SOURCE.replacen("/datum/result\n", "/datum/result\n    var/field\n", 1)).unwrap();
 run(&mut host, &request);
 let (next_model, missing) = observe(&host);
 assert_ne!(first_model, next_model, "new immutable native model reissues the chunk");
 assert!(!missing);
}


fn admit_compact_original_report_inputs(
    request: &mut crate::request::BuildRequest,
    environment: &std::path::Path,
) {
    use crate::policy_request::{PolicyInputFile, PolicyInputRole};
    let selected = dm_analysis::check_configuration::select(environment, None);
    request.policy_inputs.as_mut().unwrap().files.extend([
        PolicyInputFile {
            path: environment.to_path_buf(), role: PolicyInputRole::DmSource, required: true,
        },
        // The real configuration capture must prove optional autodetect absence.
        PolicyInputFile {
            path: selected.path, role: PolicyInputRole::Configuration, required: false,
        },
    ]);
}

#[test]
fn current_original_compact_chunk_stages_both_phases_once_and_keeps_failed_prefix_private() {
 use dm_analysis::{check_policy::DiagnosticSeverity, checker_effects::{EffectInput, OriginalBodyDiagnostic}};
 use std::io::{self, Write};
 const SOURCE: &str = "/proc/probe()\n    set SpacemanDMM_made_up = 1\n    return missing_value\n";
 fn fail_render(_: &EffectInput, _: &OriginalBodyDiagnostic, _: DiagnosticSeverity, out: &mut dyn Write) -> io::Result<()> {
  out.write_all(b"unpublishable prefix")?;
  Err(io::Error::from_raw_os_error(1450))
 }
 let (mut host, mut request, root) = fixture(SOURCE);
 let environment = root.join("code/probe.dm");
 admit_compact_original_report_inputs(&mut request, &environment);
 let cache = request.cache_root.as_ref().unwrap().clone();
 std::fs::create_dir_all(&cache).unwrap();
 let db = host.query_db().clone();
 run(&mut host, &request);
 current(&host, |snapshot| {
  let absolute = snapshot.original_checker_request_input(&snapshot.tree).unwrap();
  let input = EffectInput::original_checker_source_with_current_bodies(
   Arc::clone(absolute.input().archive()), absolute.input().profile(),
   snapshot.diagnostic_declarations.as_ref().unwrap(), db.as_ref(),
  ).unwrap();
  snapshot.with_effect_scope(&input, &environment, None, &snapshot.tree, |db, scope| {
   let mut prelude = Vec::new();
   let mut body = Vec::new();
   let before = db.db().stats(Kind(32)).computed;
   let standalone = db.db().stats(Kind(17)).computed;
   db.stage_compact_original_chunk_for_test(&input, scope, 0, 1, &cache,
    super::original_ordered_wire::write_body_diagnostic_row, &mut prelude, &mut body)?;
   assert_eq!(db.db().stats(Kind(32)).computed, before + 1);
   assert_eq!(db.db().stats(Kind(17)).computed, standalone);
   let actual_prelude: serde_json::Value = serde_json::from_slice(&prelude)?;
   let actual_body: serde_json::Value = serde_json::from_slice(&body)?;
   let mut expected = [Vec::new(), Vec::new()];
   snapshot.visit_original_body_diagnostics(&environment, None, &snapshot.tree, |_, row| {
    let Some(severity) = scope.policy().register(row.registration_tag(), row.default_level())
     .filter(|severity| *severity <= DiagnosticSeverity::Info) else { return Ok(()); };
    let mut bytes = Vec::new();
    super::original_ordered_wire::write_body_diagnostic_row(absolute.input(), row, severity, &mut bytes)?;
    let index = if row.phase() == dm_analysis::checker_effects::OriginalDiagnosticPhase::Prelude { 0 } else { 1 };
    expected[index].push(serde_json::from_slice::<serde_json::Value>(&bytes)?);
    Ok(())
   })?;
   assert_eq!(actual_prelude, serde_json::json!(expected[0]));
   assert_eq!(actual_body, serde_json::json!(expected[1]));
   assert_eq!(expected[0].len(), 1);
   assert_eq!(expected[1].len(), 1);

   prelude.clear();
   body.clear();
   let error = db.stage_compact_original_chunk_for_test(&input, scope, 0, 1, &cache,
    fail_render, &mut prelude, &mut body).unwrap_err();
   assert_eq!(error.raw_os_error(), Some(1450));
   assert!(prelude.is_empty() && body.is_empty());
   assert_eq!(db.effect_graph_work_for_test(), 0);
   Ok(())
  }).unwrap();
 });
}

#[test]
fn current_original_archived_body_windows_keep_global_phase_order_and_atomic_staging() {
 use dm_analysis::{check_policy::DiagnosticSeverity, checker_effects::{EffectInput, OriginalBodyDiagnostic}};
 use std::io::{self, Write};
 const SOURCE: &str = concat!(
  "/datum/z/proc/z()\n    set SpacemanDMM_z_unknown = 1\n    return missing_z\n",
  "/datum/a/proc/a()\n    set SpacemanDMM_a_unknown = 1\n    return missing_a\n",
 );
 fn fail_last(input: &EffectInput, row: &OriginalBodyDiagnostic, level: DiagnosticSeverity, out: &mut dyn Write) -> io::Result<()> {
  super::original_ordered_wire::write_body_diagnostic_row(input, row, level, out)?;
  if row.diagnostic().message.contains("missing_z") { return Err(io::Error::from_raw_os_error(1450)); }
  Ok(())
 }
 let (mut host, mut request, root) = fixture(SOURCE);
 let environment = root.join("code/probe.dm");
 admit_compact_original_report_inputs(&mut request, &environment);
 let cache = request.cache_root.as_ref().unwrap().clone();
 std::fs::create_dir_all(&cache).unwrap();
 let db = host.query_db().clone();
 run(&mut host, &request);
 current(&host, |snapshot| {
  let absolute = snapshot.original_checker_request_input(&snapshot.tree).unwrap();
  let input = EffectInput::original_checker_source_with_current_bodies(
   Arc::clone(absolute.input().archive()), absolute.input().profile(),
   snapshot.diagnostic_declarations.as_ref().unwrap(), db.as_ref(),
  ).unwrap();
  let roster = input.archive().callables();
  assert_eq!(roster.identity(roster.source_order()[0]).unwrap().name, SymbolId::of("z"));
  snapshot.with_effect_scope(&input, &environment, None, &snapshot.tree, |db, scope| {
   let mut prelude = Vec::new();
   let mut body = Vec::new();
   let before = db.db().stats(Kind(32)).computed;
   let standalone = db.db().stats(Kind(17)).computed;
   db.stage_archived_original_body_windows_for_test(&input, scope, 1, &cache,
    super::original_ordered_wire::write_body_diagnostic_row, &mut prelude, &mut body)?;
   assert_eq!(db.db().stats(Kind(32)).computed, before + 2);
   assert_eq!(db.db().stats(Kind(17)).computed, standalone);
   let actual = [serde_json::from_slice::<serde_json::Value>(&prelude)?, serde_json::from_slice(&body)?];
   let mut expected = [Vec::new(), Vec::new()];
   snapshot.visit_original_body_diagnostics(&environment, None, &snapshot.tree, |_, row| {
    let Some(severity) = scope.policy().register(row.registration_tag(), row.default_level())
     .filter(|severity| *severity <= DiagnosticSeverity::Info) else { return Ok(()); };
    let mut bytes = Vec::new();
    super::original_ordered_wire::write_body_diagnostic_row(absolute.input(), row, severity, &mut bytes)?;
    let index = if row.phase() == dm_analysis::checker_effects::OriginalDiagnosticPhase::Prelude { 0 } else { 1 };
    expected[index].push(serde_json::from_slice::<serde_json::Value>(&bytes)?);
    Ok(())
   })?;
   assert_eq!(actual, [serde_json::json!(expected[0]), serde_json::json!(expected[1])]);
   assert!(actual[0][0]["message"].as_str().unwrap().contains("SpacemanDMM_a_unknown"));
   assert!(actual[1][0]["message"].as_str().unwrap().contains("missing_a"));
   prelude.clear();
   body.clear();
   let before = db.db().stats(Kind(32)).computed;
   let error = db.stage_archived_original_body_windows_for_test(&input, scope, 1, &cache,
    fail_last, &mut prelude, &mut body).unwrap_err();
   assert_eq!(error.raw_os_error(), Some(1450));
   assert_eq!(db.db().stats(Kind(32)).computed, before + 1, "first window staged before second refused");
   assert!(prelude.is_empty() && body.is_empty());
   assert_eq!(db.effect_graph_work_for_test(), 0);
   Ok(())
  }).unwrap();
 });
}

#[test]
fn current_original_compact_whole_ordered_report_matches_real_absolute_wire() {
 use dm_analysis::checker_effects::EffectInput;
 let source=concat!(
  "var/shared_sink=0\n",
  "/proc/leaf()\n    return sleep()\n",
  "/proc/probe()\n",
  "    set SpacemanDMM_should_not_sleep = 1\n",
  "    set SpacemanDMM_made_up = 1\n",
  "    return leaf()\n",
  "/proc/negative()\n    return missing_value\n",
 );
 let(mut host,mut request,root)=fixture(source);
 let env=root.join("code/probe.dm");
 admit_compact_original_report_inputs(&mut request, &env);
 let cache=request.cache_root.as_ref().unwrap().clone();
 std::fs::create_dir_all(&cache).unwrap();
 let db=host.query_db().clone();
 run(&mut host,&request);
 current(&host,|snapshot|{
  let absolute=snapshot.original_checker_request_input(&snapshot.tree).unwrap();
  let input=EffectInput::original_checker_source_with_current_bodies(
   Arc::clone(absolute.input().archive()),absolute.input().profile(),
   snapshot.diagnostic_declarations.as_ref().unwrap(),db.as_ref(),
  ).unwrap();
  let body_before=db.db().stats(Kind(17)).computed;
  let parsed_before=db.db().stats(Kind(4)).computed;
  let mut actual=Vec::new();
  let clean=snapshot.write_compact_original_ordered_checker_for_test(
   &input,&env,None,&snapshot.tree,&cache,1,&mut actual,
  ).unwrap();
  assert_eq!(db.db().stats(Kind(17)).computed,body_before);
  assert_eq!(db.db().stats(Kind(4)).computed,parsed_before+3);
  let json:serde_json::Value=serde_json::from_slice(&actual).unwrap();
  let rows=json["diagnostics"].as_array().unwrap();
  for family in ["unknown_linter_setting","undefined_variable","must_not_sleep"] {
   assert!(rows.iter().any(|row|row["family"]==family),"{family}: {rows:?}");
  }
  let mut expected=Vec::new();
  let expected_clean=snapshot.write_original_ordered_checker_using(
   absolute.input(),&env,None,&snapshot.tree,&mut expected,
  ).unwrap();
  assert_eq!(actual,expected);
  assert_eq!(clean,expected_clean);
  let mut denied=Vec::new();
  assert!(snapshot.write_compact_original_ordered_checker_for_test(
   &input,&root.join("deepquarry.dme"),None,&snapshot.tree,&cache,1,&mut denied,
  ).is_err());
  assert!(denied.is_empty());
 });
}

#[test]
#[ignore = "explicit 10,001-body Original checker scale control"]
fn current_original_compact_whole_ordered_scales_past_per_body_node_cap() {
    use dm_analysis::{
        checker_effects::EffectInput,
        checker_order::ARCHIVED_CHUNK_WIDTH,
    };
    use std::{fmt::Write as _, time::{Duration, Instant}};

    const BODIES: usize = 10_001;
    let mut source = String::from(concat!(
        "/datum/scale_negative/proc/negative()\n",
        "    return missing_scale_value\n",
        "/proc/aa_scale_leaf()\n",
        "    return sleep()\n",
    ));
    for index in 0..BODIES - 3 {
        // Distinct body code makes the parse/evaluator assertions meaningful.
        writeln!(source, "/proc/scale_fill_{index:05}()\n    return {index}").unwrap();
    }
    source.push_str(concat!(
        "/proc/zz_scale_probe()\n",
        "    set SpacemanDMM_should_not_sleep = 1\n",
        "    set SpacemanDMM_made_up = 1\n",
        "    return aa_scale_leaf()\n",
    ));

    let (mut host, mut request, root) = fixture(&source);
    let environment = root.join("code/probe.dm");
    admit_compact_original_report_inputs(&mut request, &environment);
    let cache = request.cache_root.as_ref().unwrap().clone();
    std::fs::create_dir_all(&cache).unwrap();
    let db = host.query_db().clone();
    run(&mut host, &request);

    let _deadline = crate::daemon::control::bind_with_deadline(
        crate::daemon::control::Cancellation::default(),
        Instant::now() + Duration::from_secs(300),
    );
    current(&host, |snapshot| {
        let absolute = snapshot.original_checker_request_input(&snapshot.tree).unwrap();
        let input = EffectInput::original_checker_source_with_current_bodies(
            Arc::clone(absolute.input().archive()),
            absolute.input().profile(),
            snapshot.diagnostic_declarations.as_ref().unwrap(),
            db.as_ref(),
        ).unwrap();
        assert_eq!(input.archive().len(), BODIES);
        assert_eq!(input.archive().callables().source_order().len(), BODIES);

        let computed = |kind| db.db().stats(Kind(kind)).computed;
        let parsed_before = computed(4);
        let legacy_body_before = computed(17);
        let legacy_lookup_before = computed(21);
        let chunks_before = computed(32);
        #[cfg(debug_assertions)]
        let evaluated_before =
            dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread();

        let mut wire = Vec::new();
        let clean = snapshot.write_compact_original_ordered_checker_for_test(
            &input, &environment, None, &snapshot.tree, &cache, ARCHIVED_CHUNK_WIDTH, &mut wire,
        ).unwrap_or_else(|error| {
            assert!(wire.is_empty(), "failed scale run published a partial report");
            panic!("compact report failed at {BODIES} real bodies: {error}");
        });
        assert!(!clean);
        assert_eq!(computed(4) - parsed_before, BODIES as u64);
        assert_eq!(computed(17), legacy_body_before);
        assert_eq!(computed(21), legacy_lookup_before);
        assert_eq!(computed(32) - chunks_before, BODIES.div_ceil(ARCHIVED_CHUNK_WIDTH) as u64);
        #[cfg(debug_assertions)]
        assert_eq!(
            dm_analysis::checker_expression_visit::actual_evaluator_entries_on_current_thread()
                - evaluated_before,
            BODIES as u64,
        );
        assert_eq!(db.effect_graph_work_for_test(), 0);

        let report: serde_json::Value = serde_json::from_slice(&wire).unwrap();
        let rows = report["diagnostics"].as_array().unwrap();
        let phases_and_families = rows.iter().map(|row| (
            row["phase"].as_str().unwrap(),
            row["family"].as_str().unwrap(),
        )).collect::<Vec<_>>();
        assert_eq!(phases_and_families, [
            ("settings_prelude", "unknown_linter_setting"),
            ("body", "undefined_variable"),
            ("sleep_graph", "must_not_sleep"),
        ], "{rows:?}");
        assert_eq!(rows[0]["message"], "unknown linter setting \"SpacemanDMM_made_up\"");
        assert_eq!(rows[1]["message"], "undefined var: \"missing_scale_value\"");
        let graph_message = rows[2]["message"].as_str().unwrap();
        assert!(graph_message.contains("zz_scale_probe"), "{graph_message}");
        assert!(graph_message.contains("aa_scale_leaf"), "{graph_message}");
        assert!(!rows[2]["notes"].as_array().unwrap().is_empty());
    });
}
