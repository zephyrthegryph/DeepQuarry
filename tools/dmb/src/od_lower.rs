//! Guarded translation of OpenDream VM instructions to BYOND v516 code words.
//!
//! OpenDream's bytecode is byte-addressed and has its own reference model. This
//! module deliberately rejects operations whose BYOND stack or call convention
//! has not been established, rather than emitting a plausible but invalid DMB.
use crate::operands::{Value, Variable};
use std::collections::HashMap;

/// OpenDream operations with the same stack contract and no immediate
/// operands in native BYOND. Keep these mappings apart from operations that
/// need cache, branch, or call-frame rewrites.
fn direct_stack_opcode(op: u8) -> Option<u32> {
    const PAIRS: &[(u8, u32)] = &[
        (0x08, 0x3e),
        (0x12, 0x3f),
        (0x28, 0x40),
        (0x27, 0x41),
        (0x19, 0x42),
        (0x42, 0x6a),
        (0x18, 0x3d),
        (0x16, 0x0e),
        (0x25, 0x38),
        (0x13, 0x39),
        (0x14, 0x3a),
        (0x1d, 0x3b),
        (0x31, 0x3c),
        (0x24, 0x7e),
        (0x2b, 0x7f),
        (0x2a, 0x80),
        (0x2c, 0x81),
        (0x01, 0x82),
        (0x40, 0x83),
        (0x4c, 0x9e),
        (0x58, 0x140),
        (0x59, 0x141),
        (0x49, 0x7d),
        (0x52, 0x21),
        (0x76, 0x6d),
        (0x77, 0x96),
        (0x79, 0x182),
        (0x7a, 0x183),
        (0x7b, 0x184),
        (0x7c, 0xc4),
        (0x7d, 0xc5),
        (0x7e, 0x145),
        (0x7f, 0x146),
        (0x80, 0x69),
        (0x82, 0x31),
        (0x83, 0x68),
        (0x60, 0x176),
    ];
    PAIRS
        .iter()
        .find(|(source, _)| *source == op)
        .map(|(_, target)| *target)
}

/// Emit the OpenDream stack operation family. Equality is the one member
/// whose retained operand needs an extra native flag conversion.
fn emit_stack_operation(
    op: u8,
    next_source_opcode: Option<&u8>,
    next_source_offset: usize,
    fixups: &[Fixup],
    out: &mut Vec<u32>,
) -> bool {
    if let Some(native) = direct_stack_opcode(op) {
        out.push(native);
        return true;
    }
    if op != 0x0f {
        return false;
    }
    out.push(0x37); // CompareEquals sets the native comparison flag.
    if next_source_opcode != Some(&0x0c)
        || fixups
            .iter()
            .any(|fixup| fixup.target as usize == next_source_offset)
    {
        out.extend([0x51, 0x36]); // Pop retained operand; push boolean.
    }
    true
}

pub trait SymbolResolver {
    fn string(&self, old: u32) -> Option<u32> {
        Some(old)
    }
    /// Effective native method name for an exporter-resolved procedure binding.
    fn method_call_name(&self, _old_proc: u32, old_field: u32) -> Option<u32> {
        self.string(old_field)
    }
    /// Native selector for a bare self call, resolved in the current proc's owner.
    fn self_call_name(&self, old_field: u32) -> Option<u32> {
        self.method_call_name(u32::MAX, old_field)
    }
    fn method_call_is_verb(&self, _old_proc: u32) -> bool {
        false
    }
    fn self_call_is_verb(&self, _old_field: u32) -> bool {
        false
    }
    fn type_id(&self, old: u32) -> Option<u32> {
        Some(old)
    }
    fn proc_id(&self, old: u32) -> Option<u32> {
        Some(old)
    }
    /// A native OpenDream global proc that DreamMaker emits as one opcode.
    /// Return the verified BYOND opcode, or None for an ordinary proc.
    fn builtin_proc(&self, _old: u32) -> Option<u32> {
        None
    }
    /// Native instance prototype for `new /type{constant_overrides}`.
    /// The second ID indexes the original OpenDream JSON string table.
    fn modified_instance(&self, _old_type: u32, _old_string: u32) -> Option<u32> {
        None
    }
    fn sound_type_string(&self) -> Option<u32> {
        None
    }
    fn icon_type_string(&self) -> Option<u32> {
        None
    }
    fn generator_type_string(&self) -> Option<u32> {
        None
    }
    fn resource(&self, old: u32) -> Option<u32> {
        Some(old)
    }
    /// Exporter-proven implicit locate container at an optimized byte offset.
    fn implicit_locate(&self, _offset: usize) -> bool {
        false
    }
    /// Exporter-proven authored null load, distinct from synthetic null padding.
    fn native_try_continue(&self, _offset: usize) -> bool {
        false
    }
    fn native_try_goto(&self, _offset: usize) -> bool {
        false
    }
    /// Authored goto performs native loop-budget dispatch even to a forward label.
    fn native_goto(&self, _offset: usize) -> bool {
        false
    }
    /// None is a legacy export without authored-continue provenance.
    fn native_continue(&self, _offset: usize) -> Option<bool> {
        None
    }
    /// Nonconstant authored do/while condition checks the budget on both outcomes.
    fn native_do_while_condition(&self, _offset: usize) -> bool {
        false
    }
    fn native_try_break(&self, _offset: usize) -> bool {
        false
    }
    fn native_constant_global(&self, _old: u32) -> bool {
        false
    }
    fn native_initial_reference_offsets(&self) -> &[usize] {
        &[]
    }
    fn native_is_saved_reference_offsets(&self) -> &[usize] {
        &[]
    }
    fn native_is_saved_reference(&self, _offset: usize) -> bool {
        false
    }
    fn native_initial_reference(&self, _offset: usize) -> bool {
        false
    }
    fn native_delete_clear(&self, _offset: usize) -> bool {
        false
    }
    /// Optimizer-created local/argument statement-store followed by a reload.
    fn native_store_reload(&self, _offset: usize) -> bool {
        false
    }
    fn native_store_reload_offsets(&self) -> &[u32] {
        &[]
    }
    fn native_delete_src(&self, _offset: usize) -> bool {
        false
    }
    fn native_null(&self, _offset: usize) -> bool {
        false
    }
    fn global_vars_variable(&self) -> Option<u32> {
        None
    }
    fn global(&self, old: u32) -> Option<u32> {
        Some(old)
    }
    /// DMB value tag for a type path; `/datum` uses 32, atom paths use 8–11.
    fn type_tag(&self, _old: u32) -> Option<u8> {
        Some(32)
    }
    /// Coarse native iterator category derived from the type's actual ancestry.
    /// Coarse world-contents mask and exact-root filter elision for a lowered type.
    fn world_iterator_mask(&self, _tag: u8, _native_id: u32) -> Option<(u32, bool)> {
        None
    }
    fn iterator_type_mask(&self, _old: u32) -> Option<u32> {
        None
    }
    /// Exact native roots whose category mask replaces the subtype test.
    /// Other roots and every subtype retain their conditional budget check.
    fn iterator_root_mask(&self, _old: u32) -> Option<u32> {
        None
    }
}

