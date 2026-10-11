use super::*;

struct NoTypes;
impl TypeValuePolicy for NoTypes {
    fn tag(&self, _: SymbolId) -> Result<u8, ProjectionError> {
        Err(ProjectionError::Unsupported(
            "no type values in fixture".into(),
        ))
    }
}

#[test]
fn shared_string_writer_matches_wrappers_with_duplicates_reserved_slots_and_authored_fields() {
    use byond_dmb::dmb::{DmString, Dmb};
    let bytes = include_bytes!("../../../../fixtures/native_template.bin");
    let mut image = Dmb::from_bytes(bytes).unwrap();
    let mut symbols = crate::engine::EngineSnapshot::from_bytes(bytes, 1)
        .unwrap()
        .symbols()
        .clone();
    let area = symbols.intern("/area").unwrap();
    let child = symbols.intern("/area/shared_writer_fixture").unwrap();
    let name = symbols.intern("name").unwrap();
    let area_id = image
        .classes
        .iter()
        .position(|class| image.string(class.path_string_id()) == Some(b"/area"))
        .unwrap() as u32;
    let child_id = image.classes.len() as u32;
    let lowest_name_id = image.strings.len() as u32;
    for _ in 0..2 {
        image.strings.push(DmString {
            data: b"shared writer name".to_vec(),
            long_chunks: 0,
        });
    }
    image.strings.resize(
        0xffcd,
        DmString {
            data: Vec::new(),
            long_chunks: 0,
        },
    );
    let projection = ClassProjection {
        type_construction: Default::default(),
        variable_records: Default::default(),
        field_placements: Default::default(),
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
            owner: child,
            declaring_owner: child,
            name,
            role: FieldRole::Assignment,
            wire_flags: None,
            intrinsic: true,
            shared: false,
            value: DefaultValue::Scalar(SemanticValue::Text(Arc::from(
                b"shared writer name".as_slice(),
            ))),
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
    let mut independent = image.clone();
    materialize_types(&mut independent, &projection, &tables, &symbols).unwrap();
    materialize_members(&mut independent, &projection, &tables, &symbols, &NoTypes).unwrap();
    headers::finalize_headers(&mut independent, bytes, &projection, &tables, &symbols).unwrap();
    let mut shared = crate::composition::StringIndex::build(&image).unwrap();
    let roster =
        materialize_types_with_roster(&mut image, &projection, &tables, &symbols, &mut shared)
            .unwrap();
    let mobs = crate::mob_writer::materialize_projection(&mut image, &tables, &projection).unwrap();
    materialize_members_with_roster(
        &mut image,
        &projection,
        (&tables, mobs),
        &symbols,
        &NoTypes,
        &mut shared,
        Some(&roster),
    )
    .unwrap();
    headers::finalize_headers_with_roster(
        &mut image,
        bytes,
        &projection,
        &tables,
        &symbols,
        &mut shared,
        Some(&roster),
    )
    .unwrap();
    assert_eq!(
        image.classes[child_id as usize].name_string_id(),
        lowest_name_id
    );
    assert_eq!(
        image.string(lowest_name_id),
        Some(b"shared writer name".as_slice())
    );
    assert!(image.strings[0xffcd..=0xfff1]
        .iter()
        .all(|string| string.data.is_empty()));
    assert_eq!(image.to_bytes().unwrap(), independent.to_bytes().unwrap());
}
