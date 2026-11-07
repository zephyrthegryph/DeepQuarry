//! Independent legacy Engine plus original ALLOW completion for the exact
//! native raw declaration-policy roster. The three producers are frozen originals.
use std::{fmt::Write as _, fs, path::PathBuf};
pub use dq_analyze::{allow, incr, lint, parity, pat, pat_match, scopes, sem, tree, util};
pub use dq_analyze::original_policy_descriptors as allow_registry_fields;
#[path = "../src/allow_annotations_original.rs"]
mod original_allow;
#[path = "../fixtures/original_policies/raw_eight_cap_bits.rs"]
mod original_cap_bits;
#[path = "../fixtures/original_policies/raw_eight_declaration_block.rs"]
mod original_declaration_block;
#[path = "../fixtures/original_policies/raw_eight_duplicate_input_key.rs"]
mod original_duplicate_input_key;

const SELECTED: &[&str] = &[
    "allow_annotations", "cap_bits", "declaration_block", "duplicate_input_key",
    "notice_publisher", "report_in_catch", "scheduler",
];

fn main() {
    let args: Vec<PathBuf> = std::env::args_os().skip(1).map(PathBuf::from).collect();
    let [root, native] = args.as_slice() else {
        panic!("usage: unified_selected_raw_declaration_original ABSOLUTE_ROOT ABSOLUTE_NATIVE_REPORT");
    };
    assert!(root.is_absolute() && native.is_absolute());
    let mut registry = dq_analyze::run::registry();
    registry.lints.retain(|lint| !matches!(lint.meta().name,
        "allow_annotations" | "cap_bits" | "declaration_block" | "duplicate_input_key"));
    original_allow::register(&mut registry);
    original_cap_bits::register(&mut registry);
    original_declaration_block::register(&mut registry);
    original_duplicate_input_key::register(&mut registry);
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
