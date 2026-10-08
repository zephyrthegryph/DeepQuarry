use super::*;

impl<R: SymbolResolver> PassState<'_, R> {
    pub(super) fn lower_constants_constructors(
        &mut self,
        start: usize,
        op: u8,
        _follows_format: bool,
    ) -> Result<OpcodeFlow, LowerError> {
        let ids = self.inputs.ids;
        match op {
            0x11 | 0x38 => {
                if lower_constant_and_switch(
                    op,
                    &mut self.reader,
                    ids,
                    start,
                    &mut self.out,
                    &mut self.offsets,
                    &mut self.fixups,
                    &self.spawn_targets,
                )? {
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
            }
            0x2e => {
                let mode = self.reader.byte()?;
                let count = self.reader.word()?;
                if !(matches!((mode, count), (0, 0))
                    || mode == 1 && (1..=255).contains(&count)
                    || mode == 2 && (2..=510).contains(&count) && count % 2 == 0
                    || (mode, count) == (3, 1))
                {
                    return Err(LowerError {
                        kind: LowerErrorKind::UnsupportedConstruct,
                        offset: start,
                        reason: "dynamic CreateObject argument mode/count is unsupported".into(),
                    });
                }
                let instructions =
                    crate::bytecode::decode(&self.out).map_err(|error| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: format!("cannot inspect dynamic constructor: {}", error.reason),
                    })?;
                let pair = instructions
                    .get(instructions.len().saturating_sub(2)..)
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "dynamic constructor lacks null and type".into(),
                    })?;
                let null = &pair[0];
                let ty = &pair[1];
                if null.opcode != 0x60
                    || self.out.get(null.offset..null.offset + 3) != Some(&[0x60, 0, 0][..])
                    || ty.opcode != 0x33
                {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "dynamic constructor requires direct type reference".into(),
                    });
                }
                let arg_at = if count == 0 {
                    null.offset
                } else {
                    constructor_argument_start(&self.out[..null.offset], count as usize)
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::UnsupportedConstruct,
                            offset: start,
                            reason: "dynamic constructor argument effects are unsupported".into(),
                        })?
                };
                let mut replacement = self.out[ty.offset..].to_vec();
                replacement.extend_from_slice(&self.out[arg_at..null.offset]);
                let old_len = self.out.len() - arg_at;
                replace_words(
                    &mut self.out,
                    &mut self.offsets,
                    &mut self.fixups,
                    arg_at,
                    old_len,
                    &replacement,
                );
                if mode == 2 {
                    self.out.extend([0xc8, count / 2, 0xcf]);
                } else if mode == 3 {
                    self.out.push(0xcf);
                } else {
                    self.out.extend([0x01, count]);
                }
            }
            0x98 => {
                // ReturnFloat
                let bits = self.reader.word()?;
                self.out
                    .extend([0x60, 0x2a, bits >> 16, bits & 0xffff, 0x12]);
            }
            0x9a => {
                // PushFloatAssign(float, reference)
                let bits = self.reader.word()?;
                if self.reader.code.get(self.reader.at) == Some(&7) {
                    self.reader.byte()?; // Index reference consumes the list and key.
                    let argument_start =
                        constructor_argument_start(&self.out, 2).ok_or_else(|| LowerError {
                            kind: LowerErrorKind::UnsupportedConstruct,
                            offset: start,
                            reason: "indexed float assignment has unsupported list/key expressions"
                                .into(),
                        })?;
                    let value = [0x60, 0x2a, bits >> 16, bits & 0xffff];
                    replace_words(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        argument_start,
                        0,
                        &value,
                    );
                    self.out.push(0x7c); // native ListSet(value, list, key)
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                let target = reference(&mut self.reader, ids)?;
                if let Variable::Field(field) = target {
                    emit_float_field_assignment(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        start,
                        field,
                        bits,
                    )?;
                    self.state.last_reference_push = None;
                    self.state.cached_world_owner = false;
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                self.out
                    .extend([0x60, 0x2a, bits >> 16, bits & 0xffff, 0x34]);
                emit_tracked_reference(
                    &mut self.out,
                    &target,
                    &mut self.state.cached_world_owner,
                    &mut self.state.pending_world_ref,
                );
            }
            0x9b => {
                // Repeated PushFloat + AssignNoPush pairs, packed by
                // OpenDream's compactor.
                let count = self.reader.word()?;
                if count > 255 {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "NPushFloatAssign count exceeds 255".into(),
                    });
                }
                for _ in 0..count {
                    let bits = self.reader.word()?;
                    if self.reader.code.get(self.reader.at) == Some(&7) {
                        self.reader.byte()?;
                        let at = constructor_argument_start(&self.out, 2).ok_or_else(|| {
                            LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason:
                                "packed indexed float assignment has unknown list/key stack effects"
                                    .into(),
                        }
                        })?;
                        let value = [0x60, 0x2a, bits >> 16, bits & 0xffff];
                        replace_words(
                            &mut self.out,
                            &mut self.offsets,
                            &mut self.fixups,
                            at,
                            0,
                            &value,
                        );
                        self.out.push(0x7c);
                        continue;
                    }
                    let target = reference(&mut self.reader, ids)?;
                    if let Variable::Field(field) = target {
                        emit_float_field_assignment(
                            &mut self.out,
                            &mut self.offsets,
                            &mut self.fixups,
                            start,
                            field,
                            bits,
                        )?;
                        self.state.last_reference_push = None;
                        self.state.cached_world_owner = false;
                        continue;
                    }
                    self.out
                        .extend([0x60, 0x2a, bits >> 16, bits & 0xffff, 0x34]);
                    emit_tracked_reference(
                        &mut self.out,
                        &target,
                        &mut self.state.cached_world_owner,
                        &mut self.state.pending_world_ref,
                    );
                }
            }
            0x03 => {
                let old_string = self.reader.word()?;
                if self.reader.code.get(self.reader.at) == Some(&0x02)
                    && self.reader.code.get(self.reader.at + 5) == Some(&0x2e)
                {
                    let old_type = u32::from_le_bytes(
                        self.reader.code[self.reader.at + 1..self.reader.at + 5]
                            .try_into()
                            .unwrap(),
                    );
                    let mode =
                        *self
                            .reader
                            .code
                            .get(self.reader.at + 6)
                            .ok_or_else(|| LowerError {
                                kind: LowerErrorKind::TruncatedOperand,
                                offset: start,
                                reason: "truncated modified constructor mode".into(),
                            })?;
                    let count = u32::from_le_bytes(
                        self.reader
                            .code
                            .get(self.reader.at + 7..self.reader.at + 11)
                            .ok_or_else(|| LowerError {
                                kind: LowerErrorKind::TruncatedOperand,
                                offset: start,
                                reason: "truncated modified constructor count".into(),
                            })?
                            .try_into()
                            .unwrap(),
                    );
                    if !(matches!((mode, count), (0, 0))
                        || mode == 1 && (1..=255).contains(&count)
                        || mode == 2 && (2..=510).contains(&count) && count % 2 == 0
                        || (mode, count) == (3, 1))
                    {
                        return Err(LowerError {
                            kind: LowerErrorKind::UnsupportedConstruct,
                            offset: start,
                            reason: "modified constructor argument mode/count is unsupported"
                                .into(),
                        });
                    }
                    let instance = mapped(
                        ids.modified_instance(old_type, old_string),
                        start,
                        "modified instance prototype",
                    )?;
                    if count > 0 {
                        let args_at = constructor_argument_start(&self.out, count as usize)
                            .ok_or_else(|| LowerError {
                                kind: LowerErrorKind::UnsupportedConstruct,
                                offset: start,
                                reason:
                                    "modified constructor arguments have unsupported stack effects"
                                        .into(),
                            })?;
                        let mut prototype = Vec::new();
                        push_value(&mut prototype, 41, instance);
                        replace_words(
                            &mut self.out,
                            &mut self.offsets,
                            &mut self.fixups,
                            args_at,
                            0,
                            &prototype,
                        );
                    } else {
                        push_value(&mut self.out, 41, instance);
                    }
                    self.offsets
                        .insert(self.reader.at as u32, self.out.len() as u32);
                    self.reader.at += 5; // PushType + original type ID
                    self.offsets
                        .insert(self.reader.at as u32, self.out.len() as u32);
                    self.reader.at += 6; // CreateObject + argument mode/count
                    if mode == 2 {
                        self.out.extend([0xc8, count / 2, 0xcf]);
                    } else if mode == 3 {
                        self.out.push(0xcf);
                    } else {
                        self.out.extend([0x01, count]);
                    }
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                let first = mapped(ids.string(old_string), start, "string")?;
                if self.reader.code.get(self.reader.at) == Some(&0x32) {
                    let switch_at = self.out.len();
                    let mut cases = Vec::new();
                    let mut string_id = first;
                    loop {
                        if self.reader.byte()? != 0x32 {
                            return Err(LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "string switch lacks SwitchCase".into(),
                            });
                        }
                        cases.push((string_id, self.reader.word()?));
                        if self.reader.code.get(self.reader.at) == Some(&0x03)
                            && self.reader.code.get(self.reader.at + 5) == Some(&0x32)
                        {
                            self.offsets.insert(self.reader.at as u32, switch_at as u32);
                            self.reader.at += 1;
                            string_id = mapped(ids.string(self.reader.word()?), start, "string")?;
                        } else {
                            break;
                        }
                    }
                    if self.reader.code.get(self.reader.at) != Some(&0x51) {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "string switch lacks Pop".into(),
                        });
                    }
                    self.offsets.insert(self.reader.at as u32, switch_at as u32);
                    self.reader.at += 1;
                    let default = if self.reader.code.get(self.reader.at) == Some(&0x0e)
                        && !authored_control_jump(ids, self.reader.code, self.reader.at)
                    {
                        self.offsets.insert(self.reader.at as u32, switch_at as u32);
                        self.reader.at += 1;
                        self.reader.word()?
                    } else {
                        self.reader.at as u32
                    };
                    self.out.extend([0x78, cases.len() as u32]);
                    for (id, target) in cases {
                        self.out.extend(
                            Value {
                                tag_word: 6 | ((id >> 16) << 8),
                                data_word: id & 0xffff,
                                extra_word: None,
                            }
                            .encode(),
                        );
                        let at = self.out.len();
                        self.out.push(0);
                        self.fixups.push(Fixup {
                            at,
                            target,
                            source: start,
                        });
                    }
                    let at = self.out.len();
                    self.out.push(0);
                    self.fixups.push(Fixup {
                        at,
                        target: default,
                        source: start,
                    });
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                push_value(&mut self.out, 6, first);
            }
            0x8a => {
                // PushStringFloat, used for associative-list key/value
                push_value(
                    &mut self.out,
                    6,
                    mapped(ids.string(self.reader.word()?), start, "string")?,
                );
                let bits = self.reader.word()?;
                self.out.extend([0x60, 0x2a, bits >> 16, bits & 0xffff]);
            }
            0x8d | 0x93 => {
                // SwitchOnFloat / SwitchOnString case chain
                let switch_at = self.out.len();
                let mut cases = Vec::new();
                let mut ranges = Vec::new();
                let mut case_op = op;
                loop {
                    if case_op == 0x88 {
                        if self.reader.word()? != 2 {
                            return Err(LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "switch range requires two bounds".into(),
                            });
                        }
                        let lo = self.reader.word()?;
                        let hi = self.reader.word()?;
                        if self.reader.byte()? != 0x05 {
                            return Err(LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "switch range lacks SwitchCaseRange".into(),
                            });
                        }
                        ranges.push((lo, hi, self.reader.word()?));
                    } else {
                        let value = if case_op == 0x11 {
                            self.reader.byte()?; // paired PushNull + SwitchCase
                            Value {
                                tag_word: 0,
                                data_word: 0,
                                extra_word: None,
                            }
                        } else if case_op == 0x8d {
                            let bits = self.reader.word()?;
                            Value {
                                tag_word: 0x2a,
                                data_word: bits >> 16,
                                extra_word: Some(bits & 0xffff),
                            }
                        } else {
                            let id = mapped(ids.string(self.reader.word()?), start, "string")?;
                            Value {
                                tag_word: 6 | ((id >> 16) << 8),
                                data_word: id & 0xffff,
                                extra_word: None,
                            }
                        };
                        let target = self.reader.word()?;
                        cases.push((value, target));
                    }
                    let next = self.reader.code.get(self.reader.at).copied();
                    let next_range = self.reader.code.get(self.reader.at..self.reader.at + 5)
                        == Some(&[0x88, 2, 0, 0, 0])
                        && self.reader.code.get(self.reader.at + 13) == Some(&0x05);
                    let next_null = self.reader.code.get(self.reader.at..self.reader.at + 2)
                        == Some(&[0x11, 0x32]);
                    if next != Some(0x8d) && next != Some(0x93) && !next_range && !next_null {
                        break;
                    }
                    self.offsets.insert(self.reader.at as u32, switch_at as u32);
                    case_op = self.reader.byte()?;
                }
                if self.reader.code.get(self.reader.at) != Some(&0x51) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "switch case chain lacks Pop before default".into(),
                    });
                }
                self.offsets.insert(self.reader.at as u32, switch_at as u32);
                self.reader.byte()?; // Pop switch expression
                let default = if self.reader.code.get(self.reader.at) == Some(&0x0e)
                    && !authored_control_jump(ids, self.reader.code, self.reader.at)
                {
                    self.offsets.insert(self.reader.at as u32, switch_at as u32);
                    self.reader.byte()?; // Jump default
                    self.reader.word()?
                } else {
                    self.reader.at as u32 // Default body starts immediately after Pop.
                };
                if ranges.is_empty() {
                    self.out.extend([0x78, cases.len() as u32]);
                } else {
                    self.out.extend([0x7a, ranges.len() as u32]);
                    for (lo, hi, target) in ranges {
                        self.out
                            .extend([0x2a, lo >> 16, lo & 0xffff, 0x2a, hi >> 16, hi & 0xffff]);
                        let at = self.out.len();
                        self.out.push(0);
                        self.fixups.push(Fixup {
                            at,
                            target,
                            source: start,
                        });
                    }
                    self.out.push(cases.len() as u32);
                }
                for (value, target) in cases {
                    self.out.extend(value.encode());
                    let at = self.out.len();
                    self.out.push(0);
                    self.fixups.push(Fixup {
                        at,
                        target,
                        source: start,
                    });
                }
                let at = self.out.len();
                self.out.push(0);
                self.fixups.push(Fixup {
                    at,
                    target: default,
                    source: start,
                });
            }
            0x04 => {
                // FormatString(template ID, interpolation count)
                let template = mapped(ids.string(self.reader.word()?), start, "string")?;
                let count = self.reader.word()?;
                self.out.extend([0x02, template, count]);
                self.state.last_was_format = true;
            }
            0x21 => push_value(
                &mut self.out,
                12,
                mapped(ids.resource(self.reader.word()?), start, "resource")?,
            ),
            0x26 => push_value(
                &mut self.out,
                38,
                mapped(ids.proc_id(self.reader.word()?), start, "proc")?,
            ),
            0x9f => {
                // Pinned OpenDream exporter: modified type constant. Native
                // stores its preallocated instance prototype as value tag 41.
                let old_type = self.reader.word()?;
                let old_string = self.reader.word()?;
                push_value(
                    &mut self.out,
                    41,
                    mapped(
                        ids.modified_instance(old_type, old_string),
                        start,
                        "modified type instance",
                    )?,
                );
            }
            0x02 => {
                let old = self.reader.word()?;
                let tag = ids.type_tag(old).ok_or_else(|| LowerError {
                    kind: LowerErrorKind::UnresolvedSymbol,
                    offset: start,
                    reason: "unresolved type tag".into(),
                })?;
                let first = mapped(ids.type_id(old), start, "type")?;
                if self.reader.code.get(self.reader.at) == Some(&0x32) {
                    // A switch on type paths is a native Switch table whose
                    // case values retain each type's BYOND value tag.
                    let switch_at = self.out.len();
                    let mut cases = Vec::new();
                    let mut case_tag = tag;
                    let mut case_id = first;
                    loop {
                        if self.reader.byte()? != 0x32 {
                            return Err(LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "type switch lacks SwitchCase".into(),
                            });
                        }
                        cases.push((case_tag, case_id, self.reader.word()?));
                        if self.reader.code.get(self.reader.at) == Some(&0x02)
                            && self.reader.code.get(self.reader.at + 5) == Some(&0x32)
                        {
                            self.offsets.insert(self.reader.at as u32, switch_at as u32);
                            self.reader.at += 1;
                            let old = self.reader.word()?;
                            case_tag = ids.type_tag(old).ok_or_else(|| LowerError {
                                kind: LowerErrorKind::UnresolvedSymbol,
                                offset: start,
                                reason: "unresolved switch type tag".into(),
                            })?;
                            case_id = mapped(ids.type_id(old), start, "switch type")?;
                        } else {
                            break;
                        }
                    }
                    if self.reader.code.get(self.reader.at) != Some(&0x51) {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "type switch lacks Pop".into(),
                        });
                    }
                    self.offsets.insert(self.reader.at as u32, switch_at as u32);
                    self.reader.at += 1;
                    let default = if self.reader.code.get(self.reader.at) == Some(&0x0e)
                        && !authored_control_jump(ids, self.reader.code, self.reader.at)
                    {
                        self.offsets.insert(self.reader.at as u32, switch_at as u32);
                        self.reader.at += 1;
                        self.reader.word()?
                    } else {
                        self.reader.at as u32
                    };
                    self.out.extend([0x78, cases.len() as u32]);
                    for (tag, id, target) in cases {
                        self.out.extend(
                            Value {
                                tag_word: tag as u32 | ((id >> 16) << 8),
                                data_word: id & 0xffff,
                                extra_word: None,
                            }
                            .encode(),
                        );
                        let at = self.out.len();
                        self.out.push(0);
                        self.fixups.push(Fixup {
                            at,
                            target,
                            source: start,
                        });
                    }
                    let at = self.out.len();
                    self.out.push(0);
                    self.fixups.push(Fixup {
                        at,
                        target: default,
                        source: start,
                    });
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                push_value(&mut self.out, tag, first);
            }
            0x95 => {
                // IsTypeDirect folds PushType; IsType. Preserve the original
                // stack order by expanding that pair for DreamDaemon.
                let old = self.reader.word()?;
                let tag = ids.type_tag(old).ok_or_else(|| LowerError {
                    kind: LowerErrorKind::UnresolvedSymbol,
                    offset: start,
                    reason: "unresolved type tag".into(),
                })?;
                push_value(&mut self.out, tag, mapped(ids.type_id(old), start, "type")?);
                self.out.push(0x7d);
            }
            0x5f => {
                let id = mapped(ids.global_vars_variable(), start, "GlobalVars variable")?;
                let at = self.out.len();
                self.out.extend([0x33, 0xffdb, id]);
                self.state.last_reference_push = Some((at, Variable::Global(id)));
            }
            0x5c => self.out.extend([0x6c, self.reader.word()?]), // addtext(...)
            0x07 => {
                let mode = self.reader.byte()?;
                let count = self.reader.word()?;
                match (mode, count) {
                    (1, 3) => self.out.push(0xbb),
                    (1, 4) => self.out.push(0x113),
                    (1, 5) => self.out.push(0x161),
                    _ => {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "Rgb argument mode/count has no verified lowering".into(),
                        })
                    }
                }
            }
            0xa9 => {
                // Pinned Field compound/unary operations evaluate RHS first,
                // then the owner. Direct references remain late native reads.
                let operation = self.reader.byte()?;
                let field = mapped(ids.string(self.reader.word()?), start, "string")?;
                let discard = match self.reader.byte()? {
                    0 => false,
                    1 => true,
                    _ => {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "native Field operation discard flag is invalid".into(),
                        })
                    }
                };
                let native_op = match (operation, discard) {
                    (0x56 | 0x62, true) => 0x66,
                    (0x57 | 0x63, true) => 0x67,
                    (0x56, false) => 0x63,
                    (0x57, false) => 0x65,
                    (0x62, false) => 0x62,
                    (0x63, false) => 0x64,
                    (0x1a, _) => 0x45,
                    (0x1f, _) => 0x46,
                    (0x0b, _) => 0x47,
                    (0x17, _) => 0x48,
                    (0x39, _) => 0x49,
                    (0x33, _) => 0x4a,
                    (0x2d, _) => 0x4b,
                    (0x29, _) => 0x4c,
                    (0x6d, _) => 0x4d,
                    (0x6e, _) => 0x4e,
                    (0x61, _) => 0x177,
                    _ => {
                        return Err(LowerError {
                            kind: LowerErrorKind::UnsupportedConstruct,
                            offset: start,
                            reason: format!(
                                "native Field operation {operation:#04x} is unsupported"
                            ),
                        })
                    }
                };
                let direct = if !self.fixups.iter().any(|fixup| fixup.target == start as u32) {
                    constructor_argument_start(&self.out, 1).and_then(|at| {
                        let items = crate::bytecode::decode(&self.out[at..]).ok()?;
                        let executable: Vec<_> = items
                            .iter()
                            .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
                            .collect();
                        let [item] = executable.as_slice() else {
                            return None;
                        };
                        if item.opcode != 0x33 {
                            return None;
                        }
                        Variable::decode(&item.operands)
                            .ok()
                            .map(|(reference, _)| (at + item.offset, reference))
                    })
                } else {
                    None
                };
                let target = if let Some((at, reference)) = direct {
                    // Preserve source markers around the folded owner read.
                    let old_len = 1 + reference.encode().len();
                    replace_words(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        at,
                        old_len,
                        &[],
                    );
                    append_field(reference, field)
                } else {
                    self.out.extend([0x34, 0xffd8]);
                    Variable::Field(field)
                };
                self.out.push(native_op);
                emit_tracked_reference(
                    &mut self.out,
                    &target,
                    &mut self.state.cached_world_owner,
                    &mut self.state.pending_world_ref,
                );
                if !discard && !matches!(operation, 0x56 | 0x57 | 0x62 | 0x63) {
                    self.out.push(0x13f);
                }
                self.state.last_reference_push = None;
                self.state.cached_world_owner = false;
                if let Some(pending) = &mut self.state.pending_world_ref {
                    pending.rhs_changed_cache = true;
                }
            }
            _ => return Ok(OpcodeFlow::Unhandled),
        }
        Ok(OpcodeFlow::Advance)
    }
}
