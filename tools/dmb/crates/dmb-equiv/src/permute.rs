//! Consistent renumbering of a compiled world, for testing the equivalence
//! checker and for runtime probes of which table orders are observable.
//!
//! Every table selected in `PermuteOptions` is shuffled and every reference to
//! it (records, metadata lists and bytecode operands) is rewritten. Indices
//! 0xffcd..=0xffff stay fixed: 0xffff is the nullable sentinel in every table,
//! and Field operands cannot encode string IDs in the intrinsic range.
use byond_dmb::bytecode::{self, Instruction, Operand};
use byond_dmb::dmb::{Dmb, WordLists};
use byond_dmb::ids::NONE;
use byond_dmb::operands::{Value, ValueKind, Variable};
use std::collections::HashMap;
use std::io;

#[derive(Clone, Debug)]
pub struct PermuteOptions {
    pub seed: u64,
    pub classes: bool,
    pub procs: bool,
    pub strings: bool,
    pub variables: bool,
    pub instances: bool,
    pub mobs: bool,
    pub resources: bool,
    pub lists: bool,
    /// Reverse each class's variable declaration pairs (order probe).
    pub reverse_decls: bool,
    /// Reverse the global footer pairs (order probe).
    pub reverse_footer: bool,
    /// Keep string IDs below this bound in place (probe for positional strings).
    pub keep_strings: usize,
    /// Preserve every runtime-observable order (see `ORDER_POLICY`): the
    /// builtin string prefix, relative StringID order of declared variable
    /// names, relative order of named procedures, and the class table order.
    pub preserve_semantics: bool,
}

impl PermuteOptions {
    pub fn all(seed: u64) -> Self {
        Self { seed, classes: true, procs: true, strings: true, variables: true, instances: true, mobs: true, resources: true, lists: true, reverse_decls: false, reverse_footer: false, keep_strings: 0, preserve_semantics: false }
    }
    pub fn none(seed: u64) -> Self {
        Self { seed, classes: false, procs: false, strings: false, variables: false, instances: false, mobs: false, resources: false, lists: false, reverse_decls: false, reverse_footer: false, keep_strings: 0, preserve_semantics: false }
    }
    /// Parse a comma list such as `classes,procs` (or `all`).
    pub fn parse(seed: u64, tables: &str) -> io::Result<Self> {
        let mut o = Self::none(seed);
        for t in tables.split(',').filter(|t| !t.is_empty()) {
            match t {
                "all" => o = Self::all(seed),
                "safe" => {
                    o = Self::all(seed);
                    o.preserve_semantics = true;
                }
                "classes" | "types" => o.classes = true,
                "procs" => o.procs = true,
                "strings" => o.strings = true,
                "variables" | "vars" => o.variables = true,
                "instances" => o.instances = true,
                "mobs" => o.mobs = true,
                "resources" => o.resources = true,
                "lists" => o.lists = true,
                "reverse_decls" => o.reverse_decls = true,
                "reverse_footer" => o.reverse_footer = true,
                other => return Err(io::Error::new(io::ErrorKind::InvalidInput, format!("unknown table {other}"))),
            }
        }
        Ok(o)
    }
}

struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u64 {
        // splitmix64
        self.0 = self.0.wrapping_add(0x9e37_79b9_7f4a_7c15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        z ^ (z >> 31)
    }
    fn below(&mut self, n: usize) -> usize {
        (self.next() % n as u64) as usize
    }
}

fn fixed(i: usize) -> bool {
    (0xffcd..=0xffff).contains(&i)
}

/// old index -> new index; identity when `enabled` is false.
fn permutation(n: usize, enabled: bool, rng: &mut Rng) -> Vec<u32> {
    permutation_from(n, enabled, 0, rng)
}

fn permutation_from(n: usize, enabled: bool, keep: usize, rng: &mut Rng) -> Vec<u32> {
    let mut map: Vec<u32> = (0..n as u32).collect();
    if !enabled {
        return map;
    }
    let mut movable: Vec<usize> = (0..n).filter(|&i| !fixed(i) && i >= keep).collect();
    let slots = movable.clone();
    for i in (1..movable.len()).rev() {
        let j = rng.below(i + 1);
        movable.swap(i, j);
    }
    for (slot, old) in slots.into_iter().zip(movable) {
        map[old] = slot as u32;
    }
    map
}

