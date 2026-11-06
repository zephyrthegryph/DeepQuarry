//! Compare one actual mixed selected-handler fixture with the frozen legacy
//! handler and ALLOW implementations using the old filesystem Tree and parser.
use std::{fmt::Write as _, fs, path::PathBuf};

pub use dq_analyze::{allow, incr, lint, parity, pat, sem, tree, util};
pub use dq_analyze::original_policy_descriptors as allow_registry_fields;

#[path = "../src/allow_annotations_original.rs"]
mod original_allow;
#[path = "../fixtures/original_policies/sem_handlers.rs"]
mod original_handlers;

const SELECTED: &[&str] = &[
    "allow_annotations", "cooldown", "notice_publisher", "report_in_catch", "scheduler", "sem/handlers",
];

fn main() {
    let paths: Vec<PathBuf> = std::env::args_os().skip(1).map(PathBuf::from).collect();
    let [root, native] = paths.as_slice() else {
        panic!("usage: unified_selected_handlers_original ABSOLUTE_FIXTURE_ROOT ABSOLUTE_NATIVE_REPORT");
    };
    assert!(root.is_absolute() && native.is_absolute(), "absolute fixture and native report paths required");
    assert_eq!(
        include_bytes!("../src/sem/handlers.rs").as_slice(),
        include_bytes!("../fixtures/original_policies/handler_analysis.rs").as_slice(),
        "the handler analysis used by the frozen lint must remain byte-identical",
    );

    let mut registry = dq_analyze::run::registry();
    registry.lints.retain(|lint| !matches!(lint.meta().name, "allow_annotations" | "sem/handlers"));
    original_allow::register(&mut registry);
    original_handlers::register(&mut registry);
    let engine = dq_analyze::run::Engine::new(registry, dq_analyze::run::Options {
        root: root.clone(),
        lints: SELECTED.iter().map(|name| (*name).to_owned()).collect(),
        no_cache: true,
        raw: true,
        ..Default::default()
    }).expect("actual legacy mixed-scope Tree");
    let mut known: std::collections::BTreeSet<_> = engine.scopes.known_allow.iter().cloned().collect();
    known.extend(engine.reg.lints.iter().flat_map(|lint| lint.meta().allow.iter().map(|name| (*name).to_owned())));
    original_allow::set_known(known);

    assert!(engine.tree.get("maps/.override.dm").is_some(), "mixed original Tree must contain the hidden map");
    let model = sem::sem_for(&engine.tree).expect("actual legacy full DME model");
    assert!(model.errors.is_empty(), "legacy fixture parser errors: {:?}", model.errors);
    let outcomes: Vec<_> = SELECTED.iter().map(|name| engine.run_one(engine.reg.find(name).unwrap())).collect();
    assert!(outcomes.iter().all(|outcome| outcome.internal_error.is_none()));
    let handler = outcomes.last().unwrap();
    assert_eq!(handler.name, "sem/handlers");
    for (rule, relative, line) in [
        ("context_escape", "code/structural.dm", 2),
        ("requirement_return", "code/handler.dm", 2),
        ("output_signature", "maps/.override.dm", 1),
    ] {
        assert!(handler.run.sites.iter().any(|site| site.rule == rule && site.rel == relative && site.line == line),
            "legacy handler did not exercise {rule} at {relative}:{line}: {:?}", handler.run.sites);
    }
    for (relative, line) in [("code/structural.dm", 4), ("maps/allowed.dm", 1)] {
        assert!(handler.allow_used.iter().any(|used| used.name == "handlers" && used.rel == relative && used.line == line),
            "legacy handler did not use {relative}:{line}: {:?}", handler.allow_used);
    }
    let used: Vec<_> = outcomes.iter().flat_map(|outcome| outcome.allow_used.iter().cloned()).collect();
    let unused = original_allow::unused(&engine.tree, &used, &[], &|_| String::new());
    assert_eq!(unused.len(), 1, "{unused:?}");
    assert!(unused[0].starts_with("maps/unused.dm:1: ALLOW(scheduler) is unused"), "{unused:?}");
    let (mut expected, mut failed) = dq_analyze::run::render(&outcomes, false);
    for problem in &unused {
        writeln!(expected, "{problem}").unwrap();
    }
    writeln!(expected, "allow annotations: {} unused", unused.len()).unwrap();
    failed.push("allow_annotations --unused".to_owned());
    expected.push_str(&dq_analyze::policy_finish::result_line(&failed));
    assert_eq!(fs::read_to_string(native).expect("verified native report bytes"), expected,
        "mixed selected report differs from the frozen legacy producers");
}
