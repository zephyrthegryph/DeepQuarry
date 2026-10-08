//! Shared routing of source namespaces and intrinsic configuration fields.
use super::*;
use dm_ir::SymbolTable;

pub(super) fn separate_type_record(owner: SymbolId) -> bool {
    owner == SymbolId::of("/") || owner == SymbolId::of("/world")
}

pub(super) fn client_configuration_order(
    projection: &ClassProjection,
    tables: &dm_link::LinkTables,
) -> Result<Vec<SymbolId>, ProjectionError> {
    let types = projection
        .types
        .iter()
        .filter_map(|ty| {
            tables
                .index(Key::Type(ty.path))
                .map(|ordinal| (ty.path, ty.parent, ordinal))
        })
        .collect::<Vec<_>>();
    crate::client_projection::configuration_order(SymbolId::of("/client"), &types)
        .map_err(|error| ProjectionError::Unsupported(format!("client order {error:?}")))
}

/// Only positively classified intrinsic fields use the separate configuration
/// writers. Other fields, including unknown savefile names, stay class fields.
pub(super) fn separate_intrinsic_field(
    field: &FieldProjection,
    client_owners: &HashSet<SymbolId>,
    symbols: &SymbolTable,
) -> Result<bool, ProjectionError> {
    if !field.intrinsic {
        return Ok(false);
    }
    if field.owner == SymbolId::of("/world") {
        return Ok(true);
    }
    if field.owner == SymbolId::of("/savefile") && field.name == SymbolId::of("byond_version") {
        return Ok(true);
    }
    if !client_owners.contains(&field.owner) {
        return Ok(false);
    }
    let name = symbols.text(field.name).ok_or_else(|| {
        ProjectionError::Unsupported(format!(
            "missing configuration field spelling {:?}",
            field.name
        ))
    })?;
    Ok(crate::client_projection::is_header_field(name)
        && !(name == "preload_rsc"
            && matches!(&field.value, DefaultValue::Scalar(SemanticValue::Text(_)))))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exact_savefile_route_never_skips_unknown_fields() {
        let mut symbols = SymbolTable::default();
        let name = symbols.intern("byond_version").unwrap();
        let mut field = FieldProjection {
            owner: SymbolId::of("/savefile"),
            declaring_owner: SymbolId::of("/savefile"),
            name,
            role: FieldRole::Assignment,
            wire_flags: None,
            intrinsic: true,
            shared: false,
            value: DefaultValue::Scalar(SemanticValue::Null),
        };
        assert!(separate_intrinsic_field(&field, &HashSet::new(), &symbols).unwrap());
        field.name = symbols.intern("unrecognized").unwrap();
        assert!(!separate_intrinsic_field(&field, &HashSet::new(), &symbols).unwrap());
        field.name = name;
        field.intrinsic = false;
        assert!(!separate_intrinsic_field(&field, &HashSet::new(), &symbols).unwrap());
    }
    #[test]
    fn client_text_preload_keeps_exact_class_override_exception() {
        let mut symbols = SymbolTable::default();
        let owner = symbols.intern("/client/subtype").unwrap();
        let name = symbols.intern("preload_rsc").unwrap();
        let clients = HashSet::from([owner]);
        let mut field = FieldProjection {
            owner,
            declaring_owner: owner,
            name,
            role: FieldRole::Assignment,
            wire_flags: None,
            intrinsic: true,
            shared: false,
            value: DefaultValue::Scalar(SemanticValue::Text(Arc::from(&b"asset.rsc"[..]))),
        };
        assert!(!separate_intrinsic_field(&field, &clients, &symbols).unwrap());
        field.value = DefaultValue::Scalar(SemanticValue::NumberBits(1.0_f32.to_bits()));
        assert!(separate_intrinsic_field(&field, &clients, &symbols).unwrap());
        assert!(!separate_intrinsic_field(&field, &HashSet::new(), &symbols).unwrap());
    }
}
