//! Uncached Phase 1 frontend. No Salsa database, session, graph or legacy index
//! participates in this path. Directive planning freezes expansion environments;
//! the combined encounter AST supplies scope before the resolved tree is built.

#[path = "frontend_callable_roster.rs"]
mod callable_roster;
#[path = "frontend_procedure_delta.rs"]
mod procedure_delta;
pub use procedure_delta::ProcedureInputDelta;
#[path = "frontend_read_delta.rs"]
mod read_delta;
pub use read_delta::FrontendReadHost;
#[path = "frontend_compile_only.rs"]
mod compile_only;
pub use callable_roster::{
    CallableAbiEntry, CallableAbiGraph, CallableAbiMeaning, CallableAbiRoster, CallableRoster,
    CallableRosterStorage,
};
#[path = "frontend_diagnostic_cursor.rs"]
mod diagnostic_cursor;
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

#[derive(Clone, Debug, Eq, PartialEq)]
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
    stored_candidates: bool,
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
    callable_roster: Arc<CallableRoster>,
    abi_settings_complete: bool,
    body_by_declaration: Arc<HashMap<OccurrenceId, usize>>,
    issued_bodies: Arc<[BodyOccurrence]>,
    issued_body_codes: Arc<[body_code::BodyCodeOwner]>,
    issued_settings: Arc<[Option<Arc<dm_ir::ProcedureMetadata>>]>,
    issued_syntax: Arc<DeclarationSyntax>,
    issued_arena: dm_preprocess::SourceText,
    /// Explicit linker projection. It never changes semantic override priority
    /// or reorders origins independently from their declaration targets.
    pub emission_order: Arc<[OccurrenceId]>,
    source_export_mapping: Arc<source_export_mapping::SourceExportMapping>,
    body_queries: Option<body_queries::BodyQueries>,
    reused_body_queries: bool,
    setting_expression_queries: Option<std::sync::Weak<dyn SettingExpressionQueries>>,
}

impl ColdFrontend {
    pub fn settings_owner_storage(&self) -> &Arc<[Option<Arc<dm_ir::ProcedureMetadata>>]> {
        &self.issued_settings
    }

