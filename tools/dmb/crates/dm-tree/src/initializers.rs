//! Immutable authored initializer ledger. It preserves declaration/emission
//! order without deciding BYOND's materialization or runtime scheduling phases.
use crate::{DefinitionMode, MemberId, MemberKind, OccurrenceId, Provenance, Target, TreeSnapshot};
use dm_ir::{InitializerTarget, InitializerValue, InitializerWrite, ResolveQuery, ResolvedMeaning};
use std::sync::Arc;

#[derive(Clone, Debug)]
pub struct InitializerOrigin {
    pub occurrence: OccurrenceId,
    pub member: MemberId,
    pub encounter_ordinal: usize,
    pub emission_ordinal: usize,
    pub provenance: Provenance,
}
#[derive(Clone, Debug)]
pub struct InitializerPlan {
    /// Retains formal/effective defaults and inherited opaque knowledge without
    /// copying a project binding table or conflating their lexical scopes.
    pub source: TreeSnapshot,
    pub writes: Arc<[InitializerWrite]>,
    /// One source sidecar per write, excluded from semantic identity.
    pub origins: Arc<[InitializerOrigin]>,
    /// Identity of this ordered authored ledger, not a replacement for lowering
    /// resolver dependency receipts or backend policy/configuration identity.
    pub identity: u128,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PlanError {
    SnapshotIdentityMismatch,
    IncompleteEmissionOrder {
        occurrences: usize,
        provided: usize,
    },
    InvalidOccurrence(OccurrenceId),
    DuplicateOccurrence(OccurrenceId),
    InvalidMember(MemberId),
    UnsupportedStorage {
        occurrence: OccurrenceId,
        query: ResolveQuery,
    },
    InvalidStorage {
        occurrence: OccurrenceId,
    },
}

/// `emission_order` must explicitly project every current occurrence once.
/// This validates the projection rather than deriving order from arena/hash IDs.
/// Every authored variable occurrence is retained, including superseded writes;
/// a backend must prove which records are defaults versus executable effects.
pub fn plan(
    source: &TreeSnapshot,
    emission_order: &[OccurrenceId],
) -> Result<InitializerPlan, Vec<PlanError>> {
    if source.tree.identity() != source.occurrences.tree_identity() {
        return Err(vec![PlanError::SnapshotIdentityMismatch]);
    }
    let occurrences = source.occurrences.source_order();
    if occurrences.len() != emission_order.len() {
        return Err(vec![PlanError::IncompleteEmissionOrder {
            occurrences: occurrences.len(),
            provided: emission_order.len(),
        }]);
    }
    let mut seen = vec![false; occurrences.len()];
    let mut writes = Vec::new();
    let mut origins = Vec::new();
    let mut errors = Vec::new();
    for (emission_ordinal, &id) in emission_order.iter().enumerate() {
        let Some(occurrence) = source.occurrences.get(id) else {
            errors.push(PlanError::InvalidOccurrence(id));
            continue;
        };
        if std::mem::replace(&mut seen[id.0 as usize], true) {
            errors.push(PlanError::DuplicateOccurrence(id));
            continue;
        }
        let Target::Member(member_id) = occurrence.target else {
            continue;
        };
        let Some(member) = source.tree.member(member_id) else {
            errors.push(PlanError::InvalidMember(member_id));
            continue;
        };
        if member.kind != MemberKind::Var {
            continue;
        }
        let Some(owner) = source.tree.type_node(member.owner) else {
            errors.push(PlanError::InvalidMember(member_id));
            continue;
        };
        let lexical_owner = owner.path;
        let target = match source.tree.variable_storage_for_member(member_id) {
            ResolvedMeaning::Slot {
                symbol,
                owner,
                name,
            } => InitializerTarget::Shared {
                slot: symbol,
                owner,
                name,
            },
            ResolvedMeaning::InstanceField {
                declaring_owner,
                name,
            } => InitializerTarget::Instance {
                declaring_owner,
                receiver_owner: lexical_owner,
                name,
            },
            ResolvedMeaning::Unsupported(query) => {
                errors.push(PlanError::UnsupportedStorage {
                    occurrence: id,
                    query,
                });
                continue;
            }
            _ => {
                errors.push(PlanError::InvalidStorage { occurrence: id });
                continue;
            }
        };
        let metadata = &member.metadata;
        let declared_array = if matches!(
            member.definition,
            DefinitionMode::Declare | DefinitionMode::Implicit
        ) {
            metadata.array.clone()
        } else {
            None
        };
        let value = if let Some(expression) = &metadata.initializer {
            InitializerValue::Expression(expression.clone())
        } else if let Some(array) = declared_array
            .as_ref()
            .filter(|array| array.dimensions.iter().any(Option::is_some))
        {
            InitializerValue::ArrayAllocation(Arc::clone(array))
        } else {
            InitializerValue::NoAuthoredValue
        };
        writes.push(InitializerWrite {
            target,
            lexical_owner,
            value,
            declared_array,
            declaration_flags: metadata
                .inherited_opaque
                .is_none()
                .then_some(metadata.flags),
        });
        origins.push(InitializerOrigin {
            occurrence: id,
            member: member_id,
            encounter_ordinal: id.0 as usize,
            emission_ordinal,
            provenance: occurrence.provenance.clone(),
        });
    }
    if !errors.is_empty() {
        return Err(errors);
    }
    let mut canonical = b"dm-authored-initializer-plan-v1\0".to_vec();
    canonical.extend_from_slice(&(writes.len() as u64).to_le_bytes());
    for write in &writes {
        let bytes = write.canonical_bytes();
        canonical.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
        canonical.extend_from_slice(&bytes);
    }
    Ok(InitializerPlan {
        source: source.clone(),
        writes: writes.into(),
        origins: origins.into(),
        identity: xxhash_rust::xxh3::xxh3_128(&canonical),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::{FileId, SymbolId, SymbolTable};
    fn snapshot(source: &str, file: u32) -> TreeSnapshot {
        crate::from_ast(
            &dm_syntax::parse(source),
            SymbolTable::default(),
            FileId(file),
            0,
            0,
        )
        .unwrap()
        .finish()
        .unwrap()
    }
    fn order(snapshot: &TreeSnapshot) -> Vec<OccurrenceId> {
        (0..snapshot.occurrences.source_order().len())
            .map(|index| OccurrenceId(index as u32))
            .collect()
    }
    #[test]
    fn globals_statics_instance_overrides_and_allocations_retain_scopes_and_order() {
        let snapshot = snapshot("var/global_value = mark(1)\n/datum/base\n    var/static/shared = mark(2)\n    var/value = mark(3)\n    var/list/items[2]\n/datum/base/child\n    shared = mark(4)\n    value = mark(5)\n    items = list(7)\n", 1);
        let plan = plan(&snapshot, &order(&snapshot)).unwrap();
        assert_eq!(plan.writes.len(), 7);
        assert!(
            matches!(plan.writes[0].target, InitializerTarget::Shared { owner, .. } if owner == SymbolId::of("/"))
        );
        assert!(
            matches!(plan.writes[4].target, InitializerTarget::Shared { owner, .. } if owner == SymbolId::of("/datum/base"))
        );
        assert_eq!(
            plan.writes[4].lexical_owner,
            SymbolId::of("/datum/base/child")
        );
        assert!(
            matches!(plan.writes[5].target, InitializerTarget::Instance { declaring_owner,receiver_owner,.. }
            if declaring_owner == SymbolId::of("/datum/base") && receiver_owner == SymbolId::of("/datum/base/child"))
        );
        assert!(matches!(
            plan.writes[3].value,
            InitializerValue::ArrayAllocation(_)
        ));
        assert!(matches!(
            plan.writes[6].value,
            InitializerValue::Expression(_)
        ));
        assert!(plan.writes[6].declared_array.is_none());
        let node = plan.source.tree.member(plan.origins[5].member).unwrap();
        assert!(node.metadata.declared_initializer.is_some());
        assert!(node.metadata.initializer.is_some());
    }
    #[test]
    fn explicit_projection_and_current_origins_are_independent_of_ledger_identity() {
        let first = snapshot("var/a = mark(1)\nvar/b = mark(2)\n", 1);
        let second = snapshot("var/a = mark(1)\nvar/b = mark(2)\n", 9);
        let forward = plan(&first, &order(&first)).unwrap();
        let other_source = plan(&second, &order(&second)).unwrap();
        assert_eq!(forward.identity, other_source.identity);
        assert_ne!(
            forward.origins[0].provenance.span.file,
            other_source.origins[0].provenance.span.file
        );
        let mut reverse = order(&first);
        reverse.reverse();
        assert_ne!(forward.identity, plan(&first, &reverse).unwrap().identity);
        assert!(
            matches!(plan(&first, &[OccurrenceId(0),OccurrenceId(0)]), Err(errors)
            if matches!(errors[0], PlanError::DuplicateOccurrence(_)))
        );
    }
    #[test]
    fn absent_unsized_and_explicit_sized_array_values_are_not_guessed() {
        let snapshot = snapshot(
            "var/absent\nvar/list/unsized_value[]\nvar/list/explicit_value[2] = list(1)\n",
            0,
        );
        let plan = plan(&snapshot, &order(&snapshot)).unwrap();
        assert!(matches!(
            plan.writes[0].value,
            InitializerValue::NoAuthoredValue
        ));
        assert!(matches!(
            plan.writes[1].value,
            InitializerValue::NoAuthoredValue
        ));
        assert!(plan.writes[1].declared_array.is_some());
        assert!(matches!(
            plan.writes[2].value,
            InitializerValue::Expression(_)
        ));
        assert!(plan.writes[2].declared_array.is_some());
    }
}
