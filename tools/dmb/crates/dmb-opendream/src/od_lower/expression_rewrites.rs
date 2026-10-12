use super::*;

pub(super) fn replace_words(
    out: &mut Vec<u32>,
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut [Fixup],
    start: usize,
    old_len: usize,
    replacement: &[u32],
) {
    let delta = replacement.len() as isize - old_len as isize;
    out.splice(start..start + old_len, replacement.iter().copied());
    for value in offsets.values_mut() {
        if (*value as usize) >= start + old_len {
            *value = (*value as isize + delta) as u32;
        }
    }
    for fixup in fixups {
        if fixup.at >= start + old_len {
            fixup.at = (fixup.at as isize + delta) as usize;
        }
    }
}

// Receiver cache analysis and rewrite are isolated from opcode emission.

/// Locate an indexed-assignment RHS containing verified expression diamonds.
/// Collapse each diamond only for stack-span analysis; emitted instructions and
/// their branch fixups remain intact until the caller relocates the whole RHS.
pub(super) fn closed_spans(
    spans: &[(usize, usize)],
    offsets: &HashMap<u32, u32>,
    fixups: &[Fixup],
) -> bool {
    let Some(&(base, _)) = spans.first() else {
        return false;
    };
    fixups.iter().all(|fixup| {
        if fixup.at < base {
            return offsets
                .get(&fixup.target)
                .is_none_or(|target| *target as usize <= base);
        }
        spans.iter().any(|(begin, end)| {
            fixup.at >= *begin
                && fixup.at < *end
                && offsets.get(&fixup.target).is_some_and(|target| {
                    (*target as usize) >= *begin && (*target as usize) <= *end
                })
        })
    })
}
pub(super) fn remap_closed_spans(
    original: &HashMap<u32, u32>,
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut [Fixup],
    moved: &[((usize, usize), usize)],
) {
    for fixup in fixups.iter_mut() {
        if let Some(&((begin, end), destination)) = moved
            .iter()
            .find(|((begin, end), _)| fixup.at >= *begin && fixup.at < *end)
        {
            let target = original[&fixup.target] as usize;
            debug_assert!((begin..=end).contains(&target));
            let mut synthetic = 0x8000_0000;
            while offsets.contains_key(&synthetic) {
                synthetic += 1;
            }
            fixup.target = synthetic;
            offsets.insert(synthetic, (destination + target - begin) as u32);
            fixup.at = destination + fixup.at - begin;
        }
    }
    for (&byte, &word) in original {
        if let Some(&((begin, _), destination)) = moved
            .iter()
            .find(|((begin, end), _)| word as usize >= *begin && (word as usize) < *end)
        {
            offsets.insert(byte, (destination + word as usize - begin) as u32);
        }
    }
}

pub(super) fn moved_offset_snapshot(
    offsets: &HashMap<u32, u32>,
    fixups: &[Fixup],
    moved: &[((usize, usize), usize)],
) -> HashMap<u32, u32> {
    let in_moved = |position: usize| {
        moved
            .iter()
            .any(|((begin, end), _)| (*begin..*end).contains(&position))
    };
    let mut snapshot: HashMap<_, _> = offsets
        .iter()
        .filter(|(_, &position)| in_moved(position as usize))
        .map(|(&source, &position)| (source, position))
        .collect();
    for fixup in fixups {
        if in_moved(fixup.at) {
            if let Some(&target) = offsets.get(&fixup.target) {
                snapshot.insert(fixup.target, target);
            }
        }
    }
    snapshot
}

/// Replace a closed expression region and relocate all source positions and
/// branch fixups that lived inside moved subexpressions. Callers verify
/// `closed_spans` first, so no external branch can enter a moved interior.
pub(super) fn replace_closed_spans(
    out: &mut Vec<u32>,
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut [Fixup],
    start: usize,
    old_len: usize,
    replacement: &[u32],
    moved: &[((usize, usize), usize)],
) {
    let original_offsets = moved_offset_snapshot(offsets, fixups, moved);
    replace_words(out, offsets, fixups, start, old_len, replacement);
    remap_closed_spans(&original_offsets, offsets, fixups, moved);
}

