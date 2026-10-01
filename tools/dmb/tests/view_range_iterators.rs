use byond_dmb::{
    compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
#[test]
fn inline_view_and_range_preserve_native_collection_iterator_modes() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let dir = root.join("fixtures/translation/view_range_iterators");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let input = OpenDreamProgram::from_path(dir.join("probe.json")).unwrap();
    let native = Dmb::from_bytes(&std::fs::read(dir.join("probe.native.bin")).unwrap()).unwrap();
    let paths = [
        "/proc/view_zero",
        "/proc/view_one",
        "/proc/view_two",
        "/proc/range_zero",
        "/proc/range_one",
        "/proc/range_two",
        "/proc/view_any",
        "/proc/range_untyped",
        "/proc/view_mob",
        "/proc/range_turf",
        "/proc/view_conditional",
        "/proc/range_conditional",
        "/proc/view_whole_conditional",
        "/proc/range_whole_conditional",
        "/proc/view_effectful",
        "/proc/range_effectful",
        "/proc/oview_zero",
        "/proc/oview_one",
        "/proc/oview_two",
        "/proc/oview_any",
        "/proc/oview_untyped",
        "/proc/oview_conditional",
        "/proc/oview_whole_conditional",
        "/proc/oview_list_0",
        "/proc/oview_list_1",
        "/proc/viewers_zero",
        "/proc/viewers_one",
        "/proc/viewers_two",
        "/proc/viewers_any",
        "/proc/viewers_untyped",
        "/proc/viewers_conditional",
        "/proc/viewers_whole_conditional",
        "/proc/viewers_list_0",
        "/proc/viewers_list_1",
        "/proc/oviewers_zero",
        "/proc/oviewers_one",
        "/proc/oviewers_two",
        "/proc/oviewers_any",
        "/proc/oviewers_untyped",
        "/proc/oviewers_conditional",
        "/proc/oviewers_whole_conditional",
        "/proc/oviewers_list_0",
        "/proc/oviewers_list_1",
        "/proc/hearers_zero",
        "/proc/hearers_one",
        "/proc/hearers_two",
        "/proc/hearers_any",
        "/proc/hearers_untyped",
        "/proc/hearers_conditional",
        "/proc/hearers_whole_conditional",
        "/proc/hearers_list_0",
        "/proc/hearers_list_1",
        "/proc/ohearers_zero",
        "/proc/ohearers_one",
        "/proc/ohearers_two",
        "/proc/ohearers_any",
        "/proc/ohearers_untyped",
        "/proc/ohearers_conditional",
        "/proc/ohearers_whole_conditional",
        "/proc/ohearers_list_0",
        "/proc/ohearers_list_1",
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
            for dmb in [&native, &output.dmb] {
                let body =
                    byond_dmb::bytecode::decode(dmb.proc_code_words(find(dmb, path)).unwrap())
                        .unwrap();
                if path.contains("_list_") {
                    assert!(!body.iter().any(|ins| ins.opcode == 0x52));
                    continue;
                }
                let mode = body.iter().find(|ins| ins.opcode == 0x52).unwrap().operands[0];
                let expected = if path.contains("whole_conditional") {
                    5
                } else if path.starts_with("/proc/oviewers_") {
                    16
                } else if path.starts_with("/proc/ohearers_") {
                    18
                } else if path.starts_with("/proc/hearers_") {
                    17
                } else if path.starts_with("/proc/viewers_") {
                    15
                } else if path.starts_with("/proc/oview_") {
                    8
                } else if path.starts_with("/proc/view_") {
                    7
                } else {
                    13
                };
                assert_eq!(mode, expected, "{path}, debug={debug}");
                assert_eq!(
                    body.iter().any(|ins| matches!(
                        ins.opcode,
                        0x1b | 0x59 | 0x1c | 0xe5 | 0xe6 | 0xe7 | 0xe8
                    )),
                    path.contains("whole_conditional")
                );
            }
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
