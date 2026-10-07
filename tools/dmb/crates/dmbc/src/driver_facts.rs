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
use std::{
    cell::RefCell,
    collections::{BTreeMap, HashMap},
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

/// One immutable resolver must include the selected scalar constant overlay,
/// engine constants and captured resources. No filesystem access occurs here.
pub struct DriverEvaluator<'a> {
    pub resolver: &'a dyn Resolver,
    pub symbols: &'a dm_ir::SymbolTable,
}
impl DriverEvaluator<'_> {
    fn scalar(
        &self,
        owner: SymbolId,
        expression: &SymbolicExpression,
    ) -> Result<Option<SemanticValue>, String> {
        let failure = RefCell::new(None);
        let value = dm_tree::constants::evaluate_with(
            &expression
                .source_text(self.symbols)
                .ok_or("expression spelling is not captured")?,
            |name| {
                let (scope, name) = name
                    .rsplit_once("::")
                    .map_or((owner, name), |(path, name)| (SymbolId::of(path), name));
                let query = ResolveQuery::Constant {
                    owner: scope,
                    name: SymbolId::of(name),
                };
                let answer = self.resolver.resolve(query);
                let value = match answer {
                    ResolvedMeaning::Value(value) => value,
                    ResolvedMeaning::Member { data, .. } if data.resolved_constant.is_some() => {
                        data.resolved_constant.as_ref().unwrap().clone()
                    }
                    // A positive, non-opaque nonconst variable is a runtime
                    // dependency, rather than an unknown constant spelling.
                    other @ (ResolvedMeaning::Unsupported(_) | ResolvedMeaning::Missing) => {
                        let runtime = |meaning| matches!(meaning, ResolvedMeaning::Member { data, .. } if data.inherited_opaque.is_none() && data.flags & 2 == 0);
                        if runtime(self.resolver.resolve(ResolveQuery::Var {
                            owner: scope,
                            name: SymbolId::of(name),
                        })) || (scope == owner
                            && runtime(
                                self.resolver
                                    .resolve(ResolveQuery::GlobalVar(SymbolId::of(name))),
                            ))
                        {
                            return None;
                        }
                        match self
                            .resolver
                            .resolve(ResolveQuery::PredefinedConstant(SymbolId::of(name)))
                        {
                            ResolvedMeaning::Value(value) => value,
                            _ => {
                                *failure.borrow_mut() =
                                    Some(format!("constant {name} is not captured: {other:?}"));
                                return None;
                            }
                        }
                    }
                    other => {
                        *failure.borrow_mut() =
                            Some(format!("constant query is unsupported: {other:?}"));
                        return None;
                    }
                };
                match value {
                    SemanticValue::Null => Some(Constant::Null),
                    SemanticValue::NumberBits(bits) => Some(Constant::Number(f32::from_bits(bits))),
                    SemanticValue::Text(bytes) => Some(Constant::EncodedText(bytes.to_vec())),
                    SemanticValue::Type(path) => self
                        .symbols
                        .text(path)
                        .map(|path| Constant::TypePath(path.into())),
                    _ => {
                        *failure.borrow_mut() = Some("constant value is not scalar".into());
                        None
                    }
                }
            },
            |raw| match dm_codegen_byond::decode_constant_string_literal(raw) {
                Ok(value) => value,
                Err(error) => {
                    *failure.borrow_mut() = Some(error);
                    None
                }
            },
            |expr| dm_codegen_byond::nameof_reference(expr).map(str::to_owned),
        );
        if let Some(error) = failure.into_inner() {
            return Err(error);
        }
        Ok(match value {
            None => None,
            Some(Constant::Null) => Some(SemanticValue::Null),
            Some(Constant::Number(number)) => Some(SemanticValue::NumberBits(number.to_bits())),
            Some(Constant::Text(text)) => Some(SemanticValue::Text(text.into_bytes().into())),
            Some(Constant::EncodedText(bytes)) => Some(SemanticValue::Text(bytes.into())),
            Some(Constant::TypePath(path)) => {
                let id = SymbolId::of(&path);
                if self.symbols.text(id) != Some(path.as_str())
                    || !matches!(self.resolver.resolve(ResolveQuery::Type(id)), ResolvedMeaning::Symbol(found) if found == id)
                {
                    return Err(format!("type constant {path} is not positively captured"));
                }
                Some(SemanticValue::Type(id))
            }
        })
    }
}
impl CapturedConstantEvaluator for DriverEvaluator<'_> {
    fn evaluate(
        &self,
        expression: &SymbolicExpression,
        context: &AbiContext<'_>,
    ) -> Result<SemanticValue, AbiError> {
        self.scalar(context.identity.owner, expression)
            .map_err(AbiError)?
            .ok_or_else(|| AbiError("ABI setting is not a captured scalar".into()))
    }
}
impl CapturedInitializerEvaluator for DriverEvaluator<'_> {
    fn evaluate(
        &self,
        owner: SymbolId,
        expression: &SymbolicExpression,
    ) -> Result<Evaluation, String> {
        Ok(self
            .scalar(owner, expression)?
            .map_or(Evaluation::Runtime, Evaluation::Scalar))
    }
}

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
    pub(crate) fn new_del(
        engine: &EngineSnapshot,
        owner: SymbolId,
        name: SymbolId,
    ) -> Result<Self, AbiError> {
        const TEMPLATE: &[u8] = include_bytes!("../../../fixtures/native_template.bin");
        if !engine.matches_template(TEMPLATE, 1)
            || !["/datum", "/atom", "/mob", "/client", "/world"]
                .into_iter()
                .any(|path| SymbolId::of(path) == owner)
        {
            return Err(AbiError("unsupported intrinsic ABI receipt domain".into()));
        }
        let spelling = if name == SymbolId::of("New") {
            "New"
        } else if name == SymbolId::of("Del") {
            "Del"
        } else {
            return Err(AbiError("unsupported intrinsic ABI receipt name".into()));
        };
        Ok(Self {
            engine_identity: engine.identity(),
            owner,
            name,
            layout: ProcLayout {
                display_name: Some(spelling.as_bytes().to_vec()),
                ..ProcLayout::default()
            },
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
    let index = unit_members(frontend)?;
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
    while !ready.is_empty() {
        let inherited = DriverInheritedFacts {
            frontend,
            engine,
            source_layouts: &layouts,
            boundaries,
            unit_members: &index,
        };
        let policy = crate::procedure_policy::CapturedProcedurePolicy {
            evaluator,
            inherited: &inherited,
            resource_search_context,
        };
        let worker_count = workers.clamp(1, 8).min(ready.len());
        let chunk = ready.len().div_ceil(worker_count);
        let wave = std::thread::scope(|scope| {
            let handles: Vec<_> = ready
                .chunks(chunk)
                .map(|ordinals| {
                    let policy = &policy;
                    let identities = &identities;
                    scope.spawn(move || {
                        ordinals
                            .iter()
                            .map(|ordinal| {
                                let body = &frontend.bodies[*ordinal];
                                let result = (|| {
                                    let node = tree
                                        .member(body.member)
                                        .ok_or_else(|| AbiError("body member missing".into()))?;
                                    let metadata =
                                        node.metadata.procedure.as_ref().ok_or_else(|| {
                                            AbiError("procedure metadata unsupported".into())
                                        })?;
                                    let parsed = frontend.body(body).map_err(|error| {
                                        AbiError(format!("body parse: {error:?}"))
                                    })?;
                                    let context = AbiContext {
                                        identity: identities[&body.member],
                                        symbols: tree.symbols(),
                                        origin: &body.source,
                                        resolver: evaluator.resolver,
                                    };
                                    policy.prepare(metadata, &parsed, &context)
                                })();
                                (*ordinal, result)
                            })
                            .collect::<Vec<_>>()
                    })
                })
                .collect();
            handles
                .into_iter()
                .map(|handle| {
                    handle
                        .join()
                        .map_err(|_| AbiError("ABI preparation worker panicked".into()))
                })
                .collect::<Result<Vec<_>, _>>()
        })?;
        ready.clear();
        for (ordinal, result) in wave.into_iter().flatten() {
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
    members: BTreeMap<UnitIdentity, MemberId>,
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
        let members = unit_members(frontend)?;
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
        if !std::ptr::eq(symbols, self.frontend.snapshot.tree.symbols()) {
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
            executable_body: unit.executable_body.clone(),
            abi: unit.abi.clone(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            // Descendant encountered first: scheduling must follow previous,
            // not source order. Public result order remains source order.
            Ok("/child\n    parent_type = /base\n/child/p()\n    return 2\n/base\n/base/proc/p()\n    set name = \"base display\"\n    return 1\n".into())
        }
    }
    fn frontend() -> ColdFrontend {
        dm_tree::frontend::build_with_config(
            Path::new("project.dme"),
            &Source,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
        )
        .unwrap()
    }
    #[test]
    fn pinned_constructor_prepares_source_dependency_without_caller_fresh_map() {
        let engine =
            EngineSnapshot::from_bytes(include_bytes!("../../../fixtures/native_template.bin"), 1)
                .unwrap();
        let seed = engine.frontend_seed();
        let frontend = dm_tree::frontend::build_with_config(
            Path::new("project.dme"),
            &Source,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap();
        let prepared =
            prepare_pinned_source_abi(&frontend, &engine, frontend.snapshot.tree.as_ref(), None, 2)
                .unwrap();
        assert!(
            prepared.prepared.diagnostics.is_empty(),
            "{:?}",
            prepared.prepared.diagnostics
        );
        assert_eq!(prepared.prepared.units.len(), frontend.bodies.len());
        assert_ne!(prepared.policy_identity, engine.identity());
        let policy = FrozenPreparedPolicy::new(&frontend, &prepared.prepared).unwrap();
        let lowered = crate::lowering::lower_frontend(
            &frontend,
            frontend.snapshot.tree.as_ref(),
            &policy,
            crate::lowering::LoweringConfig { workers: 2, ..Default::default() },
        );
        assert!(lowered.diagnostics.is_empty(), "{:?}", lowered.diagnostics);
        assert!(lowered.units.iter().all(|unit| unit.abi.is_some()));
    }
    #[test]
    fn predecessor_abi_waves_preserve_encounter_order_and_inherited_layout() {
        let frontend = frontend();
        let engine =
            EngineSnapshot::from_bytes(include_bytes!("../../../fixtures/native_template.bin"), 1)
                .unwrap();
        let index = unit_members(&frontend).unwrap();
        let base = *index
            .keys()
            .find(|identity| identity.owner == SymbolId::of("/base"))
            .unwrap();
        let evaluator = DriverEvaluator {
            resolver: frontend.snapshot.tree.as_ref(),
            symbols: frontend.snapshot.tree.symbols(),
        };
        // Fixture explicitly declares its base fresh; production must capture
        // the corresponding complete engine absence fact before issuing Fresh.
        let boundaries = BTreeMap::from([(base, BoundaryAbi::Fresh)]);
        let batch =
            prepare_source_abi(&frontend, &engine, &evaluator, &boundaries, None, 2).unwrap();
        assert!(batch.diagnostics.is_empty(), "{:?}", batch.diagnostics);
        assert_eq!(
            batch.units.iter().map(|(id, _)| *id).collect::<Vec<_>>(),
            frontend
                .bodies
                .iter()
                .map(|body| body.member)
                .collect::<Vec<_>>()
        );
        for (_, unit) in &batch.units {
            assert_eq!(
                unit.require_production_abi()
                    .unwrap()
                    .layout
                    .display_name
                    .as_deref(),
                Some(b"base display".as_slice())
            );
        }
        let policy = FrozenPreparedPolicy::new(&frontend, &batch).unwrap();
        let lowered = crate::lowering::lower_frontend(
            &frontend,
            frontend.snapshot.tree.as_ref(),
            &policy,
            Default::default(),
        );
        assert!(lowered.diagnostics.is_empty(), "{:?}", lowered.diagnostics);
        lowered.require_production_abi().unwrap();
    }
    #[test]
    fn unknown_root_abi_is_not_fresh_and_blocks_descendants() {
        let frontend = frontend();
        let engine =
            EngineSnapshot::from_bytes(include_bytes!("../../../fixtures/native_template.bin"), 1)
                .unwrap();
        let evaluator = DriverEvaluator {
            resolver: frontend.snapshot.tree.as_ref(),
            symbols: frontend.snapshot.tree.symbols(),
        };
        let batch =
            prepare_source_abi(&frontend, &engine, &evaluator, &BTreeMap::new(), None, 8).unwrap();
        assert!(batch.units.is_empty());
        assert_eq!(batch.diagnostics.len(), frontend.bodies.len());
        assert!(batch
            .diagnostics
            .windows(2)
            .all(|pair| pair[0].0 < pair[1].0));
        assert!(FrozenPreparedPolicy::new(&frontend, &batch).is_err());
    }
}
