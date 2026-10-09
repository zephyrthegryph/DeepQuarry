use super::*;
#[test]
fn retained_parent_projection_preserves_native_header_and_physical_identity() {
    let mut dmb =
        byond_dmb::dmb::Dmb::from_bytes(include_bytes!("../../../fixtures/native_template.bin"))
            .unwrap();
    let mut symbols = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap()
    .symbols()
    .clone();
    let mut inventory = dm_link::LinkInventory::default();
    let mut ids = BTreeMap::new();
    for path in ["/client", "/datum"] {
        let index = dmb
            .classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(path.as_bytes()))
            .unwrap() as u32;
        let symbol = symbols.intern(path).unwrap();
        ids.insert(path, (symbol, index));
        inventory
            .spellings
            .push((symbol, Arc::from(path.as_bytes())));
        inventory.entries.push(dm_link::Entry {
            key: Key::Type(symbol),
            content: Arc::<[u8]>::from([]).into(),
        });
        inventory.fixed.push((Key::Type(symbol), index));
    }
    let (client, client_index) = ids["/client"];
    let (datum, datum_index) = ids["/datum"];
    let original = dmb.classes[client_index as usize].clone();
    let count = dmb.classes.len();
    let projection = ClassProjection {
        procedure_declarations: Default::default(),
        shared_slot_order: Arc::from([]),
        procedure_statics: Arc::from([]),
        runtime_writes: Arc::from([]),
        tree_identity: 0,
        occurrence_count: 0,
        fields: Arc::from([]),
        chains: Arc::from([]),
        types: Arc::from([TypeProjection {
            path: client,
            parent: Some(datum),
        }]),
    };
    let tables = dm_link::LinkTables::build(inventory).unwrap();
    materialize_types(&mut dmb, &projection, &tables, &symbols).unwrap();
    let mut expected = original;
    expected.initial_ids[1] = datum_index;
    assert_eq!(dmb.classes[client_index as usize], expected);
    assert_eq!(dmb.classes.len(), count);
}
#[test]
fn procedure_literal_default_uses_exact_frozen_procedure_table_index() {
    let bytes = include_bytes!("../../../fixtures/native_template.bin");
    let engine = crate::engine::EngineSnapshot::from_bytes(bytes, 1).unwrap();
    let mut symbols = engine.symbols().clone();
    let layout = engine
        .procedure_layouts()
        .iter()
        .find(|layout| layout.name.is_some() && layout.kind == MemberKind::Proc)
        .unwrap();
    let identity = dm_ir::ProcedureIdentity {
        owner: layout.owner,
        name: layout.name.unwrap(),
        verb: false,
        occurrence: 0,
    };
    let callable = Key::Proc {
        owner: identity.owner,
        name: identity.name,
        occurrence: 0,
    };
    let root = symbols.intern("/").unwrap();
    let name = symbols.intern("saved_callback").unwrap();
    let variable = Key::Variable { owner: root, name };
    let mut dmb = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
    let footer_index = dmb.lists[dmb.variable_footer as usize].len() as u32 / 2;
    let mut inventory = dm_link::LinkInventory::default();
    for id in [root, name, identity.owner, identity.name] {
        inventory
            .spellings
            .push((id, Arc::from(symbols.text(id).unwrap().as_bytes())));
    }
    for key in [variable, callable] {
        inventory.entries.push(dm_link::Entry {
            key,
            content: Arc::<[u8]>::from([]).into(),
        });
    }
    inventory.fixed = vec![(variable, footer_index), (callable, layout.wire_proc)];
    let tables = dm_link::LinkTables::build(inventory).unwrap();
    let projection = ClassProjection {
        procedure_declarations: Default::default(),
        shared_slot_order: Arc::from([variable]),
        procedure_statics: Arc::from([]),
        runtime_writes: Arc::from([]),
        tree_identity: 0,
        occurrence_count: 1,
        types: Arc::from([]),
        chains: Arc::from([]),
        fields: Arc::from([FieldProjection {
            owner: root,
            declaring_owner: root,
            name,
            role: FieldRole::Declaration,
            wire_flags: Some(1),
            intrinsic: false,
            shared: true,
            value: DefaultValue::Scalar(SemanticValue::Procedure(identity)),
        }]),
    };
    materialize_members(&mut dmb, &projection, &tables, &symbols, &NoTypes).unwrap();
    let record_id = dmb.lists[dmb.variable_footer as usize][footer_index as usize * 2];
    let record = &dmb.variables[record_id as usize];
    assert_eq!((record.kind, record.value), (38, layout.wire_proc));
    assert_eq!(dmb.string(record.name), Some(b"saved_callback".as_slice()));
    dmb.validate_references().unwrap();
}
#[test]
fn indexed_client_headers_preserve_owner_and_repeated_write_effects() {
    let mut symbols = dm_ir::SymbolTable::default();
    let parent = symbols.intern("/client").unwrap();
    let child = symbols.intern("/client/child").unwrap();
    let unrelated = symbols.intern("/datum/unrelated").unwrap();
    let name = symbols.intern("control_freak").unwrap();
    let field = |owner, value, intrinsic| FieldProjection {
        owner,
        declaring_owner: parent,
        name,
        role: FieldRole::Assignment,
        wire_flags: None,
        intrinsic,
        shared: false,
        value: DefaultValue::Scalar(SemanticValue::NumberBits((value as f32).to_bits())),
    };
    let fields = [
        field(child, 1, true),
        field(parent, 2, true),
        field(unrelated, 7, true),
        field(child, 3, true),
        field(parent, 4, true),
        field(child, 6, false),
    ];
    let mut dmb = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../fixtures/translation/client_header_probe/feature_load_ext.native.bin"
    ))
    .unwrap();
    let directives = client_header_directives(&fields, &[parent, child], &symbols).unwrap();
    crate::client_projection::apply(&mut dmb, &directives);
    assert_eq!(dmb.world.control, 3);
    let directives = client_header_directives(&fields, &[child, parent], &symbols).unwrap();
    crate::client_projection::apply(&mut dmb, &directives);
    assert_eq!(dmb.world.control, 4);
}
struct NoTypes;
impl TypeValuePolicy for NoTypes {
    fn tag(&self, _: SymbolId) -> Result<u8, ProjectionError> {
        Err(ProjectionError::Unsupported("no type values".into()))
    }
}
#[test]
fn opaque_intrinsic_name_and_layer_use_native_records_without_syntax_flags() {
    let bytes = include_bytes!(
        "../../../fixtures/translation/client_header_probe/feature_load_ext.native.bin"
    );
    let engine = crate::engine::EngineSnapshot::from_bytes(bytes, 1).unwrap();
    let mut symbols = engine.symbols().clone();
    let owner = symbols.intern("/obj").unwrap();
    let name = symbols.intern("name").unwrap();
    let layer = symbols.intern("layer").unwrap();
    let projection = ClassProjection {
        procedure_declarations: Default::default(),
        shared_slot_order: Arc::from([]),
        procedure_statics: Arc::from([]),
        runtime_writes: Arc::from([]),
        tree_identity: 0,
        occurrence_count: 0,
        types: Arc::from([]),
        chains: Arc::from([]),
        fields: Arc::from([
            FieldProjection {
                owner,
                declaring_owner: owner,
                name,
                role: FieldRole::Assignment,
                wire_flags: None,
                intrinsic: true,
                shared: false,
                value: DefaultValue::Scalar(SemanticValue::Text(Arc::from(
                    b"source name".as_slice(),
                ))),
            },
            FieldProjection {
                owner,
                declaring_owner: owner,
                name: layer,
                role: FieldRole::Assignment,
                wire_flags: None,
                intrinsic: true,
                shared: false,
                value: DefaultValue::Scalar(SemanticValue::NumberBits(3.5f32.to_bits())),
            },
        ]),
    };
    let mut dmb = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
    let tables = dm_link::LinkTables::build(Default::default()).unwrap();
    materialize_members(&mut dmb, &projection, &tables, &symbols, &NoTypes).unwrap();
    let record = dmb
        .classes
        .iter()
        .find(|class| dmb.string(class.path_string_id()) == Some(b"/obj".as_slice()))
        .unwrap();
    assert_eq!(
        dmb.string(record.initial_ids[2]),
        Some(b"source name".as_slice())
    );
    assert_eq!(record.layer_bits, 3.5f32.to_bits());
    dmb.validate_references().unwrap();
}

