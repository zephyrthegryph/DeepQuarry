//! Output reachability is distinct from the complete analysis type universe.
//! Unused virtual engine catalog skeletons do not acquire fabricated wire rows.
use crate::{class_projection::ClassProjection, lowering::LoweringBatch};
use dm_codegen_byond::{lower_resolver::ResolverProc, Table};
use dm_ir::{SemanticValue, SymbolId, SymbolTable};
use dm_link::{Key, LinkInventory};
use std::collections::{BTreeMap, HashSet};

pub struct Inputs<'a> {
    pub source_order: &'a [SymbolId],
    pub bodies: &'a LoweringBatch,
    pub initializers: &'a [crate::initializer_lowering::LoweredInitializerUnit],
    pub maps: &'a [crate::initialization_artifact::InitializationArtifact],
    pub inventory: &'a LinkInventory,
    pub symbols: &'a SymbolTable,
    pub non_text_types: &'a [SymbolId],
}
pub fn admit(
    mut projection: ClassProjection,
    inputs: Inputs<'_>,
) -> Result<(ClassProjection, Vec<SymbolId>), String> {
    let Inputs {
        source_order,
        bodies,
        initializers,
        maps,
        inventory,
        symbols,
        non_text_types,
    } = inputs;
    let parents: BTreeMap<_, _> = projection
        .types
        .iter()
        .map(|ty| (ty.path, ty.parent))
        .collect();
    let retained: HashSet<_> = inventory
        .fixed
        .iter()
        .filter_map(|(key, _)| match key {
            Key::Type(path) => Some(*path),
            _ => None,
        })
        .collect();
    let mut needed = retained.clone();
    needed.insert(SymbolId::of("/"));
    needed.insert(SymbolId::of("/world"));
    let mut order = Vec::new();
    fn require(
        path: SymbolId,
        parents: &BTreeMap<SymbolId, Option<SymbolId>>,
        needed: &mut HashSet<SymbolId>,
        order: &mut Vec<SymbolId>,
        active: &mut HashSet<SymbolId>,
    ) -> Result<(), String> {
        if dm_codegen_byond::NativePrimitiveType::from_symbol(path).is_some() {
            return Err(format!(
                "native primitive requires explicit physical class ABI: {path:?}"
            ));
        }
        if needed.contains(&path) {
            return Ok(());
        }
        if !active.insert(path) {
            return Err("required class parent cycle".into());
        }
        let parent = parents
            .get(&path)
            .ok_or_else(|| format!("referenced class absent from semantic skeleton: {path:?}"))?;
        if let Some(parent) = parent {
            require(*parent, parents, needed, order, active)?;
        }
        active.remove(&path);
        needed.insert(path);
        order.push(path);
        Ok(())
    }
    let mut requests = Vec::new();
    let mut source_seen = HashSet::new();
    for &path in source_order {
        if !source_seen.insert(path) {
            return Err("duplicate explicit source class order".into());
        }
        if dm_codegen_byond::NativePrimitiveType::from_symbol(path).is_some() {
            // Semantic declarations remain in the projection. Any actual
            // callable/instance dependency below still requires an explicit ABI.
            continue;
        }
        if !needed.contains(&path) {
            if !parents.contains_key(&path) {
                return Err("source allocation class absent from semantic skeleton".into());
            }
            needed.insert(path);
            order.push(path);
        }
        requests.push(path);
    }
    // Preserve the certified source allocation order verbatim. Dependency
    // closure can append unseen parents; it must not reorder a forward parent
    // assignment that was encountered after the child's allocation.
    for &path in source_order {
        if dm_codegen_byond::NativePrimitiveType::from_symbol(path).is_some() {
            continue;
        }
        if let Some(Some(parent)) = parents.get(&path) {
            require(
                *parent,
                &parents,
                &mut needed,
                &mut order,
                &mut HashSet::new(),
            )?;
        }
    }
    fn values(value: &SemanticValue, requests: &mut Vec<SymbolId>) {
        match value {
            SemanticValue::Type(path)
                if dm_codegen_byond::NativePrimitiveType::from_symbol(*path).is_some() => {}
            SemanticValue::Type(path) => requests.push(*path),
            SemanticValue::Procedure(identity) => requests.push(identity.owner),
            SemanticValue::ModifiedInstance(instance) => requests.push(instance.runtime_type()),
            SemanticValue::List(entries) => {
                for (key, value) in entries.iter() {
                    if let Some(key) = key {
                        values(key, requests);
                    }
                    values(value, requests);
                }
            }
            _ => (),
        }
    }
    for field in projection.fields.iter() {
        let savefile_header = field.owner == SymbolId::of("/savefile")
            && field.declaring_owner == SymbolId::of("/savefile")
            && field.name == SymbolId::of("byond_version")
            && field.role == crate::class_projection::FieldRole::Assignment
            && field.intrinsic
            && !field.shared;
        if !savefile_header {
            requests.push(field.owner);
            requests.push(field.declaring_owner);
        }
        if let crate::initializer_policy::DefaultValue::Scalar(value) = &field.value {
            values(value, &mut requests);
        }
    }
    for chain in projection.chains.iter() {
        requests.push(chain.owner);
    }
    for local in projection.procedure_statics.iter() {
        requests.push(local.identity.procedure.owner);
        if let crate::initializer_policy::DefaultValue::Scalar(value) = &local.value {
            values(value, &mut requests);
        }
    }
    fn code(
        code: &ResolverProc,
        requests: &mut Vec<SymbolId>,
        symbols: &SymbolTable,
    ) -> Result<(), String> {
        let mut failure = None;
        code.procedure.code.for_each_reference(|table, path| {
            if table == Table::Class {
                let id = SymbolId::of(path);
                if symbols.text(id) != Some(path) {
                    failure = Some(format!(
                        "referenced type spelling not collision checked: {path}"
                    ));
                }
                requests.push(id);
            }
        });
        // Modified alias identities do not invent class rows; their explicitly
        // resolved runtime class is a real dependency of the instance artifact.
        for instance in code.instances.values() {
            requests.push(instance.runtime_type);
        }
        for instance in code.modified_instances.values() {
            requests.push(instance.descriptor.runtime_type());
        }
        failure.map_or(Ok(()), Err)
    }
    for unit in &bodies.units {
        code(&unit.code, &mut requests, symbols)?;
        for helper in &unit.source_helpers {
            code(&helper.code, &mut requests, symbols)?;
        }
    }
    for unit in initializers {
        code(&unit.code, &mut requests, symbols)?;
    }
    for unit in maps {
        code(&unit.code, &mut requests, symbols)?;
    }
    // Non-text descriptor producers already issue exact semantic type keys.
    // Preserve their caller-provided order when available, never sort hashes.
    if let Some(types) = inventory.append_orders.get(&dm_link::Table::Type) {
        for key in types {
            if let Key::Type(path) = key {
                if dm_codegen_byond::NativePrimitiveType::from_symbol(*path).is_none() {
                    requests.push(*path);
                }
            }
        }
    }
    requests.extend_from_slice(non_text_types);
    for path in requests {
        require(path, &parents, &mut needed, &mut order, &mut HashSet::new())?;
    }
    projection.types = projection
        .types
        .iter()
        .filter(|ty| needed.contains(&ty.path))
        .cloned()
        .collect::<Vec<_>>()
        .into();
    Ok((projection, order))
}

