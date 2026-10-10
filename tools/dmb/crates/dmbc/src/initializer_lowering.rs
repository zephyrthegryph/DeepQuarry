//! Cold initializer artifacts from captured authored writes and explicit ABI
//! classification. No mutable DMB, filesystem reads or project binding copies.
use crate::debug_sources::{DebugOrigin, DebugOriginProvider, DebugOrigins};
use crate::initializer_diagnostics::{map_captured_lower_errors, InitializerLoweringError};
use crate::initializer_policy::{
    self, CapturedInitializerEvaluator, ClassifiedInitializers, RuntimeValue,
};
use dm_codegen_byond::{initializer::InitializerContext, DebugSourceProvider};
use dm_ir::{InitializerScope, Resolver};
use dm_tree::{frontend::ColdFrontend, initializers::InitializerPlan};
use std::sync::Arc;
#[path = "initializer_fragments.rs"]
mod fragments;
#[path = "initializer_receipts.rs"]
pub(crate) mod receipts;
pub use fragments::InitializerFragments;
#[path = "initializer_assemblies.rs"]
mod assemblies;
pub use assemblies::InitializerAssemblies;

#[derive(Clone, Copy, Debug)]
pub enum InitializerStage {
    Classification,
    Codegen,
}
pub type InitializerMeasurement = crate::stage_measurements::Measurement<InitializerStage>;
impl crate::stage_measurements::StageName for InitializerStage {
    fn profile_name(self) -> &'static str {
        match self {
            Self::Classification => "initializer.classification",
            Self::Codegen => "initializer.codegen",
        }
    }
}
pub type InitializerObserver<'a> = crate::stage_measurements::Observer<'a, InitializerStage>;

/// Issued only after current declaration/provenance validation by lower_group.
#[derive(Clone)]
pub struct DeclarationPresence {
    owner: dm_ir::SymbolId,
    source_ordinal: usize,
    classified_ordinal: usize,
}
impl DeclarationPresence {
    pub(crate) fn owner(&self) -> dm_ir::SymbolId {
        self.owner
    }
    pub(crate) fn source_ordinal(&self) -> usize {
        self.source_ordinal
    }
    pub(crate) fn classified_ordinal(&self) -> usize {
        self.classified_ordinal
    }
}
pub struct LoweredInitializerUnit {
    pub(crate) declaration_presence: Option<DeclarationPresence>,
    pub scope: InitializerScope,
    /// Exact selected source writes, in executable order after ABI phasing.
    pub write_ordinals: Vec<usize>,
    pub code: crate::InitializerCode,
    pub debug_origins: DebugOrigins,
    pub(crate) encoding: Option<Arc<crate::symbolic::InitializerEncoding>>,
}
pub struct LoweredInitializers {
    pub classified: ClassifiedInitializers,
    pub units: Vec<LoweredInitializerUnit>,
}
struct CapturedOrigins {
    origins: DebugOrigins,
}
impl DebugSourceProvider for CapturedOrigins {
    fn entry_ordinal(&self) -> Result<u32, String> {
        Ok(0)
    }
    fn ordinal(&self, write_ordinal: usize) -> Result<u32, String> {
        if write_ordinal >= self.origins.entries.len() {
            return Err("initializer debug occurrence missing".into());
        }
        u32::try_from(write_ordinal).map_err(|_| "initializer debug ordinal exceeds u32".into())
    }
}
fn value_expression(value: &RuntimeValue) -> std::borrow::Cow<'_, dm_syntax::Expr> {
    use dm_syntax::{Expr, ExprKind, Span};
    match value {
        RuntimeValue::Expression(value) => std::borrow::Cow::Borrowed(value.as_ref()),
        RuntimeValue::SizedArrayExplicit {
            expression: Some(expression),
            ..
        } => std::borrow::Cow::Borrowed(expression),
        RuntimeValue::SizedArrayExplicit {
            expression: None, ..
        } => std::borrow::Cow::Owned(Expr {
            span: Span::new(0, 0),
            kind: ExprKind::Literal("null".into()),
        }),
        RuntimeValue::SizedArray(dimensions) => {
            // A policy-issued typed constructor; no DM source is generated.
            let span = Span::new(0, 0);
            std::borrow::Cow::Owned(Expr {
                span,
                kind: ExprKind::Unary {
                    op: "new".into(),
                    value: Box::new(Expr {
                        span,
                        kind: ExprKind::Call {
                            callee: Box::new(Expr {
                                span,
                                kind: ExprKind::TypePath("/list".into()),
                            }),
                            args: dimensions
                                .iter()
                                .map(|size| Expr {
                                    span,
                                    kind: ExprKind::Literal(size.to_string()),
                                })
                                .collect(),
                        },
                    }),
                },
            })
        }
    }
}
pub fn lower<R: Resolver>(
    frontend: &ColdFrontend,
    plan: &InitializerPlan,
    evaluator: &dyn CapturedInitializerEvaluator,
    host: &R,
    resource_search_context: Option<u128>,
) -> Result<LoweredInitializers, InitializerLoweringError> {
    lower_plan(
        (frontend, plan),
        evaluator,
        host,
        resource_search_context,
        true,
        LowerOptions {
            allocation: None,
            observer: None,
            classification: None,
            memo: None,
            parallel: None,
            executor: None,
        },
    )
}

