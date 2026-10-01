use super::*;

#[test]
fn wide_class_and_proc_tables_keep_native_nullable_id_holes() {
    let mut template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    template.classes.resize(NONE as usize, native_blank_class());
    let filler_proc = template.procs[0].clone();
    template.procs.resize(NONE as usize, filler_proc);
    let mut input = OpenDreamProgram::from_slice(
        br#"{
            "Metadata":{"Version":"test"}, "Strings":[], "Resources":[], "Maps":[],
            "Types":[{"Path":"/"},{"Path":"/world","Parent":0},
                {"Path":"/datum","Parent":0},{"Path":"/atom","Parent":2},
                {"Path":"/atom/movable","Parent":3},{"Path":"/obj","Parent":4},
                {"Path":"/obj/boundary","Parent":5,"Procs":[[0]]}],
            "Procs":[{"Name":"boundary","OwningTypeId":6,"Bytecode":"lwI="}]
        }"#,
    )
    .unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let mut authored_type = input.types.pop().unwrap();
    let mut authored_proc = input.procs.pop().unwrap();
    input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let authored_type_id = input.types.len();
    let authored_proc_id = input.procs.len();
    authored_type.parent = input.types.iter().position(|typ| typ.path == "/obj");
    authored_type.procs = vec![vec![authored_proc_id]];
    authored_proc.owning_type_id = authored_type_id;
    input.types.push(authored_type);
    input.procs.push(authored_proc);
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
    assert_eq!(emitted.dmb.classes[NONE as usize], native_blank_class());
    assert_eq!(emitted.dmb.procs[NONE as usize], native_blank_proc());
    let class = emitted.ids.classes[authored_type_id];
    let proc = emitted.ids.procs[authored_proc_id];
    assert_ne!(class, NONE);
    assert_ne!(proc, NONE);
    assert_eq!(
        emitted
            .dmb
            .string(emitted.dmb.classes[class as usize].path_string_id()),
        Some(b"/obj/boundary".as_slice())
    );
    assert_eq!(
        emitted
            .dmb
            .string(emitted.dmb.procs[proc as usize].strings[0]),
        Some(b"/obj/boundary/proc/boundary".as_slice())
    );
    let bytes = emitted.dmb.to_bytes().unwrap();
    let reread = Dmb::from_bytes(&bytes).unwrap();
    reread.validate_references().unwrap();
    assert_eq!(reread.to_bytes().unwrap(), bytes);
}

#[test]
fn instance_allocation_rejects_native_save_crash_boundary() {
    let mut template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    template
        .instances
        .resize(NONE as usize, template.instances[0].clone());
    let input = OpenDreamProgram::from_slice(
        br#"{
            "Metadata":{"Version":"test"}, "Strings":[], "Resources":[], "Maps":[],
            "Types":[{"Path":"/"},{"Path":"/world","Parent":0},
                {"Path":"/obj","Parent":0},{"Path":"/obj/boundary","Parent":2}],"Procs":[]
        }"#,
    )
    .unwrap();
    let error = emit(&input, &template, Path::new(".")).err().unwrap();
    assert!(error
        .to_string()
        .contains("instance table reaches native unsupported ID 65535"));
}

#[test]
fn authored_global_at_temporary_variable_65535_is_initialized_and_reindexed() {
    let mut template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    template.variables.resize(
        NONE as usize,
        Variable {
            kind: 0,
            value: 0,
            name: NONE,
        },
    );
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let globals = input.globals.as_mut().unwrap();
    let authored_global_id = globals.names.len();
    globals.names.push("wide_global".into());
    globals.global_count += 1;
    globals.globals.insert(authored_global_id, JsonValue::Null);
    globals
        .dynamic_initializer_global_ids
        .insert(authored_global_id);
    let output = emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
    let id = output.ids.globals[authored_global_id];
    assert_ne!(
        id, NONE,
        "authored globals reorder ahead of scaffold locals"
    );
    let variable = &output.dmb.variables[id as usize];
    assert_eq!(
        output.dmb.string(variable.name),
        Some(b"wide_global".as_slice())
    );
    assert_eq!(
        variable.kind, 62,
        "temporary Variable65535 must receive its dynamic marker"
    );
    assert!(output.dmb.lists[output.dmb.variable_footer as usize]
        .chunks_exact(2)
        .any(|record| record[0] == id));
    let reread = Dmb::from_bytes(&output.dmb.to_bytes().unwrap()).unwrap();
    reread.validate_references().unwrap();
    assert_eq!(reread.variables[id as usize], *variable);
}

#[test]
fn emits_new_type_without_copying_opendream_native_classes() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let json = br#"{
            "Metadata":{"Version":"test"}, "Strings":[], "Resources":[], "Maps":[],
            "Types":[
                {"Path":"/"},
                {"Path":"/world","Parent":0},
                {"Path":"/obj","Parent":0},
                {"Path":"/obj/item","Parent":2,"Variables":{"value":5}}
            ],
            "Procs":[]
        }"#;
    let input = OpenDreamProgram::from_slice(json).unwrap();
    let output = emit(&input, &template, Path::new(".")).unwrap();
    assert_eq!(output.ids.classes[0], NONE);
    assert_eq!(output.ids.classes[1], NONE);
    assert_eq!(output.dmb.classes.len(), template.classes.len() + 1);
    assert_eq!(output.dmb.instances.len(), template.instances.len() + 1);
    assert_eq!(
        output.dmb.instances[output.ids.instances[3] as usize].class,
        output.ids.classes[3]
    );
    assert_eq!(
        output
            .dmb
            .string(output.dmb.classes[output.ids.classes[3] as usize].path_string_id()),
        Some(&b"/obj/item"[..])
    );
    Dmb::from_bytes(&output.dmb.to_bytes().unwrap())
        .unwrap()
        .validate_references()
        .unwrap();
}

#[test]
fn real_opendream_smoke_emits_only_authored_procedures() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let smoke =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/opendream_smoke.json")).unwrap();
    let output = emit_with_baseline(&smoke, Some(&native), &template, Path::new(".")).unwrap();
    assert_eq!(output.dmb.classes.len(), template.classes.len() + 1);
    assert_eq!(output.dmb.procs.len(), template.procs.len() + 3);
    assert_eq!(output.ids.procs.iter().filter(|&&id| id != NONE).count(), 3);
    output.dmb.validate_references().unwrap();
}

#[test]
fn map_override_and_text_resource_have_native_record_shapes() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let maps =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/maps.json")).unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let native_maps = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&maps, Some(&native_maps), &template, &root).unwrap();
    assert_eq!(emitted.dmb.dimensions, [1, 1, 1]);
    assert_eq!(emitted.dmb.grid.len(), 1);
    assert_eq!(emitted.dmb.grid[0].contents, NONE);
    assert_eq!(emitted.dmb.map_objects.len(), 1);
    let instance = &emitted.dmb.instances[emitted.dmb.map_objects[0].instance as usize];
    assert_eq!(instance.kind, 9);
    assert_ne!(instance.initializer, NONE);
    let code = emitted
        .dmb
        .proc_code_words(instance.initializer as usize)
        .unwrap();
    assert_eq!(&code[..3], &[0x50, 12, 0x34]);
    let assets =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/assets.json"))
            .unwrap();
    let emitted = emit_with_baseline(&assets, Some(&native), &template, &root).unwrap();
    assert_eq!(emitted.dmb.resources.len(), 1);
    assert_eq!(emitted.dmb.resources[0].kind, 0);
    assert_eq!(emitted.resources.len(), 1);
    let format_id = assets
        .strings
        .iter()
        .position(|text| text == "ASSETS \u{ff00}")
        .unwrap();
    assert_eq!(
        emitted.dmb.string(emitted.ids.strings[format_id]),
        Some(&b"ASSETS \xff\x01"[..])
    );
}
#[test]
fn resource_alias_adds_archive_name_without_another_dmb_resource() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/assets.json"))
            .unwrap();
    input
        .resource_aliases
        .insert("Asset.txt".into(), "asset.txt".into());
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, &root).unwrap();
    assert_eq!(emitted.dmb.resources.len(), 1);
    let names: HashSet<_> = emitted
        .resources
        .iter()
        .filter_map(|entry| match entry {
            Entry::Named(named) => Some(named.name.as_slice()),
            _ => None,
        })
        .collect();
    assert_eq!(
        names,
        HashSet::from([b"asset.txt".as_slice(), b"Asset.txt".as_slice()])
    );
}
#[test]
fn literal_fullwidth_characters_bypass_native_format_controls() {
    for value in 0xff00..=0xff5e {
        let literal = char::from_u32(value).unwrap();
        let escaped = format!("\u{ff5e}{literal}");
        let mut encoded = [0; 4];
        assert_eq!(
            native_string_bytes(&escaped),
            literal.encode_utf8(&mut encoded).as_bytes()
        );
    }
    assert_eq!(
        native_string_bytes("\u{ff5e}\u{ff21}\u{ff21}"),
        [0xef, 0xbc, 0xa1, 0xff, 0x12]
    );
    assert_eq!(
        native_string_bytes("\u{ff5e}\u{ff12}\u{ff12}\u{ff01}"),
        [0xef, 0xbc, 0x92, 0xff, 0x2c]
    );
    assert_eq!(native_string_bytes("\u{ff5e}A"), "\u{ff5e}A".as_bytes());
}

#[test]
fn improper_article_marker_uses_native_string_bytes() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/assets.json"))
            .unwrap();
    input.strings.push("\u{ff11}Telecomms Storage".into());
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, &root).unwrap();
    let id = *emitted.ids.strings.last().unwrap();
    assert_eq!(
        emitted.dmb.string(id),
        Some(&b"\xff\x16Telecomms Storage"[..])
    );
}
#[test]
fn all_observed_format_markers_match_paired_native_bytes() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/assets.json"))
            .unwrap();
    let cases = [
        (0x00, 0x02),
        (0x01, 0x03),
        (0x03, 0x2a),
        (0x04, 0x09),
        (0x05, 0x08),
        (0x06, 0x07),
        (0x07, 0x06),
        (0x09, 0x0a),
        (0x0b, 0x0c),
        (0x0d, 0x11),
        (0x0f, 0x0e),
        (0x10, 0x15),
        (0x11, 0x16),
        (0x12, 0x2c),
        (0x13, 0x2d),
        (0x14, 0x05),
        (0x15, 0x14),
    ];
    let first = input.strings.len();
    for &(suffix, _) in &cases {
        input.strings.push(if matches!(suffix, 0x12 | 0x13) {
            format!("{}\u{ff01}", char::from_u32(0xff00 + suffix).unwrap())
        } else {
            char::from_u32(0xff00 + suffix).unwrap().to_string()
        });
    }
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/translation");
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, &root).unwrap();
    for (index, &(_, native)) in cases.iter().enumerate() {
        assert_eq!(
            emitted.dmb.string(emitted.ids.strings[first + index]),
            Some(&[0xff, native][..])
        );
    }
}
#[test]
fn leading_interpolation_templates_match_native_operand_types_and_boundaries() {
    let source =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/stringtypes.json"))
            .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/stringtypes.native.bin"
    ))
    .unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let first = input.strings.len();
    input.strings.extend(
        source
            .strings
            .iter()
            .filter(|value| value.contains('\u{ff00}') && !baseline.strings.contains(value))
            .cloned(),
    );
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures");
    let output = emit_with_baseline(&input, Some(&baseline), &template, &root).unwrap();
    assert!(input.strings.len() > first + 5);
    for index in first..input.strings.len() {
        let encoded = output.dmb.string(output.ids.strings[index]).unwrap();
        assert!(
            native.strings.iter().any(|value| value.data == encoded),
            "unmatched template {:?}: {encoded:?}",
            input.strings[index]
        );
    }
}
#[test]
fn sentence_and_markup_interpolation_context_matches_native_templates() {
    let source = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/format_context.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/format_context.native.bin"
    ))
    .unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let first = input.strings.len();
    input.strings.extend(
        source
            .strings
            .iter()
            .filter(|value| {
                value
                    .chars()
                    .any(|ch| (0xff00..=0xff1f).contains(&(ch as u32)))
                    && !baseline.strings.contains(value)
            })
            .cloned(),
    );
    assert!(input.strings.len() > first + 100);
    let output = emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
    for index in first..input.strings.len() {
        let bytes = output.dmb.string(output.ids.strings[index]).unwrap();
        assert!(
            native.strings.iter().any(|string| string.data == bytes),
            "template {:?} differs from native: {bytes:?}",
            input.strings[index]
        );
    }
}

#[test]
fn interpolation_sentence_scan_preserves_native_delimiter_boundaries() {
    for prefix in [
        b"".as_slice(),
        b" \t\n",
        b"K.",
        b"K!",
        b"K?",
        b"K.\t\n\"",
        b"<div>",
        b"</div>",
        b"<div><span>",
        b"<!--comment-->",
        b"K.<div>",
        b"K>>",
    ] {
        assert!(native_interpolation_starts_sentence(prefix), "{prefix:?}");
    }
    for prefix in [
        b"K".as_slice(),
        b"K:",
        b"K;",
        b"K,",
        b"K\n",
        b"K\t",
        b"K.)",
        b"&nbsp;",
        b"<div>X</div>",
        b"K<div>",
        b"<<>>",
        b"<!-- < -->",
        b"<tag a=\"<x>\">",
        b"<a><",
        b"\xff\x15<div>",
        b"K.\xff\x2a ",
    ] {
        assert!(!native_interpolation_starts_sentence(prefix), "{prefix:?}");
    }
}

