use byond_dmb::{
    bytecode::decode, dmb::Dmb, opendream::OpenDreamProgram, translate::translate_named_debug,
};
use std::path::Path;

fn branch_frames(dmb: &Dmb, path: &str) -> (Vec<usize>, usize, usize) {
    let id = dmb
        .procs
        .iter()
        .position(|p| dmb.string(p.strings[0]) == Some(path.as_bytes()))
        .unwrap();
    let body = decode(dmb.proc_code_words(id).unwrap()).unwrap();
    let regions: Vec<_> = body
        .iter()
        .filter(|i| i.opcode == 0x12c)
        .map(|i| (i.offset + 2, i.operands[0] as usize))
        .collect();
    let unwound = body
        .iter()
        .filter(|i| i.opcode == 0x12f)
        .map(|i| {
            let destination = i.operands[0] as usize - 1;
            regions
                .iter()
                .filter(|(start, end)| {
                    *start <= i.offset
                        && i.offset < *end
                        && !(*start <= destination && destination < *end)
                })
                .count()
        })
        .collect();
    (
        unwound,
        body.iter().filter(|i| i.opcode == 0x12e).count(),
        body.iter().filter(|i| i.opcode == 0xf8).count(),
    )
}

#[test]
fn authored_protected_loop_branches_preserve_native_exception_frames() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixture = root.join("fixtures/translation/try_loop_provenance");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(fixture.join("try_loop_provenance.native.bin")).unwrap())
            .unwrap();
    let input = OpenDreamProgram::from_path(fixture.join("try_loop_provenance.json")).unwrap();
    for debug in [false, true] {
        let output = translate_named_debug(
            &input,
            &baseline,
            &template,
            &fixture,
            Some("try_loop_provenance"),
            debug,
        )
        .unwrap();
        for name in [
            "head_continue",
            "prefixed_continue",
            "natural_tail",
            "nested_continue",
            "indexed_continue",
            "loop_break",
            "head_goto",
            "forward_goto",
            "unprotected_goto",
        ] {
            let path = format!("/proc/try_{name}");
            let expected = branch_frames(&native, &path);
            let actual = branch_frames(&output.dmb, &path);
            assert_eq!(
                actual.0, expected.0,
                "debug={debug} {path}: exception-frame cleanup at continue"
            );
            assert_eq!(
                actual.1, expected.1,
                "debug={debug} {path}: authored break/normal cleanup handlers"
            );
            if matches!(name, "head_continue" | "head_goto") {
                assert_eq!(expected.0, vec![1]);
            }
            if matches!(name, "prefixed_continue" | "forward_goto") {
                assert_eq!(expected.0, vec![0]);
            }
            if name == "natural_tail" {
                assert!(actual.0.is_empty());
                assert_eq!(actual.2, 1);
            }
            if name == "loop_break" {
                assert_eq!(actual.1, 2);
            }
        }
    }
}
