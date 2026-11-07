//! Independent legacy Engine plus original ALLOW completion for the exact
//! native whole raw-file roster. Only the original standalone Engine scans.
use std::{fmt::Write as _, fs, path::PathBuf};
pub use dq_analyze::{allow, incr, lint, parity, pat, sem, tree, util};
pub use dq_analyze::original_policy_descriptors as allow_registry_fields;
#[path = "../src/allow_annotations_original.rs"]
mod original_allow;

const SELECTED: &[&str] = &[
    "actor_forwarding", "allow_annotations", "breakpoint", "containment",
    "dcs", "door_gates", "engine_internal", "entity_ids",
    "entry_slots", "i7_handler", "in_precedence", "leftovers",
    "legacy_forms", "lifecycle_counts", "lifeform_allows", "escape_hatches",
    "mouse_override", "native_ref_write", "notice_publisher", "organ_slots",
    "qdel_src", "reactions_table_proc", "ref_text", "registry",
    "report_in_catch", "saved_handle", "scheduler", "silent_catch",
    "spatial", "stance_examine", "subsystem_fire", "sys/contents",
    "sys/damage_reactions", "sys/dx_manual_transfer", "sys/dx_raw_delay", "sys/dx_raw_overlays",
    "sys/dx_review", "sys/emag", "sys/grants", "sys/messages",
    "sys/presentation", "sys/sync_sql", "sys/topic", "sys/usr_use",
    "verb_category",
];

fn main() {
    let args: Vec<PathBuf> = std::env::args_os().skip(1).map(PathBuf::from).collect();
    let [root, native] = args.as_slice() else {
        panic!("usage: unified_selected_all_raw_original ABSOLUTE_ROOT ABSOLUTE_NATIVE_REPORT");
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
    assert_eq!(fs::read(native).expect("native verified report"), expected.as_bytes());
}
