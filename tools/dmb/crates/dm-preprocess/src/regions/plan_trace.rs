//! Reuse records of the ordered directive pass (doc/incremental_core.md, migration step 3).
//!
//! The pass is a serial state machine, but an include subtree is a pure function of its files,
//! the state it starts from (macro environment, open conditionals, `FILE_DIR` stack, `#pragma
//! multiple` set, which files were already included) and the include directive that reaches it.
//! Each subtree the pass visits leaves a [`SubtreeRecord`]; the next pass adopts a subtree whose
//! inputs are all unchanged by copying its occurrences, regions and ordered items (renumbered by
//! the distance the subtree moved) and jumping to its recorded outgoing state. A changed file, a
//! changed incoming state or a changed include context makes only that subtree run again, and its
//! outgoing state decides whether the subtrees after it can still be adopted (early cutoff).
use super::{DefinitionOrigin, MacroEnvironment};
use crate::{Conditional, Macro};
use std::collections::BTreeSet;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

/// Everything the pass carries from one include directive to the next.
#[derive(Clone, Debug, Default)]
pub(super) struct PassState {
    pub(super) environment: MacroEnvironment,
    pub(super) conditionals: Vec<Conditional>,
    pub(super) file_dirs: Vec<PathBuf>,
    pub(super) file_dir_definitions: Vec<Macro>,
    pub(super) file_dir_origins: Vec<Option<DefinitionOrigin>>,
    pub(super) repeatable: BTreeSet<PathBuf>,
}
impl PassState {
    /// Whether a subtree that started from `self` starts the same from `other`.
    pub(super) fn same(&self, other: &Self) -> bool {
        self.environment.same_bindings(&other.environment) && self.same_apart_from_macros(other)
    }
    /// Everything but the macro environment is the same.
    pub(super) fn same_apart_from_macros(&self, other: &Self) -> bool {
        self.conditionals == other.conditionals
            && self.file_dirs == other.file_dirs
            && self.file_dir_definitions == other.file_dir_definitions
            && self.file_dir_origins == other.file_dir_origins
            && self.repeatable == other.repeatable
    }
}

/// One decision of the include-once rule: the file, whether the set already held it, and whether
/// the visit went on to read it (a file may be visited again after `#pragma multiple`).
#[derive(Clone, Debug)]
pub(super) struct VisitEntry {
    pub(super) path: Arc<PathBuf>,
    pub(super) was_visited: bool,
    pub(super) proceeded: bool,
}

/// One include subtree as the pass left it. Extents are counts; positions live in the entry.
#[derive(Clone, Debug)]
pub(super) struct SubtreeRecord {
    pub(super) occurrences: usize,
    pub(super) regions: usize,
    pub(super) items: usize,
    pub(super) state_in: PassState,
    pub(super) state_out: PassState,
    /// Semantic path of the subtree root: every descendant's spelling derives from it.
    pub(super) root_semantic_path: Arc<str>,
    /// Every visit decision the subtree made, in order: the file and whether the include-once set
    /// already held it. The first decision per file is the subtree's dependency on its start.
    pub(super) visits: Vec<VisitEntry>,
    /// Files whose text the pass read (the non-suppressed visits).
    pub(super) reads: Vec<Arc<PathBuf>>,
    /// Every path the subtree adds to the plan's dependency set (reads and non-text includes).
    pub(super) dependencies: Vec<PathBuf>,
    /// Every macro name the subtree's directives read or wrote (sorted, unique): the part of the incoming macro
    /// environment the subtree depends on. A later pass whose environment differs only in other names adopts the
    /// subtree with those bindings carried into its regions (`DirectivePass::adopt_previous_inner`).
    pub(super) tested: Arc<[Arc<str>]>,
}

/// A subtree record with the position it had in the plan that produced it.
#[derive(Clone, Debug)]
pub(super) struct TraceEntry {
    pub(super) key: u128,
    pub(super) occurrence: usize,
    pub(super) region: usize,
    pub(super) item: usize,
    pub(super) record: Arc<SubtreeRecord>,
}