#[cfg(test)]
mod tests {
    use super::*;
    fn projection() -> ClassProjection {
        ClassProjection {
            tree_identity: 0,
            occurrence_count: 1,
            types: vec![
                crate::class_projection::TypeProjection {
                    path: SymbolId::of("/"),
                    parent: None,
                },
                crate::class_projection::TypeProjection {
                    path: SymbolId::of("/savefile"),
                    parent: Some(SymbolId::of("/")),
                },
            ]
            .into(),
            fields: vec![crate::class_projection::FieldProjection {
                owner: SymbolId::of("/savefile"),
                declaring_owner: SymbolId::of("/savefile"),
                name: SymbolId::of("byond_version"),
                role: crate::class_projection::FieldRole::Assignment,
                wire_flags: None,
                intrinsic: true,
                shared: false,
                value: crate::initializer_policy::DefaultValue::Scalar(SemanticValue::NumberBits(
                    516f32.to_bits(),
                )),
            }]
            .into(),
            shared_slot_order: Vec::new().into(),
            procedure_statics: Vec::new().into(),
            runtime_writes: Vec::new().into(),
            chains: Vec::new().into(),
        }
    }
    #[test]
    fn savefile_header_stays_semantic_without_fabricated_physical_class() {
        let bodies = LoweringBatch::default();
        let inventory = LinkInventory::default();
        let symbols = SymbolTable::default();
        let order = [SymbolId::of("/savefile")];
        let inputs = || Inputs {
            source_order: &order,
            bodies: &bodies,
            initializers: &[],
            maps: &[],
            inventory: &inventory,
            symbols: &symbols,
            non_text_types: &[],
        };
        let (output, allocation) = admit(projection(), inputs()).unwrap();
        assert!(allocation.is_empty());
        assert_eq!(output.fields.len(), 1);
        assert!(!output
            .types
            .iter()
            .any(|ty| ty.path == SymbolId::of("/savefile")));
        let mut callable = projection();
        callable.chains = vec![crate::class_projection::ProcedureChain {
            owner: SymbolId::of("/savefile"),
            name: SymbolId::of("unsupported"),
            verb: false,
            entries: Vec::new().into(),
        }]
        .into();
        assert!(admit(callable, inputs())
            .unwrap_err()
            .contains("native primitive requires explicit physical class ABI"));
        let mut field = projection();
        std::sync::Arc::make_mut(&mut field.fields)[0].name = SymbolId::of("eof");
        assert!(admit(field, inputs())
            .unwrap_err()
            .contains("native primitive requires explicit physical class ABI"));
    }
}
