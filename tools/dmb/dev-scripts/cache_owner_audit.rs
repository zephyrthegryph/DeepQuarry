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
mod tests {
    use super::*;
    #[test]
    fn cache_value_and_conditional_fallthrough_are_bounded() {
        let dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        let field = dmb.variables.first().unwrap().name;
        let make = |offset, opcode, name, operands| Instruction {
            offset,
            opcode,
            name,
            operands,
        };
        let instructions = vec![
            make(0, 0x33, "GetVar", Variable::World.encode()),
            make(2, 0x142, "PushCache", vec![]),
            make(3, 0x34, "SetVar", Variable::Cache.encode()),
            make(5, 0x11, "Jz", vec![20]),
            make(7, 0x33, "GetVar", Variable::Field(field).encode()),
            make(9, 0x29, "Call", {
                let mut words = Variable::SetCache(
                    Box::new(Variable::Field(field)),
                    Box::new(Variable::DynamicProc(field)),
                )
                .encode();
                words.push(0);
                words
            }),
            make(12, 0x33, "GetVar", Variable::Field(field).encode()),
            make(20, 0x33, "GetVar", Variable::Field(field).encode()),
        ];
        let empty = HashSet::new();
        let result = references(&dmb, &instructions, &[], &empty, &empty);
        let owner = Place::Root("World".into());
        assert_eq!(
            result[4],
            Some(vec![Some(Place::Field(
                Box::new(owner),
                dmb.string(field).unwrap().to_vec()
            ))])
        );
        assert_eq!(result[6], Some(vec![None]), "a call invalidates ownership");
        assert_eq!(
            result[7],
            Some(vec![None]),
            "the branch destination invalidates ownership"
        );
        let joined = vec![
            instructions[0].clone(),
            instructions[1].clone(),
            instructions[2].clone(),
            instructions[3].clone(),
            instructions[4].clone(),
            instructions[7].clone(),
        ];
        let joined_refs = references(&dmb, &joined, &[], &empty, &empty);
        assert_eq!(
            joined_refs[5], joined_refs[4],
            "identical forward branch/fallthrough ownership survives the meet"
        );
    }
    #[test]
    fn numeric_alignment_rejects_changed_values() {
        let push = |opcode, operands| Instruction {
            offset: 0,
            opcode,
            name: "push",
            operands,
        };
        assert!(same_cache_step(
            &push(0x50, vec![7]),
            &push(0x60, vec![42, 7f32.to_bits()])
        ));
        assert!(!same_cache_step(
            &push(0x50, vec![7]),
            &push(0x60, vec![42, 8f32.to_bits()])
        ));
    }
    #[test]
    fn native_paired_calls_retain_src_world_but_not_derived_owners() {
        let dmb = Dmb::from_bytes(include_bytes!(
            "../fixtures/lowering/cache_call_context.bin"
        ))
        .unwrap();
        let empty = HashSet::new();
        for id in [1, 2, 4] {
            let instructions = code(&dmb, id).unwrap();
            let refs = references(&dmb, &instructions, &[], &empty, &empty);
            assert_eq!(
                refs[0], refs[4],
                "native call context {id} must retain its root receiver"
            );
            assert!(refs[4].as_ref().unwrap()[0].is_some());
        }
        let constructor = code(&dmb, 5).unwrap();
        let refs = references(&dmb, &constructor, &[], &empty, &empty);
        assert_eq!(
            refs[0], refs[5],
            "native New preserves the caller's Src binding"
        );
        let constructor_args = code(&dmb, 6).unwrap();
        let refs = references(&dmb, &constructor_args, &[], &empty, &empty);
        assert_eq!(refs[0], refs[8], "native NewArgList preserves Src");
        let argument = code(&dmb, 7).unwrap();
        let refs = references(&dmb, &argument, &[], &empty, &empty);
        assert_eq!(
            refs[0], refs[4],
            "a non-exposed argument binding survives the call"
        );
        let exposed = code(&dmb, 8).unwrap();
        let refs = references(&dmb, &exposed, &[], &empty, &empty);
        assert_eq!(
            refs[5],
            Some(vec![None]),
            "an exposed argument list remains unproved"
        );
        let local = code(&dmb, 9).unwrap();
        let names = vec![b"B".to_vec(), b"a".to_vec()];
        let unique = names.iter().cloned().collect();
        let refs = references(&dmb, &local, &names, &unique, &empty);
        assert_eq!(
            refs[2], refs[6],
            "a uniquely named single-write local receiver survives the call"
        );
        let list_set = code(&dmb, 10).unwrap();
        let names = vec![b"B".to_vec(), b"a".to_vec(), b"L".to_vec()];
        let unique = names.iter().cloned().collect();
        let refs = references(&dmb, &list_set, &names, &unique, &empty);
        assert_eq!(
            refs[2], refs[10],
            "native stack ListSet retains the immutable local receiver"
        );
        let mut spawned = local.clone();
        spawned.push(Instruction {
            offset: 100,
            opcode: 0x25,
            name: "Spawn",
            operands: vec![101],
        });
        assert!(
            stable_bindings(&spawned, &names, &unique).is_empty(),
            "spawned shared writes prevent the immutable-binding proof"
        );
        let mut state = State {
            cache: Some(Place::Field(
                Box::new(Place::Root("Src".into())),
                b"child".to_vec(),
            )),
            frames: vec![],
            top_value: None,
            cache_key: None,
            locals: &[],
            unique_locals: &empty,
            unique_globals: &empty,
            stable_bindings: HashSet::new(),
        };
        state.call_boundary();
        assert!(state.cache.is_none(), "callee may replace src.child");
        state.cache = Some(Place::Root("Usr".into()));
        state.call_boundary();
        assert!(
            state.cache.is_none(),
            "usr persistence is deliberately unproved"
        );
        state.cache = Some(Place::Field(
            Box::new(Place::Root("Src".into())),
            b"child".to_vec(),
        ));
        state.write(Some(&Place::Field(
            Box::new(Place::Root("arg:0".into())),
            b"child".to_vec(),
        )));
        assert!(
            state.cache.is_none(),
            "arg0 may alias src and replace the derived child receiver"
        );
    }
    #[test]
    fn forward_diamond_requires_every_receiver_to_agree() {
        let dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        let field = dmb.variables.first().unwrap().name;
        let make = |offset, opcode, name, operands| Instruction {
            offset,
            opcode,
            name,
            operands,
        };
        let mut instructions = vec![
            make(
                0,
                0x33,
                "GetVar",
                Variable::SetCache(Box::new(Variable::World), Box::new(Variable::Field(field)))
                    .encode(),
            ),
            make(5, 0x11, "Jz", vec![20]),
            make(7, 0x33, "GetVar", Variable::Field(field).encode()),
            make(9, 0xf, "Jmp", vec![30]),
            make(20, 0x33, "GetVar", Variable::Field(field).encode()),
            make(22, 0x33, "GetVar", Variable::Field(field).encode()),
            make(30, 0x33, "GetVar", Variable::Field(field).encode()),
        ];
        let empty = HashSet::new();
        let refs = references(&dmb, &instructions, &[], &empty, &empty);
        assert_eq!(
            refs[0], refs[4],
            "unconditional jump has no fallthrough into the else arm"
        );
        assert_eq!(refs[0], refs[6], "all incoming World receivers agree");
        instructions[5].operands =
            Variable::SetCache(Box::new(Variable::Arg(0)), Box::new(Variable::Field(field)))
                .encode();
        let refs = references(&dmb, &instructions, &[], &empty, &empty);
        assert_eq!(
            refs[6],
            Some(vec![None]),
            "a conflicting receiver invalidates the diamond join"
        );
    }
    #[test]
    fn duplicate_local_definition_mapping_is_bijective_and_detects_misreads() {
        let dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        let make = |offset, opcode, name, operands| Instruction {
            offset,
            opcode,
            name,
            operands,
        };
        let native = vec![
            make(0, 0x50, "PushInt", vec![1]),
            make(2, 0x34, "SetVar", Variable::Local(0).encode()),
            make(5, 0x50, "PushInt", vec![2]),
            make(7, 0x34, "SetVar", Variable::Local(1).encode()),
            make(10, 0x33, "GetVar", Variable::Local(0).encode()),
            make(13, 0x33, "GetVar", Variable::Local(1).encode()),
        ];
        let mut translated = native.clone();
        for index in [1, 4] {
            translated[index].operands = Variable::Local(1).encode();
        }
        for index in [3, 5] {
            translated[index].operands = Variable::Local(0).encode();
        }
        let mut nl = vec![b"value".to_vec(); 2];
        let mut tl = nl.clone();
        disambiguate_local_definitions(&native, &translated, &mut nl, &mut tl);
        assert_eq!(nl[0], tl[1]);
        assert_eq!(nl[1], tl[0]);
        assert_ne!(nl[0], nl[1]);
        let unique = nl.iter().cloned().collect();
        let empty = HashSet::new();
        let nr = references(&dmb, &native, &nl, &unique, &empty);
        let tr = references(&dmb, &translated, &tl, &unique, &empty);
        assert_eq!(nr[4], tr[4]);
        translated[4].operands = Variable::Local(0).encode();
        let tr = references(&dmb, &translated, &tl, &unique, &empty);
        assert_ne!(
            nr[4], tr[4],
            "slot renaming must not hide a wrong receiver read"
        );
        let mut incomplete = native.clone();
        incomplete[3] = make(7, 0x51, "Pop", vec![]);
        let mut nl = vec![b"value".to_vec(); 2];
        let mut tl = nl.clone();
        disambiguate_local_definitions(&incomplete, &incomplete, &mut nl, &mut tl);
        assert_eq!(
            nl[0], nl[1],
            "an unwritten ambiguous slot keeps the entire group unknown"
        );
    }
    #[test]
    fn cache_key_write_is_a_register_target_but_index_write_needs_provenance() {
        let dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        let instructions = vec![
            Instruction {
                offset: 0,
                opcode: 0x34,
                name: "SetVar",
                operands: Variable::CacheKey.encode(),
            },
            Instruction {
                offset: 2,
                opcode: 0x34,
                name: "SetVar",
                operands: Variable::CacheIndex.encode(),
            },
        ];
        let empty = HashSet::new();
        let refs = references(&dmb, &instructions, &[], &empty, &empty);
        assert_eq!(
            refs[0],
            Some(vec![Some(Place::Root("CacheKeyRegister".into()))])
        );
        assert_eq!(
            refs[1],
            Some(vec![None]),
            "the computed list element is not a fixed register target"
        );
    }
    #[test]
    fn whole_body_method_check_requires_actual_name_and_proc_verb_mode() {
        let dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        let id = dmb
            .procs
            .iter()
            .position(|proc| {
                dmb.string(proc.strings[1])
                    .is_some_and(|name| !name.is_empty())
            })
            .unwrap();
        let display = dmb.procs[id].strings[1];
        assert_eq!(
            method_selector_name(&dmb, &Variable::StaticProc(id as u32)),
            method_selector_name(&dmb, &Variable::DynamicProc(display))
        );
        assert_ne!(
            method_selector_name(&dmb, &Variable::DynamicProc(display)),
            method_selector_name(&dmb, &Variable::DynamicVerb(display))
        );
        let different = if display == 1 { 2 } else { 1 };
        assert_ne!(
            method_selector_name(&dmb, &Variable::DynamicProc(display)),
            method_selector_name(&dmb, &Variable::DynamicProc(different))
        );
        assert!(method_selector_name(&dmb, &Variable::StaticProc(u32::MAX)).is_none());
    }