pub fn lower_captured<R: Resolver>(
    frontend: &ColdFrontend,
    startup: &crate::startup::CapturedStartup<'_>,
    evaluator: &dyn CapturedInitializerEvaluator,
    host: &R,
    resource_search_context: Option<u128>,
) -> Result<LoweredInitializers, InitializerLoweringError> {
    lower_captured_observed(
        frontend,
        startup,
        evaluator,
        host,
        resource_search_context,
        None,
    )
}
pub fn lower_captured_observed_memo<R: Resolver>(
    frontend: &ColdFrontend,
    startup: &crate::startup::CapturedStartup<'_>,
    evaluator: &dyn CapturedInitializerEvaluator,
    host: &R,
    resource_search_context: Option<u128>,
    observer: Option<&InitializerObserver<'_>>,
    memo: Option<&crate::lowering_memo::ProcedureMemo>,
) -> Result<LoweredInitializers, InitializerLoweringError> {
    startup.validate_for(frontend)?;
    lower_plan(
        (frontend, startup.plan()),
        evaluator,
        host,
        resource_search_context,
        false,
        LowerOptions {
            allocation: None,
            observer,
            classification: None,
            memo,
            parallel: None,
            executor: None,
        },
    )
}
pub fn lower_captured_observed<R: Resolver>(
    frontend: &ColdFrontend,
    startup: &crate::startup::CapturedStartup<'_>,
    evaluator: &dyn CapturedInitializerEvaluator,
    host: &R,
    resource_search_context: Option<u128>,
    observer: Option<&InitializerObserver<'_>>,
) -> Result<LoweredInitializers, InitializerLoweringError> {
    lower_captured_observed_memo(
        frontend,
        startup,
        evaluator,
        host,
        resource_search_context,
        observer,
        None,
    )
}