/// Identity of an include occurrence across passes: the file and how many occurrences of that
/// file the pass had created before it.
pub(super) fn trace_key(path: &std::path::Path, nth: u32) -> u128 {
    use xxhash_rust::xxh3::Xxh3;
    let mut hash = Xxh3::new();
    hash.update(path.as_os_str().as_encoded_bytes());
    hash.update(&nth.to_le_bytes());
    hash.digest128()
}

/// Entries sorted by occurrence, so the entries inside a subtree are one binary-searched run.
/// Opaque: the reuse records a plan carries for the next one.
#[derive(Debug, Default)]
pub struct PlanTrace {
    pub(super) entries: Vec<TraceEntry>,
    index: HashMap<u128, usize>,
}
impl PlanTrace {
    pub(super) fn new(mut entries: Vec<TraceEntry>) -> Self {
        entries.sort_by_key(|entry| entry.occurrence);
        let index = entries
            .iter()
            .enumerate()
            .map(|(position, entry)| (entry.key, position))
            .collect();
        Self { entries, index }
    }
    pub(super) fn get(&self, key: u128) -> Option<&TraceEntry> {
        self.index.get(&key).map(|position| &self.entries[*position])
    }
    /// The entries whose root lies in `[first, first + count)`, in occurrence order.
    pub(super) fn within(&self, first: usize, count: usize) -> &[TraceEntry] {
        let start = self.entries.partition_point(|entry| entry.occurrence < first);
        let end = self
            .entries
            .partition_point(|entry| entry.occurrence < first + count);
        &self.entries[start..end]
    }
}

/// What the incremental pass reused, for the expansion stage and the request log.
#[derive(Clone, Debug, Default)]
pub struct PlanReuse {
    /// For every region of the new plan: the region of the previous plan it is a verbatim copy of.
    pub regions: Vec<Option<usize>>,
    /// Include subtrees adopted whole.
    pub subtrees: usize,
    /// Of those, adopted although the macro environment differed in bindings they never read.
    pub rebased_subtrees: usize,
    /// Regions of rebased subtrees (not in `regions`): the previous region each copies and the macro names whose
    /// bindings differ from its. The expansion reuse copies the previous expansion when it read none of them.
    pub rebased_regions: std::collections::HashMap<usize, (usize, Arc<[Arc<str>]>)>,
    /// Occurrences, regions and items adopted inside them.
    pub occurrences: usize,
    pub copied_regions: usize,
    /// Changed subtrees planned again by the patch (the rest of the plan is the previous one).
    pub replanned: usize,
    /// For a patched plan: the files whose text and line starts were requested again (every other
    /// file is the previous plan's, at the same place). `None` for a plan the ordered pass made.
    pub rebuilt_files: Option<Vec<PathBuf>>,
    /// Regions the pass built again that equal the previous plan's region at the same place.
    pub matched_regions: usize,
    /// Subtrees a previous record existed for but whose inputs changed, by first failing check.
    pub declined: PlanDeclines,
    /// Where the pass spent its time.
    pub timings: PlanTimings,
}

#[derive(Clone, Copy, Debug, Default)]
pub struct PlanTimings {
    /// Adopting subtrees: the whole check and copy, of which the provider touches and the state
    /// comparison, and the copy itself.
    pub adopt: std::time::Duration,
    pub touch: std::time::Duration,
    pub state: std::time::Duration,
    pub copy: std::time::Duration,
    /// Creating include occurrences (path, spelling and cursor bookkeeping).
    pub occurrences: std::time::Duration,
    /// Visiting subtrees that were not adopted, recording included.
    pub visit: std::time::Duration,
    /// Matching regions built again against the previous plan's.
    pub matching: std::time::Duration,
    /// Patching: planning the changed subtrees, then assembling the plan around them.
    pub replan: std::time::Duration,
    pub assemble: std::time::Duration,
}

#[derive(Clone, Copy, Debug, Default)]
pub struct PlanDeclines {
    pub files: usize,
    pub state: usize,
    pub context: usize,
    pub visits: usize,
}
