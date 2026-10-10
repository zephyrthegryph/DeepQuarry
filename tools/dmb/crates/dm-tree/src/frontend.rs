//! Uncached Phase 1 frontend. No Salsa database, session, graph or legacy index
//! participates in this path. Directive planning freezes expansion environments;
//! the combined encounter AST supplies scope before the resolved tree is built.

#[path = "frontend_compile_only.rs"]
mod compile_only;
#[path = "parserwire.rs"]
mod parserwire;

use crate::{MemberId, MemberKind, OccurrenceId, Skeleton, SnapshotError, Target, TreeSnapshot};
use dm_ir::{FileId, Span, SymbolTable};
use dm_preprocess::regions::{
    plan_regions, DirectivePlan, ExpandedOriginView, ExpandedRegions, MacroExpansion, NonTextKind,
};
use dm_preprocess::SourceProvider;
use dm_syntax::{AstFile, Item, ItemKind};
use std::cell::RefCell;
use std::collections::{BTreeMap, HashMap};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};

#[cfg(test)]
#[path = "frontend_tests.rs"]
mod tests;

#[derive(Clone, Debug)]
pub struct SourceFile {
    pub id: FileId,
    pub path: Arc<PathBuf>,
    pub text: dm_preprocess::SourceText,
    /// False for non-text inputs awaiting their consumer or a failed source read.
    pub captured: bool,
    pub line_starts: Arc<[usize]>,
}

