use super::*;

struct NoTypes;
impl TypeValuePolicy for NoTypes {
    fn tag(&self, _: SymbolId) -> Result<u8, ProjectionError> {
        Err(ProjectionError::Unsupported(
            "fixture has no type values".into(),
        ))
    }
}

#[test]
fn image_defaults_and_authored_headers_follow_semantic_parent_family() {
    let bytes = include_bytes!("../../../../fixtures/native_template.bin");
    let mut dmb = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
    let mut symbols = crate::engine::EngineSnapshot::from_bytes(bytes, 1)
        .unwrap()
        .symbols()
        .clone();
    let specs = [
        ("/image", None),
        ("/atom", None),
        ("/image/empty_child", Some("/image")),
        ("/image/empty_child/grandchild", Some("/image/empty_child")),
        ("/image/authored", Some("/image")),
        ("/image/authored/child", Some("/image/authored")),
        ("/atom/atom_probe", Some("/atom")),
        // A lexical image path with an atom parent still uses atom defaults.
        ("/image/atom_parent", Some("/atom")),
        ("/datum/image_parent", Some("/image")),
    ];
    let mut inventory = dm_link::LinkInventory::default();
    let mut next = dmb.classes.len() as u32;
    let mut ids = BTreeMap::new();
    let types: Vec<_> = specs
        .iter()
        .map(|&(path, parent)| {
            let symbol = symbols.intern(path).unwrap();
            let id = dmb
                .classes
                .iter()
                .position(|record| dmb.string(record.path_string_id()) == Some(path.as_bytes()))
                .map(|id| id as u32)
                .unwrap_or_else(|| {
                    let id = next;
                    next += 1;
                    id
                });
            ids.insert(path, id);
            inventory
                .spellings
                .push((symbol, Arc::from(path.as_bytes())));
            inventory.entries.push(dm_link::Entry {
                key: Key::Type(symbol),
                content: Arc::<[u8]>::from([]).into(),
            });
            inventory.fixed.push((Key::Type(symbol), id));
            TypeProjection {
                path: symbol,
                parent: parent.map(|p| symbols.intern(p).unwrap()),
            }
        })
        .collect();
    let owner = symbols.intern("/image/authored").unwrap();
    let fields = [
        ("name", b"authored name".as_slice()),
        ("text", b"X".as_slice()),
    ]
    .into_iter()
    .map(|(name, text)| {
        Arc::new(FieldProjection {
            owner,
            declaring_owner: owner,
            name: symbols.intern(name).unwrap(),
            role: FieldRole::Assignment,
            wire_flags: None,
            intrinsic: true,
            shared: false,
            value: DefaultValue::Scalar(SemanticValue::Text(Arc::from(text))),
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
    materialize_types(&mut dmb, &projection, &tables, &symbols).unwrap();
    materialize_members(&mut dmb, &projection, &tables, &symbols, &NoTypes).unwrap();
    headers::finalize_headers(&mut dmb, bytes, &projection, &tables, &symbols).unwrap();
    for (path, name, text) in [
        ("/image/empty_child", b"".as_slice(), b"".as_slice()),
        ("/image/empty_child/grandchild", b"", b""),
        ("/datum/image_parent", b"", b""),
        ("/image/authored", b"authored name", b"X"),
        ("/image/authored/child", b"authored name", b"X"),
        ("/atom/atom_probe", b"atom probe", b"a"),
        ("/image/atom_parent", b"atom parent", b"a"),
    ] {
        let record = &dmb.classes[ids[path] as usize];
        assert_eq!(
            dmb.string(record.name_string_id()),
            Some(name),
            "{path} name"
        );
        assert_eq!(dmb.string(record.text), Some(text), "{path} text");
    }
}
