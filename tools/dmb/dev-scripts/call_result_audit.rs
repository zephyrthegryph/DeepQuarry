//! Exhaustive discarded-call witness audit; does not normalize receiver operands.
use byond_dmb::{bytecode, compare, dmb::Dmb};
use std::collections::BTreeMap;
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    let native = Dmb::from_bytes(&std::fs::read(&args[0])?)?;
    let actual = Dmb::from_bytes(&std::fs::read(&args[1])?)?;
    let report = std::fs::read_to_string(&args[2])?;
    let mut groups = BTreeMap::<String, usize>::new();
    let mut witnesses = Vec::new();
    for line in report.lines() {
        let row: serde_json::Value = serde_json::from_str(line)?;
        if row["category"] != "call_statement_opcode_encoding" {
            continue;
        }
        let ai = row["native_proc"].as_u64().unwrap() as usize;
        let bi = row["translated_proc"].as_u64().unwrap() as usize;
        let path = row["path"].as_str().unwrap();
        let read = |dmb: &Dmb, id| {
            bytecode::decode(dmb.proc_code_words(id).unwrap())
                .unwrap()
                .into_iter()
                .filter(|i| !matches!(i.opcode, 0x84 | 0x85))
                .collect::<Vec<_>>()
        };
        let left = read(&native, ai);
        let right = read(&actual, bi);
        let diffs = compare::compare_proc_code(&native, ai, &actual, bi, path, usize::MAX, true);
        let opcode_only = diffs.iter().all(|d| d.field.ends_with(".opcode"));
        let mut discarded = true;
        for (index, (a, b)) in left.iter().zip(&right).enumerate() {
            if !matches!((a.opcode, b.opcode), (0x29, 0x2a) | (0x2a, 0x29)) {
                continue;
            }
            if left.get(index + 1).is_none_or(|i| i.opcode != 0x51)
                || right.get(index + 1).is_none_or(|i| i.opcode != 0x51)
            {
                discarded = false;
            }
        }
        let group = match (opcode_only, discarded) {
            (true, true) => "same operands; differing call results immediately discarded",
            (false, true) => "discarded call difference plus unresolved operand differences",
            _ => "requires result-flow investigation",
        };
        *groups.entry(group.into()).or_default() += 1;
        if !discarded && witnesses.len() < 30 {
            witnesses.push((path.to_string(), ai, bi));
        }
    }
    println!("groups={groups:?} witnesses={witnesses:?}");
    for (label, dmb) in [("native", &native), ("translated", &actual)] {
        let mut followers = BTreeMap::new();
        for id in 0..dmb.procs.len() {
            let items: Vec<_> = bytecode::decode(dmb.proc_code_words(id).unwrap())
                .unwrap()
                .into_iter()
                .filter(|i| !matches!(i.opcode, 0x84 | 0x85))
                .collect();
            for (at, item) in items.iter().enumerate() {
                if item.opcode == 0x2a {
                    *followers
                        .entry(items.get(at + 1).map(|i| i.opcode))
                        .or_insert(0usize) += 1;
                }
            }
        }
        println!("{label} CallStatement followers={followers:?}");
    }
    Ok(())
}
