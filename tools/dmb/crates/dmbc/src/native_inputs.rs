//! Optional one-request lexical prefetch for direct literal manifest includes.
//! The ordered frontend still decides which inputs exist semantically. Keep this
//! owner/provider in the frontend capture scope; do not retain unused candidates
//! through lowering or publication.
use dm_preprocess::regions::{
    canonical_path,
    prepared_source::{
        literal_include_path, PreparedSource, PreparedSourceProvider, PreparedSources,
    },
};
use dm_preprocess::{SourcePreparationDemand, SourceProvider};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct PreparationStats {
    pub candidates: usize,
    pub prepared: usize,
    /// Omitted candidates use the ordinary provider if later actually required.
    pub deferred: usize,
    pub workers: usize,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum NativeInputError {
    RequiredSourceRead { path: PathBuf, message: String },
    InternalPreparation { message: String },
}

pub struct NativeInputs {
    sources: PreparedSources,
    stats: PreparationStats,
}
fn prepare_source<P: SourceProvider>(
    provider: &P,
    path: &Path,
) -> Result<Arc<PreparedSource>, String> {
    prepare_source_using(provider, path, provider.prepared_source(path), SourcePreparationDemand::Lexical)
}

fn prepare_source_using<P: SourceProvider>(
    provider: &P,
    path: &Path,
    candidate: Option<Arc<PreparedSource>>,
    demand: SourcePreparationDemand,
) -> Result<Arc<PreparedSource>, String> {
    if let Some(prepared) = candidate {
        return Ok(prepared);
    }
    let text = {
        let _profile = dm_profile::stage("input_scan.source_read");
        provider.read(path)?
    };
    let _profile = dm_profile::stage("input_scan.lexical_prepare");
    Ok(demand.prepare(text.into()))
}

impl NativeInputs {
    /// Capture the required manifest once. Only its direct literal source paths
    /// are offered to the build's worker pool. Conditional state, macro effects,
    /// FILE_DIR and recursive include discovery belong to the ordered frontend.
    pub fn prepare<P: SourceProvider + Sync>(
        project: &Path,
        provider: &P,
        workers: usize,
    ) -> Result<Self, NativeInputError> {
        let executor = dm_exec::BuildExecutor::new(workers).map_err(|error| {
            NativeInputError::InternalPreparation {
                message: error.to_string(),
            }
        })?;
        Self::prepare_with_executor(project, provider, &executor)
    }

    pub fn prepare_with_executor<P: SourceProvider + Sync>(
        project: &Path,
        provider: &P,
        executor: &dm_exec::BuildExecutor,
    ) -> Result<Self, NativeInputError> {
        Self::prepare_with_hints(project, provider, executor, Vec::new())
    }

    /// As [`Self::prepare_with_executor`], also offering `hints` (for example
    /// the previous request's prepared roster) as speculative candidates after
    /// the manifest's literal includes. Hints only warm captures; the ordered
    /// directive pass still decides which files are actually included.
    pub fn prepare_with_hints<P: SourceProvider + Sync>(
        project: &Path,
        provider: &P,
        executor: &dm_exec::BuildExecutor,
        hints: Vec<PathBuf>,
    ) -> Result<Self, NativeInputError> {
        Self::prepare_with_candidates(project, provider, executor, hints, prepare_source)
    }

    pub(crate) fn prepare_selected_original_with_hints<P: crate::input_snapshot::SnapshotProvider + Sync>(
        project: &Path,
        provider: &crate::input_snapshot::RecordingInputs<P>,
        executor: &dm_exec::BuildExecutor,
        hints: Vec<PathBuf>,
    ) -> Result<Self, NativeInputError> {
        if provider.initial_environment() != dm_preprocess::InitialEnvironment::OriginalChecker0290 {
            return Err(NativeInputError::InternalPreparation {
                message: "selected lexical deferral requires the actual Original recorder".into(),
            });
        }
        Self::prepare_with_candidates(project, provider, executor, hints, |provider, path| {
            prepare_source_using(provider, path, provider.selected_original_candidate(path), SourcePreparationDemand::Bytes)
        })
    }

    fn prepare_with_candidates<P: SourceProvider + Sync>(
        project: &Path,
        provider: &P,
        executor: &dm_exec::BuildExecutor,
        hints: Vec<PathBuf>,
        prepare: impl Fn(&P, &Path) -> Result<Arc<PreparedSource>, String> + Sync,
    ) -> Result<Self, NativeInputError> {
        let manifest_timer = dm_profile::detail_timer("inputs.manifest");
        let project = canonical_path(project);
        let manifest = prepare_source(provider, &project).map_err(|message| {
            NativeInputError::RequiredSourceRead {
                path: project.clone(),
                message,
            }
        })?;
        let parent = project.parent().unwrap_or(Path::new(""));
        // Hash, not ordered, membership: hinted rosters are ~11k Windows paths
        // and ordered Path comparison parses components on every compare.
        let mut seen = std::collections::HashSet::from([project.clone()]);
        let mut candidates = manifest
            .lines()
            .iter()
            .filter_map(|line| literal_include_path(line.text))
            .filter(|path| {
                path.extension()
                    .and_then(|value| value.to_str())
                    .is_some_and(|extension| {
                        extension.eq_ignore_ascii_case("dm")
                            || extension.eq_ignore_ascii_case("dme")
                    })
            })
            .map(|path| parent.join(path))
            .chain(hints.into_iter().filter(|path| {
                path.extension()
                    .and_then(|value| value.to_str())
                    .is_some_and(|extension| extension.eq_ignore_ascii_case("dm"))
            }))
            .collect::<Vec<_>>();
        // Resolve filesystem paths on the existing pool. Retaining in manifest
        // order afterwards preserves which alias supplies the first capture.
        drop(manifest_timer);
        let canonical_timer = dm_profile::detail_timer("inputs.canonical_paths");
        let chunk_size = candidates.len().div_ceil(executor.workers()).max(1);
        executor.scope(|scope| {
            for paths in candidates.chunks_mut(chunk_size) {
                scope.spawn(move |_| {
                    let _profile = dm_profile::stage("input_scan.candidate_paths");
                    for path in paths {
                        *path = canonical_path(path);
                    }
                });
            }
        });
        candidates.retain(|path| seen.insert(path.clone()));
        drop(canonical_timer);
        let _prepare_timer = dm_profile::detail_timer("inputs.prepare_sources");
        let worker_count = if candidates.is_empty() {
            0
        } else {
            executor.workers().min(candidates.len())
        };
        let next = AtomicUsize::new(0);
        let outputs = Mutex::new(vec![None; candidates.len()]);
        let workers_succeeded = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            executor.scope(|scope| {
                for _ in 0..worker_count {
                    let candidates = &candidates;
                    let outputs = &outputs;
                    let next = &next;
                    let prepare = &prepare;
                    scope.spawn(move |_| {
                        let _profile = dm_profile::stage("input_scan");
                        loop {
                            let index = next.fetch_add(1, Ordering::Relaxed);
                            if index >= candidates.len() {
                                break;
                            }
                            // A speculative failure is not an input diagnostic and
                            // is never cached as absence or a required-read error.
                            let Ok(prepared) = prepare(provider, &candidates[index]) else {
                                continue;
                            };
                            let Ok(mut outputs) = outputs.lock() else {
                                break;
                            };
                            outputs[index] = Some(prepared);
                        }
                    });
                }
            });
        }))
        .is_ok();
        if !workers_succeeded {
            return Err(NativeInputError::InternalPreparation {
                message: "worker panicked".into(),
            });
        }
        let outputs = outputs
            .into_inner()
            .map_err(|_| NativeInputError::InternalPreparation {
                message: "poisoned output state".into(),
            })?;
        let prepared = outputs.iter().filter(|source| source.is_some()).count();
        let captures = std::iter::once((project, manifest)).chain(
            candidates
                .iter()
                .cloned()
                .zip(outputs)
                .filter_map(|(path, source)| source.map(|source| (path, source))),
        );
        let sources = PreparedSources::from_prepared(captures).map_err(|error| {
            NativeInputError::InternalPreparation {
                message: format!("capture invariant: {error:?}"),
            }
        })?;
        Ok(Self {
            sources,
            stats: PreparationStats {
                candidates: candidates.len(),
                prepared,
                deferred: candidates.len() - prepared,
                workers: worker_count,
            },
        })
    }

    pub fn sources(&self) -> &PreparedSources {
        &self.sources
    }
    pub fn stats(&self) -> PreparationStats {
        self.stats
    }

    pub fn provider<'a, P: SourceProvider>(
        &'a self,
        fallback: &'a P,
    ) -> PreparedSourceProvider<'a, P> {
        PreparedSourceProvider::new(&self.sources, fallback)
    }
}

