use super::*;
struct NoTypes;
impl TypeValuePolicy for NoTypes {
    fn tag(&self, _: SymbolId) -> Result<u8, ProjectionError> {
        Err(ProjectionError::Unsupported("no type constants".into()))
    }
}
#[test]
fn fractional_mob_settings_and_bounds_match_captured_byond_records() {
    let bytes = include_bytes!("../../../../fixtures/native_template.bin");
    let mut dmb = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
    let mut symbols = crate::engine::EngineSnapshot::from_bytes(bytes, 1)
        .unwrap()
        .symbols()
        .clone();
    let mut pool = crate::composition::StringIndex::build(&dmb).unwrap();
    let mob = symbols.intern("/mob").unwrap();
    let mob_id = dmb
        .classes
        .iter()
        .position(|class| dmb.string(class.path_string_id()) == Some(b"/mob"))
        .unwrap() as u32;
    let mut inventory = dm_link::LinkInventory::default();
    let mut types = vec![TypeProjection {
        path: mob,
        parent: None,
    }];
    let mut ids = Vec::new();
    for (path, parent) in [
        ("/mob/sight_fraction", mob_id),
        ("/mob/dark_fraction", mob_id),
        ("/mob/invisible_fraction", mob_id),
        ("/mob/invisible_high", mob_id),
        ("/mob/dark_high", mob_id),
    ] {
        let symbol = symbols.intern(path).unwrap();
        let mut class = dmb.classes[mob_id as usize].clone();
        class.initial_ids[0] = pool.intern(&mut dmb, path.as_bytes()).unwrap();
        class.initial_ids[1] = parent;
        let id = dmb.classes.len() as u32;
        dmb.classes.push(class);
        ids.push((symbol, id));
        types.push(TypeProjection {
            path: symbol,
            parent: Some(if parent == mob_id { mob } else { ids[0].0 }),
        });
    }
    for (symbol, id) in std::iter::once((mob, mob_id)).chain(ids.iter().copied()) {
        inventory.entries.push(dm_link::Entry {
            key: Key::Type(symbol),
            content: Arc::<[u8]>::from([]).into(),
        });
        inventory.fixed.push((Key::Type(symbol), id));
        inventory
            .spellings
            .push((symbol, Arc::from(symbols.text(symbol).unwrap().as_bytes())));
    }
    let mut fields = Vec::new();
    for (owner, name, number) in [
        (ids[0].0, "sight", 1.5),
        (ids[1].0, "see_in_dark", 1.5),
        (ids[2].0, "see_invisible", 1.5),
        (ids[3].0, "see_invisible", 101.0),
        (ids[4].0, "see_in_dark", 1000000.0),
    ] {
        fields.push(Arc::new(FieldProjection {
            owner,
            declaring_owner: mob,
            name: symbols.intern(name).unwrap(),
            role: FieldRole::Assignment,
            wire_flags: None,
            intrinsic: true,
            shared: false,
            value: DefaultValue::Scalar(SemanticValue::NumberBits((number as f32).to_bits())),
        }));
    }
    let projection = ClassProjection {
        field_placements: Default::default(),
        shared_slot_order: Arc::from([]),
        procedure_statics: Arc::from([]),
        runtime_writes: Arc::from([]),
        tree_identity: 0,
        occurrence_count: 0,
        types: types.into(),
        fields: fields.into(),
        chains: Arc::from([]),
        procedure_membership: Arc::from([]),
        procedure_declarations: Default::default(),
    };
    let tables = dm_link::LinkTables::build(inventory).unwrap();
    materialize_members(&mut dmb, &projection, &tables, &symbols, &NoTypes).unwrap();
    let oracle = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/native_compiler/mob_numeric_settings/probe.native.bin"
    ))
    .unwrap();
    for (symbol, class) in &ids {
        let record = dmb
            .mobs
            .iter()
            .find(|record| record.class == *class)
            .unwrap();
        let path = symbols.text(*symbol).unwrap().as_bytes();
        let expected_class = oracle
            .classes
            .iter()
            .position(|class| oracle.string(class.path_string_id()) == Some(path))
            .unwrap() as u32;
        let expected = oracle
            .mobs
            .iter()
            .find(|record| record.class == expected_class)
            .unwrap();
        assert_eq!(record.extended_sight, expected.extended_sight, "{path:?}");
        assert_eq!(record.sight_bits(), expected.sight_bits(), "{path:?}");
        assert_eq!(
            record.see_in_dark_setting(),
            expected.see_in_dark_setting(),
            "{path:?}"
        );
        assert_eq!(
            record.see_invisible_setting(),
            expected.see_invisible_setting(),
            "{path:?}"
        );
        let settings = |image: &byond_dmb::dmb::Dmb, class: u32| {
            image
                .class_builtin_overrides(class as usize)
                .unwrap_or_default()
                .into_iter()
                .filter(|row| {
                    matches!(
                        image.string(row.name_string_id),
                        Some(b"sight" | b"see_in_dark" | b"see_invisible")
                    )
                })
                .map(|row| {
                    (
                        image.string(row.name_string_id).unwrap().to_vec(),
                        row.value,
                    )
                })
                .collect::<Vec<_>>()
        };
        assert_eq!(
            settings(&dmb, *class),
            settings(&oracle, expected_class),
            "{path:?}"
        );
    }
}
