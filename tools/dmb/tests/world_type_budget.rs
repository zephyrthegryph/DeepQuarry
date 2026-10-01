use byond_dmb::{
    compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
#[test]
fn world_atom_iterators_preserve_native_category_filters_and_budget_checks() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let dir = root.join("fixtures/translation/world_type_budget");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let input = OpenDreamProgram::from_path(dir.join("probe.json")).unwrap();
    let native = Dmb::from_bytes(&std::fs::read(dir.join("probe.native.bin")).unwrap()).unwrap();
    let paths = [
        "/proc/object_root",
        "/proc/object_sub",
        "/proc/mob_root",
        "/proc/turf_root",
        "/proc/area_root",
        "/proc/atom_root",
        "/proc/datum_sub",
        "/proc/datum_root",
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
                let expected_filter = matches!(
                    path,
                    "/proc/object_root" | "/proc/object_sub" | "/proc/atom_root"
                );
                assert_eq!(
                    body.iter().any(|ins| ins.opcode == 0xfa),
                    expected_filter,
                    "{path}"
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