#[derive(Clone, Debug)]
pub struct SourceLocation {
    pub span: Span,
    pub path: Arc<PathBuf>,
    pub semantic_path: Arc<str>,
    pub line: usize,
    pub encounter_ordinal: usize,
    pub include_occurrence: usize,
    pub include_chain: Arc<[usize]>,
    pub macro_expansions: Arc<Vec<MacroExpansion>>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DiagnosticStage {
    Preprocess,
    Syntax,
    Declaration,
    Resolution,
    Internal,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DiagnosticKind {
    SourceError,
    UnsupportedModel,
    Internal,
}

#[derive(Clone, Debug)]
pub struct Diagnostic {
    pub kind: DiagnosticKind,
    pub stage: DiagnosticStage,
    pub message: String,
    pub location: Option<SourceLocation>,
}

/// Bodies refer into the current expanded source arena, independently of the semantic
/// tree. Editing executable statements changes this occurrence, not tree identity.
#[derive(Clone, Debug)]
pub struct BodyOccurrence {
    pub declaration: OccurrenceId,
    pub member: MemberId,
    pub ast_path: Arc<[usize]>,
    pub expanded_span: dm_syntax::Span,
    pub source: SourceLocation,
    /// Current source origins for retained setting/guard/context headers, in
    /// compact encounter order. These never enter procedure semantic identity.
    pub setting_context_origins: Arc<[SourceLocation]>,
}

/// Measured uncached stages. Provider lookup latency belongs to directive planning;
/// caller input snapshot capture and executable lowering are outside these values.
#[derive(Clone, Debug, Default)]
pub struct FrontendTimings {
    pub directive_planning: Duration,
    pub expansion: Duration,
    pub declaration_parsing: Duration,
    pub tree_resolution: Duration,
    pub provenance_and_body_indexing: Duration,
    pub total: Duration,
    pub declaration_reuse: DeclarationReuseStats,
}
/// Worker durations are summed across workers, not stage elapsed.
#[derive(Clone, Debug, Default)]
pub struct DeclarationReuseStats {
    pub chunks: usize,
    pub region_hits: usize,
    pub independent_hits: usize,
    pub facts_hits: usize,
    pub parsed_chunks: usize,
    pub descriptor_scan: Duration,
    pub worker_lookup_decode_and_parse: Duration,
    pub worker_fresh_facts: Duration,
    pub ordered_merge: Duration,
}

/// Decoder-independent engine input. Only hierarchy is materialized as type
/// skeletons. Presence/slot inventory is deliberately incomplete: binary member
/// records do not supply decoded types, defaults, settings or signatures here.
#[derive(Clone, Debug)]
pub struct EngineSeed {
    /// Exact caller-pinned engine input identity; never a fabricated typed meaning.
    pub identity: u128,
    pub symbols: SymbolTable,
    pub hierarchy: crate::EngineHierarchy,
    pub intrinsics: Arc<[crate::IntrinsicMember]>,
    pub fields: Arc<[dm_ir::OpaqueFieldBase]>,
}

#[derive(Clone, Copy)]
pub struct FrontendConfig<'a> {
    pub workers: usize,
    pub engine: Option<&'a EngineSeed>,
    pub observer: Option<&'a dyn Fn(FrontendProgress)>,
}
impl std::fmt::Debug for FrontendConfig<'_> {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("FrontendConfig")
            .field("workers", &self.workers)
            .field("engine", &self.engine.map(|seed| seed.identity))
            .field("observer", &self.observer.is_some())
            .finish()
    }
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum FrontendStage {
    DirectivePlanning,
    Expansion,
    SourceIndexing,
    DeclarationParsing,
    DeclarationOrigins,
    TreeResolution,
    BodyIndexing,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ProgressKind {
    Started,
    Advanced,
    Completed,
}
#[derive(Clone, Copy, Debug)]
pub struct FrontendProgress {
    pub stage: FrontendStage,
    pub kind: ProgressKind,
    pub elapsed: Duration,
    pub completed_items: usize,
    pub total_items: usize,
}
fn observe(
    config: FrontendConfig<'_>,
    stage: FrontendStage,
    kind: ProgressKind,
    elapsed: Duration,
    completed_items: usize,
    total_items: usize,
) {
    if let Some(observer) = config.observer {
        observer(FrontendProgress {
            stage,
            kind,
            elapsed,
            completed_items,
            total_items,
        });
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EngineModelStatus {
    pub identity: u128,
    pub schema: u128,
    pub type_count: usize,
    pub known_intrinsic_members: usize,
    pub member_catalog_complete: bool,
    pub typed_member_metadata_decoded: bool,
}

#[derive(Clone, Debug)]
pub struct ColdFrontend {
    pub timings: FrontendTimings,
    pub engine: Option<EngineModelStatus>,
    pub plan: DirectivePlan,
    pub expanded: ExpandedRegions,
    pub syntax: Arc<DeclarationSyntax>,
    /// Original grammar groups, before flattened declaration normalization.
    pub allocation_ledger: Arc<crate::allocation_ledger::AllocationLedger>,
    pub snapshot: TreeSnapshot,
    pub files: Arc<[SourceFile]>,
    source_by_path: Arc<HashMap<PathBuf, FileId>>,
    pub bodies: Arc<[BodyOccurrence]>,
    body_by_declaration: Arc<HashMap<OccurrenceId, usize>>,
    issued_bodies: Arc<[BodyOccurrence]>,
    issued_syntax: Arc<DeclarationSyntax>,
    issued_arena: dm_preprocess::SourceText,
    /// Explicit linker projection. It never changes semantic override priority
    /// or reorders origins independently from their declaration targets.
    pub emission_order: Arc<[OccurrenceId]>,
}

impl ColdFrontend {
    /// Borrow the issuer's declaration/settings projection without parsing an
    /// executable body. Occurrence and syntax addresses are checked together;
    /// unsupported setting ancestors and their original spans remain intact.
    pub fn compact_body(&self, occurrence: &BodyOccurrence) -> Result<ItemView<'_>, Diagnostic> {
        let reject = || Diagnostic {
            kind: DiagnosticKind::Internal,
            stage: DiagnosticStage::Internal,
            location: Some(occurrence.source.clone()),
            message: "body occurrence differs from compact frontend capture".into(),
        };
        if !Arc::ptr_eq(&self.syntax, &self.issued_syntax)
            || !self.expanded.text.same_view(&self.issued_arena)
        {
            return Err(reject());
        }
        let issued = self
            .body_by_declaration
            .get(&occurrence.declaration)
            .and_then(|index| self.issued_bodies.get(*index))
            .ok_or_else(reject)?;
        if issued.member != occurrence.member
            || issued.ast_path != occurrence.ast_path
            || issued.expanded_span != occurrence.expanded_span
        {
            return Err(reject());
        }
        let item = self
            .syntax
            .item_path(&occurrence.ast_path)
            .ok_or_else(reject)?;
        if item.span() != occurrence.expanded_span
            || !matches!(item.kind(), ItemKind::Proc | ItemKind::Verb)
        {
            return Err(reject());
        }
        Ok(item)
    }
    /// Borrow exact captured procedure bytes without parsing executable syntax.
    /// This certifies source identity only; consumers still need their own
    /// immutable ABI/compiler receipt before skipping semantic preparation.
    pub fn body_input<'a>(
        &'a self,
        occurrence: &BodyOccurrence,
    ) -> Result<IssuedBodyInput<'a>, Diagnostic> {
        let compact = self.compact_body(occurrence)?;
        let issued = &self.issued_bodies[self.body_by_declaration[&occurrence.declaration]];
        let source = self
            .issued_arena
            .get(issued.expanded_span.range())
            .ok_or_else(|| internal("issued body lies outside captured arena"))?;
        Ok(IssuedBodyInput {
            issuer: self,
            occurrence: issued,
            compact,
            source,
        })
    }
    pub fn validate_body_input(
        &self,
        input: &IssuedBodyInput<'_>,
        occurrence: &BodyOccurrence,
    ) -> Result<(), Diagnostic> {
        let compact = self.compact_body(occurrence)?;
        let issued = &self.issued_bodies[self.body_by_declaration[&occurrence.declaration]];
        if !std::ptr::eq(self, input.issuer)
            || !std::ptr::eq(issued, input.occurrence)
            || !compact.same_node(input.compact)
        {
            return Err(internal(
                "body input was issued by a different frontend occurrence",
            ));
        }
        Ok(())
    }
    pub fn parse_body<'a>(
        &'a self,
        occurrence: &BodyOccurrence,
    ) -> Result<ParsedBody<'a>, Diagnostic> {
        self.compact_body(occurrence)?;
        let issued = &self.issued_bodies[self.body_by_declaration[&occurrence.declaration]];
        let item = dm_syntax::parse_proc_at_span(&self.issued_arena, issued.expanded_span)
            .map_err(|error| Diagnostic {
                kind: syntax_kind(error.kind),
                stage: DiagnosticStage::Syntax,
                location: self
                    .location(error.span.start)
                    .or_else(|| Some(occurrence.source.clone())),
                message: error.message,
            })?;
        Ok(ParsedBody {
            statements: None,
            statement_attempted: false,
            static_receipt: std::sync::OnceLock::new(),
            item,
            issuer: self,
            occurrence: issued,
        })
    }
    pub fn validate_parsed_body(
        &self,
        parsed: &ParsedBody<'_>,
        occurrence: &BodyOccurrence,
    ) -> Result<(), Diagnostic> {
        self.compact_body(occurrence)?;
        if !std::ptr::eq(self, parsed.issuer) || !std::ptr::eq(parsed.occurrence, occurrence) {
            return Err(internal(
                "parsed body was issued by a different frontend occurrence",
            ));
        }
        Ok(())
    }
    pub fn body(&self, occurrence: &BodyOccurrence) -> Result<Item, Diagnostic> {
        self.parse_body(occurrence).map(|parsed| parsed.item)
    }

    /// Current logical source span for a token in the joined expanded stream.
    /// Macro traces retain invocation/definition ancestry; character-level inverse
    /// substitution mapping is not claimed by this logical-line projection.
    pub fn location(&self, expanded_offset: usize) -> Option<SourceLocation> {
        Mapping {
            projection: Default::default(),
            plan: &self.plan,
            expanded: &self.expanded,
            files: &self.files,
            by_path: &self.source_by_path,
        }
        .output(expanded_offset)
    }

    /// Exact logical debug path/line without allocating diagnostic provenance.
    /// Uses the same captured origin and validity checks as `location`.
    pub fn debug_site(&self, expanded_offset: usize) -> Option<(Arc<str>, usize)> {
        Mapping {
            projection: Default::default(),
            plan: &self.plan,
            expanded: &self.expanded,
            files: &self.files,
            by_path: &self.source_by_path,
        }
        .debug_site(expanded_offset)
    }
    pub fn source(&self, id: FileId) -> Option<&SourceFile> {
        self.files.get(id.index())
    }

    pub fn maps(&self) -> impl Iterator<Item = &Path> {
        self.plan.non_text(NonTextKind::Map)
    }

    pub fn skins(&self) -> impl Iterator<Item = &Path> {
        self.plan.non_text(NonTextKind::Skin)
    }
}

