use super::*;

impl<R: SymbolResolver> PassState<'_, R> {
    pub(super) fn lower_references_fields(
        &mut self,
        start: usize,
        op: u8,
        _follows_format: bool,
    ) -> Result<OpcodeFlow, LowerError> {
        let code = self.inputs.code;
        let ids = self.inputs.ids;
        let world_flow = &mut *self.world_flow;
        match op {
            0xa8 => {
                let field = mapped(ids.string(self.reader.word()?), start, "field name")?;
                let retain = self.reader.byte()?;
                if retain > 1 {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "native field assignment retain flag is invalid".into(),
                    });
                }
                // Fold only an unconditional direct reference; a branch join
                // may end in GetVar while representing multiple receivers.
                let direct = byond_dmb::bytecode::decode(&self.out).ok().and_then(|items| {
                    if self.fixups.iter().any(|fixup| fixup.target == start as u32) {
                        return None;
                    }
                    let executable: Vec<_> = items
                        .iter()
                        .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
                        .collect();
                    let owner = *executable.last()?;
                    if owner.opcode != 0x33 {
                        return None;
                    }
                    let (reference, used) = Variable::decode(&owner.operands).ok()?;
                    if used != owner.operands.len()
                        || !matches!(
                            reference,
                            Variable::Arg(_)
                                | Variable::Local(_)
                                | Variable::Global(_)
                                | Variable::Src
                                | Variable::Usr
                                | Variable::World
                                | Variable::Dot
                                | Variable::SetCache(_, _)
                        )
                    {
                        return None;
                    }
                    let duplicate = if retain == 1 {
                        let duplicate = executable.get(executable.len().checked_sub(2)?)?;
                        if duplicate.opcode != 0x13c {
                            return None;
                        }
                        Some(duplicate.offset)
                    } else {
                        None
                    };
                    Some((owner.offset, reference, duplicate))
                });
                if let Some((at, owner, duplicate)) = direct {
                    let removed = 1 + owner.encode().len();
                    replace_words(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        at,
                        removed,
                        &[],
                    );
                    if let Some(duplicate) = duplicate {
                        replace_words(
                            &mut self.out,
                            &mut self.offsets,
                            &mut self.fixups,
                            duplicate,
                            1,
                            &[],
                        );
                    }
                    self.out.push(if retain == 1 { 0x35 } else { 0x34 });
                    self.out.extend(append_field(owner, field).encode());
                } else {
                    // The exporter duplicates the value before evaluating a
                    // computed owner, including conditional receiver paths.
                    self.out.extend([0x34, 0xffd8, 0x34, field]);
                }
                self.state.last_reference_push = None;
                self.state.cached_world_owner = false;
            }
            0xa7 => {
                // The patched exporter preserves AST positional keys, so no
                // instruction-span guessing is needed for computed options.
                let mode = self.reader.byte()?;
                let count = self.reader.word()?;
                match (mode, count) {
                    (1, 1) => self.out.push(0x129),
                    (2, count) if (2..=510).contains(&count) && count % 2 == 0 => {
                        self.out.extend([0xc8, count / 2, 0x128]);
                    }
                    (3, 1) => self.out.push(0x128),
                    _ => {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "native-keyed animate argument form has no paired lowering"
                                .into(),
                        })
                    }
                }
            }
            0x9c => {
                let mode = self.reader.byte()?;
                let count = self.reader.word()?;
                match (mode, count) {
                    (1, 1) => self.out.push(0x129), // animate(target)
                    (2, 4 | 6 | 8 | 10 | 12) => {
                        // Paired animate(target, alpha=n, time=n): OpenDream
                        // starts its named argument list with null; native
                        // DreamMaker starts the assoc list with integer 1.
                        let instructions =
                            byond_dmb::bytecode::decode(&self.out).map_err(|error| LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: format!(
                                    "cannot inspect animate arguments: {}",
                                    error.reason
                                ),
                            })?;
                        let args_at = constructor_argument_start(&self.out, count as usize)
                            .ok_or_else(|| LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "animate named arguments have unknown stack effects".into(),
                            })?;
                        let first = instructions
                            .iter()
                            .find(|item| item.offset == args_at)
                            .ok_or_else(|| LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "animate argument boundary is not an instruction".into(),
                            })?;
                        if first.opcode == 0x60
                            && self.out.get(first.offset..first.offset + 3)
                                == Some(&[0x60, 0, 0][..])
                        {
                            replace_words(
                                &mut self.out,
                                &mut self.offsets,
                                &mut self.fixups,
                                first.offset,
                                3,
                                &[0x50, 1],
                            );
                        }
                        self.out.extend([0xc8, count / 2, 0x128]);
                    }
                    _ => {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "animate argument form has no paired native lowering".into(),
                        });
                    }
                }
            }
            0x73 => {
                let mode = self.reader.byte()?;
                let count = self.reader.word()?;
                match (mode, count) {
                    (1, 2) => {
                        let literal_list = constructor_argument_start(&self.out, 1)
                            .and_then(|at| byond_dmb::bytecode::decode(&self.out[..at]).ok())
                            .and_then(|items| {
                                items
                                    .into_iter()
                                    .rev()
                                    .find(|item| !matches!(item.opcode, 0x84 | 0x85))
                            })
                            .is_some_and(|item| matches!(item.opcode, 0x1a | 0xc8 | 0x17c));
                        if literal_list {
                            self.out.push(0x163);
                        } else {
                            self.out.extend([0x1a, 2, 0x164]);
                        }
                    }
                    (1, 1..=255) => self.out.extend([0x1a, count, 0x164]),
                    (3, 1) => self.out.push(0x164),
                    (2, 2..=510) if count % 2 == 0 => {
                        let mut end = self.out.len();
                        let mut spans = Vec::new();
                        for _ in 0..count {
                            let at = constructor_argument_start(&self.out[..end], 1).ok_or_else(
                                || LowerError {
                                    kind: LowerErrorKind::MalformedControlFlow,
                                    offset: start,
                                    reason: "gradient keyed argument has unknown stack effects"
                                        .into(),
                                },
                            )?;
                            spans.push((at, end));
                            end = at;
                        }
                        spans.reverse();
                        for (index, pair) in spans.chunks_exact(2).enumerate().rev() {
                            let (lo, hi) = pair[0];
                            let items =
                                byond_dmb::bytecode::decode(&self.out[lo..hi]).map_err(|error| {
                                    LowerError {
                                        kind: LowerErrorKind::MalformedControlFlow,
                                        offset: start,
                                        reason: error.reason,
                                    }
                                })?;
                            let executable: Vec<_> = items
                                .iter()
                                .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
                                .collect();
                            if let [item] = executable.as_slice() {
                                if item.opcode == 0x60 && item.operands == [0, 0] {
                                    replace_words(
                                        &mut self.out,
                                        &mut self.offsets,
                                        &mut self.fixups,
                                        lo + item.offset,
                                        3,
                                        &[0x50, index as u32 + 1],
                                    );
                                }
                            }
                        }
                        self.out.extend([0xc8, count / 2, 0x164]);
                    }
                    _ => {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "gradient argument form has no paired native lowering".into(),
                        });
                    }
                }
            }
            0x48 => self.out.push(0x185), // astype(value, type)
            0x06 => {
                if ids.native_initial_reference(start) && ids.native_is_saved_reference(start) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "conflicting native reference modifiers".into(),
                    });
                }
                if (ids.native_initial_reference(start) || ids.native_is_saved_reference(start))
                    && !matches!(self.reader.code.get(self.reader.at), Some(8..=10))
                {
                    return Err(LowerError {
            kind: LowerErrorKind::MalformedControlFlow, offset: start, reason: "native reference modifier requires a local, argument, or constant global".into() });
                }
                // OpenDream writes `world.log << "text"` as a world reference,
                // a string value, and OutputReference(Field). DreamMaker uses
                // GetVar(SetCache(World, Field)), PushVal, Output instead.
                if self.reader.code.get(self.reader.at..self.reader.at + 2) == Some(&[5, 3])
                    && self.reader.code.get(self.reader.at + 6..self.reader.at + 8)
                        == Some(&[0x4e, 12])
                {
                    self.reader.byte()?; // World reference kind
                    let string_at = self.reader.at;
                    self.reader.byte()?; // PushString
                    let string_id = self.reader.word()?;
                    let output_at = self.reader.at;
                    self.reader.byte()?; // OutputReference
                    self.reader.byte()?; // Field reference kind
                    let field_id = mapped(ids.string(self.reader.word()?), start, "string")?;
                    if self.state.cached_world_owner {
                        world_flow.reused = true;
                        self.out.extend([0x33, field_id]);
                    } else {
                        self.out.extend([0x33, 0xffdc, 0xffe5, field_id]);
                    }
                    self.offsets.insert(string_at as u32, self.out.len() as u32);
                    push_value(
                        &mut self.out,
                        6,
                        mapped(ids.string(string_id), start, "string")?,
                    );
                    self.offsets.insert(output_at as u32, self.out.len() as u32);
                    self.out.push(0x03);
                    self.state.pending_world_ref = None;
                    self.state.cached_world_owner = true;
                } else {
                    let output_start = self.out.len();
                    self.out.push(0x33);
                    let source_reference_at = self.reader.at;
                    let var = reference(&mut self.reader, ids)?;
                    let var = if ids.native_initial_reference(start)
                        || ids.native_is_saved_reference(start)
                    {
                        if !matches!(
                            var,
                            Variable::Local(_) | Variable::Arg(_) | Variable::Global(_)
                        ) {
                            return Err(LowerError {
            kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "native reference modifier requires a local, argument, or constant global"
                                    .into(),
                            });
                        }
                        if matches!(var, Variable::Global(_)) {
                            let raw = self
                                .reader
                                .code
                                .get(source_reference_at + 1..source_reference_at + 5)
                                .ok_or_else(|| LowerError {
                                    kind: LowerErrorKind::TruncatedOperand,
                                    offset: start,
                                    reason: "truncated native constant global reference".into(),
                                })?;
                            let old = u32::from_le_bytes(raw.try_into().unwrap());
                            if !ids.native_constant_global(old) {
                                return Err(LowerError {
                                    kind: LowerErrorKind::MalformedControlFlow,
                                    offset: start,
                                    reason:
                                        "native reference modifier global must be readonly constant"
                                            .into(),
                                });
                            }
                        }
                        if ids.native_initial_reference(start) {
                            Variable::Initial(Box::new(var))
                        } else {
                            Variable::IsSaved(Box::new(var))
                        }
                    } else {
                        var
                    };
                    if var == Variable::World {
                        world_flow.reused |= self.state.cached_world_owner;
                        self.state.pending_world_ref = Some(PendingWorld {
                            at: output_start,
                            world_cached_at_push: self.state.cached_world_owner,
                            rhs_changed_cache: false,
                        });
                    } else if matches!(var, Variable::SetCache(_, _)) {
                        self.state.cached_world_owner = false;
                        if let Some(pending) = &mut self.state.pending_world_ref {
                            pending.rhs_changed_cache = true;
                        }
                    }
                    self.state.last_reference_push = Some((output_start, var.clone()));
                    self.out.extend(var.encode());
                }
            }
            0x86 => {
                // PushRefAndDereferenceField
                let owner = reference(&mut self.reader, ids)?;
                let field = mapped(ids.string(self.reader.word()?), start, "string")?;
                self.out.push(0x33);
                if owner == Variable::World && self.state.cached_world_owner {
                    world_flow.reused = true;
                    self.out.extend(Variable::Field(field).encode());
                } else {
                    self.out.extend(
                        Variable::SetCache(
                            Box::new(owner.clone()),
                            Box::new(Variable::Field(field)),
                        )
                        .encode(),
                    );
                }
                self.state.last_reference_push = None;
                self.state.cached_world_owner = owner == Variable::World;
                if !self.state.cached_world_owner {
                    if let Some(pending) = &mut self.state.pending_world_ref {
                        pending.rhs_changed_cache = true;
                    }
                }
            }
            0x96 => {
                // NullRef: clear a variable without retaining a value
                if self.reader.code.get(self.reader.at) == Some(&7) {
                    self.reader.byte()?;
                    let at =
                        constructor_argument_start(&self.out, 2).ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "indexed NullRef has unknown list/key stack effects".into(),
                        })?;
                    if self
                        .fixups
                        .iter()
                        .any(|fixup| fixup.at >= at && fixup.at < self.out.len())
                    {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "indexed NullRef operand branches need relocation".into(),
                        });
                    }
                    let mut replacement = vec![0x60, 0, 0];
                    replacement.extend_from_slice(&self.out[at..]);
                    replacement.push(0x7c);
                    let old_len = self.out.len() - at;
                    replace_words(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        at,
                        old_len,
                        &replacement,
                    );
                    self.state.last_reference_push = None;
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                let target = reference(&mut self.reader, ids)?;
                if let Variable::Field(field) = target {
                    let instructions =
                        byond_dmb::bytecode::decode(&self.out).map_err(|error| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: format!("cannot inspect NullRef field owner: {}", error.reason),
                        })?;
                    if let Some(prior) = instructions.last().filter(|prior| {
                        prior.opcode == 0x33
                            && !self.fixups.iter().any(|fixup| fixup.target == start as u32)
                    }) {
                        let (owner, used) =
                            Variable::decode(&prior.operands).map_err(|error| LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: format!(
                                    "cannot decode NullRef field owner: {}",
                                    error.reason
                                ),
                            })?;
                        if used != prior.operands.len() {
                            return Err(LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "NullRef field owner has extra operands".into(),
                            });
                        }
                        let mut replacement = vec![0x60, 0, 0, 0x34];
                        replacement.extend(append_field(owner, field).encode());
                        replace_words(
                            &mut self.out,
                            &mut self.offsets,
                            &mut self.fixups,
                            prior.offset,
                            1 + prior.operands.len(),
                            &replacement,
                        );
                    } else {
                        self.out.extend([0x34, 0xffd8, 0x60, 0, 0, 0x34, field]);
                    }
                    self.state.last_reference_push = None;
                    self.state.cached_world_owner = false;
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                self.out.extend([0x60, 0, 0, 0x34]);
                emit_tracked_reference(
                    &mut self.out,
                    &target,
                    &mut self.state.cached_world_owner,
                    &mut self.state.pending_world_ref,
                );
            }
            0x99 => {
                // IndexRefWithString: list/string key known at compile time
                let owner = reference(&mut self.reader, ids)?;
                let key = mapped(ids.string(self.reader.word()?), start, "string")?;
                self.out.push(0x33);
                self.out.extend(owner.encode());
                push_value(&mut self.out, 6, key);
                self.out.push(0x7b);
            }
            0x69 => {
                self.out.push(0x7b); // DereferenceIndex -> ListGet
                if self.safe.pending_safe_index == Some(self.reader.at as u32) {
                    self.out.push(0x143); // restore cache after a computed safe index
                    self.safe.pending_safe_index = None;
                } else if let Some(target) = self.safe.pending_safe_index {
                    if self.reader.code.get(self.reader.at) == Some(&0x65) {
                        if let Some((index, _)) = self.fixups.iter().enumerate().next_back() {
                            self.safe.last_safe_index = Some((self.reader.at, target, index));
                        }
                    }
                }
            }
            0x68 => {
                if self.safe.pending_safe_field {
                    let field = mapped(ids.string(self.reader.word()?), start, "string")?;
                    let field_at = self.out.len();
                    self.out.extend([0x33, field]);
                    if let Some((fixup_index, fixup)) = self.fixups.iter().enumerate().next_back() {
                        self.safe.last_safe_field =
                            Some((field_at, fixup.target, fixup_index, self.reader.at));
                    }
                    self.safe.pending_safe_field = false;
                    self.state.last_reference_push = None;
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                // Fold a chained field access into BYOND's nested SetCache
                // variable operand. This is the direct GetVar form used by
                // list.len and ordinary nested fields.
                let field = mapped(ids.string(self.reader.word()?), start, "string")?;
                let instructions =
                    byond_dmb::bytecode::decode(&self.out).map_err(|error| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: format!("cannot inspect field owner: {}", error.reason),
                    })?;
                let prior = instructions
                    .iter()
                    .rev()
                    .find(|item| !matches!(item.opcode, 0x84 | 0x85))
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "DereferenceField lacks a direct owner".into(),
                    })?;
                if self.fixups.iter().any(|fixup| fixup.target == start as u32) {
                    // At a branch join, the last GetVar belongs only to one
                    // arm. Both arms must reach a shared field read.
                    self.out.extend([0x34, 0xffd8, 0x33, field]);
                    self.state.last_reference_push = None;
                    self.state.cached_world_owner = false;
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                if prior.opcode == 0x30 {
                    // A global call leaves its return value on the stack. Native
                    // bytecode caches that value before reading its field.
                    self.out.extend([0x34, 0xffd8, 0x33, field]);
                    self.state.last_reference_push = None;
                    self.state.cached_world_owner = false;
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                if prior.opcode == 0x35 {
                    let (owner, used) =
                        Variable::decode(&prior.operands).map_err(|error| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: format!("cannot decode assigned field owner: {}", error.reason),
                        })?;
                    if used != prior.operands.len() {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "assigned field owner has extra operands".into(),
                        });
                    }
                    self.out[prior.offset] = 0x34; // SetVar, then access the assigned reference
                    self.out.push(0x33);
                    self.out.extend(append_field(owner, field).encode());
                    self.state.last_reference_push = None;
                    self.state.cached_world_owner = false;
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                if prior.opcode != 0x33 {
                    // OD DereferenceField consumes its owner from the stack.
                    // Cache consumes that same value, so this also preserves
                    // branch-bearing owners without moving any instructions.
                    self.out.extend([0x34, 0xffd8, 0x33, field]);
                    self.state.last_reference_push = None;
                    self.state.cached_world_owner = false;
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                let (owner, used) =
                    Variable::decode(&prior.operands).map_err(|error| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: format!("cannot decode field owner: {}", error.reason),
                    })?;
                if used != prior.operands.len() {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "DereferenceField owner has extra operands".into(),
                    });
                }
                let mut replacement = vec![0x33];
                replacement.extend(
                    if self.safe.pending_safe_index.is_some() && owner == Variable::Cache {
                        // The null guard already installed this indexed receiver.
                        Variable::Field(field).encode()
                    } else {
                        append_field(owner, field).encode()
                    },
                );
                replace_words(
                    &mut self.out,
                    &mut self.offsets,
                    &mut self.fixups,
                    prior.offset,
                    1 + prior.operands.len(),
                    &replacement,
                );
                self.state.last_reference_push = None;
                self.state.cached_world_owner = false;
            }
            0x47 | 0x53 => {
                // OpenDream initial/issaved(owner.field) pushes owner and
                // field separately. BYOND nests the field in GetVar.
                if start < 5 || self.reader.code[start - 5] != 0x03 {
                    if guarded_assignment_spans(
                        &self.out,
                        code,
                        &self.offsets,
                        &self.fixups,
                        start,
                        1,
                    )
                    .is_some()
                        || constructor_argument_start(&self.out, 2).is_some()
                    {
                        // Closed conditional/short-circuit list and key spans
                        // remain in source order; CacheIndex consumes both.
                        // Paired arbitrary list/key expressions, including
                        // numeric constants and the procedure's args list.
                        self.out.extend([
                            0x34,
                            0xffe3,
                            0x34,
                            0xffd8,
                            0x33,
                            if op == 0x47 { 0xffe7 } else { 0xffe8 },
                            0xffe4,
                        ]);
                        self.state.last_reference_push = None;
                        self.state.cached_world_owner = false;
                        return Ok(OpcodeFlow::ContinueThisOpcode);
                    }
                    let items = byond_dmb::bytecode::decode(&self.out).map_err(|error| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: format!("cannot inspect dynamic issaved owner: {}", error.reason),
                    })?;
                    let executable: Vec<_> = items
                        .iter()
                        .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
                        .collect();
                    if let [.., owner, key] = executable.as_slice() {
                        let owner_var = Variable::decode(&owner.operands).ok().map(|(v, _)| v);
                        let key_var = Variable::decode(&key.operands).ok().map(|(v, _)| v);
                        if owner.opcode == 0x33
                            && key.opcode == 0x33
                            && matches!(owner_var, Some(Variable::SetCache(_, _)))
                            && matches!(
                                key_var,
                                Some(
                                    Variable::Local(_)
                                        | Variable::Arg(_)
                                        | Variable::Global(_)
                                        | Variable::Field(_)
                                        | Variable::SetCache(_, _)
                                )
                            )
                        {
                            // Paired state_schema_for: issaved(D.vars[name]);
                            // mem_and_lists: initial(thing.vars[variable]).
                            // The list and key already sit on the stack.
                            self.out.extend([
                                0x34,
                                0xffe3,
                                0x34,
                                0xffd8,
                                0x33,
                                if op == 0x47 { 0xffe7 } else { 0xffe8 },
                                0xffe4,
                            ]);
                            self.state.last_reference_push = None;
                            return Ok(OpcodeFlow::ContinueThisOpcode);
                        }
                    }
                }
                if start < 5 || self.reader.code[start - 5] != 0x03 || self.out.len() < 3 {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "Initial/IsSaved requires a direct field name".into(),
                    });
                }
                let items = byond_dmb::bytecode::decode(&self.out).map_err(|error| LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: format!("cannot inspect initial/issaved field: {}", error.reason),
                })?;
                let executable: Vec<_> = items
                    .iter()
                    .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
                    .collect();
                let string = executable
                    .last()
                    .filter(|item| {
                        item.opcode == 0x60
                            && item.operands.first().is_some_and(|word| word & 0xff == 6)
                    })
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "Initial/IsSaved field is not a string constant".into(),
                    })?;
                let string_at = string.offset;
                let field = Value::decode(&string.operands)
                    .map_err(|error| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: error.reason,
                    })?
                    .0
                    .id();
                let direct_owner = self
                    .state
                    .last_reference_push
                    .take()
                    .filter(|(at, _)| {
                        executable.len() >= 2 && executable[executable.len() - 2].offset == *at
                    })
                    .or_else(|| {
                        let getter = executable.get(executable.len().checked_sub(2)?)?;
                        if getter.opcode != 0x33 {
                            return None;
                        }
                        let operands = getter.typed_operands().ok()?;
                        let [byond_dmb::bytecode::Operand::Variable(owner)] = operands.as_slice()
                        else {
                            return None;
                        };
                        fn fields_only(owner: &Variable) -> bool {
                            match owner {
                                Variable::SetCache(_, next) => fields_only(next),
                                Variable::Field(_) => true,
                                _ => false,
                            }
                        }
                        fields_only(owner).then_some((getter.offset, owner.clone()))
                    });
                if direct_owner.is_none() {
                    // Paired computed receiver: pop it into BYOND's cache.
                    replace_words(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        string_at,
                        3,
                        &[
                            0x34,
                            0xffd8,
                            0x33,
                            if op == 0x47 { 0xffe7 } else { 0xffe8 },
                            field,
                        ],
                    );
                    self.state.cached_world_owner = false;
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                let (owner_at, owner) = direct_owner.unwrap();
                replace_words(
                    &mut self.out,
                    &mut self.offsets,
                    &mut self.fixups,
                    owner_at,
                    1 + owner.encode().len(),
                    &[],
                );
                let string_at = string_at - (1 + owner.encode().len());
                let mut value = vec![0x33];
                let field = if op == 0x47 {
                    Variable::Initial(Box::new(Variable::Field(field)))
                } else {
                    Variable::IsSaved(Box::new(Variable::Field(field)))
                };
                fn append_initial(owner: Variable, field: Variable) -> Variable {
                    match owner {
                        Variable::SetCache(lhs, rhs) => {
                            Variable::SetCache(lhs, Box::new(append_initial(*rhs, field)))
                        }
                        other => Variable::SetCache(Box::new(other), Box::new(field)),
                    }
                }
                value.extend(append_initial(owner, field).encode());
                replace_words(
                    &mut self.out,
                    &mut self.offsets,
                    &mut self.fixups,
                    string_at,
                    3,
                    &value,
                );
                self.state.cached_world_owner = false;
            }
            0x4a => self.out.push(0x5a), // LocateCoord(x,y,z)
            _ => return Ok(OpcodeFlow::Unhandled),
        }
        Ok(OpcodeFlow::Advance)
    }
}
