use super::*;
use crate::class_projection::{project, CapturedFieldEvaluator};
use dm_ir::{SemanticValue, SymbolicExpression};
use std::{collections::BTreeMap, path::Path, sync::Arc};
struct Source(String);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.clone())
    }
}
struct NoFields;
impl CapturedFieldEvaluator for NoFields {
    fn evaluate(&self, _: SymbolId, _: &SymbolicExpression) -> Result<SemanticValue, String> {
        Err("callback fixture has no fields".into())
    }
}
fn materialized(name: &str) -> (Dmb, Dmb) {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../fixtures/translation/client_header_probe");
    let text = std::fs::read_to_string(root.join(format!("{name}.dm"))).unwrap();
    let frontend = dm_tree::frontend::build(
        Path::new("callback.dme"),
        &Source(text),
        &BTreeMap::new(),
        1,
    )
    .unwrap();
    let projection = project(&frontend.snapshot, &frontend.emission_order, &NoFields).unwrap();
    let expected =
        Dmb::from_bytes(&std::fs::read(root.join(format!("{name}.native.bin"))).unwrap()).unwrap();
    let mut actual = expected.clone();
    // Replace only negotiation bits with the actual pinned empty-engine state.
    let seed = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    const MASK: u32 = 0x83e4_400c;
    actual.header.flags = (actual.header.flags & !MASK) | (seed.header.flags & MASK);
    actual.header.extended_flags = seed.header.extended_flags;
    let mut inventory = dm_link::LinkInventory::default();
    let symbols = frontend.snapshot.tree.symbols();
    let mut spellings = std::collections::BTreeSet::new();
    for chain in projection.chains.iter() {
        let class = expected
            .classes
            .iter()
            .find(|class| {
                expected.string(class.path_string_id())
                    == symbols.text(chain.owner).map(str::as_bytes)
            })
            .unwrap();
        let list = &expected.lists[class.proc_list_id() as usize];
        for key in chain.entries.iter() {
            let index = *list
                .iter()
                .find(|&&id| {
                    expected.string(expected.procs[id as usize].strings[1])
                        == symbols.text(chain.name).map(str::as_bytes)
                })
                .unwrap();
            inventory.entries.push(dm_link::Entry {
                key: *key,
                content: dm_link::EntryContent::Bytes(Arc::from([])),
            });
            inventory.fixed.push((*key, index));
            for symbol in [chain.owner, chain.name] {
                if spellings.insert(symbol) {
                    inventory
                        .spellings
                        .push((symbol, Arc::from(symbols.text(symbol).unwrap().as_bytes())));
                }
            }
        }
    }
    let tables = dm_link::LinkTables::build(inventory).unwrap();
    super::super::materialize_callback_flags(&mut actual, &projection, &tables).unwrap();
    (actual, expected)
}
#[test]
fn current_declared_callbacks_match_pinned_negotiation_headers() {
    for name in [
        "handler_Click",
        "handler_DblClick",
        "handler_MouseUp",
        "handler_MouseDown",
        "handler_MouseDrop",
        "handler_MouseDrag",
        "handler_MouseEntered",
        "handler_MouseExited",
        "handler_MouseMove",
        "handler_MouseWheel",
        "handler_Command",
        "handler_IsByondMember",
        "handler_obj_test_MouseEntered",
        "handler_obj_test_MouseExited",
        "handler_obj_test_MouseMove",
        "handler_obj_test_MouseWheel",
        "handler_client_test_MouseEntered",
        "handler_client_test_MouseExited",
        "handler_client_test_MouseMove",
        "handler_client_test_MouseWheel",
    ] {
        let (actual, expected) = materialized(name);
        assert_eq!(actual.header.flags, expected.header.flags, "{name}");
        assert_eq!(
            actual.header.extended_flags, expected.header.extended_flags,
            "{name}"
        );
    }
}
#[test]
fn unrelated_owners_and_foreign_ancestry_cannot_issue_callback_negotiation() {
    let classes = [
        (SymbolId::of("/datum"), 0),
        (SymbolId::of("/atom"), 1),
        (SymbolId::of("/client"), 2),
        (SymbolId::of("/obj/child"), 3),
    ]
    .into_iter()
    .collect();
    let mut features = HeaderFeatures::default();
    features
        .observe(SymbolId::of("Click"), 0, &[NONE, 0, 0, 1], &classes)
        .unwrap();
    features
        .observe(SymbolId::of("MouseMove"), 3, &[NONE, 0, 0, 1], &classes)
        .unwrap();
    assert_eq!((features.flags, features.extended), (0, 0));
    features
        .observe(SymbolId::of("MouseDown"), 3, &[NONE, 0, 0, 1], &classes)
        .unwrap();
    assert_eq!(features.flags, 0x0040_0000);
    assert!(HeaderFeatures::default()
        .observe(SymbolId::of("Click"), 3, &[NONE, 0, 0, 3], &classes)
        .is_err());
    assert!(HeaderFeatures::default()
        .observe(SymbolId::of("Click"), 3, &[NONE, 0, 0, 9], &classes)
        .is_err());
}