/// Insert receiver code between closed expressions. Unlike `replace_words`,
/// source positions outside the moved expression spans keep their old values;
/// the caller is constructing a new suffix and will register its joins later.
pub(super) fn insert_between_closed_spans(
    out: &mut Vec<u32>,
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut [Fixup],
    at: usize,
    inserted: &[u32],
    moved: &[((usize, usize), usize)],
) {
    let original_offsets = moved_offset_snapshot(offsets, fixups, moved);
    out.splice(at..at, inserted.iter().copied());
    remap_closed_spans(&original_offsets, offsets, fixups, moved);
}
pub(super) fn guarded_indexed_spans(
    words: &[u32],
    code: &[u8],
    offsets: &HashMap<u32, u32>,
    fixups: &[Fixup],
    assignment: usize,
) -> Option<(usize, usize)> {
    guarded_assignment_spans(words, code, offsets, fixups, assignment, 2)
}

pub(super) fn guarded_assignment_spans(
    words: &[u32],
    code: &[u8],
    offsets: &HashMap<u32, u32>,
    fixups: &[Fixup],
    assignment: usize,
    destination_count: usize,
) -> Option<(usize, usize)> {
    let mut compressed = words.to_vec();
    let mut origins: Vec<usize> = (0..words.len()).collect();
    let complete_arguments = |span: &[u32], count| {
        constructor_argument_start(span, count).is_some_and(|at| {
            byond_dmb::bytecode::decode(&span[..at]).is_ok_and(|items| {
                items
                    .iter()
                    .all(|item| matches!(item.opcode, 0x84 | 0x85 | 0x142 | 0x143))
            })
        })
    };
    let mut diamonds = Vec::new();
    for jump in fixups {
        if code.get(jump.source) != Some(&0x0e) || jump.target > assignment as u32 {
            continue;
        }
        let join = *offsets.get(&jump.target)? as usize;
        if join > words.len() || jump.at + 1 > join {
            continue;
        }
        if let Some(branch) = fixups.iter().rev().find(|branch| {
            branch.at < jump.at
                && matches!(code.get(branch.source), Some(0x0c | 0x8b))
                && offsets.get(&branch.target).copied() == Some((jump.at + 1) as u32)
        }) {
            diamonds.push((*branch, *jump, join));
        }
    }
    diamonds.sort_by_key(|(branch, _, join)| join.saturating_sub(branch.at));
    let mut collapsed = false;
    loop {
        let previous_len = compressed.len();
        // A lowered multiargument pick is one value whose candidate blocks are
        // mutually exclusive. Collapse only our registered, closed pick tables.
        let mut picks: Vec<_> = fixups
            .iter()
            .filter_map(|jump| {
                let begin = *offsets.get(&(jump.source as u32))? as usize;
                let end = *offsets.get(&jump.target)? as usize;
                if !matches!(code.get(jump.source), Some(0x54 | 0x55)) {
                    return None;
                }
                let first_slot = fixups
                    .iter()
                    .filter(|f| f.source == jump.source)
                    .map(|f| f.at)
                    .min()?;
                let table = if first_slot >= 3 && words.get(first_slot - 3) == Some(&0x79) {
                    first_slot - 3
                } else if first_slot >= 2 && words.get(first_slot - 2) == Some(&0xb1) {
                    first_slot - 2
                } else {
                    return None;
                };
                // A constructor/output receiver may have been inserted at the
                // source expression entry. It remains outside the pick value.
                let begin = if words[table] == 0x79 { table } else { begin };
                let header_end = table
                    + if words[table] == 0x79 {
                        2 * words[table + 1] as usize + 3
                    } else {
                        words[table + 1] as usize + 2
                    };
                (begin <= table
                    && jump.at >= header_end
                    && words.get(jump.at - 1) == Some(&0x0f)
                    && end <= words.len())
                .then_some((begin, end, jump.source, table, header_end))
            })
            .collect();
        picks.sort_unstable_by_key(|(begin, _, _, _, _)| std::cmp::Reverse(*begin));
        picks.dedup();
        for (mut begin, end, source, table, header_end) in picks {
            let index = |original: usize| {
                if original == words.len() {
                    Some(origins.len())
                } else {
                    origins.iter().position(|offset| *offset == original)
                }
            };
            let (Some(mut first), Some(last)) = (index(begin), index(end)) else {
                continue;
            };
            let Some(table_index) = index(table) else {
                continue;
            };
            if !matches!(compressed.get(table_index), Some(0x79 | 0xb1)) {
                continue;
            }
            let mut candidates: Vec<_> = fixups
                .iter()
                .filter_map(|branch| {
                    (branch.source == source && branch.at > table && branch.at < header_end)
                        .then(|| offsets.get(&branch.target).copied().map(|at| at as usize))
                        .flatten()
                })
                .collect();
            candidates.sort_unstable();
            candidates.dedup();
            let count = words[table + 1] as usize + usize::from(words[table] == 0x79);
            if candidates.len() != count {
                continue;
            }
            if words[table] == 0xb1 {
                let Some(probability_start) =
                    constructor_argument_start(&compressed[..table_index], count)
                else {
                    continue;
                };
                if !complete_arguments(&compressed[probability_start..table_index], count) {
                    continue;
                }
                first = probability_start;
                begin = origins[first];
            }
            let valid = candidates.iter().enumerate().all(|(i, candidate)| {
                let candidate_end = if i + 1 == candidates.len() {
                    end
                } else {
                    candidates[i + 1].saturating_sub(2)
                };
                let (Some(lo), Some(hi)) = (index(*candidate), index(candidate_end)) else {
                    return false;
                };
                lo <= hi && complete_arguments(&compressed[lo..hi], 1)
            });
            if !valid
                || fixups.iter().any(|branch| {
                    let inside = branch.at >= begin && branch.at < end;
                    let target = offsets.get(&branch.target).copied().map(|at| at as usize);
                    inside && target.is_none_or(|at| at < begin || at > end)
                        || !inside && target.is_some_and(|at| at > begin && at < end)
                })
            {
                continue;
            }
            compressed.splice(first..last, [0x50, 0]);
            origins.splice(first..last, [begin, begin]);
            collapsed = true;
        }
        for (branch, jump, join) in diamonds.iter().copied() {
            let index = |original: usize| {
                if original == words.len() {
                    Some(origins.len())
                } else {
                    origins.iter().position(|offset| *offset == original)
                }
            };
            let Some(true_start) = index(branch.at + 1) else {
                continue;
            };
            let Some(true_end) = index(jump.at - 1) else {
                continue;
            };
            let Some(false_start) = index(jump.at + 1) else {
                continue;
            };
            let Some(end) = index(join) else { continue };
            if !complete_arguments(&compressed[true_start..true_end], 1)
                || !complete_arguments(&compressed[false_start..end], 1)
            {
                continue;
            }
            let source_at = *offsets.get(&(branch.source as u32))? as usize;
            let Some(source_index) = index(source_at) else {
                continue;
            };
            let begin = if code.get(branch.source) == Some(&0x8b) {
                source_index
            } else {
                let Some(begin) = constructor_argument_start(&compressed[..source_index], 1) else {
                    continue;
                };
                begin
            };
            let original_begin = origins[begin];
            // A structured expression may contain nested diamonds, but cannot jump
            // out of its own span or receive a branch from an unrelated statement.
            if fixups.iter().any(|fixup| {
                let source_inside = fixup.at >= original_begin && fixup.at < join;
                let target = offsets.get(&fixup.target).copied().map(|at| at as usize);
                source_inside && target.is_none_or(|at| at < original_begin || at > join)
                    || !source_inside && target.is_some_and(|at| at > original_begin && at < join)
            }) {
                continue;
            }
            compressed.splice(begin..end, [0x50, 0]);
            origins.splice(begin..end, [original_begin, original_begin]);
            collapsed = true;
        }
        // A safe field read produces null on the taken edge and one field value
        // otherwise. Keep its evaluated owner inside the expression span.
        for branch in fixups.iter().filter(|branch| {
            branch.target <= assignment as u32
                && branch.at > 0
                && words.get(branch.at - 1) == Some(&0x13d)
                && code.get(branch.source) == Some(&0x65)
        }) {
            let join = *offsets.get(&branch.target)? as usize;
            let locate = |original| {
                if original == words.len() {
                    Some(origins.len())
                } else {
                    origins.iter().position(|offset| *offset == original)
                }
            };
            let Some(branch_at) = locate(branch.at - 1) else {
                continue;
            };
            let Some(body_at) = locate(branch.at + 1) else {
                continue;
            };
            let Some(end) = locate(join) else { continue };
            if !complete_arguments(&compressed[body_at..end], 1) {
                continue;
            }
            let Some(begin) = constructor_argument_start(&compressed[..branch_at], 1) else {
                continue;
            };
            let original_begin = origins[begin];
            if fixups.iter().any(|fixup| {
                let inside = fixup.at >= original_begin && fixup.at < join;
                let target = offsets.get(&fixup.target).copied().map(|at| at as usize);
                inside && target.is_none_or(|at| at < original_begin || at > join)
                    || !inside && target.is_some_and(|at| at > original_begin && at < join)
            }) {
                continue;
            }
            compressed.splice(begin..end, [0x50, 0]);
            origins.splice(begin..end, [original_begin, original_begin]);
            collapsed = true;
        }
        // Short-circuit operators preserve the left value on the taken edge and
        // otherwise replace it with one RHS value. Collapse only closed spans.
        let mut short_circuits: Vec<_> = fixups
            .iter()
            .filter_map(|branch| {
                let join = *offsets.get(&branch.target)? as usize;
                (branch.target <= assignment as u32
                    && branch.at > 0
                    && matches!(words.get(branch.at - 1), Some(0xb2 | 0xb3))
                    && matches!(code.get(branch.source), Some(0x15 | 0x2f | 0x66 | 0x67)))
                .then_some((*branch, join))
            })
            .collect();
        short_circuits.sort_by_key(|(branch, join)| join.saturating_sub(branch.at));
        for (branch, join) in short_circuits {
            let locate = |original| {
                if original == words.len() {
                    Some(origins.len())
                } else {
                    origins.iter().position(|offset| *offset == original)
                }
            };
            let Some(branch_at) = locate(branch.at - 1) else {
                continue;
            };
            let Some(rhs_at) = locate(branch.at + 1) else {
                continue;
            };
            let Some(end) = locate(join) else { continue };
            if !complete_arguments(&compressed[rhs_at..end], 1) {
                continue;
            }
            let Some(begin) = constructor_argument_start(&compressed[..branch_at], 1) else {
                continue;
            };
            let original_begin = origins[begin];
            if fixups.iter().any(|fixup| {
                let inside = fixup.at >= original_begin && fixup.at < join;
                let target = offsets.get(&fixup.target).copied().map(|at| at as usize);
                inside && target.is_none_or(|at| at < original_begin || at > join)
                    || !inside && target.is_some_and(|at| at > original_begin && at < join)
            }) {
                continue;
            }
            compressed.splice(begin..end, [0x50, 0]);
            origins.splice(begin..end, [original_begin, original_begin]);
            collapsed = true;
        }
        if compressed.len() == previous_len {
            break;
        }
    }
    if !collapsed {
        return None;
    }
    let rhs = constructor_argument_start(&compressed, 1)?;
    let list = if destination_count == 0 {
        rhs
    } else {
        constructor_argument_start(&compressed[..rhs], destination_count)?
    };
    let list_at = origins[list];
    let value_at = origins[rhs];
    // The compressed destination must consist of exactly two verified values.
    // Closed branches in either value retain their original code and fixups.
    if destination_count != 0 && !complete_arguments(&compressed[list..rhs], destination_count) {
        return None;
    }
    Some((list_at, value_at))
}

