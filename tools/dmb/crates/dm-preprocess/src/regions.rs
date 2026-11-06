//! Ordered directive planning and parallel expansion with caller-owned optional memoization.
//!
//! Source regions preserve directive encounter order separately from DME text
//! emission order. Macro snapshots share persistent ordered-map roots and Arc replacement bodies.
//! Even token-pasting retains the complete environment without duplicating it.

use crate::{Diagnostic, Macro, Origin, SourceProvider};
use dm_syntax::Span;
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Component, Path, PathBuf};
use std::sync::Arc;

mod directive_memo;
mod directives;
mod generation;
pub use generation::{
    GenerationDeclareOmission, GenerationDirectivePlan, GenerationOmissions, GenerationOriginalSources,
};
mod intern_wire;
mod plan_trace;
mod segment_lines;
pub use plan_trace::{PlanReuse, PlanTimings, PlanTrace};
mod path_prefix;
pub use directive_memo::{DirectiveRecord, DIRECTIVE_VERSION};
mod environment;
pub mod prepared_source;
pub use environment::MacroEnvironment;
pub use segment_lines::SegmentLines;
mod reuse;
pub use reuse::{expand_regions_reusing, expansions_equal, plans_equal, ExpansionReuse};
mod expansion;
mod expansion_input;
mod joined_text;
pub use expansion_input::{share_expansion_inputs, ExpansionInputs};
mod origin_arena;
pub mod region_memo;
pub use region_memo::storage::ExpansionStorageView;
mod trace_arena;
pub use origin_arena::{ExpandedOriginArena, ExpandedOriginView, OriginIter, OriginView};
pub use region_memo::{
    ExpansionMemo, ExpansionRecord, FragmentRecord, EXPANSION_VERSION, FRAGMENT_VERSION,
};
#[cfg(test)]
mod reuse_tests;
#[cfg(test)]
mod tests;

pub use expansion::{
    expand_regions, expand_regions_text, expand_regions_text_with_executor,
    expand_regions_text_with_memo, expand_regions_with_executor, ExpandedRegions,
};

/// An accepted or suppressed include directive, including its parent chain.
#[derive(Clone, Debug)]
pub struct IncludeOccurrence {
    pub path: Arc<PathBuf>,
    /// Include spelling emitted by __FILE__, distinct from the access identity.
    pub semantic_path: Arc<str>,
    // Exact original entry argument only on the real root. Source-coordinate
    // data; not source content, policy or an alternate registration index.
    original_entry: Option<Arc<PathBuf>>,
    pub parent: Option<usize>,
    pub directive_span: Span,
    pub directive_line: usize,
    pub suppressed: bool,
    // Issued only by the planner's actual typed NonText dispatch; no suffix inference.
    non_text_kind:Option<NonTextKind>,
    return_cursor: Option<IncludeReturnCursor>,
    eof_cursor_line: Option<usize>,
    eof_cursor_encounter: Option<usize>,
}

/// Current directive planner authority; offsets are decoded physical source bytes.
#[derive(Clone, Copy, Debug)]
pub struct IncludeReturnCursor {
    parent_occurrence: usize,
    decoded_offset: usize,
    directive_anchor_line: Option<usize>,
    encounter_ordinal: Option<usize>,
}
impl IncludeReturnCursor {
    /// Ordered item-stream position issued immediately after the child returns.
    pub fn encounter_ordinal(self) -> Option<usize> {
        self.encounter_ordinal
    }
    pub fn parent_occurrence(self) -> usize {
        self.parent_occurrence
    }
    pub fn decoded_offset(self) -> usize {
        self.decoded_offset
    }
    /// Completed parent planning certified a following omitted directive.
    pub fn directive_anchor_line(self) -> Option<usize> {
        self.directive_anchor_line
    }
}
/// Completed logical reader EOF, not a physical source byte point.
#[derive(Clone, Copy, Debug)]
pub struct LogicalEofCursor {
    line: usize,
    encounter: usize,
}
impl LogicalEofCursor {
    pub fn line(self) -> usize {
        self.line
    }
    pub fn encounter(self) -> usize {
        self.encounter
    }
}
impl IncludeOccurrence {
    pub fn original_entry_path(&self)->Option<&Arc<PathBuf>>{self.original_entry.as_ref()}

