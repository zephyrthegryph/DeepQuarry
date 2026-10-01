//! Offline output gate; never starts DreamDaemon or invokes either compiler.
use byond_dmb::{
    compare::{self, CompareOptions},
    dmb::Dmb,
};
use std::collections::BTreeSet;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1);
    let expected_path = args.next().ok_or("expected DMB path required")?;
    let actual_path = args.next().ok_or("actual DMB path required")?;
    let report_path = args.next().ok_or("report JSON path required")?;
    let mut prefixes = Vec::new();
    let mut canonical = false;
    let mut include_instructions = false;
    for argument in args {
        match argument.as_str() {
            "--canonical" => canonical = true,
            "--instructions" => include_instructions = true,
            _ if argument.starts_with("--") => {
                return Err(format!("unknown option: {argument}").into())
            }
            _ => prefixes.push(argument),
        }
    }
    let expected_bytes = std::fs::read(&expected_path)?;
    let actual_bytes = std::fs::read(&actual_path)?;
    let expected = Dmb::from_bytes(&expected_bytes)?;
    let actual = Dmb::from_bytes(&actual_bytes)?;
    expected.validate_references()?;
    actual.validate_references()?;
    let options = CompareOptions {
        authored_prefixes: prefixes,
        compare_bytecode: false,
        max_discrepancies: 256,
    };
    let metadata = compare::compare_dmbs(&expected, &actual, &options);
    let maps = if options.authored_prefixes.is_empty() {
        compare::compare_maps(&expected, &actual, 256)
    } else {
        Vec::new()
    };
    let left = compare::procedure_groups(&expected, &options);
    let right = compare::procedure_groups(&actual, &options);
    let mut differences = Vec::new();
    let mut compared = 0;
    let mut changed = 0;
    let mut missing = 0;
    let mut decode_errors = 0;
    for path in left.keys().chain(right.keys()).collect::<BTreeSet<_>>() {
        let a = left.get(path).map(Vec::as_slice).unwrap_or_default();
        let b = right.get(path).map(Vec::as_slice).unwrap_or_default();
        let identity = String::from_utf8_lossy(path);
        if a.len() != b.len() {
            missing += a.len().abs_diff(b.len());
            differences.push(serde_json::json!({"path":identity,"path_bytes":path,"kind":"presence","expected":a.len(),"actual":b.len()}));
        }
        for (occurrence, (&ai, &bi)) in a.iter().zip(b).enumerate() {
            compared += 1;
            match (
                compare::procedure_instructions(&expected, ai, true),
                compare::procedure_instructions(&actual, bi, true),
            ) {
                (Ok(a), Ok(b)) => {
                    let equal = a.len() == b.len()
                        && a.iter()
                            .zip(&b)
                            .all(|(a, b)| a.opcode == b.opcode && a.operands == b.operands);
                    if !equal {
                        changed += 1;
                        let alignment = compare::align_procedure_instructions(&a, &b, 256);
                        let mut item = serde_json::json!({"path":identity,"path_bytes":path,"occurrence":occurrence,"expected_id":ai,"actual_id":bi,
                            "kind":"normalized_code","expected_instructions":a.len(),"actual_instructions":b.len(),"alignment":alignment,
                            "changed_regions_are_independent_issues":false,
                            "same_opcode_sequence":a.iter().map(|item|item.opcode).eq(b.iter().map(|item|item.opcode))});
                        if include_instructions {
                            item["expected_code"] = serde_json::to_value(&a)?;
                            item["actual_code"] = serde_json::to_value(&b)?;
                        }
                        differences.push(item);
                    }
                }
                (a, b) => {
                    decode_errors += 1;
                    differences.push(
                        serde_json::json!({"path":identity,"path_bytes":path,"occurrence":occurrence,"kind":"decode",
                        "expected":a.err(),"actual":b.err()}),
                    );
                }
            }
        }
    }
    let bytes_equal = expected_bytes == actual_bytes;
    // An empty selection must never produce a successful gate.
    let passed = compared > 0
        && missing == 0
        && decode_errors == 0
        && changed == 0
        && metadata.is_empty()
        && maps.is_empty()
        && (!canonical || bytes_equal);
    let report = serde_json::json!({"schema":1,"mode":if canonical {"canonical_bytes"} else {"normalized_structure"},
        "scope":"named procedures, class/world initializers, argument-source helpers; selected metadata and map records",
        "execution_equivalence_verified":false,"expected":expected_path,"actual":actual_path,"passed":passed,"bytes_equal":bytes_equal,
        "paired_procedures":compared,"changed_procedures":changed,"missing_procedures":missing,"decode_errors":decode_errors,
        "metadata":metadata,"maps":maps,"procedures":differences});
    std::fs::write(report_path, serde_json::to_vec_pretty(&report)?)?;
    println!("paired={compared} changed={changed} missing={missing} decode_errors={decode_errors} canonical_bytes={bytes_equal} passed={passed}");
    if !passed {
        std::process::exit(1);
    }
    Ok(())
}