    /// Aggregate authority is issued only after all current setting receipts agree
    /// with current metadata. Public compatibility mutation declines this path.
    pub fn callable_abi_roster(&self) -> Result<Option<&Arc<CallableAbiRoster>>, String> {
        let roster = self.callable_roster()?;
        Ok(
            (self.abi_settings_complete && Arc::ptr_eq(&self.syntax, &self.issued_syntax))
                .then(|| roster.abi())
                .flatten(),
        )
    }
    /// Borrow only the exact issued source-neutral roster beside current bodies.
    pub fn callable_roster(&self) -> Result<&Arc<CallableRoster>, String> {
        if !Arc::ptr_eq(&self.bodies, &self.issued_bodies)
            || !self.callable_roster.authenticates_tree(&self.snapshot.tree)
        {
            return Err("callable roster differs from current frontend issuance".into());
        }
        Ok(&self.callable_roster)
    }

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
    /// Current parser-issued settings proof, never constructible by callers.
    /// Unissued/custom syntax retains the ordinary extraction path.
    pub fn procedure_settings(
        &self,
        occurrence: &BodyOccurrence,
    ) -> Result<Option<IssuedProcedureSettings<'_>>, Diagnostic> {
        let compact = self.compact_body(occurrence)?;
        let index = self.body_by_declaration[&occurrence.declaration];
        Ok(self
            .issued_settings
            .get(index)
            .and_then(|owner| owner.as_ref())
            .map(|owner| IssuedProcedureSettings { compact, owner }))
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
        self.parse_body_with(occurrence, |input, host| input.obtain(host))
    }
    /// Native callers retain operational failure separately from source syntax.
    pub fn parse_body_checked<'a>(
        &'a self,
        occurrence: &BodyOccurrence,
    ) -> Result<ParsedBody<'a>, BodySyntaxFailure> {
        self.parse_body_with(occurrence, |input, host| input.obtain_checked(host))
    }
    fn parse_body_with<'a, E: From<Diagnostic>>(
        &'a self,
        occurrence: &BodyOccurrence,
        obtain: impl FnOnce(&Arc<BodySyntaxInput>, &dyn BodySyntaxQueries) -> Result<Arc<BodySyntax>, E>,
    ) -> Result<ParsedBody<'a>, E> {
        self.compact_body(occurrence)?;
        let issued = &self.issued_bodies[self.body_by_declaration[&occurrence.declaration]];
        if let Some(queries) = &self.body_queries {
            let ordinal = self.body_by_declaration[&occurrence.declaration];
            let shared = obtain(&queries.inputs[ordinal], queries.host.as_ref())?;
            return Ok(ParsedBody {
                statements: None,
                statement_attempted: false,
                static_receipt: std::sync::OnceLock::new(),
                item: shared.item.clone(),
                parameters: Arc::clone(&shared.parameters),
                shared_syntax: Some(shared),
                issuer: self,
                occurrence: issued,
            });
        }
        let original = self
            .issued_syntax
            .parse_original_procedure(issued.expanded_span, self.body_code(issued)?.identity())
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
            shared_syntax: None,
            statement_attempted: false,
            static_receipt: std::sync::OnceLock::new(),
            item: original.item,
            parameters: Arc::new(original.parameters),
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
            hints: Default::default(),
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
            hints: Default::default(),
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
pub struct IssuedProcedureSettings<'a> {
    compact: ItemView<'a>,
    owner: &'a Arc<dm_ir::ProcedureMetadata>,
}
impl IssuedProcedureSettings<'_> {
    pub fn authenticates(&self, item: ItemView<'_>, metadata: &dm_ir::ProcedureMetadata) -> bool {
        self.compact.same_node(item)
            && (Arc::ptr_eq(&self.owner.settings, &metadata.settings)
                || self.owner.settings.as_ref() == metadata.settings.as_ref())
    }
}
pub struct IssuedBodyInput<'a> {
    issuer: &'a ColdFrontend,
    occurrence: &'a BodyOccurrence,
    compact: ItemView<'a>,
    source: &'a str,
}
impl<'a> IssuedBodyInput<'a> {
    /// Lexical prefilter minted with the exact relative source recipe. This is
    /// only a candidate fact; actual declarations still require semantic capture.
    pub fn may_contain_stored_declarations(&self) -> bool {
        self.occurrence.stored_candidates
    }
    pub fn source(&self) -> &'a str {
        self.source
    }
    /// Current lexical context outside the envelope, issued from the same private arena.
    pub fn termination(&self) -> dm_syntax::BodyTermination {
        dm_syntax::termination_after_with_context(
            &self.issuer.issued_arena,
            self.occurrence.expanded_span.end,
            &|offset| self.issuer.issued_syntax.declaration_header_at(offset),
        )
    }
    pub fn compact(&self) -> ItemView<'_> {
        self.compact
    }
    pub fn occurrence(&self) -> &'a BodyOccurrence {
        self.occurrence
    }
}

