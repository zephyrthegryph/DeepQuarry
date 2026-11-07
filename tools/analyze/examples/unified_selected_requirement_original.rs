//! Independent legacy Engine plus original ALLOW completion for the exact
//! native requirement-bool roster. Semantic facts come from legacy Sem.
use std::{fmt::Write as _, fs, path::PathBuf};
pub use dq_analyze::{allow, incr, lint, parity, pat, sem, tree, util};
pub use dq_analyze::original_policy_descriptors as allow_registry_fields;
#[path = "../src/allow_annotations_original.rs"]
mod original_allow;

const SELECTED: &[&str] = &[
    "allow_annotations", "notice_publisher", "report_in_catch",
    "requirement_bool", "scheduler",
];

fn main() {
    let args: Vec<PathBuf> = std::env::args_os().skip(1).map(PathBuf::from).collect();
    let [root, native] = args.as_slice() else {
        panic!("usage: unified_selected_requirement_original ABSOLUTE_ROOT ABSOLUTE_NATIVE_REPORT");
    };
    assert!(root.is_absolute() && native.is_absolute());
    let mut registry = dq_analyze::run::registry();
    registry.lints.retain(|lint| lint.meta().name != "allow_annotations");
    original_allow::register(&mut registry);
    let engine = dq_analyze::run::Engine::new(registry, dq_analyze::run::Options {
        root: root.clone(),
        lints: SELECTED.iter().map(|name| (*name).to_owned()).collect(),
        no_cache: true,
        raw: true,
        ..Default::default()
    }).expect("independent legacy source tree");
    let model = sem::sem_for(&engine.tree).expect("independent legacy DME model");
    assert!(model.errors.is_empty(), "{:?}", model.errors);
    let mut known: std::collections::BTreeSet<_> = engine.scopes.known_allow.iter().cloned().collect();
    known.extend(engine.reg.lints.iter().flat_map(|lint| lint.meta().allow.iter().map(|name| (*name).to_owned())));
    original_allow::set_known(known);
    let outcomes: Vec<_> = SELECTED.iter()
        .map(|name| engine.run_one(engine.reg.find(name).unwrap())).collect();
    assert!(outcomes.iter().all(|outcome| outcome.internal_error.is_none()));
    for outcome in &outcomes {
        if outcome.name == "requirement_bool" {
            assert!(outcome.allow_used.is_empty());
        }
    }
    let used: Vec<_> = outcomes.iter().flat_map(|outcome| outcome.allow_used.iter().cloned()).collect();
    let unused = original_allow::unused(&engine.tree, &used, &[], &|_| String::new());
    let (mut expected, mut failed) = dq_analyze::run::render(&outcomes, false);
    for problem in &unused {
        writeln!(expected, "{problem}").unwrap();
    }
    writeln!(expected, "allow annotations: {} unused", unused.len()).unwrap();
    if !unused.is_empty() {
        failed.push("allow_annotations --unused".to_owned());
    }
    expected.push_str(&dq_analyze::policy_finish::result_line(&failed));
    assert_eq!(fs::read(native).expect("native verified report"), expected.as_bytes());
}
