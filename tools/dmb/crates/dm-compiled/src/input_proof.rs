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
    /// None means the journal covers every file (legacy serialized proofs).
    #[serde(default)]
    journal_files: Option<std::collections::BTreeSet<PathBuf>>,
}

impl InputProof {
    pub(super) fn from_stamps(files: BTreeMap<PathBuf, FileStamp>) -> Self {
        Self {
            files,
            journal: None,
            namespace_covered: false,
            namespace_digest: None,
            journal_files: None,
        }
    }
    pub(super) fn capture(paths: impl IntoIterator<Item = PathBuf>) -> Option<Self> {
        if exact_inputs() {
            return None;
        }
        let paths: Vec<_> = paths
            .into_iter()
            .collect::<std::collections::BTreeSet<_>>()
            .into_iter()
            .collect();
        let files = dm_work::map_ordered(
            &paths,
            dm_work::WorkLimits::configured(),
            |_| 1024,
            |path| capture(path).map(|value| (path.clone(), value)),
        )
        .ok()?
        .into_iter()
        .collect::<Option<BTreeMap<_, _>>>()?;
        Some(Self {
            files,
            journal: None,
            namespace_covered: false,
            namespace_digest: None,
            journal_files: None,
        })
    }

    pub(super) fn current(&self) -> bool {
        let started=std::time::Instant::now();
        if exact_inputs() {return false;}
        let mut covered=false;let mut journal_status="absent";
        if let Some(journal)=&self.journal {
            match journal.validate() {
                dm_host::journal::Validation::Current=>{covered=true;journal_status="current";},
                dm_host::journal::Validation::Changed=>{self.trace_validation("changed",0,started,false);return false;},
                dm_host::journal::Validation::Unavailable=>{journal_status="unavailable";},
            }
        }
        let files:Vec<_>=self.files.iter().filter(|(path,_)|!covered || self.journal_files.as_ref().is_some_and(|files|!files.contains(*path))).collect();
        let current=(covered || !self.files.is_empty()) && dm_work::map_ordered(&files,dm_work::WorkLimits::configured(),|_|1024,
            |(path,expected)|capture(path).as_ref()==Some(*expected)).is_ok_and(|results|results.into_iter().all(|current|current));
        self.trace_validation(journal_status,files.len(),started,current);current
    }
    fn trace_validation(&self,journal:&str,stamps:usize,started:std::time::Instant,current:bool) {
        if std::env::var_os("DM_BUILD_TRACE").is_some() {
            eprintln!("DM_BUILD_TRACE input proof validate: {} files, journal {journal}, {stamps} stamp observations, current {current}, {:.3}s",self.files.len(),started.elapsed().as_secs_f64());
        }
    }

    /// Reuse one preparation observation only when it proves the exact same
    /// expected objects/change clocks. Publication still observes independently.
    pub(super) fn validated_by(
        &self,
        observed: &Self,
        unchanged: &std::collections::BTreeSet<PathBuf>,
    ) -> bool {
        !exact_inputs()
            && !self.files.is_empty()
            && self.files.iter().all(|(path, stamp)| {
                unchanged.contains(path) && observed.files.get(path) == Some(stamp)
            })
    }

    pub(super) fn resident_bytes(&self) -> usize {
        self.files
            .keys()
            .map(|path| path.as_os_str().len() * 2 + 128)
            .sum::<usize>()
            + self.journal_files.as_ref().map_or(0,|files|files.iter().map(|path|path.as_os_str().len()*2+48).sum::<usize>())
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
        let journal_files=self.journal_files.as_ref().map(|covered|files.keys().filter(|path|covered.contains(*path)).cloned().collect());
        Some(Self {
            files,
            journal,
            namespace_covered: self.namespace_covered,
            namespace_digest: self.namespace_digest.clone(),
            journal_files,
        })
    }

    pub(super) fn combined(mut self, other: &Self) -> Option<Self> {
        let left_coverage=self.journal_files.clone().unwrap_or_else(||self.files.keys().cloned().collect());
        let right_coverage=other.journal_files.clone().unwrap_or_else(||other.files.keys().cloned().collect());
        let merged=self.journal.as_ref().zip(other.journal.as_ref()).and_then(|(left,right)|left.merged(right));
        // Namespace identity belongs to the journal selected below, never to
        // an unrelated side of a failed merge. File-only proofs contribute no
        // namespace identity; legacy empty-candidate hashes are normalized out.
        let left_namespace=self.retained_namespace_digest();
        let right_namespace=other.retained_namespace_digest();
        let (journal,coverage,namespace)=if let Some(merged)=merged {
            let mut coverage=left_coverage;coverage.extend(right_coverage);
            (Some(merged),Some(coverage),left_namespace.or(right_namespace))
        } else if let Some(left)=&self.journal {(Some(left.clone()),Some(left_coverage),left_namespace)}
        else if let Some(right)=&other.journal {(Some(right.clone()),Some(right_coverage),right_namespace)}
        else {(None,None,None)};
        self.namespace_covered=namespace.is_some();
        self.namespace_digest=namespace;
        self.journal = journal;
        self.journal_files=coverage;
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
        if self.journal_files.as_ref().is_some_and(|covered|self.files.keys().any(|path|!covered.contains(path))) {self.namespace_covered=false;}
        Some(self)
    }

