//! Semantic roles of fixed FMT `u` operands. FMT establishes width only.
//! Roles below come from the paired native builtin catalog, explicit emitter
//! operand contracts, and decoder branch metadata; unknowns stay uncovered.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum FixedWordRole {
    Scalar,
    StringId,
    ProcedureId,
    BranchTarget,
    Opaque,
}

/// Index is the typed-operand index, including preceding variable/value operands.
pub(super) fn fixed_word_role(opcode: u32, index: usize) -> FixedWordRole {
    use FixedWordRole::*;
    match (opcode, index) {
        // Existing compare_procedures normalization certifies these table roles.
        (0x02 | 0x04 | 0x84, 0) => StringId,
        (0x30, 1) | (0xcd, 0) => ProcedureId,
        // Authoritative decoder explicitly distinguishes target words from counts.
        (_, 0) if crate::bytecode::is_branch_opcode(opcode) => BranchTarget,
        // simple/expression.rs and calls_intrinsics.rs formatting: string reference followed by substitution count.
        (0x02 | 0x04, 1) => Scalar,
        // IterLoad(mode, type/filter mask). The second word's recognized filter
        // bits are checked contextually below.
        (0x52, 0) => Scalar,
        // inference.rs input first word is the accepted type-mask; third is
        // selection-list flags. The middle radius needs a proved selector shape.
        (0xc1 | 0xc6, 0 | 2) => Scalar,
        // DbgLine is a source-line number; retained for shape completeness.
        (0x85, 0) => Scalar,
        // Upstream dmasm instructions.rs names Startup's fixed word arg_count.
        (0x5e, 0) => Scalar,
        // dmasm instructions.rs 6cec0e9a60cb3b3a056daca8c791d36795185154:
        // IconNew, IconGetPixel and Database use argument counts;
        // TurnOrFlipIcon uses a numeric filter mode followed by Variable.
        // Count/filter values remain compared exactly, never normalized away.
        (0xde | 0xdf | 0x115 | 0x12b, 0) => Scalar,
        // Direct calls carry argument counts, never argument/proc-table IDs.
        (0x29 | 0x2a, 1) => Scalar,
        (0x30, 0) => Scalar,
        (
            0x01 | 0x1a | 0x2b | 0x2d | 0x2f | 0xb5 | 0xc8 | 0xd4 | 0xfb | 0x116 | 0x15d | 0x165
            | 0x167 | 0x17a | 0x17c | 0x180 | 0x13a,
            0,
        ) => Scalar,
        // builtin_catalog.rs native fixture has OpcodeCountPolicy::EmittedArgs:
        // addtext, sorts, min/max, typesof, matrix, bounds, noise_hash, pixloc.
        (0x6c | 0x72 | 0x73 | 0xa5 | 0xa6 | 0xa7 | 0x12a | 0x11b | 0x11c | 0x172 | 0x17f, 0) => {
            Scalar
        }
        // Paired native range fixture records category sentinel0xae, not a table ID.
        (0x59, 0) => Scalar,
        // PushInt is normally normalized into typed numeric PushVal earlier.
        (0x50, 0) => Scalar,
        _ => Opaque,
    }
}
pub(super) fn fixed_word_is_scalar(opcode: u32, index: usize) -> bool {
    fixed_word_role(opcode, index) == FixedWordRole::Scalar
}

