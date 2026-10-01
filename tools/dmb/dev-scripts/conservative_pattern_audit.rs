//! Read-only, deliberately bounded parity classification. Never alters the comparer.
use byond_dmb::{
    bytecode::{self, Instruction},
    compare::compare_proc_code,
    dmb::Dmb,
    operands::Variable,
};
use std::{
    collections::{BTreeMap, BTreeSet},
    io::{BufRead, Write},
};

fn plain_storage(words: &[u32]) -> bool {
    matches!(Variable::decode(words), Ok((Variable::Local(_) | Variable::Arg(_), used)) if used == words.len())
}
fn null_push(i: &Instruction) -> bool {
    (i.opcode == 0x60 && i.operands == [0, 0]) || (i.opcode == 0x33 && i.operands == [0xffe6])
}
/// Whole-body normalization only succeeds for decoded destination operands.
/// Interior branch entries prohibit every rewrite that would consume their instruction.
fn normalize(words: &[u32]) -> Option<(Vec<u32>, BTreeMap<&'static str, usize>)> {
    let all = bytecode::decode(words).ok()?;
    let boundaries: BTreeSet<_> = all.iter().map(|i| i.offset as u32).collect();
    let mut code: Vec<_> = all
        .into_iter()
        .filter(|i| !matches!(i.opcode, 0x84 | 0x85))
        .collect();
    let executable: BTreeMap<_, _> = code
        .iter()
        .map(|i| (i.offset as u32, i.offset as u32))
        .collect();
    let resolve = |target: u32| {
        boundaries
            .contains(&target)
            .then(|| executable.range(target..).next().map(|(_, &offset)| offset))
            .flatten()
    };
    let mut incoming = BTreeSet::new();
    for i in &mut code {
        let positions = i.branch_target_word_offsets().ok()?;
        for position in positions {
            let operand = position - i.offset - 1;
            let target = resolve(i.operands[operand])?;
            i.operands[operand] = target;
            incoming.insert(target as usize);
        }
    }
    let mut kept = Vec::new();
    let mut rules = BTreeMap::new();
    let mut at = 0;
    while at < code.len() {
        let i = &code[at];
        let next = code.get(at + 1);
        // Reading the flag followed immediately by discarding it neither changes
        // flag state nor stack state. Both entries must be private to fallthrough.
        if i.opcode == 0x36
            && next.is_some_and(|n| n.opcode == 0x51)
            && !incoming.contains(&i.offset)
            && !incoming.contains(&next.unwrap().offset)
        {
            *rules.entry("unused_flag_materialization").or_insert(0) += 1;
            at += 2;
            continue;
        }
        if i.opcode == 0x34
            && plain_storage(&i.operands)
            && next.is_some_and(|n| {
                n.opcode == 0x33 && n.operands == i.operands && !incoming.contains(&n.offset)
            })
        {
            let mut fused = i.clone();
            fused.opcode = 0x35;
            kept.push(fused);
            *rules.entry("local_store_reload").or_insert(0) += 1;
            at += 2;
            continue;
        }
        // Catch's exception value is already on the stack. Native sometimes
        // initializes its local to null immediately before overwriting it.
        if null_push(i)
            && code
                .get(at + 1)
                .is_some_and(|n| n.opcode == 0x34 && plain_storage(&n.operands))
            && code
                .get(at + 2)
                .is_some_and(|n| n.opcode == 0x34 && n.operands == code[at + 1].operands)
            && !incoming.contains(&code[at + 1].offset)
            && !incoming.contains(&code[at + 2].offset)
            && code[..at].last().is_some_and(|p| p.opcode == 0x12e)
        {
            // Redirect the handler's incoming entry at the null push to the
            // surviving assignment; this removes only an unobservable local write.
            let mut assignment = code[at + 2].clone();
            assignment.offset = i.offset;
            let reload = code.get(at + 3).is_some_and(|n| {
                n.opcode == 0x33
                    && n.operands == assignment.operands
                    && !incoming.contains(&n.offset)
            });
            if reload {
                assignment.opcode = 0x35;
                *rules.entry("local_store_reload").or_insert(0) += 1;
            }
            kept.push(assignment);
            *rules
                .entry("overwritten_catch_local_initialization")
                .or_insert(0) += 1;
            at += 3 + usize::from(reload);
            continue;
        }
        kept.push(i.clone());
        at += 1;
    }
    let mut offsets = BTreeMap::new();
    let mut total = 0;
    for i in &kept {
        offsets.insert(i.offset as u32, total as u32);
        total += 1 + i.operands.len();
    }
    let mut out = Vec::with_capacity(total);
    for mut i in kept {
        for position in i.branch_target_word_offsets().ok()? {
            let operand = position - i.offset - 1;
            i.operands[operand] = *offsets.get(&i.operands[operand])?;
        }
        out.push(i.opcode);
        out.extend(i.operands);
    }
    Some((out, rules))
}