// A switch may fold its synthetic default jump into the table, but an authored
// transfer still performs its own loop budget or exception-frame operation.
pub(super) fn authored_control_jump(ids: &impl SymbolResolver, code: &[u8], offset: usize) -> bool {
    let backward = code
        .get(offset + 1..offset + 5)
        .is_some_and(|bytes| u32::from_le_bytes(bytes.try_into().unwrap()) as usize <= offset);
    backward
        || ids.native_continue(offset) == Some(true)
        || ids.native_goto(offset)
        || ids.native_try_continue(offset)
        || ids.native_try_break(offset)
        || ids.native_try_goto(offset)
}

pub(super) fn read_do_while_backedge(
    reader: &mut Reader<'_>,
    start: usize,
    false_target: u32,
) -> Result<(usize, u32), LowerError> {
    let jump = reader.at;
    if reader.code.get(jump) != Some(&0x0e) || false_target as usize != jump + 5 {
        return Err(LowerError {
            kind: LowerErrorKind::MalformedControlFlow,
            offset: start,
            reason: "native do/while condition lacks its paired exit/backedge".into(),
        });
    }
    reader.byte()?;
    let target = reader.word()?;
    if target as usize >= start {
        return Err(LowerError {
            kind: LowerErrorKind::MalformedControlFlow,
            offset: start,
            reason: "native do/while condition has no backward loop body".into(),
        });
    }
    Ok((jump, target))
}
// The inserted constructor receiver belongs to the source expression's entry.
// External source branches must execute it; interior argument joins still shift.
pub(super) fn insert_expression_prefix(
    out: &mut Vec<u32>,
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut [Fixup],
    at: usize,
    prefix: &[u32],
) {
    let entries: Vec<_> = offsets
        .iter()
        .filter_map(|(&byte, &word)| (word as usize == at).then_some(byte))
        .collect();
    replace_words(out, offsets, fixups, at, 0, prefix);
    for entry in entries {
        offsets.insert(entry, at as u32);
    }
}
pub(super) fn preserve_external_expression_entry(
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut [Fixup],
    begin: usize,
    end: usize,
) -> Option<u32> {
    let incoming: Vec<_> = fixups
        .iter()
        .enumerate()
        .filter_map(|(index, fixup)| {
            (!(begin..end).contains(&fixup.at)
                && offsets.get(&fixup.target).copied() == Some(begin as u32))
            .then_some(index)
        })
        .collect();
    if incoming.is_empty() {
        return None;
    }
    let mut label = 0x8000_0000;
    while offsets.contains_key(&label) {
        label += 1;
    }
    offsets.insert(label, begin as u32);
    for index in incoming {
        fixups[index].target = label;
    }
    Some(label)
}

