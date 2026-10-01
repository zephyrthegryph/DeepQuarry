use byond_dmb::{dmb::Dmb, od_emit::emit_with_baseline, opendream::OpenDreamProgram};
use std::path::Path;

#[test]
fn native_executor_prefix_keeps_body_cipher_origin() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/world_header_fields");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    for name in [
        "executor",
        "executor_unicode",
        "executor_multiline",
        "executor_formatted",
    ] {
        let bytes = std::fs::read(fixtures.join(format!("{name}.native.bin"))).unwrap();
        let native = Dmb::from_bytes(&bytes).unwrap_or_else(|e| panic!("{name}: {e}"));
        assert_eq!(native.to_bytes().unwrap(), bytes, "{name} native roundtrip");
        let input = OpenDreamProgram::from_path(fixtures.join(format!("{name}.json"))).unwrap();
        let output = emit_with_baseline(&input, Some(&baseline), &template, &fixtures).unwrap();
        assert_eq!(
            output.dmb.header.executor_line, native.header.executor_line,
            "{name}"
        );
        let encoded = output.dmb.to_bytes().unwrap();
        let parsed = Dmb::from_bytes(&encoded).unwrap();
        assert_eq!(
            parsed.to_bytes().unwrap(),
            encoded,
            "{name} emitted roundtrip"
        );
    }
}

#[test]
fn native_executor_keeps_only_its_first_ascii_space() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/executor_whitespace");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    for name in [
        "spaces",
        "leading",
        "repeated",
        "tab_first",
        "tab_after",
        "newline_first",
        "newline_after",
    ] {
        let bytes = std::fs::read(fixtures.join(format!("{name}.native.bin"))).unwrap();
        let native = Dmb::from_bytes(&bytes).unwrap();
        assert_eq!(native.to_bytes().unwrap(), bytes, "{name} native roundtrip");
        let input = OpenDreamProgram::from_path(fixtures.join(format!("{name}.json"))).unwrap();
        let output = emit_with_baseline(&input, Some(&baseline), &template, &fixtures).unwrap();
        assert_eq!(
            output.dmb.header.executor_line, native.header.executor_line,
            "{name}"
        );
        let encoded = output.dmb.to_bytes().unwrap();
        assert_eq!(
            Dmb::from_bytes(&encoded).unwrap().to_bytes().unwrap(),
            encoded
        );
    }
}
