//! Borrowed validation traverses the authoritative decoder grammar once.
use super::*;

#[derive(Clone, Copy, Debug)]
pub struct InstructionView<'a> {
    pub offset: usize,
    pub opcode: u32,
    pub name: &'static str,
    pub operands: &'a [u32],
}

/// Callbacks observe validated instructions and exact branch-word positions.
/// On failure, earlier callbacks may have run; callers must discard the partial
/// observation. Operand validation and error offsets match the owned decoder.
pub fn visit_instructions<'a>(
    words: &'a [u32],
    mut instruction: impl FnMut(InstructionView<'a>),
    mut branch: impl FnMut(usize),
) -> Result<(), DecodeError> {
    let mut reader = Decoder { words, at: 0 };
    while reader.at < words.len() {
        let offset = reader.at;
        let opcode = reader.word()?;
        let descriptor = descriptors().get(&opcode).ok_or_else(|| DecodeError {
            offset,
            reason: format!("unknown opcode {opcode:#x}"),
        })?;
        for (index, kind) in descriptor.operands.chars().enumerate() {
            if index == 0 && kind == 'u' && is_branch_opcode(opcode) {
                branch(reader.at);
            }
            reader.walk_operand(kind, false, &mut branch)?;
        }
        instruction(InstructionView {
            offset,
            opcode,
            name: descriptor.name,
            operands: &words[offset + 1..reader.at],
        });
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn collected_reference(words: &[u32]) -> Result<Vec<Instruction>, DecodeError> {
        let mut reader = Decoder { words, at: 0 };
        let mut result = Vec::new();
        while reader.at < words.len() {
            let offset = reader.at;
            let opcode = reader.word()?;
            let descriptor = descriptors().get(&opcode).ok_or_else(|| DecodeError {
                offset,
                reason: format!("unknown opcode {opcode:#x}"),
            })?;
            for kind in descriptor.operands.chars() {
                reader.operand(kind)?;
            }
            result.push(Instruction {
                offset,
                opcode,
                name: descriptor.name,
                operands: words[offset + 1..reader.at].to_vec(),
            });
        }
        Ok(result)
    }
    #[test]
    fn borrowed_traversal_preserves_owned_grammar_branches_and_errors() {
        let fixtures = [
            (vec![0x78, 2, 6, 5, 5, 42, 0, 5, 5, 5], vec![4, 8, 9]),
            (vec![0x79, 2, 5, 5, 5, 5, 5], vec![3, 5, 6]),
            (
                vec![0x7a, 1, 6, 5, 42, 0, 5, 5, 1, 6, 5, 5, 5],
                vec![7, 11, 12],
            ),
            (vec![0xb1, 2, 5, 5], vec![2, 3]),
            (vec![0xfd, 5, 0xffd9, 0], vec![1]),
            (vec![0x50, 5], vec![]),
            (vec![0x33, 0xffdc, 0xffce, 0xffda, 0, 0x12], vec![]),
            (vec![0x60, 0xabcd_002a, 0x1234, 0x5678, 0x12], vec![]),
        ];
        let mut successful = 0;
        for (words, expected_branches) in fixtures {
            let instructions = collected_reference(&words).expect("valid grammar fixture");
            assert_eq!(decode(&words).unwrap(), instructions);
            let mut branches = Vec::new();
            let mut offsets = Vec::new();
            visit_instructions(&words, |i| offsets.push(i.offset), |at| branches.push(at)).unwrap();
            assert_eq!(branches, expected_branches);
            assert_eq!(
                offsets,
                instructions.iter().map(|i| i.offset).collect::<Vec<_>>()
            );
            assert_eq!(
                branches,
                instructions
                    .iter()
                    .flat_map(|i| i.branch_target_word_offsets().unwrap())
                    .collect::<Vec<_>>()
            );
            assert_eq!(encode(&instructions), words);
            successful += 1;
            for end in 0..words.len() {
                assert_eq!(decode(&words[..end]), collected_reference(&words[..end]));
            }
        }
        assert_eq!(successful, 8); // Switch, Pick, Range, PickProb and compound values/variables all ran.
        let mut excessive_nesting = vec![0x33];
        excessive_nesting.extend([0xffe7; 33]);
        excessive_nesting.push(0xffce);
        for words in [
            vec![0xffff_ffff],
            vec![0x33, 0xffd1],
            vec![0x60, 42, 0],
            excessive_nesting,
        ] {
            let expected = collected_reference(&words).expect_err("invalid grammar fixture");
            assert_eq!(decode(&words).unwrap_err(), expected);
            assert_eq!(
                visit_instructions(&words, |_| {}, |_| {}).unwrap_err(),
                expected
            );
        }
    }
}
