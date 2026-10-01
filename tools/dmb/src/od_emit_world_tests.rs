use super::{emit_with_baseline, Dmb, OpenDreamProgram};
use std::path::Path;

#[test]
fn native_status_version_and_executor_headers_are_preserved() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    for (name, json, bytes) in [
        (
            "status",
            include_bytes!("../fixtures/translation/world_header_fields/status.json").as_slice(),
            include_bytes!("../fixtures/translation/world_header_fields/status.native.bin")
                .as_slice(),
        ),
        (
            "version",
            include_bytes!("../fixtures/translation/world_header_fields/version.json").as_slice(),
            include_bytes!("../fixtures/translation/world_header_fields/version.native.bin")
                .as_slice(),
        ),
        (
            "executor",
            include_bytes!("../fixtures/translation/world_header_fields/executor.json").as_slice(),
            include_bytes!("../fixtures/translation/world_header_fields/executor.native.bin")
                .as_slice(),
        ),
        (
            "status_null",
            include_bytes!("../fixtures/translation/world_header_fields/status_null.json")
                .as_slice(),
            include_bytes!("../fixtures/translation/world_header_fields/status_null.native.bin")
                .as_slice(),
        ),
        (
            "executor_empty",
            include_bytes!("../fixtures/translation/world_header_fields/executor_empty.json")
                .as_slice(),
            include_bytes!("../fixtures/translation/world_header_fields/executor_empty.native.bin")
                .as_slice(),
        ),
        (
            "executor_null",
            include_bytes!("../fixtures/translation/world_header_fields/executor_null.json")
                .as_slice(),
            include_bytes!("../fixtures/translation/world_header_fields/executor_null.native.bin")
                .as_slice(),
        ),
        (
            "status_history",
            include_bytes!("../fixtures/translation/world_header_fields/status_history.json")
                .as_slice(),
            include_bytes!("../fixtures/translation/world_header_fields/status_history.native.bin")
                .as_slice(),
        ),
        (
            "name_null",
            include_bytes!("../fixtures/translation/world_header_fields/name_null.json").as_slice(),
            include_bytes!("../fixtures/translation/world_header_fields/name_null.native.bin")
                .as_slice(),
        ),
        (
            "executor_unicode",
            include_bytes!("../fixtures/translation/world_header_fields/executor_unicode.json")
                .as_slice(),
            include_bytes!(
                "../fixtures/translation/world_header_fields/executor_unicode.native.bin"
            )
            .as_slice(),
        ),
        (
            "executor_multiline",
            include_bytes!("../fixtures/translation/world_header_fields/executor_multiline.json")
                .as_slice(),
            include_bytes!(
                "../fixtures/translation/world_header_fields/executor_multiline.native.bin"
            )
            .as_slice(),
        ),
        (
            "executor_formatted",
            include_bytes!("../fixtures/translation/world_header_fields/executor_formatted.json")
                .as_slice(),
            include_bytes!(
                "../fixtures/translation/world_header_fields/executor_formatted.native.bin"
            )
            .as_slice(),
        ),
    ] {
        let input = OpenDreamProgram::from_slice(json).unwrap();
        let native = Dmb::from_bytes(bytes).unwrap();
        assert_eq!(
            native.to_bytes().unwrap(),
            bytes,
            "{name} native byte roundtrip"
        );
        let output =
            emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
        assert_eq!(
            output.dmb.string(output.dmb.world.server_name),
            native.string(native.world.server_name),
            "{name} status"
        );
        assert_eq!(
            output.dmb.world.version, native.world.version,
            "{name} version"
        );
        assert_eq!(
            output.dmb.header.executor_line, native.header.executor_line,
            "{name} executor"
        );
        let encoded = output.dmb.to_bytes().unwrap();
        assert_eq!(
            Dmb::from_bytes(&encoded).unwrap().header.executor_line,
            native.header.executor_line
        );
    }
}
#[test]
fn world_version_uses_native_signed_float_integer_conversion() {
    let baseline = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/native_template_savefile_5161687.json"
    ))
    .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let mut input = OpenDreamProgram::from_slice(include_bytes!(
        "../fixtures/translation/world_header_fields/version.json"
    ))
    .unwrap();
    let world = input.types.iter().position(|t| t.path == "/world").unwrap();
    // Independently compiled native values, including float32 rounding and out-of-range clamps.
    for (value, expected) in [
        (-1.0, u32::MAX),
        (0.0, 0),
        (1.9, 1),
        (-1.9, u32::MAX),
        (16777217.0, 16777216),
        (2147483647.0, 2147483648),
        (2147483648.0, 2147483648),
        (4294967295.0, 2147483647),
        (1e20, 2147483647),
        (-1e20, 2147483649),
    ] {
        input.types[world]
            .variables
            .insert("version".into(), serde_json::json!(value));
        let output =
            emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
        assert_eq!(output.dmb.world.version, expected, "{value}");
    }
}
