//! Source inventory admission with explicit observable class and shared-slot
//! orders. Retained engine indexes stay fixed; hash order is never substituted.
use crate::class_projection::{ClassProjection, FieldRole};
use dm_ir::{SymbolId, SymbolTable};
use dm_link::{Entry, Key, LinkInventory, Table};
use std::{
    collections::{BTreeSet, HashSet},
    sync::Arc,
};

pub fn contribute(
    plan: &ClassProjection,
    symbols: &SymbolTable,
    source_type_order: &[SymbolId],
    inventory: &mut LinkInventory,
) -> Result<(), String> {
    let retained: BTreeSet<_> = inventory.fixed.iter().map(|(key, _)| *key).collect();
    let mut source_types = HashSet::new();
    for ty in plan.types.iter() {
        let text = symbols.text(ty.path).ok_or("type spelling missing")?;
        if text == "/" || text == "/world" || retained.contains(&Key::Type(ty.path)) {
            continue;
        }
        let mut content = b"dm-class-skeleton-v1\0".to_vec();
        match ty.parent {
            None => content.push(0),
            Some(parent) => {
                content.push(1);
                content.extend_from_slice(&parent.bits().to_le_bytes());
            }
        }
        inventory.entries.push(Entry {
            key: Key::Type(ty.path),
            content: content.into(),
        });
        inventory
            .spellings
            .push((ty.path, Arc::from(text.as_bytes())));
        source_types.insert(ty.path);
    }
    if source_type_order.len() != source_types.len()
        || source_type_order.iter().copied().collect::<HashSet<_>>() != source_types
    {
        let supplied: HashSet<_> = source_type_order.iter().copied().collect();
        let mut missing: Vec<_> = source_types
            .difference(&supplied)
            .map(|id| symbols.text(*id).unwrap_or("<uncaptured>"))
            .collect();
        let mut extra: Vec<_> = supplied
            .difference(&source_types)
            .map(|id| symbols.text(*id).unwrap_or("<uncaptured>"))
            .collect();
        missing.sort_unstable();
        extra.sort_unstable();
        return Err(format!("source class order must explicitly cover all fresh classes exactly once; missing={missing:?}; extra={extra:?}; ordered={}, unique={}, required={}",source_type_order.len(),supplied.len(),source_types.len()));
    }
    let mut variable_order = Vec::new();
    for field in plan
        .fields
        .iter()
        .filter(|field| field.role == FieldRole::Declaration && field.shared)
    {
        let key = Key::Variable {
            owner: field.owner,
            name: field.name,
        };
        if retained.contains(&key) {
            continue;
        }
        let flags = field.wire_flags.ok_or("shared formal flags unknown")?;
        let mut content = b"dm-shared-slot-v1\0".to_vec();
        content.extend_from_slice(&flags.to_le_bytes());
        inventory.entries.push(Entry {
            key,
            content: content.into(),
        });
        for symbol in [field.owner, field.name] {
            inventory.spellings.push((
                symbol,
                Arc::from(
                    symbols
                        .text(symbol)
                        .ok_or("shared field spelling absent")?
                        .as_bytes(),
                ),
            ));
        }
        variable_order.push(key);
    }
    for local in plan.procedure_statics.iter() {
        let key = Key::ProcedureStatic(local.identity);
        if retained.contains(&key) {
            return Err("source static redeclares retained slot".into());
        }
        let mut content = local.identity.canonical_bytes();
        content.extend_from_slice(&local.wire_flags.to_le_bytes());
        inventory.entries.push(Entry {
            key,
            content: content.into(),
        });
        for symbol in [
            local.identity.procedure.owner,
            local.identity.procedure.name,
            local.identity.name,
        ] {
            inventory.spellings.push((
                symbol,
                Arc::from(
                    symbols
                        .text(symbol)
                        .ok_or("procedure static spelling absent")?
                        .as_bytes(),
                ),
            ));
        }
        variable_order.push(key);
    }
    let all: BTreeSet<_> = variable_order.iter().copied().collect();
    let projected: Vec<_> = plan
        .shared_slot_order
        .iter()
        .copied()
        .filter(|key| !retained.contains(key))
        .collect();
    if projected.len() != all.len() || projected.iter().copied().collect::<BTreeSet<_>>() != all {
        return Err(
            "shared slot source order does not cover class/global/procedure slots exactly once"
                .into(),
        );
    }
    variable_order = projected;
    // Procedure IDs are observable through typesof(/type/proc), independently
    // of the class's method footer. Carry the issued encounter roster into
    // the existing linker; its finalizer appends generated executable domains.
    // Membership is prepended (reverse allocation); numeric IDs use the
    // opposite order so typesof observes the authored declaration order.
    let procedure_order = plan
        .procedure_membership
        .iter()
        .rev()
        .copied()
        .filter(|key| !retained.contains(key))
        .collect::<Vec<_>>();
    for (table, fresh) in [
        (
            Table::Type,
            source_type_order
                .iter()
                .copied()
                .map(Key::Type)
                .collect::<Vec<_>>(),
        ),
        (Table::Variable, variable_order),
        (Table::Procedure, procedure_order),
    ] {
        if inventory.orders.contains_key(&table) {
            return Err("fresh append order conflicts with complete table order".into());
        }
        if inventory
            .append_orders
            .get(&table)
            .is_some_and(|existing| *existing != fresh)
        {
            return Err("source order conflicts with supplied table order".into());
        }
        inventory.append_orders.insert(table, fresh);
    }
    Ok(())
}