pub struct InitializerExecution<'a> {
    pub executor: &'a dm_exec::BuildExecutor,
    pub evaluator: Option<initializer_policy::ParallelEvaluator<'a>>,
    pub observer: Option<&'a InitializerObserver<'a>>,
    pub memo: Option<&'a crate::lowering_memo::ProcedureMemo>,
    pub classification: Option<initializer_policy::InitializerReuse<'a>>,
}
struct LowerOptions<'a> {
    allocation: Option<&'a crate::startup_allocation::StartupAllocationRoster>,
    classification: Option<initializer_policy::InitializerReuse<'a>>,
    observer: Option<&'a InitializerObserver<'a>>,
    memo: Option<&'a crate::lowering_memo::ProcedureMemo>,
    executor: Option<&'a dm_exec::BuildExecutor>,
    parallel: Option<(
        initializer_policy::ParallelEvaluator<'a>,
        &'a dm_exec::BuildExecutor,
    )>,
}
pub fn lower_captured_observed_memo_on_executor<R: Resolver>(
    frontend: &ColdFrontend,
    startup: &crate::startup::CapturedStartup<'_>,
    evaluator: &dyn CapturedInitializerEvaluator,
    host: &R,
    resource_search_context: Option<u128>,
    execution: InitializerExecution<'_>,
) -> Result<LoweredInitializers, InitializerLoweringError> {
    lower_captured_on_executor_with_allocation(
        frontend,
        startup,
        evaluator,
        host,
        resource_search_context,
        execution,
        None,
    )
}
pub(crate) fn lower_captured_on_executor_with_allocation<R: Resolver>(
    frontend: &ColdFrontend,
    startup: &crate::startup::CapturedStartup<'_>,
    evaluator: &dyn CapturedInitializerEvaluator,
    host: &R,
    resource_search_context: Option<u128>,
    execution: InitializerExecution<'_>,
    allocation: Option<&crate::startup_allocation::StartupAllocationRoster>,
) -> Result<LoweredInitializers, InitializerLoweringError> {
    startup.validate_for(frontend)?;
    lower_plan(
        (frontend, startup.plan()),
        evaluator,
        host,
        resource_search_context,
        false,
        LowerOptions {
            allocation,
            observer: execution.observer,
            classification: execution.classification,
            executor: Some(execution.executor),
            memo: execution.memo,
            parallel: execution
                .evaluator
                .map(|evaluator| (evaluator, execution.executor)),
        },
    )
}

