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
mod path_prefix;
pub use directive_memo::{DirectiveRecord, DIRECTIVE_VERSION};
mod environment;
pub mod prepared_source;
pub use environment::MacroEnvironment;
mod expansion;
mod expansion_input;
mod joined_text;
pub use expansion_input::ExpansionInputs;
mod origin_arena;
pub mod region_memo;
pub use region_memo::storage::ExpansionStorageView;
mod trace_arena;
pub use origin_arena::{ExpandedOriginArena, ExpandedOriginView, OriginIter, OriginView};
pub use region_memo::{
    ExpansionMemo, ExpansionRecord, FragmentRecord, EXPANSION_VERSION, FRAGMENT_VERSION,
};
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
    pub parent: Option<usize>,
    pub directive_span: Span,
    pub directive_line: usize,
    pub suppressed: bool,
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
impl IncludeOccurrence {
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
    pub text: crate::SourceText,
}

/// Contiguous active text with one exact expansion environment. A region may
/// contain multiple segments when a define/undef changes its state mid-region.
#[derive(Clone, Debug)]
pub struct ExpansionSegment {
    pub lines: Vec<RegionLine>,
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
    pub segments: Vec<ExpansionSegment>,
    pub effects: Vec<MacroEffect>,
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

#[derive(Clone, Debug, Default)]
pub struct DirectivePlan {
    pub source_texts: BTreeMap<PathBuf, crate::SourceText>,
    pub occurrences: Vec<IncludeOccurrence>,
    pub regions: Vec<IncludeRegion>,
    pub items: Vec<OrderedItem>,
    pub dependencies: BTreeSet<PathBuf>,
    /// Original decoded-source line starts, reused from lexical preparation.
    pub source_line_starts: BTreeMap<PathBuf, Arc<[usize]>>,
    pub diagnostics: Vec<Diagnostic>,
    /// Parallel vector identifying each directive diagnostic's encounter item.
    pub diagnostic_ordinals: Vec<usize>,
    pub final_macros: BTreeMap<String, Macro>,
    /// Terminal resource domain; resource literals do not use token encounter
    /// FILE_DIR snapshots (see the unique-name paired fixtures).
    pub file_dirs: Vec<PathBuf>,
    pub project_dir: PathBuf,
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
    directives::plan_with_memo(project, provider, defines, Some(memo))
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
pub fn relative_filesystem_path(path: &Path, root: &Path) -> Option<PathBuf> {
    let path = path_prefix::equivalent_prefix(canonical_path(path));
    let root = path_prefix::equivalent_prefix(canonical_path(root));
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
    pub macro_expansions: Arc<Vec<MacroExpansion>>,
}
