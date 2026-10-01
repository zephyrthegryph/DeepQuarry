use byond_dmb::{dmb::Dmb, od_emit::emit_with_baseline, opendream::OpenDreamProgram};
use std::path::Path;
#[test]
fn native_world_view_decimal_parsing_and_encoding() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/world_view_shapes");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let mut names = std::fs::read_dir(&fixtures)
        .unwrap()
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().is_some_and(|e| e == "json"))
        .collect::<Vec<_>>();
    names.sort();
    assert!(names.len() >= 25, "paired matrix missing");
    for path in names {
        let name = path.file_stem().unwrap().to_str().unwrap();
        let input = OpenDreamProgram::from_path(&path).unwrap();
        let native =
            Dmb::from_bytes(&std::fs::read(fixtures.join(format!("{name}.native.bin"))).unwrap())
                .unwrap();
        let output = emit_with_baseline(&input, Some(&baseline), &template, &fixtures).unwrap();
        assert_eq!(
            output.dmb.world.view_dimensions, native.world.view_dimensions,
            "{name}"
        );
        assert_eq!(
            output.dmb.header.flags & 0x200,
            native.header.flags & 0x200,
            "{name}"
        );
    }
    for (before, after) in [
        ("minusone", "half"),
        ("text_0x255", "check_10x0"),
        ("check_70x72", "negative"),
        ("negative", "check_0x10"),
    ] {
        let old = OpenDreamProgram::from_path(fixtures.join(format!("{before}.json"))).unwrap();
        let new = OpenDreamProgram::from_path(fixtures.join(format!("{after}.json"))).unwrap();
        let scaffold = emit_with_baseline(&old, Some(&baseline), &template, &fixtures).unwrap();
        let changed = emit_with_baseline(&new, Some(&old), &scaffold.dmb, &fixtures).unwrap();
        let native =
            Dmb::from_bytes(&std::fs::read(fixtures.join(format!("{after}.native.bin"))).unwrap())
                .unwrap();
        assert_eq!(
            changed.dmb.world.view_dimensions, native.world.view_dimensions,
            "{before}->{after}"
        );
    }
}

#[test]
fn compact_view_words_follow_native_signed_loader_dispatch() {
    use byond_dmb::dmb::WorldViewEncoding;
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let mut world =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap()
            .world;
    for (word, encoding, size) in [
        (0, WorldViewEncoding::Radius(0), (1, 1)),
        (5, WorldViewEncoding::Radius(5), (11, 11)),
        (255, WorldViewEncoding::Radius(255), (511, 511)),
        (0xffff, WorldViewEncoding::Radius(-1), (-1, -1)),
        (
            0x0a00,
            WorldViewEncoding::Dimensions {
                width: 10,
                height: 0,
            },
            (10, 0),
        ),
        (
            0x7fff,
            WorldViewEncoding::Dimensions {
                width: 127,
                height: 255,
            },
            (127, 255),
        ),
        (0x8000, WorldViewEncoding::Radius(i16::MIN), (1, 1)),
    ] {
        world.view_dimensions = word;
        assert_eq!(world.view_encoding(), encoding);
        assert_eq!(world.native_view_size(), size);
        assert_eq!(world.view_size(), ((word >> 8) as u8, word as u8));
    }
}
