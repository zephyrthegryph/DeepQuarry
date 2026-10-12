//! Current producer-issued startup allocation order. Symbolic IDs identify keys;
//! their numeric values never determine allocation order.
use dm_ir::{InitializerTarget, InitializerWrite, SymbolId};
use dm_link::Key;
use dm_tree::initializers::InitializerPlan;
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::{Arc, OnceLock},
};

#[path = "startup_allocation_receipt.rs"]
mod receipt;
pub(crate) use receipt::{retained_keys, ALLOCATION_KEY, FINAL_KEY};
pub(crate) use receipt::{
    AllocationInput, AllocationReceipt, FinalInput, FinalReceipt, OrderedRoster,
};
pub(crate) struct StartupAllocationRoster {
    writes: Arc<[InitializerWrite]>,
    allocation: Arc<AllocationReceipt>,
    finalized: OnceLock<Arc<OrderedRoster>>,
    artifacts: Option<Arc<crate::startup::StartupArtifacts>>,
}
impl StartupAllocationRoster {
    /// `source_owners` is the existing admitted fresh type allocation roster;
    /// retained engine owners are deliberately absent from this first partition.
    #[cfg(test)]
    pub(crate) fn issue(
        plan: &InitializerPlan,
        source_owners: &[SymbolId],
    ) -> Result<Self, String> {
        Self::issue_with_registrations(plan, source_owners, BTreeMap::new(), BTreeMap::new())
    }
    #[cfg(test)]
    pub(crate) fn issue_current(
        plan: &InitializerPlan,
        source_owners: &[SymbolId],
        frontend: &dm_tree::frontend::ColdFrontend,
    ) -> Result<Self, String> {
        Self::issue_current_with_artifacts(plan, source_owners, frontend, None)
    }
    pub(crate) fn issue_current_with_artifacts(
        plan: &InitializerPlan,
        source_owners: &[SymbolId],
        frontend: &dm_tree::frontend::ColdFrontend,
        artifacts: Option<&Arc<crate::startup::StartupArtifacts>>,
    ) -> Result<Self, String> {
        if !Arc::ptr_eq(&plan.source.tree, &frontend.snapshot.tree) {
            return Err("startup registration belongs to another current tree".into());
        }
        if !Arc::ptr_eq(&plan.source.occurrences, &frontend.snapshot.occurrences) {
            return Err("startup registration belongs to another current source".into());
        }
        let input = AllocationInput::capture(plan, source_owners, frontend)?;
        if let Some(allocation) = artifacts.and_then(|store| {
            store
                .allocation(&input)
                .filter(|receipt| receipt.bind_current(plan, frontend))
        }) {
            return Ok(Self {
                writes: Arc::clone(&plan.writes),
                allocation,
                finalized: OnceLock::new(),
                artifacts: artifacts.cloned(),
            });
        }
        let mut rows = BTreeMap::<_, std::collections::VecDeque<_>>::new();
        for (index, (write, origin)) in plan.writes.iter().zip(plan.origins.iter()).enumerate() {
            if matches!(
                origin.kind,
                dm_tree::initializers::InitializerOriginKind::Declaration(_)
            ) && matches!(write.target, InitializerTarget::Shared { owner, .. } if owner == SymbolId::of("/"))
            {
                rows.entry((
                    origin.provenance.span.file.index(),
                    origin.provenance.span.start,
                    origin.provenance.include_occurrence as usize,
                ))
                .or_default()
                .push_back((index, key(write)?));
            }
        }
        let mut registrations = BTreeMap::new();
        let mut bindings = Vec::new();
        for (span, registration_owner) in frontend.allocation_ledger.root_field_registrations() {
            let location = frontend
                .location(span.start)
                .ok_or("startup registration has no current source location")?;
            let coordinate = (
                location.span.file.index(),
                location.span.start,
                location.include_occurrence,
            );
            // Root instance declarations can have no shared write. Only source
            // rows admitted by the ordinary initializer producer are selected.
            if let Some((index, row)) = rows.get_mut(&coordinate).and_then(|rows| rows.pop_front())
            {
                bindings.push(Some(index));
                if let Some(owner) = registration_owner {
                    registrations.insert(row, owner);
                }
            } else {
                bindings.push(None);
                if registration_owner.is_some() {
                    return Err("late startup registration has no current initializer row".into());
                }
            }
        }
        let mut callable_positions = BTreeMap::new();
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
            callable_positions
                .entry((owner, member.name))
                .or_insert(body.declaration.0 as usize);
        }
        let mut current =
            Self::issue_with_registrations(plan, source_owners, registrations, callable_positions)?;
        let receipt = Arc::get_mut(&mut current.allocation).expect("new allocation owner");
        receipt.input = Some(input);
        receipt.bindings = bindings;
        if let Some(store) = artifacts {
            current.allocation = store.remember_allocation(Arc::clone(&current.allocation));
        }
        current.artifacts = artifacts.cloned();
        Ok(current)
    }
    fn issue_with_registrations(
        plan: &InitializerPlan,
        source_owners: &[SymbolId],
        registrations: BTreeMap<Key, SymbolId>,
        callable_positions: BTreeMap<(SymbolId, SymbolId), usize>,
    ) -> Result<Self, String> {
        let root = SymbolId::of("/");
        let mut owners = BTreeMap::new();
        for (rank, owner) in source_owners.iter().copied().enumerate() {
            if owner == root || owners.insert(owner, rank).is_some() {
                return Err("startup source allocation roster is not unique".into());
            }
        }
        let mut entries = Vec::new();
        let mut seen = BTreeSet::new();
        for (ordinal, write) in plan.writes.iter().enumerate() {
            let (owner, key, shared) = match write.target {
                InitializerTarget::Shared { owner, name, .. } => {
                    (owner, Key::Variable { owner, name }, true)
                }
                InitializerTarget::ProcedureStatic(identity) => (
                    identity.procedure.owner,
                    Key::ProcedureStatic(identity),
                    false,
                ),
                InitializerTarget::Instance { .. } => continue,
            };
            if !seen.insert(key) {
                continue;
            }
            let registration_owner = registrations.get(&key).copied().unwrap_or(owner);
            let group = if let Some(rank) = owners.get(&registration_owner) {
                *rank
            // Pinned observable-order fixture establishes root procedure-static
            // storage before root shared storage, after source-owner storage.
            } else if !shared && registration_owner == root {
                owners.len()
            } else if shared && registration_owner == root {
                owners.len() + 1
            } else {
                owners.len() + 2
            };
            entries.push((group, ordinal, key));
        }
        entries.sort_by_key(|(group, ordinal, _)| (*group, *ordinal));
        let keys: Vec<_> = entries.into_iter().map(|(_, _, key)| key).collect();
        let ranks = keys
            .iter()
            .copied()
            .enumerate()
            .map(|(rank, key)| (key, rank))
            .collect();
        Ok(Self {
            writes: Arc::clone(&plan.writes),
            allocation: Arc::new(AllocationReceipt {
                input: None,
                bindings: Vec::new(),
                keys,
                ranks,
                registration_owners: registrations,
                source_owners: owners,
                callable_positions,
            }),
            finalized: OnceLock::new(),
            artifacts: None,
        })
    }
    fn registration_owner(&self, write: &InitializerWrite) -> Result<SymbolId, String> {
        let entry = key(write)?;
        Ok(self
            .allocation
            .registration_owners
            .get(&entry)
            .copied()
            .unwrap_or(match write.target {
                InitializerTarget::Shared { owner, .. } => owner,
                InitializerTarget::ProcedureStatic(identity) => identity.procedure.owner,
                InitializerTarget::Instance { .. } => {
                    return Err("instance registration owner".into());
                }
            }))
    }
    fn finalize(
        &self,
        plan: &InitializerPlan,
        classified: &crate::initializer_policy::ClassifiedInitializers,
        host: &impl dm_ir::Resolver,
    ) -> Result<&OrderedRoster, String> {
        if let Some(roster) = self.finalized.get() {
            return Ok(roster);
        }
        let final_input = FinalInput::capture(&self.allocation, plan, classified);
        if let Some(input) = final_input.as_ref() {
            if let Some(owner) = self
                .artifacts
                .as_ref()
                .and_then(|store| store.final_allocation(input, host))
            {
                let _ = self.finalized.set(Arc::clone(&owner.ordered));
                return Ok(self.finalized.get().unwrap());
            }
        }
        let recording = crate::lowering_memo::RecordingResolver::new(host);
        let mut eager = BTreeSet::new();
        let mut forward = BTreeSet::new();
        for row in &classified.writes {
            if matches!(row.write.target, InitializerTarget::Instance { .. }) {
                continue;
            }
            let owner = self.registration_owner(&row.write)?;
            if !self.allocation.source_owners.contains_key(&owner) {
                continue;
            }
            let origin = plan
                .origins
                .get(row.source_ordinal)
                .ok_or("classified startup registration ordinal absent")?;
            let ast = match row.runtime_value.as_ref() {
                Some(crate::initializer_policy::RuntimeValue::Expression(ast)) => Some(ast),
                Some(crate::initializer_policy::RuntimeValue::SizedArrayExplicit {
                    expression,
                    ..
                }) => expression.as_ref(),
                _ => None,
            };
            if let Some(ast) = ast {
                let availability = authored_call_availability(
                    ast,
                    row.write.lexical_owner,
                    origin.encounter_ordinal,
                    &self.allocation.callable_positions,
                    &recording,
                );
                if availability.known {
                    eager.insert(owner);
                }
                if availability.forward {
                    forward.insert(owner);
                }
            }
        }
        let count = self.allocation.source_owners.len();
        let mut seen = BTreeSet::new();
        let mut entries = Vec::new();
        for (ordinal, write) in plan.writes.iter().enumerate() {
            if matches!(write.target, InitializerTarget::Instance { .. }) {
                continue;
            }
            let entry = key(write)?;
            if !seen.insert(entry) {
                continue;
            }
            let owner = self.registration_owner(write)?;
            let group = match self.allocation.source_owners.get(&owner) {
                Some(rank)
                    if registration_is_deferred(
                        eager.contains(&owner),
                        forward.contains(&owner),
                    ) =>
                {
                    count + 3 + *rank
                }
                Some(rank) => *rank,
                None if owner == SymbolId::of("/")
                    && matches!(write.target, InitializerTarget::ProcedureStatic(_)) =>
                {
                    count
                }
                None if owner == SymbolId::of("/")
                    && matches!(write.target, InitializerTarget::Shared { .. }) =>
                {
                    count + 1
                }
                None => count + 2,
            };
            entries.push((group, ordinal, entry));
        }
        entries.sort_by_key(|(group, ordinal, _)| (*group, *ordinal));
        let keys: Vec<_> = entries.into_iter().map(|(_, _, key)| key).collect();
        let ranks = keys
            .iter()
            .copied()
            .enumerate()
            .map(|(rank, key)| (key, rank))
            .collect();
        let ordered = Arc::new(OrderedRoster { keys, ranks });
        let ordered = if let (Some(store), Some(input)) = (&self.artifacts, final_input) {
            store.remember_final_allocation(FinalReceipt { input, ordered }, &recording)
        } else {
            ordered
        };
        self.finalized
            .set(ordered)
            .map_err(|_| "startup registration roster issued twice")?;
        Ok(self.finalized.get().unwrap())
    }
    pub(crate) fn order_runtime(
        &self,
        plan: &InitializerPlan,
        classified: &mut crate::initializer_policy::ClassifiedInitializers,
        host: &impl dm_ir::Resolver,
    ) -> Result<(), String> {
        if !Arc::ptr_eq(&self.writes, &plan.writes) && self.writes.as_ref() != plan.writes.as_ref()
        {
            return Err("startup allocation roster differs from current initializer writes".into());
        }
        let finalized = self.finalize(plan, classified, host)?;
        for group in &mut classified.groups {
            if group.receiver.is_some() {
                continue;
            }
            for index in &group.writes {
                if !self
                    .allocation
                    .ranks
                    .contains_key(&key(&classified.writes[*index].write)?)
                {
                    return Err("startup allocation roster omits executable write".into());
                }
            }
            // Existing literal allocation phase remains first. Within each phase,
            // the same current allocation producer controls execution and footer order.
            group.writes.sort_by_key(|index| {
                let write = &classified.writes[*index];
                (
                    write.phase == Some(crate::initializer_policy::Phase::Runtime),
                    finalized.ranks[&key(&write.write).unwrap()],
                )
            });
        }
        Ok(())
    }
    pub(crate) fn order_membership(&self, current: &mut Arc<[Key]>) -> Result<(), String> {
        let requested: BTreeSet<_> = current.iter().copied().collect();
        let keys = self
            .finalized
            .get()
            .map_or(&self.allocation.keys, |roster| &roster.keys);
        let ordered: Vec<_> = keys
            .iter()
            .copied()
            .filter(|key| requested.contains(key))
            .collect();
        if ordered.len() != current.len() {
            return Err("startup allocation roster omits current variable membership".into());
        }
        *current = ordered.into();
        Ok(())
    }
}
/// Availability is selected by the same current resolver precedence as the
/// evaluator. The already issued classifier AST is borrowed; no source reparse
/// or callee-spelling assumption can establish an authored procedure.
// Only positive authored-call evidence can change the compatibility stage.
fn registration_is_deferred(known: bool, forward: bool) -> bool {
    forward && !known
}