impl SymbolResolver for () {}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LowerError {
    pub offset: usize,
    pub kind: LowerErrorKind,
    pub reason: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LowerErrorKind {
    TruncatedOperand,
    UnresolvedSymbol,
    UnsupportedConstruct,
    MalformedControlFlow,
}

#[derive(Clone, Copy)]
struct Fixup {
    at: usize,
    target: u32,
    source: usize,
}

struct TryFrame {
    try_at: usize,
    catch_target: u32,
    destination: Option<Variable>,
    source_local: Option<usize>,
    source_start: usize,
}

#[derive(Clone, Copy)]
struct PendingWorld {
    at: usize,
    world_cached_at_push: bool,
    rhs_changed_cache: bool,
}

fn emit_tracked_reference(
    out: &mut Vec<u32>,
    variable: &Variable,
    world_cached: &mut bool,
    pending_world: &mut Option<PendingWorld>,
) {
    fn cache_effect(variable: &Variable, before: bool) -> (bool, bool) {
        match variable {
            Variable::SetCache(owner, field) => {
                let (after, _) = cache_effect(field, **owner == Variable::World);
                (after, true)
            }
            Variable::Initial(field) | Variable::IsSaved(field) => cache_effect(field, before),
            _ => (before, false),
        }
    }
    let (mut after, mut changed) = cache_effect(variable, *world_cached);
    if *variable == Variable::Cache
        && out.last().is_some_and(
            |opcode| matches!(opcode, 0x34 | 0x35 | 0x45..=0x4e | 0x62..=0x67 | 0x15a | 0x177),
        )
    {
        after = false;
        changed = true;
    }
    out.extend(variable.encode());
    *world_cached = after;
    if changed && !after {
        if let Some(pending) = pending_world {
            pending.rhs_changed_cache = true;
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct IteratorFrame {
    id: u32,
    range_words: Option<u32>,
}

fn begin_list_iterator(out: &mut Vec<u32>, frames: &mut Vec<IteratorFrame>, id: u32) {
    if frames.iter().any(|frame| frame.range_words.is_none()) {
        out.push(0x54); // Save the enclosing native list iterator.
    }
    frames.push(IteratorFrame {
        id,
        range_words: None,
    });
}

fn iterator_cleanup(frames: &[IteratorFrame], keep: usize) -> Vec<u32> {
    let mut words = Vec::new();
    for index in (keep..frames.len()).rev() {
        if let Some(count) = frames[index].range_words {
            words.extend([0xfb, count]);
        } else if frames[..index]
            .iter()
            .any(|frame| frame.range_words.is_none())
        {
            words.push(0x55);
        }
    }
    words
}

struct Reader<'a> {
    code: &'a [u8],
    at: usize,
    local_slots: Vec<u32>,
    remap_locals: bool,
    referenced_args: Vec<u8>,
    native_arg_slots: Vec<Option<u32>>,
}
impl Reader<'_> {
    fn byte(&mut self) -> Result<u8, LowerError> {
        let at = self.at;
        let byte = *self.code.get(at).ok_or_else(|| LowerError {
            kind: LowerErrorKind::TruncatedOperand,
            offset: at,
            reason: "truncated OpenDream operand".into(),
        })?;
        self.at += 1;
        Ok(byte)
    }
    fn word(&mut self) -> Result<u32, LowerError> {
        let at = self.at;
        let bytes = self.code.get(at..at + 4).ok_or_else(|| LowerError {
            kind: LowerErrorKind::TruncatedOperand,
            offset: at,
            reason: "truncated OpenDream operand".into(),
        })?;
        self.at += 4;
        Ok(u32::from_le_bytes(bytes.try_into().unwrap()))
    }
}

fn mapped(value: Option<u32>, at: usize, kind: &str) -> Result<u32, LowerError> {
    value.ok_or_else(|| LowerError {
        kind: LowerErrorKind::UnresolvedSymbol,
        offset: at,
        reason: format!("unresolved OpenDream {kind} ID"),
    })
}

fn push_value(out: &mut Vec<u32>, tag: u8, id: u32) {
    out.push(0x60);
    out.extend(
        Value {
            tag_word: u32::from(tag) | ((id >> 16) << 8),
            data_word: id & 0xffff,
            extra_word: None,
        }
        .encode(),
    );
}

fn replace_words(
    out: &mut Vec<u32>,
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut [Fixup],
    start: usize,
    old_len: usize,
    replacement: &[u32],
) {
    let delta = replacement.len() as isize - old_len as isize;
    out.splice(start..start + old_len, replacement.iter().copied());
    for value in offsets.values_mut() {
        if (*value as usize) >= start + old_len {
            *value = (*value as isize + delta) as u32;
        }
    }
    for fixup in fixups {
        if fixup.at >= start + old_len {
            fixup.at = (fixup.at as isize + delta) as usize;
        }
    }
}

// Receiver cache analysis and rewrite are isolated from opcode emission.
include!("od_lower/receiver.rs");
include!("od_lower/call.rs");
include!("od_lower/assignment.rs");
include!("od_lower/safe_guard.rs");

/// Locate an indexed-assignment RHS containing verified expression diamonds.
/// Collapse each diamond only for stack-span analysis; emitted instructions and
/// their branch fixups remain intact until the caller relocates the whole RHS.
fn closed_spans(spans: &[(usize, usize)], offsets: &HashMap<u32, u32>, fixups: &[Fixup]) -> bool {
    let Some(&(base, _)) = spans.first() else {
        return false;
    };
    fixups.iter().all(|fixup| {
        if fixup.at < base {
            return offsets
                .get(&fixup.target)
                .is_none_or(|target| *target as usize <= base);
        }
        spans.iter().any(|(begin, end)| {
            fixup.at >= *begin
                && fixup.at < *end
                && offsets.get(&fixup.target).is_some_and(|target| {
                    (*target as usize) >= *begin && (*target as usize) <= *end
                })
        })
    })
}
fn remap_closed_spans(
    original: &HashMap<u32, u32>,
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut [Fixup],
    moved: &[((usize, usize), usize)],
) {
    for fixup in fixups.iter_mut() {
        if let Some(&((begin, end), destination)) = moved
            .iter()
            .find(|((begin, end), _)| fixup.at >= *begin && fixup.at < *end)
        {
            let target = original[&fixup.target] as usize;
            debug_assert!((begin..=end).contains(&target));
            let mut synthetic = 0x8000_0000;
            while offsets.contains_key(&synthetic) {
                synthetic += 1;
            }
            fixup.target = synthetic;
            offsets.insert(synthetic, (destination + target - begin) as u32);
            fixup.at = destination + fixup.at - begin;
        }
    }
    for (&byte, &word) in original {
        if let Some(&((begin, _), destination)) = moved
            .iter()
            .find(|((begin, end), _)| word as usize >= *begin && (word as usize) < *end)
        {
            offsets.insert(byte, (destination + word as usize - begin) as u32);
        }
    }
}

fn moved_offset_snapshot(
    offsets: &HashMap<u32, u32>,
    fixups: &[Fixup],
    moved: &[((usize, usize), usize)],
) -> HashMap<u32, u32> {
    let in_moved = |position: usize| {
        moved
            .iter()
            .any(|((begin, end), _)| (*begin..*end).contains(&position))
    };
    let mut snapshot: HashMap<_, _> = offsets
        .iter()
        .filter(|(_, &position)| in_moved(position as usize))
        .map(|(&source, &position)| (source, position))
        .collect();
    for fixup in fixups {
        if in_moved(fixup.at) {
            if let Some(&target) = offsets.get(&fixup.target) {
                snapshot.insert(fixup.target, target);
            }
        }
    }
    snapshot
}

/// Replace a closed expression region and relocate all source positions and
/// branch fixups that lived inside moved subexpressions. Callers verify
/// `closed_spans` first, so no external branch can enter a moved interior.
fn replace_closed_spans(
    out: &mut Vec<u32>,
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut [Fixup],
    start: usize,
    old_len: usize,
    replacement: &[u32],
    moved: &[((usize, usize), usize)],
) {
    let original_offsets = moved_offset_snapshot(offsets, fixups, moved);
    replace_words(out, offsets, fixups, start, old_len, replacement);
    remap_closed_spans(&original_offsets, offsets, fixups, moved);
}

/// Insert receiver code between closed expressions. Unlike `replace_words`,
/// source positions outside the moved expression spans keep their old values;
/// the caller is constructing a new suffix and will register its joins later.
fn insert_between_closed_spans(
    out: &mut Vec<u32>,
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut [Fixup],
    at: usize,
    inserted: &[u32],
    moved: &[((usize, usize), usize)],
) {
    let original_offsets = moved_offset_snapshot(offsets, fixups, moved);
    out.splice(at..at, inserted.iter().copied());
    remap_closed_spans(&original_offsets, offsets, fixups, moved);
}
fn guarded_indexed_spans(
    words: &[u32],
    code: &[u8],
    offsets: &HashMap<u32, u32>,
    fixups: &[Fixup],
    assignment: usize,
) -> Option<(usize, usize)> {
    guarded_assignment_spans(words, code, offsets, fixups, assignment, 2)
}

fn guarded_assignment_spans(
    words: &[u32],
    code: &[u8],
    offsets: &HashMap<u32, u32>,
    fixups: &[Fixup],
    assignment: usize,
    destination_count: usize,
) -> Option<(usize, usize)> {
    let mut compressed = words.to_vec();
    let mut origins: Vec<usize> = (0..words.len()).collect();
    let complete_arguments = |span: &[u32], count| {
        constructor_argument_start(span, count).is_some_and(|at| {
            crate::bytecode::decode(&span[..at]).is_ok_and(|items| {
                items
                    .iter()
                    .all(|item| matches!(item.opcode, 0x84 | 0x85 | 0x142 | 0x143))
            })
        })
    };
    let mut diamonds = Vec::new();
    for jump in fixups {
        if code.get(jump.source) != Some(&0x0e) || jump.target > assignment as u32 {
            continue;
        }
        let join = *offsets.get(&jump.target)? as usize;
        if join > words.len() || jump.at + 1 > join {
            continue;
        }
        if let Some(branch) = fixups.iter().rev().find(|branch| {
            branch.at < jump.at
                && matches!(code.get(branch.source), Some(0x0c | 0x8b))
                && offsets.get(&branch.target).copied() == Some((jump.at + 1) as u32)
        }) {
            diamonds.push((*branch, *jump, join));
        }
    }
    diamonds.sort_by_key(|(branch, _, join)| join.saturating_sub(branch.at));
    let mut collapsed = false;
    loop {
        let previous_len = compressed.len();
        // A lowered multiargument pick is one value whose candidate blocks are
        // mutually exclusive. Collapse only our registered, closed pick tables.
        let mut picks: Vec<_> = fixups
            .iter()
            .filter_map(|jump| {
                let begin = *offsets.get(&(jump.source as u32))? as usize;
                let end = *offsets.get(&jump.target)? as usize;
                if !matches!(code.get(jump.source), Some(0x54 | 0x55)) {
                    return None;
                }
                let first_slot = fixups
                    .iter()
                    .filter(|f| f.source == jump.source)
                    .map(|f| f.at)
                    .min()?;
                let table = if first_slot >= 3 && words.get(first_slot - 3) == Some(&0x79) {
                    first_slot - 3
                } else if first_slot >= 2 && words.get(first_slot - 2) == Some(&0xb1) {
                    first_slot - 2
                } else {
                    return None;
                };
                // A constructor/output receiver may have been inserted at the
                // source expression entry. It remains outside the pick value.
                let begin = if words[table] == 0x79 { table } else { begin };
                let header_end = table
                    + if words[table] == 0x79 {
                        2 * words[table + 1] as usize + 3
                    } else {
                        words[table + 1] as usize + 2
                    };
                (begin <= table
                    && jump.at >= header_end
                    && words.get(jump.at - 1) == Some(&0x0f)
                    && end <= words.len())
                .then_some((begin, end, jump.source, table, header_end))
            })
            .collect();
        picks.sort_unstable_by_key(|(begin, _, _, _, _)| std::cmp::Reverse(*begin));
        picks.dedup();
        for (mut begin, end, source, table, header_end) in picks {
            let index = |original: usize| {
                if original == words.len() {
                    Some(origins.len())
                } else {
                    origins.iter().position(|offset| *offset == original)
                }
            };
            let (Some(mut first), Some(last)) = (index(begin), index(end)) else {
                continue;
            };
            let Some(table_index) = index(table) else {
                continue;
            };
            if !matches!(compressed.get(table_index), Some(0x79 | 0xb1)) {
                continue;
            }
            let mut candidates: Vec<_> = fixups
                .iter()
                .filter_map(|branch| {
                    (branch.source == source && branch.at > table && branch.at < header_end)
                        .then(|| offsets.get(&branch.target).copied().map(|at| at as usize))
                        .flatten()
                })
                .collect();
            candidates.sort_unstable();
            candidates.dedup();
            let count = words[table + 1] as usize + usize::from(words[table] == 0x79);
            if candidates.len() != count {
                continue;
            }
            if words[table] == 0xb1 {
                let Some(probability_start) =
                    constructor_argument_start(&compressed[..table_index], count)
                else {
                    continue;
                };
                if !complete_arguments(&compressed[probability_start..table_index], count) {
                    continue;
                }
                first = probability_start;
                begin = origins[first];
            }
            let valid = candidates.iter().enumerate().all(|(i, candidate)| {
                let candidate_end = if i + 1 == candidates.len() {
                    end
                } else {
                    candidates[i + 1].saturating_sub(2)
                };
                let (Some(lo), Some(hi)) = (index(*candidate), index(candidate_end)) else {
                    return false;
                };
                lo <= hi && complete_arguments(&compressed[lo..hi], 1)
            });
            if !valid
                || fixups.iter().any(|branch| {
                    let inside = branch.at >= begin && branch.at < end;
                    let target = offsets.get(&branch.target).copied().map(|at| at as usize);
                    inside && target.is_none_or(|at| at < begin || at > end)
                        || !inside && target.is_some_and(|at| at > begin && at < end)
                })
            {
                continue;
            }
            compressed.splice(first..last, [0x50, 0]);
            origins.splice(first..last, [begin, begin]);
            collapsed = true;
        }
        for (branch, jump, join) in diamonds.iter().copied() {
            let index = |original: usize| {
                if original == words.len() {
                    Some(origins.len())
                } else {
                    origins.iter().position(|offset| *offset == original)
                }
            };
            let Some(true_start) = index(branch.at + 1) else {
                continue;
            };
            let Some(true_end) = index(jump.at - 1) else {
                continue;
            };
            let Some(false_start) = index(jump.at + 1) else {
                continue;
            };
            let Some(end) = index(join) else { continue };
            if !complete_arguments(&compressed[true_start..true_end], 1)
                || !complete_arguments(&compressed[false_start..end], 1)
            {
                continue;
            }
            let source_at = *offsets.get(&(branch.source as u32))? as usize;
            let Some(source_index) = index(source_at) else {
                continue;
            };
            let begin = if code.get(branch.source) == Some(&0x8b) {
                source_index
            } else {
                let Some(begin) = constructor_argument_start(&compressed[..source_index], 1) else {
                    continue;
                };
                begin
            };
            let original_begin = origins[begin];
            // A structured expression may contain nested diamonds, but cannot jump
            // out of its own span or receive a branch from an unrelated statement.
            if fixups.iter().any(|fixup| {
                let source_inside = fixup.at >= original_begin && fixup.at < join;
                let target = offsets.get(&fixup.target).copied().map(|at| at as usize);
                source_inside && target.is_none_or(|at| at < original_begin || at > join)
                    || !source_inside && target.is_some_and(|at| at > original_begin && at < join)
            }) {
                continue;
            }
            compressed.splice(begin..end, [0x50, 0]);
            origins.splice(begin..end, [original_begin, original_begin]);
            collapsed = true;
        }
        // A safe field read produces null on the taken edge and one field value
        // otherwise. Keep its evaluated owner inside the expression span.
        for branch in fixups.iter().filter(|branch| {
            branch.target <= assignment as u32
                && branch.at > 0
                && words.get(branch.at - 1) == Some(&0x13d)
                && code.get(branch.source) == Some(&0x65)
        }) {
            let join = *offsets.get(&branch.target)? as usize;
            let locate = |original| {
                if original == words.len() {
                    Some(origins.len())
                } else {
                    origins.iter().position(|offset| *offset == original)
                }
            };
            let Some(branch_at) = locate(branch.at - 1) else {
                continue;
            };
            let Some(body_at) = locate(branch.at + 1) else {
                continue;
            };
            let Some(end) = locate(join) else { continue };
            if !complete_arguments(&compressed[body_at..end], 1) {
                continue;
            }
            let Some(begin) = constructor_argument_start(&compressed[..branch_at], 1) else {
                continue;
            };
            let original_begin = origins[begin];
            if fixups.iter().any(|fixup| {
                let inside = fixup.at >= original_begin && fixup.at < join;
                let target = offsets.get(&fixup.target).copied().map(|at| at as usize);
                inside && target.is_none_or(|at| at < original_begin || at > join)
                    || !inside && target.is_some_and(|at| at > original_begin && at < join)
            }) {
                continue;
            }
            compressed.splice(begin..end, [0x50, 0]);
            origins.splice(begin..end, [original_begin, original_begin]);
            collapsed = true;
        }
        // Short-circuit operators preserve the left value on the taken edge and
        // otherwise replace it with one RHS value. Collapse only closed spans.
        let mut short_circuits: Vec<_> = fixups
            .iter()
            .filter_map(|branch| {
                let join = *offsets.get(&branch.target)? as usize;
                (branch.target <= assignment as u32
                    && branch.at > 0
                    && matches!(words.get(branch.at - 1), Some(0xb2 | 0xb3))
                    && matches!(code.get(branch.source), Some(0x15 | 0x2f | 0x66 | 0x67)))
                .then_some((*branch, join))
            })
            .collect();
        short_circuits.sort_by_key(|(branch, join)| join.saturating_sub(branch.at));
        for (branch, join) in short_circuits {
            let locate = |original| {
                if original == words.len() {
                    Some(origins.len())
                } else {
                    origins.iter().position(|offset| *offset == original)
                }
            };
            let Some(branch_at) = locate(branch.at - 1) else {
                continue;
            };
            let Some(rhs_at) = locate(branch.at + 1) else {
                continue;
            };
            let Some(end) = locate(join) else { continue };
            if !complete_arguments(&compressed[rhs_at..end], 1) {
                continue;
            }
            let Some(begin) = constructor_argument_start(&compressed[..branch_at], 1) else {
                continue;
            };
            let original_begin = origins[begin];
            if fixups.iter().any(|fixup| {
                let inside = fixup.at >= original_begin && fixup.at < join;
                let target = offsets.get(&fixup.target).copied().map(|at| at as usize);
                inside && target.is_none_or(|at| at < original_begin || at > join)
                    || !inside && target.is_some_and(|at| at > original_begin && at < join)
            }) {
                continue;
            }
            compressed.splice(begin..end, [0x50, 0]);
            origins.splice(begin..end, [original_begin, original_begin]);
            collapsed = true;
        }
        if compressed.len() == previous_len {
            break;
        }
    }
    if !collapsed {
        return None;
    }
    let rhs = constructor_argument_start(&compressed, 1)?;
    let list = if destination_count == 0 {
        rhs
    } else {
        constructor_argument_start(&compressed[..rhs], destination_count)?
    };
    let list_at = origins[list];
    let value_at = origins[rhs];
    // The compressed destination must consist of exactly two verified values.
    // Closed branches in either value retain their original code and fixups.
    if destination_count != 0 && !complete_arguments(&compressed[list..rhs], destination_count) {
        return None;
    }
    Some((list_at, value_at))
}

// A switch may fold its synthetic default jump into the table, but an authored
// transfer still performs its own loop budget or exception-frame operation.
fn authored_control_jump(ids: &impl SymbolResolver, code: &[u8], offset: usize) -> bool {
    let backward = code
        .get(offset + 1..offset + 5)
        .is_some_and(|bytes| u32::from_le_bytes(bytes.try_into().unwrap()) as usize <= offset);
    backward
        || ids.native_continue(offset) == Some(true)
        || ids.native_goto(offset)
        || ids.native_try_continue(offset)
        || ids.native_try_break(offset)
        || ids.native_try_goto(offset)
}

fn read_do_while_backedge(
    reader: &mut Reader<'_>,
    start: usize,
    false_target: u32,
) -> Result<(usize, u32), LowerError> {
    let jump = reader.at;
    if reader.code.get(jump) != Some(&0x0e) || false_target as usize != jump + 5 {
        return Err(LowerError {
            kind: LowerErrorKind::MalformedControlFlow,
            offset: start,
            reason: "native do/while condition lacks its paired exit/backedge".into(),
        });
    }
    reader.byte()?;
    let target = reader.word()?;
    if target as usize >= start {
        return Err(LowerError {
            kind: LowerErrorKind::MalformedControlFlow,
            offset: start,
            reason: "native do/while condition has no backward loop body".into(),
        });
    }
    Ok((jump, target))
}
// The inserted constructor receiver belongs to the source expression's entry.
// External source branches must execute it; interior argument joins still shift.
fn insert_expression_prefix(
    out: &mut Vec<u32>,
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut [Fixup],
    at: usize,
    prefix: &[u32],
) {
    let entries: Vec<_> = offsets
        .iter()
        .filter_map(|(&byte, &word)| (word as usize == at).then_some(byte))
        .collect();
    replace_words(out, offsets, fixups, at, 0, prefix);
    for entry in entries {
        offsets.insert(entry, at as u32);
    }
}
fn preserve_external_expression_entry(
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut [Fixup],
    begin: usize,
    end: usize,
) -> Option<u32> {
    let incoming: Vec<_> = fixups
        .iter()
        .enumerate()
        .filter_map(|(index, fixup)| {
            (!(begin..end).contains(&fixup.at)
                && offsets.get(&fixup.target).copied() == Some(begin as u32))
            .then_some(index)
        })
        .collect();
    if incoming.is_empty() {
        return None;
    }
    let mut label = 0x8000_0000;
    while offsets.contains_key(&label) {
        label += 1;
    }
    offsets.insert(label, begin as u32);
    for index in incoming {
        fixups[index].target = label;
    }
    Some(label)
}

/// Rotate a verified conditional RHS before its indexed destination, retaining
/// all branches within the expression and its join before destination reads.
fn reorder_guarded_indexed_rhs(
    out: &mut Vec<u32>,
    code: &[u8],
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut [Fixup],
    safe_skip_pop: &mut HashMap<usize, u32>,
    start: usize,
    trailer: &[u32],
) -> bool {
    let Some((list_at, value_at)) = guarded_indexed_spans(out, code, offsets, fixups, start) else {
        return false;
    };
    let end = out.len();
    let external_entry = preserve_external_expression_entry(offsets, fixups, list_at, end);
    let value_len = end - value_at;
    let mut replacement = out[value_at..end].to_vec();
    replacement.extend_from_slice(&out[list_at..value_at]);
    replacement.extend_from_slice(trailer);
    let moved = |old: usize| {
        if old < value_at {
            list_at + value_len + old - list_at
        } else {
            list_at + old - value_at
        }
    };
    for value in offsets.values_mut() {
        if (*value as usize) >= list_at && (*value as usize) < end {
            *value = moved(*value as usize) as u32;
        }
    }
    let synthetic_target = u32::MAX - start as u32;
    let destination_join = synthetic_target - 1;
    let safe_join = synthetic_target - 2;
    let cache_unwind = crate::bytecode::decode(&out[value_at..end])
        .ok()
        .map_or(0, |items| {
            items
                .iter()
                .rev()
                .take_while(|item| item.opcode == 0x143)
                .count()
        });
    for (index, fixup) in fixups.iter_mut().enumerate() {
        if fixup.at >= value_at && fixup.at < end && fixup.target == start as u32 {
            fixup.target = if fixup.at > 0 && out[fixup.at - 1] == 0x13d {
                let saved = cache_frame_depth(&out[value_at..fixup.at - 1]);
                safe_skip_pop
                    .entry(index)
                    .or_insert(cache_unwind.saturating_sub(saved) as u32);
                safe_join
            } else {
                synthetic_target
            };
        }
        if fixup.at >= list_at
            && fixup.at < value_at
            && offsets.get(&fixup.target).copied() == Some(list_at as u32)
        {
            // A destination expression joining at the old RHS boundary must
            // now join immediately before the store, after destination reads.
            fixup.target = destination_join;
        }
        if fixup.at >= list_at && fixup.at < end {
            fixup.at = moved(fixup.at);
        }
    }
    replace_words(out, offsets, fixups, list_at, end - list_at, &replacement);
    offsets.insert(synthetic_target, (list_at + value_len) as u32);
    offsets.insert(safe_join, (list_at + value_len - cache_unwind) as u32);
    offsets.insert(destination_join, end as u32);
    if let Some(label) = external_entry {
        offsets.insert(label, list_at as u32);
    }
    true
}

fn cache_frame_depth(words: &[u32]) -> usize {
    crate::bytecode::decode(words).ok().map_or(0, |items| {
        items.iter().fold(0usize, |depth, item| match item.opcode {
            0x142 => depth + 1,
            0x143 => depth.saturating_sub(1),
            _ => depth,
        })
    })
}

fn branch_retains_discarded_value(fixup: &Fixup, code: &[u8], words: &[u32]) -> bool {
    // Native logical-assignment statement branches consume their tested
    // value; expression branches (JmpOr/JmpAnd) retain it for the shared Pop.
    !matches!(
        (code.get(fixup.source), words.get(fixup.at.wrapping_sub(1))),
        (Some(0x66 | 0x67), Some(0x10 | 0x11)) | (Some(0x65), Some(0x13e))
    )
}

fn simple_new_tail(reader: &Reader<'_>, arguments: u32) -> Option<u32> {
    let tail = reader.code.get(reader.at..reader.at + 12)?;
    if tail[0] != 0x11
        || tail[1] != 0x02
        || tail[6] != 0x2e
        || tail[7] != 1
        || u32::from_le_bytes(tail[8..12].try_into().ok()?) != arguments
    {
        return None;
    }
    Some(u32::from_le_bytes(tail[2..6].try_into().ok()?))
}

fn emit_float_field_assignment(
    out: &mut Vec<u32>,
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut [Fixup],
    start: usize,
    field: u32,
    bits: u32,
) -> Result<(), LowerError> {
    let items = crate::bytecode::decode(out).map_err(|error| LowerError {
        kind: LowerErrorKind::MalformedControlFlow,
        offset: start,
        reason: format!("cannot inspect float field owner: {}", error.reason),
    })?;
    if let Some(owner) = items.last().filter(|item| {
        item.opcode == 0x33 && !fixups.iter().any(|fixup| fixup.target == start as u32)
    }) {
        let (variable, used) = Variable::decode(&owner.operands).map_err(|error| LowerError {
            kind: LowerErrorKind::MalformedControlFlow,
            offset: start,
            reason: format!("cannot decode float field owner: {}", error.reason),
        })?;
        if used != owner.operands.len() {
            return Err(LowerError {
                kind: LowerErrorKind::MalformedControlFlow,
                offset: start,
                reason: "float field owner has extra operands".into(),
            });
        }
        let mut replacement = vec![0x60, 0x2a, bits >> 16, bits & 0xffff, 0x34];
        replacement.extend(append_field(variable, field).encode());
        replace_words(
            out,
            offsets,
            fixups,
            owner.offset,
            1 + owner.operands.len(),
            &replacement,
        );
    } else {
        // A computed/branch-selected owner must be consumed into the cache;
        // leaving it under the scalar would corrupt the VM operand stack.
        out.extend([
            0x34,
            0xffd8,
            0x60,
            0x2a,
            bits >> 16,
            bits & 0xffff,
            0x34,
            field,
        ]);
    }
    Ok(())
}

/// OpenDream emits log(value, base) operands in VM order; native DM evaluates
/// the authored base argument first. Move complete expressions, including their
/// internal branches, rather than swapping already evaluated stack values.
fn reorder_log_arguments(
    out: &mut [u32],
    code: &[u8],
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut [Fixup],
    source: usize,
) -> Result<(), LowerError> {
    let argument_start = |words: &[u32]| {
        guarded_assignment_spans(words, code, offsets, fixups, source, 0)
            .map(|(_, rhs)| rhs)
            .or_else(|| constructor_argument_start(words, 1))
    };
    let middle = argument_start(out).ok_or_else(|| LowerError {
        kind: LowerErrorKind::MalformedControlFlow,
        offset: source,
        reason: "log base argument has unknown stack effects".into(),
    })?;
    let begin = argument_start(&out[..middle]).ok_or_else(|| LowerError {
        kind: LowerErrorKind::MalformedControlFlow,
        offset: source,
        reason: "log value argument has unknown stack effects".into(),
    })?;
    let end = out.len();
    let left_len = middle - begin;
    let right_len = end - middle;
    let old_fixups = fixups.to_vec();
    for (byte, word) in offsets.iter_mut() {
        let position = *word as usize;
        let left_join = position == middle
            && old_fixups
                .iter()
                .any(|f| f.target == *byte && f.at >= begin && f.at < middle);
        let right_join = position == end
            && old_fixups
                .iter()
                .any(|f| f.target == *byte && f.at >= middle && f.at < end);
        let outside_entry = position == begin
            && old_fixups
                .iter()
                .any(|f| f.target == *byte && (f.at < begin || f.at >= end));
        *word = if left_join {
            end
        } else if right_join {
            begin + right_len
        } else if outside_entry {
            begin
        } else if (begin..middle).contains(&position) {
            position + right_len
        } else if (middle..end).contains(&position) {
            position - left_len
        } else {
            position
        } as u32;
    }
    for fixup in fixups {
        if (begin..middle).contains(&fixup.at) {
            fixup.at += right_len;
        } else if (middle..end).contains(&fixup.at) {
            fixup.at -= left_len;
        }
    }
    out[begin..end].rotate_left(left_len);
    Ok(())
}

fn append_field(owner: Variable, field: u32) -> Variable {
    match owner {
        Variable::SetCache(lhs, rhs) => {
            Variable::SetCache(lhs, Box::new(append_field(*rhs, field)))
        }
        other => Variable::SetCache(Box::new(other), Box::new(Variable::Field(field))),
    }
}

fn append_method_selector(owner: Variable, selector: Variable) -> Variable {
    match owner {
        Variable::SetCache(lhs, rhs) => {
            Variable::SetCache(lhs, Box::new(append_method_selector(*rhs, selector)))
        }
        other => Variable::SetCache(Box::new(other), Box::new(selector)),
    }
}

fn constructor_argument_start(words: &[u32], count: usize) -> Option<usize> {
    // Source markers do not consume or produce VM values. Ignore them only
    // during span analysis, preserving their original offsets and wire words
    // when callers relocate an expression.
    let instructions: Vec<_> = crate::bytecode::decode(words)
        .ok()?
        .into_iter()
        .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
        .collect();
    let mut cache_stack = Vec::new();
    let mut cache_stores = Vec::new();
    let mut cache_calls = Vec::new();
    let mut cache_ops = Vec::new();
    for (index, item) in instructions.iter().enumerate() {
        if item.opcode == 0x142 {
            cache_stack.push(index);
        } else if item.opcode == 0x143 {
            if let Some(push) = cache_stack.pop() {
                if push > 0
                    && instructions[push - 1].opcode == 0x34
                    && instructions[push - 1].operands == [0xffd8]
                    && instructions.get(index + 1).is_some_and(|call| {
                        call.opcode == 0x29
                            && Variable::decode(&call.operands).is_ok_and(|(variable, _)| {
                                matches!(
                                    variable,
                                    Variable::DynamicProc(_) | Variable::DynamicVerb(_)
                                )
                            })
                    })
                {
                    cache_stores.push(push - 1);
                    cache_calls.push(index + 1);
                    cache_ops.extend([push, index]);
                }
            }
        }
    }
    let mut needed = count as i64;
    for (index, instruction) in instructions.iter().enumerate().rev() {
        // Teq exposes its boolean through the comparison flag. Keep the
        // materialization together while locating argument expressions.
        if (instruction.opcode == 0x36
            && index >= 2
            && instructions[index - 1].opcode == 0x51
            && matches!(instructions[index - 2].opcode, 0x37 | 0x71))
            || (instruction.opcode == 0x51
                && index > 0
                && matches!(instructions[index - 1].opcode, 0x37 | 0x71)
                && instructions
                    .get(index + 1)
                    .is_some_and(|next| next.opcode == 0x36))
        {
            continue;
        }
        if cache_ops.contains(&index) || cache_stores.contains(&index) {
            continue;
        }
        if instruction.opcode == 0x36
            && index > 0
            && matches!(
                instructions[index - 1].opcode,
                0x86..=0x8a | 0x149 | 0xa9 | 0x11e
            )
        {
            // Treat a verified flag-producing opcode plus GetFlag as one
            // expression when finding its argument span.
            continue;
        }
        let cached_field = |item: &crate::bytecode::Instruction| {
            matches!(item.opcode, 0x33 | 0x62..=0x65)
                && Variable::decode(&item.operands).is_ok_and(|(var, used)| {
                    used == item.operands.len()
                        && matches!(
                            var,
                            Variable::Field(_) | Variable::Initial(_) | Variable::IsSaved(_)
                        )
                })
        };
        if cached_field(instruction)
            && index > 0
            && instructions[index - 1].opcode == 0x34
            && instructions[index - 1].operands == [0xffd8]
        {
            // The cached field read depends on the owner consumed immediately
            // before it; keep the pair within the owner's expression span.
            continue;
        }
        if instruction.opcode == 0x13f
            && index > 0
            && matches!(instructions[index - 1].opcode, 0x45..=0x4e | 0x177 | 0x15a)
        {
            // PushEval reads the result of the immediately preceding Aug*.
            continue;
        }
        let (pops, pushes) = match instruction.opcode {
            0x33 | 0x50 | 0x60 | 0x62..=0x65 | 0x13f => (0, 1), // GetVar, literals, Pre/PostInc/Dec, PushEval
            0x23
            | 0x71
            | 0x37..=0x3c
            | 0x3e..=0x42
            | 0x44
            | 0x6a
            | 0x56 // Num2Text(number, precision)
            | 0x158 // Text2NumRadix(text, radix)
            | 0x7b
            | 0x7d
            | 0x7e..=0x80
            | 0x140 | 0x141
            | 0x82
            | 0x83
            | 0x90 => (2, 1),
            0x93 | 0x95 | 0x6b => (2, 1), // GetStepTowards/GetDist/Turn
            0x86 | 0x89 | 0xa9
                if instructions.get(index + 1).is_some_and(|next| next.opcode == 0x36) => (2, 1),
            0x87 | 0x88 | 0x11e
                if instructions.get(index + 1).is_some_and(|next| next.opcode == 0x36) => (3, 1),
            0x8a | 0x149
                if instructions.get(index + 1).is_some_and(|next| next.opcode == 0x36) => (1, 1),
            0x21 // Prob(value)
            | 0x0e
            | 0x13..=0x17
            | 0x81
            | 0x22
            | 0x43
            | 0x3d
            | 0x68
            | 0x69
            | 0x6d
            | 0x77 // Num2Text(number)
            | 0x9e
            | 0xc2..=0xc5
            | 0x138
            | 0x139
            | 0x145
            | 0x182..=0x184
            | 0x109
            | 0xb7
            | 0x148 // Ref(object)
            | 0x169 // Ceil(value)
            | 0x31 // LogE(value)
            | 0x16a | 0x16b // Trunc/Fract(value)
            | 0x178 // RefCount(object)
            | 0x16e // TrimText(text)
            | 0x74 | 0x75 // UpperText/LowerText(text)
            | 0x9f // IsNum(value)
            | 0xa0 // IsText(value)
            | 0x147 // IsList(value)
            | 0x9a // File2Text(file)
            | 0x10a // Text2Path(text)
            | 0xbf // HtmlDecode(text)
            | 0xa8 // CKey(text)
            | 0x14d // LengthChar(text)
            | 0xb9 // CKeyEx(text)
            | 0x94 // GetStepRand(atom)
            | 0x5f // RollStr(dice)
            | 0xcd // CallGlobalArgList consumes one argument list and returns a value
            | 0xd2 // Pick(list)
            | 0x35 => (1, 1),
            0x1a => (*instruction.operands.first()? as i64, 1),
            0xa5 => (*instruction.operands.first()? as i64, 1), // Min(args...)
            0xa6 | 0xa7 | 0x13a | 0xd4 => (*instruction.operands.first()? as i64, 1), // Max/TypesOf/Regex/Image
            0xc8 => (2 * *instruction.operands.first()? as i64, 1), // associative list
            0xbb => (3, 1),                                     // Rgb(r,g,b)
            0x5b => (1, 1), // LocateRef(value)
            0x5a => (3, 1),                                     // LocatePos(x,y,z)
            0x6e | 0x14e => (3, 1),                                     // CopyText(text,start,end)
            0x91 | 0x92 => (3, 1),                                     // GetStepTo
            0x57 | 0x118 | 0x99 | 0xe7 | 0xe8 | 0x32 => (2, 1),
            0x14b | 0x108 | 0xd0 | 0xd1 | 0x128 | 0x129 | 0xba | 0xdc => (1, 1),
            0x2e => (0, 1),                              // Text2File/OHearers
            0x6f | 0x70 | 0x14f | 0x15f | 0x160 => (4, 1), // FindText and SpliceText
            0x134 | 0x135 | 0x155 | 0x156 | 0x18b | 0x18c => (3, 1),
            0x14c => (2, 1), // Text2AsciiChar
            0x136 | 0x157 => (5, 1),                            // SplitText[_char]
            0xc0 => (2, 1),                                     // Time2Text(value, format)
            0x132 => (4, 1), // FindLastText(haystack, needle, start, end)
            0x170 => (6, 1), // BlockCoordinates(x1,y1,z1,x2,y2,z2)
            0x15d => (*instruction.operands.first()? as i64, 1), // Time2TextTZ
            0x167 => (*instruction.operands.first()? as i64, 1), // JsonEncodeFlags
            0xc1 => (4 + i64::from(*instruction.operands.get(2)? == 64), 1), // Input with optional selection list
            0xc6 => (5, 1), // InputColor config plus four arguments
            0x18 => (6, 1), // Alert
            0x161 => (5, 1), // RgbEx
            0x113 => (4, 1), // Rgba(r,g,b,a)
            0x14a => (3, 1), // Clamp(value, low, high)
            0x12a if instruction.operands.first() == Some(&0) => (0, 1), // matrix()
            0x01 => (*instruction.operands.first()? as i64 + 1, 1), // New(type, args...)
            0xe9 | 0xea => (0, 1), // database constructor singletons
            0xc9 | 0xca => (1, 1), // parent/self arglist calls
            0x2f => (*instruction.operands.first()? as i64, 1), // recursive CallSelfArgs
            0x02 => (*instruction.operands.get(1)? as i64, 1),
            0x29 if cache_calls.contains(&index) => {
                let count = *instruction.operands.last()?;
                (if count == 0xffff { 2 } else { count as i64 + 1 }, 1)
            }
            0x29 => {
                let count = *instruction.operands.last()?;
                (if count == 0xffff { 1 } else { count as i64 }, 1)
            } // Call, including one arglist value
            0x30 => (*instruction.operands.first()? as i64, 1), // CallGlob
            0xb5 | 0x116 => (*instruction.operands.first()? as i64 + 2, 1), // CallName/CallLib(two targets, args...)
            0x2b | 0x17a => (*instruction.operands.first()? as i64 + 1, 1), // CallPath/CallExt(one target, args...)
            0xd3 => (1, 1), // NewImageArgList
            0xcf | 0x61 => (2, 1), // NewArgList / NewImage
            0xcb | 0x17b => (2, 1), // one target and one arglist
            0xcc | 0x117 => (3, 1), // two targets and one arglist
            0x34 if instruction.operands == [0xffd8]
                && instructions.get(index + 1).is_some_and(cached_field) => (1, 1),
            0x45..=0x4e | 0x177 | 0x15a => (1, i64::from(instructions.get(index+1).is_some_and(|next| next.opcode == 0x13f))),
            0x7c => (3, 0), // ListSet consumes value/list/key.
            0x24 | 0xda => (1, 0), // sleep/rand_seed
            0x5c | 0x8f => (2, 0), // flick/walk_rand
            0x8b | 0x8e | 0x127 | 0x10c | 0x10e | 0x10f => (3, 0),
            0x8c | 0x8d | 0x123 | 0x126 => (4, 0),
            0x124 | 0x125 => (5, 0),
            0x13c => (1, 2), // PushTop duplicates the existing stack value.
            0x142 | 0x143 => (0, 0), // Saved cache frames do not change the value stack.
            0x34 => (1, 0), // SetVar, including cached dynamic initial owner
            _ => return None,
        };
        if instruction.opcode == 0x13c {
            needed = (needed - 2).max(0) + 1;
            continue;
        }
        needed = needed - pushes + pops;
        if needed == 0 {
            return Some(instruction.offset);
        }
        if needed < 0 {
            return None;
        }
    }
    None
}

fn is_simple_continue_tail(code: &[u8], source: usize, target: u32) -> bool {
    let mut at = target as usize;
    if matches!(code.get(at), Some(0x56 | 0x57 | 0x62 | 0x63))
        && matches!(code.get(at + 1), Some(8 | 9))
    {
        at += 3; // increment/decrement of a direct argument or local
        if code.get(at) == Some(&0x51) {
            at += 1;
        }
    }
    if code.get(at) != Some(&0x0e) {
        return false;
    }
    code.get(at + 1..at + 5)
        .and_then(|bytes| bytes.try_into().ok())
        .is_some_and(|bytes: [u8; 4]| u32::from_le_bytes(bytes) < source as u32)
}

/// Restore the native exception-aware exits after all branch boundaries are
/// known. Ordinary jumps within a protected body retain their usual encoding.
fn restore_try_branch_exits(
    words: &mut [u32],
    code: &[u8],
    fixups: &[Fixup],
    regions: &[(usize, usize)],
) {
    if regions.is_empty() {
        return;
    }
    let jumps: Vec<_> = fixups
        .iter()
        .filter(|fixup| {
            code.get(fixup.source) == Some(&0x0e)
                && fixup.target as usize <= code.len()
                && matches!(words.get(fixup.at.wrapping_sub(1)), Some(0x0f | 0xf8))
        })
        .collect();
    // An explicit continue can have the same backward destination as the
    // natural loop tail. The last backward edge to that label is the tail.
    let mut tails = HashMap::<u32, usize>::new();
    for jump in &jumps {
        if (jump.target as usize) < jump.source {
            tails
                .entry(jump.target)
                .and_modify(|source| *source = (*source).max(jump.source))
                .or_insert(jump.source);
        }
    }
    let loops: Vec<_> = fixups
        .iter()
        .filter(|branch| {
            matches!(code.get(branch.source), Some(0x0c | 0x3b | 0x43 | 0x72))
                && matches!(
                    words.get(branch.at.wrapping_sub(1)),
                    Some(0x11 | 0xfd | 0xff)
                )
                && branch.target as usize > branch.source
        })
        .flat_map(|branch| {
            tails.iter().filter_map(move |(head, tail)| {
                ((*head as usize <= branch.source)
                    && (*tail > branch.source)
                    && (*tail < branch.target as usize))
                    .then_some((branch.source, *tail, branch.target))
            })
        })
        .collect();
    for jump in jumps {
        if !regions
            .iter()
            .any(|(start, end)| *start <= jump.source && jump.source < *end)
        {
            continue;
        }
        let loop_exit = loops.iter().any(|(condition, tail, exit)| {
            *exit == jump.target && *condition < jump.source && jump.source < *tail
        });
        let continues = is_simple_continue_tail(code, jump.source, jump.target)
            || tails
                .get(&jump.target)
                .is_some_and(|tail| jump.source < *tail);
        let leaves_region = regions.iter().any(|(start, end)| {
            *start <= jump.source
                && jump.source < *end
                // EndTry lowers to the native Catch cleanup instruction. A
                // join at that exact boundary must enter the cleanup normally;
                // it is not a goto that exits the protected body.
                && !(*start <= jump.target as usize && (jump.target as usize) <= *end)
        });
        if loop_exit {
            words[jump.at - 1] = 0x12e; // Catch: native break with protected cleanup.
        } else if continues || leaves_region {
            words[jump.at - 1] = 0x12f; // TryJmp: continue/goto, including nested exits.
        }
    }
}

fn literal_switch_case_at(code: &[u8], at: usize) -> bool {
    match code.get(at) {
        Some(0x8d | 0x93) => true,
        Some(0x02 | 0x03 | 0x21 | 0x26 | 0x38) => code.get(at + 5) == Some(&0x32),
        Some(0x9f) => code.get(at + 9) == Some(&0x32),
        Some(0x11) => code.get(at + 1) == Some(&0x32),
        Some(0x88) => {
            code.get(at + 1..at + 5) == Some(&[2, 0, 0, 0]) && code.get(at + 13) == Some(&0x05)
        }
        _ => false,
    }
}

/// Literal switch labels can mix compacted and ordinary pushes. Parse their
/// common case chain as one native table instead of splitting it by value type.
fn lower_literal_switch_chain(
    reader: &mut Reader<'_>,
    ids: &impl SymbolResolver,
    start: usize,
    first_op: u8,
    out: &mut Vec<u32>,
    offsets: &mut HashMap<u32, u32>,
    fixups: &mut Vec<Fixup>,
) -> Result<bool, LowerError> {
    if !literal_switch_case_at(reader.code, start) {
        return Ok(false);
    }
    let switch_at = out.len() as u32;
    let mut cases = Vec::new();
    let mut ranges = Vec::new();
    let mut op = first_op;
    loop {
        if op == 0x88 {
            if reader.word()? != 2 {
                unreachable!("range prefix checked");
            }
            let low = reader.word()?;
            let high = reader.word()?;
            reader.byte()?; // SwitchCaseRange, checked by prefix recognition.
            ranges.push((low, high, reader.word()?));
        } else {
            let value = match op {
                0x38 | 0x8d => {
                    let bits = reader.word()?;
                    Value {
                        tag_word: 42,
                        data_word: bits >> 16,
                        extra_word: Some(bits & 0xffff),
                    }
                }
                0x03 | 0x93 => {
                    let id = mapped(ids.string(reader.word()?), start, "string")?;
                    Value {
                        tag_word: 6 | ((id >> 16) << 8),
                        data_word: id & 0xffff,
                        extra_word: None,
                    }
                }
                0x02 => {
                    let old = reader.word()?;
                    let tag = mapped(ids.type_tag(old).map(u32::from), start, "type tag")?;
                    let id = mapped(ids.type_id(old), start, "type")?;
                    Value {
                        tag_word: tag | ((id >> 16) << 8),
                        data_word: id & 0xffff,
                        extra_word: None,
                    }
                }
                0x21 | 0x26 => {
                    let old = reader.word()?;
                    let id = mapped(
                        if op == 0x21 {
                            ids.resource(old)
                        } else {
                            ids.proc_id(old)
                        },
                        start,
                        if op == 0x21 { "resource" } else { "proc" },
                    )?;
                    Value {
                        tag_word: (if op == 0x21 { 12 } else { 38 }) | ((id >> 16) << 8),
                        data_word: id & 0xffff,
                        extra_word: None,
                    }
                }
                0x9f => {
                    let old_type = reader.word()?;
                    let old_string = reader.word()?;
                    let id = mapped(
                        ids.modified_instance(old_type, old_string),
                        start,
                        "modified instance",
                    )?;
                    Value {
                        tag_word: 41 | ((id >> 16) << 8),
                        data_word: id & 0xffff,
                        extra_word: None,
                    }
                }
                0x11 => Value {
                    tag_word: 0,
                    data_word: 0,
                    extra_word: None,
                },
                _ => unreachable!("literal case prefix checked"),
            };
            if !matches!(op, 0x8d | 0x93) {
                offsets.insert(reader.at as u32, switch_at);
                reader.byte()?; // SwitchCase, checked by prefix recognition.
            }
            cases.push((value, reader.word()?));
        }
        if !literal_switch_case_at(reader.code, reader.at) {
            break;
        }
        offsets.insert(reader.at as u32, switch_at);
        op = reader.byte()?;
    }
    if reader.code.get(reader.at) != Some(&0x51) {
        return Err(LowerError {
            kind: LowerErrorKind::MalformedControlFlow,
            offset: start,
            reason: "literal switch case chain lacks Pop".into(),
        });
    }
    offsets.insert(reader.at as u32, switch_at);
    reader.byte()?;
    let default = if reader.code.get(reader.at) == Some(&0x0e)
        && !authored_control_jump(ids, reader.code, reader.at)
    {
        offsets.insert(reader.at as u32, switch_at);
        reader.byte()?;
        reader.word()?
    } else {
        reader.at as u32
    };
    if ranges.is_empty() {
        out.extend([0x78, cases.len() as u32]);
    } else {
        out.extend([0x7a, ranges.len() as u32]);
        for (low, high, target) in ranges {
            out.extend([42, low >> 16, low & 0xffff, 42, high >> 16, high & 0xffff]);
            fixups.push(Fixup {
                at: out.len(),
                target,
                source: start,
            });
            out.push(0);
        }
        out.push(cases.len() as u32);
    }
    for (value, target) in cases {
        out.extend(value.encode());
        fixups.push(Fixup {
            at: out.len(),
            target,
            source: start,
        });
        out.push(0);
    }
    fixups.push(Fixup {
        at: out.len(),
        target: default,
        source: start,
    });
    out.push(0);
    Ok(true)
}

fn reference(reader: &mut Reader<'_>, ids: &impl SymbolResolver) -> Result<Variable, LowerError> {
    let at = reader.at;
    let kind = reader.byte()?;
    Ok(match kind {
        0 => Variable::Null,
        1 => Variable::Src,
        2 => Variable::Dot,
        3 => Variable::Usr,
        4 => Variable::Args,
        5 => Variable::World,
        15 => Variable::Callee,
        16 => Variable::Caller,
        17 => Variable::Cache, // Exporter-proven native frozen receiver, no index.
        8 => {
            let arg = reader.byte()?;
            reader.referenced_args.push(arg);
            let native = if reader.native_arg_slots.is_empty() {
                u32::from(arg)
            } else {
                reader
                    .native_arg_slots
                    .get(usize::from(arg))
                    .copied()
                    .flatten()
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: at,
                        reason: format!("OpenDream argument slot {arg} has no native formal"),
                    })?
            };
            Variable::Arg(native)
        }
        9 => {
            let local = usize::from(reader.byte()?);
            Variable::Local(if reader.remap_locals {
                *reader.local_slots.get(local).ok_or_else(|| LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: at,
                    reason: format!("OpenDream local slot {local} is inactive"),
                })?
            } else {
                local as u32
            })
        }
        10 => Variable::Global(mapped(ids.global(reader.word()?), at, "global")?),
        11 => Variable::StaticProc(mapped(ids.proc_id(reader.word()?), at, "proc")?),
        13 => {
            let id = mapped(ids.string(reader.word()?), at, "string")?;
            Variable::SetCache(Box::new(Variable::Src), Box::new(Variable::Field(id)))
        }
        12 => {
            let id = mapped(ids.string(reader.word()?), at, "string")?;
            Variable::Field(id)
        }
        _ => {
            return Err(LowerError {
                kind: LowerErrorKind::UnsupportedConstruct,
                offset: at,
                reason: format!("OpenDream reference kind {kind} has no verified BYOND lowering"),
            })
        }
    })
}

