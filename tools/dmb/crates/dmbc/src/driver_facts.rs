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
            return Err(AbiError(
                "unsupported intrinsic ABI receipt template".into(),
            ));
        }
        let fact = crate::native_callbacks::lookup(owner, name)
            .ok_or_else(|| AbiError("unsupported intrinsic ABI receipt callback".into()))?;
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
    pub source_layouts: &'a HashMap<MemberId, ProcLayout>,
    pub boundaries: &'a BTreeMap<UnitIdentity, BoundaryAbi>,
    pub unit_members: &'a BTreeMap<UnitIdentity, MemberId>,
}
impl CapturedInheritedFacts for DriverInheritedFacts<'_> {
    fn inherited(&self, context: &AbiContext<'_>) -> Result<InheritedLayout, AbiError> {
        let tree = &self.frontend.snapshot.tree;
        let id = self
            .unit_members
            .get(&context.identity)
            .ok_or_else(|| AbiError("procedure is not in captured model".into()))?;
        let node = tree
            .member(*id)
            .ok_or_else(|| AbiError("indexed procedure member missing".into()))?;
        if let Some(previous) = node.previous {
            return self
                .source_layouts
                .get(&previous)
                .cloned()
                .map(InheritedLayout::Known)
                .ok_or_else(|| {
                    AbiError("previous source procedure ABI has not been prepared".into())
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
                    return Err(AbiError(
                        "intrinsic ABI receipt does not match current procedure".into(),
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
                Err(AbiError(
                    "intrinsic ABI receipt is outside current ancestry".into(),
                ))
            }
            Some(BoundaryAbi::Engine { owner, name, kind }) => {
                if *name != node.name || *kind != node.kind {
                    return Err(AbiError(
                        "engine boundary names a different procedure".into(),
                    ));
                }
                let mut cursor = Some(node.owner);
                let mut contains = false;
                while let Some(id) = cursor {
                    contains |= tree.type_node(id).is_some_and(|ty| ty.path == *owner);
                    cursor = tree.parent(id);
                }
                if !contains {
                    return Err(AbiError(
                        "engine boundary is outside current ancestry".into(),
                    ));
                }
                self.engine
                    .procedure_layout(*owner, *name, *kind)
                    .map_err(|error| AbiError(format!("engine ABI: {error:?}")))?
                    .cloned()
                    .map(InheritedLayout::Known)
                    .ok_or_else(|| AbiError("selected engine ABI is not captured".into()))
            }
            None => Ok(InheritedLayout::Unsupported),
        }
    }
}

/// Exact source occurrence index built once, independently of source encounter
/// scheduling. Distinct formal/reopen identities cannot alias one prepared ABI.
pub fn unit_members(frontend: &ColdFrontend) -> Result<BTreeMap<UnitIdentity, MemberId>, AbiError> {
    let tree = &frontend.snapshot.tree;
    let mut result = BTreeMap::new();
    for body in frontend.bodies.iter() {
        let node = tree
            .member(body.member)
            .ok_or_else(|| AbiError("body member missing".into()))?;
        let owner = tree
            .type_node(node.owner)
            .ok_or_else(|| AbiError("body owner missing".into()))?
            .path;
        let namespace = match node.kind {
            MemberKind::Proc => Namespace::Proc,
            MemberKind::Verb => Namespace::Verb,
            MemberKind::Var => return Err(AbiError("variable body in procedure index".into())),
        };
        let occurrence = tree
            .override_chain(body.member)
            .iter()
            .filter(|id| {
                tree.member(**id).is_some_and(|prior| {
                    prior.owner == node.owner && prior.name == node.name && prior.kind == node.kind
                })
            })
            .count()
            .checked_sub(1)
            .ok_or_else(|| AbiError("empty procedure chain".into()))?;
        let identity = UnitIdentity {
            owner,
            name: node.name,
            namespace,
            occurrence: u32::try_from(occurrence)
                .map_err(|_| AbiError("procedure occurrence overflow".into()))?,
        };
        if result.insert(identity, body.member).is_some() {
            return Err(AbiError("ambiguous current procedure occurrence".into()));
        }
    }
    Ok(result)
}

pub struct PreparedSourceAbi {
    /// Encounter order, regardless of topological/worker completion order.
    pub units: Vec<(MemberId, crate::procedure_policy::PreparedUnit)>,
    pub diagnostics: Vec<(usize, String)>,
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
                AbiError("ABI diagnostic body ordinal is outside captured frontend".into())
            })?;
            Ok(crate::lowering::LoweringDiagnostic {
                kind: dm_tree::frontend::DiagnosticKind::UnsupportedModel,
                identity: identities.get(&body.member).copied(),
                origin: body.source.clone(),
                message: message.clone(),
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
    let coverage =
        crate::engine_abi_coverage::NamedEngineCoverage::pinned(engine).map_err(AbiError)?;
    let policy_identity = coverage.policy_identity();
    let boundaries = coverage.boundaries(frontend).map_err(AbiError)?;
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
        .map_err(|error| AbiError(format!("ABI executor creation failed: {error}")))?;
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
    startup.validate_for(frontend).map_err(AbiError)?;
    let static_resolver = startup.resolver(frontend, resolver).map_err(AbiError)?;
    let resolver = &static_resolver;
    let coverage =
        crate::engine_abi_coverage::NamedEngineCoverage::pinned(engine).map_err(AbiError)?;
    let policy_identity = coverage.policy_identity();
    let boundaries = coverage
        .boundaries_with_units(frontend, startup.unit_members())
        .map_err(AbiError)?;
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
        .map_err(|error| AbiError(format!("ABI executor creation failed: {error}")))?;
    prepare_source_abi_mode_on_executor(
        frontend,
        engine,
        evaluator,
        boundaries,
        resource_search_context,
        &executor,
        lexical_statics,
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
    issued_units: Option<&BTreeMap<UnitIdentity, MemberId>>,
) -> Result<PreparedSourceAbi, AbiError> {
    let owned_index;
    let index = match issued_units {
        Some(index) => index,
        None => {
            owned_index = unit_members(frontend)?;
            &owned_index
        }
    };
    let identities: HashMap<_, _> = index.iter().map(|(key, id)| (*id, *key)).collect();
    let tree = &frontend.snapshot.tree;
    let mut layouts = HashMap::new();
    let mut remaining = vec![true; frontend.bodies.len()];
    let mut results: Vec<Option<crate::procedure_policy::PreparedUnit>> =
        (0..remaining.len()).map(|_| None).collect();
    let mut failures = BTreeMap::new();
    let body_ordinals: HashMap<_, _> = frontend
        .bodies
        .iter()
        .enumerate()
        .map(|(ordinal, body)| (body.member, ordinal))
        .collect();
    let mut dependents = vec![Vec::new(); frontend.bodies.len()];
    let mut ready = Vec::new();
    for (ordinal, body) in frontend.bodies.iter().enumerate() {
        let node = tree
            .member(body.member)
            .ok_or_else(|| AbiError("body member missing".into()))?;
        match node.previous {
            None => ready.push(ordinal),
            Some(previous) => {
                if let Some(predecessor) = body_ordinals.get(&previous) {
                    dependents[*predecessor].push(ordinal);
                }
            }
        }
    }
    // The build executor survives every dependency wave and every other stage.
    if !ready.is_empty() {
        while !ready.is_empty() {
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
            let wave = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                executor.install(|| {
                    ready
                        .par_chunks(ready.len().div_ceil(executor.workers()).max(1))
                        .flat_map_iter(|chunk| {
                            let _profile = dm_profile::stage("cold.abi_preparation");
                            chunk
                                .iter()
                                .map(|ordinal| {
                                    let body = &frontend.bodies[*ordinal];
                                    let result = (|| {
                                        let node = tree.member(body.member).ok_or_else(|| {
                                            AbiError("body member missing".into())
                                        })?;
                                        let metadata =
                                            node.metadata.procedure.as_ref().ok_or_else(|| {
                                                AbiError("procedure metadata unsupported".into())
                                            })?;
                                        let parsed =
                                            frontend.compact_body(body).map_err(|error| {
                                                AbiError(format!("body parse: {error:?}"))
                                            })?;
                                        let context = AbiContext {
                                            identity: identities[&body.member],
                                            symbols: evaluator.symbols,
                                            origin: &body.source,
                                            resolver: evaluator.resolver,
                                        };
                                        policy.prepare(metadata, parsed, &context)
                                    })();
                                    (*ordinal, result)
                                })
                                .collect::<Vec<_>>()
                        })
                        .collect::<Vec<_>>()
                })
            }))
            .map_err(|_| AbiError("ABI preparation worker panicked".into()))?;
            ready.clear();
            for (ordinal, result) in wave {
                remaining[ordinal] = false;
                match result {
                    Ok(unit) => {
                        let layout = unit.require_production_abi()?.layout.clone();
                        layouts.insert(frontend.bodies[ordinal].member, layout);
                        results[ordinal] = Some(unit);
                        ready.extend(dependents[ordinal].iter().copied());
                    }
                    Err(error) => {
                        failures.insert(ordinal, error.to_string());
                    }
                }
            }
        }
    }

    for (ordinal, pending) in remaining.into_iter().enumerate() {
        if pending {
            failures.insert(
                ordinal,
                "predecessor ABI unavailable, failed or cyclic".into(),
            );
        }
    }
    Ok(PreparedSourceAbi {
        units: results
            .into_iter()
            .enumerate()
            .filter_map(|(ordinal, result)| {
                result.map(|unit| (frontend.bodies[ordinal].member, unit))
            })
            .collect(),
        diagnostics: failures.into_iter().collect(),
    })
}

