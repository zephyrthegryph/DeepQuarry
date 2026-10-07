//! Uncached Phase 1 frontend. No Salsa database, session, graph or legacy index
//! participates in this path. Directive planning freezes expansion environments;
//! the combined encounter AST supplies scope before the resolved tree is built.

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

#[derive(Clone, Copy, Debug)]
pub struct FrontendConfig<'a> {
    pub workers: usize,
    pub engine: Option<&'a EngineSeed>,
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
    pub snapshot: TreeSnapshot,
    pub files: Arc<[SourceFile]>,
    source_by_path: Arc<HashMap<PathBuf, FileId>>,
    pub bodies: Arc<[BodyOccurrence]>,
    /// Explicit linker projection. It never changes semantic override priority
    /// or reorders origins independently from their declaration targets.
    pub emission_order: Arc<[OccurrenceId]>,
}

impl ColdFrontend {
    pub fn body(&self, occurrence: &BodyOccurrence) -> Result<Item, Diagnostic> {
        dm_syntax::parse_proc_at_span(&self.expanded.text, occurrence.expanded_span).map_err(
            |error| Diagnostic {
                kind: syntax_kind(error.kind),
                stage: DiagnosticStage::Syntax,
                location: self
                    .location(error.span.start)
                    .or_else(|| Some(occurrence.source.clone())),
                message: error.message,
            },
        )
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

struct Captured<'a, P> {
    provider: &'a P,
    sources: RefCell<BTreeMap<PathBuf, Arc<str>>>,
}

impl<P: SourceProvider> SourceProvider for Captured<'_, P> {
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
    let workers = config.workers;
    let total_start = Instant::now();
    let mut timings = FrontendTimings::default();
    let captured = Captured {
        provider,
        sources: RefCell::new(BTreeMap::new()),
    };
    let stage_start = Instant::now();
    let plan = plan_regions(project, &captured, defines);
    timings.directive_planning = stage_start.elapsed();
    let stage_start = Instant::now();
    let expanded = expand_regions_text(&plan, workers);
    timings.expansion = stage_start.elapsed();
    let provenance_start = Instant::now();
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
        let mut starts = vec![0];
        starts.extend(
            text.bytes()
                .enumerate()
                .filter_map(|(index, byte)| (byte == b'\n').then_some(index + 1)),
        );
        by_path.insert(occurrence.path.as_ref().clone(), id);
        files.push(SourceFile {
            id,
            path: occurrence.path.clone(),
            captured: sources.contains_key(occurrence.path.as_ref()),
            text,
            line_starts: starts.into(),
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
            kind: if diagnostic.message.starts_with("unsupported") {
                DiagnosticKind::UnsupportedModel
            } else {
                DiagnosticKind::SourceError
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
    let parse_start = Instant::now();
    let ParsedDeclarations {
        items: compact_items,
        diagnostics: syntax_diagnostics,
    } = parse_declarations(&expanded.text, workers)?;
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
    let mut adapted = crate::from_ast(
        &syntax,
        config
            .engine
            .map_or_else(SymbolTable::default, |engine| engine.symbols.clone()),
        FileId(0),
        0,
        0,
    )
    .map_err(|errors| {
        errors
            .into_iter()
            .map(|error| Diagnostic {
                kind: DiagnosticKind::UnsupportedModel,
                stage: DiagnosticStage::Declaration,
                message: error.message,
                location: mapping.output(error.span.start as usize),
            })
            .collect::<Vec<_>>()
    })?;
    timings.declaration_parsing = parse_start.elapsed();
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
        let source = mapping
            .output(origin.span.start as usize)
            .ok_or_else(|| vec![internal("declaration has no current source location")])?;
        declaration_regions.push(expanded_origin.region);
        origin.span = source.span;
        origin.include_occurrence = u32::try_from(source.include_occurrence)
            .map_err(|_| vec![internal("too many include occurrences")])?;
        origin.region = region_hashes[expanded_origin.region];
        origin.expansion_stack = source
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
    let error_origins = adapted.origins.clone();
    let skeletons = adapted.skeletons.clone();
    timings.provenance_and_body_indexing += provenance_start.elapsed();
    let resolution_start = Instant::now();
    let snapshot = adapted.finish_with_engine(config.engine).map_err(|error| {
        vec![resolution_error(
            error,
            &skeletons,
            &error_origins,
            &mapping,
            config.engine.is_some(),
        )]
    })?;
    timings.tree_resolution = resolution_start.elapsed();
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
    timings.total = total_start.elapsed();
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
        expanded,
        syntax,
        snapshot,
        files: files.into(),
        source_by_path: Arc::new(by_path),
        bodies: bodies.into(),
        emission_order: emission_order.into(),
    })
}

struct ParsedDeclarations {
    items: Vec<Item>,
    diagnostics: Vec<(usize, dm_syntax::Diagnostic)>,
}

/// Grammar-safe descriptor discovery is serial; lexing/parsing is bounded by
/// worker count and two descriptors per worker in each joined batch. Workers
/// discard executable AST children before returning their compact declarations.
fn parse_declarations(source: &str, workers: usize) -> Result<ParsedDeclarations, Vec<Diagnostic>> {
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
    let batch_size = worker_count.saturating_mul(2);
    let mut items = Vec::new();
    let mut diagnostics = Vec::new();
    for batch in chunks.chunks(batch_size) {
        // Divide descriptors, rather than source bytes: an entire top-level
        // declaration always stays together, including namespace/include scope.
        let per_worker = batch.len().div_ceil(worker_count);
        let mut results = std::thread::scope(|scope| {
            let handles: Vec<_> = batch
                .chunks(per_worker)
                .enumerate()
                .map(|(worker, assigned)| {
                    scope.spawn(move || {
                        assigned
                            .iter()
                            .enumerate()
                            .map(|(index, &(offset, len))| {
                                let ast = dm_syntax::parse(&source[offset..offset + len]);
                                let diagnostics = ast.diagnostics;
                                let items = compact_declarations(ast.items, offset);
                                (worker * per_worker + index, offset, items, diagnostics)
                            })
                            .collect::<Vec<_>>()
                    })
                })
                .collect();
            // Join every spawned task even if one failed: no worker outlives
            // the source snapshot, and a panic is an internal compiler failure.
            handles
                .into_iter()
                .map(|handle| handle.join())
                .collect::<Vec<_>>()
        });
        if results.iter().any(Result::is_err) {
            return Err(vec![internal("declaration parsing worker panicked")]);
        }
        let mut ordered = Vec::new();
        for result in results.drain(..) {
            ordered
                .extend(result.map_err(|_| vec![internal("declaration parsing worker panicked")])?);
        }
        ordered.sort_by_key(|(index, _, _, _)| *index);
        for (_, offset, parsed, errors) in ordered {
            items.extend(parsed);
            diagnostics.extend(errors.into_iter().map(|error| (offset, error)));
        }
    }
    Ok(ParsedDeclarations { items, diagnostics })
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

fn compact_declarations(items: Vec<Item>, offset: usize) -> Vec<Item> {
    items
        .into_iter()
        .map(|mut item| {
            item.span.start += offset;
            item.span.end += offset;
            item.header_span.start += offset;
            item.header_span.end += offset;
            if matches!(item.kind, ItemKind::Proc | ItemKind::Verb) {
                item.children
                    .retain(|child| child.header.trim_start().starts_with("set "));
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
    error: SnapshotError,
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
            | crate::TreeError::InheritanceCycle(path)
            | crate::TreeError::MissingParent(path)) => skeletons.iter().rposition(|skeleton| matches!(skeleton, Skeleton::Type { path: found, .. } if found == path)),
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
            bodies.push(BodyOccurrence {
                declaration: declaration.0,
                member: declaration.1,
                ast_path: path.clone().into(),
                expanded_span: item.span,
                source,
            });
        } else {
            collect_bodies(&item.children, path, declarations, mapping, bodies)?;
        }
        path.pop();
    }
    Ok(())
}