fn finish_native_statement_call(
    reader: &mut Reader<'_>,
    out: &mut Vec<u32>,
    offsets: &mut HashMap<u32, u32>,
    statement: bool,
) {
    if statement {
        // CallStatement skips exactly one wire word. Emit its marker now so
        // a source event on OD's Pop cannot insert a debug opcode between them.
        debug_assert_eq!(reader.code.get(reader.at), Some(&0x51));
        offsets.insert(reader.at as u32, out.len() as u32);
        out.push(0x51);
        reader.at += 1;
    }
}

fn finish_native_void_result(
    reader: &mut Reader<'_>,
    out: &mut Vec<u32>,
    offsets: &mut HashMap<u32, u32>,
    fixups: &[Fixup],
    flow: &mut WorldFlow,
) {
    if flow.pop_is_unshared(reader, fixups) {
        offsets.insert(reader.at as u32, out.len() as u32);
        reader.at += 1;
    } else {
        // OpenDream exposes null for native statements. A common Pop must
        // remain reachable from every expression arm that joins here.
        out.extend([0x60, 0, 0]);
    }
}

/// Lower one OpenDream procedure. Branch destinations are translated from byte
/// offsets to DMB word offsets. A failed operation never yields partial code.
pub fn lower_proc_bytecode(code: &[u8], ids: &impl SymbolResolver) -> Result<Vec<u32>, LowerError> {
    lower_with_context(code, ids, false, 0, &[], &[], &[], None, false, None)
}

/// Return argument slots referenced by a companion procedure. The same
/// instruction reader used for lowering identifies references, so operand
/// bytes inside constants cannot be mistaken for argument loads.
pub fn referenced_argument_indices(code: &[u8]) -> Result<Vec<u8>, LowerError> {
    struct ScanResolver;
    impl SymbolResolver for ScanResolver {
        fn global_vars_variable(&self) -> Option<u32> {
            Some(0)
        }
    }
    let mut referenced = Vec::new();
    lower_with_context(
        code,
        &ScanResolver,
        false,
        0,
        &[],
        &[],
        &[],
        None,
        false,
        Some(&mut referenced),
    )?;
    referenced.sort_unstable();
    referenced.dedup();
    Ok(referenced)
}

/// Lower a procedure using its OpenDream local-variable count so BYOND
/// iterator scratch slots follow the procedure's declared locals.
pub fn lower_proc_bytecode_with_locals(
    code: &[u8],
    ids: &impl SymbolResolver,
    local_count: usize,
) -> Result<Vec<u32>, LowerError> {
    lower_with_context(
        code,
        ids,
        false,
        local_count,
        &[],
        &[],
        &[],
        None,
        false,
        None,
    )
}

/// Lower an authored procedure using its local lifetime events. OpenDream
/// reuses slot IDs after scope exit; BYOND retains one distinct slot per name.
pub fn lower_proc_bytecode_with_local_events(
    code: &[u8],
    ids: &impl SymbolResolver,
    local_count: usize,
    events: &[crate::opendream::OpenDreamLocal],
) -> Result<Vec<u32>, LowerError> {
    lower_with_context(
        code,
        ids,
        false,
        local_count,
        events,
        &[],
        &[],
        None,
        false,
        None,
    )
}

/// Lower with an optional native lexical ordering of OpenDream Add events.
/// Each index is the zero-based ordinal among local Add events in `events`.
pub fn lower_proc_bytecode_with_local_events_and_order(
    code: &[u8],
    ids: &impl SymbolResolver,
    local_count: usize,
    events: &[crate::opendream::OpenDreamLocal],
    lexical_local_add_indices: &[usize],
) -> Result<Vec<u32>, LowerError> {
    lower_with_context(
        code,
        ids,
        false,
        local_count,
        events,
        lexical_local_add_indices,
        &[],
        None,
        false,
        None,
    )
}

/// Lower with source line records for a DreamMaker DEBUG-mode world.
pub fn lower_proc_bytecode_with_debug_info(
    code: &[u8],
    ids: &impl SymbolResolver,
    local_count: usize,
    events: &[crate::opendream::OpenDreamLocal],
    source_info: &[crate::opendream::OpenDreamSourceInfo],
) -> Result<Vec<u32>, LowerError> {
    lower_with_context(
        code,
        ids,
        false,
        local_count,
        events,
        &[],
        &[],
        Some(source_info),
        false,
        None,
    )
}

/// DEBUG-mode authored procedure with lexical local-slot ordering.
pub fn lower_proc_bytecode_with_debug_info_and_order(
    code: &[u8],
    ids: &impl SymbolResolver,
    local_count: usize,
    events: &[crate::opendream::OpenDreamLocal],
    lexical_local_add_indices: &[usize],
    source_info: &[crate::opendream::OpenDreamSourceInfo],
) -> Result<Vec<u32>, LowerError> {
    lower_with_context(
        code,
        ids,
        false,
        local_count,
        events,
        lexical_local_add_indices,
        &[],
        Some(source_info),
        false,
        None,
    )
}

/// Lower an authored procedure with lexical locals and native formal omission.
/// `native_omit_arguments` follows the OpenDream argument order; references to
/// omitted formals are rejected because DreamMaker allocates no slot for them.
pub fn lower_proc_bytecode_with_native_layout(
    code: &[u8],
    ids: &impl SymbolResolver,
    local_count: usize,
    events: &[crate::opendream::OpenDreamLocal],
    lexical_local_add_indices: &[usize],
    native_omit_arguments: &[bool],
    source_info: Option<&[crate::opendream::OpenDreamSourceInfo]>,
) -> Result<Vec<u32>, LowerError> {
    lower_with_context(
        code,
        ids,
        false,
        local_count,
        events,
        lexical_local_add_indices,
        native_omit_arguments,
        source_info,
        false,
        None,
    )
}

/// Lower an OpenDream synthetic `<init>` procedure. Its leading inherited
/// initializer call is represented by the BYOND class initializer chain.
pub fn lower_init_bytecode(code: &[u8], ids: &impl SymbolResolver) -> Result<Vec<u32>, LowerError> {
    lower_with_context(code, ids, true, 0, &[], &[], &[], None, false, None)
}

/// DEBUG-mode class initializer: its first native source marker puts the line
/// before the file, unlike ordinary procedures and the global initializer.
pub fn lower_class_init_bytecode_with_debug_info(
    code: &[u8],
    ids: &impl SymbolResolver,
    source_info: &[crate::opendream::OpenDreamSourceInfo],
) -> Result<Vec<u32>, LowerError> {
    lower_with_context(
        code,
        ids,
        true,
        0,
        &[],
        &[],
        &[],
        Some(source_info),
        true,
        None,
    )
}

/// DEBUG-mode global initializer; it uses ordinary file-then-line order.
pub fn lower_global_init_bytecode_with_debug_info(
    code: &[u8],
    ids: &impl SymbolResolver,
    source_info: &[crate::opendream::OpenDreamSourceInfo],
) -> Result<Vec<u32>, LowerError> {
    lower_with_context(
        code,
        ids,
        true,
        0,
        &[],
        &[],
        &[],
        Some(source_info),
        false,
        None,
    )
}

#[allow(clippy::too_many_arguments)] // internal lowering options are passed explicitly by the public entry points
fn lower_with_context(
    code: &[u8],
    ids: &impl SymbolResolver,
    is_initializer: bool,
    local_count: usize,
    local_events: &[crate::opendream::OpenDreamLocal],
    lexical_local_add_indices: &[usize],
    native_omit_arguments: &[bool],
    source_info: Option<&[crate::opendream::OpenDreamSourceInfo]>,
    reverse_initial_debug_marker: bool,
    referenced_args: Option<&mut Vec<u8>>,
) -> Result<Vec<u32>, LowerError> {
    let mut flow = WorldFlow::default();
    let mut args = Vec::new();
    let mut output = lower_with_context_pass(
        code,
        ids,
        is_initializer,
        local_count,
        local_events,
        lexical_local_add_indices,
        native_omit_arguments,
        source_info,
        reverse_initial_debug_marker,
        Some(&mut args),
        &mut flow,
    )?;
    if flow.reused && !flow.targets.is_empty()
        || flow
            .candidate_pop_markers
            .iter()
            .any(|target| flow.targets.contains(target))
    {
        // The first pass uses the actual lowering reader/fixups to discover
        // joins, including backward loop headers, without a second OD decoder.
        flow.joins = std::mem::take(&mut flow.targets);
        args.clear();
        output = lower_with_context_pass(
            code,
            ids,
            is_initializer,
            local_count,
            local_events,
            lexical_local_add_indices,
            native_omit_arguments,
            source_info,
            reverse_initial_debug_marker,
            Some(&mut args),
            &mut flow,
        )?;
    }
    if let Some(referenced_args) = referenced_args {
        referenced_args.extend(args);
    }
    Ok(output)
}

#[derive(Default)]
struct WorldFlow {
    joins: std::collections::HashSet<u32>,
    targets: std::collections::HashSet<u32>,
    reused: bool,
    candidate_pop_markers: std::collections::HashSet<u32>,
}

impl WorldFlow {
    fn pop_is_unshared(&mut self, reader: &Reader<'_>, fixups: &[Fixup]) -> bool {
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

    fn separate_reordered_arguments(
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
struct LowerState {
    pending_world_ref: Option<PendingWorld>,
    cached_world_owner: bool,
    last_reference_push: Option<(usize, Variable)>,
    last_push_nrefs: Option<(usize, u32)>,
    last_was_format: bool,
    pending_output_run: bool,
}

/// One guarded access may create several native branches and cleanup frames.
/// Keep its state together so future safe-access lowering can move out of the
/// central opcode dispatch without carrying a dozen independent parameters.
#[derive(Default)]
struct SafeAccessState {
    pending_safe_field: bool,
    pending_safe_index: Option<u32>,
    last_safe_index: Option<(usize, u32, usize)>,
    pending_safe_aug_sub: bool,
    pending_safe_lvalue_at: Option<(usize, bool)>,
    pending_safe_lvalue_body: Option<usize>,
    pending_safe_lvalue_stack: Vec<(usize, bool, Option<usize>)>,
    pending_safe_index_lvalue: Option<(usize, usize)>,
    last_safe_field: Option<(usize, u32, usize, usize)>,
    nested_safe_pop: Option<(u32, u32)>,
    safe_chain_fixups: Vec<usize>,
    safe_skip_pop: HashMap<usize, u32>,
}

enum PendingReceiver {
    SafeCached,
    NativeCached,
    NativeCachedReference(Variable, bool),
    NativeReference(Variable),
}

struct PickLowering<'a> {
    code: &'a [u8],
    start: usize,
    out: &'a mut Vec<u32>,
    offsets: &'a mut HashMap<u32, u32>,
    fixups: &'a mut Vec<Fixup>,
    world_flow: &'a mut WorldFlow,
    state: &'a mut LowerState,
    probability_regions: &'a mut Vec<(u32, u32)>,
}

impl PickLowering<'_> {
    fn lower(&mut self, weighted: bool, count: usize) -> Result<(), LowerError> {
        let code = self.code;
        let start = self.start;
        let mut out = &mut *self.out;
        let mut offsets = &mut *self.offsets;
        let mut fixups = &mut *self.fixups;
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
                let at = guarded_assignment_spans(&out[..end], code, &offsets, &fixups, start, 0)
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
            if !closed_spans(&spans, &offsets, &fixups) {
                return Err(LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "PickWeighted operands have nonlocal branches".into(),
                });
            }
            world_flow.separate_reordered_arguments(&spans, &offsets, code.len());
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
            let original_offsets = moved_offset_snapshot(&offsets, &fixups, &moved);
            replace_words(
                &mut out,
                &mut offsets,
                &mut fixups,
                base,
                old_end - base,
                &replacement,
            );
            offsets.extend(remapped_offsets);
            remap_closed_spans(&original_offsets, &mut offsets, &mut fixups, &moved);
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
                    let at =
                        guarded_assignment_spans(&out[..end], code, &offsets, &fixups, start, 0)
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
                if !closed_spans(&spans, &offsets, &fixups) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "PickUnweighted operands have nonlocal branches".into(),
                    });
                }
                world_flow.separate_reordered_arguments(&spans, &offsets, code.len());
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
                    &mut out,
                    &mut offsets,
                    &mut fixups,
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

/// Constants and packed switch cases share the same source reader and
/// absolute branch relocation contract. `true` means the source instruction
/// consumed a whole case chain and the outer dispatch loop should continue.
#[allow(clippy::too_many_arguments)]
fn lower_constant_and_switch(
    op: u8,
    reader: &mut Reader<'_>,
    ids: &impl SymbolResolver,
    start: usize,
    mut out: &mut Vec<u32>,
    mut offsets: &mut HashMap<u32, u32>,
    mut fixups: &mut Vec<Fixup>,
    spawn_targets: &[u32],
) -> Result<bool, LowerError> {
    match op {
        0x11 => {
            if reader.code.get(reader.at) == Some(&0x32) {
                // A mixed constant switch can begin with the null case,
                // then continue with OpenDream's packed string/float
                // cases. Native BYOND stores all cases in one Switch.
                let switch_at = out.len();
                reader.byte()?; // SwitchCase for null
                let first_target = reader.word()?;
                let mut cases = vec![(
                    Value {
                        tag_word: 0,
                        data_word: 0,
                        extra_word: None,
                    },
                    first_target,
                )];
                while matches!(reader.code.get(reader.at), Some(0x8d | 0x93)) {
                    offsets.insert(reader.at as u32, switch_at as u32);
                    let case_op = reader.byte()?;
                    let value = if case_op == 0x93 {
                        let id = mapped(ids.string(reader.word()?), start, "switch string")?;
                        Value {
                            tag_word: 6 | ((id >> 16) << 8),
                            data_word: id & 0xffff,
                            extra_word: None,
                        }
                    } else {
                        let bits = reader.word()?;
                        Value {
                            tag_word: 0x2a,
                            data_word: bits >> 16,
                            extra_word: Some(bits & 0xffff),
                        }
                    };
                    cases.push((value, reader.word()?));
                }
                if reader.code.get(reader.at) != Some(&0x51) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "mixed switch lacks Pop before default".into(),
                    });
                }
                offsets.insert(reader.at as u32, switch_at as u32);
                reader.byte()?;
                let default = if reader.code.get(reader.at) == Some(&0x0e)
                    && !authored_control_jump(ids, reader.code, reader.at)
                {
                    offsets.insert(reader.at as u32, switch_at as u32);
                    reader.byte()?;
                    reader.word()?
                } else {
                    reader.at as u32
                };
                out.extend([0x78, cases.len() as u32]);
                for (value, target) in cases {
                    out.extend(value.encode());
                    let at = out.len();
                    out.push(0);
                    fixups.push(Fixup {
                        at,
                        target,
                        source: start,
                    });
                }
                let at = out.len();
                out.push(0);
                fixups.push(Fixup {
                    at,
                    target: default,
                    source: start,
                });
                return Ok(true);
            }
            if ids.native_null(start) {
                // The native Null reader clears retained Eval ownership at
                // this authored load, including left and conditional operands.
                // Packed switch keys above are values embedded in a table,
                // rather than executed null loads.
                out.extend([0x33, 0xffe6]);
                return Ok(true);
            }
            if reader.code.get(reader.at) == Some(&0x10)
                && spawn_targets.contains(&((reader.at + 1) as u32))
            {
                out.push(0); // DreamMaker ends spawned body with End
                offsets.insert(reader.at as u32, out.len() as u32);
                reader.byte()?; // OpenDream Return
                return Ok(true);
            }
            // `new /path` in OpenDream prefixes the type with a null
            // location. DreamMaker's New uses the type directly.
            if reader.code.get(reader.at) == Some(&0x02)
                && reader.code.get(reader.at + 5) == Some(&0x2e)
            {
                let mode = *reader.code.get(reader.at + 6).ok_or_else(|| LowerError {
                    kind: LowerErrorKind::TruncatedOperand,
                    offset: start,
                    reason: "truncated CreateObject mode".into(),
                })?;
                let count = u32::from_le_bytes(
                    reader
                        .code
                        .get(reader.at + 7..reader.at + 11)
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::TruncatedOperand,
                            offset: start,
                            reason: "truncated CreateObject count".into(),
                        })?
                        .try_into()
                        .unwrap(),
                );
                if !(matches!((mode, count), (0, 0))
                    || mode == 1 && (1..=255).contains(&count)
                    || mode == 2 && (2..=510).contains(&count) && count % 2 == 0
                    || (mode, count) == (3, 1))
                {
                    return Err(LowerError {
                        kind: LowerErrorKind::UnsupportedConstruct,
                        offset: start,
                        reason: "CreateObject argument mode/count is unsupported".into(),
                    });
                }
                let old = u32::from_le_bytes(
                    reader.code[reader.at + 1..reader.at + 5]
                        .try_into()
                        .unwrap(),
                );
                let tag = ids.type_tag(old).ok_or_else(|| LowerError {
                    kind: LowerErrorKind::UnresolvedSymbol,
                    offset: start,
                    reason: "unresolved type tag".into(),
                })?;
                let type_id = mapped(ids.type_id(old), start, "type")?;
                if count > 0 {
                    let args_at = constructor_argument_start(&out, count as usize)
                        .or_else(|| {
                            // The final constructor argument may be a
                            // short-circuit `target || fallback` or
                            // `target && fallback`. Its
                            // first value and conditional jump precede the branch
                            // fallback, so split before that branch.
                            let branch = fixups.iter().rev().find(|fixup| {
                                fixup.target == start as u32
                                    && matches!(reader.code.get(fixup.source), Some(0x15 | 0x2f))
                            })?;
                            let branch_at = *offsets.get(&(branch.source as u32))? as usize;
                            constructor_argument_start(&out[..branch_at], count as usize)
                        })
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::UnsupportedConstruct,
                            offset: start,
                            reason: "CreateObject arguments have unsupported stack effects".into(),
                        })?;
                    let mut type_push = Vec::new();
                    push_value(&mut type_push, tag, type_id);
                    insert_expression_prefix(
                        &mut out,
                        &mut offsets,
                        &mut fixups,
                        args_at,
                        &type_push,
                    );
                } else {
                    push_value(&mut out, tag, type_id);
                }
                offsets.insert(reader.at as u32, out.len() as u32);
                reader.at += 5; // PushType + type ID
                offsets.insert(reader.at as u32, out.len() as u32);
                reader.at += 6; // CreateObject + mode + count
                if mode == 2 {
                    out.extend([0xc8, count / 2, 0xcf]);
                } else if mode == 3 {
                    out.push(0xcf);
                } else {
                    out.extend([0x01, count]);
                }
            } else {
                out.extend([0x60, 0, 0]);
            }
        }
        0x38 => {
            // PushFloat
            let bits = reader.word()?;
            if reader.code.get(reader.at) == Some(&0x32) {
                // Unoptimized OpenDream emits each constant case as a
                // separate push and SwitchCase. DreamMaker stores the
                // entire table in one Switch instruction.
                let switch_at = out.len();
                let mut cases = Vec::new();
                let mut case_bits = bits;
                loop {
                    if reader.byte()? != 0x32 {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "switch case lacks SwitchCase".into(),
                        });
                    }
                    cases.push((case_bits, reader.word()?));
                    if reader.code.get(reader.at) == Some(&0x38)
                        && reader.code.get(reader.at + 5) == Some(&0x32)
                    {
                        offsets.insert(reader.at as u32, switch_at as u32);
                        reader.at += 1;
                        case_bits = reader.word()?;
                    } else {
                        break;
                    }
                }
                if reader.code.get(reader.at) != Some(&0x51) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "switch case chain lacks Pop".into(),
                    });
                }
                offsets.insert(reader.at as u32, switch_at as u32);
                reader.at += 1;
                let default = if reader.code.get(reader.at) == Some(&0x0e)
                    && !authored_control_jump(ids, reader.code, reader.at)
                {
                    offsets.insert(reader.at as u32, switch_at as u32);
                    reader.at += 1;
                    reader.word()?
                } else {
                    reader.at as u32
                };
                out.extend([0x78, cases.len() as u32]);
                for (case_bits, target) in cases {
                    out.extend([0x2a, case_bits >> 16, case_bits & 0xffff]);
                    let at = out.len();
                    out.push(0);
                    fixups.push(Fixup {
                        at,
                        target,
                        source: start,
                    });
                }
                let at = out.len();
                out.push(0);
                fixups.push(Fixup {
                    at,
                    target: default,
                    source: start,
                });
                return Ok(true);
            }
            if let Some(old_type) = simple_new_tail(&reader, 1) {
                let tag = ids.type_tag(old_type).ok_or_else(|| LowerError {
                    kind: LowerErrorKind::UnresolvedSymbol,
                    offset: start,
                    reason: "unresolved type tag".into(),
                })?;
                push_value(&mut out, tag, mapped(ids.type_id(old_type), start, "type")?);
                let null_at = reader.at;
                offsets.insert(null_at as u32, (out.len() - 3) as u32);
                offsets.insert((null_at + 1) as u32, (out.len() - 3) as u32);
                out.extend([0x60, 0x2a, bits >> 16, bits & 0xffff]);
                offsets.insert((null_at + 6) as u32, out.len() as u32);
                out.extend([0x01, 1]);
                reader.at += 12;
            } else {
                out.extend([0x60, 0x2a, bits >> 16, bits & 0xffff]);
            }
        }
        _ => unreachable!("constant family opcode"),
    }
    Ok(false)
}