/// Immutable prepared-unit consumer for the existing lowering trait. Only this
/// unit's lexical inputs/body are cloned; inherited project maps stay borrowed.
pub struct FrozenPreparedPolicy<'a> {
    frontend: &'a ColdFrontend,
    prepared: &'a PreparedSourceAbi,
    by_identity: BTreeMap<UnitIdentity, usize>,
    members: Arc<BTreeMap<UnitIdentity, MemberId>>,
    body_ordinals: HashMap<MemberId, usize>,
}
impl<'a> FrozenPreparedPolicy<'a> {
    pub fn new(
        frontend: &'a ColdFrontend,
        prepared: &'a PreparedSourceAbi,
    ) -> Result<Self, AbiError> {
        if !prepared.diagnostics.is_empty() {
            return Err(AbiError(
                "cannot lower a failed ABI preparation batch".into(),
            ));
        }
        let members = Arc::new(unit_members(frontend)?);
        Self::new_with_units(frontend, prepared, members)
    }
    pub(crate) fn new_with_units(
        frontend: &'a ColdFrontend,
        prepared: &'a PreparedSourceAbi,
        members: Arc<BTreeMap<UnitIdentity, MemberId>>,
    ) -> Result<Self, AbiError> {
        if !prepared.diagnostics.is_empty() {
            return Err(AbiError(
                "cannot lower a failed ABI preparation batch".into(),
            ));
        }
        let inverse: HashMap<_, _> = members
            .iter()
            .map(|(identity, member)| (*member, *identity))
            .collect();
        let mut by_identity = BTreeMap::new();
        for (index, (member, unit)) in prepared.units.iter().enumerate() {
            unit.require_production_abi()?;
            let identity = inverse
                .get(member)
                .ok_or_else(|| AbiError("prepared member belongs to another frontend".into()))?;
            if by_identity.insert(*identity, index).is_some() {
                return Err(AbiError("duplicate prepared member".into()));
            }
        }
        if by_identity.len() != members.len() {
            return Err(AbiError(
                "prepared ABI batch does not cover all bodies".into(),
            ));
        }
        let body_ordinals = frontend
            .bodies
            .iter()
            .enumerate()
            .map(|(ordinal, body)| (body.member, ordinal))
            .collect();
        Ok(Self {
            frontend,
            prepared,
            by_identity,
            members,
            body_ordinals,
        })
    }
    fn unit(
        &self,
        identity: UnitIdentity,
    ) -> Result<&crate::procedure_policy::PreparedUnit, String> {
        self.by_identity
            .get(&identity)
            .map(|index| &self.prepared.units[*index].1)
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
            .body_ordinals
            .get(member)
            .ok_or("prepared body missing")?;
        let body = &self.frontend.bodies[*ordinal];
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
        Ok(crate::procedure_policy::PreparedReplay::from_frozen(
            unit.inputs.clone(),
            Arc::clone(unit.abi.as_ref().ok_or("prepared production ABI missing")?),
        ))
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
        Ok(self.unit(identity)?.inputs.clone())
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
            inputs: unit.inputs.clone(),
            executable_body: dm_tree::settings::strip_setting_items(parsed.children.clone()),
            abi: unit.abi.clone(),
        })
    }
}
