use super::*;
use crate::rsc::{Entry, NamedResource};

#[test]
fn writer_rejects_unterminated_and_multiline_header_fields() {
    for line in [
        b"min compatibility v516 516".as_slice(),
        b"min compatibility v516 516\nextra\n",
    ] {
        let mut dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        dmb.header.compatibility_line = line.to_vec();
        assert!(dmb.to_bytes().is_err());
    }
    let mut dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    dmb.header.executor_line = Some(b"#!/usr/bin/env DreamDaemon".to_vec());
    assert!(dmb.to_bytes().is_err());
    dmb.header.executor_line =
        Some(b"#!cmd\nworld bin v516\nmin compatibility v516 516\n".to_vec());
    assert!(dmb.to_bytes().is_err());
}

#[test]
fn native_wide_proc_reserved_record_is_the_only_blank_exception() {
    let mut dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let filler = dmb.procs[0].clone();
    dmb.procs.resize(0x10000, filler);
    let blank = Proc {
        strings: [0xffff; 4],
        source_parameter: 255,
        source_kind: 0,
        flags: 4,
        extended_flags: None,
        code_locals_args: [0xffff; 3],
    };
    dmb.procs[0xffff] = blank.clone();
    assert!(dmb.is_reserved_proc_slot(0xffff));
    assert!(!dmb.is_reserved_proc_slot(0x10000));
    dmb.lists.resize(0x10000, Vec::new());
    dmb.lists[0xffff] = vec![0, 0, 0, 0];
    assert!(dmb.proc_code_words(0xffff).is_none());
    assert!(dmb.proc_arguments(0xffff).is_none());
    dmb.validate_references().unwrap();
    dmb.procs[0xffff].flags = 0;
    assert!(!dmb.is_reserved_proc_slot(0xffff));
    assert!(dmb.validate_references().is_err());
    dmb.procs[0xffff] = blank.clone();
    dmb.procs[0xfffe] = blank;
    assert!(!dmb.is_reserved_proc_slot(0xfffe));
    assert!(dmb.validate_references().is_err());
}

#[test]
fn finalized_list_compaction_preserves_semantics_and_roundtrip() {
    let mut dmb = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/builtin_next.native.bin"
    ))
    .unwrap();
    let before = dmb.clone();
    // A duplicate live procedure body plus an unreachable construction snapshot.
    let old = dmb.procs[0].code_locals_args[0];
    let duplicate = dmb.lists.len() as u32;
    dmb.lists.push(dmb.lists[old as usize].clone());
    dmb.procs[0].code_locals_args[0] = duplicate;
    dmb.lists.push(vec![0xdead_beef]);
    assert!(dmb.compact_lists().unwrap() >= 2);
    #[cfg(feature = "inspection")]
    {
        assert!(crate::compare::compare_dmbs(&before, &dmb, &Default::default()).is_empty());
        assert!(crate::compare::compare_maps(&before, &dmb, 100).is_empty());
    }
    for index in 0..before.procs.len() {
        assert_eq!(before.proc_code_words(index), dmb.proc_code_words(index));
    }
    let encoded = dmb.to_bytes().unwrap();
    let decoded = Dmb::from_bytes(&encoded).unwrap();
    assert_eq!(decoded.to_bytes().unwrap(), encoded);
    assert_eq!(dmb.compact_lists().unwrap(), 0);
}

#[test]
fn list_compaction_keeps_none_reserved_above_u16() {
    let mut dmb = minimal();
    dmb.lists = (0..65_538).map(|i| vec![i]).collect();
    dmb.grid = (0..65_538)
        .filter(|&i| i != 0xffff)
        .map(|i| GridRun {
            turf: 0xffff,
            area: 0xffff,
            contents: i,
            copies: 1,
        })
        .collect();
    let words: Vec<_> = dmb
        .grid
        .iter()
        .map(|run| dmb.lists[run.contents as usize].clone())
        .collect();
    dmb.compact_lists().unwrap();
    assert_eq!(dmb.world.ids[3], 0xffff);
    assert_eq!(dmb.variable_footer, 0xffff);
    assert!(dmb.lists.len() > 65_535);
    assert!(dmb.lists[65_535].is_empty());
    for (run, expected) in dmb.grid.iter().zip(words) {
        assert_ne!(run.contents, 0xffff);
        assert_eq!(dmb.lists[run.contents as usize], expected);
    }
}

