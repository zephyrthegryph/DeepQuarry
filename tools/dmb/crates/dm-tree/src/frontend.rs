//! Uncached Phase 1 frontend. No Salsa database, session, graph or legacy index
//! participates in this path. Directive planning freezes expansion environments;
//! the combined encounter AST supplies scope before the resolved tree is built.

#[path = "parserwire.rs"]
mod parserwire;

use crate::{MemberId, MemberKind, OccurrenceId, Skeleton, SnapshotError, Target, TreeSnapshot};
use dm_ir::{FileId, Span, SymbolTable};
use dm_preprocess::regions::{
    expand_regions_text, plan_regions, DirectivePlan, ExpandedOrigin, ExpandedRegions,
    MacroExpansion, NonTextKind,
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
    pub text: Arc<str>,
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
    pub syntax: Arc<AstFile>,
    /// Original grammar groups, before flattened declaration normalization.
    pub allocation_ledger: Arc<crate::allocation_ledger::AllocationLedger>,
    pub snapshot: TreeSnapshot,
    pub files: Arc<[SourceFile]>,
    source_by_path: Arc<HashMap<PathBuf, FileId>>,
    pub bodies: Arc<[BodyOccurrence]>,
    body_by_declaration: Arc<HashMap<OccurrenceId, usize>>,
    issued_bodies: Arc<[BodyOccurrence]>,
    issued_syntax: Arc<AstFile>,
    issued_arena: Arc<str>,
    /// Explicit linker projection. It never changes semantic override priority
    /// or reorders origins independently from their declaration targets.
    pub emission_order: Arc<[OccurrenceId]>,
}

impl ColdFrontend {
    /// Borrow the issuer's declaration/settings projection without parsing an
    /// executable body. Occurrence and syntax addresses are checked together;
    /// unsupported setting ancestors and their original spans remain intact.
    pub fn compact_body(&self, occurrence: &BodyOccurrence) -> Result<&Item, Diagnostic> {
        let reject = || Diagnostic {
            kind: DiagnosticKind::Internal,
            stage: DiagnosticStage::Internal,
            location: Some(occurrence.source.clone()),
            message: "body occurrence differs from compact frontend capture".into(),
        };
        if !Arc::ptr_eq(&self.syntax, &self.issued_syntax)
            || !Arc::ptr_eq(&self.expanded.text, &self.issued_arena)
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
        let mut items = self.syntax.items.as_slice();
        let mut selected = None;
        for index in occurrence.ast_path.iter() {
            let item = items.get(*index).ok_or_else(reject)?;
            selected = Some(item);
            items = &item.children;
        }
        let item = selected.ok_or_else(reject)?;
        if item.span != occurrence.expanded_span
            || !matches!(item.kind, ItemKind::Proc | ItemKind::Verb)
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
            || !std::ptr::eq(compact, input.compact)
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
            plan: &self.plan,
            expanded: &self.expanded,
            files: &self.files,
            by_path: &self.source_by_path,
        }
        .output(expanded_offset)
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

/// A bounded executable parse tied to an immutable source capture. Callers may
/// inspect its AST, but cannot replace it or manufacture its source authority.
pub struct IssuedBodyInput<'a> {
    issuer: &'a ColdFrontend,
    occurrence: &'a BodyOccurrence,
    compact: &'a Item,
    source: &'a str,
}
impl IssuedBodyInput<'_> {
    pub fn source(&self) -> &str {
        self.source
    }
    pub fn compact(&self) -> &Item {
        self.compact
    }
    pub fn occurrence(&self) -> &BodyOccurrence {
        self.occurrence
    }
}

pub struct ParsedBody<'a> {
    item: Item,
    issuer: &'a ColdFrontend,
    occurrence: &'a BodyOccurrence,
}
impl ParsedBody<'_> {
    pub fn item(&self) -> &Item {
        &self.item
    }
    pub fn occurrence(&self) -> &BodyOccurrence {
        self.occurrence
    }
}

struct Captured<'a, P> {
    provider: &'a P,
    sources: RefCell<BTreeMap<PathBuf, Arc<str>>>,
}

