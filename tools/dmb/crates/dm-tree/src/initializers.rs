//! Immutable authored initializer ledger. It preserves declaration/emission
//! order without deciding BYOND's materialization or runtime scheduling phases.
use crate::{DefinitionMode, MemberId, MemberKind, OccurrenceId, Provenance, Target, TreeSnapshot};
use dm_ir::{InitializerTarget, InitializerValue, InitializerWrite, ResolveQuery, ResolvedMeaning};
use std::sync::Arc;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct InitializerOrigin {
    pub occurrence: OccurrenceId,
    pub kind: InitializerOriginKind,
    pub encounter_ordinal: usize,
    pub emission_ordinal: usize,
    pub provenance: Provenance,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum InitializerOriginKind {
    Declaration(MemberId),
    ProcedureStatic {
        identity: dm_ir::ProcedureStaticIdentity,
        expanded_span: dm_syntax::Span,
    },
}
#[derive(Clone, Debug)]
pub struct InitializerPlan {
    /// Retains formal/effective defaults and inherited opaque knowledge without
    /// copying a project binding table or conflating their lexical scopes.
    pub source: TreeSnapshot,
    pub symbols: Arc<dm_ir::SymbolTable>,
    pub writes: Arc<[InitializerWrite]>,
    /// One source sidecar per write, excluded from semantic identity.
    pub origins: Arc<[InitializerOrigin]>,
    /// Identity of this ordered authored ledger, not a replacement for lowering
    /// resolver dependency receipts or backend policy/configuration identity.
    pub identity: u128,
}
/// Issued declaration ledger for one immutable source and emission projection.
/// The private plan cannot be replaced by a detached mutable public ledger.
pub struct DeclarationPlan<'a> {
    source: &'a TreeSnapshot,
    order: &'a [OccurrenceId],
    plan: InitializerPlan,
}
impl DeclarationPlan<'_> {
    pub fn source(&self) -> &TreeSnapshot {
        self.source
    }
    pub fn plan(&self) -> &InitializerPlan {
        &self.plan
    }
}
pub fn capture_declaration_plan<'a>(
    source: &'a TreeSnapshot,
    order: &'a [OccurrenceId],
) -> Result<DeclarationPlan<'a>, Vec<PlanError>> {
    let plan = plan(source, order)?;
    Ok(DeclarationPlan {
        source,
        order,
        plan,
    })
}
/// Join against the issuer's exact private ledger without replaying declarations.
pub fn with_captured_procedure_statics(
    declarations: &DeclarationPlan<'_>,
    captures: &[(OccurrenceId, crate::procedure_statics::StaticPlan)],
) -> Result<InitializerPlan, String> {
    with_captured_procedure_statics_borrowed(
        declarations,
        captures
            .iter()
            .map(|(occurrence, plan)| (*occurrence, plan)),
    )
}
pub fn with_captured_procedure_statics_borrowed<'a>(
    declarations: &DeclarationPlan<'_>,
    captures: impl IntoIterator<Item = (OccurrenceId, &'a crate::procedure_statics::StaticPlan)>,
) -> Result<InitializerPlan, String> {
    assemble_procedure_statics(&declarations.plan, declarations.order, captures)
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
    let draft = capture_declaration_draft(source, emission_order)?;
    let identity = plan_identity(b"dm-authored-initializer-plan-v1\0", true, &draft.writes);
    Ok(InitializerPlan {
        symbols: source.tree.shared_symbols(),
        source: source.clone(),
        writes: draft.writes.into(),
        origins: draft.origins.into(),
        identity,
    })
}

