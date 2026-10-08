//! Conservative read-only receiver audit; never normalizes comparison results.
use byond_dmb::{
    bytecode::{self, Instruction, Operand},
    dmb::Dmb,
    operands::Variable,
};
use serde_json::json;
use std::{
    collections::{HashMap, HashSet},
    fs,
    io::{BufRead, BufReader, BufWriter, Write},
};

#[derive(Clone, Debug, PartialEq, Eq)]
enum Place {
    Root(String),
    Field(Box<Place>, Vec<u8>),
    Initial(Box<Place>),
    Saved(Box<Place>),
    MethodReceiver(Box<Place>),
    StringKey(Vec<u8>),
    Index(Box<Place>, Box<Place>),
    CallResult(usize, Box<Place>, bool, Vec<u8>, Vec<u8>),
}
impl Place {
    fn depends_on(&self, other: &Self) -> bool {
        self == other
            || match self {
                Self::Field(parent, _)
                | Self::Initial(parent)
                | Self::Saved(parent)
                | Self::MethodReceiver(parent) => parent.depends_on(other),
                Self::Index(parent, key) => parent.depends_on(other) || key.depends_on(other),
                Self::CallResult(_, receiver, _, _, _) => receiver.depends_on(other),
                Self::Root(_) | Self::StringKey(_) => false,
            }
    }
}
struct State<'a> {
    cache: Option<Place>,
    frames: Vec<Option<Place>>,
    top_value: Option<Place>,
    cache_key: Option<Place>,
    locals: &'a [Vec<u8>],
    unique_locals: &'a HashSet<Vec<u8>>,
    unique_globals: &'a HashSet<Vec<u8>>,
    stable_bindings: HashSet<String>,
}
impl State<'_> {
    fn invalidate(&mut self) {
        self.cache = None;
        self.frames.fill(None);
        self.top_value = None;
        self.cache_key = None;
    }
    fn resolve(&mut self, dmb: &Dmb, variable: &Variable) -> Option<Place> {
        match variable {
            Variable::Src
            | Variable::Usr
            | Variable::World
            | Variable::Args
            | Variable::Dot
            | Variable::Caller
            | Variable::Callee
            | Variable::Null => Some(Place::Root(format!("{variable:?}"))),
            Variable::Arg(id) => Some(Place::Root(format!("arg:{id}"))),
            // Local/global table identities are not assumed equal between binaries.
            Variable::Local(id) => {
                let name = self.locals.get(*id as usize)?;
                self.unique_locals
                    .contains(name)
                    .then(|| Place::Root(format!("local:{name:?}")))
            }
            Variable::Global(id) => {
                let name = dmb.string(dmb.variables.get(*id as usize)?.name)?;
                self.unique_globals
                    .contains(name)
                    .then(|| Place::Root(format!("global:{name:?}")))
            }
            Variable::Cache => self.cache.clone(),
            Variable::CacheIndex => Some(Place::Index(
                Box::new(self.cache.clone()?),
                Box::new(self.cache_key.clone()?),
            )),
            Variable::Field(id) => Some(Place::Field(
                Box::new(self.cache.clone()?),
                dmb.string(*id)?.to_vec(),
            )),
            Variable::SetCache(owner, field) => {
                self.cache = self.resolve(dmb, owner);
                self.resolve(dmb, field)
            }
            Variable::Initial(field) => Some(Place::Initial(Box::new(self.resolve(dmb, field)?))),
            Variable::IsSaved(field) => Some(Place::Saved(Box::new(self.resolve(dmb, field)?))),
            _ => None,
        }
    }
    fn write(&mut self, target: Option<&Place>) {
        let invalid = |owner: &Option<Place>| {
            owner.as_ref().is_some_and(|owner| {
                target.map_or_else(
                        || !matches!(owner, Place::Root(root) if root == "Src" || root == "World" || self.stable_bindings.contains(root)),
                    |target| {
                        // Two differently rooted object expressions may
                        // alias. A property write can replace a receiver
                        // obtained through either object's field chain.
                        if matches!(target, Place::Field(_, _) | Place::Index(_, _)) && !matches!(owner, Place::Root(_))
                        {
                            true
                        } else {
                            owner.depends_on(target)
                        }
                    },
                )
            })
        };
        if invalid(&self.cache) {
            self.cache = None;
        }
        for frame in &mut self.frames {
            if invalid(frame) {
                *frame = None;
            }
        }
    }
    fn method_receiver(&mut self, dmb: &Dmb, variable: &Variable) -> Option<Place> {
        match variable {
            Variable::SetCache(owner, selector) => {
                self.cache = self.resolve(dmb, owner);
                self.method_receiver(dmb, selector)
            }
            Variable::StaticProc(_)
            | Variable::StaticVerb(_)
            | Variable::DynamicProc(_)
            | Variable::DynamicVerb(_) => {
                Some(Place::MethodReceiver(Box::new(self.cache.clone()?)))
            }
            _ => self.resolve(dmb, variable),
        }
    }
    fn call_boundary(&mut self) {
        // Native paired context_method/context_global/world_global keep these
        // frame bindings even when a callee changes its own src. Derived field
        // values and other bindings may change during the call.
        let stable = |owner: &Option<Place>| matches!(owner, Some(Place::Root(root)) if root == "Src" || root == "World" || self.stable_bindings.contains(root));
        if !stable(&self.cache) {
            self.cache = None;
        }
        for frame in &mut self.frames {
            if !stable(frame) {
                *frame = None;
            }
        }
        self.top_value = None;
        self.cache_key = None;
    }
}
fn boundary(instruction: &Instruction) -> bool {
    instruction.name.starts_with('J')
        || instruction.name.contains("Switch")
        || instruction.name.contains("Try")
        || instruction.name.contains("JmpIfNull")
        || instruction.name == "Spawn"
}
fn joins(instructions: &[Instruction]) -> HashSet<usize> {
    let mut result = HashSet::new();
    for instruction in instructions {
        if let Ok(targets) = instruction.branch_targets() {
            for target in targets {
                if let Some(next) = instructions
                    .iter()
                    .find(|item| item.offset >= target as usize)
                {
                    result.insert(next.offset);
                }
            }
        }
    }
    result
}
type CacheSnapshot = (Option<Place>, Vec<Option<Place>>);
fn references(
    dmb: &Dmb,
    instructions: &[Instruction],
    locals: &[Vec<u8>],
    unique_locals: &HashSet<Vec<u8>>,
    unique_globals: &HashSet<Vec<u8>>,
) -> Vec<Option<Vec<Option<Place>>>> {
    let joins = joins(instructions);
    let mut incoming_count = HashMap::<usize, usize>::new();
    for instruction in instructions {
        for target in instruction.branch_targets().unwrap_or_default() {
            if let Some(next) = instructions
                .iter()
                .find(|item| item.offset >= target as usize)
            {
                *incoming_count.entry(next.offset).or_default() += 1;
            }
        }
    }

    let mut incoming = HashMap::<usize, Vec<CacheSnapshot>>::new();
    let edges = instructions
        .iter()
        .flat_map(|instruction| {
            instruction
                .branch_targets()
                .unwrap_or_default()
                .into_iter()
                .filter_map(|target| {
                    instructions
                        .iter()
                        .find(|next| next.offset >= target as usize)
                        .map(|next| (instruction.offset, next.offset, instruction.opcode))
                })
        })
        .collect::<Vec<_>>();
    let mut loop_roots = HashMap::<usize, Place>::new();
    let mut reachable = true;
    let mut state = State {
        locals,
        unique_locals,
        unique_globals,
        cache: None,
        frames: Vec::new(),
        top_value: None,
        cache_key: None,
        stable_bindings: stable_bindings(instructions, locals, unique_locals),
    };
    // Only the adjacent native list/key setup is interpreted here. This is
    // deliberately not a general value-stack or alias analysis.
    let mut index_setup: Option<(Place, Option<Place>, u8)> = None;
    let mut preceding_getter = None;
    instructions.iter().enumerate().map(|(site, instruction)| {
        if joins.contains(&instruction.offset) {
            index_setup = None;
            preceding_getter = None;
            state.cache_key = None;
            let snapshots = incoming.get(&instruction.offset);
            let entry = if reachable { state.cache.clone() } else { snapshots.and_then(|values| values.first().and_then(|value| value.0.clone())) };
            if state.frames.is_empty() {
                if let Some(ref root @ Place::Root(ref name)) = entry {
                    if (name == "Src" || name == "World") && loop_invariant(instructions, &edges, instruction.offset, root, snapshots) {
                        let end = edges.iter().filter(|(source, target, _)| *target == instruction.offset && *source >= *target).map(|(source, _, _)| *source).max().unwrap();
                        for item in instructions.iter().filter(|item| item.offset >= instruction.offset && item.offset <= end) { loop_roots.insert(item.offset, root.clone()); }
                    }
                }
            }
            let same = snapshots.is_some_and(|snapshots| {
                snapshots.len() == incoming_count[&instruction.offset]
                    && !snapshots.is_empty()
                    && snapshots.iter().all(|snapshot| snapshot == &snapshots[0])
                    && (!reachable || snapshots[0] == (state.cache.clone(), state.frames.clone()))
            });
            if same {
                let snapshot = &snapshots.unwrap()[0];
                state.cache = snapshot.0.clone();
                state.frames = snapshot.1.clone();
            } else { state.invalidate(); }
            reachable = true;
            // Value-stack joins are outside this bounded cache-owner proof.
            state.top_value = None;
        }
        if let Some(root) = loop_roots.get(&instruction.offset) {
            state.cache = Some(root.clone());
            state.frames.clear();
        }
        let operands = instruction.typed_operands().ok()?;
        let guard_owner = if matches!(instruction.opcode, 0x13d | 0x13e) {
            preceding_getter.clone()
        } else { None };
        let key_store = instruction.opcode == 0x34
            && operands.first() == Some(&Operand::Variable(Variable::CacheKey));
        let cache_store = instruction.opcode == 0x34
            && operands.first() == Some(&Operand::Variable(Variable::Cache));
        let completed_index = if cache_store {
            index_setup.as_ref().filter(|(_, _, phase)| *phase == 2).cloned()
        } else { None };
        let literal_key = if instruction.opcode == 0x60 {
            match operands.first() {
                Some(Operand::Value(value)) if value.tag() == 6 =>
                    dmb.string(value.id()).map(|key| Place::StringKey(key.to_vec())),
                _ => None,
            }
        } else { None };
        if !reachable {
            return Some(operands.iter().filter(|operand| matches!(operand, Operand::Variable(_))).map(|_| None).collect());
        }
        // Track only an immediately captured ordinary method return with one
        // literal string argument. The call site, receiver, actual selector
        // name/mode and argument identity must all agree across paired bodies.
        let literal_method_call = if instruction.opcode == 0x29 {
            match operands.as_slice() {
                [Operand::Variable(selector), Operand::Word(1)] => {
                    let previous = site.checked_sub(1).and_then(|index| instructions.get(index));
                    previous.filter(|previous| previous.opcode == 0x60)
                        .and_then(|previous| previous.typed_operands().ok())
                        .and_then(|values| match values.as_slice() {
                            [Operand::Value(value)] if value.tag() == 6 =>
                                Some((method_selector_name(dmb, selector)?, dmb.string(value.id())?.to_vec())),
                            _ => None,
                        })
                }
                _ => None,
            }
        } else { None };
        let mut result = Vec::new();
        let setter = matches!(instruction.opcode, 0x34 | 0x35 | 0x45..=0x4e | 0x62..=0x67 | 0xfd | 0xff | 0x15a | 0x177 | 0x17e);
        for operand in operands {
            if let Operand::Variable(variable) = operand {
                    let place = if matches!(instruction.opcode, 0x29 | 0x2a) {
                        state.method_receiver(dmb, &variable)
                    } else { state.resolve(dmb, &variable) };
                if setter {
                    if variable == Variable::Cache {
                        if let Some((owner, key, _)) = &completed_index {
                            state.cache = Some(owner.clone());
                            state.cache_key = key.clone();
                        } else {
                            state.cache = state.top_value.take();
                            state.cache_key = None;
                        }
                    }
                    else if variable == Variable::CacheKey {
                        // A key-register write does not mutate a list binding.
                        state.cache_key = index_setup.as_ref()
                            .filter(|(_, _, phase)| *phase == 1)
                            .and_then(|(_, key, _)| key.clone());
                    }
                    else { state.write(place.as_ref()); }
                }
                result.push(if setter && variable == Variable::Cache {
                    Some(Place::Root("CacheRegister".into()))
                } else if setter && variable == Variable::CacheKey {
                    Some(Place::Root("CacheKeyRegister".into()))
                } else { place });
            }
        }
        index_setup = match instruction.opcode {
            0x84 | 0x85 => index_setup.take(),
            0x33 => result.first().cloned().flatten().map(|owner| (owner, None, 0)),
            0x60 if literal_key.is_some() => index_setup.take()
                .filter(|(_, _, phase)| *phase == 0)
                .map(|(owner, _, _)| (owner, literal_key, 1)),
            0x34 if key_store => index_setup.take()
                .filter(|(_, _, phase)| *phase == 1)
                .map(|(owner, key, _)| (owner, key, 2)),
            _ => None,
        };
        preceding_getter = match instruction.opcode {
            0x84 | 0x85 => preceding_getter.take(),
            0x33 => result.first().cloned().flatten(),
            _ => None,
        };
        match instruction.opcode {
            0x33 => state.top_value = result.first().cloned().flatten(),
            0x142 | 0x143 => {},
            _ => state.top_value = None,
        }
        match instruction.opcode {
            0x13d | 0x13e => {
                // Both native safe-owner guards consume the preceding value
                // into Cache on the non-null path. The null target remains
                // unknown; its state cannot authorize a later bare selector.
                for target in instruction.branch_targets().unwrap_or_default() {
                    if target as usize > instruction.offset {
                        if let Some(next) = instructions.iter().find(|item| item.offset >= target as usize) {
                            incoming.entry(next.offset).or_default().push((None, state.frames.clone()));
                        }
                    }
                }
                state.cache = guard_owner;
                state.cache_key = None;
            }
            0x142 => { state.frames.push(state.cache.clone()); state.cache_key = None; },
            0x143 => { state.cache = state.frames.pop().flatten(); state.cache_key = None; },
            // These branches inspect the value stack without changing Cache.
            // A forward destination can retain ownership only if every branch
            // snapshot and the fallthrough cache/frame state agree exactly.
            0xf | 0x10 | 0x11 | 0x78 | 0x79 | 0x7a | 0xb1 | 0xb2 | 0xb3 => {
                for target in instruction.branch_targets().unwrap_or_default() {
                    if target as usize > instruction.offset {
                        if let Some(next) = instructions.iter().find(|item| item.offset >= target as usize) {
                            incoming.entry(next.offset).or_default().push((state.cache.clone(), state.frames.clone()));
                        }
                    }
                }
                if matches!(instruction.opcode, 0xf | 0x78 | 0x79 | 0x7a | 0xb1) {
                    // Typed table dispatch always chooses an explicit outgoing
                    // target. Snapshot the actual cache after key/weight reads;
                    // do not restore the compiler's pre-probability context.
                    state.invalidate(); reachable = false;
                }
            },
            0x0 | 0x12 => { state.invalidate(); reachable = false; },
            _ if instruction.name.starts_with("Call") || matches!(instruction.name, "New" | "NewArgList") => state.call_boundary(),
            0x7c => state.write(None), // ListSet consumes stack values; its list may alias args/vars.
            _ if boundary(instruction)
                || matches!(instruction.name, "Del" | "ListSet") => state.invalidate(),
            _ => {}
        }
        if let Some(((verb, name), argument)) = literal_method_call {
            state.top_value = result.first().cloned().flatten().map(|receiver|
                Place::CallResult(site, Box::new(receiver), verb, name, argument));
        }
        Some(result)
    }).collect()
}
fn loop_invariant(
    instructions: &[Instruction],
    edges: &[(usize, usize, u32)],
    header: usize,
    root: &Place,
    snapshots: Option<&Vec<CacheSnapshot>>,
) -> bool {
    let backward = edges
        .iter()
        .filter(|(source, target, _)| *target == header && *source >= header)
        .collect::<Vec<_>>();
    let Some(end) = backward.iter().map(|(source, _, _)| *source).max() else {
        return false;
    };
    if backward
        .iter()
        .any(|(_, _, opcode)| !matches!(*opcode, 0xf | 0x10 | 0x11 | 0xb2 | 0xb3))
    {
        return false;
    }
    let forward = edges
        .iter()
        .filter(|(source, target, _)| *target == header && *source < header)
        .count();
    let snapshots = snapshots.map(Vec::as_slice).unwrap_or_default();
    if forward != snapshots.len()
        || snapshots
            .iter()
            .any(|(cache, frames)| cache.as_ref() != Some(root) || !frames.is_empty())
    {
        return false;
    }
    if edges.iter().any(|(source, target, _)| {
        *target > header && *target <= end && (*source < header || *source > end)
    }) {
        return false;
    }
    fn selector(variable: &Variable, root: &Place) -> bool {
        match variable {
            Variable::SetCache(owner, field) => {
                let expected = match root {
                    Place::Root(name) if name == "Src" => Variable::Src,
                    Place::Root(name) if name == "World" => Variable::World,
                    _ => return false,
                };
                **owner == expected && !has_cache_selector(field)
            }
            Variable::Initial(value) | Variable::IsSaved(value) => selector(value, root),
            _ => true,
        }
    }
    fn has_cache_selector(variable: &Variable) -> bool {
        match variable {
            Variable::SetCache(_, _) => true,
            Variable::Initial(value) | Variable::IsSaved(value) => has_cache_selector(value),
            _ => false,
        }
    }
    fn writes_context(variable: &Variable) -> bool {
        match variable {
            Variable::SetCache(_, target)
            | Variable::Initial(target)
            | Variable::IsSaved(target) => writes_context(target),
            Variable::Cache | Variable::Src | Variable::World => true,
            _ => false,
        }
    }
    for instruction in instructions
        .iter()
        .filter(|instruction| instruction.offset >= header && instruction.offset <= end)
    {
        if matches!(
            instruction.opcode,
            0 | 0x12 | 0x25 | 0x13d | 0x13e | 0x142 | 0x143
        ) || instruction.name.contains("Try")
            || instruction.name.contains("Catch")
            || instruction.name.contains("Switch")
            || instruction.name == "Throw"
            || instruction.name == "Del"
        {
            return false;
        }
        let Ok(operands) = instruction.typed_operands() else {
            return false;
        };
        for operand in operands {
            if let Operand::Variable(variable) = operand {
                if !selector(&variable, root) {
                    return false;
                }
                if !matches!(instruction.opcode, 0x33 | 0x29 | 0x2a) && writes_context(&variable) {
                    return false;
                }
            }
        }
    }
    true
}
fn stable_bindings(
    instructions: &[Instruction],
    locals: &[Vec<u8>],
    unique_locals: &HashSet<Vec<u8>>,
) -> HashSet<String> {
    if instructions
        .iter()
        .any(|instruction| instruction.opcode == 0x25)
    {
        return HashSet::new();
    }
    fn visit(variable: &Variable, args: &mut HashSet<u32>, exposed: &mut bool) {
        match variable {
            Variable::Args | Variable::Caller | Variable::Callee => *exposed = true,
            Variable::Arg(id) => {
                args.insert(*id);
            }
            Variable::SetCache(owner, selector) => {
                visit(owner, args, exposed);
                visit(selector, args, exposed);
            }
            Variable::Initial(value) | Variable::IsSaved(value) => visit(value, args, exposed),
            _ => {}
        }
    }
    fn target(variable: &Variable) -> &Variable {
        match variable {
            Variable::SetCache(_, selector) => target(selector),
            _ => variable,
        }
    }
    let mut writes = HashMap::<u32, usize>::new();
    let mut args = HashSet::new();
    let mut written_args = HashSet::new();
    let mut exposed = false;
    for instruction in instructions {
        for operand in instruction.typed_operands().unwrap_or_default() {
            if let Operand::Variable(variable) = operand {
                visit(&variable, &mut args, &mut exposed);
                // Treat every unknown variable-bearing operation as a possible
                // binding write; only reads and call selectors are excluded.
                if !matches!(instruction.opcode, 0x33 | 0x29 | 0x2a) {
                    match target(&variable) {
                        Variable::Local(id) => {
                            *writes.entry(*id).or_default() += 1;
                        }
                        Variable::Arg(id) => {
                            written_args.insert(*id);
                        }
                        _ => {}
                    }
                }
            }
        }
    }
    let mut stable = HashSet::new();
    for (id, name) in locals.iter().enumerate() {
        if unique_locals.contains(name) && writes.get(&(id as u32)) == Some(&1) {
            stable.insert(format!("local:{name:?}"));
        }
    }
    if !exposed {
        for id in args.difference(&written_args) {
            stable.insert(format!("arg:{id}"));
        }
    }
    stable
}
fn disambiguate_local_definitions(
    native: &[Instruction],
    translated: &[Instruction],
    nl: &mut [Vec<u8>],
    tl: &mut [Vec<u8>],
) {
    fn definitions(code: &[Instruction]) -> HashMap<u32, Vec<usize>> {
        fn target(variable: &Variable) -> &Variable {
            match variable {
                Variable::SetCache(_, value) => target(value),
                _ => variable,
            }
        }
        let mut result = HashMap::<u32, Vec<usize>>::new();
        for (index, instruction) in code.iter().enumerate() {
            if !matches!(instruction.opcode, 0x34 | 0x35 | 0x45..=0x4e | 0x62..=0x67 | 0xfd | 0xff | 0x15a | 0x177 | 0x17e)
            {
                continue;
            }
            for operand in instruction.typed_operands().unwrap_or_default() {
                if let Operand::Variable(variable) = operand {
                    if let Variable::Local(id) = target(&variable) {
                        result.entry(*id).or_default().push(index);
                    }
                }
            }
        }
        result
    }
    let nw = definitions(native);
    let tw = definitions(translated);
    let mut groups = HashMap::<Vec<u8>, Vec<usize>>::new();
    for (id, name) in nl.iter().enumerate() {
        if !name.is_empty() {
            groups.entry(name.clone()).or_default().push(id);
        }
    }
    for (name, native_ids) in groups {
        if native_ids.len() < 2 {
            continue;
        }
        let translated_ids = tl
            .iter()
            .enumerate()
            .filter(|(_, other)| **other == name)
            .map(|(id, _)| id)
            .collect::<Vec<_>>();
        if translated_ids.len() != native_ids.len() {
            continue;
        }
        let mut matches = Vec::new();
        for nid in &native_ids {
            let Some(writes) = nw.get(&(*nid as u32)) else {
                break;
            };
            let tids = translated_ids
                .iter()
                .filter(|tid| tw.get(&(**tid as u32)) == Some(writes))
                .collect::<Vec<_>>();
            if tids.len() != 1 {
                break;
            }
            matches.push((*nid, *tids[0], writes));
        }
        if matches.len() != native_ids.len()
            || matches
                .iter()
                .map(|(_, tid, _)| tid)
                .collect::<HashSet<_>>()
                .len()
                != native_ids.len()
        {
            continue;
        }
        for (nid, tid, writes) in matches {
            let mut identity = name.clone();
            identity.push(0);
            identity.extend_from_slice(format!("writes:{writes:?}").as_bytes());
            nl[nid] = identity.clone();
            tl[tid] = identity;
        }
    }
}
fn code(dmb: &Dmb, id: usize) -> Result<Vec<Instruction>, Box<dyn std::error::Error>> {
    let instructions = bytecode::decode(dmb.proc_code_words(id).ok_or("missing procedure code")?)
        .map_err(|error| format!("{error:?}"))?
        .into_iter()
        .filter(|instruction| !matches!(instruction.opcode, 0x84 | 0x85))
        .collect::<Vec<_>>();
    Ok(instructions)
}
// Numeric push width is irrelevant to the cache machine. Require the actual
// emitted floating-point value to match before aligning differing opcodes.
fn same_cache_step(a: &Instruction, b: &Instruction) -> bool {
    if a.opcode == b.opcode {
        return true;
    }
    let number = |i: &Instruction| -> Option<u32> {
        match i.opcode {
            0x50 => Some(((*i.operands.first()? as i32) as f32).to_bits()),
            0x60 if i.operands.first() == Some(&42) => i.operands.get(1).copied(),
            _ => None,
        }
    };
    number(a).is_some() && number(a) == number(b)
}
fn method_selector_name(dmb: &Dmb, variable: &Variable) -> Option<(bool, Vec<u8>)> {
    let (verb, id) = match variable {
        Variable::SetCache(_, selector) => return method_selector_name(dmb, selector),
        Variable::DynamicProc(id) => (false, *id),
        Variable::DynamicVerb(id) => (true, *id),
        Variable::StaticProc(id) => (false, dmb.procs.get(*id as usize)?.strings[1]),
        Variable::StaticVerb(id) => (true, dmb.procs.get(*id as usize)?.strings[1]),
        _ => return None,
    };
    Some((verb, dmb.string(id)?.to_vec()))
}
fn same_method_selector_names(
    native: &Dmb,
    n: &[Instruction],
    translated: &Dmb,
    t: &[Instruction],
) -> bool {
    n.iter().zip(t).all(|(n, t)| {
        if !matches!(n.opcode, 0x29 | 0x2a) {
            return true;
        }
        let selector =
            |dmb, instruction: &Instruction| match instruction.typed_operands().ok()?.first()? {
                Operand::Variable(variable) => method_selector_name(dmb, variable),
                _ => None,
            };
        let names = selector(native, n);
        names.is_some() && names == selector(translated, t)
    })
}
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if !(4..=5).contains(&args.len()) {
        return Err(
            "usage: cache_owner_audit NATIVE.dmb TRANSLATED.dmb PARITY.ndjson OUTPUT.ndjson [mixed]".into(),
        );
    }
    let native = Dmb::from_bytes(&fs::read(&args[0])?)?;
    let translated = Dmb::from_bytes(&fs::read(&args[1])?)?;
    // A name occurring exactly once in each entire variable table identifies
    // its Global operand without assuming wire IDs or compiler table order.
    let unique_names = |dmb: &Dmb| {
        let mut seen = HashSet::new();
        let mut duplicates = HashSet::new();
        for variable in &dmb.variables {
            if let Some(name) = dmb.string(variable.name) {
                if !seen.insert(name.to_vec()) {
                    duplicates.insert(name.to_vec());
                }
            }
        }
        seen.retain(|name| !duplicates.contains(name));
        seen
    };
    let nn = unique_names(&native);
    let tn = unique_names(&translated);
    let unique_globals = nn.intersection(&tn).cloned().collect::<HashSet<_>>();
    let mut output = BufWriter::new(fs::File::create(&args[3])?);
    let (mut pairs, mut skipped, mut equal, mut unknown, mut mismatches) =
        (0usize, 0usize, 0usize, 0usize, 0usize);
    let mut equal_method_receivers = 0usize;
    let mut verified_cache_only_bodies = 0usize;
    for line in BufReader::new(fs::File::open(&args[2])?).lines() {
        let row: serde_json::Value = serde_json::from_str(&line?)?;
        let category = row["category"].as_str().unwrap_or_default();
        if row["section"] != "classification"
            || !(category == "cache_or_reference_operands_only"
                || args.get(4).is_some_and(|mode| mode == "mixed")
                    && category == "mixed_same_instruction_count")
        {
            continue;
        }
        pairs += 1;
        let n = code(
            &native,
            row["native_proc"].as_u64().ok_or("missing native id")? as usize,
        )?;
        let t = code(
            &translated,
            row["translated_proc"]
                .as_u64()
                .ok_or("missing translated id")? as usize,
        )?;
        if row["path"]
            .as_str()
            .is_some_and(|path| path.ends_with("::<class initializer>"))
        {
            let ns = byond_dmb::compare::constant_initializer_signature(
                &native,
                row["native_proc"].as_u64().unwrap() as u32,
            );
            let ts = byond_dmb::compare::constant_initializer_signature(
                &translated,
                row["translated_proc"].as_u64().unwrap() as u32,
            );
            if ns.is_some() && ns == ts {
                writeln!(
                    output,
                    "{}",
                    json!({"section":"verified_constant_initializer",
                    "path":row["path"],"native_proc":row["native_proc"],"translated_proc":row["translated_proc"]})
                )?;
            }
        }
        if n.len() != t.len() || n.iter().zip(&t).any(|(n, t)| !same_cache_step(n, t)) {
            skipped += 1;
            continue;
        }
        let locals = |dmb: &Dmb, id: usize| -> Option<Vec<Vec<u8>>> {
            dmb.lists
                .get(dmb.procs.get(id)?.code_locals_args[1] as usize)?
                .iter()
                .map(|id| Some(dmb.string(dmb.variables.get(*id as usize)?.name)?.to_vec()))
                .collect()
        };
        let nl = locals(&native, row["native_proc"].as_u64().unwrap() as usize);
        let tl = locals(
            &translated,
            row["translated_proc"].as_u64().unwrap() as usize,
        );
        let mut nl = nl.unwrap_or_default();
        let mut tl = tl.unwrap_or_default();
        disambiguate_local_definitions(&n, &t, &mut nl, &mut tl);
        let unique = |names: &[Vec<u8>]| {
            names
                .iter()
                .filter(|name| {
                    !name.is_empty() && names.iter().filter(|other| other == name).count() == 1
                })
                .cloned()
                .collect::<HashSet<_>>()
        };
        let nu = unique(&nl);
        let tu = unique(&tl);
        let unique_locals = nu.intersection(&tu).cloned().collect::<HashSet<_>>();
        let nr = references(&native, &n, &nl, &unique_locals, &unique_globals);
        let tr = references(&translated, &t, &tl, &unique_locals, &unique_globals);
        let mut fully_known = category == "cache_or_reference_operands_only"
            && same_method_selector_names(&native, &n, &translated, &t);
        for (index, (nref, tref)) in nr.iter().zip(&tr).enumerate() {
            let (Some(nref), Some(tref)) = (nref, tref) else {
                unknown += 1;
                fully_known = false;
                continue;
            };
            if nref.len() != tref.len() {
                unknown += 1;
                fully_known = false;
                continue;
            }
            for (nref, tref) in nref.iter().zip(tref) {
                match (nref, tref) {
                    (Some(nref), Some(tref)) if nref == tref => {
                        if matches!(nref, Place::MethodReceiver(_)) {
                            equal_method_receivers += 1;
                        } else {
                            equal += 1;
                        }
                    }
                    (Some(nref), Some(tref)) => {
                        mismatches += 1;
                        fully_known = false;
                        writeln!(
                            output,
                            "{}",
                            json!({"path": row["path"], "native_proc":row["native_proc"],
                            "translated_proc":row["translated_proc"], "instruction":index,
                            "opcode":n[index].opcode, "native":format!("{nref:?}"), "translated":format!("{tref:?}")})
                        )?;
                    }
                    _ => {
                        unknown += 1;
                        fully_known = false;
                        writeln!(
                            output,
                            "{}",
                            json!({"section":"unknown_reference",
                            "path":row["path"], "native_proc":row["native_proc"],
                            "translated_proc":row["translated_proc"], "instruction":index,
                            "opcode":n[index].opcode,
                            "native_operands":format!("{:?}",n[index].typed_operands()),
                            "translated_operands":format!("{:?}",t[index].typed_operands()),
                            "native":format!("{nref:?}"),"translated":format!("{tref:?}")})
                        )?;
                    }
                }
            }
        }
        if fully_known {
            verified_cache_only_bodies += 1;
            writeln!(
                output,
                "{}",
                json!({"section":"verified_cache_only_body",
                "path":row["path"], "native_proc":row["native_proc"], "translated_proc":row["translated_proc"]})
            )?;
        }
    }
    writeln!(
        output,
        "{}",
        json!({"section":"summary", "pairs":pairs,"skipped_layout":skipped,
        "known_equal_references":equal,"known_equal_method_receivers":equal_method_receivers,
        "unknown_references":unknown,"candidate_mismatches":mismatches,
        "verified_cache_only_bodies":verified_cache_only_bodies})
    )?;
    eprintln!("{pairs} pairs; {skipped} skipped layouts; {equal} known equal references; {equal_method_receivers} equal method receivers; {unknown} unknown; {mismatches} candidates");
    Ok(())
}

#[cfg(test)]
#[path = "cache_owner_audit_tests.rs"]
mod tests;
