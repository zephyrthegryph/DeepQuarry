use super::*;

impl<R: SymbolResolver> PassState<'_, R> {
    pub(super) fn prepare_instruction(&mut self) -> Result<Option<(usize, u8, bool)>, LowerError> {
        let code = self.inputs.code;
        let ids = self.inputs.ids;
        let world_flow = &mut *self.world_flow;
        let local_events = self.inputs.local_events;
        let source_info = self.inputs.source_info;
        let reverse_initial_debug_marker = self.inputs.reverse_initial_debug_marker;
        let start = self.reader.at;
        if world_flow.joins.contains(&(start as u32)) {
            self.state.cached_world_owner = false;
            if let Some(pending) = &mut self.state.pending_world_ref {
                pending.rhs_changed_cache = true;
            }
        }
        self.iterator_states
            .insert(start, self.iterator_frames.clone());
        while self.local_event_index < local_events.len()
            && local_events[self.local_event_index].offset <= start
        {
            let event = &local_events[self.local_event_index];
            if let Some(remove) = event.remove {
                if remove > self.reader.local_slots.len() {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: event.offset,
                        reason: "OpenDream local lifetime removes inactive slots".into(),
                    });
                }
                self.reader
                    .local_slots
                    .truncate(self.reader.local_slots.len() - remove);
            }
            if event.add.is_some() {
                self.reader
                    .local_slots
                    .push(self.native_slot_for_add[self.add_ordinal]);
                self.add_ordinal += 1;
            }
            self.local_event_index += 1;
        }
        if self.delete_clear_cache_end == Some(start as u32) {
            self.out.push(0x143);
            self.delete_clear_cache_end = None;
        }
        self.offsets.insert(start as u32, self.out.len() as u32);
        if let Some((_, count)) = self
            .safe
            .nested_safe_pop
            .filter(|(target, _)| *target == start as u32)
        {
            let join_depth = cache_frame_depth(&self.out);
            for (index, fixup) in self.fixups.iter().enumerate().filter(|(_, fixup)| {
                fixup.target == start as u32
                    && (matches!(code.get(fixup.source), Some(0x15 | 0x2f))
                        || code.get(fixup.source) == Some(&0x0e)
                            && fixup.source < start
                            && !ids.native_goto(fixup.source))
            }) {
                // A short-circuit/conditional expression edge can skip guarded
                // RHS receivers entirely. Authored goto remains separate.
                // Skip only the cleanup frames this edge never acquired; an
                // inner guard/branch may still owe its enclosing receiver frame.
                let edge_depth = cache_frame_depth(&self.out[..fixup.at.saturating_sub(1)]);
                let skip = join_depth.saturating_sub(edge_depth).min(count as usize) as u32;
                self.safe
                    .safe_skip_pop
                    .entry(index)
                    .and_modify(|prior| *prior = (*prior).max(skip))
                    .or_insert(skip);
            }
            self.out.extend(std::iter::repeat_n(0x143, count as usize));
            self.safe.nested_safe_pop = None;
            self.safe.safe_chain_fixups.clear();
        }
        let source_events = source_info.unwrap_or(&[]);
        while self.source_event_index < source_events.len()
            && source_events[self.source_event_index].offset <= start
        {
            let event = &source_events[self.source_event_index];
            if reverse_initial_debug_marker && self.source_event_index == 0 {
                if event.line > 0 {
                    self.out.extend([0x85, event.line as u32]);
                }
                if let Some(file) = event.file {
                    let file = mapped(ids.string(file as u32), start, "source filename")?;
                    self.out.extend([0x84, file]);
                }
                self.source_event_index += 1;
                continue;
            }
            if let Some(file) = event.file {
                let file = mapped(ids.string(file as u32), start, "source filename")?;
                self.out.extend([0x84, file]);
            }
            if event.line > 0 {
                self.out.extend([0x85, event.line as u32]);
            }
            self.source_event_index += 1;
        }
        let op = self.reader.byte()?;
        if self.reader.code.get(self.reader.at) == Some(&7)
            && matches!(
                op,
                0x56 | 0x57
                    | 0x62
                    | 0x63
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
                    | 0x66
                    | 0x67
                    | 0x74
            )
        {
            // These indexed operators emit SetVar(Cache) for their list
            // receiver. A previous world field no longer owns that cache.
            self.state.cached_world_owner = false;
            if let Some(pending) = &mut self.state.pending_world_ref {
                pending.rhs_changed_cache = true;
            }
        }
        if let Some((_, body_at)) = self
            .safe
            .pending_safe_index_lvalue
            .filter(|(at, _)| *at == start)
        {
            self.safe.pending_safe_index_lvalue = None;
            let value_at = constructor_argument_start(&self.out[body_at..], 1)
                .map(|at| body_at + at)
                .ok_or_else(|| LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "safe indexed lvalue value has unknown stack effects".into(),
                })?;
            let key_at =
                constructor_argument_start(&self.out[body_at..value_at], 1).map(|at| body_at + at);
            let cached_list_field = key_at.filter(|at| *at > body_at).and_then(|at| {
                let items = crate::bytecode::decode(&self.out[body_at..at]).ok()?;
                let [item] = items.as_slice() else {
                    return None;
                };
                (item.opcode == 0x33
                    && matches!(
                        Variable::decode(&item.operands),
                        Ok((Variable::Field(_), _))
                    ))
                .then_some(at)
            });
            if key_at != Some(body_at) && cached_list_field.is_none() {
                return Err(LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "safe indexed lvalue key has unknown stack effects".into(),
                });
            }
            self.reader.byte()?; // Verified Index reference, no operands.
            let end = self.out.len();
            let value_len = end - value_at;
            let mut replacement = self.out[value_at..end].to_vec();
            replacement.push(0x143);
            if cached_list_field.is_none() {
                replacement.extend([0x33, 0xffd8]);
            }
            replacement.extend_from_slice(&self.out[body_at..value_at]);
            replacement.extend(if op == 0x1a {
                vec![0x34, 0xffe3, 0x34, 0xffd8, 0x45, 0xffe4]
            } else {
                vec![0x7c]
            });
            let cache_read_len = if cached_list_field.is_some() { 1 } else { 3 };
            let moved = |old: usize| {
                if old < value_at {
                    body_at + value_len + cache_read_len + old - body_at
                } else {
                    body_at + old - value_at
                }
            };
            let moved_offsets = self
                .offsets
                .iter()
                .filter(|(_, value)| **value as usize >= body_at && (**value as usize) < end)
                .map(|(key, value)| (*key, moved(*value as usize) as u32))
                .collect::<Vec<_>>();
            let moved_fixups = self
                .fixups
                .iter()
                .enumerate()
                .filter(|(_, fixup)| fixup.at >= body_at && fixup.at < end)
                .map(|(index, fixup)| (index, moved(fixup.at)))
                .collect::<Vec<_>>();
            replace_words(
                &mut self.out,
                &mut self.offsets,
                &mut self.fixups,
                body_at,
                end - body_at,
                &replacement,
            );
            self.offsets.extend(moved_offsets);
            for (index, at) in moved_fixups {
                self.fixups[index].at = at;
            }
            self.offsets
                .insert(self.reader.at as u32, self.out.len() as u32);
            if let Some((_, count)) = self
                .safe
                .nested_safe_pop
                .filter(|(target, _)| *target == self.reader.at as u32)
            {
                self.out.extend(std::iter::repeat_n(0x143, count as usize));
                self.safe.nested_safe_pop = None;
                self.safe.safe_chain_fixups.clear();
            }
            self.reader.byte()?; // Discarded statement result.
            return Ok(None);
        }
        if let Some((_, discard)) = self
            .safe
            .pending_safe_lvalue_at
            .filter(|(at, _)| *at == start)
        {
            let chained_body = self.safe.pending_safe_lvalue_body.take();
            if chained_body.is_none() {
                self.out.push(0x143); // Restore safe lvalue receiver after RHS evaluation.
            }
            self.safe.pending_safe_lvalue_at = None;
            self.safe.pending_safe_aug_sub = false;
            let target = reference(&mut self.reader, ids)?;
            let native_op = match op {
                0x09 | 0x85 => {
                    if discard {
                        0x34
                    } else {
                        0x35
                    }
                }
                0x1a => 0x45,
                0x1f => 0x46,
                0x0b => 0x47,
                0x17 => 0x48,
                0x39 => 0x49,
                0x33 => 0x4a,
                0x2d => 0x4b,
                0x29 => 0x4c,
                0x6d => 0x4d,
                0x6e => 0x4e,
                0x56 => {
                    if discard {
                        0x66
                    } else {
                        0x63
                    }
                }
                0x57 => {
                    if discard {
                        0x67
                    } else {
                        0x65
                    }
                }
                0x62 => {
                    if discard {
                        0x66
                    } else {
                        0x62
                    }
                }
                0x63 => {
                    if discard {
                        0x67
                    } else {
                        0x64
                    }
                }
                _ => unreachable!("safe lvalue terminal was checked before setting pending state"),
            };
            if let Some(body_at) = chained_body {
                let end = self.out.len();
                let has_rhs = !matches!(op, 0x56 | 0x57 | 0x62 | 0x63);
                let rhs_at = if has_rhs {
                    guarded_assignment_spans(&self.out, code, &self.offsets, &self.fixups, start, 1)
                        .filter(|(owner, _)| *owner >= body_at)
                        .map(|(_, rhs)| rhs)
                        .or_else(|| {
                            constructor_argument_start(&self.out[body_at..], 1)
                                .map(|at| body_at + at)
                        })
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "guarded field RHS has unknown stack effects".into(),
                        })?
                } else {
                    end
                };
                let owner_words = self.out[body_at..rhs_at].to_vec();
                let owner_instructions =
                    crate::bytecode::decode(&owner_words).map_err(|error| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: error.reason,
                    })?;
                let executable: Vec<_> = owner_instructions
                    .iter()
                    .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
                    .collect();
                let direct = if let [item] = executable.as_slice() {
                    (item.opcode == 0x33)
                        .then(|| {
                            Variable::decode(&item.operands)
                                .ok()
                                .map(|(owner, _)| owner)
                        })
                        .flatten()
                } else {
                    None
                };
                let rhs_len = end - rhs_at;
                let direct_owner = direct.is_some();
                let mut replacement = self.out[rhs_at..end].to_vec();
                let action_at;
                if let Some(owner) = direct {
                    for item in &owner_instructions {
                        if matches!(item.opcode, 0x84 | 0x85) {
                            replacement.extend_from_slice(
                                &owner_words[item.offset..item.offset + 1 + item.operands.len()],
                            );
                        }
                    }
                    replacement.push(0x143);
                    action_at = body_at + replacement.len();
                    replacement.push(native_op);
                    let destination = match target {
                        Variable::Field(field) => append_field(owner, field),
                        other => Variable::SetCache(Box::new(owner), Box::new(other)),
                    };
                    replacement.extend(destination.encode());
                } else {
                    replacement.extend_from_slice(&owner_words);
                    replacement.extend([0x34, 0xffd8]);
                    action_at = body_at + replacement.len();
                    replacement.push(native_op);
                    replacement.extend(target.encode());
                    replacement.push(0x143);
                }
                let rhs_join = u32::MAX - start as u32;
                let owner_join = rhs_join - 1;
                let mut moved_offsets = Vec::new();
                for (&source, &old) in &self.offsets {
                    let old = old as usize;
                    if old >= body_at && old < end {
                        let new = if old >= rhs_at {
                            body_at + old - rhs_at
                        } else if direct_owner {
                            action_at
                        } else {
                            body_at + rhs_len + old - body_at
                        };
                        moved_offsets.push((source, new as u32));
                    }
                }
                let mut moved_fixups = Vec::new();
                for (index, fixup) in self.fixups.iter_mut().enumerate() {
                    if fixup.at >= body_at && fixup.at < end {
                        if fixup.at >= rhs_at && fixup.target == start as u32 {
                            fixup.target = rhs_join;
                        } else if fixup.at < rhs_at
                            && (fixup.target == start as u32
                                || self.offsets.get(&fixup.target).copied() == Some(rhs_at as u32))
                        {
                            fixup.target = owner_join;
                        }
                        let new = if fixup.at >= rhs_at {
                            body_at + fixup.at - rhs_at
                        } else {
                            body_at + rhs_len + fixup.at - body_at
                        };
                        moved_fixups.push((index, new));
                    }
                }
                replace_words(
                    &mut self.out,
                    &mut self.offsets,
                    &mut self.fixups,
                    body_at,
                    end - body_at,
                    &replacement,
                );
                self.offsets.extend(moved_offsets);
                for (index, at) in moved_fixups {
                    self.fixups[index].at = at;
                }
                self.offsets.insert(rhs_join, (body_at + rhs_len) as u32);
                self.offsets
                    .insert(owner_join, (body_at + rhs_len + owner_words.len()) as u32);
                self.offsets.insert(start as u32, action_at as u32);
            } else {
                self.out.push(native_op);
                emit_tracked_reference(
                    &mut self.out,
                    &target,
                    &mut self.state.cached_world_owner,
                    &mut self.state.pending_world_ref,
                );
            }
            if !discard && matches!(op, 0x1a | 0x1f) {
                self.out.push(0x13f); // Paired safe augmented expression result.
            }
            if discard {
                self.offsets
                    .insert(self.reader.at as u32, self.out.len() as u32);
                if let Some((_, count)) = self
                    .safe
                    .nested_safe_pop
                    .filter(|(join, _)| *join == self.reader.at as u32)
                {
                    self.out.extend(std::iter::repeat_n(0x143, count as usize));
                    self.safe.nested_safe_pop = None;
                    self.safe.safe_chain_fixups.clear();
                }
                self.reader.byte()?; // Paired statement Pop is included in the safe join.
            }
            if let Some((at, discard, body)) = self.safe.pending_safe_lvalue_stack.pop() {
                self.safe.pending_safe_lvalue_at = Some((at, discard));
                self.safe.pending_safe_lvalue_body = body;
            }
            return Ok(None);
        }
        let follows_format = self.state.last_was_format;
        self.state.last_was_format = false;
        if self.safe.pending_safe_field && op != 0x68 {
            return Err(LowerError {
                kind: LowerErrorKind::MalformedControlFlow,
                offset: start,
                reason: "safe dereference requires an immediate field access".into(),
            });
        }
        if lower_literal_switch_chain(
            &mut self.reader,
            ids,
            start,
            op,
            &mut self.out,
            &mut self.offsets,
            &mut self.fixups,
        )? {
            self.state.last_reference_push = None;
            self.state.cached_world_owner = false;
            return Ok(None);
        }
        Ok(Some((start, op, follows_format)))
    }
}