/// Immutable owned frontend revision. Hosts may share/move it but cannot mutate
/// the enclosed public compatibility model or expose its Arc for replacement.
#[derive(Clone, Debug)]
pub struct FrontendRevision(Arc<ColdFrontend>);
impl FrontendRevision {
    pub fn new(frontend: ColdFrontend) -> Self {
        Self(Arc::new(frontend))
    }
    pub fn issuance(&self) -> FrontendIssuance {
        FrontendIssuance(Arc::downgrade(&self.0))
    }
}
impl std::ops::Deref for FrontendRevision {
    type Target = ColdFrontend;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}
/// A weak identity retains only the fixed frontend control block after payload
/// destruction, never a strong source arena or copied provenance ledger.
#[derive(Clone, Debug)]
pub struct FrontendIssuance(std::sync::Weak<ColdFrontend>);
impl FrontendIssuance {
    pub fn matches(&self, revision: &FrontendRevision) -> bool {
        std::sync::Weak::ptr_eq(&self.0, &Arc::downgrade(&revision.0))
    }
}

/// A bounded executable parse tied to an immutable source capture. Callers may
/// inspect its AST, but cannot replace it or manufacture its source authority.
pub struct IssuedBodyInput<'a> {
    issuer: &'a ColdFrontend,
    occurrence: &'a BodyOccurrence,
    compact: ItemView<'a>,
    source: &'a str,
}
impl IssuedBodyInput<'_> {
    pub fn source(&self) -> &str {
        self.source
    }
    pub fn compact(&self) -> ItemView<'_> {
        self.compact
    }
    pub fn occurrence(&self) -> &BodyOccurrence {
        self.occurrence
    }
}