    pub fn non_text_kind(&self)->Option<NonTextKind>{self.non_text_kind}
    pub fn logical_eof_cursor(&self) -> Option<LogicalEofCursor> {
        Some(LogicalEofCursor {
            line: self.eof_cursor_line?,
            encounter: self.eof_cursor_encounter?,
        })
    }

    pub fn return_cursor(&self) -> Option<IncludeReturnCursor> {
        self.return_cursor
    }
    /// Logical reader EOF after completed planning, including unterminated last lines.
    /// Ordered item-stream position issued at successful occurrence EOF.
    pub fn eof_cursor_encounter(&self) -> Option<usize> {
        self.eof_cursor_encounter
    }
    pub fn eof_cursor_line(&self) -> Option<usize> {
        self.eof_cursor_line
    }
}

/// One logical source line; offsets refer to the original decoded source.
#[derive(Clone, Debug)]
pub struct RegionLine {
    pub source_span: Span,
    pub source_line: usize,
    /// Physical lines this logical line joins (backslash continuations).
    pub source_lines: usize,
    pub text: crate::SourceText,
}

/// Contiguous active text with one exact expansion environment. A region may
/// contain multiple segments when a define/undef changes its state mid-region.
#[derive(Clone, Debug)]
pub struct ExpansionSegment {
    pub lines: SegmentLines,
    pub macros: MacroEnvironment,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DefinitionOrigin {
    pub path: Arc<PathBuf>,
    pub source_span: Span,
    pub source_line: usize,
}

/// One actually executed macro expansion, with its replacement ancestry. The
/// invocation span is relative to the expansion input, not an invented absolute
/// byte range when that input came from a replacement or argument rescan.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MacroExpansion {
    pub name: Arc<str>,
    pub invocation_span: Span,
    pub replacement_chain: Arc<[Arc<str>]>,
    pub definition: Option<DefinitionOrigin>,
}

#[derive(Clone, Debug)]
pub enum MacroEffect {
    Define { name: String, definition: Macro },
    Undef { name: String },
    PushFileDir { path: PathBuf, definition: Macro },
    PopFileDir,
}

/// Maximal source interval between include directives. Directives and inactive
/// text remain inside its source extent, even when no text is emitted.
#[derive(Clone, Debug)]
pub struct IncludeRegion {
    pub occurrence: usize,
    pub source_span: Span,
    pub encounter_ordinal: usize,
    pub manifest_source: bool,
    /// Shared, so a region reused by a later plan is a pointer copy, not a copy of its lines.
    pub segments: Arc<Vec<ExpansionSegment>>,
    pub effects: Arc<Vec<MacroEffect>>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NonTextKind {
    Map,
    Skin,
}

#[derive(Clone, Debug)]
pub enum OrderedItem {
    Text(usize),
    NonText {
        occurrence: usize,
        kind: NonTextKind,
    },
}

mod original_plan_paths;
pub use original_plan_paths::SourceTexts;
mod source_acquisitions;
pub use source_acquisitions::SourceAcquisitions;

#[derive(Clone, Debug, Default)]
pub struct DirectivePlan {
    pub initial_environment:crate::InitialEnvironment,
    /// Per-current-include acquisition binding, separate from interned text.
    pub source_acquisitions: SourceAcquisitions,
    pub source_texts: BTreeMap<PathBuf, crate::SourceText>,
    pub occurrences: Vec<IncludeOccurrence>,
    pub regions: Vec<IncludeRegion>,
    pub items: Vec<OrderedItem>,
    pub dependencies: BTreeSet<PathBuf>,
    /// Original decoded-source line starts, reused from lexical preparation.
    pub source_line_starts: BTreeMap<PathBuf, Arc<[usize]>>,
    pub diagnostics: Vec<Diagnostic>,
    /// `#warn` directives in active code, in encounter order; never failures.
    pub warnings: Vec<Diagnostic>,
    /// Parallel vector identifying each directive diagnostic's encounter item.
    pub diagnostic_ordinals: Vec<usize>,
    pub final_macros: BTreeMap<String, Macro>,
    /// Terminal resource domain; resource literals do not use token encounter
    /// FILE_DIR snapshots (see the unique-name paired fixtures).
    pub file_dirs: Vec<PathBuf>,
    pub project_dir: PathBuf,
    /// Reuse records of every include subtree this plan visited or reused, so the next request
    /// can adopt unchanged subtrees whole (`plan_regions_incremental`).
    pub trace: Option<Arc<plan_trace::PlanTrace>>,
    /// The provider's input revision this plan was made at (`SourceProvider::revision`).
    pub input_revision: Option<u64>,
    /// The caller's defines the plan was made with. A plan of other defines is a base for the ordered pass (it adopts
    /// the subtrees that read none of the differing macros), never for the changed-files patch.
    pub defines: BTreeMap<String, String>,
}


/// Borrowed original-source geometry. This is data, with no compiler-input
/// completeness, directive interpretation or expansion capability.
#[derive(Clone, Copy)]
pub struct SourcePlanGeometry<'a> {
    pub source_acquisitions:&'a SourceAcquisitions,
    pub source_texts: SourceTexts<'a>,
    pub occurrences: &'a [IncludeOccurrence],
    pub regions: &'a [IncludeRegion],
    pub source_line_starts: &'a BTreeMap<PathBuf, Arc<[usize]>>,
    pub project_dir: &'a Path,
}
impl DirectivePlan {
    pub fn source_geometry(&self) -> SourcePlanGeometry<'_> {
        SourcePlanGeometry {source_acquisitions:&self.source_acquisitions,source_texts:SourceTexts::ordinary(&self.source_texts), occurrences:&self.occurrences, regions:&self.regions, source_line_starts:&self.source_line_starts, project_dir:&self.project_dir}
    }
}

