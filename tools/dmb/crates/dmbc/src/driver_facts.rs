//! Captured CLI policy adapter prototype. Not exported until inherited absence
//! coverage and resource capture are supplied by the production discovery stage.
use crate::{
    engine::EngineSnapshot,
    initializer_policy::{CapturedInitializerEvaluator, Evaluation},
    lowering::{Namespace, UnitIdentity},
    procedure_policy::{
        AbiContext, CapturedConstantEvaluator, CapturedInheritedFacts, InheritedLayout,
    },
};
use dm_codegen_byond::procedure_abi::{AbiError, ProcLayout};
use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver, SemanticValue, SymbolId, SymbolicExpression};
use dm_tree::{constants::Constant, frontend::ColdFrontend, MemberId, MemberKind};
use rayon::prelude::*;
use std::{
    cell::RefCell,
    collections::{BTreeMap, HashMap},
    sync::Arc,
};

/// Configuration captured before compilation. All policy views borrow these
/// same immutable hosts; resource context is issued by discovery, not filenames.
pub struct DriverFacts<'a> {
    pub evaluator: DriverEvaluator<'a>,
    pub inherited: DriverInheritedFacts<'a>,
    pub resource_search_context: Option<u128>,
}
impl DriverFacts<'_> {
    pub fn procedure_policy(&self) -> crate::procedure_policy::CapturedProcedurePolicy<'_> {
        crate::procedure_policy::CapturedProcedurePolicy {
            evaluator: &self.evaluator,
            inherited: &self.inherited,
            resource_search_context: self.resource_search_context,
        }
    }
    pub fn initializer_evaluator(&self) -> crate::initializer_policy::EngineCapturedEvaluator<'_> {
        crate::initializer_policy::EngineCapturedEvaluator {
            engine: self.inherited.engine,
            evaluator: &self.evaluator,
        }
    }
}

#[path = "driver_facts_evaluator.rs"]
mod evaluator;
pub use evaluator::DriverEvaluator;
use evaluator::LexicalAbiEvaluator;
#[path = "driver_facts/abi_artifacts.rs"]
pub(crate) mod abi_artifacts;
mod abi_scheduler;
pub use abi_artifacts::AbiArtifacts;

