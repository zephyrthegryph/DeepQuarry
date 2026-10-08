use super::*;

#[derive(Default)]
pub(super) struct WorldFlow {
    pub(super) joins: std::collections::HashSet<u32>,
    pub(super) targets: std::collections::HashSet<u32>,
    pub(super) reused: bool,
    pub(super) candidate_pop_markers: std::collections::HashSet<u32>,
}

impl WorldFlow {
    pub(super) fn pop_is_unshared(&mut self, reader: &Reader<'_>, fixups: &[Fixup]) -> bool {
        let target = reader.at as u32;
        if reader.code.get(reader.at) != Some(&0x51)
            || self.joins.contains(&target)
            || fixups.iter().any(|fixup| fixup.target == target)
        {
            return false;
        }
        // A later backedge may enter this Pop. The first pass collects every
        // actual source target; retry only if one intersects a chosen marker.
        self.candidate_pop_markers.insert(target);
        true
    }

    pub(super) fn separate_reordered_arguments(
        &mut self,
        spans: &[(usize, usize)],
        offsets: &HashMap<u32, u32>,
        source_len: usize,
    ) {
        for &(begin, _) in spans {
            if let Some(position) = offsets
                .iter()
                .filter(|(source, position)| {
                    **source as usize <= source_len && **position as usize <= begin
                })
                .map(|(_, position)| *position)
                .max()
            {
                self.targets
                    .extend(offsets.iter().filter_map(|(source, value)| {
                        (*value == position && *source as usize <= source_len).then_some(*source)
                    }));
            }
        }
    }
}
/// Mutable state shared by receiver, formatting, and output instruction
/// families during one procedure lowering pass.
#[derive(Default)]
pub(super) struct LowerState {
    pub(super) pending_world_ref: Option<PendingWorld>,
    pub(super) cached_world_owner: bool,
    pub(super) last_reference_push: Option<(usize, Variable)>,
    pub(super) last_push_nrefs: Option<(usize, u32)>,
    pub(super) last_was_format: bool,
    pub(super) pending_output_run: bool,
}

/// One guarded access may create several native branches and cleanup frames.
/// Keep its state together so future safe-access lowering can move out of the
/// central opcode dispatch without carrying a dozen independent parameters.
#[derive(Default)]
pub(super) struct SafeAccessState {
    pub(super) pending_safe_field: bool,
    pub(super) pending_safe_index: Option<u32>,
    pub(super) last_safe_index: Option<(usize, u32, usize)>,
    pub(super) pending_safe_aug_sub: bool,
    pub(super) pending_safe_lvalue_at: Option<(usize, bool)>,
    pub(super) pending_safe_lvalue_body: Option<usize>,
    pub(super) pending_safe_lvalue_stack: Vec<(usize, bool, Option<usize>)>,
    pub(super) pending_safe_index_lvalue: Option<(usize, usize)>,
    pub(super) last_safe_field: Option<(usize, u32, usize, usize)>,
    pub(super) nested_safe_pop: Option<(u32, u32)>,
    pub(super) safe_chain_fixups: Vec<usize>,
    pub(super) safe_skip_pop: HashMap<usize, u32>,
}

pub(super) enum PendingReceiver {
    SafeCached,
    NativeCached,
    NativeCachedReference(Variable, bool),
    NativeReference(Variable),
}

pub(super) struct PickLowering<'a> {
    pub(super) code: &'a [u8],
    pub(super) start: usize,
    pub(super) out: &'a mut Vec<u32>,
    pub(super) offsets: &'a mut HashMap<u32, u32>,
    pub(super) fixups: &'a mut Vec<Fixup>,
    pub(super) world_flow: &'a mut WorldFlow,
    pub(super) state: &'a mut LowerState,
    pub(super) probability_regions: &'a mut Vec<(u32, u32)>,
}

