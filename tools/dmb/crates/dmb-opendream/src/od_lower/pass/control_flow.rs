use super::*;

impl<R: SymbolResolver> PassState<'_, R> {
    pub(super) fn lower_control_flow(
        &mut self,
        start: usize,
        op: u8,
        _follows_format: bool,
    ) -> Result<OpcodeFlow, LowerError> {
        let code = self.inputs.code;
        let ids = self.inputs.ids;
        let world_flow = &mut *self.world_flow;
        match op {
            0x30 => {
                let count = self.reader.word()?;
                if count == 0 || count > 255 {
                    return Err(LowerError {
                        kind: LowerErrorKind::UnsupportedConstruct,
                        offset: start,
                        reason: "multidimensional list dimension count is unsupported".into(),
                    });
                }
                let args_at = constructor_argument_start(&self.out, count as usize)
                    .or_else(|| {
                        guarded_assignment_spans(
                            &self.out,
                            code,
                            &self.offsets,
                            &self.fixups,
                            start,
                            count as usize - 1,
                        )
                        .map(|(first, _)| first)
                    })
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::UnsupportedConstruct,
                        offset: start,
                        reason: "multidimensional list sizes have unsupported stack effects".into(),
                    })?;
                if count == 1 {
                    // DreamMaker emits EmptyList for a one-dimensional list
                    // whose size is computed at runtime.
                    self.out.push(0x19);
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                replace_words(
                    &mut self.out,
                    &mut self.offsets,
                    &mut self.fixups,
                    args_at,
                    0,
                    &[0x60, 40, 0],
                );
                self.out.extend([0x01, count]);
            }
            0x54 | 0x55 => {
                let count = self.reader.word()? as usize;
                PickLowering {
                    code,
                    start,
                    out: &mut self.out,
                    offsets: &mut self.offsets,
                    fixups: &mut self.fixups,
                    world_flow: &mut *world_flow,
                    state: &mut self.state,
                    probability_regions: &mut self.probability_regions,
                }
                .lower(op == 0x55, count)?;
            }
            0x5b => {
                // OD pushes value, lower, upper; native IsIn range expects
                // lower, upper, value and then reads the membership flag.
                let upper_at = guarded_assignment_spans(
                    &self.out,
                    code,
                    &self.offsets,
                    &self.fixups,
                    start,
                    0,
                )
                .map(|(first, _)| first)
                .or_else(|| constructor_argument_start(&self.out, 1))
                .ok_or_else(|| LowerError {
                    kind: LowerErrorKind::UnsupportedConstruct,
                    offset: start,
                    reason: "IsInRange upper bound has unsupported stack effects".into(),
                })?;
                let lower_at = guarded_assignment_spans(
                    &self.out[..upper_at],
                    code,
                    &self.offsets,
                    &self.fixups,
                    start,
                    0,
                )
                .map(|(first, _)| first)
                .or_else(|| constructor_argument_start(&self.out[..upper_at], 1))
                .ok_or_else(|| LowerError {
                    kind: LowerErrorKind::UnsupportedConstruct,
                    offset: start,
                    reason: "IsInRange lower bound has unsupported stack effects".into(),
                })?;
                let value_at = guarded_assignment_spans(
                    &self.out[..lower_at],
                    code,
                    &self.offsets,
                    &self.fixups,
                    start,
                    0,
                )
                .map(|(first, _)| first)
                .or_else(|| constructor_argument_start(&self.out[..lower_at], 1))
                .ok_or_else(|| LowerError {
                    kind: LowerErrorKind::UnsupportedConstruct,
                    offset: start,
                    reason: "IsInRange value has unsupported stack effects".into(),
                })?;
                let old_end = self.out.len();
                let spans = [
                    (value_at, lower_at),
                    (lower_at, upper_at),
                    (upper_at, old_end),
                ];
                if !closed_spans(&spans, &self.offsets, &self.fixups) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "IsInRange operands have nonlocal branches".into(),
                    });
                }
                world_flow.separate_reordered_arguments(&spans, &self.offsets, code.len());
                self.state.cached_world_owner = false;
                self.state.pending_world_ref = None;
                self.state.last_reference_push = None;
                let moved = [
                    ((lower_at, upper_at), value_at),
                    ((upper_at, old_end), value_at + upper_at - lower_at),
                    ((value_at, lower_at), value_at + old_end - lower_at),
                ];
                let mut reordered = self.out[lower_at..upper_at].to_vec();
                reordered.extend_from_slice(&self.out[upper_at..]);
                reordered.extend_from_slice(&self.out[value_at..lower_at]);
                let old_len = self.out.len() - value_at;
                replace_closed_spans(
                    &mut self.out,
                    &mut self.offsets,
                    &mut self.fixups,
                    value_at,
                    old_len,
                    &reordered,
                    &moved,
                );
                self.out.extend([0xa9, 11, 0x36]);
            }
            0x1e => {
                let count = self.reader.word()?;
                let entry_words = (count as usize).checked_mul(2).ok_or_else(|| LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "associative list entry count overflow".into(),
                })?;
                let mut end = self.out.len();
                let mut entries = Vec::with_capacity(entry_words);
                for _ in 0..entry_words {
                    let at = constructor_argument_start(&self.out[..end], 1).ok_or_else(|| {
                        LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "associative list entry has unknown stack effects".into(),
                        }
                    })?;
                    entries.push((at, end));
                    end = at;
                }
                entries.reverse();
                for index in (0..count as usize).rev() {
                    let (key_at, key_end) = entries[index * 2];
                    if self.out[key_at..key_end] == [0x60, 0, 0] {
                        replace_words(
                            &mut self.out,
                            &mut self.offsets,
                            &mut self.fixups,
                            key_at,
                            3,
                            &[0x50, index as u32 + 1],
                        );
                    }
                }
                self.out.extend([0xc8, count]);
            } // CreateAssociativeList
            0x0e | 0x0c | 0x15 | 0x2f => {
                let target = self.reader.word()?;
                if op == 0x0c {
                    // DreamMaker equality leaves a comparison flag that needs
                    // Pop; relational comparisons require Test before Jz.
                    let last_opcode =
                        byond_dmb::bytecode::decode(&self.out)
                            .ok()
                            .and_then(|instructions| {
                                instructions
                                    .iter()
                                    .rev()
                                    .find(|item| !matches!(item.opcode, 0x84 | 0x85))
                                    .map(|item| item.opcode)
                            });
                    let last_uses_flag = last_opcode
                        .is_some_and(|opcode| matches!(opcode, 0xa9 | 0x14..=0x17 | 0x16c | 0x16d));
                    if !last_uses_flag {
                        self.out.push(if matches!(last_opcode, Some(0x37 | 0x71)) {
                            0x51
                        } else {
                            0x0d
                        });
                    }
                }
                let do_while = op == 0x0c && ids.native_do_while_condition(start);
                let target = if do_while {
                    let (jump, body) = read_do_while_backedge(&mut self.reader, start, target)?;
                    self.offsets.insert(jump as u32, self.out.len() as u32);
                    body
                } else {
                    target
                };
                let byond = if do_while {
                    0xf9
                } else {
                    match op {
                        0x0e if (target as usize) <= start
                            || ids.native_continue(start).unwrap_or_else(|| {
                                is_simple_continue_tail(code, start, target)
                            }) =>
                        {
                            0xf8
                        }
                        0x0e => 0x0f,
                        0x0c => 0x11,
                        0x15 => 0xb3,
                        _ => 0xb2,
                    }
                };
                self.out.extend([byond, 0]);
                self.fixups.push(Fixup {
                    at: self.out.len() - 1,
                    target,
                    source: start,
                });
            }
            _ => return Ok(OpcodeFlow::Unhandled),
        }
        Ok(OpcodeFlow::Advance)
    }
}