#[path = "frontend_body_code.rs"]
mod body_code;
#[path = "frontend_relative_declarations.rs"]
mod relative_declarations;
pub use body_code::IssuedBodyCode;
#[path = "frontend_body_queries.rs"]
mod body_queries;
#[path = "frontend_initializer_source.rs"]
mod initializer_source;
pub use initializer_source::{
    OriginalDeclarationExpressionContext, OriginalDeclarationExpressionInput,
    InitializerExpressionRecipe, OriginalInitializerContext, OriginalInitializerExpression,
    OriginalInitializerExpressionInput,
};
#[path = "frontend_setting_source.rs"]
mod setting_source;
pub use body_queries::{BodySyntax, BodySyntaxInput, BodySyntaxQueries};
#[path = "frontend_setting_queries.rs"]
mod setting_queries;
pub use setting_queries::{
    ReturnAnnotationInput, SettingExpressionInput, SettingExpressionQueries, SettingStatementsInput,
};
#[path = "frontend_body_failure.rs"]
mod body_failure;
pub use body_failure::BodySyntaxFailure;
#[path = "frontend_body_archive.rs"]
mod body_archive;
pub use body_archive::{
    AnnotationCandidateRoster, ArchivedBody, BodyArchive, CheckerVariableProperties,
    OriginalHeaderExpressionHandle, SourceHeaderExpressions, SourceLocalView, SourceParameterView,
};
pub use relative_declarations::BodyCodeIdentity;
pub use relative_declarations::{CurrentSyntaxChunk, DeclarationSyntax, ItemView, RelativeSyntax};
#[path = "body_arena.rs"]
mod body_arena;
pub use body_arena::{BodyArena, BodyArenaStorage};

#[path = "frontend_static_receipt.rs"]
mod static_receipt;
pub use static_receipt::{InitializerFrameReceipt, IssuedStaticPlan, RelativeStaticPlan};
#[path = "frontend_expression_site.rs"]
mod expression_site;

pub struct ParsedBody<'a> {
    static_receipt: std::sync::OnceLock<Result<Arc<IssuedStaticPlan>, String>>,
    item: Item,
    parameters: Arc<dm_syntax::ParameterSignature>,
    shared_syntax: Option<Arc<body_queries::BodySyntax>>,
    statements: Option<Arc<StatementBody>>,
    statement_attempted: bool,
    issuer: &'a ColdFrontend,
    occurrence: &'a BodyOccurrence,
}
/// A typed statement tree issued from an exact lossless procedure parse.
/// Full lossless children are released once the target admits this model.
pub struct StatementBody {
    parsed: dm_syntax::ParsedBody,
    syntax_complete: std::sync::OnceLock<bool>,
    declaration_headers: std::collections::HashSet<(usize, usize)>,
    stored_candidates: bool,
    // LAST: source-free literal credit survives every original payload buffer.
    literal_admission:Option<dm_syntax::BodyLiteralAdmission>,
}
impl Drop for StatementBody{fn drop(&mut self){let parsed=std::mem::take(&mut self.parsed);drop(std::mem::take(&mut self.declaration_headers));dm_syntax::drop_body_literal_syntax(parsed,self.literal_admission.take());}}
impl StatementBody {
    /// Storage completion of this exact native parse, not source/semantic authority.
    pub fn has_native_literal_syntax(&self)->bool{self.literal_admission.is_some()}
    pub fn visit_literal_admission_storage(&self,visit:impl FnMut(usize,usize)){if let Some(a)=&self.literal_admission{a.visit_storage(visit);}}