impl<P: SourceProvider> SourceProvider for Captured<'_, P> {
    fn prepared_source(
        &self,
        path: &Path,
    ) -> Option<Arc<dm_preprocess::regions::prepared_source::PreparedSource>> {
        let prepared = self.provider.prepared_source(path)?;
        self.sources
            .borrow_mut()
            .insert(path.to_owned(), Arc::clone(prepared.original()));
        Some(prepared)
    }
    fn read(&self, path: &Path) -> Result<String, String> {
        let source = self.provider.read(path)?;
        self.sources
            .borrow_mut()
            .insert(path.to_owned(), Arc::from(source.as_str()));
        Ok(source)
    }
}

/// Build a resolved source model from a captured provider. Map/resource consumers
/// receive the ordered non-text ledger and terminal FILE_DIR domain afterward.
pub fn build<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
    workers: usize,
) -> Result<ColdFrontend, Vec<Diagnostic>> {
    build_with_config(
        project,
        provider,
        defines,
        FrontendConfig {
            workers,
            engine: None,
            observer: None,
        },
    )
}

/// Resolve against an explicit engine seed, without any binary decoder/compiler
/// dependency. Caller supplies target-version macros and pinned engine identity.
pub fn build_with_config<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
    config: FrontendConfig<'_>,
) -> Result<ColdFrontend, Vec<Diagnostic>> {
    build_with_expansion_memo(project, provider, defines, config, None)
}

/// Optional client-owned expansion reuse. The ordered plan and joined grammar
/// remain authoritative, including declarations crossing include boundaries.
pub fn build_with_expansion_memo<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
    config: FrontendConfig<'_>,
    memo: Option<&dyn dm_preprocess::regions::ExpansionMemo>,
) -> Result<ColdFrontend, Vec<Diagnostic>> {
    build_with_memos(project, provider, defines, config, memo, None)
}