#[test]
fn unpaired_format_marker_is_an_explicit_error() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let json = br#"{
            "Metadata":{"Version":"test"}, "Strings":["\uff02"],
            "Resources":[], "Maps":[],
            "Types":[{"Path":"/"},{"Path":"/world","Parent":0}],
            "Procs":[]
        }"#;
    let input = OpenDreamProgram::from_slice(json).unwrap();
    let result = emit(&input, &template, Path::new("."));
    assert!(matches!(result, Err(EmitError::Unsupported(message)) if message.contains("U+FF02")));
}
#[test]
fn promoted_mob_defaults_and_savefile_version_match_native_metadata() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_metadata_defaults_5161687.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/metadata_defaults.native.bin"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/metadata_defaults.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
        .unwrap()
        .dmb;
    let settings = |dmb: &Dmb, path: &str| {
        let class = dmb
            .classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(path.as_bytes()))
            .unwrap();
        let mob = dmb
            .mobs
            .iter()
            .find(|mob| mob.class == class as u32)
            .unwrap();
        (
            mob.sight_bits(),
            mob.see_in_dark_setting().unwrap_or(2),
            mob.see_invisible_setting().unwrap_or(0),
        )
    };
    for path in input
        .types
        .iter()
        .map(|typ| typ.path.as_str())
        .filter(|path| path.starts_with("/mob/metadata_defaults"))
    {
        assert_eq!(settings(&emitted, path), settings(&native, path), "{path}");
    }
    assert_eq!(native.world.savefile_byond_version, 0);
    assert_eq!(
        emitted.world.savefile_byond_version,
        native.world.savefile_byond_version
    );
    assert_eq!(
        Dmb::from_bytes(&emitted.to_bytes().unwrap())
            .unwrap()
            .world
            .savefile_byond_version,
        0
    );
}

#[test]
fn mutable_appearance_subtypes_have_native_plain_prototypes() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/mutable_appearance_subtype.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/mutable_appearance_subtype.native.bin"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
    for path in [
        "/mutable_appearance/fixture",
        "/mutable_appearance/fixture/child",
    ] {
        let prototypes = |dmb: &Dmb| {
            dmb.instances
                .iter()
                .filter(|instance| {
                    instance.kind == 63
                        && instance.initializer == NONE
                        && dmb
                            .classes
                            .get(instance.class as usize)
                            .is_some_and(|class| {
                                dmb.string(class.path_string_id()) == Some(path.as_bytes())
                            })
                })
                .count()
        };
        assert_eq!(prototypes(&native), 1, "{path}");
        assert_eq!(prototypes(&emitted.dmb), prototypes(&native), "{path}");
        let old_type = input.types.iter().position(|typ| typ.path == path).unwrap();
        let instance = &emitted.dmb.instances[emitted.ids.instances[old_type] as usize];
        assert_eq!(instance.kind, 63);
    }
    let bytes = emitted.dmb.to_bytes().unwrap();
    assert_eq!(Dmb::from_bytes(&bytes).unwrap().to_bytes().unwrap(), bytes);
}

#[test]
fn authored_savefile_version_matches_native_and_survives_roundtrip() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let cases: &[(&[u8], &[u8])] = &[
        (
            include_bytes!("../fixtures/translation/savefile_default.json"),
            include_bytes!("../fixtures/translation/savefile_default.native.bin"),
        ),
        (
            include_bytes!("../fixtures/translation/savefile_0.json"),
            include_bytes!("../fixtures/translation/savefile_0.native.bin"),
        ),
        (
            include_bytes!("../fixtures/translation/savefile_513.json"),
            include_bytes!("../fixtures/translation/savefile_513.native.bin"),
        ),
        (
            include_bytes!("../fixtures/translation/savefile_516.json"),
            include_bytes!("../fixtures/translation/savefile_516.native.bin"),
        ),
    ];
    for &(json, bytes) in cases {
        let input = OpenDreamProgram::from_slice(json).unwrap();
        let native = Dmb::from_bytes(bytes).unwrap();
        let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
            .unwrap()
            .dmb;
        assert_eq!(
            emitted.world.savefile_byond_version,
            native.world.savefile_byond_version
        );
        let decoded = Dmb::from_bytes(&emitted.to_bytes().unwrap()).unwrap();
        assert_eq!(
            decoded.world.savefile_byond_version,
            native.world.savefile_byond_version
        );
    }
}

#[test]
fn legacy_compatibility_omits_savefile_compiler_version() {
    let mut template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    template.header.compatibility_line = b"min compatibility v514 507\n".to_vec();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let emitted = emit_with_baseline(&baseline, Some(&baseline), &template, Path::new("."))
        .unwrap()
        .dmb;
    assert_eq!(emitted.world.savefile_byond_version, 0);
    let decoded = Dmb::from_bytes(&emitted.to_bytes().unwrap()).unwrap();
    assert_eq!(decoded.world.savefile_byond_version, 0);
}

#[test]
fn world_procedure_membership_excludes_global_procedures() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_metadata_defaults_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/world_proc_scope.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/world_proc_scope.native.bin"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
        .unwrap()
        .dmb;
    let members = |dmb: &Dmb| {
        let mut names: Vec<_> = dmb
            .lists
            .get(dmb.world.ids[3] as usize)
            .into_iter()
            .flatten()
            .filter_map(|id| dmb.procs.get(*id as usize))
            .filter_map(|proc| dmb.string(proc.strings[0]))
            .map(|path| String::from_utf8_lossy(path).into_owned())
            .filter(|path| {
                path.ends_with("/global_not_world")
                    || path.ends_with("/global_verb_not_world")
                    || path.ends_with("/world_member")
            })
            .collect();
        names.sort();
        names
    };
    let expected = members(&native);
    assert_eq!(expected.len(), 1);
    assert!(expected[0].ends_with("/world_member"));
    assert_eq!(members(&emitted), expected);
    for proc in
        input.procs.iter().enumerate().filter(|(_, proc)| {
            proc.name == "global_not_world" || proc.name == "global_verb_not_world"
        })
    {
        assert!(emitted.procs.iter().any(|record| {
            emitted
                .string(record.strings[0])
                .is_some_and(|path| path.ends_with(proc.1.name.as_bytes()))
        }));
    }
}

#[test]
fn client_builtins_use_world_fields_and_header_flags() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let client = input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/client")
        .unwrap();
    client
        .variables
        .insert("control_freak".into(), JsonValue::from(1));
    client
        .variables
        .insert("preload_rsc".into(), JsonValue::from(0));
    client
        .variables
        .insert("script".into(), JsonValue::from("HELLO"));
    client
        .variables
        .insert("show_verb_panel".into(), JsonValue::from(0));
    client.explicit_type_fields.extend([
        "control_freak".into(),
        "preload_rsc".into(),
        "script".into(),
        "show_verb_panel".into(),
    ]);
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
    assert_eq!(emitted.dmb.world.control, 1);
    assert_ne!(emitted.dmb.header.flags & 0x800, 0);
    assert_ne!(emitted.dmb.header.flags & 0x400, 0);
    assert_eq!(
        emitted.dmb.string(emitted.dmb.world.client_script),
        Some(&b"HELLO"[..])
    );
    let class_id = emitted.ids.classes[input
        .types
        .iter()
        .position(|typ| typ.path == "/client")
        .unwrap()];
    let names: HashSet<Vec<u8>> = emitted
        .dmb
        .class_variable_declarations(class_id as usize)
        .unwrap_or_default()
        .into_iter()
        .map(|(id, _)| {
            emitted
                .dmb
                .string(emitted.dmb.variables[id as usize].name)
                .unwrap()
                .to_vec()
        })
        .collect();
    assert!(!names.contains(b"control_freak".as_slice()));
    assert!(!names.contains(b"preload_rsc".as_slice()));
    assert!(!names.contains(b"script".as_slice()));
    assert!(!names.contains(b"show_verb_panel".as_slice()));
}
#[test]
fn mob_path_constants_use_mob_table_and_movable_paths_use_tag_nine() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let json = br#"{
            "Metadata":{"Version":"test"}, "Strings":[], "Resources":[], "Maps":[],
            "Types":[
                {"Path":"/"}, {"Path":"/world","Parent":0},
                {"Path":"/datum","Parent":0}, {"Path":"/atom","Parent":0},
                {"Path":"/atom/movable","Parent":3}, {"Path":"/mob","Parent":4},
                {"Path":"/mob/test","Parent":5},
                {"Path":"/datum/holder","Parent":2,"Variables":{
                    "mob_path":{"type":1,"value":6},
                    "movable_path":{"type":1,"value":4}
                }},
                {"Path":"/datum/holder/child","Parent":7,"Variables":{
                    "mob_path":{"type":1,"value":6}
                }}
            ], "Procs":[]
        }"#;
    let input = OpenDreamProgram::from_slice(json).unwrap();
    let output = emit(&input, &template, Path::new(".")).unwrap();
    let holder = output.ids.classes[7] as usize;
    let declarations = output.dmb.class_variable_declarations(holder).unwrap();
    let mob_var = declarations
        .iter()
        .map(|pair| pair.0)
        .find(|&id| output.dmb.string(output.dmb.variables[id as usize].name) == Some(b"mob_path"))
        .unwrap();
    let mob = &output.dmb.variables[mob_var as usize];
    assert_eq!(mob.kind, 8);
    assert_eq!(
        output.dmb.mobs[mob.value as usize].class,
        output.ids.classes[6]
    );
    let movable_var = declarations
        .iter()
        .map(|pair| pair.0)
        .find(|&id| {
            output.dmb.string(output.dmb.variables[id as usize].name) == Some(b"movable_path")
        })
        .unwrap();
    assert_eq!(output.dmb.variables[movable_var as usize].kind, 9);
    assert_eq!(
        output.dmb.variables[movable_var as usize].value,
        output.ids.classes[4]
    );
    let child = output.ids.classes[8] as usize;
    let initial = output.dmb.class_initial_values(child).unwrap();
    let value = initial
        .iter()
        .find(|entry| entry.variable_id == mob_var)
        .unwrap();
    assert_eq!(value.value.tag(), 8);
    assert_eq!(
        output.dmb.mobs[value.value.id() as usize].class,
        output.ids.classes[6]
    );
}
#[test]
fn class_const_declaration_has_native_flags_three() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let json = br#"{
            "Metadata":{"Version":"test"}, "Strings":[], "Resources":[], "Maps":[],
            "Types":[
                {"Path":"/"}, {"Path":"/world","Parent":0},
                {"Path":"/datum","Parent":0},
                {"Path":"/datum/constant","Parent":2,
                 "Variables":{"limit":7},"ConstVariables":["limit"]}
            ], "Procs":[]
        }"#;
    let input = OpenDreamProgram::from_slice(json).unwrap();
    let output = emit(&input, &template, Path::new(".")).unwrap();
    let declarations = output
        .dmb
        .class_variable_declarations(output.ids.classes[3] as usize)
        .unwrap();
    assert_eq!(declarations.len(), 1);
    assert_eq!(declarations[0].1, 3);
}
#[test]
fn implicit_empty_initializer_has_a_class_proc() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let json = br#"{
            "Metadata":{"Version":"test"}, "Strings":[], "Resources":[], "Maps":[],
            "Types":[
                {"Path":"/"},
                {"Path":"/world","Parent":0},
                {"Path":"/datum","Parent":0},
                {"Path":"/datum/example","Parent":2,"ImplicitEmptyInitProc":true}
            ],
            "Procs":[]
        }"#;
    let input = OpenDreamProgram::from_slice(json).unwrap();
    let output = emit(&input, &template, Path::new(".")).unwrap();
    let class = &output.dmb.classes[output.ids.classes[3] as usize];
    let proc_id = class.lists_and_procs[2];
    assert_ne!(proc_id, NONE);
    assert_eq!(
        output.dmb.proc_code_words(proc_id as usize).unwrap(),
        vec![0]
    );
    output.dmb.validate_references().unwrap();
}
#[test]
fn map_override_assignments_follow_target_declaration_order() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/map_order.json"))
            .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/map_order.native.bin"
    ))
    .unwrap();
    let emitted = emit_diagnostic_with_baseline_named(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
        None,
    )
    .unwrap();
    let fields = |dmb: &Dmb| {
        let instance = dmb
            .instances
            .iter()
            .find(|instance| {
                instance.kind == 9
                    && instance.initializer != NONE
                    && dmb.string(dmb.classes[instance.class as usize].path_string_id())
                        == Some(b"/obj/marker")
            })
            .unwrap();
        dmb.proc_code_words(instance.initializer as usize)
            .unwrap()
            .windows(4)
            .filter(|words| words[..3] == [0x34, 0xffdc, 0xffce])
            .map(|words| dmb.string(words[3]).unwrap().to_vec())
            .collect::<Vec<_>>()
    };
    assert_eq!(
        fields(&native),
        vec![b"nitrogen".to_vec(), b"temp".to_vec()]
    );
    assert_eq!(fields(&emitted.dmb), fields(&native));
}
#[test]
fn map_rows_follow_dmb_bottom_to_top_order() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let variant =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/variant.json"))
            .unwrap();
    let output = emit_with_baseline(&variant, Some(&native), &template, Path::new(".")).unwrap();
    let path = |turf: u32| {
        let class = output.dmb.instances[turf as usize].class;
        output
            .dmb
            .string(output.dmb.classes[class as usize].path_string_id())
            .unwrap()
            .to_vec()
    };
    assert_eq!(
        output
            .dmb
            .grid
            .iter()
            .map(|run| run.copies)
            .collect::<Vec<_>>(),
        vec![1, 2, 1]
    );
    assert_eq!(path(output.dmb.grid[0].turf), b"/turf/b");
    assert_eq!(path(output.dmb.grid[1].turf), b"/turf/a");
}

