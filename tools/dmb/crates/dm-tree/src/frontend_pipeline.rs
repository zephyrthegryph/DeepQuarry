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
    semantic_state: Option<&mut RetainedSemanticTree>,
) -> Result<ColdFrontend, Vec<Diagnostic>> {
    build_with_executor_and_semantic_state_for_policy(
        project,
        provider,
        defines,
        config,
        memo,
        executor,
        semantic_state,
        false,
    )
}
/// Rich policy preparation shares the existing primary token query after a
/// portable declaration restore. No additional work for ordinary compilation.
pub fn build_with_executor_and_semantic_state_for_policy<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
    config: FrontendConfig<'_>,
    memo: Option<&dyn dm_preprocess::regions::ExpansionMemo>,
    executor: &dm_exec::BuildExecutor,
    semantic_state: Option<&mut RetainedSemanticTree>,
    require_primary_headers: bool,
) -> Result<ColdFrontend, Vec<Diagnostic>> {
    build_with_executor_and_semantic_state_for_policy_mode(
        project,
        provider,
        defines,
        config,
        memo,
        executor,
        semantic_state,
        require_primary_headers,
        None,
    )
}
/// Select this mode UP FRONT. Never retry a failed strict build as a checker
/// graph. It uses the exact same parser/adapter/builder and refuses all errors
/// outside the explicitly recorded inherited-VAR declaration domain. Original
/// unknown setting syntax is retained for checking and prevents compiler promotion.
pub fn build_for_checker_diagnostics<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
    config: FrontendConfig<'_>,
    memo: Option<&dyn dm_preprocess::regions::ExpansionMemo>,
    executor: &dm_exec::BuildExecutor,
) -> Result<DiagnosticFrontend, Vec<Diagnostic>> {
    if provider.initial_environment()==dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err(vec![Diagnostic{kind:DiagnosticKind::UnsupportedModel,stage:DiagnosticStage::Declaration,message:"Original diagnostic preparation is unissued without the actual checked native resource host".into(),location:None}])}

    let mut receipt = None;
    let frontend = build_with_executor_and_semantic_state_for_policy_mode(
        project,
        provider,
        defines,
        config,
        memo,
        executor,
        None,
        true,
        Some(&mut receipt),
    )?;
    DiagnosticFrontend::bind(
        frontend,
        receipt.ok_or_else(|| {
            vec![internal(
                "diagnostic builder did not issue its original graph receipt",
            )]
        })?,
    )
}
pub fn build_for_checker_diagnostics_with_state<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
    config: FrontendConfig<'_>,
    memo: Option<&dyn dm_preprocess::regions::ExpansionMemo>,
    executor: &dm_exec::BuildExecutor,
    state: Option<&mut RetainedSemanticTree>,
) -> Result<DiagnosticFrontend, Vec<Diagnostic>> {
    if provider.initial_environment()==dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err(vec![Diagnostic{kind:DiagnosticKind::UnsupportedModel,stage:DiagnosticStage::Declaration,message:"Original diagnostic preparation is unissued without the actual checked native resource host".into(),location:None}])}

    let mut receipt = None;
    let frontend = build_with_executor_and_semantic_state_for_policy_mode(
        project,
        provider,
        defines,
        config,
        memo,
        executor,
        state,
        true,
        Some(&mut receipt),
    )?;
    DiagnosticFrontend::bind(
        frontend,
        receipt.ok_or_else(|| {
            vec![internal(
                "diagnostic builder did not issue its original graph receipt",
            )]
        })?,
    )
}
/// Checked original declaration producer; caller supplies its existing host.
/// No source-root feature or request routing is enabled by this additive API.
pub fn build_with_executor_and_semantic_state_for_policy_checked<P:SourceProvider>(project:&Path,provider:&P,defines:&BTreeMap<String,String>,config:FrontendConfig<'_>,memo:Option<&dyn dm_preprocess::regions::ExpansionMemo>,executor:&dm_exec::BuildExecutor,state:Option<&mut RetainedSemanticTree>,require_primary_headers:bool,host:&Arc<dyn SettingExpressionQueries>)->Result<ColdFrontend,FrontendBuildFailure>{
    use super::declaration_demand::Demand;
    let demand=super::declaration_demand::Checked{host};
    let result=build_with_executor_and_semantic_state_for_policy_demand(project,provider,defines,config,memo,executor,state,require_primary_headers,None,&demand);
    demand.finish(result)
}
pub fn build_for_checker_diagnostics_with_state_checked<P:SourceProvider>(project:&Path,provider:&P,defines:&BTreeMap<String,String>,config:FrontendConfig<'_>,memo:Option<&dyn dm_preprocess::regions::ExpansionMemo>,executor:&dm_exec::BuildExecutor,state:Option<&mut RetainedSemanticTree>,host:&Arc<dyn SettingExpressionQueries>)->Result<DiagnosticFrontend,FrontendBuildFailure>{
    use super::declaration_demand::Demand;
    let demand=super::declaration_demand::Checked{host};
    let mut receipt=None;
    let result=(||{
        let frontend=build_with_executor_and_semantic_state_for_policy_demand(project,provider,defines,config,memo,executor,state,true,Some(&mut receipt),&demand)?;
        DiagnosticFrontend::bind(frontend,receipt.ok_or_else(||vec![internal("diagnostic builder did not issue its original graph receipt")])?).map_err(FrontendBuildFailure::from)
    })();
    demand.finish(result)
}
fn build_with_executor_and_semantic_state_for_policy_mode<P: SourceProvider>(
    project: &Path,
    provider: &P,
    defines: &BTreeMap<String, String>,
    config: FrontendConfig<'_>,
    memo: Option<&dyn dm_preprocess::regions::ExpansionMemo>,
    executor: &dm_exec::BuildExecutor,
    mut semantic_state: Option<&mut RetainedSemanticTree>,
    require_primary_headers: bool,
    diagnostic: Option<&mut Option<crate::diagnostic_declarations::DiagnosticDeclarationReceipt>>,
) -> Result<ColdFrontend, Vec<Diagnostic>> {
    build_with_executor_and_semantic_state_for_policy_demand(project,provider,defines,config,memo,executor,semantic_state,require_primary_headers,diagnostic,&super::declaration_demand::Compatibility)
}
fn build_with_executor_and_semantic_state_for_policy_demand<P:SourceProvider,D:super::declaration_demand::Demand>(project:&Path,provider:&P,defines:&BTreeMap<String,String>,config:FrontendConfig<'_>,memo:Option<&dyn dm_preprocess::regions::ExpansionMemo>,executor:&dm_exec::BuildExecutor,mut semantic_state:Option<&mut RetainedSemanticTree>,require_primary_headers:bool,diagnostic:Option<&mut Option<crate::diagnostic_declarations::DiagnosticDeclarationReceipt>>,demand:&D)->Result<ColdFrontend,D::Failure>{
    build_with_executor_and_semantic_state_for_policy_demand_role(project,provider,defines,config,memo,executor,semantic_state,require_primary_headers,diagnostic,demand,None)
}
fn build_with_executor_and_semantic_state_for_policy_demand_role<P:SourceProvider,D:super::declaration_demand::Demand>(project:&Path,provider:&P,defines:&BTreeMap<String,String>,config:FrontendConfig<'_>,memo:Option<&dyn dm_preprocess::regions::ExpansionMemo>,executor:&dm_exec::BuildExecutor,mut semantic_state:Option<&mut RetainedSemanticTree>,require_primary_headers:bool,diagnostic:Option<&mut Option<crate::diagnostic_declarations::DiagnosticDeclarationReceipt>>,demand:&D,original:Option<&mut Option<Arc<super::original_declaration_input::OriginalPrimaryRetention>>>)->Result<ColdFrontend,D::Failure>{
    demand.run(|permit|permit.checkpoint())?;
    let original_role=original.is_some();
    let original_mode=diagnostic.is_some()&&provider.initial_environment()==dm_preprocess::InitialEnvironment::OriginalChecker0290&&crate::checker_builtins::OriginalVariableDeclarations::for_seed(config.engine).is_some()&&demand.run(|permit|Ok(permit.original_primary_admitted()))?;
    if original_role&&provider.initial_environment()!=dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err(vec![internal("Original Analyze role requires its actual Original source environment")].into())}
    let declaration_request = if original_mode{None}else{semantic_state
        .as_ref()
        .and_then(|state| state.declarations.compatibility_request())};
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
    // SAME predecessor/engine/model cache, authenticated by its actual primary
    // outcome. Ordinary complete recipes cannot fabricate Original outcomes.
    let previous = if original_mode{semantic_state.as_ref().and_then(|state|state.previous_original_frontend(project,defines,original_role))}else{semantic_state
        .as_ref()
        .and_then(|state| state.previous_frontend(project,defines,provider.initial_environment(),diagnostic.is_some()))};
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
    crate::change_set::record_outcome(format!(
        "frontend source index {}: {:.3}s",
        if source_index_reused {
            "reused"
        } else {
            "built"
        },
        index_started.elapsed().as_secs_f64()
    ));
    let mapping = Mapping {
        projection: Default::default(),
        plan: plan.source_geometry(),
        expanded: &expanded,
        files: &files,
        by_path: &by_path,
        hints: Default::default(),
    };
    let mut text_expression_files = std::collections::HashSet::new();
    let mut diagnostics: Vec<_> = expanded
        .diagnostics
        .iter()
        .flat_map(|diagnostic| {
            if diagnostic.kind == dm_preprocess::DiagnosticKind::Macro
                && diagnostic
                    .message
                    .starts_with("unterminated text expression")
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
    // Current native preparation/planning/expansion has issued ALL new input
    // facts and acquisition leases. Reuse no program merely from a hash.
    drop(mapping);
    let admitted_previous=match previous.as_ref(){Some(old)=>demand.run(|permit|permit.syntax(&old.syntax))?,None=>false};
    let (plan, expanded, files, by_path, mut timings) = if diagnostics.is_empty() && admitted_previous
        && previous
            .as_ref()
            .zip(semantic_state.as_ref())
            .is_some_and(|(old, state)| state.admits_preparation_owner(old, config.engine))
    {
        let old = previous
            .as_ref()
            .expect("checked original remembered owner");
        match ColdFrontend::reissue_unchanged_program(
            old,
            plan,
            expanded,
            files,
            by_path,
            timings,
            require_primary_headers,
        ) {
            Ok(mut frontend) => {
                frontend.timings.total = total_start.elapsed();
                let frontend=demand.attach(frontend)?;
                demand.run(|permit|permit.checkpoint())?;
                if let Some(state) = semantic_state.as_deref_mut() {
                    state.record_original_program_reuse();
                }
                // Return through the same private branch below, never parse or
                // normalize an unchanged program a second time.
                if let Some(slot) = diagnostic {
                    let mut receipt=old.diagnostic_receipt(&frontend.snapshot.tree).ok_or_else(||vec![internal("unchanged diagnostic error owner no longer authenticates")])?;
                    receipt.retained_records=old.diagnostic_records();
                    // Renew only the actual previous declaration loan after the
                    // existing owner/engine/program reuse proof and current seed join.
                    if frontend.plan.initial_environment==dm_preprocess::InitialEnvironment::OriginalChecker0290&&crate::checker_builtins::OriginalVariableDeclarations::for_seed(config.engine).is_some(){receipt.original_variables=old.original_variables();}
                    *slot=Some(receipt);
                }
                if let Some(request) = &declaration_request {
                    request.publish_successful();
                }
                if let Some(slot)=original{*slot=old.original_primary();}
                return Ok(frontend);
            }
            Err(parts) => parts,
        }
    } else {
        (plan, expanded, files, by_path, timings)
    };
    let mapping = Mapping {
        projection: Default::default(),
        plan: plan.source_geometry(),
        expanded: &expanded,
        files: &files,
        by_path: &by_path,
        hints: Default::default(),
    };
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
    let (parsed,original_primary)=if original_mode{
        let prepared=demand.run(|permit|permit.original_analysis_declarations(&expanded,config.engine,previous.as_ref().map(|row|row.syntax.as_ref())))?;
        (prepared.parsed,Some(prepared.retention))
    }else{(declaration_parse::parse_declarations_with_demand_profile(&expanded,config,memo,executor,semantic_state.as_deref().map(|state|&state.declarations),demand,diagnostic.is_some())?,None)};
    let ParsedDeclarations {
        syntax,
        diagnostics: syntax_diagnostics,
        mut adapted,
        allocation_ledger,
        declaration_errors,
        reuse_stats,
    } = parsed;
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
                !(diagnostic
                    .message
                    .starts_with("unterminated text expression")
                    && diagnostic.location.as_ref().is_some_and(|location| {
                        text_expression_files.contains(location.path.as_path())
                    }))
            }),
    );
    let syntax = Arc::new(syntax);
    if original_mode&&!original_role{if let Some(primary)=&original_primary{if primary.frontier().is_some(){return Err(demand.run(|permit|permit.original_primary_failure(primary,&syntax,&mapping))?.into())}}}
    diagnostics.sort_by_key(|diagnostic| {
        diagnostic
            .location
            .as_ref()
            .map_or((usize::MAX, usize::MAX), |location| {
                (location.encounter_ordinal, location.line)
            })
    });
    if !diagnostics.is_empty() {
        demand.run(|permit|permit.checkpoint())?;
        return Err(diagnostics.into());
    }
    if !declaration_errors.is_empty() {
        demand.run(|permit|permit.checkpoint())?;
        let first_outer_block=if diagnostic.is_some()&&plan.initial_environment==dm_preprocess::InitialEnvironment::OriginalChecker0290{
            demand.run(|permit|syntax.first_original_outer_block_using(&||permit.checkpoint()))?.map_err(|reason|vec![internal(reason)])?
        }else{None};

        return Err(declaration_errors
            .into_iter()
            .map(|error| Diagnostic {
                kind: if diagnostic.is_some()&&plan.initial_environment==dm_preprocess::InitialEnvironment::OriginalChecker0290{error.original_fatal.and_then(|receipt|{
                    // SAME native original token/macro byte projection used by
                    // retained checker bodies; never derive a column by slicing.
                    let native=mapping.output(receipt.token_span().start)?;
                    let original=source_export_mapping::original_note_point_in(&expanded.origins,receipt.token_span().start,|region|{let include=mapping.plan.regions.get(region).ok_or("fatal original region absent")?.occurrence;let acquired=mapping.plan.source_acquisitions.get(&include).ok_or("fatal original source acquisition absent")?;Ok((include,acquired))},|include|Ok(&mapping.plan.occurrences.get(include).ok_or("fatal original include absent")?.path)).ok()?;
                    if native.path.as_path()!=original.path.as_path()||native.line!=original.line{return None}
                    Some(DiagnosticKind::OriginalFatalParameter{reason:receipt,byte_column:original.byte_column,indentation:receipt.prior_outer_block()||first_outer_block.is_some_and(|at|at<receipt.token_span().start)})
                }).unwrap_or_else(||syntax_kind(error.kind))}else{syntax_kind(error.kind)},
                stage: DiagnosticStage::Declaration,
                message: if let Some(receipt)=error.original_fatal{receipt.message()}else{error.message},
                location: mapping.output(if diagnostic.is_some()&&plan.initial_environment==dm_preprocess::InitialEnvironment::OriginalChecker0290{error.original_fatal.map_or(error.span.start as usize,|receipt|receipt.token_span().start)}else{error.span.start as usize}),
            })
            .collect::<Vec<_>>().into());
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
    let (expanded_spans, declaration_regions, current_origins) =
        project_declaration_origins(&mapping, &adapted.origins)?;
    adapted.origins = current_origins;
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
    let diagnostic_records = if original_primary.as_ref().is_some_and(|primary|primary.frontier().is_some()){None}else{diagnostic.as_ref().and_then(|_| {
        semantic_state.as_deref().and_then(|state| {
            super::DiagnosticRetainedRecords::capture(&adapted, config.engine, Some(state))
        })
    })};
    let snapshot = if let Some(slot) = diagnostic {
        let variables=if plan.initial_environment==dm_preprocess::InitialEnvironment::OriginalChecker0290{crate::checker_builtins::OriginalVariableDeclarations::for_seed(config.engine)}else{None};
        if variables.is_some(){dm_profile::request_mark("frontend.original_builtin_variable_declarations");}
        let prepared = if let Some(primary)=&original_primary{adapted.finish_original_diagnostic_with_variables(config.engine,on_error,executor,variables,Arc::clone(primary))}else{adapted.finish_checker_diagnostic_with_variables(config.engine,on_error,executor,variables)}
            .map_err(|_| {
                resolution_diagnostic
                    .take()
                    .expect("fatal diagnostic preparation notifies original observer")
            })?;
        let (snapshot, mut receipt) = prepared.into_parts();
        if receipt.errors().is_empty() {
            receipt.retained_records =
                diagnostic_records.map(|records| Arc::new(records.bind(&snapshot.tree)));
        }

        *slot = Some(receipt);
        snapshot
    } else {
        let snapshot = match semantic_state.as_deref_mut() {
            Some(state) => state.resolve(adapted, config.engine, on_error, executor),
            None => {
                adapted.finish_with_engine_observed_on_executor(config.engine, on_error, executor)
            }
        }
        .map_err(|_| resolution_diagnostic.expect("resolution failure must notify observer"))?;
        snapshot
    };
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
    let declarations_by_start=resolved_callable_declarations(&expanded_spans,&snapshot.tree);
    let mut bodies = Vec::new();
    let mut issued_settings = Vec::new();
    let mut body_codes = Vec::new();
    collect_bodies(
        &syntax,
        &snapshot.tree,
        &declarations_by_start,
        &mapping,
        &mut bodies,
        &mut issued_settings,
        &mut body_codes,
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
    let issued_body_codes = bodies
        .iter()
        .zip(body_codes)
        .map(|(body, identity)| body_code::BodyCodeOwner {
            identity,
            termination: dm_syntax::termination_after_with_context(
                &expanded.text,
                body.expanded_span.end,
                &|offset| syntax.declaration_header_at(offset),
            ),
        })
        .collect();
    let files: Arc<[SourceFile]> = files.into();
    let source_by_path = by_path;
    let declaration_qualifiers = expanded_spans
        .iter()
        .enumerate()
        .map(|(index, span)| match snapshot.tree.declarations()[index] {
            Target::Member(member)
                if snapshot
                    .tree
                    .member(member)
                    .is_some_and(|node| node.kind == MemberKind::Var) =>
            {
                if require_primary_headers {
                    syntax
                        .declaration_checker_qualifiers_at_for_policy(span.start as usize)
                        .unwrap_or(dm_syntax::UNKNOWN_HEADER_QUALIFIERS)
                } else {
                    dm_syntax::UNKNOWN_HEADER_QUALIFIERS
                }
            }
            _ => dm_syntax::UNKNOWN_HEADER_QUALIFIERS,
        })
        .collect::<Vec<_>>()
        .into_boxed_slice();
    let declaration_cursors = expanded_spans
        .into_iter()
        .enumerate()
        .map(|(index, span)| match snapshot.tree.declarations()[index] {
            Target::Member(member)
                if snapshot
                    .tree
                    .member(member)
                    .is_some_and(|node| node.kind == MemberKind::Var) =>
            {
                (if require_primary_headers {
                    syntax.declaration_cursor_at_for_policy(span.start as usize)
                } else {
                    syntax.declaration_cursor_at(span.start as usize)
                })
                .and_then(|at| u32::try_from(at).ok())
                .unwrap_or(u32::MAX)
            }
            _ => u32::MAX,
        })
        .collect::<Vec<_>>()
        .into_boxed_slice();
    let source_export_mapping = Arc::new(source_export_mapping::SourceExportMapping::capture(
        &plan,
        &expanded,
        &files,
        &source_by_path,
        &snapshot.occurrences,
        &snapshot.tree,
        declaration_cursors,
        declaration_qualifiers,
        original_primary.clone(),
    ));
    let mut frontend = ColdFrontend {
        original_primary:original_primary.clone(),
        body_queries: None,
        reused_body_queries: false,
        setting_expression_queries: None,
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
        body_by_declaration: Arc::new(
            bodies
                .iter()
                .enumerate()
                .map(|(index, body)| (body.declaration, index))
                .collect(),
        ),
        issued_bodies: Arc::clone(&bodies),
        issued_body_codes,
        issued_settings: issued_settings.into(),
        bodies,
        emission_order: emission_order.into(),
    };
    if require_primary_headers {
        frontend.issue_declaration_compatibility();
    }
    let frontend=demand.attach(frontend)?;
    demand.run(|permit|permit.checkpoint())?;
    if let Some(request)=&declaration_request{request.publish_successful();}
    if let Some(slot)=original{*slot=original_primary;}
    Ok(frontend)
}



pub(super) fn resolved_callable_declarations(spans:&[Span],tree:&crate::SemanticTree)->HashMap<usize,(OccurrenceId,MemberId)>{
    let declarations_by_start: HashMap<_, _> = spans
        .iter()
        .enumerate()
        .filter_map(|(index, span)| match tree.declarations()[index] {
            Target::Member(member)
                if matches!(
                    tree.member(member)?.kind,
                    MemberKind::Proc | MemberKind::Verb
                ) =>
            {
                Some((span.start as usize, (OccurrenceId(index as u32), member)))
            }
            _ => None,
        })
        .collect();
    declarations_by_start
}

/// SAME original provenance projector for complete and generation-only native
/// assembly. The borrowed mapping carries no compiler-completeness receipt.
pub(super) fn project_declaration_origins(
    mapping:&Mapping<'_>, origins:&crate::relative_origins::OriginRoster,
)->Result<(Vec<Span>,Vec<usize>,crate::relative_origins::OriginRoster),Vec<Diagnostic>> {
    let expanded_spans: Vec<_> = origins.iter().map(|origin| origin.span).collect();
    // Hash each original region once, not once for every declaration in it.
    let region_hashes: Vec<_> = mapping.plan
        .regions
        .iter()
        .map(|region| {
            let path = mapping.plan.occurrences[region.occurrence].path.as_ref();
            let file = mapping.by_path
                .get(path)
                .and_then(|id| mapping.files.get(id.index()))
                .ok_or_else(|| vec![internal("include region has no captured source")])?;
            file.text
                .span_fingerprint(region.source_span.range())
                .ok_or_else(|| vec![internal("include region lies outside captured source")])
        })
        .collect::<Result<Vec<_>, Vec<Diagnostic>>>()?;
    let mut declaration_regions = Vec::with_capacity(origins.len());
    let mut current_origins = Vec::with_capacity(origins.len());
    for origin in origins.iter() {
        let expanded_origin = mapping
            .origin(origin.span.start as usize)
            .ok_or_else(|| vec![internal("declaration has no current expansion origin")])?;
        // Declaration provenance needs the source span and occurrence, not a
        // complete diagnostic location (which also allocates an include chain).
        // Reuse the expansion lookup above instead of building that temporary.
        let file = mapping
            .file_of(expanded_origin.origin.path)
            .ok_or_else(|| vec![internal("declaration has no captured source file")])?;
        declaration_regions.push(expanded_origin.region);
        let span = source_span(file, expanded_origin.source_span)?;
        let include_occurrence = u32::try_from(mapping.plan.regions[expanded_origin.region].occurrence)
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
    Ok((expanded_spans, declaration_regions, current_origins.into()))

}

/// Every distinct file of the plan, in the order its first occurrence appears, with the text the
/// provider served for it.
fn build_source_index(
    plan: &DirectivePlan,
    sources: &BTreeMap<PathBuf, dm_preprocess::SourceText>,
) -> Result<(Vec<SourceFile>, Arc<HashMap<PathBuf, FileId>>), Vec<Diagnostic>> {
    build_source_index_geometry(plan.source_geometry(),sources,false)
}
pub(super) fn build_source_index_geometry(
    plan:dm_preprocess::regions::SourcePlanGeometry<'_>,
    sources:&BTreeMap<PathBuf,dm_preprocess::SourceText>,
    captured_only:bool,
)->Result<(Vec<SourceFile>,Arc<HashMap<PathBuf,FileId>>),Vec<Diagnostic>> {
    let mut files = Vec::new();
    let mut by_path = HashMap::new();
    for occurrence in plan.occurrences {
        // Generation has explicit negative occurrences, never empty files.
        // The ordinary path retains its existing non-text coordinate rows.
        if captured_only && !sources.contains_key(occurrence.path.as_ref()){continue}
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

/// Explicit Original Analyze purpose selected before the one native frontend
/// pass. Checker-fatal APIs and ordinary compiler admission remain unchanged.
pub fn build_for_original_analysis_with_state_checked<P:SourceProvider>(project:&Path,provider:&P,defines:&BTreeMap<String,String>,config:FrontendConfig<'_>,memo:Option<&dyn dm_preprocess::regions::ExpansionMemo>,executor:&dm_exec::BuildExecutor,state:Option<&mut RetainedSemanticTree>,host:&Arc<dyn SettingExpressionQueries>)->Result<DiagnosticFrontend,FrontendBuildFailure>{
 use super::declaration_demand::Demand;let demand=super::declaration_demand::Checked{host};let mut receipt=None;let mut primary=None;
 let result=(||{
  let frontend=build_with_executor_and_semantic_state_for_policy_demand_role(project,provider,defines,config,memo,executor,state,true,Some(&mut receipt),&demand,Some(&mut primary))?;
  let diagnostic=DiagnosticFrontend::bind(frontend,receipt.ok_or_else(||vec![internal("original analysis builder lacks its actual native graph receipt")])?).map_err(FrontendBuildFailure::from)?;
  diagnostic.bind_original_primary(primary.ok_or_else(||vec![internal("original analysis builder lacks its actual primary preparation owner")])?).map_err(FrontendBuildFailure::from)
 })();demand.finish(result)
}