#[path = "frontend_relative_declarations.rs"]
mod relative_declarations;
pub use relative_declarations::{CurrentSyntaxChunk, DeclarationSyntax, ItemView, RelativeSyntax};
#[path = "body_arena.rs"]
mod body_arena;
pub use body_arena::{BodyArena, BodyArenaStorage};

#[path = "frontend_static_receipt.rs"]
mod static_receipt;
pub use static_receipt::{IssuedStaticPlan, RelativeStaticPlan};
#[path = "frontend_expression_site.rs"]
mod expression_site;

pub struct ParsedBody<'a> {
    static_receipt: std::sync::OnceLock<Result<Arc<IssuedStaticPlan>, String>>,
    item: Item,
    statements: Option<Arc<StatementBody>>,
    statement_attempted: bool,
    issuer: &'a ColdFrontend,
    occurrence: &'a BodyOccurrence,
}
/// A typed statement tree issued from an exact lossless procedure parse.
/// Full lossless children are released once the target admits this model.
pub struct StatementBody {
    parsed: dm_syntax::ParsedBody,
    declaration_headers: std::collections::HashSet<(usize, usize)>,
    stored_candidates: bool,
}
impl StatementBody {
    pub fn parsed(&self) -> &dm_syntax::ParsedBody {
        &self.parsed
    }
    pub fn declaration_header_storage(&self) -> (usize, usize) {
        (
            self.declaration_headers.len(),
            self.declaration_headers.capacity(),
        )
    }
    pub fn may_contain_stored_declarations(&self) -> bool {
        self.stored_candidates
    }
    pub(crate) fn declaration_headers(&self) -> &std::collections::HashSet<(usize, usize)> {
        &self.declaration_headers
    }
    pub fn view(&self) -> dm_syntax::StatementView<'_> {
        dm_syntax::StatementView::all(&self.parsed.statements)
    }
}
impl ParsedBody<'_> {
    pub fn item(&self) -> &Item {
        &self.item
    }
    pub fn occurrence(&self) -> &BodyOccurrence {
        self.occurrence
    }
    /// Consume this issued parse without copying its executable items.
    pub fn into_item(self) -> Item {
        self.item
    }
    pub fn statement_attempted(&self) -> bool {
        self.statement_attempted
    }
    pub fn statement_body(&self) -> Option<&StatementBody> {
        self.statements.as_deref()
    }
    pub fn shared_statement_body(&self) -> Option<Arc<StatementBody>> {
        self.statements.clone()
    }
    pub fn into_parts(self) -> (Item, Option<Arc<StatementBody>>) {
        (self.item, self.statements)
    }
    pub(super) fn admit_statements(
        mut self,
        supported: fn(&[dm_syntax::Statement]) -> bool,
    ) -> Self {
        self.statement_attempted = true;
        let parsed = dm_syntax::parse_body_items(&self.item.children);
        fn headers(items: &[Item], result: &mut std::collections::HashSet<(usize, usize)>) {
            for item in items {
                if item.header.trim_start().starts_with("var/") {
                    result.insert((item.header_span.start, item.header_span.end));
                }
                headers(&item.children, result);
            }
        }
        let stored_candidates =
            crate::procedure_statics::items_may_contain_stored_declarations(&self.item.children);
        let mut declaration_headers = std::collections::HashSet::new();
        // This roster certifies only extracted stored-local declarations. The
        // existing negative proof excludes all such origins; ordinary locals
        // need neither header traversal nor HashSet backing allocation.
        if stored_candidates {
            headers(&self.item.children, &mut declaration_headers);
        }
        if parsed.diagnostics.is_empty() && supported(&parsed.statements) {
            self.item.children = Vec::new();
        }
        self.statements = Some(Arc::new(StatementBody {
            parsed,
            declaration_headers,
            stored_candidates,
        }));

        self
    }
}