#[test]
fn project_name_sets_default_world_name() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/inheritance.json"))
            .unwrap();
    let emitted = emit_with_baseline_named(
        &input,
        Some(&native),
        &template,
        Path::new("."),
        Some("inheritance"),
    )
    .unwrap();
    assert_eq!(
        emitted.dmb.string(emitted.dmb.world.name_string_id()),
        Some(&b"inheritance"[..])
    );
}

#[test]
fn explicit_world_fields_match_paired_dream_maker_settings() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let reference = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/world_settings.native.bin"
    ))
    .unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/world_settings_annotated.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    assert_eq!(emitted.dmb.header.flags, reference.header.flags);
    assert_eq!(
        emitted.dmb.header.compatibility_line,
        reference.header.compatibility_line
    );
    assert_eq!(emitted.dmb.world.tick_lag, reference.world.tick_lag);
    assert_eq!(
        emitted.dmb.world.view_dimensions,
        reference.world.view_dimensions
    );
    assert_eq!(
        emitted.dmb.world.icon_dimensions_format,
        reference.world.icon_dimensions_format
    );
    assert_eq!(
        emitted.dmb.string(emitted.dmb.world.name_string_id()),
        reference.string(reference.world.name_string_id())
    );
    for slot in [1, 2] {
        let actual = &emitted.dmb.classes[emitted.dmb.world.ids[slot] as usize];
        let expected = &reference.classes[reference.world.ids[slot] as usize];
        assert_eq!(
            emitted.dmb.string(actual.path_string_id()),
            reference.string(expected.path_string_id())
        );
    }
    let actual = &emitted.dmb.mobs[emitted.dmb.world.ids[0] as usize];
    let expected = &reference.mobs[reference.world.ids[0] as usize];
    assert_eq!(
        emitted
            .dmb
            .string(emitted.dmb.classes[actual.class as usize].path_string_id()),
        reference.string(reference.classes[expected.class as usize].path_string_id())
    );
}

#[test]
fn authored_arguments_reuse_native_variable_names() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/calls.json")).unwrap();
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    // Dream Maker adds `value` and `math`, and reuses its existing `a` and `b` records.
    assert_eq!(output.dmb.variables.len(), template.variables.len() + 2);
    for name in [b"a".as_slice(), b"b".as_slice()] {
        assert_eq!(
            output
                .dmb
                .variables
                .iter()
                .filter(|variable| output.dmb.string(variable.name) == Some(name))
                .count(),
            2
        );
    }
}

#[test]
fn list_initializers_bind_class_and_global_procedures() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/list_constants.json"
    ))
    .unwrap();
    let reference = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/list_constants.native.bin"
    ))
    .unwrap();
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    assert_eq!(output.dmb.procs.len(), reference.procs.len());
    assert_eq!(output.dmb.variables.len(), reference.variables.len());
    assert_eq!(
        output.dmb.classes[0].lists_and_procs[2],
        reference.classes[0].lists_and_procs[2]
    );
    assert_eq!(
        output.dmb.world.global_initializer_proc_id(),
        reference.world.global_initializer_proc_id()
    );
    assert_eq!(
        output.ids.global_init_proc,
        Some(reference.world.global_initializer_proc_id())
    );
    for id in 67..70 {
        assert_eq!(output.dmb.variables[id].kind, 62);
        assert_eq!(
            output.dmb.variables[id].value,
            reference.variables[id].value
        );
    }
}

#[test]
fn inherited_list_initializers_bind_child_then_parent() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/list_init_chain.json"
    ))
    .unwrap();
    let reference = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/list_init_chain.native.bin"
    ))
    .unwrap();
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    for class in 0..2 {
        assert_eq!(
            output.dmb.classes[class].parent_class_id(),
            reference.classes[class].parent_class_id()
        );
        assert_eq!(
            output.dmb.classes[class].lists_and_procs[2],
            reference.classes[class].lists_and_procs[2]
        );
    }
}

#[test]
fn verb_source_and_display_match_dreammaker() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/verbs.json")).unwrap();
    let reference =
        Dmb::from_bytes(include_bytes!("../fixtures/translation/verbs.native.bin")).unwrap();
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    let actual = &output.dmb.procs[0];
    let expected = &reference.procs[0];
    assert_eq!(actual.source_location(), expected.source_location());
    assert_eq!(actual.flags, expected.flags);
    for field in 0..4 {
        assert_eq!(
            output.dmb.string(actual.strings[field]),
            reference.string(expected.strings[field])
        );
    }
}

#[test]
fn verb_invisibility_has_native_extended_flags() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/verb_invisibility.json"
    ))
    .unwrap();
    let reference = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/verb_invisibility.native.bin"
    ))
    .unwrap();
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    assert_eq!(output.dmb.procs[0].flags, reference.procs[0].flags);
    assert_eq!(
        output.dmb.procs[0].extended_flags,
        reference.procs[0].extended_flags
    );
    input
        .procs
        .iter_mut()
        .find(|proc| proc.name == "fixture_hidden")
        .unwrap()
        .invisibility = -1;
    assert!(matches!(
        emit_with_baseline(&input, Some(&native), &template, Path::new(".")),
        Err(EmitError::Unsupported(_))
    ));
}

#[test]
fn explicit_zero_invisibility_matches_paired_dream_maker_proc() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/explicit_invisibility_annotated.json"
    ))
    .unwrap();
    let reference = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/explicit_invisibility.native.bin"
    ))
    .unwrap();
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    for name in ["default_visibility", "explicit_zero", "explicit_seven"] {
        let path = format!("/mob/verb/{name}");
        let actual = output
            .dmb
            .procs
            .iter()
            .find(|proc| output.dmb.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let expected = reference
            .procs
            .iter()
            .find(|proc| reference.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(
            (actual.flags, actual.extended_flags),
            (expected.flags, expected.extended_flags)
        );
    }
}

#[test]
fn native_type_can_add_tmp_declaration_without_changing_scaffold_flags() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let datum = input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/datum")
        .unwrap();
    datum
        .variables
        .insert("fixture_tmp".into(), JsonValue::Null);
    datum.tmp_variables.insert("fixture_tmp".into());
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    let class = output
        .dmb
        .classes
        .iter()
        .find(|class| output.dmb.string(class.path_string_id()) == Some(b"/datum"))
        .unwrap();
    let declarations = &output.dmb.lists[class.defining_variable_list_id() as usize];
    assert!(declarations.chunks_exact(2).any(|pair| {
        let var = &output.dmb.variables[pair[0] as usize];
        output.dmb.string(var.name) == Some(b"fixture_tmp") && pair[1] == 4
    }));

    input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/datum")
        .unwrap()
        .tmp_variables
        .remove("type");
    assert!(matches!(
        emit_with_baseline(&input, Some(&native), &template, Path::new(".")),
        Err(EmitError::Unsupported(message)) if message.contains("removes or reclassifies")
    ));
}

#[test]
fn explicit_client_datum_parent_rebinds_native_class() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let datum_od = input
        .types
        .iter()
        .position(|typ| typ.path == "/datum")
        .unwrap();
    let client_od = input
        .types
        .iter()
        .position(|typ| typ.path == "/client")
        .unwrap();
    input.types[client_od].parent = Some(datum_od);
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    let client = output.ids.classes[client_od] as usize;
    assert_eq!(
        output.dmb.classes[client].parent_class_id(),
        output.ids.classes[datum_od]
    );
}

#[test]
fn user_classes_resolve_later_parent_type() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let datum = input
        .types
        .iter()
        .position(|typ| typ.path == "/datum")
        .unwrap();
    let child = input.types.len();
    let parent = child + 1;
    input.types.push(
        serde_json::from_value(serde_json::json!({
            "Path": "/datum/later_parent/early_child", "Parent": parent
        }))
        .unwrap(),
    );
    input.types.push(
        serde_json::from_value(serde_json::json!({
            "Path": "/datum/later_parent", "Parent": datum
        }))
        .unwrap(),
    );
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    let child_class = output.ids.classes[child] as usize;
    assert_eq!(
        output.dmb.classes[child_class].parent_class_id(),
        output.ids.classes[parent]
    );
    input.types[parent].parent = Some(child);
    assert!(matches!(
        emit_with_baseline(&input, Some(&native), &template, Path::new(".")),
        Err(EmitError::Invalid(message)) if message.contains("cyclic parent")
    ));
}

#[test]
fn diagnostic_emission_reserves_resources_without_asset_io() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/assets.json"))
        .unwrap();
    let output = emit_diagnostic_with_baseline_named(
        &input,
        Some(&native),
        &template,
        Path::new("intentionally-missing-resource-root"),
        None,
    )
    .unwrap();
    assert_eq!(output.ids.resources.len(), input.resources.len());
    assert_eq!(output.dmb.resources.len(), input.resources.len());
    assert!(output.resources.is_empty());
}

#[test]
fn hashed_diagnostic_matches_materialized_resource_table() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/assets.json"))
        .unwrap();
    let root = Path::new("fixtures/translation");
    let full = emit_with_baseline(&input, Some(&native), &template, root).unwrap();
    let hashed =
        emit_diagnostic_hashed_with_baseline_named(&input, Some(&native), &template, root, None)
            .unwrap();
    assert_eq!(hashed.dmb.resources, full.dmb.resources);
    assert_eq!(hashed.ids.resources, full.ids.resources);
    assert!(hashed.resources.is_empty());
}

#[test]
fn observed_hub_and_null_password_match_dream_maker() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let reference = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/hub_settings.native.bin"
    ))
    .unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let world = input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/world")
        .unwrap();
    world.variables.insert(
        "hub".into(),
        JsonValue::String("Exadv1.spacestation13".into()),
    );
    world
        .variables
        .insert("hub_password".into(), JsonValue::String("null".into()));
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    assert_eq!(
        output.dmb.string(output.dmb.world.hub_channel_skin[0]),
        reference.string(reference.world.hub_channel_skin[0])
    );
    assert_eq!(
        output.dmb.string(output.dmb.world.hub_password),
        reference.string(reference.world.hub_password)
    );
    input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/world")
        .unwrap()
        .variables
        .insert("hub_password".into(), JsonValue::String("other".into()));
    let other = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    assert_eq!(
        other.dmb.string(other.dmb.world.hub_password),
        Some(crate::hash::hub_password_hash(b"other").as_bytes()),
    );
}

#[test]
fn world_cache_lifespan_matches_dream_maker_scalar() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let reference = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/world_cache.native.bin"
    ))
    .unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let world = input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/world")
        .unwrap();
    world
        .variables
        .insert("cache_lifespan".into(), JsonValue::from(43));
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    assert_eq!(
        output.dmb.world.cache_lifespan,
        reference.world.cache_lifespan
    );
    input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/world")
        .unwrap()
        .variables
        .insert("cache_lifespan".into(), JsonValue::from(0));
    let zero = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    assert_eq!(zero.dmb.world.cache_lifespan, 0);
}

#[test]
fn world_fps_uses_native_integer_millisecond_tick_lag() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    for (fps, reference_bytes) in [
        (
            40,
            &include_bytes!("../fixtures/translation/world_fps40.native.bin")[..],
        ),
        (
            59,
            &include_bytes!("../fixtures/translation/world_fps59.native.bin")[..],
        ),
    ] {
        input
            .types
            .iter_mut()
            .find(|typ| typ.path == "/world")
            .unwrap()
            .variables
            .insert("fps".into(), JsonValue::from(fps));
        let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
        let reference = Dmb::from_bytes(reference_bytes).unwrap();
        assert_eq!(output.dmb.world.tick_lag, reference.world.tick_lag);
    }
}

#[test]
fn world_view_width_by_height_matches_dream_maker() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    for (view, bytes) in [
        (
            "7x11",
            &include_bytes!("../fixtures/translation/world_view_7x11.native.bin")[..],
        ),
        (
            "15x15",
            &include_bytes!("../fixtures/translation/world_view_15x15.native.bin")[..],
        ),
    ] {
        input
            .types
            .iter_mut()
            .find(|typ| typ.path == "/world")
            .unwrap()
            .variables
            .insert("view".into(), JsonValue::String(view.into()));
        let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
        let reference = Dmb::from_bytes(bytes).unwrap();
        assert_eq!(output.dmb.world.view_size(), reference.world.view_size());
        assert_eq!(
            output.dmb.header.flags & 0x200,
            reference.header.flags & 0x200
        );
    }
}

