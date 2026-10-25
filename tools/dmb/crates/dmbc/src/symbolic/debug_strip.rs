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

/// Stripped copies of shared images, by the address of the image they were made from: the stripped words are a pure
/// function of the image, so every session of a daemon that wires the same shared image gets the one stripped copy instead
/// of making its own. Weak on both sides: the pool keeps nothing alive, and an entry whose image or copy is gone is dead.
pub(super) struct StrippedPool {
    shards: Box<[std::sync::Mutex<StrippedShard>]>,
}
struct Stripped {
    image: std::sync::Weak<Vec<u32>>,
    stripped: std::sync::Weak<Vec<u32>>,
}
struct StrippedShard {
    copies: std::collections::HashMap<usize, Stripped>,
    prune_at: usize,
}
impl StrippedPool {
    pub(super) fn new() -> Self {
        const SHARDS: usize = 32;
        Self {
            shards: (0..SHARDS)
                .map(|_| {
                    std::sync::Mutex::new(StrippedShard {
                        copies: Default::default(),
                        prune_at: 4096,
                    })
                })
                .collect(),
        }
    }
}
fn daemon_pool() -> Option<&'static StrippedPool> {
    crate::shared_store::active()?;
    static POOL: std::sync::OnceLock<StrippedPool> = std::sync::OnceLock::new();
    Some(POOL.get_or_init(StrippedPool::new))
}

/// Strip a shared image, copying it only when it holds debug instructions. Returns whether any were removed.
pub(super) fn strip_shared(words: &mut Arc<Vec<u32>>) -> Result<bool, String> {
    strip_shared_in(daemon_pool(), words)
}
pub(super) fn strip_shared_in(pool: Option<&StrippedPool>, words: &mut Arc<Vec<u32>>) -> Result<bool, String> {
    if !has_debug_ops(words) {
        return Ok(false);
    }
    let Some(pool) = pool.filter(|_| Arc::strong_count(words) > 1) else {
        // No daemon pool, or nothing else holds this image (no other session can ask for the same copy): strip in place.
        let removed = strip_debug_ops(Arc::make_mut(words))?;
        *words = super::image_pool::intern_words(Arc::clone(words));
        return Ok(removed != 0);
    };
    let address = Arc::as_ptr(words) as usize;
    let shard = &pool.shards[(address >> 4) % pool.shards.len()];
    {
        let held = shard.lock().unwrap_or_else(|error| error.into_inner());
        if let Some(entry) = held.copies.get(&address) {
            if let (Some(image), Some(stripped)) = (entry.image.upgrade(), entry.stripped.upgrade()) {
                // The address names the image only while that image is alive; the held image says it is this one.
                if Arc::ptr_eq(&image, words) {
                    *words = stripped;
                    return Ok(true);
                }
            }
        }
    }
    let image = Arc::downgrade(words);
    let removed = strip_debug_ops(Arc::make_mut(words))?;
    if removed != 0 {
        *words = super::image_pool::intern_words(Arc::clone(words));
        let mut held = shard.lock().unwrap_or_else(|error| error.into_inner());
        held.copies.insert(
            address,
            Stripped {
                image,
                stripped: Arc::downgrade(words),
            },
        );
        if held.copies.len() >= held.prune_at {
            held.copies
                .retain(|_, entry| entry.image.strong_count() > 0 && entry.stripped.strong_count() > 0);
            held.prune_at = (held.copies.len() * 2).max(4096);
        }
    }
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
    fn one_shared_image_has_one_stripped_copy_for_every_holder() {
        let words = encode(&[
            instruction(opcode::DBG_FILE, &[7]),
            instruction(opcode::DBG_LINE, &[3]),
            instruction(opcode::PUSH_INT, &[5]),
        ]);
        let image = Arc::new(words.clone());
        let pool = StrippedPool::new();
        let (mut first, mut second) = (Arc::clone(&image), Arc::clone(&image));
        assert!(strip_shared_in(Some(&pool), &mut first).unwrap());
        assert!(strip_shared_in(Some(&pool), &mut second).unwrap());
        assert!(Arc::ptr_eq(&first, &second), "a second holder reuses the stripped copy");
        assert!(!Arc::ptr_eq(&first, &image));
        assert_eq!(*image, words, "the shared image itself is untouched");
        assert!(!has_debug_ops(&first));
        // An image nobody else holds is stripped in place.
        let mut alone = Arc::new(words);
        assert!(strip_shared_in(Some(&pool), &mut alone).unwrap());
        assert!(!has_debug_ops(&alone));
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
