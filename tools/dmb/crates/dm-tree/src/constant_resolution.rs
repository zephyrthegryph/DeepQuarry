//! Demand-driven scalar evaluation over one immutable declaration snapshot.
//! Backend decoding is explicit; unsupported values never become null/missing.
use crate::constants::{evaluate_with_resources_and_calls, Constant, PureCallError, PureCalls};
use crate::{DefinitionMode, MemberId, MemberKind, SemanticTree, TreeSnapshot};
use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver, SemanticValue, SymbolId};
use dm_syntax::Expr;
use std::cell::RefCell;
use std::collections::{BTreeMap, BTreeSet};
use std::sync::Arc;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub enum ScalarQuery {
    Const { owner: SymbolId, name: SymbolId },
    DeclaredDefault { owner: SymbolId, name: SymbolId },
    EffectiveDefault { owner: SymbolId, name: SymbolId },
}
impl ScalarQuery {
    fn parts(self) -> (u8, SymbolId, SymbolId) {
        match self {
            Self::Const { owner, name } => (0, owner, name),
            Self::DeclaredDefault { owner, name } => (1, owner, name),
            Self::EffectiveDefault { owner, name } => (2, owner, name),
        }
    }
    fn encode(self, bytes: &mut Vec<u8>) {
        let (domain, owner, name) = self.parts();
        bytes.push(domain);
        bytes.extend_from_slice(&owner.bits().to_le_bytes());
        bytes.extend_from_slice(&name.bits().to_le_bytes());
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum UnsupportedReason {
    MissingDeclaration,
    NotConst,
    OpaqueInheritedMetadata,
    MissingInitializer,
    RuntimeOrUnsupportedExpression,
    BackendInterpretation,
    UnknownType,
}
impl UnsupportedReason {
    fn tag(self) -> u8 {
        match self {
            Self::MissingDeclaration => 0,
            Self::NotConst => 1,
            Self::OpaqueInheritedMetadata => 2,
            Self::MissingInitializer => 3,
            Self::RuntimeOrUnsupportedExpression => 4,
            Self::BackendInterpretation => 5,
            Self::UnknownType => 6,
        }
    }
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ScalarOutcome {
    Value(SemanticValue),
    Unsupported(UnsupportedReason),
    RejectedPureCall(PureCallError),
    /// Actual dependency-cycle traversal, rotated to its lowest structural key.
    Cycle(Arc<[ScalarQuery]>),
}

pub struct ScalarBackend<'a> {
    /// Caller-pinned decoder/nameof policy identity, mandatory for cache identity.
    pub identity: u128,
    pub decode_string: &'a dyn Fn(&str) -> Option<Vec<u8>>,
    pub nameof: &'a dyn Fn(&Expr) -> Option<String>,
}

#[derive(Clone, Debug)]
pub struct ScalarSnapshot {
    issued_domain: ScalarDomain,

    pub source: TreeSnapshot,
    pub identity: u128,
    pub backend_identity: u128,
    pub requested: Arc<[ScalarQuery]>,
    pub outcomes: Arc<BTreeMap<ScalarQuery, ScalarOutcome>>,
    pub dependencies: Arc<BTreeMap<ScalarQuery, Arc<[ScalarQuery]>>>,
    /// Separate engine-domain reads: a missing source declaration can resolve
    /// a predefined constant, but a nonconstant source declaration shadows it.
    pub predefined_reads: Arc<BTreeMap<SymbolId, PredefinedOutcome>>,
}
#[derive(Clone, Debug)]
struct ScalarDomain {
    certificates: Arc<BTreeMap<ScalarQuery, u64>>,
    source: Arc<crate::SemanticTree>,
    outcomes: Arc<BTreeMap<ScalarQuery, ScalarOutcome>>,
    identity: u128,
    backend: u128,
    version: u128,
    requested: Arc<[ScalarQuery]>,
    dependencies: Arc<BTreeMap<ScalarQuery, Arc<[ScalarQuery]>>>,
    predefined_reads: Arc<BTreeMap<SymbolId, PredefinedOutcome>>,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum PredefinedOutcome {
    Value(SemanticValue),
    Missing,
    Unsupported,
}
#[path = "constant_resolution_retained.rs"]
mod retained;
pub use retained::ScalarFacts;

impl ScalarSnapshot {
    /// Borrow the issued process-local certificate roster for owner accounting.
    pub fn certificates(&self) -> &Arc<BTreeMap<ScalarQuery, u64>> {
        &self.issued_domain.certificates
    }
    pub fn outcome(&self, query: ScalarQuery) -> Option<&ScalarOutcome> {
        self.outcomes.get(&query)
    }
}

#[path = "constant_resolution_pass.rs"]
mod pass;
use pass::{Memo, Pass};
#[path = "constant_resolution_artifacts.rs"]
mod artifacts;
pub use artifacts::{ScalarArtifact, ScalarArtifacts, ScalarReadAnswer, ScalarReadQuery};

/// Only selected declarations and transitively reached consts are evaluated.
/// Unsupported/cyclic outcomes are data, not user syntax diagnostics.
pub fn resolve(
    snapshot: &TreeSnapshot,
    requests: &[ScalarQuery],
    backend: &ScalarBackend<'_>,
) -> ScalarSnapshot {
    resolve_with_predefined(snapshot, requests, backend, None)
}

/// `backend.identity` must bind the captured predefined catalog as well as
/// string/nameof rules. Engine reads remain separate from source dependency edges.
pub fn resolve_with_predefined(
    snapshot: &TreeSnapshot,
    requests: &[ScalarQuery],
    backend: &ScalarBackend<'_>,
    predefined: Option<&dyn Resolver>,
) -> ScalarSnapshot {
    resolve_with_predefined_and_calls(snapshot, requests, backend, predefined, None)
}
/// Pure-call policy identity is framed into the snapshot independently of decoder identity.
pub fn resolve_with_predefined_and_calls(
    snapshot: &TreeSnapshot,
    requests: &[ScalarQuery],
    backend: &ScalarBackend<'_>,
    predefined: Option<&dyn Resolver>,
    calls: Option<&dyn PureCalls>,
) -> ScalarSnapshot {
    resolve_with_artifacts(snapshot, requests, backend, predefined, calls, None)
}

/// Retention requires an artifact provider that certifies the concrete immutable
/// decoder/nameof function pair. Opaque closure backends use the ordinary API.
#[allow(clippy::too_many_arguments)]
pub fn resolve_pinned_with_artifacts(
    snapshot: &TreeSnapshot,
    requests: &[ScalarQuery],
    identity: u128,
    decode: fn(&str) -> Option<Vec<u8>>,
    nameof: fn(&Expr) -> Option<String>,
    predefined: Option<&dyn Resolver>,
    calls: Option<&dyn PureCalls>,
    artifacts: Option<&dyn ScalarArtifacts>,
) -> ScalarSnapshot {
    let artifacts = artifacts.filter(|owner| owner.accept_policy(decode, nameof));
    resolve_with_artifacts(
        snapshot,
        requests,
        &ScalarBackend {
            identity,
            decode_string: &decode,
            nameof: &nameof,
        },
        predefined,
        calls,
        artifacts,
    )
}

/// Explicit retained evaluator boundary. The artifact provider must bind the exact
/// decoder, nameof and engine owners; ordinary/custom backend APIs never opt in.
fn resolve_with_artifacts(
    snapshot: &TreeSnapshot,
    requests: &[ScalarQuery],
    backend: &ScalarBackend<'_>,
    predefined: Option<&dyn Resolver>,
    calls: Option<&dyn PureCalls>,
    artifacts: Option<&dyn ScalarArtifacts>,
) -> ScalarSnapshot {
    let artifacts =
        artifacts.filter(|_| calls.is_none_or(|calls| calls.immutable_policy_identity().is_some()));
    let mut policy = backend.identity.to_le_bytes().to_vec();
    policy.push(u8::from(calls.is_some()));
    if let Some(calls) = calls {
        policy.extend_from_slice(&calls.identity().to_le_bytes());
    }
    let backend_identity = xxhash_rust::xxh3::xxh3_128(&policy);
    let requested = requests.iter().copied().collect::<BTreeSet<_>>();
    let pass = Pass {
        tree: &snapshot.tree,
        backend,
        memo: RefCell::new(Memo::default()),
        predefined,
        calls,
        artifacts,
    };
    for query in &requested {
        pass.query(*query);
    }
    let memo = pass.memo.into_inner();
    if let Some(artifacts) = artifacts {
        artifacts.finish(
            &memo
                .values
                .keys()
                .filter(|query| !memo.cyclic.contains(query))
                .copied()
                .collect::<Vec<_>>(),
        );
    }
    let dependencies: BTreeMap<_, Arc<[ScalarQuery]>> = memo
        .edges
        .into_iter()
        .map(|(query, edges)| (query, edges.into_iter().collect::<Vec<_>>().into()))
        .collect();
    let mut bytes = b"dm-scalar-overlay-v3\0".to_vec();
    bytes.extend_from_slice(&snapshot.tree.identity().to_le_bytes());
    bytes.extend_from_slice(&backend.identity.to_le_bytes());
    bytes.push(u8::from(calls.is_some()));
    if let Some(calls) = calls {
        bytes.extend_from_slice(&calls.identity().to_le_bytes());
    }
    bytes.extend_from_slice(&(requested.len() as u64).to_le_bytes());
    for query in &requested {
        query.encode(&mut bytes);
    }
    for (query, outcome) in &memo.values {
        query.encode(&mut bytes);
        match outcome {
            ScalarOutcome::Value(value) => {
                bytes.push(0);
                let value = value.canonical_bytes();
                bytes.extend_from_slice(&(value.len() as u64).to_le_bytes());
                bytes.extend_from_slice(&value);
            }
            ScalarOutcome::Unsupported(reason) => {
                bytes.push(1);
                bytes.push(reason.tag());
            }
            ScalarOutcome::RejectedPureCall(error) => {
                bytes.push(3);
                for text in [&error.name, &error.reason] {
                    bytes.extend_from_slice(&(text.len() as u64).to_le_bytes());
                    bytes.extend_from_slice(text.as_bytes());
                }
            }
            ScalarOutcome::Cycle(cycle) => {
                bytes.push(2);
                bytes.extend_from_slice(&(cycle.len() as u64).to_le_bytes());
                for query in cycle.iter() {
                    query.encode(&mut bytes);
                }
            }
        }
        let edges = dependencies
            .get(query)
            .map_or(&[][..], |edges| edges.as_ref());
        bytes.extend_from_slice(&(edges.len() as u64).to_le_bytes());
        for dependency in edges {
            dependency.encode(&mut bytes);
        }
    }
    bytes.push(255);
    bytes.extend_from_slice(&(memo.predefined.len() as u64).to_le_bytes());
    for (name, outcome) in &memo.predefined {
        bytes.extend_from_slice(&name.bits().to_le_bytes());
        match outcome {
            PredefinedOutcome::Value(value) => {
                bytes.push(0);
                let value = value.canonical_bytes();
                bytes.extend_from_slice(&(value.len() as u64).to_le_bytes());
                bytes.extend_from_slice(&value);
            }
            PredefinedOutcome::Missing => bytes.push(1),
            PredefinedOutcome::Unsupported => bytes.push(2),
        }
    }
    let identity = xxhash_rust::xxh3::xxh3_128(&bytes);
    let outcomes = Arc::new(memo.values);
    let mut domain_hash = xxhash_rust::xxh3::Xxh3::new();
    domain_hash.update(b"dm-scalar-answer-domain-v1\0");
    domain_hash.update(&identity.to_le_bytes());
    domain_hash.update(&backend_identity.to_le_bytes());
    let requested: Arc<[ScalarQuery]> = requested.into_iter().collect::<Vec<_>>().into();
    let dependencies = Arc::new(dependencies);
    let predefined_reads = Arc::new(memo.predefined);
    ScalarSnapshot {
        issued_domain: ScalarDomain {
            certificates: Arc::new(
                memo.certificates
                    .into_iter()
                    .filter(|(query, _)| !memo.cyclic.contains(query))
                    .collect(),
            ),
            source: Arc::clone(&snapshot.tree),
            outcomes: Arc::clone(&outcomes),
            identity,
            backend: backend_identity,
            version: domain_hash.digest128(),
            requested: Arc::clone(&requested),
            dependencies: Arc::clone(&dependencies),
            predefined_reads: Arc::clone(&predefined_reads),
        },
        source: snapshot.clone(),
        identity,
        backend_identity,
        requested,
        outcomes,
        dependencies,
        predefined_reads,
    }
}

impl ScalarSnapshot {
    fn original_domain(&self) -> bool {
        let issued = &self.issued_domain;
        Arc::ptr_eq(&issued.source, &self.source.tree)
            && Arc::ptr_eq(&issued.outcomes, &self.outcomes)
            && Arc::ptr_eq(&issued.requested, &self.requested)
            && Arc::ptr_eq(&issued.dependencies, &self.dependencies)
            && Arc::ptr_eq(&issued.predefined_reads, &self.predefined_reads)
            && issued.identity == self.identity
            && issued.backend == self.backend_identity
    }
    /// A non-constant variable's scalar answer is the source tree's own member
    /// answer (`resolve` delegates it unchanged). Its owner-variable demand token
    /// certifies the declaring chain, selection and metadata; the member content
    /// is the only other input of that answer's fingerprint, so it is hashed in.
    /// The top bit keeps these disjoint from issued constant certificates.
    pub(crate) fn source_variable_certificate(
        tree: &crate::SemanticTree,
        owner: SymbolId,
        name: SymbolId,
        member: &crate::MemberNode,
    ) -> Option<u64> {
        let token = Resolver::domain_version(
            tree,
            dm_ir::ReadDomain::OwnerVariable(ResolveQuery::HasMemberVar { owner, name }),
        )?;
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        hash.update(b"dm-scalar-source-variable-v1\0");
        hash.update(&token.to_le_bytes());
        hash.update(&member.content.to_le_bytes());
        hash.update(&crate::metadata_fingerprint(&member.metadata).to_le_bytes());
        Some(hash.digest() | (1 << 63))
    }
    fn scalar_certificate(&self, query: ResolveQuery) -> Option<u64> {
        if !self.original_domain() {
            return None;
        }
        let (owner, name) = match query {
            ResolveQuery::Constant { owner, name } | ResolveQuery::Var { owner, name } => {
                (owner, name)
            }
            ResolveQuery::GlobalVar(name) => (SymbolId::of("/"), name),
            _ => return None,
        };
        let tree = &self.source.tree;
        let member =
            tree.member(tree.resolve(tree.lookup_type(owner)?, name, MemberKind::Var)?)?;
        if member.metadata.inherited_opaque.is_some() {
            return None;
        }
        if member.metadata.flags & 2 == 0 {
            return Self::source_variable_certificate(tree, owner, name, member);
        }
        let actual_owner = tree.type_node(member.owner)?.path;
        let requested = ScalarQuery::Const { owner, name };
        let actual = ScalarQuery::Const {
            owner: actual_owner,
            name,
        };
        // Match the same first-present selection used by resolve, including an
        // unsupported requested outcome that must not fall through to an ancestor.
        let selected = if self.outcomes.contains_key(&requested) {
            requested
        } else {
            actual
        };
        if !matches!(self.outcomes.get(&selected), Some(ScalarOutcome::Value(_))) {
            return None;
        }
        self.issued_domain.certificates.get(&selected).copied()
    }
}

impl Resolver for ScalarSnapshot {
    fn observes_reads(&self) -> bool {
        false
    }

    fn domain_version(&self, domain: dm_ir::ReadDomain) -> Option<u128> {
        if let dm_ir::ReadDomain::OwnerScalar(query) = domain {
            return self.scalar_certificate(query).map(u128::from);
        }
        if matches!(
            domain,
            dm_ir::ReadDomain::OwnerHierarchy(_)
                | dm_ir::ReadDomain::OwnerCallable(_)
                | dm_ir::ReadDomain::OwnerVariable(_)
        ) {
            // Scalar enrichment only changes Var/Constant/GlobalVar, never
            // Type/Parent/Ancestry or callable queries. Bind to the CURRENT source tree certificate.
            return self.source.tree.domain_version(domain);
        }
        if domain != dm_ir::ReadDomain::Tree {
            return self.source.tree.domain_version(domain);
        }
        let issued = &self.issued_domain;
        // Public analysis projections can be replaced. Only the originally
        // issued immutable tables retain authority for replay shortcuts.
        if self.original_domain() {
            Some(issued.version)
        } else {
            None
        }
    }

    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        let (owner, name, constant_query) = match query {
            ResolveQuery::Constant { owner, name } => (owner, name, true),
            ResolveQuery::Var { owner, name } => (owner, name, false),
            ResolveQuery::GlobalVar(name) => (SymbolId::of("/"), name, false),
            _ => return Resolver::resolve(self.source.tree.as_ref(), query),
        };
        let tree = &self.source.tree;
        let Some(id) = tree
            .lookup_type(owner)
            .and_then(|id| tree.resolve(id, name, MemberKind::Var))
        else {
            return ResolvedMeaning::Unsupported(query);
        };
        let member = tree.member(id).expect("resolved member belongs to tree");
        if member.metadata.inherited_opaque.is_some() {
            return ResolvedMeaning::Unsupported(query);
        }
        if !constant_query && member.metadata.flags & 2 == 0 {
            return Resolver::resolve(tree.as_ref(), query);
        }
        let actual_owner = tree
            .type_node(member.owner)
            .expect("member owner belongs to tree")
            .path;
        let value = self
            .outcome(ScalarQuery::Const { owner, name })
            .or_else(|| {
                self.outcome(ScalarQuery::Const {
                    owner: actual_owner,
                    name,
                })
            });
        let Some(ScalarOutcome::Value(value)) = value else {
            return ResolvedMeaning::Unsupported(query);
        };
        let mut data = member.metadata.as_ref().clone();
        data.resolved_constant = Some(value.clone());
        let mut bytes = b"dm-scalar-member-v1\0".to_vec();
        bytes.extend_from_slice(&member.content.to_le_bytes());
        bytes.extend_from_slice(&crate::metadata_fingerprint(&data).to_le_bytes());
        bytes.extend_from_slice(&self.backend_identity.to_le_bytes());
        ResolvedMeaning::Member {
            owner: actual_owner,
            name,
            fingerprint: xxhash_rust::xxh3::xxh3_128(&bytes),
            data: Arc::new(data),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::{FileId, SymbolTable};
    #[test]
    fn scalar_domain_rejects_replaced_public_outcomes() {
        let source = snapshot("/datum/x\n    var/const/value = 1\n");
        let mut resolved = resolve(
            &source,
            &[],
            &ScalarBackend {
                identity: 1,
                decode_string: &|text| Some(text.as_bytes().to_vec()),
                nameof: &|_| None,
            },
        );
        assert!(resolved.domain_version(dm_ir::ReadDomain::Tree).is_some());
        resolved.outcomes = Arc::new(BTreeMap::new());
        assert_eq!(resolved.domain_version(dm_ir::ReadDomain::Tree), None);
    }
    pub(super) fn snapshot(source: &str) -> TreeSnapshot {
        crate::from_ast(
            &dm_syntax::parse(source),
            SymbolTable::default(),
            FileId(0),
            0,
            0,
        )
        .unwrap()
        .finish()
        .unwrap()
    }
    fn query(owner: &str, name: &str) -> ScalarQuery {
        ScalarQuery::Const {
            owner: SymbolId::of(owner),
            name: SymbolId::of(name),
        }
    }
    fn number(value: f32) -> ScalarOutcome {
        ScalarOutcome::Value(SemanticValue::NumberBits(value.to_bits()))
    }
    pub(super) fn backend_disabled() -> ScalarBackend<'static> {
        ScalarBackend {
            identity: 1,
            decode_string: &|_| None,
            nameof: &|_| None,
        }
    }
    #[test]
    fn pure_call_rejections_and_policy_are_retained_in_scalar_snapshot() {
        struct Calls(u128);
        impl PureCalls for Calls {
            fn identity(&self) -> u128 {
                self.0
            }
            fn accepts(&self, name: &str) -> bool {
                name == "pure"
            }
            fn evaluate(
                &self,
                name: &str,
                arguments: &[Option<Constant>],
            ) -> Result<Constant, PureCallError> {
                match arguments {
                    [Some(value)] => Ok(value.clone()),
                    _ => Err(PureCallError {
                        name: name.into(),
                        reason: "constant argument required".into(),
                    }),
                }
            }
        }
        let source = snapshot("var/const/a = pure(7)\nvar/const/b = pure(runtime())\nvar/const/c = pure(d)\nvar/const/d = c\n");
        let requests = [query("/", "a"), query("/", "b")];
        let first = resolve_with_predefined_and_calls(
            &source,
            &requests,
            &backend_disabled(),
            None,
            Some(&Calls(1)),
        );
        assert_eq!(first.outcome(requests[0]), Some(&number(7.0)));
        assert!(
            matches!(first.outcome(requests[1]), Some(ScalarOutcome::RejectedPureCall(error)) if error.name == "pure")
        );
        let second = resolve_with_predefined_and_calls(
            &source,
            &requests,
            &backend_disabled(),
            None,
            Some(&Calls(2)),
        );
        assert_ne!(first.identity, second.identity);
        assert_ne!(first.backend_identity, second.backend_identity);
        let cycle = resolve_with_predefined_and_calls(
            &source,
            &[query("/", "c")],
            &backend_disabled(),
            None,
            Some(&Calls(1)),
        );
        assert!(matches!(
            cycle.outcome(query("/", "c")),
            Some(ScalarOutcome::Cycle(_))
        ));
        let legacy = resolve(&source, &requests, &backend_disabled());
        assert!(matches!(
            legacy.outcome(requests[0]),
            Some(ScalarOutcome::Unsupported(_))
        ));
    }
    #[test]
    fn predefined_reads_are_recorded_separately_and_source_names_shadow_them() {
        struct Engine;
        impl Resolver for Engine {
            fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
                match query {
                    ResolveQuery::PredefinedConstant(name)
                        if name == SymbolId::of("ENGINE_VALUE") =>
                    {
                        ResolvedMeaning::Value(SemanticValue::NumberBits(7.0f32.to_bits()))
                    }
                    _ => ResolvedMeaning::Missing,
                }
            }
        }
        let source = snapshot("/datum/probe\n    var/const/a = ENGINE_VALUE + 1\n");
        let a = query("/datum/probe", "a");
        let result = resolve_with_predefined(&source, &[a], &backend_disabled(), Some(&Engine));
        assert_eq!(result.outcome(a), Some(&number(8.0)));
        assert_eq!(
            result.predefined_reads.get(&SymbolId::of("ENGINE_VALUE")),
            Some(&PredefinedOutcome::Value(SemanticValue::NumberBits(
                7.0f32.to_bits()
            )))
        );
        assert!(result.dependencies[&a]
            .iter()
            .any(|dependency| *dependency == query("/", "ENGINE_VALUE")));
        let source = snapshot(
            "/datum/probe\n    var/ENGINE_VALUE = 4\n    var/const/a = ENGINE_VALUE + 1\n",
        );
        let result = resolve_with_predefined(&source, &[a], &backend_disabled(), Some(&Engine));
        assert_eq!(
            result.outcome(a),
            Some(&ScalarOutcome::Unsupported(UnsupportedReason::NotConst))
        );
        assert!(result.predefined_reads.is_empty());
    }
    #[test]
    fn forward_const_dependencies_and_short_circuit_are_demand_driven() {
        let source=snapshot("/datum/probe\n    var/const/a = b * 2 + 1\n    var/const/b = 5\n    var/const/unused = list(1)\n    var/const/short = 1 || a_cycle\n    var/const/a_cycle = a_cycle\n");
        let a = query("/datum/probe", "a");
        let short = query("/datum/probe", "short");
        let result = resolve(&source, &[a, short], &backend_disabled());
        assert_eq!(result.outcome(a), Some(&number(11.0)));
        assert_eq!(result.outcome(short), Some(&number(1.0)));
        assert_eq!(result.outcomes.len(), 3);
        assert!(!result
            .outcomes
            .contains_key(&query("/datum/probe", "unused")));
        assert!(!result
            .outcomes
            .contains_key(&query("/datum/probe", "a_cycle")));
        assert_eq!(
            result.dependencies.get(&a).unwrap().as_ref(),
            &[query("/datum/probe", "b")]
        );
        let meaning = Resolver::resolve(
            &result,
            ResolveQuery::Constant {
                owner: SymbolId::of("/datum/probe"),
                name: SymbolId::of("a"),
            },
        );
        assert!(
            matches!(meaning,ResolvedMeaning::Member {data,..} if data.resolved_constant==Some(SemanticValue::NumberBits(11.0f32.to_bits())))
        );
        assert_eq!(
            source
                .tree
                .member(
                    source
                        .tree
                        .resolve(
                            source
                                .tree
                                .lookup_type(SymbolId::of("/datum/probe"))
                                .unwrap(),
                            SymbolId::of("a"),
                            MemberKind::Var
                        )
                        .unwrap()
                )
                .unwrap()
                .metadata
                .resolved_constant,
            None
        );
    }
    #[test]
    fn cycles_and_unsupported_values_are_not_null_or_missing() {
        let source=snapshot("/datum/probe\n    var/const/a = b\n    var/const/b = a\n    var/const/items = list(1,2)\n    var/const/asset = 'asset.txt'\n    var/const/runtime = rand(1,2)\n    var/const/none = null\n");
        let a = query("/datum/probe", "a");
        let b = query("/datum/probe", "b");
        let result = resolve(
            &source,
            &[
                a,
                b,
                query("/datum/probe", "items"),
                query("/datum/probe", "asset"),
                query("/datum/probe", "runtime"),
                query("/datum/probe", "none"),
            ],
            &backend_disabled(),
        );
        assert!(matches!(result.outcome(a),Some(ScalarOutcome::Cycle(cycle)) if cycle.len()==2));
        assert_eq!(result.outcome(a), result.outcome(b));
        for name in ["items", "asset", "runtime"] {
            assert!(matches!(
                result.outcome(query("/datum/probe", name)),
                Some(ScalarOutcome::Unsupported(_))
            ));
        }
        assert_eq!(
            result.outcome(query("/datum/probe", "none")),
            Some(&ScalarOutcome::Value(SemanticValue::Null))
        );
        let reordered = resolve(
            &source,
            &[
                b,
                a,
                query("/datum/probe", "none"),
                query("/datum/probe", "runtime"),
                query("/datum/probe", "asset"),
                query("/datum/probe", "items"),
            ],
            &backend_disabled(),
        );
        assert_eq!(result.identity, reordered.identity);
    }
    #[test]
    fn declaration_default_keeps_formal_lexical_scope_apart_from_class_assignment() {
        let source=snapshot("/datum/base\n    var/const/seed = 2\n    var/value = seed + 1\n/datum/base/child\n    seed = 20\n    value = seed + 4\n");
        let owner = SymbolId::of("/datum/base/child");
        let name = SymbolId::of("value");
        let declared = ScalarQuery::DeclaredDefault { owner, name };
        let effective = ScalarQuery::EffectiveDefault { owner, name };
        let result = resolve(&source, &[declared, effective], &backend_disabled());
        assert_eq!(result.outcome(declared), Some(&number(3.0)));
        assert_eq!(result.outcome(effective), Some(&number(24.0)));
    }
    #[test]
    fn backend_policy_is_explicit_and_exact_bytes_qualify_overlay_identity() {
        let source = snapshot(
            "/datum/probe\n    var/const/text = \"value\"\n    var/const/named = nameof(text)\n",
        );
        let decoder = |_: &str| Some(vec![0xff, 0x80]);
        let nameof = |_: &Expr| Some("chosen".into());
        let backend = ScalarBackend {
            identity: 123,
            decode_string: &decoder,
            nameof: &nameof,
        };
        let text = query("/datum/probe", "text");
        let named = query("/datum/probe", "named");
        let result = resolve(&source, &[text, named], &backend);
        assert_eq!(
            result.outcome(text),
            Some(&ScalarOutcome::Value(SemanticValue::Text(Arc::from([
                0xff, 0x80
            ]))))
        );
        assert_eq!(
            result.outcome(named),
            Some(&ScalarOutcome::Value(SemanticValue::Text(Arc::from(
                b"chosen".as_slice()
            ))))
        );
        let changed_backend = ScalarBackend {
            identity: 124,
            decode_string: &decoder,
            nameof: &nameof,
        };
        assert_ne!(
            result.identity,
            resolve(&source, &[text, named], &changed_backend).identity
        );
        assert!(matches!(
            resolve(&source, &[text], &backend_disabled()).outcome(text),
            Some(ScalarOutcome::Unsupported(
                UnsupportedReason::BackendInterpretation
            ))
        ));
    }
    #[test]
    fn opaque_inherited_defaults_are_unsupported_but_authored_effective_expression_is_exact() {
        let source = "/datum/probe\n    value = 9\n";
        let mut symbols = SymbolTable::default();
        for name in ["/datum/probe", "value"] {
            symbols.intern(name).unwrap();
        }
        let adapted = crate::from_ast(&dm_syntax::parse(source), symbols, FileId(0), 0, 0).unwrap();
        let fields = vec![dm_ir::OpaqueFieldBase {
            owner: SymbolId::of("/datum/probe"),
            name: SymbolId::of("value"),
            declared_type: dm_ir::DeclaredTypeKnowledge::Unsupported,
        }];
        let tree = crate::build_with_intrinsic_fields(adapted.symbols, &adapted.skeletons, &fields)
            .unwrap();
        let occurrences = crate::OccurrenceTable::build(&tree, adapted.origins).unwrap();
        let source = TreeSnapshot {
            tree: Arc::new(tree),
            occurrences: Arc::new(occurrences),
        };
        let owner = SymbolId::of("/datum/probe");
        let name = SymbolId::of("value");
        let declared = ScalarQuery::DeclaredDefault { owner, name };
        let effective = ScalarQuery::EffectiveDefault { owner, name };
        let result = resolve(&source, &[declared, effective], &backend_disabled());
        assert_eq!(
            result.outcome(declared),
            Some(&ScalarOutcome::Unsupported(
                UnsupportedReason::OpaqueInheritedMetadata
            ))
        );
        assert_eq!(result.outcome(effective), Some(&number(9.0)));
        let query = ResolveQuery::Var { owner, name };
        assert_eq!(
            Resolver::resolve(&result, query),
            ResolvedMeaning::Unsupported(query)
        );
    }
    #[test]
    fn lexical_type_constants_preserve_declaring_owner_and_root_null() {
        let source = snapshot("/var/const/root_type = __TYPE__\n/datum/base\n    var/value = __TYPE__\n    var/const/type_constant = __TYPE__\n/datum/base/child\n    value = __TYPE__\n");
        let owner = SymbolId::of("/datum/base/child");
        let declared = ScalarQuery::DeclaredDefault {
            owner,
            name: SymbolId::of("value"),
        };
        let effective = ScalarQuery::EffectiveDefault {
            owner,
            name: SymbolId::of("value"),
        };
        let inherited = query("/datum/base/child", "type_constant");
        let root = query("/", "root_type");
        let result = resolve(
            &source,
            &[declared, effective, inherited, root],
            &backend_disabled(),
        );
        let base = ScalarOutcome::Value(SemanticValue::Type(SymbolId::of("/datum/base")));
        let child = ScalarOutcome::Value(SemanticValue::Type(owner));
        assert_eq!(result.outcome(declared), Some(&base));
        assert_eq!(result.outcome(effective), Some(&child));
        assert_eq!(result.outcome(inherited), Some(&base));
        assert_eq!(
            result.outcome(root),
            Some(&ScalarOutcome::Value(SemanticValue::Null))
        );
    }
    #[test]
    fn authored_type_identifier_shadows_intrinsic_without_fabricated_constant() {
        let source = snapshot("/var/const/__TYPE__ = 7\n/datum/global_shadow\n    var/const/value = __TYPE__\n/datum/local_shadow\n    var/const/__TYPE__ = 9\n    var/const/value = __TYPE__\n/datum/runtime_shadow\n    var/__TYPE__ = 11\n    var/const/value = __TYPE__\n");
        let global = query("/datum/global_shadow", "value");
        let local = query("/datum/local_shadow", "value");
        let runtime = query("/datum/runtime_shadow", "value");
        let result = resolve(&source, &[global, local, runtime], &backend_disabled());
        assert_eq!(result.outcome(global), Some(&number(7.0)));
        assert_eq!(result.outcome(local), Some(&number(9.0)));
        assert_eq!(
            result.outcome(runtime),
            Some(&ScalarOutcome::Unsupported(UnsupportedReason::NotConst))
        );
    }
}

#[cfg(test)]
#[path = "constant_resolution_artifact_tests.rs"]
mod artifact_tests;