/// Owned rows issued by the same declaration traversal as the analysis plan.
/// Fields remain private so detached callers cannot forge source authority.
pub struct DeclarationDraft<'a> {
    source: &'a TreeSnapshot,
    order: &'a [OccurrenceId],
    writes: Vec<InitializerWrite>,
    origins: Vec<InitializerOrigin>,
}
pub fn capture_declaration_draft<'a>(
    source: &'a TreeSnapshot,
    emission_order: &'a [OccurrenceId],
) -> Result<DeclarationDraft<'a>, Vec<PlanError>> {
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
            lexical_procedure: None,
            value,
            declared_array,
            declaration_flags: metadata
                .inherited_opaque
                .is_none()
                .then_some(metadata.flags),
        });
        origins.push(InitializerOrigin {
            occurrence: id,
            kind: InitializerOriginKind::Declaration(member_id),
            encounter_ordinal: id.0 as usize,
            emission_ordinal,
            provenance: occurrence.provenance.clone(),
        });
    }
    if !errors.is_empty() {
        return Err(errors);
    }
    Ok(DeclarationDraft {
        source,
        order: emission_order,
        writes,
        origins,
    })
}
pub fn finish_declaration_draft<'a>(
    draft: DeclarationDraft<'_>,
    captures: impl IntoIterator<Item = (OccurrenceId, &'a crate::procedure_statics::StaticPlan)>,
) -> Result<InitializerPlan, String> {
    assemble_procedure_rows(
        draft.source,
        draft.order,
        draft.writes.into_iter().zip(draft.origins),
        captures,
    )
}

/// Interleave captured procedure statics at the procedure declaration's actual
/// emission position. Class-global and procedure-static writes share one ledger.
pub fn with_procedure_statics(
    base: &InitializerPlan,
    order: &[OccurrenceId],
    captures: &[(OccurrenceId, crate::procedure_statics::StaticPlan)],
) -> Result<InitializerPlan, String> {
    let current = plan(&base.source, order)
        .map_err(|error| format!("startup declaration order: {error:?}"))?;
    if current.identity != base.identity
        || current.writes.as_ref() != base.writes.as_ref()
        || current.origins.as_ref() != base.origins.as_ref()
    {
        return Err("startup base ledger differs from current declarations".into());
    }
    assemble_procedure_statics(
        base,
        order,
        captures
            .iter()
            .map(|(occurrence, plan)| (*occurrence, plan)),
    )
}
fn assemble_procedure_statics<'a>(
    base: &InitializerPlan,
    order: &[OccurrenceId],
    captures: impl IntoIterator<Item = (OccurrenceId, &'a crate::procedure_statics::StaticPlan)>,
) -> Result<InitializerPlan, String> {
    assemble_procedure_rows(
        &base.source,
        order,
        base.writes
            .iter()
            .cloned()
            .zip(base.origins.iter().cloned()),
        captures,
    )
}
fn assemble_procedure_rows<'a>(
    source: &TreeSnapshot,
    order: &[OccurrenceId],
    rows: impl Iterator<Item = (InitializerWrite, InitializerOrigin)>,
    captures: impl IntoIterator<Item = (OccurrenceId, &'a crate::procedure_statics::StaticPlan)>,
) -> Result<InitializerPlan, String> {
    let mut symbols = dm_ir::SymbolTable::overlay(source.tree.shared_symbols());
    let mut by_occurrence = std::collections::HashMap::new();
    for (occurrence, capture) in captures {
        if by_occurrence.insert(occurrence, capture).is_some()
            || capture.declarations.len() != capture.origins.len()
        {
            return Err("duplicate or incomplete procedure static capture".into());
        }
        for (_, text) in capture.symbols.ordered() {
            symbols.intern(text).map_err(|e| e.to_string())?;
        }
    }
    let mut declarations = rows.peekable();
    let mut writes = Vec::new();
    let mut origins = Vec::new();
    for (emission_ordinal, occurrence_id) in order.iter().enumerate() {
        if declarations
            .peek()
            .is_some_and(|(_, origin)| origin.occurrence == *occurrence_id)
        {
            let (write, origin) = declarations.next().expect("peeked declaration row");
            writes.push(write);
            origins.push(origin);
        }
        if let Some(capture) = by_occurrence.remove(occurrence_id) {
            let occurrence = source
                .occurrences
                .get(*occurrence_id)
                .ok_or("static procedure occurrence absent")?;
            let Target::Member(member) = occurrence.target else {
                return Err("static owner occurrence is not a member".into());
            };
            let node = source
                .tree
                .member(member)
                .ok_or("static procedure member absent")?;
            let owner = source
                .tree
                .type_node(node.owner)
                .ok_or("static procedure owner absent")?
                .path;
            // The producer retains an empty capture for every procedure so its
            // lexical inventory remains authoritative. There is no declaration
            // identity to compare with an override chain in those captures.
            // Keep occurrence/member/owner validation above; malformed variable
            // captures still follow the strict validation path below.
            if capture.declarations.is_empty() && node.kind != MemberKind::Var {
                continue;
            }
            let procedure_occurrence = source
                .tree
                .override_chain(member)
                .iter()
                .filter(|id| {
                    source.tree.member(**id).is_some_and(|entry| {
                        entry.owner == node.owner
                            && entry.name == node.name
                            && entry.kind == node.kind
                    })
                })
                .count()
                .checked_sub(1)
                .ok_or("static procedure chain empty")?;
            for (declaration, origin) in capture.declarations.iter().zip(&capture.origins) {
                let identity = declaration.identity;
                if usize::try_from(identity.procedure.occurrence).ok() != Some(procedure_occurrence)
                    || identity.procedure.owner != owner
                    || identity.procedure.name != node.name
                    || identity.procedure.verb != (node.kind == MemberKind::Verb)
                    || node.kind == MemberKind::Var
                {
                    return Err("static declaration belongs to another procedure".into());
                }
                writes.push(InitializerWrite {
                    target: InitializerTarget::ProcedureStatic(identity),
                    lexical_owner: owner,
                    lexical_procedure: Some(identity.procedure),
                    value: declaration.initializer.clone(),
                    declared_array: declaration.declared_array.clone(),
                    declaration_flags: Some(declaration.modifiers),
                });
                origins.push(InitializerOrigin {
                    occurrence: *occurrence_id,
                    kind: InitializerOriginKind::ProcedureStatic {
                        identity,
                        expanded_span: origin.header_span,
                    },
                    encounter_ordinal: occurrence_id.0 as usize,
                    emission_ordinal,
                    provenance: occurrence.provenance.clone(),
                });
            }
        }
    }
    if declarations.peek().is_some() || !by_occurrence.is_empty() {
        return Err("startup captures are outside complete emission order".into());
    }
    let identity = plan_identity(b"dm-authored-startup-plan-v2\0", false, &writes);
    Ok(InitializerPlan {
        source: source.clone(),
        symbols: Arc::new(symbols),
        writes: writes.into(),
        origins: origins.into(),
        identity,
    })
}

