//! Deterministic static debug-boundary inventory. Never launches DreamDaemon.
//! Usage: cargo run -p byond-dmb --example debug_coverage -- [--summary|--details] left.dmb [right.dmb]
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
    boundary_digest_md5: String,
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
    stats: Statistics,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    procedures: Vec<Procedure>,
}
#[derive(Default, Serialize)]
struct Statistics {
    procedures: usize,
    reserved_slots: usize,
    missing_code: usize,
    decode_errors: usize,
    ordinary_instructions: usize,
    sequentially_located_instructions: usize,
    branch_instructions: usize,
    debug_files: usize,
    debug_lines: usize,
    invalid_debug_file_refs: usize,
    zero_debug_lines: usize,
    procedures_with_no_debug_boundaries: usize,
    procedures_with_unlocated_instructions: usize,
}
impl Statistics {
    fn add(&mut self, procedure: &Procedure) {
        self.procedures += 1;
        self.reserved_slots += usize::from(procedure.reserved_slot);
        self.missing_code += usize::from(procedure.missing_code);
        self.decode_errors += usize::from(procedure.decode_error.is_some());
        self.ordinary_instructions += procedure.ordinary_instructions;
        self.sequentially_located_instructions += procedure.sequentially_located_instructions;
        self.branch_instructions += procedure.branch_instructions;
        self.debug_files += procedure.debug_files;
        self.debug_lines += procedure.debug_lines;
        self.invalid_debug_file_refs += procedure.invalid_debug_file_refs;
        self.zero_debug_lines += procedure.zero_debug_lines;
        self.procedures_with_no_debug_boundaries += usize::from(
            procedure.debug_files == 0 && procedure.debug_lines == 0 && !procedure.reserved_slot,
        );
        self.procedures_with_unlocated_instructions += usize::from(
            procedure.ordinary_instructions > procedure.sequentially_located_instructions,
        );
    }
}
#[derive(Default, Serialize)]
struct ComparisonStatistics {
    unique_exact_name_matches: usize,
    ambiguous_names: usize,
    left_only: usize,
    right_only: usize,
    boundary_digest_matches: usize,
    boundary_digest_differences: usize,
    located_instruction_count_differences: usize,
}
impl ComparisonStatistics {
    fn from_rows(rows: &[Difference]) -> Self {
        let mut stats = Self::default();
        for row in rows {
            match row.status {
                "unique-exact-name-match" => stats.unique_exact_name_matches += 1,
                "ambiguous-name-not-matched" => stats.ambiguous_names += 1,
                "left-only" => stats.left_only += 1,
                "right-only" => stats.right_only += 1,
                _ => unreachable!(),
            }
            if let Some(equal) = row.boundary_digest_matches {
                if equal {
                    stats.boundary_digest_matches += 1;
                } else {
                    stats.boundary_digest_differences += 1;
                }
                if row.left_located != row.right_located {
                    stats.located_instruction_count_differences += 1;
                }
            }
        }
        stats
    }
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
    boundary_digest_matches: Option<bool>,
    exact_boundaries_identical: Option<bool>,
}
#[derive(Serialize)]
struct Report {
    schema: &'static str,
    coverage_model: &'static str,
    runtime_ownership_certified: bool,
    branch_domination_certified: bool,
    limitations: [&'static str; 3],
    inputs: Vec<Inventory>,
    comparison_summary: Option<ComparisonStatistics>,
    #[serde(skip_serializing_if = "Option::is_none")]
    comparison_details: Option<Vec<Difference>>,
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
fn record_boundary(
    report: &mut Procedure,
    digest: &mut md5::Context,
    boundary: Boundary,
    details: bool,
) {
    digest.consume((boundary.word_offset as u64).to_le_bytes());
    digest.consume((boundary.kind.len() as u64).to_le_bytes());
    digest.consume(boundary.kind.as_bytes());
    match &boundary.file_bytes_hex {
        None => digest.consume([0]),
        Some(file) => {
            digest.consume([1]);
            digest.consume((file.len() as u64).to_le_bytes());
            digest.consume(file.as_bytes());
        }
    }
    match boundary.line {
        None => digest.consume([0]),
        Some(line) => {
            digest.consume([1]);
            digest.consume(line.to_le_bytes());
        }
    }
    if details {
        report.boundaries.push(boundary);
    }
}
fn inspect_words(
    report: &mut Procedure,
    words: &[u32],
    string: impl Fn(u32) -> Option<Vec<u8>>,
    details: bool,
) {
    report.code_words = words.len();
    let decoded = match bytecode::decode(words) {
        Ok(decoded) => decoded,
        Err(error) => {
            report.decode_error = Some(format!("{error:?}"));
            return;
        }
    };
    report.decoded_instructions = decoded.len();
    let mut digest = md5::Context::new();
    digest.consume(b"static-debug-boundary-digest-v1");
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
                record_boundary(
                    report,
                    &mut digest,
                    Boundary {
                        word_offset: instruction.offset,
                        file_bytes_hex: file.clone(),
                        line,
                        kind: "DbgFile",
                    },
                    details,
                );
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
                record_boundary(
                    report,
                    &mut digest,
                    Boundary {
                        word_offset: instruction.offset,
                        file_bytes_hex: file.clone(),
                        line,
                        kind: "DbgLine",
                    },
                    details,
                );
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
    report.boundary_digest_md5 = format!("{:x}", digest.compute());
}
fn inventory(path: String, details: bool) -> Result<Inventory, Box<dyn Error>> {
    let bytes = fs::read(&path)?;
    let input_md5 = format!("{:x}", md5::compute(&bytes));
    let input_bytes = bytes.len();
    let dmb = Dmb::from_bytes(&bytes)?;
    let mut procedures = Vec::with_capacity(dmb.procs.len());
    let mut stats = Statistics::default();
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
            boundary_digest_md5: String::new(),
            boundaries: Vec::new(),
            decode_error: None,
            missing_code: false,
            reserved_slot: dmb.is_reserved_proc_slot(index),
        };
        match dmb.proc_code_words(index) {
            Some(words) => inspect_words(
                &mut report,
                words,
                |id| dmb.string(id).map(Vec::from),
                details,
            ),
            None => report.missing_code = !report.reserved_slot,
        }
        stats.add(&report);
        procedures.push(report);
    }
    Ok(Inventory {
        path,
        input_md5,
        input_bytes,
        stats,
        procedures,
    })
}
fn compare(left: &Inventory, right: &Inventory, details: bool) -> Vec<Difference> {
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
            let decoded = unique
                && left[0].decode_error.is_none()
                && right[0].decode_error.is_none()
                && !left[0].missing_code
                && !right[0].missing_code
                && !left[0].reserved_slot
                && !right[0].reserved_slot;
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
                boundary_digest_matches: decoded
                    .then(|| left[0].boundary_digest_md5 == right[0].boundary_digest_md5),
                exact_boundaries_identical: (decoded && details)
                    .then(|| left[0].boundaries == right[0].boundaries),
            }
        })
        .collect()
}
fn main() -> Result<(), Box<dyn Error>> {
    let mut details = false;
    let mut paths = Vec::new();
    for argument in std::env::args().skip(1) {
        match argument.as_str() {
            "--details" => details = true,
            "--summary" => details = false,
            flag if flag.starts_with("--") => return Err(format!("unknown option {flag}").into()),
            _ => paths.push(argument),
        }
    }
    if paths.is_empty() || paths.len() > 2 {
        return Err("expected one or two compiled DMB paths".into());
    }
    // Decode inputs sequentially; summary retains no per-boundary arrays.
    let mut inputs = paths
        .into_iter()
        .map(|path| inventory(path, details))
        .collect::<Result<Vec<_>, _>>()?;
    let comparison = (inputs.len() == 2).then(|| compare(&inputs[0], &inputs[1], details));
    let comparison_summary = comparison
        .as_ref()
        .map(|rows| ComparisonStatistics::from_rows(rows));
    let comparison_details = if details { comparison } else { None };
    if !details {
        for input in &mut inputs {
            input.procedures.clear();
        }
    }
    let report=Report {
        schema:"dmb-static-debug-boundaries-v2",
        coverage_model:"linear-instruction-state-with-explicit-file-line-boundaries",
        runtime_ownership_certified:false,branch_domination_certified:false,
        limitations:["DBG boundaries do not establish runtime error routing or per-test ownership","Sequentially located instructions may have incoming branches that bypass DBG setup","Duplicate/anonymous proc identities remain unmatched; digest equality is not a byte-equality proof"],
        inputs,comparison_summary,comparison_details,
    };
    // Even opt-in details stream directly instead of allocating a giant JSON string.
    let stdout = std::io::stdout();
    let mut output = stdout.lock();
    serde_json::to_writer_pretty(&mut output, &report)?;
    std::io::Write::write_all(&mut output, b"\n")?;
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
            boundary_digest_md5: String::new(),
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
            true,
        );
        assert_eq!(report.ordinary_instructions, 3);
        assert_eq!(report.sequentially_located_instructions, 1);
        assert_eq!(report.boundaries[1].line, Some(12));
        assert_eq!(report.boundaries[2].file_bytes_hex.as_deref(), Some("ff"));
        assert_eq!(report.boundaries[2].line, None);
    }
    #[test]
    fn summary_has_same_counters_and_digest_without_boundary_allocation() {
        let mut detailed = empty();
        let mut summary = empty();
        let words = [0x84, 7, 0x85, 12, 0];
        inspect_words(&mut detailed, &words, |_| Some(b"a.dm".to_vec()), true);
        inspect_words(&mut summary, &words, |_| Some(b"a.dm".to_vec()), false);
        assert_eq!(summary.boundary_digest_md5, detailed.boundary_digest_md5);
        assert_eq!(
            summary.sequentially_located_instructions,
            detailed.sequentially_located_instructions
        );
        assert_eq!(summary.debug_files, detailed.debug_files);
        assert_eq!(summary.debug_lines, detailed.debug_lines);
        assert!(summary.boundaries.is_empty());
        let mut stats = Statistics::default();
        stats.add(&summary);
        let inventory = Inventory {
            path: "source.dmb".into(),
            input_md5: "captured".into(),
            input_bytes: 1,
            stats,
            procedures: Vec::new(),
        };
        let json = serde_json::to_value(inventory).unwrap();
        assert!(json.get("procedures").is_none());
        assert_eq!(json["stats"]["sequentially_located_instructions"], 1);
    }
    #[test]
    fn missing_file_and_zero_line_remain_unlocated() {
        let mut report = empty();
        inspect_words(&mut report, &[0x84, 77, 0x85, 0, 0], |_| None, true);
        assert_eq!(report.invalid_debug_file_refs, 1);
        assert_eq!(report.zero_debug_lines, 1);
        assert_eq!(report.sequentially_located_instructions, 0);
    }
}
