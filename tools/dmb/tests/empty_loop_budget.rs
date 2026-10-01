use byond_dmb::{
    compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
#[test]
fn empty_constant_true_loops_budget_equal_address_backedges() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let dir = root.join("fixtures/translation/empty_loop_budget");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let input = OpenDreamProgram::from_path(dir.join("probe.json")).unwrap();
    let native = Dmb::from_bytes(&std::fs::read(dir.join("probe.native.bin")).unwrap()).unwrap();
    let paths = ["/proc/empty_while", "/proc/empty_do"];
    for debug in [false, true] {
        let output =
            translate_named_debug(&input, &baseline, &template, &dir, Some("probe"), debug)
                .unwrap();
        let find = |dmb: &Dmb, path: &str| {
            dmb.procs
                .iter()
                .position(|p| {
                    dmb.string(p.strings[0]).is_some_and(|s| {
                        String::from_utf8_lossy(s).replace("/proc/", "/")
                            == path.replace("/proc/", "/")
                    })
                })
                .unwrap()
        };
        for path in paths {
            let body = byond_dmb::bytecode::decode(
                output.dmb.proc_code_words(find(&output.dmb, path)).unwrap(),
            )
            .unwrap();
            let first = body
                .iter()
                .find(|ins| !matches!(ins.opcode, 0x84 | 0x85))
                .unwrap();
            assert_eq!(first.opcode, 0xf8);
            let target = first.branch_targets().unwrap()[0] as usize;
            let selected = body
                .iter()
                .skip_while(|ins| ins.offset < target)
                .find(|ins| !matches!(ins.opcode, 0x84 | 0x85))
                .unwrap();
            assert_eq!(selected.offset, first.offset);
        }
        for path in paths {
            let find = |dmb: &Dmb| {
                dmb.procs
                    .iter()
                    .position(|p| {
                        dmb.string(p.strings[0]).is_some_and(|s| {
                            String::from_utf8_lossy(s).replace("/proc/", "/")
                                == path.replace("/proc/", "/")
                        })
                    })
                    .unwrap()
            };
            let differences = compare_proc_code(
                &native,
                find(&native),
                &output.dmb,
                find(&output.dmb),
                path,
                100,
                true,
            );
            assert!(
                differences.is_empty(),
                "{path}, debug={debug}: {differences:#?}"
            );
        }
    }
}
