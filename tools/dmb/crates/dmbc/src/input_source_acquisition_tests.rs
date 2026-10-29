use super::*;
use dm_preprocess::SourceProvider;
#[derive(Clone)]
struct P {
    bytes: Arc<Vec<u8>>,
    reads: Arc<std::sync::atomic::AtomicUsize>,
}
impl P {
    fn new(bytes: &[u8]) -> Self {
        Self {
            bytes: Arc::new(bytes.to_vec()),
            reads: Arc::new(Default::default()),
        }
    }
}
impl SnapshotProvider for P {
    fn stamp(&self, _: &Path) -> io::Result<Stamp> {
        Ok(Stamp {
            size: self.bytes.len() as u64,
            modified_ns: 1,
            file_id: Some(1),
        })
    }
    fn read(&self, p: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        self.reads.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        Ok((self.stamp(p)?, self.bytes.as_ref().clone()))
    }
    fn list(&self, _: &Path) -> io::Result<FolderListing> {
        Ok(FolderListing::Present(vec!["x.dm".into()]))
    }
}
#[test]
fn warm_prepared_reissues_actual_original_lease_without_a_read() {
    let p = P::new(b"/datum/acquired_source_warm\n");
    let store = Arc::new(PreparedInputArtifacts::default());
    let path = Path::new("x.dm");
    let first = RecordingInputs::new(p.clone(), 4_000_000_000).with_prepared_sources(Some(store.clone()));
    let old = SourceProvider::acquired_source(&first, path)
        .unwrap()
        .unwrap();
    let before = p.reads.load(std::sync::atomic::Ordering::SeqCst);
    let next = RecordingInputs::new(p.clone(), 5_000_000_000).with_prepared_sources(Some(store));
    let new = SourceProvider::acquired_source(&next, path)
        .unwrap()
        .unwrap();
    assert_eq!(p.reads.load(std::sync::atomic::Ordering::SeqCst), before);
    assert!(old.same_original_acquisition(&new));
    assert!(!old.same_binding(&new));
    assert!(next.validate_source_acquisition(path, &new));
    assert!(!next.validate_source_acquisition(path, &old));
}
#[test]
fn foreign_normal_lease_rejects_even_with_equal_interned_source() {
    let a = RecordingInputs::new(P::new(b"/datum/foreign_normal_lease\n"), 1);
    let b = RecordingInputs::new(P::new(b"/datum/foreign_normal_lease\n"), 1);
    let p = Path::new("x.dm");
    let x = SourceProvider::acquired_source(&a, p).unwrap().unwrap();
    let y = SourceProvider::acquired_source(&b, p).unwrap().unwrap();
    assert!(Arc::ptr_eq(x.prepared(), y.prepared()));
    assert!(!b.validate_source_acquisition(p, &x));
    assert!(b.validate_source_acquisition(p, &y));
}

#[test]
fn racy_timestamp_rechecks_original_and_reissues_only_authenticated_lease(){
 let p=P::new(b"/datum/acquired_source_racy\n");let store=Arc::new(PreparedInputArtifacts::default());let path=Path::new("x.dm");
 let first=RecordingInputs::new(p.clone(),1).with_prepared_sources(Some(store.clone()));
 let old=SourceProvider::acquired_source(&first,path).unwrap().unwrap();let before=p.reads.load(std::sync::atomic::Ordering::SeqCst);
 let next=RecordingInputs::new(p.clone(),2).with_prepared_sources(Some(store));
 let current=SourceProvider::acquired_source(&next,path).unwrap().unwrap();
 assert!(p.reads.load(std::sync::atomic::Ordering::SeqCst)>before,"racy source metadata cannot suppress original-byte validation");
 assert!(old.same_original_acquisition(&current));assert!(!old.same_binding(&current));
 assert!(next.validate_source_acquisition(path,&current));assert!(!next.validate_source_acquisition(path,&old));
}
