use byond_dmb::{bytecode, dmb::Dmb};

fn proc_id(dmb: &Dmb, path: &str) -> usize {
    dmb.procs
        .iter()
        .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
        .unwrap()
}

#[test]
fn each_override_uses_its_own_proc_ref_and_parent_call() {
    let dmb = Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/proc_override_chain.native.bin"
    ))
    .unwrap();
    let paths = [
        "/datum/override_probe/child/grandchild/foo",
        "/datum/override_probe/child/foo",
        "/datum/override_probe/proc/foo",
    ];
    for (ordinal, path) in paths.iter().enumerate() {
        let id = proc_id(&dmb, path);
        assert_eq!(id, ordinal);
        let code = bytecode::decode(dmb.proc_code_words(id).unwrap()).unwrap();
        assert_eq!(code[0].name, "PushVal");
        assert_eq!(code[0].operands, [38, id as u32]);
        assert_eq!(code.iter().any(|i| i.name == "CallParent"), ordinal < 2);
    }
}

#[test]
fn custom_display_name_does_not_replace_source_proc_path() {
    let dmb = Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/proc_override_chain.native.bin"
    ))
    .unwrap();
    let id = proc_id(&dmb, "/datum/override_probe/proc/under_score");
    assert_eq!(dmb.string(dmb.procs[id].strings[1]), Some(b"Custom Visible Name".as_slice()));
    let global = proc_id(&dmb, "/proc/global_under_score");
    assert_eq!(dmb.string(dmb.procs[global].strings[1]), Some(b"Global Visible Name".as_slice()));
    let direct = bytecode::decode(
        dmb.proc_code_words(proc_id(&dmb, "/proc/invoke_source_name"))
            .unwrap(),
    )
    .unwrap();
    assert!(direct[0].operands.contains(&(id as u32)));
    let dynamic = bytecode::decode(
        dmb.proc_code_words(proc_id(&dmb, "/proc/invoke_dynamic_source_name"))
            .unwrap(),
    )
    .unwrap();
    let string_id = dynamic.iter().find(|i| i.name == "PushVal").unwrap().operands[1];
    assert_eq!(dmb.string(string_id), Some(b"under_score".as_slice()));
}

#[test]
fn native_calls_use_display_selector_or_static_proc_for_custom_name() {
    let dmb = Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/proc_override_chain.native.bin"
    ))
    .unwrap();
    let renamed = proc_id(&dmb, "/datum/override_probe/proc/under_score") as u32;
    for path in [
        "/proc/invoke_source_name",
        "/proc/invoke_named_colon",
        "/proc/invoke_named_colon_untyped",
    ] {
        let code = bytecode::decode(dmb.proc_code_words(proc_id(&dmb, path)).unwrap()).unwrap();
        assert_eq!(code[0].name, "Call");
        assert_eq!(&code[0].operands[3..5], &[0xffdf, renamed]);
    }
    let plain = proc_id(&dmb, "/datum/override_probe/proc/plain_method");
    assert_eq!(dmb.string(dmb.procs[plain].strings[1]), Some(b"plain method".as_slice()));
    for path in [
        "/proc/invoke_plain_typed",
        "/proc/invoke_plain_colon",
        "/proc/invoke_plain_colon_untyped",
    ] {
        let code = bytecode::decode(dmb.proc_code_words(proc_id(&dmb, path)).unwrap()).unwrap();
        assert_eq!(code[0].name, "Call");
        assert_eq!(code[0].operands[3], 0xffdd);
        assert_eq!(dmb.string(code[0].operands[4]), Some(b"plain method".as_slice()));
    }
}