/// Random order that keeps every parent class before its children.
fn class_permutation(dmb: &Dmb, enabled: bool, rng: &mut Rng) -> Vec<u32> {
    let n = dmb.classes.len();
    if !enabled {
        return (0..n as u32).collect();
    }
    let mut children: Vec<Vec<usize>> = vec![Vec::new(); n];
    let mut ready = Vec::new();
    for (i, c) in dmb.classes.iter().enumerate() {
        let p = c.parent_class_id() as usize;
        if c.parent_class_id() == NONE || p >= n || p == i {
            ready.push(i);
        } else {
            children[p].push(i);
        }
    }
    let mut order = Vec::with_capacity(n);
    while !ready.is_empty() {
        let k = rng.below(ready.len());
        let i = ready.swap_remove(k);
        order.push(i);
        ready.extend(children[i].iter().copied());
    }
    let slots: Vec<usize> = (0..n).filter(|&i| !fixed(i)).collect();
    let mut map: Vec<u32> = (0..n as u32).collect();
    let movable: Vec<usize> = order.into_iter().filter(|&i| !fixed(i)).collect();
    for (slot, old) in slots.into_iter().zip(movable) {
        map[old] = slot as u32;
    }
    map
}

fn apply<T: Clone>(items: &[T], map: &[u32]) -> Vec<T> {
    let mut out: Vec<Option<T>> = vec![None; items.len()];
    for (old, item) in items.iter().enumerate() {
        out[map[old] as usize] = Some(item.clone());
    }
    out.into_iter().map(|x| x.expect("permutation is a bijection")).collect()
}

/// Shuffle, then put the `ordered` members back into increasing slot order
/// so their relative order is unchanged.
fn constrain(mut map: Vec<u32>, ordered: &[bool]) -> Vec<u32> {
    let members: Vec<usize> = (0..map.len()).filter(|&i| ordered[i]).collect();
    let mut slots: Vec<u32> = members.iter().map(|&i| map[i]).collect();
    slots.sort_unstable();
    for (i, slot) in members.into_iter().zip(slots) {
        map[i] = slot;
    }
    map
}

fn builtin_prefix(dmb: &Dmb) -> usize {
    dmb.strings.iter().position(|s| s.data == b"BLEND_INSET_OVERLAY").map_or(0, |i| i + 1)
}

struct Maps {
    c: Vec<u32>,
    p: Vec<u32>,
    s: Vec<u32>,
    v: Vec<u32>,
    i: Vec<u32>,
    m: Vec<u32>,
    r: Vec<u32>,
}

fn m(map: &[u32], id: u32) -> u32 {
    if id == NONE {
        NONE
    } else {
        map.get(id as usize).copied().unwrap_or(id)
    }
}