/// Captured boundary facts are explicit; a missing entry never means Fresh.
/// Discovery must certify Fresh only with complete named-procedure absence.
pub enum BoundaryAbi {
    Fresh,
    CertifiedIntrinsic(CertifiedIntrinsicAbi),
    Engine {
        owner: SymbolId,
        name: SymbolId,
        kind: MemberKind,
    },
}
/// Positive finite native-control receipt; this is not semantic name absence.
pub struct CertifiedIntrinsicAbi {
    engine_identity: u128,
    owner: SymbolId,
    name: SymbolId,
    layout: ProcLayout,
}
impl CertifiedIntrinsicAbi {
    pub(crate) fn callback(
        engine: &EngineSnapshot,
        owner: SymbolId,
        name: SymbolId,
    ) -> Result<Self, AbiError> {
        const TEMPLATE: &[u8] = include_bytes!("../../../fixtures/native_template.bin");
        if !engine.matches_template(TEMPLATE, 1) {
            return Err(AbiError::unsupported(
                "unsupported intrinsic ABI receipt template",
            ));
        }
        let fact = crate::native_callbacks::lookup(owner, name)
            .ok_or_else(|| AbiError::unsupported("unsupported intrinsic ABI receipt callback"))?;
        Ok(Self {
            engine_identity: engine.identity(),
            owner,
            name,
            layout: fact.layout(),
        })
    }
}
pub struct DriverInheritedFacts<'a> {
    pub frontend: &'a ColdFrontend,
    pub engine: &'a EngineSnapshot,
    /// Prepared ABI of actual previous source members, populated in dependency order.
    pub source_layouts: &'a HashMap<MemberId, Arc<crate::procedure_policy::PreparedAbi>>,
    pub boundaries: &'a BTreeMap<UnitIdentity, BoundaryAbi>,
    pub unit_members: &'a BTreeMap<UnitIdentity, MemberId>,
}
impl DriverInheritedFacts<'_> {
    /// Implicit implementations do not redefine the inherited declaration ABI.
    /// BYOND 516.1687 inherits settings from the original formal declaration,
    /// even when a nearer implementation has authored different flags.
    fn source_predecessor(&self, member: MemberId) -> Result<Option<MemberId>, AbiError> {
        let tree = &self.frontend.snapshot.tree;
        if let Ok(roster) = self.frontend.callable_roster() {
            if let (Some(ordinal), Some(abi)) = (roster.ordinal(member), roster.abi()) {
                return Ok(abi.entries()[ordinal].predecessor);
            }
        }
        let first = tree
            .member(member)
            .ok_or_else(|| AbiError::unsupported("indexed procedure member missing"))?
            .previous;
        let mut cursor = first;
        while let Some(id) = cursor {
            let node = tree
                .member(id)
                .ok_or_else(|| AbiError::unsupported("inherited procedure member missing"))?;
            if node.definition == dm_tree::DefinitionMode::Declare {
                return Ok(Some(id));
            }
            cursor = node.previous;
        }
        // Engine-boundary chains have no authored formal source declaration.
        // Their existing certified receipt path remains unchanged.
        Ok(first)
    }
}
impl CapturedInheritedFacts for DriverInheritedFacts<'_> {
    fn inherited(&self, context: &AbiContext<'_>) -> Result<InheritedLayout, AbiError> {
        let tree = &self.frontend.snapshot.tree;
        let id = self
            .unit_members
            .get(&context.identity)
            .ok_or_else(|| AbiError::unsupported("procedure is not in captured model"))?;
        let node = tree
            .member(*id)
            .ok_or_else(|| AbiError::unsupported("indexed procedure member missing"))?;
        if let Some(previous) = self.source_predecessor(*id)? {
            return self
                .source_layouts
                .get(&previous)
                .map(|abi| InheritedLayout::Known(abi.layout.clone()))
                .ok_or_else(|| {
                    AbiError::unsupported("previous source procedure ABI has not been prepared")
                });
        }
        match self.boundaries.get(&context.identity) {
            Some(BoundaryAbi::Fresh) => Ok(InheritedLayout::Fresh),
            Some(BoundaryAbi::CertifiedIntrinsic(receipt)) => {
                if receipt.engine_identity != self.engine.identity()
                    || receipt.name != node.name
                    || node.kind != MemberKind::Proc
                    || node.definition == dm_tree::DefinitionMode::Declare
                {
                    return Err(AbiError::unsupported(
                        "intrinsic ABI receipt does not match current procedure",
                    ));
                }
                let mut cursor = Some(node.owner);
                while let Some(id) = cursor {
                    if tree
                        .type_node(id)
                        .is_some_and(|ty| ty.path == receipt.owner)
                    {
                        return Ok(InheritedLayout::Known(receipt.layout.clone()));
                    }
                    cursor = tree.parent(id);
                }
                Err(AbiError::unsupported(
                    "intrinsic ABI receipt is outside current ancestry",
                ))
            }
            Some(BoundaryAbi::Engine { owner, name, kind }) => {
                if *name != node.name || *kind != node.kind {
                    return Err(AbiError::unsupported(
                        "engine boundary names a different procedure",
                    ));
                }
                let mut cursor = Some(node.owner);
                let mut contains = false;
                while let Some(id) = cursor {
                    contains |= tree.type_node(id).is_some_and(|ty| ty.path == *owner);
                    cursor = tree.parent(id);
                }
                if !contains {
                    return Err(AbiError::unsupported(
                        "engine boundary is outside current ancestry",
                    ));
                }
                self.engine
                    .procedure_layout(*owner, *name, *kind)
                    .map_err(|error| AbiError::unsupported(format!("engine ABI: {error:?}")))?
                    .cloned()
                    .map(InheritedLayout::Known)
                    .ok_or_else(|| AbiError::unsupported("selected engine ABI is not captured"))
            }
            None => Ok(InheritedLayout::Unsupported),
        }
    }
}

/// Exact source occurrence index built once, independently of source encounter
/// scheduling. Distinct formal/reopen identities cannot alias one prepared ABI.
pub fn unit_members(frontend: &ColdFrontend) -> Result<BTreeMap<UnitIdentity, MemberId>, AbiError> {
    let roster = frontend.callable_roster().map_err(AbiError::unsupported)?;
    let mut result = BTreeMap::new();
    for (ordinal, member) in roster.members().iter().enumerate() {
        let identity = roster
            .identity(ordinal)
            .ok_or_else(|| AbiError::invariant("callable identity missing"))?;
        let unit = UnitIdentity {
            owner: identity.owner,
            name: identity.name,
            namespace: if identity.verb {
                Namespace::Verb
            } else {
                Namespace::Proc
            },
            occurrence: identity.occurrence,
        };
        if result.insert(unit, *member).is_some() {
            return Err(AbiError::unsupported(
                "ambiguous current procedure occurrence",
            ));
        }
    }
    Ok(result)
}

