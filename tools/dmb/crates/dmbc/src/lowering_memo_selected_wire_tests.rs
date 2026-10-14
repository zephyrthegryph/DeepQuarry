use super::*;
#[test]
fn selected_wire_roundtrips_runtime_dispatch_and_rejects_bad_coordinate_or_complete_claims() {
    let meanings = [
        SelectedMeaning::RuntimeProperty {
            name: SymbolId::of("field"),
            static_property: false,
            safe: true,
        },
        SelectedMeaning::ProcedureCall {
            reference: dm_ir::SymRef::Proc {
                owner: SymbolId::of("/datum"),
                name: SymbolId::of("run"),
                occurrence: 0,
            },
            safe: false,
        },
        SelectedMeaning::DynamicProcedure {
            selector: SymbolId::of("run"),
            safe: true,
        },
        SelectedMeaning::DynamicCall {
            dispatcher: SymbolId::of("call"),
            target_count: 2,
        },
        SelectedMeaning::IntrinsicCall(SymbolId::of("abs")),
    ];
    let facts = SelectedReferences {
        references: meanings
            .into_iter()
            .enumerate()
            .map(|(index, meaning)| SelectedReference {
                relative_span: Some((index, index + 1)),
                path: vec![NodeStep::Statement(index), NodeStep::Expression(0)],
                name: SymbolId::of("name"),
                meaning,
            })
            .collect(),
        complete: false,
        unbound_selections: 1,
    };
    let wire = SelectedWire::capture(&facts).unwrap();
    let bytes = dm_wire::encode(0x53454c32, &wire).unwrap();
    let roundtrip: SelectedWire = dm_wire::decode(0x53454c32, &bytes, bytes.len()).unwrap();
    assert_eq!(roundtrip.rehydrate().unwrap(), facts);
    let mut bad = SelectedWire::capture(&facts).unwrap();
    bad.references[0].path[0].0 = 4;
    assert!(!bad.valid());
    assert!(bad.rehydrate().is_none());
    let mut reversed = SelectedWire::capture(&facts).unwrap();
    reversed.references[0].relative_span = Some((3, 2));
    assert!(!reversed.valid());
    assert!(reversed.rehydrate().is_none());
    let mut complete = SelectedWire::capture(&facts).unwrap();
    complete.complete = true;
    assert!(!complete.valid());
    assert!(complete.rehydrate().is_none());
}