#[cfg(test)]
mod tests {

    #[test]
    fn actual_selected_original_candidates_keep_the_same_revision_and_warm_lexical_owner() {
        use crate::input_snapshot::{FileSystemInputs, PreparedInputArtifacts, RecordingInputs};
        use dm_preprocess::InitialEnvironment::OriginalChecker0290;
        let root = crate::test_scratch::dir("original-selected-deferred-lexical");
        let project = root.join("project.dme");
        let ordinary = root.join("plain.dm");
        let bom = root.join("bom.dm");
        std::fs::write(&project, b"#include \"plain.dm\"\n#if 0\n#include \"bom.dm\"\n#endif\n").unwrap();
        std::fs::write(&ordinary, b"/datum/cold_selected_candidate_0290\n").unwrap();
        std::fs::write(&bom, b"\xef\xbb\xbf/datum/cold_bom_candidate_0290\n").unwrap();

        let inputs = Arc::new(PreparedInputArtifacts::default());
        let capture = || {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
            RecordingInputs::new(FileSystemInputs, now)
                .with_initial_environment(OriginalChecker0290)
                .with_exact_reuse(true)
                .with_prepared_sources(Some(Arc::clone(&inputs)))
        };
        let executor = dm_exec::BuildExecutor::new(2).unwrap();
        let selected = capture();
        let prefetched = NativeInputs::prepare_selected_original_with_hints(
            &project, &selected, &executor, Vec::new(),
        ).unwrap();
        assert!(prefetched.sources().get(&project).unwrap().resident_lexical_lines().is_some());
        let original_plain = prefetched.sources().get(&ordinary).unwrap();
        let original_bom = prefetched.sources().get(&bom).unwrap();
        assert!(original_plain.resident_lexical_lines().is_none());
        assert!(original_bom.resident_lexical_lines().is_none());
        let original_bytes = selected.source_acquisition(&bom, original_bom.original()).unwrap();
        assert_eq!(original_bytes.encoding(), dm_preprocess::SourceEncoding::Utf8Bom);
        let selected_facts = selected.snapshot().unwrap();
        assert!(selected_facts.contains_file(&bom), "inactive candidates still keep old revision coverage");

        let db = crate::query_db::QueryDb::default();
        let first = db.revise(prefetched.sources(), 0x29).unwrap();
        assert_eq!((first.sources, first.changed, first.removed), (3, 3, 0));
        selected.finish_prepared().unwrap();
        drop((prefetched, selected));

        let ordinary_capture = capture();
        let warm = NativeInputs::prepare_with_hints(
            &project, &ordinary_capture, &executor, Vec::new(),
        ).unwrap();
        for (path, prior) in [(&ordinary, original_plain), (&bom, original_bom)] {
            let current = warm.sources().get(path).unwrap();
            assert!(Arc::ptr_eq(&prior, &current));
            assert!(current.resident_lexical_lines().is_some(), "ordinary warm hit must eagerly prepare");
        }
        let warm_facts = ordinary_capture.snapshot().unwrap();
        assert_eq!(selected_facts.files().collect::<Vec<_>>(), warm_facts.files().collect::<Vec<_>>());
        let second = db.revise(warm.sources(), 0x29).unwrap();
        assert_eq!((second.sources, second.changed, second.removed), (3, 0, 0));
        assert_eq!(second.revision, first.revision);
        assert!(second.green);
    }
    use super::*;
    use dm_preprocess::regions::{expand_regions, plan_regions};
    use std::collections::BTreeMap;