    /// Recovering syntax can contain Unsupported nodes without a parser
    /// diagnostic (some semantic diagnostics are deferred). Analysis consumers
    /// must reject both, not turn an omitted node into a successful proof.
    /// Shared once per issued syntax owner; compile-only callers stay lazy.
    pub fn syntax_complete(&self) -> bool {
        *self.syntax_complete.get_or_init(|| {
            if !self.parsed.diagnostics.is_empty()
                || self.parsed.pending_bodies.iter().any(|pending| {
                    pending.missing_body()
                        || pending.termination == dm_syntax::BodyTermination::Unknown
                })
            {
                return false;
            }
            struct Coverage<'a> {
                valid: bool,
                parsed: &'a dm_syntax::ParsedBody,
            }
            impl dm_syntax::TypedVisitor for Coverage<'_> {
                fn projected_expression(
                    &mut self,
                    view: dm_syntax::ProjectedExprView<'_>,
                    path: &[dm_syntax::NodeStep],
                ) -> dm_syntax::VisitDecision {
                    // Explicitly shape/identity-only; no original span is used as current.
                    self.expression(view.original(), path)
                }

                fn statement(
                    &mut self,
                    node: &dm_syntax::Statement,
                    _: &[dm_syntax::NodeStep],
                ) -> dm_syntax::VisitDecision {
                    if let dm_syntax::StatementKind::If { condition, .. }
                    | dm_syntax::StatementKind::DoWhile { condition, .. } = &node.kind
                    {
                        if self.parsed.control_origin(condition.span).is_none() {
                            self.valid = false;
                            return dm_syntax::VisitDecision::Stop;
                        }
                    }
                    dm_syntax::VisitDecision::Descend
                }
                fn expression(
                    &mut self,
                    node: &dm_syntax::Expr,
                    _: &[dm_syntax::NodeStep],
                ) -> dm_syntax::VisitDecision {
                    if let dm_syntax::ExprKind::Literal(text) = &node.kind {
                        if text.parts().is_err() {
                            self.valid = false;
                            return dm_syntax::VisitDecision::Stop;
                        }
                    }
                    dm_syntax::VisitDecision::Descend
                }
            }
            let mut coverage = Coverage {
                valid: true,
                parsed: &self.parsed,
            };
            let report = dm_syntax::visit_statements(&self.parsed.statements, &mut coverage);
            coverage.valid && report.unsupported_statements == 0
        })
    }
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
        dm_syntax::StatementView::from_parsed(&self.parsed)
    }
}
impl ParsedBody<'_> {
    pub fn source_locals(&self) -> Result<SourceLocalView<'_>, String> {
        self.issuer
            .validate_parsed_body(self, self.occurrence)
            .map_err(|e| e.message)?;
        let syntax = self
            .statements
            .as_deref()
            .ok_or("local source body syntax was not issued")?;
        body_archive::checked_source_locals(
            &self.issuer.snapshot.tree,
            self.occurrence,
            syntax,
            &self.issuer.issued_arena,
        )
    }

    pub fn source_parameters(&self) -> Result<SourceParameterView<'_>, String> {
        self.issuer
            .validate_parsed_body(self, self.occurrence)
            .map_err(|e| e.message)?;
        body_archive::checked_source_parameters(
            &self.issuer.snapshot.tree,
            self.occurrence,
            &self.item,
            &self.parameters,
            &self.issuer.issued_arena,
        )
    }
    /// Borrow optional roots only after the original callable/header receipt
    /// and selected original metadata have been bound to this exact occurrence.
    pub fn source_header_expressions(&self) -> Result<SourceHeaderExpressions<'_>, String> {
        self.source_parameters()?.header_expressions()
    }
    pub fn checker_parameters(
        &self,
        profile: dm_ir::PackedU128,
    ) -> Result<SourceParameterView<'_>, String> {
        self.issuer
            .snapshot
            .tree
            .validate_checker_builtin_profile(profile)
            .map_err(|e| format!("parameter checker profile: {e:?}"))?;
        self.source_parameters()
    }
    pub fn parameter_storage(&self) -> &Arc<dm_syntax::ParameterSignature> {
        &self.parameters
    }
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
    /// Kind4 already carries its checked shared model. One-shot native demand
    /// uses ONLY the attached settings provider/direct permit, never a new Db or
    /// a full-body query attachment. Unattached compatibility demand with a
    /// proved empty settings roster keeps the ordinary statement parser path.
    pub(super) fn admit_statements_checked(
        mut self,
        supported: fn(&[dm_syntax::Statement]) -> bool,
    ) -> Result<Self, BodySyntaxFailure> {
        if self.shared_syntax.is_some() {
            return Ok(self.admit_statements(supported));
        }
        let proof = self
            .issuer
            .procedure_settings(self.occurrence)
            .map_err(BodySyntaxFailure::Syntax)?;
        let proof = proof.ok_or_else(|| {
            BodySyntaxFailure::Syntax(internal("original statement settings receipt unavailable"))
        })?;
        // A native provider also admits ordinary literal children/statics after
        // an ACTUAL checked body request, even when this body has no Set.
        // Unattached compatibility frontends retain the ordinary fast path.
        if proof.owner.settings.is_empty() && self.issuer.setting_expression_queries.is_none() {
            return Ok(self.admit_statements(supported));
        }
        let statements =
            self.issuer
                .setting_statements(self.occurrence, &mut self.item, supported)?;
        self.statement_attempted = true;
        self.statements = Some(statements);
        Ok(self)
    }
    pub(super) fn admit_statements(
        mut self,
        supported: fn(&[dm_syntax::Statement]) -> bool,
    ) -> Self {
        self.statement_attempted = true;
        self.statements = if let Some(shared) = self.shared_syntax.take() {
            let statements = Arc::clone(&shared.statements);
            if statements.parsed().diagnostics.is_empty()
                && supported(&statements.parsed().statements)
            {
                self.item.children = Vec::new();
            }
            Some(statements)
        } else {
            Some(body_archive::parse_statements(
                &mut self.item,
                &self.issuer.issued_arena,
                &self.issuer.issued_syntax,
                supported,
            ))
        };

        self
    }
}

