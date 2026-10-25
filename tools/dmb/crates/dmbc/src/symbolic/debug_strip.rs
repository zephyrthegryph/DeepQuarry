//! Removal of `DbgFile`/`DbgLine` from linked procedure words for builds without `DEBUG`.
//!
//! Lowering always emits the two source-position instructions, so one lowered record serves the game and the
//! test variant; a variant that does not define `DEBUG` drops them from its final words (`LatestImage::wire_image`). The result
//! is the word sequence the lowering would have produced had it never emitted them: every instruction keeps its
//! operands, and every absolute branch destination (jump, switch case, pick-probability target) moves to the
//! offset the same instruction has in the shortened code. A destination that named a removed instruction names
//! the next kept one, which is where control reaches after the instruction is skipped.
use byond_dmb::bytecode::{opcode, visit_instructions};
use std::sync::Arc;

fn is_debug(code: u32) -> bool {
    code == opcode::DBG_FILE || code == opcode::DBG_LINE
}

/// Whether `words` holds at least one debug instruction (and decodes). Allocation-free.
pub(super) fn has_debug_ops(words: &[u32]) -> bool {
    let mut found = false;
    let decoded = visit_instructions(words, |instruction| found |= is_debug(instruction.opcode), |_| {});
    found && decoded.is_ok()
}

/// Strip the debug instructions of `words` in place. Returns `Ok(removed_words)`; nothing is touched
/// (and 0 is returned) when there are none. An undecodable image is an error and is left unchanged.
pub(super) fn strip_debug_ops(words: &mut Vec<u32>) -> Result<usize, String> {
    // Removed ranges (start offset, length) in code order, and every branch destination word position.
    let mut removed: Vec<(usize, usize)> = Vec::new();
    let mut branches: Vec<usize> = Vec::new();
    visit_instructions(
        words,
        |instruction| {
            if is_debug(instruction.opcode) {
                removed.push((instruction.offset, 1 + instruction.operands.len()));
            }
        },
        |at| branches.push(at),
    )
    .map_err(|error| format!("debug strip: invalid bytecode: {error:?}"))?;
    if removed.is_empty() {
        return Ok(0);
    }
    // removed_before[i]: words removed by ranges 0..i, so an offset between range i-1 and range i shifts by
    // removed_before[i]. A range's own start is not shifted by itself (it names the next kept instruction).
    let mut removed_before = Vec::with_capacity(removed.len() + 1);
    let mut total = 0usize;
    removed_before.push(0);
    for &(_, length) in &removed {
        total += length;
        removed_before.push(total);
    }
    let shift = |offset: usize| -> usize {
        let ranges_before = removed.partition_point(|&(start, _)| start < offset);
        offset - removed_before[ranges_before]
    };
    // Compact the words, then rewrite the branch words at their new positions.
    let mut write = 0usize;
    let mut next = 0usize;
    for read in 0..words.len() {
        if next < removed.len() && read >= removed[next].0 + removed[next].1 {
            next += 1;
        }
        if next < removed.len() && read >= removed[next].0 {
            continue;
        }
        words[write] = words[read];
        write += 1;
    }
    words.truncate(write);
    for at in branches {
        let position = shift(at);
        let target = words[position] as usize;
        words[position] =
            u32::try_from(shift(target)).map_err(|_| "debug strip: offset overflow".to_string())?;
    }
    Ok(total)
}

/// Strip a shared image, copying it only when it holds debug instructions. Returns whether any were removed.
pub(super) fn strip_shared(words: &mut Arc<Vec<u32>>) -> Result<bool, String> {
    if !has_debug_ops(words) {
        return Ok(false);
    }
    let removed = strip_debug_ops(Arc::make_mut(words))?;
    Ok(removed != 0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use byond_dmb::bytecode::{decode, encode, Instruction};

    fn instruction(code: u32, operands: &[u32]) -> Instruction {
        Instruction {
            offset: 0,
            opcode: code,
            name: "",
            operands: operands.to_vec(),
        }
    }

    #[test]
    fn strips_debug_instructions_and_retargets_branches() {
        // 0 DbgFile, 2 DbgLine, 4 PushInt, 6 Jump -> 10, 8 DbgLine, 10 DbgLine, 12 PushInt
        let words = encode(&[
            instruction(opcode::DBG_FILE, &[7]),
            instruction(opcode::DBG_LINE, &[3]),
            instruction(opcode::PUSH_INT, &[5]),
            instruction(0xf, &[10]),
            instruction(opcode::DBG_LINE, &[4]),
            instruction(opcode::DBG_LINE, &[5]),
            instruction(opcode::PUSH_INT, &[9]),
        ]);
        assert!(has_debug_ops(&words));
        let mut stripped = words.clone();
        assert_eq!(strip_debug_ops(&mut stripped).unwrap(), 8);
        let decoded = decode(&stripped).unwrap();
        assert_eq!(
            decoded
                .iter()
                .map(|i| (i.opcode, i.operands.clone()))
                .collect::<Vec<_>>(),
            vec![
                (opcode::PUSH_INT, vec![5]),
                (0xf, vec![4]),
                (opcode::PUSH_INT, vec![9])
            ]
        );
        assert!(!has_debug_ops(&stripped));
    }

    #[test]
    fn image_without_debug_instructions_is_untouched() {
        let words = encode(&[instruction(opcode::PUSH_INT, &[1]), instruction(0xf, &[0])]);
        let mut same = words.clone();
        assert_eq!(strip_debug_ops(&mut same).unwrap(), 0);
        assert_eq!(same, words);
        let mut shared = Arc::new(words);
        let before = Arc::clone(&shared);
        assert!(!strip_shared(&mut shared).unwrap());
        assert!(Arc::ptr_eq(&shared, &before));
    }

    #[test]
    fn a_branch_to_the_end_follows_the_shortened_code() {
        let words = encode(&[instruction(0xf, &[4]), instruction(opcode::DBG_LINE, &[1])]);
        let mut stripped = words;
        strip_debug_ops(&mut stripped).unwrap();
        assert_eq!(stripped, vec![0xf, 2]);
    }

    #[test]
    fn invalid_bytecode_is_an_error_and_unchanged() {
        let mut words = vec![0xffff_fff0];
        assert!(strip_debug_ops(&mut words).is_err());
        assert_eq!(words, vec![0xffff_fff0]);
    }
}
