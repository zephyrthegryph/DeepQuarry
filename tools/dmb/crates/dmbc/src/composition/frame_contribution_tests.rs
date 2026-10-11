//! One shared emitter; one-shot composition does not capture a retained frame.
use super::*;

#[test]
fn frame_reuse_checks_used_ids_instead_of_unrelated_table_frontiers() {
    use std::sync::Arc;
    for has_local in [false, true] {
        let (mut batch, _) = ownership_fixture_source("/proc/frontier_probe()\n    return 1\n");
        if has_local {
            Arc::make_mut(&mut batch.units[0].lowered.frame).local_count = 1;
            Arc::make_mut(&mut batch.units[0].lowered.frame).local_names =
                vec!["frontier_local".into()];
        }
        let mut baseline =
            Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
        let mut strings = StringIndex::build(&baseline).unwrap();
        for spelling in ["/proc/frontier_probe", "frontier probe", "frontier_local"] {
            strings.intern(&mut baseline, spelling.as_bytes()).unwrap();
        }
        let emit = |model: &mut Dmb| {
            let mut index = StringIndex::build(model).unwrap();
            frame_contribution::emit(
                model,
                &mut index,
                &batch.units[0],
                Arc::new(vec![1]),
                procedure_plan::ProcedureMetadata {
                    declared: Some(true),
                    path: Ok(Arc::from("/proc/frontier_probe")),
                    default_display: Ok(Arc::from("frontier probe")),
                    value_sources: Vec::new(),
                },
                true,
            )
            .unwrap();
        };
        emit(&mut baseline.clone());
        let owner = batch.units[0]
            .metadata_recipe
            .frame_owner()
            .lock()
            .unwrap()
            .clone()
            .unwrap();
        for change in 0..5 {
            let mut current = baseline.clone();
            match change {
                0 => current.procs.push(current.procs[0].clone()),
                1 => current.lists.push(vec![123]),
                2 => current.strings.push(DmString {
                    data: b"unrelated frontier text".to_vec(),
                    long_chunks: 0,
                }),
                3 => current.variables.push(Variable {
                    kind: 0,
                    value: 0,
                    name: 0,
                }),
                _ => {
                    let display = current
                        .strings
                        .iter_mut()
                        .find(|row| row.data == b"frontier probe")
                        .unwrap();
                    display.data = b"different binding".to_vec();
                }
            }
            let original_owner = batch.units[0].metadata_recipe.frame_owner();
            *original_owner.lock().unwrap() = Some(Arc::clone(&owner));
            let mut fresh = current.clone();
            let mut index = StringIndex::build(&fresh).unwrap();
            frame_contribution::emit(
                &mut fresh,
                &mut index,
                &batch.units[0],
                Arc::new(vec![1]),
                procedure_plan::ProcedureMetadata {
                    declared: Some(true),
                    path: Ok(Arc::from("/proc/frontier_probe")),
                    default_display: Ok(Arc::from("frontier probe")),
                    value_sources: Vec::new(),
                },
                false,
            )
            .unwrap();
            emit(&mut current);
            assert_eq!(current, fresh);
            assert_eq!(
                Arc::ptr_eq(&owner, original_owner.lock().unwrap().as_ref().unwrap()),
                change != 4 && (change != 3 || !has_local)
            );
        }
    }
}
#[test]
fn one_shot_frame_emission_skips_retention_and_matches_retained_output() {
    use std::sync::Arc;
    let (mut batch, _) = ownership_fixture_source("/proc/cold_frame_probe()\n    return 1\n");
    Arc::make_mut(&mut batch.units[0].lowered.frame).local_count = 1;
    Arc::make_mut(&mut batch.units[0].lowered.frame).local_names = vec!["current_local".into()];
    let baseline =
        Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let emit = |retain| {
        let mut model = baseline.clone();
        let mut index = StringIndex::build(&model).unwrap();
        frame_contribution::emit(
            &mut model,
            &mut index,
            &batch.units[0],
            Arc::new(vec![1]),
            procedure_plan::ProcedureMetadata {
                declared: Some(true),
                path: Ok(Arc::from("/proc/cold_frame_probe")),
                default_display: Ok(Arc::from("cold frame probe")),
                value_sources: Vec::new(),
            },
            retain,
        )
        .unwrap();
        model
    };
    let cold = emit(false);
    assert!(batch.units[0]
        .metadata_recipe
        .frame_owner()
        .lock()
        .unwrap()
        .is_none());
    let retained = emit(true);
    assert!(cold == retained);
    let owner = batch.units[0]
        .metadata_recipe
        .frame_owner()
        .lock()
        .unwrap()
        .clone()
        .unwrap();
    let cold_again = emit(false);
    assert!(cold_again == retained);
    assert!(Arc::ptr_eq(
        &owner,
        batch.units[0]
            .metadata_recipe
            .frame_owner()
            .lock()
            .unwrap()
            .as_ref()
            .unwrap()
    ));
}
#[test]
fn prepared_metadata_reuse_checks_declarations_symbols_and_current_helper_order() {
    use procedure_plan::{PreparedMetadata, ProcedureMetadata, Slot};
    use std::sync::Arc;
    let (mut batch, symbols) = ownership_fixture_source("/proc/metadata_probe()\n    return 1\n");
    Arc::make_mut(&mut batch.units[0].lowered.frame).argument_names = vec!["argument".into()];
    Arc::make_mut(&mut batch.units[0].lowered.frame).argument_type_flags = vec![0];
    Arc::make_mut(batch.units[0].lowered.abi.as_mut().unwrap()).argument_sources =
        vec![dm_codegen_byond::procedure_abi::ArgumentSource::Helper { argument: 0 }];
    let identity = batch.units[0].lowered.identity;
    let keys = [
        crate::symbolic::helper_key(identity, 0),
        crate::symbolic::helper_key(identity, 1),
    ];
    let tables = dm_link::LinkTables::build(dm_link::LinkInventory {
        spellings: [identity.owner, identity.name]
            .into_iter()
            .map(|id| (id, Arc::from(symbols.text(id).unwrap().as_bytes())))
            .collect(),
        entries: keys
            .iter()
            .map(|&key| dm_link::Entry {
                key,
                content: Vec::<u8>::new().into(),
            })
            .collect(),
        ..Default::default()
    })
    .unwrap();
    let original = dm_link::ArgumentSourceReferences::assign(&tables, 1, &keys).unwrap();
    let reordered =
        dm_link::ArgumentSourceReferences::assign(&tables, 1, &[keys[1], keys[0]]).unwrap();
    let missing = dm_link::ArgumentSourceReferences::assign(
        &dm_link::LinkTables::build(Default::default()).unwrap(),
        0,
        &[],
    )
    .unwrap();
    let mut model =
        Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let mut index = StringIndex::build(&model).unwrap();
    frame_contribution::emit(
        &mut model,
        &mut index,
        &batch.units[0],
        Arc::new(vec![1]),
        ProcedureMetadata {
            declared: Some(true),
            path: batch.units[0].metadata_recipe.path(&symbols, true),
            default_display: batch.units[0].metadata_recipe.display(&symbols),
            value_sources: vec![Ok(0x140)],
        },
        true,
    )
    .unwrap();
    let slots = [Slot {
        table_index: 0,
        identity,
        artifact: Some(0),
    }];
    let prepare = |projection, symbols, references, retain| {
        procedure_plan::prepare_metadata(
            &slots, &batch, projection, symbols, references, None, retain,
        )
        .pop()
        .unwrap()
        .unwrap()
    };
    assert!(matches!(
        prepare(None, &symbols, &original, true),
        PreparedMetadata::Retained(_)
    ));
    assert!(matches!(
        prepare(None, &symbols, &original, false),
        PreparedMetadata::Fresh(_)
    ));
    assert!(matches!(
        prepare(None, &symbols, &reordered, true),
        PreparedMetadata::Fresh(_)
    ));
    let PreparedMetadata::Fresh(changed) = prepare(None, &symbols, &reordered, true) else {
        panic!("changed ordinal must rebuild")
    };
    assert_eq!(changed.value_sources[0].as_ref().unwrap(), &0x240);
    let PreparedMetadata::Fresh(absent) = prepare(None, &symbols, &missing, true) else {
        panic!("missing helper must decline")
    };
    assert!(absent.value_sources[0].is_err());
    let absent_symbols = SymbolTable::default();
    let PreparedMetadata::Fresh(absent) = prepare(None, &absent_symbols, &original, true) else {
        panic!("missing spelling must decline")
    };
    assert!(absent.path.is_err());
    let projection = crate::class_projection::ClassProjection {
        type_construction: Default::default(),
        variable_records: Default::default(),
        field_placements: Default::default(),
        procedure_declarations: Default::default(),
        shared_slot_order: Arc::from([]),
        procedure_statics: Arc::from([]),
        runtime_writes: Arc::from([]),
        tree_identity: 0,
        occurrence_count: 0,
        types: Arc::from([]),
        fields: Arc::from([]),
        chains: Arc::from([]),
        procedure_membership: Arc::from([]),
    };
    let PreparedMetadata::Fresh(absent) = prepare(Some(&projection), &symbols, &original, true)
    else {
        panic!("missing declaration must decline")
    };
    assert!(
        matches!(&absent.path,Err(CompositionError::Unsupported(message)) if message=="missing source procedure declaration provenance")
    );
    // Negative metadata remains deferred until after current code list binding.
    let before = model.lists.len();
    let error = frame_contribution::emit(
        &mut model,
        &mut index,
        &batch.units[0],
        Arc::new(vec![2]),
        absent,
        false,
    )
    .unwrap_err();
    assert!(matches!(error, CompositionError::Unsupported(_)));
    assert!(model.lists.len() > before);
}

