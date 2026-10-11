//! Output reachability is distinct from the complete analysis type universe.
//! Unused virtual engine catalog skeletons do not acquire fabricated wire rows.
use crate::{class_projection::ClassProjection, lowering::LoweringBatch};
use dm_codegen_byond::lower_resolver::ResolverProc;
use dm_ir::{SemanticValue, SymbolId, SymbolTable};
use dm_link::{Key, LinkInventory};
use std::collections::{BTreeMap, HashSet};
pub(crate) mod ancestry;
pub(crate) mod field_requests;
pub(crate) mod parent_index;
pub(crate) mod selected_roster;
pub(crate) mod source_prefix;
pub use ancestry::RequiredTypeArtifacts;

pub struct Inputs<'a> {
    pub source_order: &'a [SymbolId],
    pub bodies: &'a LoweringBatch,
    pub initializers: &'a [crate::initializer_lowering::LoweredInitializerUnit],
    pub maps: &'a [crate::initialization_artifact::InitializationArtifact],
    pub inventory: &'a LinkInventory,
    pub symbols: &'a SymbolTable,
    pub non_text_types: &'a [SymbolId],
}
pub struct PreparedInputs<'a> {
    pub source_allocation_roster:
        Option<&'a std::sync::Arc<crate::type_creation_order::AllocationRoster>>,
    pub source_order: &'a [SymbolId],
    pub body_type_requests: &'a [SymbolId],
    pub initializers: &'a [crate::initializer_lowering::LoweredInitializerUnit],
    pub maps: &'a [crate::initialization_artifact::InitializationArtifact],
    pub inventory: &'a LinkInventory,
    pub symbols: &'a SymbolTable,
    pub non_text_types: &'a [SymbolId],
}
enum BodyRequirements<'a> {
    Rich(&'a LoweringBatch),
    Prepared(&'a [SymbolId]),
}
struct CommonInputs<'a> {
    source_allocation_roster:
        Option<&'a std::sync::Arc<crate::type_creation_order::AllocationRoster>>,
    source_order: &'a [SymbolId],
    bodies: BodyRequirements<'a>,
    initializers: &'a [crate::initializer_lowering::LoweredInitializerUnit],
    maps: &'a [crate::initialization_artifact::InitializationArtifact],
    inventory: &'a LinkInventory,
    symbols: &'a SymbolTable,
    non_text_types: &'a [SymbolId],
}
pub fn admit(
    projection: ClassProjection,
    inputs: Inputs<'_>,
) -> Result<(ClassProjection, Vec<SymbolId>), String> {
    admit_common(
        projection,
        CommonInputs {
            source_order: inputs.source_order,
            bodies: BodyRequirements::Rich(inputs.bodies),
            source_allocation_roster: None,
            initializers: inputs.initializers,
            maps: inputs.maps,
            inventory: inputs.inventory,
            symbols: inputs.symbols,
            non_text_types: inputs.non_text_types,
        },
        None,
    )
}
pub fn admit_prepared(
    projection: ClassProjection,
    inputs: PreparedInputs<'_>,
) -> Result<(ClassProjection, Vec<SymbolId>), String> {
    admit_common(
        projection,
        CommonInputs {
            source_order: inputs.source_order,
            bodies: BodyRequirements::Prepared(inputs.body_type_requests),
            source_allocation_roster: inputs.source_allocation_roster,
            initializers: inputs.initializers,
            maps: inputs.maps,
            inventory: inputs.inventory,
            symbols: inputs.symbols,
            non_text_types: inputs.non_text_types,
        },
        None,
    )
}
pub fn admit_prepared_retained(
    projection: ClassProjection,
    inputs: PreparedInputs<'_>,
    artifacts: Option<&RequiredTypeArtifacts>,
) -> Result<(ClassProjection, Vec<SymbolId>), String> {
    admit_common(
        projection,
        CommonInputs {
            source_order: inputs.source_order,
            bodies: BodyRequirements::Prepared(inputs.body_type_requests),
            source_allocation_roster: inputs.source_allocation_roster,
            initializers: inputs.initializers,
            maps: inputs.maps,
            inventory: inputs.inventory,
            symbols: inputs.symbols,
            non_text_types: inputs.non_text_types,
        },
        artifacts,
    )
}
fn admit_common(
    mut projection: ClassProjection,
    inputs: CommonInputs<'_>,
    artifacts: Option<&RequiredTypeArtifacts>,
) -> Result<(ClassProjection, Vec<SymbolId>), String> {
    let CommonInputs {
        source_order,
        source_allocation_roster,
        bodies,
        initializers,
        maps,
        inventory,
        symbols,
        non_text_types,
    } = inputs;
    let retained_parents = artifacts.map(|artifacts| artifacts.parents.obtain(&projection.types));
    let fresh_parents;
    let parents = match &retained_parents {
        Some(parents) => parents.as_ref(),
        None => {
            fresh_parents = parent_index::produce(&projection.types);
            &fresh_parents
        }
    };
    let retained: HashSet<_> = inventory
        .fixed
        .iter()
        .filter_map(|(key, _)| match key {
            Key::Type(path) => Some(*path),
            _ => None,
        })
        .collect();
    let mut ancestry = ancestry::Request::new(artifacts);
    // Compatibility callers may supply only a slice. An issued owner must also
    // match that slice; neither public argument can override the current roster.
    let prefix = match (
        artifacts,
        source_allocation_roster,
        retained_parents.as_ref(),
    ) {
        (Some(artifacts), Some(source), Some(parents)) if source.order() == source_order => {
            (*artifacts
                .prefixes
                .obtain(source, &retained, parents, &mut ancestry)?)
            .clone()
        }
        _ => source_prefix::produce(source_order, &retained, parents, &mut ancestry)?,
    };
    let source_prefix::Prefix {
        mut needed,
        mut order,
        mut requests,
    } = prefix;
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
    if let Some(artifacts) = artifacts {
        artifacts.fields.append(&projection.fields, &mut requests);
    } else {
        for field in projection.fields.iter() {
            field_requests::produce(field, &mut requests);
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
    match bodies {
        BodyRequirements::Rich(bodies) => {
            for unit in &bodies.units {
                append_code_requests(&unit.code, &mut requests, symbols)?;
                for helper in &unit.source_helpers {
                    append_code_requests(&helper.code, &mut requests, symbols)?;
                }
            }
        }
        BodyRequirements::Prepared(prepared) => requests.extend_from_slice(prepared),
    }
    for unit in initializers {
        unit.code.requests().append(&mut requests, symbols)?;
    }
    for unit in maps {
        unit.code.requests().append(&mut requests, symbols)?;
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
        ancestry.require(path, parents, &mut needed, &mut order)?;
    }
    projection.types = match artifacts {
        Some(artifacts) => artifacts.selected.obtain(&projection.types, needed),
        None => selected_roster::produce(&projection.types, &needed),
    };
    ancestry.finish();
    Ok((projection, order))
}

pub(crate) fn append_code_requests(
    code: &ResolverProc,
    requests: &mut Vec<SymbolId>,
    symbols: &SymbolTable,
) -> Result<(), String> {
    crate::initializer_code::append_fresh(code, requests, symbols)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn projection() -> ClassProjection {
        ClassProjection {
            type_construction: Default::default(),
            variable_records: Default::default(),
            field_placements: Default::default(),
            procedure_declarations: Default::default(),
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
            fields: vec![std::sync::Arc::new(
                crate::class_projection::FieldProjection {
                    owner: SymbolId::of("/savefile"),
                    declaring_owner: SymbolId::of("/savefile"),
                    name: SymbolId::of("byond_version"),
                    role: crate::class_projection::FieldRole::Assignment,
                    wire_flags: None,
                    intrinsic: true,
                    shared: false,
                    value: crate::initializer_policy::DefaultValue::Scalar(
                        SemanticValue::NumberBits(516f32.to_bits()),
                    ),
                },
            )]
            .into(),
            shared_slot_order: Vec::new().into(),
            procedure_statics: Vec::new().into(),
            runtime_writes: Vec::new().into(),
            chains: Vec::new().into(),
            procedure_membership: std::sync::Arc::from([]),
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
        std::sync::Arc::make_mut(&mut std::sync::Arc::make_mut(&mut field.fields)[0]).name =
            SymbolId::of("eof");
        assert!(admit(field, inputs())
            .unwrap_err()
            .contains("native primitive requires explicit physical class ABI"));
    }
}
