//! Candidate index only; a selected alias still needs its private receipt.
use super::*;
use dm_preprocess::regions::filesystem_comparison_key;
use std::hash::{Hash, Hasher};

pub(crate) struct AliasIndex<'a> {
    rows: Vec<(u64, &'a Path)>,
    #[cfg(test)]
    normalized: std::cell::Cell<usize>,
    #[cfg(test)]
    comparisons: std::cell::Cell<usize>,
}

impl<'a> AliasIndex<'a> {
    fn scratch(path: &Path) -> io::Result<usize> {
        path.as_os_str().as_encoded_bytes().len().checked_mul(4)
            .and_then(|bytes| bytes.checked_add(512))
            .ok_or_else(|| io::Error::other("workspace alias normalization reserve overflow"))
    }

    fn row_bytes(count: usize) -> io::Result<usize> {
        count.checked_mul(std::mem::size_of::<(u64, &Path)>())
            .and_then(|bytes| bytes.checked_add(std::mem::size_of::<Self>()))
            .ok_or_else(|| io::Error::other("workspace alias rows reserve overflow"))
    }

    fn key(path: &Path) -> u64 {
        let mut hash = std::collections::hash_map::DefaultHasher::new();
        // Use Path's equality-compatible hash after the exact existing
        // comparison normalization. A collision only adds candidate checks.
        filesystem_comparison_key(path).hash(&mut hash);
        hash.finish()
    }

    pub(crate) fn reserve_charge(mut paths: impl ExactSizeIterator<Item = &'a Path>) -> io::Result<usize> {
        let rows = Self::row_bytes(paths.len())?;
        let scratch = paths.try_fold(0, |peak, path| Ok::<_, io::Error>(peak.max(Self::scratch(path)?)))?;
        rows.checked_add(scratch).ok_or_else(|| io::Error::other("workspace alias reserve overflow"))
    }

    pub(crate) fn new(paths: impl ExactSizeIterator<Item = &'a Path>, budget: usize) -> io::Result<Self> {
        let count = paths.len();
        let row_bytes = Self::row_bytes(count)?;
        let scratch = budget.checked_sub(row_bytes)
            .ok_or_else(|| io::Error::other("alias rows exceed preallocation admission"))?;
        let mut result = Self {
            rows: Vec::new(),
            #[cfg(test)]
            normalized: std::cell::Cell::new(0),
            #[cfg(test)]
            comparisons: std::cell::Cell::new(0),
        };
        result.rows.try_reserve_exact(count)
            .map_err(|error| io::Error::new(io::ErrorKind::OutOfMemory, error))?;
        if result.rows.capacity() != count {
            return Err(io::Error::new(io::ErrorKind::OutOfMemory, "alias row capacity differs from admission"));
        }
        for path in paths {
            crate::daemon::control::checkpoint()?;
            if Self::scratch(path)? > scratch || result.rows.len() == count {
                return Err(io::Error::new(io::ErrorKind::OutOfMemory, "alias index exceeds admission"));
            }
            result.rows.push((Self::key(path), path));
            #[cfg(test)]
            result.normalized.set(result.normalized.get() + 1);
        }
        crate::daemon::control::checkpoint()?;
        result.rows.sort_unstable_by_key(|(hash, _)| *hash);
        crate::daemon::control::checkpoint()?;
        Ok(result)
    }