    #[test]
    fn safe_owner_fallthrough_requires_a_getter_and_null_joins_remain_unknown() {
        let dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        let field = dmb.variables[0].name;
        let make = |offset, opcode, name, operands| Instruction {
            offset,
            opcode,
            name,
            operands,
        };
        let empty = HashSet::new();
        for opcode in [0x13d, 0x13e] {
            let mut code = vec![
                make(0, 0x33, "GetVar", Variable::Arg(0).encode()),
                make(3, opcode, "safe-owner", vec![20]),
                make(5, 0x33, "GetVar", Variable::Field(field).encode()),
                make(7, 0xf, "Jmp", vec![30]),
                make(20, 0x33, "GetVar", Variable::Field(field).encode()),
                make(30, 0x33, "GetVar", Variable::Field(field).encode()),
            ];
            let refs = references(&dmb, &code, &[], &empty, &empty);
            assert_eq!(
                refs[2],
                Some(vec![Some(Place::Field(
                    Box::new(Place::Root("arg:0".into())),
                    dmb.string(field).unwrap().to_vec()
                ))])
            );
            assert_eq!(
                refs[4],
                Some(vec![None]),
                "null target does not receive the non-null owner proof"
            );
            assert_eq!(
                refs[5],
                Some(vec![None]),
                "a shared null/non-null join remains unresolved"
            );
            code.insert(1, make(2, 0x30, "CallGlob", vec![0, 0]));
            let interrupted = references(&dmb, &code, &[], &empty, &empty);
            assert_eq!(
                interrupted[3],
                Some(vec![None]),
                "an intervening call breaks the immediate-getter proof"
            );
        }
    }

