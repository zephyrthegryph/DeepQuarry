//! Independent legacy Engine plus original ALLOW completion for the exact
//! native raw runtime-policy roster. The five producers are frozen originals.
use std::{fmt::Write as _, fs, path::PathBuf};
pub use dq_analyze::{allow, captured_generator_budget, incr, lint, parity, pat, pat_match, scopes, sem, tree, util};
pub use dq_analyze::original_policy_descriptors as allow_registry_fields;
pub mod dm { pub use dq_analyze::dm::*; }
#[path = "../fixtures/original_policies/raw_eight_raw_name_match.rs"]
pub mod raw_name_match;
#[path = "../fixtures/original_policies/pool_workspace_policy.rs"]
pub mod pool_policy;
#[path = "../src/allow_annotations_original.rs"]
mod original_allow;
#[path = "../fixtures/original_policies/raw_eight_interactions.rs"]
mod original_interactions;
#[path = "../fixtures/original_policies/raw_eight_latent.rs"]
mod original_latent;

// The scanner is frozen. Its old Sites metadata predates the current Hard
// judgment, so the standalone oracle uses the current registered metadata.
struct CurrentLatent(Box<dyn lint::Lint>);
impl lint::Lint for CurrentLatent {
    fn meta(&self) -> &lint::Meta { &dq_analyze::raw_tree_latent_policy::META }
    fn scan_tree(&self, cx: &lint::Cx, out: &mut lint::Sink) {
        self.0.scan_tree(cx, out);
    }
}
#[path = "../fixtures/original_policies/raw_eight_pollers.rs"]
mod original_pollers;
#[path = "../fixtures/original_policies/pool_workspace.rs"]
mod original_pool;
#[path = "../fixtures/original_policies/raw_eight_read_back.rs"]
mod original_read_back;

const SELECTED: &[&str] = &[
    "allow_annotations", "interactions", "latent", "notice_publisher", "pollers",
    "pool", "read_back", "report_in_catch", "scheduler",
];

fn main() {
    let args: Vec<PathBuf> = std::env::args_os().skip(1).map(PathBuf::from).collect();
    let [root, native] = args.as_slice() else {
        panic!("usage: unified_selected_raw_runtime_original ABSOLUTE_ROOT ABSOLUTE_NATIVE_REPORT");
    };
    assert!(root.is_absolute() && native.is_absolute());
    let mut registry = dq_analyze::run::registry();
    registry.lints.retain(|lint| !matches!(lint.meta().name,
        "allow_annotations" | "interactions" | "latent" | "pollers" | "pool" | "read_back"));
    original_allow::register(&mut registry);
    original_interactions::register(&mut registry);
    let mut frozen_latent = lint::Registry::default();
    original_latent::register(&mut frozen_latent);
    registry.add(CurrentLatent(frozen_latent.lints.pop().unwrap()));
    original_pollers::register(&mut registry);
    original_pool::register(&mut registry);
    original_read_back::register(&mut registry);
    let engine = dq_analyze::run::Engine::new(registry, dq_analyze::run::Options {
        root: root.clone(),
        lints: SELECTED.iter().map(|name| (*name).to_owned()).collect(),
        no_cache: true,
        raw: true,
        ..Default::default()
    }).expect("independent legacy source tree");
    let mut known: std::collections::BTreeSet<_> = engine.scopes.known_allow.iter().cloned().collect();
    known.extend(engine.reg.lints.iter().flat_map(|lint| lint.meta().allow.iter().map(|name| (*name).to_owned())));
    original_allow::set_known(known);
    let outcomes: Vec<_> = SELECTED.iter()
        .map(|name| engine.run_one(engine.reg.find(name).unwrap())).collect();
    assert!(outcomes.iter().all(|outcome| outcome.internal_error.is_none()));
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
    // The frozen cap_bits rule predates the registry file move. Keep its
    // independent findings and update only that rule's obsolete rendered hint.
    const OLD_HINT: &str = " -- allocate the bit in code/__defines/cap_bits.dm";
    const CURRENT_HINT: &str = " -- allocate the bit in code/defines/engine/cap_bits.dm";
    let expected: String = expected.split_inclusive('\n').map(|line| {
        if line.contains("[cap_bits/outside_registry]") {
            if let Some(prefix) = line.trim_end_matches('\n').strip_suffix(OLD_HINT) {
                return format!("{prefix}{CURRENT_HINT}\n");
            }
        }
        line.to_owned()
    }).collect();
    assert_eq!(fs::read_to_string(native).expect("native verified report"), expected);
}