impl PickLowering<'_> {
    pub(super) fn lower(&mut self, weighted: bool, count: usize) -> Result<(), LowerError> {
        let code = self.code;
        let start = self.start;
        let out = &mut *self.out;
        let offsets = &mut *self.offsets;
        let fixups = &mut *self.fixups;
        let world_flow = &mut *self.world_flow;
        let state = &mut *self.state;
        let probability_regions = &mut *self.probability_regions;
        if weighted {
            // Native weighted pick evaluates weights, then evaluates only
            // the selected candidate. OD places eager weight/value pairs
            // on its stack; split those pairs by verified stack effects.

            let operand_count = count
                .checked_mul(2)
                .filter(|&n| n <= code.len())
                .ok_or_else(|| LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "PickWeighted candidate count exceeds bytecode bounds".into(),
                })?;
            if count < 2 {
                return Err(LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "PickWeighted requires at least two candidates".into(),
                });
            }
            let mut end = out.len();
            let mut spans = Vec::with_capacity(operand_count);
            for _ in 0..operand_count {
                let at = guarded_assignment_spans(&out[..end], code, offsets, fixups, start, 0)
                    .map(|(first, _)| first)
                    .or_else(|| constructor_argument_start(&out[..end], 1))
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "PickWeighted operand has unknown stack effects".into(),
                    })?;
                spans.push((at, end));
                end = at;
            }
            spans.reverse();
            let base = end;
            if !closed_spans(&spans, offsets, fixups) {
                return Err(LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "PickWeighted operands have nonlocal branches".into(),
                });
            }
            world_flow.separate_reordered_arguments(&spans, offsets, code.len());
            state.cached_world_owner = false;
            state.pending_world_ref = None;
            state.last_reference_push = None;
            let external_entries: Vec<_> = fixups
                .iter()
                .filter(|f| f.at < base && offsets.get(&f.target).copied() == Some(base as u32))
                .map(|f| f.target)
                .collect();
            let mut literal_weights = Some(Vec::with_capacity(count));
            for pair in spans.chunks_exact(2) {
                let items =
                    crate::bytecode::decode(&out[pair[0].0..pair[0].1]).map_err(|error| {
                        LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: error.reason,
                        }
                    })?;
                if items.len() != 1
                    || items[0].opcode != 0x60
                    || items[0].operands.len() != 3
                    || items[0].operands[0] != 0x2a
                {
                    literal_weights = None;
                    break;
                }
                let operands = &items[0].operands;
                let weight = f32::from_bits((operands[1] << 16) | operands[2]);
                if !weight.is_finite() || weight < 0.0 {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "PickWeighted requires finite nonnegative weights".into(),
                    });
                }
                literal_weights.as_mut().unwrap().push(weight as f64);
            }
            let mut replacement = Vec::new();
            let mut moved = Vec::new();
            let table_at;
            let mut address_slots = Vec::with_capacity(count);
            if let Some(weights) = literal_weights {
                let total: f64 = weights.iter().sum();
                if total <= 0.0 {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "PickWeighted requires positive total weight".into(),
                    });
                }
                table_at = 0;
                replacement.extend([0x79, count as u32 - 1]);
                let mut cumulative = 0u32;
                for weight in weights.iter().take(count - 1) {
                    // DreamMaker truncates each normalized weight before
                    // accumulating it, rather than truncating the sum.
                    cumulative += ((weight / total) * 65535.0).floor() as u32;
                    replacement.push(cumulative);
                    address_slots.push(replacement.len());
                    replacement.push(0);
                }
                address_slots.push(replacement.len());
                replacement.push(0);
            } else {
                for pair in spans.chunks_exact(2) {
                    moved.push((pair[0], base + replacement.len()));
                    replacement.extend_from_slice(&out[pair[0].0..pair[0].1]);
                }
                table_at = replacement.len();
                replacement.extend([0xb1, count as u32]);
                for _ in 0..count {
                    address_slots.push(replacement.len());
                    replacement.push(0);
                }
            }
            let mut jumps = Vec::new();
            for (index, pair) in spans.chunks_exact(2).enumerate() {
                let at = base + replacement.len();
                replacement[address_slots[index]] = at as u32;
                moved.push((pair[1], at));
                replacement.extend_from_slice(&out[pair[1].0..pair[1].1]);
                if index + 1 < count {
                    jumps.push(replacement.len() + 1);
                    replacement.extend([0x0f, 0]);
                }
            }
            let new_end = base + replacement.len();
            for jump in &jumps {
                replacement[*jump] = new_end as u32;
            }
            let old_end = out.len();
            // Rebind source positions inside moved expressions so outside
            // branches and debug markers still target their own code.
            let mut remapped_offsets = Vec::new();
            for (&source, &position) in &*offsets {
                let old = position as usize;
                if old >= base && old < old_end {
                    let new = moved
                        .iter()
                        .find(|((lo, hi), _)| old >= *lo && old < *hi)
                        .map(|((lo, _), new)| new + old - lo)
                        .unwrap_or(base + table_at) as u32;
                    remapped_offsets.push((source, new));
                }
            }
            let original_offsets = moved_offset_snapshot(offsets, fixups, &moved);
            replace_words(out, offsets, fixups, base, old_end - base, &replacement);
            offsets.extend(remapped_offsets);
            remap_closed_spans(&original_offsets, offsets, fixups, &moved);
            for target in external_entries {
                offsets.insert(target, base as u32);
            }
            offsets.insert(start as u32, base as u32);
            for at in address_slots.into_iter().chain(jumps) {
                let target = out[base + at];
                let mut synthetic = 0x8000_0000;
                while offsets.contains_key(&synthetic) {
                    synthetic += 1;
                }
                offsets.insert(synthetic, target);
                fixups.push(Fixup {
                    at: base + at,
                    target: synthetic,
                    source: start,
                });
            }
            if table_at != 0 {
                // Private labels participate in every later word relocation.
                // They are never branch destinations or source instructions.
                let begin = code.len() as u32 + 1 + probability_regions.len() as u32 * 2;
                let end = begin + 1;
                offsets.insert(begin, base as u32);
                offsets.insert(end, (base + table_at) as u32);
                probability_regions.push((begin, end));
            }
        } else {
            if count == 0 || count > code.len() {
                return Err(LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "PickUnweighted count is outside supported range".into(),
                });
            }
            if count == 1 {
                out.push(0xd2); // Native pick(list) evaluates its sole argument.
            } else {
                let mut end = out.len();
                let mut spans = Vec::with_capacity(count);
                for _ in 0..count {
                    let at = guarded_assignment_spans(&out[..end], code, offsets, fixups, start, 0)
                        .map(|(first, _)| first)
                        .or_else(|| constructor_argument_start(&out[..end], 1))
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "PickUnweighted operand has unknown stack effects".into(),
                        })?;
                    spans.push((at, end));
                    end = at;
                }
                spans.reverse();
                let base = end;
                if !closed_spans(&spans, offsets, fixups) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "PickUnweighted operands have nonlocal branches".into(),
                    });
                }
                world_flow.separate_reordered_arguments(&spans, offsets, code.len());
                state.cached_world_owner = false;
                state.pending_world_ref = None;
                state.last_reference_push = None;
                let external_entries: Vec<_> = fixups
                    .iter()
                    .filter(|f| f.at < base && offsets.get(&f.target).copied() == Some(base as u32))
                    .map(|f| f.target)
                    .collect();
                let mut replacement = vec![0x79, count as u32 - 1];
                let step = 65535 / count as u32;
                let mut address_slots = Vec::with_capacity(count);
                for index in 1..count {
                    replacement.push(step * index as u32);
                    address_slots.push(replacement.len());
                    replacement.push(0);
                }
                address_slots.push(replacement.len());
                replacement.push(0);
                let mut moved = Vec::with_capacity(count);
                let mut jumps = Vec::new();
                for (index, span) in spans.iter().copied().enumerate() {
                    let at = base + replacement.len();
                    replacement[address_slots[index]] = at as u32;
                    moved.push((span, at));
                    replacement.extend_from_slice(&out[span.0..span.1]);
                    if index + 1 < count {
                        jumps.push(replacement.len() + 1);
                        replacement.extend([0x0f, 0]);
                    }
                }
                let new_end = base + replacement.len();
                for jump in &jumps {
                    replacement[*jump] = new_end as u32;
                }
                let old_end = out.len();
                replace_closed_spans(
                    out,
                    offsets,
                    fixups,
                    base,
                    old_end - base,
                    &replacement,
                    &moved,
                );
                for target in external_entries {
                    offsets.insert(target, base as u32);
                }
                offsets.insert(start as u32, base as u32);
                // Register native-internal branches so subsequent expression
                // relocation and receiver folding also update this lazy pick.
                for at in address_slots.into_iter().chain(jumps) {
                    let target = out[base + at];
                    let mut synthetic = 0x8000_0000;
                    while offsets.contains_key(&synthetic) {
                        synthetic += 1;
                    }
                    offsets.insert(synthetic, target);
                    fixups.push(Fixup {
                        at: base + at,
                        target: synthetic,
                        source: start,
                    });
                }
            }
        }
        Ok(())
    }
}
