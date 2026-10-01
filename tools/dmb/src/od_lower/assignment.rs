/// Guarded and ordinary statement assignments, including native Del clearing.
struct AssignmentLowering<'a, 'code, R: SymbolResolver> {
    code: &'code [u8],
    reader: &'a mut Reader<'code>,
    ids: &'a R,
    start: usize,
    out: &'a mut Vec<u32>,
    offsets: &'a mut HashMap<u32, u32>,
    fixups: &'a mut Vec<Fixup>,
    state: &'a mut LowerState,
    safe: &'a mut SafeAccessState,
    is_initializer: bool,
}

impl<R: SymbolResolver> AssignmentLowering<'_, '_, R> {
    /// Returns true when the source loop must start at the next instruction.
    fn lower(&mut self) -> Result<bool, LowerError> {
        let code = self.code;
        let mut reader = &mut *self.reader;
        let ids = self.ids;
        let start = self.start;
        let mut out = &mut *self.out;
        let mut offsets = &mut *self.offsets;
        let mut fixups = &mut *self.fixups;
        let state = &mut *self.state;
        let safe = &mut *self.safe;
        let is_initializer = self.is_initializer;
        if ids.native_delete_clear(start) {
            // Exported Del clearing has already evaluated null before
            // the reference; its original deletion target remains below.
            if reader.code.get(reader.at) == Some(&7) {
                reader.byte()?;
                out.push(0x7c);
            } else {
                let target = reference(&mut reader, ids)?;
                if let Variable::Field(field) = target {
                    let guarded_owner = crate::bytecode::decode(&out)
                        .ok()
                        .and_then(|items| {
                            items
                                .into_iter()
                                .rev()
                                .find(|item| !matches!(item.opcode, 0x84 | 0x85))
                        })
                        .is_some_and(|item| item.opcode == 0x13e);
                    if guarded_owner {
                        out.extend([0x34, field]);
                    } else if let Some((at, owner)) =
                        state.last_reference_push.clone().filter(|(at, owner)| {
                            matches!(
                                owner,
                                Variable::Arg(_)
                                    | Variable::Local(_)
                                    | Variable::Global(_)
                                    | Variable::Src
                            ) && !fixups.iter().any(|fixup| {
                                fixup.target == start as u32
                                    || offsets.get(&fixup.target).is_some_and(|target| {
                                        (*target as usize) >= *at + 1 + owner.encode().len()
                                            && (*target as usize) <= out.len()
                                    })
                            }) && crate::bytecode::decode(&out)
                                .ok()
                                .and_then(|items| {
                                    items
                                        .into_iter()
                                        .rev()
                                        .find(|item| !matches!(item.opcode, 0x84 | 0x85))
                                })
                                .is_some_and(|item| item.opcode == 0x33 && item.offset == *at)
                        })
                    {
                        let mut replacement = vec![0x34];
                        replacement.extend(
                            Variable::SetCache(
                                Box::new(owner.clone()),
                                Box::new(Variable::Field(field)),
                            )
                            .encode(),
                        );
                        let length = 1 + owner.encode().len();
                        replace_words(&mut out, &mut offsets, &mut fixups, at, length, &[]);
                        out.extend(replacement);
                    } else {
                        out.extend([0x34, 0xffd8, 0x34, field]);
                    }
                } else {
                    out.push(0x34);
                    out.extend(target.encode());
                }
            }
            state.last_reference_push = None;
            state.cached_world_owner = false;
            return Ok(true);
        }
        if reader.code.get(reader.at) == Some(&7) {
            reader.byte()?;
            let short_circuit_indexed = (|| {
                let branch = *fixups.last()?;
                if reader.code.get(branch.source) != Some(&0x2f) || branch.target > start as u32 {
                    return None;
                }
                let items = crate::bytecode::decode(&out).ok()?;
                let jump_at = items.iter().rposition(|item| item.opcode == 0xb2)?;
                let before = items.get(jump_at.checked_sub(5)?..jump_at)?;
                if before.iter().map(|item| item.opcode).collect::<Vec<_>>()
                    != [0x33, 0x33, 0x33, 0x33, 0x7b]
                    || before[0].operands != before[2].operands
                    || before[1].operands != before[3].operands
                    || branch.at != items[jump_at].offset + 1
                {
                    return None;
                }
                let list_at = before[0].offset;
                let value_at = before[2].offset;
                if *offsets.get(&branch.target)? as usize <= items[jump_at].offset {
                    return None;
                }
                Some((list_at, value_at, branch.target == start as u32))
            })();
            if let Some((list_at, value_at, branch_at_assignment)) = short_circuit_indexed {
                // OD preserves the assignment's list/key on the stack
                // while computing a short-circuit value. DreamMaker
                // computes the value, then fetches list/key for ListSet.
                let end = out.len();
                let value_len = end - value_at;
                let mut replacement = out[value_at..end].to_vec();
                replacement.extend_from_slice(&out[list_at..value_at]);
                replacement.push(0x7c);
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
                for fixup in fixups.iter_mut() {
                    if fixup.at >= list_at && fixup.at < end {
                        fixup.at = moved(fixup.at);
                    }
                }
                replace_words(
                    &mut out,
                    &mut offsets,
                    &mut fixups,
                    list_at,
                    end - list_at,
                    &replacement,
                );
                if branch_at_assignment {
                    let synthetic_target = u32::MAX - start as u32;
                    offsets.insert(synthetic_target, (list_at + value_len) as u32);
                    if let Some(branch) = fixups.last_mut() {
                        branch.target = synthetic_target;
                    }
                }
                return Ok(true);
            }
            if let Some((list_at, value_at)) =
                guarded_indexed_spans(&out, code, &offsets, &fixups, start)
            {
                // Native evaluates the entire conditional RHS before
                // the destination list/key, including enclosing calls.
                let end = out.len();
                let value_len = end - value_at;
                let mut replacement = out[value_at..end].to_vec();
                replacement.extend_from_slice(&out[list_at..value_at]);
                replacement.push(0x7c);
                let moved = |old: usize| {
                    if old < value_at {
                        list_at + value_len + (old - list_at)
                    } else {
                        list_at + (old - value_at)
                    }
                };
                for value in offsets.values_mut() {
                    if (*value as usize) >= list_at && (*value as usize) < end {
                        *value = moved(*value as usize) as u32;
                    }
                }
                for fixup in fixups.iter_mut() {
                    if fixup.at >= list_at && fixup.at < end {
                        fixup.at = moved(fixup.at);
                    }
                }
                replace_words(
                    &mut out,
                    &mut offsets,
                    &mut fixups,
                    list_at,
                    end - list_at,
                    &replacement,
                );
                let synthetic_target = u32::MAX - start as u32;
                // Safe RHS exits already carry per-edge cache-unwind
                // adjustments. Their shared join starts before trailing
                // PopCache instructions, as in the direct safe path.
                let cache_unwind = crate::bytecode::decode(&replacement[..value_len])
                    .ok()
                    .map_or(0, |items| {
                        items
                            .iter()
                            .rev()
                            .take_while(|item| item.opcode == 0x143)
                            .count()
                    });
                let safe_target = synthetic_target - 1;
                offsets.insert(synthetic_target, (list_at + value_len) as u32);
                offsets.insert(safe_target, (list_at + value_len - cache_unwind) as u32);
                for (index, fixup) in fixups.iter_mut().enumerate() {
                    if fixup.at >= list_at
                        && fixup.at < list_at + value_len
                        && fixup.target == start as u32
                    {
                        fixup.target = if fixup.at > 0 && out[fixup.at - 1] == 0x13d {
                            let saved = cache_frame_depth(&out[list_at..fixup.at - 1]);
                            safe.safe_skip_pop
                                .entry(index)
                                .or_insert(cache_unwind.saturating_sub(saved) as u32);
                            safe_target
                        } else {
                            synthetic_target
                        };
                    }
                }
                return Ok(true);
            }
            if let Some(safe_index) = fixups.iter().position(|fixup| {
                fixup.target == start as u32
                    && fixup.at > 0
                    && out.get(fixup.at - 1) == Some(&0x13d)
            }) {
                // `L[key] = owner?.field`: OpenDream leaves L and key on
                // stack before evaluating the safe value. DreamMaker
                // evaluates the value first, then L/key and ListSet.
                let branch_at = fixups[safe_index].at - 1;
                let value_at =
                    constructor_argument_start(&out[..branch_at], 1).ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "safe indexed value has no direct receiver".into(),
                    })?;
                let key_at =
                    constructor_argument_start(&out[..value_at], 1).ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "safe indexed assignment has no key".into(),
                    })?;
                let list_at =
                    constructor_argument_start(&out[..key_at], 1).ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "safe indexed assignment has no list".into(),
                    })?;
                let pure = |slice: &[u32]| {
                    crate::bytecode::decode(slice).is_ok_and(|items| {
                        items.iter().all(|item| {
                            matches!(
                                item.opcode,
                                0x02 | 0x33
                                    | 0x3e
                                    | 0x50
                                    | 0x60
                                    | 0x62
                                    | 0x65
                                    | 0x6e
                                    | 0x74
                                    | 0x75
                                    | 0x7b
                                    | 0x13f
                            )
                        })
                    })
                };
                // The safe branch already installed its receiver in
                // Cache. An indexed field read can otherwise carry a
                // redundant SetCache(Cache, Field) wrapper.
                let redundant_cache = crate::bytecode::decode(&out[branch_at..])
                    .ok()
                    .into_iter()
                    .flatten()
                    .filter(|item| {
                        item.opcode == 0x33
                            && item.operands.len() == 3
                            && item.operands[..2] == [0xffdc, 0xffd8]
                    })
                    .map(|item| branch_at + item.offset + 1)
                    .collect::<Vec<_>>();
                for at in redundant_cache.into_iter().rev() {
                    replace_words(&mut out, &mut offsets, &mut fixups, at, 2, &[]);
                }
                let tail_items = crate::bytecode::decode(&out[branch_at..]).ok();
                let cache_unwind = tail_items.as_ref().map_or(0, |items| {
                    items
                        .iter()
                        .rev()
                        .take_while(|item| item.opcode == 0x143)
                        .count()
                });
                let safe_tail = tail_items.is_some_and(|items| {
                    items.iter().all(|item| {
                        matches!(
                            item.opcode,
                            0x13d | 0x33 | 0x142 | 0x143 | 0x29 | 0x50 | 0x60 | 0x7b
                        )
                    })
                });
                if !pure(&out[list_at..key_at]) || !pure(&out[key_at..value_at]) || !safe_tail {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "safe indexed assignment has unverified operand shape".into(),
                    });
                }
                let end = out.len();
                let value_len = end - value_at;
                let mut replacement = out[value_at..end].to_vec();
                replacement.extend_from_slice(&out[list_at..value_at]);
                replacement.push(0x7c);
                let moved = |old: usize| {
                    if old < value_at {
                        list_at + value_len + (old - list_at)
                    } else {
                        list_at + (old - value_at)
                    }
                };
                for value in offsets.values_mut() {
                    if (*value as usize) >= list_at && (*value as usize) < end {
                        *value = moved(*value as usize) as u32;
                    }
                }
                for fixup in fixups.iter_mut() {
                    if fixup.at >= list_at && fixup.at < end {
                        fixup.at = moved(fixup.at);
                    }
                }
                replace_words(
                    &mut out,
                    &mut offsets,
                    &mut fixups,
                    list_at,
                    end - list_at,
                    &replacement,
                );
                let synthetic_target = u32::MAX - start as u32;
                offsets.insert(
                    synthetic_target,
                    (list_at + value_len - cache_unwind) as u32,
                );
                safe.safe_skip_pop
                    .entry(safe_index)
                    .or_insert(cache_unwind as u32);
                for fixup in fixups.iter_mut() {
                    if fixup.target == start as u32
                        && fixup.at >= list_at
                        && fixup.at < list_at + value_len
                    {
                        fixup.target = synthetic_target;
                    }
                }
                return Ok(true);
            }
            let mut end = out.len();
            let mut spans = Vec::new();
            for _ in 0..3 {
                let Some(at) = constructor_argument_start(&out[..end], 1).or_else(|| {
                    guarded_assignment_spans(&out[..end], code, &offsets, &fixups, start, 0)
                        .map(|(first, _)| first)
                }) else {
                    break;
                };
                spans.push((at, end));
                end = at;
            }
            spans.reverse();
            if spans.len() == 2 {
                // An initializer may leave its assigned list on the
                // stack for the first indexed write. DreamMaker stores
                // it, then fetches the list after computing the value.
                let key_at = spans[0].0;
                if let Ok(instructions) = crate::bytecode::decode(&out) {
                    if let Some(initializer) =
                        instructions.iter().rev().find(|item| item.offset < key_at)
                    {
                        if initializer.opcode == 0x35
                            && matches!(initializer.operands.as_slice(), [65498, _])
                        {
                            let target = initializer.operands.clone();
                            let mut replacement = out[spans[1].0..spans[1].1].to_vec();
                            replacement.push(0x33);
                            replacement.extend(target);
                            replacement.extend_from_slice(&out[spans[0].0..spans[0].1]);
                            replacement.push(0x7c);
                            let old_len = out.len() - key_at;
                            replace_words(
                                &mut out,
                                &mut offsets,
                                &mut fixups,
                                key_at,
                                old_len,
                                &replacement,
                            );
                            out[initializer.offset] = 0x34;
                            return Ok(true);
                        }
                    }
                }
            }
            if spans.len() == 3 {
                let (list_at, list_end) = spans[0];
                if let Ok(instructions) = crate::bytecode::decode(&out[list_at..list_end]) {
                    if let Some(set) = instructions.last() {
                        if set.opcode == 0x35
                                    && instructions.len() >= 2
                                    && instructions[..instructions.len() - 1]
                                        .iter()
                                        .all(|item| !matches!(item.opcode, 0x0f..=0x11 | 0xb2..=0xb4 | 0x13d | 0x13e))
                                {
                                    if let Ok((Variable::Local(local), used)) =
                                        Variable::decode(&set.operands)
                                    {
                                        if used == set.operands.len() {
                                            // OD keeps the assigned list on the stack. Native
                                            // stores it in the local, computes the value, then
                                            // reloads the local for ListSet.
                                            let mut replacement = out[list_at..list_end].to_vec();
                                            replacement[set.offset] = 0x34;
                                            replacement
                                                .extend_from_slice(&out[spans[2].0..spans[2].1]);
                                            replacement.push(0x33);
                                            replacement.extend(Variable::Local(local).encode());
                                            replacement
                                                .extend_from_slice(&out[spans[1].0..spans[1].1]);
                                            replacement.push(0x7c);
                                            let old_len = out.len() - list_at;
                                            replace_words(
                                                &mut out,
                                                &mut offsets,
                                                &mut fixups,
                                                list_at,
                                                old_len,
                                                &replacement,
                                            );
                                            return Ok(true);
                                        }
                                    }
                                }
                    }
                }
            }
            if spans.len() != 3
                || spans[..2].iter().any(|(at, end)| {
                    !crate::bytecode::decode(&out[*at..*end]).is_ok_and(|items| {
                        items.iter().all(|item| {
                            matches!(
                                item.opcode,
                                0x02 | 0x30
                                    | 0x33
                                    | 0x3e
                                    | 0x50
                                    | 0x60
                                    | 0x62
                                    | 0x65
                                    | 0x6e
                                    | 0x74
                                    | 0x75
                                    | 0x7b
                                    | 0x13f
                            )
                        })
                    })
                })
            {
                return Err(LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "indexed assignment requires known list/key and value stack effects"
                        .into(),
                });
            }
            let mut replacement = Vec::new();
            for (at, end) in [spans[2], spans[0], spans[1]] {
                replacement.extend_from_slice(&out[at..end]);
            }
            replacement.push(0x7c); // ListSet
            let at = spans[0].0;
            let old_len = out.len() - at;
            replace_words(
                &mut out,
                &mut offsets,
                &mut fixups,
                at,
                old_len,
                &replacement,
            );
            return Ok(true);
        }
        out.push(0x34);
        let target = reference(&mut reader, ids)?;
        if matches!(target, Variable::Field(_)) {
            return Err(LowerError {
                kind: LowerErrorKind::MalformedControlFlow,
                offset: start,
                reason: "legacy field statement assignment requires the native-ordered A8 exporter"
                    .into(),
            });
        }
        let target = if is_initializer {
            match target {
                Variable::SetCache(lhs, rhs) if *lhs == Variable::Src => Variable::SetCache(
                    lhs,
                    Box::new(Variable::SetCache(Box::new(Variable::Src), rhs)),
                ),
                other => other,
            }
        } else {
            target
        };
        emit_tracked_reference(
            &mut out,
            &target,
            &mut state.cached_world_owner,
            &mut state.pending_world_ref,
        );

        Ok(false)
    }
}