#[test]
fn optional_class_list_ids_do_not_resolve_list_65535() {
    let mut dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let class_id = dmb
        .classes
        .iter()
        .position(|class| dmb.string(class.path_string_id()) == Some(b"/alist"))
        .unwrap();
    assert_eq!(dmb.classes[class_id].defining_variable_list_id(), 0xffff);
    assert_eq!(dmb.classes[class_id].initialized_variable_list_id(), 0xffff);
    assert_eq!(dmb.classes[class_id].overriding_variable_list_id(), 0xffff);
    dmb.lists.resize(65_536, Vec::new());
    dmb.lists[65_535] = vec![0, 0];
    assert_eq!(dmb.class_variable_declarations(class_id), None);
    assert_eq!(dmb.class_initial_values(class_id), None);
    assert_eq!(dmb.class_builtin_overrides(class_id), None);
}

fn minimal() -> Dmb {
    Dmb {
        header: Header {
            executor_line: None,
            version_line: b"world bin v516\n".to_vec(),
            compatibility_line: b"min compatibility v516 516\n".to_vec(),
            flags: 0x4000_0000,
            extended_flags: None,
        },
        dimensions: [1, 1, 1],
        grid: vec![GridRun {
            turf: 0xffff,
            area: 0xffff,
            contents: 0xffff,
            copies: 1,
        }],
        classes: vec![],
        mobs: vec![],
        strings: vec![DmString {
            data: b"hello".to_vec(),
            long_chunks: 0,
        }],
        lists: vec![vec![0, 42]].into(),
        procs: vec![],
        variables: vec![],
        variable_footer: 0xffff,
        proc_references: vec![],
        instances: vec![],
        map_objects: vec![],
        world: World {
            ids: [0xffff; 7],
            tick_lag: 10,
            client: 0xffff,
            image: 0xffff,
            savefile_byond_version: 0,
            eye: 0,
            direction: 2,
            control: 0,
            unknown_byte: 0,
            client_script: 0xffff,
            client_script_files: vec![],
            view_dimensions: 0x0b0b,
            hub_password: 0xffff,
            server_name: 0xffff,
            hub_number: 0,
            version: 0,
            cache_lifespan: 0,
            command_ids: [0xffff; 2],
            hub_channel_skin: [0xffff; 3],
            icon_dimensions_format: [32, 32, 0],
        },
        resources: vec![ResourceRef { id: 23, kind: 6 }],
    }
}

#[test]
fn list_delta_validator_checks_affected_local_and_argument_schemas() {
    let mut dmb = minimal();
    dmb.variables.push(Variable {
        kind: 0,
        value: 0,
        name: 0,
    });
    dmb.lists.extend([vec![0], Vec::new()]);
    dmb.procs.push(Proc {
        strings: [0; 4],
        source_parameter: 0,
        source_kind: 0,
        flags: 0,
        extended_flags: None,
        code_locals_args: [0, 1, 2],
    });
    dmb.validate_references().unwrap();
    dmb.lists[0] = vec![0, 42, 0];
    dmb.validate_changed_lists(&[0]).unwrap();
    dmb.lists[1] = vec![1];
    assert!(dmb.validate_changed_lists(&[1]).is_err());
    assert!(dmb.validate_references().is_err());
    dmb.lists[1] = vec![0];
    dmb.lists[2] = vec![7];
    assert!(dmb.validate_changed_lists(&[2]).is_err());
    assert!(dmb.validate_changed_lists(&[u32::MAX]).is_err());
    dmb.lists[2].clear();
    dmb.validate_changed_lists(&[0, 1, 2]).unwrap();
    dmb.validate_references().unwrap();
}

