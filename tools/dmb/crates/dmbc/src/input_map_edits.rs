//! Private strict-domain MapEdits source feed. This is a recording operation,
//! not a finished report or a claim of legacy parity outside this domain.
use super::*;
use dq_analyze::{
    captured_allow_annotations::Operation, captured_generator_budget::Budget,
    key_policy_control as kc, map_edits_policy,
};
use std::sync::Arc;

#[path = "input_paired_dmm.rs"]
mod paired;
pub(crate) use paired::{PairedDmmFacts, PairedDmmStage};

const MAX_NESTING: usize = 256;

fn unsupported(message: &'static str) -> io::Error {
    io::Error::new(io::ErrorKind::Unsupported, message)
}

fn map_failure(failure: dq_analyze::captured_reactive_reads::Failure) -> io::Error {
    match failure {
        dq_analyze::captured_reactive_reads::Failure::Operational(error) => error,
        dq_analyze::captured_reactive_reads::Failure::Unsupported(message) =>
            io::Error::new(io::ErrorKind::Unsupported, message),
    }
}

fn quota(message: String) -> io::Error {
    io::Error::new(io::ErrorKind::OutOfMemory, message)
}

fn path_charge(path: &Path, multiplier: usize, overhead: usize) -> io::Result<usize> {
    path.as_os_str().len().checked_mul(multiplier)
        .and_then(|bytes| bytes.checked_add(overhead))
        .ok_or_else(|| io::ErrorKind::OutOfMemory.into())
}

fn collect<P: SnapshotProvider>(
    inputs: &RecordingInputs<P>, folder: &Path, depth: usize, budget: &Arc<Budget>,
    scratch: &Arc<Budget>, lender: &mut dyn RecordedPolicySourceLender, paths: &mut Vec<PathBuf>, directories: &mut Vec<PathBuf>,
    joined: Option<&crate::runner_host::workspace_discovery::DiscoveryReceipt>,
) -> io::Result<()> {
    crate::daemon::control::checkpoint()?;
    if depth == MAX_NESTING {
        return Err(unsupported("MapEdits directory nesting or alias cycle exceeds its bounded domain"));
    }
    // One exact lexical folder observation. Child classification is the
    // existing no-follow typed provider contract. Never silently skip an
    // observation where legacy would have examined a link's target.
    let acquired;
    let listing = if let Some(discovery) = joined {
        discovery.joined_map_directory(folder)?
    } else {
        acquired = inputs.capture_policy_directory_lent(folder, false, 0, budget, lender)?;
        &acquired
    };
    if joined.is_none() {
        let mut work = Operation { budget: scratch, poll: &crate::daemon::control::checkpoint };
        kc::row(&mut work, directories).map_err(map_failure)?;
        scratch.charge(path_charge(folder, 4, 256)?).map_err(quota)?;
        directories.push(folder.to_path_buf());
    }
    let entries = match listing {
        PolicyDirectoryListing::Missing if depth == 0 => return Ok(()),
        PolicyDirectoryListing::Present(entries) => entries,
        _ => return Err(unsupported("MapEdits requires a stable ordinary directory")),
    };
    for entry in entries.iter() {
        crate::daemon::control::checkpoint()?;
        let child = Path::new(&entry.name);
        let is_map = child.extension().is_some_and(|extension| extension == "dmm");
        if matches!(entry.kind, PolicyEntryKind::Symlink | PolicyEntryKind::Other) {
            return Err(unsupported("MapEdits cannot prove the legacy outcome of a link or special entry"));
        }
        if !matches!(entry.kind, PolicyEntryKind::Directory) && !is_map {
            continue;
        }
        let temporary = Budget::scoped_temporaries(budget).map_err(quota)?;
        temporary.charge(path_charge(folder, 4, entry.name.len().checked_mul(4)
            .and_then(|bytes| bytes.checked_add(512)).ok_or(io::ErrorKind::OutOfMemory)?)?).map_err(quota)?;
        let path = folder.join(child);
        if entry.kind == PolicyEntryKind::Directory {
            collect(inputs, &path, depth + 1, budget, scratch, lender, paths, directories, joined)?;
        } else {
            // Move the same allocation into the candidate roster; retain
            // funding after the iteration's temporary slot is dropped.
            scratch.charge(path_charge(&path, 4, 256)?).map_err(quota)?;
            let mut work = Operation { budget: scratch, poll: &crate::daemon::control::checkpoint };
            kc::row(&mut work, paths).map_err(map_failure)?;
            paths.push(path);
        }
    }
    Ok(())
}

