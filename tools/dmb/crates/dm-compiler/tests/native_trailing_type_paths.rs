use byond_dmb::{bytecode, dmb::Dmb};

#[test]
fn trailing_slash_type_values_and_new_match_canonical_path() {
    let dmb = Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/trailing_type_paths.native.bin"
    ))
    .unwrap();
    let variable = |name: &str| {
        dmb.variables
            .iter()
            .find(|variable| dmb.string(variable.name) == Some(name.as_bytes()))
            .unwrap()
    };
    let with = variable("type_with_slash");
    let without = variable("type_without_slash");
    assert_eq!((with.kind, with.value), (without.kind, without.value));
    let code = |name: &str| {
        let id = dmb
            .procs
            .iter()
            .position(|proc| dmb.string(proc.strings[0]) == Some(name.as_bytes()))
            .unwrap();
        dmb.proc_code_words(id).unwrap().to_vec()
    };
    assert_eq!(code("/proc/type_path_with_slash"), code("/proc/type_path_without_slash"));
    assert_eq!(code("/proc/new_with_slash"), code("/proc/new_without_slash"));
    let instructions = bytecode::decode(&code("/proc/new_with_slash")).unwrap();
    assert_eq!((instructions[0].name, instructions[1].name), ("PushVal", "New"));
}
