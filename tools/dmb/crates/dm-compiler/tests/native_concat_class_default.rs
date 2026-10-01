use byond_dmb::dmb::Dmb;

#[test]
fn concatenated_improper_name_is_one_class_header_string() {
    let dmb = Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/concat_class_default.native.bin"
    ))
    .unwrap();
    let class = dmb
        .classes
        .iter()
        .find(|class| {
            dmb.string(class.path_string_id()) == Some(b"/obj/item/gun/projectile/cyborgtoy")
        })
        .unwrap();
    assert_eq!(
        dmb.string(class.name_string_id()),
        Some(b"\xff\x16Donk-Soft Cyborg Blaster".as_slice())
    );
    assert_eq!(class.overrides, u16::MAX as u32);
}