    #[test]
    fn typed_dispatch_snapshots_actual_owner_and_rejects_conflicting_shared_joins() {
        let dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        let field = dmb.variables[0].name;
        let make = |offset, opcode, name, operands| Instruction {
            offset,
            opcode,
            name,
            operands,
        };
        let empty = HashSet::new();
        for (opcode, table) in [
            (0x78, vec![1, 42, 0, 0, 20, 30]),
            (0x79, vec![1, 32767, 20, 30]),
            (0x7a, vec![1, 42, 0, 0, 42, 16256, 0, 20, 0, 30]),
            (0xb1, vec![2, 20, 30]),
        ] {
            let mut code = vec![
                make(
                    0,
                    0x33,
                    "GetVar",
                    Variable::SetCache(Box::new(Variable::Src), Box::new(Variable::Field(field)))
                        .encode(),
                ),
                // The dispatch snapshots this later weight/key receiver, not
                // the original Src selected before expression evaluation.
                make(
                    5,
                    0x33,
                    "GetVar",
                    Variable::SetCache(
                        Box::new(Variable::Arg(0)),
                        Box::new(Variable::Field(field)),
                    )
                    .encode(),
                ),
                make(10, opcode, "dispatch", table),
                make(20, 0x33, "GetVar", Variable::Field(field).encode()),
                make(22, 0xf, "Jmp", vec![40]),
                make(30, 0x33, "GetVar", Variable::Field(field).encode()),
                make(32, 0xf, "Jmp", vec![40]),
                make(40, 0x33, "GetVar", Variable::Field(field).encode()),
            ];
            let refs = references(&dmb, &code, &[], &empty, &empty);
            assert_eq!(refs[1], refs[3], "case entry retains actual selected Arg0");
            assert_eq!(
                refs[1], refs[5],
                "default entry has the same dispatch snapshot"
            );
            assert_eq!(refs[1], refs[7], "agreeing arms meet at the shared join");
            code[5].operands =
                Variable::SetCache(Box::new(Variable::World), Box::new(Variable::Field(field)))
                    .encode();
            let conflict = references(&dmb, &code, &[], &empty, &empty);
            assert_eq!(
                conflict[7],
                Some(vec![None]),
                "conflicting arm receivers invalidate the join"
            );
        }
    }

