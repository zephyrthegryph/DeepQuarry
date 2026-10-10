use super::*;

#[test]
fn fresh_and_retained_null_names_match_captured_descendants() {
    let reference = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/native_compiler/header_null_name/probe.native.bin"
    ))
    .unwrap();
    let engine = include_bytes!("../../../../fixtures/native_template.bin");
    let mut symbols = dm_ir::SymbolTable::default();
    let mut inventory = dm_link::LinkInventory::default();
    let mut types = Vec::new();
    let mut fields = Vec::new();
    for (id, class) in reference.classes.iter().enumerate() {
        let path = std::str::from_utf8(reference.string(class.path_string_id()).unwrap()).unwrap();
        if !path.starts_with("/obj/probe") && !path.starts_with("/obj/named") {
            continue;
        }
        let owner = symbols.intern(path).unwrap();
        inventory
            .spellings
            .push((owner, Arc::from(path.as_bytes())));
        let key = Key::Type(owner);
        inventory.entries.push(dm_link::Entry {
            key,
            content: Arc::<[u8]>::from([]).into(),
        });
        inventory.fixed.push((key, id as u32));
        types.push(TypeProjection {
            path: owner,
            parent: None,
        });
        let value = match path {
            "/obj/probe" | "/obj/named/reset_child" => Some(dm_ir::SemanticValue::Null),
            "/obj/named" => Some(dm_ir::SemanticValue::Text(Arc::from(&b"parent label"[..]))),
            _ => None,
        };
        if let Some(value) = value {
            fields.push(Arc::new(FieldProjection {
                owner,
                declaring_owner: symbols.intern("/atom").unwrap(),
                name: symbols.intern("name").unwrap(),
                role: FieldRole::Assignment,
                wire_flags: None,
                intrinsic: true,
                shared: false,
                value: crate::initializer_policy::DefaultValue::Scalar(value),
            }));
        }
    }
    let tables = dm_link::LinkTables::build(inventory).unwrap();
    let projection = ClassProjection {
        field_placements: Default::default(),
        procedure_declarations: Default::default(),
        shared_slot_order: Arc::from([]),
        procedure_statics: Arc::from([]),
        runtime_writes: Arc::from([]),
        tree_identity: 0,
        occurrence_count: 0,
        types: types.into(),
        fields: fields.into(),
        chains: Arc::from([]),
        procedure_membership: Arc::from([]),
    };
    let store = header_recipes::HeaderRecipes::default();
    for retained in [None, Some(&store), Some(&store)] {
        let mut actual = reference.clone();
        for field in projection.fields.iter().filter(|field| {
            matches!(
                field.value,
                crate::initializer_policy::DefaultValue::Scalar(dm_ir::SemanticValue::Null)
            )
        }) {
            actual.classes[tables.index(Key::Type(field.owner)).unwrap() as usize].initial_ids[2] =
                NONE;
        }
        let mut pool = crate::composition::StringIndex::build(&actual).unwrap();
        finalize_headers_retained(
            &mut actual,
            engine,
            &projection,
            &tables,
            &symbols,
            &mut pool,
            None,
            retained,
        )
        .unwrap();
        for ty in projection.types.iter() {
            let id = tables.index(Key::Type(ty.path)).unwrap() as usize;
            assert_eq!(
                actual.string(actual.classes[id].name_string_id()),
                reference.string(reference.classes[id].name_string_id())
            );
            assert_eq!(
                actual.string(actual.classes[id].text),
                reference.string(reference.classes[id].text)
            );
        }
    }
}
