use super::*;
struct OwnedRoot(PathBuf);
impl OwnedRoot {
    fn new() -> Self {
        let base = if cfg!(windows) { PathBuf::from("E:/dq-cache/dmb-protocol-checks") }
            else { std::env::temp_dir() };
        let stamp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)
            .unwrap().as_nanos();
        let root = base.join(format!("journal-view-{}-{stamp}", std::process::id()));
        fs::create_dir_all(&root).unwrap(); Self(root)
    }
}
impl Drop for OwnedRoot { fn drop(&mut self) { let _ = fs::remove_dir_all(&self.0); } }
#[test]
fn access_view_preserves_exact_bytes_absence_and_membership_after_live_change() {
    let root = OwnedRoot::new();
    let source = root.0.join("source.dm");
    let absent = root.0.join("absent.dm");
    let folder = root.0.join("assets");
    fs::create_dir(&folder).unwrap();
    fs::write(folder.join("first.txt"), b"first").unwrap();
    fs::write(&source, b"captured source").unwrap();
    let directory = root.0.join("journal");
    let inputs = Inputs::record(&directory).unwrap();
    let original = inputs.read_verified(&source).unwrap();
    assert_eq!(inputs.read(&absent).unwrap_err().kind(), io::ErrorKind::NotFound);
    let membership = inputs.list(&folder).unwrap();
    inputs.finish().unwrap();
    drop(inputs);
    fs::write(&source, b"new source").unwrap();
    fs::write(&absent, b"now present").unwrap();
    fs::write(folder.join("second.txt"), b"second").unwrap();
    let replay = Inputs::replay(&directory).unwrap();
    replay.with_access_view(|view| {
        let files = view.files().collect::<Vec<_>>();
        assert_eq!(files.len(), 1);
        assert_eq!(files[0].path, canonical_path(&source));
        assert_eq!(files[0].stamp, original.stamp());
        assert_eq!(files[0].content, original.content());
        assert_eq!(files[0].read_verified()?.bytes(), b"captured source");
        assert_eq!(view.negative_paths().collect::<Vec<_>>(), vec![canonical_path(&absent)]);
        let folders = view.folders().collect::<Vec<_>>();
        assert_eq!(folders.len(), 1);
        assert_eq!(folders[0], (canonical_path(&folder).as_path(), &membership));
        Ok(())
    }).unwrap().unwrap();
    assert_ne!(FileSystemInputs.list(&folder).unwrap(), membership);
}
#[test]
fn access_view_recording_and_replay_share_payload_validation() {
    let root = OwnedRoot::new();
    let source = root.0.join("source.dm");
    fs::write(&source, b"valid").unwrap();
    let directory = root.0.join("journal");
    let inputs = Inputs::record(&directory).unwrap();
    inputs.read(&source).unwrap();
    inputs.with_access_view(|view| {
        let file = view.files().next().unwrap();
        assert_eq!(file.read_verified()?.bytes(), b"valid");
        fs::write(directory.join("payloads").join(format!("{:032x}", file.content)), b"wrong")?;
        assert_eq!(file.read_verified().err().unwrap().kind(), io::ErrorKind::InvalidData);
        Ok(())
    }).unwrap();
    assert_eq!(inputs.read_verified(&source).unwrap().bytes(), b"valid");
    inputs.finish().unwrap();
    let replay = Inputs::replay(&directory).unwrap();
    assert_eq!(replay.read_verified(&source).err().unwrap().kind(), io::ErrorKind::InvalidData);
}
#[test]
fn access_view_live_provider_has_no_issued_roster() {
    let result = Inputs::Live.with_access_view(|_| -> io::Result<()> {
        panic!("live provider must not invent journal authority")
    }).unwrap();
    assert!(result.is_none());
}
