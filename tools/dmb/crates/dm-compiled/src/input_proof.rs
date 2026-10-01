//! Metadata proofs accelerate reuse only on filesystems exposing a change clock.
//! Modification time alone is never sufficient: editors can preserve it.
use dm_host::file_stamp::{capture, FileStamp};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, path::PathBuf};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(super) struct InputProof {
    files: BTreeMap<PathBuf, FileStamp>,
    #[serde(default)]
    journal: Option<dm_host::journal::JournalProof>,
    #[serde(default)]
    namespace_covered: bool,
    #[serde(default)]
    namespace_digest: Option<String>,
}

impl InputProof {
    pub(super) fn from_stamps(files: BTreeMap<PathBuf, FileStamp>) -> Self {
        Self {
            files,
            journal: None,
            namespace_covered: false,
            namespace_digest: None,
        }
    }
    pub(super) fn capture(paths: impl IntoIterator<Item = PathBuf>) -> Option<Self> {
        if exact_inputs() {
            return None;
        }
        let files = paths
            .into_iter()
            .map(|path| capture(&path).map(|value| (path, value)))
            .collect::<Option<BTreeMap<_, _>>>()?;
        Some(Self {
            files,
            journal: None,
            namespace_covered: false,
            namespace_digest: None,
        })
    }

    pub(super) fn current(&self) -> bool {
        if exact_inputs() {
            return false;
        }
        if let Some(journal) = &self.journal {
            match journal.validate() {
                dm_host::journal::Validation::Current => return true,
                dm_host::journal::Validation::Changed => return false,
                dm_host::journal::Validation::Unavailable => {}
            }
        }
        !self.files.is_empty()
            && self
                .files
                .iter()
                .all(|(path, expected)| capture(path).as_ref() == Some(expected))
    }

    pub(super) fn resident_bytes(&self) -> usize {
        self.files
            .keys()
            .map(|path| path.as_os_str().len() * 2 + 128)
            .sum::<usize>()
            + self
                .journal
                .as_ref()
                .map_or(0, dm_host::journal::JournalProof::resident_bytes)
    }

    pub(super) fn subset(&self, paths: impl IntoIterator<Item = PathBuf>) -> Option<Self> {
        let files = paths
            .into_iter()
            .map(|path| self.files.get(&path).cloned().map(|stamp| (path, stamp)))
            .collect::<Option<BTreeMap<_, _>>>()?;
        let journal = self
            .journal
            .as_ref()
            .and_then(|journal| journal.for_files(&files));
        Some(Self {
            files,
            journal,
            namespace_covered: self.namespace_covered,
            namespace_digest: self.namespace_digest.clone(),
        })
    }

    pub(super) fn combined(mut self, other: &Self) -> Option<Self> {
        let journal = self
            .journal
            .as_ref()
            .zip(other.journal.as_ref())
            .and_then(|(left, right)| left.merged(right));
        self.namespace_covered &= other.namespace_covered;
        self.namespace_digest = match (&self.namespace_digest, &other.namespace_digest) {
            (Some(a), Some(b)) if a == b => Some(a.clone()),
            (Some(a), None) => Some(a.clone()),
            (None, Some(b)) => Some(b.clone()),
            _ => None,
        };
        self.journal = journal;
        for (path, stamp) in &other.files {
            if self
                .files
                .get(path)
                .is_some_and(|existing| existing != stamp)
            {
                return None;
            }
            self.files.insert(path.clone(), stamp.clone());
        }
        Some(self)
    }

    pub(super) fn inherit_unchanged(&mut self, previous: &Self) {
        if exact_inputs() {
            return;
        }
        self.journal = previous
            .journal
            .as_ref()
            .and_then(|journal| journal.refreshed(&previous.files, &self.files));
        self.namespace_covered = false;
        // A refresh with no unchanged files establishes a new file-only proof;
        // it does not retain the previous namespace barriers.
        self.namespace_digest = self.journal.as_ref().and_then(|_| {
            self.files
                .iter()
                .any(|(path, stamp)| previous.files.get(path) == Some(stamp))
                .then(|| previous.namespace_digest.clone())
                .flatten()
        });
    }

