//! Exact symbolic inputs and shared ordering payloads; no current spans/tree IDs.
use super::*;
pub(crate) const ALLOCATION_KEY: &[u8] =
    b"dmbc-startup-allocation-v4-forward-source-registration\0";
pub(crate) const FINAL_KEY: &[u8] =
    b"dmbc-startup-allocation-final-v4-forward-source-registration\0";
pub(crate) fn retained_keys() -> impl Iterator<Item = &'static [u8]> {
    [ALLOCATION_KEY, FINAL_KEY].into_iter()
}
#[derive(Clone, PartialEq, Eq)]
pub(crate) struct AllocationInput {
    pub targets: Vec<InitializerTarget>,
    pub owners: Vec<SymbolId>,
    pub registrations: Vec<dm_tree::allocation_ledger::RootFieldRegistration>,
    // These numbers are semantic encounter positions compared as values, never
    // used to address an old occurrence/member arena.
    pub callables: Vec<(dm_ir::ProcedureIdentity, usize)>,
    /// Digest of the allocation ledger's events (`startup_order_facts::OrderEvents`): the order of the walk.
    pub events: u128,
    /// Per write, the declared type and typed-list element type of a shared variable.
    pub declared: Vec<Option<(Option<SymbolId>, Option<SymbolId>)>>,
}
impl AllocationInput {
    pub(super) fn capture(
        plan: &InitializerPlan,
        owners: &[SymbolId],
        frontend: &dm_tree::frontend::ColdFrontend,
        events: &crate::startup_order_facts::OrderEvents,
    ) -> Result<Self, String> {
        let mut callables = Vec::new();
        for body in frontend.bodies.iter() {
            let member = frontend
                .snapshot
                .tree
                .member(body.member)
                .ok_or("startup callable registration member absent")?;
            if member.kind != dm_tree::MemberKind::Proc {
                continue;
            }
            let owner = frontend
                .snapshot
                .tree
                .type_node(member.owner)
                .ok_or("startup callable registration owner absent")?
                .path;
            let identity = frontend
                .callable_roster()?
                .identity_for_member(body.member)
                .ok_or("startup callable identity absent")?;
            if identity.owner != owner || identity.name != member.name {
                return Err("startup callable identity differs".into());
            }
            callables.push((identity, body.declaration.0 as usize));
        }
        Ok(Self {
            targets: plan
                .writes
                .iter()
                .map(|write| write.target.clone())
                .collect(),
            owners: owners.to_vec(),
            registrations: frontend
                .allocation_ledger
                .root_field_descriptors()
                .map(|(_, row)| row)
                .collect(),
            callables,
            events: events.digest,
            declared: plan
                .writes
                .iter()
                .zip(plan.origins.iter())
                .map(|(write, origin)| match (&write.target, origin.kind) {
                    (
                        InitializerTarget::Shared { .. },
                        dm_tree::initializers::InitializerOriginKind::Declaration(member),
                    ) => plan.source.tree.member(member).map(|member| {
                        (
                            member.metadata.declared_type,
                            member.metadata.list_element_type,
                        )
                    }),
                    _ => None,
                })
                .collect(),
        })
    }
}
pub(crate) struct AllocationReceipt {
    pub input: Option<AllocationInput>,
    // A position in the exact ordered initializer roster, never an arena ID.
    pub bindings: Vec<Option<usize>>,
    pub keys: Vec<Key>,
    pub ranks: BTreeMap<Key, usize>,
    pub registration_owners: BTreeMap<Key, SymbolId>,
    pub source_owners: BTreeMap<SymbolId, usize>,
    pub callable_positions: BTreeMap<(SymbolId, SymbolId), usize>,
    pub first_root_callable: Option<dm_ir::ProcedureIdentity>,
}
impl AllocationReceipt {
    pub(crate) fn bind_current(
        &self,
        plan: &InitializerPlan,
        frontend: &dm_tree::frontend::ColdFrontend,
    ) -> bool {
        if self.bindings.len() != frontend.allocation_ledger.root_field_descriptors().count() {
            return false;
        }
        frontend.allocation_ledger.root_field_descriptors().zip(&self.bindings).all(|((span, descriptor), binding)| {
            let Some(index) = binding else { return descriptor.registration_owner.is_none(); };
            let Some(origin) = plan.origins.get(*index) else { return false; };
            let Some(write) = plan.writes.get(*index) else { return false; };
            let Some(location) = frontend.location(span.start) else { return false; };
            matches!(origin.kind, dm_tree::initializers::InitializerOriginKind::Declaration(_))
                && matches!(write.target, InitializerTarget::Shared { owner, name, .. } if owner == SymbolId::of("/") && name == descriptor.name)
                && origin.provenance.span.file.index() == location.span.file.index()
                && origin.provenance.span.start == location.span.start
                && origin.provenance.include_occurrence as usize == location.include_occurrence
        })
    }
}
pub(crate) struct OrderedRoster {
    pub keys: Vec<Key>,
    pub ranks: BTreeMap<Key, usize>,
    /// The order DreamMaker runs the global initializers in (`startup_order`); empty when the ledger is not at hand.
    pub execution: BTreeMap<Key, usize>,
}
pub(crate) struct FinalInput {
    pub allocation: Arc<AllocationReceipt>,
    pub classifications: Vec<(
        usize,
        usize,
        SymbolId,
        crate::initializer_policy::ClassificationOwner,
    )>,
    /// Digest of every non-instance write's initializer expression: the references that order the walk.
    pub expressions: u128,
}
impl FinalInput {
    pub(super) fn capture(
        allocation: &Arc<AllocationReceipt>,
        plan: &InitializerPlan,
        classified: &crate::initializer_policy::ClassifiedInitializers,
    ) -> Option<Self> {
        allocation.input.as_ref()?;
        let mut classifications = Vec::new();
        for (index, row) in classified.writes.iter().enumerate() {
            if matches!(row.write.target, InitializerTarget::Instance { .. }) {
                continue;
            }
            let origin = plan.origins.get(row.source_ordinal)?;
            let owner = classified.accepted.get(index)?.as_ref()?.clone();
            classifications.push((
                row.source_ordinal,
                origin.encounter_ordinal,
                row.write.lexical_owner,
                owner,
            ));
        }
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        for write in plan.writes.iter() {
            if matches!(write.target, InitializerTarget::Instance { .. }) {
                continue;
            }
            match &write.value {
                dm_ir::InitializerValue::Expression(expression) => {
                    hash.update(&[1]);
                    hash.update(expression.source_text(&plan.symbols)?.as_bytes());
                }
                _ => hash.update(&[0]),
            }
            hash.update(&[0xff]);
        }
        Some(Self {
            allocation: Arc::clone(allocation),
            classifications,
            expressions: hash.digest128(),
        })
    }
    pub(crate) fn matches(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.allocation, &other.allocation)
            && self.classifications == other.classifications
            && self.expressions == other.expressions
    }
}
pub(crate) struct FinalReceipt {
    pub input: FinalInput,
    pub ordered: Arc<OrderedRoster>,
}
