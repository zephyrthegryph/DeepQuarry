use super::*;
use std::sync::Arc;

#[test]
fn references_reuse_only_current_binding_start_and_exact_helper_order() {
    let owner = SymbolId::of("/");
    let name = SymbolId::of("reference_probe");
    let keys: Vec<_> = (0..2)
        .map(|argument| Key::ArgumentSource {
            owner,
            name,
            verb: false,
            occurrence: 0,
            argument,
        })
        .collect();
    let inventory = dm_link::LinkInventory {
        spellings: [
            (owner, Arc::from(b"/".as_slice())),
            (name, Arc::from(b"reference_probe".as_slice())),
        ]
        .into(),
        entries: keys
            .iter()
            .map(|&key| dm_link::Entry {
                key,
                content: Arc::<[u8]>::from([]).into(),
            })
            .collect(),
        ..Default::default()
    };
    let tables = dm_link::LinkTables::build(inventory.clone()).unwrap();
    let mut plan = CachedPlan {
        bindings: tables.binding_tables(),
        assignment_floor: None,
        raw: CompositionPlan::default(),
        units: Vec::new(),
        helpers: keys.clone(),
        initializers: Vec::new(),
        procedures: Arc::new(Vec::new()),
        helper_rows: Arc::new(Vec::new()),
        initializer_rows: Arc::new(Vec::new()),
        argument_sources: None,
        metadata: None,
    };
    let first = plan.argument_sources(&tables, 1, &keys).unwrap();
    assert_eq!(first.index(keys[0]), Some(1));
    assert!(Arc::ptr_eq(
        &first,
        &plan.argument_sources(&tables, 1, &keys).unwrap()
    ));
    let offset = plan.argument_sources(&tables, 3, &keys).unwrap();
    assert!(!Arc::ptr_eq(&first, &offset));
    assert_eq!(offset.index(keys[0]), Some(3));
    let reversed = [keys[1], keys[0]];
    let reordered = plan.argument_sources(&tables, 3, &reversed).unwrap();
    assert!(!Arc::ptr_eq(&offset, &reordered));
    assert_eq!(reordered.index(keys[0]), Some(4));
    // A distinct validated binding owner cannot inherit this owner's certificate.
    let mut changed = inventory;
    changed.fixed.push((keys[0], 9));
    let changed = dm_link::LinkTables::build(changed).unwrap();
    let rebound = plan.argument_sources(&changed, 3, &keys).unwrap();
    assert!(!Arc::ptr_eq(&offset, &rebound));
    assert_eq!(rebound.index(keys[0]), Some(3));
    assert!(plan.argument_sources(&tables, 256, &keys).is_err());
    assert!(plan.argument_sources(&tables, 3, &[keys[0]]).is_err());
    assert!(plan
        .argument_sources(&tables, 3, &[keys[0], keys[0]])
        .is_err());
    assert!(
        Arc::ptr_eq(&offset, &plan.argument_sources(&tables, 3, &keys).unwrap()),
        "failed assignment must not poison the prior admitted owner"
    );
}
