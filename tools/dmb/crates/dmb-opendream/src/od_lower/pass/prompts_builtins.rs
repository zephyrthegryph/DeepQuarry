use super::*;

impl<R: SymbolResolver> PassState<'_, R> {
    pub(super) fn lower_prompts_builtins(
        &mut self,
        start: usize,
        op: u8,
        _follows_format: bool,
    ) -> Result<OpcodeFlow, LowerError> {
        let code = self.inputs.code;
        let world_flow = &mut *self.world_flow;
        match op {
            0x45 => {
                // OpenDream pushes four prompt arguments in reverse order,
                // followed by a selection list. DreamMaker consumes normal
                // argument order and includes PromptCheck after Input.
                let exported_types = self.reader.word()?;
                let explicit_anything = exported_types & 0x8000_0000 != 0;
                let authored_choices = exported_types & 0x4000_0000 != 0;
                // Preserve omission separately from OpenDream's default text/anything.
                let implicit_types = exported_types & 0x2000_0000 != 0;
                let types = if implicit_types {
                    0
                } else {
                    exported_types & 0x1fff_ffff
                };
                if types & !0x1fff != 0 {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: format!("Prompt type mask {types:#x} has no paired native mapping"),
                    });
                }
                let mut native_flags = if explicit_anything { 0x1000 } else { 0 };
                for (od, native) in [
                    (1, 128),
                    (2, 4),
                    (4, 2),
                    (8, 1),
                    (16, 32),
                    (32, 8),
                    (64, 2048),
                    (128, 256),
                    (512, 16),
                    (2048, 1024),
                    (4096, 512),
                ] {
                    if types & od != 0 {
                        native_flags |= native;
                    }
                }
                let special_flags = if types & 0x100 != 0 { 131072 } else { 0 }
                    | if types & 0x400 != 0 { 65536 } else { 0 };
                let prompt_config = (special_flags != 0).then_some(special_flags | native_flags);
                let native_type = if prompt_config.is_some() {
                    0
                } else {
                    native_flags
                };
                let instructions =
                    byond_dmb::bytecode::decode(&self.out).map_err(|error| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: format!("cannot inspect prompt arguments: {}", error.reason),
                    })?;
                let null_selection = instructions
                    .last()
                    .is_some_and(|item| item.opcode == 0x60 && item.operands == [0, 0]);
                let selection_choice = authored_choices || !null_selection;
                if null_selection || selection_choice {
                    let mut end = self.out.len();
                    let mut spans = Vec::new();
                    for _ in 0..5 {
                        let Some(at) = guarded_assignment_spans(
                            &self.out[..end],
                            code,
                            &self.offsets,
                            &self.fixups,
                            start,
                            0,
                        )
                        .map(|(first, _)| first)
                        .or_else(|| constructor_argument_start(&self.out[..end], 1)) else {
                            break;
                        };
                        spans.push((at, end));
                        end = at;
                    }
                    if spans.len() == 5 {
                        spans.reverse();
                        world_flow.separate_reordered_arguments(&spans, &self.offsets, code.len());
                        let at = spans[0].0;
                        let computed = instructions
                            .iter()
                            .any(|item| item.offset >= at && !matches!(item.opcode, 0x33 | 0x60));
                        if computed
                            && self.fixups.iter().all(|fixup| {
                                if fixup.at < at {
                                    return self
                                        .offsets
                                        .get(&fixup.target)
                                        .is_none_or(|target| *target as usize <= at);
                                }
                                spans.iter().any(|(begin, end)| {
                                    fixup.at >= *begin
                                        && fixup.at < *end
                                        && self.offsets.get(&fixup.target).is_some_and(|target| {
                                            (*target as usize) >= *begin
                                                && (*target as usize) <= *end
                                        })
                                })
                            })
                        {
                            let mut replacement = Vec::new();
                            if let Some(config) = prompt_config {
                                let bits = (config as f32).to_bits();
                                replacement.extend([0x60, 42, bits >> 16, bits & 0xffff]);
                            }
                            if selection_choice {
                                if self.out[spans[4].0..spans[4].1] == [0x60, 0, 0] {
                                    replacement.push(0x33);
                                    replacement.extend(Variable::Null.encode());
                                } else {
                                    replacement
                                        .extend_from_slice(&self.out[spans[4].0..spans[4].1]);
                                }
                            }
                            for index in (0..4).rev() {
                                let (begin, end) = spans[index];
                                if (index == 1 || index == 4)
                                    && self.out[begin..end] == [0x60, 0, 0]
                                {
                                    replacement.push(0x33);
                                    replacement.extend(Variable::Null.encode());
                                } else {
                                    replacement.extend_from_slice(&self.out[begin..end]);
                                }
                            }
                            replacement.extend([
                                if prompt_config.is_some() { 0xc6 } else { 0xc1 },
                                native_type,
                                0,
                                if selection_choice { 64 } else { 0 },
                                0xba,
                            ]);
                            // Each argument is a closed expression. Preserve its
                            // internal targets while changing argument order.
                            let mut moved = Vec::new();
                            let mut cursor = at + if prompt_config.is_some() { 4 } else { 0 };
                            let order: Vec<usize> = if selection_choice {
                                vec![4, 3, 2, 1, 0]
                            } else {
                                vec![3, 2, 1, 0]
                            };
                            for index in order {
                                let (begin, end) = spans[index];
                                moved.push(((begin, end), cursor));
                                cursor += if (index == 1 || index == 4)
                                    && self.out[begin..end] == [0x60, 0, 0]
                                {
                                    2
                                } else {
                                    end - begin
                                };
                            }
                            let original_offsets =
                                moved_offset_snapshot(&self.offsets, &self.fixups, &moved);
                            remap_closed_spans(
                                &original_offsets,
                                &mut self.offsets,
                                &mut self.fixups,
                                &moved,
                            );
                            self.out.truncate(at);
                            self.out.extend(replacement);
                            self.state.cached_world_owner = false;
                            self.state.pending_world_ref = None;
                            self.state.last_reference_push = None;
                            return Ok(OpcodeFlow::ContinueThisOpcode);
                        }
                    }
                }
                let nullable_selection = selection_choice;
                let (argument_start, list_start, list_flag) = if nullable_selection {
                    let last = instructions.last().ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "Prompt lacks a selection list".into(),
                    })?;
                    let list_instruction_count = if last.opcode == 0x1a {
                        1 + last.operands.first().copied().unwrap_or(0) as usize
                    } else if matches!(last.opcode, 0x33 | 0x60) {
                        1
                    } else {
                        return Err(LowerError {
                            kind: LowerErrorKind::TruncatedOperand,
                            offset: start,
                            reason: "Prompt selection list has an unsupported expression".into(),
                        });
                    };
                    let list_start = instructions
                        .len()
                        .checked_sub(list_instruction_count)
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::TruncatedOperand,
                            offset: start,
                            reason: "Prompt selection list is truncated".into(),
                        })?;
                    let argument_start = list_start.checked_sub(4).ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "Prompt lacks four direct arguments".into(),
                    })?;
                    (argument_start, list_start, 64)
                } else {
                    let argument_start =
                        instructions
                            .len()
                            .checked_sub(5)
                            .ok_or_else(|| LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "Prompt lacks five direct operands".into(),
                            })?;
                    if instructions
                        .last()
                        .is_none_or(|item| item.opcode != 0x60 || item.operands != [0, 0])
                    {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "Prompt with this type requires a null selection list".into(),
                        });
                    }
                    (argument_start, instructions.len() - 1, 0)
                };
                let arguments = &instructions[argument_start..list_start];
                if arguments
                    .iter()
                    .any(|item| !matches!(item.opcode, 0x33 | 0x60))
                {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "Prompt supports direct arguments only".into(),
                    });
                }
                let mut replacement = Vec::new();
                if let Some(config) = prompt_config {
                    // Native nullable color prompt carries its type flags as
                    // a number before the four ordinary input arguments.
                    let bits = (config as f32).to_bits();
                    replacement.extend([0x60, 42, bits >> 16, bits & 0xffff]);
                }
                if list_flag != 0 {
                    if instructions[list_start..instructions.len() - 1]
                        .iter()
                        .any(|item| !matches!(item.opcode, 0x33 | 0x60))
                    {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "Prompt selection list has nonliteral entries".into(),
                        });
                    }
                    for item in &instructions[list_start..] {
                        if item.opcode == 0x60 && item.operands == [0, 0] {
                            replacement.push(0x33);
                            replacement.extend(Variable::Null.encode());
                        } else {
                            replacement.push(item.opcode);
                            replacement.extend(&item.operands);
                        }
                    }
                }
                for item in arguments.iter().rev() {
                    replacement.push(item.opcode);
                    replacement.extend(&item.operands);
                }
                replacement.extend([
                    if prompt_config.is_some() { 0xc6 } else { 0xc1 },
                    native_type,
                    0,
                    list_flag,
                    0xba,
                ]);
                let spans: Vec<_> = arguments
                    .iter()
                    .map(|item| (item.offset, item.offset + 1 + item.operands.len()))
                    .collect();
                world_flow.separate_reordered_arguments(&spans, &self.offsets, code.len());
                self.state.cached_world_owner = false;
                self.state.pending_world_ref = None;
                self.state.last_reference_push = None;
                let at = arguments[0].offset;
                let old_len = self.out.len() - at;
                replace_words(
                    &mut self.out,
                    &mut self.offsets,
                    &mut self.fixups,
                    at,
                    old_len,
                    &replacement,
                );
            }
            0x23 => {
                return Err(LowerError {
            kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "stock OpenDream CallStatement conflates call() and call_ext(); use the pinned compiler patch with explicit 0x9D/0x9E opcodes".into(),
                });
            }
            0xa3 => {
                // Native direct references are read after arguments; computed owners
                // are evaluated before arguments and protected by the cache stack.
                let cached_fields = byond_dmb::bytecode::decode(&self.out).ok().and_then(|items| {
                    let items: Vec<_> = items
                        .iter()
                        .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
                        .collect();
                    let [.., parent, getter] = items.as_slice() else {
                        return None;
                    };
                    let guarded = matches!(parent.opcode, 0x13d | 0x13e);
                    if getter.opcode != 0x33
                        || !(guarded || parent.opcode == 0x34 && parent.operands == [0xffd8])
                    {
                        return None;
                    }
                    let (reference, used) = Variable::decode(&getter.operands).ok()?;
                    fn fields(variable: &Variable) -> bool {
                        match variable {
                            Variable::Field(_) => true,
                            Variable::SetCache(owner, field) => fields(owner) && fields(field),
                            _ => false,
                        }
                    }
                    (used == getter.operands.len() && fields(&reference)).then_some((
                        getter.offset,
                        reference,
                        guarded,
                    ))
                });
                if let Some((at, reference, guarded)) = cached_fields {
                    // Retain the computed parent during argument evaluation;
                    // read its child fields only after restoring that parent.
                    replace_words(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        at,
                        1 + reference.encode().len(),
                        &[],
                    );
                    self.out.push(0x142);
                    self.pending_receivers
                        .push(PendingReceiver::NativeCachedReference(reference, guarded));
                    self.state.last_reference_push = None;
                    self.state.cached_world_owner = false;
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                let assigned_owner = byond_dmb::bytecode::decode(&self.out).ok().and_then(|items| {
                    let last = items
                        .iter()
                        .rev()
                        .find(|item| !matches!(item.opcode, 0x84 | 0x85))?;
                    if last.opcode != 0x35 {
                        return None;
                    }
                    let (reference, used) = Variable::decode(&last.operands).ok()?;
                    if used != last.operands.len()
                        || !matches!(
                            reference,
                            Variable::Arg(_) | Variable::Local(_) | Variable::Global(_)
                        )
                    {
                        return None;
                    }
                    Some((last.offset, reference, true))
                });
                let direct = if !self.fixups.iter().any(|fixup| fixup.target == start as u32) {
                    assigned_owner.or_else(|| {
                        constructor_argument_start(&self.out, 1).and_then(|at| {
                            let items: Vec<_> = byond_dmb::bytecode::decode(&self.out[at..])
                                .ok()?
                                .into_iter()
                                .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
                                .collect();
                            if items.len() != 1 || !matches!(items[0].opcode, 0x33 | 0x35) {
                                return None;
                            }
                            Variable::decode(&items[0].operands)
                                .ok()
                                .map(|(reference, _)| (at, reference, items[0].opcode == 0x35))
                        })
                    })
                } else {
                    None
                };
                if let Some((at, reference, assigned)) = direct {
                    // Keep intervening source markers when deferring the
                    // receiver read until after argument evaluation.
                    let old_len = 1 + reference.encode().len();
                    if assigned {
                        self.out[at] = 0x34;
                    } else {
                        replace_words(
                            &mut self.out,
                            &mut self.offsets,
                            &mut self.fixups,
                            at,
                            old_len,
                            &[],
                        );
                    }
                    self.pending_receivers
                        .push(PendingReceiver::NativeReference(reference));
                } else {
                    self.out.extend([0x34, 0xffd8, 0x142]);
                    self.pending_receivers.push(PendingReceiver::NativeCached);
                }
                self.state.last_reference_push = None;
                self.state.cached_world_owner = false;
            }
            0xa6 => {
                // Native indexed assignment expression preserves its RHS value.
                self.out.push(0x13c);
                self.state.last_reference_push = None;
            }
            0xa5 => {
                // Pinned compiler has evaluated value, list and key in native order.
                self.out.push(0x7c);
                self.state.last_reference_push = None;
                self.state.cached_world_owner = false;
            }
            0xa4 => {
                // Pinned compiler evaluates the membership list before item.
                self.out.extend([0xa9, 5]);
                if self.reader.code.get(self.reader.at) != Some(&0x0c)
                    || self
                        .fixups
                        .iter()
                        .any(|fixup| fixup.target as usize == self.reader.at)
                {
                    self.out.push(0x36);
                }
                self.state.last_reference_push = None;
            }
            0xa2 => {
                // Pinned exporter has already distinguished numeric positional
                // keys from explicit null keys, preserving expression order.
                let count = self.reader.word()?;
                self.out.extend([0xc8, count]);
                self.state.last_reference_push = None;
            }
            0xa1 => {
                // Pinned exporter preserves DreamMaker's type-before-arguments
                // evaluation order and native numeric positional keys.
                let mode = self.reader.byte()?;
                let count = self.reader.word()?;
                match mode {
                    0 | 1 if count <= 255 && (mode == 1 || count == 0) => {
                        self.out.extend([0x01, count]);
                    }
                    2 if (2..=510).contains(&count) && count % 2 == 0 => {
                        self.out.extend([0xc8, count / 2, 0xcf]);
                    }
                    3 if count == 1 => self.out.push(0xcf),
                    _ => return Err(LowerError {
            kind: LowerErrorKind::UnsupportedConstruct,
                        offset: start,
                        reason: format!("native-ordered constructor argument mode {mode} count {count} is unsupported"),
                    }),
                }
                self.state.last_reference_push = None;
                self.state.cached_world_owner = false;
            }
            0xa0 => {
                // Pinned exporter extension: targets and arguments are
                // already evaluated in native order, with explicit arity.
                let is_ext = self.reader.byte()?;
                let targets = self.reader.byte()?;
                let mode = self.reader.byte()?;
                let count = self.reader.word()?;
                if is_ext > 1 || !matches!(targets, 1 | 2) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "native-ordered call has invalid target metadata".into(),
                    });
                }
                let is_ext = is_ext == 1;
                match mode {
                    0 | 1 if count <= 255 && (mode == 1 || count == 0) => {
                        let native = match (is_ext, targets) {
                            (false, 1) => 0x2b,
                            (false, 2) => 0xb5,
                            (true, 1) => 0x17a,
                            (true, 2) => 0x116,
                            _ => unreachable!(),
                        };
                        self.out.extend([native, count]);
                    }
                    2 | 3
                        if mode == 3 && count == 1
                            || mode == 2 && (2..=510).contains(&count) && count % 2 == 0 =>
                    {
                        if mode == 2 {
                            self.out.extend([0xc8, count / 2]);
                        }
                        self.out.push(match (is_ext, targets) {
                            (false, 1) => 0xcb,
                            (false, 2) => 0xcc,
                            (true, 1) => 0x17b,
                            (true, 2) => 0x117,
                            _ => unreachable!(),
                        });
                    }
                    _ => {
                        return Err(LowerError {
                            kind: LowerErrorKind::UnsupportedConstruct,
                            offset: start,
                            reason: format!(
                            "native-ordered call argument mode {mode} count {count} is unsupported"
                        ),
                        })
                    }
                }
                self.state.last_reference_push = None;
                self.state.cached_world_owner = false;
            }
            0x9d | 0x9e => {
                // OpenDream evaluates arguments before the call target(s).
                // The pinned compiler emits 0x9D for call_ext and 0x9E for call.
                // DreamMaker evaluates target(s) before arguments.
                let is_ext = op == 0x9d;
                let mode = self.reader.byte()?;
                let argc = self.reader.word()? as usize;
                if !(mode == 0 && argc == 0 || mode == 1 && argc <= 255 || mode == 3 && argc == 1) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "CallStatement supports positional or arglist arguments only"
                            .into(),
                    });
                }
                let instructions =
                    byond_dmb::bytecode::decode(&self.out).map_err(|error| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: format!("cannot inspect dynamic call: {}", error.reason),
                    })?;
                if (mode == 0 && argc == 0 || mode == 1 && argc <= 255) && instructions.len() >= 4 {
                    let tail = &instructions[instructions.len() - 4..];
                    if tail[0].opcode == 0x60
                        && tail[0].operands.first() == Some(&6)
                        && tail[1].opcode == 0x33
                        && tail[2].opcode == 0xb2
                        && tail[3].opcode == 0x30
                        && tail[3].operands.first() == Some(&0)
                    {
                        // `call_ext((cached || detect()), "name")()` evaluates
                        // the name before the short-circuit owner in OD. The
                        // literal name can move after the owner for BYOND.
                        let name_at = tail[0].offset;
                        let name_end = tail[1].offset;
                        let name = self.out[name_at..name_end].to_vec();
                        let arguments_at = if argc == 0 {
                            name_at
                        } else {
                            constructor_argument_start(&self.out[..name_at], argc).ok_or_else(
                                || LowerError {
                                    kind: LowerErrorKind::UnsupportedConstruct,
                                    offset: start,
                                    reason:
                                        "CallStatement arguments have unsupported stack effects"
                                            .into(),
                                },
                            )?
                        };
                        let argument_words = self.out[arguments_at..name_at].to_vec();
                        replace_words(
                            &mut self.out,
                            &mut self.offsets,
                            &mut self.fixups,
                            arguments_at,
                            name_end - arguments_at,
                            &[],
                        );
                        self.out.extend(name);
                        self.out.extend(argument_words);
                        self.out
                            .extend([if is_ext { 0x116 } else { 0xb5 }, argc as u32]);
                        return Ok(OpcodeFlow::ContinueThisOpcode);
                    }
                }
                let last = instructions.last().ok_or_else(|| LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "CallStatement lacks a target".into(),
                })?;
                let grouped_two_targets =
                    self.state.last_push_nrefs == Some((start, argc as u32 + 2));
                let target_count = if last.opcode == 0x33 {
                    if grouped_two_targets
                        || instructions.len() >= 2
                            && instructions[instructions.len() - 2].opcode == 0x60
                            && instructions[instructions.len() - 2].operands.first() == Some(&6)
                    {
                        2
                    } else {
                        1
                    }
                } else if last.opcode == 0x60 && last.operands.first() == Some(&6) {
                    1
                } else {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "CallStatement target form is not paired".into(),
                    });
                };
                let first = instructions
                    .len()
                    .checked_sub(argc + target_count)
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "CallStatement lacks direct argument values".into(),
                    })?;
                let args = &instructions[first..first + argc];
                let targets = &instructions[first + argc..];
                if args
                    .iter()
                    .any(|item| !matches!(item.opcode, 0x33 | 0x50 | 0x60))
                    || (target_count == 2
                        && !grouped_two_targets
                        && (targets[0].opcode != 0x60 || targets[0].operands.first() != Some(&6)))
                {
                    return Err(LowerError {
            kind: LowerErrorKind::MalformedControlFlow, offset: start, reason: "CallStatement supports direct positional arguments and literal target name".into() });
                }
                let mut replacement = Vec::new();
                for item in targets.iter().rev().chain(args.iter()) {
                    replacement.push(item.opcode);
                    replacement.extend(&item.operands);
                }
                if mode == 3 {
                    replacement.push(match (is_ext, target_count) {
                        (true, 1) => 0x17b,
                        (true, _) => 0x117,
                        (false, 1) => 0xcb,
                        (false, _) => 0xcc,
                    });
                } else {
                    replacement.extend([
                        match (is_ext, target_count) {
                            (true, 1) => 0x17a,
                            (true, _) => 0x116,
                            (false, 1) => 0x2b,
                            (false, _) => 0xb5,
                        },
                        argc as u32,
                    ]);
                }
                let at = instructions[first].offset;
                let old_len = self.out.len() - at;
                replace_words(
                    &mut self.out,
                    &mut self.offsets,
                    &mut self.fixups,
                    at,
                    old_len,
                    &replacement,
                );
            }
            _ => return Ok(OpcodeFlow::Unhandled),
        }
        Ok(OpcodeFlow::Advance)
    }
}