struct Captured<'a, P> {
    provider: &'a P,
    sources: RefCell<BTreeMap<PathBuf, dm_preprocess::SourceText>>,
}

impl<P: SourceProvider> SourceProvider for Captured<'_, P> {
    fn prepared_source(
        &self,
        path: &Path,
    ) -> Option<Arc<dm_preprocess::regions::prepared_source::PreparedSource>> {
        let prepared = self.provider.prepared_source(path)?;
        self.sources
            .borrow_mut()
            .insert(path.to_owned(), prepared.original().clone());
        Some(prepared)
    }
    fn read(&self, path: &Path) -> Result<String, String> {
        let source = self.provider.read(path)?;
        self.sources.borrow_mut().insert(
            path.to_owned(),
            dm_preprocess::SourceText::from(source.as_str()),
        );
        Ok(source)
    }
}

/// Build a resolved source model from a captured provider. Map/resource consumers
/// receive the ordered non-text ledger and terminal FILE_DIR domain afterward.
#[cfg(test)]
#[path = "frontend_ast_capacity.rs"]
mod ast_capacity;
#[path = "frontend_pipeline.rs"]
mod pipeline;
pub use pipeline::{
    build, build_with_config, build_with_executor, build_with_executor_and_semantic_state,
    build_with_expansion_memo,
};
#[path = "frontend_semantic_state.rs"]
mod semantic_state;
#[path = "frontend_symbol_catalog.rs"]
pub(crate) mod symbol_catalog;
pub use crate::owner_normalization::NormalizationStorageView;
pub use semantic_state::RetainedSemanticTree;
#[path = "frontend_grammar_roster.rs"]
mod grammar_roster;
pub use grammar_roster::{GrammarAnswer, GrammarDescriptors, GrammarQuery};
#[path = "frontend_declaration_state.rs"]
mod declaration_state;
pub(crate) use declaration_state::Contribution;
pub use declaration_state::{
    DeclarationContributionView, DeclarationRetentionStats, DeclarationStorageView,
};
#[path = "frontend_parse.rs"]
mod declaration_parse;
#[cfg(test)]
use declaration_parse::parse_declarations;
use declaration_parse::ParsedDeclarations;

