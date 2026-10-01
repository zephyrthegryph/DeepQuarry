use byond_dmb::{
    compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
fn selector(dmb: &Dmb, id: usize) -> byond_dmb::operands::Variable {
    use byond_dmb::{
        bytecode::{decode, Operand},
        operands::Variable,
    };
    let instruction = decode(dmb.proc_code_words(id).unwrap())
        .unwrap()
        .into_iter()
        .find(|i| matches!(i.opcode, 0x29 | 0x2a))
        .unwrap();
    let Operand::Variable(mut value) = instruction.typed_operands().unwrap()[0].clone() else {
        panic!("missing selector")
    };
    while let Variable::SetCache(_, nested) = value {
        value = *nested;
    }
    value
}
#[test]
fn static_selector_dispatches_by_actual_display_name() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/static_selector");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(fixtures.join("probe.native.bin")).unwrap()).unwrap();
    let input = OpenDreamProgram::from_path(fixtures.join("probe.json")).unwrap();
    let name = "/datum/selector_static_caller/proc/test";
    let find = |dmb: &Dmb| {
        dmb.procs
            .iter()
            .position(|p| dmb.string(p.strings[0]) == Some(name.as_bytes()))
            .unwrap()
    };
    let byond_dmb::operands::Variable::StaticProc(target) = selector(&native, find(&native)) else {
        panic!("fixture must exercise native StaticProc")
    };
    assert_eq!(
        native.string(native.procs[target as usize].strings[1]),
        Some(b"Base Action".as_slice())
    );
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
        let byond_dmb::operands::Variable::DynamicProc(display) =
            selector(&output.dmb, find(&output.dmb))
        else {
            panic!("output must exercise DynamicProc")
        };
        assert_eq!(output.dmb.string(display), Some(b"Base Action".as_slice()));
        let differences = compare_proc_code(
            &native,
            find(&native),
            &output.dmb,
            find(&output.dmb),
            name,
            30,
            true,
        );
        assert!(differences.is_empty(), "debug={debug}: {differences:#?}");
    }
}