/// Bind VM Global operands to actual VarIDs. Footer order is a separate
/// declaration roster and must never be substituted for a variable record ID.
pub(crate) fn bind_global_records(
    plan: &ClassProjection,
    frame_records: usize,
    inventory: &mut LinkInventory,
) -> Result<(), String> {
    let mut next = usize::try_from(
        *inventory
            .reserved_prefixes
            .get(&Table::VariableRecord)
            .ok_or("variable record prefix missing")?,
    )
    .map_err(|_| "variable prefix overflow")?;
    if inventory
        .entries
        .iter()
        .any(|entry| entry.key == Key::BuiltinGlobalVars)
        && !inventory
            .fixed
            .iter()
            .any(|(key, _)| *key == Key::BuiltinGlobalVars)
    {
        next = next.checked_add(1).ok_or("builtin variable overflow")?;
    }
    next = next
        .checked_add(frame_records)
        .ok_or("procedure variable overflow")?;
    for field in plan
        .fields
        .iter()
        .filter(|field| field.role == FieldRole::Declaration)
    {
        let index = u32::try_from(next).map_err(|_| "field variable overflow")?;
        next = next.checked_add(1).ok_or("field variable overflow")?;
        if field.shared {
            let key = Key::Variable {
                owner: field.owner,
                name: field.name,
            };
            if inventory.fixed.iter().any(|(existing, _)| *existing == key) {
                return Err("source field redeclares retained record".into());
            }
            inventory.fixed.push((key, index));
        }
    }
    for local in plan.procedure_statics.iter() {
        let index = u32::try_from(next).map_err(|_| "static variable overflow")?;
        next = next.checked_add(1).ok_or("static variable overflow")?;
        inventory
            .fixed
            .push((Key::ProcedureStatic(local.identity), index));
    }
    inventory.append_orders.remove(&Table::Variable);
    Ok(())
}

#[cfg(test)]
mod global_record_tests {
    use super::*;
    #[test]
    fn frame_and_nonshared_records_are_counted_without_changing_footer_order() {
        use crate::class_projection::{FieldProjection, ProcedureStaticProjection};
        let owner = SymbolId::of("/");
        let shared = Key::Variable {
            owner,
            name: SymbolId::of("shared"),
        };
        let local = dm_ir::ProcedureStaticIdentity {
            procedure: dm_ir::ProcedureIdentity {
                owner,
                name: SymbolId::of("probe"),
                verb: false,
                occurrence: 0,
            },
            name: SymbolId::of("local_static"),
        };
        let plan = ClassProjection {
            field_placements: Default::default(),
            types: Arc::from([]),
            chains: Arc::from([]),
        procedure_membership: Arc::from([]),
            fields: [false, true]
                .into_iter()
                .enumerate()
                .map(|(ordinal, shared)| {
                    Arc::new(FieldProjection {
                        owner,
                        declaring_owner: owner,
                        name: SymbolId::of(if ordinal == 0 { "instance" } else { "shared" }),
                        role: FieldRole::Declaration,
                        wire_flags: Some(if shared { 1 } else { 0 }),
                        intrinsic: false,
                        shared,
                        value: crate::initializer_policy::DefaultValue::Scalar(
                            dm_ir::SemanticValue::Null,
                        ),
                    })
                })
                .collect::<Vec<_>>()
                .into(),
            procedure_declarations: Default::default(),
            shared_slot_order: Arc::from([Key::ProcedureStatic(local), shared]),
            procedure_statics: Arc::from([ProcedureStaticProjection {
                identity: local,
                wire_flags: 1,
                value: crate::initializer_policy::DefaultValue::Scalar(dm_ir::SemanticValue::Null),
                source_ordinal: 0,
            }]),
            runtime_writes: Arc::from([]),
            tree_identity: 0,
            occurrence_count: 0,
        };
        let mut inventory = LinkInventory::default();
        inventory
            .reserved_prefixes
            .insert(Table::VariableRecord, 177);
        inventory.entries.push(Entry {
            key: Key::BuiltinGlobalVars,
            content: Vec::<u8>::new().into(),
        });
        inventory
            .append_orders
            .insert(Table::Variable, plan.shared_slot_order.to_vec());
        bind_global_records(&plan, 7, &mut inventory).unwrap();
        assert_eq!(
            inventory.fixed,
            vec![(shared, 186), (Key::ProcedureStatic(local), 187)]
        );
        assert!(!inventory.append_orders.contains_key(&Table::Variable));
        assert_eq!(
            &*plan.shared_slot_order,
            &[Key::ProcedureStatic(local), shared]
        );
    }
}