impl Maps {
    fn tagged(&self, tag: u8, id: u32) -> u32 {
        match ValueKind::from_tag(tag) {
            ValueKind::String => m(&self.s, id),
            ValueKind::MobPath => m(&self.m, id),
            ValueKind::ClientPath | ValueKind::ListPath | ValueKind::FilePath | ValueKind::SavefilePath if id == 0 => 0,
            ValueKind::MovablePath
            | ValueKind::AtomPath
            | ValueKind::AreaPath
            | ValueKind::DatumPath
            | ValueKind::SavefilePath
            | ValueKind::FilePath
            | ValueKind::ListPath
            | ValueKind::ImagePath
            | ValueKind::ClientPath
            | ValueKind::BuiltinPath => m(&self.c, id),
            ValueKind::Resource => m(&self.r, id),
            ValueKind::ProcPath => m(&self.p, id),
            ValueKind::InstanceTypePath => m(&self.i, id),
            _ => id,
        }
    }
    fn value(&self, v: &Value) -> Value {
        if v.kind() == ValueKind::Number {
            return *v;
        }
        let id = self.tagged(v.tag(), v.id());
        Value {
            tag_word: (v.tag_word & !0xff00) | ((id >> 8) & 0xff00),
            data_word: (v.data_word & !0xffff) | (id & 0xffff),
            extra_word: v.extra_word,
        }
    }
    fn variable(&self, v: &Variable) -> Variable {
        use Variable::*;
        match v {
            Field(id) => Field(m(&self.s, *id)),
            Global(id) => Global(m(&self.v, *id)),
            DynamicProc(id) => DynamicProc(m(&self.s, *id)),
            DynamicVerb(id) => DynamicVerb(m(&self.s, *id)),
            StaticProc(id) => StaticProc(m(&self.p, *id)),
            StaticVerb(id) => StaticVerb(m(&self.p, *id)),
            SetCache(a, b) => SetCache(Box::new(self.variable(a)), Box::new(self.variable(b))),
            Initial(x) => Initial(Box::new(self.variable(x))),
            IsSaved(x) => IsSaved(Box::new(self.variable(x))),
            other => other.clone(),
        }
    }
    fn code(&self, words: &[u32]) -> io::Result<Vec<u32>> {
        let ins = bytecode::decode(words).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e.reason))?;
        let mut out = Vec::with_capacity(words.len());
        for i in &ins {
            out.extend(self.instruction(i)?);
        }
        if out.len() != words.len() {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "re-encoded code changed length"));
        }
        Ok(out)
    }
    fn instruction(&self, i: &Instruction) -> io::Result<Vec<u32>> {
        let ops = i.typed_operands().map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e.reason))?;
        let mut w = vec![i.opcode];
        for (index, op) in ops.into_iter().enumerate() {
            match op {
                Operand::Word(x) => w.push(if index == 0 && matches!(i.opcode, 0x02 | 0x04 | 0x84) {
                    m(&self.s, x)
                } else if (i.opcode == 0x30 && index == 1) || (i.opcode == 0xcd && index == 0) {
                    m(&self.p, x)
                } else {
                    x
                }),
                Operand::Value(v) => w.extend(self.value(&v).encode()),
                Operand::Variable(v) => w.extend(self.variable(&v).encode()),
                Operand::Switch { cases, default } => {
                    w.push(cases.len() as u32);
                    for (v, t) in cases {
                        w.extend(self.value(&v).encode());
                        w.push(t);
                    }
                    w.push(default);
                }
                Operand::PickSwitch { cases, default } => {
                    w.push(cases.len() as u32);
                    for (p, t) in cases {
                        w.push(p);
                        w.push(t);
                    }
                    w.push(default);
                }
                Operand::RangeSwitch { ranges, exact, default } => {
                    w.push(ranges.len() as u32);
                    for (a, b, t) in ranges {
                        w.extend(self.value(&a).encode());
                        w.extend(self.value(&b).encode());
                        w.push(t);
                    }
                    w.push(exact.len() as u32);
                    for (v, t) in exact {
                        w.extend(self.value(&v).encode());
                        w.push(t);
                    }
                    w.push(default);
                }
                Operand::PickProb(targets) => {
                    w.push(targets.len() as u32);
                    w.extend(targets);
                }
            }
        }
        Ok(w)
    }
    fn values_list(&self, words: &[u32], first: impl Fn(u32) -> u32) -> io::Result<Vec<u32>> {
        let mut out = Vec::with_capacity(words.len());
        let mut at = 0;
        while at < words.len() {
            out.push(first(words[at]));
            at += 1;
            let (v, used) = Value::decode(&words[at..]).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e.reason))?;
            out.extend(self.value(&v).encode());
            at += used;
        }
        Ok(out)
    }
}

#[derive(Default)]
struct Interner {
    lists: Vec<Vec<u32>>,
    index: HashMap<Vec<u32>, u32>,
}
impl Interner {
    fn add(&mut self, words: Vec<u32>) -> u32 {
        if let Some(&id) = self.index.get(&words) {
            return id;
        }
        if self.lists.len() == NONE as usize {
            self.lists.push(Vec::new());
        }
        let id = self.lists.len() as u32;
        self.index.insert(words.clone(), id);
        self.lists.push(words);
        id
    }
}

