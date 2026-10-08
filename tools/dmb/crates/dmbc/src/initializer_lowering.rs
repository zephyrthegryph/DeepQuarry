//! Cold initializer artifacts from captured authored writes and explicit ABI
//! classification. No mutable DMB, filesystem reads or project binding copies.
use crate::debug_sources::{DebugOrigin, DebugOriginProvider, DebugOrigins};
use crate::initializer_diagnostics::{map_captured_lower_errors, InitializerLoweringError};
use crate::initializer_policy::{
    self, CapturedInitializerEvaluator, ClassifiedInitializers, RuntimeValue,
};
use dm_codegen_byond::{
    initializer::InitializerContext, lower_resolver::ResolverProc, DebugSourceProvider,
};
use dm_ir::{InitializerScope, Resolver};
use dm_tree::{frontend::ColdFrontend, initializers::InitializerPlan};

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

pub struct LoweredInitializerUnit {
    pub scope: InitializerScope,
    /// Exact selected source writes, in executable order after ABI phasing.
    pub write_ordinals: Vec<usize>,
    pub code: ResolverProc,
    pub debug_origins: DebugOrigins,
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
fn value_expression(value: &RuntimeValue) -> dm_syntax::Expr {
    use dm_syntax::{Expr, ExprKind, Span};
    match value {
        RuntimeValue::Expression(value) => value.clone(),
        RuntimeValue::SizedArray(dimensions) => {
            // A policy-issued typed constructor; no DM source is generated.
            let span = Span::new(0, 0);
            Expr {
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
            }
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
        None,
        None,
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
        observer,
        memo,
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

fn lower_plan<R: Resolver>(
    captured: (&ColdFrontend, &InitializerPlan),
    evaluator: &dyn CapturedInitializerEvaluator,
    host: &R,
    resource_search_context: Option<u128>,
    validate_statics: bool,
    observer: Option<&InitializerObserver<'_>>,
    memo: Option<&crate::lowering_memo::ProcedureMemo>,
) -> Result<LoweredInitializers, InitializerLoweringError> {
    let (frontend, plan) = captured;
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
    let classified = match initializer_policy::classify_with_token_mode(
        &plan.writes,
        symbols,
        evaluator,
        frontend.plan.final_macros.contains_key("DEBUG"),
    ) {
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
                    statement: "initializer classification".into(),
                    reason: issue.reason,
                    kind: dm_codegen_byond::LowerErrorKind::UnsupportedModel,
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
    measurement.complete();
    let measurement = crate::stage_measurements::Scope::new(observer, InitializerStage::Codegen);
    let mut units = Vec::with_capacity(classified.groups.len());
    for group in &classified.groups {
        let mut assignments = Vec::with_capacity(group.writes.len());
        let mut entries = Vec::with_capacity(group.writes.len());
        let mut write_ordinals = Vec::with_capacity(group.writes.len());
        for (index, &write_index) in group.writes.iter().enumerate() {
            let write = classified
                .writes
                .get(write_index)
                .ok_or("initializer group write missing")?;
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
                dm_tree::initializers::InitializerOriginKind::ProcedureStatic {
                    identity, ..
                } => {
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
            if let dm_tree::initializers::InitializerOriginKind::ProcedureStatic {
                expanded_span,
                ..
            } = &origin.kind
            {
                entries.push(frontend.origin(expanded_span.start)?);
            } else {
                entries.push(DebugOrigin {
                    semantic_path: occurrence.semantic_path.to_string(),
                    line: u32::try_from(line).map_err(|_| "initializer source line exceeds u32")?,
                });
            }
            let mut value = value_expression(
                write
                    .runtime_value
                    .as_ref()
                    .ok_or("initializer runtime value missing")?,
            );
            // Typed statements carry a local occurrence discriminator. The
            // provider above binds it to captured source provenance, never to
            // synthetic parser text or inferred source byte offsets.
            value.span = dm_syntax::Span::new(index, index);
            assignments.push((write.write.target.clone(), write.write.lexical_owner, value));
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
            debug: Some(&debug),
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
        let code = if let Some(memo) = memo {
            let mut key = b"dmbc-anonymous-declaration-v2-relative-debug\0".to_vec();
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
                    RuntimeValue::SizedArray(dimensions) => {
                        key.push(1);
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
                    error.span.is_none_or(|span| {
                        span.start <= span.end && span.end < write_ordinals.len()
                    })
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
                let code = dm_codegen_byond::initializer::lower_scoped_assignments(
                    &assignments,
                    context(),
                    &recorder,
                )
                .map_err(|error| {
                    if let dm_codegen_byond::initializer::InitializerError::Lowering(errors) =
                        &error
                    {
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
                memo.remember_executable(
                    &key,
                    &recorder.reads(),
                    &code,
                    &recorder.domain_receipts(),
                );
                code
            }
        } else {
            // Cold oracle path performs no cache key, serialization, extra
            // ancestry reads or recording allocation.
            dm_codegen_byond::initializer::lower_scoped_assignments(&assignments, context(), host)
                .map_err(map_error)?
        };
        units.push(LoweredInitializerUnit {
            scope: group
                .receiver
                .map(InitializerScope::Instance)
                .unwrap_or(InitializerScope::Global),
            write_ordinals,
            code,
            debug_origins: debug.origins,
        });
    }
    measurement.complete();
    Ok(LoweredInitializers { classified, units })
}