#[test]
fn pressure_release_recomputes_identical_frame_output() {
    use std::sync::Arc;
    let (mut batch, _) = ownership_fixture_source("/proc/pressure_probe()\n    return 1\n");
    Arc::make_mut(&mut batch.units[0].lowered.frame).local_count = 1;
    Arc::make_mut(&mut batch.units[0].lowered.frame).local_names = vec!["pressure_local".into()];
    let baseline =
        Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let emit = |model: &mut Dmb| {
        let mut index = StringIndex::build(model).unwrap();
        frame_contribution::emit(
            model,
            &mut index,
            &batch.units[0],
            Arc::new(vec![1]),
            procedure_plan::ProcedureMetadata {
                declared: Some(true),
                path: Ok(Arc::from("/proc/pressure_probe")),
                default_display: Ok(Arc::from("pressure probe")),
                value_sources: Vec::new(),
            },
            true,
        )
        .unwrap();
    };
    let mut expected = baseline.clone();
    emit(&mut expected);
    let weak = {
        let cache = batch.units[0].metadata_recipe.frame_owner().lock().unwrap();
        Arc::downgrade(cache.as_ref().unwrap())
    };
    assert!(batch.units[0].metadata_recipe.release_numeric_caches() >= 1);
    assert!(weak.upgrade().is_none());
    assert!(batch.units[0]
        .metadata_recipe
        .frame_owner()
        .lock()
        .unwrap()
        .is_none());
    assert_eq!(batch.units[0].metadata_recipe.release_numeric_caches(), 0);
    let mut rebuilt = baseline;
    emit(&mut rebuilt);
    assert_eq!(rebuilt, expected);
    assert!(batch.units[0]
        .metadata_recipe
        .frame_owner()
        .lock()
        .unwrap()
        .is_some());
}