impl<P: SnapshotProvider> RecordingInputs<P> {
    /// Fold bounded, original DMM payloads in legacy lexical PathBuf order.
    /// All folder/file facts go to this recorder. The caller must stage any
    /// output, then successfully admit this same recording before publication.
    /// Map observations grant no compiled-source membership.
    pub(crate) fn fold_regular_map_edits_inputs(
        &self, root: &Path, budget: &Arc<Budget>, lender: &mut dyn RecordedPolicySourceLender,
        mut visit: impl FnMut(&Path, &str, &[u8]) -> io::Result<()>,
    ) -> io::Result<Vec<PathBuf>> {
        self.fold_map_edits_using(root, budget, lender, None, |path, relative, bytes| {
            visit(path, relative, bytes.expect("standalone MapEdits reads the actual payload"))
        })
    }

    pub(crate) fn fold_observed_map_edits_inputs(
        &self, discovery: &crate::runner_host::workspace_discovery::DiscoveryReceipt,
        budget: &Arc<Budget>, lender: &mut dyn RecordedPolicySourceLender,
        mut visit: impl FnMut(&Path, &str) -> io::Result<()>,
    ) -> io::Result<()> {
        discovery.validate_recording(self)?;
        // Each joined directory must be found in this exact discovery.
        // Its typed path is already part of the workspace closure roster.
        self.fold_map_edits_using(&discovery.contract().root, budget, lender, Some(discovery),
            |path, relative, _| visit(path, relative)).map(|_| ())
    }

