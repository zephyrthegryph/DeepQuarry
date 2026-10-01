use byond_dmb::{
    bytecode::decode, compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
#[test]
fn deletion_clears_only_native_mutable_intrinsics() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/delete_readonly_intrinsics");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(fixtures.join("probe.native.bin")).unwrap()).unwrap();
    let input = OpenDreamProgram::from_path(fixtures.join("probe.json")).unwrap();
    let cases = native
        .procs
        .iter()
        .enumerate()
        .filter_map(|(id, p)| {
            let path = String::from_utf8(native.string(p.strings[0])?.to_vec()).ok()?;
            path.contains("/delete_intrinsic_").then_some((id, path))
        })
        .collect::<Vec<_>>();
    assert_eq!(cases.len(), 12);
    for debug in [false, true] {
        let output = translate_named_debug(
            &input,
            &baseline,
            &template,
            &fixtures,
            Some("probe"),
            debug,
        )
        .unwrap();
        for (native_id, path) in &cases {
            let actual = output
                .dmb
                .procs
                .iter()
                .position(|p| output.dmb.string(p.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            let differences =
                compare_proc_code(&native, *native_id, &output.dmb, actual, path, 60, true);
            assert!(
                differences.is_empty(),
                "debug={debug} {path}: {differences:#?}"
            );
            for (dmb, id) in [(&native, *native_id), (&output.dmb, actual)] {
                let body = decode(dmb.proc_code_words(id).unwrap())
                    .unwrap()
                    .into_iter()
                    .filter(|i| !matches!(i.opcode, 0x84 | 0x85))
                    .collect::<Vec<_>>();
                let del = body.iter().position(|i| i.opcode == 0x0c).unwrap();
                let mutable = path.ends_with("_src")
                    || path.ends_with("_usr")
                    || path.ends_with("_args")
                    || path.ends_with("_global_type");
                assert_eq!(
                    body[..del].iter().filter(|i| i.opcode == 0x34).count(),
                    usize::from(mutable),
                    "{path}: native intrinsic mutability"
                );
                if mutable {
                    assert_eq!(body[del - 2].opcode, 0x60);
                    assert_eq!(body[del - 2].operands, vec![0, 0]);
                }
                if path.ends_with("_src") {
                    assert_eq!(body[del + 1].opcode, 0);
                }
            }
        }
    }
}
