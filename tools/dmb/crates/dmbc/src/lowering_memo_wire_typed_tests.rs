use super::*;
struct Host;
impl Resolver for Host {
    fn resolve(&self, query: ResolveQuery) -> dm_ir::ResolvedMeaning {
        dm_ir::ResolvedMeaning::Unsupported(query)
    }
}
fn code() -> ResolverProc {
    ResolverProc {
        procedure: Default::default(),
        slots: Default::default(),
        resources: Default::default(),
        instances: Default::default(),
        procedure_values: Default::default(),
        procedure_statics: Default::default(),
        modified_instances: Default::default(),
    }
}
#[test]
fn exact_slot_and_callable_occurrences_roundtrip_and_reject_forged_keys() {
    let slot = SymbolId::of("exact-slot");
    let owner = SymbolId::of("/datum/base");
    let name = SymbolId::of("callback");
    let identity = ProcedureIdentity {
        owner,
        name,
        verb: false,
        occurrence: 7,
    };
    let reference = SymRef::Proc {
        owner,
        name,
        occurrence: 7,
    };
    let mut original = code();
    original.slots.insert(
        SymRef::VariableSlot(slot),
        ResolvedSlot {
            symbol: slot,
            owner,
            name,
        },
    );
    original.procedure_values.insert(reference, identity);
    let wire = CodeWire::capture(&original);
    let replay = wire.rehydrate(&Host, 0).unwrap();
    assert_eq!(replay.slots, original.slots);
    assert_eq!(replay.procedure_values, original.procedure_values);
    let mut wrong_slot = CodeWire::capture(&original);
    wrong_slot.slots[0].0 = SymRef::String(slot);
    assert!(wrong_slot.rehydrate(&Host, 0).is_none());
    let mut wrong_occurrence = CodeWire::capture(&original);
    wrong_occurrence.procedure_values.clear();
    wrong_occurrence.procedure_values.insert(
        SymRef::Proc {
            owner,
            name,
            occurrence: 0,
        },
        identity,
    );
    assert!(wrong_occurrence.rehydrate(&Host, 0).is_none());
}