#[path = "chunkfacts.rs"]
mod chunkfacts;

fn syntax_kind(kind: dm_syntax::DiagnosticKind) -> DiagnosticKind {
    if kind == dm_syntax::DiagnosticKind::Unsupported {
        DiagnosticKind::UnsupportedModel
    } else {
        DiagnosticKind::SourceError
    }
}

fn internal(message: &str) -> Diagnostic {
    Diagnostic {
        kind: DiagnosticKind::Internal,
        stage: DiagnosticStage::Internal,
        message: message.into(),
        location: None,
    }
}

fn shift_items(items: &mut [Item], offset: usize) {
    for item in items {
        item.span.start += offset;
        item.span.end += offset;
        item.header_span.start += offset;
        item.header_span.end += offset;
        shift_items(&mut item.children, offset);
    }
}

fn compact_declarations(items: Vec<Item>, offset: usize) -> Vec<Item> {
    items
        .into_iter()
        .map(|mut item| {
            item.span.start += offset;
            item.span.end += offset;
            item.header_span.start += offset;
            item.header_span.end += offset;
            if matches!(item.kind, ItemKind::Proc | ItemKind::Verb) {
                item.children = crate::settings::compact_setting_items(item.children);
            }
            item.children = compact_declarations(item.children, offset);
            item
        })
        .collect()
}

fn source_span(file: FileId, span: dm_syntax::Span) -> Result<Span, Vec<Diagnostic>> {
    Ok(Span {
        file,
        start: u32::try_from(span.start).map_err(|_| vec![internal("source span exceeds u32")])?,
        end: u32::try_from(span.end).map_err(|_| vec![internal("source span exceeds u32")])?,
    })
}

#[path = "frontend_source_projection.rs"]
mod source_projection;
struct Mapping<'a> {
    projection: source_projection::CurrentSourceProjection,
    plan: &'a DirectivePlan,
    expanded: &'a ExpandedRegions,
    files: &'a [SourceFile],
    by_path: &'a HashMap<PathBuf, FileId>,
}

