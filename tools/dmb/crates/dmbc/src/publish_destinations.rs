//! Reject conventional destination aliases before any file is replaced.
use super::*;
use crate::input_snapshot::{FileSystemInputs, SnapshotProvider};

pub(super) fn absolute_identity(path: &Path) -> io::Result<PathBuf> {
    let absolute = std::path::absolute(path)?;
    let mut ancestor = absolute.clone();
    let mut tail = Vec::new();
    loop {
        match fs::canonicalize(&ancestor) {
            Ok(mut resolved) => {
                for part in tail.iter().rev() {
                    resolved.push(part);
                }
                return Ok(dm_preprocess::regions::canonical_path(&resolved));
            }
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                let name = ancestor
                    .file_name()
                    .ok_or_else(|| invalid("output destination has no existing ancestor"))?
                    .to_owned();
                tail.push(name);
                if !ancestor.pop() {
                    return Err(error);
                }
            }
            Err(error) => return Err(error),
        }
    }
}
#[cfg(not(windows))]
pub(super) fn same_path(left: &Path, right: &Path) -> io::Result<bool> {
    Ok(left == right)
}
#[cfg(windows)]
pub(super) fn same_path(left: &Path, right: &Path) -> io::Result<bool> {
    use std::os::windows::ffi::OsStrExt;
    #[link(name = "kernel32")]
    extern "system" {
        fn CompareStringOrdinal(
            left: *const u16,
            left_len: i32,
            right: *const u16,
            right_len: i32,
            ignore_case: i32,
        ) -> i32;
    }
    let left: Vec<u16> = left.as_os_str().encode_wide().collect();
    let right: Vec<u16> = right.as_os_str().encode_wide().collect();
    let left_len = i32::try_from(left.len()).map_err(invalid)?;
    let right_len = i32::try_from(right.len()).map_err(invalid)?;
    let result =
        unsafe { CompareStringOrdinal(left.as_ptr(), left_len, right.as_ptr(), right_len, 1) };
    if result == 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(result == 2)
    }
}
pub(super) fn distinct(paths: [&Path; 3]) -> io::Result<()> {
    let identities = paths.map(absolute_identity);
    let identities = identities.into_iter().collect::<io::Result<Vec<_>>>()?;
    let mut files = Vec::new();
    for path in paths {
        match FileSystemInputs.stamp(path) {
            Ok(stamp) => files.push(stamp.file_id),
            Err(error) if error.kind() == io::ErrorKind::NotFound => files.push(None),
            Err(error) => return Err(error),
        }
    }
    for left in 0..3 {
        for right in left + 1..3 {
            if same_path(&identities[left], &identities[right])?
                || files[left].is_some() && files[left] == files[right]
            {
                return Err(invalid(
                    "conventional output destinations alias the same file",
                ));
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn aliases_are_rejected_before_existing_outputs_change() {
        let store = super::super::tests::store();
        let file = store.root.join("existing.dmb");
        let alias = store.root.join("existing-alias.rsc");
        fs::write(&file, b"preserved").unwrap();
        fs::hard_link(&file, &alias).unwrap();
        assert!(distinct([&file, &alias, &store.root.join("marker.json")]).is_err());
        assert_eq!(fs::read(file).unwrap(), b"preserved");
    }
    #[test]
    fn absent_parent_component_aliases_are_rejected() {
        let store = super::super::tests::store();
        let output = store.root.join("missing/output.dmb");
        let alias = store.root.join("missing/./output.dmb");
        assert!(distinct([&output, &alias, &store.root.join("marker.json")]).is_err());
        assert!(!store.root.join("missing").exists());
    }
    #[cfg(windows)]
    #[test]
    fn absent_case_aliases_are_rejected() {
        let store = super::super::tests::store();
        assert!(distinct([
            &store.root.join("missing/OUTPUT.dmb"),
            &store.root.join("missing/output.dmb"),
            &store.root.join("marker.json")
        ])
        .is_err());
    }
}