struct Captured<'a, P> {
    provider: &'a P,
    sources: RefCell<BTreeMap<PathBuf, dm_preprocess::SourceText>>,
}

impl<P: SourceProvider> SourceProvider for Captured<'_, P> {
    fn acquired_source(
        &self,
        path: &Path,
    ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
        let acquired = self.provider.acquired_source(path)?;
        if let Some(acquired) = &acquired {
            self.sources
                .borrow_mut()
                .insert(path.to_owned(), acquired.prepared().original().clone());
        }
        Ok(acquired)
    }
    fn source_acquisition(
        &self,
        path: &Path,
        text: &dm_preprocess::SourceText,
    ) -> Option<dm_preprocess::AcquiredSource> {
        // Projection only: never call read/prepared_source to obtain evidence.
        self.provider.source_acquisition(path, text)
    }
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
    fn revision(&self) -> Option<u64> {
        self.provider.revision()
    }
    fn changes_since(&self, revision: u64) -> Option<Arc<std::collections::BTreeSet<PathBuf>>> {
        self.provider.changes_since(revision)
    }
}

/// Build a resolved source model from a captured provider. Map/resource consumers
/// receive the ordered non-text ledger and terminal FILE_DIR domain afterward.
#[cfg(test)]
#[path = "frontend_ast_capacity.rs"]
mod ast_capacity;
#[path = "frontend_diagnostic_preparation.rs"]
mod diagnostic_preparation;
#[path = "frontend_pipeline.rs"]
mod pipeline;
pub use diagnostic_preparation::{DiagnosticFrontend, DiagnosticSourceView};
pub use pipeline::{
    build, build_for_checker_diagnostics, build_for_checker_diagnostics_with_state,
    build_with_config, build_with_executor, build_with_executor_and_semantic_state,
    build_with_executor_and_semantic_state_for_policy, build_with_expansion_memo,
    build_with_executor_and_semantic_state_for_policy_checked,
    build_for_checker_diagnostics_with_state_checked,
};
#[path = "frontend_semantic_state.rs"]
mod semantic_state;
#[path = "frontend_symbol_catalog.rs"]
pub(crate) mod symbol_catalog;
pub use crate::owner_normalization::NormalizationStorageView;
pub(crate) use semantic_state::DiagnosticRetainedRecords;
pub use semantic_state::RetainedSemanticTree;
#[path = "frontend_grammar_roster.rs"]
mod grammar_roster;
pub use grammar_roster::{GrammarAnswer, GrammarDescriptors, GrammarQuery};
#[path = "frontend_declaration_state.rs"]
mod declaration_state;
pub(crate) use declaration_state::Contribution;
pub use declaration_state::{
    ChunkSourceAnswer, DeclarationContributionView, DeclarationRequest, DeclarationRetentionStats,
    DeclarationStorageView,
};
#[path="frontend_declaration_demand.rs"]
mod declaration_demand;
pub use declaration_demand::FrontendBuildFailure;
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
        item.declaration_cursor = item
            .declaration_cursor
            .and_then(|at| at.checked_add(offset));
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
            item.declaration_cursor = item
                .declaration_cursor
                .and_then(|at| at.checked_add(offset));
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

