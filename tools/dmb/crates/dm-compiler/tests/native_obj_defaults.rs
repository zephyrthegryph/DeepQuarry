use byond_dmb::dmb::Dmb;

#[test]
fn obj_infra_and_pointer_defaults_are_numeric_overrides() {
    let dmb = Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/obj_defaults.native.bin"
    ))
    .unwrap();
    let obj = dmb
        .classes
        .iter()
        .find(|class| dmb.string(class.path_string_id()) == Some(b"/obj/probe"))
        .unwrap();
    assert_eq!(obj.flags, 4);
    let overrides = dmb.lists[obj.overrides as usize]
        .chunks_exact(4)
        .map(|words| {
            (
                std::str::from_utf8(dmb.string(words[0]).unwrap()).unwrap(),
                words[1],
                f32::from_bits((words[2] << 16) | words[3]),
            )
        })
        .collect::<Vec<_>>();
    assert_eq!(
        overrides,
        [
            ("infra_luminosity", 42, 6.0),
            ("mouse_drag_pointer", 42, 1.0),
            ("mouse_over_pointer", 42, 7.0),
        ]
    );
}
