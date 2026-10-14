//! Coverage is licensed by pinned native forms, not by the absence of differences.
use super::*;

fn input_words(bytes: &[u8], name: &[u8], opcode: u32) -> Vec<u32> {
    let dmb = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
    let id = dmb
        .procs
        .iter()
        .position(|proc| dmb.string(proc.strings[0]) == Some(name))
        .unwrap();
    byond_dmb::bytecode::decode(dmb.proc_code_words(id).unwrap())
        .unwrap()
        .into_iter()
        .find(|item| item.opcode == opcode)
        .unwrap()
        .operands
}

#[test]
fn numeric_and_file_prompt_absence_matches_captured_native_forms() {
    let native =
        include_bytes!("../../../fixtures/translation/input_numeric_file/input_numeric_file.native.bin");
    for (name, expected) in [
        (b"/proc/number_prompt".as_slice(), [136, 0, 0]),
        (b"/proc/file_prompt".as_slice(), [144, 0, 0]),
    ] {
        let actual = input_words(native, name, 0xc1);
        assert_eq!(actual, expected);
        assert!(contextual_fixed_word_is_scalar(0xc1, 1, &actual));
        let mut unknown_radius = actual;
        unknown_radius[1] = 1;
        assert!(!contextual_fixed_word_is_scalar(0xc1, 1, &unknown_radius));
    }
}

#[test]
fn ordinary_prompt_and_generic_choice_metadata_matches_pinned_native_forms() {
    let native =
        include_bytes!("../../../fixtures/translation/input_uncovered/input_uncovered.native.bin");
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
        (include_bytes!("../../../fixtures/translation/input_selection/input_selection.native.bin").as_slice(), b"/proc/contents_prompt".as_slice(), [2, 0, 64]),
        (include_bytes!("../../../fixtures/translation/input_selection/input_selection.native.bin").as_slice(), b"/proc/view_dynamic".as_slice(), [2, 125, 64]),
        (include_bytes!("../../../fixtures/translation/input_selection_centers/input_selection_centers.native.bin").as_slice(), b"/proc/shadow_center".as_slice(), [2, 5, 64]),
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
            include_bytes!("../../../fixtures/translation/input_uncovered/color_plain.native.bin")
                .as_slice(),
            [0, 0, 0],
        ),
        (
            include_bytes!("../../../fixtures/translation/input_uncovered/color_choices.native.bin")
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

#[test]
fn omitted_file_and_anything_shapes_match_authenticated_native_capture() {
    let native =
        include_bytes!("../../../fixtures/translation/input_remaining_shapes/input_shapes.native.bin");
    for (name, expected) in [
        (b"/proc/omitted_prompt".as_slice(), [0, 0, 0]),
        (b"/proc/omitted_choices".as_slice(), [0, 0, 64]),
        (b"/proc/file_prompt".as_slice(), [16, 0, 0]),
        (b"/proc/file_choices".as_slice(), [16, 0, 64]),
        (b"/proc/anything_prompt".as_slice(), [4096, 0, 0]),
        (b"/proc/anything_choices".as_slice(), [4096, 0, 64]),
    ] {
        let actual = input_words(native, name, 0xc1);
        assert_eq!(actual, expected);
        assert!(contextual_fixed_word_is_scalar(0xc1, 1, &actual));
        let mut unproved = actual.clone();
        unproved[1] = 1;
        assert!(!contextual_fixed_word_is_scalar(0xc1, 1, &unproved));
        unproved[1] = 0;
        unproved[2] = 32;
        assert!(!contextual_fixed_word_is_scalar(0xc1, 1, &unproved));
    }
    assert!(!contextual_fixed_word_is_scalar(0xc1, 1, &[8192, 0, 0]));
}

#[test]
fn mob_choices_absent_radius_matches_preserved_byond_matrix() {
    // receipt.json pins DM 516.1687 and output SHA
    // 1976beb24c0bb0c78753d5056ab9703736bbadcca6a5105922335256ddabce48.
    // case_15 is `input("prompt") as mob in choices`; this same shape occurs
    // in the preserved whole-program remoteobserve procedure.
    let native = include_bytes!("../../../fixtures/native/input_warning_masks/matrix.native.bin");
    let actual = input_words(native, b"/proc/case_15", 0xc1);
    assert_eq!(actual, [1, 0, 64]);
    assert!(contextual_fixed_word_is_scalar(0xc1, 1, &actual));
    for unproved in [[1, 1, 64], [1, 0, 32], [1, 0, 0]] {
        assert!(!contextual_fixed_word_is_scalar(0xc1, 1, &unproved));
    }
}
