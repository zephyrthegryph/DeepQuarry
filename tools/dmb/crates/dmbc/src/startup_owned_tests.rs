use super::*;
use dm_tree::frontend::FrontendRevision;
use std::{path::Path, sync::Arc};

struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok("/proc/p()\n    var/static/cache = 3\n    return cache\n".into())
    }
}
fn frontend() -> ColdFrontend {
    dm_tree::frontend::build(Path::new("owned.dme"), &Source, &Default::default(), 1).unwrap()
}

#[test]
fn owned_facts_rebind_after_frontend_moves_and_reject_new_issuers() {
    let original = FrontendRevision::new(frontend());
    let facts = capture_revision_facts_with_spellings_and_workers(&original, &[], 1).unwrap();
    let view = facts.view_revision(&original).unwrap();
    let identity = view.plan().identity;
    assert!(view.procedures().any(|(_, p)| !p.declarations.is_empty()));
    drop(view);
    let moved = Box::new(original);
    let rebound = facts.view_revision(&moved).unwrap();
    assert_eq!(rebound.plan().identity, identity);
    rebound.validate_for(&moved).unwrap();
    let rebuilt = FrontendRevision::new(frontend());
    assert_eq!(
        rebuilt.snapshot.tree.identity(),
        moved.snapshot.tree.identity()
    );
    assert!(facts.view_revision(&rebuilt).is_err());
}

#[test]
fn public_frontend_mutation_cannot_reuse_issued_startup_facts() {
    let original = FrontendRevision::new(frontend());
    let facts = capture_revision_facts_with_spellings_and_workers(&original, &[], 1).unwrap();
    let mut changed = (*original).clone();
    changed.expanded.text = Arc::from(changed.expanded.text.replace("= 3", "= 4"));
    assert!(facts
        .view_revision(&FrontendRevision::new(changed))
        .is_err());
    let mut changed = (*original).clone();
    changed.emission_order = changed
        .emission_order
        .iter()
        .copied()
        .rev()
        .collect::<Vec<_>>()
        .into();
    assert!(facts
        .view_revision(&FrontendRevision::new(changed))
        .is_err());
    let mut changed = (*original).clone();
    changed.snapshot = frontend().snapshot;
    assert!(facts
        .view_revision(&FrontendRevision::new(changed))
        .is_err());
    let mut changed = (*original).clone();
    changed.expanded.origins.clear();
    assert!(facts
        .view_revision(&FrontendRevision::new(changed))
        .is_err());
    let mut changed = (*original).clone();
    changed.files = Arc::from([]);
    assert!(facts
        .view_revision(&FrontendRevision::new(changed))
        .is_err());
    let mut changed = (*original).clone();
    changed.plan.project_dir = "different".into();
    assert!(facts
        .view_revision(&FrontendRevision::new(changed))
        .is_err());
}

#[test]
fn owned_startup_certificate_does_not_keep_body_source_payloads_alive() {
    let frontend = FrontendRevision::new(frontend());
    let syntax = Arc::downgrade(&frontend.syntax);
    let arena = Arc::downgrade(&frontend.expanded.text);
    let bodies = Arc::downgrade(&frontend.bodies);
    let ledger = Arc::downgrade(&frontend.allocation_ledger);
    let facts = capture_revision_facts_with_spellings_and_workers(&frontend, &[], 1).unwrap();
    drop(frontend);
    assert!(syntax.upgrade().is_none());
    assert!(arena.upgrade().is_none());
    assert!(bodies.upgrade().is_none());
    assert!(ledger.upgrade().is_none());
    assert!(facts
        .view_revision(&FrontendRevision::new(self::frontend()))
        .is_err());
}

#[test]
fn raw_model_rebinding_revalidates_stored_body_facts() {
    struct Edited;
    impl dm_preprocess::SourceProvider for Edited {
        fn read(&self, _: &Path) -> Result<String, String> {
            Source
                .read(Path::new("owned.dme"))
                .map(|source| source.replace("= 3", "= 4"))
        }
    }
    let revision = FrontendRevision::new(frontend());
    let facts = capture_revision_facts_with_spellings_and_workers(&revision, &[], 1).unwrap();
    let identical = frontend();
    facts
        .view(&identical)
        .unwrap()
        .validate_for(&identical)
        .unwrap();
    let edited =
        dm_tree::frontend::build(Path::new("owned.dme"), &Edited, &Default::default(), 1).unwrap();
    assert_eq!(
        edited.snapshot.tree.identity(),
        revision.snapshot.tree.identity()
    );
    assert!(facts.view(&edited).is_err());
}
