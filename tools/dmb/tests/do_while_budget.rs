use byond_dmb::bytecode::decode;
use byond_dmb::{
    compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
#[test]
fn authored_do_while_checks_budget_on_the_final_false_condition() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let dir = root.join("fixtures/translation/do_while_budget");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let input = OpenDreamProgram::from_path(dir.join("probe.json")).unwrap();
    let native = Dmb::from_bytes(&std::fs::read(dir.join("probe.native.bin")).unwrap()).unwrap();
    let paths = [
        "/proc/simple",
        "/proc/effectful",
        "/proc/continue_tail",
        "/proc/nested",
        "/proc/protected",
        "/proc/body_try",
        "/proc/conditional_goto",
        "/proc/conditional_continue",
        "/proc/false_tail",
        "/proc/true_tail",
        "/proc/null_tail",
        "/proc/const_null_tail",
        "/proc/const_zero_tail",
        "/proc/const_null_outside",
        "/proc/iterator_body",
        "/proc/protected_continue",
        "/proc/const_true_continue",
    ];
    for debug in [false, true] {
        let output =
            translate_named_debug(&input, &baseline, &template, &dir, Some("probe"), debug)
                .unwrap();
        let find = |dmb: &Dmb, path: &str| {
            dmb.procs
                .iter()
                .position(|p| dmb.string(p.strings[0]) == Some(path.as_bytes()))
                .unwrap()
        };
        for path in [
            "/proc/simple",
            "/proc/effectful",
            "/proc/continue_tail",
            "/proc/nested",
            "/proc/protected",
            "/proc/body_try",
            "/proc/iterator_body",
            "/proc/protected_continue",
        ] {
            for dmb in [&native, &output.dmb] {
                let body = decode(dmb.proc_code_words(find(dmb, path)).unwrap()).unwrap();
                assert!(
                    body.iter().any(|i| i.opcode == 0xf9),
                    "final-false budget check missing: {path}, debug={debug}"
                );
            }
        }
        for path in [
            "/proc/conditional_goto",
            "/proc/conditional_continue",
            "/proc/false_tail",
            "/proc/true_tail",
            "/proc/null_tail",
            "/proc/const_null_tail",
            "/proc/const_zero_tail",
            "/proc/const_null_outside",
        ] {
            let body =
                decode(output.dmb.proc_code_words(find(&output.dmb, path)).unwrap()).unwrap();
            assert!(
                !body.iter().any(|i| i.opcode == 0xf9),
                "unrelated conditional budget fusion: {path}"
            );
        }
        // This control has an unreachable natural tail in native code that the
        // source optimizer removes. Check the reachable budget graph explicitly.
        for dmb in [&native, &output.dmb] {
            let body = decode(
                dmb.proc_code_words(find(dmb, "/proc/const_true_unreachable"))
                    .unwrap(),
            )
            .unwrap();
            let by_offset: std::collections::HashMap<_, _> = body
                .iter()
                .enumerate()
                .map(|(i, ins)| (ins.offset, i))
                .collect();
            let mut pending = vec![0usize];
            let mut seen = std::collections::HashSet::new();
            let mut budgeted = 0;
            while let Some(i) = pending.pop() {
                if !seen.insert(i) {
                    continue;
                }
                let ins = &body[i];
                if ins.opcode == 0xf8 {
                    budgeted += 1;
                    let target = ins.branch_targets().unwrap()[0] as usize;
                    assert_ne!(
                        body[by_offset[&target]].opcode, 0xf8,
                        "double continue budget"
                    );
                }
                for target in ins.branch_targets().unwrap() {
                    pending.push(by_offset[&(target as usize)]);
                }
                if !matches!(ins.opcode, 0 | 0x12 | 0x0f | 0xf8) && i + 1 < body.len() {
                    pending.push(i + 1);
                }
            }
            assert_eq!(budgeted, 1, "unreachable natural tail must not count");
        }
        for path in paths {
            let find = |dmb: &Dmb| {
                dmb.procs
                    .iter()
                    .position(|p| dmb.string(p.strings[0]) == Some(path.as_bytes()))
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