impl Mapping<'_> {
    fn origin(&self, offset: usize) -> Option<ExpandedOriginView<'_>> {
        let index = self
            .expanded
            .origins
            .partition_point(|origin| origin.output_span.end <= offset);
        self.expanded
            .origins
            .get(index)
            .or_else(|| self.expanded.origins.last())
    }
    fn debug_site(&self, offset: usize) -> Option<(Arc<str>, usize)> {
        let origin = self.origin(offset)?;
        let occurrence = self.plan.regions[origin.region].occurrence;
        let file = *self.by_path.get(origin.origin.path.as_ref())?;
        source_span(file, origin.source_span).ok()?;
        Some((
            self.plan.occurrences[occurrence].semantic_path.clone(),
            origin.origin.source_line,
        ))
    }
    fn output(&self, offset: usize) -> Option<SourceLocation> {
        let origin = self.origin(offset)?;
        let occurrence = self.plan.regions[origin.region].occurrence;
        let file = *self.by_path.get(origin.origin.path.as_ref())?;
        let span = source_span(file, origin.source_span).ok()?;
        Some(SourceLocation {
            span,
            path: self.plan.occurrences[occurrence].path.clone(),
            semantic_path: self.plan.occurrences[occurrence].semantic_path.clone(),
            line: origin.origin.source_line,
            encounter_ordinal: self.plan.regions[origin.region].encounter_ordinal,
            include_occurrence: occurrence,
            include_chain: self.include_chain(occurrence),
            macro_expansions: Arc::clone(origin.macro_expansions),
        })
    }
    fn line(&self, path: &Path, line: usize) -> Option<SourceLocation> {
        let file = *self.by_path.get(path)?;
        let source = &self.files[file.index()];
        let start = *source
            .line_starts
            .get(line.saturating_sub(1))
            .unwrap_or(&source.text.len());
        let end = *source.line_starts.get(line).unwrap_or(&source.text.len());
        let occurrence = self
            .plan
            .occurrences
            .iter()
            .position(|occurrence| occurrence.path.as_path() == path)?;
        Some(SourceLocation {
            span: source_span(file, dm_syntax::Span::new(start, end)).ok()?,
            path: self.plan.occurrences[occurrence].path.clone(),
            semantic_path: self.plan.occurrences[occurrence].semantic_path.clone(),
            line,
            encounter_ordinal: self
                .plan
                .regions
                .iter()
                .find(|region| {
                    region.occurrence == occurrence
                        && region.source_span.start <= start
                        && start <= region.source_span.end
                })
                .map_or(occurrence, |region| region.encounter_ordinal),
            include_occurrence: occurrence,
            include_chain: self.include_chain(occurrence),
            macro_expansions: Arc::new(Vec::new()),
        })
    }
    fn chain(&self, mut occurrence: usize) -> Vec<usize> {
        let mut chain = vec![occurrence];
        while let Some(parent) = self.plan.occurrences[occurrence].parent {
            chain.push(parent);
            occurrence = parent;
        }
        chain.reverse();
        chain
    }
}

fn resolution_error(
    error: &SnapshotError,
    skeletons: &[Skeleton],
    origins: &[crate::Provenance],
    mapping: &Mapping<'_>,
    opaque_engine: bool,
) -> Diagnostic {
    let index = match &error {
        SnapshotError::Tree(crate::TreeError::Duplicate { owner, name, kind }
            | crate::TreeError::MissingOverride { owner, name, kind }) => skeletons.iter().rposition(|skeleton| matches!(skeleton,
                Skeleton::Member { owner: found_owner, name: found_name, kind: found_kind, .. } if found_owner == owner && found_name == name && found_kind == kind)),
        SnapshotError::Tree(crate::TreeError::ConflictingParent(path)
            | crate::TreeError::InheritanceCycle(path)) => skeletons.iter().rposition(|skeleton| matches!(skeleton, Skeleton::Type { path: found, explicit_parent: Some(_), .. } if found == path)).or_else(|| skeletons.iter().rposition(|skeleton| matches!(skeleton, Skeleton::Type { path: found, .. } if found == path))),
        SnapshotError::Tree(crate::TreeError::MissingParent(path)) => skeletons.iter().rposition(|skeleton| matches!(skeleton, Skeleton::Type { explicit_parent: Some(parent), .. } if parent == path)),
        _ => None,
    };
    let location = index
        .and_then(|index| origins.get(index))
        .and_then(|origin| {
            let source = mapping.files.get(origin.span.file.index())?;
            let line = source
                .line_starts
                .partition_point(|start| *start <= origin.span.start as usize);
            mapping.line(&source.path, line)
        });
    Diagnostic {
        kind: match &error {
            SnapshotError::Tree(crate::TreeError::MissingOverride { .. }) if opaque_engine => {
                DiagnosticKind::UnsupportedModel
            }
            SnapshotError::Inventory(_) => DiagnosticKind::Internal,
            SnapshotError::Origins(_)
            | SnapshotError::Tree(
                crate::TreeError::Symbol(_)
                | crate::TreeError::ConflictingIntrinsicField { .. }
                | crate::TreeError::UnknownSymbol(_)
                | crate::TreeError::TooManyNodes,
            ) => DiagnosticKind::Internal,
            _ => DiagnosticKind::SourceError,
        },
        stage: DiagnosticStage::Resolution,
        message: format!("{error:?}"),
        location,
    }
}