#[path = "driver_facts/prepared_units.rs"]
mod prepared_units;
pub(crate) use prepared_units::PreparedAbiUnits;
#[path = "driver_facts/local_inputs.rs"]
mod local_inputs;
pub use local_inputs::LocalInputRoster;
pub struct PreparedSourceAbi {
    units: Arc<PreparedAbiUnits>,
    pub diagnostics: Vec<(usize, AbiError)>,
}
impl PreparedSourceAbi {
    /// Immutable producer order; source contexts remain on the current frontend.
    pub fn units(&self) -> &[(MemberId, crate::procedure_policy::PreparedUnit)] {
        self.units.entries()
    }
    pub(crate) fn units_owner(&self) -> &Arc<PreparedAbiUnits> {
        &self.units
    }
}
pub struct PreparedPinnedSourceAbi {
    pub policy_identity: u128,
    pub prepared: PreparedSourceAbi,
}
/// Preserve every failed unit's actual captured origin and cause. Preparation
/// stores encounter ordinals; these are never compiler-generated output IDs.
pub fn abi_diagnostics(
    frontend: &ColdFrontend,
    prepared: &PreparedSourceAbi,
) -> Result<Vec<crate::lowering::LoweringDiagnostic>, AbiError> {
    let identities: HashMap<_, _> = unit_members(frontend)?
        .into_iter()
        .map(|(unit, member)| (member, unit))
        .collect();
    let mut diagnostics = prepared
        .diagnostics
        .iter()
        .map(|(ordinal, message)| {
            let body = frontend.bodies.get(*ordinal).ok_or_else(|| {
                AbiError::invariant("ABI diagnostic body ordinal is outside captured frontend")
            })?;
            Ok(crate::lowering::LoweringDiagnostic {
                related: Vec::new(),
                kind: match message.kind {
                    dm_codegen_byond::procedure_abi::AbiErrorKind::Source => {
                        dm_tree::frontend::DiagnosticKind::SourceError
                    }
                    dm_codegen_byond::procedure_abi::AbiErrorKind::Unsupported => {
                        dm_tree::frontend::DiagnosticKind::UnsupportedModel
                    }
                    dm_codegen_byond::procedure_abi::AbiErrorKind::Invariant => {
                        dm_tree::frontend::DiagnosticKind::Internal
                    }
                },
                identity: identities.get(&body.member).copied(),
                origin: body.source.clone(),
                message: message.message.clone(),
            })
        })
        .collect::<Result<Vec<_>, AbiError>>()?;
    diagnostics.sort_by_key(|diagnostic| {
        (
            diagnostic.origin.encounter_ordinal,
            diagnostic.origin.span.start,
        )
    });
    Ok(diagnostics)
}
/// Production constructor: dependency waves consume exact source predecessors
/// and pinned engine boundary certificates; callers cannot fill all rows Fresh.
pub fn prepare_pinned_source_abi(
    frontend: &ColdFrontend,
    engine: &EngineSnapshot,
    resolver: &dyn Resolver,
    resource_search_context: Option<u128>,
    workers: usize,
) -> Result<PreparedPinnedSourceAbi, AbiError> {
    let coverage = crate::engine_abi_coverage::NamedEngineCoverage::pinned(engine)
        .map_err(AbiError::unsupported)?;
    let policy_identity = coverage.policy_identity();
    let boundaries = coverage
        .boundaries(frontend)
        .map_err(AbiError::unsupported)?;
    let evaluator = DriverEvaluator {
        pure_calls: None,
        resource_search_context,
        resolver,
        symbols: frontend.snapshot.tree.symbols(),
    };
    let prepared = prepare_source_abi(
        frontend,
        engine,
        &evaluator,
        &boundaries,
        resource_search_context,
        workers,
    )?;
    Ok(PreparedPinnedSourceAbi {
        policy_identity,
        prepared,
    })
}
/// Production startup variant: settings and parameter scalar expressions resolve
/// lexical statics through the same captured inventory as executable lowering.
pub fn prepare_pinned_source_abi_with_startup<R: Resolver>(
    frontend: &ColdFrontend,
    engine: &EngineSnapshot,
    resolver: &R,
    startup: &crate::startup::CapturedStartup,
    resource_search_context: Option<u128>,
    workers: usize,
) -> Result<PreparedPinnedSourceAbi, AbiError> {
    let executor = dm_exec::BuildExecutor::new(workers)
        .map_err(|error| AbiError::unsupported(format!("ABI executor creation failed: {error}")))?;
    prepare_pinned_source_abi_with_startup_on_executor(
        frontend,
        engine,
        resolver,
        startup,
        resource_search_context,
        &executor,
    )
}
pub fn prepare_pinned_source_abi_with_startup_on_executor<R: Resolver>(
    frontend: &ColdFrontend,
    engine: &EngineSnapshot,
    resolver: &R,
    startup: &crate::startup::CapturedStartup,
    resource_search_context: Option<u128>,
    executor: &dm_exec::BuildExecutor,
) -> Result<PreparedPinnedSourceAbi, AbiError> {
    prepare_pinned_source_abi_with_startup_on_executor_with_artifacts(
        frontend,
        engine,
        resolver,
        startup,
        resource_search_context,
        executor,
        None,
    )
}
#[allow(clippy::too_many_arguments)] // Shared optional retained owner, same preparation pipeline.
pub fn prepare_pinned_source_abi_with_startup_on_executor_with_artifacts<R: Resolver>(
    frontend: &ColdFrontend,
    engine: &EngineSnapshot,
    resolver: &R,
    startup: &crate::startup::CapturedStartup,
    resource_search_context: Option<u128>,
    executor: &dm_exec::BuildExecutor,
    artifacts: Option<&AbiArtifacts>,
) -> Result<PreparedPinnedSourceAbi, AbiError> {
    startup
        .validate_for(frontend)
        .map_err(AbiError::unsupported)?;
    let static_resolver = startup
        .resolver(frontend, resolver)
        .map_err(AbiError::unsupported)?;
    let resolver = &static_resolver;
    let coverage = crate::engine_abi_coverage::NamedEngineCoverage::pinned(engine)
        .map_err(AbiError::unsupported)?;
    let policy_identity = coverage.policy_identity();
    let boundaries = coverage
        .boundaries_with_units(frontend, startup.unit_members())
        .map_err(AbiError::unsupported)?;
    let evaluator = DriverEvaluator {
        pure_calls: None,
        resource_search_context,
        resolver,
        symbols: startup.plan().symbols.as_ref(),
    };
    let prepared = prepare_source_abi_mode_on_executor(
        frontend,
        engine,
        &evaluator,
        &boundaries,
        resource_search_context,
        executor,
        true,
        Some(startup.unit_members()),
        artifacts,
    )?;
    Ok(PreparedPinnedSourceAbi {
        policy_identity,
        prepared,
    })
}
/// Dependency-ready waves borrow one immutable predecessor-layout map. A wave
/// never mutates that map while workers read it, and clones no project bindings.
/// Unsupported roots fail explicitly; their descendants cannot inherit defaults.
pub fn prepare_source_abi(
    frontend: &ColdFrontend,
    engine: &EngineSnapshot,
    evaluator: &DriverEvaluator<'_>,
    boundaries: &BTreeMap<UnitIdentity, BoundaryAbi>,
    resource_search_context: Option<u128>,
    workers: usize,
) -> Result<PreparedSourceAbi, AbiError> {
    prepare_source_abi_mode(
        frontend,
        engine,
        evaluator,
        boundaries,
        resource_search_context,
        workers,
        false,
    )
}

