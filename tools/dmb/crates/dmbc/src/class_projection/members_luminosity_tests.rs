use super::*;
struct NoTypes;
impl TypeValuePolicy for NoTypes {
    fn tag(&self, _: SymbolId) -> Result<u8, ProjectionError> {
        Err(ProjectionError::Unsupported(
            "no type constants in fixture".into(),
        ))
    }
}

#[test]
fn authored_baseline_luminosity_and_inherited_selector_match_pinned_byond() {
    let bytes = include_bytes!("../../../../fixtures/native_template.bin");
    let mut dmb = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
    // The writer also consults captured engine field spellings while creating
    // world/default metadata; a source-only three-name dictionary is incomplete.
    let mut symbols = crate::engine::EngineSnapshot::from_bytes(bytes, 1)
        .unwrap()
        .symbols()
        .clone();
    let area = symbols.intern("/area").unwrap();
    let child = symbols.intern("/area/fixture/child").unwrap();
    let luminosity = symbols.intern("luminosity").unwrap();
    let area_id = dmb
        .classes
        .iter()
        .position(|class| dmb.string(class.path_string_id()) == Some(b"/area"))
        .unwrap() as u32;
    let mut record = dmb.classes[area_id as usize].clone();
    let mut pool = crate::composition::StringIndex::build(&dmb).unwrap();
    record.initial_ids[0] = pool.intern(&mut dmb, b"/area/fixture/child").unwrap();
    record.initial_ids[1] = area_id;
    let child_id = dmb.classes.len() as u32;
    dmb.classes.push(record);
    let baseline = f32::from(dmb.classes[area_id as usize].luminosity());
    let projection = ClassProjection {
        shared_slot_order: Arc::from([]),
        procedure_statics: Arc::from([]),
        runtime_writes: Arc::from([]),
        tree_identity: 0,
        occurrence_count: 0,
        types: vec![
            TypeProjection {
                path: area,
                parent: None,
            },
            TypeProjection {
                path: child,
                parent: Some(area),
            },
        ]
        .into(),
        fields: vec![std::sync::Arc::new(FieldProjection {
            owner: area,
            declaring_owner: area,
            name: luminosity,
            role: FieldRole::Assignment,
            wire_flags: None,
            intrinsic: true,
            shared: false,
            value: DefaultValue::Scalar(SemanticValue::NumberBits(baseline.to_bits())),
        })]
        .into(),
        chains: Arc::from([]),
        procedure_membership: Arc::from([]),
        procedure_declarations: Default::default(),
    };
    let mut inventory = dm_link::LinkInventory::default();
    for (path, id) in [(area, area_id), (child, child_id)] {
        inventory
            .spellings
            .push((path, Arc::from(symbols.text(path).unwrap().as_bytes())));
        inventory.entries.push(dm_link::Entry {
            key: Key::Type(path),
            content: Arc::<[u8]>::from([]).into(),
        });
        inventory.fixed.push((Key::Type(path), id));
    }
    let tables = dm_link::LinkTables::build(inventory).unwrap();
    materialize_members(&mut dmb, &projection, &tables, &symbols, &NoTypes).unwrap();
    headers::finalize_headers(&mut dmb, bytes, &projection, &tables, &symbols).unwrap();
    let oracle = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/explicit_type_field.native.bin"
    ))
    .unwrap();
    for path in [b"/area".as_slice(), b"/area/fixture/child"] {
        let selectors = |image: &byond_dmb::dmb::Dmb| {
            let id = image
                .classes
                .iter()
                .position(|class| image.string(class.path_string_id()) == Some(path))
                .unwrap();
            image
                .class_builtin_overrides(id)
                .unwrap_or_default()
                .into_iter()
                .filter(|field| image.string(field.name_string_id) == Some(b"luminosity"))
                .map(|field| field.value.clone())
                .collect::<Vec<_>>()
        };
        assert_eq!(selectors(&dmb), selectors(&oracle));
    }
}