#[test]
fn source_modifiers_do_not_equal_wire_flags_or_slot_indexes() {
    let root = SymbolId::of("/");
    let datum = SymbolId::of("/datum/x");
    assert_eq!(wire_flags(2, datum), Ok((3, true)));
    assert_eq!(wire_flags(4, datum), Ok((4, false)));
    assert_eq!(wire_flags(0, root), Ok((1, true)));
    assert!(wire_flags(16, datum).is_err());
}
#[test]
fn ordinary_source_root_matches_native_datum_parent_prototype() {
    let template = include_bytes!("../../../fixtures/native_template.bin");
    let captured = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../fixtures/phase1/native_root_procpath/empty.native.bin"
    ))
    .unwrap();
    let mut dmb = byond_dmb::dmb::Dmb::from_bytes(template).unwrap();
    let mut symbols = crate::engine::EngineSnapshot::from_bytes(template, 1)
        .unwrap()
        .symbols()
        .clone();
    let path = symbols.intern("/standalone_empty").unwrap();
    let datum = symbols.intern("/datum").unwrap();
    let parent = dmb
        .classes
        .iter()
        .position(|class| dmb.string(class.path_string_id()) == Some(b"/datum".as_slice()))
        .unwrap() as u32;
    let index = dmb.classes.len() as u32;
    let mut inventory = dm_link::LinkInventory::default();
    inventory
        .spellings
        .push((path, Arc::from(b"/standalone_empty".as_slice())));
    inventory.entries.push(dm_link::Entry {
        key: Key::Type(path),
        content: Arc::<[u8]>::from([]).into(),
    });
    inventory
        .reserved_prefixes
        .insert(dm_link::Table::Type, index);
    inventory
        .append_orders
        .insert(dm_link::Table::Type, vec![Key::Type(path)]);
    let tables = dm_link::LinkTables::build(inventory).unwrap();
    let projection = ClassProjection {
        procedure_declarations: Default::default(),
        shared_slot_order: Arc::from([]),
        procedure_statics: Arc::from([]),
        runtime_writes: Arc::from([]),
        tree_identity: 0,
        occurrence_count: 0,
        fields: Arc::from([]),
        chains: Arc::from([]),
        types: Arc::from([TypeProjection {
            path,
            parent: Some(datum),
        }]),
    };
    materialize_types(&mut dmb, &projection, &tables, &symbols).unwrap();
    let mut actual = dmb.classes[index as usize].clone();
    let expected = captured.classes[24].clone();
    assert_eq!(actual.initial_ids[1], parent);
    assert_eq!(
        captured.string(captured.classes[expected.initial_ids[1] as usize].path_string_id()),
        Some(b"/datum".as_slice())
    );
    actual.initial_ids[1] = expected.initial_ids[1];
    for slot in [0, 2] {
        assert_eq!(
            dmb.string(actual.initial_ids[slot]),
            captured.string(expected.initial_ids[slot])
        );
        actual.initial_ids[slot] = expected.initial_ids[slot];
    }
    assert_eq!(dmb.string(actual.text), captured.string(expected.text));
    actual.text = expected.text;
    assert_eq!(actual, expected);
}