/// Reuse only a tree certified against current ordered declaration facts;
/// source occurrence provenance is rebuilt for every captured input.
pub fn build_with_memos<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
    config: FrontendConfig<'_>,
    memo: Option<&dyn dm_preprocess::regions::ExpansionMemo>,
    tree_reuse: Option<&crate::tree_reuse::TreeReuse>,
) -> Result<ColdFrontend, Vec<Diagnostic>> {
    let workers = config.workers;
    let total_start = Instant::now();
    let mut timings = FrontendTimings::default();
    let captured = Captured {
        provider,
        sources: RefCell::new(BTreeMap::new()),
    };
    let stage_start = Instant::now();
    observe(
        config,
        FrontendStage::DirectivePlanning,
        ProgressKind::Started,
        Duration::ZERO,
        0,
        0,
    );
    let plan = match memo {
        Some(memo) => {
            dm_preprocess::regions::plan_regions_with_memo(project, &captured, defines, memo)
        }
        None => plan_regions(project, &captured, defines),
    };
    timings.directive_planning = stage_start.elapsed();
    observe(
        config,
        FrontendStage::DirectivePlanning,
        ProgressKind::Completed,
        timings.directive_planning,
        plan.regions.len(),
        plan.regions.len(),
    );
    let stage_start = Instant::now();
    observe(
        config,
        FrontendStage::Expansion,
        ProgressKind::Started,
        Duration::ZERO,
        0,
        plan.regions.len(),
    );
    let expanded = match memo {
        Some(memo) => dm_preprocess::regions::expand_regions_text_with_memo(&plan, workers, memo),
        None => expand_regions_text(&plan, workers),
    };
    timings.expansion = stage_start.elapsed();
    observe(
        config,
        FrontendStage::Expansion,
        ProgressKind::Completed,
        timings.expansion,
        plan.regions.len(),
        plan.regions.len(),
    );
    let provenance_start = Instant::now();
    observe(
        config,
        FrontendStage::SourceIndexing,
        ProgressKind::Started,
        Duration::ZERO,
        0,
        plan.occurrences.len(),
    );
    let sources = captured.sources.into_inner();
    let mut files = Vec::new();
    let mut by_path = HashMap::new();
    for occurrence in &plan.occurrences {
        if by_path.contains_key(occurrence.path.as_ref()) {
            continue;
        }
        let id = FileId(
            u32::try_from(files.len()).map_err(|_| vec![internal("too many source files")])?,
        );
        let text = sources
            .get(occurrence.path.as_ref())
            .cloned()
            .unwrap_or_else(|| Arc::from(""));
        let starts = plan
            .source_line_starts
            .get(occurrence.path.as_ref())
            .cloned()
            .unwrap_or_else(|| Arc::from([0_usize]));
        by_path.insert(occurrence.path.as_ref().clone(), id);
        files.push(SourceFile {
            id,
            path: occurrence.path.clone(),
            captured: sources.contains_key(occurrence.path.as_ref()),
            text,
            line_starts: starts,
        });
    }
    let mapping = Mapping {
        plan: &plan,
        expanded: &expanded,
        files: &files,
        by_path: &by_path,
    };
    let mut diagnostics: Vec<_> = expanded
        .diagnostics
        .iter()
        .map(|diagnostic| Diagnostic {
            kind: match diagnostic.kind {
                dm_preprocess::DiagnosticKind::Unsupported => DiagnosticKind::UnsupportedModel,
                dm_preprocess::DiagnosticKind::Io
                | dm_preprocess::DiagnosticKind::Include
                | dm_preprocess::DiagnosticKind::Conditional
                | dm_preprocess::DiagnosticKind::Macro
                | dm_preprocess::DiagnosticKind::Directive
                | dm_preprocess::DiagnosticKind::UserError => DiagnosticKind::SourceError,
            },
            stage: DiagnosticStage::Preprocess,
            message: diagnostic.message.clone(),
            location: mapping.line(&diagnostic.path, diagnostic.line),
        })
        .collect();
    // Chunk the joined encounter stream at grammar-safe top-level boundaries,
    // not include boundaries. Every declaration is accepted regardless of size;
    // a large declaration consumes its own chunk rather than changing algorithms.
    timings.provenance_and_body_indexing += provenance_start.elapsed();
    observe(
        config,
        FrontendStage::SourceIndexing,
        ProgressKind::Completed,
        provenance_start.elapsed(),
        files.len(),
        files.len(),
    );
    let parse_start = Instant::now();
    observe(
        config,
        FrontendStage::DeclarationParsing,
        ProgressKind::Started,
        Duration::ZERO,
        0,
        0,
    );
    let ParsedDeclarations {
        items: compact_items,
        diagnostics: syntax_diagnostics,
        mut adapted,
        allocation_ledger,
        declaration_errors,
    } = parse_declarations(&expanded, config, memo)?;
    diagnostics.extend(
        syntax_diagnostics
            .into_iter()
            .map(|(offset, diagnostic)| Diagnostic {
                kind: syntax_kind(diagnostic.kind),
                stage: DiagnosticStage::Syntax,
                message: diagnostic.message,
                location: mapping.output(offset + diagnostic.span.start),
            }),
    );
    let syntax = Arc::new(AstFile {
        items: compact_items,
        ..AstFile::default()
    });
    diagnostics.sort_by_key(|diagnostic| {
        diagnostic
            .location
            .as_ref()
            .map_or((usize::MAX, usize::MAX), |location| {
                (location.encounter_ordinal, location.line)
            })
    });
    if !diagnostics.is_empty() {
        return Err(diagnostics);
    }
    if !declaration_errors.is_empty() {
        return Err(declaration_errors
            .into_iter()
            .map(|error| Diagnostic {
                kind: DiagnosticKind::UnsupportedModel,
                stage: DiagnosticStage::Declaration,
                message: error.message,
                location: mapping.output(error.span.start as usize),
            })
            .collect());
    }
    timings.declaration_parsing = parse_start.elapsed();
    observe(
        config,
        FrontendStage::DeclarationParsing,
        ProgressKind::Completed,
        timings.declaration_parsing,
        adapted.skeletons.len(),
        adapted.skeletons.len(),
    );
    observe(
        config,
        FrontendStage::DeclarationOrigins,
        ProgressKind::Started,
        Duration::ZERO,
        0,
        adapted.origins.len(),
    );
    let provenance_start = Instant::now();
    let expanded_spans: Vec<_> = adapted.origins.iter().map(|origin| origin.span).collect();
    // Hash each original region once, not once for every declaration in it.
    let region_hashes: Vec<_> = plan
        .regions
        .iter()
        .map(|region| {
            let path = plan.occurrences[region.occurrence].path.as_ref();
            let file = by_path
                .get(path)
                .and_then(|id| files.get(id.index()))
                .ok_or_else(|| vec![internal("include region has no captured source")])?;
            let text = file
                .text
                .get(region.source_span.range())
                .ok_or_else(|| vec![internal("include region lies outside captured source")])?;
            Ok(xxhash_rust::xxh3::xxh3_128(text.as_bytes()))
        })
        .collect::<Result<Vec<_>, Vec<Diagnostic>>>()?;
    let mut declaration_regions = Vec::new();
    for origin in &mut adapted.origins {
        let expanded_origin = mapping
            .origin(origin.span.start as usize)
            .ok_or_else(|| vec![internal("declaration has no current expansion origin")])?;
        // Declaration provenance needs the source span and occurrence, not a
        // complete diagnostic location (which also allocates an include chain).
        // Reuse the expansion lookup above instead of building that temporary.
        let file = *by_path
            .get(expanded_origin.origin.path.as_ref())
            .ok_or_else(|| vec![internal("declaration has no captured source file")])?;
        declaration_regions.push(expanded_origin.region);
        origin.span = source_span(file, expanded_origin.source_span)?;
        origin.include_occurrence = u32::try_from(plan.regions[expanded_origin.region].occurrence)
            .map_err(|_| vec![internal("too many include occurrences")])?;
        origin.region = region_hashes[expanded_origin.region];
        origin.expansion_stack = expanded_origin
            .macro_expansions
            .iter()
            .filter_map(|expansion| expansion.definition.as_ref())
            .filter_map(|definition| {
                by_path
                    .get(definition.path.as_ref())
                    .map(|file| (*file, definition))
            })
            .map(|(file, definition)| source_span(file, definition.source_span))
            .collect::<Result<Vec<_>, _>>()?
            .into();
    }
    timings.provenance_and_body_indexing += provenance_start.elapsed();
    observe(
        config,
        FrontendStage::DeclarationOrigins,
        ProgressKind::Completed,
        provenance_start.elapsed(),
        adapted.origins.len(),
        adapted.origins.len(),
    );
    let resolution_start = Instant::now();
    observe(
        config,
        FrontendStage::TreeResolution,
        ProgressKind::Started,
        Duration::ZERO,
        0,
        adapted.skeletons.len(),
    );
    let mut resolution_diagnostic = None;
    let snapshot = adapted
        .finish_with_engine_reuse_observed(
            config.engine,
            tree_reuse,
            |error, skeletons, origins| {
                resolution_diagnostic = Some(resolution_error(
                    error,
                    skeletons,
                    origins,
                    &mapping,
                    config.engine.is_some(),
                ));
            },
        )
        .map_err(|_| {
            vec![resolution_diagnostic.expect("resolution failure must notify observer")]
        })?;
    timings.tree_resolution = resolution_start.elapsed();
    observe(
        config,
        FrontendStage::TreeResolution,
        ProgressKind::Completed,
        timings.tree_resolution,
        snapshot.tree.declarations().len(),
        snapshot.tree.declarations().len(),
    );
    observe(
        config,
        FrontendStage::BodyIndexing,
        ProgressKind::Started,
        Duration::ZERO,
        0,
        snapshot.tree.declarations().len(),
    );
    let provenance_start = Instant::now();
    let declarations_by_start: HashMap<_, _> = expanded_spans
        .iter()
        .enumerate()
        .filter_map(|(index, span)| match snapshot.tree.declarations()[index] {
            Target::Member(member)
                if matches!(
                    snapshot.tree.member(member)?.kind,
                    MemberKind::Proc | MemberKind::Verb
                ) =>
            {
                Some((span.start as usize, (OccurrenceId(index as u32), member)))
            }
            _ => None,
        })
        .collect();
    let mut bodies = Vec::new();
    collect_bodies(
        &syntax.items,
        &mut Vec::new(),
        &declarations_by_start,
        &mapping,
        &mut bodies,
    )?;
    let mut ranks = vec![0; plan.regions.len()];
    for (rank, region) in expanded.emission_regions.iter().enumerate() {
        ranks[*region] = rank;
    }
    let mut emission_order: Vec<_> = (0..declaration_regions.len())
        .map(|index| OccurrenceId(index as u32))
        .collect();
    emission_order.sort_by_key(|id| (ranks[declaration_regions[id.0 as usize]], id.0));
    timings.provenance_and_body_indexing += provenance_start.elapsed();
    observe(
        config,
        FrontendStage::BodyIndexing,
        ProgressKind::Completed,
        provenance_start.elapsed(),
        bodies.len(),
        bodies.len(),
    );
    timings.total = total_start.elapsed();
    let bodies: Arc<[BodyOccurrence]> = bodies.into();
    Ok(ColdFrontend {
        timings,
        engine: config.engine.map(|seed| EngineModelStatus {
            identity: seed.identity,
            schema: seed.hierarchy.schema,
            type_count: seed.hierarchy.parents.len(),
            known_intrinsic_members: seed.intrinsics.len(),
            member_catalog_complete: false,
            typed_member_metadata_decoded: false,
        }),
        plan,
        issued_arena: Arc::clone(&expanded.text),
        expanded,
        issued_syntax: Arc::clone(&syntax),
        syntax,
        allocation_ledger: Arc::new(allocation_ledger),
        snapshot,
        files: files.into(),
        source_by_path: Arc::new(by_path),
        body_by_declaration: Arc::new(
            bodies
                .iter()
                .enumerate()
                .map(|(index, body)| (body.declaration, index))
                .collect(),
        ),
        issued_bodies: Arc::clone(&bodies),
        bodies,
        emission_order: emission_order.into(),
    })
}