#[test]
fn proc_set_attributes_match_paired_dream_maker_flags() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/proc_attributes.json"
    ))
    .unwrap();
    let reference = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/proc_attributes.native.bin"
    ))
    .unwrap();
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    for name in [
        "fixture_default",
        "fixture_waitfor",
        "fixture_background",
        "fixture_hidden",
        "fixture_popup",
        "fixture_instant",
        "fixture_all",
        "fixture_background_nowait",
    ] {
        let actual = output
            .dmb
            .procs
            .iter()
            .find(|proc| {
                output
                    .dmb
                    .string(proc.strings[0])
                    .is_some_and(|path| path.ends_with(name.as_bytes()))
            })
            .unwrap();
        let expected = reference
            .procs
            .iter()
            .find(|proc| {
                reference
                    .string(proc.strings[0])
                    .is_some_and(|path| path.ends_with(name.as_bytes()))
            })
            .unwrap();
        assert_eq!(
            (actual.flags, actual.extended_flags),
            (expected.flags, expected.extended_flags),
            "{name}"
        );
    }
}

#[test]
fn datum_verb_uses_is_verb_even_without_type_verbs_entry() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/datum_verb.json"))
            .unwrap();
    let reference = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/datum_verb.native.bin"
    ))
    .unwrap();
    let owner = input
        .types
        .iter()
        .find(|typ| typ.path == "/datum/fixture")
        .unwrap();
    assert!(!owner.verbs.contains("fixture_action"));
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    let path = b"/datum/fixture/verb/fixture_action";
    assert!(output
        .dmb
        .procs
        .iter()
        .any(|proc| output.dmb.string(proc.strings[0]) == Some(path)));
    assert!(reference
        .procs
        .iter()
        .any(|proc| reference.string(proc.strings[0]) == Some(path)));
}

#[test]
fn rejects_untranslated_program_metadata_and_world_fields() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/calls.json")).unwrap();
    input.interface = Some("custom.dmf".into());
    assert!(matches!(
        emit_with_baseline(&input, Some(&native), &template, Path::new(".")),
        Err(EmitError::Invalid(_))
    ));
    input.interface = None;
    let world = input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/world")
        .unwrap();
    let original_build = world
        .variables
        .insert("byond_build".into(), JsonValue::from(1687));
    assert!(matches!(
        emit_with_baseline(&input, Some(&native), &template, Path::new(".")),
        Err(EmitError::Unsupported(message)) if message.contains("same BYOND version")
    ));
    let world = input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/world")
        .unwrap();
    world
        .variables
        .insert("byond_build".into(), original_build.unwrap());
    input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/world")
        .unwrap()
        .variables
        .insert("host".into(), JsonValue::String("changed".into()));
    assert!(matches!(
        emit_with_baseline(&input, Some(&native), &template, Path::new(".")),
        Err(EmitError::Unsupported(_))
    ));
}

#[test]
fn rejects_semantic_json_fields_that_cannot_be_emitted() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut calls =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/calls.json")).unwrap();
    let authored = calls
        .procs
        .iter()
        .position(|proc| proc.name == "fixture_double")
        .unwrap();
    calls.procs[authored].bytecode = None;
    assert!(matches!(
        emit_with_baseline(
            &calls,
            Some(&native),
            &template,
            Path::new("fixtures/translation")
        ),
        Err(EmitError::Unsupported(_))
    ));

    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/obj")
        .unwrap()
        .parent = Some(2);
    assert!(matches!(
        emit_with_baseline(
            &input,
            Some(&native),
            &template,
            Path::new("fixtures/translation")
        ),
        Err(EmitError::Unsupported(_))
    ));

    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/variables.json"))
            .unwrap();
    let north = input
        .globals
        .as_ref()
        .unwrap()
        .names
        .iter()
        .position(|name| name == "NORTH")
        .unwrap();
    input
        .globals
        .as_mut()
        .unwrap()
        .globals
        .insert(north, serde_json::json!(999));
    assert!(matches!(
        emit_with_baseline(
            &input,
            Some(&native),
            &template,
            Path::new("fixtures/translation")
        ),
        Err(EmitError::Unsupported(_))
    ));

    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/maps.json")).unwrap();
    input.maps[0]
        .cell_definitions
        .values_mut()
        .next()
        .unwrap()
        .name = "mismatch".into();
    let native_maps = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    assert!(matches!(
        emit_with_baseline(
            &input,
            Some(&native_maps),
            &template,
            Path::new("fixtures/translation")
        ),
        Err(EmitError::Invalid(_))
    ));

    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/calls.json")).unwrap();
    input
        .optional_errors
        .insert("Example".into(), serde_json::json!(true));
    assert!(matches!(
        emit(&input, &template, Path::new("fixtures/translation")),
        Err(EmitError::Unsupported(_))
    ));

    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/calls.json")).unwrap();
    input.procs[authored]
        .source_info
        .push(crate::opendream::OpenDreamSourceInfo {
            offset: 0,
            file: Some(input.strings.len()),
            line: 1,
        });
    assert!(matches!(
        emit_with_baseline(
            &input,
            Some(&native),
            &template,
            Path::new("fixtures/translation")
        ),
        Err(EmitError::Invalid(_))
    ));
}

#[test]
fn multiple_map_sections_fill_skipped_levels_with_world_defaults() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/multi_maps.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    assert_eq!(emitted.dmb.dimensions, [1, 1, 3]);
    let paths: Vec<_> = emitted
        .dmb
        .grid
        .iter()
        .map(|run| {
            let instance = &emitted.dmb.instances[run.turf as usize];
            let class = &emitted.dmb.classes[instance.class as usize];
            emitted.dmb.string(class.path_string_id()).unwrap().to_vec()
        })
        .collect();
    assert_eq!(
        paths,
        [
            b"/turf/first".to_vec(),
            b"/turf".to_vec(),
            b"/turf/second".to_vec()
        ]
    );
    emitted.dmb.validate_references().unwrap();
}

#[test]
fn interface_resource_sets_native_skin_field() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/skin_simple.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    assert_eq!(emitted.dmb.resources.len(), 1);
    assert_eq!(emitted.resources.len(), 1);
    assert_eq!(emitted.dmb.world.hub_channel_skin[2], 0);
    emitted.dmb.validate_references().unwrap();
}

#[test]
fn common_resource_kinds_match_paired_dream_maker_fixture() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/resource_kinds/resource_kinds.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation/resource_kinds"),
    )
    .unwrap();
    assert_eq!(
        emitted
            .dmb
            .resources
            .iter()
            .map(|r| r.kind)
            .collect::<Vec<_>>(),
        [3, 6, 2, 14, 0, 0, 0, 0, 0]
    );
    assert_eq!(emitted.resources.len(), 9);
}

#[test]
fn generated_icon_names_and_skin_only_assets_match_native_archive() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    input.resources = vec![
        "icons/gen/icons/test.dmi".into(),
        "icons/gen/icons/copy.dmi".into(),
        "interface/test.dmf".into(),
    ];
    input.interface = Some("interface/test.dmf".into());
    let root = std::env::temp_dir().join(format!("dmb-skin-resource-test-{}", std::process::id()));
    std::fs::create_dir_all(root.join("icons/gen/icons")).unwrap();
    std::fs::create_dir_all(root.join("interface")).unwrap();
    std::fs::create_dir_all(root.join("icons")).unwrap();
    std::fs::write(root.join("icons/gen/icons/test.dmi"), b"same").unwrap();
    std::fs::write(root.join("icons/gen/icons/copy.dmi"), b"same").unwrap();
    std::fs::write(
        root.join("interface/test.dmf"),
        b"icon = 'icons/skin.png'\n",
    )
    .unwrap();
    std::fs::write(root.join("icons/skin.png"), b"skin icon").unwrap();
    let output = emit_with_baseline(&input, Some(&baseline), &template, &root).unwrap();
    assert_eq!(output.ids.resources[0], output.ids.resources[1]);
    assert_eq!(output.dmb.resources.len(), 3);
    let names: Vec<_> = output
        .resources
        .iter()
        .filter_map(|entry| match entry {
            Entry::Named(named) => Some(String::from_utf8_lossy(&named.name).into_owned()),
            _ => None,
        })
        .collect();
    assert_eq!(
        names,
        [
            "icons/test.dmi",
            "icons/copy.dmi",
            "interface/test.dmf",
            "icons/skin.png"
        ]
    );
    input.native_resource_archive_order = Some(vec![
        "interface/test.dmf".into(),
        "icons/copy.dmi".into(),
        "icons/test.dmi".into(),
    ]);
    let ordered = emit_with_baseline(&input, Some(&baseline), &template, &root).unwrap();
    let names: Vec<_> = ordered
        .resources
        .iter()
        .map(|entry| match entry {
            Entry::Named(named) => named.name.as_slice(),
            _ => panic!("unexpected opaque resource"),
        })
        .collect();
    assert_eq!(
        names,
        [
            b"icons/skin.png".as_slice(),
            b"interface/test.dmf",
            b"icons/copy.dmi",
            b"icons/test.dmi"
        ]
    );
    assert_eq!(ordered.ids.resources, output.ids.resources);
    let hashed =
        emit_diagnostic_hashed_with_baseline_named(&input, Some(&baseline), &template, &root, None)
            .unwrap();
    assert_eq!(hashed.dmb.resources, ordered.dmb.resources);
    input.native_resource_archive_order = Some(vec!["absent.txt".into()]);
    assert!(matches!(
        emit_with_baseline(&input, Some(&baseline), &template, &root),
        Err(EmitError::Invalid(_))
    ));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn unrelated_classes_share_identical_variable_record_like_dream_maker() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/variable_dedupe.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/variable_dedupe.native.bin"
    ))
    .unwrap();
    let shared_id = |dmb: &Dmb, path: &[u8]| -> u32 {
        let class = dmb
            .classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(path))
            .unwrap();
        dmb.class_variable_declarations(class)
            .unwrap()
            .into_iter()
            .map(|(id, _)| id)
            .find(|&id| dmb.string(dmb.variables[id as usize].name) == Some(b"shared"))
            .unwrap()
    };
    assert_eq!(
        shared_id(&native, b"/datum/a"),
        shared_id(&native, b"/datum/b")
    );
    assert_eq!(
        shared_id(&emitted, b"/datum/a"),
        shared_id(&emitted, b"/datum/b")
    );
    let overrides = |dmb: &Dmb, path: &[u8]| -> Vec<(Vec<u8>, Value)> {
        let class = dmb
            .classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(path))
            .unwrap();
        let mut values: Vec<_> = dmb
            .class_builtin_overrides(class)
            .unwrap_or_default()
            .into_iter()
            .map(|entry| {
                (
                    dmb.string(entry.name_string_id).unwrap().to_vec(),
                    entry.value,
                )
            })
            .collect();
        values.sort_by(|left, right| left.0.cmp(&right.0));
        values
    };
    let child = b"/obj/fixture/defaults/child";
    assert_eq!(overrides(&native, child), overrides(&emitted, child));
    let grandchild = b"/datum/a/child/grandchild";
    for dmb in [&native, &emitted] {
        let class = dmb
            .classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(grandchild))
            .unwrap();
        assert!(dmb
            .class_initial_values(class)
            .unwrap_or_default()
            .is_empty());
    }
    let final_access = |dmb: &Dmb| -> (u8, f32) {
        let class = dmb
            .classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(b"/obj/fixture/cash"))
            .unwrap();
        let entry = dmb
            .class_initial_values(class)
            .unwrap()
            .into_iter()
            .find(|item| {
                dmb.string(dmb.variables[item.variable_id as usize].name) == Some(b"access")
            })
            .unwrap();
        (
            dmb.variables[entry.variable_id as usize].kind,
            f32::from_bits(entry.value.number_bits().unwrap()),
        )
    };
    assert_eq!(final_access(&native), (62, 200.0));
    assert_eq!(final_access(&emitted), final_access(&native));
    let mob_settings = |dmb: &Dmb, path: &[u8]| {
        let class = dmb
            .classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(path))
            .unwrap();
        let mob = dmb
            .mobs
            .iter()
            .find(|mob| mob.class == class as u32)
            .unwrap();
        (
            mob.sight_bits(),
            mob.see_in_dark_setting(),
            mob.see_invisible_setting(),
        )
    };
    for path in [b"/mob/fixture/eyes".as_slice(), b"/mob/fixture/eyes/child"] {
        assert_eq!(mob_settings(&emitted, path), mob_settings(&native, path));
    }
    let area = b"/area/fixture/glow";
    assert_eq!(overrides(&native, area), overrides(&emitted, area));
}