fn prepare_source_abi_mode(
    frontend: &ColdFrontend,
    engine: &EngineSnapshot,
    evaluator: &DriverEvaluator<'_>,
    boundaries: &BTreeMap<UnitIdentity, BoundaryAbi>,
    resource_search_context: Option<u128>,
    workers: usize,
    lexical_statics: bool,
) -> Result<PreparedSourceAbi, AbiError> {
    let executor = dm_exec::BuildExecutor::new(workers)
        .map_err(|error| AbiError::unsupported(format!("ABI executor creation failed: {error}")))?;
    prepare_source_abi_mode_on_executor(
        frontend,
        engine,
        evaluator,
        boundaries,
        resource_search_context,
        &executor,
        lexical_statics,
        None,
        None,
    )
}
#[allow(clippy::too_many_arguments)] // Explicit issued source index and borrowed ABI boundaries.
fn prepare_source_abi_mode_on_executor(
    frontend: &ColdFrontend,
    engine: &EngineSnapshot,
    evaluator: &DriverEvaluator<'_>,
    boundaries: &BTreeMap<UnitIdentity, BoundaryAbi>,
    resource_search_context: Option<u128>,
    executor: &dm_exec::BuildExecutor,
    lexical_statics: bool,
    issued_units: Option<&Arc<BTreeMap<UnitIdentity, MemberId>>>,
    artifacts: Option<&AbiArtifacts>,
) -> Result<PreparedSourceAbi, AbiError> {
    let batch_stage = dm_profile::stage("abi.batch.inputs");
    let batch_inputs = artifacts.and_then(|store| {
        abi_artifacts::batch::inputs(
            store,
            frontend,
            engine,
            boundaries,
            evaluator,
            resource_search_context,
            lexical_statics,
        )
    });
    drop(batch_stage);
    dm_profile::request_mark("abi.batch_inputs");
    let _replay_stage = dm_profile::stage("abi.batch.replay");
    // Whole-batch replay validates the union of every unit's reads in one
    // sequential receipt (~3.2 s on DeepQuarry, hit or miss); the per-unit
    // scheduler below admits the same retained rows in ~0.5 s. Opt in with
    // DMB_ABI_BATCH_REPLAY=1.
    let batch_replay = std::env::var_os("DMB_ABI_BATCH_REPLAY").is_some_and(|value| value == "1");
    if let (true, Some(store), Some(inputs)) = (batch_replay, artifacts, batch_inputs.as_ref()) {
        if let Some(prepared) =
            abi_artifacts::batch::replay(store, inputs, evaluator.resolver, frontend, issued_units)
        {
            return Ok(prepared);
        }
    }
    drop(_replay_stage);
    dm_profile::request_mark("abi.batch_replay_declined");
    let batch_capture = batch_inputs
        .as_ref()
        .map(|_| abi_artifacts::batch::Capture::default());
    let semantic_host = abi_artifacts::admission::SemanticHost(evaluator.resolver);
    let shared_admission = (!evaluator.resolver.observes_reads()
        || evaluator.resolver.transparent_receipt_observer().is_some())
    .then(|| dm_session::ReceiptAdmission::new(&semantic_host));
    let artifact_keys = std::sync::Mutex::new(Vec::new());
    let owned_index;
    let index = match issued_units {
        Some(index) => index,
        None => {
            owned_index = Arc::new(unit_members(frontend)?);
            &owned_index
        }
    };
    let roster = frontend.callable_roster().map_err(AbiError::unsupported)?;
    let tree = &frontend.snapshot.tree;
    let scheduled = artifacts
        .map(|store| executor.install(|| {
            abi_scheduler::admitted(
                store,
                frontend,
                engine,
                evaluator,
                boundaries,
                resource_search_context,
                lexical_statics,
                index,
                shared_admission.as_ref(),
                batch_inputs.as_deref(),
                &artifact_keys,
                batch_capture.as_ref(),
            )
        }))
        .unwrap_or_default();
    let abi_scheduler::Admitted {
        accepted: scheduled,
        provisional,
        candidate_layouts,
    } = scheduled;
    dm_profile::request_mark("abi.scheduled");
    let abi_scheduler::Seed {
        mut layouts,
        mut remaining,
        mut results,
        mut ready,
    } = abi_scheduler::seed(frontend, roster, scheduled)?;
    // Members whose final layout differs from the retained candidate layout
    // (recomputed to a different ABI, failed, or had no candidate). A
    // provisional row is accepted only when no direct parent is in this set.
    let mut changed_layouts: std::collections::HashSet<MemberId> = std::collections::HashSet::new();
    let mut provisional_accepted = 0usize;
    let mut wave_recomputed = 0usize;
    let mut failures = BTreeMap::new();
    // Only dirty rows enter dependency waves. Admitted immutable layouts already
    // satisfy their current predecessor edges and never re-enter worker dispatch.
    if !ready.is_empty() {
        while !ready.is_empty() {
            let encounter = ready.clone();
            let inherited = DriverInheritedFacts {
                frontend,
                engine,
                source_layouts: &layouts,
                boundaries,
                unit_members: index,
            };
            let lexical = LexicalAbiEvaluator(evaluator);
            let selected_evaluator: &dyn CapturedConstantEvaluator =
                if lexical_statics { &lexical } else { evaluator };
            let policy = crate::procedure_policy::CapturedProcedurePolicy {
                evaluator: selected_evaluator,
                inherited: &inherited,
                resource_search_context,
            };
            // Indexed collection preserves ready encounter order. install returns
            // only after the wave and all sibling jobs finish, including unwinding.
            let mut wave = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                executor.install(|| {
                    ready
                        .par_chunks(ready.len().div_ceil(executor.workers()).max(1))
                        .flat_map_iter(|chunk| {
                            let _profile = dm_profile::stage("cold.abi_preparation");
                            chunk
                                .iter()
                                .map(|ordinal| {
                                    let body = &frontend.bodies[*ordinal];
                                    if let (Some(row), Some(store)) = (provisional.get(ordinal), artifacts) {
                                        if row.parents.iter().flatten().all(|parent| !changed_layouts.contains(parent)) {
                                            return (*ordinal, Ok(row.accept(store, &artifact_keys, batch_capture.as_ref())), true);
                                        }
                                    }
                                    let result = (|| {
                                        let node = tree.member(body.member).ok_or_else(|| {
                                            AbiError::unsupported("body member missing")
                                        })?;
                                        let metadata =
                                            node.metadata.procedure.as_ref().ok_or_else(|| {
                                                AbiError::unsupported(
                                                    "procedure metadata unsupported",
                                                )
                                            })?;
                                        let parsed =
                                            frontend.compact_body(body).map_err(|error| {
                                                AbiError::unsupported(format!(
                                                    "body parse: {error:?}"
                                                ))
                                            })?;
                                        let context = AbiContext {
                                            identity: {
                                                let identity =
                                                    roster.identity(*ordinal).ok_or_else(|| {
                                                        AbiError::invariant(
                                                            "callable identity missing",
                                                        )
                                                    })?;
                                                UnitIdentity {
                                                    owner: identity.owner,
                                                    name: identity.name,
                                                    namespace: if identity.verb {
                                                        Namespace::Verb
                                                    } else {
                                                        Namespace::Proc
                                                    },
                                                    occurrence: identity.occurrence,
                                                }
                                            },
                                            symbols: evaluator.symbols,
                                            origin: &body.source,
                                            resolver: evaluator.resolver,
                                        };
                                        match artifacts {
                                            Some(artifacts) => abi_artifacts::prepare(
                                                artifacts,
                                                &artifact_keys,
                                                metadata,
                                                frontend
                                                    .procedure_settings(body)
                                                    .map_err(|error| {
                                                        AbiError::unsupported(format!(
                                                            "body settings: {error:?}"
                                                        ))
                                                    })?
                                                    .as_ref(),
                                                parsed,
                                                &context,
                                                evaluator,
                                                &inherited,
                                                lexical_statics,
                                                resource_search_context,
                                                shared_admission.as_ref(),
                                                batch_capture.as_ref(),
                                            ),
                                            None => policy.prepare_view(metadata, parsed, &context),
                                        }
                                    })();
                                    (*ordinal, result, false)
                                })
                                .collect::<Vec<_>>()
                        })
                        .collect::<Vec<_>>()
                })
            }))
            .map_err(|_| AbiError::invariant("ABI preparation worker panicked"))?;
            let positions: HashMap<_, _> = encounter
                .iter()
                .enumerate()
                .map(|(position, ordinal)| (*ordinal, position))
                .collect();
            wave.sort_by_key(|(ordinal, _, _)| positions[ordinal]);
            ready.clear();
            for (ordinal, result, reused) in wave {
                remaining[ordinal] = false;
                let member = frontend.bodies[ordinal].member;
                if reused {
                    provisional_accepted += 1;
                } else {
                    wave_recomputed += 1;
                    let same = match (&result, candidate_layouts.get(&member)) {
                        (Ok(unit), Some(old)) => unit
                            .abi
                            .as_ref()
                            .is_some_and(|new| Arc::ptr_eq(new, old) || new.as_ref() == old.as_ref()),
                        _ => false,
                    };
                    if !same {
                        changed_layouts.insert(member);
                    }
                }
                match result {
                    Ok(mut unit) => {
                        unit.require_production_abi()?;
                        // ABI preparation already validated this executable body. Final
                        // lowering consumes its independently authenticated current body;
                        // retaining this temporary copy would duplicate every cold unit.
                        unit.executable_body = Vec::new();
                        if unit.canonical.is_none() {
                            unit.issue_canonical();
                        }
                        let abi = Arc::clone(unit.abi.as_ref().expect("validated production ABI"));
                        layouts.insert(frontend.bodies[ordinal].member, abi);
                        results[ordinal] = Some(unit);
                        ready.extend(roster.dependents(ordinal).iter().copied());
                    }
                    Err(error) => {
                        failures.insert(ordinal, error);
                    }
                }
            }
        }
    }

    dm_profile::request_mark("abi.waves");
    if artifacts.is_some() {
        crate::daemon_eprintln!(
            "native ABI waves: recomputed_or_receipted={} provisional_accepted={} provisional_declined={} changed_layouts={}",
            wave_recomputed,
            provisional_accepted,
            provisional.len().saturating_sub(provisional_accepted),
            changed_layouts.len()
        );
    }
    for (ordinal, pending) in remaining.into_iter().enumerate() {
        if pending {
            // Descendants retain their failed predecessor's typed cause. A
            // source error must not turn into an internal failure just because
            // dependent layouts cannot be prepared after it.
            let mut previous = tree
                .member(frontend.bodies[ordinal].member)
                .and_then(|node| node.previous);
            let mut inherited_kind = None;
            for _ in 0..frontend.bodies.len() {
                let Some(member) = previous else { break };
                if let Some(index) = roster.ordinal(member) {
                    if let Some(error) = failures.get(&index) {
                        inherited_kind = Some(error.kind);
                        break;
                    }
                }
                previous = tree.member(member).and_then(|node| node.previous);
            }
            failures.insert(
                ordinal,
                AbiError {
                    kind: inherited_kind
                        .unwrap_or(dm_codegen_byond::procedure_abi::AbiErrorKind::Unsupported),
                    message: "predecessor ABI unavailable, failed or cyclic".into(),
                },
            );
        }
    }
    if let Some(artifacts) = artifacts {
        artifacts.prune(&artifact_keys);
    }
    let entries = results
        .into_iter()
        .enumerate()
        .filter_map(|(ordinal, result)| result.map(|unit| (frontend.bodies[ordinal].member, unit)))
        .collect();
    let diagnostics: Vec<_> = failures.into_iter().collect();
    let units =
        PreparedAbiUnits::issue(frontend, Arc::clone(index), entries, diagnostics.is_empty())?;
    let units = prepared_units::certify_capture(units, batch_capture.as_ref());
    let prepared = PreparedSourceAbi { units, diagnostics };
    if prepared.diagnostics.is_empty() {
        if let (Some(store), Some(inputs)) = (artifacts, batch_inputs) {
            if let Some(capture) = &batch_capture {
                abi_artifacts::batch::remember(
                    store,
                    inputs,
                    evaluator.resolver,
                    capture,
                    prepared.units_owner(),
                );
            }
        }
    }
    Ok(prepared)
}