    #[test]
    fn adjacent_constant_index_setup_requires_the_same_list_and_key() {
        let dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        let fields = [dmb.variables[0].name, dmb.variables[1].name];
        assert_ne!(dmb.string(fields[0]), dmb.string(fields[1]));
        assert_ne!(dmb.string(1), dmb.string(2));
        let make = |field, key, interrupted| {
            let mut words = vec![0x33];
            words.extend(
                Variable::SetCache(Box::new(Variable::Src), Box::new(Variable::Field(field)))
                    .encode(),
            );
            words.extend([0x60, 6, key]);
            if interrupted {
                words.extend([0x30, 0, 0]);
            }
            words.push(0x34);
            words.extend(Variable::CacheKey.encode());
            words.push(0x34);
            words.extend(Variable::Cache.encode());
            words.push(0x33);
            words.extend(Variable::CacheIndex.encode());
            bytecode::decode(&words).unwrap()
        };
        let empty = HashSet::new();
        let resolved = |field, key, interrupted| {
            references(&dmb, &make(field, key, interrupted), &[], &empty, &empty)
                .last()
                .unwrap()
                .clone()
        };
        let reference = resolved(fields[0], 1, false);
        assert!(
            matches!(&reference, Some(values) if matches!(&values[0], Some(Place::Index(_, _))))
        );
        assert_eq!(reference, resolved(fields[0], 1, false));
        assert_ne!(
            reference,
            resolved(fields[0], 2, false),
            "changed constant keys must differ"
        );
        assert_ne!(
            reference,
            resolved(fields[1], 1, false),
            "changed list getters must differ"
        );
        assert_eq!(
            resolved(fields[0], 1, true),
            Some(vec![None]),
            "an intervening call breaks the bounded stack proof"
        );
    }

