use byond_dmb::{dmb::Dmb, opendream::OpenDreamProgram, translate::translate_named_debug};
use std::path::Path;
#[test]
fn switch_defaults_preserve_authored_transfer_operations() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let dir = root.join("fixtures/translation/switch_default_transfer");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let input = OpenDreamProgram::from_path(dir.join("probe.json")).unwrap();
    let native = Dmb::from_bytes(&std::fs::read(dir.join("probe.native.bin")).unwrap()).unwrap();
    let paths = [
        "/proc/range_continue",
        "/proc/exact_continue",
        "/proc/string_goto",
        "/proc/range_protected_continue",
        "/proc/plain_default",
    ];
    let mut legacy = OpenDreamProgram::from_path(dir.join("probe.json")).unwrap();
    for proc in &mut legacy.procs {
        proc.native_continue_offsets = None;
        proc.native_goto_offsets.clear();
    }
    for debug in [false, true] {
        let output =
            translate_named_debug(&legacy, &baseline, &template, &dir, Some("probe"), debug)
                .unwrap();
        let id = output
            .dmb
            .procs
            .iter()
            .position(|p| output.dmb.string(p.strings[0]) == Some(b"/proc/string_goto".as_slice()))
            .unwrap();
        let body = byond_dmb::bytecode::decode(output.dmb.proc_code_words(id).unwrap()).unwrap();
        let table = body.iter().find(|ins| ins.opcode == 0x78).unwrap();
        let target = *table.branch_targets().unwrap().last().unwrap() as usize;
        let first = body
            .iter()
            .skip_while(|ins| ins.offset < target)
            .find(|ins| !matches!(ins.opcode, 0x84 | 0x85))
            .unwrap();
        assert_eq!(
            first.opcode, 0xf8,
            "legacy backward default must execute its budget check"
        );
    }
    for debug in [false, true] {
        let output =
            translate_named_debug(&input, &baseline, &template, &dir, Some("probe"), debug)
                .unwrap();
        for path in paths {
            let find = |dmb: &Dmb| {
                dmb.procs
                    .iter()
                    .position(|p| dmb.string(p.strings[0]) == Some(path.as_bytes()))
                    .unwrap()
            };
            let trace = |dmb: &Dmb| {
                let body =
                    byond_dmb::bytecode::decode(dmb.proc_code_words(find(dmb)).unwrap()).unwrap();
                let at: std::collections::HashMap<_, _> = body
                    .iter()
                    .enumerate()
                    .map(|(i, ins)| (ins.offset, i))
                    .collect();
                let table = body
                    .iter()
                    .find(|ins| matches!(ins.opcode, 0x78 | 0x7a))
                    .unwrap();
                table
                    .branch_targets()
                    .unwrap()
                    .into_iter()
                    .map(|target| {
                        let mut i = at[&(target as usize)];
                        let mut result = Vec::new();
                        for _ in 0..body.len() {
                            let ins = &body[i];
                            if matches!(ins.opcode, 0x84 | 0x85) {
                                i += 1;
                                continue;
                            }
                            if ins.opcode == 0x0f {
                                i = at[&(ins.branch_targets().unwrap()[0] as usize)];
                                continue;
                            }
                            if matches!(ins.opcode, 0xf8 | 0x12e | 0x12f) {
                                let mut destination =
                                    at[&(ins.branch_targets().unwrap()[0] as usize)];
                                while matches!(body[destination].opcode, 0x84 | 0x85) {
                                    destination += 1;
                                }
                                let mut destination_value = vec![body[destination].opcode];
                                destination_value.extend(&body[destination].operands);
                                result.push((ins.opcode, destination_value));
                                return result;
                            }
                            if ins.opcode == 0x50 {
                                let bits = (ins.operands[0] as i32 as f32).to_bits();
                                result.push((0x60, vec![42, bits >> 16, bits & 0xffff]));
                            } else {
                                result.push((ins.opcode, ins.operands.clone()));
                            }
                            if matches!(ins.opcode, 0x12 | 0) {
                                return result;
                            }
                            // An increment is the shared for-loop continuation.
                            if ins.opcode == 0x66 {
                                return result;
                            }
                            i += 1;
                        }
                        panic!("arm trace did not reach a bounded continuation");
                    })
                    .collect::<Vec<_>>()
            };
            assert_eq!(trace(&native), trace(&output.dmb), "{path}, debug={debug}");
            if path != "/proc/plain_default" {
                let arms = trace(&output.dmb);
                let expected = if path == "/proc/range_protected_continue" {
                    0x12f
                } else {
                    0xf8
                };
                assert_eq!(
                    arms.last().unwrap()[0].0,
                    expected,
                    "default authored transfer must execute"
                );
            }
        }
    }
}
