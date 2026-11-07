//! End-to-end real current callee prefix and negative type lookup controls.
use super::*;
use super::super::analysis_context_tests::{checker_fixture as fixture,run,current};
use dm_ir::{ResolveQuery,SymbolId};use dm_query::Kind;
const MISSING_TYPE:&str="/proc/choose()\n    set SpacemanDMM_return_type=/datum/result\n    return null\n/proc/probe()\n    return choose().field\n";
const PRESENT_TYPE:&str="/datum/result\n/proc/choose()\n    set SpacemanDMM_return_type=/datum/result\n    return null\n/proc/probe()\n    return choose().field\n";
fn observed(host:&crate::runner_host::BuildHost,root:&Path)->(Vec<(usize,usize,String)>,usize){current(host,|snapshot|{let archive=snapshot.body_archive.as_ref().unwrap();assert_eq!(archive.len(),2);let dot=archive.expanded_source().find("().field").unwrap()+2;let mut rows=Vec::new();let result=snapshot.visit_current_variable_diagnostics(1,&root.join("deepquarry.dme"),None,&snapshot.tree,|row|{rows.push((row.span.start,row.span.end,row.diagnostic.message.clone()));Ok(())});println!("CURRENT_CALLABLE_NATIVE={:?}",(&result,&rows,dot));assert_eq!(result.unwrap(),dm_analysis::checks_undefined_variable::CurrentUndefinedDisposition::Evaluated);(rows,dot)})}
#[test]fn current_callable_actual_rejected_return_type_absence_is_a_dependency_before_eval_and_rebinds_on_type_add(){
 let(mut host,request,root)=fixture(MISSING_TYPE);let queries=host.query_db().clone();run(&mut host,&request);let first=observed(&host,&root);assert!(first.0.is_empty(),"selected variable error family excludes the separately owned return-compile error/warning prelude");let syntax=queries.db().stats(Kind(4)).computed;assert_eq!(syntax,2,"caller and callee use their two canonical products, no issued absolute sibling parse");let semantics=queries.db().stats(Kind(28)).computed;
 let(parent,type_lookup,_)=current(&host,|snapshot|{let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap();queries.current_variable_keys_for_test(input.input(),1,ResolveQuery::Type(SymbolId::of("/datum/result")))});assert!(queries.db().dependants(&[type_lookup]).contains(&parent),"compile-rejected Type lookup must exist even when Eval did not execute");
 std::fs::write(root.join("code/probe.dm"),PRESENT_TYPE).unwrap();run(&mut host,&request);let present=observed(&host,&root);assert_eq!(present.0,[(present.1,present.1+1,"undefined field: \"field\" on /datum/result".to_owned())]);assert_eq!(queries.db().stats(Kind(28)).computed,semantics+1,"a real missing->present type changes return binding while both code identities stay equal");assert_eq!(queries.db().stats(Kind(4)).computed,syntax);
 let shifted=format!("// α both unchanged bodies shift\n{PRESENT_TYPE}// later file shift\n");std::fs::write(root.join("code/probe.dm"),shifted).unwrap();run(&mut host,&request);let shifted=observed(&host,&root);assert_eq!(shifted.0,[(shifted.1,shifted.1+1,"undefined field: \"field\" on /datum/result".to_owned())]);assert_ne!(present.1,shifted.1);assert_eq!(queries.db().stats(Kind(28)).computed,semantics+1,"unchanged actual callee/type answers must cut off semantic reevaluation");assert_eq!(queries.db().stats(Kind(4)).computed,syntax);
}
#[test]fn current_callable_actual_callee_setting_edit_retracts_old_type_dependency_and_changes_caller_receiver(){
 let(mut host,request,root)=fixture(PRESENT_TYPE);let queries=host.query_db().clone();run(&mut host,&request);let first=observed(&host,&root);assert_eq!(first.0.len(),1);let(old_parent,old_type,_)=current(&host,|snapshot|{let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap();queries.current_variable_keys_for_test(input.input(),1,ResolveQuery::Type(SymbolId::of("/datum/result")))});assert!(queries.db().dependants(&[old_type]).contains(&old_parent));let semantics=queries.db().stats(Kind(28)).computed;
 let changed="/datum/result\n/datum/other\n/proc/choose()\n    set SpacemanDMM_return_type=/datum/other\n    return null\n/proc/probe()\n    return choose().field\n";std::fs::write(root.join("code/probe.dm"),changed).unwrap();run(&mut host,&request);let changed=observed(&host,&root);assert_eq!(changed.0,[(changed.1,changed.1+1,"undefined field: \"field\" on /datum/other".to_owned())]);assert_eq!(queries.db().stats(Kind(28)).computed,semantics+1);assert!(!queries.db().dependants(&[old_type]).contains(&old_parent),"changing the actual callee directive retracts the caller's previous return-type edge");let(parent,new_type,_)=current(&host,|snapshot|{let input=snapshot.original_checker_request_input(&snapshot.tree).unwrap();queries.current_variable_keys_for_test(input.input(),1,ResolveQuery::Type(SymbolId::of("/datum/other")))});assert_eq!(parent,old_parent,"caller code is unchanged; only actual source meaning changed");assert!(queries.db().dependants(&[new_type]).contains(&parent));
}