/// Sequentially interpret directives. Actual text expansion is a separate,
/// independently schedulable step after all region environments are frozen.
pub fn plan_regions<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
) -> DirectivePlan {
    directives::plan(project, provider, defines)
}

pub fn plan_regions_with_memo<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
    memo: &dyn ExpansionMemo,
) -> DirectivePlan {
    directives::plan_with_memo(project, provider, defines, Some(memo)).0
}

/// The ordered directive pass, adopting every include subtree of `previous` whose files, incoming
/// state and include context are unchanged instead of interpreting it again. The result equals a
/// full pass; `PlanReuse` says which regions are verbatim copies of the previous plan's.
pub fn plan_regions_incremental<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
    memo: Option<&dyn ExpansionMemo>,
    previous: Option<&DirectivePlan>,
) -> (DirectivePlan, PlanReuse) {
    directives::plan_incremental(project, provider, defines, memo, previous)
}

impl DirectivePlan {
    /// Source declaration projection follows directive encounter order.
    /// BYOND groups some output tables by owner; that is a LINK policy, not
    /// permission to defer all manifest declarations in the grammar pipeline.
    pub fn emission_regions(&self) -> impl Iterator<Item = usize> + '_ {
        self.items.iter().filter_map(|item| match item {
            OrderedItem::Text(index) => Some(*index),
            _ => None,
        })
    }


    /// The original checker reports the actual environment-relative opened
    /// spelling, whereas native compilation preserves its existing semantic
    /// include operand. Both originate from the SAME issued occurrence/root.
    pub(crate) fn original_main(&self,occurrence:usize)->bool{
        let Some(entry)=self.occurrences.first().and_then(IncludeOccurrence::original_entry_path)else{return false};
        let row=&self.occurrences[occurrence];
        row.parent.is_none() || entry.parent().unwrap_or_else(||Path::new("")).join(row.semantic_path.as_ref()).as_path()==entry.as_path()
    }
    pub(crate) fn expansion_path(&self,occurrence:usize)->String{
        if self.initial_environment==crate::InitialEnvironment::Native5161687{return self.semantic_path(occurrence)}
        let row=&self.occurrences[occurrence];
        let Some(entry)=self.occurrences.first().and_then(IncludeOccurrence::original_entry_path)else{return self.semantic_path(occurrence)};
        if row.parent.is_none(){entry.display().to_string()}else{entry.parent().unwrap_or_else(||Path::new("")).join(row.semantic_path.as_ref()).display().to_string()}
    }
    pub fn semantic_path(&self, occurrence: usize) -> String {
        self.occurrences[occurrence].semantic_path.to_string()
    }

    pub fn non_text(&self, kind: NonTextKind) -> impl Iterator<Item = &Path> {
        self.items.iter().filter_map(move |item| match item {
            OrderedItem::NonText {
                occurrence,
                kind: item_kind,
            } if *item_kind == kind => Some(self.occurrences[*occurrence].path.as_path()),
            _ => None,
        })
    }
}

