//! Bounded cold procedure driver. ABI interpretation remains an explicit policy.
use crate::debug_sources::{DebugOrigins, FrontendDebugProvider};
use crate::procedure_policy::{AbiContext, PreparedAbi, PreparedReplay, PreparedUnit};
use dm_codegen_byond::lower_resolver::ResolverProc;
use dm_codegen_byond::{compile_simple_proc_with_resolver_and_debug, ProcedureInputs};
use dm_ir::{ProcedureMetadata, Resolver, SymbolId, SymbolTable};
use dm_tree::{
    frontend::{BodyOccurrence, ColdFrontend, DiagnosticKind, SourceLocation},
    MemberKind,
};
use std::cell::RefCell;
use std::{collections::BTreeMap, sync::Arc};
#[derive(Default)]
struct MemoCapture {
    debug: Vec<usize>,
    errors: Option<Vec<dm_codegen_byond::LowerError>>,
}
fn replay_errors(
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
    identity: dm_ir::ProcedureIdentity,
    errors: Vec<dm_codegen_byond::LowerError>,
) -> Option<Vec<LoweringDiagnostic>> {
    errors
        .into_iter()
        .map(|error| {
            let origin = match error.span {
                None => body.source.clone(),
                Some(span) => {
                    if span.end
                        > body
                            .expanded_span
                            .end
                            .checked_sub(body.expanded_span.start)?
                        || span.start > span.end
                    {
                        return None;
                    }
                    frontend.location(body.expanded_span.start.checked_add(span.start)?)?
                }
            };
            Some(LoweringDiagnostic {
                kind: match error.kind {
                    dm_codegen_byond::LowerErrorKind::SourceError => DiagnosticKind::SourceError,
                    dm_codegen_byond::LowerErrorKind::UnsupportedModel => {
                        DiagnosticKind::UnsupportedModel
                    }
                    dm_codegen_byond::LowerErrorKind::Internal => return None,
                },
                identity: Some(UnitIdentity {
                    owner: identity.owner,
                    name: identity.name,
                    namespace: if identity.verb {
                        Namespace::Verb
                    } else {
                        Namespace::Proc
                    },
                    occurrence: identity.occurrence,
                }),
                origin,
                message: if error.statement.is_empty() {
                    error.reason
                } else {
                    format!("{}: {}", error.statement, error.reason)
                },
            })
        })
        .collect()
}
struct MemoDebugProvider<'a> {
    original: FrontendDebugProvider<'a>,
    base: usize,
    entry: usize,
    capture: Option<&'a RefCell<MemoCapture>>,
}
impl dm_codegen_byond::DebugSourceProvider for MemoDebugProvider<'_> {
    fn entry_ordinal(&self) -> Result<u32, String> {
        let ordinal = self.original.entry_ordinal()?;
        if let Some(capture) = self.capture {
            let mut capture = capture.borrow_mut();
            if capture.debug.len() <= ordinal as usize {
                capture.debug.resize(ordinal as usize + 1, usize::MAX);
            }
            capture.debug[ordinal as usize] =
                self.entry.checked_sub(self.base).unwrap_or(usize::MAX);
        }
        Ok(ordinal)
    }
    fn ordinal(&self, offset: usize) -> Result<u32, String> {
        let ordinal = self.original.ordinal(offset)?;
        if let Some(capture) = self.capture {
            // An unrebased legacy/default expression is uncacheable; recording
            // it must never introduce a new compiler failure.
            let relative = offset.checked_sub(self.base).unwrap_or(usize::MAX);
            let mut capture = capture.borrow_mut();
            if capture.debug.len() <= ordinal as usize {
                capture.debug.resize(ordinal as usize + 1, usize::MAX);
            }
            capture.debug[ordinal as usize] = relative;
        }
        Ok(ordinal)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Namespace {
    Proc,
    Verb,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct UnitIdentity {
    pub owner: SymbolId,
    pub name: SymbolId,
    pub namespace: Namespace,
    pub occurrence: u32,
}
/// Converts signature/default/annotation semantics using one pinned compiler ABI.
/// Reject unsupported flags/value-source/default decoding rather than guessing.
pub trait AbiPolicy: Sync {
    /// Custom policies retain full parsing. Only an authoritative captured policy
    /// can issue a fixed-transform replay preparation for the current body.
    fn prepare_issued(
        &self,
        _metadata: &ProcedureMetadata,
        _input: &dm_tree::frontend::IssuedBodyInput<'_>,
        _context: &AbiContext<'_>,
    ) -> Result<Option<PreparedReplay>, String> {
        Ok(None)
    }
    /// Issued production parses retain the existing behavior for custom policies.
    fn prepare_captured(
        &self,
        metadata: &ProcedureMetadata,
        parsed: &dm_tree::frontend::ParsedBody<'_>,
        context: &AbiContext<'_>,
    ) -> Result<PreparedUnit, String> {
        self.prepare(metadata, parsed.item(), context)
    }
    fn inputs(
        &self,
        identity: UnitIdentity,
        metadata: &ProcedureMetadata,
        symbols: &SymbolTable,
        origin: &SourceLocation,
    ) -> Result<ProcedureInputs, String>;
    /// Existing local-only policies are deliberately unauthoritative for DMB output.
    fn prepare(
        &self,
        metadata: &ProcedureMetadata,
        parsed: &dm_syntax::Item,
        context: &AbiContext<'_>,
    ) -> Result<PreparedUnit, String> {
        self.inputs(context.identity, metadata, context.symbols, context.origin)
            .map(|inputs| PreparedUnit::local_only(inputs, parsed))
    }
}
#[derive(Clone, Copy, Debug)]
pub struct LoweringConfig {
    pub workers: usize,
    pub max_chunk: usize,
}
impl Default for LoweringConfig {
    fn default() -> Self {
        Self {
            workers: 1,
            max_chunk: 32,
        }
    }
}
#[derive(Clone)]
pub struct LoweredUnit {
    pub identity: UnitIdentity,
    /// Exact immutable tree selection, independent of encounter order.
    pub effective: bool,
    pub origin: BodyOccurrence,
    pub code: ResolverProc,
    pub metadata: Arc<ProcedureMetadata>,
    pub abi: Option<Arc<PreparedAbi>>,
    pub debug_origins: DebugOrigins,
    pub source_helpers: Vec<crate::argument_sources::LoweredHelper>,
}
#[derive(Clone, Debug)]
pub struct LoweringDiagnostic {
    pub kind: DiagnosticKind,
    pub identity: Option<UnitIdentity>,
    pub origin: SourceLocation,
    pub message: String,
}
#[derive(Default)]
pub struct LoweringBatch {
    pub units: Vec<LoweredUnit>,
    pub diagnostics: Vec<LoweringDiagnostic>,
}
pub fn lower_frontend<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
) -> LoweringBatch {
    lower_frontend_impl(frontend, host, policy, config, None, None)
}
/// Startup admission is an exact captured body inventory, never a bypass flag.
pub fn lower_frontend_with_statics<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    startup: &crate::startup::CapturedStartup,
) -> LoweringBatch {
    lower_frontend_impl(frontend, host, policy, config, Some(startup), None)
}
/// Memo admission retains the cold startup/ABI guards. The caller supplies a
/// compiler policy identity; it must not substitute a whole-program tree hash.
pub fn lower_frontend_with_memo<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    startup: &crate::startup::CapturedStartup,
    memo: &crate::lowering_memo::ProcedureMemo,
) -> LoweringBatch {
    lower_frontend_impl(frontend, host, policy, config, Some(startup), Some(memo))
}
/// One borrowed build executor and its issued request-local lazy body arena.
#[derive(Clone, Copy)]
pub struct LoweringExecution<'a, 'frontend> {
    pub executor: &'a dm_exec::BuildExecutor,
    pub bodies: &'a dm_tree::frontend::BodyArena<'frontend>,
}
impl<'a, 'frontend> LoweringExecution<'a, 'frontend> {
    pub fn new(
        executor: &'a dm_exec::BuildExecutor,
        bodies: &'a dm_tree::frontend::BodyArena<'frontend>,
    ) -> Self {
        Self { executor, bodies }
    }
}
pub fn lower_frontend_on_executor<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    executor: &dm_exec::BuildExecutor,
) -> LoweringBatch {
    let bodies = dm_tree::frontend::BodyArena::new(frontend);
    lower_frontend_impl_on_execution(
        frontend,
        host,
        policy,
        config,
        None,
        None,
        LoweringExecution::new(executor, &bodies),
    )
}
/// Borrow the configured build executor; no stage-local pool is constructed.
pub fn lower_frontend_with_statics_on_executor<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    startup: &crate::startup::CapturedStartup,
    executor: &dm_exec::BuildExecutor,
) -> LoweringBatch {
    let bodies = dm_tree::frontend::BodyArena::new(frontend);
    lower_frontend_impl_on_execution(
        frontend,
        host,
        policy,
        config,
        Some(startup),
        None,
        LoweringExecution::new(executor, &bodies),
    )
}
pub fn lower_frontend_with_memo_on_executor<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    startup: &crate::startup::CapturedStartup,
    memo: &crate::lowering_memo::ProcedureMemo,
    executor: &dm_exec::BuildExecutor,
) -> LoweringBatch {
    let bodies = dm_tree::frontend::BodyArena::new(frontend);
    lower_frontend_impl_on_execution(
        frontend,
        host,
        policy,
        config,
        Some(startup),
        Some(memo),
        LoweringExecution::new(executor, &bodies),
    )
}
pub fn lower_frontend_with_statics_on_executor_and_bodies<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    startup: &crate::startup::CapturedStartup,
    execution: LoweringExecution<'_, '_>,
) -> LoweringBatch {
    lower_frontend_impl_on_execution(
        frontend,
        host,
        policy,
        config,
        Some(startup),
        None,
        execution,
    )
}
pub fn lower_frontend_with_memo_on_executor_and_bodies<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    startup: &crate::startup::CapturedStartup,
    memo: &crate::lowering_memo::ProcedureMemo,
    execution: LoweringExecution<'_, '_>,
) -> LoweringBatch {
    lower_frontend_impl_on_execution(
        frontend,
        host,
        policy,
        config,
        Some(startup),
        Some(memo),
        execution,
    )
}
fn lower_frontend_impl<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    startup: Option<&crate::startup::CapturedStartup>,
    memo: Option<&crate::lowering_memo::ProcedureMemo>,
) -> LoweringBatch {
    let executor = match dm_exec::BuildExecutor::new(config.workers) {
        Ok(executor) => executor,
        Err(error) => {
            return LoweringBatch {
                units: Vec::new(),
                diagnostics: frontend
                    .bodies
                    .iter()
                    .map(|body| LoweringDiagnostic {
                        kind: DiagnosticKind::Internal,
                        identity: None,
                        origin: body.source.clone(),
                        message: format!("procedure lowering executor creation failed: {error}"),
                    })
                    .collect(),
            }
        }
    };
    let bodies = dm_tree::frontend::BodyArena::new(frontend);
    lower_frontend_impl_on_execution(
        frontend,
        host,
        policy,
        config,
        startup,
        memo,
        LoweringExecution::new(&executor, &bodies),
    )
}
fn lower_frontend_impl_on_execution<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    startup: Option<&crate::startup::CapturedStartup>,
    memo: Option<&crate::lowering_memo::ProcedureMemo>,
    execution: LoweringExecution<'_, '_>,
) -> LoweringBatch {
    let executor = execution.executor;
    let workers = executor.workers();
    let chunk = config.max_chunk.clamp(1, 256);
    let mut bodies: Vec<_> = frontend.bodies.iter().collect();
    bodies.sort_by_key(|body| {
        (
            body.source.encounter_ordinal,
            body.expanded_span.start,
            body.declaration.0,
        )
    });
    // Only final outputs occupy indexed slots. Each worker holds at most one
    // bounded chunk; publication remains inside the existing memo producer.
    let slices: Vec<_> = bodies.chunks(chunk).collect();
    let results: Vec<_> = (0..slices.len())
        .map(|_| std::sync::Mutex::new(None))
        .collect();
    let next = std::sync::atomic::AtomicUsize::new(0);
    let scheduling = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        executor.scope(|scope| {
            for _ in 0..workers.min(slices.len()) {
                let slices = &slices;
                let results = &results;
                let next = &next;
                scope.spawn(move |_| {
                    let _profile = dm_profile::stage("cold.procedure_lowering");
                    loop {
                        let index = next.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                        let Some(slice) = slices.get(index) else {
                            break;
                        };
                        let outcomes =
                            std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                                slice
                                    .iter()
                                    .map(|body| {
                                        lower_one_memo(
                                            frontend,
                                            body,
                                            host,
                                            policy,
                                            startup,
                                            memo,
                                            execution.bodies,
                                        )
                                    })
                                    .collect::<Vec<_>>()
                            }))
                            .unwrap_or_else(|_| {
                                slice
                                    .iter()
                                    .map(|body| {
                                        Err(vec![LoweringDiagnostic {
                                            kind: DiagnosticKind::Internal,
                                            identity: None,
                                            origin: body.source.clone(),
                                            message: "procedure lowering worker panicked".into(),
                                        }])
                                    })
                                    .collect()
                            });
                        *results[index]
                            .lock()
                            .unwrap_or_else(|error| error.into_inner()) = Some(outcomes);
                    }
                });
            }
        })
    }));
    // Every sibling job has joined before the scope propagates a panic. Missing
    // slots become source-ordered internal diagnostics rather than escaping.
    let scheduling_failed = scheduling.is_err();
    let mut batch = LoweringBatch::default();
    for (index, slot) in results.into_iter().enumerate() {
        let outcomes = slot.into_inner().unwrap_or_else(|error| error.into_inner());
        let outcomes = outcomes.unwrap_or_else(|| {
            slices[index]
                .iter()
                .map(|body| {
                    Err(vec![LoweringDiagnostic {
                        kind: DiagnosticKind::Internal,
                        identity: None,
                        origin: body.source.clone(),
                        message: if scheduling_failed {
                            "procedure scheduling worker panicked"
                        } else {
                            "procedure lowering job did not complete"
                        }
                        .into(),
                    }])
                })
                .collect()
        });
        for outcome in outcomes {
            match outcome {
                Ok(unit) => batch.units.push(unit),
                Err(errors) => batch.diagnostics.extend(errors),
            }
        }
    }
    batch
}
mod body;
mod memo;
use body::{lower_one, lower_one_captured, LoweringCapture};
use memo::lower_one_memo;