    #[test]
    fn loop_owner_invariant_requires_a_known_preheader_and_unchanged_body() {
        let dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        let field = Variable::Field(0);
        let make = |offset, opcode, name, operands| Instruction {
            offset,
            opcode,
            name,
            operands,
        };
        let mut code = vec![
            make(
                0,
                0x33,
                "GetVar",
                Variable::SetCache(Box::new(Variable::Src), Box::new(field.clone())).encode(),
            ),
            make(5, 0x11, "Jz", vec![30]),
            make(7, 0x33, "GetVar", field.clone().encode()),
            make(20, 0xf, "Jmp", vec![5]),
            make(30, 0, "End", vec![]),
        ];
        let empty = HashSet::new();
        let known = references(&dmb, &code, &[], &empty, &empty);
        assert!(known[2].as_ref().unwrap()[0].is_some());
        code.insert(
            3,
            make(
                10,
                0x33,
                "GetVar",
                Variable::SetCache(Box::new(Variable::Arg(0)), Box::new(field.clone())).encode(),
            ),
        );
        let conflict = references(&dmb, &code, &[], &empty, &empty);
        assert_eq!(
            conflict[2],
            Some(vec![None]),
            "different backedge owner must invalidate the header"
        );
        code.remove(3);
        code[0].operands = field.encode();
        let unseeded = references(&dmb, &code, &[], &empty, &empty);
        assert_eq!(
            unseeded[2],
            Some(vec![None]),
            "entry cache is never assumed Src"
        );
    }
    #[test]
    fn captured_method_result_requires_same_site_receiver_name_and_literal_argument() {
        let dmb = Dmb::from_bytes(include_bytes!(
            "../fixtures/lowering/cache_call_context.bin"
        ))
        .unwrap();
        let empty = HashSet::new();
        let name = dmb.procs[1].strings[1];
        let argument = dmb.procs[2].strings[0];
        let field = dmb.procs[1].strings[0];
        let words = vec![
            0x60, 6, argument, 0x29, 0xffdc, 0xffce, 0xffdd, name, 1, 0x34, 0xffd8, 0x33, field,
        ];
        let resolve = |words: &[u32]| {
            let instructions = bytecode::decode(words).unwrap();
            references(&dmb, &instructions, &[], &empty, &empty)
                .last()
                .cloned()
                .unwrap()
        };
        let known = resolve(&words);
        assert!(matches!(known.as_ref().unwrap().as_slice(),
            [Some(Place::Field(owner, _))] if matches!(owner.as_ref(), Place::CallResult(1, _, false, _, _))));
        let mut changed_name = words.clone();
        changed_name[7] = argument;
        assert_ne!(resolve(&changed_name), known);
        let mut changed_argument = words.clone();
        changed_argument[2] = name;
        assert_ne!(resolve(&changed_argument), known);
        let mut changed_owner = words.clone();
        changed_owner[5] = 0xffcf;
        assert_ne!(resolve(&changed_owner), known);
        let mut interrupted = words.clone();
        interrupted.splice(9..9, [0x51]);
        assert_eq!(resolve(&interrupted), Some(vec![None]));
        let mut joined = words.clone();
        joined.splice(9..9, [0x11, 11]);
        assert_eq!(resolve(&joined), Some(vec![None]));
        let mut non_literal = words.clone();
        non_literal.splice(0..3, [0x33, 0xffd9, 0]);
        assert_eq!(resolve(&non_literal), Some(vec![None]));
    }
}
