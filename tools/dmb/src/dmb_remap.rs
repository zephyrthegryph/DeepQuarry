//! In-place procedure-table renumbering for stable incremental output
//! (tools/dmb/doc/structural_change_set.md, addendum). The named-procedure
//! table order is runtime-observable (`typesof(/T/proc)`), so an appended
//! procedure is moved to its fresh position and every procedure reference is
//! renumbered consistently. List and variable IDs do not change: list rows are
//! rewritten in place, so a row shared between a procedure-ID role and any
//! other role is refused (rewriting it would corrupt the other referrer).
use super::*;
use crate::bytecode::{self, Operand};
use crate::operands::{Value, ValueKind, Variable};

fn mapped(map: &[u32], id: u32) -> u32 {
    if id == NONE {
        NONE
    } else {
        map.get(id as usize).copied().unwrap_or(id)
    }
}
fn value(map: &[u32], v: &Value) -> Value {
    if v.kind() != ValueKind::ProcPath {
        return *v;
    }
    let id = mapped(map, v.id());
    Value {
        tag_word: (v.tag_word & !0xff00) | ((id >> 8) & 0xff00),
        data_word: (v.data_word & !0xffff) | (id & 0xffff),
        extra_word: v.extra_word,
    }
}
fn variable(map: &[u32], v: &Variable) -> Variable {
    use Variable::*;
    match v {
        StaticProc(id) => StaticProc(mapped(map, *id)),
        StaticVerb(id) => StaticVerb(mapped(map, *id)),
        SetCache(a, b) => SetCache(Box::new(variable(map, a)), Box::new(variable(map, b))),
        Initial(x) => Initial(Box::new(variable(map, x))),
        IsSaved(x) => IsSaved(Box::new(variable(map, x))),
        other => other.clone(),
    }
}
fn invalid(reason: &str) -> io::Error {
    io::Error::new(ErrorKind::InvalidData, reason.to_string())
}
fn code(map: &[u32], words: &[u32]) -> io::Result<Vec<u32>> {
    let instructions = bytecode::decode(words).map_err(|e| invalid(&e.reason))?;
    let mut out = Vec::with_capacity(words.len());
    for instruction in &instructions {
        let operands = instruction
            .typed_operands()
            .map_err(|e| invalid(&e.reason))?;
        out.push(instruction.opcode);
        for (index, operand) in operands.into_iter().enumerate() {
            match operand {
                Operand::Word(x) => out.push(
                    if (instruction.opcode == 0x30 && index == 1)
                        || (instruction.opcode == 0xcd && index == 0)
                    {
                        mapped(map, x)
                    } else {
                        x
                    },
                ),
                Operand::Value(v) => out.extend(value(map, &v).encode()),
                Operand::Variable(v) => out.extend(variable(map, &v).encode()),
                Operand::Switch { cases, default } => {
                    out.push(cases.len() as u32);
                    for (v, target) in cases {
                        out.extend(value(map, &v).encode());
                        out.push(target);
                    }
                    out.push(default);
                }
                Operand::PickSwitch { cases, default } => {
                    out.push(cases.len() as u32);
                    for (p, target) in cases {
                        out.push(p);
                        out.push(target);
                    }
                    out.push(default);
                }
                Operand::RangeSwitch {
                    ranges,
                    exact,
                    default,
                } => {
                    out.push(ranges.len() as u32);
                    for (a, b, target) in ranges {
                        out.extend(value(map, &a).encode());
                        out.extend(value(map, &b).encode());
                        out.push(target);
                    }
                    out.push(exact.len() as u32);
                    for (v, target) in exact {
                        out.extend(value(map, &v).encode());
                        out.push(target);
                    }
                    out.push(default);
                }
                Operand::PickProb(targets) => {
                    out.push(targets.len() as u32);
                    out.extend(targets);
                }
            }
        }
    }
    if out.len() != words.len() {
        return Err(invalid("re-encoded code changed length"));
    }
    Ok(out)
}
fn values_list(map: &[u32], words: &[u32]) -> io::Result<Vec<u32>> {
    let mut out = Vec::with_capacity(words.len());
    let mut at = 0;
    while at < words.len() {
        out.push(words[at]);
        at += 1;
        let (v, used) = Value::decode(&words[at..]).map_err(|e| invalid(&e.reason))?;
        out.extend(value(map, &v).encode());
        at += used;
    }
    Ok(out)
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Role {
    ProcIds,
    Code,
    Values,
    Other,
}

impl Dmb {
    /// Renumber the procedure table by `map` (`map[old] = new`, a
    /// permutation of `0..procs.len()` that keeps any reserved slot fixed).
    /// Only rows that carry procedure IDs are rewritten. Errors leave `self`
    /// unchanged only up to the role check; callers discard the model on error.
    pub fn remap_procedures(&mut self, map: &[u32]) -> io::Result<()> {
        if map.len() != self.procs.len() {
            return Err(invalid("procedure map length"));
        }
        let mut seen = vec![false; map.len()];
        for (old, &new) in map.iter().enumerate() {
            let slot = seen.get_mut(new as usize).ok_or_else(|| invalid("procedure map range"))?;
            if std::mem::replace(slot, true) {
                return Err(invalid("procedure map is not a permutation"));
            }
            if (self.is_reserved_proc_slot(old) || new == NONE) && old as u32 != new {
                return Err(invalid("procedure map moves a reserved slot"));
            }
        }
        // Classify every list row by the role its referrers give it.
        let mut roles: HashMap<u32, Role> = HashMap::new();
        let mut claim = |id: u32, role: Role| -> io::Result<()> {
            if id == NONE {
                return Ok(());
            }
            match roles.insert(id, role) {
                Some(previous) if previous != role => {
                    Err(invalid("list row shared between procedure and other roles"))
                }
                _ => Ok(()),
            }
        };
        for class in &self.classes {
            claim(class.verb_list_id(), Role::ProcIds)?;
            claim(class.proc_list_id(), Role::ProcIds)?;
            claim(class.initialized_variable_list_id(), Role::Values)?;
            claim(class.overriding_variable_list_id(), Role::Values)?;
            claim(class.defining_variable_list_id(), Role::Other)?;
        }
        for (index, proc_) in self.procs.iter().enumerate() {
            if self.is_reserved_proc_slot(index) {
                continue;
            }
            let [code, locals, args] = proc_.code_locals_args;
            claim(code, Role::Code)?;
            claim(locals, Role::Other)?;
            claim(args, Role::Other)?;
        }
        claim(self.world.ids[3], Role::ProcIds)?;
        claim(self.variable_footer, Role::Other)?;
        for cell in &self.grid {
            claim(cell.contents, Role::Other)?;
        }
        // Rewrite rows (each once).
        for (&id, &role) in &roles {
            let Some(words) = self.lists.get(id as usize) else {
                continue;
            };
            let rewritten = match role {
                Role::ProcIds => words.iter().map(|&p| mapped(map, p)).collect(),
                Role::Code => code(map, words)?,
                Role::Values => values_list(map, words)?,
                Role::Other => continue,
            };
            if &rewritten != words {
                *self.lists.get_mut(id as usize).expect("listed row") = rewritten;
            }
        }
        for class in &mut self.classes {
            class.lists_and_procs[2] = mapped(map, class.lists_and_procs[2]);
        }
        for v in &mut self.variables {
            if v.kind != 42 && v.kind != 62 && ValueKind::from_tag(v.kind) == ValueKind::ProcPath {
                v.value = mapped(map, v.value);
            }
        }
        for reference in &mut self.proc_references {
            *reference = mapped(map, *reference);
        }
        for instance in &mut self.instances {
            instance.initializer = mapped(map, instance.initializer);
        }
        self.world.ids[4] = mapped(map, self.world.ids[4]);
        let mut procs = self.procs.clone();
        for (old, proc_) in self.procs.drain(..).enumerate() {
            procs[map[old] as usize] = proc_;
        }
        self.procs = procs;
        Ok(())
    }
}