    pub(crate) fn candidate(&self, path: &Path) -> io::Result<Option<&'a Path>> {
        let key = Self::key(path);
        #[cfg(test)]
        self.normalized.set(self.normalized.get() + 1);
        let start = self.rows.partition_point(|(hash, _)| *hash < key);
        let mut found = None;
        for &(hash, candidate) in &self.rows[start..] {
            if hash != key {
                break;
            }
            crate::daemon::control::checkpoint()?;
            #[cfg(test)]
            self.comparisons.set(self.comparisons.get() + 1);
            // Keep the old predicate; an index key is never source authority.
            if relative_filesystem_path(candidate, path).is_some_and(|p| p.as_os_str().is_empty()) {
                if found.replace(candidate).is_some() {
                    return Err(io::Error::other("ambiguous native source acquisition alias"));
                }
            }
        }
        Ok(found)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn old<'a>(known: &'a [PathBuf], path: &Path) -> io::Result<Option<&'a Path>> {
        let mut found = None;
        for candidate in known {
            if relative_filesystem_path(candidate, path).is_some_and(|v| v.as_os_str().is_empty()) {
                if found.replace(candidate.as_path()).is_some() {
                    return Err(io::Error::other("ambiguous"));
                }
            }
        }
        Ok(found)
    }
    #[test]
    fn alias_index_matches_original_scan_collisions_and_negative_keys() {
        let known = vec![
            PathBuf::from("root/a.dm"),
            PathBuf::from("root/x/../b.dm"),
            PathBuf::from("root/b.dm"),
            PathBuf::from("root/unicode-\u{0394}.dm"),
        ];
        let index = AliasIndex::new(
            known.iter().map(PathBuf::as_path),
            AliasIndex::reserve_charge(known.iter().map(PathBuf::as_path)).unwrap(),
        )
        .unwrap();
        for path in [
            "root/a.dm",
            "root/./a.dm",
            "root/b.dm",
            "root/x/../b.dm",
            "root/missing.dm",
            "root/unicode-\u{0394}.dm",
            "root/UNICODE-\u{0394}.dm",
        ] {
            let a = index.candidate(Path::new(path));
            let b = old(&known, Path::new(path));
            assert_eq!(a.is_err(), b.is_err(), "{path}");
            if let (Ok(a), Ok(b)) = (a, b) {
                assert_eq!(a, b, "{path}");
            }
        }
    }
    #[test]
    fn alias_lookup_work_is_normalizations_plus_candidates_not_uncompiled_times_compiled() {
        let known = (0..128)
            .map(|n| PathBuf::from(format!("root/compiled-{n}.dm")))
            .collect::<Vec<_>>();
        let index = AliasIndex::new(
            known.iter().map(PathBuf::as_path),
            AliasIndex::reserve_charge(known.iter().map(PathBuf::as_path)).unwrap(),
        )
        .unwrap();
        let mut reference = 0;
        for n in 0..128 {
            let path = PathBuf::from(format!("root/uncompiled-{n}.dm"));
            for candidate in &known {
                reference += 1;
                assert!(!relative_filesystem_path(candidate, &path)
                    .is_some_and(|p| p.as_os_str().is_empty()));
            }
            assert!(index.candidate(&path).unwrap().is_none());
        }
        assert_eq!(reference, 128 * 128);
        assert_eq!(index.normalized.get(), 256);
        assert_eq!(index.comparisons.get(), 0);
    }
    #[test]
    fn alias_index_actual_coordinates_are_charged_and_admission_precedes_growth() {
        let known = vec![PathBuf::from("root/long-key.dm")];
        assert!(AliasIndex::new(
            known.iter().map(PathBuf::as_path),
            std::mem::size_of::<AliasIndex<'_>>()
        )
        .is_err());
        let index = AliasIndex::new(
            known.iter().map(PathBuf::as_path),
            AliasIndex::reserve_charge(known.iter().map(PathBuf::as_path)).unwrap(),
        )
        .unwrap();
        assert_eq!(index.rows.capacity(), known.len());
        assert_eq!(
            AliasIndex::reserve_charge(known.iter().map(PathBuf::as_path)).unwrap(),
            AliasIndex::row_bytes(index.rows.capacity()).unwrap()
                + AliasIndex::scratch(&known[0]).unwrap(),
        );
    }

    #[test]
    fn alias_digest_collision_cannot_authorize_a_foreign_path() {
        let known = [PathBuf::from("root/a.dm"), PathBuf::from("root/b.dm")];
        let mut index = AliasIndex::new(
            known.iter().map(PathBuf::as_path),
            AliasIndex::reserve_charge(known.iter().map(PathBuf::as_path)).unwrap(),
        ).unwrap();
        let hash = AliasIndex::key(&known[0]);
        for row in &mut index.rows {
            row.0 = hash;
        }
        assert_eq!(index.candidate(&known[0]).unwrap(), Some(known[0].as_path()));
        index.rows.retain(|row| row.1 == known[1].as_path());
        assert!(index.candidate(&known[0]).unwrap().is_none());
    }
    #[cfg(windows)]
    #[test]
    fn windows_alias_keys_keep_unsafe_verbatim_and_device_policy() {
        let known = vec![
            PathBuf::from(r"C:\root\a.dm"),
            PathBuf::from(r"\\?\C:\root\a.dm"),
            PathBuf::from(r"\\?\C:\root\NUL.dm"),
            PathBuf::from(r"C:\root\a.dm:stream"),
        ];
        let index = AliasIndex::new(
            known.iter().map(PathBuf::as_path),
            AliasIndex::reserve_charge(known.iter().map(PathBuf::as_path)).unwrap(),
        )
        .unwrap();
        for path in [
            r"C:\root\a.dm",
            r"\\?\C:\root\a.dm",
            r"C:\root\NUL.dm",
            r"\\?\C:\root\NUL.dm",
            r"C:\root\a.dm:stream",
        ] {
            let a = index.candidate(Path::new(path));
            let b = old(&known, Path::new(path));
            assert_eq!(a.is_err(), b.is_err());
            if let (Ok(a), Ok(b)) = (a, b) {
                assert_eq!(a, b);
            }
        }
    }
}
