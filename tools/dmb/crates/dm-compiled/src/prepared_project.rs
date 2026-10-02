//! Detached, immutable project inputs shared by compilation and source tools.
//! Digests identify decoded DM text; filesystem proofs are an acceleration,
//! never a replacement for the content identities or authored source origins.
#[path = "expanded_segments.rs"]
mod expanded_segments;
use crate::input_proof::InputProof;
use dm_host::file_stamp::FileStamp;
use dm_preprocess::PreprocessedProject;
use dm_syntax::Span;
pub(crate) use expanded_segments::splice_source_edits;
pub use expanded_segments::{ExpandedSegment, SegmentedExpansion};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;

#[derive(Clone, Debug)]
pub struct PreparedSource {
    pub text: Arc<str>,
    /// Content identity after the compiler's UTF-8/Windows-1252 decoding.
    pub digest: [u8; 32],
    pub(crate) stamp: Option<FileStamp>,
}

#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub struct IncludeOccurrence {
    pub path: PathBuf,
    /// Source-order ordinal for this path, including repeated includes.
    pub ordinal: usize,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct UnitChange {
    pub occurrence: IncludeOccurrence,
    pub previous_span: Option<Span>,
    pub current_span: Option<Span>,
}

#[derive(Clone, Debug, Default)]
pub struct PreparationChanges {
    pub added_sources: BTreeSet<PathBuf>,
    pub changed_sources: BTreeSet<PathBuf>,
    pub removed_sources: BTreeSet<PathBuf>,
    /// Expanded unit changes, separate from shifted presentation offsets.
    /// Procedure/signature equality belongs to the shared compiler frontend.
    pub changed_units: Vec<UnitChange>,
    pub configuration_changed: bool,
}

#[derive(Clone, Copy, Debug, Default)]
pub struct PreparationStats {
    pub retained_hit: bool,
    pub disk_restored: bool,
    pub preprocessed: bool,
    pub source_files_read: usize,
    pub source_bytes_read: usize,
    pub sources_reused: usize,
}

/// Source text, exact origins and include order belong to one frozen revision.
/// Holding this Arc pins only detached data, never a Salsa database/session.
#[derive(Clone)]
pub struct PreparedProject {
    pub project: Arc<PreprocessedProject>,
    /// Persistent pieces shared across edited expansion generations.
    pub expansion: Arc<SegmentedExpansion>,
    /// Conservative temporal macro namespace, including later #undefs.
    pub macro_names: Arc<BTreeSet<String>>,
    pub sources: Arc<BTreeMap<PathBuf, PreparedSource>>,
    pub project_digest: String,
    pub expanded_digest: String,
    pub revision: String,
    pub changes: PreparationChanges,
    pub stats: PreparationStats,
    pub(crate) context: String,
    pub(crate) proof: Option<InputProof>,
}

impl PreparedProject {
    pub fn current(&self) -> bool {
        let missing = || {
            self.project
                .dependencies
                .iter()
                .filter(|path| !self.sources.contains_key(*path))
                .any(|path| path.exists())
        };
        if let Some(proof) = &self.proof {
            if let Some(current) = proof.namespace_current() {
                return current;
            }
            return proof.current() && !missing();
        }
        let limits = dm_work::WorkLimits::configured();
        !missing()
            && dm_work::map_ordered(
                &self.sources.iter().collect::<Vec<_>>(),
                limits,
                |(_, source)| {
                    source
                        .text
                        .len()
                        .saturating_mul(8)
                        .saturating_add(16 * 1024)
                },
                |(path, expected)| {
                    crate::project_discovery::read_prepared_source(path, limits)
                        .is_ok_and(|source| source.digest == expected.digest)
                },
            )
            .is_ok_and(|results| results.into_iter().all(|current| current))
    }

    pub fn resident_bytes(&self) -> usize {
        let mut paths = BTreeSet::new();
        self.macro_names
            .iter()
            .map(|name| name.len() + 48)
            .sum::<usize>()
            + self
                .expansion
                .segments
                .iter()
                .map(|piece| piece.text.len() + piece.lines.len()*std::mem::size_of::<usize>() + 96)
                .sum::<usize>()
            + self.project.text.capacity()
            + self.project.origins.capacity() * std::mem::size_of::<dm_preprocess::Origin>()
            + self
                .project
                .origins
                .iter()
                .filter(|origin| paths.insert(Arc::as_ptr(&origin.path) as usize))
                .map(|origin| origin.path.as_os_str().len() * 2 + 64)
                .sum::<usize>()
            + self.project.units.capacity() * std::mem::size_of::<dm_preprocess::Unit>()
            + self
                .project
                .units
                .iter()
                .map(|unit| unit.path.as_os_str().len() * 2)
                .sum::<usize>()
            + self.project.unit_digests.capacity() * 32
            + self
                .sources
                .iter()
                .map(|(path, source)| path.as_os_str().len() * 2 + source.text.len() + 192)
                .sum::<usize>()
            + self.proof.as_ref().map_or(0, InputProof::resident_bytes)
            + self
                .project
                .dependencies
                .iter()
                .chain(&self.project.map_includes)
                .chain(&self.project.skin_includes)
                .chain(&self.project.file_dirs)
                .map(|path| path.as_os_str().len() * 2 + 48)
                .sum::<usize>()
            + self
                .project
                .final_macros
                .iter()
                .map(|(name, value)| name.capacity() + value.replacement.capacity() + 128)
                .sum::<usize>()
            + self
                .project
                .diagnostics
                .iter()
                .map(|value| value.message.capacity() + value.path.as_os_str().len() * 2 + 64)
                .sum::<usize>()
    }
}

