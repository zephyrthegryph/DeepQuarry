use byond_dmb::{bytecode, dmb::Dmb, od_emit::emit_with_baseline, opendream::OpenDreamProgram};
use std::path::Path;

#[test]
fn code_edit_crosses_nullable_list_id_and_promotes_object_width() {
    let mut dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    dmb.header.flags &= !0x4000_0000;
    dmb.lists.resize(0xffff, Vec::new());
    let instructions = bytecode::decode(&[0x50, 7, 0]).unwrap();
    dmb.replace_proc_code(0, &instructions).unwrap();
    assert!(dmb.lists[0xffff].is_empty());
    assert_eq!(dmb.procs[0].code_locals_args[0], 0x10000);
    assert!(dmb.header.uses_large_object_ids());
    let bytes = dmb.to_bytes().unwrap();
    let decoded = Dmb::from_bytes(&bytes).unwrap();
    assert_eq!(decoded.lists.len(), 0x10001);
    assert_eq!(decoded.proc_code_words(0), Some([0x50,7,0].as_slice()));
    assert_eq!(decoded.to_bytes().unwrap(), bytes);
}

#[test]
fn emitted_long_strings_keep_native_length_chunk_framing() {
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let baseline_bytes = include_bytes!("../fixtures/native_template_savefile_5161687.json");
    let baseline = OpenDreamProgram::from_slice(baseline_bytes).unwrap();
    let mut input = OpenDreamProgram::from_slice(baseline_bytes).unwrap();
    let text = "x".repeat(u16::MAX as usize + 9);
    input.strings.push(text.clone());
    let emitted = emit_with_baseline(&input, Some(&baseline), &template, Path::new(".")).unwrap();
    let id = *emitted.ids.strings.last().unwrap();
    assert_eq!(emitted.dmb.strings[id as usize].long_chunks, 1);
    let bytes = emitted.dmb.to_bytes().unwrap();
    let decoded = Dmb::from_bytes(&bytes).unwrap();
    assert_eq!(decoded.string(id), Some(text.as_bytes()));
    assert_eq!(decoded.to_bytes().unwrap(), bytes);
}