/// Immutable prepared-unit consumer for the existing lowering trait. Only this
/// unit's lexical inputs/body are cloned; inherited project maps stay borrowed.
pub struct FrozenPreparedPolicy<'a> {
    frontend: &'a ColdFrontend,
    prepared: &'a PreparedSourceAbi,
    members: Arc<BTreeMap<UnitIdentity, MemberId>>,
    roster: &'a dm_tree::frontend::CallableRoster,
}
impl<'a> FrozenPreparedPolicy<'a> {
    pub fn new(
        frontend: &'a ColdFrontend,
        prepared: &'a PreparedSourceAbi,
    ) -> Result<Self, AbiError> {
        if !prepared.diagnostics.is_empty() {
            return Err(AbiError::unsupported(
                "cannot lower a failed ABI preparation batch",
            ));
        }
        let members = Arc::clone(prepared.units.members());
        Self::new_with_units(frontend, prepared, members)
    }
    pub(crate) fn new_with_units(
        frontend: &'a ColdFrontend,
        prepared: &'a PreparedSourceAbi,
        members: Arc<BTreeMap<UnitIdentity, MemberId>>,
    ) -> Result<Self, AbiError> {
        if !prepared.diagnostics.is_empty() {
            return Err(AbiError::unsupported(
                "cannot lower a failed ABI preparation batch",
            ));
        }
        let roster = frontend.callable_roster().map_err(AbiError::unsupported)?;
        if members.len() != roster.members().len() {
            return Err(AbiError::unsupported(
                "issued callable index differs from frontend",
            ));
        }
        prepared.units.admit(frontend, &members)?;
        Ok(Self {
            frontend,
            prepared,
            members,
            roster,
        })
    }
    fn unit(
        &self,
        identity: UnitIdentity,
    ) -> Result<&crate::procedure_policy::PreparedUnit, String> {
        let member = self
            .members
            .get(&identity)
            .ok_or("prepared ABI identity missing")?;
        let ordinal = self
            .roster
            .ordinal(*member)
            .ok_or("prepared ABI member missing")?;
        self.prepared
            .units()
            .get(ordinal)
            .filter(|(id, _)| id == member)
            .map(|(_, unit)| unit)
            .ok_or_else(|| "prepared ABI identity missing".into())
    }