fn collect_bodies(
    syntax: &DeclarationSyntax,
    declarations: &HashMap<usize, (OccurrenceId, MemberId)>,
    mapping: &Mapping<'_>,
    bodies: &mut Vec<BodyOccurrence>,
) -> Result<(), Vec<Diagnostic>> {
    for recipe in syntax.body_recipes() {
        let span = recipe.span();
        let declaration = declarations
            .get(&span.start)
            .copied()
            .ok_or_else(|| vec![internal("procedure body has no resolved declaration")])?;
        let source = mapping
            .output(span.start)
            .ok_or_else(|| vec![internal("procedure body has no source origin")])?;
        let setting_context_origins = recipe
            .settings()
            .map(|span| {
                mapping
                    .output(span.start)
                    .ok_or_else(|| vec![internal("procedure setting has no current source origin")])
            })
            .collect::<Result<Vec<_>, _>>()?;
        bodies.push(BodyOccurrence {
            declaration: declaration.0,
            member: declaration.1,
            ast_path: recipe.path(),
            expanded_span: span,
            source,
            setting_context_origins: setting_context_origins.into(),
        });
    }
    Ok(())
}

#[cfg(test)]
mod worker_facts_tests {
    use super::*;
    #[test]
    fn worker_declaration_facts_equal_complete_ast_adapter_and_allocation_order() {
        struct Source(String);
        impl dm_preprocess::SourceProvider for Source {
            fn read(&self, _: &std::path::Path) -> Result<String, String> {
                Ok(self.0.clone())
            }
        }
        let mut text = String::new();
        for index in 0..750 {
            text.push_str(&format!("/datum/unit{index}\n    var\n        list/obj/items\n        value = {index}\n    proc\n        read(arg = 2)\n            if(1)\n                set waitfor = 0\n            return value\n"));
        }
        text.push_str(
            "/datum/unit0/child\n    parent_type = /datum/unit1\n/datum/unit0/value = 7\n",
        );
        let source = Source(text);
        let plan = dm_preprocess::regions::plan_regions(
            std::path::Path::new("project.dme"),
            &source,
            &std::collections::BTreeMap::new(),
        );
        let expanded = dm_preprocess::regions::expand_regions_text(&plan, 1);
        for workers in [1, 2] {
            let parsed = parse_declarations(
                &expanded,
                FrontendConfig {
                    workers,
                    engine: None,
                    observer: None,
                },
                None,
            )
            .unwrap();
            assert!(parsed.diagnostics.is_empty());
            assert!(parsed.declaration_errors.is_empty());
            let ast = AstFile {
                items: parsed
                    .syntax
                    .items()
                    .map(|item| item.materialize())
                    .collect(),
                ..AstFile::default()
            };
            let mut expected =
                crate::from_ast(&ast, SymbolTable::default(), FileId(0), 0, 0).unwrap();
            let ledger =
                crate::allocation_ledger::capture(&ast.items, "/", &mut expected.symbols).unwrap();
            assert!(
                parsed
                    .adapted
                    .skeletons
                    .iter()
                    .eq(expected.skeletons.iter()),
                "worker skeleton order differs"
            );
            assert!(
                parsed.adapted.origins == expected.origins,
                "worker origins differ"
            );
            assert!(
                parsed.adapted.symbols.ordered() == expected.symbols.ordered(),
                "worker spelling dictionary differs"
            );
            assert!(
                parsed.allocation_ledger.events == ledger.events,
                "worker allocation order differs"
            );
        }
    }
}
