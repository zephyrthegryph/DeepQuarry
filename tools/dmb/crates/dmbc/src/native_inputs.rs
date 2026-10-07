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
use dm_preprocess::SourceProvider;
use std::collections::BTreeSet;
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
    if let Some(prepared) = provider.prepared_source(path) {
        return Ok(prepared);
    }
    provider
        .read(path)
        .map(|text| Arc::new(PreparedSource::new(Arc::from(text))))
}

impl NativeInputs {
    /// Capture the required manifest once. Only its direct literal source paths
    /// are offered to at most two workers. Conditional state, macro effects,
    /// FILE_DIR and recursive include discovery belong to the ordered frontend.
    pub fn prepare<P: SourceProvider + Sync>(
        project: &Path,
        provider: &P,
        workers: usize,
    ) -> Result<Self, NativeInputError> {
        let project = canonical_path(project);
        let manifest = prepare_source(provider, &project).map_err(|message| {
            NativeInputError::RequiredSourceRead {
                path: project.clone(),
                message,
            }
        })?;
        let parent = project.parent().unwrap_or(Path::new(""));
        let mut seen = BTreeSet::from([project.clone()]);
        let candidates = manifest
            .lines()
            .iter()
            .filter_map(|line| literal_include_path(&line.text))
            .filter(|path| {
                path.extension()
                    .and_then(|value| value.to_str())
                    .is_some_and(|extension| {
                        extension.eq_ignore_ascii_case("dm")
                            || extension.eq_ignore_ascii_case("dme")
                    })
            })
            .map(|path| canonical_path(&parent.join(path)))
            .filter(|path| seen.insert(path.clone()))
            .collect::<Vec<_>>();
        let worker_count = if candidates.is_empty() {
            0
        } else {
            workers
                .clamp(1, 2)
                .min(std::thread::available_parallelism().map_or(1, usize::from))
                .min(candidates.len())
        };
        let next = AtomicUsize::new(0);
        let outputs = Mutex::new(vec![None; candidates.len()]);
        let workers_succeeded = std::thread::scope(|scope| {
            let handles = (0..worker_count)
                .map(|_| {
                    let candidates = &candidates;
                    let outputs = &outputs;
                    let next = &next;
                    scope.spawn(move || loop {
                        let _profile = dm_profile::stage("input_scan");
                        let index = next.fetch_add(1, Ordering::Relaxed);
                        if index >= candidates.len() {
                            break;
                        }
                        // A speculative failure is not an input diagnostic and
                        // is never cached as absence or a required-read error.
                        let Ok(prepared) = prepare_source(provider, &candidates[index]) else {
                            continue;
                        };
                        let Ok(mut outputs) = outputs.lock() else {
                            break;
                        };
                        outputs[index] = Some(prepared);
                    })
                })
                .collect::<Vec<_>>();
            // Join every worker, including after an earlier panic. Code defects
            // are internal failures; only ordinary read errors are optional.
            handles
                .into_iter()
                .map(|handle| handle.join().is_ok())
                .fold(true, |all, succeeded| all && succeeded)
        });
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
        for workers in [0, 1, 2, usize::MAX] {
            let source = Memory::new(&files);
            let inputs = NativeInputs::prepare(Path::new("project.dme"), &source, workers).unwrap();
            assert!(inputs.stats().workers <= 2);
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
                    .map(|o| (&o.origin, o.source_span, o.region))
                    .collect::<Vec<_>>(),
                expected
                    .origins
                    .iter()
                    .map(|o| (&o.origin, o.source_span, o.region))
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
