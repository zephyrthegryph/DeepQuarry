//! Deterministic static debug-boundary inventory. Never launches DreamDaemon.
//! Usage: cargo run -p byond-dmb --example debug_coverage -- left.dmb [right.dmb]
//! This reports sequential instruction metadata, not runtime error ownership or
//! CFG domination. Branches and duplicate procedure names remain explicit gaps.
use byond_dmb::{bytecode, dmb::Dmb};
use serde::Serialize;
use std::{collections::BTreeMap, error::Error, fs};

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
struct Boundary {
    word_offset: usize,
    file_bytes_hex: Option<String>,
    line: Option<u32>,
    kind: &'static str,
}
#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
struct Procedure {
    physical_proc_index: usize,
    path_bytes_hex: Option<String>,
    display_bytes_hex: Option<String>,
    code_words: usize,
    decoded_instructions: usize,
    ordinary_instructions: usize,
    sequentially_located_instructions: usize,
    branch_instructions: usize,
    debug_files: usize,
    debug_lines: usize,
    invalid_debug_file_refs: usize,
    zero_debug_lines: usize,
    boundaries: Vec<Boundary>,
    decode_error: Option<String>,
    missing_code: bool,
    reserved_slot: bool,
}
#[derive(Serialize)]
struct Inventory {
    path: String,
    input_md5: String,
    input_bytes: usize,
    procedures: Vec<Procedure>,
}
#[derive(Serialize)]
struct Difference {
    path_bytes_hex: Option<String>,
    display_bytes_hex: Option<String>,
    left_indexes: Vec<usize>,
    right_indexes: Vec<usize>,
    status: &'static str,
    left_located: Option<usize>,
    right_located: Option<usize>,
    boundaries_identical: Option<bool>,
}
#[derive(Serialize)]
struct Report {
    schema: &'static str,
    coverage_model: &'static str,
    runtime_ownership_certified: bool,
    branch_domination_certified: bool,
    limitations: [&'static str; 3],
    inputs: Vec<Inventory>,
    comparison: Option<Vec<Difference>>,
}
fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8] = b"0123456789abcdef";
    let mut text = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        text.push(DIGITS[(byte >> 4) as usize] as char);
        text.push(DIGITS[(byte & 15) as usize] as char);
    }
    text
}
fn inspect_words(report: &mut Procedure, words: &[u32], string: impl Fn(u32) -> Option<Vec<u8>>) {
    report.code_words = words.len();
    let decoded = match bytecode::decode(words) {
        Ok(decoded) => decoded,
        Err(error) => {
            report.decode_error = Some(format!("{error:?}"));
            return;
        }
    };
    report.decoded_instructions = decoded.len();
    let mut file = None;
    let mut line = None;
    for instruction in decoded {
        match instruction.opcode {
            0x84 => {
                report.debug_files += 1;
                file = instruction
                    .operands
                    .first()
                    .and_then(|id| string(*id))
                    .filter(|bytes| !bytes.is_empty())
                    .map(|bytes| hex(&bytes));
                // A file switch never borrows a previous file's line evidence.
                line = None;
                if file.is_none() {
                    report.invalid_debug_file_refs += 1;
                }
                report.boundaries.push(Boundary {
                    word_offset: instruction.offset,
                    file_bytes_hex: file.clone(),
                    line,
                    kind: "DbgFile",
                });
            }
            0x85 => {
                report.debug_lines += 1;
                line = instruction
                    .operands
                    .first()
                    .copied()
                    .filter(|line| *line != 0);
                if line.is_none() {
                    report.zero_debug_lines += 1;
                }
                report.boundaries.push(Boundary {
                    word_offset: instruction.offset,
                    file_bytes_hex: file.clone(),
                    line,
                    kind: "DbgLine",
                });
            }
            _ => {
                report.ordinary_instructions += 1;
                if file.is_some() && line.is_some() {
                    report.sequentially_located_instructions += 1;
                }
                match instruction.branch_targets() {
                    Ok(targets) if !targets.is_empty() => report.branch_instructions += 1,
                    Ok(_) => (),
                    Err(error) => report.decode_error = Some(format!("branch operands: {error:?}")),
                }
            }
        }
    }
}
fn inventory(path: String) -> Result<Inventory, Box<dyn Error>> {
    let bytes = fs::read(&path)?;
    let input_md5 = format!("{:x}", md5::compute(&bytes));
    let input_bytes = bytes.len();
    let dmb = Dmb::from_bytes(&bytes)?;
    let mut procedures = Vec::with_capacity(dmb.procs.len());
    for (index, record) in dmb.procs.iter().enumerate() {
        let mut report = Procedure {
            physical_proc_index: index,
            path_bytes_hex: dmb.string(record.strings[0]).map(hex),
            display_bytes_hex: dmb.string(record.strings[1]).map(hex),
            code_words: 0,
            decoded_instructions: 0,
            ordinary_instructions: 0,
            sequentially_located_instructions: 0,
            branch_instructions: 0,
            debug_files: 0,
            debug_lines: 0,
            invalid_debug_file_refs: 0,
            zero_debug_lines: 0,
            boundaries: Vec::new(),
            decode_error: None,
            missing_code: false,
            reserved_slot: dmb.is_reserved_proc_slot(index),
        };
        match dmb.proc_code_words(index) {
            Some(words) => inspect_words(&mut report, words, |id| dmb.string(id).map(Vec::from)),
            None => report.missing_code = !report.reserved_slot,
        }
        procedures.push(report);
    }
    Ok(Inventory {
        path,
        input_md5,
        input_bytes,
        procedures,
    })
}
fn compare(left: &Inventory, right: &Inventory) -> Vec<Difference> {
    type Identity = (Option<String>, Option<String>);
    let mut grouped: BTreeMap<Identity, (Vec<&Procedure>, Vec<&Procedure>)> = BTreeMap::new();
    for procedure in &left.procedures {
        grouped
            .entry((
                procedure.path_bytes_hex.clone(),
                procedure.display_bytes_hex.clone(),
            ))
            .or_default()
            .0
            .push(procedure);
    }
    for procedure in &right.procedures {
        grouped
            .entry((
                procedure.path_bytes_hex.clone(),
                procedure.display_bytes_hex.clone(),
            ))
            .or_default()
            .1
            .push(procedure);
    }
    grouped
        .into_iter()
        .map(|((path, display), (left, right))| {
            let unique = !path.as_ref().is_none_or(|path| path.is_empty())
                && left.len() == 1
                && right.len() == 1;
            Difference {
                path_bytes_hex: path,
                display_bytes_hex: display,
                left_indexes: left.iter().map(|proc| proc.physical_proc_index).collect(),
                right_indexes: right.iter().map(|proc| proc.physical_proc_index).collect(),
                status: if unique {
                    "unique-exact-name-match"
                } else if left.is_empty() {
                    "right-only"
                } else if right.is_empty() {
                    "left-only"
                } else {
                    "ambiguous-name-not-matched"
                },
                left_located: unique.then(|| left[0].sequentially_located_instructions),
                right_located: unique.then(|| right[0].sequentially_located_instructions),
                boundaries_identical: unique.then(|| left[0].boundaries == right[0].boundaries),
            }
        })
        .collect()
}
fn main() -> Result<(), Box<dyn Error>> {
    let paths: Vec<_> = std::env::args().skip(1).collect();
    if paths.is_empty() || paths.len() > 2 {
        return Err("expected one or two compiled DMB paths".into());
    }
    // Decode inputs sequentially; never hold two decoded worlds simultaneously.
    let inputs = paths
        .into_iter()
        .map(inventory)
        .collect::<Result<Vec<_>, _>>()?;
    let comparison = (inputs.len() == 2).then(|| compare(&inputs[0], &inputs[1]));
    let report = Report {
        schema:"dmb-static-debug-boundaries-v1",
        coverage_model:"linear-instruction-state-with-explicit-file-line-boundaries",
        runtime_ownership_certified:false,branch_domination_certified:false,
        limitations:["DBG boundaries do not establish runtime error routing or per-test ownership","Sequentially located instructions may have incoming branches that bypass DBG setup","Duplicate/anonymous proc identities remain unmatched; source bytes use exact hexadecimal encoding"],
        inputs,comparison,
    };
    println!("{}", serde_json::to_string_pretty(&report)?);
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    fn empty() -> Procedure {
        Procedure {
            physical_proc_index: 0,
            path_bytes_hex: None,
            display_bytes_hex: None,
            code_words: 0,
            decoded_instructions: 0,
            ordinary_instructions: 0,
            sequentially_located_instructions: 0,
            branch_instructions: 0,
            debug_files: 0,
            debug_lines: 0,
            invalid_debug_file_refs: 0,
            zero_debug_lines: 0,
            boundaries: Vec::new(),
            decode_error: None,
            missing_code: false,
            reserved_slot: false,
        }
    }
    #[test]
    fn exact_debug_operands_preserve_unlocated_prefix_and_file_change() {
        let mut report = empty();
        inspect_words(
            &mut report,
            &[0, 0x84, 7, 0x85, 12, 0, 0x84, 8, 0],
            |id| match id {
                7 => Some(b"a.dm".to_vec()),
                8 => Some(vec![255]),
                _ => None,
            },
        );
        assert_eq!(report.ordinary_instructions, 3);
        assert_eq!(report.sequentially_located_instructions, 1);
        assert_eq!(report.boundaries[1].line, Some(12));
        assert_eq!(report.boundaries[2].file_bytes_hex.as_deref(), Some("ff"));
        assert_eq!(report.boundaries[2].line, None);
    }
    #[test]
    fn missing_file_and_zero_line_remain_unlocated() {
        let mut report = empty();
        inspect_words(&mut report, &[0x84, 77, 0x85, 0, 0], |_| None);
        assert_eq!(report.invalid_debug_file_refs, 1);
        assert_eq!(report.zero_debug_lines, 1);
        assert_eq!(report.sequentially_located_instructions, 0);
    }
}