fn lower_plan<R: Resolver>(
    captured: (&ColdFrontend, &InitializerPlan),
    evaluator: &dyn CapturedInitializerEvaluator,
    host: &R,
    resource_search_context: Option<u128>,
    validate_statics: bool,
    options: LowerOptions<'_>,
) -> Result<LoweredInitializers, InitializerLoweringError> {
    let (frontend, plan) = captured;
    let LowerOptions {
        allocation,
        classification: reuse,
        observer,
        memo,
        parallel,
        executor,
    } = options;
    if frontend.snapshot.tree.identity() != plan.source.tree.identity()
        || frontend.snapshot.occurrences.tree_identity() != plan.source.occurrences.tree_identity()
        || plan.writes.len() != plan.origins.len()
    {
        return Err("initializer plan differs from captured frontend".into());
    }
    if validate_statics
        && plan.origins.iter().any(|origin| {
            matches!(
                origin.kind,
                dm_tree::initializers::InitializerOriginKind::ProcedureStatic { .. }
            )
        })
    {
        crate::startup::validate(frontend, plan)?;
    }
    let symbols = plan.symbols.as_ref();
    let measurement =
        crate::stage_measurements::Scope::new(observer, InitializerStage::Classification);
    let debug_defined = frontend.plan.final_macros.contains_key("DEBUG");
    let classification = match (parallel, reuse) {
        (Some((context, executor)), Some(reuse)) => {
            initializer_policy::classify_with_reuse_on_executor(
                &plan.writes,
                symbols,
                context,
                debug_defined,
                executor,
                reuse,
            )
        }
        (Some((context, executor)), None) => {
            initializer_policy::classify_with_token_mode_on_executor(
                &plan.writes,
                symbols,
                context,
                debug_defined,
                executor,
            )
        }
        (None, _) => initializer_policy::classify_with_token_mode(
            &plan.writes,
            symbols,
            evaluator,
            debug_defined,
        ),
    };
    let mut classified = match classification {
        Ok(classified) => classified,
        Err(error) => {
            let ordinals = error
                .issues
                .iter()
                .map(|issue| issue.source_ordinal)
                .collect::<Vec<_>>();
            let errors = error
                .issues
                .into_iter()
                .enumerate()
                .map(|(local, issue)| dm_codegen_byond::LowerError {
                    // Certified source text already has its language-level
                    // wording; internal stage context belongs to unsupported errors.
                    statement: match issue.kind {
                        crate::initializer_policy::ClassificationIssueKind::SourceError => {
                            String::new()
                        }
                        crate::initializer_policy::ClassificationIssueKind::Unsupported => {
                            "initializer classification".into()
                        }
                    },
                    reason: issue.reason,
                    kind: match issue.kind {
                        crate::initializer_policy::ClassificationIssueKind::SourceError => {
                            dm_codegen_byond::LowerErrorKind::SourceError
                        }
                        crate::initializer_policy::ClassificationIssueKind::Unsupported => {
                            dm_codegen_byond::LowerErrorKind::UnsupportedModel
                        }
                    },
                    span: Some(dm_codegen_byond::LowerSpan {
                        start: local,
                        end: local,
                    }),
                })
                .collect();
            return Err(InitializerLoweringError::Diagnostics(
                map_captured_lower_errors(errors, frontend, plan, &ordinals)?,
            ));
        }
    };
    if let Some(allocation) = allocation {
        allocation.order_runtime(plan, &mut classified, host)?;
    }
    measurement.complete();
    let measurement = crate::stage_measurements::Scope::new(observer, InitializerStage::Codegen);
    let fragment_store = memo.and_then(|memo| memo.initializer_fragments.as_deref());
    let assembly_store = memo.and_then(|memo| memo.initializer_assemblies.as_deref());
    let fragment_keys =
        if let Some(memo) = memo.filter(|_| fragment_store.is_some() || assembly_store.is_some()) {
            let keys = fragments::current_keys(&classified, memo.policy, resource_search_context)?;
            if let Some(store) = fragment_store {
                store.retain_keys(&keys);
            }
            Some(keys)
        } else {
            None
        };
    let assembly_keys = assembly_store
        .zip(fragment_keys.as_ref())
        .map(|(store, keys)| {
            let keys = assemblies::current_keys(&classified, keys)?;
            store.retain_keys(&keys);
            Ok::<_, String>(keys)
        })
        .transpose()?;
    let lower_one = |index: usize| {
        let _profile = dm_profile::stage("initializer.codegen_group");
        lower_group(
            frontend,
            plan,
            &classified,
            &classified.groups[index],
            host,
            resource_search_context,
            memo,
            fragment_store.zip(fragment_keys.as_ref()),
            assembly_store
                .zip(assembly_keys.as_ref())
                .map(|(store, keys)| (store, &keys[index])),
        )
    };
    let units =
        match executor.filter(|executor| executor.workers() > 1 && classified.groups.len() > 1) {
            Some(executor) => {
                parallel_groups::ordered_jobs(classified.groups.len(), executor, lower_one)
                    .map_err(InitializerLoweringError::from)?
                    .into_iter()
                    .collect::<Result<Vec<_>, _>>()?
            }
            None => (0..classified.groups.len())
                .map(lower_one)
                .collect::<Result<Vec<_>, _>>()?,
        };
    measurement.complete();
    Ok(LoweredInitializers { classified, units })
}

#[path = "initializer_parallel_groups.rs"]
mod parallel_groups;

#[cfg(test)]
#[path = "initializer_presence_tests.rs"]
mod presence_tests;