#[test]
fn string_change_reencodes_offsets_and_checksum() {
    let mut dmb = minimal();
    let original = dmb.to_bytes().unwrap();
    assert_eq!(Dmb::from_bytes(&original).unwrap(), dmb);
    dmb.strings[0].data = b"a longer string".to_vec();
    let changed = dmb.to_bytes().unwrap();
    assert_ne!(changed, original);
    assert_eq!(Dmb::from_bytes(&changed).unwrap(), dmb);
}

#[test]
fn narrow_object_ids_roundtrip_and_reject_overflow() {
    let mut dmb = minimal();
    dmb.header.flags &= !0x4000_0000;
    dmb.header.compatibility_line = b"min compatibility v516 468\n".to_vec();
    let encoded = dmb.to_bytes().unwrap();
    assert_eq!(Dmb::from_bytes(&encoded).unwrap(), dmb);
    dmb.grid[0].turf = 0x1_0000;
    assert!(dmb.to_bytes().is_err());
}

#[test]
fn compatibility_514_omits_savefile_version() {
    let mut dmb = minimal();
    dmb.header.flags &= !0x4000_0000;
    dmb.header.compatibility_line = b"min compatibility v514 468\n".to_vec();
    let bytes = dmb.to_bytes().unwrap();
    assert_eq!(Dmb::from_bytes(&bytes).unwrap(), dmb);
}

#[test]
fn world_view_dimensions_match_dm_order() {
    let mut world = minimal().world;
    world.set_view_size(9, 13);
    assert_eq!(world.view_dimensions, 0x090d);
    assert_eq!(world.view_size(), (9, 13));
}

#[test]
fn extended_header_word_round_trips() {
    let mut dmb = minimal();
    assert_eq!(dmb.header.movement_mode_setting(), Some(0));
    dmb.header.flags |= 0x8000_0000;
    dmb.header.extended_flags = Some(0x1234_567c);
    assert_eq!(dmb.header.movement_mode_setting(), None);
    let encoded = dmb.to_bytes().unwrap();
    assert_eq!(Dmb::from_bytes(&encoded).unwrap(), dmb);
    dmb.header.extended_flags = None;
    assert!(dmb.to_bytes().is_err());
}

#[test]
fn declaration_and_argument_lists_decode_without_losing_raw_words() {
    let mut dmb = minimal();
    dmb.strings.push(DmString {
        data: b"target".to_vec(),
        long_chunks: 0,
    });
    dmb.variables.push(Variable {
        kind: 0,
        value: 0,
        name: 1,
    });
    dmb.lists.push(vec![0, 5]);
    let declarations = (dmb.lists.len() - 1) as u32;
    dmb.classes.push(Class {
        initial_ids: [0; 6],
        direction: 2,
        interface: 1,
        extended_interface: None,
        text: 0xffff,
        maptext: 0xffff,
        maptext_geometry: [0; 4],
        suffix: 0xffff,
        flags: 4,
        lists_and_procs: [0xffff, 0xffff, 0xffff, 0xffff, declarations, 0xffff],
        layer_bits: 0,
        transform_flag: 0,
        transform: None,
        color_matrix_flag: 0,
        color_matrix: None,
        overrides: 0xffff,
    });
    assert_eq!(dmb.class_variable_declarations(0), Some(vec![(0, 5)]));
    dmb.lists.push(vec![8, 0x7d01, 0, 0]);
    let args = (dmb.lists.len() - 1) as u32;
    dmb.procs.push(Proc {
        strings: [0; 4],
        source_parameter: 0,
        source_kind: 0,
        flags: 0,
        extended_flags: None,
        code_locals_args: [0xffff, 0xffff, args],
    });
    let decoded = dmb.proc_arguments(0).unwrap();
    let borrowed = dmb.proc_arguments_iter(0).unwrap();
    assert_eq!(borrowed.len(), decoded.len());
    assert_eq!(borrowed.clone().collect::<Vec<_>>(), decoded);
    assert_eq!(borrowed.collect::<Vec<_>>(), decoded);
    assert_eq!(decoded.len(), 1);
    assert_eq!(decoded[0].value_source_kind(), 1);
    assert_eq!(decoded[0].value_source_parameter(), 125);
    assert_eq!(decoded[0].variable_id, 0);
    let source = ProcArgument {
        value_source: 0x140,
        ..decoded[0]
    };
    assert_eq!(source.source_expression_index(), Some(1));
    dmb.proc_references = vec![0, 7];
    assert_eq!(dmb.argument_source_proc_id(&source), Some(7));
    dmb.lists[args as usize].push(0);
    assert!(dmb.proc_arguments_iter(0).is_none());
    assert!(dmb.proc_arguments(0).is_none());
    assert!(dmb.proc_arguments_iter(usize::MAX).is_none());
}

