use super::*;

impl<R: SymbolResolver> PassState<'_, R> {
    pub(super) fn lower_postfix_calls(
        &mut self,
        start: usize,
        op: u8,
        follows_format: bool,
    ) -> Result<OpcodeFlow, LowerError> {
        let code = self.inputs.code;
        let ids = self.inputs.ids;
        match op {
            0x57 => {
                if self.reader.code.get(self.reader.at) == Some(&7) {
                    self.reader.byte()?;
                    let at =
                        constructor_argument_start(&self.out, 2).ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "indexed decrement has unknown list/key stack effects".into(),
                        })?;
                    if self.fixups.iter().any(|fixup| fixup.at >= at) {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "indexed decrement operand branches are unverified".into(),
                        });
                    }
                    self.out.extend([0x34, 0xffe3, 0x34, 0xffd8]);
                    let statement = self.reader.code.get(self.reader.at) == Some(&0x51)
                        && !self
                            .fixups
                            .iter()
                            .any(|fixup| fixup.target == self.reader.at as u32);
                    self.out
                        .extend([if statement { 0x67 } else { 0x65 }, 0xffe4]);
                    if statement {
                        self.offsets
                            .insert(self.reader.at as u32, self.out.len() as u32);
                        self.reader.byte()?;
                    }
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                let target = reference(&mut self.reader, ids)?;
                if self.reader.code.get(self.reader.at) == Some(&0x51)
                    && !self
                        .fixups
                        .iter()
                        .any(|fixup| fixup.target == self.reader.at as u32)
                {
                    self.out.push(0x67); // Dec in statement position
                    emit_tracked_reference(
                        &mut self.out,
                        &target,
                        &mut self.state.cached_world_owner,
                        &mut self.state.pending_world_ref,
                    );
                    self.offsets
                        .insert(self.reader.at as u32, self.out.len() as u32);
                    self.reader.byte()?;
                } else {
                    self.out.push(0x65); // PostDec in expression position
                    emit_tracked_reference(
                        &mut self.out,
                        &target,
                        &mut self.state.cached_world_owner,
                        &mut self.state.pending_world_ref,
                    );
                }
            }
            0x62 | 0x63 => {
                if self.reader.code.get(self.reader.at) == Some(&7) {
                    self.reader.byte()?;
                    self.out.extend([
                        0x34,
                        0xffe3,
                        0x34,
                        0xffd8,
                        if op == 0x62 { 0x62 } else { 0x64 },
                        0xffe4,
                    ]);
                } else {
                    self.out.push(if op == 0x62 { 0x62 } else { 0x64 });
                    let target = reference(&mut self.reader, ids)?;
                    emit_tracked_reference(
                        &mut self.out,
                        &target,
                        &mut self.state.cached_world_owner,
                        &mut self.state.pending_world_ref,
                    );
                }
            }
            0x4e => {
                // OutputReference(Field) uses a world target placed earlier
                // on the stack. DreamMaker resolves the field on that target
                // before evaluating the output value.
                let at = self.reader.at;
                let kind = self.reader.byte()?;
                if kind == 7 {
                    // Indexed output uses the list value, key, and RHS on
                    // OpenDream's stack. Native output first constructs an
                    // Index receiver from the list/key pair.
                    let rhs_at = guarded_assignment_spans(
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
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "indexed output RHS has unknown stack effects".into(),
                    })?;
                    let key_at = guarded_assignment_spans(
                        &self.out[..rhs_at],
                        code,
                        &self.offsets,
                        &self.fixups,
                        start,
                        0,
                    )
                    .map(|(first, _)| first)
                    .or_else(|| constructor_argument_start(&self.out[..rhs_at], 1))
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "indexed output key has unknown stack effects".into(),
                    })?;
                    let preceding = byond_dmb::bytecode::decode(&self.out)
                        .ok()
                        .and_then(|items| items.into_iter().rfind(|item| item.offset < key_at));
                    let list = if let Some(initializer) = preceding.filter(|item| {
                        item.opcode == 0x35 && matches!(item.operands.as_slice(), [65498, _])
                    }) {
                        self.out[initializer.offset] = 0x34;
                        let mut get = vec![0x33];
                        get.extend(initializer.operands);
                        get
                    } else {
                        let list_at = guarded_assignment_spans(
                            &self.out[..key_at],
                            code,
                            &self.offsets,
                            &self.fixups,
                            start,
                            0,
                        )
                        .map(|(first, _)| first)
                        .or_else(|| constructor_argument_start(&self.out[..key_at], 1))
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "indexed output receiver has unknown stack effects".into(),
                        })?;
                        let old_end = self.out.len();
                        let spans = [(list_at, key_at), (key_at, rhs_at), (rhs_at, old_end)];
                        if !closed_spans(&spans, &self.offsets, &self.fixups) {
                            return Err(LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "indexed output operands have nonlocal branches".into(),
                            });
                        }
                        let mut replacement = self.out[list_at..rhs_at].to_vec();
                        replacement.push(0xb0);
                        replacement.extend_from_slice(&self.out[rhs_at..]);
                        replacement.push(0x03);
                        let old_len = self.out.len() - list_at;
                        replace_closed_spans(
                            &mut self.out,
                            &mut self.offsets,
                            &mut self.fixups,
                            list_at,
                            old_len,
                            &replacement,
                            &[
                                ((list_at, key_at), list_at),
                                ((key_at, rhs_at), key_at),
                                ((rhs_at, old_end), rhs_at + 1),
                            ],
                        );
                        self.state.last_reference_push = None;
                        return Ok(OpcodeFlow::ContinueThisOpcode);
                    };
                    let old_end = self.out.len();
                    let spans = [(key_at, rhs_at), (rhs_at, old_end)];
                    if !closed_spans(&spans, &self.offsets, &self.fixups) {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "indexed output operands have nonlocal branches".into(),
                        });
                    }
                    let list_len = list.len();
                    let mut replacement = list;
                    replacement.extend_from_slice(&self.out[key_at..rhs_at]);
                    replacement.push(0xb0); // Index
                    replacement.extend_from_slice(&self.out[rhs_at..]);
                    replacement.push(0x03); // Output
                    let old_len = self.out.len() - key_at;
                    replace_closed_spans(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        key_at,
                        old_len,
                        &replacement,
                        &[
                            ((key_at, rhs_at), key_at + list_len),
                            ((rhs_at, old_end), rhs_at + list_len + 1),
                        ],
                    );
                    self.state.last_reference_push = None;
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                if kind != 12 {
                    let output_opcode = if self.state.pending_output_run {
                        if kind != 1 {
                            return Err(LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "run() output requires a direct src receiver".into(),
                            });
                        }
                        self.state.pending_output_run = false;
                        0x09 // OutputRun
                    } else {
                        0x03 // Output
                    };
                    // OpenDream evaluates RHS before OutputReference(target),
                    // while DreamMaker evaluates the target before RHS.
                    if !matches!(kind, 1 | 3 | 5 | 8 | 9 | 10 | 13) {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: at,
                            reason: "OutputReference target needs a direct reference".into(),
                        });
                    }
                    self.reader.at = at;
                    let target = reference(&mut self.reader, ids)?;
                    let rhs_at = guarded_assignment_spans(
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
                        reason: "OutputReference RHS stack effects are unsupported".into(),
                    })?;
                    let mut get_target = vec![0x33];
                    get_target.extend(target.encode());
                    // A source label at the RHS expression enters the whole
                    // output statement, including this newly inserted receiver.
                    let entries: Vec<_> = self
                        .offsets
                        .iter()
                        .filter_map(|(&byte, &word)| (word as usize == rhs_at).then_some(byte))
                        .collect();
                    replace_words(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        rhs_at,
                        0,
                        &get_target,
                    );
                    for entry in entries {
                        self.offsets.insert(entry, rhs_at as u32);
                    }
                    let format = byond_dmb::bytecode::decode(&self.out)
                        .ok()
                        .and_then(|items| {
                            items
                                .into_iter()
                                .rfind(|item| !matches!(item.opcode, 0x84 | 0x85))
                        })
                        .filter(|item| item.opcode == 0x02);
                    if let Some(format) = format.filter(|_| output_opcode == 0x03) {
                        self.out[format.offset] = 0x04; // Native OutputFormat.
                    } else {
                        self.out.push(output_opcode);
                    }
                    self.state.last_reference_push = None;
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                let field = mapped(ids.string(self.reader.word()?), start, "string")?;
                if let Some(world) = self.state.pending_world_ref.take() {
                    if world.world_cached_at_push {
                        self.out[world.at + 1] = field;
                    } else {
                        replace_words(
                            &mut self.out,
                            &mut self.offsets,
                            &mut self.fixups,
                            world.at,
                            2,
                            &[0x33, 0xffdc, 0xffe5, field],
                        );
                    }
                    self.state.cached_world_owner = !world.rhs_changed_cache;
                } else {
                    let rhs_at = guarded_assignment_spans(
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
                        reason: "field output RHS stack effects are unsupported".into(),
                    })?;
                    let owner_at = guarded_assignment_spans(
                        &self.out[..rhs_at],
                        code,
                        &self.offsets,
                        &self.fixups,
                        start,
                        0,
                    )
                    .map(|(first, _)| first)
                    .or_else(|| constructor_argument_start(&self.out[..rhs_at], 1))
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "field output owner has unknown stack effects".into(),
                    })?;
                    let owner_items = byond_dmb::bytecode::decode(&self.out[owner_at..rhs_at])
                        .map_err(|error| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: error.reason,
                        })?;
                    let direct = owner_items
                        .iter()
                        .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
                        .count()
                        == 1
                        && owner_items.iter().any(|item| item.opcode == 0x33);
                    if !direct {
                        let old_end = self.out.len();
                        let spans = [(owner_at, rhs_at), (rhs_at, old_end)];
                        if !closed_spans(&spans, &self.offsets, &self.fixups) {
                            return Err(LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "field output operands have nonlocal branches".into(),
                            });
                        }
                        let mut receiver = vec![0x34];
                        receiver.extend(Variable::Cache.encode());
                        receiver.push(0x33);
                        receiver.extend(Variable::Field(field).encode());
                        let added = receiver.len();
                        insert_between_closed_spans(
                            &mut self.out,
                            &mut self.offsets,
                            &mut self.fixups,
                            rhs_at,
                            &receiver,
                            &[
                                ((owner_at, rhs_at), owner_at),
                                ((rhs_at, old_end), rhs_at + added),
                            ],
                        );
                        self.state.cached_world_owner = false;
                    } else {
                        let instructions =
                            byond_dmb::bytecode::decode(&self.out[..rhs_at]).map_err(|error| {
                                LowerError {
                                    kind: LowerErrorKind::MalformedControlFlow,
                                    offset: start,
                                    reason: format!(
                                        "cannot inspect field output owner: {}",
                                        error.reason
                                    ),
                                }
                            })?;
                        let owner_instruction = instructions
                            .iter()
                            .rev()
                            .find(|item| !matches!(item.opcode, 0x84 | 0x85))
                            .filter(|item| item.opcode == 0x33)
                            .ok_or_else(|| LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "field output requires direct owner reference".into(),
                            })?;
                        let (owner, _) =
                            Variable::decode(&owner_instruction.operands).map_err(|error| {
                                LowerError {
                                    kind: LowerErrorKind::MalformedControlFlow,
                                    offset: start,
                                    reason: format!(
                                        "field output owner cannot be decoded: {}",
                                        error.reason
                                    ),
                                }
                            })?;
                        let mut target = vec![0x33];
                        target.extend(
                            Variable::SetCache(Box::new(owner), Box::new(Variable::Field(field)))
                                .encode(),
                        );
                        replace_words(
                            &mut self.out,
                            &mut self.offsets,
                            &mut self.fixups,
                            owner_instruction.offset,
                            1 + owner_instruction.operands.len(),
                            &target,
                        );
                        self.state.cached_world_owner = false;
                    }
                }
                self.state.last_reference_push = None;
                // DreamMaker has a fused output opcode for interpolated
                // strings. The operands are identical to Format, and the
                // fused form consumes the output target as well.
                if follows_format {
                    let format = byond_dmb::bytecode::decode(&self.out)
                        .map_err(|error| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: error.reason,
                        })?
                        .into_iter()
                        .rev()
                        .find(|item| !matches!(item.opcode, 0x84 | 0x85))
                        .filter(|item| item.opcode == 0x02)
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "formatted output lacks its formatting instruction".into(),
                        })?;
                    self.out[format.offset] = 0x04;
                } else {
                    self.out.push(0x03);
                }
            }
            _ => return Ok(OpcodeFlow::Unhandled),
        }
        Ok(OpcodeFlow::Advance)
    }
}