#[path = "chunkfacts.rs"]
mod chunkfacts;

struct ParsedDeclarations {
    items: Vec<Item>,
    diagnostics: Vec<(usize, dm_syntax::Diagnostic)>,
    adapted: crate::AdaptedDeclarations,
    allocation_ledger: crate::allocation_ledger::AllocationLedger,
    declaration_errors: Vec<crate::AdapterError>,
}

/// Grammar-safe descriptor discovery is serial; lexing/parsing is bounded by
/// worker count and two descriptors per worker in each joined batch. Workers
/// discard executable AST children before returning their compact declarations.
fn parse_declarations(
    expanded: &ExpandedRegions,
    config: FrontendConfig<'_>,
    memo: Option<&dyn dm_preprocess::regions::ExpansionMemo>,
) -> Result<ParsedDeclarations, Vec<Diagnostic>> {
    let source = expanded.text.as_ref();
    let workers = config.workers;
    let parse_start = Instant::now();
    let mut chunks = Vec::new();
    let report = dm_syntax::for_each_source_chunk_with_limits(
        source,
        32 * 1024,
        source.len().max(1),
        |text, offset| chunks.push((offset, text.len())),
    );
    if report.skipped_declarations != 0 {
        return Err(vec![internal("grammar chunker omitted a declaration")]);
    }
    let hardware_workers = std::thread::available_parallelism().map_or(1, usize::from);
    let worker_count = workers
        .max(1)
        .min(hardware_workers)
        .min(chunks.len().max(1));
    let mut items = Vec::new();
    let mut diagnostics = Vec::new();
    // One bounded pool for the complete capture. Workers claim whole grammar-
    // safe descriptors; completion order never determines declaration identity.
    let next = std::sync::atomic::AtomicUsize::new(0);
    let mut ordered = std::thread::scope(|scope| {
        let (sender, receiver) = std::sync::mpsc::sync_channel(worker_count * 2);
        let handles: Vec<_> = (0..worker_count)
            .map(|_| {
                let sender = sender.clone();
                let chunks = &chunks;
                let next = &next;
                scope.spawn(move || loop {
                    let index = next.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    let Some(&(offset, len)) = chunks.get(index) else {
                        break;
                    };
                    let text = &source[offset..offset + len];
                    let receipt_index = expanded
                        .receipts
                        .partition_point(|receipt| receipt.output_span().end <= offset);
                    let receipt = expanded.receipts.get(receipt_index).filter(|receipt| {
                        receipt.output_span().start <= offset
                            && offset + len <= receipt.output_span().end
                    });
                    let relative = receipt.map(|receipt| {
                        dm_syntax::Span::new(
                            offset - receipt.output_span().start,
                            offset + len - receipt.output_span().start,
                        )
                    });
                    let cached = receipt
                        .zip(relative)
                        .and_then(|(receipt, span)| {
                            receipt.record().fragment(parserwire::VERSION, span)
                        })
                        .and_then(|bytes| parserwire::decode_with_facts(bytes, text));
                    let independent = if cached.is_none() {
                        memo.and_then(|memo| {
                            let key = dm_preprocess::regions::FragmentRecord::lookup_key(
                                parserwire::VERSION,
                                text,
                            );
                            memo.fragment_candidates(key)
                                .into_iter()
                                .rev()
                                .find_map(|record| {
                                    record
                                        .matches(parserwire::VERSION, text)
                                        .then(|| {
                                            parserwire::decode_with_facts(record.payload(), text)
                                        })
                                        .flatten()
                                })
                        })
                    } else {
                        None
                    };
                    let independent_hit = independent.is_some();
                    let cached = cached.or(independent);
                    let cached_fragment_hit = cached.is_some();
                    let (mut parsed, errors, cached_facts) = match cached {
                        Some((items, errors, facts)) => (items, errors, facts),
                        None => {
                            let ast = dm_syntax::parse_declaration_skeleton(text);
                            // Without an issued contained-region receipt, preserve
                            // the original one-pass cold compaction/rebase path.
                            let items = compact_declarations(
                                ast.items,
                                if receipt.is_some() || independent_hit {
                                    0
                                } else {
                                    offset
                                },
                            );
                            (items, ast.diagnostics, None)
                        }
                    };
                    if receipt.is_some() || independent_hit {
                        shift_items(&mut parsed, offset);
                    }
                    // Grammar-safe chunks are complete root-context units,
                    // including any declaration continued across include regions.
                    // Facts use a small local spelling table, never a cloned tree.
                    let ast = AstFile {
                        items: parsed,
                        ..AstFile::default()
                    };
                    let admitted_facts = cached_facts
                        .as_deref()
                        .and_then(|bytes| chunkfacts::decode(bytes, text, offset));
                    let has_cached_facts = admitted_facts.is_some();
                    let facts = if let Some(facts) = admitted_facts {
                        Ok(facts)
                    } else if errors.is_empty() {
                        crate::from_ast(&ast, SymbolTable::default(), FileId(0), 0, 0).and_then(
                            |mut adapted| {
                                crate::allocation_ledger::capture(
                                    &ast.items,
                                    "/",
                                    &mut adapted.symbols,
                                )
                                .map(|ledger| (adapted, ledger))
                                .map_err(|error| {
                                    vec![crate::AdapterError {
                                        span: dm_ir::Span {
                                            file: FileId(0),
                                            start: error.span.start as u32,
                                            end: error.span.end as u32,
                                        },
                                        message: error.message,
                                    }]
                                })
                            },
                        )
                    } else {
                        Err(Vec::new())
                    };
                    let parsed = ast.items;
                    if !cached_fragment_hit {
                        if let Some(memo) = memo {
                            let facts_bytes = facts.as_ref().ok().and_then(|(facts, ledger)| {
                                chunkfacts::encode(facts, ledger, offset)
                            });
                            if let Some(bytes) =
                                parserwire::encode_with_facts(&parsed, &errors, offset, facts_bytes)
                            {
                                if let Some(record) = dm_preprocess::regions::FragmentRecord::new(
                                    parserwire::VERSION,
                                    text,
                                    bytes.into(),
                                ) {
                                    memo.insert_fragment(Arc::new(record));
                                }
                            }
                        }
                    }
                    let fragment = if has_cached_facts {
                        None
                    } else {
                        receipt.zip(relative).and_then(|(_, span)| {
                            let bytes = facts.as_ref().ok().and_then(|(facts, ledger)| {
                                chunkfacts::encode(facts, ledger, offset)
                            });
                            parserwire::encode_with_facts(&parsed, &errors, offset, bytes)
                                .map(|bytes| (receipt_index, span, bytes))
                        })
                    };
                    if sender
                        .send((index, offset, parsed, errors, fragment, facts))
                        .is_err()
                    {
                        break;
                    }
                })
            })
            .collect();
        drop(sender);
        let mut ordered = Vec::with_capacity(chunks.len());
        for result in receiver {
            ordered.push(result);
            if ordered.len() % (worker_count * 2) == 0 || ordered.len() == chunks.len() {
                observe(
                    config,
                    FrontendStage::DeclarationParsing,
                    ProgressKind::Advanced,
                    parse_start.elapsed(),
                    ordered.len(),
                    chunks.len(),
                );
            }
        }
        // Consume every join, including after a panic, before releasing source.
        let failed = handles
            .into_iter()
            .map(|handle| handle.join())
            .fold(false, |failed, result| failed | result.is_err());
        if failed {
            Err(vec![internal("declaration parsing worker panicked")])
        } else {
            Ok(ordered)
        }
    })?;
    ordered.sort_by_key(|(index, _, _, _, _, _)| *index);
    let mut updated = std::collections::BTreeMap::new();
    let mut adapted = crate::AdaptedDeclarations {
        symbols: config
            .engine
            .map_or_else(SymbolTable::default, |engine| engine.symbols.clone()),
        skeletons: Vec::new(),
        origins: Vec::new(),
    };
    let mut allocation_events = Vec::new();
    let mut declaration_errors = Vec::new();
    for (_, offset, parsed, errors, fragment, facts) in ordered {
        match facts {
            Ok((facts, ledger)) => {
                for (expected, spelling) in facts.symbols.ordered() {
                    let actual = adapted
                        .symbols
                        .intern(spelling)
                        .map_err(|error| vec![internal(&error.to_string())])?;
                    if actual != expected {
                        return Err(vec![internal(
                            "worker declaration symbol identity mismatch",
                        )]);
                    }
                }
                adapted.skeletons.extend(facts.skeletons);
                adapted.origins.extend(facts.origins);
                for mut event in ledger.events.iter().cloned() {
                    event.encounter_order = allocation_events.len();
                    allocation_events.push(event);
                }
            }
            Err(errors) => declaration_errors.extend(errors),
        }
        if let Some((index, span, bytes)) = fragment {
            let record = updated
                .entry(index)
                .or_insert_with(|| expanded.receipts[index].record().as_ref().clone());
            if let Some(next) = record.with_fragment(parserwire::VERSION, span, bytes.into()) {
                *record = next;
            }
        }
        items.extend(parsed);
        diagnostics.extend(errors.into_iter().map(|error| (offset, error)));
    }
    if let Some(memo) = memo {
        for record in updated.into_values() {
            memo.insert(Arc::new(record));
        }
    }
    Ok(ParsedDeclarations {
        items,
        diagnostics,
        adapted,
        allocation_ledger: crate::allocation_ledger::AllocationLedger {
            events: allocation_events.into(),
        },
        declaration_errors,
    })
}

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