fn lower_group<R: Resolver>(
    frontend: &ColdFrontend,
    plan: &InitializerPlan,
    classified: &ClassifiedInitializers,
    group: &initializer_policy::RuntimeGroup,
    host: &R,
    resource_search_context: Option<u128>,
    memo: Option<&crate::lowering_memo::ProcedureMemo>,
    fragments: Option<(
        &InitializerFragments,
        &std::collections::HashMap<usize, receipts::Binding>,
    )>,
    assembly: Option<(&InitializerAssemblies, &receipts::Binding)>,
) -> Result<LoweredInitializerUnit, InitializerLoweringError> {
    let symbols = plan.symbols.as_ref();
    let mut entries = Vec::with_capacity(group.writes.len());
    let mut write_ordinals = Vec::with_capacity(group.writes.len());
    let mut declaration_presence = None;
    for &write_index in group.writes.iter().chain(group.declaration_presence.iter()) {
        let write = classified
            .writes
            .get(write_index)
            .ok_or("initializer group write missing")?;
        if plan.writes.get(write.source_ordinal) != Some(&write.write) {
            return Err("initializer write differs from current source ledger".into());
        }
        let origin = plan
            .origins
            .get(write.source_ordinal)
            .ok_or("initializer origin missing")?;
        let current = frontend
            .snapshot
            .occurrences
            .get(origin.occurrence)
            .ok_or("initializer current occurrence missing")?;
        let expected_member = match &origin.kind {
            dm_tree::initializers::InitializerOriginKind::Declaration(member) => *member,
            dm_tree::initializers::InitializerOriginKind::ProcedureStatic { identity, .. } => {
                let dm_tree::Target::Member(member) = current.target else {
                    return Err("static origin is not a procedure".into());
                };
                let node = frontend
                    .snapshot
                    .tree
                    .member(member)
                    .ok_or("static procedure missing")?;
                let owner = frontend
                    .snapshot
                    .tree
                    .type_node(node.owner)
                    .ok_or("static owner missing")?
                    .path;
                if owner != identity.procedure.owner
                    || node.name != identity.procedure.name
                    || (node.kind == dm_tree::MemberKind::Verb) != identity.procedure.verb
                    || node.kind == dm_tree::MemberKind::Var
                {
                    return Err("static origin procedure differs".into());
                }
                member
            }
        };
        if current.target != dm_tree::Target::Member(expected_member)
            || current.provenance.span != origin.provenance.span
            || current.provenance.include_occurrence != origin.provenance.include_occurrence
            || current.provenance.region != origin.provenance.region
            || current.provenance.expansion_stack != origin.provenance.expansion_stack
        {
            return Err("initializer source provenance differs from current occurrence".into());
        }
        let occurrence = frontend
            .plan
            .occurrences
            .get(origin.provenance.include_occurrence as usize)
            .ok_or("initializer include occurrence missing")?;
        let file = frontend
            .files
            .get(origin.provenance.span.file.index())
            .ok_or("initializer source file missing")?;
        if file.path.as_ref() != occurrence.path.as_ref() || !file.captured {
            return Err("initializer origin does not bind captured source".into());
        }
        let offset = origin.provenance.span.start as usize;
        if offset > file.text.len() {
            return Err("initializer source span out of bounds".into());
        }
        let line = file.line_starts.partition_point(|start| *start <= offset);
        if group.declaration_presence == Some(write_index) && group.writes.is_empty() {
            let dm_ir::InitializerTarget::Instance { receiver_owner, .. } = write.write.target
            else {
                return Err("declaration presence is not an instance field".into());
            };
            if Some(receiver_owner) != group.receiver
                || write.write.source_site != dm_ir::InitializerSite::Declaration
                || write.phase.is_some()
                || !matches!(write.write.value, dm_ir::InitializerValue::NoAuthoredValue)
                || !write.write.declared_array.as_ref().is_some_and(|array| {
                    array.dimensions.len() == 1 && array.dimensions[0].is_none()
                })
                || !matches!(
                    origin.kind,
                    dm_tree::initializers::InitializerOriginKind::Declaration(_)
                )
            {
                return Err("declaration presence differs from current unsized field".into());
            }
            declaration_presence = Some(DeclarationPresence {
                owner: receiver_owner,
                source_ordinal: write.source_ordinal,
                classified_ordinal: write_index,
            });
            continue;
        }
        if group.declaration_presence == Some(write_index) && !group.writes.contains(&write_index) {
            continue;
        }

        if let dm_tree::initializers::InitializerOriginKind::ProcedureStatic {
            expanded_span, ..
        } = &origin.kind
        {
            entries.push(frontend.origin(expanded_span.start)?);
        } else {
            entries.push(DebugOrigin {
                semantic_path: occurrence.semantic_path.clone(),
                line: u32::try_from(line).map_err(|_| "initializer source line exceeds u32")?,
            });
        }
        // Presence is mandatory even when the admitted assembly needs no AST roots.
        write
            .runtime_value
            .as_ref()
            .ok_or("initializer runtime value missing")?;
        write_ordinals.push(write.source_ordinal);
    }
    let debug = CapturedOrigins {
        origins: DebugOrigins { entries },
    };
    // Current classification and provenance are always validated above.
    // Exact authored values and policy-issued array dimensions describe the
    // executable inputs; local debug ordinals are reconstructed every build.
    let context = || InitializerContext {
        symbols,
        resource_search_context,
        // Presence-only groups have no executable source occurrence.
        debug: (!group.writes.is_empty()).then_some(&debug),
    };
    let map_error = |error| match error {
        dm_codegen_byond::initializer::InitializerError::Unsupported(message) => {
            InitializerLoweringError::Unsupported(message)
        }
        dm_codegen_byond::initializer::InitializerError::Invalid(message) => {
            InitializerLoweringError::Invariant(message)
        }
        dm_codegen_byond::initializer::InitializerError::Lowering(errors) => {
            match map_captured_lower_errors(errors, frontend, plan, &write_ordinals) {
                Ok(diagnostics) => InitializerLoweringError::Diagnostics(diagnostics),
                Err(error) => error,
            }
        }
    };
    if let Some((store, key)) = assembly {
        if let Some((code, encoding)) = store.lookup_with_current_roots(
            key,
            group.writes.len(),
            |index| {
                let write = classified.writes.get(*group.writes.get(index)?)?;
                Some(value_expression(write.runtime_value.as_ref()?))
            },
            symbols,
            host,
        ) {
            return Ok(LoweredInitializerUnit {
                declaration_presence,
                scope: group
                    .receiver
                    .map(InitializerScope::Instance)
                    .unwrap_or(InitializerScope::Global),
                write_ordinals,
                code: crate::InitializerCode::from_admitted(code, encoding.type_requests()),
                debug_origins: debug.origins,
                encoding: Some(encoding),
            });
        }
    }
    let assignments = group
        .writes
        .iter()
        .map(|&index| {
            let write = &classified.writes[index];
            let value = value_expression(
                write
                    .runtime_value
                    .as_ref()
                    .expect("current runtime presence validated above"),
            );
            (&write.write.target, write.write.lexical_owner, value)
        })
        .collect::<Vec<_>>();
    let value_continuations = group
        .writes
        .iter()
        .map(
            |&index| match classified.writes[index].runtime_value.as_ref() {
                Some(RuntimeValue::SizedArrayExplicit {
                    dimensions,
                    expression,
                }) => Some(dm_codegen_byond::initializer::ValueContinuation {
                    dimensions,
                    before_assignment: group.receiver.is_none(),
                    emit_assignment: expression.is_some(),
                    assignment_is_allocation: false,
                }),
                Some(RuntimeValue::SizedArray(dimensions)) => {
                    Some(dm_codegen_byond::initializer::ValueContinuation {
                        dimensions,
                        before_assignment: false,
                        emit_assignment: true,
                        assignment_is_allocation: true,
                    })
                }
                _ => None,
            },
        )
        .collect::<Vec<_>>();
    let assignment_views = assignments
        .iter()
        .enumerate()
        .map(|(index, (target, lexical_owner, value))| {
            dm_codegen_byond::initializer::AssignmentView {
                source_site: classified.writes[group.writes[index]].write.source_site,
                target,
                lexical_owner: *lexical_owner,
                value: value.as_ref(),
                occurrence: dm_syntax::Span::new(index, index),
            }
        })
        .collect::<Vec<_>>();
    let assembly_recorder = assembly.map(|_| crate::lowering_memo::RecordingResolver::new(host));
    if let Some(recorder) = &assembly_recorder {
        for &index in &group.writes {
            let write = &classified.writes[index].write;
            recorder.resolve(dm_ir::ResolveQuery::Ancestry(write.lexical_owner));
            if let Some(identity) = write.lexical_procedure {
                recorder.record_occurrence(identity);
            }
        }
    }
    let observed_host = assemblies::AssemblyHost {
        original: host,
        recorder: assembly_recorder.as_ref(),
    };
    let host = &observed_host;
    let mut assembled_recipes = None;
    let code = if let Some((store, keys)) = fragments {
        let prepared = dm_codegen_byond::initializer::prepare_assignment_group(
            &assignment_views,
            context(),
            host,
        )
        .and_then(|prepared| prepared.with_value_continuations(value_continuations.clone()))
        .map_err(map_error)?;
        let mut continuations = Vec::with_capacity(group.writes.len());
        let mut recipe_fragments = Vec::with_capacity(group.writes.len());
        let mut unsupported = false;
        for (index, &write_index) in group.writes.iter().enumerate() {
            let write = &classified.writes[write_index];
            let key = keys
                .get(&write.source_ordinal)
                .ok_or("initializer fragment key missing")?;
            let fragment = store
                .fragment_with_recipes(key, &prepared, index, &write.write, host)
                .map_err(|mut error| {
                    if let dm_codegen_byond::initializer::InitializerError::Lowering(errors) =
                        &mut error
                    {
                        for diagnostic in errors {
                            if let Some(span) = &mut diagnostic.span {
                                // Fragment producer errors bind its single assignment.
                                if span.start == 0 && span.end == 0 {
                                    span.start = index;
                                    span.end = index;
                                }
                            }
                        }
                    }
                    map_error(error)
                })?;
            let Some(fragment) = fragment else {
                unsupported = true;
                break;
            };
            let mut recipes = fragment.recipes.map(|recipes| {
                recipes
                    .into_iter()
                    .map(|recipe| (recipe.reference(), recipe))
                    .collect::<std::collections::BTreeMap<_, _>>()
            });
            let entries = fragment
                .code
                .code()
                .modified_instances
                .keys()
                .map(|reference| {
                    (
                        *reference,
                        recipes
                            .as_mut()
                            .and_then(|recipes| recipes.remove(reference)),
                    )
                })
                .collect();
            recipe_fragments.push((index, entries));
            continuations.push(fragment.code);
        }
        if unsupported {
            dm_codegen_byond::initializer::lower_with_value_continuations(
                &assignment_views,
                context(),
                host,
                value_continuations.clone(),
            )
            .map_err(map_error)?
        } else {
            match prepared.assemble(continuations) {
                Ok(code) => {
                    assembled_recipes = recipe_handoff::first_placements(
                        recipe_fragments,
                        code.modified_instances.keys().copied(),
                    )
                    .and_then(|placements| {
                        placements
                            .into_iter()
                            .map(|(_, index, recipe)| {
                                Some((
                                    index,
                                    recipe.with_assignment_origin(u32::try_from(index).ok()?),
                                ))
                            })
                            .collect::<Option<Vec<_>>>()
                    });
                    code
                }
                Err(_) => {
                    // Cross-fragment collisions use the established producer's
                    // exact diagnostics rather than introducing a new failure.
                    dm_codegen_byond::initializer::lower_with_value_continuations(
                        &assignment_views,
                        context(),
                        host,
                        value_continuations.clone(),
                    )
                    .map_err(map_error)?
                }
            }
        }
    } else if let Some(memo) = memo {
        let mut key = b"dmbc-anonymous-declaration-v3-sized-continuations\0".to_vec();
        key.extend_from_slice(&memo.policy.to_le_bytes());
        key.extend_from_slice(
            &serde_json::to_vec(&resource_search_context).map_err(|error| error.to_string())?,
        );
        for &write_index in &group.writes {
            let write = classified
                .writes
                .get(write_index)
                .ok_or("initializer group write missing")?;
            let bytes = write.write.canonical_bytes();
            key.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
            key.extend_from_slice(&bytes);
            match write
                .runtime_value
                .as_ref()
                .ok_or("initializer runtime value missing")?
            {
                RuntimeValue::Expression(_) => key.push(0),
                RuntimeValue::SizedArray(dimensions)
                | RuntimeValue::SizedArrayExplicit { dimensions, .. } => {
                    key.push(
                        if matches!(
                            write.runtime_value,
                            Some(RuntimeValue::SizedArrayExplicit { .. })
                        ) {
                            2
                        } else {
                            1
                        },
                    );
                    key.extend_from_slice(&(dimensions.len() as u64).to_le_bytes());
                    for dimension in dimensions.iter() {
                        key.extend_from_slice(&dimension.to_le_bytes());
                    }
                }
            }
        }
        for origin in &debug.origins.entries {
            key.extend_from_slice(&(origin.semantic_path.len() as u64).to_le_bytes());
            key.extend_from_slice(origin.semantic_path.as_bytes());
        }
        // Stored reads (including mandatory ancestry/override facts) are
        // validated by the lookup. A hit does not build a second recorder.
        let replay = memo.lookup_anonymous(&key, host, debug.origins.entries.len());
        if let Some(errors) = replay.errors {
            if errors.iter().all(|error| {
                error
                    .span
                    .is_none_or(|span| span.start <= span.end && span.end < write_ordinals.len())
            }) {
                return Err(map_error(
                    dm_codegen_byond::initializer::InitializerError::Lowering(errors),
                ));
            }
        }
        if let Some(code) = replay.code {
            code
        } else {
            let recorder = crate::lowering_memo::RecordingResolver::new(host);
            for &write_index in &group.writes {
                let write = classified
                    .writes
                    .get(write_index)
                    .ok_or("initializer group write missing")?;
                recorder.resolve(dm_ir::ResolveQuery::Ancestry(write.write.lexical_owner));
                if let Some(identity) = write.write.lexical_procedure {
                    recorder.record_occurrence(identity);
                }
            }
            let code = dm_codegen_byond::initializer::lower_with_value_continuations(
                &assignment_views,
                context(),
                &recorder,
                value_continuations.clone(),
            )
            .map_err(|error| {
                if let dm_codegen_byond::initializer::InitializerError::Lowering(errors) = &error {
                    if errors.iter().all(|error| {
                        error.span.is_none_or(|span| {
                            span.start <= span.end && span.end < write_ordinals.len()
                        })
                    }) {
                        memo.remember_failure(
                            &key,
                            None,
                            &recorder.reads(),
                            errors,
                            &recorder.domain_receipts(),
                        );
                    }
                }
                map_error(error)
            })?;
            memo.remember_executable(&key, &recorder.reads(), &code, &recorder.domain_receipts());
            code
        }
    } else {
        // Cold oracle path performs no cache key, serialization, extra
        // ancestry reads or recording allocation.
        dm_codegen_byond::initializer::lower_with_value_continuations(
            &assignment_views,
            context(),
            host,
            value_continuations.clone(),
        )
        .map_err(map_error)?
    };
    let encoding =
        if let (Some((store, key)), Some(recorder)) = (assembly, assembly_recorder.as_ref()) {
            store.remember_with_recipes(key, &code, &assignment_views, recorder, assembled_recipes)
        } else {
            None
        };
    Ok(LoweredInitializerUnit {
        declaration_presence,
        scope: group
            .receiver
            .map(InitializerScope::Instance)
            .unwrap_or(InitializerScope::Global),
        write_ordinals,
        code: match &encoding {
            Some(owner) => crate::InitializerCode::from_admitted(code, owner.type_requests()),
            None => code.into(),
        },
        debug_origins: debug.origins,
        encoding,
    })
}

#[path = "initializer_recipe_handoff.rs"]
mod recipe_handoff;