    pub(super) fn namespace_current(&self) -> Option<bool> {
        if !self.namespace_covered || exact_inputs() {
            return None;
        }
        match self.journal.as_ref()?.validate() {
            dm_host::journal::Validation::Current => Some(true),
            dm_host::journal::Validation::Changed => Some(false),
            dm_host::journal::Validation::Unavailable => None,
        }
    }
    pub(super) fn unchanged_paths(&self) -> std::collections::BTreeSet<PathBuf> {
        if !exact_inputs() {
            if let Some(paths) = self
                .journal
                .as_ref()
                .and_then(|journal| journal.unchanged_paths(&self.files))
            {
                return paths;
            }
        }
        self.files
            .iter()
            .filter(|(path, stamp)| capture(path).as_ref() == Some(stamp))
            .map(|(path, _)| path.clone())
            .collect()
    }
    #[cfg(test)]
    pub(super) fn enable_journal(&mut self) {
        self.enable_namespace_journal(&[]);
    }
    fn namespace_digest(candidates: &[PathBuf]) -> String {
        use sha2::{Digest, Sha256};
        let mut ordered = candidates.to_vec();
        ordered.sort();
        ordered.dedup();
        let mut hash = Sha256::new();
        for candidate in &ordered {
            let bytes = candidate.as_os_str().as_encoded_bytes();
            hash.update((bytes.len() as u64).to_le_bytes());
            hash.update(bytes);
        }
        format!("{:x}", hash.finalize())
    }
    /// Reuse only an already-established proof for this exact search namespace.
    /// This does not establish a new cursor or perform filesystem discovery.
    pub(super) fn reuse_namespace(&mut self, candidates: &[PathBuf]) -> bool {
        if !candidates.is_empty()
            && !exact_inputs()
            && self.namespace_digest.as_ref() == Some(&Self::namespace_digest(candidates))
            && self
                .journal
                .as_ref()
                .is_some_and(|journal| journal.current())
        {
            self.namespace_covered = true;
            true
        } else {
            false
        }
    }
    pub(super) fn enable_namespace_journal(&mut self, candidates: &[PathBuf]) {
        let digest = Self::namespace_digest(candidates);
        if self.reuse_namespace(candidates) {
            return;
        }
        self.journal = if exact_inputs() {
            None
        } else {
            self.journal
                .as_ref()
                .and_then(|journal| journal.with_namespaces(candidates))
                .or_else(|| {
                    dm_host::journal::JournalProof::establish_namespaces(&self.files, candidates)
                })
        };
        self.namespace_covered = self.journal.is_some() && !candidates.is_empty();
        self.namespace_digest = self.journal.as_ref().map(|_| digest);
        if std::env::var_os("DM_BUILD_TRACE").is_some() {
            eprintln!(
                "DM_BUILD_TRACE input journal proof: {} files, enabled {}",
                self.files.len(),
                self.journal.is_some()
            );
        }
    }
}

pub(super) fn exact_inputs() -> bool {
    std::env::var("DM_BUILD_EXACT_INPUTS").is_ok_and(|value| value != "0")
}

