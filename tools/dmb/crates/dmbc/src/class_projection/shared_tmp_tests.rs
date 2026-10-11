use super::*;
use byond_dmb::dmb::Dmb;

struct NoTypes;
impl TypeValuePolicy for NoTypes {
    fn tag(&self, _: SymbolId) -> Result<u8, ProjectionError> {
        Err(ProjectionError::Unsupported(
            "fixture contains only numbers".into(),
        ))
    }
}
fn globals(dmb: &Dmb) -> BTreeMap<Vec<u8>, u32> {
    dmb.global_variable_flags()
        .unwrap()
        .into_iter()
        .map(|(id, flags)| {
            (
                dmb.string(dmb.variables[id as usize].name)
                    .unwrap()
                    .to_vec(),
                flags,
            )
        })
        .collect()
}
fn fields(dmb: &Dmb, owner: &[u8]) -> BTreeMap<Vec<u8>, u32> {
    let index = dmb
        .classes
        .iter()
        .position(|class| dmb.string(class.path_string_id()) == Some(owner))
        .unwrap();
    dmb.class_variable_declarations(index)
        .unwrap()
        .into_iter()
        .map(|(id, flags)| {
            (
                dmb.string(dmb.variables[id as usize].name)
                    .unwrap()
                    .to_vec(),
                flags,
            )
        })
        .collect()
}
#[test]
fn captured_byond_tmp_flags_differ_between_class_declarations_and_shared_slots() {
    let expected = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/native_compiler/shared_tmp_modifiers/probe.native.bin"
    ))
    .unwrap();
    let expected_globals = globals(&expected);
    let expected_fields = fields(&expected, b"/datum/tmp_modifiers");
    // These are independent captured wire domains, not a guessed bit rewrite.
    assert_eq!(expected_fields[b"instance_tmp".as_slice()], 4);
    assert_eq!(expected_fields[b"shared_tmp".as_slice()], 5);
    assert_eq!(expected_fields[b"constant_tmp".as_slice()], 7);
    for (name, flags) in [
        ("root_tmp", 1),
        ("root_shared_tmp", 1),
        ("root_const_tmp", 3),
        ("shared_tmp", 1),
        ("constant_tmp", 3),
        ("proc_static", 1),
    ] {
        assert_eq!(expected_globals[name.as_bytes()], flags);
    }
    let bytes = include_bytes!("../../../../fixtures/native_template.bin");
    let engine = crate::engine::EngineSnapshot::from_bytes(bytes, 1).unwrap();
    let mut symbols = engine.symbols().clone();
    let root = symbols.intern("/").unwrap();
    let datum = symbols.intern("/datum").unwrap();
    let mut actual = Dmb::from_bytes(bytes).unwrap();
    let mut inventory = dm_link::LinkInventory::default();
    let mut projections = Vec::new();
    let mut shared_order = Vec::new();
    for (owner, name, modifiers) in [
        (root, "root_tmp", 4),
        (root, "root_shared_tmp", 12),
        (root, "root_const_tmp", 6),
        (datum, "instance_tmp", 4),
        (datum, "shared_tmp", 12),
        (datum, "constant_tmp", 6),
    ] {
        let name = symbols.intern(name).unwrap();
        let (flags, shared) = wire_flags(modifiers, owner).unwrap();
        if shared {
            let key = Key::Variable { owner, name };
            inventory.entries.push(dm_link::Entry {
                key,
                content: Arc::<[u8]>::from([]).into(),
            });
            inventory.fixed.push((
                key,
                actual.variables.len() as u32 + projections.len() as u32,
            ));
            shared_order.push(key);
        }
        projections.push(std::sync::Arc::new(FieldProjection {
            owner,
            declaring_owner: owner,
            name,
            role: FieldRole::Declaration,
            wire_flags: Some(flags),
            intrinsic: false,
            shared,
            value: DefaultValue::Scalar(SemanticValue::NumberBits(1f32.to_bits())),
        }));
    }
    let local = dm_ir::ProcedureStaticIdentity {
        procedure: dm_ir::ProcedureIdentity {
            owner: datum,
            name: symbols.intern("probe").unwrap(),
            verb: false,
            occurrence: 0,
        },
        name: symbols.intern("proc_static").unwrap(),
    };
    let local_key = Key::ProcedureStatic(local);
    inventory.entries.push(dm_link::Entry {
        key: local_key,
        content: Arc::<[u8]>::from([]).into(),
    });
    inventory.fixed.push((
        local_key,
        actual.variables.len() as u32 + projections.len() as u32,
    ));
    let names: std::collections::BTreeSet<_> = projections
        .iter()
        .flat_map(|field| [field.owner, field.name])
        .chain([local.procedure.owner, local.procedure.name, local.name])
        .collect();
    for name in names {
        inventory
            .spellings
            .push((name, Arc::from(symbols.text(name).unwrap().as_bytes())));
    }
    let tables = dm_link::LinkTables::build(inventory).unwrap();
    let projection = ClassProjection {
        source_features: Default::default(),
        type_construction: Default::default(),
        variable_records: Default::default(),
        field_placements: Default::default(),
        procedure_declarations: Default::default(),
        shared_slot_order: {
            shared_order.push(local_key);
            shared_order.into()
        },
        procedure_statics: Arc::from([ProcedureStaticProjection {
            identity: local,
            wire_flags: 5,
            value: DefaultValue::Scalar(SemanticValue::NumberBits(7f32.to_bits())),
            source_ordinal: 0,
        }]),
        runtime_writes: Arc::from([]),
        tree_identity: 0,
        occurrence_count: 0,
        types: Arc::from([]),
        chains: Arc::from([]),
        procedure_membership: Arc::from([]),
        fields: projections.into(),
    };
    materialize_members(&mut actual, &projection, &tables, &symbols, &NoTypes).unwrap();
    let actual_globals = globals(&actual);
    for name in [
        "root_tmp",
        "root_shared_tmp",
        "root_const_tmp",
        "shared_tmp",
        "constant_tmp",
        "proc_static",
    ] {
        assert_eq!(
            actual_globals[name.as_bytes()],
            expected_globals[name.as_bytes()],
            "shared slot {name}"
        );
    }
    let actual_fields = fields(&actual, b"/datum");
    for name in ["instance_tmp", "shared_tmp", "constant_tmp"] {
        assert_eq!(
            actual_fields[name.as_bytes()],
            expected_fields[name.as_bytes()],
            "class declaration {name}"
        );
    }
    actual.validate_references().unwrap();
}