    struct Memory {
        files: BTreeMap<PathBuf, Arc<str>>,
        reads: Mutex<Vec<PathBuf>>,
        transient: Mutex<Option<PathBuf>>,
    }
    impl Memory {
        fn new(files: &[(&str, &str)]) -> Self {
            Self {
                files: files
                    .iter()
                    .map(|(path, text)| (PathBuf::from(path), Arc::from(*text)))
                    .collect(),
                reads: Mutex::new(Vec::new()),
                transient: Mutex::new(None),
            }
        }
    }
    impl SourceProvider for Memory {
        fn read(&self, path: &Path) -> Result<String, String> {
            self.reads.lock().unwrap().push(path.to_owned());
            let mut transient = self.transient.lock().unwrap();
            if transient.as_deref() == Some(path) {
                transient.take();
                return Err("speculative read unavailable".into());
            }
            self.files
                .get(path)
                .map(ToString::to_string)
                .ok_or_else(|| format!("missing {}", path.display()))
        }
    }

    #[test]
    fn direct_prefetch_preserves_order_conditional_origins_and_file_dir() {
        let files = [
            ("project.dme", "#define ENABLE 1\n#define FILE_DIR \"root-assets\"\n#include \"parent.dm\"\n#if 0\n#include \"inactive.dm\"\n#include \"missing.dm\"\n#endif\n#include \"./parent.dm\"\n#include \"map.dmm\"\n"),
            ("parent.dm", "#if ENABLE\n#define VALUE 4\n#define FILE_DIR \"child-assets\"\n#include \"nested.dm\"\n#undef FILE_DIR\n#endif\n/datum/probe\n    var/after = VALUE\n"),
            ("nested.dm", "#define VALUE 7\n"),
            ("inactive.dm", "#error must remain inactive\n"),
        ];
        let direct = Memory::new(&files);
        let reference = plan_regions(Path::new("project.dme"), &direct, &BTreeMap::new());
        let expected = expand_regions(&reference, 1);
        for workers in [0, 1, 2, 8] {
            let source = Memory::new(&files);
            let inputs = NativeInputs::prepare(Path::new("project.dme"), &source, workers).unwrap();
            assert!(inputs.stats().workers <= workers.max(1));
            assert_eq!(inputs.stats().candidates, 3);
            assert_eq!(inputs.stats().deferred, 1);
            let provider = inputs.provider(&source);
            let plan = plan_regions(Path::new("project.dme"), &provider, &BTreeMap::new());
            let actual = expand_regions(&plan, 2);
            assert_eq!(actual.text, expected.text);
            assert_eq!(actual.tokens, expected.tokens);
            assert_eq!(actual.diagnostics, expected.diagnostics);
            assert_eq!(plan.dependencies, reference.dependencies);
            assert_eq!(plan.file_dirs, reference.file_dirs);
            assert_eq!(plan.source_line_starts, reference.source_line_starts);
            assert_eq!(
                plan.occurrences
                    .iter()
                    .map(|o| (&o.path, o.parent, o.suppressed))
                    .collect::<Vec<_>>(),
                reference
                    .occurrences
                    .iter()
                    .map(|o| (&o.path, o.parent, o.suppressed))
                    .collect::<Vec<_>>()
            );
            assert_eq!(
                actual
                    .origins
                    .iter()
                    .map(|o| (o.origin, o.source_span, o.region))
                    .collect::<Vec<_>>(),
                expected
                    .origins
                    .iter()
                    .map(|o| (o.origin, o.source_span, o.region))
                    .collect::<Vec<_>>()
            );
            let frontend =
                dm_tree::frontend::build(Path::new("project.dme"), &provider, &BTreeMap::new(), 2)
                    .unwrap();
            assert!(!frontend
                .files
                .iter()
                .any(|file| file.path.as_ref() == Path::new("inactive.dm")));
            let reads = source.reads.lock().unwrap();
            assert_eq!(
                reads
                    .iter()
                    .filter(|path| path.as_path() == Path::new("project.dme"))
                    .count(),
                1
            );
            assert_eq!(
                reads
                    .iter()
                    .filter(|path| path.as_path() == Path::new("parent.dm"))
                    .count(),
                1
            );
            assert!(!reads
                .iter()
                .any(|path| path.extension().is_some_and(|ext| ext == "dmm")));
        }
    }