/// Known selector/filter values license contextual scalar roles. Unknown filter
/// bits cannot silently gain coverage merely because the operand is fixed width.
pub(super) fn contextual_fixed_word_is_scalar(
    opcode: u32,
    index: usize,
    raw_words: &[u32],
) -> bool {
    fixed_word_is_scalar(opcode, index)
        // Pinned dmasm instructions.rs declares the second IterLoad operand
        // TypeFilter independently of mode; list_operands.rs rejects unknown
        // bits. This includes native view/range modes 13 and 15 as well.
        || (opcode == 0x52
            && index == 1
            && raw_words.get(1).is_some_and(|mask| mask & !0x3dfff == 0))
        // simple/expression.rs and paired OD/native fixtures distinguish list
        // membership mode 5 from numeric range mode 11. Neither is a table ID.
        // Unobserved selector values retain explicit uncovered status.
        || (opcode == 0xa9 && index == 0 && matches!(raw_words.first(), Some(5 | 11)))
        // calls_intrinsics.rs and od_lower/call.rs both encode orange's category
        // sentinel 0xae; unknown ORange selectors remain uncovered.
        || (opcode == 0xad && index == 0 && raw_words.first() == Some(&0xae))
        // Pinned native input_selection fixture: view/oview encode their literal
        // radius here; world/usr encode the numeric unrestricted sentinel127.
        // Unproved filter/radius/list combinations remain unknown.
        || (opcode == 0xc1 && index == 1 && raw_words.len() == 3
            && match raw_words[2] {
                1 | 2 => raw_words[1] <= 127,
                8 | 16 => raw_words[1] == 127,
                // Native controls establish absent-radius metadata for these
                // ordinary prompts; generic choices preserve proved radius.
                0 => raw_words[1] == 0 && matches!(raw_words[0], 640 | 132 | 2176 | 136 | 144 | 0 | 16 | 4096),
                64 => (raw_words[0] == 2 && matches!(raw_words[1], 0 | 5 | 125))
                    || (matches!(raw_words[0], 1 | 4224 | 0 | 16 | 4096) && raw_words[1] == 0),
                _ => false,
            })
        // Compile-only color probes: no radius, optional evaluated choices.
        || (opcode == 0xc6 && index == 1 && raw_words.len() == 3
            && raw_words[0] == 0 && raw_words[1] == 0 && matches!(raw_words[2], 0 | 64))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn positional_references_and_unknown_shapes_never_become_scalar() {
        assert_eq!(fixed_word_role(0x30, 1), FixedWordRole::ProcedureId);
        assert_eq!(fixed_word_role(0x02, 0), FixedWordRole::StringId);
        assert_eq!(fixed_word_role(0xfd, 0), FixedWordRole::BranchTarget);
        assert!(!fixed_word_is_scalar(0x30, 1));
        assert!(!fixed_word_is_scalar(0xcd, 0));
        assert!(fixed_word_is_scalar(0x5e, 0)); // Authoritative argument count.
        assert!(!fixed_word_is_scalar(0x5e, 1));
        assert!(!fixed_word_is_scalar(0xc1, 1)); // Selector-free Input middle remains unproven.
        assert!(!fixed_word_is_scalar(0x1a, 1)); // Invalid extra fixed operand.
        assert!(!fixed_word_is_scalar(0xdead, 0));
        assert!(fixed_word_is_scalar(0x29, 1));
        assert!(fixed_word_is_scalar(0x02, 1));
        assert!(contextual_fixed_word_is_scalar(0x52, 1, &[5, 4096]));
        assert!(contextual_fixed_word_is_scalar(0x52, 1, &[99, 4096]));
        assert!(contextual_fixed_word_is_scalar(0x52, 1, &[13, 291]));
        assert!(contextual_fixed_word_is_scalar(0x52, 1, &[15, 4096]));
        assert!(!contextual_fixed_word_is_scalar(0x52, 1, &[5, 0x2000]));
        assert!(!contextual_fixed_word_is_scalar(0x52, 1, &[5, 0x8000_0000]));
        assert!(!contextual_fixed_word_is_scalar(0x52, 1, &[]));
        assert!(contextual_fixed_word_is_scalar(0xa9, 0, &[5]));
        assert!(contextual_fixed_word_is_scalar(0xa9, 0, &[11]));
        assert!(!contextual_fixed_word_is_scalar(0xa9, 0, &[100]));
        assert!(!contextual_fixed_word_is_scalar(0xa9, 1, &[5]));
        assert!(contextual_fixed_word_is_scalar(0xad, 0, &[0xae]));
        assert!(!contextual_fixed_word_is_scalar(0xad, 0, &[0x100]));
    }
}

#[cfg(test)]
mod input_selection_tests {
    use super::*;
    #[test]
    fn input_radius_coverage_requires_proved_selection_shape() {
        for words in [
            [2, 127, 16],
            [2, 127, 8],
            [2, 5, 1],
            [2, 7, 2],
            [2, 0, 1],
            [2, 125, 1],
        ] {
            assert!(contextual_fixed_word_is_scalar(0xc1, 1, &words));
        }
        for words in [
            [2, 0, 0],
            [2, 7, 64],
            [2, 126, 64],
            [2, 128, 1],
            [2, 0, 16],
            [2, 127, 32],
        ] {
            assert!(!contextual_fixed_word_is_scalar(0xc1, 1, &words));
        }
        assert!(!contextual_fixed_word_is_scalar(0xc1, 1, &[2, 5]));
        assert!(!contextual_fixed_word_is_scalar(0xc6, 1, &[2, 5, 1]));
        assert!(!contextual_fixed_word_is_scalar(0xc1, 3, &[2, 5, 1]));
    }
}

#[cfg(test)]
#[path = "compare_input_coverage_tests.rs"]
mod native_input_coverage_tests;

#[cfg(test)]
#[path = "compare_engine_fixed_word_tests.rs"]
mod native_engine_coverage_tests;