#[test]
fn extended_proc_flags_match_compiler_settings() {
    let proc = Proc {
        strings: [0; 4],
        source_parameter: 0,
        source_kind: 0,
        flags: 0x80,
        extended_flags: Some((0x285, 0)),
        code_locals_args: [0; 3],
    };
    assert!(proc.is_hidden());
    assert!(proc.is_instant());
    assert!(proc.waits_for_completion());
    assert!(!proc.runs_in_background());
    assert_eq!(proc.invisibility_setting(), None);
    let mut proc = proc;
    proc.extended_flags = Some((0x9c, 42));
    assert_eq!(proc.invisibility_setting(), Some(42));
    proc.extended_flags = Some((0x8c, 255));
    assert_eq!(proc.invisibility_setting(), Some(0));
    proc.source_kind = 1;
    proc.source_parameter = 5;
    assert_eq!(proc.source_location(), ProcSource::InView(5));
}

#[test]
fn extended_mob_sight_keeps_setting_bytes_distinct_from_flags() {
    let mob = MobType {
        class: 0,
        key: 0xffff,
        sight: 0x80,
        extended_sight: Some((0x10084, 12, 42)),
    };
    assert_eq!(
        mob.sight_bits(),
        mob_sight::SEE_INFRARED | mob_sight::SEE_MOBS
    );
    assert_eq!(mob.see_in_dark_setting(), Some(12));
    assert_eq!(mob.see_invisible_setting(), Some(42));
}

#[test]
fn appearance_flags_occupy_high_class_flag_bits() {
    let mut class = Class {
        initial_ids: [0; 6],
        direction: 2,
        interface: 1,
        extended_interface: None,
        text: 0xffff,
        maptext: 0xffff,
        maptext_geometry: [0; 4],
        suffix: 0xffff,
        flags: 0x6430_4804,
        lists_and_procs: [0xffff; 6],
        layer_bits: 0,
        transform_flag: 0,
        transform: None,
        color_matrix_flag: 0,
        color_matrix: None,
        overrides: 0xffff,
    };
    assert_eq!(class.appearance_flags(), 0x321);
    assert_eq!(class.native_interface(), ClassInterface::Regular);
    assert!(!class.is_dense());
    assert!(!class.is_opaque());
    assert_eq!(class.gender_code(), 0);
    assert_eq!(class.mouse_opacity(), 1);
    assert!(class.is_normally_visible());
    assert!(class.has_mouse_event_proc());
    assert!(!class.has_mouse_move_proc());
    assert!(class.has_mouse_wheel_proc());
    assert_eq!(class.animate_movement(), 2);
    class.set_opaque(true);
    assert!(class.is_opaque());
    class.set_opaque(false);
    class.set_dense(true);
    assert!(class.is_dense());
    class.set_dense(false);
    class.set_gender_code(2).unwrap();
    assert_eq!(class.gender_code(), 2);
    class.set_gender_code(0).unwrap();
    class.set_mouse_opacity(0).unwrap();
    assert_eq!(class.mouse_opacity(), 0);
    class.set_mouse_opacity(1).unwrap();
    class.set_luminosity(7).unwrap();
    assert_eq!(class.luminosity(), 7);
    class.set_luminosity(0).unwrap();
    class.set_animate_movement(0).unwrap();
    assert_eq!(class.animate_movement(), 0);
    class.set_animate_movement(2).unwrap();
    class.set_appearance_flags(0x100);
    assert_eq!(class.flags, 0x2010_4804);
}

