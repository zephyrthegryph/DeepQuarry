use byond_dmb::dmb::Dmb;

#[test]
fn image_defaults_use_appearance_header_and_overrides() {
    let dmb = Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/image_defaults.native.bin"
    ))
    .unwrap();
    let image = dmb
        .classes
        .iter()
        .find(|class| dmb.string(class.path_string_id()) == Some(b"/image/compass_marker"))
        .unwrap();
    assert_eq!(image.maptext_geometry, [96, 64, 0, 0]);
    assert_eq!(dmb.string(image.maptext), Some(b"hello".as_slice()));
    assert_eq!(dmb.string(image.icon_state_string_id()), Some(b"marker".as_slice()));
    assert_eq!(f32::from_bits(image.layer_bits), 4.5);
    assert_eq!(image.appearance_flags(), 7);
    assert_eq!(image.initialized_variable_list_id(), u16::MAX as u32);
    assert_eq!(image.defining_variable_list_id(), u16::MAX as u32);

    let overrides = dmb.lists[image.overrides as usize]
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
            ("alpha", 42, 128.0),
            ("plane", 42, 5.0),
            ("pixel_x", 42, 3.0),
            ("pixel_y", 42, -2.0),
        ]
    );
}
