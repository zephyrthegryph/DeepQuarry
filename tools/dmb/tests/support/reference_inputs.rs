use byond_dmb::rsc::Entry;
use std::path::{Component, Path, PathBuf};

pub struct ReferenceInputs(pub PathBuf);
impl Drop for ReferenceInputs {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

/// Mirror authored inputs, accepting only checkout newline differences from
/// the exact declared resource payload in a pinned reference archive.
pub fn prepare(root: &Path, archive: &[Entry], selected: impl Fn(&str) -> bool) -> ReferenceInputs {
    static SEQUENCE: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    fn copy(source: &Path, target: &Path) {
        for entry in std::fs::read_dir(source).unwrap() {
            let entry = entry.unwrap();
            let output = target.join(entry.file_name());
            if entry.file_type().unwrap().is_dir() {
                std::fs::create_dir(&output).unwrap();
                copy(&entry.path(), &output);
            } else {
                std::fs::copy(entry.path(), output).unwrap();
            }
        }
    }
    fn lf(bytes: &[u8]) -> Vec<u8> {
        bytes
            .iter()
            .enumerate()
            .filter_map(|(index, &byte)| {
                if byte == b'\r' && bytes.get(index + 1) == Some(&b'\n') {
                    None
                } else {
                    Some(byte)
                }
            })
            .collect()
    }
    let directory = std::env::temp_dir().join(format!(
        "dmb-reference-inputs-{}-{}",
        std::process::id(),
        SEQUENCE.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    ));
    std::fs::create_dir(&directory).unwrap();
    let inputs = ReferenceInputs(directory);
    copy(root, &inputs.0);
    for entry in archive {
        if let Entry::Named(asset) = entry {
            let name = std::str::from_utf8(&asset.name).unwrap();
            if !selected(name) {
                continue;
            }
            let relative = Path::new(name);
            assert!(
                relative
                    .components()
                    .all(|part| matches!(part, Component::Normal(_))),
                "reference asset path"
            );
            let output = inputs.0.join(relative);
            let checkout = std::fs::read(&output).unwrap();
            let payload = asset.asset_bytes().unwrap();
            assert_eq!(
                lf(&checkout),
                lf(payload),
                "{name}: fixture differs beyond LF/CRLF"
            );
            // RAD trailing capacity is not authored source content.
            std::fs::write(output, payload).unwrap();
        }
    }
    inputs
}
