//! ABI producer inputs and semantic reads share one generic observation ledger.
use super::*;
#[derive(Clone, Eq, PartialEq, Ord, PartialOrd)]
pub(crate) enum Query {
    Inputs,
    BatchInputs,
    Semantic(ResolveQuery),
}
#[derive(Clone, Eq, PartialEq, Ord, PartialOrd)]
pub(crate) enum Domain {
    Inputs,
    BatchInputs,
    Semantic(ReadDomain),
}
#[derive(Clone)]
pub(crate) enum Answer {
    /// Request-wide semantic host cannot authorize per-unit Inputs.
    Unissued,
    Inputs(Arc<Inputs>),
    BatchInputs(Arc<super::batch::Inputs>),
    Semantic(ResolvedMeaning),
}
impl PartialEq for Answer {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Unissued, Self::Unissued) => true,
            (Self::BatchInputs(a), Self::BatchInputs(b)) => Arc::ptr_eq(a, b) || a == b,
            (Self::Inputs(a), Self::Inputs(b)) => Arc::ptr_eq(a, b) || a == b,
            (Self::Semantic(a), Self::Semantic(b)) => a == b,
            _ => false,
        }
    }
}
impl Eq for Answer {}
#[derive(Clone)]
pub(crate) struct Inputs {
    pub(crate) metadata: Arc<dm_ir::ProcedureMetadata>,
    pub(crate) predecessor: Option<Arc<PreparedAbi>>,
    pub(crate) engine: Arc<crate::runner_host::EnginePayload>,
    pub(crate) boundary: Boundary,
    pub(crate) resource: Option<u128>,
    pub(crate) evaluation_resource: Option<u128>,
    pub(crate) lexical: bool,
    pub(crate) pure_policy: Option<u128>,
}
#[derive(Clone, Eq, PartialEq)]
pub(crate) enum Boundary {
    Absent,
    Fresh,
    Engine {
        owner: SymbolId,
        name: SymbolId,
        kind: MemberKind,
    },
    Intrinsic {
        engine_identity: u128,
        owner: SymbolId,
        name: SymbolId,
        layout: ProcLayout,
    },
}
impl Boundary {
    pub(in crate::driver_facts) fn capture(boundary: Option<&BoundaryAbi>) -> Self {
        match boundary {
            None => Self::Absent,
            Some(BoundaryAbi::Fresh) => Self::Fresh,
            Some(BoundaryAbi::Engine { owner, name, kind }) => Self::Engine {
                owner: *owner,
                name: *name,
                kind: *kind,
            },
            Some(BoundaryAbi::CertifiedIntrinsic(r)) => Self::Intrinsic {
                engine_identity: r.engine_identity,
                owner: r.owner,
                name: r.name,
                layout: r.layout.clone(),
            },
        }
    }
}
impl PartialEq for Inputs {
    fn eq(&self, b: &Self) -> bool {
        Arc::ptr_eq(&self.engine, &b.engine)
            && (Arc::ptr_eq(&self.metadata, &b.metadata)
                || self.metadata == b.metadata
                || self.metadata.canonical_bytes() == b.metadata.canonical_bytes())
            && match (&self.predecessor, &b.predecessor) {
                (None, None) => true,
                (Some(a), Some(b)) => Arc::ptr_eq(a, b) || a == b,
                _ => false,
            }
            && self.boundary == b.boundary
            && self.resource == b.resource
            && self.evaluation_resource == b.evaluation_resource
            && self.lexical == b.lexical
            && self.pure_policy == b.pure_policy
    }
}
impl Eq for Inputs {}
pub(in crate::driver_facts) struct Current<'a> {
    pub inputs: Arc<Inputs>,
    pub resolver: &'a dyn Resolver,
}
impl dm_session::ObservationHost<Query, Answer, Domain> for Current<'_> {
    fn answer(&self, query: &Query) -> Answer {
        match query {
            Query::Inputs => Answer::Inputs(Arc::clone(&self.inputs)),
            Query::BatchInputs => Answer::Unissued,
            Query::Semantic(query) => Answer::Semantic(self.resolver.resolve(*query)),
        }
    }
    fn version(&self, domain: &Domain) -> Option<u128> {
        match domain {
            Domain::Inputs | Domain::BatchInputs => None,
            Domain::Semantic(domain) => self.resolver.domain_version(*domain),
        }
    }
    fn equivalent(&self, a: &Answer, b: &Answer) -> bool {
        a == b
            || match (a, b) {
                (Answer::Semantic(a), Answer::Semantic(b)) => {
                    a.canonical_bytes() == b.canonical_bytes()
                }
                _ => false,
            }
    }
}
pub(super) fn reads(
    inputs: Arc<Inputs>,
    reads: Vec<dm_session::ResolverRead>,
) -> Vec<dm_session::Observation<Query, Answer, Domain>> {
    // Inputs sorts before Semantic; the sole existing recorder already canonicalizes
    // semantic queries and preserves conflicting answers. No second evaluator runs.
    let mut out = Vec::with_capacity(reads.len() + 1);
    out.push(dm_session::Observation {
        query: Query::Inputs,
        domain: Domain::Inputs,
        answer: Answer::Inputs(inputs),
    });
    out.extend(reads.into_iter().map(|read| dm_session::Observation {
        query: Query::Semantic(read.query),
        domain: Domain::Semantic(read.domain),
        answer: Answer::Semantic(read.answer),
    }));
    out
}
pub(in crate::driver_facts) fn locator(identity: UnitIdentity) -> Arc<[u8]> {
    let mut out = b"dm-process-abi-unit-v3\0".to_vec();
    out.extend_from_slice(&identity.owner.bits().to_le_bytes());
    out.extend_from_slice(&identity.name.bits().to_le_bytes());
    out.push(u8::from(identity.namespace == Namespace::Verb));
    out.extend_from_slice(&identity.occurrence.to_le_bytes());
    out.into()
}
