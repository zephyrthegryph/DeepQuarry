use super::*;
use dm_preprocess::{AcquiredSource, SourceProvider};
struct Provider(AcquiredSource);
impl SourceProvider for Provider {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Err("issued source expected".into())
    }
    fn acquired_source(&self, _: &std::path::Path) -> Result<Option<AcquiredSource>, String> {
        Ok(Some(self.0.clone()))
    }
    fn source_acquisition(
        &self,
        _: &std::path::Path,
        text: &dm_preprocess::SourceText,
    ) -> Option<AcquiredSource> {
        self.0
            .prepared()
            .original()
            .same_view(text)
            .then(|| self.0.clone())
    }
}
#[test]
fn release_body_queries_frees_lexical_preparation_but_preserves_light_pages() {
    let provider = Provider(AcquiredSource::from_original_bytes(
        b"/datum/idle_lease_unique_834798/proc/run()\n    return\n".to_vec(),
        23u64,
    ));
    let lexical = Arc::downgrade(provider.0.prepared());
    let frontend = dm_tree::frontend::build(
        std::path::Path::new("code/idle_lease.dm"),
        &provider,
        &Default::default(),
        1,
    )
    .unwrap();
    let mut snapshot = SourceSnapshot::capture(&frontend);
    let mut before = Vec::new();
    snapshot
        .write_body_contexts_page(0, 1, &snapshot.tree, &mut before)
        .unwrap();
    let lease = snapshot
        .source_mapping
        .as_ref()
        .unwrap()
        .source_acquisition(0)
        .unwrap()
        .clone();
    drop(frontend);
    drop(provider);
    snapshot.release_body_queries();
    assert!(
        lexical.upgrade().is_none(),
        "light mapping/lease must not retain PreparedSource lexical tables"
    );
    assert_eq!(lease.receipt::<u64>(), Some(&23));
    assert!(lease.source_text().contains("idle_lease_unique_834798"));
    let mut after = Vec::new();
    snapshot
        .write_body_contexts_page(0, 1, &snapshot.tree, &mut after)
        .unwrap();
    assert_eq!(
        after, before,
        "lightweight current source pages remain identical after heavy owner release"
    );
}