#[test]
fn authored_type_field_equal_to_baseline_is_preserved() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template_annotated.json"))
            .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/explicit_type_field_annotated.json"
    ))
    .unwrap();
    assert_eq!(
        input
            .types
            .iter()
            .find(|typ| typ.path == "/area")
            .unwrap()
            .explicit_type_fields,
        ["luminosity".to_owned()].into()
    );
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/explicit_type_field.native.bin"
    ))
    .unwrap();
    for path in [b"/area".as_slice(), b"/area/fixture/child"] {
        let defaults = |dmb: &Dmb| {
            let class = dmb
                .classes
                .iter()
                .position(|class| dmb.string(class.path_string_id()) == Some(path))
                .unwrap();
            dmb.class_builtin_overrides(class)
                .unwrap_or_default()
                .into_iter()
                .filter(|field| dmb.string(field.name_string_id) == Some(b"luminosity"))
                .map(|field| field.value)
                .collect::<Vec<_>>()
        };
        assert_eq!(
            defaults(&emitted),
            defaults(&native),
            "{}",
            String::from_utf8_lossy(path)
        );
    }
}

#[test]
fn maptext_geometry_matches_paired_dream_maker_class() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/maptext_geometry.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/maptext_geometry.native.bin"
    ))
    .unwrap();
    let geometry = |dmb: &Dmb| {
        dmb.classes
            .iter()
            .find(|class| dmb.string(class.path_string_id()) == Some(b"/obj/fixture/maptext"))
            .unwrap()
            .maptext_geometry
    };
    assert_eq!(geometry(&native), [56, 21, (-3i16) as u16, 4]);
    assert_eq!(geometry(&emitted), geometry(&native));
}

#[test]
fn literal_matrix_transform_matches_paired_dream_maker_class() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/transform_default.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/transform_default.native.bin"
    ))
    .unwrap();
    let transform = |dmb: &Dmb| {
        let class = dmb
            .classes
            .iter()
            .find(|class| dmb.string(class.path_string_id()) == Some(b"/obj/fixture/transform"))
            .unwrap();
        (
            class.transform_flag,
            class.transform,
            dmb.class_builtin_overrides(
                dmb.classes
                    .iter()
                    .position(|candidate| std::ptr::eq(candidate, class))
                    .unwrap(),
            )
            .unwrap_or_default(),
        )
    };
    assert_eq!(transform(&emitted), transform(&native));
}

#[test]
fn explicit_variable_override_gets_class_initial_value() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template_annotated.json"))
            .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/explicit_variable_override.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/explicit_variable_override.native.bin"
    ))
    .unwrap();
    let initial = |dmb: &Dmb, path: &[u8]| {
        let class = dmb
            .classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(path))
            .unwrap();
        dmb.class_initial_values(class)
            .unwrap_or_default()
            .into_iter()
            .filter(|item| {
                dmb.string(dmb.variables[item.variable_id as usize].name) == Some(b"value")
            })
            .map(|item| item.value)
            .collect::<Vec<_>>()
    };
    for path in [b"/datum/fixture".as_slice(), b"/datum/fixture/child"] {
        assert_eq!(initial(&emitted, path), initial(&native, path));
    }
}

#[test]
fn dynamic_initializer_markers_match_paired_declarations_and_overrides() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/dynamic_initializer_fields.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/dynamic_initializer_fields.native.bin"
    ))
    .unwrap();
    let markers = |dmb: &Dmb| {
        let class = dmb
            .classes
            .iter()
            .position(|class| {
                dmb.string(class.path_string_id()) == Some(b"/datum/dynamic_initializer_probe")
            })
            .unwrap();
        let declaration = dmb
            .class_variable_declarations(class)
            .unwrap()
            .into_iter()
            .find_map(|(id, _)| {
                (dmb.string(dmb.variables[id as usize].name) == Some(b"items"))
                    .then_some(dmb.variables[id as usize].hidden_initializer_marker())
                    .flatten()
            })
            .unwrap();
        let initial: Vec<_> = dmb
            .class_initial_values(class)
            .unwrap()
            .into_iter()
            .filter(|entry| entry.value.tag() == 62)
            .map(|entry| {
                (
                    dmb.string(dmb.variables[entry.variable_id as usize].name)
                        .unwrap()
                        .to_vec(),
                    entry.value.id(),
                )
            })
            .collect();
        (declaration, initial)
    };
    assert_eq!(
        markers(&native),
        (
            0,
            vec![
                (b"items".to_vec(), 2),
                (b"items".to_vec(), 3),
                (b"created".to_vec(), 4)
            ]
        )
    );
    assert_eq!(markers(&emitted), markers(&native));
    let particle_marker = |dmb: &Dmb| {
        let class = dmb
            .classes
            .iter()
            .position(|class| {
                dmb.string(class.path_string_id()) == Some(b"/particles/dynamic_initializer_probe")
            })
            .unwrap();
        dmb.class_initial_values(class)
            .unwrap()
            .into_iter()
            .filter(|entry| entry.value.tag() == 62)
            .map(|entry| {
                (
                    dmb.string(dmb.variables[entry.variable_id as usize].name)
                        .unwrap()
                        .to_vec(),
                    entry.value.id(),
                )
            })
            .collect::<Vec<_>>()
    };
    assert_eq!(particle_marker(&native), vec![(b"drift".to_vec(), 1)]);
    assert_eq!(particle_marker(&emitted), particle_marker(&native));
}
#[test]
fn later_null_keeps_dynamic_marker_before_final_class_value() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/dynamic_initializer_fields.json"
    ))
    .unwrap();
    let typ = input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/datum/dynamic_initializer_probe")
        .unwrap();
    typ.dynamic_initializer_fields.remove("created");
    typ.constant_initializer_fields
        .insert("created".into(), JsonValue::Null);
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let class = emitted
        .classes
        .iter()
        .position(|class| {
            emitted.string(class.path_string_id()) == Some(b"/datum/dynamic_initializer_probe")
        })
        .unwrap();
    let values: Vec<_> = emitted
        .class_initial_values(class)
        .unwrap()
        .into_iter()
        .filter(|entry| {
            emitted.string(emitted.variables[entry.variable_id as usize].name) == Some(b"created")
        })
        .map(|entry| entry.value.tag())
        .collect();
    assert_eq!(values, [62, 0]);
}

#[test]
fn hidden_initializer_variable_markers_have_scoped_allocator_ids() {
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/static_marker_kinds.native.bin"
    ))
    .unwrap();
    let marker = |name: &[u8]| {
        native.variables.iter().find_map(|variable| {
            (native.string(variable.name) == Some(name))
                .then_some((variable.kind, variable.hidden_initializer_marker()))
        })
    };
    assert_eq!(marker(b"global_list"), Some((62, Some(0))));
    assert_eq!(marker(b"items"), Some((62, Some(0))));
    assert_eq!(marker(b"proc_list"), Some((62, Some(0))));
    assert_eq!(marker(b"proc_icon"), Some((62, Some(2))));
    assert_eq!(marker(b"proc_image"), Some((0, None)));
    assert_eq!(marker(b"proc_number"), Some((0, None)));
    assert_eq!(marker(b"global_number"), Some((0, None)));
    let class = native
        .classes
        .iter()
        .position(|class| native.string(class.path_string_id()) == Some(b"/datum/marker_scope"))
        .unwrap();
    let initial = native.class_initial_values(class).unwrap();
    assert_eq!(
        initial
            .iter()
            .filter(|entry| entry.value.tag() == 62)
            .map(|entry| entry.value.id())
            .collect::<Vec<_>>(),
        vec![1]
    );
}

#[test]
fn argument_in_expression_uses_anonymous_proc_reference() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/argument_defaults.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/argument_defaults.native.bin"
    ))
    .unwrap();
    let emitted = emit_diagnostic_with_baseline_named(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
        None,
    )
    .unwrap();
    let owner = input
        .procs
        .iter()
        .position(|proc| proc.name == "argument_in_probe")
        .unwrap();
    let companion = input.procs[owner].arguments[0]
        .possible_values_proc
        .unwrap();
    let dmb_owner = emitted.ids.procs[owner] as usize;
    let dmb_companion = emitted.ids.procs[companion];
    let argument = emitted.dmb.proc_arguments(dmb_owner).unwrap()[0];
    assert_eq!(argument.value_source, 0x40);
    assert_eq!(
        emitted.dmb.argument_source_proc_id(&argument),
        Some(dmb_companion)
    );
    assert!(emitted.ids.argument_source_procs.contains(&companion));
    assert_eq!(emitted.dmb.procs[dmb_companion as usize].strings, [NONE; 4]);
    let native_owner = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/argument_in_probe"))
        .unwrap();
    let native_arg = native.proc_arguments(native_owner).unwrap()[0];
    assert_eq!(native_arg.value_source, argument.value_source);
    assert_eq!(
        native.proc_references.len(),
        emitted.dmb.proc_references.len()
    );
}

#[test]
fn direct_argument_sources_match_paired_native_codes() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template_annotated.json"))
            .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/argument_sources.json"
    ))
    .unwrap();
    let emitted = emit_diagnostic_with_baseline_named(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
        None,
    )
    .unwrap();
    for (name, expected) in [
        ("in_view", 0x7d01),
        ("in_oview", 0x7d02),
        ("in_range", 0x0505),
        ("in_usr_contents", 0x7f08),
        ("in_world", 0x7f10),
    ] {
        let owner = input
            .procs
            .iter()
            .position(|proc| proc.name == name)
            .unwrap();
        let companion = input.procs[owner].arguments[0]
            .possible_values_proc
            .unwrap();
        assert_eq!(emitted.ids.procs[companion], NONE, "{name}");
        let argument = emitted
            .dmb
            .proc_arguments(emitted.ids.procs[owner] as usize)
            .unwrap()[0];
        assert_eq!(argument.value_source, expected, "{name}");
    }
}

#[test]
fn movable_glide_size_uses_builtin_override() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/atom/movable")
        .unwrap()
        .variables
        .insert("glide_size".into(), JsonValue::from(8));
    let output = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let class = output
        .classes
        .iter()
        .position(|class| output.string(class.path_string_id()) == Some(b"/atom/movable"))
        .unwrap();
    assert!(output
        .class_builtin_overrides(class)
        .unwrap_or_default()
        .iter()
        .any(|value| output.string(value.name_string_id) == Some(b"glide_size")));
}

#[test]
fn map_list_override_uses_native_constructor_bytecode() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/map_list.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    let instance = &emitted.dmb.instances[emitted.dmb.map_objects[0].instance as usize];
    let code = emitted
        .dmb
        .proc_code_words(instance.initializer as usize)
        .unwrap();
    assert_eq!(&code[..7], &[0x50, 1, 0x50, 2, 0x1a, 2, 0x34]);
}

#[test]
fn map_associative_list_override_uses_native_constructor_bytecode() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/map_assoc.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    let instance = &emitted.dmb.instances[emitted.dmb.map_objects[0].instance as usize];
    let code = emitted
        .dmb
        .proc_code_words(instance.initializer as usize)
        .unwrap();
    assert_eq!(code[0], 0x60);
    assert_eq!(&code[3..7], &[0x50, 1, 0x60, 6]);
    assert_eq!(&code[8..12], &[0x50, 2, 0xc8, 2]);
}

#[test]
fn map_proc_reference_override_uses_native_value_tag() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/map_proc.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    let instance = &emitted.dmb.instances[emitted.dmb.map_objects[0].instance as usize];
    let code = emitted
        .dmb
        .proc_code_words(instance.initializer as usize)
        .unwrap();
    assert_eq!(&code[..3], &[0x60, 38, emitted.ids.procs[0]]);
}

#[test]
fn default_proc_display_name_replaces_underscores() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/map_proc.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    let proc = &emitted.dmb.procs[emitted.ids.procs[0] as usize];
    assert_eq!(
        emitted.dmb.string(proc.strings[1]),
        Some(&b"fixture target"[..])
    );
}

#[test]
fn class_proc_reference_default_resolves_after_proc_allocation() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/proc_constant.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    let variable = emitted
        .dmb
        .variables
        .iter()
        .find(|variable| emitted.dmb.string(variable.name) == Some(&b"target"[..]))
        .unwrap();
    assert_eq!(variable.kind, 38);
    assert_eq!(variable.value, emitted.ids.procs[0]);
    emitted.dmb.validate_references().unwrap();
}

#[test]
fn inherited_proc_reference_override_remaps_class_list() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/proc_inherited.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    let class = emitted
        .dmb
        .classes
        .iter()
        .find(|class| {
            emitted.dmb.string(class.path_string_id()) == Some(&b"/datum/proc_parent/child"[..])
        })
        .unwrap();
    let initial = &emitted.dmb.lists[class.lists_and_procs[3] as usize];
    assert_eq!(initial.len(), 3);
    assert_eq!(initial[1..], [38, emitted.ids.procs[0]]);
    emitted.dmb.validate_references().unwrap();
}

#[test]
fn infinity_constant_tags_match_dream_maker_numeric_bits() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/infinity.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    for (name, expected) in [
        (b"positive".as_slice(), f32::INFINITY.to_bits()),
        (b"negative".as_slice(), f32::NEG_INFINITY.to_bits()),
    ] {
        let variable = emitted
            .dmb
            .variables
            .iter()
            .find(|variable| emitted.dmb.string(variable.name) == Some(name))
            .unwrap();
        assert_eq!((variable.kind, variable.value), (42, expected));
    }
}