    pub(super) fn inherit_unchanged(&mut self, previous: &Self) {
        if exact_inputs() {
            return;
        }
        let covered: BTreeMap<_,_>=previous.files.iter().filter(|(path,_)|previous.journal_files.as_ref().map_or(true,|files|files.contains(*path))).map(|(path,stamp)|(path.clone(),stamp.clone())).collect();
        self.journal = previous.journal.as_ref().and_then(|journal|journal.refreshed(&covered,&self.files));
        self.journal_files=None;
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
        let started=std::time::Instant::now();
        let covered:BTreeMap<_,_>=self.files.iter().filter(|(path,_)|self.journal_files.as_ref().map_or(true,|files|files.contains(*path))).map(|(path,stamp)|(path.clone(),stamp.clone())).collect();
        let journal_paths=if exact_inputs(){None}else{self.journal.as_ref().and_then(|journal|journal.unchanged_paths(&covered))};
        let files:Vec<_>=self.files.iter().filter(|(path,_)|journal_paths.as_ref().map_or(true,|_|!covered.contains_key(*path))).collect();
        let mut paths=journal_paths.unwrap_or_default();
        if let Ok(observed)=dm_work::map_ordered(&files,dm_work::WorkLimits::configured(),|_|1024,
            |(path,stamp)|(capture(path).as_ref()==Some(*stamp)).then(||(*path).clone())) {
            paths.extend(observed.into_iter().flatten());
        }
        self.trace_validation("unchanged-paths",files.len(),started,paths.len()==self.files.len());paths
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
        let eligible=!candidates.is_empty() && !exact_inputs();
        let covered=self.journal_files.as_ref().map_or(true,|covered|self.files.keys().all(|path|covered.contains(path)));
        let same_namespace=eligible && self.namespace_digest.as_ref()==Some(&Self::namespace_digest(candidates));
        let observed=eligible && covered && same_namespace;
        let current=observed && self.journal.as_ref().is_some_and(|journal|journal.current());
        if current {
            self.namespace_covered = true;
            true
        } else {
            if std::env::var_os("DM_BUILD_TRACE").is_some() {
                eprintln!("DM_BUILD_TRACE namespace reuse miss: files={} candidates={} eligible={eligible} file_coverage={covered} retained_namespace={} same_namespace={same_namespace} journal_present={} journal_observed={observed}",
                    self.files.len(),candidates.len(),self.namespace_digest.is_some(),self.journal.is_some());
            }
            false
        }
    }
    fn retained_namespace_digest(&self)->Option<String> {
        self.journal.as_ref()?;
        self.namespace_digest.as_ref().filter(|digest|**digest!=Self::namespace_digest(&[])).cloned()
    }

    pub(super) fn enable_namespace_journal(&mut self, candidates: &[PathBuf]) {
        if candidates.is_empty() {
            if exact_inputs() {
                self.journal=None;self.journal_files=None;self.namespace_digest=None;self.namespace_covered=false;
                return;
            }
            let coverage=self.journal_files.as_ref().map_or(true,|covered|self.files.keys().all(|path|covered.contains(path)));
            let retained=self.journal.as_ref().filter(|_|coverage).filter(|journal|journal.current()).cloned();
            let namespace=retained.as_ref().and_then(|_|self.retained_namespace_digest());
            self.journal=retained.or_else(||dm_host::journal::JournalProof::establish(&self.files));
            self.journal_files=None;
            self.namespace_digest=self.journal.as_ref().and(namespace);
            self.namespace_covered=self.namespace_digest.is_some();
            if std::env::var_os("DM_BUILD_TRACE").is_some() {eprintln!("DM_BUILD_TRACE input journal proof: {} files, enabled {}, retained namespace {}",self.files.len(),self.journal.is_some(),self.namespace_covered);}
            return;
        }
        let digest = Self::namespace_digest(candidates);
        if self.reuse_namespace(candidates) {
            return;
        }
        self.journal = if exact_inputs() {
            None
        } else {
            self.journal
                .as_ref()
                .filter(|_|self.journal_files.as_ref().map_or(true,|covered|self.files.keys().all(|path|covered.contains(path))))
                .and_then(|journal| journal.with_namespaces(candidates))
                .or_else(|| {
                    dm_host::journal::JournalProof::establish_namespaces(&self.files, candidates)
                })
        };
        self.journal_files=None;
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