#[test]
fn retained_frame_shares_immutable_payload_and_checks_distinct_values() {
    use std::sync::Arc;
    let (mut batch, _) = ownership_fixture_source("/proc/shared_frame_probe()\n    return 1\n");
    let frame = Arc::make_mut(&mut batch.units[0].lowered.frame);
    frame.local_count = 1;
    frame.local_names = vec!["shared_local".into()];
    let baseline =
        Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let emit = |model: &mut Dmb, unit: &crate::symbolic::FrozenUnit| {
        let mut index = StringIndex::build(model).unwrap();
        frame_contribution::emit(
            model,
            &mut index,
            unit,
            Arc::new(vec![1]),
            procedure_plan::ProcedureMetadata {
                declared: Some(true),
                path: Ok(Arc::from("/proc/shared_frame_probe")),
                default_display: Ok(Arc::from("shared frame probe")),
                value_sources: Vec::new(),
            },
            true,
        )
        .unwrap();
    };
    assert_eq!(Arc::strong_count(&batch.units[0].lowered.frame), 1);
    let mut expected = baseline.clone();
    emit(&mut expected, &batch.units[0]);
    assert_eq!(Arc::strong_count(&batch.units[0].lowered.frame), 2);
    let first = batch.units[0]
        .metadata_recipe
        .frame_owner()
        .lock()
        .unwrap()
        .clone()
        .unwrap();
    // A distinct equal compatibility value must retain the exact same numeric receipt.
    batch.units[0].lowered.frame = Arc::new((*batch.units[0].lowered.frame).clone());
    let mut equal = baseline.clone();
    emit(&mut equal, &batch.units[0]);
    assert_eq!(equal, expected);
    assert!(Arc::ptr_eq(
        &first,
        batch.units[0]
            .metadata_recipe
            .frame_owner()
            .lock()
            .unwrap()
            .as_ref()
            .unwrap()
    ));
    Arc::make_mut(&mut batch.units[0].lowered.frame).local_names[0] = "changed_local".into();
    let mut changed = baseline;
    emit(&mut changed, &batch.units[0]);
    assert!(!Arc::ptr_eq(
        &first,
        batch.units[0]
            .metadata_recipe
            .frame_owner()
            .lock()
            .unwrap()
            .as_ref()
            .unwrap()
    ));
    assert_ne!(changed, expected);
}

