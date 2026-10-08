//! Guarded translation of OpenDream VM instructions to BYOND v516 code words.
//!
//! OpenDream's bytecode is byte-addressed and has its own reference model. This
//! module deliberately rejects operations whose BYOND stack or call convention
//! has not been established, rather than emitting a plausible but invalid DMB.
use crate::operands::{Value, Variable};
use std::collections::HashMap;
mod receiver;
use receiver::*;
mod call;
use call::*;
mod assignment;
use assignment::*;
mod safe_guard;
use safe_guard::*;

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

mod expression_rewrites;
use expression_rewrites::*;

mod control_rewrites;
use control_rewrites::*;

mod references;
use references::*;

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

mod state;
use state::*;

mod literals;
use literals::*;

mod pass;
use pass::lower_with_context_pass;

#[cfg(test)]
#[path = "od_lower_tests.rs"]
mod tests;
