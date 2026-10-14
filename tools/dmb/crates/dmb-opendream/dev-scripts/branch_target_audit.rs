use byond_dmb::{bytecode, dmb::Dmb};
use std::{collections::BTreeSet, io::Write};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = std::env::args().collect();
    let dmb = Dmb::from_bytes(&std::fs::read(
        args.get(1)
            .ok_or("usage: branch_target_audit FILE.dmb [REPORT.ndjson]")?,
    )?)?;
    let mut report: Box<dyn Write> = if let Some(path) = args.get(2) {
        Box::new(std::fs::File::create(path)?)
    } else {
        Box::new(std::io::sink())
    };
    let mut reserved = 0usize;
    let mut branches = 0usize;
    let mut invalid = 0usize;
    for (id, proc) in dmb.procs.iter().enumerate() {
        if dmb.is_reserved_proc_slot(id) {
            reserved += 1;
            continue;
        }
        let words = dmb.proc_code_words(id).ok_or("missing procedure code")?;
        let instructions = bytecode::decode(words).map_err(|error| error.reason)?;
        let boundaries: BTreeSet<_> = instructions.iter().map(|item| item.offset).collect();
        for instruction in instructions {
            for target in instruction.branch_targets().map_err(|error| error.reason)? {
                branches += 1;
                if !boundaries.contains(&(target as usize)) {
                    invalid += 1;
                    let row = serde_json::json!({
                        "proc": id,
                        "path": String::from_utf8_lossy(dmb.string(proc.strings[0]).unwrap_or_default()),
                        "instruction": instruction.offset,
                        "opcode": instruction.opcode,
                        "target": target,
                        "code_words": words.len()
                    });
                    writeln!(report, "{row}")?;
                }
            }
        }
    }
    println!(
        "procedures={} reserved={reserved} branch_targets={branches} invalid_targets={invalid}",
        dmb.procs.len()
    );
    if invalid != 0 {
        return Err("branch destinations must be instruction boundaries".into());
    }
    Ok(())
}
