use super::*;
use byond_dmb::dmb::Dmb;

#[test]
fn captured_static_vars_keeps_slot_but_omits_global_declaration() {
    let expected = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/native_compiler/procedure_static_vars/probe.native.bin"
    ))
    .unwrap();
    let expected_flags = expected.global_variable_flags().unwrap();
    for (name, present) in [("vars", false), ("other", true)] {
        let record = expected
            .variables
            .iter()
            .position(|value| {
                value.kind == 62 && expected.string(value.name) == Some(name.as_bytes())
            })
            .unwrap() as u32;
        assert_eq!(expected_flags.iter().any(|&(id, _)| id == record), present);
    }
    let bytes = include_bytes!("../../../../fixtures/native_template.bin");
    let engine = crate::engine::EngineSnapshot::from_bytes(bytes, 1).unwrap();
    let mut symbols = engine.symbols().clone();
    let mut actual = Dmb::from_bytes(bytes).unwrap();
    let initial_records = actual.variables.len();
    let mut inventory = dm_link::LinkInventory::default();
    for text in ["/datum", "probe", "vars", "other"] {
        let symbol = symbols.intern(text).unwrap();
        inventory
            .spellings
            .push((symbol, Arc::from(text.as_bytes())));
    }
    let mut locals = Vec::new();
    let mut order = Vec::new();
    for (ordinal, name) in ["vars", "other"].into_iter().enumerate() {
        let identity = dm_ir::ProcedureStaticIdentity {
            procedure: dm_ir::ProcedureIdentity {
                owner: symbols.intern("/datum").unwrap(),
                name: symbols.intern("probe").unwrap(),
                verb: false,
                occurrence: 0,
            },
            name: symbols.intern(name).unwrap(),
        };
        let key = Key::ProcedureStatic(identity);
        inventory.entries.push(dm_link::Entry {
            key,
            content: Arc::<[u8]>::from([]).into(),
        });
        inventory
            .fixed
            .push((key, (initial_records + ordinal) as u32));
        order.push(key);
        locals.push(ProcedureStaticProjection {
            identity,
            wire_flags: 1,
            value: DefaultValue::InitializerExpression {
                token: 0,
                canonical: Arc::from([]),
            },
            source_ordinal: ordinal,
        });
    }
    let tables = dm_link::LinkTables::build(inventory).unwrap();
    let projection = ClassProjection {
        source_features: Default::default(),
        type_construction: Default::default(),
        variable_records: Default::default(),
        field_placements: Default::default(),
        procedure_declarations: Default::default(),
        shared_slot_order: order.into(),
        procedure_statics: locals.into(),
        runtime_writes: Arc::from([]),
        tree_identity: 0,
        occurrence_count: 0,
        types: Arc::from([]),
        chains: Arc::from([]),
        procedure_membership: Arc::from([]),
        fields: Arc::from([]),
    };
    struct NoTypes;
    impl TypeValuePolicy for NoTypes {
        fn tag(&self, _: SymbolId) -> Result<u8, ProjectionError> {
            Err(ProjectionError::MissingMember)
        }
    }
    materialize_members(&mut actual, &projection, &tables, &symbols, &NoTypes).unwrap();
    let flags = actual.global_variable_flags().unwrap();
    for (ordinal, name) in ["vars", "other"].into_iter().enumerate() {
        let id = (initial_records + ordinal) as u32;
        assert_eq!(
            actual.string(actual.variables[id as usize].name),
            Some(name.as_bytes())
        );
        assert_eq!(actual.variables[id as usize].kind, 62);
        assert_eq!(
            flags.iter().any(|&(record, _)| record == id),
            name == "other"
        );
    }
}