#[test]
fn frame_metadata_admits_shared_and_equal_abi_owners_but_rejects_changed_layout() {
    use std::sync::Arc;
    let (mut batch, symbols) = ownership_fixture_source("/proc/abi_owner_probe()\n    return 1\n");
    let baseline =
        Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let mut model = baseline.clone();
    let mut index = StringIndex::build(&model).unwrap();
    frame_contribution::emit(
        &mut model,
        &mut index,
        &batch.units[0],
        Arc::new(vec![1]),
        procedure_plan::ProcedureMetadata {
            declared: Some(true),
            path: batch.units[0].metadata_recipe.path(&symbols, true),
            default_display: batch.units[0].metadata_recipe.display(&symbols),
            value_sources: Vec::new(),
        },
        true,
    )
    .unwrap();
    let owner = batch.units[0]
        .metadata_recipe
        .frame_owner()
        .lock()
        .unwrap()
        .clone()
        .unwrap();
    let tables = dm_link::LinkTables::build(Default::default()).unwrap();
    let references = dm_link::ArgumentSourceReferences::assign(&tables, 0, &[]).unwrap();
    let original = Arc::clone(batch.units[0].lowered.abi.as_ref().unwrap());
    assert!(owner.admit_current_metadata(&batch.units[0], None, &symbols, &references));
    let equal = Arc::new(original.as_ref().clone());
    assert!(!Arc::ptr_eq(&original, &equal));
    batch.units[0].lowered.abi = Some(equal);
    assert!(owner.admit_current_metadata(&batch.units[0], None, &symbols, &references));
    Arc::make_mut(batch.units[0].lowered.abi.as_mut().unwrap())
        .layout
        .flags ^= 1;
    assert!(!owner.admit_current_metadata(&batch.units[0], None, &symbols, &references));
    batch.units[0].lowered.abi = None;
    assert!(!owner.admit_current_metadata(&batch.units[0], None, &symbols, &references));
}
