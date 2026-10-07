use super::*;
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
