//! Read-only bounded keyed control-flow audit. Does not change production comparison.
//! Exact cache-selector differences remain unresolved. Unreachable bodies are excluded.
use byond_dmb::{
    bytecode::{self, Instruction, Operand},
    dmb::Dmb,
    operands::{Value, ValueKind, Variable},
};
use std::collections::{BTreeMap, BTreeSet, VecDeque};
fn s(d: &Dmb, x: u32) -> String {
    format!("{:?}", d.string(x))
}
fn p(d: &Dmb, x: u32) -> String {
    d.procs
        .get(x as usize)
        .map(|p| s(d, p.strings[0]))
        .unwrap_or_else(|| format!("invalidproc{x}"))
}
fn v(d: &Dmb, x: Value) -> String {
    match x.kind() {
        ValueKind::String => format!("string{}", s(d, x.id())),
        ValueKind::Number => format!("number{:?}", x.number_bits()),
        ValueKind::Null => "null".into(),
        ValueKind::MovablePath
        | ValueKind::AtomPath
        | ValueKind::DatumPath
        | ValueKind::AreaPath
        | ValueKind::ImagePath
        | ValueKind::BuiltinPath => format!(
            "type{}:{}",
            x.tag(),
            d.classes
                .get(x.id() as usize)
                .map(|c| s(d, c.initial_ids[0]))
                .unwrap_or_default()
        ),
        ValueKind::Resource => format!(
            "resource{:?}",
            d.resources.get(x.id() as usize).map(|r| (r.kind, r.id))
        ),
        _ => format!("unsupported{x:?}"),
    }
}
fn var(d: &Dmb, x: &Variable) -> String {
    use Variable::*;
    match x {
        Field(id) => format!("field{}", s(d, *id)),
        Global(id) => format!(
            "global{}",
            d.variables
                .get(*id as usize)
                .map(|x| s(d, x.name))
                .unwrap_or_default()
        ),
        DynamicProc(id) => format!("proc{}", s(d, *id)),
        DynamicVerb(id) => format!("verb{}", s(d, *id)),
        StaticProc(id) => format!(
            "proc{}",
            d.procs
                .get(*id as usize)
                .map(|x| s(d, x.strings[1]))
                .unwrap_or_default()
        ),
        StaticVerb(id) => format!(
            "verb{}",
            d.procs
                .get(*id as usize)
                .map(|x| s(d, x.strings[1]))
                .unwrap_or_default()
        ),
        SetCache(a, b) => format!("setcache({},{})", var(d, a), var(d, b)),
        Initial(a) => format!("initial({})", var(d, a)),
        IsSaved(a) => format!("issaved({})", var(d, a)),
        _ => format!("{x:?}"),
    }
}
fn code(d: &Dmb, id: usize) -> Vec<Instruction> {
    bytecode::decode(d.proc_code_words(id).unwrap())
        .unwrap()
        .into_iter()
        .filter(|x| !matches!(x.opcode, 0x84 | 0x85))
        .collect()
}
fn target(c: &[Instruction], t: u32) -> Result<usize, String> {
    c.iter()
        .position(|x| x.offset >= t as usize)
        .ok_or_else(|| format!("bad target{t}"))
}
fn chase(c: &[Instruction], mut at: usize) -> Result<usize, String> {
    let mut seen = BTreeSet::new();
    while let Some(i) = c.get(at) {
        if i.opcode != 0xf {
            return Ok(at);
        }
        if !seen.insert(at) {
            return Err("jump cycle".into());
        }
        at = target(c, i.operands[0])?;
    }
    Ok(at)
}
fn edges(
    d: &Dmb,
    c: &[Instruction],
    i: &Instruction,
) -> Result<Option<BTreeMap<String, usize>>, String> {
    let mut edges = BTreeMap::new();
    let mut add = |key: String, t: u32| -> Result<(), String> {
        let dst = chase(c, target(c, t)?)?;
        let mut occurrence = 0;
        while edges.contains_key(&format!("{key}#{occurrence}")) {
            occurrence += 1;
        }
        edges.insert(format!("{key}#{occurrence}"), dst);
        Ok(())
    };
    for o in i.typed_operands().map_err(|e| format!("{e:?}"))? {
        match o {
            Operand::Switch { cases, default } => {
                for (k, t) in cases {
                    add(v(d, k), t)?
                }
                add("DEFAULT".into(), default)?
            }
            Operand::RangeSwitch {
                ranges,
                exact,
                default,
            } => {
                // Reordering overlapping ranges/exact cases may change which
                // effect runs. Only accept disjoint ranges unless both targets
                // are the same; preserve duplicate exact-case occurrence order.
                for (index, (lo, hi, dst)) in ranges.iter().enumerate() {
                    let (lo, hi) = (
                        f32::from_bits(lo.number_bits().ok_or("nonnumeric range")?),
                        f32::from_bits(hi.number_bits().ok_or("nonnumeric range")?),
                    );
                    if lo.is_nan() || hi.is_nan() || lo > hi {
                        return Err("invalid range bounds".into());
                    }
                    for (other_lo, other_hi, other_dst) in ranges.iter().skip(index + 1) {
                        let other_lo =
                            f32::from_bits(other_lo.number_bits().ok_or("nonnumeric range")?);
                        let other_hi =
                            f32::from_bits(other_hi.number_bits().ok_or("nonnumeric range")?);
                        if lo <= other_hi && other_lo <= hi && dst != other_dst {
                            return Err("overlapping range precedence".into());
                        }
                    }
                    for (value, other_dst) in &exact {
                        if let Some(bits) = value.number_bits() {
                            let value = f32::from_bits(bits);
                            if lo <= value && value <= hi && dst != other_dst {
                                return Err("range/exact precedence".into());
                            }
                        }
                    }
                }
                for (lo, hi, t) in ranges {
                    add(format!("range:{}:{}", v(d, lo), v(d, hi)), t)?
                }
                for (k, t) in exact {
                    add(format!("exact:{}", v(d, k)), t)?
                }
                add("DEFAULT".into(), default)?
            }
            Operand::PickSwitch { cases, default } => {
                for (k, t) in cases {
                    add(format!("pick{k}"), t)?
                }
                add("DEFAULT".into(), default)?
            }
            _ => {}
        }
    }
    Ok((!edges.is_empty()).then_some(edges))
}
fn operands(d: &Dmb, i: &Instruction) -> Result<Vec<String>, String> {
    let branches = i
        .branch_target_word_offsets()
        .map_err(|e| format!("{e:?}"))?;
    let mut at = i.offset + 1;
    let mut out = vec![];
    for (ix, o) in i
        .typed_operands()
        .map_err(|e| format!("{e:?}"))?
        .into_iter()
        .enumerate()
    {
        let (key, len) = match o {
            Operand::Word(w) => {
                let text = if branches.contains(&at) {
                    "TARGET".into()
                } else if ix == 0 && matches!(i.opcode, 2 | 4 | 0x84) {
                    s(d, w)
                } else if i.opcode == 0x30 && ix == 1 || i.opcode == 0xcd && ix == 0 {
                    p(d, w)
                } else {
                    format!("word{w}")
                };
                (text, 1)
            }
            Operand::Variable(x) => {
                let len = x.encode().len();
                (var(d, &x), len)
            }
            Operand::Value(x) => {
                let len = x.encode().len();
                (v(d, x), len)
            }
            _ => return Err("unsupported non-switch operand".into()),
        };
        if key.starts_with("unsupported") {
            return Err(key);
        }
        out.push(key);
        at += len;
    }
    Ok(out)
}
fn audit(n: &Dmb, ni: usize, a: &Dmb, ai: usize) -> Result<usize, String> {
    audit_code(n, code(n, ni), a, code(a, ai))
}
fn audit_code(
    n: &Dmb,
    nc: Vec<Instruction>,
    a: &Dmb,
    ac: Vec<Instruction>,
) -> Result<usize, String> {
    let mut queue = VecDeque::from([(0, 0)]);
    let mut visited = BTreeSet::new();
    let mut keyed = 0;
    while let Some((x, y)) = queue.pop_front() {
        let x = chase(&nc, x)?;
        let y = chase(&ac, y)?;
        if !visited.insert((x, y)) {
            continue;
        }
        match (nc.get(x), ac.get(y)) {
            (None, None) => continue,
            (Some(i), Some(j)) => {
                if i.opcode != j.opcode {
                    return Err(format!("opcode {x}/{y}:{:x}/{:x}", i.opcode, j.opcode));
                }
                let ne = edges(n, &nc, i)?;
                let ae = edges(a, &ac, j)?;
                if let (Some(ne), Some(ae)) = (ne, ae) {
                    if ne.keys().ne(ae.keys()) {
                        return Err(format!("switch keys {x}/{y}"));
                    }
                    keyed += 1;
                    for (k, t) in ne {
                        queue.push_back((t, ae[&k]));
                    }
                    continue;
                }
                let no = operands(n, i)?;
                let ao = operands(a, j)?;
                if no != ao {
                    return Err(format!("operands {x}/{y}: {no:?} / {ao:?}"));
                }
                let nt = i.branch_targets().map_err(|e| format!("{e:?}"))?;
                let at = j.branch_targets().map_err(|e| format!("{e:?}"))?;
                if nt.len() != at.len() {
                    return Err("branch arity".into());
                }
                for (t, u) in nt.into_iter().zip(at) {
                    queue.push_back((target(&nc, t)?, target(&ac, u)?));
                }
                if !matches!(i.opcode, 0 | 0x12 | 0x12d) {
                    queue.push_back((x + 1, y + 1));
                }
            }
            _ => return Err(format!("end {x}/{y}")),
        }
    }
    Ok(keyed)
}
fn main() {
    let args: Vec<_> = std::env::args().collect();
    let n = Dmb::from_bytes(&std::fs::read(&args[1]).unwrap()).unwrap();
    let a = Dmb::from_bytes(&std::fs::read(&args[2]).unwrap()).unwrap();
    let mut proved = 0;
    for line in std::fs::read_to_string(&args[3]).unwrap().lines() {
        let z: Vec<_> = line.splitn(3, '\t').collect();
        match audit(&n, z[0].parse().unwrap(), &a, z[1].parse().unwrap()) {
            Ok(k) => {
                proved += 1;
                println!("{} PASS keyed={k}", z[2])
            }
            Err(e) => println!("{} UNRESOLVED {e}", z[2]),
        }
    }
    println!("PROVED {proved}");
}
#[cfg(test)]
mod tests {
    use super::*;
    fn template() -> Dmb {
        Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap()
    }
    fn decode(w: &[u32]) -> Vec<Instruction> {
        bytecode::decode(w).unwrap()
    }
    #[test]
    fn relocated_keyed_arms_preserve_values() {
        let d = template();
        let n = decode(&[0x78, 1, 0, 0, 6, 9, 0x50, 11, 0x12, 0x50, 22, 0x12]);
        let a = decode(&[0x78, 1, 0, 0, 9, 6, 0x50, 22, 0x12, 0x50, 11, 0x12]);
        assert_eq!(audit_code(&d, n, &d, a), Ok(1));
    }
    #[test]
    fn wrong_case_association_and_key_are_rejected() {
        let d = template();
        let n = decode(&[0x78, 1, 0, 0, 6, 9, 0x50, 11, 0x12, 0x50, 22, 0x12]);
        let wrong = decode(&[0x78, 1, 0, 0, 6, 9, 0x50, 22, 0x12, 0x50, 11, 0x12]);
        assert!(audit_code(&d, n.clone(), &d, wrong).is_err());
        let key = decode(&[0x78, 1, 6, 0, 6, 9, 0x50, 11, 0x12, 0x50, 22, 0x12]);
        assert!(audit_code(&d, n, &d, key).is_err());
    }
    #[test]
    fn relocated_range_arms_match_but_overlapping_precedence_is_unresolved() {
        let d = template();
        let n = decode(&[
            0x7a, 1, 0x102a, 0x3f80, 0, 0x102a, 0x4000, 0, 11, 0, 14, 0x50, 11, 0x12, 0x50, 22,
            0x12,
        ]);
        let a = decode(&[
            0x7a, 1, 0x102a, 0x3f80, 0, 0x102a, 0x4000, 0, 14, 0, 11, 0x50, 22, 0x12, 0x50, 11,
            0x12,
        ]);
        assert_eq!(audit_code(&d, n, &d, a), Ok(1));
        let overlap = decode(&[
            0x7a, 2, 0x102a, 0x3f80, 0, 0x102a, 0x4000, 0, 18, 0x102a, 0x3f80, 0, 0x102a, 0x4040,
            0, 21, 0, 24, 0x50, 11, 0x12, 0x50, 22, 0x12, 0x50, 33, 0x12,
        ]);
        assert!(edges(&d, &overlap, &overlap[0]).is_err());
    }
}