#[test]
fn literal_only_global_initializer_becomes_variable_default() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/variables.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    assert_eq!(emitted.ids.global_init_proc, None);
    assert_eq!(emitted.dmb.world.global_initializer_proc_id(), NONE);
    let calls = emitted
        .dmb
        .variables
        .iter()
        .find(|variable| emitted.dmb.string(variable.name) == Some(&b"calls"[..]))
        .unwrap();
    assert_eq!((calls.kind, calls.value), (42, 0));
}

#[test]
fn authored_static_global_is_declared_on_owning_class() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/list_constants.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    let class = emitted
        .dmb
        .classes
        .iter()
        .find(|class| {
            emitted.dmb.string(class.path_string_id()) == Some(&b"/datum/fixture_lists"[..])
        })
        .unwrap();
    let declarations = &emitted.dmb.lists[class.defining_variable_list_id() as usize];
    assert!(declarations.chunks_exact(2).any(|pair| {
        let var = &emitted.dmb.variables[pair[0] as usize];
        emitted.dmb.string(var.name) == Some(&b"shared"[..]) && pair[1] == 1 && var.kind == 62
    }));
}

#[test]
fn temporary_static_annotation_sets_class_declaration_flag_five() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/list_constants.json"
    ))
    .unwrap();
    let id = input
        .types
        .iter()
        .find(|typ| typ.path == "/datum/fixture_lists")
        .unwrap()
        .global_variables["shared"];
    input
        .globals
        .as_mut()
        .unwrap()
        .temporary_global_ids
        .insert(id);
    let dmb = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let class_id = dmb
        .classes
        .iter()
        .position(|class| dmb.string(class.path_string_id()) == Some(b"/datum/fixture_lists"))
        .unwrap();
    let declaration = dmb
        .class_variable_declarations(class_id)
        .unwrap()
        .into_iter()
        .find(|(id, _)| dmb.string(dmb.variables[*id as usize].name) == Some(b"shared"))
        .unwrap();
    assert_eq!(declaration.1, 5);
}

#[test]
fn static_const_declaration_uses_native_flag_three() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/static_const.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    let class = emitted
        .dmb
        .classes
        .iter()
        .find(|class| {
            emitted.dmb.string(class.path_string_id()) == Some(&b"/datum/static_const"[..])
        })
        .unwrap();
    let declarations = &emitted.dmb.lists[class.defining_variable_list_id() as usize];
    assert_eq!(declarations.len(), 2);
    assert_eq!(declarations[1], 3);
    let variable = &emitted.dmb.variables[declarations[0] as usize];
    assert_eq!(variable.number(), Some(7.0));
}

#[test]
fn class_const_footer_matches_paired_dream_maker() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/class_const.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/class_const.native.bin"
    ))
    .unwrap();
    let summary = |dmb: &Dmb| {
        let class_id = dmb
            .classes
            .iter()
            .position(|class| {
                dmb.string(class.path_string_id()) == Some(b"/obj/class_const_fixture")
            })
            .unwrap();
        let declarations = dmb.class_variable_declarations(class_id).unwrap();
        ["TAG_LOCAL_CONST", "TAG_STATIC_CONST", "TAG_MUTABLE"].map(|name| {
            let (id, flag) = declarations
                .iter()
                .copied()
                .find(|(id, _)| {
                    dmb.string(dmb.variables[*id as usize].name) == Some(name.as_bytes())
                })
                .unwrap();
            let footer = dmb
                .global_variable_flags()
                .unwrap()
                .into_iter()
                .find(|(footer_id, _)| *footer_id == id);
            (flag, footer.map(|(_, flags)| flags))
        })
    };
    assert_eq!(summary(&emitted), summary(&native));
    assert_eq!(summary(&native), [(3, Some(3)), (3, Some(3)), (0, None)]);
}

#[test]
fn proc_local_consts_preserve_duplicate_footer_names() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/proc_const.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/proc_const.native.bin"
    ))
    .unwrap();
    let summary = |dmb: &Dmb| {
        let mut values: Vec<_> = dmb
            .global_variable_flags()
            .unwrap()
            .into_iter()
            .filter_map(|(id, flags)| {
                let variable = &dmb.variables[id as usize];
                let name = dmb.string(variable.name)?;
                if name != b"LOCAL_TEXT" && name != b"LOCAL_ZERO" {
                    return None;
                }
                let value = if variable.kind == 6 {
                    dmb.string(variable.value)?.to_vec()
                } else if variable.kind == 42 {
                    variable.number()?.to_string().into_bytes()
                } else {
                    return None;
                };
                Some((name.to_vec(), flags, value))
            })
            .collect();
        values.sort();
        values
    };
    assert_eq!(summary(&emitted), summary(&native));
    assert_eq!(
        summary(&native),
        vec![
            (b"LOCAL_TEXT".to_vec(), 3, b"a".to_vec()),
            (b"LOCAL_TEXT".to_vec(), 3, b"b".to_vec()),
            (b"LOCAL_ZERO".to_vec(), 3, b"0".to_vec())
        ]
    );
}

#[test]
fn verb_sources_match_paired_dream_maker_metadata() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/verb_source_all.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/verb_source_all.native.bin"
    ))
    .unwrap();
    for name in [
        "v_inoview",
        "v_usr",
        "v_inusr",
        "v_usrloc",
        "v_world",
        "v_inworld",
        "v_default",
    ] {
        let metadata = |dmb: &Dmb| {
            let proc = dmb
                .procs
                .iter()
                .find(|proc| {
                    dmb.string(proc.strings[0])
                        .is_some_and(|path| path.ends_with(name.as_bytes()))
                })
                .unwrap();
            (
                proc.source_kind,
                proc.source_parameter,
                proc.effective_flags(),
            )
        };
        assert_eq!(metadata(&emitted), metadata(&native), "{name}");
    }
}

#[test]
fn omitted_verb_source_radius_uses_native_parameter_125() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/verb_source_default_range.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/verb_source_default_range.native.bin"
    ))
    .unwrap();
    for name in [
        "v_view_default",
        "v_inview_default",
        "v_oview_default",
        "v_inoview_default",
        "v_range_default",
        "v_inrange_default",
    ] {
        let metadata = |dmb: &Dmb| {
            let proc = dmb
                .procs
                .iter()
                .find(|proc| {
                    dmb.string(proc.strings[0])
                        .is_some_and(|path| path.ends_with(name.as_bytes()))
                })
                .unwrap();
            (
                proc.source_kind,
                proc.source_parameter,
                proc.effective_flags(),
            )
        };
        assert_eq!(metadata(&emitted), metadata(&native), "{name}");
        assert_eq!(metadata(&native).1, 125);
    }
}

#[test]
fn verb_source_edge_variants_match_paired_native_metadata() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/verb_source_edge.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/verb_source_edge.native.bin"
    ))
    .unwrap();
    for name in ["v_usr_group", "v_inorange", "v_orange"] {
        let metadata = |dmb: &Dmb| {
            let proc = dmb
                .procs
                .iter()
                .find(|proc| {
                    dmb.string(proc.strings[0])
                        .is_some_and(|path| path.ends_with(name.as_bytes()))
                })
                .unwrap();
            (
                proc.source_kind,
                proc.source_parameter,
                proc.effective_flags(),
            )
        };
        assert_eq!(metadata(&emitted), metadata(&native), "{name}");
    }
}

#[test]
fn inherited_proc_membership_matches_paired_native_classes() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/inheritance.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/inheritance.native.bin"
    ))
    .unwrap();
    let members = |dmb: &Dmb, path: &[u8]| {
        let class = dmb
            .classes
            .iter()
            .find(|class| dmb.string(class.path_string_id()) == Some(path))
            .unwrap();
        let id = class.proc_list_id();
        if id == NONE {
            return Vec::new();
        }
        dmb.lists[id as usize]
            .iter()
            .filter_map(|&id| dmb.procs.get(id as usize))
            .filter_map(|proc| {
                (proc.strings[0] != NONE)
                    .then(|| dmb.string(proc.strings[0]))
                    .flatten()
            })
            .map(|name| name.to_vec())
            .collect::<Vec<_>>()
    };
    for path in [
        b"/datum/fixture_parent".as_slice(),
        b"/datum/fixture_parent/fixture_child".as_slice(),
    ] {
        assert_eq!(
            members(&emitted, path),
            members(&native, path),
            "{}",
            String::from_utf8_lossy(path)
        );
    }
}

#[test]
fn inherited_verb_override_uses_bare_proc_path() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/inherited_verb_path.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
        .unwrap()
        .dmb;
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/inherited_verb_path.native.bin"
    ))
    .unwrap();
    for path in [
        b"/mob/child/parent_action".as_slice(),
        b"/mob/child/verb/own_action".as_slice(),
    ] {
        assert!(emitted
            .procs
            .iter()
            .any(|proc| emitted.string(proc.strings[0]) == Some(path)));
        assert!(native
            .procs
            .iter()
            .any(|proc| native.string(proc.strings[0]) == Some(path)));
    }
    for dmb in [&emitted, &native] {
        let class = dmb
            .classes
            .iter()
            .find(|class| dmb.string(class.path_string_id()) == Some(b"/mob/child"))
            .unwrap();
        let verbs = &dmb.lists[class.verb_list_id() as usize];
        assert!(verbs.iter().any(|&id| {
            dmb.string(dmb.procs[id as usize].strings[0]) == Some(b"/mob/child/parent_action")
        }));
    }
}

#[test]
fn optional_verb_arguments_have_native_nullable_prompt_flags() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_nativeordered_5161687.json"
    ))
    .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/null_default.json"))
            .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/null_default.native.bin"
    ))
    .unwrap();
    let output = emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
    for (id, proc) in native.procs.iter().enumerate() {
        let Some(path) = native.string(proc.strings[0]) else {
            continue;
        };
        if !path.windows(12).any(|part| part == b"default_arg_") {
            continue;
        }
        let emitted_id = output
            .dmb
            .procs
            .iter()
            .position(|item| output.dmb.string(item.strings[0]) == Some(path))
            .unwrap();
        let expected = native.proc_arguments(id).unwrap()[0].type_flags;
        let actual = output.dmb.proc_arguments(emitted_id).unwrap()[0].type_flags;
        assert_eq!(actual, expected, "{}", String::from_utf8_lossy(path));
    }
}
#[test]
fn proc_local_compile_time_consts_do_not_occupy_native_local_slots() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/proc_const.json"))
            .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/proc_const.native.bin"
    ))
    .unwrap();
    let output = emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
    for name in [b"/proc/alpha".as_slice(), b"/proc/beta".as_slice()] {
        let emitted_id = output
            .dmb
            .procs
            .iter()
            .position(|proc| output.dmb.string(proc.strings[0]) == Some(name))
            .unwrap();
        let native_id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(name))
            .unwrap();
        let emitted_locals = output.dmb.procs[emitted_id].code_locals_args[1];
        let native_locals = native.procs[native_id].code_locals_args[1];
        assert_eq!(
            output.dmb.lists[emitted_locals as usize].len(),
            native.lists[native_locals as usize].len(),
            "{}",
            String::from_utf8_lossy(name)
        );
    }
}

#[test]
fn lexical_local_metadata_order_matches_native_branch_declarations() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/lexical_locals.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/lexical_locals.native.bin"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
        .unwrap()
        .dmb;
    let local_names = |dmb: &Dmb| {
        let proc = dmb
            .procs
            .iter()
            .find(|proc| dmb.string(proc.strings[0]) == Some(b"/proc/branch_locals"))
            .unwrap();
        dmb.lists[proc.code_locals_args[1] as usize]
            .iter()
            .map(|&variable| {
                dmb.string(dmb.variables[variable as usize].name)
                    .unwrap()
                    .to_vec()
            })
            .collect::<Vec<_>>()
    };
    assert_eq!(local_names(&emitted), local_names(&native));
    assert_eq!(
        local_names(&emitted),
        vec![b"first".to_vec(), b"second".to_vec()]
    );
}

#[test]
fn inherited_proc_metadata_matches_explicit_set_provenance() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    for (json, native) in [
        (
            &include_bytes!("../fixtures/translation/inherited_verb_flags.json")[..],
            &include_bytes!("../fixtures/translation/inherited_verb_flags.native.bin")[..],
        ),
        (
            &include_bytes!("../fixtures/translation/inherited_proc_flags.json")[..],
            &include_bytes!("../fixtures/translation/inherited_proc_flags.native.bin")[..],
        ),
    ] {
        let input = OpenDreamProgram::from_slice(json).unwrap();
        let native = Dmb::from_bytes(native).unwrap();
        let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
            .unwrap()
            .dmb;
        for expected in &native.procs {
            let Some(path) = native.string(expected.strings[0]) else {
                continue;
            };
            if !(path
                .windows(b"hidden_parent".len())
                .any(|part| part == b"hidden_parent")
                || path
                    .windows(b"popup_parent".len())
                    .any(|part| part == b"popup_parent")
                || path
                    .windows(b"flagged".len())
                    .any(|part| part == b"flagged"))
            {
                continue;
            }
            let actual = emitted
                .procs
                .iter()
                .find(|proc| emitted.string(proc.strings[0]) == Some(path))
                .unwrap();
            assert_eq!(
                actual.effective_flags(),
                expected.effective_flags(),
                "{}",
                String::from_utf8_lossy(path)
            );
            for slot in 1..4 {
                let actual_string = (actual.strings[slot] != NONE)
                    .then(|| emitted.string(actual.strings[slot]))
                    .flatten();
                let expected_string = (expected.strings[slot] != NONE)
                    .then(|| native.string(expected.strings[slot]))
                    .flatten();
                assert_eq!(
                    actual_string,
                    expected_string,
                    "{} slot {slot}",
                    String::from_utf8_lossy(path)
                );
            }
        }
    }
}

