//! Compare the actual selected setter report to the frozen legacy scanner.
use std::{fmt::Write as _,fs,path::PathBuf};
pub use dq_analyze::{allow,gens,incr,lint,parity,pat,sem,tree,util};
pub use dq_analyze::original_policy_descriptors as allow_registry_fields;
use dreammaker as _;
#[path="../src/allow_annotations_original.rs"] mod original_allow;
#[path="../fixtures/original_policies/setter_publishes.rs"] mod original_setter;

const SELECTED:&[&str]=&["allow_annotations","notice_publisher","report_in_catch","scheduler","setter_publishes"];
fn main(){
    let args:Vec<_>=std::env::args_os().skip(1).collect();
    let [root,native,case]=args.as_slice() else {
        panic!("usage: unified_selected_setter_original ABSOLUTE_ROOT ABSOLUTE_NATIVE_REPORT outside|admitted");
    };
    let root=PathBuf::from(root);
    let native=PathBuf::from(native);
    assert!(root.is_absolute()&&native.is_absolute());
    let outside=match case.to_str(){Some("outside")=>true,Some("admitted")=>false,_=>panic!("unknown case")};
    let mut registry=dq_analyze::run::registry();
    registry.lints.retain(|lint|!matches!(lint.meta().name,"allow_annotations"|"setter_publishes"));
    original_allow::register(&mut registry);
    original_setter::register(&mut registry);
    let engine=dq_analyze::run::Engine::new(registry,dq_analyze::run::Options{
        root,lints:SELECTED.iter().map(|name|(*name).to_owned()).collect(),no_cache:true,raw:true,..Default::default()
    }).expect("actual legacy selected Tree");
    let mut known:std::collections::BTreeSet<_>=engine.scopes.known_allow.iter().cloned().collect();
    known.extend(engine.reg.lints.iter().flat_map(|lint|lint.meta().allow.iter().map(|name|(*name).to_owned())));
    original_allow::set_known(known);

    let model=sem::sem_for(&engine.tree).expect("actual legacy DME model");
    assert!(model.errors.is_empty(),"legacy fixture parser errors: {:?}",model.errors);
    assert!(engine.tree.get("maps/.legacy_macro.dm").is_some());
    assert!(engine.tree.get("maps/legacy_macro.dm").is_some());
    assert!(engine.tree.get("interface/legacy_macro.dm").is_none());
    let defs=gens::auto_tracked::setter_defs(&engine.tree,&model);
    assert!(defs.contains_key("set_charge"),"{defs:?}");
    assert!(!defs.contains_key("set_map_charge")&&!defs.contains_key("set_hidden_charge"),"{defs:?}");
    assert_eq!(defs.contains_key("set_outside_charge"),outside,"{defs:?}");

    let outcomes:Vec<_>=SELECTED.iter().map(|name|engine.run_one(engine.reg.find(name).unwrap())).collect();
    assert!(outcomes.iter().all(|outcome|outcome.internal_error.is_none()));
    let setters=outcomes.last().unwrap();
    assert!(setters.allow_used.is_empty());
    assert_eq!(setters.run.sites.iter().filter(|site|site.rel=="code/probe.dm"&&site.rule=="no_publish").count(),2);
    assert_eq!(setters.run.sites.iter().any(|site|site.rel=="interface/legacy_macro.dm"&&site.rule=="no_publish"),outside);
    let used:Vec<_>=outcomes.iter().flat_map(|outcome|outcome.allow_used.iter().cloned()).collect();
    let unused=original_allow::unused(&engine.tree,&used,&[],&|_|String::new());
    let (mut expected,mut failed)=dq_analyze::run::render(&outcomes,false);
    for problem in &unused{writeln!(expected,"{problem}").unwrap();}
    writeln!(expected,"allow annotations: {} unused",unused.len()).unwrap();
    if !unused.is_empty(){failed.push("allow_annotations --unused".to_owned());}
    expected.push_str(&dq_analyze::policy_finish::result_line(&failed));
    assert_eq!(fs::read_to_string(native).expect("native verified report bytes"),expected);
}
