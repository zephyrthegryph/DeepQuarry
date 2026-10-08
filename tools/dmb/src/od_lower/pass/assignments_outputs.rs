use super::*;

impl<R: SymbolResolver> PassState<'_, R> {
    pub(super) fn lower_assignments_outputs(
        &mut self,
        start: usize,
        op: u8,
        _follows_format: bool,
    ) -> Result<OpcodeFlow, LowerError> {
        let code = self.inputs.code;
        let ids = self.inputs.ids;
        let is_initializer = self.inputs.is_initializer;
        match op {
            0x88 => {
                // PushNFloats
                let count = self.reader.word()?;
                if count as usize > self.reader.code.len().saturating_sub(self.reader.at) / 4 {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "PushNFloats count exceeds available operands".into(),
                    });
                }
                if count == 2
                    && self.reader.code.get(self.reader.at + 8) == Some(&0x5b)
                    && self.state.last_reference_push.is_some()
                {
                    let (value_at, value) =
                        self.state
                            .last_reference_push
                            .take()
                            .ok_or_else(|| LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "IsInRange requires a direct value reference".into(),
                            })?;
                    replace_words(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        value_at,
                        1 + value.encode().len(),
                        &[],
                    );
                    for _ in 0..2 {
                        let bits = self.reader.word()?;
                        self.out.extend([0x60, 0x2a, bits >> 16, bits & 0xffff]);
                    }
                    self.offsets
                        .insert(self.reader.at as u32, self.out.len() as u32);
                    self.reader.byte()?; // IsInRange
                    self.out.push(0x33);
                    self.out.extend(value.encode());
                    self.out.extend([0xa9, 11, 0x36]);
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                if count == 2 && self.reader.code.get(self.reader.at + 8) == Some(&0x05) {
                    // OpenDream emits each range as two float pushes and
                    // SwitchCaseRange; BYOND stores bounds in SwitchRange.
                    let switch_at = self.out.len();
                    let mut ranges = Vec::new();
                    let mut exact = Vec::new();
                    loop {
                        let lo = self.reader.word()?;
                        let hi = self.reader.word()?;
                        if self.reader.byte()? != 0x05 {
                            return Err(LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "switch range lacks SwitchCaseRange".into(),
                            });
                        }
                        let target = self.reader.word()?;
                        ranges.push((lo, hi, target));
                        // OpenDream may interleave exact and range cases in
                        // source order. Native SwitchRange keeps separate
                        // range and exact tables, so collect both until Pop.
                        loop {
                            if self.reader.code.get(self.reader.at) == Some(&0x8d) {
                                self.offsets.insert(self.reader.at as u32, switch_at as u32);
                                self.reader.byte()?;
                                let bits = self.reader.word()?;
                                let target = self.reader.word()?;
                                exact.push((
                                    Value {
                                        tag_word: 0x2a,
                                        data_word: bits >> 16,
                                        extra_word: Some(bits & 0xffff),
                                    },
                                    target,
                                ));
                            } else if self.reader.code.get(self.reader.at) == Some(&0x93) {
                                self.offsets.insert(self.reader.at as u32, switch_at as u32);
                                self.reader.byte()?;
                                let id = mapped(
                                    ids.string(self.reader.word()?),
                                    start,
                                    "switch string",
                                )?;
                                let target = self.reader.word()?;
                                exact.push((
                                    Value {
                                        tag_word: 6 | ((id >> 16) << 8),
                                        data_word: id & 0xffff,
                                        extra_word: None,
                                    },
                                    target,
                                ));
                            } else if self.reader.code.get(self.reader.at..self.reader.at + 2)
                                == Some(&[0x11, 0x32])
                            {
                                self.offsets.insert(self.reader.at as u32, switch_at as u32);
                                self.reader.at += 2;
                                let target = self.reader.word()?;
                                exact.push((
                                    Value {
                                        tag_word: 0,
                                        data_word: 0,
                                        extra_word: None,
                                    },
                                    target,
                                ));
                            } else {
                                break;
                            }
                        }
                        if self.reader.code.get(self.reader.at..self.reader.at + 5)
                            == Some(&[0x88, 2, 0, 0, 0])
                            && self.reader.code.get(self.reader.at + 13) == Some(&0x05)
                        {
                            self.offsets.insert(self.reader.at as u32, switch_at as u32);
                            self.reader.at += 5;
                            continue;
                        }
                        break;
                    }
                    if self.reader.code.get(self.reader.at) != Some(&0x51) {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "switch range lacks Pop default".into(),
                        });
                    }
                    self.offsets.insert(self.reader.at as u32, switch_at as u32);
                    self.reader.byte()?;
                    let default = if self.reader.code.get(self.reader.at) == Some(&0x0e)
                        && !authored_control_jump(ids, self.reader.code, self.reader.at)
                    {
                        self.offsets.insert(self.reader.at as u32, switch_at as u32);
                        self.reader.byte()?;
                        self.reader.word()?
                    } else {
                        // A terminal `else` follows the removed switch
                        // selector directly, without an intermediate jump.
                        self.reader.at as u32
                    };
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
                    self.out.push(exact.len() as u32);
                    for (value, target) in exact {
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
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                for _ in 0..count {
                    let bits = self.reader.word()?;
                    self.out.extend([0x60, 0x2a, bits >> 16, bits & 0xffff]);
                }
            }
            0x8f..=0x92 => {
                // OpenDream's compact list constructors carry the same
                // operands as their corresponding PushN opcode plus CreateList.
                let count = self.reader.word()?;
                if (count as usize) > self.reader.code.len() - self.reader.at {
                    return Err(LowerError {
                        kind: LowerErrorKind::TruncatedOperand,
                        offset: start,
                        reason: "truncated compact list values".into(),
                    });
                }
                for _ in 0..count {
                    match op {
                        0x8f => {
                            let bits = self.reader.word()?;
                            self.out.extend([0x60, 0x2a, bits >> 16, bits & 0xffff]);
                        }
                        0x90 => push_value(
                            &mut self.out,
                            6,
                            mapped(ids.string(self.reader.word()?), start, "string")?,
                        ),
                        0x91 => {
                            self.out.push(0x33);
                            let target = reference(&mut self.reader, ids)?;
                            emit_tracked_reference(
                                &mut self.out,
                                &target,
                                &mut self.state.cached_world_owner,
                                &mut self.state.pending_world_ref,
                            );
                        }
                        0x92 => push_value(
                            &mut self.out,
                            12,
                            mapped(ids.resource(self.reader.word()?), start, "resource")?,
                        ),
                        _ => unreachable!(),
                    }
                }
                self.out.extend([0x1a, count]);
            }
            0x8c => {
                // PushNStrings
                let count = self.reader.word()?;
                if count as usize > self.reader.code.len().saturating_sub(self.reader.at) / 4 {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "PushNStrings count exceeds available operands".into(),
                    });
                }
                for _ in 0..count {
                    push_value(
                        &mut self.out,
                        6,
                        mapped(ids.string(self.reader.word()?), start, "string")?,
                    );
                }
            }
            0x8e => {
                // Packed PushStringFloat pairs.
                let count = self.reader.word()?;
                if count > 255 {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "PushNOfStringFloats count exceeds 255".into(),
                    });
                }
                for _ in 0..count {
                    push_value(
                        &mut self.out,
                        6,
                        mapped(ids.string(self.reader.word()?), start, "string")?,
                    );
                    let bits = self.reader.word()?;
                    self.out.extend([0x60, 0x2a, bits >> 16, bits & 0xffff]);
                }
            }
            0x89 => {
                // PushNResources
                let count = self.reader.word()?;
                if count as usize > self.reader.code.len().saturating_sub(self.reader.at) / 4 {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "PushNResources count exceeds available operands".into(),
                    });
                }
                for _ in 0..count {
                    push_value(
                        &mut self.out,
                        12,
                        mapped(ids.resource(self.reader.word()?), start, "resource")?,
                    );
                }
            }
            0x09 => {
                if ids.native_store_reload(start) {
                    if !matches!(self.reader.code.get(self.reader.at), Some(8 | 9)) {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "native store/reload annotation requires a local or argument"
                                .into(),
                        });
                    }
                    let target = reference(&mut self.reader, ids)?;
                    self.out.push(0x34);
                    self.out.extend(target.encode());
                    let get_at = self.out.len();
                    self.out.push(0x33);
                    self.out.extend(target.encode());
                    self.state.last_reference_push = Some((get_at, target));
                    self.store_reload_boundaries.insert(start as u32);
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                if self
                    .pending_indexed_logical
                    .last()
                    .is_some_and(|(target, _, _)| {
                        (self.reader.code.get(self.reader.at) == Some(&7)
                            && *target == (self.reader.at + 1) as u32)
                            || (self.reader.code.get(self.reader.at) == Some(&12)
                                && *target == (self.reader.at + 5) as u32)
                    })
                {
                    if self.reader.code.get(self.reader.at) == Some(&7) {
                        self.reader.byte()?;
                    } else {
                        let field = reference(&mut self.reader, ids)?;
                        let (_, _, setter) = self.pending_indexed_logical.last().unwrap();
                        let mut setter_field = setter;
                        while let Variable::SetCache(_, field) = setter_field {
                            setter_field = field.as_ref();
                        }
                        if setter_field != &field {
                            return Err(LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "logical field assignment does not match tested field"
                                    .into(),
                            });
                        }
                    }
                    let (_, source, variable) = self.pending_indexed_logical.pop().unwrap();
                    let frame_at = self
                        .fixups
                        .iter()
                        .find(|fixup| fixup.source == source)
                        .unwrap()
                        .at
                        + 1;
                    let rhs =
                        crate::bytecode::decode(&self.out[frame_at + 1..]).map_err(|error| {
                            LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: error.reason,
                            }
                        })?;
                    let direct_rhs = rhs.iter().all(|item| {
                        matches!(item.opcode, 0x50 | 0x60 | 0x84 | 0x85)
                            || matches!(item.opcode, 0x33..=0x35)
                                && Variable::decode(&item.operands).is_ok_and(|(var, _)| {
                                    matches!(
                                        var,
                                        Variable::Local(_)
                                            | Variable::Arg(_)
                                            | Variable::Global(_)
                                            | Variable::Src
                                            | Variable::Usr
                                    )
                                })
                    });
                    if direct_rhs {
                        replace_words(
                            &mut self.out,
                            &mut self.offsets,
                            &mut self.fixups,
                            frame_at,
                            1,
                            &[],
                        );
                    } else {
                        self.out.push(0x143);
                    }
                    let discard = self.reader.code.get(self.reader.at) == Some(&0x51)
                        && !self.fixups.iter().any(|fixup| {
                            fixup.target == self.reader.at as u32
                                && branch_retains_discarded_value(fixup, code, &self.out)
                        });
                    self.out.push(if discard { 0x34 } else { 0x35 });
                    self.out.extend(variable.encode());
                    if self.computed_safe_logical.remove(&source) {
                        let cache_join = u32::MAX - source as u32;
                        self.offsets.insert(cache_join, self.out.len() as u32);
                        self.fixups
                            .iter_mut()
                            .find(|fixup| fixup.source == source)
                            .unwrap()
                            .target = cache_join;
                        self.out.push(0x143);
                        self.offsets
                            .insert(self.reader.at as u32, self.out.len() as u32);
                    }
                    if discard {
                        self.offsets
                            .insert(self.reader.at as u32, self.out.len() as u32);
                        self.reader.byte()?;
                    }
                    if self.safe_logical_continuations.remove(&source) {
                        if let Some((at, discard, body)) = self.safe.pending_safe_lvalue_stack.pop()
                        {
                            self.safe.pending_safe_lvalue_at = Some((at, discard));
                            self.safe.pending_safe_lvalue_body = body;
                        }
                    }
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                if self.reader.code.get(self.reader.at) == Some(&7) {
                    self.reader.byte()?;
                    let mut end = self.out.len();
                    let mut spans = Vec::new();
                    for _ in 0..3 {
                        let at =
                            constructor_argument_start(&self.out[..end], 1).ok_or_else(|| {
                                LowerError {
                                    kind: LowerErrorKind::MalformedControlFlow,
                                    offset: start,
                                    reason:
                                        "indexed assignment expression has unknown stack effects"
                                            .into(),
                                }
                            })?;
                        spans.push((at, end));
                        end = at;
                    }
                    spans.reverse();
                    let direct_targets = spans[..2].iter().all(|(at, end)| {
                        crate::bytecode::decode(&self.out[*at..*end])
                            .is_ok_and(|items| items.len() == 1 && items[0].opcode == 0x33)
                    });
                    let nonbranching_value = crate::bytecode::decode(
                        &self.out[spans[2].0..spans[2].1],
                    )
                    .is_ok_and(|items| {
                        items.iter().all(|item| {
                                !matches!(item.opcode, 0x0f..=0x11 | 0xb2..=0xb4 | 0x13d | 0x13e)
                            })
                    });
                    if !direct_targets || !nonbranching_value {
                        return Err(LowerError {
            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason:
                                "indexed assignment expression requires direct list/key and a nonbranching value"
                                    .into(),
                        });
                    }
                    let mut replacement = self.out[spans[2].0..spans[2].1].to_vec();
                    replacement.push(0x13c); // retain assigned value for expression result
                    for (at, end) in [spans[0], spans[1]] {
                        replacement.extend_from_slice(&self.out[at..end]);
                    }
                    replacement.push(0x7c);
                    let old_len = self.out.len() - spans[0].0;
                    replace_words(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        spans[0].0,
                        old_len,
                        &replacement,
                    );
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                let target = reference(&mut self.reader, ids)?;
                let discard = self.reader.code.get(self.reader.at) == Some(&0x51)
                    && !self.fixups.iter().any(|fixup| {
                        fixup.target == self.reader.at as u32
                            && branch_retains_discarded_value(fixup, code, &self.out)
                    })
                    && self.inputs.source_info.is_none_or(|events| {
                        events.iter().all(|event| event.offset != self.reader.at)
                    });
                if let Variable::Field(field) = target {
                    let rhs_at =
                        constructor_argument_start(&self.out, 1).ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "field assignment expression value has unknown stack effects"
                                .into(),
                        })?;
                    let owner_at =
                        constructor_argument_start(&self.out[..rhs_at], 1).ok_or_else(|| {
                            LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason:
                                    "field assignment expression receiver has unknown stack effects"
                                        .into(),
                            }
                        })?;
                    let owner_items = crate::bytecode::decode(&self.out[owner_at..rhs_at])
                        .map_err(|error| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: error.reason,
                        })?;
                    let direct_owner = if let [item] = owner_items.as_slice() {
                        if item.opcode == 0x33 {
                            Variable::decode(&item.operands)
                                .ok()
                                .map(|(owner, _)| owner)
                                .filter(|owner| {
                                    matches!(
                                        owner,
                                        Variable::Arg(_)
                                            | Variable::Local(_)
                                            | Variable::Global(_)
                                            | Variable::Src
                                            | Variable::Usr
                                            | Variable::World
                                            | Variable::Dot
                                            | Variable::SetCache(_, _)
                                    )
                                })
                        } else {
                            None
                        }
                    } else {
                        None
                    };
                    let old_end = self.out.len();
                    let rhs_length = old_end - rhs_at;
                    let computed_owner = direct_owner.is_none();
                    let mut replacement = self.out[rhs_at..old_end].to_vec();
                    let retained_value = usize::from(computed_owner && !discard);
                    if let Some(owner) = direct_owner {
                        replacement.push(if discard { 0x34 } else { 0x35 });
                        replacement.extend(append_field(owner, field).encode());
                    } else {
                        if !discard {
                            replacement.push(0x13c);
                        }
                        replacement.extend_from_slice(&self.out[owner_at..rhs_at]);
                        replacement.extend([0x34, 0xffd8, 0x34, field]);
                    }
                    let moved = |old: usize| {
                        if old >= rhs_at {
                            owner_at + old - rhs_at
                        } else if computed_owner {
                            owner_at + rhs_length + retained_value + old - owner_at
                        } else {
                            owner_at
                        }
                    };
                    let previous_offsets: Vec<_> = self
                        .offsets
                        .iter()
                        .filter(|(_, &position)| (owner_at..old_end).contains(&(position as usize)))
                        .map(|(&source, &position)| (source, position))
                        .collect();
                    let previous_fixups =
                        self.fixups.iter().map(|fixup| fixup.at).collect::<Vec<_>>();
                    replace_words(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        owner_at,
                        old_end - owner_at,
                        &replacement,
                    );
                    for (key, old) in previous_offsets {
                        if old as usize >= owner_at && (old as usize) < old_end {
                            self.offsets.insert(key, moved(old as usize) as u32);
                        }
                    }
                    for (fixup, old) in self.fixups.iter_mut().zip(previous_fixups) {
                        if old >= owner_at && old < old_end {
                            fixup.at = moved(old);
                        }
                    }
                    self.offsets
                        .insert(start as u32, (owner_at + rhs_length) as u32);
                    if discard {
                        self.offsets
                            .insert(self.reader.at as u32, self.out.len() as u32);
                        self.reader.byte()?;
                    }
                    self.state.last_reference_push = None;
                    self.state.cached_world_owner = false;
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                self.out.push(if discard { 0x34 } else { 0x35 });
                emit_tracked_reference(
                    &mut self.out,
                    &target,
                    &mut self.state.cached_world_owner,
                    &mut self.state.pending_world_ref,
                );
                if discard {
                    self.offsets
                        .insert(self.reader.at as u32, self.out.len() as u32);
                    self.reader.byte()?;
                }
            }
            0x85 => {
                if (AssignmentLowering {
                    code,
                    reader: &mut self.reader,
                    ids,
                    start,
                    out: &mut self.out,
                    offsets: &mut self.offsets,
                    fixups: &mut self.fixups,
                    state: &mut self.state,
                    safe: &mut self.safe,
                    is_initializer,
                })
                .lower()?
                {
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
            }
            0x97 => {
                let value = reference(&mut self.reader, ids)?;
                if value == Variable::Dot {
                    self.out.push(0); // End returns the procedure's implicit Dot value.
                } else {
                    self.out.push(0x33);
                    self.out.extend(value.encode());
                    self.out.push(0x12);
                }
            }
            op if emit_stack_operation(
                op,
                self.reader.code.get(self.reader.at),
                self.reader.at,
                &self.fixups,
                &mut self.out,
            ) => {}
            0x81 => {
                reorder_log_arguments(
                    &mut self.out,
                    self.reader.code,
                    &mut self.offsets,
                    &mut self.fixups,
                    start,
                )?;
                self.out.push(0x32);
            }
            0x20 => {
                self.out.push(0x0c);
                if ids.native_delete_src(start) {
                    self.out.push(0x00); // Native del(src) terminates this proc path.
                }
            }
            0x1c => {
                // `source >> destination` reads into the destination ref.
                let source = if self.reader.code.get(self.reader.at) == Some(&7) {
                    self.reader.byte()?;
                    None
                } else {
                    Some(reference(&mut self.reader, ids)?)
                };
                let destination = if self.reader.code.get(self.reader.at) == Some(&7) {
                    self.reader.byte()?;
                    None
                } else {
                    Some(reference(&mut self.reader, ids)?)
                };
                let source_at = if source.is_none() {
                    constructor_argument_start(&self.out, 2).ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "indexed read source has unknown stack effects".into(),
                    })?
                } else {
                    self.out.len()
                };
                let destination_at = if destination.is_none() {
                    constructor_argument_start(&self.out[..source_at], 2).ok_or_else(|| {
                        LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "indexed read destination has unknown stack effects".into(),
                        }
                    })?
                } else if matches!(destination, Some(Variable::Field(_))) {
                    constructor_argument_start(&self.out[..source_at], 1).ok_or_else(|| {
                        LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "read field destination has unknown owner stack effects".into(),
                        }
                    })?
                } else {
                    source_at
                };
                if self
                    .fixups
                    .iter()
                    .any(|fixup| fixup.at >= destination_at && fixup.at < self.out.len())
                {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "read operand branches need relocation".into(),
                    });
                }
                let mut replacement = Vec::new();
                if let Some(source) = source {
                    replacement.push(0x33);
                    replacement.extend(source.encode());
                } else {
                    replacement.extend_from_slice(&self.out[source_at..]);
                    replacement.push(0xb0); // Index: savefile slot, not ListGet
                }
                replacement.push(0xaf);
                if let Some(destination) = destination {
                    if let Variable::Field(field) = destination {
                        let owner = crate::bytecode::decode(&self.out[destination_at..source_at])
                            .ok()
                            .filter(|items| items.len() == 1 && items[0].opcode == 0x33)
                            .and_then(|items| {
                                Variable::decode(&items[0].operands)
                                    .ok()
                                    .map(|(owner, _)| owner)
                            })
                            .ok_or_else(|| LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "read field destination requires a direct owner".into(),
                            })?;
                        replacement.push(0x34);
                        replacement.extend(append_field(owner, field).encode());
                    } else {
                        replacement.push(0x34);
                        replacement.extend(destination.encode());
                    }
                } else {
                    replacement.extend_from_slice(&self.out[destination_at..source_at]);
                    replacement.push(0x7c); // ListSet consumes the Read result
                }
                let old_len = self.out.len() - destination_at;
                replace_words(
                    &mut self.out,
                    &mut self.offsets,
                    &mut self.fixups,
                    destination_at,
                    old_len,
                    &replacement,
                );
                self.state.last_reference_push = None;
            }
            0x0d => self.out.extend([0x17c, self.reader.word()?]), // paired alist -> NewAList
            0x3d => self.out.push(0xab), // Browse with options already on stack
            0x3e => self.out.push(0x27), // BrowseResource
            0x3f => self.out.push(0x10b), // OutputControl
            0x44 => self.out.push(0x07), // Link
            0x46 => self.out.push(0x08), // OutputFtp
            _ => return Ok(OpcodeFlow::Unhandled),
        }
        Ok(OpcodeFlow::Advance)
    }
}
