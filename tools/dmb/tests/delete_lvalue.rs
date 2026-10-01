use byond_dmb::{
    bytecode::decode, compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
#[test]
fn deleting_mutable_storage_clears_it_before_deletion() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/delete_lvalue");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(fixtures.join("delete_lvalue.native.bin")).unwrap())
            .unwrap();
    let input = OpenDreamProgram::from_path(fixtures.join("delete_lvalue.json")).unwrap();
    let cases = native
        .procs
        .iter()
        .enumerate()
        .filter_map(|(id, p)| {
            let path = String::from_utf8(native.string(p.strings[0])?.to_vec()).ok()?;
            path.split('/')
                .next_back()?
                .starts_with("delete_")
                .then_some((id, path))
        })
        .collect::<Vec<_>>();
    assert_eq!(cases.len(), 23, "all authored native deletion cases");
    for debug in [false, true] {
        let output = translate_named_debug(
            &input,
            &baseline,
            &template,
            &fixtures,
            Some("delete_lvalue"),
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
                let deletion = body.iter().position(|i| i.opcode == 0xc).unwrap();
                if path.ends_with("delete_local") {
                    assert_eq!(body[deletion - 2].opcode, 0x60);
                    assert_eq!(body[deletion - 2].operands, vec![0, 0]);
                    assert_eq!(body[deletion - 1].opcode, 0x34);
                    assert_eq!(body[deletion + 1].opcode, 0x33);
                    assert_eq!(body[deletion - 1].operands, body[deletion + 1].operands);
                }
                if path.ends_with("delete_effectful_index") {
                    assert_eq!(
                        body[..deletion].iter().filter(|i| i.opcode == 0x30).count(),
                        4,
                        "owner/key reread"
                    );
                    assert_eq!(body[deletion - 1].opcode, 0x7c);
                }
                if path.contains("delete_const_") {
                    assert!(
                        !body[..deletion]
                            .iter()
                            .any(|i| matches!(i.opcode, 0x34 | 0x7c)),
                        "readonly binding mutated"
                    );
                }
            }
        }
    }
}
