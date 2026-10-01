use byond_dmb::{
    compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
#[test]
fn background_loops_use_native_budget_scheduling_without_synthetic_sleep() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let dir = root.join("fixtures/translation/background_budget");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let input = OpenDreamProgram::from_path(dir.join("probe.json")).unwrap();
    let native = Dmb::from_bytes(&std::fs::read(dir.join("probe.native.bin")).unwrap()).unwrap();
    let paths = [
        "/proc/background_while",
        "/proc/background_do",
        "/proc/background_try",
        "/proc/background_nested",
        "/proc/explicit_sleep",
        "/datum/base/proc/work",
        "/datum/child/proc/work",
        "/proc/not_background",
    ];
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
            let count_sleep = |dmb: &Dmb| {
                byond_dmb::bytecode::decode(dmb.proc_code_words(find(dmb, path)).unwrap())
                    .unwrap()
                    .iter()
                    .filter(|ins| ins.opcode == 0x24)
                    .count()
            };
            assert_eq!(
                count_sleep(&native),
                usize::from(path == "/proc/explicit_sleep")
            );
            assert_eq!(
                count_sleep(&output.dmb),
                usize::from(path == "/proc/explicit_sleep")
            );
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