/// Lexical normalization preserves unresolved leading parents. It never
/// silently drops an external relative path component.
pub fn canonical_path(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for component in path.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => match out.components().next_back() {
                Some(Component::Normal(_)) => {
                    out.pop();
                }
                Some(Component::RootDir | Component::Prefix(_)) => {}
                _ => out.push(".."),
            },
            other => out.push(other.as_os_str()),
        }
    }
    out
}

/// Compare lexical filesystem containment without changing provider keys or
/// authored provenance. Only equivalent ordinary Windows drive spellings unify.
/// Candidate-index key only. It does not authorize an alias or rewrite a
/// provider key: an admitted alias still needs the provider's private receipt.
/// Equal keys are EXACTLY an empty relative_filesystem_path comparison.
pub fn filesystem_comparison_key(path: &Path) -> PathBuf {
    path_prefix::equivalent_prefix(canonical_path(path))
}

pub fn relative_filesystem_path(path: &Path, root: &Path) -> Option<PathBuf> {
    let path = filesystem_comparison_key(path);
    let root = filesystem_comparison_key(root);
    path.strip_prefix(root).ok().map(Path::to_path_buf)
}

/// Decode the literal operand using the ordered directive pass's exact path
/// spelling policy. This does not expand macros or select conditional includes.
pub fn literal_include_path(operand: &str) -> Option<PathBuf> {
    crate::parse_include(operand)
}

/// Expanded line provenance, retaining the source interval for analysis tools.
#[derive(Clone, Debug)]
pub struct ExpandedOrigin {
    pub origin: Origin,
    pub output_span: Span,
    pub source_span: Span,
    pub region: usize,
    pub macro_expansions: Arc<Box<[MacroExpansion]>>,
}

mod origin_byte_layout;
pub use origin_byte_layout::OriginalByteCursor;

// Resource-only transformed allocation owner; no source/model/EOF role.
mod original_source_arena;

mod original_lexical_frame;
pub use original_lexical_frame::OriginalLexicalFrameIdentity;

mod original_literal_source;
pub use original_literal_source::{OriginalLiteralSourceBinding,OriginalLiteralSourceView};

mod original_batch_execution;
mod original_batch_primary;
pub use original_batch_execution::{OriginalBatchSyntaxHost,OriginalBatchExecution};

mod original_stream_consumer;
pub use original_stream_consumer::{OriginalDemandDelivery,OriginalFormalTokenStream,OriginalPrimaryStreamConsumer};
pub use original_formal_source::{OriginalFormalMemberRecovery,OriginalFormalActualEnd};

// The shared value judge consumes already-issued roots; it has no source producer.
mod original_condition_value;

mod original_raw_frame;

mod original_token_factory;

mod original_raw_points;

mod original_raw_inputs;

mod original_macro_source;

mod original_output_queue;

mod original_ordinary_output;

mod original_token_pump;

mod original_conditional;

mod original_driver;
mod original_raw_geometry;
mod original_file_path;
mod original_define_demand;
mod original_directive_arguments;
mod original_directive_dispatch;
mod original_literal_owner;
mod original_native_projection;
mod original_trace_frames;
mod original_conditional_pump;
mod original_condition_tokens;
mod origin_raw_rows;

mod original_output_trace;

mod original_prepared_output;
mod original_final_output;

mod original_formal_source;

mod original_primary_controller;

mod original_current_location;

mod original_rich_notices;

pub use original_rich_notices::{OriginalRichNotices,OriginalNoticeView,OriginalNoticeNotes,OriginalNoticePlace,OriginalNoticeSeverity};

mod original_define_history;

mod original_diagnostic_plan;
pub use original_diagnostic_plan::{OriginalDiagnosticPlan,OriginalDiagnosticStorage};

mod original_plan_owner;
mod original_source_controller;
mod original_generation;
pub use original_generation::{OriginalGenerationProduct,OriginalRootOpenObserver,OriginalRootOpenFailureLoan};

mod original_conditional_history;
pub use original_conditional_history::OriginalConditionalRange;