/// Return a renumbered copy of `dmb`. The result encodes the same world.
pub fn permute(dmb: &Dmb, opts: &PermuteOptions) -> io::Result<Dmb> {
    let mut rng = Rng(opts.seed ^ 0x5eed_0f_d3b);
    let safe = opts.preserve_semantics;
    let keep = if safe { opts.keep_strings.max(builtin_prefix(dmb)) } else { opts.keep_strings };
    let mut s_map = permutation_from(dmb.strings.len(), opts.strings, keep, &mut rng);
    let mut p_map = permutation(dmb.procs.len(), opts.procs, &mut rng);
    if safe {
        let mut var_names = vec![false; dmb.strings.len()];
        for v in &dmb.variables {
            if let Some(slot) = var_names.get_mut(v.name as usize) {
                *slot = true;
            }
        }
        s_map = constrain(s_map, &var_names);
        let named: Vec<bool> = dmb.procs.iter().map(|p| p.strings[0] != NONE).collect();
        p_map = constrain(p_map, &named);
    }
    let maps = Maps {
        c: class_permutation(dmb, opts.classes && !safe, &mut rng),
        p: p_map,
        s: s_map,
        v: permutation(dmb.variables.len(), opts.variables, &mut rng),
        i: permutation(dmb.instances.len(), opts.instances, &mut rng),
        m: permutation(dmb.mobs.len(), opts.mobs, &mut rng),
        r: permutation(dmb.resources.len(), opts.resources, &mut rng),
    };
    let list = |id: u32| -> Option<&Vec<u32>> { (id != NONE).then(|| dmb.lists.get(id as usize)).flatten() };
    let mut lists = Interner::default();
    let add = |lists: &mut Interner, words: Option<Vec<u32>>| words.map_or(NONE, |w| lists.add(w));
    let ids = |map: &[u32], words: &[u32]| words.iter().map(|&x| m(map, x)).collect::<Vec<_>>();

    let mut out = dmb.clone();
    // Classes.
    let mut classes = Vec::with_capacity(dmb.classes.len());
    for (ci, c) in dmb.classes.iter().enumerate() {
        let mut n = c.clone();
        let [path, parent, name, desc, icon, state] = c.initial_ids;
        n.initial_ids = [m(&maps.s, path), m(&maps.c, parent), m(&maps.s, name), m(&maps.s, desc), m(&maps.r, icon), m(&maps.s, state)];
        n.text = m(&maps.s, c.text);
        n.maptext = m(&maps.s, c.maptext);
        n.suffix = m(&maps.s, c.suffix);
        n.lists_and_procs[0] = add(&mut lists, list(c.verb_list_id()).map(|l| ids(&maps.p, l)));
        n.lists_and_procs[1] = add(&mut lists, list(c.proc_list_id()).map(|l| ids(&maps.p, l)));
        n.lists_and_procs[2] = m(&maps.p, c.initializer_proc_id());
        n.lists_and_procs[3] = add(&mut lists, list(c.initialized_variable_list_id()).map(|l| maps.values_list(l, |v| m(&maps.v, v))).transpose()?);
        n.lists_and_procs[4] = add(
            &mut lists,
            list(c.defining_variable_list_id()).map(|l| {
                let mut pairs: Vec<[u32; 2]> = l.chunks(2).map(|p| [m(&maps.v, p[0]), *p.get(1).unwrap_or(&0)]).collect();
                if opts.reverse_decls {
                    pairs.reverse();
                }
                pairs.concat()
            }),
        );
        n.overrides = add(&mut lists, list(c.overriding_variable_list_id()).map(|l| maps.values_list(l, |s| m(&maps.s, s))).transpose()?);
        let _ = ci;
        classes.push(n);
    }
    out.classes = apply(&classes, &maps.c);
    // Mobs.
    let mobs: Vec<_> = dmb
        .mobs
        .iter()
        .map(|mb| {
            let mut n = mb.clone();
            n.class = m(&maps.c, mb.class);
            n.key = m(&maps.s, mb.key);
            n
        })
        .collect();
    out.mobs = apply(&mobs, &maps.m);
    out.strings = apply(&dmb.strings, &maps.s);
    // Procs.
    let mut procs = Vec::with_capacity(dmb.procs.len());
    for (p, pr) in dmb.procs.iter().enumerate() {
        let mut n = pr.clone();
        if !dmb.is_reserved_proc_slot(p) {
            n.strings = pr.strings.map(|s| m(&maps.s, s));
            let [code, locals, args] = pr.code_locals_args;
            n.code_locals_args = [
                add(&mut lists, list(code).map(|l| maps.code(l)).transpose()?),
                add(&mut lists, list(locals).map(|l| ids(&maps.v, l))),
                add(
                    &mut lists,
                    list(args).map(|l| l.chunks(4).flat_map(|a| [a[0], a[1], m(&maps.v, a[2]), a[3]]).collect()),
                ),
            ];
        }
        procs.push(n);
    }
    out.procs = apply(&procs, &maps.p);
    // Variables.
    let vars: Vec<_> = dmb
        .variables
        .iter()
        .map(|v| {
            let mut n = v.clone();
            n.name = m(&maps.s, v.name);
            if v.kind != 42 && v.kind != 62 {
                n.value = maps.tagged(v.kind, v.value);
            }
            n
        })
        .collect();
    out.variables = apply(&vars, &maps.v);
    out.variable_footer = add(
        &mut lists,
        list(dmb.variable_footer).map(|l| {
            let mut pairs: Vec<[u32; 2]> = l.chunks(2).map(|p| [m(&maps.v, p[0]), *p.get(1).unwrap_or(&0)]).collect();
            if opts.reverse_footer {
                pairs.reverse();
            }
            pairs.concat()
        }),
    );
    out.proc_references = ids(&maps.p, &dmb.proc_references);
    // Instances.
    let insts: Vec<_> = dmb
        .instances
        .iter()
        .map(|i| {
            let mut n = i.clone();
            n.class = if i.kind == 8 { m(&maps.m, i.class) } else { m(&maps.c, i.class) };
            n.initializer = m(&maps.p, i.initializer);
            n
        })
        .collect();
    out.instances = apply(&insts, &maps.i);
    for (o, n) in dmb.map_objects.iter().zip(out.map_objects.iter_mut()) {
        n.instance = m(&maps.i, o.instance);
    }
    for (r, n) in dmb.grid.iter().zip(out.grid.iter_mut()) {
        n.turf = m(&maps.i, r.turf);
        n.area = m(&maps.i, r.area);
        n.contents = add(&mut lists, list(r.contents).map(|l| ids(&maps.i, l)));
    }
    out.resources = apply(&dmb.resources, &maps.r);
    // World.
    let w = &dmb.world;
    let ow = &mut out.world;
    ow.ids = [
        m(&maps.m, w.ids[0]),
        m(&maps.c, w.ids[1]),
        m(&maps.c, w.ids[2]),
        add(&mut lists, list(w.ids[3]).map(|l| ids(&maps.p, l))),
        m(&maps.p, w.ids[4]),
        m(&maps.s, w.ids[5]),
        m(&maps.s, w.ids[6]),
    ];
    ow.client = m(&maps.c, w.client);
    ow.image = m(&maps.c, w.image);
    ow.client_script = m(&maps.s, w.client_script);
    ow.client_script_files = ids(&maps.r, &w.client_script_files);
    ow.hub_password = m(&maps.s, w.hub_password);
    ow.server_name = m(&maps.s, w.server_name);
    ow.command_ids = w.command_ids.map(|s| m(&maps.s, s));
    ow.hub_channel_skin = [m(&maps.s, w.hub_channel_skin[0]), m(&maps.s, w.hub_channel_skin[1]), m(&maps.r, w.hub_channel_skin[2])];

    // List table: optionally shuffled, then every list reference is remapped.
    let n = lists.lists.len();
    let pl = permutation(n, opts.lists, &mut rng);
    let mut table: Vec<Vec<u32>> = vec![Vec::new(); n];
    for (old, words) in lists.lists.into_iter().enumerate() {
        table[pl[old] as usize] = words;
    }
    let l = |id: &mut u32| *id = m(&pl, *id);
    for c in &mut out.classes {
        l(&mut c.lists_and_procs[0]);
        l(&mut c.lists_and_procs[1]);
        l(&mut c.lists_and_procs[3]);
        l(&mut c.lists_and_procs[4]);
        l(&mut c.overrides);
    }
    for (p, pr) in out.procs.iter_mut().enumerate() {
        if pr.code_locals_args != [NONE; 3] || p != NONE as usize {
            pr.code_locals_args.iter_mut().for_each(l);
        }
    }
    for r in &mut out.grid {
        l(&mut r.contents);
    }
    l(&mut out.world.ids[3]);
    l(&mut out.variable_footer);
    out.lists = WordLists::from(table);
    out.validate_references()?;
    Ok(out)
}
