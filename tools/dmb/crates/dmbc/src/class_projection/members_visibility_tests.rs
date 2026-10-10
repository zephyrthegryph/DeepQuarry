use super::*;
struct NoTypes;
impl TypeValuePolicy for NoTypes {
    fn tag(&self, _: SymbolId) -> Result<u8, ProjectionError> {
        Err(ProjectionError::Unsupported("no type constants".into()))
    }
}
#[test]
fn authored_visibility_and_inheritance_match_captured_byond_headers() {
    let bytes = include_bytes!("../../../../fixtures/native_template.bin");
    let mut dmb = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
    let mut symbols = crate::engine::EngineSnapshot::from_bytes(bytes, 1)
        .unwrap()
        .symbols()
        .clone();
    let mut pool = crate::composition::StringIndex::build(&dmb).unwrap();
    let obj = symbols.intern("/obj").unwrap();
    let atom = symbols.intern("/atom").unwrap();
    let invisibility = symbols.intern("invisibility").unwrap();
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
        ("/obj/hidden_probe", obj_id),
        ("/obj/hidden_probe/child", dmb.classes.len() as u32),
        ("/obj/hidden_probe/reset", dmb.classes.len() as u32),
        ("/obj/visible_probe", obj_id),
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
                SymbolId::of("/obj/hidden_probe")
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
    let fields = [
        (
            ids[0].0,
            DefaultValue::Scalar(SemanticValue::NumberBits(101f32.to_bits())),
        ),
        (
            ids[2].0,
            DefaultValue::Scalar(SemanticValue::NumberBits(0f32.to_bits())),
        ),
        (
            ids[3].0,
            DefaultValue::Scalar(SemanticValue::NumberBits(0f32.to_bits())),
        ),
    ]
    .into_iter()
    .map(|(owner, value)| {
        std::sync::Arc::new(FieldProjection {
            owner,
            declaring_owner: atom,
            name: invisibility,
            role: FieldRole::Assignment,
            wire_flags: None,
            intrinsic: true,
            shared: false,
            value,
        })
    })
    .collect::<Vec<_>>();
    let projection = ClassProjection {
        shared_slot_order: Arc::from([]),
        procedure_statics: Arc::from([]),
        runtime_writes: Arc::from([]),
        tree_identity: 0,
        occurrence_count: 0,
        types: types.into(),
        fields: fields.into(),
        chains: Arc::from([]),
        procedure_declarations: Default::default(),
    };
    let tables = dm_link::LinkTables::build(inventory).unwrap();
    materialize_members(&mut dmb, &projection, &tables, &symbols, &NoTypes).unwrap();
    headers::finalize_headers(&mut dmb, bytes, &projection, &tables, &symbols).unwrap();
    let oracle = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/native_compiler/type_visibility/probe.native.bin"
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
            dmb.classes[id as usize].is_normally_visible(),
            expected.is_normally_visible(),
            "{:?}",
            path
        );
        let values = |image: &byond_dmb::dmb::Dmb, class: usize| {
            image
                .class_builtin_overrides(class)
                .unwrap_or_default()
                .into_iter()
                .filter(|row| image.string(row.name_string_id) == Some(b"invisibility"))
                .map(|row| row.value)
                .collect::<Vec<_>>()
        };
        let expected_id = oracle
            .classes
            .iter()
            .position(|class| oracle.string(class.path_string_id()) == Some(path))
            .unwrap();
        assert_eq!(values(&dmb, id as usize), values(&oracle, expected_id));
    }
}