#[path = "frontend_source_export_mapping.rs"]
mod source_export_mapping;
pub use source_export_mapping::{
    SourceDeclarationPolicyCursor, SourceExportMapping, SourceNoteOrigin, SourcePolicyLineOrigin,
};
#[path = "frontend_source_projection.rs"]
mod source_projection;
struct Mapping<'a> {
    projection: source_projection::CurrentSourceProjection,
    plan: &'a DirectivePlan,
    expanded: &'a ExpandedRegions,
    files: &'a [SourceFile],
    by_path: &'a HashMap<PathBuf, FileId>,
    /// Where the last two questions were answered: declarations and bodies are asked about in
    /// source order, so the next answer is almost always the same file and the same or a nearby row.
    hints: MappingHints,
}
#[derive(Default)]
struct MappingHints {
    file: std::cell::Cell<Option<(usize, FileId)>>,
    row: std::cell::Cell<usize>,
}

impl Mapping<'_> {
    fn origin(&self, offset: usize) -> Option<ExpandedOriginView<'_>> {
        let index = self
            .expanded
            .origins
            .partition_point_near(self.hints.row.get(), |origin| {
                origin.output_span.end <= offset
            });
        self.hints.row.set(index);
        self.expanded
            .origins
            .get(index)
            .or_else(|| self.expanded.origins.last())
    }
    /// The file of a path, remembering the last answer by the path allocation (every row of a
    /// file shares one).
    fn file_of(&self, path: &Arc<PathBuf>) -> Option<FileId> {
        let pointer = Arc::as_ptr(path) as usize;
        if let Some((known, file)) = self.hints.file.get() {
            if known == pointer {
                return Some(file);
            }
        }
        let file = *self.by_path.get(path.as_ref())?;
        self.hints.file.set(Some((pointer, file)));
        Some(file)
    }
    fn debug_site(&self, offset: usize) -> Option<(Arc<str>, usize)> {
        let origin = self.origin(offset)?;
        let occurrence = self.plan.regions[origin.region].occurrence;
        let file = self.file_of(origin.origin.path)?;
        source_span(file, origin.source_span).ok()?;
        Some((
            self.plan.occurrences[occurrence].semantic_path.clone(),
            origin.origin.source_line,
        ))
    }
    fn output(&self, offset: usize) -> Option<SourceLocation> {
        let origin = self.origin(offset)?;
        let occurrence = self.plan.regions[origin.region].occurrence;
        source_export_mapping::source_location_in(
            self.file_of(origin.origin.path)?,
            origin,
            &self.plan.occurrences[occurrence].path,
            &self.plan.occurrences[occurrence].semantic_path,
            self.plan.regions[origin.region].encounter_ordinal,
            occurrence,
            self.include_chain(occurrence),
        )
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

#[path = "frontend_duplicate_diagnostics.rs"]
mod duplicate_diagnostics;

fn resolution_error(
    error: &SnapshotError,
    skeletons: &[Skeleton],
    origins: &[crate::Provenance],
    mapping: &Mapping<'_>,
    opaque_engine: bool,
    symbols: &SymbolTable,
    intrinsics: &[crate::IntrinsicMember],
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
            // A partial engine inventory cannot prove a built-in absent; a name
            // that is no BYOND built-in anywhere is still the author's error.
            SnapshotError::Tree(crate::TreeError::MissingOverride { owner, name, kind })
                if opaque_engine
                    && (intrinsics.iter().any(|member| {
                        member.name == *name
                            && member.kind == *kind
                            && authored_ancestry(*owner, skeletons, symbols).contains(&member.owner)
                    }) || symbols.text(*name).is_none_or(|name| {
                        let plain = plain_datum_owner(*owner, skeletons, symbols);
                        match kind {
                            MemberKind::Var => dm_ir::builtin_names::is_builtin_var_in(plain, name),
                            MemberKind::Proc | MemberKind::Verb => {
                                dm_ir::builtin_names::is_builtin_proc_in(plain, name)
                            }
                        }
                    })) =>
            {
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
        message: resolution_message(error, symbols),
        location,
    }
}

#[path = "frontend_resolution_messages.rs"]
mod resolution_messages;
use resolution_messages::{authored_ancestry, plain_datum_owner, resolution_message};

fn collect_bodies(
    syntax: &DeclarationSyntax,
    tree: &crate::SemanticTree,
    declarations: &HashMap<usize, (OccurrenceId, MemberId)>,
    mapping: &Mapping<'_>,
    bodies: &mut Vec<BodyOccurrence>,
    settings: &mut Vec<Option<Arc<dm_ir::ProcedureMetadata>>>,
    codes: &mut Vec<Arc<BodyCodeIdentity>>,
) -> Result<(), Vec<Diagnostic>> {
    for recipe in syntax.body_recipes() {
        codes.push(recipe.code_identity());
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
        settings.push(recipe.settings_owner().and_then(|issued| {
            let current = tree.member(declaration.1)?.metadata.procedure.as_ref()?;
            (Arc::ptr_eq(&issued.settings, &current.settings)
                || issued.settings.as_ref() == current.settings.as_ref())
            .then(|| Arc::clone(current))
        }));
        bodies.push(BodyOccurrence {
            stored_candidates: recipe.stored_candidates(),
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

pub(crate) use declaration_state::shared::SharedContributionStore;

#[cfg(test)]
#[path = "frontend_settings_receipt_tests.rs"]
mod settings_receipt_tests;

#[path = "frontend_initial_setting_prefix.rs"]
mod initial_setting_prefix;
pub use initial_setting_prefix::InitialSettingPrefix;

#[cfg(test)]
mod primary_cursor_rebase_tests {
    use super::*;
    #[test]
    fn cold_compaction_and_warm_rebase_shift_the_same_primary_cursor() {
        let source = "/datum/probe\n    var/item = 1\n    var/other\n";
        let parsed = dm_syntax::parse_declaration_skeleton(source);
        assert!(parsed.diagnostics.is_empty());
        let mut shifted = parsed.items.clone();
        shift_items(&mut shifted, 117);
        let compacted = compact_declarations(parsed.items, 117);
        for (cold, warm) in compacted[0].children.iter().zip(&shifted[0].children) {
            assert_eq!(cold.declaration_cursor, warm.declaration_cursor);
            assert!(cold.declaration_cursor.unwrap() >= 117);
        }
        assert_eq!(
            compacted[0].children[0].declaration_cursor,
            source.find('=').map(|at| at + 117)
        );
    }
    #[test]
    fn later_top_level_type_chunks_do_not_fail_relative_cursor_binding() {
        struct Source;
        impl dm_preprocess::SourceProvider for Source {
            fn read(&self, _: &Path) -> Result<String, String> {
                Ok("/datum/first\n    var/value\n/datum/second\n    var/other\n".into())
            }
        }
        build(
            Path::new("primary-offset.dm"),
            &Source,
            &Default::default(),
            1,
        )
        .unwrap();
    }
}

#[path = "frontend_unchanged_program.rs"]
mod unchanged_program;

impl<'frontend> ParsedBody<'frontend> {
    /// Preserve the existing original root owner before ABI preparation consumes
    /// this wrapper. The handle retains no Item/Expr/occurrence clone or parser.
    pub fn share_header_expressions(
        &self,
    ) -> Result<OriginalHeaderExpressionHandle<'frontend>, String> {
        self.source_parameters()?;
        body_archive::capture_header_expression_handle(
            self.issuer,
            self.occurrence,
            Arc::clone(&self.parameters),
        )
    }
}

#[cfg(test)]
#[path="frontend_declaration_checked_tests.rs"]
mod declaration_checked_tests;
