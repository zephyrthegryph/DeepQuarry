use super::*;
struct NoTypes;
impl TypeValuePolicy for NoTypes {
    fn tag(&self, _: SymbolId) -> Result<u8, ProjectionError> {
        Err(ProjectionError::Unsupported("no type constants".into()))
    }
}
#[test]
fn captured_matrix_headers_and_null_reset_match_full_projection_writer() {
    let bytes = include_bytes!("../../../../fixtures/native_template.bin");
    let mut dmb = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
    let mut symbols = crate::engine::EngineSnapshot::from_bytes(bytes, 1)
        .unwrap()
        .symbols()
        .clone();
    let mut pool = crate::composition::StringIndex::build(&dmb).unwrap();
    let obj = symbols.intern("/obj").unwrap();
    let atom = symbols.intern("/atom").unwrap();
    let transform = symbols.intern("transform").unwrap();
    let obj_id = dmb
        .classes
        .iter()
        .position(|class| dmb.string(class.path_string_id()) == Some(b"/obj"))
        .unwrap() as u32;
    let mut inventory = dm_link::LinkInventory::default();
    let mut types = vec![TypeProjection {
        path: obj,
        parent: None,
    }];
    let mut ids = Vec::new();
    for (path, parent) in [
        ("/obj/matrix_probe", obj_id),
        ("/obj/matrix_probe/child", dmb.classes.len() as u32),
        ("/obj/matrix_probe/reset", dmb.classes.len() as u32),
        ("/obj/identity_probe", obj_id),
    ] {
        let symbol = symbols.intern(path).unwrap();
        let mut class = dmb.classes[obj_id as usize].clone();
        class.initial_ids[0] = pool.intern(&mut dmb, path.as_bytes()).unwrap();
        class.initial_ids[1] = parent;
        let id = dmb.classes.len() as u32;
        dmb.classes.push(class);
        ids.push((symbol, id));
        types.push(TypeProjection {
            path: symbol,
            parent: Some(if parent == obj_id {
                obj
            } else {
                SymbolId::of("/obj/matrix_probe")
            }),
        });
    }
    for (symbol, id) in std::iter::once((obj, obj_id)).chain(ids.iter().copied()) {
        inventory.entries.push(dm_link::Entry {
            key: Key::Type(symbol),
            content: Arc::<[u8]>::from([]).into(),
        });
        inventory.fixed.push((Key::Type(symbol), id));
        inventory
            .spellings
            .push((symbol, Arc::from(symbols.text(symbol).unwrap().as_bytes())));
    }
    let matrix = [
        2f32.to_bits(),
        0,
        3f32.to_bits(),
        0,
        4f32.to_bits(),
        5f32.to_bits(),
    ];
    let fields = [
        (ids[0].0, DefaultValue::Transform(matrix)),
        (ids[2].0, DefaultValue::Scalar(SemanticValue::Null)),
        (
            ids[3].0,
            DefaultValue::Transform([1f32.to_bits(), 0, 0, 0, 1f32.to_bits(), 0]),
        ),
    ]
    .into_iter()
    .map(|(owner, value)| {
        std::sync::Arc::new(FieldProjection {
            owner,
            declaring_owner: atom,
            name: transform,
            role: FieldRole::Assignment,
            wire_flags: None,
            intrinsic: true,
            shared: false,
            value,
        })
    })
    .collect::<Vec<_>>();
    let projection = ClassProjection {
        variable_records: Default::default(),
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
    headers::finalize_headers(&mut dmb, bytes, &projection, &tables, &symbols).unwrap();
    let oracle = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/native_compiler/matrix_transform/probe.native.bin"
    ))
    .unwrap();
    for (symbol, id) in ids {
        let path = symbols.text(symbol).unwrap().as_bytes();
        let expected = oracle
            .classes
            .iter()
            .find(|class| oracle.string(class.path_string_id()) == Some(path))
            .unwrap();
        assert_eq!(
            (
                dmb.classes[id as usize].transform_flag,
                dmb.classes[id as usize].transform
            ),
            (expected.transform_flag, expected.transform)
        );
    }
}
