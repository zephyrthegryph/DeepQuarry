use super::*;

impl<R: SymbolResolver> PassState<'_, R> {
    pub(super) fn lower_safe_try(
        &mut self,
        start: usize,
        op: u8,
        _follows_format: bool,
    ) -> Result<OpcodeFlow, LowerError> {
        let code = self.inputs.code;
        let ids = self.inputs.ids;
        match op {
            0x74 => {
                if let Some((base_at, chain_at)) = self.guarded_assign_into.remove(&start) {
                    let target = reference(&mut self.reader, ids)?;
                    let rhs_at = guarded_assignment_spans(
                        &self.out,
                        code,
                        &self.offsets,
                        &self.fixups,
                        start,
                        1,
                    )
                    .or_else(|| {
                        guarded_assignment_spans(
                            &self.out,
                            code,
                            &self.offsets,
                            &self.fixups,
                            start,
                            0,
                        )
                    })
                    .map(|(_, rhs)| rhs)
                    .or_else(|| {
                        constructor_argument_start(&self.out[chain_at..], 1).map(|at| chain_at + at)
                    })
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "guarded AssignInto RHS has unknown stack effects".into(),
                    })?;
                    let end = self.out.len();
                    let items =
                        crate::bytecode::decode(&self.out[chain_at..rhs_at]).map_err(|error| {
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
                    let nested_guard = self.guarded_assign_into_nested.remove(&start);
                    let direct = if !nested_guard && executable.len() == 1 {
                        let item = executable[0];
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
                    let computed = direct.is_none() && !executable.is_empty();
                    let rhs_len = end - rhs_at;
                    let base_len = chain_at - base_at;
                    let mut replacement = self.out[rhs_at..end].to_vec();
                    replacement.extend_from_slice(&self.out[base_at..chain_at]);
                    let destination =
                        if let (Some(owner), Variable::Field(field)) = (direct, &target) {
                            for item in items
                                .iter()
                                .filter(|item| matches!(item.opcode, 0x84 | 0x85))
                            {
                                replacement.extend_from_slice(
                                    &self.out[chain_at + item.offset
                                        ..chain_at + item.offset + 1 + item.operands.len()],
                                );
                            }
                            append_field(owner, *field)
                        } else {
                            if computed {
                                replacement.push(0x142);
                                replacement.extend_from_slice(&self.out[chain_at..rhs_at]);
                                replacement.extend([0x34, 0xffd8, 0x143]);
                            }
                            target
                        };
                    let action_at = base_at + replacement.len();
                    let rhs_join = u32::MAX - start as u32;
                    let owner_join = rhs_join - 1;
                    let safe_rhs_join = rhs_join - 2;
                    let cache_unwind =
                        crate::bytecode::decode(&self.out[rhs_at..end])
                            .ok()
                            .map_or(0, |items| {
                                items
                                    .iter()
                                    .rev()
                                    .take_while(|item| item.opcode == 0x143)
                                    .count()
                            });
                    let moved_offsets: Vec<_> = self
                        .offsets
                        .iter()
                        .filter_map(|(&source, &old)| {
                            let old = old as usize;
                            (old >= base_at && old < end).then(|| {
                                (
                                    source,
                                    if old >= rhs_at {
                                        base_at + old - rhs_at
                                    } else if old < chain_at {
                                        base_at + rhs_len + old - base_at
                                    } else if computed {
                                        base_at + rhs_len + base_len + 1 + old - chain_at
                                    } else {
                                        action_at
                                    } as u32,
                                )
                            })
                        })
                        .collect();
                    let mut moved_fixups = Vec::new();
                    for (index, fixup) in self.fixups.iter_mut().enumerate() {
                        if fixup.at >= base_at && fixup.at < end {
                            if fixup.at >= rhs_at && fixup.target == start as u32 {
                                fixup.target = if fixup.at > 0 && self.out[fixup.at - 1] == 0x13d {
                                    let saved = cache_frame_depth(&self.out[rhs_at..fixup.at - 1]);
                                    self.safe
                                        .safe_skip_pop
                                        .entry(index)
                                        .or_insert(cache_unwind.saturating_sub(saved) as u32);
                                    safe_rhs_join
                                } else {
                                    rhs_join
                                };
                            } else if fixup.at >= chain_at
                                && fixup.at < rhs_at
                                && (fixup.target == start as u32
                                    || self.offsets.get(&fixup.target).copied()
                                        == Some(rhs_at as u32))
                            {
                                fixup.target = owner_join;
                            }
                            moved_fixups.push((
                                index,
                                if fixup.at >= rhs_at {
                                    base_at + fixup.at - rhs_at
                                } else if fixup.at < chain_at {
                                    base_at + rhs_len + fixup.at - base_at
                                } else {
                                    base_at + rhs_len + base_len + 1 + fixup.at - chain_at
                                },
                            ));
                        }
                    }
                    replace_words(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        base_at,
                        end - base_at,
                        &replacement,
                    );
                    self.offsets.extend(moved_offsets);
                    self.offsets.insert(rhs_join, (base_at + rhs_len) as u32);
                    self.offsets
                        .insert(safe_rhs_join, (base_at + rhs_len - cache_unwind) as u32);
                    self.offsets
                        .insert(owner_join, (action_at - usize::from(computed) * 3) as u32);
                    self.offsets.insert(start as u32, action_at as u32);
                    for (index, at) in moved_fixups {
                        self.fixups[index].at = at;
                    }
                    self.out.push(0x15a);
                    self.out.extend(destination.encode());
                    if self.reader.code.get(self.reader.at) == Some(&0x51)
                        && !self
                            .fixups
                            .iter()
                            .any(|fixup| fixup.target == self.reader.at as u32)
                    {
                        self.offsets
                            .insert(self.reader.at as u32, self.out.len() as u32);
                        self.reader.byte()?;
                    } else {
                        self.out.push(0x13f);
                    }
                    self.state.last_reference_push = None;
                    self.state.cached_world_owner = false;
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                let indexed = self.reader.code.get(self.reader.at) == Some(&7);
                let mut target = if indexed {
                    self.reader.byte()?;
                    Variable::CacheIndex
                } else {
                    reference(&mut self.reader, ids)?
                };
                let destination_count = if indexed {
                    2
                } else {
                    usize::from(matches!(target, Variable::Field(_)))
                };
                let spans = guarded_assignment_spans(
                    &self.out,
                    code,
                    &self.offsets,
                    &self.fixups,
                    start,
                    destination_count,
                );
                let value_at = spans
                    .map(|(_, value)| value)
                    .or_else(|| constructor_argument_start(&self.out, 1))
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "AssignInto value has unknown stack effects".into(),
                    })?;
                let owner_at = if let Some((owner, _)) = spans {
                    Some(owner)
                } else if indexed {
                    constructor_argument_start(&self.out[..value_at], 2)
                } else if matches!(target, Variable::Field(_)) {
                    constructor_argument_start(&self.out[..value_at], 1)
                } else {
                    None
                };
                if indexed || matches!(target, Variable::Field(_)) {
                    let owner_at = owner_at.ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "AssignInto owner has unknown stack effects".into(),
                    })?;
                    let owner = self.out[owner_at..value_at].to_vec();
                    let items = crate::bytecode::decode(&owner).map_err(|error| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: error.reason,
                    })?;
                    let executable: Vec<_> = items
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
                    let end = self.out.len();
                    let rhs_len = end - value_at;
                    let mut replacement = self.out[value_at..].to_vec();
                    let direct_owner = direct.is_some() && matches!(target, Variable::Field(_));
                    if let (Some(owner), Variable::Field(field)) = (direct, &target) {
                        target = append_field(owner, *field);
                        for item in items
                            .iter()
                            .filter(|item| matches!(item.opcode, 0x84 | 0x85))
                        {
                            replacement.extend_from_slice(
                                &self.out[owner_at + item.offset
                                    ..owner_at + item.offset + 1 + item.operands.len()],
                            );
                        }
                    } else {
                        replacement.extend(owner);
                        if indexed {
                            replacement.extend([0x34, 0xffe3]);
                        }
                        replacement.extend([0x34, 0xffd8]);
                    }
                    let old_len = self.out.len() - owner_at;
                    let rhs_join = u32::MAX - start as u32;
                    let owner_join = rhs_join - 1;
                    let safe_rhs_join = rhs_join - 2;
                    let cache_unwind = crate::bytecode::decode(&self.out[value_at..end])
                        .ok()
                        .map_or(0, |items| {
                            items
                                .iter()
                                .rev()
                                .take_while(|item| item.opcode == 0x143)
                                .count()
                        });
                    let action_at = owner_at + replacement.len();
                    let owner_end = if indexed {
                        action_at - 4
                    } else {
                        action_at - 2
                    };
                    let moved_offsets: Vec<_> = self
                        .offsets
                        .iter()
                        .filter_map(|(&source, &old)| {
                            let old = old as usize;
                            (old >= owner_at && old < end).then(|| {
                                (
                                    source,
                                    if old >= value_at {
                                        owner_at + old - value_at
                                    } else if direct_owner {
                                        action_at
                                    } else {
                                        owner_at + rhs_len + old - owner_at
                                    } as u32,
                                )
                            })
                        })
                        .collect();
                    let mut moved_fixups = Vec::new();
                    for (index, fixup) in self.fixups.iter_mut().enumerate() {
                        if fixup.at >= owner_at && fixup.at < end {
                            if fixup.at >= value_at && fixup.target == start as u32 {
                                fixup.target = if fixup.at > 0 && self.out[fixup.at - 1] == 0x13d {
                                    let saved =
                                        cache_frame_depth(&self.out[value_at..fixup.at - 1]);
                                    self.safe
                                        .safe_skip_pop
                                        .entry(index)
                                        .or_insert(cache_unwind.saturating_sub(saved) as u32);
                                    safe_rhs_join
                                } else {
                                    rhs_join
                                };
                            } else if fixup.at < value_at
                                && (fixup.target == start as u32
                                    || self.offsets.get(&fixup.target).copied()
                                        == Some(value_at as u32))
                            {
                                fixup.target = owner_join;
                            }
                            moved_fixups.push((
                                index,
                                if fixup.at >= value_at {
                                    owner_at + fixup.at - value_at
                                } else {
                                    owner_at + rhs_len + fixup.at - owner_at
                                },
                            ));
                        }
                    }
                    replace_words(
                        &mut self.out,
                        &mut self.offsets,
                        &mut self.fixups,
                        owner_at,
                        old_len,
                        &replacement,
                    );
                    self.offsets.extend(moved_offsets);
                    self.offsets.insert(rhs_join, (owner_at + rhs_len) as u32);
                    self.offsets
                        .insert(safe_rhs_join, (owner_at + rhs_len - cache_unwind) as u32);
                    self.offsets.insert(owner_join, owner_end as u32);
                    self.offsets.insert(start as u32, action_at as u32);
                    for (index, at) in moved_fixups {
                        self.fixups[index].at = at;
                    }
                }
                self.out.push(0x15a);
                emit_tracked_reference(
                    &mut self.out,
                    &target,
                    &mut self.state.cached_world_owner,
                    &mut self.state.pending_world_ref,
                );
                if self.reader.code.get(self.reader.at) == Some(&0x51)
                    && !self
                        .fixups
                        .iter()
                        .any(|fixup| fixup.target == self.reader.at as u32)
                {
                    self.offsets
                        .insert(self.reader.at as u32, self.out.len() as u32);
                    self.reader.byte()?;
                } else {
                    self.out.push(0x13f);
                }
                self.state.last_reference_push = None;
                self.state.cached_world_owner = false;
            }
            0x4f => self.out.push(0x03), // Output(target, value)
            0x75 => self.out.push(0x90), // GetStep(start, direction)
            0x4d => {
                let target = self.reader.word()?;
                self.spawn_targets.push(target);
                self.out.extend([0x25, 0]);
                self.fixups.push(Fixup {
                    at: self.out.len() - 1,
                    target,
                    source: start,
                });
            }
            0x65 => {
                if (SafeGuardLowering {
                    code,
                    reader: &mut self.reader,
                    ids,
                    start,
                    out: &mut self.out,
                    offsets: &mut self.offsets,
                    fixups: &mut self.fixups,
                    state: &mut self.state,
                    safe: &mut self.safe,
                    pending_receivers: &mut self.pending_receivers,
                    guarded_assign_into: &mut self.guarded_assign_into,
                    guarded_assign_into_nested: &mut self.guarded_assign_into_nested,
                })
                .lower()?
                {
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
            }
            0x64 => {
                // A safe lvalue in `for(a?.field in list)` has two OD
                // enumeration paths. Native BYOND shares IterNext and Jz,
                // skipping SetVar when the receiver is null.
                let no_assign = self.reader.word()?;
                if ids.native_delete_clear(start) {
                    self.out.extend([0x13e, 0]);
                    self.fixups.push(Fixup {
                        at: self.out.len() - 1,
                        target: no_assign,
                        source: start,
                    });
                    if self.reader.code.get(self.reader.at) != Some(&0x85) {
                        self.out.extend([0x142, 0x33, 0xffd8]);
                        self.delete_clear_cache_end = Some(no_assign);
                    }
                    self.state.last_reference_push = None;
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                let instructions =
                    crate::bytecode::decode(&self.out).map_err(|error| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: format!("cannot inspect safe iterator receiver: {}", error.reason),
                    })?;
                let owner = instructions
                    .iter()
                    .rev()
                    .find(|item| !matches!(item.opcode, 0x84 | 0x85))
                    .filter(|item| item.opcode == 0x33)
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "JumpIfNull lacks direct iterator receiver".into(),
                    })?;
                let old = self.out[owner.offset..owner.offset + 1 + owner.operands.len()].to_vec();
                let mut with_iter = vec![0x53];
                with_iter.extend(old);
                replace_words(
                    &mut self.out,
                    &mut self.offsets,
                    &mut self.fixups,
                    owner.offset,
                    1 + owner.operands.len(),
                    &with_iter,
                );
                if self.reader.code.get(self.reader.at) != Some(&0x3b) {
                    // An indexed lvalue evaluates its key only on the non-null
                    // path. Keep the shared IterNext before the null guard.
                    self.out.extend([0x13e, 0]);
                    self.fixups.push(Fixup {
                        at: self.out.len() - 1,
                        target: no_assign,
                        source: start,
                    });
                    self.out.extend([0x142, 0x33, 0xffd8]);
                    self.safe_index_enumerator = Some(no_assign);
                    self.state.last_reference_push = None;
                    return Ok(OpcodeFlow::ContinueThisOpcode);
                }
                self.reader.byte()?; // Enumerate
                let id = self.reader.word()?;
                let destination = reference(&mut self.reader, ids)?;
                let exit = self.reader.word()?;
                if !matches!(destination, Variable::Field(_)) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "safe iterator requires direct field destination".into(),
                    });
                }
                if self.reader.byte()? != 0x0e {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "safe iterator lacks join Jump".into(),
                    });
                }
                let body = self.reader.word()?;
                if self.reader.at as u32 != no_assign
                    || self.reader.byte()? != 0x72
                    || self.reader.word()? != id
                {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "safe iterator lacks matching EnumerateNoAssign".into(),
                    });
                }
                if self.reader.word()? != exit || self.reader.at as u32 != body {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "safe iterator branch targets differ".into(),
                    });
                }
                self.out.extend([0x13e, 0]);
                let null_fixup = self.out.len() - 1;
                self.out.push(0x34);
                self.out.extend(destination.encode());
                let jz_at = self.out.len() as u32;
                self.out[null_fixup] = jz_at;
                self.offsets.insert(no_assign, jz_at);
                self.out.extend([0x11, 0]);
                self.fixups.push(Fixup {
                    at: self.out.len() - 1,
                    target: exit,
                    source: start,
                });
                return Ok(OpcodeFlow::ContinueThisOpcode);
            }
            0x66 | 0x67 => {
                // `x ||= y` and `x &&= y`: test the current reference and
                // skip assignment when it already determines the result.
                let indexed = self.reader.code.get(self.reader.at) == Some(&7);
                let mut variable = if indexed {
                    self.reader.byte()?;
                    Variable::CacheIndex
                } else {
                    reference(&mut self.reader, ids)?
                };
                let target = self.reader.word()?;
                let field_owned = matches!(variable, Variable::Field(_));
                if field_owned {
                    let safe_cached = self.safe.pending_safe_lvalue_at.is_some();
                    if safe_cached {
                        if let Some(body_at) = self.safe.pending_safe_lvalue_body.take() {
                            let items = crate::bytecode::decode(&self.out[body_at..]).ok();
                            let direct = items.as_ref().and_then(|items| {
                                let executable: Vec<_> = items
                                    .iter()
                                    .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
                                    .collect();
                                let [item] = executable.as_slice() else {
                                    return None;
                                };
                                (item.opcode == 0x33)
                                    .then(|| {
                                        Variable::decode(&item.operands)
                                            .ok()
                                            .map(|(owner, _)| (body_at + item.offset, owner))
                                    })
                                    .flatten()
                            });
                            if let Some((at, owner)) = direct {
                                let Variable::Field(field) = variable else {
                                    unreachable!()
                                };
                                variable = append_field(owner.clone(), field);
                                replace_words(
                                    &mut self.out,
                                    &mut self.offsets,
                                    &mut self.fixups,
                                    at,
                                    1 + owner.encode().len(),
                                    &[],
                                );
                            } else {
                                // Native computed guarded logical owners retain
                                // the base frame until the logical join.
                                self.out.extend([0x34, 0xffd8]);
                                self.computed_safe_logical.insert(start);
                            }
                        }
                        if !self.computed_safe_logical.contains(&start) {
                            self.out.push(0x143);
                        }
                        self.safe.pending_safe_lvalue_at = None;
                        self.safe_logical_continuations.insert(start);
                    }
                    let direct_owner = (!safe_cached)
                        .then(|| {
                            crate::bytecode::decode(&self.out).ok().and_then(|items| {
                                let prior = items
                                    .iter()
                                    .rfind(|item| !matches!(item.opcode, 0x84 | 0x85))?;
                                if prior.opcode != 0x33 {
                                    return None;
                                }
                                let (owner, _) = Variable::decode(&prior.operands).ok()?;
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
                                .then_some((prior.offset, owner))
                            })
                        })
                        .flatten();
                    self.state.last_reference_push = None;
                    if let Some((at, owner)) = direct_owner {
                        let length = 1 + owner.encode().len();
                        replace_words(
                            &mut self.out,
                            &mut self.offsets,
                            &mut self.fixups,
                            at,
                            length,
                            &[],
                        );
                        let Variable::Field(field) = variable else {
                            unreachable!()
                        };
                        variable = append_field(owner, field);
                    } else if !safe_cached {
                        constructor_argument_start(&self.out, 1).ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "logical field receiver has unknown stack effects".into(),
                        })?;
                        self.out.extend([0x34, 0xffd8]);
                    }
                    self.state.cached_world_owner = false;
                }
                if indexed {
                    self.out.extend([0x34, 0xffe3, 0x34, 0xffd8]);
                }
                self.out.push(0x33);
                self.out.extend(variable.encode());
                let discard = self.reader.code.get(target as usize) == Some(&0x51)
                    && !self.fixups.iter().any(|fixup| {
                        fixup.target == target
                            && branch_retains_discarded_value(fixup, code, &self.out)
                    });
                if discard {
                    self.out.push(0x0d);
                }
                self.out.extend([
                    if discard {
                        if op == 0x66 {
                            0x10
                        } else {
                            0x11
                        }
                    } else if op == 0x66 {
                        0xb2
                    } else {
                        0xb3
                    },
                    0,
                ]);
                self.fixups.push(Fixup {
                    at: self.out.len() - 1,
                    target,
                    source: start,
                });
                if indexed || field_owned {
                    self.out.push(0x142);
                    self.pending_indexed_logical.push((target, start, variable));
                }
            }
            0x6f | 0x70 => {
                if self.pending_try.is_empty() {
                    self.catch_local_base = None;
                    self.catches_emitted = 0;
                }
                let catch_target = self.reader.word()?;
                let source_local = (op == 0x6f && self.reader.code.get(self.reader.at) == Some(&9))
                    .then(|| {
                        self.reader
                            .code
                            .get(self.reader.at + 1)
                            .copied()
                            .map(usize::from)
                    })
                    .flatten();
                let destination = if op == 0x6f {
                    Some(reference(&mut self.reader, ids)?)
                } else {
                    None
                };
                if let Some(Variable::Local(slot)) = &destination {
                    self.catch_local_base =
                        Some(self.catch_local_base.map_or(*slot, |base| base.min(*slot)));
                }
                let try_at = self.out.len() + 1;
                self.out.extend([0x12c, 0]);
                self.pending_try.push(TryFrame {
                    try_at,
                    catch_target,
                    destination,
                    source_local,
                    source_start: start,
                });
            }
            0x71 => {
                let TryFrame {
                    try_at,
                    catch_target,
                    destination,
                    source_local,
                    source_start,
                } = self.pending_try.pop().ok_or_else(|| LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "EndTry lacks matching Try".into(),
                })?;
                self.try_regions.push((source_start, start));
                let end_target = if self.reader.code.get(self.reader.at) == Some(&0x0e) {
                    self.offsets
                        .insert(self.reader.at as u32, self.out.len() as u32);
                    self.reader.byte()?;
                    self.reader.word()?
                } else if self.reader.at as u32 == catch_target {
                    // An empty catch has no handler to jump over. OpenDream
                    // omits its Jump; the native EndTry still names the join.
                    catch_target
                } else {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "EndTry lacks following Jump".into(),
                    });
                };
                if self.reader.at as u32 != catch_target {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "Try catch label is not after EndTry Jump".into(),
                    });
                }
                self.out.extend([0x12e, 0]);
                self.fixups.push(Fixup {
                    at: self.out.len() - 1,
                    target: end_target,
                    source: start,
                });
                self.out[try_at] = self.out.len() as u32;
                if let Some(destination) = destination {
                    let destination =
                        if self.reader.remap_locals {
                            if let (Some(source_slot), Variable::Local(_), Some(base)) =
                                (source_local, &destination, self.catch_local_base)
                            {
                                let native_slot = base + self.catches_emitted;
                                self.catches_emitted += 1;
                                *self.reader.local_slots.get_mut(source_slot).ok_or_else(
                                    || LowerError {
                                        kind: LowerErrorKind::MalformedControlFlow,
                                        offset: start,
                                        reason: "catch local slot is inactive".into(),
                                    },
                                )? = native_slot;
                                Variable::Local(native_slot)
                            } else {
                                destination
                            }
                        } else {
                            destination
                        };
                    self.out.push(0x34);
                    self.out.extend(destination.encode());
                } else {
                    self.out.push(0x51); // discard exception value
                }
                self.state.cached_world_owner = false;
            }
            0x5a => self.out.push(0x12d), // Throw
            0x8b => {
                let target_ref = reference(&mut self.reader, ids)?;
                let target = self.reader.word()?;
                self.out.push(0x33);
                self.out.extend(target_ref.encode());
                let (branch, target) = if ids.native_do_while_condition(start) {
                    let (jump, body) = read_do_while_backedge(&mut self.reader, start, target)?;
                    self.offsets
                        .insert(jump as u32, (self.out.len() + 1) as u32);
                    (0xf9, body)
                } else {
                    (0x11, target)
                };
                self.out.extend([0x0d, branch, 0]);
                self.fixups.push(Fixup {
                    at: self.out.len() - 1,
                    target,
                    source: start,
                });
            }
            0x51 => self.out.push(0x51), // Pop
            0x10 => self.out.push(0x12), // Return
            0x22 => {
                self.out.extend([0x1a, self.reader.word()?]);
            } // CreateList
            _ => return Ok(OpcodeFlow::Unhandled),
        }
        Ok(OpcodeFlow::Advance)
    }
}
