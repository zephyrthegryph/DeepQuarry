//! Parallel candidate capture with the same ordered search and observation ledger.
use super::*;
#[cfg(test)]
use crate::SharedBytes;
use std::sync::Mutex;

/// Read and hash only demanded candidates. Each search wave visits one FILE_DIR
/// level for aliases still unresolved; a successful candidate stops its search.
/// The ordinary capture walk then emits observations and errors in authored order.
pub fn capture_discovered_on_executor<P: CaptureProvider + Sync>(
    demand: ResourceDemand,
    config: CaptureConfig<'_>,
    provider: &P,
    executor: &dm_exec::BuildExecutor,
) -> Result<CapturedResources, CaptureError> {
    validate_demand(&demand, config)?;
    let mut aliases = Vec::new();
    let mut seen = BTreeSet::new();
    for literal in &demand.literals {
        if seen.insert(literal.path.as_str()) {
            let alias = literal.path.replace('\\', "/");
            // Leave admission errors to the ordered walk: do not read an invalid
            // alias or let another worker's error replace its diagnostic.
            if crate::validate_archive_name(&alias).is_err() {
                break;
            }
            aliases.push(alias);
        }
    }
    let mut files = HashMap::new();
    let mut failures = HashMap::new();
    let mut unresolved = vec![true; aliases.len()];
    for directory in demand.search_roots() {
        let paths = aliases
            .iter()
            .zip(&unresolved)
            .filter(|(_, active)| **active)
            .map(|(alias, _)| normalize(&directory.join(alias)))
            .collect::<BTreeSet<_>>();
        capture_wave(paths, provider, executor, &mut files, &mut failures)?;
        for (alias, active) in aliases.iter().zip(&mut unresolved) {
            let path = normalize(&directory.join(alias));
            if *active
                && (failures.contains_key(&path)
                    || files
                        .get(&path)
                        .is_some_and(|candidate| candidate.bytes.is_some()))
            {
                *active = false;
            }
        }
    }
    let additional = config
        .additional
        .iter()
        .filter(|request| crate::validate_archive_name(&request.archive_name).is_ok())
        .map(|request| normalize(&request.disk_path))
        .collect();
    capture_wave(additional, provider, executor, &mut files, &mut failures)?;
    capture_seeded(demand, config, provider, files, failures)
}

fn capture_wave<P: CaptureProvider + Sync>(
    paths: BTreeSet<PathBuf>,
    provider: &P,
    executor: &dm_exec::BuildExecutor,
    files: &mut HashMap<PathBuf, CapturedCandidate>,
    failures: &mut HashMap<PathBuf, CaptureError>,
) -> Result<(), CaptureError> {
    let paths = paths
        .into_iter()
        .filter(|path| !files.contains_key(path) && !failures.contains_key(path))
        .collect::<Vec<_>>();
    if paths.is_empty() {
        return Ok(());
    }
    let slots = (0..paths.len())
        .map(|_| Mutex::new(None))
        .collect::<Vec<_>>();
    let chunk_size = paths.len().div_ceil(executor.workers());
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        executor.scope(|scope| {
            for (paths, slots) in paths.chunks(chunk_size).zip(slots.chunks(chunk_size)) {
                scope.spawn(move |_| {
                    let _profile = dm_profile::stage("resources.candidate_capture");
                    for (path, slot) in paths.iter().zip(slots) {
                        let candidate = provider
                            .read_candidate(path)
                            .map(|bytes| CapturedCandidate {
                                digest: bytes.as_ref().map(|bytes| bytes.sha256()),
                                bytes,
                            })
                            .map_err(|source| CaptureError::Io {
                                path: path.clone(),
                                source,
                            });
                        *slot.lock().unwrap_or_else(|error| error.into_inner()) = Some(candidate);
                    }
                });
            }
        });
    }));
    if result.is_err() {
        return Err(CaptureError::Invalid(
            "resource capture worker panicked".into(),
        ));
    }
    for (path, slot) in paths.into_iter().zip(slots) {
        match slot
            .into_inner()
            .unwrap_or_else(|error| error.into_inner())
            .ok_or_else(|| {
                CaptureError::Invalid("resource capture worker omitted candidate".into())
            })? {
            Ok(candidate) => {
                files.insert(path, candidate);
            }
            Err(error) => {
                failures.insert(path, error);
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Memory {
        files: HashMap<PathBuf, SharedBytes>,
        reads: Mutex<Vec<PathBuf>>,
        denied: BTreeSet<PathBuf>,
    }
    impl CaptureProvider for Memory {
        fn read_candidate(&self, path: &Path) -> io::Result<Option<SharedBytes>> {
            self.reads.lock().unwrap().push(path.to_owned());
            if self.denied.contains(path) {
                return Err(io::Error::new(io::ErrorKind::PermissionDenied, "denied"));
            }
            Ok(self.files.get(path).cloned())
        }
    }
    fn demand() -> ResourceDemand {
        let plan = DirectivePlan {
            project_dir: PathBuf::from("game"),
            file_dirs: vec!["early".into(), "late".into()],
            ..Default::default()
        };
        let expanded = ExpandedRegions {
            text: "'a.txt' 'b.txt' 'a.txt' 'missing.txt'".into(),
            ..Default::default()
        };
        discover_demand(&plan, &expanded, &[], &[]).unwrap()
    }
    fn memory() -> Memory {
        Memory {
            files: HashMap::from([
                (
                    PathBuf::from("game/a.txt"),
                    SharedBytes::from(b"a".as_slice()),
                ),
                (
                    PathBuf::from("game/late/b.txt"),
                    SharedBytes::from(b"b".as_slice()),
                ),
            ]),
            reads: Mutex::new(Vec::new()),
            denied: BTreeSet::new(),
        }
    }
    #[test]
    fn parallel_capture_matches_order_and_never_reads_past_success() {
        let policy = CapturePolicy {
            certified_raw_extensions: BTreeSet::from(["txt".into()]),
        };
        let config = CaptureConfig {
            policy: &policy,
            encoded: &[],
            additional: &[],
        };
        let serial = capture_discovered(demand(), config, &memory()).unwrap();
        for workers in [1, 2, 8] {
            let provider = memory();
            let pool = dm_exec::BuildExecutor::new(workers).unwrap();
            let parallel =
                capture_discovered_on_executor(demand(), config, &provider, &pool).unwrap();
            assert_eq!(serial.observations, parallel.observations);
            assert_eq!(serial.resources.fingerprint, parallel.resources.fingerprint);
            assert_eq!(serial.lookups, parallel.lookups);
            let reads = provider.reads.lock().unwrap();
            assert_eq!(reads.len(), reads.iter().collect::<BTreeSet<_>>().len());
            assert!(!reads.contains(&PathBuf::from("game/late/a.txt")));
            assert!(!reads.contains(&PathBuf::from("game/early/b.txt")));
        }
    }
    #[test]
    fn parallel_failure_preserves_authored_error_order() {
        let mut provider = memory();
        provider.files.clear();
        provider.denied = BTreeSet::from(["game/late/a.txt".into(), "game/b.txt".into()]);
        let policy = CapturePolicy::default();
        let config = CaptureConfig {
            policy: &policy,
            encoded: &[],
            additional: &[],
        };
        let pool = dm_exec::BuildExecutor::new(2).unwrap();
        let error = capture_discovered_on_executor(demand(), config, &provider, &pool)
            .err()
            .unwrap();
        assert!(
            matches!(error, CaptureError::Io { path, .. } if path == Path::new("game/late/a.txt"))
        );
    }
}
