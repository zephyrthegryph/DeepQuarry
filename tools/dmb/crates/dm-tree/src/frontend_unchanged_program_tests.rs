use super::*;
use std::{
    cell::RefCell,
    collections::BTreeMap,
    sync::atomic::{AtomicUsize, Ordering},
    sync::Mutex,
};
struct Sources {
    entries: RefCell<BTreeMap<PathBuf, dm_preprocess::AcquiredSource>>,
}
impl Sources {
    fn new(source: &str) -> Self {
        Self {
            entries: RefCell::new(BTreeMap::from([(
                PathBuf::from("reuse.dme"),
                dm_preprocess::AcquiredSource::from_original_bytes(
                    source.as_bytes().to_vec(),
                    1u64,
                ),
            )])),
        }
    }
    fn refresh(&self) {
        for value in self.entries.borrow_mut().values_mut() {
            *value = value.reissued(2u64);
        }
    }
    fn replace(&self, source: &str) {
        self.entries.borrow_mut().insert(
            PathBuf::from("reuse.dme"),
            dm_preprocess::AcquiredSource::from_original_bytes(source.as_bytes().to_vec(), 3u64),
        );
    }
}
impl SourceProvider for Sources {
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("original acquisition required".into())
    }
    fn acquired_source(
        &self,
        path: &Path,
    ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
        Ok(self.entries.borrow().get(path).cloned())
    }
    fn source_acquisition(
        &self,
        path: &Path,
        text: &dm_preprocess::SourceText,
    ) -> Option<dm_preprocess::AcquiredSource> {
        self.entries
            .borrow()
            .get(path)
            .filter(|value| value.lease().source_text().same_view(text))
            .cloned()
    }
}
#[derive(Debug, Default)]
struct Bodies {
    parsed: AtomicUsize,
    values: Mutex<BTreeMap<u64, Arc<BodySyntax>>>,
}
impl BodySyntaxQueries for Bodies {
    fn syntax(&self, input: &Arc<BodySyntaxInput>) -> Result<Arc<BodySyntax>, Diagnostic> {
        let mut values = self.values.lock().unwrap();
        if let Some(value) = values.get(&input.key()) {
            return Ok(Arc::clone(value));
        }
        self.parsed.fetch_add(1, Ordering::Relaxed);
        let value = Arc::new(input.parse()?);
        values.insert(input.key(), Arc::clone(&value));
        Ok(value)
    }
}
fn prepare(
    sources: &Sources,
    state: &mut RetainedSemanticTree,
    executor: &dm_exec::BuildExecutor,
) -> DiagnosticFrontend {
    build_for_checker_diagnostics_with_state(
        Path::new("reuse.dme"),
        sources,
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        executor,
        Some(state),
    )
    .unwrap()
}
#[test]
fn valid_diagnostic_transfer_adopts_complete_native_entry_and_reuses_original_tree_and_body_parse()
{
    let source = "/datum/probe\n    var/value=null\n    proc/read()\n        return value\n";
    let sources = Sources::new(source);
    let mut state = RetainedSemanticTree::one_shot();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let bodies = Arc::new(Bodies::default());
    let first =
        match prepare(&sources, &mut state, &executor).try_into_compilable_retained(&mut state) {
            Ok(value) => value,
            Err(_) => panic!("valid original graph needs complete records"),
        }
        .with_body_queries(bodies.clone());
    let first = FrontendRevision::new(first);
    assert!(Arc::ptr_eq(
        state.snapshot_tree().unwrap(),
        &first.snapshot.tree
    ));
    assert_eq!(state.rebuilds(), 1);
    let a = first.body_archive().unwrap();
    let old = a.parse(0).unwrap();
    assert_eq!(bodies.parsed.load(Ordering::Relaxed), 1);
    state.remember_frontend(Path::new("reuse.dme"), &Default::default(), first.clone());
    sources.refresh();
    let second = build_with_executor_and_semantic_state_for_policy(
        Path::new("reuse.dme"),
        &sources,
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        &executor,
        Some(&mut state),
        true,
    )
    .unwrap()
    .with_body_queries(bodies.clone());
    assert_eq!(
        first.snapshot.tree.identity(),
        second.snapshot.tree.identity()
    );
    assert_eq!(
        first.source_export_revision(),
        second.source_export_revision()
    );
    assert!(Arc::ptr_eq(&first.snapshot.tree, &second.snapshot.tree));
    assert!(Arc::ptr_eq(&first.syntax, &second.syntax));
    assert!(Arc::ptr_eq(
        &first.allocation_ledger,
        &second.allocation_ledger
    ));
    assert!(Arc::ptr_eq(&first.bodies, &second.bodies));
    assert_eq!(state.rebuilds(), 1, "no second native normalization/build");
    assert_eq!(state.hits(), 1);
    assert_eq!(second.timings.declaration_parsing, Duration::ZERO);
    assert_eq!(second.timings.tree_resolution, Duration::ZERO);
    let b = second.body_archive().unwrap();
    let new = b.parse(0).unwrap();
    assert!(std::ptr::eq(old.statement_body(), new.statement_body()));
    assert_eq!(
        bodies.parsed.load(Ordering::Relaxed),
        1,
        "same original BodySyntax input must not parse again"
    );
    assert!(
        !Arc::ptr_eq(a.source_mapping(), b.source_mapping()),
        "current authority wrapper must refresh, not reuse old issuer"
    );
    let old_lease = a.source_acquisition(0).unwrap();
    let new_lease = b.source_acquisition(0).unwrap();
    assert!(old_lease.same_original_acquisition(new_lease));
    assert!(!old_lease.same_binding(new_lease));
    b.original_note_origin(source.find("value=null").unwrap())
        .unwrap();
    sources.refresh();
    let again = prepare(&sources, &mut state, &executor);
    let again = match again.try_into_compilable_retained(&mut state) {
        Ok(frontend) => frontend,
        Err(_) => panic!("same original complete entry must admit re-preparation"),
    }
    .with_body_queries(bodies.clone());
    assert!(Arc::ptr_eq(&first.snapshot.tree, &again.snapshot.tree));
    assert_eq!(state.rebuilds(), 1);
    assert_eq!(state.hits(), 2);
    again.body_archive().unwrap().parse(0).unwrap();
    assert_eq!(bodies.parsed.load(Ordering::Relaxed), 1);
}
#[test]
fn changed_original_bytes_invalidate_same_program_reuse_and_error_owner_never_enters_retained_state(
) {
    let sources = Sources::new("/datum/probe\n    var/value=1\n");
    let mut state = RetainedSemanticTree::one_shot();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let first =
        match prepare(&sources, &mut state, &executor).try_into_compilable_retained(&mut state) {
            Ok(value) => FrontendRevision::new(value),
            Err(_) => panic!("valid original"),
        };
    state.remember_frontend(Path::new("reuse.dme"), &Default::default(), first.clone());
    sources.replace("/datum/probe\n    var/value=2\n");
    let changed = prepare(&sources, &mut state, &executor);
    assert!(!Arc::ptr_eq(
        changed.source_view().unwrap().tree(),
        &first.snapshot.tree
    ));
    sources.replace("/datum/base\n    var/p=null\n/datum/base/child\n    var/p=null\n");
    let error = prepare(&sources, &mut state, &executor);
    assert_eq!(error.source_view().unwrap().receipt().errors().len(), 1);
    assert!(error.try_into_compilable_retained(&mut state).is_err());
    assert!(Arc::ptr_eq(
        state.snapshot_tree().unwrap(),
        &first.snapshot.tree
    ));
}

#[test]
fn decoded_equal_bom_change_does_not_fake_original_acquisition_identity() {
    let plain = "/datum/probe\n    var/value=1\n";
    let sources = Sources::new(plain);
    let mut state = RetainedSemanticTree::one_shot();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let first =
        match prepare(&sources, &mut state, &executor).try_into_compilable_retained(&mut state) {
            Ok(frontend) => FrontendRevision::new(frontend),
            Err(_) => panic!("valid original"),
        };
    state.remember_frontend(Path::new("reuse.dme"), &Default::default(), first.clone());
    sources.replace(&format!("\u{feff}{plain}"));
    let changed = prepare(&sources, &mut state, &executor);
    let current = changed.source_view().unwrap();
    assert_eq!(
        current.tree().identity(),
        first.snapshot.tree.identity(),
        "semantic equality alone must not authorize reuse"
    );
    assert!(!Arc::ptr_eq(current.tree(), &first.snapshot.tree));
    assert_ne!(
        current.mapping().source_acquisition(0).unwrap().encoding(),
        first
            .source_export_mapping()
            .unwrap()
            .source_acquisition(0)
            .unwrap()
            .encoding()
    );
}