struct Mapping<'a> {
    plan: &'a DirectivePlan,
    expanded: &'a ExpandedRegions,
    files: &'a [SourceFile],
    by_path: &'a HashMap<PathBuf, FileId>,
}

impl Mapping<'_> {
    fn origin(&self, offset: usize) -> Option<&ExpandedOrigin> {
        let index = self
            .expanded
            .origins
            .partition_point(|origin| origin.output_span.end <= offset);
        self.expanded
            .origins
            .get(index)
            .or_else(|| self.expanded.origins.last())
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
            include_chain: self.chain(occurrence).into(),
            macro_expansions: origin.macro_expansions.clone(),
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
            include_chain: self.chain(occurrence).into(),
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
    items: &[Item],
    path: &mut Vec<usize>,
    declarations: &HashMap<usize, (OccurrenceId, MemberId)>,
    mapping: &Mapping<'_>,
    bodies: &mut Vec<BodyOccurrence>,
) -> Result<(), Vec<Diagnostic>> {
    for (index, item) in items.iter().enumerate() {
        path.push(index);
        if matches!(item.kind, ItemKind::Proc | ItemKind::Verb) {
            let declaration = declarations
                .get(&item.span.start)
                .copied()
                .ok_or_else(|| vec![internal("procedure body has no resolved declaration")])?;
            let source = mapping
                .output(item.span.start)
                .ok_or_else(|| vec![internal("procedure body has no source origin")])?;
            let mut setting_spans = Vec::new();
            crate::settings::setting_spans(&item.children, &mut setting_spans);
            let setting_context_origins = setting_spans
                .into_iter()
                .map(|span| {
                    mapping.output(span.start).ok_or_else(|| {
                        vec![internal("procedure setting has no current source origin")]
                    })
                })
                .collect::<Result<Vec<_>, _>>()?;
            bodies.push(BodyOccurrence {
                declaration: declaration.0,
                member: declaration.1,
                ast_path: path.clone().into(),
                expanded_span: item.span,
                source,
                setting_context_origins: setting_context_origins.into(),
            });
        } else {
            collect_bodies(&item.children, path, declarations, mapping, bodies)?;
        }
        path.pop();
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
                items: parsed.items,
                ..AstFile::default()
            };
            let mut expected =
                crate::from_ast(&ast, SymbolTable::default(), FileId(0), 0, 0).unwrap();
            let ledger =
                crate::allocation_ledger::capture(&ast.items, "/", &mut expected.symbols).unwrap();
            assert!(
                parsed.adapted.skeletons == expected.skeletons,
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
