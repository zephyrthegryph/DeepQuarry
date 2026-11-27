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

/// `DMB_FRONTEND_VERIFY=1` also runs the full directive pass and the full expansion and logs any
/// difference from the incremental ones (the full results are used). Off by default.
fn verify_enabled() -> bool {
    std::env::var_os("DMB_FRONTEND_VERIFY").is_some_and(|value| value == "1")
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
    let declaration_request = semantic_state
        .as_ref()
        .and_then(|state| state.declarations.compatibility_request());
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
    // The previous request's frontend, when this session built one for the same project and
    // defines: every unchanged include subtree of its plan is adopted, not interpreted again.
    let previous = semantic_state
        .as_ref()
        .and_then(|state| state.previous_frontend(project, defines));
    let (mut plan, mut plan_reuse) = dm_preprocess::regions::plan_regions_incremental(
        project,
        &captured,
        defines,
        memo,
        previous.as_ref().map(|previous| &previous.plan),
    );
    if verify_enabled() && previous.is_some() {
        let full = match memo {
            Some(memo) => {
                dm_preprocess::regions::plan_regions_with_memo(project, provider, defines, memo)
            }
            None => plan_regions(project, provider, defines),
        };
        match dm_preprocess::regions::plans_equal(&plan, &full) {
            Ok(()) => crate::change_set::record_outcome(
                "frontend verify: incremental plan equals the full plan".into(),
            ),
            Err(why) => {
                eprintln!("frontend verify: PLAN MISMATCH: {why}");
                crate::change_set::record_outcome(format!("frontend verify: PLAN MISMATCH: {why}"));
                // The full plan is the authority; nothing of it is a copy of the previous one.
                plan = full;
                plan_reuse = dm_preprocess::regions::PlanReuse::default();
            }
        }
    }
    // Files a patched or adopted plan did not request from the provider are the previous plan's.
    let seed_started = Instant::now();
    if plan_reuse.replanned > 0 || plan_reuse.subtrees > 0 {
        // The plan holds the text of every file it read, whether it asked the provider again or
        // adopted the previous plan's reads; a clone has no path comparisons to make.
        *captured.sources.borrow_mut() = plan.source_texts.clone();
    }
    let seeded = seed_started.elapsed();
    crate::change_set::record_outcome(format!(
        "frontend plan: {} replanned, {} subtrees adopted ({} occurrences, {} regions of {} copied, {} more matched); declined files={} state={} context={} visits={}; {:.3}s",
        plan_reuse.replanned,
        plan_reuse.subtrees,
        plan_reuse.occurrences,
        plan_reuse.copied_regions,
        plan.regions.len(),
        plan_reuse.matched_regions,
        plan_reuse.declined.files,
        plan_reuse.declined.state,
        plan_reuse.declined.context,
        plan_reuse.declined.visits,
        stage_start.elapsed().as_secs_f64()
    ));
    let t = plan_reuse.timings;
    crate::change_set::record_outcome(format!(
        "frontend plan detail: seed={:.3}s adopt={:.3}s (touch={:.3}s state={:.3}s copy={:.3}s) occurrences={:.3}s visit={:.3}s matching={:.3}s patch (replan={:.3}s assemble={:.3}s)",
        seeded.as_secs_f64(),
        t.adopt.as_secs_f64(),
        t.touch.as_secs_f64(),
        t.state.as_secs_f64(),
        t.copy.as_secs_f64(),
        t.occurrences.as_secs_f64(),
        t.visit.as_secs_f64(),
        t.matching.as_secs_f64(),
        t.replan.as_secs_f64(),
        t.assemble.as_secs_f64(),
    ));
    dm_profile::request_mark("frontend.plan_done");
    timings.directive_planning = stage_start.elapsed();
    timings.phase("plan", stage_start);
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
    let full_expansion =
        || dm_preprocess::regions::expand_regions_text_with_executor(&plan, executor, memo);
    let reusing = match (previous.as_ref(), memo) {
        (Some(previous), Some(memo)) => dm_preprocess::regions::expand_regions_reusing(
            &previous.expanded,
            &plan,
            &plan_reuse,
            memo,
            executor,
        ),
        _ => None,
    };
    let (expanded, expansion_reuse) = match reusing {
        Some((expansion, stats)) => {
            if verify_enabled() {
                let full = full_expansion();
                match dm_preprocess::regions::expansions_equal(&expansion, &full) {
                    Ok(()) => crate::change_set::record_outcome(
                        "frontend verify: reusing expansion equals the full expansion".into(),
                    ),
                    Err(why) => {
                        eprintln!("frontend verify: EXPANSION MISMATCH: {why}");
                        crate::change_set::record_outcome(format!(
                            "frontend verify: EXPANSION MISMATCH: {why}"
                        ));
                    }
                }
                (full, Some(stats))
            } else {
                (expansion, Some(stats))
            }
        }
        None => (full_expansion(), None),
    };
    timings.expansion = stage_start.elapsed();
    timings.phase("expansion", stage_start);
    crate::change_set::record_outcome(match expansion_reuse {
        Some(stats) => format!(
            "frontend expansion: {} regions reused ({} rows moved), {} expanded; prepare={:.3}s expand={:.3}s text={:.3}s rows={:.3}s; {:.3}s",
            stats.reused,
            stats.rows_moved,
            stats.expanded,
            stats.prepare.as_secs_f64(),
            stats.expand.as_secs_f64(),
            stats.text.as_secs_f64(),
            stats.rows.as_secs_f64(),
            timings.expansion.as_secs_f64()
        ),
        None => format!(
            "frontend expansion: full ({} regions); {:.3}s",
            plan.regions.len(),
            timings.expansion.as_secs_f64()
        ),
    });
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
    // A patched plan has the previous plan's occurrences at the same places, so the previous
    // source index stands except for the files that were requested again.
    let index_started = Instant::now();
    let reused_index = previous.as_ref().and_then(|previous| {
        let rebuilt = plan_reuse.rebuilt_files.as_ref()?;
        let same_places = plan.occurrences.len() == previous.plan.occurrences.len()
            && plan
                .occurrences
                .iter()
                .zip(&previous.plan.occurrences)
                .all(|(now, was)| Arc::ptr_eq(&now.path, &was.path) || now.path == was.path);
        if !same_places {
            return None;
        }
        let mut files = previous.files.to_vec();
        for path in rebuilt {
            let id = *previous.source_by_path.get(path)?;
            files[id.index()] = SourceFile {
                id,
                path: Arc::clone(&files[id.index()].path),
                captured: sources.contains_key(path),
                text: sources
                    .get(path)
                    .cloned()
                    .unwrap_or_else(|| dm_preprocess::SourceText::from("")),
                line_starts: plan
                    .source_line_starts
                    .get(path)
                    .cloned()
                    .unwrap_or_else(|| Arc::from([0_usize])),
            };
        }
        Some((files, Arc::clone(&previous.source_by_path)))
    });
    let source_index_reused = reused_index.is_some();
    let (files, by_path) = match reused_index {
        Some(index) => index,
        None => build_source_index(&plan, &sources)?,
    };
    timings.phase("source_index", index_started);
    crate::change_set::record_outcome(format!(
        "frontend source index {}: {:.3}s",
        if source_index_reused { "reused" } else { "built" },
        index_started.elapsed().as_secs_f64()
    ));
    let mapping = Mapping {
        projection: Default::default(),
        plan: &plan,
        expanded: &expanded,
        files: &files,
        by_path: &by_path,
        hints: Default::default(),
    };
    let diagnostics_started = Instant::now();
    let mut text_expression_files = std::collections::HashSet::new();
    let mut diagnostics: Vec<_> = expanded
        .diagnostics
        .iter()
        .flat_map(|diagnostic| {
            if diagnostic.kind == dm_preprocess::DiagnosticKind::Macro
                && diagnostic.message.starts_with("unterminated text expression")
            {
                // The expression runs to the end of the file, so only the first one is read.
                return if text_expression_files.insert(diagnostic.path.clone()) {
                    text_expression_diagnostics(&mapping, diagnostic)
                } else {
                    Vec::new()
                };
            }
            vec![Diagnostic {
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
            // DreamMaker echoes the directive with the author's text.
            message: if diagnostic.kind == dm_preprocess::DiagnosticKind::UserError {
                format!("#error {}", diagnostic.message.trim())
            } else {
                diagnostic.message.clone()
            },
            location: mapping.line(&diagnostic.path, diagnostic.line),
            }]
        })
        .collect();
    timings.phase("preprocess_diagnostics", diagnostics_started);
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
            })
            // The preprocessor already reported an unterminated text expression, which consumes the rest of its file.
            .filter(|diagnostic| {
                !(diagnostic.message.starts_with("unterminated text expression")
                    && diagnostic.location.as_ref().is_some_and(|location| {
                        text_expression_files.contains(location.path.as_path())
                    }))
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
    timings.phase("declaration_parsing", parse_start);
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
    // What the previous revision's origins can be reused for: its files are this revision's at the same ids (the source
    // index was reused) and the plan says which regions are verbatim copies of which previous ones.
    // A rebuilt index (the ordered pass adopted subtrees instead of patching) still qualifies when it numbers the same files
    // the same way.
    let origin_base = previous.as_ref().filter(|previous| {
        plan_reuse.regions.len() == plan.regions.len()
            && (source_index_reused
                || (previous.files.len() == files.len()
                    && previous.files.iter().zip(files.iter()).all(|(was, now)| {
                        Arc::ptr_eq(&was.path, &now.path) || was.path == now.path
                    })))
    });
    // Hash each original region once, not once for every declaration in it; a copied region's hash is the previous one.
    let region_hashes: Vec<_> = plan
        .regions
        .iter()
        .enumerate()
        .map(|(index, region)| {
            if let Some(hash) = origin_base.and_then(|base| plan_reuse.regions[index].and_then(|old| base.region_hashes.get(old))) {
                return Ok(*hash);
            }
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
    timings.phase("region_hashes", provenance_start);
    let origins_started = Instant::now();
    // A declaration in a copied region has the previous revision's origin (same file, span, region text and macro
    // trace) with this plan's occurrence; only the others are looked up.
    let reused_origins = origin_base.and_then(|base| {
        let starts: Vec<usize> = expanded_spans.iter().map(|span| span.start as usize).collect();
        super::origin_reuse::plan(base, &plan_reuse.regions, &expanded.receipts, &starts)
    });
    let reused_count = reused_origins.as_ref().map_or(0, |rows| rows.iter().filter(|row| row.is_some()).count());
    // Every declaration's origin, in parallel chunks (each with its own lookup hints), joined in declaration order.
    let parts = mapping.parts();
    let indices: Vec<usize> = (0..expanded_spans.len()).collect();
    let origin_rows = super::parallel::chunked_map(executor, &indices, |_, part| {
    let mapping = parts.mapping();
    let mut rows = Vec::with_capacity(part.len());
    for &index in part {
        if let Some((region, old)) = reused_origins.as_ref().and_then(|rows| rows[index]) {
            let base = origin_base.expect("reused origins have a base");
            let mut provenance = base
                .snapshot
                .occurrences
                .get(OccurrenceId(old))
                .ok_or_else(|| vec![internal("reused origin has no previous occurrence")])?
                .provenance
                .clone();
            provenance.include_occurrence = u32::try_from(plan.regions[region].occurrence)
                .map_err(|_| vec![internal("too many include occurrences")])?;
            rows.push((region, provenance));
            continue;
        }
        let origin_span = &expanded_spans[index];
        let expanded_origin = mapping
            .origin(origin_span.start as usize)
            .ok_or_else(|| vec![internal("declaration has no current expansion origin")])?;
        // Declaration provenance needs the source span and occurrence, not a
        // complete diagnostic location (which also allocates an include chain).
        // Reuse the expansion lookup above instead of building that temporary.
        let file = mapping
            .file_of(expanded_origin.origin.path)
            .ok_or_else(|| vec![internal("declaration has no captured source file")])?;
        let span = source_span(file, expanded_origin.source_span)?;
        let include_occurrence = u32::try_from(plan.regions[expanded_origin.region].occurrence)
            .map_err(|_| vec![internal("too many include occurrences")])?;
        let region = region_hashes[expanded_origin.region];
        let expansion_stack = mapping.expansion_stack(expanded_origin.macro_expansions)?;
        rows.push((
            expanded_origin.region,
            crate::Provenance {
                span,
                include_occurrence,
                region,
                expansion_stack,
            },
        ));
    }
    Ok::<_, Vec<Diagnostic>>(rows)
    })?;
    let (declaration_regions, current_origins): (Vec<_>, Vec<_>) = origin_rows.into_iter().unzip();
    if verify_enabled() && reused_count > 0 {
        // The full lookup for every declaration: a reused origin must equal it.
        let full = mapping.parts().mapping();
        let mismatch = expanded_spans.iter().zip(&current_origins).zip(&declaration_regions).position(|((span, reused), region)| {
            full.origin(span.start as usize).is_none_or(|origin| {
                origin.region != *region
                    || full.file_of(origin.origin.path).is_none_or(|file| {
                        source_span(file, origin.source_span).ok() != Some(reused.span)
                            || full.expansion_stack(origin.macro_expansions).ok().as_ref() != Some(&reused.expansion_stack)
                    })
                    || reused.region != region_hashes[origin.region]
                    || reused.include_occurrence as usize != plan.regions[origin.region].occurrence
            })
        });
        match mismatch {
            None => crate::change_set::record_outcome(format!("frontend verify: {reused_count} reused origins equal the full lookup")),
            Some(index) => {
                eprintln!("frontend verify: ORIGIN MISMATCH at declaration {index}");
                crate::change_set::record_outcome(format!("frontend verify: ORIGIN MISMATCH at declaration {index}"));
            }
        }
    }
    timings.reused_origins = reused_count;
    crate::change_set::record_outcome(format!(
        "frontend origins: {reused_count} of {} reused from the previous revision",
        current_origins.len()
    ));
    adapted.origins = current_origins.into();
    timings.phase("origins", origins_started);
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
    let resolution_symbols = adapted.symbols.clone();
    let mut resolution_diagnostic = None;
    let on_error =
        |error: &SnapshotError, skeletons: &[Skeleton], origins: &[crate::Provenance]| {
            resolution_diagnostic = Some(duplicate_diagnostics::resolve(
                error,
                skeletons,
                origins,
                &mapping,
                config.engine.is_some(),
                &resolution_symbols,
                config.engine.map_or(&[][..], |seed| &seed.intrinsics[..]),
            ));
        };
    let snapshot = match semantic_state.as_deref_mut() {
        Some(state) => state.resolve(adapted, config.engine, on_error, executor),
        None => adapted.finish_with_engine_observed_on_executor(config.engine, on_error, executor),
    }
    .map_err(|_| resolution_diagnostic.expect("resolution failure must notify observer"))?;
    timings.tree_resolution = resolution_start.elapsed();
    timings.phase("tree", resolution_start);
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
    // Declaration starts in output order: a body finds its declaration by binary search (`collect_bodies`).
    let mut declaration_starts_now: Vec<(usize, usize)> =
        expanded_spans.iter().enumerate().map(|(index, span)| (span.start as usize, index)).collect();
    // Almost always already in order; a stable sort keeps declarations that start together in index order.
    if declaration_starts_now.windows(2).any(|pair| pair[0].0 > pair[1].0) {
        declaration_starts_now.sort_by_key(|&(start, _)| start);
    }
    // The previous revision's bodies stand for the bodies of declarations whose origin was reused, when the tree is the
    // previous one (member ids are the same).
    let body_reuse = match (origin_base, reused_origins.as_ref()) {
        (Some(base), Some(origins)) if Arc::ptr_eq(&base.snapshot.tree, &snapshot.tree) => {
            Some(BodyReuse { base, origins, plan: &plan })
        }
        _ => None,
    };
    timings.phase("body_starts", provenance_start);
    let collect_started = Instant::now();
    let mut bodies = Vec::new();
    let mut issued_settings = Vec::new();
    let mut body_codes = Vec::new();
    let reused_bodies = collect_bodies(
        &syntax,
        &snapshot.tree,
        &declaration_starts_now,
        &mapping,
        &mut bodies,
        &mut issued_settings,
        &mut body_codes,
        executor,
        body_reuse.as_ref(),
    )?;
    if verify_enabled() && reused_bodies > 0 {
        let (mut full_bodies, mut full_settings, mut full_codes) = (Vec::new(), Vec::new(), Vec::new());
        collect_bodies(
            &syntax,
            &snapshot.tree,
            &declaration_starts_now,
            &mapping,
            &mut full_bodies,
            &mut full_settings,
            &mut full_codes,
            executor,
            None,
        )?;
        let same = full_bodies.len() == bodies.len()
            && full_bodies.iter().zip(&bodies).all(|(a, b)| {
                a.declaration == b.declaration
                    && a.member == b.member
                    && a.expanded_span == b.expanded_span
                    && a.source == b.source
                    && a.setting_context_origins == b.setting_context_origins
            })
            && full_settings.iter().zip(&issued_settings).all(|(a, b)| a == b);
        let line = if same {
            format!("frontend verify: {reused_bodies} reused bodies equal the full indexing")
        } else {
            eprintln!("frontend verify: BODY MISMATCH");
            "frontend verify: BODY MISMATCH".to_string()
        };
        crate::change_set::record_outcome(line);
    }
    crate::change_set::record_outcome(format!("frontend bodies: {reused_bodies} of {} reused", bodies.len()));
    timings.phase("collect_bodies", collect_started);
    let roster_started = Instant::now();
    let callable_roster = match semantic_state.as_deref_mut() {
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
    timings.phase("callable_roster", roster_started);
    let order_started = Instant::now();
    let mut ranks = vec![0; plan.regions.len()];
    for (rank, region) in expanded.emission_regions.iter().enumerate() {
        ranks[*region] = rank;
    }
    let emission_order = emission_order::ordered_occurrences(&declaration_regions, &ranks);
    timings.phase("emission_order", order_started);
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
    let codes_started = Instant::now();
    let bodies: Arc<[BodyOccurrence]> = bodies.into();
    if let Some(request) = &declaration_request {
        request.publish_successful();
    }
    let terminations = super::parallel::chunked_map(executor, &bodies, |_, part| {
        Ok::<_, std::convert::Infallible>(
            part.iter()
                .map(|body| {
                    dm_syntax::termination_after_with_context(
                        &expanded.text,
                        body.expanded_span.end,
                        &|offset| syntax.declaration_header_at(offset),
                    )
                })
                .collect(),
        )
    });
    let terminations = match terminations {
        Ok(terminations) => terminations,
        Err(never) => match never {},
    };
    let issued_body_codes = body_codes
        .into_iter()
        .zip(terminations)
        .map(|(identity, termination)| body_code::BodyCodeOwner { identity, termination })
        .collect();
    timings.phase("body_codes", codes_started);
    let export_started = Instant::now();
    let files: Arc<[SourceFile]> = files.into();
    let source_by_path = by_path;
    let source_export_mapping = Arc::new(source_export_mapping::SourceExportMapping::capture(
        &plan,
        &expanded,
        &files,
        &source_by_path,
        &snapshot.occurrences,
        &snapshot.tree,
    ));
    timings.phase("export_mapping", export_started);
    let body_index_started = Instant::now();
    let body_by_declaration = Arc::new(
        bodies
            .iter()
            .enumerate()
            .map(|(index, body)| (body.declaration, index))
            .collect(),
    );
    timings.phase("body_by_declaration", body_index_started);
    timings.total = total_start.elapsed();
    crate::change_set::record_outcome(format!(
        "frontend phases: {} total={:.3}s",
        timings.phase_summary(),
        timings.total.as_secs_f64()
    ));
    let declaration_regions: Arc<[u32]> = declaration_regions.iter().map(|&region| region as u32).collect();
    let declaration_starts: Arc<[u32]> = expanded_spans.iter().map(|span| span.start).collect();
    let mut frontend = ColdFrontend {
        declaration_spans: expanded_spans.into(),
        declaration_regions,
        declaration_starts,
        region_hashes: region_hashes.into(),
        revision: 0,
        delta: None,
        source_export_mapping,
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
        files,
        source_by_path,
        body_by_declaration,
        issued_bodies: Arc::clone(&bodies),
        issued_body_codes,
        issued_settings: issued_settings.into(),
        bodies,
        emission_order: emission_order.into(),
    };
    if let Some(state) = semantic_state {
        let delta_started = Instant::now();
        frontend.revision = state.next_revision();
        frontend.delta = previous.as_ref().and_then(|previous| {
            delta::compute(previous, &frontend, &plan_reuse.regions, previous.revision, frontend.revision)
        });
        crate::change_set::record_outcome(match &frontend.delta {
            Some(delta) => format!(
                "frontend delta {}->{}: files={} declarations={} bodies={} in {:.3}s",
                delta.base,
                delta.revision,
                delta.files.len(),
                delta.declarations.len(),
                delta.bodies.len(),
                delta_started.elapsed().as_secs_f64()
            ),
            None => format!("frontend delta: none (revision {})", frontend.revision),
        });
    }
    Ok(frontend)
}

/// Every distinct file of the plan, in the order its first occurrence appears, with the text the
/// provider served for it.
fn build_source_index(
    plan: &DirectivePlan,
    sources: &BTreeMap<PathBuf, dm_preprocess::SourceText>,
) -> Result<(Vec<SourceFile>, Arc<HashMap<PathBuf, FileId>>), Vec<Diagnostic>> {
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
    Ok((files, Arc::new(by_path)))
}

/// A `"text [expression"` that never closes its `[`: DreamMaker reads the rest of the file as the expression, so the error
/// lands on the line after the including directive. An indented line also leaves its `{` block open at the end of the file,
/// which adds `end of file: expected }` there and `location of top-most unmatched {` at the first line of the outermost
/// open block (pinned 516.1681, fixtures/diagnostics/cases/string_embed_unterminated).
fn text_expression_diagnostics(
    mapping: &Mapping<'_>,
    diagnostic: &dm_preprocess::Diagnostic,
) -> Vec<Diagnostic> {
    let in_file = mapping.line(&diagnostic.path, diagnostic.line);
    let at_end = in_file.as_ref().and_then(|location| {
        let parent = mapping.plan.occurrences[location.include_occurrence].parent?;
        let mut end = location.clone();
        end.semantic_path = mapping.plan.occurrences[parent].semantic_path.clone();
        end.line = mapping.plan.occurrences[location.include_occurrence].directive_line + 1;
        Some(end)
    });
    let at_end = at_end.or_else(|| in_file.clone());
    let make = |message: &str, location: Option<SourceLocation>| Diagnostic {
        kind: DiagnosticKind::SourceError,
        stage: DiagnosticStage::Preprocess,
        message: message.into(),
        location,
    };
    let mut found = vec![make(&diagnostic.message, at_end.clone())];
    // The first indented code line after the last unindented one, up to the literal's line.
    let text = mapping
        .by_path
        .get(&diagnostic.path)
        .map(|file| mapping.files[file.index()].text.as_str().to_owned())
        .unwrap_or_default();
    let mut header = false;
    let mut block = None;
    for (index, line) in text.lines().enumerate().take(diagnostic.line) {
        let code = line.trim_start_matches([' ', '\t']);
        if code.trim().is_empty() || code.starts_with("//") {
            continue;
        }
        if code.len() == line.len() {
            header = true;
            block = None;
        } else if header && block.is_none() {
            block = Some(index + 1);
        }
    }
    if let Some(block) = block {
        found.push(make("end of file: expected }", at_end));
        found.push(make(
            "location of top-most unmatched {",
            mapping.line(&diagnostic.path, block),
        ));
    }
    found
}
