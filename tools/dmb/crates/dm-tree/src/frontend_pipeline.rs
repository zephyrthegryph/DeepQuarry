use super::*;
#[path = "frontend_emission_order.rs"]
mod emission_order;

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
    let executor = dm_exec::BuildExecutor::new(config.workers).map_err(|error| {
        vec![internal(&format!(
            "frontend executor creation failed: {error}"
        ))]
    })?;
    build_with_executor(project, provider, defines, config, memo, &executor)
}

/// Build the frontend on the request's borrowed executor, including expansion
/// and declaration parsing. Ordered directive traversal remains on the caller.
pub fn build_with_executor<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
    config: FrontendConfig<'_>,
    memo: Option<&dyn dm_preprocess::regions::ExpansionMemo>,
    executor: &dm_exec::BuildExecutor,
) -> Result<ColdFrontend, Vec<Diagnostic>> {
    build_with_executor_and_semantic_state(project, provider, defines, config, memo, executor, None)
}
/// Share only resolved semantic declarations; all source issuance is rebuilt.
pub fn build_with_executor_and_semantic_state<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
    config: FrontendConfig<'_>,
    memo: Option<&dyn dm_preprocess::regions::ExpansionMemo>,
    executor: &dm_exec::BuildExecutor,
    mut semantic_state: Option<&mut RetainedSemanticTree>,
) -> Result<ColdFrontend, Vec<Diagnostic>> {
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
    let profile_stage = dm_profile::stage("frontend.directive_planning");
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
    drop(profile_stage);
    let stage_start = Instant::now();
    observe(
        config,
        FrontendStage::Expansion,
        ProgressKind::Started,
        Duration::ZERO,
        0,
        plan.regions.len(),
    );
    let profile_stage = dm_profile::stage("frontend.expansion");
    let expanded = dm_preprocess::regions::expand_regions_text_with_executor(&plan, executor, memo);
    timings.expansion = stage_start.elapsed();
    observe(
        config,
        FrontendStage::Expansion,
        ProgressKind::Completed,
        timings.expansion,
        plan.regions.len(),
        plan.regions.len(),
    );
    drop(profile_stage);
    let provenance_start = Instant::now();
    observe(
        config,
        FrontendStage::SourceIndexing,
        ProgressKind::Started,
        Duration::ZERO,
        0,
        plan.occurrences.len(),
    );
    let profile_stage = dm_profile::stage("frontend.source_indexing");
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
            .unwrap_or_else(|| dm_preprocess::SourceText::from(""));
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
        projection: Default::default(),
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
    drop(profile_stage);
    let parse_start = Instant::now();
    observe(
        config,
        FrontendStage::DeclarationParsing,
        ProgressKind::Started,
        Duration::ZERO,
        0,
        0,
    );
    let profile_stage = dm_profile::stage("frontend.declaration_parsing");
    let ParsedDeclarations {
        syntax,
        diagnostics: syntax_diagnostics,
        mut adapted,
        allocation_ledger,
        declaration_errors,
        reuse_stats,
    } = declaration_parse::parse_declarations_with_state(
        &expanded,
        config,
        memo,
        executor,
        semantic_state.as_deref().map(|state| &state.declarations),
    )?;
    timings.declaration_reuse = reuse_stats;
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
    let syntax = Arc::new(syntax);
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
                kind: syntax_kind(error.kind),
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
    drop(profile_stage);
    observe(
        config,
        FrontendStage::DeclarationOrigins,
        ProgressKind::Started,
        Duration::ZERO,
        0,
        adapted.origins.len(),
    );
    let profile_stage = dm_profile::stage("frontend.declaration_origins");
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
            file.text
                .span_fingerprint(region.source_span.range())
                .ok_or_else(|| vec![internal("include region lies outside captured source")])
        })
        .collect::<Result<Vec<_>, Vec<Diagnostic>>>()?;
    let mut declaration_regions = Vec::with_capacity(adapted.origins.len());
    let mut current_origins = Vec::with_capacity(adapted.origins.len());
    for origin in adapted.origins.iter() {
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
        let span = source_span(file, expanded_origin.source_span)?;
        let include_occurrence = u32::try_from(plan.regions[expanded_origin.region].occurrence)
            .map_err(|_| vec![internal("too many include occurrences")])?;
        let region = region_hashes[expanded_origin.region];
        let expansion_stack = mapping.expansion_stack(expanded_origin.macro_expansions)?;
        current_origins.push(crate::Provenance {
            span,
            include_occurrence,
            region,
            expansion_stack,
        });
    }
    adapted.origins = current_origins.into();
    timings.provenance_and_body_indexing += provenance_start.elapsed();
    observe(
        config,
        FrontendStage::DeclarationOrigins,
        ProgressKind::Completed,
        provenance_start.elapsed(),
        adapted.origins.len(),
        adapted.origins.len(),
    );
    drop(profile_stage);
    let resolution_start = Instant::now();
    observe(
        config,
        FrontendStage::TreeResolution,
        ProgressKind::Started,
        Duration::ZERO,
        0,
        adapted.skeletons.len(),
    );
    let profile_stage = dm_profile::stage("frontend.tree_resolution");
    let mut resolution_diagnostic = None;
    let on_error =
        |error: &SnapshotError, skeletons: &[Skeleton], origins: &[crate::Provenance]| {
            resolution_diagnostic = Some(resolution_error(
                error,
                skeletons,
                origins,
                &mapping,
                config.engine.is_some(),
            ));
        };
    let snapshot = match semantic_state.as_deref_mut() {
        Some(state) => state.resolve(adapted, config.engine, on_error, executor),
        None => adapted.finish_with_engine_observed_on_executor(config.engine, on_error, executor),
    }
    .map_err(|_| vec![resolution_diagnostic.expect("resolution failure must notify observer")])?;
    timings.tree_resolution = resolution_start.elapsed();
    observe(
        config,
        FrontendStage::TreeResolution,
        ProgressKind::Completed,
        timings.tree_resolution,
        snapshot.tree.declarations().len(),
        snapshot.tree.declarations().len(),
    );
    drop(profile_stage);
    observe(
        config,
        FrontendStage::BodyIndexing,
        ProgressKind::Started,
        Duration::ZERO,
        0,
        snapshot.tree.declarations().len(),
    );
    let profile_stage = dm_profile::stage("frontend.body_indexing");
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
    let mut issued_settings = Vec::new();
    collect_bodies(
        &syntax,
        &snapshot.tree,
        &declarations_by_start,
        &mapping,
        &mut bodies,
        &mut issued_settings,
    )?;
    let callable_roster = match semantic_state {
        Some(state) => state.bind_callable_roster(&snapshot.tree, &bodies),
        None => CallableRoster::issue(&snapshot.tree, &bodies),
    }
    .map_err(|message| vec![internal(&message)])?;

    // Ineligible/custom metadata preserves the ordinary downstream ABI error path.
    let abi_settings_complete = callable_roster.abi().is_some_and(|abi| {
        issued_settings.len() == abi.entries().len()
            && issued_settings
                .iter()
                .zip(abi.entries())
                .all(|(settings, entry)| {
                    settings.as_ref().is_some_and(|owner| {
                        Arc::ptr_eq(owner, &entry.metadata) || owner == &entry.metadata
                    })
                })
    });
    let mut ranks = vec![0; plan.regions.len()];
    for (rank, region) in expanded.emission_regions.iter().enumerate() {
        ranks[*region] = rank;
    }
    let emission_order = emission_order::ordered_occurrences(&declaration_regions, &ranks);
    timings.provenance_and_body_indexing += provenance_start.elapsed();
    observe(
        config,
        FrontendStage::BodyIndexing,
        ProgressKind::Completed,
        provenance_start.elapsed(),
        bodies.len(),
        bodies.len(),
    );
    drop(profile_stage);
    timings.total = total_start.elapsed();
    let bodies: Arc<[BodyOccurrence]> = bodies.into();
    Ok(ColdFrontend {
        callable_roster,
        abi_settings_complete,
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
        issued_arena: expanded.text.clone(),
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
        issued_settings: issued_settings.into(),
        bodies,
        emission_order: emission_order.into(),
    })
}
