use byond_dmb::{
    bytecode::decode,
    compare::compare_proc_code,
    dmb::Dmb,
    od_lower::{lower_proc_bytecode, SymbolResolver},
    opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
fn check(name: &str, names: &[&str]) {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let dir = root.join("fixtures/translation").join(name);
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native = Dmb::from_bytes(&std::fs::read(dir.join("probe.native.bin")).unwrap()).unwrap();
    let input = OpenDreamProgram::from_path(dir.join("probe.json")).unwrap();
    for debug in [false, true] {
        let output =
            translate_named_debug(&input, &baseline, &template, &dir, Some("probe"), debug)
                .unwrap();
        for name in names {
            let path = format!("/proc/{name}");
            let find = |dmb: &Dmb| {
                dmb.procs
                    .iter()
                    .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
                    .unwrap()
            };
            let differences = compare_proc_code(
                &native,
                find(&native),
                &output.dmb,
                find(&output.dmb),
                &path,
                100,
                true,
            );
            assert!(
                differences.is_empty(),
                "{path} debug={debug}: {differences:#?}"
            );
        }
        if name == "initial_saved_wrappers" {
            for dmb in [&native, &output.dmb] {
                let readonly = dmb.lists[dmb.variable_footer as usize]
                    .chunks_exact(2)
                    .filter(|pair| {
                        pair[1] == 3
                            && dmb.string(dmb.variables[pair[0] as usize].name)
                                == Some(b"foo".as_slice())
                    })
                    .count();
                assert_eq!(
                    readonly, 3,
                    "numeric local constants retain separate readonly global bindings"
                );
                for (name, expected) in [(b"X".as_slice(), 5), (b"UNUSED".as_slice(), 1)] {
                    assert_eq!(
                        dmb.lists[dmb.variable_footer as usize]
                            .chunks_exact(2)
                            .filter(|pair| pair[1] == 3
                                && dmb.string(dmb.variables[pair[0] as usize].name) == Some(name))
                            .count(),
                        expected,
                        "folded and unused declarations retain readonly bindings"
                    );
                }
                let path = "/proc/ordinary_const";
                let id = dmb
                    .procs
                    .iter()
                    .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
                    .unwrap();
                let body = decode(dmb.proc_code_words(id).unwrap()).unwrap();
                assert!(
                    body.iter().any(|i| i.opcode == 0x33 && matches!(i.typed_operands().unwrap().as_slice(),
                        [byond_dmb::bytecode::Operand::Variable(byond_dmb::operands::Variable::Global(id))]
                        if dmb.string(dmb.variables[*id as usize].name) == Some(b"foo".as_slice())
                            && dmb.variables[*id as usize].number() == Some(7.0))),
                    "direct numeric constant reads use their readonly global binding"
                );
            }
        }
    }
}
#[test]
fn nonnumeric_constant_logarithms_preserve_native_runtime_instructions() {
    check(
        "log_constant_fallback",
        &[
            "log_text",
            "log_base_text",
            "log_null",
            "log_base_null",
            "log_numeric",
            "log_base_numeric",
            "log_runtime",
        ],
    );
}
#[test]
fn nested_initial_saved_selectors_preserve_outer_reference_modifiers() {
    check(
        "initial_saved_wrappers",
        &[
            "initial_saved_local",
            "initial_saved_arg",
            "initial_saved_field",
            "saved_initial_field",
            "initial_initial_field",
            "saved_saved_field",
            "initial_saved_computed",
            "get_owner",
            "saved_local",
            "saved_arg",
            "saved_initial_local",
            "saved_initial_arg",
            "initial_const",
            "saved_const",
            "ordinary_const",
            "constant_number_read",
            "constant_text_read",
            "constant_type_read",
            "constant_number_fold",
            "constant_text_fold",
            "constant_unused",
        ],
    );
}

#[test]
fn native_global_reference_modifiers_require_readonly_source_bindings() {
    struct GlobalModifier {
        readonly: bool,
        saved: bool,
    }
    impl SymbolResolver for GlobalModifier {
        fn global(&self, old: u32) -> Option<u32> {
            (old == 0).then_some(99)
        }
        fn native_constant_global(&self, old: u32) -> bool {
            self.readonly && old == 0
        }
        fn native_initial_reference(&self, at: usize) -> bool {
            !self.saved && at == 0
        }
        fn native_is_saved_reference(&self, at: usize) -> bool {
            self.saved && at == 0
        }
        fn native_initial_reference_offsets(&self) -> &[usize] {
            if self.saved {
                &[]
            } else {
                &[0]
            }
        }
        fn native_is_saved_reference_offsets(&self) -> &[usize] {
            if self.saved {
                &[0]
            } else {
                &[]
            }
        }
    }
    let code = [0x06, 10, 0, 0, 0, 0, 0x10];
    for saved in [false, true] {
        assert!(lower_proc_bytecode(
            &code,
            &GlobalModifier {
                readonly: false,
                saved
            }
        )
        .is_err());
        assert_eq!(
            lower_proc_bytecode(
                &code,
                &GlobalModifier {
                    readonly: true,
                    saved
                }
            )
            .unwrap(),
            [
                0x33,
                if saved { 0xffe8 } else { 0xffe7 },
                0xffdb,
                99,
                0x12,
                0
            ]
        );
    }
}
struct Marked {
    initial: &'static [usize],
    saved: &'static [usize],
}
impl SymbolResolver for Marked {
    fn native_initial_reference(&self, at: usize) -> bool {
        self.initial.contains(&at)
    }
    fn native_is_saved_reference(&self, at: usize) -> bool {
        self.saved.contains(&at)
    }
    fn native_initial_reference_offsets(&self) -> &[usize] {
        self.initial
    }
    fn native_is_saved_reference_offsets(&self) -> &[usize] {
        self.saved
    }
}
#[test]
fn reference_modifier_provenance_is_bounded_and_legacy_optional() {
    let code = [0x06, 8, 0, 0x10];
    assert_eq!(
        lower_proc_bytecode(&code, &()).unwrap(),
        [0x33, 0xffd9, 0, 0x12, 0]
    );
    assert_eq!(
        lower_proc_bytecode(
            &code,
            &Marked {
                initial: &[0],
                saved: &[]
            }
        )
        .unwrap(),
        [0x33, 0xffe7, 0xffd9, 0, 0x12, 0]
    );
    assert_eq!(
        lower_proc_bytecode(
            &code,
            &Marked {
                initial: &[],
                saved: &[0]
            }
        )
        .unwrap(),
        [0x33, 0xffe8, 0xffd9, 0, 0x12, 0]
    );
    for marker in [
        Marked {
            initial: &[1],
            saved: &[],
        },
        Marked {
            initial: &[99],
            saved: &[],
        },
        Marked {
            initial: &[0],
            saved: &[0],
        },
    ] {
        assert!(lower_proc_bytecode(&code, &marker).is_err());
    }
    assert!(lower_proc_bytecode(
        &[0x06, 1, 0x10],
        &Marked {
            initial: &[0],
            saved: &[]
        }
    )
    .is_err());
    assert!(lower_proc_bytecode(
        &[0x06, 8, 6, 0x10],
        &Marked {
            initial: &[2],
            saved: &[]
        }
    )
    .is_err());
}