/// A deterministic identity index for subsequent linking; duplicate structural
/// identities are a driver/model error, never silently overwritten.
impl LoweringBatch {
    /// Symbolic-only lowering may use local policies. Full output must have
    /// authoritative metadata and actual linked argument-source artifacts.
    pub fn require_production_abi(&self) -> Result<(), String> {
        for unit in &self.units {
            let abi = unit.abi.as_ref().ok_or_else(|| {
                format!(
                    "authoritative procedure ABI missing for {:?}",
                    unit.identity
                )
            })?;
            if abi.source_helpers.len() != unit.source_helpers.len()
                || abi
                    .source_helpers
                    .iter()
                    .zip(unit.source_helpers.iter())
                    .any(|(expected, actual)| {
                        actual.owner != unit.identity
                            || usize::try_from(actual.argument).ok() != Some(expected.argument)
                    })
            {
                return Err(format!(
                    "argument-source helper lowering is incomplete for {:?}",
                    unit.identity
                ));
            }
        }
        Ok(())
    }
    pub fn identity_index(&self) -> Result<BTreeMap<UnitIdentity, usize>, UnitIdentity> {
        let mut index = BTreeMap::new();
        for (position, unit) in self.units.iter().enumerate() {
            if index.insert(unit.identity, position).is_some() {
                return Err(unit.identity);
            }
        }
        Ok(index)
    }
}

#[cfg(test)]
#[path = "lowering_tests.rs"]
mod tests;
