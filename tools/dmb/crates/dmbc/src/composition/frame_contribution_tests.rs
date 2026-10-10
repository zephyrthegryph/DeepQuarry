//! One shared emitter; one-shot composition does not capture a retained frame.
use super::*;

#[test]
fn frame_reuse_checks_used_ids_instead_of_unrelated_table_frontiers() {
    use std::sync::Arc;
    for has_local in [false, true] {
        let (mut batch, _) = ownership_fixture_source("/proc/frontier_probe()\n    return 1\n");
        if has_local {
            batch.units[0].lowered.frame.local_count = 1;
            batch.units[0].lowered.frame.local_names = vec!["frontier_local".into()];
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
    batch.units[0].lowered.frame.local_count = 1;
    batch.units[0].lowered.frame.local_names = vec!["current_local".into()];
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
    batch.units[0].lowered.frame.argument_names = vec!["argument".into()];
    batch.units[0].lowered.frame.argument_type_flags = vec![0];
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
