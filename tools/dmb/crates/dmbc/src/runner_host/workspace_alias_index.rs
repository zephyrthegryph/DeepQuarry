//! Candidate index only; a selected alias still needs its private receipt.
use super::*;
use dm_preprocess::regions::filesystem_comparison_key;
const COORD: usize = 128 + std::mem::size_of::<(PathBuf, Vec<&Path>)>();
pub(super) struct AliasIndex<'a> {
    rows: BTreeMap<PathBuf, Vec<&'a Path>>,
    charged: usize,
    #[cfg(test)]
    normalized: std::cell::Cell<usize>,
    #[cfg(test)]
    comparisons: std::cell::Cell<usize>,
}
impl<'a> AliasIndex<'a> {
    pub(super) fn reserve_charge(mut paths: impl Iterator<Item = &'a Path>) -> io::Result<usize> {
        paths.try_fold(std::mem::size_of::<Self>(), |n, path| {
            n.checked_add(512)
                .and_then(|n| {
                    n.checked_add(path.as_os_str().as_encoded_bytes().len().checked_mul(4)?)
                })
                .ok_or_else(|| io::Error::other("workspace alias index reserve overflow"))
        })
    }
    pub(super) fn new(paths: impl Iterator<Item = &'a Path>, budget: usize) -> io::Result<Self> {
        let mut result = Self {
            rows: BTreeMap::new(),
            charged: std::mem::size_of::<Self>(),
            #[cfg(test)]
            normalized: std::cell::Cell::new(0),
            #[cfg(test)]
            comparisons: std::cell::Cell::new(0),
        };
        if result.charged > budget {
            return Err(io::Error::other("alias index metadata admission exhausted"));
        }
        for path in paths {
            crate::daemon::control::checkpoint()?;
            let reserve = 512usize
                .checked_add(
                    path.as_os_str()
                        .as_encoded_bytes()
                        .len()
                        .checked_mul(4)
                        .ok_or_else(|| io::Error::other("alias path reserve overflow"))?,
                )
                .ok_or_else(|| io::Error::other("alias index reserve overflow"))?;
            if result
                .charged
                .checked_add(reserve)
                .is_none_or(|n| n > budget)
            {
                return Err(io::Error::other(
                    "alias index preallocation admission exhausted",
                ));
            }
            let key = filesystem_comparison_key(path);
            #[cfg(test)]
            result.normalized.set(result.normalized.get() + 1);
            let key_charge = if !result.rows.contains_key(&key) {
                key.capacity() + COORD
            } else {
                0
            };
            let values = result.rows.entry(key).or_default();
            let old = values.capacity();
            values
                .try_reserve_exact(1)
                .map_err(|_| io::Error::other("alias vector allocation failed"))?;
            let delta = values
                .capacity()
                .checked_sub(old)
                .and_then(|n| n.checked_mul(std::mem::size_of::<&Path>()))
                .ok_or_else(|| io::Error::other("alias vector overflow"))?;
            result.charged = result
                .charged
                .checked_add(key_charge)
                .and_then(|n| n.checked_add(delta))
                .filter(|n| *n <= budget)
                .ok_or_else(|| io::Error::other("actual alias index capacity exceeds admission"))?;
            values.push(path);
        }
        Ok(result)
    }
    pub(super) fn candidate(&self, path: &Path) -> io::Result<Option<&'a Path>> {
        let key = filesystem_comparison_key(path);
        #[cfg(test)]
        self.normalized.set(self.normalized.get() + 1);
        let mut found = None;
        if let Some(candidates) = self.rows.get(&key) {
            for &candidate in candidates {
                #[cfg(test)]
                self.comparisons.set(self.comparisons.get() + 1);
                // Keep the old predicate; an index key is never source authority.
                if relative_filesystem_path(candidate, path)
                    .is_some_and(|p| p.as_os_str().is_empty())
                {
                    if found.replace(candidate).is_some() {
                        return Err(io::Error::other(
                            "ambiguous native source acquisition alias",
                        ));
                    }
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
        assert_eq!(
            index.charged,
            std::mem::size_of_val(&index)
                + index
                    .rows
                    .iter()
                    .map(|(key, v)| key.capacity()
                        + COORD
                        + v.capacity() * std::mem::size_of::<&Path>())
                    .sum::<usize>()
        );
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