    fn validate(
        &self,
        identity: UnitIdentity,
        metadata: &dm_ir::ProcedureMetadata,
        symbols: &dm_ir::SymbolTable,
        origin: &dm_tree::frontend::SourceLocation,
    ) -> Result<&dm_tree::frontend::BodyOccurrence, String> {
        if !symbols.is_extension_of(self.frontend.snapshot.tree.symbols()) {
            return Err("prepared ABI symbol snapshot changed".into());
        }
        let member = self
            .members
            .get(&identity)
            .ok_or("prepared ABI identity missing")?;
        let node = self
            .frontend
            .snapshot
            .tree
            .member(*member)
            .ok_or("prepared member missing")?;
        if node.metadata.procedure.as_deref() != Some(metadata) {
            return Err("prepared ABI metadata changed".into());
        }
        let ordinal = self
            .roster
            .ordinal(*member)
            .ok_or("prepared body missing")?;
        let body = &self.frontend.bodies[ordinal];
        let source = &body.source;
        let macros_equal = source.macro_expansions.len() == origin.macro_expansions.len()
            && source
                .macro_expansions
                .iter()
                .zip(origin.macro_expansions.iter())
                .all(|(left, right)| {
                    left.name == right.name
                        && left.invocation_span == right.invocation_span
                        && left.replacement_chain == right.replacement_chain
                        && match (&left.definition, &right.definition) {
                            (None, None) => true,
                            (Some(left), Some(right)) => {
                                left.path == right.path
                                    && left.source_span == right.source_span
                                    && left.source_line == right.source_line
                            }
                            _ => false,
                        }
                });
        if source.span != origin.span
            || source.path != origin.path
            || source.semantic_path != origin.semantic_path
            || source.line != origin.line
            || source.encounter_ordinal != origin.encounter_ordinal
            || source.include_occurrence != origin.include_occurrence
            || source.include_chain != origin.include_chain
            || !macros_equal
        {
            return Err("prepared ABI source occurrence changed".into());
        }
        Ok(body)
    }
}
impl crate::lowering::AbiPolicy for FrozenPreparedPolicy<'_> {
    fn current_local_inputs<'a>(
        &'a self,
        frontend: &'a ColdFrontend,
        symbols: &dm_ir::SymbolTable,
    ) -> Option<crate::lowering::LocalInputRoster<'a>> {
        if !std::ptr::eq(frontend, self.frontend)
            || !symbols.is_extension_of(frontend.snapshot.tree.symbols())
        {
            return None;
        }
        Some(LocalInputRoster::from_admitted(
            frontend,
            self.prepared.units_owner(),
        ))
    }

    fn uses_issued_statements(&self) -> bool {
        true
    }
    fn prepare_issued(
        &self,
        metadata: &dm_ir::ProcedureMetadata,
        input: &dm_tree::frontend::IssuedBodyInput<'_>,
        context: &AbiContext<'_>,
    ) -> Result<Option<crate::procedure_policy::PreparedReplay>, String> {
        let body = self.validate(context.identity, metadata, context.symbols, context.origin)?;
        self.frontend
            .validate_body_input(input, body)
            .map_err(|error| error.message)?;
        let unit = self.unit(context.identity)?;
        Ok(crate::procedure_policy::PreparedReplay::from_unit(unit))
    }
    fn prepare_captured(
        &self,
        metadata: &dm_ir::ProcedureMetadata,
        parsed: &dm_tree::frontend::ParsedBody<'_>,
        context: &AbiContext<'_>,
    ) -> Result<crate::procedure_policy::PreparedUnit, String> {
        let body = self.validate(context.identity, metadata, context.symbols, context.origin)?;
        self.frontend
            .validate_parsed_body(parsed, body)
            .map_err(|error| error.message)?;
        let unit = self.unit(context.identity)?;
        Ok(crate::procedure_policy::PreparedUnit {
            canonical: unit.canonical.clone(),
            inputs: unit.inputs.clone(),
            executable_body: dm_tree::settings::strip_setting_items(parsed.item().children.clone()),
            abi: unit.abi.clone(),
        })
    }
    fn prepare_owned_captured(
        &self,
        metadata: &dm_ir::ProcedureMetadata,
        parsed: dm_tree::frontend::ParsedBody<'_>,
        context: &AbiContext<'_>,
    ) -> Result<
        (
            crate::procedure_policy::PreparedUnit,
            dm_syntax::Item,
            Option<std::sync::Arc<dm_tree::frontend::StatementBody>>,
        ),
        String,
    > {
        let body = self.validate(context.identity, metadata, context.symbols, context.origin)?;
        self.frontend
            .validate_parsed_body(&parsed, body)
            .map_err(|error| error.message)?;
        let unit = self.unit(context.identity)?;
        let (mut header, statements) = parsed.into_parts();
        let executable_body =
            dm_tree::settings::strip_setting_items(std::mem::take(&mut header.children));
        Ok((
            crate::procedure_policy::PreparedUnit {
                canonical: unit.canonical.clone(),
                inputs: unit.inputs.clone(),
                executable_body,
                abi: unit.abi.clone(),
            },
            header,
            statements,
        ))
    }
    fn inputs(
        &self,
        identity: UnitIdentity,
        metadata: &dm_ir::ProcedureMetadata,
        symbols: &dm_ir::SymbolTable,
        origin: &dm_tree::frontend::SourceLocation,
    ) -> Result<dm_codegen_byond::ProcedureInputs, String> {
        self.validate(identity, metadata, symbols, origin)?;
        Ok((*self.unit(identity)?.inputs).clone())
    }
    fn prepare(
        &self,
        metadata: &dm_ir::ProcedureMetadata,
        parsed: &dm_syntax::Item,
        context: &AbiContext<'_>,
    ) -> Result<crate::procedure_policy::PreparedUnit, String> {
        let body = self.validate(context.identity, metadata, context.symbols, context.origin)?;
        let captured = self
            .frontend
            .body(body)
            .map_err(|error| format!("prepared body capture: {error:?}"))?;
        if &captured != parsed {
            return Err("prepared ABI body differs from captured frontend".into());
        }
        let unit = self.unit(context.identity)?;
        Ok(crate::procedure_policy::PreparedUnit {
            canonical: unit.canonical.clone(),
            inputs: unit.inputs.clone(),
            executable_body: dm_tree::settings::strip_setting_items(parsed.children.clone()),
            abi: unit.abi.clone(),
        })
    }
}

#[cfg(test)]
#[path = "driver_facts/abi_body_release_tests.rs"]
mod abi_body_release_tests;

pub(crate) use abi_artifacts::{admit_initializer_engine_bucket, initializer_engine_record};