#[test]
fn resource_refs_match_archive_id_and_kind() {
    let dmb = minimal();
    let archive = [Entry::Named(NamedResource {
        kind: 6,
        id: 23,
        timestamp: 0,
        source_timestamp: 0,
        declared_size: 0,
        name: b"icon.png".to_vec(),
        data: vec![],
    })];
    assert!(dmb.missing_resources(&archive).is_empty());
    assert_eq!(dmb.missing_resources(&[]), dmb.resources);
    assert_eq!(
        ResourceLookup::new(&archive)
            .get(&dmb, ResourceId::from_raw(0).unwrap())
            .unwrap()
            .name,
        b"icon.png"
    );
}

#[test]
fn writer_rejects_dangling_cross_table_reference() {
    let mut dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    dmb.validate_references().unwrap();
    dmb.classes[0].lists_and_procs[2] = dmb.procs.len() as u32 + 1;
    assert_eq!(dmb.to_bytes().unwrap_err().kind(), ErrorKind::InvalidData);
}

#[test]
fn attach_resource_writes_matching_dmb_and_rsc_entries() {
    let mut dmb = minimal();
    let mut archive = Vec::new();
    let resource = NamedResource::from_data(6, b"new.png".to_vec(), b"abc".to_vec(), 0, 0).unwrap();
    let index = {
        let mut batch = ResourceAttachment::new(&mut dmb, &mut archive);
        let index = batch.attach(resource.clone()).unwrap();
        assert_eq!(batch.attach(resource.clone()).unwrap(), index);
        index
    };
    assert_eq!(index.raw(), 1);
    assert_eq!(
        ResourceLookup::new(&archive).get(&dmb, index),
        Some(&resource)
    );
    assert_eq!(archive.len(), 1);
}

#[test]
fn indexed_resource_batch_reuses_entries() {
    let mut dmb = minimal();
    let mut archive = Vec::new();
    let first = NamedResource::from_data(6, b"one.txt".to_vec(), b"one".to_vec(), 0, 0).unwrap();
    let second = NamedResource::from_data(6, b"two.txt".to_vec(), b"two".to_vec(), 0, 0).unwrap();
    let (first_id, second_id) = {
        let mut batch = ResourceAttachment::new(&mut dmb, &mut archive);
        let first_id = batch.attach(first.clone()).unwrap();
        let second_id = batch.attach(second.clone()).unwrap();
        assert_eq!(batch.attach(first.clone()).unwrap(), first_id);
        (first_id, second_id)
    };
    assert_eq!(archive.len(), 2);
    let lookup = ResourceLookup::new(&archive);
    assert_eq!(lookup.get(&dmb, first_id), Some(&first));
    assert_eq!(lookup.get(&dmb, second_id), Some(&second));
}

#[test]
fn code_edit_uses_a_fresh_list_slot() {
    let mut dmb = minimal();
    // The raw list under test is not a procedure locals/arguments table.
    let empty_list = dmb.lists.len() as u32;
    dmb.lists.push(Vec::new());
    dmb.procs.push(Proc {
        strings: [0; 4],
        source_parameter: 0,
        source_kind: 0,
        flags: 0,
        extended_flags: None,
        code_locals_args: [0, empty_list, empty_list],
    });
    let old_list = dmb.lists[0].clone();
    let instructions = crate::bytecode::decode(&[0x50, 7, 0]).unwrap();
    dmb.replace_proc_code(0, &instructions).unwrap();
    assert_eq!(dmb.lists[0], old_list);
    assert_eq!(dmb.proc_code_words(0).unwrap(), [0x50, 7, 0]);
    let reparsed = Dmb::from_bytes(&dmb.to_bytes().unwrap()).unwrap();
    assert_eq!(reparsed.proc_code_words(0).unwrap(), [0x50, 7, 0]);
}