    #[test]
    fn failed_candidates_retry_and_macro_include_policy_stays_on_demand() {
        let source = Memory::new(&[
            ("project.dme", "#include \"active.dm\"\n"),
            ("active.dm", "/datum/probe\n    var/value = 3\n"),
        ]);
        *source.transient.lock().unwrap() = Some(PathBuf::from("active.dm"));
        let inputs = NativeInputs::prepare(Path::new("project.dme"), &source, 2).unwrap();
        assert_eq!(inputs.stats().deferred, 1);
        let provider = inputs.provider(&source);
        let frontend =
            dm_tree::frontend::build(Path::new("project.dme"), &provider, &BTreeMap::new(), 1)
                .unwrap();
        assert!(frontend
            .files
            .iter()
            .any(|file| file.path.as_ref() == Path::new("active.dm") && file.captured));

        let source = Memory::new(&[
            (
                "macro.dme",
                "#define HEADER \"generated.dm\"\n#include HEADER\n",
            ),
            ("generated.dm", "/datum/generated\n"),
        ]);
        let direct = plan_regions(Path::new("macro.dme"), &source, &BTreeMap::new());
        let inputs = NativeInputs::prepare(Path::new("macro.dme"), &source, 2).unwrap();
        assert_eq!(inputs.stats().candidates, 0);
        let provider = inputs.provider(&source);
        let actual = plan_regions(Path::new("macro.dme"), &provider, &BTreeMap::new());
        // Current directive grammar does not certify macro include operands.
        // Acceleration must retain that diagnostic rather than interpret them.
        assert_eq!(actual.diagnostics, direct.diagnostics);
        assert!(provider
            .prepared_source(Path::new("generated.dm"))
            .is_none());
        assert_eq!(
            provider.read(Path::new("generated.dm")).unwrap(),
            "/datum/generated\n"
        );
    }
    #[test]
    fn manifest_read_failures_and_preparation_panics_remain_distinct() {
        let source = Memory::new(&[]);
        assert!(
            matches!(NativeInputs::prepare(Path::new("absent.dme"), &source, 2),
            Err(NativeInputError::RequiredSourceRead { path, .. }) if path == Path::new("absent.dme"))
        );
        struct Panicking;
        impl SourceProvider for Panicking {
            fn read(&self, path: &Path) -> Result<String, String> {
                if path == Path::new("project.dme") {
                    Ok("#include \"candidate.dm\"\n".into())
                } else {
                    panic!("fixture preparation defect");
                }
            }
        }
        assert!(matches!(
            NativeInputs::prepare(Path::new("project.dme"), &Panicking, 2),
            Err(NativeInputError::InternalPreparation { .. })
        ));
    }
    #[test]
    fn issued_preparations_are_reused_without_reads_or_repreparation() {
        struct Issued {
            sources: PreparedSources,
            reads: AtomicUsize,
        }
        impl SourceProvider for Issued {
            fn prepared_source(&self, path: &Path) -> Option<Arc<PreparedSource>> {
                self.sources.get(path)
            }
            fn read(&self, _: &Path) -> Result<String, String> {
                self.reads.fetch_add(1, Ordering::Relaxed);
                Err("prepared authority must avoid fallback reads".into())
            }
        }
        let manifest = Arc::new(PreparedSource::new(Arc::from("#include \"body.dm\"\n")));
        let body = Arc::new(PreparedSource::new(Arc::from("/proc/p()\n    return 1\n")));
        let provider = Issued {
            sources: PreparedSources::from_prepared([
                (PathBuf::from("project.dme"), Arc::clone(&manifest)),
                (PathBuf::from("body.dm"), Arc::clone(&body)),
            ])
            .unwrap(),
            reads: AtomicUsize::new(0),
        };
        for workers in [1, 2] {
            let inputs =
                NativeInputs::prepare(Path::new("project.dme"), &provider, workers).unwrap();
            assert!(Arc::ptr_eq(
                &inputs.sources.get(Path::new("project.dme")).unwrap(),
                &manifest
            ));
            assert!(Arc::ptr_eq(
                &inputs.sources.get(Path::new("body.dm")).unwrap(),
                &body
            ));
            let prepared_provider = inputs.provider(&provider);
            let actual = plan_regions(
                Path::new("project.dme"),
                &prepared_provider,
                &BTreeMap::new(),
            );
            let expected = plan_regions(Path::new("project.dme"), &provider, &BTreeMap::new());
            assert_eq!(
                expand_regions(&actual, workers).text,
                expand_regions(&expected, workers).text
            );
        }
        assert_eq!(provider.reads.load(Ordering::Relaxed), 0);
    }
}