#[cfg(test)]
mod table_tests {
    use super::normalize;

    #[test]
    fn probability_threshold_is_not_relocated_as_a_destination() {
        // The threshold equals an instruction boundary whose relocated offset changes.
        let words = [
            0x79, 1, 12, 12, 12, 0x34, 0xffd9, 0, 0x33, 0xffd9, 0, 0x51, 0,
        ];
        let (normalized, _) = normalize(&words).unwrap();
        assert_eq!(&normalized[..5], &[0x79, 1, 12, 9, 9]);
    }

    #[test]
    fn table_entry_into_reload_prevents_store_reload_fusion() {
        let words = [
            0x79, 1, 123, 8, 12, 0x34, 0xffd9, 0, 0x33, 0xffd9, 0, 0x51, 0,
        ];
        let (normalized, rules) = normalize(&words).unwrap();
        assert_eq!(normalized, words);
        assert!(rules.is_empty());
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = std::env::args().collect();
    if args.len() != 5 {
        return Err(
            "usage: conservative_pattern_audit NATIVE.dmb ACTUAL.dmb PARITY.ndjson OUTPUT.ndjson"
                .into(),
        );
    }
    let mut native = Dmb::from_bytes(&std::fs::read(&args[1])?)?;
    let mut actual = Dmb::from_bytes(&std::fs::read(&args[2])?)?;
    let mut output = std::fs::File::create(&args[4])?;
    let mut checked = 0;
    let mut classified = 0;
    let mut counts = BTreeMap::<String, usize>::new();
    for line in std::io::BufReader::new(std::fs::File::open(&args[3])?).lines() {
        let row: serde_json::Value = serde_json::from_str(&line?)?;
        if row["section"] != "classification"
            || !row["category"]
                .as_str()
                .is_some_and(|s| s.starts_with("mixed_"))
        {
            continue;
        }
        let n = row["native_proc"].as_u64().ok_or("native proc missing")? as usize;
        let a = row["translated_proc"]
            .as_u64()
            .ok_or("translated proc missing")? as usize;
        checked += 1;
        let (Some(n_words), Some(a_words)) = (native.proc_code_words(n), actual.proc_code_words(a))
        else {
            continue;
        };
        let (Some((n_norm, n_rules)), Some((a_norm, a_rules))) =
            (normalize(n_words), normalize(a_words))
        else {
            continue;
        };
        if n_rules.is_empty() && a_rules.is_empty() {
            continue;
        }
        // Give each body a private temporary list; restore afterward. All cross-table
        // identities and argument metadata still pass through the strict comparer.
        let n_old = native.procs[n].code_locals_args[0];
        let a_old = actual.procs[a].code_locals_args[0];
        native.procs[n].code_locals_args[0] = native.lists.len() as u32;
        actual.procs[a].code_locals_args[0] = actual.lists.len() as u32;
        native.lists.push(n_norm);
        actual.lists.push(a_norm);
        let differences = compare_proc_code(
            &native,
            n,
            &actual,
            a,
            row["path"].as_str().unwrap_or(""),
            1,
            true,
        );
        native.procs[n].code_locals_args[0] = n_old;
        actual.procs[a].code_locals_args[0] = a_old;
        native.lists.pop();
        actual.lists.pop();
        if !differences.is_empty() {
            continue;
        }
        classified += 1;
        let mut used = BTreeMap::new();
        for (rule, count) in n_rules.into_iter().chain(a_rules) {
            *used.entry(rule).or_insert(0) += count;
        }
        for rule in used.keys() {
            *counts.entry((*rule).into()).or_insert(0) += 1;
        }
        writeln!(
            output,
            "{}",
            serde_json::json!({"path":row["path"],"native_proc":n,"translated_proc":a,"category":"conservative_proven_patterns","rules":used})
        )?;
    }
    println!(
        "{}",
        serde_json::json!({"mixed_pairs_checked":checked,"whole_bodies_classified":classified,"procedures_by_rule":counts})
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn native_paired_stack_patterns_match_after_bounded_rewrites() {
        use byond_dmb::{opendream::OpenDreamProgram, translate::translate_named_debug};
        let input = OpenDreamProgram::from_slice(include_bytes!(
            "../fixtures/lowering/flow_stack_patterns.json"
        ))
        .unwrap();
        let baseline = OpenDreamProgram::from_slice(include_bytes!(
            "../fixtures/native_template_savefile_5161687.json"
        ))
        .unwrap();
        let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
        let mut native = Dmb::from_bytes(include_bytes!(
            "../fixtures/lowering/flow_stack_patterns.bin"
        ))
        .unwrap();
        let mut actual = translate_named_debug(
            &input,
            &baseline,
            &template,
            std::path::Path::new("."),
            None,
            true,
        )
        .unwrap()
        .dmb;
        for name in [
            "flow_stack_local",
            "flow_stack_step",
            "flow_stack_catch_loop",
        ] {
            let path = format!("/proc/{name}");
            let n = native
                .procs
                .iter()
                .position(|p| native.string(p.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            let a = actual
                .procs
                .iter()
                .position(|p| actual.string(p.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            assert!(
                !compare_proc_code(&native, n, &actual, a, &path, 1, true).is_empty(),
                "{name} must demonstrate a real native layout difference"
            );
            let (nw, nr) = normalize(native.proc_code_words(n).unwrap()).unwrap();
            let (aw, ar) = normalize(actual.proc_code_words(a).unwrap()).unwrap();
            assert!(!nr.is_empty() || !ar.is_empty());
            if name == "flow_stack_catch_loop" {
                assert!(nr.contains_key("overwritten_catch_local_initialization"));
            }
            native.procs[n].code_locals_args[0] = native.lists.len() as u32;
            actual.procs[a].code_locals_args[0] = actual.lists.len() as u32;
            native.lists.push(nw);
            actual.lists.push(aw);
            assert!(
                compare_proc_code(&native, n, &actual, a, &path, 1, true).is_empty(),
                "{name}"
            );
        }
    }
    #[test]
    fn local_store_reload_matches_expression_store() {
        assert_eq!(
            normalize(&[0x34, 0xffda, 0, 0x33, 0xffda, 0, 0x12, 0])
                .unwrap()
                .0,
            vec![0x35, 0xffda, 0, 0x12, 0]
        );
        assert!(
            normalize(&[0x34, 0xffdc, 0xffce, 123, 0x33, 0xffdc, 0xffce, 123, 0])
                .unwrap()
                .1
                .is_empty()
        );
    }
    #[test]
    fn private_unused_flag_pair_disappears_but_common_pop_survives() {
        assert_eq!(normalize(&[0x86, 0x36, 0x51, 0]).unwrap().0, vec![0x86, 0]);
        assert!(normalize(&[0xf, 3, 0x36, 0x51, 0]).unwrap().1.is_empty());
        assert!(normalize(&[0xf, 2, 0x36, 0x51, 0]).unwrap().1.is_empty());
    }
    #[test]
    fn incoming_reload_prevents_fusion() {
        assert!(normalize(&[0xf, 5, 0x34, 0xffda, 0, 0x33, 0xffda, 0, 0])
            .unwrap()
            .1
            .is_empty());
    }
    #[test]
    fn catch_local_overwrite_is_bounded_and_relocated() {
        let out = normalize(&[0x12e, 11, 0x60, 0, 0, 0x34, 0xffda, 0, 0x34, 0xffda, 0, 0]).unwrap();
        assert_eq!(out.0, vec![0x12e, 5, 0x34, 0xffda, 0, 0]);
        assert!(
            normalize(&[0x60, 0, 0, 0x34, 0xffda, 0, 0x34, 0xffda, 0, 0])
                .unwrap()
                .1
                .is_empty()
        );
    }
}
