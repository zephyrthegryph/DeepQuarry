//! The E5 reads spike (doc/rewrite/final_api.html section 19), held forever: on 18 real handlers
//! the generated reads contain every read in the existing hand-written lists, with at most one
//! handler needing a `READS_AS` / `READS_FROM` annotation. The handlers and the one invalidation
//! token are pinned in `tools/analyze/oracle/spike.toml`.
//!
//! This parses the whole tree (a few seconds): it is the proof that the generator can replace the
//! lists, so it runs against the real code, not a fixture.

use std::path::PathBuf;

use dq_analyze::run::{Engine, Options};
use dq_analyze::sem::decls::Decls;
use dq_analyze::sem::oracle::{entries, evaluate, generated_entries, SpikeConfig};
use dq_analyze::sem::reads::{Annotations, ReadsEngine};

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap().to_path_buf()
}

#[test]
fn generated_reads_contain_every_hand_written_read_on_the_pinned_handlers() {
    let root = repo_root();
    let cfg = SpikeConfig::parse(&std::fs::read_to_string(root.join("tools/analyze/oracle/spike.toml")).expect("spike.toml"));
    assert_eq!(cfg.handlers.len(), 13, "the spike pins 13 handlers");

    let opts = Options { root: root.clone(), lints: vec!["sem/keys".to_string()], no_cache: true, raw: true, ..Default::default() };
    let engine = Engine::new(dq_analyze::run::registry(), opts).expect("engine");
    let sem = dq_analyze::sem::sem_for(&engine.tree).expect("the real tree parses");
    let decls = Decls::get(&engine.tree);
    let ann = Annotations::get(&sem, &decls);
    let eng = ReadsEngine::new(&sem, &decls, &ann).with_opaque(dq_analyze::sem::handlers::OPAQUE_DIRS);

    let mut all = entries(&sem);
    all.extend(generated_entries(&root));
    let rows = evaluate(&sem, &eng, &all, &cfg.tokens);

    let gone: Vec<String> = cfg
        .handlers
        .iter()
        .filter(|(ty, kind, var)| !rows.iter().any(|r| &r.ty == ty && r.kind.label() == kind && &r.var == var))
        .map(|(ty, kind, var)| format!("{} {} {}", ty, kind, var))
        .collect();
    assert!(gone.is_empty(), "pinned handlers with no hand-written list in the tree any more (converted: drop their pins from spike.toml and lower the count here): {:?}", gone);
    let mut needing_annotation = Vec::new();
    for (ty, kind, var) in &cfg.handlers {
        let row = rows
            .iter()
            .find(|r| &r.ty == ty && r.kind.label() == kind && &r.var == var)
            .unwrap_or_else(|| panic!("pinned handler {} {} {} has no hand-written list in the tree any more", ty, kind, var));
        assert!(!row.procs.is_empty(), "{} {}: no handler proc on the type", ty, kind);
        assert!(!row.declared.is_empty(), "{} {}: an empty list proves nothing", ty, kind);
        // The spike's criterion: a hand-written read the generated reads lack is what needs an annotation.
        if row.needs_annotation() {
            needing_annotation.push(format!("{} {} missing {:?}", ty, kind, row.missing));
        }
    }
    let mut helpers = std::collections::BTreeSet::new();
    let mut with_globals = 0;
    for (ty, kind, var) in &cfg.handlers {
        let row = rows.iter().find(|r| &r.ty == ty && r.kind.label() == kind && &r.var == var).unwrap();
        if !row.unannotated.is_empty() {
            with_globals += 1;
        }
        helpers.extend(row.unannotated.iter().cloned());
    }
    let new_helpers: Vec<&String> = helpers.iter().filter(|h| !cfg.unannotated.contains(*h)).collect();
    assert!(new_helpers.is_empty(), "handlers call global procs without READS_FROM that spike.toml [unannotated] does not list: {:?}", new_helpers);
    eprintln!("spike: {} of 18 handlers call {} global helpers without READS_FROM", with_globals, helpers.len());
    assert!(needing_annotation.len() <= 1, "more than one handler needs an annotation: {:#?}", needing_annotation);
    // The report the lead reads: how many differ only by the invalidation token.
    let tokens = cfg
        .handlers
        .iter()
        .filter(|(t, k, v)| rows.iter().any(|r| &r.ty == t && r.kind.label() == k && &r.var == v && !r.tokens.is_empty()))
        .count();
    eprintln!("spike: 18 handlers, {} need an annotation, {} list the invalidation token", needing_annotation.len(), tokens);
}
