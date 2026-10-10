use super::*;
#[test]
fn ordered_metadata_reuses_exact_owners_and_declines_changed_current_authority() {
    let (mut batch, symbols) =
        crate::composition::tests::ownership_fixture_source("/proc/roster_probe()\n    return 1\n");
    let identity = batch.units[0].lowered.identity;
    let slots = [Slot {
        table_index: 0,
        identity,
        artifact: Some(0),
    }];
    let references =
        Arc::new(dm_link::ArgumentSourceReferences::assign(&batch.tables, 0, &[]).unwrap());
    let mut model =
        byond_dmb::dmb::Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin"))
            .unwrap();
    let mut strings = crate::composition::StringIndex::build(&model).unwrap();
    super::super::super::frame_contribution::emit(
        &mut model,
        &mut strings,
        &batch.units[0],
        Arc::new(vec![1]),
        ProcedureMetadata {
            declared: Some(true),
            path: batch.units[0].metadata_recipe.path(&symbols, true),
            default_display: batch.units[0].metadata_recipe.display(&symbols),
            value_sources: Vec::new(),
        },
        true,
    )
    .unwrap();
    let prepared = prepare_metadata(&slots, &batch, None, &symbols, &references, None, true);
    let roster = MetadataRoster::capture(&slots, &batch, None, &references, &prepared).unwrap();
    let first = roster
        .admit(&slots, &batch, None, &symbols, &references)
        .unwrap();
    let (Ok(PreparedMetadata::Retained(a)), Some(b)) = (&prepared[0], &first[0]) else {
        panic!("retained owner expected");
    };
    assert!(Arc::ptr_eq(a, b));
    let other_references =
        Arc::new(dm_link::ArgumentSourceReferences::assign(&batch.tables, 0, &[]).unwrap());
    assert!(roster
        .admit(&slots, &batch, None, &symbols, &other_references)
        .is_none());
    assert!(roster
        .admit(&slots, &batch, None, &SymbolTable::default(), &references)
        .unwrap()[0]
        .is_none());
    let changed_slot = [Slot {
        table_index: 1,
        ..slots[0]
    }];
    assert!(roster
        .admit(&changed_slot, &batch, None, &symbols, &references)
        .unwrap()[0]
        .is_none());
    let original = Arc::clone(&batch.units[0].lowered.abi.as_ref().unwrap());
    batch.units[0].lowered.abi = Some(Arc::new(original.as_ref().clone()));
    assert!(roster
        .admit(&slots, &batch, None, &symbols, &references)
        .unwrap()[0]
        .is_none());
    batch.units[0].lowered.abi = Some(original);
    let original = Arc::clone(&batch.units[0].lowered.frame);
    batch.units[0].lowered.frame = Arc::new(original.as_ref().clone());
    assert!(roster
        .admit(&slots, &batch, None, &symbols, &references)
        .unwrap()[0]
        .is_none());
    batch.units[0].lowered.frame = original;
    assert!(roster
        .admit(&slots, &batch, None, &symbols, &references)
        .is_some());
    let fresh = prepare_metadata(&slots, &batch, None, &symbols, &references, None, false);
    assert!(MetadataRoster::capture(&slots, &batch, None, &references, &fresh).is_none());
    let errors = vec![Err(crate::composition::unsupported("current failure"))];
    assert!(MetadataRoster::capture(&slots, &batch, None, &references, &errors).is_none());
    let raw = CompositionPlan {
        procedures: vec![(0, identity)],
        ..Default::default()
    };
    let bound = raw.clone().bind(&batch);
    let mut plan = CachedPlan::capture(raw, &batch, &bound).unwrap();
    plan.prepare_metadata(&slots, &batch, None, &symbols, &references, None);
    assert!(plan.metadata.is_some());
    let original_tables = batch.tables.clone();
    batch.tables = dm_link::LinkTables::build(Default::default()).unwrap();
    plan.prepare_metadata(&slots, &batch, None, &symbols, &references, None);
    assert!(
        plan.metadata.is_none(),
        "changed binding owner must discard the ordered proof"
    );
    batch.tables = original_tables;
}

#[test]
fn changed_row_reuses_sibling_and_prunes_deleted_or_failed_rows() {
    let (mut batch, symbols) = crate::composition::tests::ownership_fixture_source(
        "/proc/first()\n    return 1\n/proc/second()\n    return 2\n",
    );
    let slots: Vec<_> = batch
        .units
        .iter()
        .enumerate()
        .map(|(index, unit)| Slot {
            table_index: index as u32,
            identity: unit.lowered.identity,
            artifact: Some(index),
        })
        .collect();
    assert_eq!(slots.len(), 2);
    let references =
        Arc::new(dm_link::ArgumentSourceReferences::assign(&batch.tables, 0, &[]).unwrap());
    let mut model =
        byond_dmb::dmb::Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin"))
            .unwrap();
    let mut strings = crate::composition::StringIndex::build(&model).unwrap();
    for unit in &batch.units {
        super::super::super::frame_contribution::emit(
            &mut model,
            &mut strings,
            unit,
            Arc::new(vec![1]),
            ProcedureMetadata {
                declared: Some(true),
                path: unit.metadata_recipe.path(&symbols, true),
                default_display: unit.metadata_recipe.display(&symbols),
                value_sources: Vec::new(),
            },
            true,
        )
        .unwrap();
    }
    let prepared = prepare_metadata(&slots, &batch, None, &symbols, &references, None, true);
    let roster = MetadataRoster::capture(&slots, &batch, None, &references, &prepared).unwrap();
    let Ok(PreparedMetadata::Retained(sibling)) = &prepared[1] else {
        panic!("retained sibling");
    };
    // A distinct equal ABI is deliberately not the exact admitted owner.
    let abi = batch.units[0].lowered.abi.as_ref().unwrap();
    batch.units[0].lowered.abi = Some(Arc::new(abi.as_ref().clone()));
    let admitted = roster
        .admit(&slots, &batch, None, &symbols, &references)
        .unwrap();
    assert!(admitted[0].is_none());
    assert!(Arc::ptr_eq(admitted[1].as_ref().unwrap(), sibling));
    let mixed = super::super::prepare_metadata_with_admitted(
        &slots,
        &batch,
        None,
        &symbols,
        &references,
        None,
        true,
        Some(&admitted),
    );
    let Ok(PreparedMetadata::Retained(reused)) = &mixed[1] else {
        panic!("retained sibling");
    };
    assert!(Arc::ptr_eq(reused, sibling));
    // Current missing slot is processed by the normal producer in place.
    let missing = [
        slots[0],
        Slot {
            artifact: None,
            ..slots[1]
        },
    ];
    let admitted = roster
        .admit(&missing, &batch, None, &symbols, &references)
        .unwrap();
    let failed = super::super::prepare_metadata_with_admitted(
        &missing,
        &batch,
        None,
        &symbols,
        &references,
        None,
        true,
        Some(&admitted),
    );
    assert!(failed[1].is_err());
    // Capturing the new current roster keeps successful rows only.
    let current = MetadataRoster::capture(&slots, &batch, None, &references, &mixed).unwrap();
    let deleted =
        MetadataRoster::capture(&slots[..1], &batch, None, &references, &mixed[..1]).unwrap();
    assert_eq!(current.rows.len(), 2);
    assert_eq!(deleted.rows.len(), 1);
    let partial = MetadataRoster::capture(&missing, &batch, None, &references, &failed).unwrap();
    assert!(partial.rows[0].is_some());
    assert!(partial.rows[1].is_none());
}
