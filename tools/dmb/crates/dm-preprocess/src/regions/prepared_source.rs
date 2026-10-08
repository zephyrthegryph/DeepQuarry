//! Immutable lexical preparation separated from ordered directive interpretation.
//!
//! Preparation never interprets conditional state or discovers includes. Callers
//! supply already captured sources; a later directive walk decides which are used.
use super::canonical_path;
use crate::{logical_lines, strip_source_comments};
use dm_syntax::Span;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

/// Recognize a literal include candidate from an already prepared logical line.
/// Candidate discovery does not evaluate whether the directive is active.
pub fn literal_include_path(line: &str) -> Option<PathBuf> {
    let directive = line.trim_start().strip_prefix('#')?;
    let (word, operand) = crate::split_word(directive.trim_start());
    if word != "include" {
        return None;
    }
    super::literal_include_path(operand)
}

#[derive(Clone, Debug)]
pub struct PreparedLine {
    pub source_span: Span,
    pub source_line: usize,
    pub source_lines: usize,
    pub text: Arc<str>,
}

/// Prepared bytes and locations are constructed together and cannot be replaced
/// independently. Text is decoded by the capture boundary before preparation.
#[derive(Clone, Debug)]
pub struct PreparedSource {
    original: Arc<str>,
    line_starts: Arc<[usize]>,
    lines: Arc<[PreparedLine]>,
}
impl PreparedSource {
    pub fn new(original: Arc<str>) -> Self {
        let mut starts = vec![0];
        starts.extend(
            original
                .bytes()
                .enumerate()
                .filter_map(|(offset, byte)| (byte == b'\n').then_some(offset + 1)),
        );
        let uncommented = strip_source_comments(&original);
        let mut source_line = 0;
        let lines = logical_lines(&uncommented)
            .into_iter()
            .map(|logical| {
                let first = source_line;
                source_line += logical.source_lines;
                PreparedLine {
                    source_span: Span::new(
                        starts[first],
                        starts.get(source_line).copied().unwrap_or(original.len()),
                    ),
                    source_line: first + 1,
                    source_lines: logical.source_lines,
                    text: Arc::from(logical.text),
                }
            })
            .collect::<Vec<_>>();
        Self {
            original,
            line_starts: starts.into(),
            lines: lines.into(),
        }
    }
    pub fn original(&self) -> &Arc<str> {
        &self.original
    }
    pub fn line_starts(&self) -> &Arc<[usize]> {
        &self.line_starts
    }
    pub fn lines(&self) -> &[PreparedLine] {
        &self.lines
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PreparationError {
    DuplicatePath(PathBuf),
    WorkerPanicked,
}

/// One build's immutable preparations. No memo, include policy or filesystem
/// reads are hidden here. Only the supplied captures are prepared.
#[derive(Clone, Debug, Default)]
pub struct PreparedSources {
    sources: BTreeMap<PathBuf, Arc<PreparedSource>>,
}
impl PreparedSources {
    pub fn prepare(
        captures: impl IntoIterator<Item = (PathBuf, Arc<str>)>,
        workers: usize,
    ) -> Result<Self, PreparationError> {
        let captures = captures
            .into_iter()
            .map(|(path, text)| (canonical_path(&path), text))
            .collect::<Vec<_>>();
        let mut seen = std::collections::BTreeSet::new();
        for (path, _) in &captures {
            if !seen.insert(path.clone()) {
                return Err(PreparationError::DuplicatePath(path.clone()));
            }
        }
        let count = captures.len();
        let worker_count = workers
            .max(1)
            .min(std::thread::available_parallelism().map_or(1, usize::from))
            .min(count.max(1));
        let next = AtomicUsize::new(0);
        let outputs = Mutex::new((0..count).map(|_| None).collect::<Vec<_>>());
        let succeeded = std::thread::scope(|scope| {
            let handles = (0..worker_count)
                .map(|_| {
                    let captures = &captures;
                    let next = &next;
                    let outputs = &outputs;
                    scope.spawn(move || loop {
                        let index = next.fetch_add(1, Ordering::Relaxed);
                        if index >= captures.len() {
                            break;
                        }
                        let prepared = Arc::new(PreparedSource::new(captures[index].1.clone()));
                        let Ok(mut outputs) = outputs.lock() else {
                            break;
                        };
                        outputs[index] = Some(prepared);
                    })
                })
                .collect::<Vec<_>>();
            let mut all_joined = true;
            for handle in handles {
                // Join every worker even after one fails; iterator all() would
                // short-circuit these side effects.
                all_joined &= handle.join().is_ok();
            }
            all_joined
        });
        if !succeeded {
            return Err(PreparationError::WorkerPanicked);
        }
        let outputs = outputs
            .into_inner()
            .map_err(|_| PreparationError::WorkerPanicked)?;
        let mut sources = BTreeMap::new();
        for ((path, _), prepared) in captures.into_iter().zip(outputs) {
            sources.insert(path, prepared.ok_or(PreparationError::WorkerPanicked)?);
        }
        Ok(Self { sources })
    }
    /// Admit already-issued immutable preparations without lexing them again.
    /// Paths use the directive pass's access identity; duplicates are rejected
    /// even when both entries reference the same immutable source object.
    pub fn from_prepared(
        captures: impl IntoIterator<Item = (PathBuf, Arc<PreparedSource>)>,
    ) -> Result<Self, PreparationError> {
        let mut sources = BTreeMap::new();
        for (path, prepared) in captures {
            let path = canonical_path(&path);
            if sources.insert(path.clone(), prepared).is_some() {
                return Err(PreparationError::DuplicatePath(path));
            }
        }
        Ok(Self { sources })
    }
    pub fn get(&self, path: &Path) -> Option<Arc<PreparedSource>> {
        self.sources.get(&canonical_path(path)).cloned()
    }
    pub fn len(&self) -> usize {
        self.sources.len()
    }
    pub fn is_empty(&self) -> bool {
        self.sources.is_empty()
    }
}

impl crate::SourceProvider for PreparedSources {
    fn read(&self, path: &Path) -> Result<String, String> {
        self.get(path)
            .map(|source| source.original().to_string())
            .ok_or_else(|| format!("source not captured: {}", path.display()))
    }
    fn prepared_source(&self, path: &Path) -> Option<Arc<PreparedSource>> {
        self.get(path)
    }
}

/// Known captures are authoritative immutable input bytes. Includes discovered
/// during directive replay and absent from this set delegate to the source
/// provider and use the identical on-demand preparation algorithm.
pub struct PreparedSourceProvider<'a, P> {
    captures: &'a PreparedSources,
    fallback: &'a P,
}
impl<'a, P> PreparedSourceProvider<'a, P> {
    pub fn new(captures: &'a PreparedSources, fallback: &'a P) -> Self {
        Self { captures, fallback }
    }
}
impl<P: crate::SourceProvider> crate::SourceProvider for PreparedSourceProvider<'_, P> {
    fn read(&self, path: &Path) -> Result<String, String> {
        match self.captures.get(path) {
            Some(source) => Ok(source.original().to_string()),
            None => self.fallback.read(path),
        }
    }
    fn prepared_source(&self, path: &Path) -> Option<Arc<PreparedSource>> {
        self.captures
            .get(path)
            .or_else(|| self.fallback.prepared_source(path))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::regions::{expand_regions, plan_regions};
    use crate::SourceProvider;
    struct Memory {
        files: BTreeMap<PathBuf, Arc<str>>,
        reads: Mutex<Vec<PathBuf>>,
    }
    impl SourceProvider for Memory {
        fn read(&self, path: &Path) -> Result<String, String> {
            self.reads.lock().unwrap().push(path.to_owned());
            self.files
                .get(path)
                .map(ToString::to_string)
                .ok_or_else(|| "missing".into())
        }
    }
    #[test]
    fn parallel_preparations_preserve_conditional_include_replay_and_origins() {
        let files: BTreeMap<_, Arc<str>> = [
            ("project.dme", "/* #include \"absent.dm\" */\n#define ENABLE 1\n#include \"parent.dm\"\n#include \"parent.dm\"\n#if 0\n#include \"absent.dm\"\n#endif\n"),
            ("parent.dm", "#define VALUE 1\nvar/before = VALUE\n#include \"child.dm\"\nvar/after = VALUE\nvar/joined = (\n#include \"fragment.dm\"\n)\n"),
            ("child.dm", "#if ENABLE\n#define VALUE 2\nvar/child = VALUE\n#endif\n"),
            ("fragment.dm", "VALUE + 3\n"),
        ].into_iter().map(|(path, text)| (PathBuf::from(path), Arc::from(text))).collect();
        let direct = Memory {
            files: files.clone(),
            reads: Mutex::new(Vec::new()),
        };
        let reference = plan_regions(Path::new("project.dme"), &direct, &BTreeMap::new());
        let reference_output = expand_regions(&reference, 1);
        assert!(reference_output.diagnostics.is_empty());
        for workers in [1, 2, usize::MAX] {
            let prepared = PreparedSources::prepare(
                files
                    .iter()
                    .filter(|(path, _)| path.as_path() != Path::new("child.dm"))
                    .map(|(path, source)| (path.clone(), source.clone())),
                workers,
            )
            .unwrap();
            let fallback = Memory {
                files: files.clone(),
                reads: Mutex::new(Vec::new()),
            };
            let provider = PreparedSourceProvider::new(&prepared, &fallback);
            let plan = plan_regions(Path::new("project.dme"), &provider, &BTreeMap::new());
            let output = expand_regions(&plan, workers);
            assert_eq!(output.text, reference_output.text);
            assert_eq!(output.tokens, reference_output.tokens);
            assert_eq!(output.diagnostics, reference_output.diagnostics);
            assert_eq!(plan.dependencies, reference.dependencies);
            assert_eq!(plan.source_line_starts, reference.source_line_starts);
            assert_eq!(
                plan.occurrences
                    .iter()
                    .map(|entry| (&entry.path, entry.parent, entry.suppressed))
                    .collect::<Vec<_>>(),
                reference
                    .occurrences
                    .iter()
                    .map(|entry| (&entry.path, entry.parent, entry.suppressed))
                    .collect::<Vec<_>>()
            );
            assert_eq!(
                output
                    .origins
                    .iter()
                    .map(|entry| (&entry.origin, entry.source_span, entry.region))
                    .collect::<Vec<_>>(),
                reference_output
                    .origins
                    .iter()
                    .map(|entry| (&entry.origin, entry.source_span, entry.region))
                    .collect::<Vec<_>>()
            );
            assert_eq!(
                *fallback.reads.lock().unwrap(),
                vec![PathBuf::from("child.dm")]
            );
            let parent = prepared.get(Path::new("parent.dm")).unwrap();
            let before = plan
                .regions
                .iter()
                .flat_map(|region| &region.segments)
                .flat_map(|segment| &segment.lines)
                .find(|line| line.text.contains("var/before"))
                .unwrap();
            let prepared_before = parent
                .lines()
                .iter()
                .find(|line| line.text.contains("var/before"))
                .unwrap();
            assert!(Arc::ptr_eq(&before.text, &prepared_before.text));
            assert!(Arc::ptr_eq(
                &plan.source_line_starts[Path::new("parent.dm")],
                parent.line_starts()
            ));
        }
    }
    #[test]
    fn duplicate_access_paths_are_rejected_before_preparation() {
        let error = PreparedSources::prepare(
            [
                (PathBuf::from("folder/../same.dm"), Arc::from("var/a = 1\n")),
                (PathBuf::from("same.dm"), Arc::from("var/a = 2\n")),
            ],
            2,
        )
        .unwrap_err();
        assert_eq!(
            error,
            PreparationError::DuplicatePath(PathBuf::from("same.dm"))
        );
    }
    #[test]
    fn logical_offsets_preserve_comments_continuations_and_multiline_literals() {
        let source: Arc<str> = Arc::from("/* comment\ncontinued */\n#define VALUE \\\n  4\nvar/name = {\"first\nsecond\"}\nvar/r = @\"^\\[abc\\]$\"\n");
        let prepared = PreparedSource::new(source.clone());
        assert!(Arc::ptr_eq(prepared.original(), &source));
        let direct = logical_lines(&strip_source_comments(&source));
        assert_eq!(
            prepared
                .lines()
                .iter()
                .map(|line| (line.text.as_ref(), line.source_lines))
                .collect::<Vec<_>>(),
            direct
                .iter()
                .map(|line| (line.text.as_str(), line.source_lines))
                .collect::<Vec<_>>()
        );
        for line in prepared.lines() {
            assert!(source.get(line.source_span.range()).is_some());
            assert_eq!(
                line.source_span.start,
                prepared.line_starts()[line.source_line - 1]
            );
        }
    }
    #[test]
    fn issued_preparations_reuse_bytes_and_exact_access_path_policy() {
        let issued = Arc::new(PreparedSource::new(Arc::from(
            "#define VALUE 3\nvar/value = VALUE\n",
        )));
        let captures = PreparedSources::from_prepared([(
            PathBuf::from("folder/../project.dme"),
            issued.clone(),
        )])
        .unwrap();
        assert!(Arc::ptr_eq(
            &captures.get(Path::new("./project.dme")).unwrap(),
            &issued
        ));
        assert_eq!(
            captures.read(Path::new("project.dme")).unwrap(),
            issued.original().as_ref()
        );
        let error = PreparedSources::from_prepared([
            (PathBuf::from("folder/../project.dme"), issued.clone()),
            (PathBuf::from("project.dme"), issued),
        ])
        .unwrap_err();
        assert_eq!(
            error,
            PreparationError::DuplicatePath(PathBuf::from("project.dme"))
        );
        assert_eq!(
            super::super::literal_include_path(r#"  "code\sub\file.dm"  "#),
            Some(PathBuf::from("code/sub/file.dm"))
        );
        assert_eq!(super::super::literal_include_path("INCLUDE_MACRO"), None);
        assert_eq!(
            literal_include_path(r#"  #include "code\sub\file.dm" "#),
            Some(PathBuf::from("code/sub/file.dm"))
        );
        assert_eq!(
            literal_include_path(r##"var/text = "#include fake.dm""##),
            None
        );
        assert_eq!(literal_include_path("#include INCLUDE_MACRO"), None);
    }
    #[test]
    fn implicit_terminal_offset_matches_sentinel_provenance() {
        for text in [
            "",
            "\n",
            "var/a = 1",
            "var/a = 1\n",
            "var/a = 1\n\n",
            "/* block\ncomment */\nvar/a = 1",
            "var/a = 1 // comment\n",
            "#define VALUE (1 + \\\n2)\nvar/a = VALUE",
            "var/text = {\"first\n\nlast\"}\nvar/after = 2\n",
        ] {
            let prepared = PreparedSource::new(Arc::from(text));
            let mut starts = vec![0];
            starts.extend(
                text.bytes()
                    .enumerate()
                    .filter_map(|(index, byte)| (byte == b'\n').then_some(index + 1)),
            );
            assert_eq!(prepared.line_starts().as_ref(), starts.as_slice());
            starts.push(text.len());
            let mut line = 0;
            let expected = logical_lines(&strip_source_comments(text))
                .into_iter()
                .map(|logical| {
                    let first = line;
                    line += logical.source_lines;
                    (
                        Span::new(starts[first], starts[line]),
                        first + 1,
                        logical.source_lines,
                        logical.text,
                    )
                })
                .collect::<Vec<_>>();
            let actual = prepared
                .lines()
                .iter()
                .map(|logical| {
                    (
                        logical.source_span,
                        logical.source_line,
                        logical.source_lines,
                        logical.text.to_string(),
                    )
                })
                .collect::<Vec<_>>();
            assert_eq!(actual, expected, "{text:?}");
        }
    }
}