#[test]
fn authored_verb_category_and_view_radius_match_native() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/verb_metadata.json"))
            .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/verb_metadata.native.bin"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
        .unwrap()
        .dmb;
    for path in [
        b"/obj/verb/action".as_slice(),
        b"/obj/sub/action".as_slice(),
    ] {
        let actual = emitted
            .procs
            .iter()
            .find(|proc| emitted.string(proc.strings[0]) == Some(path))
            .unwrap();
        let expected = native
            .procs
            .iter()
            .find(|proc| native.string(proc.strings[0]) == Some(path))
            .unwrap();
        assert_eq!(actual.source_kind, expected.source_kind);
        assert_eq!(actual.source_parameter, expected.source_parameter);
        assert_eq!(
            emitted.string(actual.strings[3]),
            native.string(expected.strings[3]),
        );
    }
}

#[test]
fn null_and_empty_verb_categories_have_distinct_native_flags() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/verb_category_nil.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/verb_category_nil.native.bin"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
        .unwrap()
        .dmb;
    for name in ["cat_null", "cat_empty", "cat_regular"] {
        let path = format!("/mob/verb/{name}");
        let actual = emitted
            .procs
            .iter()
            .find(|proc| emitted.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let expected = native
            .procs
            .iter()
            .find(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(
            actual.effective_flags(),
            expected.effective_flags(),
            "{name}"
        );
        let actual_category = (actual.strings[3] != NONE)
            .then(|| emitted.string(actual.strings[3]))
            .flatten();
        let expected_category = (expected.strings[3] != NONE)
            .then(|| native.string(expected.strings[3]))
            .flatten();
        assert_eq!(actual_category, expected_category, "{name}");
    }
}

#[test]
fn equal_and_in_verb_source_keywords_have_distinct_native_flags() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/verb_source_keyword.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/verb_source_keyword.native.bin"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
        .unwrap()
        .dmb;
    for name in ["equal_source", "in_source"] {
        let path = format!("/obj/verb/{name}");
        let actual = emitted
            .procs
            .iter()
            .find(|proc| emitted.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let expected = native
            .procs
            .iter()
            .find(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        assert_eq!(actual.source_kind, expected.source_kind, "{name}");
        assert_eq!(actual.source_parameter, expected.source_parameter, "{name}");
        assert_eq!(
            actual.effective_flags(),
            expected.effective_flags(),
            "{name}"
        );
    }
}

#[test]
fn waitfor_defaults_follow_original_declaration_and_nested_background_is_emitted() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    for (json, native) in [
        (
            &include_bytes!("../fixtures/translation/waitfor_chain.json")[..],
            &include_bytes!("../fixtures/translation/waitfor_chain.native.bin")[..],
        ),
        (
            &include_bytes!("../fixtures/translation/nested_set_flags.json")[..],
            &include_bytes!("../fixtures/translation/nested_set_flags.native.bin")[..],
        ),
    ] {
        let input = OpenDreamProgram::from_slice(json).unwrap();
        let native = Dmb::from_bytes(native).unwrap();
        let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
            .unwrap()
            .dmb;
        for expected in &native.procs {
            let Some(path) = native.string(expected.strings[0]) else {
                continue;
            };
            if !(path.ends_with(b"/p") || path.ends_with(b"/nested_background")) {
                continue;
            }
            let actual = emitted
                .procs
                .iter()
                .find(|proc| emitted.string(proc.strings[0]) == Some(path))
                .unwrap();
            assert_eq!(
                actual.effective_flags(),
                expected.effective_flags(),
                "{}",
                String::from_utf8_lossy(path)
            );
        }
    }
}

#[test]
fn mixed_map_list_assigns_positional_keys() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/map_mixed.json"))
            .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&native),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    let instance = &emitted.dmb.instances[emitted.dmb.map_objects[0].instance as usize];
    let code = emitted
        .dmb
        .proc_code_words(instance.initializer as usize)
        .unwrap();
    assert_eq!(&code[..5], &[0x50, 1, 0x50, 9, 0x60]);
    assert_eq!(&code[7..11], &[0x50, 1, 0xc8, 2]);
}

#[test]
fn typed_argument_bits_match_paired_compilers() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/argument_types.json"
    ))
    .unwrap();
    let reference = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/argument_types.native.bin"
    ))
    .unwrap();
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    let actual = output.dmb.proc_arguments(0).unwrap();
    let expected = reference.proc_arguments(0).unwrap();
    assert_eq!(actual.len(), expected.len());
    for index in (0..actual.len()).filter(|&index| index != 7) {
        assert_eq!(actual[index].type_flags, expected[index].type_flags);
    }
    assert_eq!(actual[0].type_flags, crate::dmb::argument_type::MOB);
    assert_eq!(actual[1].type_flags, crate::dmb::argument_type::OBJ);
    // OpenDream JSON does not distinguish explicit `as anything` from
    // an untyped argument (both have Type=0), so index 7 stays untyped.
    assert_eq!(actual[7].type_flags, 0);
    assert_eq!(expected[7].type_flags, crate::dmb::argument_type::ANYTHING);
    input
        .procs
        .iter_mut()
        .find(|proc| proc.name == "fixture_arg_types")
        .unwrap()
        .arguments[7]
        .explicit_anything = true;
    let annotated = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    assert_eq!(
        annotated.dmb.proc_arguments(0).unwrap()[7].type_flags,
        expected[7].type_flags
    );
}

#[test]
fn movable_argument_path_restores_native_type_flags() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/animation_gradient.json"
    ))
    .unwrap();
    let proc = input
        .procs
        .iter_mut()
        .find(|proc| proc.name == "use_animate")
        .unwrap();
    proc.arguments[0].type_path = Some("/atom/movable".to_owned());
    let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
    let proc_id = output.ids.procs[input
        .procs
        .iter()
        .position(|proc| proc.name == "use_animate")
        .unwrap()] as usize;
    assert_eq!(output.dmb.proc_arguments(proc_id).unwrap()[0].type_flags, 3);
}

#[test]
fn atom_and_turf_argument_paths_restore_native_type_flags() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/animation_gradient.json"
    ))
    .unwrap();
    let proc_index = input
        .procs
        .iter()
        .position(|proc| proc.name == "use_animate")
        .unwrap();
    for (path, expected) in [("/atom", 0x123), ("/turf", 0x20)] {
        input.procs[proc_index].arguments[0].type_path = Some(path.to_owned());
        let output = emit_with_baseline(&input, Some(&native), &template, Path::new(".")).unwrap();
        let proc_id = output.ids.procs[proc_index] as usize;
        assert_eq!(
            output.dmb.proc_arguments(proc_id).unwrap()[0].type_flags,
            expected
        );
    }
}

#[test]
fn explicit_anything_union_preserves_other_argument_type_bits() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/animation_gradient.json"
    ))
    .unwrap();
    let proc_index = input
        .procs
        .iter()
        .position(|proc| proc.name == "use_animate")
        .unwrap();
    input.procs[proc_index].arguments[0].r#type = 1;
    input.procs[proc_index].arguments[0].explicit_anything = true;
    let output = emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
    let proc_id = output.ids.procs[proc_index] as usize;
    assert_eq!(
        output.dmb.proc_arguments(proc_id).unwrap()[0].type_flags,
        0x1080
    );
}

#[test]
fn typed_list_argument_uses_declared_element_path() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/animation_gradient.json"
    ))
    .unwrap();
    let proc_index = input
        .procs
        .iter()
        .position(|proc| proc.name == "use_animate")
        .unwrap();
    for (path, expected) in [
        ("list/turf/to_add", 0x20),
        ("list/mob/living/targets", 1),
        ("list/area/supply_shuttle_areas", 0x100),
        ("list/items", 0),
    ] {
        input.procs[proc_index].arguments[0].type_path = Some("/list".to_owned());
        input.procs[proc_index].arguments[0].declared_path = Some(path.to_owned());
        let emitted =
            emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
        let proc_id = emitted.ids.procs[proc_index] as usize;
        assert_eq!(
            emitted.dmb.proc_arguments(proc_id).unwrap()[0].type_flags,
            expected,
            "{path}"
        );
    }
}

#[test]
fn declared_list_elements_and_absolute_parameter_omission_match_native() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    for (json, native, paths) in [
        (
            &include_bytes!("../fixtures/translation/list_arg_path.json")[..],
            &include_bytes!("../fixtures/translation/list_arg_path.native.bin")[..],
            &[
                "/proc/list_turf",
                "/proc/list_mob",
                "/proc/list_area",
                "/proc/list_plain",
            ][..],
        ),
        (
            &include_bytes!("../fixtures/translation/absolute_arg.json")[..],
            &include_bytes!("../fixtures/translation/absolute_arg.native.bin")[..],
            &["/datum/symptom/heal/proc/Heal"][..],
        ),
    ] {
        let input = OpenDreamProgram::from_slice(json).unwrap();
        let native = Dmb::from_bytes(native).unwrap();
        let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
            .unwrap()
            .dmb;
        let args = |dmb: &Dmb, path: &str| {
            let id = dmb
                .procs
                .iter()
                .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            dmb.proc_arguments(id)
                .unwrap()
                .iter()
                .map(|arg| {
                    (
                        dmb.string(dmb.variables[arg.variable_id as usize].name)
                            .unwrap()
                            .to_vec(),
                        arg.type_flags,
                    )
                })
                .collect::<Vec<_>>()
        };
        for &path in paths {
            assert_eq!(args(&emitted, path), args(&native, path), "{path}");
        }
    }
}

#[test]
fn in_world_argument_uses_native_atom_selector_for_datum_or_untyped() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/argument_world.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/argument_world.native.bin"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
        .unwrap()
        .dmb;
    for name in [
        b"datum_world".as_slice(),
        b"obj_world".as_slice(),
        b"turf_world".as_slice(),
        b"atom_world".as_slice(),
        b"any_world".as_slice(),
    ] {
        let path = [b"/proc/".as_slice(), name].concat();
        let emitted_id = emitted
            .procs
            .iter()
            .position(|proc| emitted.string(proc.strings[0]) == Some(path.as_slice()))
            .unwrap();
        let native_id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_slice()))
            .unwrap();
        let actual = emitted.proc_arguments(emitted_id).unwrap()[0];
        let expected = native.proc_arguments(native_id).unwrap()[0];
        assert_eq!(
            actual.type_flags,
            expected.type_flags,
            "{}",
            String::from_utf8_lossy(&path)
        );
        assert_eq!(
            actual.value_source,
            expected.value_source,
            "{}",
            String::from_utf8_lossy(&path)
        );
    }
}

#[test]
fn argument_source_companion_receives_preceding_arguments_only() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/argument_source_parameter.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/argument_source_parameter.native.bin"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
        .unwrap()
        .dmb;
    for name in [
        "global_options",
        "member_options",
        "call_options",
        "unused_options",
    ] {
        let path = format!("/proc/{name}");
        let actual_owner = emitted
            .procs
            .iter()
            .position(|proc| emitted.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let expected_owner = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let actual_argument = *emitted
            .proc_arguments(actual_owner)
            .unwrap()
            .last()
            .unwrap();
        let expected_argument = *native
            .proc_arguments(expected_owner)
            .unwrap()
            .last()
            .unwrap();
        let actual_source = emitted.argument_source_proc_id(&actual_argument).unwrap() as usize;
        let expected_source = native.argument_source_proc_id(&expected_argument).unwrap() as usize;
        let actual_args = emitted.proc_arguments(actual_source).unwrap();
        let expected_args = native.proc_arguments(expected_source).unwrap();
        assert_eq!(actual_args.len(), expected_args.len(), "{name}");
        for (actual, expected) in actual_args.iter().zip(&expected_args) {
            assert_eq!(actual.type_flags, expected.type_flags, "{name}");
            assert_eq!(actual.value_source, expected.value_source, "{name}");
        }
    }
}

#[test]
fn argument_source_companion_includes_current_when_referenced() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/argument_source_self.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/argument_source_self.native.bin"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new("."))
        .unwrap()
        .dmb;
    let source_args = |dmb: &Dmb| {
        let owner = dmb
            .procs
            .iter()
            .position(|proc| dmb.string(proc.strings[0]) == Some(b"/proc/self_source"))
            .unwrap();
        let argument = dmb.proc_arguments(owner).unwrap()[0];
        let source = dmb.argument_source_proc_id(&argument).unwrap() as usize;
        dmb.proc_arguments(source).unwrap()
    };
    let actual = source_args(&emitted);
    let expected = source_args(&native);
    assert_eq!(actual.len(), expected.len());
    assert_eq!(actual.len(), 1);
    assert_eq!(actual[0].type_flags, expected[0].type_flags);
    assert_eq!(actual[0].value_source, expected[0].value_source);
}