pub(crate) fn project_digest(root: &Path, sources: &BTreeMap<PathBuf, PreparedSource>) -> String {
    let directory = root.parent().unwrap_or_else(|| Path::new("."));
    let mut hash = Sha256::new();
    hash.update(b"dm-project-inputs-v2\0");
    for (path, source) in sources {
        let name = path
            .strip_prefix(directory)
            .unwrap_or(path)
            .to_string_lossy();
        hash.update((name.len() as u64).to_le_bytes());
        hash.update(name.as_bytes());
        hash.update((source.text.len() as u64).to_le_bytes());
        hash.update(source.digest);
    }
    format!("{:x}", hash.finalize())
}

pub(crate) fn changes(
    previous: Option<&PreparedProject>,
    project: &PreprocessedProject,
    sources: &BTreeMap<PathBuf, PreparedSource>,
    context: &str,
) -> PreparationChanges {
    let mut result = PreparationChanges::default();
    result.configuration_changed = previous.is_some_and(|old| old.context != context);
    for (path, source) in sources {
        match previous.and_then(|old| old.sources.get(path)) {
            None => {
                result.added_sources.insert(path.clone());
            }
            Some(old) if old.digest != source.digest => {
                result.changed_sources.insert(path.clone());
            }
            _ => {}
        }
    }
    if let Some(previous) = previous {
        result.removed_sources.extend(
            previous
                .sources
                .keys()
                .filter(|path| !sources.contains_key(*path))
                .cloned(),
        );
    }
    fn units(
        project: &PreprocessedProject,
    ) -> BTreeMap<IncludeOccurrence, (Span, Option<[u8; 32]>)> {
        let mut ordinals = BTreeMap::new();
        project
            .units
            .iter()
            .enumerate()
            .map(|(index, unit)| {
                let ordinal = ordinals.entry(unit.path.clone()).or_insert(0);
                let occurrence = IncludeOccurrence {
                    path: unit.path.clone(),
                    ordinal: *ordinal,
                };
                *ordinal += 1;
                (
                    occurrence,
                    (unit.output_span, project.unit_digests.get(index).copied()),
                )
            })
            .collect()
    }
    let before = previous.map(|old| units(&old.project)).unwrap_or_default();
    let after = units(project);
    let occurrences: BTreeSet<_> = before.keys().chain(after.keys()).cloned().collect();
    for occurrence in occurrences {
        let old = before.get(&occurrence);
        let new = after.get(&occurrence);
        if result.configuration_changed
            || old.map(|item| item.1) != new.map(|item| item.1)
            || old.into_iter().chain(new).any(|item| item.1.is_none())
        {
            result.changed_units.push(UnitChange {
                occurrence,
                previous_span: old.map(|item| item.0),
                current_span: new.map(|item| item.0),
            });
        }
    }
    result
}

/// A conservative namespace is sufficient to prove absence of expansion on a
/// changed line. Scan every #define spelling, including inactive branches and
/// continuations; false positives only disable a splice. This is computed once
/// for a preprocessed generation and persisted with it.
pub(crate) fn macro_namespace(
    project: &PreprocessedProject,
    sources: &BTreeMap<PathBuf, PreparedSource>,
) -> BTreeSet<String> {
    let mut names: BTreeSet<_> = project.final_macros.keys().cloned().collect();
    names.extend([
        "__FILE__".into(),
        "__LINE__".into(),
        "EXCEPTION".into(),
        "REGEX_QUOTE".into(),
        "REGEX_QUOTE_REPLACEMENT".into(),
    ]);
    for source in sources.values() {
        let logical = if source.text.contains("\\\n") || source.text.contains("\\\r\n") {
            std::borrow::Cow::Owned(source.text.replace("\\\r\n", "").replace("\\\n", ""))
        } else {
            std::borrow::Cow::Borrowed(source.text.as_ref())
        };
        for tail in logical.split('#').skip(1) {
            let tail = tail.trim_start_matches(|c: char| c.is_whitespace() || c == char::from(92));
            let Some(tail) = tail.strip_prefix("define") else {
                continue;
            };
            if tail
                .chars()
                .next()
                .is_some_and(|c| !c.is_whitespace() && c != char::from(92))
            {
                continue;
            }
            let tail = tail.trim_start_matches(|c: char| c.is_whitespace() || c == char::from(92));
            let name: String = tail
                .chars()
                .take_while(|c| *c == '_' || c.is_alphanumeric())
                .collect();
            if !name.is_empty() {
                names.insert(name);
            }
        }
    }
    names
}
