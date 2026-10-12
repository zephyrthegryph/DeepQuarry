use super::*;

impl<R: SymbolResolver> PassState<'_, R> {
    pub(super) fn finish(
        mut self,
        referenced_args: Option<&mut Vec<u8>>,
    ) -> Result<Vec<u32>, LowerError> {
        let code = self.inputs.code;
        let ids = self.inputs.ids;
        let world_flow = &mut *self.world_flow;

        if !self.pending_indexed_logical.is_empty() {
            return Err(LowerError {
                kind: LowerErrorKind::MalformedControlFlow,
                offset: code.len(),
                reason: "indexed logical reference lacks its matching assignment".into(),
            });
        }
        if !self.pending_receivers.is_empty() {
            return Err(LowerError {
                kind: LowerErrorKind::MalformedControlFlow,
                offset: code.len(),
                reason: "native cached receiver lacks method call".into(),
            });
        }
        if !self.pending_try.is_empty() {
            return Err(LowerError {
                kind: LowerErrorKind::MalformedControlFlow,
                offset: code.len(),
                reason: "Try lacks matching EndTry".into(),
            });
        }
        for offset in ids.native_store_reload_offsets() {
            if !self.store_reload_boundaries.contains(offset) {
                return Err(LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: *offset as usize,
                    reason:
                        "native store/reload offset is not a marked assignment instruction boundary"
                            .into(),
                });
            }
        }
        let delete_clears = self
            .offsets
            .iter()
            .filter_map(|(source, word)| {
                ids.native_delete_clear(*source as usize)
                    .then_some(*word as usize)
            })
            .collect();
        retain_frozen_root_cache(
            &mut self.out,
            &mut self.offsets,
            &mut self.fixups,
            &delete_clears,
            &self.probability_regions,
        );
        for offset in ids
            .native_initial_reference_offsets()
            .iter()
            .chain(ids.native_is_saved_reference_offsets())
        {
            if !self.offsets.contains_key(&(*offset as u32)) || code.get(*offset) != Some(&0x06) {
                return Err(LowerError {
                kind: LowerErrorKind::MalformedControlFlow,
                offset: *offset,
                reason:
                    "native reference modifier offset is not a reference-load instruction boundary"
                        .into(),
            });
            }
        }
        self.offsets
            .insert(code.len() as u32, self.out.len() as u32);
        self.iterator_states
            .insert(code.len(), self.iterator_frames);
        if let Some((_, count)) = self
            .safe
            .nested_safe_pop
            .filter(|(target, _)| *target == code.len() as u32)
        {
            self.out.extend(std::iter::repeat_n(0x143, count as usize));
        }
        // Branches to an enclosing loop can bypass one or more DestroyEnumerator
        // instructions (labelled break/continue and goto). Unwind only that edge.
        let mut trampolines = Vec::new();
        world_flow.targets.extend(
            self.fixups
                .iter()
                .map(|fixup| fixup.target)
                .filter(|target| *target as usize <= code.len()),
        );
        restore_try_branch_exits(&mut self.out, code, &self.fixups, &self.try_regions);
        // Source branch provenance survives optimizer removal of unreachable loop
        // tails. Native protected continue/break handlers also inspect target-1,
        // so a continue to the first protected word cannot use ordinary JmpLoop.
        for fixup in &self.fixups {
            let Some(opcode) = self.out.get_mut(fixup.at.wrapping_sub(1)) else {
                continue;
            };
            if matches!(*opcode, 0x0f | 0xf8 | 0x12e | 0x12f) {
                if ids.native_try_continue(fixup.source) || ids.native_try_goto(fixup.source) {
                    *opcode = 0x12f;
                } else if ids.native_try_break(fixup.source) {
                    *opcode = 0x12e;
                } else if ids.native_goto(fixup.source) {
                    *opcode = 0xf8;
                }
            }
        }
        for (index, fixup) in self.fixups.into_iter().enumerate() {
            let target = *self.offsets.get(&fixup.target).ok_or_else(|| LowerError {
                kind: LowerErrorKind::MalformedControlFlow,
                offset: fixup.source,
                reason: format!(
                    "branch target {} is not an instruction boundary",
                    fixup.target
                ),
            })? + self.safe.safe_skip_pop.get(&index).copied().unwrap_or(0);
            let source_state = self
                .iterator_states
                .range(..=fixup.source)
                .next_back()
                .map(|(_, frames)| frames.as_slice())
                .unwrap_or(&[]);
            let target_state = if fixup.target as usize > code.len() {
                // A virtual label joins a reordered native expression within the
                // current scope. Its large ID is not a later OpenDream byte offset.
                source_state
            } else {
                self.iterator_states
                    .range(..=fixup.target as usize)
                    .next_back()
                    .map(|(_, frames)| frames.as_slice())
                    .unwrap_or(&[])
            };
            let common = source_state
                .iter()
                .zip(target_state)
                .take_while(|(a, b)| a == b)
                .count();
            let cleanup = if common == target_state.len() {
                iterator_cleanup(source_state, common)
            } else {
                Vec::new()
            };
            if cleanup.is_empty() {
                self.out[fixup.at] = target;
            } else {
                let branch_opcode = self.out[fixup.at - 1];
                if matches!(branch_opcode, 0x12e | 0x12f) {
                    // Iterator cleanup must precede the exception-aware transfer;
                    // the trampoline itself is outside every protected region.
                    self.out[fixup.at - 1] = 0x0f;
                }
                self.out[fixup.at] = (self.out.len() + 1 + trampolines.len()) as u32;
                trampolines.extend(cleanup);
                trampolines.extend([
                    if matches!(branch_opcode, 0x12e | 0x12f) {
                        branch_opcode
                    } else {
                        0x0f
                    },
                    target,
                ]);
            }
        }
        if let Some(referenced_args) = referenced_args {
            referenced_args.extend(self.reader.referenced_args);
        }
        self.out.push(0); // DreamMaker terminates every nonempty procedure with End.
        self.out.extend(trampolines);
        Ok(self.out)
    }
}