#[test]fn current_callable_same_metadata_body_choice_is_current_even_with_old_archive_retained(){
 fn read(host:&crate::runner_host::BuildHost,root:&Path)->(dm_analysis::checks_undefined_variable::CurrentUndefinedDisposition,Vec<(usize,usize,String)>){current(host,|snapshot|{let mut rows=Vec::new();let actual=snapshot.visit_current_variable_diagnostics(1,&root.join("deepquarry.dme"),None,&snapshot.tree,|row|{rows.push((row.span.start,row.span.end,row.diagnostic.message.clone()));Ok(())});println!("CURRENT_CALLEE_CODE_CHOICE={actual:?} rows={rows:?}");(actual.unwrap(),rows)})}
 fn native_chain(host:&crate::runner_host::BuildHost)->Vec<u8>{current(host,|snapshot|{dm_ir::Resolver::resolve(snapshot.tree.as_ref(),ResolveQuery::SourceDeclarationChain{owner:SymbolId::of("/"),name:SymbolId::of("choose"),verb:false}).canonical_bytes()})}
 let(mut host,request,root)=fixture(PRESENT_TYPE);let queries=host.query_db().clone();run(&mut host,&request);let first=read(&host,&root);assert_eq!(first.1.len(),1);let metadata=native_chain(&host);let semantic=queries.db().stats(Kind(28)).computed;let syntax=queries.db().stats(Kind(4)).computed;
 let retained_old=current(&host,|snapshot|{let owner=snapshot.original_checker_request_input(&snapshot.tree).unwrap();Arc::clone(owner.input())});
 let old_callee=Arc::downgrade(retained_old.archive().syntax_inputs().unwrap()[0].original_code_owner().unwrap());let old_caller=Arc::downgrade(retained_old.archive().syntax_inputs().unwrap()[1].original_code_owner().unwrap());
 let(parent,chain,_)=current(&host,|snapshot|{let owner=snapshot.original_checker_request_input(&snapshot.tree).unwrap();queries.current_variable_keys_for_test(owner.input(),1,ResolveQuery::SourceDeclarationChain{owner:SymbolId::of("/"),name:SymbolId::of("choose"),verb:false})});assert!(queries.db().dependants(&[chain]).contains(&parent));
 for(index,body)in ["return 1","return 1 +","return null"].into_iter().enumerate(){
  let source=PRESENT_TYPE.replace("return null",body);std::fs::write(root.join("code/probe.dm"),&source).unwrap();run(&mut host,&request);assert_eq!(native_chain(&host),metadata,"this control changes actual BODY choice while native signature/settings metadata is byte-identical");
  let incremental=read(&host,&root);let(mut fresh,fresh_request,fresh_root)=fixture(&source);run(&mut fresh,&fresh_request);let independent=read(&fresh,&fresh_root);assert_eq!(incremental,independent,"complete current selected rows must match genuine fresh execution for {body}");
  assert_eq!(queries.db().stats(Kind(28)).computed,semantic+index as u64+1,"the actual current callee code choice invalidates the existing caller contribution");assert_eq!(queries.db().stats(Kind(4)).computed,syntax+index as u64+1,"only the edited callee parses; unchanged caller uses its SAME canonical product");
  current(&host,|snapshot|{let inputs=snapshot.body_archive.as_ref().unwrap().syntax_inputs().unwrap();assert!(std::sync::Weak::ptr_eq(&old_caller,&Arc::downgrade(inputs[1].original_code_owner().unwrap())));if index==0{assert!(!std::sync::Weak::ptr_eq(&old_callee,&Arc::downgrade(inputs[0].original_code_owner().unwrap())));}});
 }
 assert_eq!(retained_old.archive().len(),2,"genuine old input/source/archive stayed live through all edits; old child liveness cannot authorize its current choice");assert_eq!(queries.effect_graph_work_for_test(),0);
 let stable=queries.db().stats(Kind(28)).computed;let parses=queries.db().stats(Kind(4)).computed;std::fs::write(root.join("code/probe.dm"),format!("// α source-only shift\n{PRESENT_TYPE}")).unwrap();run(&mut host,&request);let shifted=read(&host,&root);assert_eq!(shifted.1.len(),first.1.len());assert_eq!(shifted.1[0].2,first.1[0].2);assert_ne!(shifted.1[0].0,first.1[0].0);assert_eq!(queries.db().stats(Kind(28)).computed,stable,"actual unchanged code-choice answers cut off semantic work");assert_eq!(queries.db().stats(Kind(4)).computed,parses);
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
 use dm_analysis::checker_effects::EffectInput;
 const SOURCE:&str=concat!(
  "/proc/leaf()\n    return sleep()\n",
  "/proc/probe(item)\n",
  "    set SpacemanDMM_should_not_sleep = 1\n",
  "    set SpacemanDMM_made_up = 1\n",
  "    return leaf()\n",
  "/proc/note(item)\n    return item.field\n",
 );
 let(mut host,mut request,root)=fixture(SOURCE);
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