#[test]
fn promotes_to_wide_object_ids_when_string_table_exceeds_u16() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    for id in 0..u16::MAX as usize {
        input.strings.push(format!("wide_{id}"));
    }
    let output = emit_with_baseline(&input, Some(&input), &template, Path::new(".")).unwrap();
    for &id in &output.ids.strings {
        assert!(
            !native_reserved_string_id(id),
            "authored string occupies reserved ID {id:#x}"
        );
        let field = crate::operands::Variable::Field(id);
        assert_eq!(
            crate::operands::Variable::decode(&field.encode())
                .unwrap()
                .0,
            field
        );
    }
    assert!(requires_wide_object_ids(&output.dmb));
    assert!(output.dmb.header.uses_large_object_ids());
    let bytes = output.dmb.to_bytes().unwrap();
    let parsed = Dmb::from_bytes(&bytes).unwrap();
    assert_eq!(parsed.strings.len(), output.dmb.strings.len());
    assert_eq!(parsed.world.domain_string_id(), NONE);
}
#[test]
fn client_path_defaults_use_native_singleton_payload() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let client = input
        .types
        .iter()
        .position(|typ| typ.path == "/client")
        .unwrap();
    let datum = input
        .types
        .iter()
        .position(|typ| typ.path == "/datum")
        .unwrap();
    input.types.push(
        serde_json::from_value(serde_json::json!({
            "Path":"/datum/client_path_holder", "Parent":datum,
            "Variables":{"client_default":{"type":1,"value":client}}
        }))
        .unwrap(),
    );
    let output = emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
    let variable = output
        .dmb
        .variables
        .iter()
        .find(|var| output.dmb.string(var.name) == Some(b"client_default"))
        .unwrap();
    assert_eq!((variable.kind, variable.value), (59, 0));
}
#[test]
fn wide_optional_lists_skip_absent_sentinel_id() {
    let mut template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    template.lists.resize(NONE as usize, Vec::new());
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/native_template.json")).unwrap();
    let datum = input
        .types
        .iter()
        .position(|typ| typ.path == "/datum")
        .unwrap();
    let own_type = input.types.len();
    input.types.push(
        serde_json::from_value(serde_json::json!({
            "Path":"/datum/wide_list_holder", "Parent":datum, "Variables":{"list_probe":1}
        }))
        .unwrap(),
    );
    let output = emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
    assert!(output.dmb.lists[NONE as usize].is_empty());
    let declaration_id =
        output.dmb.classes[output.ids.classes[own_type] as usize].lists_and_procs[4];
    assert!(declaration_id > NONE);
    assert!(!output.dmb.lists[declaration_id as usize].is_empty());
    let parsed = Dmb::from_bytes(&output.dmb.to_bytes().unwrap()).unwrap();
    assert_eq!(
        parsed.classes[output.ids.classes[own_type] as usize].lists_and_procs[4],
        declaration_id
    );
}

#[test]
fn modified_type_values_use_instance_ids() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/modified_type.json"))
            .unwrap();
    let dmb = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let owner = dmb
        .classes
        .iter()
        .position(|class| dmb.string(class.path_string_id()) == Some(b"/datum/modified_holder"))
        .unwrap();
    let declaration = dmb
        .class_variable_declarations(owner)
        .unwrap()
        .into_iter()
        .find(|(id, _)| dmb.string(dmb.variables[*id as usize].name) == Some(b"tag_modified"))
        .unwrap();
    let variable = &dmb.variables[declaration.0 as usize];
    assert_eq!(variable.kind, 41);
    let instance = &dmb.instances[variable.value as usize];
    assert_eq!(instance.kind, 9);
    assert_eq!(
        dmb.string(dmb.classes[instance.class as usize].path_string_id()),
        Some(b"/obj/tagged".as_slice())
    );
    assert_ne!(instance.initializer, NONE);
    let child = dmb
        .classes
        .iter()
        .position(|class| {
            dmb.string(class.path_string_id()) == Some(b"/datum/modified_holder/child")
        })
        .unwrap();
    let initial = dmb
        .class_initial_values(child)
        .unwrap()
        .into_iter()
        .find(|value| {
            dmb.string(dmb.variables[value.variable_id as usize].name) == Some(b"tag_modified")
        })
        .unwrap();
    assert_eq!(initial.value.tag(), 41);
    assert_ne!(initial.value.id(), variable.value);
}

#[test]
fn declaration_provenance_keeps_original_default_and_final_override() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/modified_type.json"))
            .unwrap();
    let typ = input
        .types
        .iter_mut()
        .find(|typ| typ.path == "/datum/modified_holder")
        .unwrap();
    typ.variables.insert("tag_plain".into(), JsonValue::from(6));
    typ.variable_declaration_values
        .insert("tag_plain".into(), JsonValue::from(0));
    typ.explicit_type_fields.insert("tag_plain".into());
    typ.variable_override_order.push("tag_plain".into());
    let dmb = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap()
    .dmb;
    let class_id = dmb
        .classes
        .iter()
        .position(|class| dmb.string(class.path_string_id()) == Some(b"/datum/modified_holder"))
        .unwrap();
    let var_id = dmb
        .class_variable_declarations(class_id)
        .unwrap()
        .into_iter()
        .find(|(id, _)| dmb.string(dmb.variables[*id as usize].name) == Some(b"tag_plain"))
        .unwrap()
        .0;
    let variable = &dmb.variables[var_id as usize];
    assert_eq!(variable.kind, 42);
    assert_eq!(variable.value, 0);
    let override_value = dmb
        .class_initial_values(class_id)
        .unwrap()
        .into_iter()
        .find(|entry| entry.variable_id == var_id)
        .unwrap()
        .value;
    assert_eq!(override_value.number_bits(), Some(6f32.to_bits()));
}

#[test]
fn inline_modified_datum_allocates_native_kind_32_instance() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_nativeconstruct_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/constructor_order.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/constructor_order.native.bin"
    ))
    .unwrap();
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
    let type_id = input
        .types
        .iter()
        .position(|typ| typ.path == "/datum/ctor")
        .unwrap();
    let json = input
        .strings
        .iter()
        .find(|value| value.as_str() == "{\"foo\":3}")
        .unwrap();
    let id = emitted.ids.modified_instances[&(type_id, json.clone())];
    let instance = &emitted.dmb.instances[id as usize];
    assert_eq!(instance.kind, 32);
    assert_eq!(instance.class, emitted.ids.classes[type_id]);
    assert_ne!(instance.initializer, NONE);
    assert_eq!(
        emitted
            .dmb
            .instances
            .iter()
            .filter(|record| record.kind == 32)
            .count(),
        native
            .instances
            .iter()
            .filter(|record| record.kind == 32)
            .count()
    );
}
#[test]
fn inline_modified_new_allocates_instance_for_lowerer() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../fixtures/translation/modified_type.json"))
            .unwrap();
    let type_id = input
        .types
        .iter()
        .position(|typ| typ.path == "/obj/tagged")
        .unwrap();
    let json = r#"{"amount":99}"#.to_owned();
    let string_id = input.strings.len() as u32;
    input.strings.push(json.clone());
    let code = input
        .procs
        .iter_mut()
        .find_map(|proc| proc.bytecode.as_mut())
        .unwrap();
    code.push(0x03);
    code.extend(string_id.to_le_bytes());
    code.push(0x02);
    code.extend((type_id as u32).to_le_bytes());
    code.extend([0x2e, 0, 0, 0, 0, 0]);
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    let id = emitted.ids.modified_instances[&(type_id, json)];
    let instance = &emitted.dmb.instances[id as usize];
    assert_eq!(instance.kind, 9);
    assert_ne!(instance.initializer, NONE);
}

#[test]
fn modified_type_constants_emit_tag_41_for_class_global_and_proc() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_modifiedtype_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/modified_constant.json"
    ))
    .unwrap();
    let emitted = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/translation"),
    )
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/modified_constant.native.bin"
    ))
    .unwrap();
    let class_default = |dmb: &Dmb| {
        let class_id = dmb
            .classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(b"/datum/modified_holder"))
            .unwrap();
        let id = dmb
            .class_variable_declarations(class_id)
            .unwrap()
            .into_iter()
            .find(|(id, _)| dmb.string(dmb.variables[*id as usize].name) == Some(b"object_type"))
            .unwrap()
            .0;
        let var = &dmb.variables[id as usize];
        assert_eq!(var.kind, 41);
        assert_eq!(dmb.instances[var.value as usize].kind, 9);
        assert_ne!(dmb.instances[var.value as usize].initializer, NONE);
    };
    class_default(&emitted.dmb);
    class_default(&native);
    let global = |dmb: &Dmb| {
        let id = dmb
            .global_variable_flags()
            .unwrap()
            .into_iter()
            .find(|(id, _)| dmb.string(dmb.variables[*id as usize].name) == Some(b"type_reference"))
            .unwrap()
            .0;
        let var = &dmb.variables[id as usize];
        assert_eq!(var.kind, 41);
        assert_ne!(dmb.instances[var.value as usize].initializer, NONE);
    };
    global(&emitted.dmb);
    global(&native);
    let type_id = input
        .types
        .iter()
        .position(|typ| typ.path == "/obj/modified_constant")
        .unwrap();
    let json = input
        .strings
        .iter()
        .find(|text| text.contains("\"amount\":22"))
        .unwrap();
    let proc_instance = emitted.ids.modified_instances[&(type_id, json.clone())];
    assert_ne!(
        emitted.dmb.instances[proc_instance as usize].initializer,
        NONE
    );
}

#[test]
fn preserved_native_procedure_references_survive_authored_prefix() {
    use crate::bytecode::Operand;
    use crate::operands::Variable;
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/selector_alias_collision.json"
    ))
    .unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let output = crate::translate::translate_named_debug(
        &input,
        &baseline,
        &template,
        Path::new("fixtures/lowering"),
        Some("selector_alias_collision"),
        false,
    )
    .unwrap();
    let find = |dmb: &Dmb, name: &[u8]| {
        dmb.procs
            .iter()
            .position(|p| dmb.string(p.strings[0]) == Some(name))
            .unwrap()
    };
    for dmb in [&template, &output.dmb] {
        let code =
            crate::bytecode::decode(dmb.proc_code_words(find(dmb, b"/database/New")).unwrap())
                .unwrap();
        let call = code.iter().find(|i| i.opcode == 0x2a).unwrap();
        let operands = call.typed_operands().unwrap();
        let Operand::Variable(Variable::SetCache(_, right)) = &operands[0] else {
            panic!("database selector")
        };
        let Variable::StaticProc(id) = **right else {
            panic!("database static selector")
        };
        assert_eq!(
            dmb.string(dmb.procs[id as usize].strings[0]),
            Some(&b"/database/proc/Open"[..])
        );
        let sound = crate::bytecode::decode(dmb.proc_code_words(find(dmb, b"/sound/New")).unwrap())
            .unwrap();
        assert!(sound
            .iter()
            .any(|i| i.opcode == 0x60 && i.operands == [40, 0]));
    }
}

#[test]
fn scaffold_global_call_count_and_nested_verb_selector_relocate_independently() {
    use crate::bytecode::Operand;
    use crate::operands::Variable;
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/lowering/selector_alias_collision.json"
    ))
    .unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let mut template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let owner = template
        .procs
        .iter()
        .position(|p| template.string(p.strings[0]) == Some(b"/database/New"))
        .unwrap();
    let target = template
        .procs
        .iter()
        .position(|p| template.string(p.strings[0]) == Some(b"/database/proc/Open"))
        .unwrap() as u32;
    let mut words = vec![0x30, 2, target, 0x33];
    words.extend(
        Variable::SetCache(
            Box::new(Variable::Src),
            Box::new(Variable::StaticVerb(target)),
        )
        .encode(),
    );
    words.push(0);
    template.procs[owner].code_locals_args[0] = template.lists.len() as u32;
    template.lists.push(words);
    let output = emit_with_baseline(
        &input,
        Some(&baseline),
        &template,
        Path::new("fixtures/lowering"),
    )
    .unwrap();
    let owner = output
        .dmb
        .procs
        .iter()
        .position(|p| output.dmb.string(p.strings[0]) == Some(b"/database/New"))
        .unwrap();
    let target = output
        .dmb
        .procs
        .iter()
        .position(|p| output.dmb.string(p.strings[0]) == Some(b"/database/proc/Open"))
        .unwrap() as u32;
    let instructions = crate::bytecode::decode(output.dmb.proc_code_words(owner).unwrap()).unwrap();
    assert_eq!(instructions[0].operands, [2, target]);
    assert_eq!(
        instructions[1].typed_operands().unwrap(),
        vec![Operand::Variable(Variable::SetCache(
            Box::new(Variable::Src),
            Box::new(Variable::StaticVerb(target))
        ))]
    );
}
