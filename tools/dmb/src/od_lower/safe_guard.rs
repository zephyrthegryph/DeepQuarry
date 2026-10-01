/// Lower null-guarded member access and its receiver cleanup branches.
struct SafeGuardLowering<'a, 'code, R: SymbolResolver> {
    code: &'code [u8],
    reader: &'a mut Reader<'code>,
    ids: &'a R,
    start: usize,
    out: &'a mut Vec<u32>,
    offsets: &'a mut HashMap<u32, u32>,
    fixups: &'a mut Vec<Fixup>,
    state: &'a mut LowerState,
    safe: &'a mut SafeAccessState,
    pending_receivers: &'a mut Vec<PendingReceiver>,
    guarded_assign_into: &'a mut HashMap<usize, (usize, usize)>,
    guarded_assign_into_nested: &'a mut std::collections::HashSet<usize>,
}

impl<R: SymbolResolver> SafeGuardLowering<'_, '_, R> {
    /// Returns true when the source loop must begin a new instruction.
    fn lower(&mut self) -> Result<bool, LowerError> {
        let code = self.code;
        let reader = &mut *self.reader;
        let ids = self.ids;
        let start = self.start;
        let mut out = &mut *self.out;
        let mut offsets = &mut *self.offsets;
        let mut fixups = &mut *self.fixups;
        let state = &mut *self.state;
        let safe = &mut *self.safe;
        let pending_receivers = &mut *self.pending_receivers;
        let guarded_assign_into = &mut *self.guarded_assign_into;
        let guarded_assign_into_nested = &mut *self.guarded_assign_into_nested;
        // A safe const-null member evaluates its receiver for the
        // guard, then reads the declaration's native global binding.
        // Native SetCacheJmpIfNull already consumes the non-null owner;
        // the exporter-only Eval assignment must not consume it again.
        if reader.code.get(reader.at + 4..reader.at + 6) == Some(&[0x85, 17]) {
            let target = reader.word()?;
            out.extend([0x13d, 0]);
            fixups.push(Fixup {
                at: out.len() - 1,
                target,
                source: start,
            });
            offsets.insert(reader.at as u32, out.len() as u32);
            reader.at += 2; // AssignNoPush native Cache, consumed by the guard.
            state.last_reference_push = None;
            state.cached_world_owner = false;
            if let Some(pending) = &mut state.pending_world_ref {
                pending.rhs_changed_cache = true;
            }
            return Ok(true);
        }
        // Native AssignInto encodes the receiver through its cache
        // reference without a separate null-guard instruction.
        if let Some(terminal) = reader
            .code
            .get(reader.at..reader.at + 4)
            .and_then(|bytes| <[u8; 4]>::try_from(bytes).ok())
            .map(u32::from_le_bytes)
            .and_then(|target| (target as usize).checked_sub(6))
            .filter(|at| code.get(*at) == Some(&0x74) && code.get(*at + 1) == Some(&12))
        {
            reader.word()?;
            if let std::collections::hash_map::Entry::Vacant(e) =
                guarded_assign_into.entry(terminal)
            {
                let base_at = constructor_argument_start(&out, 1).ok_or_else(|| LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "guarded AssignInto base has unknown stack effects".into(),
                })?;
                out.extend([0x34, 0xffd8]);
                e.insert((base_at, out.len()));
                safe.pending_safe_field = reader.code.get(reader.at) == Some(&0x68);
            } else {
                // Native materializes the intermediate owner for each
                // additional guarded receiver before AssignInto.
                guarded_assign_into_nested.insert(terminal);
            }
            state.last_reference_push = None;
            state.cached_world_owner = false;
            if let Some(pending) = &mut state.pending_world_ref {
                pending.rhs_changed_cache = true;
            }
            return Ok(true);
        }
        state.cached_world_owner = false; // Safe receivers become the active cache.
        if let Some(pending) = &mut state.pending_world_ref {
            pending.rhs_changed_cache = true;
        }
        let indexed_lvalue = reader
            .code
            .get(reader.at..reader.at + 4)
            .and_then(|bytes| bytes.try_into().ok())
            .map(u32::from_le_bytes)
            .and_then(|target| {
                let at = (target as usize).checked_sub(2)?;
                (reader.code.get(at + 1) == Some(&7)
                    && reader.code.get(target as usize) == Some(&0x51)
                    && matches!(reader.code.get(at), Some(0x09 | 0x85 | 0x1a)))
                .then_some((target, at))
            });
        if let Some((target, at)) = indexed_lvalue {
            if let Some((field_at, prior_target, outer_index, end_byte)) =
                safe.last_safe_field.take()
            {
                if prior_target == target && end_byte == start {
                    out[fixups[outer_index].at - 1] = 0x13e;
                    if out.get(field_at.wrapping_sub(1)) != Some(&0x142) {
                        replace_words(&mut out, &mut offsets, &mut fixups, field_at, 0, &[0x142]);
                    }
                    safe.safe_chain_fixups.push(outer_index);
                    for index in &safe.safe_chain_fixups {
                        *safe.safe_skip_pop.entry(*index).or_default() += 1;
                    }
                    safe.nested_safe_pop = Some((
                        target,
                        safe.nested_safe_pop.map_or(1, |(_, count)| count + 1),
                    ));
                }
            }
            reader.word()?;
            out.extend([0x13e, 0, 0x142]);
            fixups.push(Fixup {
                at: out.len() - 2,
                target,
                source: start,
            });
            safe.pending_safe_index_lvalue = Some((at, out.len()));
            safe.pending_safe_field = reader.code.get(reader.at) == Some(&0x68);
            state.last_reference_push = None;
            return Ok(true);
        }
        let computed_index_target = reader
            .code
            .get(reader.at..reader.at + 4)
            .and_then(|bytes| bytes.try_into().ok())
            .map(u32::from_le_bytes)
            .filter(|target| {
                // Paired ___TraitRemove has a direct reference key;
                // ___TraitAdd formats that reference first.
                let direct = *target as usize == reader.at + 8
                    && reader.code.get(reader.at + 4) == Some(&0x06)
                    && reader.code.get(reader.at + 7) == Some(&0x69);
                let formatted = *target as usize == reader.at + 17
                    && reader.code.get(reader.at + 4) == Some(&0x06)
                    && reader.code.get(reader.at + 7) == Some(&0x04)
                    && reader.code.get(reader.at + 16) == Some(&0x69);
                let body_at = reader.at + 4;
                // A safe method can itself be followed by a safe index
                // with the same exit. Its receiver marker belongs to
                // the call, rather than the final indexed value.
                let receiver_method = matches!(reader.code.get(body_at), Some(0x6a | 0xaa))
                    || (reader.code.get(body_at) == Some(&0x68)
                        && reader.code.get(body_at + 5) == Some(&0x65))
                    || (reader.code.get(body_at) == Some(&0x02)
                        && matches!(reader.code.get(body_at + 5), Some(0x6a | 0xaa)));
                let expression = *target as usize > body_at
                    && reader.code.get(*target as usize - 1) == Some(&0x69)
                    && !receiver_method;
                direct || formatted || expression
            });
        if reader.code.get(reader.at + 4) == Some(&0x03)
            && reader.code.get(reader.at + 9) == Some(&0x69)
            && computed_index_target == Some((reader.at + 10) as u32)
        {
            // `owner?.field[key]`: keep the cached receiver through
            // the indexed access, then restore the prior cache.
            let target = reader.word()?;
            let string_at = reader.at;
            reader.byte()?;
            let key = mapped(ids.string(reader.word()?), start, "safe index key")?;
            let index_at = reader.at;
            reader.byte()?;
            if reader.at as u32 != target {
                return Err(LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "safe indexed access has an unverified branch target".into(),
                });
            }
            out.extend([0x13d, 0]);
            fixups.push(Fixup {
                at: out.len() - 1,
                target,
                source: start,
            });
            out.extend([0x142, 0x33, 0xffd8]);
            offsets.insert(string_at as u32, out.len() as u32);
            push_value(&mut out, 6, key);
            offsets.insert(index_at as u32, out.len() as u32);
            out.extend([0x7b, 0x143]);
            state.last_reference_push = None;
            return Ok(true);
        }
        if let Some(target) = computed_index_target {
            reader.word()?;
            if safe
                .pending_safe_index
                .take()
                .is_some_and(|prior_target| prior_target == target)
                && !safe
                    .last_safe_index
                    .is_some_and(|(end_byte, prior_target, _)| {
                        end_byte == start && prior_target == target
                    })
            {
                // A guarded parent expression can contain a method
                // before its final guarded index. The inner guard must
                // not overwrite the outer saved cache frame.
                if let Some((outer_index, _)) = fixups
                    .iter()
                    .enumerate()
                    .rev()
                    .find(|(_, fixup)| fixup.target == target)
                {
                    safe.safe_chain_fixups.push(outer_index);
                    for index in &safe.safe_chain_fixups {
                        *safe.safe_skip_pop.entry(*index).or_default() += 1;
                    }
                    safe.nested_safe_pop = Some((
                        target,
                        safe.nested_safe_pop.map_or(1, |(_, count)| count + 1),
                    ));
                }
            }
            if let Some((end_byte, prior_target, outer_index)) = safe.last_safe_index.take() {
                if end_byte == start && prior_target == target {
                    safe.safe_chain_fixups.push(outer_index);
                    for index in &safe.safe_chain_fixups {
                        *safe.safe_skip_pop.entry(*index).or_default() += 1;
                    }
                    safe.nested_safe_pop = Some((
                        target,
                        safe.nested_safe_pop.map_or(1, |(_, count)| count + 1),
                    ));
                }
            }
            out.extend([0x13d, 0]);
            fixups.push(Fixup {
                at: out.len() - 1,
                target,
                source: start,
            });
            out.extend([0x142, 0x33, 0xffd8]);
            safe.pending_safe_index = Some(target);
            state.last_reference_push = None;
            return Ok(true);
        }
        if reader.code.get(reader.at + 4) == Some(&0x03)
            && matches!(reader.code.get(reader.at + 9), Some(0x47 | 0x53))
        {
            let _null_exit = reader.word()?;
            let string_at = reader.at;
            reader.byte()?; // PushString
            let field = mapped(ids.string(reader.word()?), start, "initial field")?;
            let initial_at = reader.at;
            let operation = reader.byte()?; // Initial or IsSaved
            out.extend([
                0x34,
                0xffd8,
                0x33,
                if operation == 0x47 { 0xffe7 } else { 0xffe8 },
                field,
            ]);
            offsets.insert(string_at as u32, out.len() as u32);
            offsets.insert(initial_at as u32, out.len() as u32);
            state.last_reference_push = None;
            return Ok(true);
        }
        let next_is_field = reader.code.get(reader.at + 4) == Some(&0x68);
        let safe_target = reader
            .code
            .get(reader.at..reader.at + 4)
            .and_then(|bytes| bytes.try_into().ok())
            .map(u32::from_le_bytes)
            .map(|target| target as usize);
        let safe_lvalue_at = safe_target.and_then(|target| {
            let at = target.checked_sub(6)?;
            let body = reader.code.get(at..=target)?;
            (body[1] == 12
                && matches!(
                    body[0],
                    0x09 | 0x85
                        | 0x1a
                        | 0x1f
                        | 0x0b
                        | 0x17
                        | 0x39
                        | 0x33
                        | 0x2d
                        | 0x29
                        | 0x6d
                        | 0x6e
                        | 0x56
                        | 0x57
                        | 0x62
                        | 0x63
                )
                && (body[6] == 0x51
                    || matches!(
                        body[0],
                        0x09 | 0x85 | 0x1a | 0x1f | 0x56 | 0x57 | 0x62 | 0x63
                    )))
            .then_some((at, body[6] == 0x51))
        });
        let mut chain_end = reader.at + 4;
        while reader.code.get(chain_end) == Some(&0x68) {
            chain_end += 5;
        }
        // A further guard consumes the intermediate owner itself.
        // Preserve the established nested-guard cache restoration path.
        if let Some((at, discard)) =
            safe_lvalue_at.filter(|_| !next_is_field || reader.code.get(chain_end) != Some(&0x65))
        {
            let target = reader.word()?;
            if safe
                .pending_safe_lvalue_at
                .is_some_and(|(outer_at, _)| outer_at == at)
            {
                if let Some(outer_body) = safe.pending_safe_lvalue_body.take() {
                    if let Some((outer_index, _)) = fixups
                        .iter()
                        .enumerate()
                        .find(|(_, fixup)| fixup.at + 2 == outer_body)
                    {
                        safe.safe_chain_fixups.push(outer_index);
                        for index in &safe.safe_chain_fixups {
                            *safe.safe_skip_pop.entry(*index).or_default() += 1;
                        }
                        safe.nested_safe_pop = Some((
                            target,
                            safe.nested_safe_pop.map_or(1, |(_, count)| count + 1),
                        ));
                    }
                }
            }
            // DreamMaker preserves the guarded base, then traverses
            // chained lvalue fields after evaluating the RHS. Keeping
            // an intermediate field on the stack would leave mutation
            // targeting the guarded base instead of that field owner.
            if let Some((field_at, prior_target, outer_index, end_byte)) =
                safe.last_safe_field.take()
            {
                if end_byte == start && prior_target == target {
                    out[fixups[outer_index].at - 1] = if discard { 0x13e } else { 0x13d };
                    replace_words(&mut out, &mut offsets, &mut fixups, field_at, 0, &[0x142]);
                    safe.safe_chain_fixups.push(outer_index);
                    for index in &safe.safe_chain_fixups {
                        *safe.safe_skip_pop.entry(*index).or_default() += 1;
                    }
                    safe.nested_safe_pop = Some((
                        target,
                        safe.nested_safe_pop.map_or(1, |(_, count)| count + 1),
                    ));
                }
            }
            out.extend([if discard { 0x13e } else { 0x13d }, 0, 0x142]);
            fixups.push(Fixup {
                at: out.len() - 2,
                target,
                source: start,
            });
            if let Some((outer_at, outer_discard)) = safe.pending_safe_lvalue_at {
                if outer_at != at {
                    safe.pending_safe_lvalue_stack.push((
                        outer_at,
                        outer_discard,
                        safe.pending_safe_lvalue_body.take(),
                    ));
                }
            }
            safe.pending_safe_lvalue_at = Some((at, discard));
            if next_is_field {
                safe.pending_safe_field = true;
                safe.pending_safe_lvalue_body = Some(out.len());
            }
            state.last_reference_push = None;
            return Ok(true);
        }
        let method_before_exit = safe_target.is_some_and(|target| {
            reader
                .code
                .get(reader.at + 4..target)
                .is_some_and(|body| body.contains(&0x6a) || body.contains(&0xaa))
        });
        let aug_sub_before_exit = safe_target.is_some_and(|target| {
            reader.code.get(reader.at + 4..target).is_some_and(|body| {
                body.len() >= 6 && body[body.len() - 6] == 0x1f && body[body.len() - 5] == 12
            })
        });
        if !next_is_field && !method_before_exit && !aug_sub_before_exit {
            return Err(LowerError {
                kind: LowerErrorKind::MalformedControlFlow,
                offset: start,
                reason: "safe dereference lacks a paired field or method call".into(),
            });
        }
        safe.pending_safe_field = next_is_field;
        state.last_reference_push = None;
        let target = reader.word()?;
        if aug_sub_before_exit {
            safe.pending_safe_aug_sub = true;
        } else if !next_is_field {
            pending_receivers.push(PendingReceiver::SafeCached);
        }
        if let Some((field_at, prior_target, outer_index, end_byte)) = safe.last_safe_field.take() {
            if end_byte == start && prior_target == target {
                if safe
                    .nested_safe_pop
                    .is_some_and(|(pop_target, _)| pop_target != target)
                {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "multiple nested safe chains with different exits are not verified"
                            .into(),
                    });
                }
                replace_words(&mut out, &mut offsets, &mut fixups, field_at, 0, &[0x142]);
                safe.safe_chain_fixups.push(outer_index);
                for index in &safe.safe_chain_fixups {
                    *safe.safe_skip_pop.entry(*index).or_default() += 1;
                }
                safe.nested_safe_pop = Some((
                    target,
                    safe.nested_safe_pop.map_or(1, |(_, count)| count + 1),
                ));
            }
        }
        out.extend([if aug_sub_before_exit { 0x13e } else { 0x13d }, 0]);
        fixups.push(Fixup {
            at: out.len() - 1,
            target,
            source: start,
        });
        if !next_is_field {
            out.push(0x142); // Preserve safe-call receiver through arguments.
        }

        Ok(false)
    }
}
