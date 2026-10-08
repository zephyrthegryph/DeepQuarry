use super::*;

impl<R: SymbolResolver> PassState<'_, R> {
    pub(super) fn lower_enumerators_augmented(
        &mut self,
        start: usize,
        op: u8,
        _follows_format: bool,
    ) -> Result<OpcodeFlow, LowerError> {
        let code = self.inputs.code;
        let ids = self.inputs.ids;
        match op {
            0x4b => {
                if ids.implicit_locate(start) {
                    let instructions =
                        crate::bytecode::decode(&self.out).map_err(|error| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: format!(
                                "cannot inspect implicit locate container: {}",
                                error.reason
                            ),
                        })?;
                    let world = instructions
                        .iter()
                        .rev()
                        .find(|item| !matches!(item.opcode, 0x84 | 0x85))
                        .filter(|item| {
                            item.opcode == 0x33 && item.operands == Variable::World.encode()
                        })
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "implicit locate annotation lacks synthesized world getter"
                                .into(),
                        })?;
                    replace_words(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        world.offset,
                        1 + world.operands.len(),
                        &[],
                    );
                    self.state.pending_world_ref = None;
                    self.state.last_reference_push = None;
                    self.out.push(0x5b);
                } else {
                    self.out.push(0x97);
                }
            }
            0x3a => {
                // CreateListEnumerator(id)
                let id = self.reader.word()?;
                begin_list_iterator(&mut self.out, &mut self.iterator_frames, id);
                let mode = self
                    .pending_view_range_iterator
                    .take()
                    .unwrap_or(if self.pending_orange_iterator { 14 } else { 5 });
                let mask = self.pending_iterator_mask.take().unwrap_or(0);
                self.out.extend([0x52, mode, mask]);
                self.pending_orange_iterator = false;
            }
            0xab => {
                // Native iterator filter provenance; legacy exports lack explicit `as` flags.
                self.pending_iterator_mask = Some(self.reader.word()?);
            }
            0x41 => {
                // CreateFilteredListEnumerator(id, type filter).
                let id = self.reader.word()?;
                let old_type = self.reader.word()?;
                let tag = ids.type_tag(old_type).ok_or_else(|| LowerError {
                    kind: LowerErrorKind::UnresolvedSymbol,
                    offset: start,
                    reason: "unresolved iterator filter type tag".into(),
                })?;
                let type_id = mapped(ids.type_id(old_type), start, "iterator filter type")?;
                begin_list_iterator(&mut self.out, &mut self.iterator_frames, id);
                let exported_mask = self.pending_iterator_mask.take().unwrap_or(0);
                let mask = if exported_mask == 0 {
                    ids.iterator_type_mask(old_type).unwrap_or(0)
                } else {
                    exported_mask
                };
                if mask & 0x1000 == 0 && ids.iterator_root_mask(old_type) != Some(mask) {
                    self.filtered_enumerators.insert(id, (tag, type_id));
                }
                // Native prefilters the coarse category before assigning the
                // loop lvalue, then checks the specific subtype below.
                self.out.extend([
                    0x52,
                    self.pending_view_range_iterator
                        .take()
                        .unwrap_or(if self.pending_orange_iterator { 14 } else { 5 }),
                    mask,
                ]);
                self.pending_orange_iterator = false;
            }
            0x5d => {
                // OpenDream's type iterator takes a type value; DreamMaker
                // iterates world and filters each result by that type.
                let id = self.reader.word()?;
                let instructions =
                    crate::bytecode::decode(&self.out).map_err(|error| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: format!("cannot inspect type iterator operand: {}", error.reason),
                    })?;
                let prior = instructions
                    .iter()
                    .rev()
                    .find(|item| !matches!(item.opcode, 0x84 | 0x85))
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "type iterator lacks a type value".into(),
                    })?;
                if prior.opcode != 0x60 {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "type iterator requires a literal type".into(),
                    });
                }
                let (value, _) = Value::decode(&prior.operands).map_err(|error| LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: format!("type iterator value cannot be decoded: {}", error.reason),
                })?;
                if value.tag() == 59 {
                    // Client enumeration is a native typed world iterator;
                    // world contents plus a manual istype filter omits clients.
                    replace_words(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        prior.offset,
                        1 + prior.operands.len(),
                        &[0x33, 0xffe5, 0x60, 59, 0],
                    );
                    begin_list_iterator(&mut self.out, &mut self.iterator_frames, id);
                    self.out.extend([0x52, 5, 0x4000]);
                    if self.reader.code.get(self.reader.at) == Some(&0x06)
                        && self.reader.code.get(self.reader.at + 1) == Some(&9)
                        && self.reader.code.get(self.reader.at + 3) == Some(&0x51)
                    {
                        self.offsets
                            .insert(self.reader.at as u32, self.out.len() as u32);
                        self.reader.at += 4;
                    }
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                if !matches!(value.tag(), 8..=11 | 32) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "type iterator value is not a supported path".into(),
                    });
                }
                let (mask, omit_filter) = ids
                    .world_iterator_mask(value.tag(), value.id())
                    .unwrap_or((0, false));
                let replacement = if mask == 0 {
                    vec![0x33, 0xffe5, 0x60, prior.operands[0], prior.operands[1]]
                } else {
                    vec![0x33, 0xffe5]
                };
                replace_words(
                    &mut self.out,
                    &mut self.offsets,
                    &mut self.fixups,
                    prior.offset,
                    1 + prior.operands.len(),
                    &replacement,
                );
                begin_list_iterator(&mut self.out, &mut self.iterator_frames, id);
                if mask != 0 && !omit_filter {
                    self.filtered_enumerators
                        .insert(id, (value.tag(), value.id()));
                }
                // Atoms use world.contents plus the native category prefilter;
                // non-atom types use the type-specific instance universe.
                self.out
                    .extend([0x52, 5, if mask == 0 { 0x4000 } else { mask }]);
                if self.reader.code.get(self.reader.at) == Some(&0x06)
                    && self.reader.code.get(self.reader.at + 1) == Some(&9)
                    && self.reader.code.get(self.reader.at + 3) == Some(&0x51)
                {
                    self.offsets
                        .insert(self.reader.at as u32, self.out.len() as u32);
                    self.reader.at += 4;
                }
            }
            0x3b => {
                // Enumerate(id, destination, exit label)
                let id = self.reader.word()?;
                if let Some(no_assign) = self.safe_index_enumerator.take() {
                    if self.reader.byte()? != 7 {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "safe indexed iterator lacks indexed destination".into(),
                        });
                    }
                    let exit = self.reader.word()?;
                    if self.reader.byte()? != 0x0e {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "safe indexed iterator lacks join Jump".into(),
                        });
                    }
                    let body = self.reader.word()?;
                    if self.reader.at as u32 != no_assign
                        || self.reader.byte()? != 0x72
                        || self.reader.word()? != id
                        || self.reader.word()? != exit
                        || self.reader.at as u32 != body
                    {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "safe indexed iterator branch targets differ".into(),
                        });
                    }
                    self.out.extend([0x7c, 0x143]);
                    self.offsets.insert(no_assign, self.out.len() as u32);
                    self.out.extend([0x11, 0]);
                    self.fixups.push(Fixup {
                        at: self.out.len() - 1,
                        target: exit,
                        source: start,
                    });
                    self.state.last_reference_push = None;
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                let indexed = self.reader.code.get(self.reader.at) == Some(&7);
                let destination = if indexed {
                    self.reader.byte()?;
                    Variable::CacheIndex
                } else {
                    reference(&mut self.reader, ids)?
                };
                let target = self.reader.word()?;
                let mut indexed_receiver_origin: Option<usize> = None;
                let mut indexed_receiver_offsets: Vec<(u32, usize)> = Vec::new();
                let indexed_receivers = if indexed {
                    let at = guarded_assignment_spans(
                        &self.out,
                        code,
                        &self.offsets,
                        &self.fixups,
                        start,
                        1,
                    )
                    .map(|(first, _)| first)
                    .or_else(|| constructor_argument_start(&self.out, 2))
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "indexed iterator receiver has unknown stack effects".into(),
                    })?;
                    let words = self.out[at..].to_vec();
                    indexed_receiver_origin = Some(at);
                    indexed_receiver_offsets = self
                        .offsets
                        .iter()
                        .filter(|(_, value)| {
                            **value as usize > at && **value as usize <= self.out.len()
                        })
                        .map(|(byte, word)| (*byte, *word as usize))
                        .collect();
                    replace_words(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        at,
                        words.len(),
                        &[],
                    );
                    words
                } else {
                    Vec::new()
                };
                if let Some(&stack_count) = self.range_enumerators.get(&id) {
                    // Native 516 omits receiver evaluation for indexed numeric
                    // ranges and references CacheIndex directly (paired fixture).
                    if let Some(origin) = indexed_receiver_origin {
                        self.fixups.retain(|fixup| fixup.at < origin);
                    }
                    self.out
                        .extend([if stack_count == 2 { 0xfd } else { 0xff }, 0]);
                    self.fixups.push(Fixup {
                        at: self.out.len() - 1,
                        target,
                        source: start,
                    });
                    self.out.extend(destination.encode());
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                let loop_at = self.out.len() as u32;
                self.out.push(0x53); // IterNext evaluates before lvalue receivers.
                if indexed {
                    let destination = self.out.len();
                    let origin = indexed_receiver_origin.unwrap();
                    for (byte, word) in indexed_receiver_offsets {
                        self.offsets
                            .insert(byte, (destination + word - origin) as u32);
                    }
                    for fixup in &mut self.fixups {
                        if fixup.at >= origin && fixup.at < origin + indexed_receivers.len() {
                            fixup.at = destination + fixup.at - origin;
                        }
                    }
                    self.out.extend(indexed_receivers);
                    if self.filtered_enumerators.contains_key(&id) {
                        // Keep the assigned list/key in cache for the subtype test.
                        self.out.extend([0x34, 0xffe3, 0x34, 0xffd8, 0x34, 0xffe4]);
                    } else {
                        self.out.push(0x7c);
                    }
                } else {
                    self.out.push(0x34);
                    self.out.extend(destination.encode());
                }
                self.out.extend([0x11, 0]);
                self.fixups.push(Fixup {
                    at: self.out.len() - 1,
                    target,
                    source: start,
                });
                if let Some(&(tag, type_id)) = self.filtered_enumerators.get(&id) {
                    self.out.push(0x33);
                    self.out.extend(destination.encode());
                    push_value(&mut self.out, tag, type_id);
                    self.out.extend([0x7d, 0x0d, 0xfa, loop_at]);
                }
            }
            0x43 => {
                let id = self.reader.word()?;
                if self.range_enumerators.contains_key(&id) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "EnumerateAssoc supports list iterators only".into(),
                    });
                }
                let indexed_value = self.reader.code.get(self.reader.at) == Some(&7);
                let value = if indexed_value {
                    self.reader.byte()?;
                    Variable::CacheIndex
                } else {
                    reference(&mut self.reader, ids)?
                };
                let indexed_key = self.reader.code.get(self.reader.at) == Some(&7);
                let key = if indexed_key {
                    self.reader.byte()?;
                    Variable::CacheIndex
                } else {
                    reference(&mut self.reader, ids)?
                };
                let target = self.reader.word()?;
                let receiver_count = 2 * (usize::from(indexed_value) + usize::from(indexed_key));
                let receiver_at = if receiver_count == 0 {
                    self.out.len()
                } else {
                    guarded_assignment_spans(
                        &self.out,
                        code,
                        &self.offsets,
                        &self.fixups,
                        start,
                        receiver_count - 1,
                    )
                    .map(|(first, _)| first)
                    .or_else(|| constructor_argument_start(&self.out, receiver_count))
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "associative iterator indexed receivers have unknown stack effects"
                            .into(),
                    })?
                };
                let receivers = self.out[receiver_at..].to_vec();
                let receiver_end = self.out.len();
                let moved_offsets = self
                    .offsets
                    .iter()
                    .filter(|(_, value)| {
                        **value as usize > receiver_at && **value as usize <= receiver_end
                    })
                    .map(|(byte, word)| (*byte, *word as usize))
                    .collect::<Vec<_>>();
                let moved_fixups = self
                    .fixups
                    .iter()
                    .enumerate()
                    .filter(|(_, fixup)| fixup.at >= receiver_at && fixup.at < receiver_end)
                    .map(|(index, fixup)| (index, fixup.at))
                    .collect::<Vec<_>>();
                let value_words = if indexed_value {
                    let end = if indexed_key {
                        guarded_assignment_spans(
                            &self.out,
                            code,
                            &self.offsets,
                            &self.fixups,
                            start,
                            1,
                        )
                        .map(|(first, _)| first - receiver_at)
                        .or_else(|| constructor_argument_start(&receivers, 2))
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "associative key receiver has unknown stack effects".into(),
                        })?
                    } else {
                        receivers.len()
                    };
                    receivers[..end].to_vec()
                } else {
                    Vec::new()
                };
                let key_words = receivers[value_words.len()..].to_vec();
                replace_words(
                    &mut self.out,
                    &mut self.offsets,
                    &mut self.fixups,
                    receiver_at,
                    receivers.len(),
                    &[],
                );
                let instructions =
                    crate::bytecode::decode(&self.out).map_err(|error| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: format!("cannot inspect associative iterator: {}", error.reason),
                    })?;
                let load = instructions
                    .iter()
                    .rev()
                    .find(|item| !matches!(item.opcode, 0x84 | 0x85))
                    .filter(|item| item.opcode == 0x52 && item.operands.first() == Some(&5))
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "EnumerateAssoc lacks ordinary IterLoad".into(),
                    })?;
                self.out[load.offset + 1] = 20;
                let loop_at = self.out.len() as u32;
                self.out.push(0x53);
                let value_destination = self.out.len();
                let value_len = value_words.len();
                if indexed_value {
                    self.out.extend(value_words);
                    self.out.extend([0x34, 0xffe3, 0x34, 0xffd8]);
                }
                self.out.push(0x17e);
                self.out.extend(value.encode());
                let key_destination = self.out.len();
                if indexed_key {
                    self.out.extend(key_words);
                    self.out.push(0x7c);
                } else {
                    self.out.push(0x34);
                    self.out.extend(key.encode());
                }
                let relocated = |word: usize| {
                    if indexed_value && word <= receiver_at + value_len {
                        value_destination + word - receiver_at
                    } else {
                        key_destination + word - receiver_at - value_len
                    }
                };
                for (byte, word) in moved_offsets {
                    self.offsets.insert(byte, relocated(word) as u32);
                }
                for (index, word) in moved_fixups {
                    self.fixups[index].at = relocated(word);
                }
                self.out.extend([0x11, 0]);
                self.fixups.push(Fixup {
                    at: self.out.len() - 1,
                    target,
                    source: start,
                });
                if let Some(&(tag, type_id)) = self.filtered_enumerators.get(&id) {
                    self.out.push(0x33);
                    self.out.extend(key.encode());
                    push_value(&mut self.out, tag, type_id);
                    self.out.extend([0x7d, 0x0d, 0xfa, loop_at]);
                }
            }
            0x3c => {
                let id = self.reader.word()?;
                self.filtered_enumerators.remove(&id);
                self.range_enumerators.remove(&id);
                if self.iterator_frames.last().map(|frame| frame.id) != Some(id) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "iterator destruction is not nested in creation order".into(),
                    });
                }
                self.out.extend(iterator_cleanup(
                    &self.iterator_frames,
                    self.iterator_frames.len() - 1,
                ));
                self.iterator_frames.pop();
            }
            0x1b => {
                let id = self.reader.word()?;
                let instructions =
                    crate::bytecode::decode(&self.out).map_err(|error| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: format!("cannot inspect range step: {}", error.reason),
                    })?;
                let step = instructions.last().ok_or_else(|| LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "range enumerator lacks a step".into(),
                })?;
                let unit_step = step.opcode == 0x60 && step.operands == [0x2a, 0x3f80, 0];
                if unit_step {
                    replace_words(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        step.offset,
                        1 + step.operands.len(),
                        &[],
                    );
                }
                self.out.push(if unit_step { 0xfc } else { 0xfe });
                let range_words = if unit_step { 2 } else { 3 };
                self.range_enumerators.insert(id, range_words);
                self.iterator_frames.push(IteratorFrame {
                    id,
                    range_words: Some(range_words),
                });
            }
            0x84 => {
                // AppendNoPush: `x += rhs` in statement position
                if self.reader.code.get(self.reader.at) == Some(&7) {
                    self.reader.byte()?;
                    if reorder_guarded_indexed_rhs(
                        &mut self.out,
                        code,
                        &mut self.offsets,
                        &mut self.fixups,
                        &mut self.safe.safe_skip_pop,
                        start,
                        &[0x34, 0xffe3, 0x34, 0xffd8, 0x45, 0xffe4],
                    ) {
                        return Ok(OpcodeFlow::ContinueThisOpcode);
                    }
                    let mut end = self.out.len();
                    let mut spans = Vec::new();
                    for _ in 0..3 {
                        let Some(at) =
                            constructor_argument_start(&self.out[..end], 1).or_else(|| {
                                guarded_assignment_spans(
                                    &self.out[..end],
                                    code,
                                    &self.offsets,
                                    &self.fixups,
                                    start,
                                    0,
                                )
                                .map(|(first, _)| first)
                            })
                        else {
                            break;
                        };
                        spans.push((at, end));
                        end = at;
                    }
                    spans.reverse();
                    if spans.len() != 3
                        || spans[..2].iter().any(|(at, end)| {
                            !crate::bytecode::decode(&self.out[*at..*end]).is_ok_and(|items| {
                                items.iter().all(|item| {
                                    !matches!(item.opcode,
                                    0x0f..=0x11 | 0x14..=0x16 | 0xb2..=0xb4 |
                                    0xf9 | 0xfa | 0x13d | 0x13e)
                                })
                            })
                        })
                    {
                        return Err(LowerError {
            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "indexed append requires direct list/key and known value stack effects".into(),
                        });
                    }
                    let mut replacement = Vec::new();
                    for (at, end) in [spans[2], spans[0], spans[1]] {
                        replacement.extend_from_slice(&self.out[at..end]);
                    }
                    replacement.extend([0x34, 0xffe3, 0x34, 0xffd8, 0x45, 0xffe4]);
                    let at = spans[0].0;
                    let old_len = self.out.len() - at;
                    replace_words(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        at,
                        old_len,
                        &replacement,
                    );
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                self.out.push(0x45);
                let target = reference(&mut self.reader, ids)?;
                emit_tracked_reference(
                    &mut self.out,
                    &target,
                    &mut self.state.cached_world_owner,
                    &mut self.state.pending_world_ref,
                );
            }
            0x1a => {
                let target = reference(&mut self.reader, ids)?;
                self.out.push(0x45); // AugAdd stores expression result in eval cache.
                emit_tracked_reference(
                    &mut self.out,
                    &target,
                    &mut self.state.cached_world_owner,
                    &mut self.state.pending_world_ref,
                );
                self.out.push(0x13f); // PushEval
            }
            0x1f if self.reader.code.get(self.reader.at) != Some(&7) => {
                let target = reference(&mut self.reader, ids)?;
                let discard = self.reader.code.get(self.reader.at) == Some(&0x51)
                    && !self
                        .fixups
                        .iter()
                        .any(|fixup| fixup.target == self.reader.at as u32);
                if self.safe.pending_safe_aug_sub {
                    if !matches!(target, Variable::Field(_)) {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "safe augmented subtraction requires a field".into(),
                        });
                    }
                    self.out.push(0x143); // Restore cached receiver before AugSub.
                    self.safe.pending_safe_aug_sub = false;
                }
                self.out.push(0x46);
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
                } else {
                    self.out.push(0x13f); // PushEval exposes augmented expression result.
                }
            }
            0x0b | 0x17 | 0x39 | 0x33 | 0x2d | 0x29 | 0x6d | 0x6e | 0x61 | 0x1f => {
                // BYOND Aug* stores its result in the eval cache. Statement
                // position discards it; expression position pushes it.
                let indexed = self.reader.code.get(self.reader.at) == Some(&7);
                let target = if indexed {
                    self.reader.byte()?;
                    Variable::CacheIndex
                } else {
                    reference(&mut self.reader, ids)?
                };
                let discard = self.reader.code.get(self.reader.at) == Some(&0x51)
                    && !self
                        .fixups
                        .iter()
                        .any(|fixup| fixup.target == self.reader.at as u32);
                let byond = match op {
                    0x0b => 0x47,
                    0x17 => 0x48,
                    0x39 => 0x49,
                    0x33 => 0x4a,
                    0x2d => 0x4b,
                    0x29 => 0x4c,
                    0x6d => 0x4d,
                    0x6e => 0x4e,
                    0x61 => 0x177,
                    0x1f => 0x46,
                    _ => unreachable!(),
                };
                if indexed
                    && reorder_guarded_indexed_rhs(
                        &mut self.out,
                        code,
                        &mut self.offsets,
                        &mut self.fixups,
                        &mut self.safe.safe_skip_pop,
                        start,
                        &[0x34, 0xffe3, 0x34, 0xffd8, byond, 0xffe4],
                    )
                {
                    // The common result/discard handling follows below.
                } else if indexed {
                    let mut end = self.out.len();
                    let mut spans = Vec::new();
                    for _ in 0..3 {
                        let Some(at) =
                            constructor_argument_start(&self.out[..end], 1).or_else(|| {
                                guarded_assignment_spans(
                                    &self.out[..end],
                                    code,
                                    &self.offsets,
                                    &self.fixups,
                                    start,
                                    0,
                                )
                                .map(|(first, _)| first)
                            })
                        else {
                            break;
                        };
                        spans.push((at, end));
                        end = at;
                    }
                    spans.reverse();
                    if spans.len() != 3 {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "indexed augmented assignment needs three known stack values"
                                .into(),
                        });
                    }
                    let mut replacement = Vec::new();
                    for (at, end) in [spans[2], spans[0], spans[1]] {
                        replacement.extend_from_slice(&self.out[at..end]);
                    }
                    replacement.extend([0x34, 0xffe3, 0x34, 0xffd8, byond]);
                    replacement.extend(target.encode());
                    let old_len = self.out.len() - spans[0].0;
                    replace_words(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        spans[0].0,
                        old_len,
                        &replacement,
                    );
                } else {
                    self.out.push(byond);
                    emit_tracked_reference(
                        &mut self.out,
                        &target,
                        &mut self.state.cached_world_owner,
                        &mut self.state.pending_world_ref,
                    );
                }
                if discard {
                    self.offsets
                        .insert(self.reader.at as u32, self.out.len() as u32);
                    self.reader.byte()?;
                } else {
                    self.out.push(0x13f);
                }
            }
            0x56 => {
                if self.reader.code.get(self.reader.at) == Some(&7) {
                    self.reader.byte()?; // indexed reference
                                         // Both expressions already leave list/key on the stack.
                                         // Caching consumes them in place, including branch joins.
                    self.out.extend([0x34, 0xffe3, 0x34, 0xffd8]); // CacheKey, Cache
                    let statement = self.reader.code.get(self.reader.at) == Some(&0x51)
                        && !self
                            .fixups
                            .iter()
                            .any(|fixup| fixup.target == self.reader.at as u32);
                    self.out
                        .extend([if statement { 0x66 } else { 0x63 }, 0xffe4]); // Inc/PostInc CacheIndex
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
                    self.out.push(0x66); // Inc in statement position
                    emit_tracked_reference(
                        &mut self.out,
                        &target,
                        &mut self.state.cached_world_owner,
                        &mut self.state.pending_world_ref,
                    );
                    self.offsets
                        .insert(self.reader.at as u32, self.out.len() as u32);
                    self.reader.byte()?; // discard OpenDream's pushed old value
                } else {
                    self.out.push(0x63); // PostInc in expression position
                    emit_tracked_reference(
                        &mut self.out,
                        &target,
                        &mut self.state.cached_world_owner,
                        &mut self.state.pending_world_ref,
                    );
                }
            }
            _ => return Ok(OpcodeFlow::Unhandled),
        }
        Ok(OpcodeFlow::Advance)
    }
}