/// Rotate a verified conditional RHS before its indexed destination, retaining
/// all branches within the expression and its join before destination reads.
pub(super) fn reorder_guarded_indexed_rhs(
    out: &mut Vec<u32>,
    code: &[u8],
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut [Fixup],
    safe_skip_pop: &mut HashMap<usize, u32>,
    start: usize,
    trailer: &[u32],
) -> bool {
    let Some((list_at, value_at)) = guarded_indexed_spans(out, code, offsets, fixups, start) else {
        return false;
    };
    let end = out.len();
    let external_entry = preserve_external_expression_entry(offsets, fixups, list_at, end);
    let value_len = end - value_at;
    let mut replacement = out[value_at..end].to_vec();
    replacement.extend_from_slice(&out[list_at..value_at]);
    replacement.extend_from_slice(trailer);
    let moved = |old: usize| {
        if old < value_at {
            list_at + value_len + old - list_at
        } else {
            list_at + old - value_at
        }
    };
    for value in offsets.values_mut() {
        if (*value as usize) >= list_at && (*value as usize) < end {
            *value = moved(*value as usize) as u32;
        }
    }
    let synthetic_target = u32::MAX - start as u32;
    let destination_join = synthetic_target - 1;
    let safe_join = synthetic_target - 2;
    let cache_unwind = byond_dmb::bytecode::decode(&out[value_at..end])
        .ok()
        .map_or(0, |items| {
            items
                .iter()
                .rev()
                .take_while(|item| item.opcode == 0x143)
                .count()
        });
    for (index, fixup) in fixups.iter_mut().enumerate() {
        if fixup.at >= value_at && fixup.at < end && fixup.target == start as u32 {
            fixup.target = if fixup.at > 0 && out[fixup.at - 1] == 0x13d {
                let saved = cache_frame_depth(&out[value_at..fixup.at - 1]);
                safe_skip_pop
                    .entry(index)
                    .or_insert(cache_unwind.saturating_sub(saved) as u32);
                safe_join
            } else {
                synthetic_target
            };
        }
        if fixup.at >= list_at
            && fixup.at < value_at
            && offsets.get(&fixup.target).copied() == Some(list_at as u32)
        {
            // A destination expression joining at the old RHS boundary must
            // now join immediately before the store, after destination reads.
            fixup.target = destination_join;
        }
        if fixup.at >= list_at && fixup.at < end {
            fixup.at = moved(fixup.at);
        }
    }
    replace_words(out, offsets, fixups, list_at, end - list_at, &replacement);
    offsets.insert(synthetic_target, (list_at + value_len) as u32);
    offsets.insert(safe_join, (list_at + value_len - cache_unwind) as u32);
    offsets.insert(destination_join, end as u32);
    if let Some(label) = external_entry {
        offsets.insert(label, list_at as u32);
    }
    true
}
