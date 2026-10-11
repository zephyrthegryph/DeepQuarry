use super::*;
struct NoTypes;
impl TypeValuePolicy for NoTypes {
    fn tag(&self, _: SymbolId) -> Result<u8, ProjectionError> {
        Err(ProjectionError::Unsupported("no type constants".into()))
    }
}
#[test]
fn authored_gender_and_inheritance_match_captured_byond_headers() {
    let bytes = include_bytes!("../../../../fixtures/native_template.bin");
    let mut dmb = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
    let mut symbols = crate::engine::EngineSnapshot::from_bytes(bytes, 1)
        .unwrap()
        .symbols()
        .clone();
    let mut pool = crate::composition::StringIndex::build(&dmb).unwrap();
    let obj = symbols.intern("/obj").unwrap();
    let atom = symbols.intern("/atom").unwrap();
    let gender = symbols.intern("gender").unwrap();
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
        ("/obj/gender_probe", obj_id),
        ("/obj/gender_probe/child", dmb.classes.len() as u32),
        ("/obj/gender_probe/female", dmb.classes.len() as u32),
        ("/obj/gender_probe/reset", dmb.classes.len() as u32),
        ("/obj/gender_probe/plural", dmb.classes.len() as u32),
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
                SymbolId::of("/obj/gender_probe")
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
            DefaultValue::Scalar(SemanticValue::Text(Arc::from(b"male".as_slice()))),
        ),
        (
            ids[2].0,
            DefaultValue::Scalar(SemanticValue::Text(Arc::from(b"female".as_slice()))),
        ),
        (
            ids[3].0,
            DefaultValue::Scalar(SemanticValue::Text(Arc::from(b"neuter".as_slice()))),
        ),
        (
            ids[4].0,
            DefaultValue::Scalar(SemanticValue::Text(Arc::from(b"plural".as_slice()))),
        ),
    ]
    .into_iter()
    .map(|(owner, value)| {
        std::sync::Arc::new(FieldProjection {
            owner,
            declaring_owner: atom,
            name: gender,
            role: FieldRole::Assignment,
            wire_flags: None,
            intrinsic: true,
            shared: false,
            value,
        })
    })
    .collect::<Vec<_>>();
    let projection = ClassProjection {
        type_construction: Default::default(),
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
    let before_headers = dmb.clone();
    headers::finalize_headers(&mut dmb, bytes, &projection, &tables, &symbols).unwrap();
    let recipes = HeaderRecipes::default();
    let engine = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
    // Exercise the production retained branch both while populating recipes
    // and on warm lookup. Its inherited-field selection must match fresh.
    for _ in 0..2 {
        let mut retained = before_headers.clone();
        let mut strings = crate::composition::StringIndex::build(&retained).unwrap();
        headers::finalize_headers_with_engine(
            &mut retained,
            &engine,
            &projection,
            &tables,
            &symbols,
            &mut strings,
            None,
            Some(&recipes),
        )
        .unwrap();
        assert_eq!(retained.to_bytes().unwrap(), dmb.to_bytes().unwrap());
    }
    assert!(recipes.hits.load(std::sync::atomic::Ordering::Relaxed) > 0);
    let oracle = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/native_compiler/gender_settings/probe.native.bin"
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
            dmb.classes[id as usize].gender_code(),
            expected.gender_code(),
            "{:?}",
            path
        );
        let values = |image: &byond_dmb::dmb::Dmb, class: usize| {
            image
                .class_builtin_overrides(class)
                .unwrap_or_default()
                .into_iter()
                .filter(|row| image.string(row.name_string_id) == Some(b"gender"))
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
