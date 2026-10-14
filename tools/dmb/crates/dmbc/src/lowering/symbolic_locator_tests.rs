use super::*;
#[test]
fn borrowed_symbolic_locator_matches_existing_bytes_and_rejects_forged_identity() {
    struct Source(&'static str);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok(self.0.into())
        }
    }
    let make = |source| {
        dm_tree::frontend::build(
            std::path::Path::new("probe.dme"),
            &Source(source),
            &Default::default(),
            1,
        )
        .unwrap()
    };
    let front = make("/proc/probe()\n    return 7\n");
    let shifted = make("// shifted source\n/proc/probe()\n    return 7\n");
    let current = crate::lowering_memo::key_recipe::CurrentKey::new(
        &front,
        &front.bodies[0],
        7,
        false,
        false,
    )
    .unwrap();
    let shifted_key = crate::lowering_memo::key_recipe::CurrentKey::new(
        &shifted,
        &shifted.bodies[0],
        7,
        false,
        false,
    )
    .unwrap();
    let tail = crate::lowering_memo::key_recipe::PreparedKey::Parsed(vec![1, 2]);
    let identity = UnitIdentity {
        owner: dm_ir::SymbolId::of("/"),
        name: dm_ir::SymbolId::of("probe"),
        namespace: Namespace::Proc,
        occurrence: 0,
    };
    let bytes = locator(identity, &current.materialize(&tail));
    let borrowed = BorrowedLocator::new(identity, &current, &tail);
    assert_eq!(borrowed.digest(), xxhash_rust::xxh3::xxh3_128(&bytes));
    assert!(borrowed.matches(&bytes));
    assert!(BorrowedLocator::new(identity, &shifted_key, &tail).matches(&bytes));
    let wrong = UnitIdentity {
        name: dm_ir::SymbolId::of("wrong"),
        ..identity
    };
    assert!(!BorrowedLocator::new(wrong, &current, &tail).matches(&bytes));
    assert!(!borrowed.matches(&bytes[..bytes.len() - 1]));
    assert!(!borrowed.matches(&locator(wrong, &current.materialize(&tail))));
}
