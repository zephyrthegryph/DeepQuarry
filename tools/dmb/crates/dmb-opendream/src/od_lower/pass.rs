//! One owned lowering pass; opcode families share its exact state.
use super::*;

#[derive(Clone, Copy)]
enum OpcodeFlow {
    Advance,
    ContinueThisOpcode,
    Unhandled,
}

struct PassInputs<'a, R: SymbolResolver> {
    code: &'a [u8],
    ids: &'a R,
    is_initializer: bool,
    local_count: usize,
    local_events: &'a [crate::opendream::OpenDreamLocal],
    lexical_local_add_indices: &'a [usize],
    native_omit_arguments: &'a [bool],
    source_info: Option<&'a [crate::opendream::OpenDreamSourceInfo]>,
    reverse_initial_debug_marker: bool,
}
struct PassState<'a, R: SymbolResolver> {
    inputs: PassInputs<'a, R>,
    world_flow: &'a mut WorldFlow,
    reader: Reader<'a>,
    local_event_index: usize,
    add_ordinal: usize,
    native_slot_for_add: Vec<u32>,
    source_event_index: usize,
    out: Vec<u32>,
    offsets: HashMap<u32, u32>,
    probability_regions: Vec<(u32, u32)>,
    fixups: Vec<Fixup>,
    state: LowerState,
    spawn_targets: Vec<u32>,
    pending_try: Vec<TryFrame>,
    try_regions: Vec<(usize, usize)>,
    catch_local_base: Option<u32>,
    catches_emitted: u32,
    safe: SafeAccessState,
    pending_receivers: Vec<PendingReceiver>,
    pending_indexed_logical: Vec<(u32, usize, Variable)>,
    safe_logical_continuations: std::collections::HashSet<usize>,
    computed_safe_logical: std::collections::HashSet<usize>,
    guarded_assign_into: HashMap<usize, (usize, usize)>,
    guarded_assign_into_nested: std::collections::HashSet<usize>,
    filtered_enumerators: HashMap<u32, (u8, u32)>,
    pending_orange_iterator: bool,
    pending_view_range_iterator: Option<u32>,
    range_enumerators: HashMap<u32, u32>,
    safe_index_enumerator: Option<u32>,
    delete_clear_cache_end: Option<u32>,
    iterator_frames: Vec<IteratorFrame>,
    iterator_states: std::collections::BTreeMap<usize, Vec<IteratorFrame>>,
    pending_iterator_mask: Option<u32>,
    store_reload_boundaries: std::collections::HashSet<u32>,
}
impl<'a, R: SymbolResolver> PassState<'a, R> {
    fn new(inputs: PassInputs<'a, R>, world_flow: &'a mut WorldFlow) -> Result<Self, LowerError> {
        let code = inputs.code;
        let local_events = inputs.local_events;
        let lexical_local_add_indices = inputs.lexical_local_add_indices;
        let native_omit_arguments = inputs.native_omit_arguments;
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
        let reader = Reader {
            code,
            at: 0,
            local_slots: Vec::new(),
            remap_locals: !local_events.is_empty(),
            referenced_args: Vec::new(),
            native_arg_slots,
        };
        let local_event_index = 0;
        let add_ordinal = 0usize;
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
        let source_event_index = 0;
        let out = Vec::new();
        let offsets = HashMap::new();
        let probability_regions = Vec::new();
        let fixups: Vec<Fixup> = Vec::new();
        let state = LowerState::default();
        let spawn_targets = Vec::new();
        let pending_try: Vec<TryFrame> = Vec::new();
        let try_regions = Vec::new();
        let catch_local_base: Option<u32> = None;
        let catches_emitted = 0u32;
        let safe = SafeAccessState::default();
        let pending_receivers = Vec::new();
        let pending_indexed_logical = Vec::<(u32, usize, Variable)>::new();
        let safe_logical_continuations = std::collections::HashSet::new();
        let computed_safe_logical = std::collections::HashSet::new();
        let guarded_assign_into = HashMap::<usize, (usize, usize)>::new();
        let guarded_assign_into_nested = std::collections::HashSet::<usize>::new();
        let filtered_enumerators: HashMap<u32, (u8, u32)> = HashMap::new();
        let pending_orange_iterator = false;
        let pending_view_range_iterator = None;
        let range_enumerators = std::collections::HashMap::new();
        let safe_index_enumerator = None;
        let delete_clear_cache_end: Option<u32> = None;
        let _ = inputs.local_count; // Iterator IDs are not native local slots.
        let iterator_frames = Vec::<IteratorFrame>::new();
        let iterator_states = std::collections::BTreeMap::new();
        let pending_iterator_mask = None;
        let store_reload_boundaries = std::collections::HashSet::new();
        Ok(Self {
            inputs,
            world_flow,
            reader,
            local_event_index,
            add_ordinal,
            native_slot_for_add,
            source_event_index,
            out,
            offsets,
            probability_regions,
            fixups,
            state,
            spawn_targets,
            pending_try,
            try_regions,
            catch_local_base,
            catches_emitted,
            safe,
            pending_receivers,
            pending_indexed_logical,
            safe_logical_continuations,
            computed_safe_logical,
            guarded_assign_into,
            guarded_assign_into_nested,
            filtered_enumerators,
            pending_orange_iterator,
            pending_view_range_iterator,
            range_enumerators,
            safe_index_enumerator,
            delete_clear_cache_end,
            iterator_frames,
            iterator_states,
            pending_iterator_mask,
            store_reload_boundaries,
        })
    }
    fn dispatch(
        &mut self,
        start: usize,
        op: u8,
        follows_format: bool,
    ) -> Result<OpcodeFlow, LowerError> {
        match self.lower_constants_constructors(start, op, follows_format)? {
            OpcodeFlow::Unhandled => {}
            flow => return Ok(flow),
        }
        match self.lower_references_fields(start, op, follows_format)? {
            OpcodeFlow::Unhandled => {}
            flow => return Ok(flow),
        }
        match self.lower_enumerators_augmented(start, op, follows_format)? {
            OpcodeFlow::Unhandled => {}
            flow => return Ok(flow),
        }
        match self.lower_postfix_calls(start, op, follows_format)? {
            OpcodeFlow::Unhandled => {}
            flow => return Ok(flow),
        }
        match self.lower_methods_receivers(start, op, follows_format)? {
            OpcodeFlow::Unhandled => {}
            flow => return Ok(flow),
        }
        match self.lower_assignments_outputs(start, op, follows_format)? {
            OpcodeFlow::Unhandled => {}
            flow => return Ok(flow),
        }
        match self.lower_prompts_builtins(start, op, follows_format)? {
            OpcodeFlow::Unhandled => {}
            flow => return Ok(flow),
        }
        match self.lower_safe_try(start, op, follows_format)? {
            OpcodeFlow::Unhandled => {}
            flow => return Ok(flow),
        }
        match self.lower_control_flow(start, op, follows_format)? {
            OpcodeFlow::Unhandled => {}
            flow => return Ok(flow),
        }
        Err(LowerError {
            kind: LowerErrorKind::UnsupportedConstruct,
            offset: start,
            reason: format!("OpenDream opcode {op:#04x} has no verified BYOND lowering"),
        })
    }
    fn run(mut self, referenced_args: Option<&mut Vec<u8>>) -> Result<Vec<u32>, LowerError> {
        while self.reader.at < self.inputs.code.len() {
            let Some((start, op, follows_format)) = self.prepare_instruction()? else {
                continue;
            };
            match self.dispatch(start, op, follows_format)? {
                OpcodeFlow::Advance | OpcodeFlow::ContinueThisOpcode => {}
                OpcodeFlow::Unhandled => unreachable!("dispatch rejects unhandled opcodes"),
            }
        }
        self.finish(referenced_args)
    }
}

#[allow(clippy::too_many_arguments)]
pub(super) fn lower_with_context_pass(
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
    PassState::new(
        PassInputs {
            code,
            ids,
            is_initializer,
            local_count,
            local_events,
            lexical_local_add_indices,
            native_omit_arguments,
            source_info,
            reverse_initial_debug_marker,
        },
        world_flow,
    )?
    .run(referenced_args)
}

mod assignments_outputs;
mod constants_constructors;
mod control_flow;
mod enumerators_augmented;
mod finish;
mod methods_receivers;
mod postfix_calls;
mod prepare;
mod prompts_builtins;
mod references_fields;
mod safe_try;
