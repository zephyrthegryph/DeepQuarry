//! Renumber the class table of a world in place, rewriting every class reference: parent
//! links, mob and instance records, typed values in variable records, class value lists and
//! bytecode operands, and the world's class slots. List IDs do not change; each list is
//! rewritten once.
use super::*;
use crate::bytecode::{self, Instruction, Operand};
use crate::operands::{Value, ValueKind, Variable as VariableOperand};
use std::collections::HashSet;

fn remap(map: &[u32], id: u32) -> u32 {
    if id == NONE {
        NONE
    } else {
        map.get(id as usize).copied().unwrap_or(id)
    }
}

fn class_tagged(tag: u8, id: u32) -> bool {
    match ValueKind::from_tag(tag) {
        ValueKind::ClientPath
        | ValueKind::ListPath
        | ValueKind::FilePath
        | ValueKind::SavefilePath
            if id == 0 =>
        {
            false
        }
        ValueKind::MovablePath
        | ValueKind::AtomPath
        | ValueKind::AreaPath
        | ValueKind::DatumPath
        | ValueKind::SavefilePath
        | ValueKind::FilePath
        | ValueKind::ListPath
        | ValueKind::ImagePath
        | ValueKind::ClientPath
        | ValueKind::BuiltinPath => true,
        _ => false,
    }
}

fn value(map: &[u32], v: &Value) -> Value {
    if v.kind() == ValueKind::Number || !class_tagged(v.tag(), v.id()) {
        return *v;
    }
    let id = remap(map, v.id());
    Value {
        tag_word: (v.tag_word & !0xff00) | ((id >> 8) & 0xff00),
        data_word: (v.data_word & !0xffff) | (id & 0xffff),
        extra_word: v.extra_word,
    }
}

fn invalid(reason: impl Into<String>) -> io::Error {
    io::Error::new(ErrorKind::InvalidData, reason.into())
}

fn instruction(map: &[u32], i: &Instruction) -> io::Result<Vec<u32>> {
    let ops = i.typed_operands().map_err(|e| invalid(e.reason))?;
    let mut w = vec![i.opcode];
    for op in ops {
        match op {
            Operand::Word(x) => w.push(x),
            Operand::Value(v) => w.extend(value(map, &v).encode()),
            Operand::Variable(v) => w.extend(variable(&v).encode()),
            Operand::Switch { cases, default } => {
                w.push(cases.len() as u32);
                for (v, t) in cases {
                    w.extend(value(map, &v).encode());
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
            Operand::RangeSwitch {
                ranges,
                exact,
                default,
            } => {
                w.push(ranges.len() as u32);
                for (a, b, t) in ranges {
                    w.extend(value(map, &a).encode());
                    w.extend(value(map, &b).encode());
                    w.push(t);
                }
                w.push(exact.len() as u32);
                for (v, t) in exact {
                    w.extend(value(map, &v).encode());
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

/// Variable operands name strings, variables and procedures, never classes.
fn variable(v: &VariableOperand) -> VariableOperand {
    v.clone()
}

fn code(map: &[u32], words: &[u32]) -> io::Result<Vec<u32>> {
    let ins = bytecode::decode(words).map_err(|e| invalid(e.reason))?;
    let mut out = Vec::with_capacity(words.len());
    for i in &ins {
        out.extend(instruction(map, i)?);
    }
    if out.len() != words.len() {
        return Err(invalid("renumbered code changed length"));
    }
    Ok(out)
}

/// (name or variable id, value) pairs.
fn values_list(map: &[u32], words: &[u32]) -> io::Result<Vec<u32>> {
    let mut out = Vec::with_capacity(words.len());
    let mut at = 0;
    while at < words.len() {
        out.push(words[at]);
        at += 1;
        let (v, used) = Value::decode(&words[at..]).map_err(|e| invalid(e.reason))?;
        out.extend(value(map, &v).encode());
        at += used;
    }
    Ok(out)
}

impl Dmb {
    /// Move class `i` to `map[i]` in a table of `len` classes; slots no class moves to hold
    /// `placeholder`. Every class reference in the world follows.
    pub fn renumber_classes(
        &mut self,
        map: &[u32],
        len: usize,
        placeholder: &Class,
    ) -> io::Result<()> {
        if map.len() != self.classes.len() {
            return Err(invalid("class map does not cover the class table"));
        }
        let mut targets = HashSet::with_capacity(map.len());
        if map.iter().any(|&to| to as usize >= len || !targets.insert(to)) {
            return Err(invalid("class map is not injective into the new table"));
        }
        let mut code_lists = HashSet::new();
        let mut value_lists = HashSet::new();
        for class in &self.classes {
            for id in [class.initialized_variable_list_id(), class.overriding_variable_list_id()] {
                if id != NONE {
                    value_lists.insert(id);
                }
            }
        }
        for (index, proc) in self.procs.iter().enumerate() {
            if self.is_reserved_proc_slot(index) {
                continue;
            }
            let id = proc.code_locals_args[0];
            if id != NONE {
                code_lists.insert(id);
            }
        }
        if code_lists.iter().any(|id| value_lists.contains(id)) {
            return Err(invalid("a list is both code and class values"));
        }
        for id in code_lists {
            let Some(words) = self.lists.get(id as usize) else {
                continue;
            };
            let words = code(map, words)?;
            *self.lists.get_mut(id as usize).expect("listed") = words;
        }
        for id in value_lists {
            let Some(words) = self.lists.get(id as usize) else {
                continue;
            };
            let words = values_list(map, words)?;
            *self.lists.get_mut(id as usize).expect("listed") = words;
        }
        let mut classes = vec![placeholder.clone(); len];
        for (old, class) in std::mem::take(&mut self.classes).into_iter().enumerate() {
            let mut class = class;
            class.initial_ids[1] = remap(map, class.initial_ids[1]);
            classes[map[old] as usize] = class;
        }
        self.classes = classes;
        for mob in &mut self.mobs {
            mob.class = remap(map, mob.class);
        }
        for instance in &mut self.instances {
            if instance.kind != 8 {
                instance.class = remap(map, instance.class);
            }
        }
        for record in &mut self.variables {
            if record.kind != 42 && record.kind != 62 && class_tagged(record.kind, record.value) {
                record.value = remap(map, record.value);
            }
        }
        self.world.ids[1] = remap(map, self.world.ids[1]);
        self.world.ids[2] = remap(map, self.world.ids[2]);
        self.world.client = remap(map, self.world.client);
        self.world.image = remap(map, self.world.image);
        Ok(())
    }
}
