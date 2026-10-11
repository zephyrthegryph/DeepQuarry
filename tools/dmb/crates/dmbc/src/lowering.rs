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
    debug: Vec<crate::debug_sources::RelativeDebugAnchor>,
    errors: Option<Vec<dm_codegen_byond::LowerError>>,
}

#[cfg(test)]
#[path = "lowering/diagnostic_anchor_tests.rs"]
mod diagnostic_anchor_tests;
#[path = "lowering/error_anchor.rs"]
mod error_anchor;
#[path = "lowering/grammar.rs"]
mod grammar;
fn replay_errors(
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
    identity: dm_ir::ProcedureIdentity,
    errors: Vec<dm_codegen_byond::LowerError>,
) -> Option<Vec<LoweringDiagnostic>> {
    errors
        .into_iter()
        .map(|error| {
            let origin = if let Some(anchor) = error.primary_anchor {
                error_anchor::bind(frontend, body, anchor, true)?
            } else {
                match error.span {
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
                }
            };
            Some(LoweringDiagnostic {
                related: related::bind_related(frontend, body, error.related, true)?,
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
                message: if error.kind == dm_codegen_byond::LowerErrorKind::SourceError
                    || error.statement.is_empty()
                {
                    error.reason
                } else {
                    format!("{}: {}", error.statement, error.reason)
                },
            })
        })
        .collect()
}
#[path = "lowering/related.rs"]
mod related;
struct MemoDebugProvider<'a> {
    original: FrontendDebugProvider<'a>,
    base: usize,
    entry: usize,
    capture: Option<&'a RefCell<MemoCapture>>,
    parameters: Option<crate::argument_sources::ParameterDiagnosticSource<'a>>,
}
impl dm_codegen_byond::DebugSourceProvider for MemoDebugProvider<'_> {
    fn parameter_declaration(
        &self,
        name: &str,
    ) -> Result<Option<dm_codegen_byond::LowerSpan>, String> {
        match &self.parameters {
            Some(source) => source.declaration(name),
            None => Ok(None),
        }
    }
    fn diagnostic_ordinal(
        &self,
        anchor: dm_codegen_byond::DiagnosticAnchor,
    ) -> Result<Option<u32>, String> {
        let Some(ordinal) = self.original.diagnostic_ordinal(anchor)? else {
            return Ok(None);
        };
        if let Some(capture) = self.capture {
            use crate::debug_sources::RelativeDebugAnchor as R;
            use dm_codegen_byond::DiagnosticAnchor as A;
            let relative = match anchor {
                A::AtOffset(offset) => offset.checked_sub(self.base).map(R::AtBodyOffset),
                A::LexerCursorAfterOffset(offset) => offset
                    .checked_sub(self.base)
                    .map(R::LexerCursorAfterBodyOffset),
                A::UnresolvedCursorAtOffset(offset) => offset
                    .checked_sub(self.base)
                    .map(R::UnresolvedCursorAtBodyOffset),
            }
            .unwrap_or(R::Unbound);
            let mut capture = capture.borrow_mut();
            if capture.debug.len() <= ordinal as usize {
                capture.debug.resize(ordinal as usize + 1, R::Unbound);
            }
            capture.debug[ordinal as usize] = relative;
        }
        Ok(Some(ordinal))
    }
    fn entry_ordinal(&self) -> Result<u32, String> {
        let ordinal = self.original.entry_ordinal()?;
        if let Some(capture) = self.capture {
            let mut capture = capture.borrow_mut();
            if capture.debug.len() <= ordinal as usize {
                capture.debug.resize(
                    ordinal as usize + 1,
                    crate::debug_sources::RelativeDebugAnchor::Unbound,
                );
            }
            capture.debug[ordinal as usize] = self
                .entry
                .checked_sub(self.base)
                .map(crate::debug_sources::RelativeDebugAnchor::AtBodyOffset)
                .unwrap_or(crate::debug_sources::RelativeDebugAnchor::Unbound);
        }
        Ok(ordinal)
    }
    fn ordinal(&self, offset: usize) -> Result<u32, String> {
        let ordinal = self.original.ordinal(offset)?;
        if let Some(capture) = self.capture {
            // An unrebased legacy/default expression is uncacheable; recording
            // it must never introduce a new compiler failure.
            let relative = offset
                .checked_sub(self.base)
                .map(crate::debug_sources::RelativeDebugAnchor::AtBodyOffset)
                .unwrap_or(crate::debug_sources::RelativeDebugAnchor::Unbound);
            let mut capture = capture.borrow_mut();
            if capture.debug.len() <= ordinal as usize {
                capture.debug.resize(
                    ordinal as usize + 1,
                    crate::debug_sources::RelativeDebugAnchor::Unbound,
                );
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
/// Authenticated source identity before any rich procedure IR is allocated.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SourceUnitIdentity {
    pub identity: UnitIdentity,
    pub effective: bool,
}
#[path = "lowering_source_identity.rs"]
mod source_identity;
pub(crate) use source_identity::from_issued as source_identity_for_issued;
pub use source_identity::source_unit_identity;
#[path = "lowering/prepared_roster.rs"]
mod prepared_roster;
pub(crate) use prepared_roster::{PreparedBody, PreparedBodyRoster};
/// Same authored ordering as the completion scheduler, without lowering bodies.
pub fn source_unit_roster(
    frontend: &ColdFrontend,
) -> Result<Vec<SourceUnitIdentity>, Vec<LoweringDiagnostic>> {
    let mut bodies: Vec<_> = frontend.bodies.iter().collect();
    bodies.sort_by_key(|body| {
        (
            body.source.encounter_ordinal,
            body.expanded_span.start,
            body.declaration.0,
        )
    });
    let mut units = Vec::with_capacity(bodies.len());
    let mut diagnostics = Vec::new();
    for body in bodies {
        match source_unit_identity(frontend, body) {
            Ok(unit) => units.push(unit),
            Err(message) => diagnostics.push(LoweringDiagnostic {
                related: Vec::new(),
                kind: DiagnosticKind::Internal,
                identity: None,
                origin: body.source.clone(),
                message,
            }),
        }
    }
    if diagnostics.is_empty() {
        Ok(units)
    } else {
        Err(diagnostics)
    }
}
/// Converts signature/default/annotation semantics using one pinned compiler ABI.
/// Reject unsupported flags/value-source/default decoding rather than guessing.
pub trait AbiPolicy: Sync {
    fn uses_issued_statements(&self) -> bool {
        false
    }

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
    /// Owned production preparation; custom policies retain their borrowed hook.
    /// The returned header keeps exact source spans but no executable children.
    fn prepare_owned_captured(
        &self,
        metadata: &ProcedureMetadata,
        parsed: dm_tree::frontend::ParsedBody<'_>,
        context: &AbiContext<'_>,
    ) -> Result<
        (
            PreparedUnit,
            dm_syntax::Item,
            Option<std::sync::Arc<dm_tree::frontend::StatementBody>>,
        ),
        String,
    > {
        let prepared = self.prepare_captured(metadata, &parsed, context)?;
        let mut header = parsed.into_item();
        header.children = Vec::new();
        Ok((prepared, header, None))
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
    /// Optional compiler-selected facts with relative typed-node coordinates.
    /// Source locations are always bound against this request's body issuance.
    pub selected_references: Option<Arc<dm_ir::SelectedReferences>>,
    pub metadata: Arc<ProcedureMetadata>,
    pub abi: Option<Arc<PreparedAbi>>,
    pub debug_origins: DebugOrigins,
    pub source_helpers: Vec<crate::argument_sources::LoweredHelper>,
}
#[derive(Clone, Debug)]
pub struct LoweringDiagnostic {
    pub related: Vec<RelatedDiagnostic>,
    pub kind: DiagnosticKind,
    pub identity: Option<UnitIdentity>,
    pub origin: SourceLocation,
    pub message: String,
}
#[derive(Clone, Debug)]
pub struct RelatedDiagnostic {
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
pub struct DiskReplayBindings<'a> {
    pub source: &'a std::collections::BTreeSet<dm_ir::SymRef>,
    pub external: &'a crate::symbolic::ReferenceBindings,
}
#[derive(Clone, Copy)]
pub struct LoweringExecution<'a, 'frontend> {
    pub executor: &'a dm_exec::BuildExecutor,
    pub bodies: &'a dm_tree::frontend::BodyArena<'frontend>,
    pub capture_references: bool,
    pub(crate) selections_only: bool,
    /// Analysis query selection; compilation uses the complete issued roster.
    pub selected_bodies: Option<&'a [&'frontend BodyOccurrence]>,
    pub disk_replay_bindings: Option<DiskReplayBindings<'a>>,
    pub(crate) prepared_roster: Option<&'a PreparedBodyRoster<'frontend>>,
}
impl<'a, 'frontend> LoweringExecution<'a, 'frontend> {
    pub fn new(
        executor: &'a dm_exec::BuildExecutor,
        bodies: &'a dm_tree::frontend::BodyArena<'frontend>,
    ) -> Self {
        Self {
            executor,
            bodies,
            capture_references: false,
            selections_only: false,
            selected_bodies: None,
            disk_replay_bindings: None,
            prepared_roster: None,
        }
    }
    pub fn with_disk_replay_bindings(mut self, bindings: DiskReplayBindings<'a>) -> Self {
        self.disk_replay_bindings = Some(bindings);
        self
    }
    pub(crate) fn with_prepared_roster(
        mut self,
        roster: &'a PreparedBodyRoster<'frontend>,
    ) -> Self {
        self.prepared_roster = Some(roster);
        self
    }
    /// Explicit analysis clients pay for typed-node selection recording.
    /// Ordinary builds keep the existing no-capture lowering path.
    pub(crate) fn with_selection_query(mut self) -> Self {
        self.capture_references = true;
        self.selections_only = true;
        self
    }
    pub fn with_reference_capture(mut self) -> Self {
        self.capture_references = true;
        self
    }
    /// Query a subset through the same admission and lowering producer.
    /// Each selection must be a unique occurrence from the current frontend.
    /// This never certifies a complete program for output composition.
    pub fn with_selected_bodies(mut self, bodies: &'a [&'frontend BodyOccurrence]) -> Self {
        self.selected_bodies = Some(bodies);
        self
    }
}
pub fn lower_frontend_on_executor<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    executor: &dm_exec::BuildExecutor,
) -> LoweringBatch {
    let bodies = if policy.uses_issued_statements() {
        dm_tree::frontend::BodyArena::new_typed(
            frontend,
            dm_codegen_byond::typed_statements_supported_for_capture,
        )
    } else {
        dm_tree::frontend::BodyArena::new(frontend)
    };
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
    let bodies = if policy.uses_issued_statements() {
        dm_tree::frontend::BodyArena::new_typed(
            frontend,
            dm_codegen_byond::typed_statements_supported_for_capture,
        )
    } else {
        dm_tree::frontend::BodyArena::new(frontend)
    };
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
    let bodies = if policy.uses_issued_statements() {
        dm_tree::frontend::BodyArena::new_typed(
            frontend,
            dm_codegen_byond::typed_statements_supported_for_capture,
        )
    } else {
        dm_tree::frontend::BodyArena::new(frontend)
    };
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
                        related: Vec::new(),
                        kind: DiagnosticKind::Internal,
                        identity: None,
                        origin: body.source.clone(),
                        message: format!("procedure lowering executor creation failed: {error}"),
                    })
                    .collect(),
            }
        }
    };
    let bodies = if policy.uses_issued_statements() {
        dm_tree::frontend::BodyArena::new_typed(
            frontend,
            dm_codegen_byond::typed_statements_supported_for_capture,
        )
    } else {
        dm_tree::frontend::BodyArena::new(frontend)
    };
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
    let completed = lower_frontend_completed_on_execution(
        frontend,
        host,
        policy,
        config,
        startup,
        memo,
        execution,
        &|mut unit| {
            compact_retained(&mut unit);
            Ok::<_, std::convert::Infallible>(unit)
        },
    );
    if let Some((_, impossible)) = completed.completion_errors.into_iter().next() {
        match impossible {}
    }
    LoweringBatch {
        units: completed.units.into_iter().map(|unit| unit.value).collect(),
        diagnostics: completed.diagnostics,
    }
}
mod completion;
pub(crate) mod symbolic_input;
pub use completion::{
    lower_frontend_completed_input_on_execution, lower_frontend_completed_on_execution,
    CompletedLoweringBatch, CompletedUnit,
};
pub use symbolic_input::{CompletedInput, ProcedureSelections, SymbolicRetentionStats};
fn compact_retained(unit: &mut LoweredUnit) {
    fn compact<T>(values: &mut Vec<T>) {
        if values.capacity() > values.len() {
            values.shrink_to_fit();
        }
    }
    fn debug(origins: &mut DebugOrigins) {
        compact(&mut origins.entries);
    }
    unit.code.compact_retained();
    debug(&mut unit.debug_origins);
    for helper in &mut unit.source_helpers {
        helper.code.compact_retained();
        debug(&mut helper.debug_origins);
    }
    compact(&mut unit.source_helpers);
}
mod body;
mod memo;
use body::{lower_one, lower_one_captured, LoweringCapture};

/// A deterministic identity index for subsequent linking; duplicate structural
/// identities are a driver/model error, never silently overwritten.
impl LoweringBatch {
    /// Symbolic-only lowering may use local policies. Full output must have
    /// authoritative metadata and actual linked argument-source artifacts.
    pub fn require_production_abi(&self) -> Result<(), String> {
        for unit in &self.units {
            unit.require_production_abi()?;
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

impl LoweredUnit {
    pub fn require_production_abi(&self) -> Result<(), String> {
        let abi = self.abi.as_ref().ok_or_else(|| {
            format!(
                "authoritative procedure ABI missing for {:?}",
                self.identity
            )
        })?;
        if abi.source_helpers.len() != self.source_helpers.len()
            || abi
                .source_helpers
                .iter()
                .zip(self.source_helpers.iter())
                .any(|(expected, actual)| {
                    actual.owner != self.identity
                        || usize::try_from(actual.argument).ok() != Some(expected.argument)
                })
        {
            return Err(format!(
                "argument-source helper lowering is incomplete for {:?}",
                self.identity
            ));
        }
        Ok(())
    }
}
