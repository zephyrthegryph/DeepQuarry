use super::*;
#[test]
fn latest_image_census_deduplicates_shared_words_and_preserves_binding_unknowns() {
    use byond_dmb::bytecode::opcode;
    use dm_codegen_byond::{Instruction, Item, SymbolicProc, Word};
    let code = SymbolicProc {
        items: vec![
            Item::Instruction(Instruction {
                opcode: opcode::DBG_LINE,
                operands: vec![Word::Reference(SymRef::SourceLine(0))],
            }),
            Item::Instruction(Instruction {
                opcode: opcode::RET,
                operands: vec![],
            }),
        ],
    };
    let frozen = Arc::new(dm_codegen_byond::encoder::freeze_proc(&code).unwrap());
    let owner = Arc::new(LatestImage::default());
    let tables = LinkTables::build(Default::default()).unwrap();
    let origins = crate::debug_sources::DebugOrigins {
        entries: vec![crate::debug_sources::DebugOrigin {
            semantic_path: Arc::from("current.dm"),
            line: 7,
        }],
    }
    .into();
    let image = owner.link(&frozen, &origins, &tables).unwrap();
    let mut single = crate::heap_census::HeapCensus::new("single");
    single.latest_image(&owner);
    let single = single.finish();
    let mut shared = crate::heap_census::HeapCensus::new("shared");
    shared.latest_image(&owner);
    shared.latest_image(&Arc::clone(&owner));
    if shared.arc_object("separate_current_image", &image.words) {
        shared.vec_payload("separate_current_image", &image.words);
    }
    let shared = shared.finish();
    assert_eq!(
        single.unique_known_capacity_bytes,
        shared.unique_known_capacity_bytes
    );
    assert_eq!(
        single.unknown_capacity_payload_bytes,
        shared.unknown_capacity_payload_bytes
    );
    assert!(shared
        .owners
        .iter()
        .any(|owner| owner.shared_encounters > 0));
    let bindings = shared
        .owners
        .iter()
        .find(|owner| owner.owner == "latest_images.bindings")
        .unwrap();
    assert!(bindings.unknown_capacity_payload_bytes > 0);
    assert!(bindings
        .unknown
        .iter()
        .any(|reason| reason.contains("HashMap allocated")));
    let unchanged = owner.link(&frozen, &origins, &tables).unwrap();
    assert!(Arc::ptr_eq(&image.words, &unchanged.words));
}