#[cfg(test)]
mod tests {
    use super::*;
    #[cfg(windows)]
    #[test]
    fn journal_subset_ignores_source_edits_and_detects_asset_edits() {
        let dir = std::env::temp_dir().join(format!(
            "dm-proof-subset-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&dir).unwrap();
        let source = dir.join("source.dm");
        let asset = dir.join("asset.dmi");
        fs::write(&source, "before").unwrap();
        fs::write(&asset, "before").unwrap();
        let mut all = InputProof::capture([source.clone(), asset.clone()]).unwrap();
        all.enable_journal();
        let assets = all.subset([asset.clone()]).unwrap();
        assert!(assets.current());
        if all.journal.is_some() {
            assert!(
                assets.journal.is_some(),
                "subset must inherit the already validated journal baseline"
            );
        }
        fs::write(&source, "edited").unwrap();
        assert!(!all.current());
        assert!(
            assets.current(),
            "source-only journal changes must not invalidate the asset subset"
        );
        fs::write(&asset, "edited").unwrap();
        assert!(!assets.current());
        fs::remove_dir_all(dir).unwrap();
    }
    use std::fs;
    use std::time::SystemTime;
    #[cfg(windows)]
    #[test]
    fn namespace_proof_detects_new_resolution_candidates() {
        let dir = std::env::temp_dir().join(format!(
            "dm-proof-namespace-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&dir).unwrap();
        let source = dir.join("source.dm");
        let missing = dir.join("shadow.dmi");
        fs::write(&source, "before").unwrap();
        let mut proof = InputProof::capture([source]).unwrap();
        proof.enable_namespace_journal(&[missing.clone()]);
        if proof.namespace_current() == Some(true) {
            fs::write(&missing, "shadow").unwrap();
            assert_eq!(proof.namespace_current(), Some(false));
        }
        fs::remove_dir_all(dir).unwrap();
    }

    #[cfg(windows)]
    #[test]
    fn namespace_proof_rejects_renames_from_a_writer_predating_baseline() {
        use std::{io::Write, os::windows::fs::OpenOptionsExt};
        let dir = std::env::temp_dir().join(format!(
            "dm-proof-held-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(dir.join("other")).unwrap();
        let source = dir.join("source.dm");
        fs::write(&source, "source").unwrap();
        for cross_parent in [false, true] {
            let first = dir.join("first.dmi");
            let renamed = dir.join("renamed.dmi");
            let candidate = if cross_parent {
                dir.join("other/shadow.dmi")
            } else {
                dir.join("shadow.dmi")
            };
            let mut writer = fs::OpenOptions::new()
                .read(true)
                .write(true)
                .create_new(true)
                .share_mode(7)
                .open(&first)
                .unwrap();
            writer.write_all(b"asset").unwrap();
            fs::rename(&first, &renamed).unwrap();
            let mut proof = InputProof::capture([source.clone()]).unwrap();
            proof.enable_namespace_journal(&[candidate.clone()]);
            let enabled = proof.namespace_current() == Some(true);
            fs::rename(&renamed, &candidate).unwrap();
            if enabled {
                assert_eq!(
                    proof.namespace_current(),
                    Some(false),
                    "held writer rename, cross_parent={cross_parent}"
                );
            }
            drop(writer);
            fs::remove_file(candidate).unwrap();
        }
        fs::remove_dir_all(dir).unwrap();
    }

    #[cfg(windows)]
    #[test]
    fn refresh_reuses_unchanged_barriers_and_checks_only_dirty_files() {
        let root = std::env::temp_dir().join(format!(
            "dm-proof-refresh-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&root).unwrap();
        let dirty = root.join("dirty.dm");
        let unchanged = root.join("unchanged.dm");
        fs::write(&dirty, "before").unwrap();
        fs::write(&unchanged, "before").unwrap();
        let mut previous = InputProof::capture([dirty.clone(), unchanged.clone()]).unwrap();
        let missing = root.join("missing.resource");
        previous.enable_namespace_journal(&[missing.clone()]);
        if previous.journal.is_some() {
            let reader = fs::File::open(&unchanged).unwrap();
            fs::write(&dirty, "after!").unwrap();
            let mut stamps = previous.files.clone();
            stamps.insert(dirty.clone(), capture(&dirty).unwrap());
            let mut refreshed = InputProof::from_stamps(stamps);
            refreshed.inherit_unchanged(&previous);
            assert!(
                refreshed.journal.is_some(),
                "unchanged reader must not force all sharing barriers to be reopened"
            );
            assert!(refreshed.current());
            let namespace_digest = previous.namespace_digest.clone();
            refreshed.enable_namespace_journal(&[missing.clone()]);
            assert_eq!(refreshed.namespace_digest, namespace_digest);
            assert_eq!(refreshed.namespace_current(), Some(true));
            fs::write(&missing, "new shadow").unwrap();
            assert_eq!(refreshed.namespace_current(), Some(false));
            fs::write(&unchanged, "edited").unwrap();
            assert!(
                !refreshed.current(),
                "new write after old sharing barrier must still invalidate"
            );
            drop(reader);
        }
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn combining_proofs_rejects_conflicting_observations_of_one_file() {
        let dir = std::env::temp_dir().join(format!(
            "dm-proof-conflict-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("source");
        fs::write(&path, "before").unwrap();
        let before = InputProof::capture([path.clone()]).unwrap();
        assert!(before.clone().combined(&before).is_some());
        fs::write(&path, "edited").unwrap();
        let after = InputProof::capture([path]).unwrap();
        assert!(before.combined(&after).is_none());
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn preserved_mtime_and_atomic_replacement_invalidate() {
        let dir = std::env::temp_dir().join(format!(
            "dm-proof-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("source");
        fs::write(&path, "before").unwrap();
        let time = fs::metadata(&path).unwrap().modified().unwrap();
        let proof = InputProof::capture([path.clone()]).unwrap();
        assert!(proof.current());
        fs::write(&path, "edited").unwrap();
        fs::File::options()
            .write(true)
            .open(&path)
            .unwrap()
            .set_times(fs::FileTimes::new().set_modified(time))
            .unwrap();
        assert!(!proof.current());
        let proof = InputProof::capture([path.clone()]).unwrap();
        fs::remove_file(&path).unwrap();
        fs::write(&path, "edited").unwrap();
        fs::File::options()
            .write(true)
            .open(&path)
            .unwrap()
            .set_times(fs::FileTimes::new().set_modified(time))
            .unwrap();
        assert!(!proof.current());
        fs::remove_dir_all(dir).unwrap();
    }
}
