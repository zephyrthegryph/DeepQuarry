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
    let (Ok(PreparedMetadata::Retained(a)), Ok(PreparedMetadata::Retained(b))) =
        (&prepared[0], &first[0])
    else {
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
        .is_none());
    let changed_slot = [Slot {
        table_index: 1,
        ..slots[0]
    }];
    assert!(roster
        .admit(&changed_slot, &batch, None, &symbols, &references)
        .is_none());
    let original = Arc::clone(&batch.units[0].lowered.abi.as_ref().unwrap());
    batch.units[0].lowered.abi = Some(Arc::new(original.as_ref().clone()));
    assert!(roster
        .admit(&slots, &batch, None, &symbols, &references)
        .is_none());
    batch.units[0].lowered.abi = Some(original);
    let original = Arc::clone(&batch.units[0].lowered.frame);
    batch.units[0].lowered.frame = Arc::new(original.as_ref().clone());
    assert!(roster
        .admit(&slots, &batch, None, &symbols, &references)
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