    fn fold_map_edits_using(
        &self, root: &Path, budget: &Arc<Budget>, lender: &mut dyn RecordedPolicySourceLender,
        joined: Option<&crate::runner_host::workspace_discovery::DiscoveryReceipt>,
        mut visit: impl FnMut(&Path, &str, Option<&[u8]>) -> io::Result<()>,
    ) -> io::Result<Vec<PathBuf>> {
        if !root.is_absolute() || canonical_path(root) != root
            || self.initial_environment != dm_preprocess::InitialEnvironment::OriginalChecker0290 {
            return Err(invalid("MapEdits requires the fixed actual Original workspace root"));
        }
        let scratch = Budget::scoped_temporaries(budget).map_err(quota)?;
        scratch.charge(path_charge(root, 4, 512)?).map_err(quota)?;
        let mut paths = Vec::new();
        let mut directories = Vec::new();
        // Directory names cross the temporary path scope and feed the
        // enclosing policy closure; fund them for the rest of this operation.
        collect(self, &root.join("maps"), 0, budget, budget, lender, &mut paths, &mut directories, joined)?;
        let pending = (|| -> io::Result<()> {
            paths.sort_unstable();
            for path in paths {
                crate::daemon::control::checkpoint()?;
                let bytes_scope = Budget::scoped_temporaries(budget).map_err(quota)?;
                bytes_scope.charge(path_charge(&path, 4, 512)?).map_err(quota)?;
                let relative = path.strip_prefix(root).map_err(io::Error::other)?;
                let relative = relative.to_string_lossy().replace('\\', "/");
                if map_edits_policy::skips_map(&relative) {
                    continue;
                }
                if joined.is_some() {
                    visit(&path, &relative, None)?;
                    continue;
                }
                // Fund the recorder nodes before the existing admitted read. The
                // bounded reader authenticates the same handle and lexical path.
                budget.charge(path_charge(&path, 32, 8192)?).map_err(quota)?;
                let payload = self.read_policy_payload_admitted(&path, budget.remaining(), &mut |bytes| {
                    bytes_scope.charge(bytes).map_err(quota)
                })?.ok_or_else(|| io::Error::new(io::ErrorKind::Interrupted,
                    "discovered MapEdits input disappeared before its bounded read"))?;
                visit(&path, &relative, Some(&payload))?;
            }
            crate::daemon::control::checkpoint()?;
            Ok(())
        })();
        // The joined fold borrows already-observed directories and bytes. It
        // neither opens a recorder directory window nor changes its metadata.
        // Settle only the ordinary fold, which used the lent directory reader.
        let settled = if joined.is_none() {
            self.snapshot.lock()
                .map_err(|_| invalid("map_edits capture mutex poisoned"))
                .and_then(|snapshot| snapshot.policy_closure_charge())
                .and_then(|bytes| lender.directory_metadata_settled(&self.policy_metadata_owner(None)?, bytes))
        } else {
            Ok(())
        };
        pending?;
        settled?;
        Ok(directories)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Lender;
    impl RecordedPolicySourceLender for Lender {
        fn prepare_source(&mut self) -> io::Result<()> { unreachable!() }
        fn acquired(&mut self, _: &dm_preprocess::SourceAcquisitionLease) -> io::Result<()> { unreachable!() }
        fn prepare_directory_metadata(&mut self, _: &Arc<()>, _: usize) -> io::Result<()> { Ok(()) }
        fn directory_window_started(&mut self, _: &Arc<()>, _: usize) -> io::Result<()> { Ok(()) }
        fn directory_metadata_settled(&mut self, _: &Arc<()>, _: usize) -> io::Result<()> { Ok(()) }
    }

    fn actual() -> RecordingInputs {
        RecordingInputs::new(FileSystemInputs, 0)
            .with_initial_environment(dm_preprocess::InitialEnvironment::OriginalChecker0290)
    }

    // Independently keep the old filesystem sequence for this comparison.
    fn legacy_candidates(root: &Path, output: &mut Vec<PathBuf>) {
        let Ok(entries) = std::fs::read_dir(root) else { return };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                legacy_candidates(&path, output);
            } else if path.extension().is_some_and(|extension| extension == "dmm") {
                output.push(path);
            }
        }
    }

    #[test]
    fn original_map_edits_regular_feed_matches_legacy_order_and_original_bytes() {
        let root = crate::test_scratch::dir("map-edits-original-regular");
        let fixtures: [(&str, &[u8]); 6] = [
            ("maps/.hidden/input.dmm", b"\xff/obj/probe{line = 0}\r\n"),
            ("maps/a.dmm/z.dmm", b"/obj/probe{first = 1}\r/obj/probe{second = 2}\n"),
            ("maps/Z.dmm", b"/obj/probe{last = 3}\n"),
            ("maps/upper.DMM", b"wrong case"),
            ("maps/palettes/ignore.dmm", b"excluded prefix"),
            ("maps/SouthernCrossRef.dmm", b"excluded suffix"),
        ];
        for (path, bytes) in fixtures {
            let path = root.join(path);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(path, bytes).unwrap();
        }
        let mut paths = Vec::new();
        legacy_candidates(&root.join("maps"), &mut paths);
        paths.sort();
        let expected: Vec<_> = paths.into_iter().filter_map(|path| {
            let relative = path.strip_prefix(&root).unwrap().to_string_lossy().replace('\\', "/");
            if relative.starts_with("maps/palettes/") || relative.ends_with("SouthernCrossRef.dmm") {
                return None;
            }
            std::fs::read(path).ok().map(|bytes| (relative, bytes))
        }).collect();
        let inputs = actual();
        let budget = Budget::new(16 * 1024 * 1024).unwrap();
        let mut observed = Vec::new();
        inputs.fold_regular_map_edits_inputs(&root, &budget, &mut Lender, |_, relative, payload| {
            observed.push((relative.to_owned(), payload.to_vec()));
            Ok(())
        }).unwrap();
        assert_eq!(expected.len(), 3);
        assert_eq!(observed, expected);
        assert!(inputs.recorded_file_fact(&root.join("maps/.hidden/input.dmm")).is_ok());
        assert!(inputs.recorded_file_fact(&root.join("maps/palettes/ignore.dmm")).is_err());
        let proof = inputs.snapshot().unwrap();
        assert!(proof.validate(&FileSystemInputs, true, 1).unwrap().0.unchanged());
        std::fs::write(root.join("maps/a.dmm/new.dmm"), b"new map").unwrap();
        assert!(!proof.validate(&FileSystemInputs, true, 2).unwrap().0.unchanged());
    }

    #[test]
    fn original_map_edits_regular_feed_records_missing_root_for_freshness() {
        let root = crate::test_scratch::dir("map-edits-original-missing");
        let inputs = actual();
        let budget = Budget::new(16 * 1024 * 1024).unwrap();
        inputs.fold_regular_map_edits_inputs(&root, &budget, &mut Lender, |_, _, _| {
            panic!("missing maps root cannot yield an input")
        }).unwrap();
        let proof = inputs.snapshot().unwrap();
        assert!(proof.validate(&FileSystemInputs, true, 1).unwrap().0.unchanged());
        std::fs::create_dir(root.join("maps")).unwrap();
        assert!(!proof.validate(&FileSystemInputs, true, 2).unwrap().0.unchanged());
    }

    #[cfg(unix)]
    #[test]
    fn original_map_edits_regular_feed_refuses_lexical_alias_without_partial_fold() {
        let root = crate::test_scratch::dir("map-edits-original-alias");
        std::fs::create_dir_all(root.join("maps")).unwrap();
        std::fs::write(root.join("maps/actual.dmm"), b"body").unwrap();
        std::os::unix::fs::symlink("actual.dmm", root.join("maps/alias.dmm")).unwrap();
        let budget = Budget::new(16 * 1024 * 1024).unwrap();
        let error = actual().fold_regular_map_edits_inputs(&root, &budget, &mut Lender, |_, _, _| {
            panic!("alias refusal must not begin folding map files")
        }).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::Unsupported);
    }
}