/// Preserve the existing write codec and framing, retaining only one write's
/// canonical buffer at a time rather than a second whole-plan byte image.
fn plan_identity(header: &[u8], include_count: bool, writes: &[InitializerWrite]) -> u128 {
    let mut hash = xxhash_rust::xxh3::Xxh3::new();
    hash.update(header);
    if include_count {
        hash.update(&(writes.len() as u64).to_le_bytes());
    }
    for write in writes {
        hash.update(&(write.canonical_len() as u64).to_le_bytes());
        write.write_canonical(|chunk| hash.update(chunk));
    }
    hash.digest128()
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
    fn assert_legacy_identity(plan: &InitializerPlan, header: &[u8], count: bool) {
        let mut bytes = header.to_vec();
        if count {
            bytes.extend_from_slice(&(plan.writes.len() as u64).to_le_bytes());
        }
        for write in plan.writes.iter() {
            let canonical = write.canonical_bytes();
            bytes.extend_from_slice(&(canonical.len() as u64).to_le_bytes());
            bytes.extend_from_slice(&canonical);
        }
        assert_eq!(plan.identity, xxhash_rust::xxh3::xxh3_128(&bytes));
    }

    #[test]
    fn streaming_identity_preserves_variable_unicode_expression_array_and_order_bytes() {
        let source =
            "var/a = list(1, \"雪\", list(2, 3))\nvar/b[2][3]\nvar/c = \"different-length\"\n";
        let snapshot = snapshot(source, 0);
        let order = order(&snapshot);
        let captured = plan(&snapshot, &order).unwrap();
        assert_eq!(captured.writes.len(), 3);
        assert_legacy_identity(&captured, b"dm-authored-initializer-plan-v1\0", true);
        let mut reverse = order;
        reverse.reverse();
        let reordered = plan(&snapshot, &reverse).unwrap();
        assert_legacy_identity(&reordered, b"dm-authored-initializer-plan-v1\0", true);
        assert_ne!(captured.identity, reordered.identity);
    }
    #[test]
    fn procedure_statics_join_global_writes_at_source_encounter() {
        let source = "var/a = mark(1)\n/proc/work()\n    var/static/local = mark(2)\n    return local\nvar/b = mark(3)\n";
        let snapshot = snapshot(source, 0);
        let order = order(&snapshot);
        let ast = dm_syntax::parse(source);
        let procedure = ast
            .items
            .iter()
            .find(|item| item.header.contains("work("))
            .unwrap();
        let identity = dm_ir::ProcedureIdentity {
            owner: SymbolId::of("/"),
            name: SymbolId::of("work"),
            verb: false,
            occurrence: 0,
        };
        let capture = crate::procedure_statics::capture(identity, &procedure.children).unwrap();
        let occurrence = order.iter().copied().find(|id| snapshot.occurrences.get(*id).is_some_and(|row| matches!(row.target,Target::Member(member) if snapshot.tree.member(member).is_some_and(|node| node.kind==MemberKind::Proc)))).unwrap();
        let base = plan(&snapshot, &order).unwrap();
        let empty = crate::procedure_statics::capture(identity, &[]).unwrap();
        let unchanged = with_procedure_statics(&base, &order, &[(occurrence, empty)]).unwrap();
        assert_eq!(unchanged.origins, base.origins);
        assert_eq!(
            unchanged
                .writes
                .iter()
                .map(InitializerWrite::canonical_bytes)
                .collect::<Vec<_>>(),
            base.writes
                .iter()
                .map(InitializerWrite::canonical_bytes)
                .collect::<Vec<_>>()
        );
        let startup = with_procedure_statics(&base, &order, &[(occurrence, capture)]).unwrap();
        assert_eq!(startup.writes.len(), 3);
        assert!(
            matches!(startup.writes[0].target,InitializerTarget::Shared{name,..} if name==SymbolId::of("a"))
        );
        assert!(
            matches!(startup.writes[1].target,InitializerTarget::ProcedureStatic(id) if id.procedure==identity && id.name==SymbolId::of("local"))
        );
        assert!(
            matches!(startup.writes[2].target,InitializerTarget::Shared{name,..} if name==SymbolId::of("b"))
        );
        assert_eq!(startup.writes[1].lexical_procedure, Some(identity));
        assert_legacy_identity(&base, b"dm-authored-initializer-plan-v1\0", true);
        assert_legacy_identity(&startup, b"dm-authored-startup-plan-v2\0", false);

        assert_eq!(startup.symbols.text(SymbolId::of("local")), Some("local"));
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
        let InitializerOriginKind::Declaration(member) = plan.origins[5].kind else {
            panic!("expected declaration");
        };
        let node = plan.source.tree.member(member).unwrap();
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
    #[test]
    fn issued_declaration_plan_matches_strict_join_and_rejects_detached_tampering() {
        let snapshot = snapshot("var/first = 1\nvar/second = 2\n", 0);
        let order = order(&snapshot);
        let issued = capture_declaration_plan(&snapshot, &order).unwrap();
        assert!(std::ptr::eq(issued.source(), &snapshot));
        let strict = with_procedure_statics(issued.plan(), &order, &[]).unwrap();
        let captured = with_captured_procedure_statics(&issued, &[]).unwrap();
        assert_eq!(strict.identity, captured.identity);
        assert_eq!(strict.writes.as_ref(), captured.writes.as_ref());
        assert_eq!(strict.origins.as_ref(), captured.origins.as_ref());
        let mut forged_write = issued.plan().clone();
        Arc::make_mut(&mut forged_write.writes)[0].value = InitializerValue::NoAuthoredValue;
        assert_eq!(forged_write.identity, issued.plan().identity);
        assert!(with_procedure_statics(&forged_write, &order, &[]).is_err());
        let mut forged_origin = issued.plan().clone();
        Arc::make_mut(&mut forged_origin.origins)[0]
            .provenance
            .include_occurrence += 1;
        assert_eq!(forged_origin.identity, issued.plan().identity);
        assert!(with_procedure_statics(&forged_origin, &order, &[]).is_err());
        // Detached copies cannot alter the issuer's read-only ledger.
        let still_captured = with_captured_procedure_statics(&issued, &[]).unwrap();
        assert_eq!(still_captured.writes.as_ref(), captured.writes.as_ref());
        assert_eq!(still_captured.origins.as_ref(), captured.origins.as_ref());
    }
}

#[cfg(test)]
#[path = "initializer_draft_tests.rs"]
mod draft_tests;
