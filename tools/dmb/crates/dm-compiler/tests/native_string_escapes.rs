use byond_dmb::{bytecode, dmb::Dmb};

#[test]
fn native_string_escape_bytes_and_empty_brackets() {
    let dmb = Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/string_escapes.native.bin"
    ))
    .unwrap();
    let expected: &[(&str, &[u8])] = &[
        ("/proc/line_join", b"alpha beta"),
        ("/proc/escaped_space", b"leftright"),
        ("/proc/hex_bytes", &[0xc3, 0xbf, 0xc3, 0x98, 0xc3, 0xbf]),
        ("/proc/hex_png", &[0xc2, 0x89, b'P', b'N', b'G']),
        ("/proc/escaped_brackets", b"[]"),
        ("/proc/escaped_slash_empty_brackets", &[b'\\', 0xff, 1]),
        ("/proc/regex_like", &[b'a', b'\\', 0xff, 1, b'b']),
    ];
    for (path, bytes) in expected {
        let id = dmb
            .procs
            .iter()
            .position(|proc| dmb.string(proc.strings[0]) == Some(path.as_bytes()))
            .unwrap();
        let code = bytecode::decode(dmb.proc_code_words(id).unwrap()).unwrap();
        assert_eq!(code.iter().map(|i| i.name).collect::<Vec<_>>(), ["PushVal", "Ret", "End"]);
        assert_eq!(code[0].operands[0], 6);
        assert_eq!(dmb.string(code[0].operands[1]), Some(*bytes), "{path}");
    }
}
