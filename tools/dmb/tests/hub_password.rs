use byond_dmb::{dmb::Dmb, od_emit::emit_with_baseline, opendream::OpenDreamProgram};
use std::path::Path;

#[test]
fn native_hub_password_hashes_and_null_reset_match() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/hub_password");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    for name in [
        "p0",
        "p1",
        "p2",
        "p3",
        "p4",
        "p5",
        "p6",
        "unicode",
        "controls",
        "escaped",
        "formats",
        "actual_null",
    ] {
        let input = OpenDreamProgram::from_path(fixtures.join(format!("{name}.json"))).unwrap();
        let native =
            Dmb::from_bytes(&std::fs::read(fixtures.join(format!("{name}.native.bin"))).unwrap())
                .unwrap();
        let output = emit_with_baseline(&input, Some(&baseline), &template, &fixtures).unwrap();
        assert_eq!(
            output.dmb.string(output.dmb.world.hub_password),
            native.string(native.world.hub_password),
            "{name}"
        );
        output.dmb.validate_references().unwrap();
    }
    let previous = OpenDreamProgram::from_path(fixtures.join("p2.json")).unwrap();
    let previous_template =
        Dmb::from_bytes(&std::fs::read(fixtures.join("p2.native.bin")).unwrap()).unwrap();
    let cleared = OpenDreamProgram::from_path(fixtures.join("actual_null.json")).unwrap();
    let output =
        emit_with_baseline(&cleared, Some(&previous), &previous_template, &fixtures).unwrap();
    assert_eq!(output.dmb.world.hub_password, 0xffff);
}

#[test]
fn native_hub_password_retains_last_text_assignment_before_null() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/hub_password_history");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    for name in [
        "secret_null",
        "secret_empty_null",
        "secret_other_null",
        "folded_null",
        "only_null",
    ] {
        let input = OpenDreamProgram::from_path(fixtures.join(format!("{name}.json"))).unwrap();
        let native =
            Dmb::from_bytes(&std::fs::read(fixtures.join(format!("{name}.native.bin"))).unwrap())
                .unwrap();
        let output = emit_with_baseline(&input, Some(&baseline), &template, &fixtures).unwrap();
        assert_eq!(
            output.dmb.string(output.dmb.world.hub_password),
            native.string(native.world.hub_password),
            "{name}"
        );
    }
}
