use super::*;

impl<R: SymbolResolver> PassState<'_, R> {
    pub(super) fn lower_methods_receivers(
        &mut self,
        start: usize,
        op: u8,
        _follows_format: bool,
    ) -> Result<OpcodeFlow, LowerError> {
        let code = self.inputs.code;
        let ids = self.inputs.ids;
        let world_flow = &mut *self.world_flow;
        let is_initializer = self.inputs.is_initializer;
        match op {
            0x6a | 0xaa => {
                // DereferenceCall(name, argument mode, count)
                let target = if op == 0xaa {
                    Some(self.reader.word()?)
                } else {
                    None
                };
                let old_field = self.reader.word()?;
                let field = mapped(
                    target.map_or_else(
                        || ids.string(old_field),
                        |target| ids.method_call_name(target, old_field),
                    ),
                    start,
                    "method call name",
                )?;
                let selector = if target.is_some_and(|target| ids.method_call_is_verb(target)) {
                    Variable::DynamicVerb(field)
                } else {
                    Variable::DynamicProc(field)
                };
                let mode = self.reader.byte()?;
                let argc = self.reader.word()?;
                if let Some(receiver) = self.pending_receivers.pop() {
                    if !(matches!((mode, argc), (0, 0) | (3, 1))
                        || mode == 1 && argc <= 255
                        || mode == 2 && (2..=510).contains(&argc) && argc % 2 == 0)
                    {
                        return Err(LowerError {
                            kind: LowerErrorKind::UnsupportedConstruct,
                            offset: start,
                            reason: "native method argument shape is unsupported".into(),
                        });
                    }
                    if mode == 2 {
                        self.out.extend([0xc8, argc / 2]);
                    }
                    let direct_receiver = matches!(receiver, PendingReceiver::NativeReference(_));
                    let safe_receiver = matches!(
                        receiver,
                        PendingReceiver::SafeCached
                            | PendingReceiver::NativeCachedReference(_, true)
                    );
                    let chained_safe_index = safe_receiver
                        .then(|| {
                            if self.reader.code.get(self.reader.at) != Some(&0x65) {
                                return None;
                            }
                            let target = u32::from_le_bytes(
                                self.reader
                                    .code
                                    .get(self.reader.at + 1..self.reader.at + 5)?
                                    .try_into()
                                    .ok()?,
                            );
                            if self.reader.code.get((target as usize).checked_sub(1)?)
                                != Some(&0x69)
                            {
                                return None;
                            }
                            let pure = argc == 0
                                || (mode == 1
                                    && constructor_argument_start(&self.out, argc as usize)
                                        .and_then(|at| {
                                            byond_dmb::bytecode::decode(&self.out[at..]).ok()
                                        })
                                        .is_some_and(|items| {
                                            items
                                                .iter()
                                                .all(|item| matches!(item.opcode, 0x50 | 0x60))
                                        }));
                            pure.then_some(target)
                        })
                        .flatten();
                    if !direct_receiver {
                        if let Some(target) = chained_safe_index {
                            if let Some(index) =
                                self.fixups.iter().rposition(|fixup| fixup.target == target)
                            {
                                *self.safe.safe_skip_pop.entry(index).or_default() += 1;
                            }
                            for index in &self.safe.safe_chain_fixups {
                                *self.safe.safe_skip_pop.entry(*index).or_default() += 1;
                            }
                            self.safe.nested_safe_pop = Some((
                                target,
                                self.safe.nested_safe_pop.map_or(1, |(_, count)| count + 1),
                            ));
                        } else {
                            self.out.push(0x143);
                        }
                    }
                    let variable = match receiver {
                        PendingReceiver::NativeCachedReference(reference, _) => {
                            append_method_selector(reference, selector.clone())
                        }
                        PendingReceiver::NativeReference(reference) => {
                            append_method_selector(reference, selector.clone())
                        }
                        PendingReceiver::SafeCached | PendingReceiver::NativeCached => {
                            selector.clone()
                        }
                    };
                    let statement_call =
                        direct_receiver && world_flow.pop_is_unshared(&self.reader, &self.fixups);
                    self.out.push(if statement_call { 0x2a } else { 0x29 });
                    self.out.extend(variable.encode());
                    self.out
                        .push(if mode == 2 || mode == 3 { 0xffff } else { argc });
                    finish_native_statement_call(
                        &mut self.reader,
                        &mut self.out,
                        &mut self.offsets,
                        statement_call,
                    );
                    self.state.last_reference_push = None;
                    self.state.cached_world_owner = false;
                    if let Some(pending) = &mut self.state.pending_world_ref {
                        pending.rhs_changed_cache = true;
                    }
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                let mut owner_from_stack = None;
                if matches!(mode, 1..=3) {
                    if let Some(owner_at) = constructor_argument_start(&self.out, argc as usize + 1)
                    {
                        if let Ok(instructions) = byond_dmb::bytecode::decode(&self.out[owner_at..]) {
                            if let Some(first) = instructions.first() {
                                if first.opcode == 0x33
                                    && first.offset == 0
                                    && (if argc == 0 {
                                        Some(self.out.len())
                                    } else {
                                        constructor_argument_start(&self.out, argc as usize)
                                    })
                                    .is_some_and(|args_at| {
                                        owner_at + 1 + first.operands.len() == args_at
                                    })
                                {
                                    if let Ok((variable, _)) = Variable::decode(&first.operands) {
                                        owner_from_stack = Some((owner_at, variable));
                                    }
                                }
                            }
                        }
                    }
                }
                if owner_from_stack.is_none() && mode == 1 && argc == 1 {
                    // Paired _addtimer: `hashlist += callback.arguments;`
                    // followed by `hashlist.Join("|||||||")`. OD keeps the
                    // AugAdd result via PushEval as Join's receiver. Native
                    // stores the list and calls Join through that local.
                    if let Some(arg_at) = constructor_argument_start(&self.out, 1) {
                        if let Ok(items) = byond_dmb::bytecode::decode(&self.out[..arg_at]) {
                            if let [.., aug, eval] = items.as_slice() {
                                if aug.opcode == 0x45 && eval.opcode == 0x13f {
                                    if let Ok((Variable::Local(local), used)) =
                                        Variable::decode(&aug.operands)
                                    {
                                        if used == aug.operands.len() {
                                            replace_words(
                                                &mut self.out,
                                                &mut self.offsets,
                                                &mut self.fixups,
                                                eval.offset,
                                                1,
                                                &[],
                                            );
                                            owner_from_stack =
                                                Some((self.out.len(), Variable::Local(local)));
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if owner_from_stack.is_none() && mode == 1 && argc > 0 {
                    // Paired _queue_verb: `var/L = args.Copy(); L.Cut(2,4)`.
                    // OD retains the assignment value, then pushes method
                    // arguments. Native stores L and calls through the local.
                    if let Some(arg_at) = constructor_argument_start(&self.out, argc as usize) {
                        if let Ok(items) = byond_dmb::bytecode::decode(&self.out[..arg_at]) {
                            if let Some(set) = items.last().filter(|item| item.opcode == 0x35) {
                                if let Ok((Variable::Local(local), used)) =
                                    Variable::decode(&set.operands)
                                {
                                    if used == set.operands.len() {
                                        self.out[set.offset] = 0x34;
                                        owner_from_stack =
                                            Some((self.out.len(), Variable::Local(local)));
                                    }
                                }
                            }
                        }
                    }
                }
                if owner_from_stack.is_none() && mode == 1 && argc == 1 {
                    // Paired get_uplink_purchases: the first interpolation
                    // value is a nested conditional, followed by two ordinary
                    // values. Find its enclosing false arm before selecting
                    // the direct method receiver preceding that expression.
                    let conditional_format_owner = (|| {
                        let items = byond_dmb::bytecode::decode(&self.out).ok()?;
                        let format = items
                            .iter()
                            .rev()
                            .find(|item| !matches!(item.opcode, 0x84 | 0x85))
                            .filter(|item| item.opcode == 0x02)?;
                        let format_count = *format.operands.get(1)? as usize;
                        if format_count == 0 {
                            return None;
                        }
                        let mut first_value_end = format.offset;
                        for _ in 1..format_count {
                            first_value_end =
                                constructor_argument_start(&self.out[..first_value_end], 1)?;
                        }
                        let jump = self.fixups.iter().rev().find(|fixup| {
                            self.reader.code.get(fixup.source) == Some(&0x0e)
                                && self.offsets.get(&fixup.target).copied()
                                    == Some(first_value_end as u32)
                                && fixup.at < first_value_end
                        })?;
                        let else_at = jump.at + 1;
                        let branch = self.fixups.iter().find(|fixup| {
                            self.reader.code.get(fixup.source) == Some(&0x0c)
                                && self.offsets.get(&fixup.target).copied() == Some(else_at as u32)
                                && fixup.source < jump.source
                        })?;
                        let condition_start = *self.offsets.get(&(branch.source as u32))? as usize;
                        let condition_at = items
                            .iter()
                            .find(|item| {
                                item.offset >= condition_start
                                    && !matches!(item.opcode, 0x84 | 0x85)
                            })?
                            .offset;
                        if self.out.get(condition_at) != Some(&0x0d) {
                            return None;
                        }
                        let first_value_at =
                            constructor_argument_start(&self.out[..condition_at], 1)?;
                        let prefix = byond_dmb::bytecode::decode(&self.out[..first_value_at]).ok()?;
                        let owner = prefix
                            .iter()
                            .rev()
                            .find(|item| !matches!(item.opcode, 0x84 | 0x85))
                            .filter(|item| item.opcode == 0x33)?;
                        let (variable, used) = Variable::decode(&owner.operands).ok()?;
                        if used != owner.operands.len()
                            || !matches!(variable, Variable::Local(_) | Variable::Arg(_))
                        {
                            return None;
                        }
                        Some((owner.offset, variable))
                    })();
                    owner_from_stack = conditional_format_owner;
                }
                let mut converted_mode3_owner = false;
                if mode == 3 && argc == 1 {
                    // The arglist expression may itself read a field. Locate
                    // its stack-producing span before selecting the owner.
                    if let Some(arg_at) = constructor_argument_start(&self.out, 1) {
                        if let Ok(instructions) = byond_dmb::bytecode::decode(&self.out[..arg_at]) {
                            if let Some(last) = instructions
                                .iter()
                                .rev()
                                .find(|item| !matches!(item.opcode, 0x84 | 0x85))
                            {
                                if last.opcode == 0x35 {
                                    if let Ok((variable @ Variable::Local(_), used)) =
                                        Variable::decode(&last.operands)
                                    {
                                        if used == last.operands.len() {
                                            self.out[last.offset] = 0x34;
                                            owner_from_stack = Some((self.out.len(), variable));
                                            converted_mode3_owner = true;
                                        }
                                    }
                                } else if last.opcode == 0x33 {
                                    if let Ok((variable, used)) = Variable::decode(&last.operands) {
                                        if used == last.operands.len() {
                                            owner_from_stack = Some((last.offset, variable));
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if mode == 0 && argc == 0 {
                    if let Ok(instructions) = byond_dmb::bytecode::decode(&self.out) {
                        if let Some(last) = instructions
                            .iter()
                            .rev()
                            .find(|item| !matches!(item.opcode, 0x84 | 0x85))
                        {
                            if last.opcode == 0x35 {
                                if let Ok((variable, _)) = Variable::decode(&last.operands) {
                                    self.out[last.offset] = 0x34; // SetVar then reload via Call reference
                                    owner_from_stack = Some((self.out.len(), variable));
                                }
                            } else if last.opcode == 0x33 {
                                if let Ok((variable, used)) = Variable::decode(&last.operands) {
                                    if used == last.operands.len() {
                                        owner_from_stack = Some((last.offset, variable));
                                    }
                                }
                            }
                        }
                    }
                }
                let argument_span = match mode {
                    0 | 1 if argc == 0 => Some(self.out.len()),
                    1 if argc <= 255 => constructor_argument_start(&self.out, argc as usize),
                    2 if (2..=510).contains(&argc) && argc % 2 == 0 => {
                        constructor_argument_start(&self.out, argc as usize)
                    }
                    3 if argc == 1 => constructor_argument_start(&self.out, 1),
                    _ => None,
                };
                if let Some(args_at) = argument_span {
                    let joined_owner = self.fixups.iter().any(|fixup| {
                        self.offsets.get(&fixup.target).copied() == Some(args_at as u32)
                            && fixup.at < owner_from_stack.as_ref().map_or(args_at, |(at, _)| *at)
                    });
                    if owner_from_stack.is_none() || joined_owner {
                        // Paired computed/conditional receiver: preserve the
                        // receiver cache across argument evaluation. A branch
                        // join must execute this common cache store in both arms.
                        let joins: Vec<_> = self
                            .offsets
                            .iter()
                            .filter_map(|(key, value)| (*value == args_at as u32).then_some(*key))
                            .collect();
                        replace_words(
                            &mut self.out,
                            &mut self.offsets,
                            &mut self.fixups,
                            args_at,
                            0,
                            &[0x34, 0xffd8, 0x142],
                        );
                        for key in joins {
                            self.offsets.insert(key, args_at as u32);
                        }
                        if mode == 2 {
                            self.out.extend([0xc8, argc / 2]);
                        }
                        self.out.extend([
                            0x143,
                            // Native computed receiver calls retain an
                            // executable Pop, releasing their result there.
                            0x29,
                        ]);
                        self.out.extend(selector.clone().encode());
                        self.out
                            .push(if mode == 2 || mode == 3 { 0xffff } else { argc });
                        self.state.last_reference_push = None;
                        self.state.cached_world_owner = false;
                        if let Some(pending) = &mut self.state.pending_world_ref {
                            pending.rhs_changed_cache = true;
                        }
                        return Ok(OpcodeFlow::ContinueThisOpcode);
                    }
                }
                let (at, owner) = owner_from_stack
                    .or_else(|| self.state.last_reference_push.take())
                    .ok_or_else(|| LowerError {
            kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: format!(
                        "DereferenceCall requires a direct owner reference (mode {mode}, argc {argc}, tail {:?})",
                        byond_dmb::bytecode::decode(&self.out).ok().map(|items| items.into_iter().rev().take(10).collect::<Vec<_>>())
                    ),
                })?;
                if mode == 3 && argc == 1 && at == self.out.len() && !converted_mode3_owner {
                    return Err(LowerError {
                        kind: LowerErrorKind::UnsupportedConstruct,
                        offset: start,
                        reason: "method arglist owner was not separated from its argument".into(),
                    });
                }
                if !(matches!((mode, argc), (0, 0) | (1, _) | (3, 1))
                    || mode == 2 && (2..=510).contains(&argc) && argc % 2 == 0)
                {
                    return Err(LowerError {
                        kind: LowerErrorKind::UnsupportedConstruct,
                        offset: start,
                        reason: format!("DereferenceCall argument mode {mode} is unsupported"),
                    });
                }
                let reuse_cache = matches!(owner, Variable::Local(_) | Variable::Arg(_))
                    && byond_dmb::bytecode::decode(&self.out[..at])
                        .ok()
                        .and_then(|instructions| {
                            instructions
                                .into_iter()
                                .rev()
                                .find(|item| !matches!(item.opcode, 0x84 | 0x85))
                        })
                        .filter(|instruction| instruction.opcode == 0x29)
                        .and_then(|instruction| Variable::decode(&instruction.operands).ok())
                        .is_some_and(|(previous, _)| {
                            previous
                                == Variable::SetCache(
                                    Box::new(owner.clone()),
                                    Box::new(selector.clone()),
                                )
                        });
                let old_len = 1 + owner.encode().len();
                if at < self.out.len() {
                    replace_words(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        at,
                        old_len,
                        &[],
                    );
                }
                if mode == 2 {
                    self.out.extend([0xc8, argc / 2]);
                }
                let discard_result = world_flow.pop_is_unshared(&self.reader, &self.fixups);
                self.out.push(if discard_result { 0x2a } else { 0x29 });
                self.out.extend(if reuse_cache {
                    selector.clone().encode()
                } else {
                    Variable::SetCache(Box::new(owner), Box::new(selector.clone())).encode()
                });
                self.out
                    .push(if mode == 2 || mode == 3 { 0xffff } else { argc });
                finish_native_statement_call(
                    &mut self.reader,
                    &mut self.out,
                    &mut self.offsets,
                    discard_result,
                );
                self.state.last_reference_push = None;
                self.state.cached_world_owner = false;
                if let Some(pending) = &mut self.state.pending_world_ref {
                    pending.rhs_changed_cache = true;
                }
            }
            0x0a => CallLowering {
                code,
                reader: &mut self.reader,
                ids,
                start,
                out: &mut self.out,
                offsets: &mut self.offsets,
                fixups: &mut self.fixups,
                world_flow,
                state: &mut self.state,
                pending_view_range_iterator: &mut self.pending_view_range_iterator,
                pending_orange_iterator: &mut self.pending_orange_iterator,
                is_initializer,
            }
            .lower()?,
            0x87 => {
                // PushNRefs: an int32 count followed by references
                let count = self.reader.word()?;
                if count as usize > self.reader.code.len().saturating_sub(self.reader.at) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "PushNRefs count exceeds available operands".into(),
                    });
                }
                let mut references = Vec::with_capacity(count as usize);
                for _ in 0..count {
                    references.push(reference(&mut self.reader, ids)?);
                }
                if count == 2 && self.reader.code.get(self.reader.at) == Some(&0x36) {
                    // OpenDream pushes item then list. BYOND IsIn expects
                    // list then item. Reordering direct references is safe.
                    let item = references.remove(0);
                    let list = references.remove(0);
                    self.offsets
                        .insert(self.reader.at as u32, self.out.len() as u32);
                    self.reader.byte()?; // IsInList
                    self.out.push(0x33);
                    self.out.extend(list.encode());
                    self.out.push(0x33);
                    self.out.extend(item.encode());
                    self.out.extend([0xa9, 5, 0x36]);
                    self.state.last_reference_push = None;
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                if count == 3
                    && self.reader.code.get(self.reader.at..self.reader.at + 2) == Some(&[0x85, 7])
                {
                    // OpenDream list assignment uses list, key, value;
                    // DreamMaker's ListSet consumes value, list, key.
                    let list = references.remove(0);
                    let key = references.remove(0);
                    let value = references.remove(0);
                    self.offsets
                        .insert(self.reader.at as u32, self.out.len() as u32);
                    self.reader.byte()?; // AssignNoPush
                    self.reader.byte()?; // indexed reference
                    for var in [value, list, key] {
                        self.out.push(0x33);
                        self.out.extend(var.encode());
                    }
                    self.out.push(0x7c);
                    self.state.last_reference_push = None;
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                for var in references {
                    let at = self.out.len();
                    self.out.push(0x33);
                    if var == Variable::World {
                        world_flow.reused |= self.state.cached_world_owner;
                        self.state.pending_world_ref = Some(PendingWorld {
                            at,
                            world_cached_at_push: self.state.cached_world_owner,
                            rhs_changed_cache: false,
                        });
                    } else if matches!(var, Variable::SetCache(_, _)) {
                        self.state.cached_world_owner = false;
                        if let Some(pending) = &mut self.state.pending_world_ref {
                            pending.rhs_changed_cache = true;
                        }
                    }
                    self.state.last_reference_push = Some((at, var.clone()));
                    self.out.extend(var.encode());
                }
                self.state.last_push_nrefs = Some((self.reader.at, count));
            }
            0x36 => {
                // Mixed-width references in `item in list` cannot use the
                // compact PushNRefs lookahead above. The preceding two GetVar
                // instructions still identify the pure item/list operands.
                let instructions =
                    byond_dmb::bytecode::decode(&self.out).map_err(|error| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: format!("cannot inspect IsInList operands: {}", error.reason),
                    })?;
                let pair = instructions
                    .get(instructions.len().saturating_sub(2)..)
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "IsInList lacks item and list".into(),
                    })?;
                if pair.len() != 2 {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "IsInList lacks two complete operand expressions".into(),
                    });
                }
                if pair[1].opcode != 0x33 {
                    let list_at =
                        constructor_argument_start(&self.out, 1).ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "IsInList computed list has unknown stack effects".into(),
                        })?;
                    let item_at =
                        constructor_argument_start(&self.out[..list_at], 1).ok_or_else(|| {
                            LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason:
                                    "IsInList item before computed list has unknown stack effects"
                                        .into(),
                            }
                        })?;
                    let mut replacement = self.out[list_at..].to_vec();
                    replacement.extend_from_slice(&self.out[item_at..list_at]);
                    replacement.extend([0xa9, 5]);
                    if self.reader.code.get(self.reader.at) != Some(&0x0c)
                        || self
                            .fixups
                            .iter()
                            .any(|fixup| fixup.target as usize == self.reader.at)
                    {
                        replacement.push(0x36);
                    }
                    let old_len = self.out.len() - item_at;
                    replace_words(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        item_at,
                        old_len,
                        &replacement,
                    );
                    self.state.last_reference_push = None;
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                let mut replacement = Vec::new();
                if pair[0].opcode == 0x35 {
                    // OpenDream reuses an assignment's pushed value as the
                    // membership item. Native BYOND evaluates that assignment
                    // once, then reloads the assigned reference after the list.
                    replacement.push(0x34);
                    replacement.extend(&pair[0].operands);
                    replacement.push(0x33);
                    replacement.extend(&pair[1].operands);
                    replacement.push(0x33);
                    replacement.extend(&pair[0].operands);
                } else if pair[0].opcode == 0x60 && pair[0].operands == [0, 0] {
                    replacement.push(0x33);
                    replacement.extend(&pair[1].operands);
                    replacement.extend([0x33, 0xffe6]); // Native null reference
                } else if pair[0].opcode == 0x33 {
                    for item in pair.iter().rev() {
                        replacement.push(item.opcode);
                        replacement.extend(&item.operands);
                    }
                } else {
                    let list_at = pair[1].offset;
                    let item_at =
                        constructor_argument_start(&self.out[..list_at], 1).ok_or_else(|| {
                            LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "IsInList item expression has unknown stack effects".into(),
                            }
                        })?;
                    let mut computed = self.out[list_at..].to_vec();
                    computed.extend_from_slice(&self.out[item_at..list_at]);
                    computed.extend([0xa9, 5]);
                    if self.reader.code.get(self.reader.at) != Some(&0x0c)
                        || self
                            .fixups
                            .iter()
                            .any(|fixup| fixup.target as usize == self.reader.at)
                    {
                        computed.push(0x36);
                    }
                    let old_len = self.out.len() - item_at;
                    replace_words(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        item_at,
                        old_len,
                        &computed,
                    );
                    self.state.last_reference_push = None;
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                replacement.extend([0xa9, 5]);
                // A short-circuit predecessor reaches the condition with a
                // boolean value, so the join must Test that value on every
                // edge rather than rely on the final producer's comparison flag.
                let condition_is_join = self
                    .fixups
                    .iter()
                    .any(|fixup| fixup.target as usize == self.reader.at);
                if self.reader.code.get(self.reader.at) != Some(&0x0c) || condition_is_join {
                    replacement.push(0x36);
                }
                let at = pair[0].offset;
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
            }
            _ => return Ok(OpcodeFlow::Unhandled),
        }
        Ok(OpcodeFlow::Advance)
    }
}