#[allow(clippy::too_many_arguments)]
fn lower_with_context_pass(
    code: &[u8],
    ids: &impl SymbolResolver,
    is_initializer: bool,
    local_count: usize,
    local_events: &[crate::opendream::OpenDreamLocal],
    lexical_local_add_indices: &[usize],
    native_omit_arguments: &[bool],
    source_info: Option<&[crate::opendream::OpenDreamSourceInfo]>,
    reverse_initial_debug_marker: bool,
    referenced_args: Option<&mut Vec<u8>>,
    world_flow: &mut WorldFlow,
) -> Result<Vec<u32>, LowerError> {
    let mut next_arg_slot = 0u32;
    let native_arg_slots = native_omit_arguments
        .iter()
        .map(|omit| {
            if *omit {
                None
            } else {
                let slot = next_arg_slot;
                next_arg_slot += 1;
                Some(slot)
            }
        })
        .collect();
    let mut reader = Reader {
        code,
        at: 0,
        local_slots: Vec::new(),
        remap_locals: !local_events.is_empty(),
        referenced_args: Vec::new(),
        native_arg_slots,
    };
    let mut local_event_index = 0;
    let mut add_ordinal = 0usize;
    let add_count = local_events
        .iter()
        .filter(|event| event.add.is_some())
        .count();
    let mut native_slot_for_add: Vec<u32> = (0..add_count as u32).collect();
    if !lexical_local_add_indices.is_empty() {
        let mut mapped = vec![None; add_count];
        for (native_slot, &ordinal) in lexical_local_add_indices.iter().enumerate() {
            let slot = mapped.get_mut(ordinal).ok_or_else(|| LowerError {
                kind: LowerErrorKind::MalformedControlFlow,
                offset: 0,
                reason: format!("lexical local Add ordinal {ordinal} is out of bounds"),
            })?;
            if slot.is_some() {
                return Err(LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: 0,
                    reason: format!("lexical local Add ordinal {ordinal} appears twice"),
                });
            }
            *slot = Some(native_slot as u32);
        }
        let mut next = lexical_local_add_indices.len() as u32;
        for (ordinal, slot) in mapped.into_iter().enumerate() {
            native_slot_for_add[ordinal] = slot.unwrap_or_else(|| {
                let reserved = next;
                next += 1;
                reserved
            });
        }
    }
    let mut source_event_index = 0;
    let mut out = Vec::new();
    let mut offsets = HashMap::new();
    let mut probability_regions = Vec::new();
    let mut fixups: Vec<Fixup> = Vec::new();
    let mut state = LowerState::default();
    let mut spawn_targets = Vec::new();
    let mut pending_try: Vec<TryFrame> = Vec::new();
    let mut try_regions = Vec::new();
    let mut catch_local_base: Option<u32> = None;
    let mut catches_emitted = 0u32;
    let mut safe = SafeAccessState::default();
    let mut pending_receivers = Vec::new();
    let mut pending_indexed_logical = Vec::<(u32, usize, Variable)>::new();
    let mut safe_logical_continuations = std::collections::HashSet::new();
    let mut computed_safe_logical = std::collections::HashSet::new();
    let mut guarded_assign_into = HashMap::<usize, (usize, usize)>::new();
    let mut guarded_assign_into_nested = std::collections::HashSet::<usize>::new();
    let mut filtered_enumerators: HashMap<u32, (u8, u32)> = HashMap::new();
    let mut pending_orange_iterator = false;
    let mut pending_view_range_iterator = None;
    let mut range_enumerators = std::collections::HashMap::new();
    let mut safe_index_enumerator = None;
    let mut delete_clear_cache_end: Option<u32> = None;
    let _ = local_count; // Iterator IDs are not native local slots.
    let mut iterator_frames = Vec::<IteratorFrame>::new();
    let mut iterator_states = std::collections::BTreeMap::new();
    let mut pending_iterator_mask = None;
    let mut store_reload_boundaries = std::collections::HashSet::new();
    while reader.at < code.len() {
        let start = reader.at;
        if world_flow.joins.contains(&(start as u32)) {
            state.cached_world_owner = false;
            if let Some(pending) = &mut state.pending_world_ref {
                pending.rhs_changed_cache = true;
            }
        }
        iterator_states.insert(start, iterator_frames.clone());
        while local_event_index < local_events.len()
            && local_events[local_event_index].offset <= start
        {
            let event = &local_events[local_event_index];
            if let Some(remove) = event.remove {
                if remove > reader.local_slots.len() {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: event.offset,
                        reason: "OpenDream local lifetime removes inactive slots".into(),
                    });
                }
                reader
                    .local_slots
                    .truncate(reader.local_slots.len() - remove);
            }
            if event.add.is_some() {
                reader.local_slots.push(native_slot_for_add[add_ordinal]);
                add_ordinal += 1;
            }
            local_event_index += 1;
        }
        if delete_clear_cache_end == Some(start as u32) {
            out.push(0x143);
            delete_clear_cache_end = None;
        }
        offsets.insert(start as u32, out.len() as u32);
        if let Some((_, count)) = safe
            .nested_safe_pop
            .filter(|(target, _)| *target == start as u32)
        {
            let join_depth = cache_frame_depth(&out);
            for (index, fixup) in fixups.iter().enumerate().filter(|(_, fixup)| {
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
                let edge_depth = cache_frame_depth(&out[..fixup.at.saturating_sub(1)]);
                let skip = join_depth.saturating_sub(edge_depth).min(count as usize) as u32;
                safe.safe_skip_pop
                    .entry(index)
                    .and_modify(|prior| *prior = (*prior).max(skip))
                    .or_insert(skip);
            }
            out.extend(std::iter::repeat_n(0x143, count as usize));
            safe.nested_safe_pop = None;
            safe.safe_chain_fixups.clear();
        }
        let source_events = source_info.unwrap_or(&[]);
        while source_event_index < source_events.len()
            && source_events[source_event_index].offset <= start
        {
            let event = &source_events[source_event_index];
            if reverse_initial_debug_marker && source_event_index == 0 {
                if event.line > 0 {
                    out.extend([0x85, event.line as u32]);
                }
                if let Some(file) = event.file {
                    let file = mapped(ids.string(file as u32), start, "source filename")?;
                    out.extend([0x84, file]);
                }
                source_event_index += 1;
                continue;
            }
            if let Some(file) = event.file {
                let file = mapped(ids.string(file as u32), start, "source filename")?;
                out.extend([0x84, file]);
            }
            if event.line > 0 {
                out.extend([0x85, event.line as u32]);
            }
            source_event_index += 1;
        }
        let op = reader.byte()?;
        if reader.code.get(reader.at) == Some(&7)
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
            state.cached_world_owner = false;
            if let Some(pending) = &mut state.pending_world_ref {
                pending.rhs_changed_cache = true;
            }
        }
        if let Some((_, body_at)) = safe
            .pending_safe_index_lvalue
            .filter(|(at, _)| *at == start)
        {
            safe.pending_safe_index_lvalue = None;
            let value_at = constructor_argument_start(&out[body_at..], 1)
                .map(|at| body_at + at)
                .ok_or_else(|| LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "safe indexed lvalue value has unknown stack effects".into(),
                })?;
            let key_at =
                constructor_argument_start(&out[body_at..value_at], 1).map(|at| body_at + at);
            let cached_list_field = key_at.filter(|at| *at > body_at).and_then(|at| {
                let items = crate::bytecode::decode(&out[body_at..at]).ok()?;
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
            reader.byte()?; // Verified Index reference, no operands.
            let end = out.len();
            let value_len = end - value_at;
            let mut replacement = out[value_at..end].to_vec();
            replacement.push(0x143);
            if cached_list_field.is_none() {
                replacement.extend([0x33, 0xffd8]);
            }
            replacement.extend_from_slice(&out[body_at..value_at]);
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
            let moved_offsets = offsets
                .iter()
                .filter(|(_, value)| **value as usize >= body_at && (**value as usize) < end)
                .map(|(key, value)| (*key, moved(*value as usize) as u32))
                .collect::<Vec<_>>();
            let moved_fixups = fixups
                .iter()
                .enumerate()
                .filter(|(_, fixup)| fixup.at >= body_at && fixup.at < end)
                .map(|(index, fixup)| (index, moved(fixup.at)))
                .collect::<Vec<_>>();
            replace_words(
                &mut out,
                &mut offsets,
                &mut fixups,
                body_at,
                end - body_at,
                &replacement,
            );
            offsets.extend(moved_offsets);
            for (index, at) in moved_fixups {
                fixups[index].at = at;
            }
            offsets.insert(reader.at as u32, out.len() as u32);
            if let Some((_, count)) = safe
                .nested_safe_pop
                .filter(|(target, _)| *target == reader.at as u32)
            {
                out.extend(std::iter::repeat_n(0x143, count as usize));
                safe.nested_safe_pop = None;
                safe.safe_chain_fixups.clear();
            }
            reader.byte()?; // Discarded statement result.
            continue;
        }
        if let Some((_, discard)) = safe.pending_safe_lvalue_at.filter(|(at, _)| *at == start) {
            let chained_body = safe.pending_safe_lvalue_body.take();
            if chained_body.is_none() {
                out.push(0x143); // Restore safe lvalue receiver after RHS evaluation.
            }
            safe.pending_safe_lvalue_at = None;
            safe.pending_safe_aug_sub = false;
            let target = reference(&mut reader, ids)?;
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
                let end = out.len();
                let has_rhs = !matches!(op, 0x56 | 0x57 | 0x62 | 0x63);
                let rhs_at = if has_rhs {
                    guarded_assignment_spans(&out, code, &offsets, &fixups, start, 1)
                        .filter(|(owner, _)| *owner >= body_at)
                        .map(|(_, rhs)| rhs)
                        .or_else(|| {
                            constructor_argument_start(&out[body_at..], 1).map(|at| body_at + at)
                        })
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "guarded field RHS has unknown stack effects".into(),
                        })?
                } else {
                    end
                };
                let owner_words = out[body_at..rhs_at].to_vec();
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
                let mut replacement = out[rhs_at..end].to_vec();
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
                for (&source, &old) in &offsets {
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
                for (index, fixup) in fixups.iter_mut().enumerate() {
                    if fixup.at >= body_at && fixup.at < end {
                        if fixup.at >= rhs_at && fixup.target == start as u32 {
                            fixup.target = rhs_join;
                        } else if fixup.at < rhs_at
                            && (fixup.target == start as u32
                                || offsets.get(&fixup.target).copied() == Some(rhs_at as u32))
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
                    &mut out,
                    &mut offsets,
                    &mut fixups,
                    body_at,
                    end - body_at,
                    &replacement,
                );
                offsets.extend(moved_offsets);
                for (index, at) in moved_fixups {
                    fixups[index].at = at;
                }
                offsets.insert(rhs_join, (body_at + rhs_len) as u32);
                offsets.insert(owner_join, (body_at + rhs_len + owner_words.len()) as u32);
                offsets.insert(start as u32, action_at as u32);
            } else {
                out.push(native_op);
                emit_tracked_reference(
                    &mut out,
                    &target,
                    &mut state.cached_world_owner,
                    &mut state.pending_world_ref,
                );
            }
            if !discard && matches!(op, 0x1a | 0x1f) {
                out.push(0x13f); // Paired safe augmented expression result.
            }
            if discard {
                offsets.insert(reader.at as u32, out.len() as u32);
                if let Some((_, count)) = safe
                    .nested_safe_pop
                    .filter(|(join, _)| *join == reader.at as u32)
                {
                    out.extend(std::iter::repeat_n(0x143, count as usize));
                    safe.nested_safe_pop = None;
                    safe.safe_chain_fixups.clear();
                }
                reader.byte()?; // Paired statement Pop is included in the safe join.
            }
            if let Some((at, discard, body)) = safe.pending_safe_lvalue_stack.pop() {
                safe.pending_safe_lvalue_at = Some((at, discard));
                safe.pending_safe_lvalue_body = body;
            }
            continue;
        }
        let follows_format = state.last_was_format;
        state.last_was_format = false;
        if safe.pending_safe_field && op != 0x68 {
            return Err(LowerError {
                kind: LowerErrorKind::MalformedControlFlow,
                offset: start,
                reason: "safe dereference requires an immediate field access".into(),
            });
        }
        if lower_literal_switch_chain(
            &mut reader,
            ids,
            start,
            op,
            &mut out,
            &mut offsets,
            &mut fixups,
        )? {
            state.last_reference_push = None;
            state.cached_world_owner = false;
            continue;
        }
        match op {
            // Constants and direct references.
            0x11 | 0x38 => {
                if lower_constant_and_switch(
                    op,
                    &mut reader,
                    ids,
                    start,
                    &mut out,
                    &mut offsets,
                    &mut fixups,
                    &spawn_targets,
                )? {
                    continue;
                }
            }
            0x2e => {
                let mode = reader.byte()?;
                let count = reader.word()?;
                if !(matches!((mode, count), (0, 0))
                    || mode == 1 && (1..=255).contains(&count)
                    || mode == 2 && (2..=510).contains(&count) && count % 2 == 0
                    || (mode, count) == (3, 1))
                {
                    return Err(LowerError {
                        kind: LowerErrorKind::UnsupportedConstruct,
                        offset: start,
                        reason: "dynamic CreateObject argument mode/count is unsupported".into(),
                    });
                }
                let instructions = crate::bytecode::decode(&out).map_err(|error| LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: format!("cannot inspect dynamic constructor: {}", error.reason),
                })?;
                let pair = instructions
                    .get(instructions.len().saturating_sub(2)..)
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "dynamic constructor lacks null and type".into(),
                    })?;
                let null = &pair[0];
                let ty = &pair[1];
                if null.opcode != 0x60
                    || out.get(null.offset..null.offset + 3) != Some(&[0x60, 0, 0][..])
                    || ty.opcode != 0x33
                {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "dynamic constructor requires direct type reference".into(),
                    });
                }
                let arg_at = if count == 0 {
                    null.offset
                } else {
                    constructor_argument_start(&out[..null.offset], count as usize).ok_or_else(
                        || LowerError {
                            kind: LowerErrorKind::UnsupportedConstruct,
                            offset: start,
                            reason: "dynamic constructor argument effects are unsupported".into(),
                        },
                    )?
                };
                let mut replacement = out[ty.offset..].to_vec();
                replacement.extend_from_slice(&out[arg_at..null.offset]);
                let old_len = out.len() - arg_at;
                replace_words(
                    &mut out,
                    &mut offsets,
                    &mut fixups,
                    arg_at,
                    old_len,
                    &replacement,
                );
                if mode == 2 {
                    out.extend([0xc8, count / 2, 0xcf]);
                } else if mode == 3 {
                    out.push(0xcf);
                } else {
                    out.extend([0x01, count]);
                }
            }
            0x98 => {
                // ReturnFloat
                let bits = reader.word()?;
                out.extend([0x60, 0x2a, bits >> 16, bits & 0xffff, 0x12]);
            }
            0x9a => {
                // PushFloatAssign(float, reference)
                let bits = reader.word()?;
                if reader.code.get(reader.at) == Some(&7) {
                    reader.byte()?; // Index reference consumes the list and key.
                    let argument_start =
                        constructor_argument_start(&out, 2).ok_or_else(|| LowerError {
                            kind: LowerErrorKind::UnsupportedConstruct,
                            offset: start,
                            reason: "indexed float assignment has unsupported list/key expressions"
                                .into(),
                        })?;
                    let value = [0x60, 0x2a, bits >> 16, bits & 0xffff];
                    replace_words(
                        &mut out,
                        &mut offsets,
                        &mut fixups,
                        argument_start,
                        0,
                        &value,
                    );
                    out.push(0x7c); // native ListSet(value, list, key)
                    continue;
                }
                let target = reference(&mut reader, ids)?;
                if let Variable::Field(field) = target {
                    emit_float_field_assignment(
                        &mut out,
                        &mut offsets,
                        &mut fixups,
                        start,
                        field,
                        bits,
                    )?;
                    state.last_reference_push = None;
                    state.cached_world_owner = false;
                    continue;
                }
                out.extend([0x60, 0x2a, bits >> 16, bits & 0xffff, 0x34]);
                emit_tracked_reference(
                    &mut out,
                    &target,
                    &mut state.cached_world_owner,
                    &mut state.pending_world_ref,
                );
            }
            0x9b => {
                // Repeated PushFloat + AssignNoPush pairs, packed by
                // OpenDream's compactor.
                let count = reader.word()?;
                if count > 255 {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "NPushFloatAssign count exceeds 255".into(),
                    });
                }
                for _ in 0..count {
                    let bits = reader.word()?;
                    if reader.code.get(reader.at) == Some(&7) {
                        reader.byte()?;
                        let at = constructor_argument_start(&out, 2).ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason:
                                "packed indexed float assignment has unknown list/key stack effects"
                                    .into(),
                        })?;
                        let value = [0x60, 0x2a, bits >> 16, bits & 0xffff];
                        replace_words(&mut out, &mut offsets, &mut fixups, at, 0, &value);
                        out.push(0x7c);
                        continue;
                    }
                    let target = reference(&mut reader, ids)?;
                    if let Variable::Field(field) = target {
                        emit_float_field_assignment(
                            &mut out,
                            &mut offsets,
                            &mut fixups,
                            start,
                            field,
                            bits,
                        )?;
                        state.last_reference_push = None;
                        state.cached_world_owner = false;
                        continue;
                    }
                    out.extend([0x60, 0x2a, bits >> 16, bits & 0xffff, 0x34]);
                    emit_tracked_reference(
                        &mut out,
                        &target,
                        &mut state.cached_world_owner,
                        &mut state.pending_world_ref,
                    );
                }
            }
            0x03 => {
                let old_string = reader.word()?;
                if reader.code.get(reader.at) == Some(&0x02)
                    && reader.code.get(reader.at + 5) == Some(&0x2e)
                {
                    let old_type = u32::from_le_bytes(
                        reader.code[reader.at + 1..reader.at + 5]
                            .try_into()
                            .unwrap(),
                    );
                    let mode = *reader.code.get(reader.at + 6).ok_or_else(|| LowerError {
                        kind: LowerErrorKind::TruncatedOperand,
                        offset: start,
                        reason: "truncated modified constructor mode".into(),
                    })?;
                    let count = u32::from_le_bytes(
                        reader
                            .code
                            .get(reader.at + 7..reader.at + 11)
                            .ok_or_else(|| LowerError {
                                kind: LowerErrorKind::TruncatedOperand,
                                offset: start,
                                reason: "truncated modified constructor count".into(),
                            })?
                            .try_into()
                            .unwrap(),
                    );
                    if !(matches!((mode, count), (0, 0))
                        || mode == 1 && (1..=255).contains(&count)
                        || mode == 2 && (2..=510).contains(&count) && count % 2 == 0
                        || (mode, count) == (3, 1))
                    {
                        return Err(LowerError {
                            kind: LowerErrorKind::UnsupportedConstruct,
                            offset: start,
                            reason: "modified constructor argument mode/count is unsupported"
                                .into(),
                        });
                    }
                    let instance = mapped(
                        ids.modified_instance(old_type, old_string),
                        start,
                        "modified instance prototype",
                    )?;
                    if count > 0 {
                        let args_at =
                            constructor_argument_start(&out, count as usize).ok_or_else(|| {
                                LowerError {
            kind: LowerErrorKind::UnsupportedConstruct,
                                offset: start,
                                reason:
                                    "modified constructor arguments have unsupported stack effects"
                                        .into(),
                            }
                            })?;
                        let mut prototype = Vec::new();
                        push_value(&mut prototype, 41, instance);
                        replace_words(&mut out, &mut offsets, &mut fixups, args_at, 0, &prototype);
                    } else {
                        push_value(&mut out, 41, instance);
                    }
                    offsets.insert(reader.at as u32, out.len() as u32);
                    reader.at += 5; // PushType + original type ID
                    offsets.insert(reader.at as u32, out.len() as u32);
                    reader.at += 6; // CreateObject + argument mode/count
                    if mode == 2 {
                        out.extend([0xc8, count / 2, 0xcf]);
                    } else if mode == 3 {
                        out.push(0xcf);
                    } else {
                        out.extend([0x01, count]);
                    }
                    continue;
                }
                let first = mapped(ids.string(old_string), start, "string")?;
                if reader.code.get(reader.at) == Some(&0x32) {
                    let switch_at = out.len();
                    let mut cases = Vec::new();
                    let mut string_id = first;
                    loop {
                        if reader.byte()? != 0x32 {
                            return Err(LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "string switch lacks SwitchCase".into(),
                            });
                        }
                        cases.push((string_id, reader.word()?));
                        if reader.code.get(reader.at) == Some(&0x03)
                            && reader.code.get(reader.at + 5) == Some(&0x32)
                        {
                            offsets.insert(reader.at as u32, switch_at as u32);
                            reader.at += 1;
                            string_id = mapped(ids.string(reader.word()?), start, "string")?;
                        } else {
                            break;
                        }
                    }
                    if reader.code.get(reader.at) != Some(&0x51) {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "string switch lacks Pop".into(),
                        });
                    }
                    offsets.insert(reader.at as u32, switch_at as u32);
                    reader.at += 1;
                    let default = if reader.code.get(reader.at) == Some(&0x0e)
                        && !authored_control_jump(ids, reader.code, reader.at)
                    {
                        offsets.insert(reader.at as u32, switch_at as u32);
                        reader.at += 1;
                        reader.word()?
                    } else {
                        reader.at as u32
                    };
                    out.extend([0x78, cases.len() as u32]);
                    for (id, target) in cases {
                        out.extend(
                            Value {
                                tag_word: 6 | ((id >> 16) << 8),
                                data_word: id & 0xffff,
                                extra_word: None,
                            }
                            .encode(),
                        );
                        let at = out.len();
                        out.push(0);
                        fixups.push(Fixup {
                            at,
                            target,
                            source: start,
                        });
                    }
                    let at = out.len();
                    out.push(0);
                    fixups.push(Fixup {
                        at,
                        target: default,
                        source: start,
                    });
                    continue;
                }
                push_value(&mut out, 6, first);
            }
            0x8a => {
                // PushStringFloat, used for associative-list key/value
                push_value(
                    &mut out,
                    6,
                    mapped(ids.string(reader.word()?), start, "string")?,
                );
                let bits = reader.word()?;
                out.extend([0x60, 0x2a, bits >> 16, bits & 0xffff]);
            }
            0x8d | 0x93 => {
                // SwitchOnFloat / SwitchOnString case chain
                let switch_at = out.len();
                let mut cases = Vec::new();
                let mut ranges = Vec::new();
                let mut case_op = op;
                loop {
                    if case_op == 0x88 {
                        if reader.word()? != 2 {
                            return Err(LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "switch range requires two bounds".into(),
                            });
                        }
                        let lo = reader.word()?;
                        let hi = reader.word()?;
                        if reader.byte()? != 0x05 {
                            return Err(LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "switch range lacks SwitchCaseRange".into(),
                            });
                        }
                        ranges.push((lo, hi, reader.word()?));
                    } else {
                        let value = if case_op == 0x11 {
                            reader.byte()?; // paired PushNull + SwitchCase
                            Value {
                                tag_word: 0,
                                data_word: 0,
                                extra_word: None,
                            }
                        } else if case_op == 0x8d {
                            let bits = reader.word()?;
                            Value {
                                tag_word: 0x2a,
                                data_word: bits >> 16,
                                extra_word: Some(bits & 0xffff),
                            }
                        } else {
                            let id = mapped(ids.string(reader.word()?), start, "string")?;
                            Value {
                                tag_word: 6 | ((id >> 16) << 8),
                                data_word: id & 0xffff,
                                extra_word: None,
                            }
                        };
                        let target = reader.word()?;
                        cases.push((value, target));
                    }
                    let next = reader.code.get(reader.at).copied();
                    let next_range = reader.code.get(reader.at..reader.at + 5)
                        == Some(&[0x88, 2, 0, 0, 0])
                        && reader.code.get(reader.at + 13) == Some(&0x05);
                    let next_null =
                        reader.code.get(reader.at..reader.at + 2) == Some(&[0x11, 0x32]);
                    if next != Some(0x8d) && next != Some(0x93) && !next_range && !next_null {
                        break;
                    }
                    offsets.insert(reader.at as u32, switch_at as u32);
                    case_op = reader.byte()?;
                }
                if reader.code.get(reader.at) != Some(&0x51) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "switch case chain lacks Pop before default".into(),
                    });
                }
                offsets.insert(reader.at as u32, switch_at as u32);
                reader.byte()?; // Pop switch expression
                let default = if reader.code.get(reader.at) == Some(&0x0e)
                    && !authored_control_jump(ids, reader.code, reader.at)
                {
                    offsets.insert(reader.at as u32, switch_at as u32);
                    reader.byte()?; // Jump default
                    reader.word()?
                } else {
                    reader.at as u32 // Default body starts immediately after Pop.
                };
                if ranges.is_empty() {
                    out.extend([0x78, cases.len() as u32]);
                } else {
                    out.extend([0x7a, ranges.len() as u32]);
                    for (lo, hi, target) in ranges {
                        out.extend([0x2a, lo >> 16, lo & 0xffff, 0x2a, hi >> 16, hi & 0xffff]);
                        let at = out.len();
                        out.push(0);
                        fixups.push(Fixup {
                            at,
                            target,
                            source: start,
                        });
                    }
                    out.push(cases.len() as u32);
                }
                for (value, target) in cases {
                    out.extend(value.encode());
                    let at = out.len();
                    out.push(0);
                    fixups.push(Fixup {
                        at,
                        target,
                        source: start,
                    });
                }
                let at = out.len();
                out.push(0);
                fixups.push(Fixup {
                    at,
                    target: default,
                    source: start,
                });
            }
            0x04 => {
                // FormatString(template ID, interpolation count)
                let template = mapped(ids.string(reader.word()?), start, "string")?;
                let count = reader.word()?;
                out.extend([0x02, template, count]);
                state.last_was_format = true;
            }
            0x21 => push_value(
                &mut out,
                12,
                mapped(ids.resource(reader.word()?), start, "resource")?,
            ),
            0x26 => push_value(
                &mut out,
                38,
                mapped(ids.proc_id(reader.word()?), start, "proc")?,
            ),
            0x9f => {
                // Pinned OpenDream exporter: modified type constant. Native
                // stores its preallocated instance prototype as value tag 41.
                let old_type = reader.word()?;
                let old_string = reader.word()?;
                push_value(
                    &mut out,
                    41,
                    mapped(
                        ids.modified_instance(old_type, old_string),
                        start,
                        "modified type instance",
                    )?,
                );
            }
            0x02 => {
                let old = reader.word()?;
                let tag = ids.type_tag(old).ok_or_else(|| LowerError {
                    kind: LowerErrorKind::UnresolvedSymbol,
                    offset: start,
                    reason: "unresolved type tag".into(),
                })?;
                let first = mapped(ids.type_id(old), start, "type")?;
                if reader.code.get(reader.at) == Some(&0x32) {
                    // A switch on type paths is a native Switch table whose
                    // case values retain each type's BYOND value tag.
                    let switch_at = out.len();
                    let mut cases = Vec::new();
                    let mut case_tag = tag;
                    let mut case_id = first;
                    loop {
                        if reader.byte()? != 0x32 {
                            return Err(LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "type switch lacks SwitchCase".into(),
                            });
                        }
                        cases.push((case_tag, case_id, reader.word()?));
                        if reader.code.get(reader.at) == Some(&0x02)
                            && reader.code.get(reader.at + 5) == Some(&0x32)
                        {
                            offsets.insert(reader.at as u32, switch_at as u32);
                            reader.at += 1;
                            let old = reader.word()?;
                            case_tag = ids.type_tag(old).ok_or_else(|| LowerError {
                                kind: LowerErrorKind::UnresolvedSymbol,
                                offset: start,
                                reason: "unresolved switch type tag".into(),
                            })?;
                            case_id = mapped(ids.type_id(old), start, "switch type")?;
                        } else {
                            break;
                        }
                    }
                    if reader.code.get(reader.at) != Some(&0x51) {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "type switch lacks Pop".into(),
                        });
                    }
                    offsets.insert(reader.at as u32, switch_at as u32);
                    reader.at += 1;
                    let default = if reader.code.get(reader.at) == Some(&0x0e)
                        && !authored_control_jump(ids, reader.code, reader.at)
                    {
                        offsets.insert(reader.at as u32, switch_at as u32);
                        reader.at += 1;
                        reader.word()?
                    } else {
                        reader.at as u32
                    };
                    out.extend([0x78, cases.len() as u32]);
                    for (tag, id, target) in cases {
                        out.extend(
                            Value {
                                tag_word: tag as u32 | ((id >> 16) << 8),
                                data_word: id & 0xffff,
                                extra_word: None,
                            }
                            .encode(),
                        );
                        let at = out.len();
                        out.push(0);
                        fixups.push(Fixup {
                            at,
                            target,
                            source: start,
                        });
                    }
                    let at = out.len();
                    out.push(0);
                    fixups.push(Fixup {
                        at,
                        target: default,
                        source: start,
                    });
                    continue;
                }
                push_value(&mut out, tag, first);
            }
            0x95 => {
                // IsTypeDirect folds PushType; IsType. Preserve the original
                // stack order by expanding that pair for DreamDaemon.
                let old = reader.word()?;
                let tag = ids.type_tag(old).ok_or_else(|| LowerError {
                    kind: LowerErrorKind::UnresolvedSymbol,
                    offset: start,
                    reason: "unresolved type tag".into(),
                })?;
                push_value(&mut out, tag, mapped(ids.type_id(old), start, "type")?);
                out.push(0x7d);
            }
            0x5f => {
                let id = mapped(ids.global_vars_variable(), start, "GlobalVars variable")?;
                let at = out.len();
                out.extend([0x33, 0xffdb, id]);
                state.last_reference_push = Some((at, Variable::Global(id)));
            }
            0x5c => out.extend([0x6c, reader.word()?]), // addtext(...)
            0x07 => {
                let mode = reader.byte()?;
                let count = reader.word()?;
                match (mode, count) {
                    (1, 3) => out.push(0xbb),
                    (1, 4) => out.push(0x113),
                    (1, 5) => out.push(0x161),
                    _ => {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "Rgb argument mode/count has no verified lowering".into(),
                        })
                    }
                }
            }
            0xa9 => {
                // Pinned Field compound/unary operations evaluate RHS first,
                // then the owner. Direct references remain late native reads.
                let operation = reader.byte()?;
                let field = mapped(ids.string(reader.word()?), start, "string")?;
                let discard = match reader.byte()? {
                    0 => false,
                    1 => true,
                    _ => {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "native Field operation discard flag is invalid".into(),
                        })
                    }
                };
                let native_op = match (operation, discard) {
                    (0x56 | 0x62, true) => 0x66,
                    (0x57 | 0x63, true) => 0x67,
                    (0x56, false) => 0x63,
                    (0x57, false) => 0x65,
                    (0x62, false) => 0x62,
                    (0x63, false) => 0x64,
                    (0x1a, _) => 0x45,
                    (0x1f, _) => 0x46,
                    (0x0b, _) => 0x47,
                    (0x17, _) => 0x48,
                    (0x39, _) => 0x49,
                    (0x33, _) => 0x4a,
                    (0x2d, _) => 0x4b,
                    (0x29, _) => 0x4c,
                    (0x6d, _) => 0x4d,
                    (0x6e, _) => 0x4e,
                    (0x61, _) => 0x177,
                    _ => {
                        return Err(LowerError {
                            kind: LowerErrorKind::UnsupportedConstruct,
                            offset: start,
                            reason: format!(
                                "native Field operation {operation:#04x} is unsupported"
                            ),
                        })
                    }
                };
                let direct = if !fixups.iter().any(|fixup| fixup.target == start as u32) {
                    constructor_argument_start(&out, 1).and_then(|at| {
                        let items = crate::bytecode::decode(&out[at..]).ok()?;
                        let executable: Vec<_> = items
                            .iter()
                            .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
                            .collect();
                        let [item] = executable.as_slice() else {
                            return None;
                        };
                        if item.opcode != 0x33 {
                            return None;
                        }
                        Variable::decode(&item.operands)
                            .ok()
                            .map(|(reference, _)| (at + item.offset, reference))
                    })
                } else {
                    None
                };
                let target = if let Some((at, reference)) = direct {
                    // Preserve source markers around the folded owner read.
                    let old_len = 1 + reference.encode().len();
                    replace_words(&mut out, &mut offsets, &mut fixups, at, old_len, &[]);
                    append_field(reference, field)
                } else {
                    out.extend([0x34, 0xffd8]);
                    Variable::Field(field)
                };
                out.push(native_op);
                emit_tracked_reference(
                    &mut out,
                    &target,
                    &mut state.cached_world_owner,
                    &mut state.pending_world_ref,
                );
                if !discard && !matches!(operation, 0x56 | 0x57 | 0x62 | 0x63) {
                    out.push(0x13f);
                }
                state.last_reference_push = None;
                state.cached_world_owner = false;
                if let Some(pending) = &mut state.pending_world_ref {
                    pending.rhs_changed_cache = true;
                }
            }
            0xa8 => {
                let field = mapped(ids.string(reader.word()?), start, "field name")?;
                let retain = reader.byte()?;
                if retain > 1 {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "native field assignment retain flag is invalid".into(),
                    });
                }
                // Fold only an unconditional direct reference; a branch join
                // may end in GetVar while representing multiple receivers.
                let direct = crate::bytecode::decode(&out).ok().and_then(|items| {
                    if fixups.iter().any(|fixup| fixup.target == start as u32) {
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
                    replace_words(&mut out, &mut offsets, &mut fixups, at, removed, &[]);
                    if let Some(duplicate) = duplicate {
                        replace_words(&mut out, &mut offsets, &mut fixups, duplicate, 1, &[]);
                    }
                    out.push(if retain == 1 { 0x35 } else { 0x34 });
                    out.extend(append_field(owner, field).encode());
                } else {
                    // The exporter duplicates the value before evaluating a
                    // computed owner, including conditional receiver paths.
                    out.extend([0x34, 0xffd8, 0x34, field]);
                }
                state.last_reference_push = None;
                state.cached_world_owner = false;
            }
            0xa7 => {
                // The patched exporter preserves AST positional keys, so no
                // instruction-span guessing is needed for computed options.
                let mode = reader.byte()?;
                let count = reader.word()?;
                match (mode, count) {
                    (1, 1) => out.push(0x129),
                    (2, count) if (2..=510).contains(&count) && count % 2 == 0 => {
                        out.extend([0xc8, count / 2, 0x128]);
                    }
                    (3, 1) => out.push(0x128),
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
                let mode = reader.byte()?;
                let count = reader.word()?;
                match (mode, count) {
                    (1, 1) => out.push(0x129), // animate(target)
                    (2, 4 | 6 | 8 | 10 | 12) => {
                        // Paired animate(target, alpha=n, time=n): OpenDream
                        // starts its named argument list with null; native
                        // DreamMaker starts the assoc list with integer 1.
                        let instructions =
                            crate::bytecode::decode(&out).map_err(|error| LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: format!(
                                    "cannot inspect animate arguments: {}",
                                    error.reason
                                ),
                            })?;
                        let args_at =
                            constructor_argument_start(&out, count as usize).ok_or_else(|| {
                                LowerError {
                                    kind: LowerErrorKind::MalformedControlFlow,
                                    offset: start,
                                    reason: "animate named arguments have unknown stack effects"
                                        .into(),
                                }
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
                            && out.get(first.offset..first.offset + 3) == Some(&[0x60, 0, 0][..])
                        {
                            replace_words(
                                &mut out,
                                &mut offsets,
                                &mut fixups,
                                first.offset,
                                3,
                                &[0x50, 1],
                            );
                        }
                        out.extend([0xc8, count / 2, 0x128]);
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
                let mode = reader.byte()?;
                let count = reader.word()?;
                match (mode, count) {
                    (1, 2) => {
                        let literal_list = constructor_argument_start(&out, 1)
                            .and_then(|at| crate::bytecode::decode(&out[..at]).ok())
                            .and_then(|items| {
                                items
                                    .into_iter()
                                    .rev()
                                    .find(|item| !matches!(item.opcode, 0x84 | 0x85))
                            })
                            .is_some_and(|item| matches!(item.opcode, 0x1a | 0xc8 | 0x17c));
                        if literal_list {
                            out.push(0x163);
                        } else {
                            out.extend([0x1a, 2, 0x164]);
                        }
                    }
                    (1, 1..=255) => out.extend([0x1a, count, 0x164]),
                    (3, 1) => out.push(0x164),
                    (2, 2..=510) if count % 2 == 0 => {
                        let mut end = out.len();
                        let mut spans = Vec::new();
                        for _ in 0..count {
                            let at =
                                constructor_argument_start(&out[..end], 1).ok_or_else(|| {
                                    LowerError {
                                        kind: LowerErrorKind::MalformedControlFlow,
                                        offset: start,
                                        reason: "gradient keyed argument has unknown stack effects"
                                            .into(),
                                    }
                                })?;
                            spans.push((at, end));
                            end = at;
                        }
                        spans.reverse();
                        for (index, pair) in spans.chunks_exact(2).enumerate().rev() {
                            let (lo, hi) = pair[0];
                            let items = crate::bytecode::decode(&out[lo..hi]).map_err(|error| {
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
                                        &mut out,
                                        &mut offsets,
                                        &mut fixups,
                                        lo + item.offset,
                                        3,
                                        &[0x50, index as u32 + 1],
                                    );
                                }
                            }
                        }
                        out.extend([0xc8, count / 2, 0x164]);
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
            0x48 => out.push(0x185), // astype(value, type)
            0x06 => {
                if ids.native_initial_reference(start) && ids.native_is_saved_reference(start) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "conflicting native reference modifiers".into(),
                    });
                }
                if (ids.native_initial_reference(start) || ids.native_is_saved_reference(start))
                    && !matches!(reader.code.get(reader.at), Some(8..=10))
                {
                    return Err(LowerError {
            kind: LowerErrorKind::MalformedControlFlow, offset: start, reason: "native reference modifier requires a local, argument, or constant global".into() });
                }
                // OpenDream writes `world.log << "text"` as a world reference,
                // a string value, and OutputReference(Field). DreamMaker uses
                // GetVar(SetCache(World, Field)), PushVal, Output instead.
                if reader.code.get(reader.at..reader.at + 2) == Some(&[5, 3])
                    && reader.code.get(reader.at + 6..reader.at + 8) == Some(&[0x4e, 12])
                {
                    reader.byte()?; // World reference kind
                    let string_at = reader.at;
                    reader.byte()?; // PushString
                    let string_id = reader.word()?;
                    let output_at = reader.at;
                    reader.byte()?; // OutputReference
                    reader.byte()?; // Field reference kind
                    let field_id = mapped(ids.string(reader.word()?), start, "string")?;
                    if state.cached_world_owner {
                        world_flow.reused = true;
                        out.extend([0x33, field_id]);
                    } else {
                        out.extend([0x33, 0xffdc, 0xffe5, field_id]);
                    }
                    offsets.insert(string_at as u32, out.len() as u32);
                    push_value(&mut out, 6, mapped(ids.string(string_id), start, "string")?);
                    offsets.insert(output_at as u32, out.len() as u32);
                    out.push(0x03);
                    state.pending_world_ref = None;
                    state.cached_world_owner = true;
                } else {
                    let output_start = out.len();
                    out.push(0x33);
                    let source_reference_at = reader.at;
                    let var = reference(&mut reader, ids)?;
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
                            let raw = reader
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
                        world_flow.reused |= state.cached_world_owner;
                        state.pending_world_ref = Some(PendingWorld {
                            at: output_start,
                            world_cached_at_push: state.cached_world_owner,
                            rhs_changed_cache: false,
                        });
                    } else if matches!(var, Variable::SetCache(_, _)) {
                        state.cached_world_owner = false;
                        if let Some(pending) = &mut state.pending_world_ref {
                            pending.rhs_changed_cache = true;
                        }
                    }
                    state.last_reference_push = Some((output_start, var.clone()));
                    out.extend(var.encode());
                }
            }
            0x86 => {
                // PushRefAndDereferenceField
                let owner = reference(&mut reader, ids)?;
                let field = mapped(ids.string(reader.word()?), start, "string")?;
                out.push(0x33);
                if owner == Variable::World && state.cached_world_owner {
                    world_flow.reused = true;
                    out.extend(Variable::Field(field).encode());
                } else {
                    out.extend(
                        Variable::SetCache(
                            Box::new(owner.clone()),
                            Box::new(Variable::Field(field)),
                        )
                        .encode(),
                    );
                }
                state.last_reference_push = None;
                state.cached_world_owner = owner == Variable::World;
                if !state.cached_world_owner {
                    if let Some(pending) = &mut state.pending_world_ref {
                        pending.rhs_changed_cache = true;
                    }
                }
            }
            0x96 => {
                // NullRef: clear a variable without retaining a value
                if reader.code.get(reader.at) == Some(&7) {
                    reader.byte()?;
                    let at = constructor_argument_start(&out, 2).ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "indexed NullRef has unknown list/key stack effects".into(),
                    })?;
                    if fixups
                        .iter()
                        .any(|fixup| fixup.at >= at && fixup.at < out.len())
                    {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "indexed NullRef operand branches need relocation".into(),
                        });
                    }
                    let mut replacement = vec![0x60, 0, 0];
                    replacement.extend_from_slice(&out[at..]);
                    replacement.push(0x7c);
                    let old_len = out.len() - at;
                    replace_words(
                        &mut out,
                        &mut offsets,
                        &mut fixups,
                        at,
                        old_len,
                        &replacement,
                    );
                    state.last_reference_push = None;
                    continue;
                }
                let target = reference(&mut reader, ids)?;
                if let Variable::Field(field) = target {
                    let instructions =
                        crate::bytecode::decode(&out).map_err(|error| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: format!("cannot inspect NullRef field owner: {}", error.reason),
                        })?;
                    if let Some(prior) = instructions.last().filter(|prior| {
                        prior.opcode == 0x33
                            && !fixups.iter().any(|fixup| fixup.target == start as u32)
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
                            &mut out,
                            &mut offsets,
                            &mut fixups,
                            prior.offset,
                            1 + prior.operands.len(),
                            &replacement,
                        );
                    } else {
                        out.extend([0x34, 0xffd8, 0x60, 0, 0, 0x34, field]);
                    }
                    state.last_reference_push = None;
                    state.cached_world_owner = false;
                    continue;
                }
                out.extend([0x60, 0, 0, 0x34]);
                emit_tracked_reference(
                    &mut out,
                    &target,
                    &mut state.cached_world_owner,
                    &mut state.pending_world_ref,
                );
            }
            0x99 => {
                // IndexRefWithString: list/string key known at compile time
                let owner = reference(&mut reader, ids)?;
                let key = mapped(ids.string(reader.word()?), start, "string")?;
                out.push(0x33);
                out.extend(owner.encode());
                push_value(&mut out, 6, key);
                out.push(0x7b);
            }
            0x69 => {
                out.push(0x7b); // DereferenceIndex -> ListGet
                if safe.pending_safe_index == Some(reader.at as u32) {
                    out.push(0x143); // restore cache after a computed safe index
                    safe.pending_safe_index = None;
                } else if let Some(target) = safe.pending_safe_index {
                    if reader.code.get(reader.at) == Some(&0x65) {
                        if let Some((index, _)) = fixups.iter().enumerate().next_back() {
                            safe.last_safe_index = Some((reader.at, target, index));
                        }
                    }
                }
            }
            0x68 => {
                if safe.pending_safe_field {
                    let field = mapped(ids.string(reader.word()?), start, "string")?;
                    let field_at = out.len();
                    out.extend([0x33, field]);
                    if let Some((fixup_index, fixup)) = fixups.iter().enumerate().next_back() {
                        safe.last_safe_field =
                            Some((field_at, fixup.target, fixup_index, reader.at));
                    }
                    safe.pending_safe_field = false;
                    state.last_reference_push = None;
                    continue;
                }
                // Fold a chained field access into BYOND's nested SetCache
                // variable operand. This is the direct GetVar form used by
                // list.len and ordinary nested fields.
                let field = mapped(ids.string(reader.word()?), start, "string")?;
                let instructions = crate::bytecode::decode(&out).map_err(|error| LowerError {
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
                if fixups.iter().any(|fixup| fixup.target == start as u32) {
                    // At a branch join, the last GetVar belongs only to one
                    // arm. Both arms must reach a shared field read.
                    out.extend([0x34, 0xffd8, 0x33, field]);
                    state.last_reference_push = None;
                    state.cached_world_owner = false;
                    continue;
                }
                if prior.opcode == 0x30 {
                    // A global call leaves its return value on the stack. Native
                    // bytecode caches that value before reading its field.
                    out.extend([0x34, 0xffd8, 0x33, field]);
                    state.last_reference_push = None;
                    state.cached_world_owner = false;
                    continue;
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
                    out[prior.offset] = 0x34; // SetVar, then access the assigned reference
                    out.push(0x33);
                    out.extend(append_field(owner, field).encode());
                    state.last_reference_push = None;
                    state.cached_world_owner = false;
                    continue;
                }
                if prior.opcode != 0x33 {
                    // OD DereferenceField consumes its owner from the stack.
                    // Cache consumes that same value, so this also preserves
                    // branch-bearing owners without moving any instructions.
                    out.extend([0x34, 0xffd8, 0x33, field]);
                    state.last_reference_push = None;
                    state.cached_world_owner = false;
                    continue;
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
                    if safe.pending_safe_index.is_some() && owner == Variable::Cache {
                        // The null guard already installed this indexed receiver.
                        Variable::Field(field).encode()
                    } else {
                        append_field(owner, field).encode()
                    },
                );
                replace_words(
                    &mut out,
                    &mut offsets,
                    &mut fixups,
                    prior.offset,
                    1 + prior.operands.len(),
                    &replacement,
                );
                state.last_reference_push = None;
                state.cached_world_owner = false;
            }
            0x47 | 0x53 => {
                // OpenDream initial/issaved(owner.field) pushes owner and
                // field separately. BYOND nests the field in GetVar.
                if start < 5 || reader.code[start - 5] != 0x03 {
                    if guarded_assignment_spans(&out, code, &offsets, &fixups, start, 1).is_some()
                        || constructor_argument_start(&out, 2).is_some()
                    {
                        // Closed conditional/short-circuit list and key spans
                        // remain in source order; CacheIndex consumes both.
                        // Paired arbitrary list/key expressions, including
                        // numeric constants and the procedure's args list.
                        out.extend([
                            0x34,
                            0xffe3,
                            0x34,
                            0xffd8,
                            0x33,
                            if op == 0x47 { 0xffe7 } else { 0xffe8 },
                            0xffe4,
                        ]);
                        state.last_reference_push = None;
                        state.cached_world_owner = false;
                        continue;
                    }
                    let items = crate::bytecode::decode(&out).map_err(|error| LowerError {
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
                            out.extend([
                                0x34,
                                0xffe3,
                                0x34,
                                0xffd8,
                                0x33,
                                if op == 0x47 { 0xffe7 } else { 0xffe8 },
                                0xffe4,
                            ]);
                            state.last_reference_push = None;
                            continue;
                        }
                    }
                }
                if start < 5 || reader.code[start - 5] != 0x03 || out.len() < 3 {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "Initial/IsSaved requires a direct field name".into(),
                    });
                }
                let items = crate::bytecode::decode(&out).map_err(|error| LowerError {
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
                let direct_owner = state
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
                        let [crate::bytecode::Operand::Variable(owner)] = operands.as_slice()
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
                        &mut out,
                        &mut offsets,
                        &mut fixups,
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
                    state.cached_world_owner = false;
                    continue;
                }
                let (owner_at, owner) = direct_owner.unwrap();
                replace_words(
                    &mut out,
                    &mut offsets,
                    &mut fixups,
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
                replace_words(&mut out, &mut offsets, &mut fixups, string_at, 3, &value);
                state.cached_world_owner = false;
            }
            0x4a => out.push(0x5a), // LocateCoord(x,y,z)
            0x4b => {
                if ids.implicit_locate(start) {
                    let instructions =
                        crate::bytecode::decode(&out).map_err(|error| LowerError {
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
                        &mut out,
                        &mut offsets,
                        &mut fixups,
                        world.offset,
                        1 + world.operands.len(),
                        &[],
                    );
                    state.pending_world_ref = None;
                    state.last_reference_push = None;
                    out.push(0x5b);
                } else {
                    out.push(0x97);
                }
            }
            0x3a => {
                // CreateListEnumerator(id)
                let id = reader.word()?;
                begin_list_iterator(&mut out, &mut iterator_frames, id);
                let mode = pending_view_range_iterator
                    .take()
                    .unwrap_or(if pending_orange_iterator { 14 } else { 5 });
                let mask = pending_iterator_mask.take().unwrap_or(0);
                out.extend([0x52, mode, mask]);
                pending_orange_iterator = false;
            }
            0xab => {
                // Native iterator filter provenance; legacy exports lack explicit `as` flags.
                pending_iterator_mask = Some(reader.word()?);
            }
            0x41 => {
                // CreateFilteredListEnumerator(id, type filter).
                let id = reader.word()?;
                let old_type = reader.word()?;
                let tag = ids.type_tag(old_type).ok_or_else(|| LowerError {
                    kind: LowerErrorKind::UnresolvedSymbol,
                    offset: start,
                    reason: "unresolved iterator filter type tag".into(),
                })?;
                let type_id = mapped(ids.type_id(old_type), start, "iterator filter type")?;
                begin_list_iterator(&mut out, &mut iterator_frames, id);
                let exported_mask = pending_iterator_mask.take().unwrap_or(0);
                let mask = if exported_mask == 0 {
                    ids.iterator_type_mask(old_type).unwrap_or(0)
                } else {
                    exported_mask
                };
                if mask & 0x1000 == 0 && ids.iterator_root_mask(old_type) != Some(mask) {
                    filtered_enumerators.insert(id, (tag, type_id));
                }
                // Native prefilters the coarse category before assigning the
                // loop lvalue, then checks the specific subtype below.
                out.extend([
                    0x52,
                    pending_view_range_iterator
                        .take()
                        .unwrap_or(if pending_orange_iterator { 14 } else { 5 }),
                    mask,
                ]);
                pending_orange_iterator = false;
            }
            0x5d => {
                // OpenDream's type iterator takes a type value; DreamMaker
                // iterates world and filters each result by that type.
                let id = reader.word()?;
                let instructions = crate::bytecode::decode(&out).map_err(|error| LowerError {
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
                        &mut out,
                        &mut offsets,
                        &mut fixups,
                        prior.offset,
                        1 + prior.operands.len(),
                        &[0x33, 0xffe5, 0x60, 59, 0],
                    );
                    begin_list_iterator(&mut out, &mut iterator_frames, id);
                    out.extend([0x52, 5, 0x4000]);
                    if reader.code.get(reader.at) == Some(&0x06)
                        && reader.code.get(reader.at + 1) == Some(&9)
                        && reader.code.get(reader.at + 3) == Some(&0x51)
                    {
                        offsets.insert(reader.at as u32, out.len() as u32);
                        reader.at += 4;
                    }
                    continue;
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
                    &mut out,
                    &mut offsets,
                    &mut fixups,
                    prior.offset,
                    1 + prior.operands.len(),
                    &replacement,
                );
                begin_list_iterator(&mut out, &mut iterator_frames, id);
                if mask != 0 && !omit_filter {
                    filtered_enumerators.insert(id, (value.tag(), value.id()));
                }
                // Atoms use world.contents plus the native category prefilter;
                // non-atom types use the type-specific instance universe.
                out.extend([0x52, 5, if mask == 0 { 0x4000 } else { mask }]);
                if reader.code.get(reader.at) == Some(&0x06)
                    && reader.code.get(reader.at + 1) == Some(&9)
                    && reader.code.get(reader.at + 3) == Some(&0x51)
                {
                    offsets.insert(reader.at as u32, out.len() as u32);
                    reader.at += 4;
                }
            }
            0x3b => {
                // Enumerate(id, destination, exit label)
                let id = reader.word()?;
                if let Some(no_assign) = safe_index_enumerator.take() {
                    if reader.byte()? != 7 {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "safe indexed iterator lacks indexed destination".into(),
                        });
                    }
                    let exit = reader.word()?;
                    if reader.byte()? != 0x0e {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "safe indexed iterator lacks join Jump".into(),
                        });
                    }
                    let body = reader.word()?;
                    if reader.at as u32 != no_assign
                        || reader.byte()? != 0x72
                        || reader.word()? != id
                        || reader.word()? != exit
                        || reader.at as u32 != body
                    {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "safe indexed iterator branch targets differ".into(),
                        });
                    }
                    out.extend([0x7c, 0x143]);
                    offsets.insert(no_assign, out.len() as u32);
                    out.extend([0x11, 0]);
                    fixups.push(Fixup {
                        at: out.len() - 1,
                        target: exit,
                        source: start,
                    });
                    state.last_reference_push = None;
                    continue;
                }
                let indexed = reader.code.get(reader.at) == Some(&7);
                let destination = if indexed {
                    reader.byte()?;
                    Variable::CacheIndex
                } else {
                    reference(&mut reader, ids)?
                };
                let target = reader.word()?;
                let mut indexed_receiver_origin: Option<usize> = None;
                let mut indexed_receiver_offsets: Vec<(u32, usize)> = Vec::new();
                let indexed_receivers = if indexed {
                    let at = guarded_assignment_spans(&out, code, &offsets, &fixups, start, 1)
                        .map(|(first, _)| first)
                        .or_else(|| constructor_argument_start(&out, 2))
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "indexed iterator receiver has unknown stack effects".into(),
                        })?;
                    let words = out[at..].to_vec();
                    indexed_receiver_origin = Some(at);
                    indexed_receiver_offsets = offsets
                        .iter()
                        .filter(|(_, value)| **value as usize > at && **value as usize <= out.len())
                        .map(|(byte, word)| (*byte, *word as usize))
                        .collect();
                    replace_words(&mut out, &mut offsets, &mut fixups, at, words.len(), &[]);
                    words
                } else {
                    Vec::new()
                };
                if let Some(&stack_count) = range_enumerators.get(&id) {
                    // Native 516 omits receiver evaluation for indexed numeric
                    // ranges and references CacheIndex directly (paired fixture).
                    if let Some(origin) = indexed_receiver_origin {
                        fixups.retain(|fixup| fixup.at < origin);
                    }
                    out.extend([if stack_count == 2 { 0xfd } else { 0xff }, 0]);
                    fixups.push(Fixup {
                        at: out.len() - 1,
                        target,
                        source: start,
                    });
                    out.extend(destination.encode());
                    continue;
                }
                let loop_at = out.len() as u32;
                out.push(0x53); // IterNext evaluates before lvalue receivers.
                if indexed {
                    let destination = out.len();
                    let origin = indexed_receiver_origin.unwrap();
                    for (byte, word) in indexed_receiver_offsets {
                        offsets.insert(byte, (destination + word - origin) as u32);
                    }
                    for fixup in &mut fixups {
                        if fixup.at >= origin && fixup.at < origin + indexed_receivers.len() {
                            fixup.at = destination + fixup.at - origin;
                        }
                    }
                    out.extend(indexed_receivers);
                    if filtered_enumerators.contains_key(&id) {
                        // Keep the assigned list/key in cache for the subtype test.
                        out.extend([0x34, 0xffe3, 0x34, 0xffd8, 0x34, 0xffe4]);
                    } else {
                        out.push(0x7c);
                    }
                } else {
                    out.push(0x34);
                    out.extend(destination.encode());
                }
                out.extend([0x11, 0]);
                fixups.push(Fixup {
                    at: out.len() - 1,
                    target,
                    source: start,
                });
                if let Some(&(tag, type_id)) = filtered_enumerators.get(&id) {
                    out.push(0x33);
                    out.extend(destination.encode());
                    push_value(&mut out, tag, type_id);
                    out.extend([0x7d, 0x0d, 0xfa, loop_at]);
                }
            }
            0x43 => {
                let id = reader.word()?;
                if range_enumerators.contains_key(&id) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "EnumerateAssoc supports list iterators only".into(),
                    });
                }
                let indexed_value = reader.code.get(reader.at) == Some(&7);
                let value = if indexed_value {
                    reader.byte()?;
                    Variable::CacheIndex
                } else {
                    reference(&mut reader, ids)?
                };
                let indexed_key = reader.code.get(reader.at) == Some(&7);
                let key = if indexed_key {
                    reader.byte()?;
                    Variable::CacheIndex
                } else {
                    reference(&mut reader, ids)?
                };
                let target = reader.word()?;
                let receiver_count = 2 * (usize::from(indexed_value) + usize::from(indexed_key));
                let receiver_at = if receiver_count == 0 {
                    out.len()
                } else {
                    guarded_assignment_spans(
                        &out,
                        code,
                        &offsets,
                        &fixups,
                        start,
                        receiver_count - 1,
                    )
                    .map(|(first, _)| first)
                    .or_else(|| constructor_argument_start(&out, receiver_count))
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "associative iterator indexed receivers have unknown stack effects"
                            .into(),
                    })?
                };
                let receivers = out[receiver_at..].to_vec();
                let receiver_end = out.len();
                let moved_offsets = offsets
                    .iter()
                    .filter(|(_, value)| {
                        **value as usize > receiver_at && **value as usize <= receiver_end
                    })
                    .map(|(byte, word)| (*byte, *word as usize))
                    .collect::<Vec<_>>();
                let moved_fixups = fixups
                    .iter()
                    .enumerate()
                    .filter(|(_, fixup)| fixup.at >= receiver_at && fixup.at < receiver_end)
                    .map(|(index, fixup)| (index, fixup.at))
                    .collect::<Vec<_>>();
                let value_words = if indexed_value {
                    let end = if indexed_key {
                        guarded_assignment_spans(&out, code, &offsets, &fixups, start, 1)
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
                    &mut out,
                    &mut offsets,
                    &mut fixups,
                    receiver_at,
                    receivers.len(),
                    &[],
                );
                let instructions = crate::bytecode::decode(&out).map_err(|error| LowerError {
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
                out[load.offset + 1] = 20;
                let loop_at = out.len() as u32;
                out.push(0x53);
                let value_destination = out.len();
                let value_len = value_words.len();
                if indexed_value {
                    out.extend(value_words);
                    out.extend([0x34, 0xffe3, 0x34, 0xffd8]);
                }
                out.push(0x17e);
                out.extend(value.encode());
                let key_destination = out.len();
                if indexed_key {
                    out.extend(key_words);
                    out.push(0x7c);
                } else {
                    out.push(0x34);
                    out.extend(key.encode());
                }
                let relocated = |word: usize| {
                    if indexed_value && word <= receiver_at + value_len {
                        value_destination + word - receiver_at
                    } else {
                        key_destination + word - receiver_at - value_len
                    }
                };
                for (byte, word) in moved_offsets {
                    offsets.insert(byte, relocated(word) as u32);
                }
                for (index, word) in moved_fixups {
                    fixups[index].at = relocated(word);
                }
                out.extend([0x11, 0]);
                fixups.push(Fixup {
                    at: out.len() - 1,
                    target,
                    source: start,
                });
                if let Some(&(tag, type_id)) = filtered_enumerators.get(&id) {
                    out.push(0x33);
                    out.extend(key.encode());
                    push_value(&mut out, tag, type_id);
                    out.extend([0x7d, 0x0d, 0xfa, loop_at]);
                }
            }
            0x3c => {
                let id = reader.word()?;
                filtered_enumerators.remove(&id);
                range_enumerators.remove(&id);
                if iterator_frames.last().map(|frame| frame.id) != Some(id) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "iterator destruction is not nested in creation order".into(),
                    });
                }
                out.extend(iterator_cleanup(
                    &iterator_frames,
                    iterator_frames.len() - 1,
                ));
                iterator_frames.pop();
            }
            0x1b => {
                let id = reader.word()?;
                let instructions = crate::bytecode::decode(&out).map_err(|error| LowerError {
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
                        &mut out,
                        &mut offsets,
                        &mut fixups,
                        step.offset,
                        1 + step.operands.len(),
                        &[],
                    );
                }
                out.push(if unit_step { 0xfc } else { 0xfe });
                let range_words = if unit_step { 2 } else { 3 };
                range_enumerators.insert(id, range_words);
                iterator_frames.push(IteratorFrame {
                    id,
                    range_words: Some(range_words),
                });
            }
            0x84 => {
                // AppendNoPush: `x += rhs` in statement position
                if reader.code.get(reader.at) == Some(&7) {
                    reader.byte()?;
                    if reorder_guarded_indexed_rhs(
                        &mut out,
                        code,
                        &mut offsets,
                        &mut fixups,
                        &mut safe.safe_skip_pop,
                        start,
                        &[0x34, 0xffe3, 0x34, 0xffd8, 0x45, 0xffe4],
                    ) {
                        continue;
                    }
                    let mut end = out.len();
                    let mut spans = Vec::new();
                    for _ in 0..3 {
                        let Some(at) = constructor_argument_start(&out[..end], 1).or_else(|| {
                            guarded_assignment_spans(&out[..end], code, &offsets, &fixups, start, 0)
                                .map(|(first, _)| first)
                        }) else {
                            break;
                        };
                        spans.push((at, end));
                        end = at;
                    }
                    spans.reverse();
                    if spans.len() != 3
                        || spans[..2].iter().any(|(at, end)| {
                            !crate::bytecode::decode(&out[*at..*end]).is_ok_and(|items| {
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
                        replacement.extend_from_slice(&out[at..end]);
                    }
                    replacement.extend([0x34, 0xffe3, 0x34, 0xffd8, 0x45, 0xffe4]);
                    let at = spans[0].0;
                    let old_len = out.len() - at;
                    replace_words(
                        &mut out,
                        &mut offsets,
                        &mut fixups,
                        at,
                        old_len,
                        &replacement,
                    );
                    continue;
                }
                out.push(0x45);
                let target = reference(&mut reader, ids)?;
                emit_tracked_reference(
                    &mut out,
                    &target,
                    &mut state.cached_world_owner,
                    &mut state.pending_world_ref,
                );
            }
            0x1a => {
                let target = reference(&mut reader, ids)?;
                out.push(0x45); // AugAdd stores expression result in eval cache.
                emit_tracked_reference(
                    &mut out,
                    &target,
                    &mut state.cached_world_owner,
                    &mut state.pending_world_ref,
                );
                out.push(0x13f); // PushEval
            }
            0x1f if reader.code.get(reader.at) != Some(&7) => {
                let target = reference(&mut reader, ids)?;
                let discard = reader.code.get(reader.at) == Some(&0x51)
                    && !fixups.iter().any(|fixup| fixup.target == reader.at as u32);
                if safe.pending_safe_aug_sub {
                    if !matches!(target, Variable::Field(_)) {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "safe augmented subtraction requires a field".into(),
                        });
                    }
                    out.push(0x143); // Restore cached receiver before AugSub.
                    safe.pending_safe_aug_sub = false;
                }
                out.push(0x46);
                emit_tracked_reference(
                    &mut out,
                    &target,
                    &mut state.cached_world_owner,
                    &mut state.pending_world_ref,
                );
                if discard {
                    offsets.insert(reader.at as u32, out.len() as u32);
                    reader.byte()?;
                } else {
                    out.push(0x13f); // PushEval exposes augmented expression result.
                }
            }
            0x0b | 0x17 | 0x39 | 0x33 | 0x2d | 0x29 | 0x6d | 0x6e | 0x61 | 0x1f => {
                // BYOND Aug* stores its result in the eval cache. Statement
                // position discards it; expression position pushes it.
                let indexed = reader.code.get(reader.at) == Some(&7);
                let target = if indexed {
                    reader.byte()?;
                    Variable::CacheIndex
                } else {
                    reference(&mut reader, ids)?
                };
                let discard = reader.code.get(reader.at) == Some(&0x51)
                    && !fixups.iter().any(|fixup| fixup.target == reader.at as u32);
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
                        &mut out,
                        code,
                        &mut offsets,
                        &mut fixups,
                        &mut safe.safe_skip_pop,
                        start,
                        &[0x34, 0xffe3, 0x34, 0xffd8, byond, 0xffe4],
                    )
                {
                    // The common result/discard handling follows below.
                } else if indexed {
                    let mut end = out.len();
                    let mut spans = Vec::new();
                    for _ in 0..3 {
                        let Some(at) = constructor_argument_start(&out[..end], 1).or_else(|| {
                            guarded_assignment_spans(&out[..end], code, &offsets, &fixups, start, 0)
                                .map(|(first, _)| first)
                        }) else {
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
                        replacement.extend_from_slice(&out[at..end]);
                    }
                    replacement.extend([0x34, 0xffe3, 0x34, 0xffd8, byond]);
                    replacement.extend(target.encode());
                    let old_len = out.len() - spans[0].0;
                    replace_words(
                        &mut out,
                        &mut offsets,
                        &mut fixups,
                        spans[0].0,
                        old_len,
                        &replacement,
                    );
                } else {
                    out.push(byond);
                    emit_tracked_reference(
                        &mut out,
                        &target,
                        &mut state.cached_world_owner,
                        &mut state.pending_world_ref,
                    );
                }
                if discard {
                    offsets.insert(reader.at as u32, out.len() as u32);
                    reader.byte()?;
                } else {
                    out.push(0x13f);
                }
            }
            0x56 => {
                if reader.code.get(reader.at) == Some(&7) {
                    reader.byte()?; // indexed reference
                                    // Both expressions already leave list/key on the stack.
                                    // Caching consumes them in place, including branch joins.
                    out.extend([0x34, 0xffe3, 0x34, 0xffd8]); // CacheKey, Cache
                    let statement = reader.code.get(reader.at) == Some(&0x51)
                        && !fixups.iter().any(|fixup| fixup.target == reader.at as u32);
                    out.extend([if statement { 0x66 } else { 0x63 }, 0xffe4]); // Inc/PostInc CacheIndex
                    if statement {
                        offsets.insert(reader.at as u32, out.len() as u32);
                        reader.byte()?;
                    }
                    continue;
                }
                let target = reference(&mut reader, ids)?;
                if reader.code.get(reader.at) == Some(&0x51)
                    && !fixups.iter().any(|fixup| fixup.target == reader.at as u32)
                {
                    out.push(0x66); // Inc in statement position
                    emit_tracked_reference(
                        &mut out,
                        &target,
                        &mut state.cached_world_owner,
                        &mut state.pending_world_ref,
                    );
                    offsets.insert(reader.at as u32, out.len() as u32);
                    reader.byte()?; // discard OpenDream's pushed old value
                } else {
                    out.push(0x63); // PostInc in expression position
                    emit_tracked_reference(
                        &mut out,
                        &target,
                        &mut state.cached_world_owner,
                        &mut state.pending_world_ref,
                    );
                }
            }
            0x57 => {
                if reader.code.get(reader.at) == Some(&7) {
                    reader.byte()?;
                    let at = constructor_argument_start(&out, 2).ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "indexed decrement has unknown list/key stack effects".into(),
                    })?;
                    if fixups.iter().any(|fixup| fixup.at >= at) {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "indexed decrement operand branches are unverified".into(),
                        });
                    }
                    out.extend([0x34, 0xffe3, 0x34, 0xffd8]);
                    let statement = reader.code.get(reader.at) == Some(&0x51)
                        && !fixups.iter().any(|fixup| fixup.target == reader.at as u32);
                    out.extend([if statement { 0x67 } else { 0x65 }, 0xffe4]);
                    if statement {
                        offsets.insert(reader.at as u32, out.len() as u32);
                        reader.byte()?;
                    }
                    continue;
                }
                let target = reference(&mut reader, ids)?;
                if reader.code.get(reader.at) == Some(&0x51)
                    && !fixups.iter().any(|fixup| fixup.target == reader.at as u32)
                {
                    out.push(0x67); // Dec in statement position
                    emit_tracked_reference(
                        &mut out,
                        &target,
                        &mut state.cached_world_owner,
                        &mut state.pending_world_ref,
                    );
                    offsets.insert(reader.at as u32, out.len() as u32);
                    reader.byte()?;
                } else {
                    out.push(0x65); // PostDec in expression position
                    emit_tracked_reference(
                        &mut out,
                        &target,
                        &mut state.cached_world_owner,
                        &mut state.pending_world_ref,
                    );
                }
            }
            0x62 | 0x63 => {
                if reader.code.get(reader.at) == Some(&7) {
                    reader.byte()?;
                    out.extend([
                        0x34,
                        0xffe3,
                        0x34,
                        0xffd8,
                        if op == 0x62 { 0x62 } else { 0x64 },
                        0xffe4,
                    ]);
                } else {
                    out.push(if op == 0x62 { 0x62 } else { 0x64 });
                    let target = reference(&mut reader, ids)?;
                    emit_tracked_reference(
                        &mut out,
                        &target,
                        &mut state.cached_world_owner,
                        &mut state.pending_world_ref,
                    );
                }
            }
            0x4e => {
                // OutputReference(Field) uses a world target placed earlier
                // on the stack. DreamMaker resolves the field on that target
                // before evaluating the output value.
                let at = reader.at;
                let kind = reader.byte()?;
                if kind == 7 {
                    // Indexed output uses the list value, key, and RHS on
                    // OpenDream's stack. Native output first constructs an
                    // Index receiver from the list/key pair.
                    let rhs_at = guarded_assignment_spans(&out, code, &offsets, &fixups, start, 0)
                        .map(|(first, _)| first)
                        .or_else(|| constructor_argument_start(&out, 1))
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "indexed output RHS has unknown stack effects".into(),
                        })?;
                    let key_at =
                        guarded_assignment_spans(&out[..rhs_at], code, &offsets, &fixups, start, 0)
                            .map(|(first, _)| first)
                            .or_else(|| constructor_argument_start(&out[..rhs_at], 1))
                            .ok_or_else(|| LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "indexed output key has unknown stack effects".into(),
                            })?;
                    let preceding = crate::bytecode::decode(&out)
                        .ok()
                        .and_then(|items| items.into_iter().rfind(|item| item.offset < key_at));
                    let list = if let Some(initializer) = preceding.filter(|item| {
                        item.opcode == 0x35 && matches!(item.operands.as_slice(), [65498, _])
                    }) {
                        out[initializer.offset] = 0x34;
                        let mut get = vec![0x33];
                        get.extend(initializer.operands);
                        get
                    } else {
                        let list_at = guarded_assignment_spans(
                            &out[..key_at],
                            code,
                            &offsets,
                            &fixups,
                            start,
                            0,
                        )
                        .map(|(first, _)| first)
                        .or_else(|| constructor_argument_start(&out[..key_at], 1))
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "indexed output receiver has unknown stack effects".into(),
                        })?;
                        let old_end = out.len();
                        let spans = [(list_at, key_at), (key_at, rhs_at), (rhs_at, old_end)];
                        if !closed_spans(&spans, &offsets, &fixups) {
                            return Err(LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "indexed output operands have nonlocal branches".into(),
                            });
                        }
                        let mut replacement = out[list_at..rhs_at].to_vec();
                        replacement.push(0xb0);
                        replacement.extend_from_slice(&out[rhs_at..]);
                        replacement.push(0x03);
                        let old_len = out.len() - list_at;
                        replace_closed_spans(
                            &mut out,
                            &mut offsets,
                            &mut fixups,
                            list_at,
                            old_len,
                            &replacement,
                            &[
                                ((list_at, key_at), list_at),
                                ((key_at, rhs_at), key_at),
                                ((rhs_at, old_end), rhs_at + 1),
                            ],
                        );
                        state.last_reference_push = None;
                        continue;
                    };
                    let old_end = out.len();
                    let spans = [(key_at, rhs_at), (rhs_at, old_end)];
                    if !closed_spans(&spans, &offsets, &fixups) {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "indexed output operands have nonlocal branches".into(),
                        });
                    }
                    let list_len = list.len();
                    let mut replacement = list;
                    replacement.extend_from_slice(&out[key_at..rhs_at]);
                    replacement.push(0xb0); // Index
                    replacement.extend_from_slice(&out[rhs_at..]);
                    replacement.push(0x03); // Output
                    let old_len = out.len() - key_at;
                    replace_closed_spans(
                        &mut out,
                        &mut offsets,
                        &mut fixups,
                        key_at,
                        old_len,
                        &replacement,
                        &[
                            ((key_at, rhs_at), key_at + list_len),
                            ((rhs_at, old_end), rhs_at + list_len + 1),
                        ],
                    );
                    state.last_reference_push = None;
                    continue;
                }
                if kind != 12 {
                    let output_opcode = if state.pending_output_run {
                        if kind != 1 {
                            return Err(LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "run() output requires a direct src receiver".into(),
                            });
                        }
                        state.pending_output_run = false;
                        0x09 // OutputRun
                    } else {
                        0x03 // Output
                    };
                    // OpenDream evaluates RHS before OutputReference(target),
                    // while DreamMaker evaluates the target before RHS.
                    if !matches!(kind, 1 | 3 | 5 | 8 | 9 | 10 | 13) {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: at,
                            reason: "OutputReference target needs a direct reference".into(),
                        });
                    }
                    reader.at = at;
                    let target = reference(&mut reader, ids)?;
                    let rhs_at = guarded_assignment_spans(&out, code, &offsets, &fixups, start, 0)
                        .map(|(first, _)| first)
                        .or_else(|| constructor_argument_start(&out, 1))
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::UnsupportedConstruct,
                            offset: start,
                            reason: "OutputReference RHS stack effects are unsupported".into(),
                        })?;
                    let mut get_target = vec![0x33];
                    get_target.extend(target.encode());
                    // A source label at the RHS expression enters the whole
                    // output statement, including this newly inserted receiver.
                    let entries: Vec<_> = offsets
                        .iter()
                        .filter_map(|(&byte, &word)| (word as usize == rhs_at).then_some(byte))
                        .collect();
                    replace_words(&mut out, &mut offsets, &mut fixups, rhs_at, 0, &get_target);
                    for entry in entries {
                        offsets.insert(entry, rhs_at as u32);
                    }
                    let format = crate::bytecode::decode(&out)
                        .ok()
                        .and_then(|items| {
                            items
                                .into_iter()
                                .rfind(|item| !matches!(item.opcode, 0x84 | 0x85))
                        })
                        .filter(|item| item.opcode == 0x02);
                    if let Some(format) = format.filter(|_| output_opcode == 0x03) {
                        out[format.offset] = 0x04; // Native OutputFormat.
                    } else {
                        out.push(output_opcode);
                    }
                    state.last_reference_push = None;
                    continue;
                }
                let field = mapped(ids.string(reader.word()?), start, "string")?;
                if let Some(world) = state.pending_world_ref.take() {
                    if world.world_cached_at_push {
                        out[world.at + 1] = field;
                    } else {
                        replace_words(
                            &mut out,
                            &mut offsets,
                            &mut fixups,
                            world.at,
                            2,
                            &[0x33, 0xffdc, 0xffe5, field],
                        );
                    }
                    state.cached_world_owner = !world.rhs_changed_cache;
                } else {
                    let rhs_at = guarded_assignment_spans(&out, code, &offsets, &fixups, start, 0)
                        .map(|(first, _)| first)
                        .or_else(|| constructor_argument_start(&out, 1))
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::UnsupportedConstruct,
                            offset: start,
                            reason: "field output RHS stack effects are unsupported".into(),
                        })?;
                    let owner_at =
                        guarded_assignment_spans(&out[..rhs_at], code, &offsets, &fixups, start, 0)
                            .map(|(first, _)| first)
                            .or_else(|| constructor_argument_start(&out[..rhs_at], 1))
                            .ok_or_else(|| LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "field output owner has unknown stack effects".into(),
                            })?;
                    let owner_items =
                        crate::bytecode::decode(&out[owner_at..rhs_at]).map_err(|error| {
                            LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: error.reason,
                            }
                        })?;
                    let direct = owner_items
                        .iter()
                        .filter(|item| !matches!(item.opcode, 0x84 | 0x85))
                        .count()
                        == 1
                        && owner_items.iter().any(|item| item.opcode == 0x33);
                    if !direct {
                        let old_end = out.len();
                        let spans = [(owner_at, rhs_at), (rhs_at, old_end)];
                        if !closed_spans(&spans, &offsets, &fixups) {
                            return Err(LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "field output operands have nonlocal branches".into(),
                            });
                        }
                        let mut receiver = vec![0x34];
                        receiver.extend(Variable::Cache.encode());
                        receiver.push(0x33);
                        receiver.extend(Variable::Field(field).encode());
                        let added = receiver.len();
                        insert_between_closed_spans(
                            &mut out,
                            &mut offsets,
                            &mut fixups,
                            rhs_at,
                            &receiver,
                            &[
                                ((owner_at, rhs_at), owner_at),
                                ((rhs_at, old_end), rhs_at + added),
                            ],
                        );
                        state.cached_world_owner = false;
                    } else {
                        let instructions =
                            crate::bytecode::decode(&out[..rhs_at]).map_err(|error| {
                                LowerError {
                                    kind: LowerErrorKind::MalformedControlFlow,
                                    offset: start,
                                    reason: format!(
                                        "cannot inspect field output owner: {}",
                                        error.reason
                                    ),
                                }
                            })?;
                        let owner_instruction = instructions
                            .iter()
                            .rev()
                            .find(|item| !matches!(item.opcode, 0x84 | 0x85))
                            .filter(|item| item.opcode == 0x33)
                            .ok_or_else(|| LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "field output requires direct owner reference".into(),
                            })?;
                        let (owner, _) =
                            Variable::decode(&owner_instruction.operands).map_err(|error| {
                                LowerError {
                                    kind: LowerErrorKind::MalformedControlFlow,
                                    offset: start,
                                    reason: format!(
                                        "field output owner cannot be decoded: {}",
                                        error.reason
                                    ),
                                }
                            })?;
                        let mut target = vec![0x33];
                        target.extend(
                            Variable::SetCache(Box::new(owner), Box::new(Variable::Field(field)))
                                .encode(),
                        );
                        replace_words(
                            &mut out,
                            &mut offsets,
                            &mut fixups,
                            owner_instruction.offset,
                            1 + owner_instruction.operands.len(),
                            &target,
                        );
                        state.cached_world_owner = false;
                    }
                }
                state.last_reference_push = None;
                // DreamMaker has a fused output opcode for interpolated
                // strings. The operands are identical to Format, and the
                // fused form consumes the output target as well.
                if follows_format {
                    let format = crate::bytecode::decode(&out)
                        .map_err(|error| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: error.reason,
                        })?
                        .into_iter()
                        .rev()
                        .find(|item| !matches!(item.opcode, 0x84 | 0x85))
                        .filter(|item| item.opcode == 0x02)
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "formatted output lacks its formatting instruction".into(),
                        })?;
                    out[format.offset] = 0x04;
                } else {
                    out.push(0x03);
                }
            }
            0x6a | 0xaa => {
                // DereferenceCall(name, argument mode, count)
                let target = if op == 0xaa {
                    Some(reader.word()?)
                } else {
                    None
                };
                let old_field = reader.word()?;
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
                let mode = reader.byte()?;
                let argc = reader.word()?;
                if let Some(receiver) = pending_receivers.pop() {
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
                        out.extend([0xc8, argc / 2]);
                    }
                    let direct_receiver = matches!(receiver, PendingReceiver::NativeReference(_));
                    let safe_receiver = matches!(
                        receiver,
                        PendingReceiver::SafeCached
                            | PendingReceiver::NativeCachedReference(_, true)
                    );
                    let chained_safe_index = safe_receiver
                        .then(|| {
                            if reader.code.get(reader.at) != Some(&0x65) {
                                return None;
                            }
                            let target = u32::from_le_bytes(
                                reader
                                    .code
                                    .get(reader.at + 1..reader.at + 5)?
                                    .try_into()
                                    .ok()?,
                            );
                            if reader.code.get((target as usize).checked_sub(1)?) != Some(&0x69) {
                                return None;
                            }
                            let pure = argc == 0
                                || (mode == 1
                                    && constructor_argument_start(&out, argc as usize)
                                        .and_then(|at| crate::bytecode::decode(&out[at..]).ok())
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
                                fixups.iter().rposition(|fixup| fixup.target == target)
                            {
                                *safe.safe_skip_pop.entry(index).or_default() += 1;
                            }
                            for index in &safe.safe_chain_fixups {
                                *safe.safe_skip_pop.entry(*index).or_default() += 1;
                            }
                            safe.nested_safe_pop = Some((
                                target,
                                safe.nested_safe_pop.map_or(1, |(_, count)| count + 1),
                            ));
                        } else {
                            out.push(0x143);
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
                        direct_receiver && world_flow.pop_is_unshared(&reader, &fixups);
                    out.push(if statement_call { 0x2a } else { 0x29 });
                    out.extend(variable.encode());
                    out.push(if mode == 2 || mode == 3 { 0xffff } else { argc });
                    finish_native_statement_call(
                        &mut reader,
                        &mut out,
                        &mut offsets,
                        statement_call,
                    );
                    state.last_reference_push = None;
                    state.cached_world_owner = false;
                    if let Some(pending) = &mut state.pending_world_ref {
                        pending.rhs_changed_cache = true;
                    }
                    continue;
                }
                let mut owner_from_stack = None;
                if matches!(mode, 1..=3) {
                    if let Some(owner_at) = constructor_argument_start(&out, argc as usize + 1) {
                        if let Ok(instructions) = crate::bytecode::decode(&out[owner_at..]) {
                            if let Some(first) = instructions.first() {
                                if first.opcode == 0x33
                                    && first.offset == 0
                                    && (if argc == 0 {
                                        Some(out.len())
                                    } else {
                                        constructor_argument_start(&out, argc as usize)
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
                    if let Some(arg_at) = constructor_argument_start(&out, 1) {
                        if let Ok(items) = crate::bytecode::decode(&out[..arg_at]) {
                            if let [.., aug, eval] = items.as_slice() {
                                if aug.opcode == 0x45 && eval.opcode == 0x13f {
                                    if let Ok((Variable::Local(local), used)) =
                                        Variable::decode(&aug.operands)
                                    {
                                        if used == aug.operands.len() {
                                            replace_words(
                                                &mut out,
                                                &mut offsets,
                                                &mut fixups,
                                                eval.offset,
                                                1,
                                                &[],
                                            );
                                            owner_from_stack =
                                                Some((out.len(), Variable::Local(local)));
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
                    if let Some(arg_at) = constructor_argument_start(&out, argc as usize) {
                        if let Ok(items) = crate::bytecode::decode(&out[..arg_at]) {
                            if let Some(set) = items.last().filter(|item| item.opcode == 0x35) {
                                if let Ok((Variable::Local(local), used)) =
                                    Variable::decode(&set.operands)
                                {
                                    if used == set.operands.len() {
                                        out[set.offset] = 0x34;
                                        owner_from_stack =
                                            Some((out.len(), Variable::Local(local)));
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
                        let items = crate::bytecode::decode(&out).ok()?;
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
                                constructor_argument_start(&out[..first_value_end], 1)?;
                        }
                        let jump = fixups.iter().rev().find(|fixup| {
                            reader.code.get(fixup.source) == Some(&0x0e)
                                && offsets.get(&fixup.target).copied()
                                    == Some(first_value_end as u32)
                                && fixup.at < first_value_end
                        })?;
                        let else_at = jump.at + 1;
                        let branch = fixups.iter().find(|fixup| {
                            reader.code.get(fixup.source) == Some(&0x0c)
                                && offsets.get(&fixup.target).copied() == Some(else_at as u32)
                                && fixup.source < jump.source
                        })?;
                        let condition_start = *offsets.get(&(branch.source as u32))? as usize;
                        let condition_at = items
                            .iter()
                            .find(|item| {
                                item.offset >= condition_start
                                    && !matches!(item.opcode, 0x84 | 0x85)
                            })?
                            .offset;
                        if out.get(condition_at) != Some(&0x0d) {
                            return None;
                        }
                        let first_value_at = constructor_argument_start(&out[..condition_at], 1)?;
                        let prefix = crate::bytecode::decode(&out[..first_value_at]).ok()?;
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
                    if let Some(arg_at) = constructor_argument_start(&out, 1) {
                        if let Ok(instructions) = crate::bytecode::decode(&out[..arg_at]) {
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
                                            out[last.offset] = 0x34;
                                            owner_from_stack = Some((out.len(), variable));
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
                    if let Ok(instructions) = crate::bytecode::decode(&out) {
                        if let Some(last) = instructions
                            .iter()
                            .rev()
                            .find(|item| !matches!(item.opcode, 0x84 | 0x85))
                        {
                            if last.opcode == 0x35 {
                                if let Ok((variable, _)) = Variable::decode(&last.operands) {
                                    out[last.offset] = 0x34; // SetVar then reload via Call reference
                                    owner_from_stack = Some((out.len(), variable));
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
                    0 | 1 if argc == 0 => Some(out.len()),
                    1 if argc <= 255 => constructor_argument_start(&out, argc as usize),
                    2 if (2..=510).contains(&argc) && argc % 2 == 0 => {
                        constructor_argument_start(&out, argc as usize)
                    }
                    3 if argc == 1 => constructor_argument_start(&out, 1),
                    _ => None,
                };
                if let Some(args_at) = argument_span {
                    let joined_owner = fixups.iter().any(|fixup| {
                        offsets.get(&fixup.target).copied() == Some(args_at as u32)
                            && fixup.at < owner_from_stack.as_ref().map_or(args_at, |(at, _)| *at)
                    });
                    if owner_from_stack.is_none() || joined_owner {
                        // Paired computed/conditional receiver: preserve the
                        // receiver cache across argument evaluation. A branch
                        // join must execute this common cache store in both arms.
                        let joins: Vec<_> = offsets
                            .iter()
                            .filter_map(|(key, value)| (*value == args_at as u32).then_some(*key))
                            .collect();
                        replace_words(
                            &mut out,
                            &mut offsets,
                            &mut fixups,
                            args_at,
                            0,
                            &[0x34, 0xffd8, 0x142],
                        );
                        for key in joins {
                            offsets.insert(key, args_at as u32);
                        }
                        if mode == 2 {
                            out.extend([0xc8, argc / 2]);
                        }
                        out.extend([
                            0x143,
                            // Native computed receiver calls retain an
                            // executable Pop, releasing their result there.
                            0x29,
                        ]);
                        out.extend(selector.clone().encode());
                        out.push(if mode == 2 || mode == 3 { 0xffff } else { argc });
                        state.last_reference_push = None;
                        state.cached_world_owner = false;
                        if let Some(pending) = &mut state.pending_world_ref {
                            pending.rhs_changed_cache = true;
                        }
                        continue;
                    }
                }
                let (at, owner) = owner_from_stack
                    .or_else(|| state.last_reference_push.take())
                    .ok_or_else(|| LowerError {
            kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: format!(
                        "DereferenceCall requires a direct owner reference (mode {mode}, argc {argc}, tail {:?})",
                        crate::bytecode::decode(&out).ok().map(|items| items.into_iter().rev().take(10).collect::<Vec<_>>())
                    ),
                })?;
                if mode == 3 && argc == 1 && at == out.len() && !converted_mode3_owner {
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
                    && crate::bytecode::decode(&out[..at])
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
                if at < out.len() {
                    replace_words(&mut out, &mut offsets, &mut fixups, at, old_len, &[]);
                }
                if mode == 2 {
                    out.extend([0xc8, argc / 2]);
                }
                let discard_result = world_flow.pop_is_unshared(&reader, &fixups);
                out.push(if discard_result { 0x2a } else { 0x29 });
                out.extend(if reuse_cache {
                    selector.clone().encode()
                } else {
                    Variable::SetCache(Box::new(owner), Box::new(selector.clone())).encode()
                });
                out.push(if mode == 2 || mode == 3 { 0xffff } else { argc });
                finish_native_statement_call(&mut reader, &mut out, &mut offsets, discard_result);
                state.last_reference_push = None;
                state.cached_world_owner = false;
                if let Some(pending) = &mut state.pending_world_ref {
                    pending.rhs_changed_cache = true;
                }
            }
            0x0a => CallLowering {
                code,
                reader: &mut reader,
                ids,
                start,
                out: &mut out,
                offsets: &mut offsets,
                fixups: &mut fixups,
                world_flow,
                state: &mut state,
                pending_view_range_iterator: &mut pending_view_range_iterator,
                pending_orange_iterator: &mut pending_orange_iterator,
                is_initializer,
            }
            .lower()?,
            0x87 => {
                // PushNRefs: an int32 count followed by references
                let count = reader.word()?;
                if count as usize > reader.code.len().saturating_sub(reader.at) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "PushNRefs count exceeds available operands".into(),
                    });
                }
                let mut references = Vec::with_capacity(count as usize);
                for _ in 0..count {
                    references.push(reference(&mut reader, ids)?);
                }
                if count == 2 && reader.code.get(reader.at) == Some(&0x36) {
                    // OpenDream pushes item then list. BYOND IsIn expects
                    // list then item. Reordering direct references is safe.
                    let item = references.remove(0);
                    let list = references.remove(0);
                    offsets.insert(reader.at as u32, out.len() as u32);
                    reader.byte()?; // IsInList
                    out.push(0x33);
                    out.extend(list.encode());
                    out.push(0x33);
                    out.extend(item.encode());
                    out.extend([0xa9, 5, 0x36]);
                    state.last_reference_push = None;
                    continue;
                }
                if count == 3 && reader.code.get(reader.at..reader.at + 2) == Some(&[0x85, 7]) {
                    // OpenDream list assignment uses list, key, value;
                    // DreamMaker's ListSet consumes value, list, key.
                    let list = references.remove(0);
                    let key = references.remove(0);
                    let value = references.remove(0);
                    offsets.insert(reader.at as u32, out.len() as u32);
                    reader.byte()?; // AssignNoPush
                    reader.byte()?; // indexed reference
                    for var in [value, list, key] {
                        out.push(0x33);
                        out.extend(var.encode());
                    }
                    out.push(0x7c);
                    state.last_reference_push = None;
                    continue;
                }
                for var in references {
                    let at = out.len();
                    out.push(0x33);
                    if var == Variable::World {
                        world_flow.reused |= state.cached_world_owner;
                        state.pending_world_ref = Some(PendingWorld {
                            at,
                            world_cached_at_push: state.cached_world_owner,
                            rhs_changed_cache: false,
                        });
                    } else if matches!(var, Variable::SetCache(_, _)) {
                        state.cached_world_owner = false;
                        if let Some(pending) = &mut state.pending_world_ref {
                            pending.rhs_changed_cache = true;
                        }
                    }
                    state.last_reference_push = Some((at, var.clone()));
                    out.extend(var.encode());
                }
                state.last_push_nrefs = Some((reader.at, count));
            }
            0x36 => {
                // Mixed-width references in `item in list` cannot use the
                // compact PushNRefs lookahead above. The preceding two GetVar
                // instructions still identify the pure item/list operands.
                let instructions = crate::bytecode::decode(&out).map_err(|error| LowerError {
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
                        constructor_argument_start(&out, 1).ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "IsInList computed list has unknown stack effects".into(),
                        })?;
                    let item_at =
                        constructor_argument_start(&out[..list_at], 1).ok_or_else(|| {
                            LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason:
                                    "IsInList item before computed list has unknown stack effects"
                                        .into(),
                            }
                        })?;
                    let mut replacement = out[list_at..].to_vec();
                    replacement.extend_from_slice(&out[item_at..list_at]);
                    replacement.extend([0xa9, 5]);
                    if reader.code.get(reader.at) != Some(&0x0c)
                        || fixups
                            .iter()
                            .any(|fixup| fixup.target as usize == reader.at)
                    {
                        replacement.push(0x36);
                    }
                    let old_len = out.len() - item_at;
                    replace_words(
                        &mut out,
                        &mut offsets,
                        &mut fixups,
                        item_at,
                        old_len,
                        &replacement,
                    );
                    state.last_reference_push = None;
                    continue;
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
                        constructor_argument_start(&out[..list_at], 1).ok_or_else(|| {
                            LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "IsInList item expression has unknown stack effects".into(),
                            }
                        })?;
                    let mut computed = out[list_at..].to_vec();
                    computed.extend_from_slice(&out[item_at..list_at]);
                    computed.extend([0xa9, 5]);
                    if reader.code.get(reader.at) != Some(&0x0c)
                        || fixups
                            .iter()
                            .any(|fixup| fixup.target as usize == reader.at)
                    {
                        computed.push(0x36);
                    }
                    let old_len = out.len() - item_at;
                    replace_words(
                        &mut out,
                        &mut offsets,
                        &mut fixups,
                        item_at,
                        old_len,
                        &computed,
                    );
                    state.last_reference_push = None;
                    continue;
                }
                replacement.extend([0xa9, 5]);
                // A short-circuit predecessor reaches the condition with a
                // boolean value, so the join must Test that value on every
                // edge rather than rely on the final producer's comparison flag.
                let condition_is_join = fixups
                    .iter()
                    .any(|fixup| fixup.target as usize == reader.at);
                if reader.code.get(reader.at) != Some(&0x0c) || condition_is_join {
                    replacement.push(0x36);
                }
                let at = pair[0].offset;
                let old_len = out.len() - at;
                replace_words(
                    &mut out,
                    &mut offsets,
                    &mut fixups,
                    at,
                    old_len,
                    &replacement,
                );
                state.last_reference_push = None;
            }
            0x88 => {
                // PushNFloats
                let count = reader.word()?;
                if count as usize > reader.code.len().saturating_sub(reader.at) / 4 {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "PushNFloats count exceeds available operands".into(),
                    });
                }
                if count == 2
                    && reader.code.get(reader.at + 8) == Some(&0x5b)
                    && state.last_reference_push.is_some()
                {
                    let (value_at, value) =
                        state.last_reference_push.take().ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "IsInRange requires a direct value reference".into(),
                        })?;
                    replace_words(
                        &mut out,
                        &mut offsets,
                        &mut fixups,
                        value_at,
                        1 + value.encode().len(),
                        &[],
                    );
                    for _ in 0..2 {
                        let bits = reader.word()?;
                        out.extend([0x60, 0x2a, bits >> 16, bits & 0xffff]);
                    }
                    offsets.insert(reader.at as u32, out.len() as u32);
                    reader.byte()?; // IsInRange
                    out.push(0x33);
                    out.extend(value.encode());
                    out.extend([0xa9, 11, 0x36]);
                    continue;
                }
                if count == 2 && reader.code.get(reader.at + 8) == Some(&0x05) {
                    // OpenDream emits each range as two float pushes and
                    // SwitchCaseRange; BYOND stores bounds in SwitchRange.
                    let switch_at = out.len();
                    let mut ranges = Vec::new();
                    let mut exact = Vec::new();
                    loop {
                        let lo = reader.word()?;
                        let hi = reader.word()?;
                        if reader.byte()? != 0x05 {
                            return Err(LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "switch range lacks SwitchCaseRange".into(),
                            });
                        }
                        let target = reader.word()?;
                        ranges.push((lo, hi, target));
                        // OpenDream may interleave exact and range cases in
                        // source order. Native SwitchRange keeps separate
                        // range and exact tables, so collect both until Pop.
                        loop {
                            if reader.code.get(reader.at) == Some(&0x8d) {
                                offsets.insert(reader.at as u32, switch_at as u32);
                                reader.byte()?;
                                let bits = reader.word()?;
                                let target = reader.word()?;
                                exact.push((
                                    Value {
                                        tag_word: 0x2a,
                                        data_word: bits >> 16,
                                        extra_word: Some(bits & 0xffff),
                                    },
                                    target,
                                ));
                            } else if reader.code.get(reader.at) == Some(&0x93) {
                                offsets.insert(reader.at as u32, switch_at as u32);
                                reader.byte()?;
                                let id =
                                    mapped(ids.string(reader.word()?), start, "switch string")?;
                                let target = reader.word()?;
                                exact.push((
                                    Value {
                                        tag_word: 6 | ((id >> 16) << 8),
                                        data_word: id & 0xffff,
                                        extra_word: None,
                                    },
                                    target,
                                ));
                            } else if reader.code.get(reader.at..reader.at + 2)
                                == Some(&[0x11, 0x32])
                            {
                                offsets.insert(reader.at as u32, switch_at as u32);
                                reader.at += 2;
                                let target = reader.word()?;
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
                        if reader.code.get(reader.at..reader.at + 5) == Some(&[0x88, 2, 0, 0, 0])
                            && reader.code.get(reader.at + 13) == Some(&0x05)
                        {
                            offsets.insert(reader.at as u32, switch_at as u32);
                            reader.at += 5;
                            continue;
                        }
                        break;
                    }
                    if reader.code.get(reader.at) != Some(&0x51) {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "switch range lacks Pop default".into(),
                        });
                    }
                    offsets.insert(reader.at as u32, switch_at as u32);
                    reader.byte()?;
                    let default = if reader.code.get(reader.at) == Some(&0x0e)
                        && !authored_control_jump(ids, reader.code, reader.at)
                    {
                        offsets.insert(reader.at as u32, switch_at as u32);
                        reader.byte()?;
                        reader.word()?
                    } else {
                        // A terminal `else` follows the removed switch
                        // selector directly, without an intermediate jump.
                        reader.at as u32
                    };
                    out.extend([0x7a, ranges.len() as u32]);
                    for (lo, hi, target) in ranges {
                        out.extend([0x2a, lo >> 16, lo & 0xffff, 0x2a, hi >> 16, hi & 0xffff]);
                        let at = out.len();
                        out.push(0);
                        fixups.push(Fixup {
                            at,
                            target,
                            source: start,
                        });
                    }
                    out.push(exact.len() as u32);
                    for (value, target) in exact {
                        out.extend(value.encode());
                        let at = out.len();
                        out.push(0);
                        fixups.push(Fixup {
                            at,
                            target,
                            source: start,
                        });
                    }
                    let at = out.len();
                    out.push(0);
                    fixups.push(Fixup {
                        at,
                        target: default,
                        source: start,
                    });
                    continue;
                }
                for _ in 0..count {
                    let bits = reader.word()?;
                    out.extend([0x60, 0x2a, bits >> 16, bits & 0xffff]);
                }
            }
            0x8f..=0x92 => {
                // OpenDream's compact list constructors carry the same
                // operands as their corresponding PushN opcode plus CreateList.
                let count = reader.word()?;
                if (count as usize) > reader.code.len() - reader.at {
                    return Err(LowerError {
                        kind: LowerErrorKind::TruncatedOperand,
                        offset: start,
                        reason: "truncated compact list values".into(),
                    });
                }
                for _ in 0..count {
                    match op {
                        0x8f => {
                            let bits = reader.word()?;
                            out.extend([0x60, 0x2a, bits >> 16, bits & 0xffff]);
                        }
                        0x90 => push_value(
                            &mut out,
                            6,
                            mapped(ids.string(reader.word()?), start, "string")?,
                        ),
                        0x91 => {
                            out.push(0x33);
                            let target = reference(&mut reader, ids)?;
                            emit_tracked_reference(
                                &mut out,
                                &target,
                                &mut state.cached_world_owner,
                                &mut state.pending_world_ref,
                            );
                        }
                        0x92 => push_value(
                            &mut out,
                            12,
                            mapped(ids.resource(reader.word()?), start, "resource")?,
                        ),
                        _ => unreachable!(),
                    }
                }
                out.extend([0x1a, count]);
            }
            0x8c => {
                // PushNStrings
                let count = reader.word()?;
                if count as usize > reader.code.len().saturating_sub(reader.at) / 4 {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "PushNStrings count exceeds available operands".into(),
                    });
                }
                for _ in 0..count {
                    push_value(
                        &mut out,
                        6,
                        mapped(ids.string(reader.word()?), start, "string")?,
                    );
                }
            }
            0x8e => {
                // Packed PushStringFloat pairs.
                let count = reader.word()?;
                if count > 255 {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "PushNOfStringFloats count exceeds 255".into(),
                    });
                }
                for _ in 0..count {
                    push_value(
                        &mut out,
                        6,
                        mapped(ids.string(reader.word()?), start, "string")?,
                    );
                    let bits = reader.word()?;
                    out.extend([0x60, 0x2a, bits >> 16, bits & 0xffff]);
                }
            }
            0x89 => {
                // PushNResources
                let count = reader.word()?;
                if count as usize > reader.code.len().saturating_sub(reader.at) / 4 {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "PushNResources count exceeds available operands".into(),
                    });
                }
                for _ in 0..count {
                    push_value(
                        &mut out,
                        12,
                        mapped(ids.resource(reader.word()?), start, "resource")?,
                    );
                }
            }
            0x09 => {
                if ids.native_store_reload(start) {
                    if !matches!(reader.code.get(reader.at), Some(8 | 9)) {
                        return Err(LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "native store/reload annotation requires a local or argument"
                                .into(),
                        });
                    }
                    let target = reference(&mut reader, ids)?;
                    out.push(0x34);
                    out.extend(target.encode());
                    let get_at = out.len();
                    out.push(0x33);
                    out.extend(target.encode());
                    state.last_reference_push = Some((get_at, target));
                    store_reload_boundaries.insert(start as u32);
                    continue;
                }
                if pending_indexed_logical
                    .last()
                    .is_some_and(|(target, _, _)| {
                        (reader.code.get(reader.at) == Some(&7)
                            && *target == (reader.at + 1) as u32)
                            || (reader.code.get(reader.at) == Some(&12)
                                && *target == (reader.at + 5) as u32)
                    })
                {
                    if reader.code.get(reader.at) == Some(&7) {
                        reader.byte()?;
                    } else {
                        let field = reference(&mut reader, ids)?;
                        let (_, _, setter) = pending_indexed_logical.last().unwrap();
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
                    let (_, source, variable) = pending_indexed_logical.pop().unwrap();
                    let frame_at = fixups
                        .iter()
                        .find(|fixup| fixup.source == source)
                        .unwrap()
                        .at
                        + 1;
                    let rhs = crate::bytecode::decode(&out[frame_at + 1..]).map_err(|error| {
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
                        replace_words(&mut out, &mut offsets, &mut fixups, frame_at, 1, &[]);
                    } else {
                        out.push(0x143);
                    }
                    let discard = reader.code.get(reader.at) == Some(&0x51)
                        && !fixups.iter().any(|fixup| {
                            fixup.target == reader.at as u32
                                && branch_retains_discarded_value(fixup, code, &out)
                        });
                    out.push(if discard { 0x34 } else { 0x35 });
                    out.extend(variable.encode());
                    if computed_safe_logical.remove(&source) {
                        let cache_join = u32::MAX - source as u32;
                        offsets.insert(cache_join, out.len() as u32);
                        fixups
                            .iter_mut()
                            .find(|fixup| fixup.source == source)
                            .unwrap()
                            .target = cache_join;
                        out.push(0x143);
                        offsets.insert(reader.at as u32, out.len() as u32);
                    }
                    if discard {
                        offsets.insert(reader.at as u32, out.len() as u32);
                        reader.byte()?;
                    }
                    if safe_logical_continuations.remove(&source) {
                        if let Some((at, discard, body)) = safe.pending_safe_lvalue_stack.pop() {
                            safe.pending_safe_lvalue_at = Some((at, discard));
                            safe.pending_safe_lvalue_body = body;
                        }
                    }
                    continue;
                }
                if reader.code.get(reader.at) == Some(&7) {
                    reader.byte()?;
                    let mut end = out.len();
                    let mut spans = Vec::new();
                    for _ in 0..3 {
                        let at = constructor_argument_start(&out[..end], 1).ok_or_else(|| {
                            LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: "indexed assignment expression has unknown stack effects"
                                    .into(),
                            }
                        })?;
                        spans.push((at, end));
                        end = at;
                    }
                    spans.reverse();
                    let direct_targets = spans[..2].iter().all(|(at, end)| {
                        crate::bytecode::decode(&out[*at..*end])
                            .is_ok_and(|items| items.len() == 1 && items[0].opcode == 0x33)
                    });
                    let nonbranching_value = crate::bytecode::decode(&out[spans[2].0..spans[2].1])
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
                    let mut replacement = out[spans[2].0..spans[2].1].to_vec();
                    replacement.push(0x13c); // retain assigned value for expression result
                    for (at, end) in [spans[0], spans[1]] {
                        replacement.extend_from_slice(&out[at..end]);
                    }
                    replacement.push(0x7c);
                    let old_len = out.len() - spans[0].0;
                    replace_words(
                        &mut out,
                        &mut offsets,
                        &mut fixups,
                        spans[0].0,
                        old_len,
                        &replacement,
                    );
                    continue;
                }
                let target = reference(&mut reader, ids)?;
                let discard = reader.code.get(reader.at) == Some(&0x51)
                    && !fixups.iter().any(|fixup| {
                        fixup.target == reader.at as u32
                            && branch_retains_discarded_value(fixup, code, &out)
                    })
                    && source_info
                        .is_none_or(|events| events.iter().all(|event| event.offset != reader.at));
                if let Variable::Field(field) = target {
                    let rhs_at = constructor_argument_start(&out, 1).ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "field assignment expression value has unknown stack effects"
                            .into(),
                    })?;
                    let owner_at =
                        constructor_argument_start(&out[..rhs_at], 1).ok_or_else(|| {
                            LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason:
                                    "field assignment expression receiver has unknown stack effects"
                                        .into(),
                            }
                        })?;
                    let owner_items =
                        crate::bytecode::decode(&out[owner_at..rhs_at]).map_err(|error| {
                            LowerError {
                                kind: LowerErrorKind::MalformedControlFlow,
                                offset: start,
                                reason: error.reason,
                            }
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
                    let old_end = out.len();
                    let rhs_length = old_end - rhs_at;
                    let computed_owner = direct_owner.is_none();
                    let mut replacement = out[rhs_at..old_end].to_vec();
                    let retained_value = usize::from(computed_owner && !discard);
                    if let Some(owner) = direct_owner {
                        replacement.push(if discard { 0x34 } else { 0x35 });
                        replacement.extend(append_field(owner, field).encode());
                    } else {
                        if !discard {
                            replacement.push(0x13c);
                        }
                        replacement.extend_from_slice(&out[owner_at..rhs_at]);
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
                    let previous_offsets: Vec<_> = offsets
                        .iter()
                        .filter(|(_, &position)| (owner_at..old_end).contains(&(position as usize)))
                        .map(|(&source, &position)| (source, position))
                        .collect();
                    let previous_fixups = fixups.iter().map(|fixup| fixup.at).collect::<Vec<_>>();
                    replace_words(
                        &mut out,
                        &mut offsets,
                        &mut fixups,
                        owner_at,
                        old_end - owner_at,
                        &replacement,
                    );
                    for (key, old) in previous_offsets {
                        if old as usize >= owner_at && (old as usize) < old_end {
                            offsets.insert(key, moved(old as usize) as u32);
                        }
                    }
                    for (fixup, old) in fixups.iter_mut().zip(previous_fixups) {
                        if old >= owner_at && old < old_end {
                            fixup.at = moved(old);
                        }
                    }
                    offsets.insert(start as u32, (owner_at + rhs_length) as u32);
                    if discard {
                        offsets.insert(reader.at as u32, out.len() as u32);
                        reader.byte()?;
                    }
                    state.last_reference_push = None;
                    state.cached_world_owner = false;
                    continue;
                }
                out.push(if discard { 0x34 } else { 0x35 });
                emit_tracked_reference(
                    &mut out,
                    &target,
                    &mut state.cached_world_owner,
                    &mut state.pending_world_ref,
                );
                if discard {
                    offsets.insert(reader.at as u32, out.len() as u32);
                    reader.byte()?;
                }
            }
            0x85 => {
                if (AssignmentLowering {
                    code,
                    reader: &mut reader,
                    ids,
                    start,
                    out: &mut out,
                    offsets: &mut offsets,
                    fixups: &mut fixups,
                    state: &mut state,
                    safe: &mut safe,
                    is_initializer,
                })
                .lower()?
                {
                    continue;
                }
            }
            0x97 => {
                let value = reference(&mut reader, ids)?;
                if value == Variable::Dot {
                    out.push(0); // End returns the procedure's implicit Dot value.
                } else {
                    out.push(0x33);
                    out.extend(value.encode());
                    out.push(0x12);
                }
            }
            op if emit_stack_operation(
                op,
                reader.code.get(reader.at),
                reader.at,
                &fixups,
                &mut out,
            ) => {}
            0x81 => {
                reorder_log_arguments(&mut out, reader.code, &mut offsets, &mut fixups, start)?;
                out.push(0x32);
            }
            0x20 => {
                out.push(0x0c);
                if ids.native_delete_src(start) {
                    out.push(0x00); // Native del(src) terminates this proc path.
                }
            }
            0x1c => {
                // `source >> destination` reads into the destination ref.
                let source = if reader.code.get(reader.at) == Some(&7) {
                    reader.byte()?;
                    None
                } else {
                    Some(reference(&mut reader, ids)?)
                };
                let destination = if reader.code.get(reader.at) == Some(&7) {
                    reader.byte()?;
                    None
                } else {
                    Some(reference(&mut reader, ids)?)
                };
                let source_at = if source.is_none() {
                    constructor_argument_start(&out, 2).ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "indexed read source has unknown stack effects".into(),
                    })?
                } else {
                    out.len()
                };
                let destination_at = if destination.is_none() {
                    constructor_argument_start(&out[..source_at], 2).ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "indexed read destination has unknown stack effects".into(),
                    })?
                } else if matches!(destination, Some(Variable::Field(_))) {
                    constructor_argument_start(&out[..source_at], 1).ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "read field destination has unknown owner stack effects".into(),
                    })?
                } else {
                    source_at
                };
                if fixups
                    .iter()
                    .any(|fixup| fixup.at >= destination_at && fixup.at < out.len())
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
                    replacement.extend_from_slice(&out[source_at..]);
                    replacement.push(0xb0); // Index: savefile slot, not ListGet
                }
                replacement.push(0xaf);
                if let Some(destination) = destination {
                    if let Variable::Field(field) = destination {
                        let owner = crate::bytecode::decode(&out[destination_at..source_at])
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
                    replacement.extend_from_slice(&out[destination_at..source_at]);
                    replacement.push(0x7c); // ListSet consumes the Read result
                }
                let old_len = out.len() - destination_at;
                replace_words(
                    &mut out,
                    &mut offsets,
                    &mut fixups,
                    destination_at,
                    old_len,
                    &replacement,
                );
                state.last_reference_push = None;
            }
            0x0d => out.extend([0x17c, reader.word()?]), // paired alist -> NewAList
            0x3d => out.push(0xab),                      // Browse with options already on stack
            0x3e => out.push(0x27),                      // BrowseResource
            0x3f => out.push(0x10b),                     // OutputControl
            0x44 => out.push(0x07),                      // Link
            0x46 => out.push(0x08),                      // OutputFtp
            0x45 => {
                // OpenDream pushes four prompt arguments in reverse order,
                // followed by a selection list. DreamMaker consumes normal
                // argument order and includes PromptCheck after Input.
                let exported_types = reader.word()?;
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
                let instructions = crate::bytecode::decode(&out).map_err(|error| LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: format!("cannot inspect prompt arguments: {}", error.reason),
                })?;
                let null_selection = instructions
                    .last()
                    .is_some_and(|item| item.opcode == 0x60 && item.operands == [0, 0]);
                let selection_choice = authored_choices || !null_selection;
                if null_selection || selection_choice {
                    let mut end = out.len();
                    let mut spans = Vec::new();
                    for _ in 0..5 {
                        let Some(at) = guarded_assignment_spans(
                            &out[..end],
                            code,
                            &offsets,
                            &fixups,
                            start,
                            0,
                        )
                        .map(|(first, _)| first)
                        .or_else(|| constructor_argument_start(&out[..end], 1)) else {
                            break;
                        };
                        spans.push((at, end));
                        end = at;
                    }
                    if spans.len() == 5 {
                        spans.reverse();
                        world_flow.separate_reordered_arguments(&spans, &offsets, code.len());
                        let at = spans[0].0;
                        let computed = instructions
                            .iter()
                            .any(|item| item.offset >= at && !matches!(item.opcode, 0x33 | 0x60));
                        if computed
                            && fixups.iter().all(|fixup| {
                                if fixup.at < at {
                                    return offsets
                                        .get(&fixup.target)
                                        .is_none_or(|target| *target as usize <= at);
                                }
                                spans.iter().any(|(begin, end)| {
                                    fixup.at >= *begin
                                        && fixup.at < *end
                                        && offsets.get(&fixup.target).is_some_and(|target| {
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
                                if out[spans[4].0..spans[4].1] == [0x60, 0, 0] {
                                    replacement.push(0x33);
                                    replacement.extend(Variable::Null.encode());
                                } else {
                                    replacement.extend_from_slice(&out[spans[4].0..spans[4].1]);
                                }
                            }
                            for index in (0..4).rev() {
                                let (begin, end) = spans[index];
                                if (index == 1 || index == 4) && out[begin..end] == [0x60, 0, 0] {
                                    replacement.push(0x33);
                                    replacement.extend(Variable::Null.encode());
                                } else {
                                    replacement.extend_from_slice(&out[begin..end]);
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
                                    && out[begin..end] == [0x60, 0, 0]
                                {
                                    2
                                } else {
                                    end - begin
                                };
                            }
                            let original_offsets = moved_offset_snapshot(&offsets, &fixups, &moved);
                            remap_closed_spans(
                                &original_offsets,
                                &mut offsets,
                                &mut fixups,
                                &moved,
                            );
                            out.truncate(at);
                            out.extend(replacement);
                            state.cached_world_owner = false;
                            state.pending_world_ref = None;
                            state.last_reference_push = None;
                            continue;
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
                world_flow.separate_reordered_arguments(&spans, &offsets, code.len());
                state.cached_world_owner = false;
                state.pending_world_ref = None;
                state.last_reference_push = None;
                let at = arguments[0].offset;
                let old_len = out.len() - at;
                replace_words(
                    &mut out,
                    &mut offsets,
                    &mut fixups,
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
                let cached_fields = crate::bytecode::decode(&out).ok().and_then(|items| {
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
                        &mut out,
                        &mut offsets,
                        &mut fixups,
                        at,
                        1 + reference.encode().len(),
                        &[],
                    );
                    out.push(0x142);
                    pending_receivers
                        .push(PendingReceiver::NativeCachedReference(reference, guarded));
                    state.last_reference_push = None;
                    state.cached_world_owner = false;
                    continue;
                }
                let assigned_owner = crate::bytecode::decode(&out).ok().and_then(|items| {
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
                let direct = if !fixups.iter().any(|fixup| fixup.target == start as u32) {
                    assigned_owner.or_else(|| {
                        constructor_argument_start(&out, 1).and_then(|at| {
                            let items: Vec<_> = crate::bytecode::decode(&out[at..])
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
                        out[at] = 0x34;
                    } else {
                        replace_words(&mut out, &mut offsets, &mut fixups, at, old_len, &[]);
                    }
                    pending_receivers.push(PendingReceiver::NativeReference(reference));
                } else {
                    out.extend([0x34, 0xffd8, 0x142]);
                    pending_receivers.push(PendingReceiver::NativeCached);
                }
                state.last_reference_push = None;
                state.cached_world_owner = false;
            }
            0xa6 => {
                // Native indexed assignment expression preserves its RHS value.
                out.push(0x13c);
                state.last_reference_push = None;
            }
            0xa5 => {
                // Pinned compiler has evaluated value, list and key in native order.
                out.push(0x7c);
                state.last_reference_push = None;
                state.cached_world_owner = false;
            }
            0xa4 => {
                // Pinned compiler evaluates the membership list before item.
                out.extend([0xa9, 5]);
                if reader.code.get(reader.at) != Some(&0x0c)
                    || fixups
                        .iter()
                        .any(|fixup| fixup.target as usize == reader.at)
                {
                    out.push(0x36);
                }
                state.last_reference_push = None;
            }
            0xa2 => {
                // Pinned exporter has already distinguished numeric positional
                // keys from explicit null keys, preserving expression order.
                let count = reader.word()?;
                out.extend([0xc8, count]);
                state.last_reference_push = None;
            }
            0xa1 => {
                // Pinned exporter preserves DreamMaker's type-before-arguments
                // evaluation order and native numeric positional keys.
                let mode = reader.byte()?;
                let count = reader.word()?;
                match mode {
                    0 | 1 if count <= 255 && (mode == 1 || count == 0) => {
                        out.extend([0x01, count]);
                    }
                    2 if (2..=510).contains(&count) && count % 2 == 0 => {
                        out.extend([0xc8, count / 2, 0xcf]);
                    }
                    3 if count == 1 => out.push(0xcf),
                    _ => return Err(LowerError {
            kind: LowerErrorKind::UnsupportedConstruct,
                        offset: start,
                        reason: format!("native-ordered constructor argument mode {mode} count {count} is unsupported"),
                    }),
                }
                state.last_reference_push = None;
                state.cached_world_owner = false;
            }
            0xa0 => {
                // Pinned exporter extension: targets and arguments are
                // already evaluated in native order, with explicit arity.
                let is_ext = reader.byte()?;
                let targets = reader.byte()?;
                let mode = reader.byte()?;
                let count = reader.word()?;
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
                        out.extend([native, count]);
                    }
                    2 | 3
                        if mode == 3 && count == 1
                            || mode == 2 && (2..=510).contains(&count) && count % 2 == 0 =>
                    {
                        if mode == 2 {
                            out.extend([0xc8, count / 2]);
                        }
                        out.push(match (is_ext, targets) {
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
                state.last_reference_push = None;
                state.cached_world_owner = false;
            }
            0x9d | 0x9e => {
                // OpenDream evaluates arguments before the call target(s).
                // The pinned compiler emits 0x9D for call_ext and 0x9E for call.
                // DreamMaker evaluates target(s) before arguments.
                let is_ext = op == 0x9d;
                let mode = reader.byte()?;
                let argc = reader.word()? as usize;
                if !(mode == 0 && argc == 0 || mode == 1 && argc <= 255 || mode == 3 && argc == 1) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "CallStatement supports positional or arglist arguments only"
                            .into(),
                    });
                }
                let instructions = crate::bytecode::decode(&out).map_err(|error| LowerError {
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
                        let name = out[name_at..name_end].to_vec();
                        let arguments_at = if argc == 0 {
                            name_at
                        } else {
                            constructor_argument_start(&out[..name_at], argc).ok_or_else(|| {
                                LowerError {
                                    kind: LowerErrorKind::UnsupportedConstruct,
                                    offset: start,
                                    reason:
                                        "CallStatement arguments have unsupported stack effects"
                                            .into(),
                                }
                            })?
                        };
                        let argument_words = out[arguments_at..name_at].to_vec();
                        replace_words(
                            &mut out,
                            &mut offsets,
                            &mut fixups,
                            arguments_at,
                            name_end - arguments_at,
                            &[],
                        );
                        out.extend(name);
                        out.extend(argument_words);
                        out.extend([if is_ext { 0x116 } else { 0xb5 }, argc as u32]);
                        continue;
                    }
                }
                let last = instructions.last().ok_or_else(|| LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "CallStatement lacks a target".into(),
                })?;
                let grouped_two_targets = state.last_push_nrefs == Some((start, argc as u32 + 2));
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
                let old_len = out.len() - at;
                replace_words(
                    &mut out,
                    &mut offsets,
                    &mut fixups,
                    at,
                    old_len,
                    &replacement,
                );
            }
            0x74 => {
                if let Some((base_at, chain_at)) = guarded_assign_into.remove(&start) {
                    let target = reference(&mut reader, ids)?;
                    let rhs_at = guarded_assignment_spans(&out, code, &offsets, &fixups, start, 1)
                        .or_else(|| {
                            guarded_assignment_spans(&out, code, &offsets, &fixups, start, 0)
                        })
                        .map(|(_, rhs)| rhs)
                        .or_else(|| {
                            constructor_argument_start(&out[chain_at..], 1).map(|at| chain_at + at)
                        })
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "guarded AssignInto RHS has unknown stack effects".into(),
                        })?;
                    let end = out.len();
                    let items =
                        crate::bytecode::decode(&out[chain_at..rhs_at]).map_err(|error| {
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
                    let nested_guard = guarded_assign_into_nested.remove(&start);
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
                    let mut replacement = out[rhs_at..end].to_vec();
                    replacement.extend_from_slice(&out[base_at..chain_at]);
                    let destination =
                        if let (Some(owner), Variable::Field(field)) = (direct, &target) {
                            for item in items
                                .iter()
                                .filter(|item| matches!(item.opcode, 0x84 | 0x85))
                            {
                                replacement.extend_from_slice(
                                    &out[chain_at + item.offset
                                        ..chain_at + item.offset + 1 + item.operands.len()],
                                );
                            }
                            append_field(owner, *field)
                        } else {
                            if computed {
                                replacement.push(0x142);
                                replacement.extend_from_slice(&out[chain_at..rhs_at]);
                                replacement.extend([0x34, 0xffd8, 0x143]);
                            }
                            target
                        };
                    let action_at = base_at + replacement.len();
                    let rhs_join = u32::MAX - start as u32;
                    let owner_join = rhs_join - 1;
                    let safe_rhs_join = rhs_join - 2;
                    let cache_unwind =
                        crate::bytecode::decode(&out[rhs_at..end])
                            .ok()
                            .map_or(0, |items| {
                                items
                                    .iter()
                                    .rev()
                                    .take_while(|item| item.opcode == 0x143)
                                    .count()
                            });
                    let moved_offsets: Vec<_> = offsets
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
                    for (index, fixup) in fixups.iter_mut().enumerate() {
                        if fixup.at >= base_at && fixup.at < end {
                            if fixup.at >= rhs_at && fixup.target == start as u32 {
                                fixup.target = if fixup.at > 0 && out[fixup.at - 1] == 0x13d {
                                    let saved = cache_frame_depth(&out[rhs_at..fixup.at - 1]);
                                    safe.safe_skip_pop
                                        .entry(index)
                                        .or_insert(cache_unwind.saturating_sub(saved) as u32);
                                    safe_rhs_join
                                } else {
                                    rhs_join
                                };
                            } else if fixup.at >= chain_at
                                && fixup.at < rhs_at
                                && (fixup.target == start as u32
                                    || offsets.get(&fixup.target).copied() == Some(rhs_at as u32))
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
                        &mut out,
                        &mut offsets,
                        &mut fixups,
                        base_at,
                        end - base_at,
                        &replacement,
                    );
                    offsets.extend(moved_offsets);
                    offsets.insert(rhs_join, (base_at + rhs_len) as u32);
                    offsets.insert(safe_rhs_join, (base_at + rhs_len - cache_unwind) as u32);
                    offsets.insert(owner_join, (action_at - usize::from(computed) * 3) as u32);
                    offsets.insert(start as u32, action_at as u32);
                    for (index, at) in moved_fixups {
                        fixups[index].at = at;
                    }
                    out.push(0x15a);
                    out.extend(destination.encode());
                    if reader.code.get(reader.at) == Some(&0x51)
                        && !fixups.iter().any(|fixup| fixup.target == reader.at as u32)
                    {
                        offsets.insert(reader.at as u32, out.len() as u32);
                        reader.byte()?;
                    } else {
                        out.push(0x13f);
                    }
                    state.last_reference_push = None;
                    state.cached_world_owner = false;
                    continue;
                }
                let indexed = reader.code.get(reader.at) == Some(&7);
                let mut target = if indexed {
                    reader.byte()?;
                    Variable::CacheIndex
                } else {
                    reference(&mut reader, ids)?
                };
                let destination_count = if indexed {
                    2
                } else {
                    usize::from(matches!(target, Variable::Field(_)))
                };
                let spans = guarded_assignment_spans(
                    &out,
                    code,
                    &offsets,
                    &fixups,
                    start,
                    destination_count,
                );
                let value_at = spans
                    .map(|(_, value)| value)
                    .or_else(|| constructor_argument_start(&out, 1))
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "AssignInto value has unknown stack effects".into(),
                    })?;
                let owner_at = if let Some((owner, _)) = spans {
                    Some(owner)
                } else if indexed {
                    constructor_argument_start(&out[..value_at], 2)
                } else if matches!(target, Variable::Field(_)) {
                    constructor_argument_start(&out[..value_at], 1)
                } else {
                    None
                };
                if indexed || matches!(target, Variable::Field(_)) {
                    let owner_at = owner_at.ok_or_else(|| LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "AssignInto owner has unknown stack effects".into(),
                    })?;
                    let owner = out[owner_at..value_at].to_vec();
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
                    let end = out.len();
                    let rhs_len = end - value_at;
                    let mut replacement = out[value_at..].to_vec();
                    let direct_owner = direct.is_some() && matches!(target, Variable::Field(_));
                    if let (Some(owner), Variable::Field(field)) = (direct, &target) {
                        target = append_field(owner, *field);
                        for item in items
                            .iter()
                            .filter(|item| matches!(item.opcode, 0x84 | 0x85))
                        {
                            replacement.extend_from_slice(
                                &out[owner_at + item.offset
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
                    let old_len = out.len() - owner_at;
                    let rhs_join = u32::MAX - start as u32;
                    let owner_join = rhs_join - 1;
                    let safe_rhs_join = rhs_join - 2;
                    let cache_unwind =
                        crate::bytecode::decode(&out[value_at..end])
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
                    let moved_offsets: Vec<_> = offsets
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
                    for (index, fixup) in fixups.iter_mut().enumerate() {
                        if fixup.at >= owner_at && fixup.at < end {
                            if fixup.at >= value_at && fixup.target == start as u32 {
                                fixup.target = if fixup.at > 0 && out[fixup.at - 1] == 0x13d {
                                    let saved = cache_frame_depth(&out[value_at..fixup.at - 1]);
                                    safe.safe_skip_pop
                                        .entry(index)
                                        .or_insert(cache_unwind.saturating_sub(saved) as u32);
                                    safe_rhs_join
                                } else {
                                    rhs_join
                                };
                            } else if fixup.at < value_at
                                && (fixup.target == start as u32
                                    || offsets.get(&fixup.target).copied() == Some(value_at as u32))
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
                        &mut out,
                        &mut offsets,
                        &mut fixups,
                        owner_at,
                        old_len,
                        &replacement,
                    );
                    offsets.extend(moved_offsets);
                    offsets.insert(rhs_join, (owner_at + rhs_len) as u32);
                    offsets.insert(safe_rhs_join, (owner_at + rhs_len - cache_unwind) as u32);
                    offsets.insert(owner_join, owner_end as u32);
                    offsets.insert(start as u32, action_at as u32);
                    for (index, at) in moved_fixups {
                        fixups[index].at = at;
                    }
                }
                out.push(0x15a);
                emit_tracked_reference(
                    &mut out,
                    &target,
                    &mut state.cached_world_owner,
                    &mut state.pending_world_ref,
                );
                if reader.code.get(reader.at) == Some(&0x51)
                    && !fixups.iter().any(|fixup| fixup.target == reader.at as u32)
                {
                    offsets.insert(reader.at as u32, out.len() as u32);
                    reader.byte()?;
                } else {
                    out.push(0x13f);
                }
                state.last_reference_push = None;
                state.cached_world_owner = false;
            }
            0x4f => out.push(0x03), // Output(target, value)
            0x75 => out.push(0x90), // GetStep(start, direction)
            0x4d => {
                let target = reader.word()?;
                spawn_targets.push(target);
                out.extend([0x25, 0]);
                fixups.push(Fixup {
                    at: out.len() - 1,
                    target,
                    source: start,
                });
            }
            0x65 => {
                if (SafeGuardLowering {
                    code,
                    reader: &mut reader,
                    ids,
                    start,
                    out: &mut out,
                    offsets: &mut offsets,
                    fixups: &mut fixups,
                    state: &mut state,
                    safe: &mut safe,
                    pending_receivers: &mut pending_receivers,
                    guarded_assign_into: &mut guarded_assign_into,
                    guarded_assign_into_nested: &mut guarded_assign_into_nested,
                })
                .lower()?
                {
                    continue;
                }
            }
            0x64 => {
                // A safe lvalue in `for(a?.field in list)` has two OD
                // enumeration paths. Native BYOND shares IterNext and Jz,
                // skipping SetVar when the receiver is null.
                let no_assign = reader.word()?;
                if ids.native_delete_clear(start) {
                    out.extend([0x13e, 0]);
                    fixups.push(Fixup {
                        at: out.len() - 1,
                        target: no_assign,
                        source: start,
                    });
                    if reader.code.get(reader.at) != Some(&0x85) {
                        out.extend([0x142, 0x33, 0xffd8]);
                        delete_clear_cache_end = Some(no_assign);
                    }
                    state.last_reference_push = None;
                    continue;
                }
                let instructions = crate::bytecode::decode(&out).map_err(|error| LowerError {
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
                let old = out[owner.offset..owner.offset + 1 + owner.operands.len()].to_vec();
                let mut with_iter = vec![0x53];
                with_iter.extend(old);
                replace_words(
                    &mut out,
                    &mut offsets,
                    &mut fixups,
                    owner.offset,
                    1 + owner.operands.len(),
                    &with_iter,
                );
                if reader.code.get(reader.at) != Some(&0x3b) {
                    // An indexed lvalue evaluates its key only on the non-null
                    // path. Keep the shared IterNext before the null guard.
                    out.extend([0x13e, 0]);
                    fixups.push(Fixup {
                        at: out.len() - 1,
                        target: no_assign,
                        source: start,
                    });
                    out.extend([0x142, 0x33, 0xffd8]);
                    safe_index_enumerator = Some(no_assign);
                    state.last_reference_push = None;
                    continue;
                }
                reader.byte()?; // Enumerate
                let id = reader.word()?;
                let destination = reference(&mut reader, ids)?;
                let exit = reader.word()?;
                if !matches!(destination, Variable::Field(_)) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "safe iterator requires direct field destination".into(),
                    });
                }
                if reader.byte()? != 0x0e {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "safe iterator lacks join Jump".into(),
                    });
                }
                let body = reader.word()?;
                if reader.at as u32 != no_assign || reader.byte()? != 0x72 || reader.word()? != id {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "safe iterator lacks matching EnumerateNoAssign".into(),
                    });
                }
                if reader.word()? != exit || reader.at as u32 != body {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "safe iterator branch targets differ".into(),
                    });
                }
                out.extend([0x13e, 0]);
                let null_fixup = out.len() - 1;
                out.push(0x34);
                out.extend(destination.encode());
                let jz_at = out.len() as u32;
                out[null_fixup] = jz_at;
                offsets.insert(no_assign, jz_at);
                out.extend([0x11, 0]);
                fixups.push(Fixup {
                    at: out.len() - 1,
                    target: exit,
                    source: start,
                });
                continue;
            }
            0x66 | 0x67 => {
                // `x ||= y` and `x &&= y`: test the current reference and
                // skip assignment when it already determines the result.
                let indexed = reader.code.get(reader.at) == Some(&7);
                let mut variable = if indexed {
                    reader.byte()?;
                    Variable::CacheIndex
                } else {
                    reference(&mut reader, ids)?
                };
                let target = reader.word()?;
                let field_owned = matches!(variable, Variable::Field(_));
                if field_owned {
                    let safe_cached = safe.pending_safe_lvalue_at.is_some();
                    if safe_cached {
                        if let Some(body_at) = safe.pending_safe_lvalue_body.take() {
                            let items = crate::bytecode::decode(&out[body_at..]).ok();
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
                                    &mut out,
                                    &mut offsets,
                                    &mut fixups,
                                    at,
                                    1 + owner.encode().len(),
                                    &[],
                                );
                            } else {
                                // Native computed guarded logical owners retain
                                // the base frame until the logical join.
                                out.extend([0x34, 0xffd8]);
                                computed_safe_logical.insert(start);
                            }
                        }
                        if !computed_safe_logical.contains(&start) {
                            out.push(0x143);
                        }
                        safe.pending_safe_lvalue_at = None;
                        safe_logical_continuations.insert(start);
                    }
                    let direct_owner = (!safe_cached)
                        .then(|| {
                            crate::bytecode::decode(&out).ok().and_then(|items| {
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
                    state.last_reference_push = None;
                    if let Some((at, owner)) = direct_owner {
                        let length = 1 + owner.encode().len();
                        replace_words(&mut out, &mut offsets, &mut fixups, at, length, &[]);
                        let Variable::Field(field) = variable else {
                            unreachable!()
                        };
                        variable = append_field(owner, field);
                    } else if !safe_cached {
                        constructor_argument_start(&out, 1).ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "logical field receiver has unknown stack effects".into(),
                        })?;
                        out.extend([0x34, 0xffd8]);
                    }
                    state.cached_world_owner = false;
                }
                if indexed {
                    out.extend([0x34, 0xffe3, 0x34, 0xffd8]);
                }
                out.push(0x33);
                out.extend(variable.encode());
                let discard = reader.code.get(target as usize) == Some(&0x51)
                    && !fixups.iter().any(|fixup| {
                        fixup.target == target && branch_retains_discarded_value(fixup, code, &out)
                    });
                if discard {
                    out.push(0x0d);
                }
                out.extend([
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
                fixups.push(Fixup {
                    at: out.len() - 1,
                    target,
                    source: start,
                });
                if indexed || field_owned {
                    out.push(0x142);
                    pending_indexed_logical.push((target, start, variable));
                }
            }
            0x6f | 0x70 => {
                if pending_try.is_empty() {
                    catch_local_base = None;
                    catches_emitted = 0;
                }
                let catch_target = reader.word()?;
                let source_local = (op == 0x6f && reader.code.get(reader.at) == Some(&9))
                    .then(|| reader.code.get(reader.at + 1).copied().map(usize::from))
                    .flatten();
                let destination = if op == 0x6f {
                    Some(reference(&mut reader, ids)?)
                } else {
                    None
                };
                if let Some(Variable::Local(slot)) = &destination {
                    catch_local_base = Some(catch_local_base.map_or(*slot, |base| base.min(*slot)));
                }
                let try_at = out.len() + 1;
                out.extend([0x12c, 0]);
                pending_try.push(TryFrame {
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
                } = pending_try.pop().ok_or_else(|| LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "EndTry lacks matching Try".into(),
                })?;
                try_regions.push((source_start, start));
                let end_target = if reader.code.get(reader.at) == Some(&0x0e) {
                    offsets.insert(reader.at as u32, out.len() as u32);
                    reader.byte()?;
                    reader.word()?
                } else if reader.at as u32 == catch_target {
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
                if reader.at as u32 != catch_target {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "Try catch label is not after EndTry Jump".into(),
                    });
                }
                out.extend([0x12e, 0]);
                fixups.push(Fixup {
                    at: out.len() - 1,
                    target: end_target,
                    source: start,
                });
                out[try_at] = out.len() as u32;
                if let Some(destination) = destination {
                    let destination = if reader.remap_locals {
                        if let (Some(source_slot), Variable::Local(_), Some(base)) =
                            (source_local, &destination, catch_local_base)
                        {
                            let native_slot = base + catches_emitted;
                            catches_emitted += 1;
                            *reader.local_slots.get_mut(source_slot).ok_or_else(|| {
                                LowerError {
                                    kind: LowerErrorKind::MalformedControlFlow,
                                    offset: start,
                                    reason: "catch local slot is inactive".into(),
                                }
                            })? = native_slot;
                            Variable::Local(native_slot)
                        } else {
                            destination
                        }
                    } else {
                        destination
                    };
                    out.push(0x34);
                    out.extend(destination.encode());
                } else {
                    out.push(0x51); // discard exception value
                }
                state.cached_world_owner = false;
            }
            0x5a => out.push(0x12d), // Throw
            0x8b => {
                let target_ref = reference(&mut reader, ids)?;
                let target = reader.word()?;
                out.push(0x33);
                out.extend(target_ref.encode());
                let (branch, target) = if ids.native_do_while_condition(start) {
                    let (jump, body) = read_do_while_backedge(&mut reader, start, target)?;
                    offsets.insert(jump as u32, (out.len() + 1) as u32);
                    (0xf9, body)
                } else {
                    (0x11, target)
                };
                out.extend([0x0d, branch, 0]);
                fixups.push(Fixup {
                    at: out.len() - 1,
                    target,
                    source: start,
                });
            }
            0x51 => out.push(0x51), // Pop
            0x10 => out.push(0x12), // Return
            0x22 => {
                out.extend([0x1a, reader.word()?]);
            } // CreateList
            0x30 => {
                let count = reader.word()?;
                if count == 0 || count > 255 {
                    return Err(LowerError {
                        kind: LowerErrorKind::UnsupportedConstruct,
                        offset: start,
                        reason: "multidimensional list dimension count is unsupported".into(),
                    });
                }
                let args_at = constructor_argument_start(&out, count as usize)
                    .or_else(|| {
                        guarded_assignment_spans(
                            &out,
                            code,
                            &offsets,
                            &fixups,
                            start,
                            count as usize - 1,
                        )
                        .map(|(first, _)| first)
                    })
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::UnsupportedConstruct,
                        offset: start,
                        reason: "multidimensional list sizes have unsupported stack effects".into(),
                    })?;
                if count == 1 {
                    // DreamMaker emits EmptyList for a one-dimensional list
                    // whose size is computed at runtime.
                    out.push(0x19);
                    continue;
                }
                replace_words(
                    &mut out,
                    &mut offsets,
                    &mut fixups,
                    args_at,
                    0,
                    &[0x60, 40, 0],
                );
                out.extend([0x01, count]);
            }
            0x54 | 0x55 => {
                let count = reader.word()? as usize;
                PickLowering {
                    code,
                    start,
                    out: &mut out,
                    offsets: &mut offsets,
                    fixups: &mut fixups,
                    world_flow: &mut *world_flow,
                    state: &mut state,
                    probability_regions: &mut probability_regions,
                }
                .lower(op == 0x55, count)?;
            }
            0x5b => {
                // OD pushes value, lower, upper; native IsIn range expects
                // lower, upper, value and then reads the membership flag.
                let upper_at = guarded_assignment_spans(&out, code, &offsets, &fixups, start, 0)
                    .map(|(first, _)| first)
                    .or_else(|| constructor_argument_start(&out, 1))
                    .ok_or_else(|| LowerError {
                        kind: LowerErrorKind::UnsupportedConstruct,
                        offset: start,
                        reason: "IsInRange upper bound has unsupported stack effects".into(),
                    })?;
                let lower_at =
                    guarded_assignment_spans(&out[..upper_at], code, &offsets, &fixups, start, 0)
                        .map(|(first, _)| first)
                        .or_else(|| constructor_argument_start(&out[..upper_at], 1))
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::UnsupportedConstruct,
                            offset: start,
                            reason: "IsInRange lower bound has unsupported stack effects".into(),
                        })?;
                let value_at =
                    guarded_assignment_spans(&out[..lower_at], code, &offsets, &fixups, start, 0)
                        .map(|(first, _)| first)
                        .or_else(|| constructor_argument_start(&out[..lower_at], 1))
                        .ok_or_else(|| LowerError {
                            kind: LowerErrorKind::UnsupportedConstruct,
                            offset: start,
                            reason: "IsInRange value has unsupported stack effects".into(),
                        })?;
                let old_end = out.len();
                let spans = [
                    (value_at, lower_at),
                    (lower_at, upper_at),
                    (upper_at, old_end),
                ];
                if !closed_spans(&spans, &offsets, &fixups) {
                    return Err(LowerError {
                        kind: LowerErrorKind::MalformedControlFlow,
                        offset: start,
                        reason: "IsInRange operands have nonlocal branches".into(),
                    });
                }
                world_flow.separate_reordered_arguments(&spans, &offsets, code.len());
                state.cached_world_owner = false;
                state.pending_world_ref = None;
                state.last_reference_push = None;
                let moved = [
                    ((lower_at, upper_at), value_at),
                    ((upper_at, old_end), value_at + upper_at - lower_at),
                    ((value_at, lower_at), value_at + old_end - lower_at),
                ];
                let mut reordered = out[lower_at..upper_at].to_vec();
                reordered.extend_from_slice(&out[upper_at..]);
                reordered.extend_from_slice(&out[value_at..lower_at]);
                let old_len = out.len() - value_at;
                replace_closed_spans(
                    &mut out,
                    &mut offsets,
                    &mut fixups,
                    value_at,
                    old_len,
                    &reordered,
                    &moved,
                );
                out.extend([0xa9, 11, 0x36]);
            }
            0x1e => {
                let count = reader.word()?;
                let entry_words = (count as usize).checked_mul(2).ok_or_else(|| LowerError {
                    kind: LowerErrorKind::MalformedControlFlow,
                    offset: start,
                    reason: "associative list entry count overflow".into(),
                })?;
                let mut end = out.len();
                let mut entries = Vec::with_capacity(entry_words);
                for _ in 0..entry_words {
                    let at =
                        constructor_argument_start(&out[..end], 1).ok_or_else(|| LowerError {
                            kind: LowerErrorKind::MalformedControlFlow,
                            offset: start,
                            reason: "associative list entry has unknown stack effects".into(),
                        })?;
                    entries.push((at, end));
                    end = at;
                }
                entries.reverse();
                for index in (0..count as usize).rev() {
                    let (key_at, key_end) = entries[index * 2];
                    if out[key_at..key_end] == [0x60, 0, 0] {
                        replace_words(
                            &mut out,
                            &mut offsets,
                            &mut fixups,
                            key_at,
                            3,
                            &[0x50, index as u32 + 1],
                        );
                    }
                }
                out.extend([0xc8, count]);
            } // CreateAssociativeList
            0x0e | 0x0c | 0x15 | 0x2f => {
                let target = reader.word()?;
                if op == 0x0c {
                    // DreamMaker equality leaves a comparison flag that needs
                    // Pop; relational comparisons require Test before Jz.
                    let last_opcode = crate::bytecode::decode(&out).ok().and_then(|instructions| {
                        instructions
                            .iter()
                            .rev()
                            .find(|item| !matches!(item.opcode, 0x84 | 0x85))
                            .map(|item| item.opcode)
                    });
                    let last_uses_flag = last_opcode
                        .is_some_and(|opcode| matches!(opcode, 0xa9 | 0x14..=0x17 | 0x16c | 0x16d));
                    if !last_uses_flag {
                        out.push(if matches!(last_opcode, Some(0x37 | 0x71)) {
                            0x51
                        } else {
                            0x0d
                        });
                    }
                }
                let do_while = op == 0x0c && ids.native_do_while_condition(start);
                let target = if do_while {
                    let (jump, body) = read_do_while_backedge(&mut reader, start, target)?;
                    offsets.insert(jump as u32, out.len() as u32);
                    body
                } else {
                    target
                };
                let byond = if do_while {
                    0xf9
                } else {
                    match op {
                        0x0e if (target as usize) <= start
                            || ids.native_continue(start).unwrap_or_else(|| {
                                is_simple_continue_tail(code, start, target)
                            }) =>
                        {
                            0xf8
                        }
                        0x0e => 0x0f,
                        0x0c => 0x11,
                        0x15 => 0xb3,
                        _ => 0xb2,
                    }
                };
                out.extend([byond, 0]);
                fixups.push(Fixup {
                    at: out.len() - 1,
                    target,
                    source: start,
                });
            }
            _ => {
                return Err(LowerError {
                    kind: LowerErrorKind::UnsupportedConstruct,
                    offset: start,
                    reason: format!("OpenDream opcode {op:#04x} has no verified BYOND lowering"),
                })
            }
        }
    }
    if !pending_indexed_logical.is_empty() {
        return Err(LowerError {
            kind: LowerErrorKind::MalformedControlFlow,
            offset: code.len(),
            reason: "indexed logical reference lacks its matching assignment".into(),
        });
    }
    if !pending_receivers.is_empty() {
        return Err(LowerError {
            kind: LowerErrorKind::MalformedControlFlow,
            offset: code.len(),
            reason: "native cached receiver lacks method call".into(),
        });
    }
    if !pending_try.is_empty() {
        return Err(LowerError {
            kind: LowerErrorKind::MalformedControlFlow,
            offset: code.len(),
            reason: "Try lacks matching EndTry".into(),
        });
    }
    for offset in ids.native_store_reload_offsets() {
        if !store_reload_boundaries.contains(offset) {
            return Err(LowerError {
                kind: LowerErrorKind::MalformedControlFlow,
                offset: *offset as usize,
                reason:
                    "native store/reload offset is not a marked assignment instruction boundary"
                        .into(),
            });
        }
    }
    let delete_clears = offsets
        .iter()
        .filter_map(|(source, word)| {
            ids.native_delete_clear(*source as usize)
                .then_some(*word as usize)
        })
        .collect();
    retain_frozen_root_cache(
        &mut out,
        &mut offsets,
        &mut fixups,
        &delete_clears,
        &probability_regions,
    );
    for offset in ids
        .native_initial_reference_offsets()
        .iter()
        .chain(ids.native_is_saved_reference_offsets())
    {
        if !offsets.contains_key(&(*offset as u32)) || code.get(*offset) != Some(&0x06) {
            return Err(LowerError {
                kind: LowerErrorKind::MalformedControlFlow,
                offset: *offset,
                reason:
                    "native reference modifier offset is not a reference-load instruction boundary"
                        .into(),
            });
        }
    }
    offsets.insert(code.len() as u32, out.len() as u32);
    iterator_states.insert(code.len(), iterator_frames);
    if let Some((_, count)) = safe
        .nested_safe_pop
        .filter(|(target, _)| *target == code.len() as u32)
    {
        out.extend(std::iter::repeat_n(0x143, count as usize));
    }
    // Branches to an enclosing loop can bypass one or more DestroyEnumerator
    // instructions (labelled break/continue and goto). Unwind only that edge.
    let mut trampolines = Vec::new();
    world_flow.targets.extend(
        fixups
            .iter()
            .map(|fixup| fixup.target)
            .filter(|target| *target as usize <= code.len()),
    );
    restore_try_branch_exits(&mut out, code, &fixups, &try_regions);
    // Source branch provenance survives optimizer removal of unreachable loop
    // tails. Native protected continue/break handlers also inspect target-1,
    // so a continue to the first protected word cannot use ordinary JmpLoop.
    for fixup in &fixups {
        let Some(opcode) = out.get_mut(fixup.at.wrapping_sub(1)) else {
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
    for (index, fixup) in fixups.into_iter().enumerate() {
        let target = *offsets.get(&fixup.target).ok_or_else(|| LowerError {
            kind: LowerErrorKind::MalformedControlFlow,
            offset: fixup.source,
            reason: format!(
                "branch target {} is not an instruction boundary",
                fixup.target
            ),
        })? + safe.safe_skip_pop.get(&index).copied().unwrap_or(0);
        let source_state = iterator_states
            .range(..=fixup.source)
            .next_back()
            .map(|(_, frames)| frames.as_slice())
            .unwrap_or(&[]);
        let target_state = if fixup.target as usize > code.len() {
            // A virtual label joins a reordered native expression within the
            // current scope. Its large ID is not a later OpenDream byte offset.
            source_state
        } else {
            iterator_states
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
            out[fixup.at] = target;
        } else {
            let branch_opcode = out[fixup.at - 1];
            if matches!(branch_opcode, 0x12e | 0x12f) {
                // Iterator cleanup must precede the exception-aware transfer;
                // the trampoline itself is outside every protected region.
                out[fixup.at - 1] = 0x0f;
            }
            out[fixup.at] = (out.len() + 1 + trampolines.len()) as u32;
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
        referenced_args.extend(reader.referenced_args);
    }
    out.push(0); // DreamMaker terminates every nonempty procedure with End.
    out.extend(trampolines);
    Ok(out)
}

#[cfg(test)]
#[path = "od_lower_tests.rs"]
mod tests;
