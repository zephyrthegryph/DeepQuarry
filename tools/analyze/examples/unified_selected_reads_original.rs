//! Byte-level selected read report comparison against frozen legacy lints and
//! the actual old filesystem Tree and SpacemanDMM model.
use std::{fmt::Write as _, fs, path::PathBuf};
pub use dq_analyze::{allow, gens, incr, lint, parity, pat, sem, tree, util};
pub use dq_analyze::original_policy_descriptors as allow_registry_fields;

#[path="../src/allow_annotations_original.rs"] mod original_allow;
#[path="../fixtures/original_policies/sem_reads.rs"] mod original_reads;
#[path="../fixtures/original_policies/untracked_inputs.rs"] mod original_untracked;

const SELECTED: &[&str] = &[
    "allow_annotations", "notice_publisher", "report_in_catch", "scheduler", "sem/reads", "untracked_inputs",
];

fn main() {
    let args:Vec<_> = std::env::args_os().skip(1).collect();
    let [root,native,case] = args.as_slice() else {
        panic!("usage: unified_selected_reads_original ABSOLUTE_ROOT ABSOLUTE_NATIVE_REPORT kept|unkept");
    };
    let root = PathBuf::from(root);
    let native = PathBuf::from(native);
    assert!(root.is_absolute() && native.is_absolute());
    let kept = match case.to_str() { Some("kept") => true, Some("unkept") => false, _ => panic!("unknown case") };
    let mut registry = dq_analyze::run::registry();
    registry.lints.retain(|lint| !matches!(lint.meta().name,"allow_annotations"|"sem/reads"|"untracked_inputs"));
    original_allow::register(&mut registry);
    original_reads::register(&mut registry);
    original_untracked::register(&mut registry);
    let engine = dq_analyze::run::Engine::new(registry, dq_analyze::run::Options {
        root, lints:SELECTED.iter().map(|name| (*name).to_owned()).collect(), no_cache:true, raw:true,
        ..Default::default()
    }).expect("actual legacy selected Tree");
    let mut known:std::collections::BTreeSet<_> = engine.scopes.known_allow.iter().cloned().collect();
    known.extend(engine.reg.lints.iter().flat_map(|lint| lint.meta().allow.iter().map(|name| (*name).to_owned())));
    original_allow::set_known(known);
    let model=sem::sem_for(&engine.tree).expect("actual legacy manifest model");
    assert!(model.errors.is_empty(), "legacy fixture parser errors: {:?}",model.errors);
    let hidden = engine.tree.get("maps/.read_kept.dm").expect("hidden map in mixed old Tree");
    assert!(!tree::CODE_DM.matches(hidden));
    let outcomes:Vec<_>=SELECTED.iter().map(|name|engine.run_one(engine.reg.find(name).unwrap())).collect();
    assert!(outcomes.iter().all(|outcome|outcome.internal_error.is_none()));
    for (name,alias) in [("sem/reads","reads"),("untracked_inputs","untracked_inputs")] {
        let outcome=outcomes.iter().find(|outcome|outcome.name==name).unwrap();
        assert!(outcome.run.sites.iter().any(|site|site.rel=="maps/read_unkept.dm" && site.line==2), "{:?}",outcome.run.sites);
        assert_eq!(outcome.run.sites.iter().any(|site|site.rel=="maps/.read_kept.dm" && site.line==2), !kept, "{:?}",outcome.run.sites);
        assert_eq!(outcome.allow_used.iter().any(|row|row.rel=="maps/.read_kept.dm" && row.line==2 && row.name==alias), kept, "{:?}",outcome.allow_used);
    }
    let used:Vec<_>=outcomes.iter().flat_map(|outcome|outcome.allow_used.iter().cloned()).collect();
    let unused=original_allow::unused(&engine.tree,&used,&[],&|_|String::new());
    assert_eq!(unused.len(),1,"{unused:?}");
    if kept {assert!(unused[0].starts_with("maps/stale.dm:1: ALLOW(reads) is unused"),"{unused:?}");}
    let (mut expected,mut failed)=dq_analyze::run::render(&outcomes,false);
    for problem in &unused { writeln!(expected,"{problem}").unwrap(); }
    writeln!(expected,"allow annotations: {} unused",unused.len()).unwrap();
    failed.push("allow_annotations --unused".to_owned());
    expected.push_str(&dq_analyze::policy_finish::result_line(&failed));
    assert_eq!(fs::read_to_string(native).expect("native verified report bytes"),expected,
        "mixed selected report differs from frozen legacy producers");
}
