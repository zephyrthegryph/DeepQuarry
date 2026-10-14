use super::*;

#[test]
fn wide_class_and_proc_tables_keep_native_nullable_id_holes() {
    let mut template =
        Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
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
        "../../../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let mut authored_type = input.types.pop().unwrap();
    let mut authored_proc = input.procs.pop().unwrap();
    input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_savefile_5161687.json"
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
    let mut template =
        Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
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
    let mut template =
        Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    template.variables.resize(
        NONE as usize,
        Variable {
            kind: 0,
            value: 0,
            name: NONE,
        },
    );
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_savefile_5161687.json"
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
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
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
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let smoke = OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/opendream_smoke.json"))
        .unwrap();
    let output = emit_with_baseline(&smoke, Some(&native), &template, Path::new(".")).unwrap();
    assert_eq!(output.dmb.classes.len(), template.classes.len() + 1);
    assert_eq!(output.dmb.procs.len(), template.procs.len() + 3);
    assert_eq!(output.ids.procs.iter().filter(|&&id| id != NONE).count(), 3);
    output.dmb.validate_references().unwrap();
}

#[test]
fn map_override_and_text_resource_have_native_record_shapes() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let native =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let maps = OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/translation/maps.json"))
        .unwrap();
    let root = Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/../..")).join("fixtures/translation");
    let native_maps = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_annotated_5161687.json"
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
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/translation/assets.json"))
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
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/translation/assets.json"))
            .unwrap();
    input
        .resource_aliases
        .insert("Asset.txt".into(), "asset.txt".into());
    let root = Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/../..")).join("fixtures/translation");
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
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/translation/assets.json"))
            .unwrap();
    input.strings.push("\u{ff11}Telecomms Storage".into());
    let root = Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/../..")).join("fixtures/translation");
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, &root).unwrap();
    let id = *emitted.ids.strings.last().unwrap();
    assert_eq!(
        emitted.dmb.string(id),
        Some(&b"\xff\x16Telecomms Storage"[..])
    );
}
#[test]
fn all_observed_format_markers_match_paired_native_bytes() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/translation/assets.json"))
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
    let root = Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/../..")).join("fixtures/translation");
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
    let source = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/stringtypes.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/stringtypes.native.bin"
    ))
    .unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let first = input.strings.len();
    input.strings.extend(
        source
            .strings
            .iter()
            .filter(|value| value.contains('\u{ff00}') && !baseline.strings.contains(value))
            .cloned(),
    );
    let root = Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/../..")).join("fixtures");
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
        "../../../../fixtures/translation/format_context.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/format_context.native.bin"
    ))
    .unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
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
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
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
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_metadata_defaults_5161687.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/metadata_defaults.native.bin"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/metadata_defaults.json"
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
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/mutable_appearance_subtype.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/mutable_appearance_subtype.native.bin"
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
        "../../../../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let cases: &[(&[u8], &[u8])] = &[
        (
            include_bytes!("../../../../fixtures/translation/savefile_default.json"),
            include_bytes!("../../../../fixtures/translation/savefile_default.native.bin"),
        ),
        (
            include_bytes!("../../../../fixtures/translation/savefile_0.json"),
            include_bytes!("../../../../fixtures/translation/savefile_0.native.bin"),
        ),
        (
            include_bytes!("../../../../fixtures/translation/savefile_513.json"),
            include_bytes!("../../../../fixtures/translation/savefile_513.native.bin"),
        ),
        (
            include_bytes!("../../../../fixtures/translation/savefile_516.json"),
            include_bytes!("../../../../fixtures/translation/savefile_516.native.bin"),
        ),
    ];
    for &(json, bytes) in cases {
        let input = OpenDreamProgram::from_slice(json).unwrap();
        let native = Dmb::from_bytes(bytes).unwrap();
        let template =
            Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
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
    let mut template =
        Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    template.header.compatibility_line = b"min compatibility v514 507\n".to_vec();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let emitted = emit_with_baseline(&baseline, Some(&baseline), &template, Path::new("."))
        .unwrap()
        .dmb;
    assert_eq!(emitted.world.savefile_byond_version, 0);
    let decoded = Dmb::from_bytes(&emitted.to_bytes().unwrap()).unwrap();
    assert_eq!(decoded.world.savefile_byond_version, 0);
}

#[test]
fn world_procedure_membership_excludes_global_procedures() {
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_metadata_defaults_5161687.json"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/translation/world_proc_scope.json"
    ))
    .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/world_proc_scope.native.bin"
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
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
    let mut input =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/native_template.json"))
            .unwrap();
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
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
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
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
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
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
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
    let template = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../../../../fixtures/native_template_annotated_5161687.json"
    ))
    .unwrap();
    let input =
        OpenDreamProgram::from_slice(include_bytes!("../../../../fixtures/translation/map_order.json"))
            .unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../../../../fixtures/translation/map_order.native.bin"
    ))
    .unwrap();
    let emitted = emit_diagnostic_with_baseline_named(
        &input,
        Some(&baseline),
        &template,
        Path::new("../../fixtures/translation"),
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
