//! Coverage is licensed by pinned native forms, not by the absence of differences.
use super::*;

fn input_words(bytes: &[u8], name: &[u8], opcode: u32) -> Vec<u32> {
    let dmb = crate::dmb::Dmb::from_bytes(bytes).unwrap();
    let id = dmb
        .procs
        .iter()
        .position(|proc| dmb.string(proc.strings[0]) == Some(name))
        .unwrap();
    crate::bytecode::decode(dmb.proc_code_words(id).unwrap())
        .unwrap()
        .into_iter()
        .find(|item| item.opcode == opcode)
        .unwrap()
        .operands
}

#[test]
fn ordinary_prompt_and_generic_choice_metadata_matches_pinned_native_forms() {
    let native =
        include_bytes!("../fixtures/translation/input_uncovered/input_uncovered.native.bin");
    for (name, expected) in [
        (b"/proc/icon_prompt".as_slice(), [640, 0, 0]),
        (b"/proc/text_prompt".as_slice(), [132, 0, 0]),
        (b"/proc/message_prompt".as_slice(), [2176, 0, 0]),
        (b"/proc/anything_prompt".as_slice(), [4224, 0, 64]),
    ] {
        let actual = input_words(native, name, 0xc1);
        assert_eq!(actual, expected);
        assert!(contextual_fixed_word_is_scalar(0xc1, 1, &actual));
    }
    for (native, name, expected) in [
        (include_bytes!("../fixtures/translation/input_selection/input_selection.native.bin").as_slice(), b"/proc/contents_prompt".as_slice(), [2, 0, 64]),
        (include_bytes!("../fixtures/translation/input_selection/input_selection.native.bin").as_slice(), b"/proc/view_dynamic".as_slice(), [2, 125, 64]),
        (include_bytes!("../fixtures/translation/input_selection_centers/input_selection_centers.native.bin").as_slice(), b"/proc/shadow_center".as_slice(), [2, 5, 64]),
    ] {
        let actual = input_words(native, name, 0xc1);
        assert_eq!(actual, expected);
        assert!(contextual_fixed_word_is_scalar(0xc1, 1, &actual));
    }
}

#[test]
fn color_radius_absence_is_covered_only_for_proved_shapes() {
    for (native, expected) in [
        (
            include_bytes!("../fixtures/translation/input_uncovered/color_plain.native.bin")
                .as_slice(),
            [0, 0, 0],
        ),
        (
            include_bytes!("../fixtures/translation/input_uncovered/color_choices.native.bin")
                .as_slice(),
            [0, 0, 64],
        ),
    ] {
        let actual = input_words(native, b"/proc/probe", 0xc6);
        assert_eq!(actual, expected);
        assert!(contextual_fixed_word_is_scalar(0xc6, 1, &actual));
    }
    for (opcode, words) in [
        (0xc1, [132, 1, 0]),
        (0xc1, [4224, 1, 64]),
        (0xc1, [640, 0, 64]),
        (0xc1, [2, 6, 64]),
        (0xc6, [0, 1, 0]),
        (0xc6, [2, 0, 0]),
        (0xc6, [0, 0, 1]),
    ] {
        assert!(!contextual_fixed_word_is_scalar(opcode, 1, &words));
    }
}