#[derive(Default)]
struct CallAvailability {
    known: bool,
    forward: bool,
}
fn authored_call_availability(
    ast: &dm_syntax::Expr,
    owner: SymbolId,
    ordinal: usize,
    positions: &BTreeMap<(SymbolId, SymbolId), usize>,
    host: &impl dm_ir::Resolver,
) -> CallAvailability {
    use dm_ir::{ResolveQuery, ResolvedMeaning};
    let mut answer = CallAvailability::default();
    if let dm_syntax::ExprKind::Call { callee, .. } = &ast.kind {
        if let dm_syntax::ExprKind::Ident(spelling) = &callee.kind {
            if !dm_codegen_byond::is_intrinsic_named_call(spelling) {
                let name = SymbolId::of(spelling);
                let member = host.resolve(ResolveQuery::Proc {
                    owner,
                    name,
                    verb: false,
                });
                let selected = if matches!(member, ResolvedMeaning::Missing) {
                    host.resolve(ResolveQuery::GlobalProc(name))
                } else {
                    member
                };
                if let ResolvedMeaning::Member {
                    owner, name, data, ..
                } = selected
                {
                    if owner == SymbolId::of("/") && data.procedure.is_some() {
                        if let Some(position) = positions.get(&(owner, name)) {
                            answer.known = *position <= ordinal;
                            answer.forward = !answer.known;
                        }
                    }
                }
            }
        }
    }
    dm_syntax::for_each_expression_child(ast, |_, child| {
        let child = authored_call_availability(child, owner, ordinal, positions, host);
        answer.known |= child.known;
        answer.forward |= child.forward;
    });
    answer
}
fn key(write: &InitializerWrite) -> Result<Key, String> {
    match write.target {
        InitializerTarget::Shared { owner, name, .. } => Ok(Key::Variable { owner, name }),
        InitializerTarget::ProcedureStatic(identity) => Ok(Key::ProcedureStatic(identity)),
        InitializerTarget::Instance { .. } => {
            Err("instance write in startup allocation roster".into())
        }
    }
}
#[cfg(test)]
#[path = "startup_allocation_retained_tests.rs"]
mod retained_tests;

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn forward_registration_requires_positive_evidence_and_known_call_wins() {
        // Independent captured variants include both mixed source orders. A
        // previously available callback establishes the owner in either order.
        assert!(registration_is_deferred(false, true));
        assert!(!registration_is_deferred(true, true));
        assert!(!registration_is_deferred(true, false));
        // Unknown, literal and intrinsic cases do not certify a late stage.
        assert!(!registration_is_deferred(false, false));
    }
    struct Source;
    struct RegistrationSource;
    impl dm_preprocess::SourceProvider for RegistrationSource {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok("/world/proc/prior()\n\treturn 1\nvar/global/late = 1\n/proc/reset()\n\treturn 1\n/var/global/first = 2\n".into())
        }
    }
    #[test]
    fn bare_global_registration_is_late_without_changing_semantic_owner() {
        let frontend = dm_tree::frontend::build_with_config(
            std::path::Path::new("probe.dme"),
            &RegistrationSource,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
        )
        .unwrap();
        let declarations = dm_tree::initializers::capture_declaration_plan(
            &frontend.snapshot,
            &frontend.emission_order,
        )
        .unwrap();
        let plan = declarations.plan();
        let roster = StartupAllocationRoster::issue_current(plan, &[], &frontend).unwrap();
        let mut membership: Arc<[Key]> = plan
            .writes
            .iter()
            .map(key)
            .collect::<Result<Vec<_>, _>>()
            .unwrap()
            .into();
        roster.order_membership(&mut membership).unwrap();
        let names: Vec<_> = membership
            .iter()
            .map(|entry| match entry {
                Key::Variable { owner, name } => {
                    assert_eq!(*owner, SymbolId::of("/"));
                    plan.symbols.text(*name).unwrap()
                }
                _ => panic!("unexpected static"),
            })
            .collect();
        assert_eq!(names, ["first", "late"]);
    }
    struct ExistingRootSource;
    impl dm_preprocess::SourceProvider for ExistingRootSource {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok("/proc/reset()\n\treturn 1\nvar/global/cache = 1\n/datum/custom/proc/prior()\n\treturn 1\nvar/global/config = 2\n".into())
        }
    }
    #[test]
    fn existing_root_registration_survives_a_nonroot_procedure() {
        let frontend = dm_tree::frontend::build_with_config(
            std::path::Path::new("probe.dme"),
            &ExistingRootSource,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
        )
        .unwrap();
        let registrations: Vec<_> = frontend
            .allocation_ledger
            .root_field_registrations()
            .collect();
        assert_eq!(registrations.len(), 2);
        assert!(registrations.iter().all(|(_, owner)| owner.is_none()));
        let declarations = dm_tree::initializers::capture_declaration_plan(
            &frontend.snapshot,
            &frontend.emission_order,
        )
        .unwrap();
        let plan = declarations.plan();
        let roster = StartupAllocationRoster::issue_current(
            plan,
            &[SymbolId::of("/datum/custom")],
            &frontend,
        )
        .unwrap();
        let mut membership: Arc<[Key]> = plan
            .writes
            .iter()
            .map(key)
            .collect::<Result<Vec<_>, _>>()
            .unwrap()
            .into();
        roster.order_membership(&mut membership).unwrap();
        let names: Vec<_> = membership
            .iter()
            .map(|entry| match entry {
                Key::Variable { name, .. } => plan.symbols.text(*name).unwrap(),
                _ => panic!("unexpected static"),
            })
            .collect();
        assert_eq!(names, ["cache", "config"]);
    }
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok("/var/global/root_first = 1\n/datum/empty\n/datum/later\n/datum/later/var/static/later_first = 2\n/var/global/root_second = 3\n/datum/empty/var/static/empty_late = 4\n".into())
        }
    }
    #[test]
    fn source_owner_allocation_precedes_root_even_when_root_is_declared_first() {
        let frontend = dm_tree::frontend::build_with_config(
            std::path::Path::new("probe.dme"),
            &Source,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
        )
        .unwrap();
        let declarations = dm_tree::initializers::capture_declaration_plan(
            &frontend.snapshot,
            &frontend.emission_order,
        )
        .unwrap();
        let plan = declarations.plan();
        let roster = StartupAllocationRoster::issue(
            plan,
            &[SymbolId::of("/datum/empty"), SymbolId::of("/datum/later")],
        )
        .unwrap();
        let mut membership: Arc<[Key]> = plan
            .writes
            .iter()
            .map(key)
            .collect::<Result<Vec<_>, _>>()
            .unwrap()
            .into();
        roster.order_membership(&mut membership).unwrap();
        let names: Vec<_> = membership
            .iter()
            .map(|key| match key {
                Key::Variable { name, .. } => plan.symbols.text(*name).unwrap(),
                _ => panic!("unexpected procedure static"),
            })
            .collect();
        assert_eq!(
            names,
            ["empty_late", "later_first", "root_first", "root_second"]
        );
        assert!(StartupAllocationRoster::issue(
            plan,
            &[SymbolId::of("/datum/empty"), SymbolId::of("/datum/empty")]
        )
        .is_err());
        let mut omitted = membership.to_vec();
        omitted.push(Key::Variable {
            owner: SymbolId::of("/"),
            name: SymbolId::of("unissued"),
        });
        assert!(roster.order_membership(&mut omitted.into()).is_err());
    }
}

#[cfg(test)]
#[path = "startup_allocation_static_order_tests.rs"]
mod static_order_tests;
