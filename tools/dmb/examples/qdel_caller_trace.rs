//! Temporary artifact-only caller instrumentation. Does not change compiler code.
use byond_dmb::{bytecode::{self, opcode}, dmb::Dmb};
use std::{collections::{BTreeMap, BTreeSet}, env, fs, io, path::PathBuf};

fn rewrite(words: &[u32], caller: u32, targets: &BTreeSet<u32>) -> Result<Option<(Vec<u32>, usize)>, String> {
    let instructions = bytecode::decode(words).map_err(|error| format!("decode: {error:?}"))?;
    let mut rewritten = Vec::with_capacity(words.len());
    let mut starts = BTreeMap::new();
    let mut branches = Vec::new();
    let mut changed = 0;
    for instruction in instructions {
        starts.insert(instruction.offset, rewritten.len());
        let trace = instruction.opcode == opcode::CALL_GLOB
            && targets.contains(&instruction.operands[1])
            && matches!(instruction.operands[0], 1 | 2);
        if trace {
            if instruction.operands[0] == 1 {
                rewritten.extend([opcode::PUSH_VAL, 0, 0]);
            }
            rewritten.extend([opcode::PUSH_VAL, 38 | ((caller >> 16) << 8), caller & 0xffff]);
            changed += 1;
        }
        let opcode_at = rewritten.len();
        for at in instruction.branch_target_word_offsets().map_err(|error| format!("branch: {error:?}"))? {
            let relative = at - instruction.offset;
            branches.push((opcode_at + relative, words[at] as usize));
        }
        rewritten.push(instruction.opcode);
        rewritten.extend_from_slice(&instruction.operands);
        if trace { rewritten[opcode_at + 1] = 3; }
    }
    if changed == 0 { return Ok(None); }
    starts.insert(words.len(), rewritten.len());
    for (at, old_target) in branches {
        rewritten[at] = u32::try_from(*starts.get(&old_target).ok_or_else(|| format!("branch target {old_target} is not an instruction boundary"))?).map_err(|error| error.to_string())?;
    }
    bytecode::decode(&rewritten).map_err(|error| format!("rewritten decode: {error:?}"))?;
    Ok(Some((rewritten, changed)))
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = env::args_os().skip(1);
    let input = PathBuf::from(args.next().ok_or("usage: qdel_caller_trace INPUT.dmb OUTPUT.dmb")?);
    let output = PathBuf::from(args.next().ok_or("missing output")?);
    if args.next().is_some() || input == output { return Err("input and output must be distinct; exactly two paths required".into()); }
    let mut dmb = Dmb::from_bytes(&fs::read(&input)?)?;
    let targets = dmb.procs.iter().enumerate().filter_map(|(id, proc)| {
        matches!(dmb.string(proc.strings[0]), Some(b"/proc/qdel") | Some(b"/qdel")).then_some(id as u32)
    }).collect::<BTreeSet<_>>();
    if targets.is_empty() { return Err("qdel procedure not found".into()); }
    let mut proc_count = 0;
    let mut call_count = 0;
    for caller in 0..dmb.procs.len() {
        let Some(words) = dmb.proc_code_words(caller) else { continue; };
        if let Some((words, calls)) = rewrite(words, caller as u32, &targets).map_err(io::Error::other)? {
            let decoded = bytecode::decode(&words).map_err(|error| io::Error::other(format!("{error:?}")))?;
            dmb.replace_proc_code(caller, &decoded)?;
            proc_count += 1;
            call_count += calls;
        }
    }
    dmb.validate_references()?;
    let bytes = dmb.to_bytes()?;
    Dmb::from_bytes(&bytes)?.validate_references()?;
    fs::write(&output, bytes)?;
    fs::copy(input.with_extension("rsc"), output.with_extension("rsc"))?;
    println!("instrumented {call_count} qdel calls in {proc_count} procedures; targets {targets:?}");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn forwards_branches_to_prefix_and_relocates_end() {
        let words = [0x0f, 5, 0x30, 1, 9, 0x0f, 9, 0x00, 0x00];
        let (result, count) = rewrite(&words, 0x12345, &[9].into()).unwrap().unwrap();
        assert_eq!(count, 1);
        assert_eq!(result, [0x0f, 11, 0x60, 0, 0, 0x60, 38 | (1 << 8), 0x2345, 0x30, 3, 9, 0x0f, 15, 0, 0]);
        let target_call = [0x0f, 2, 0x30, 2, 9, 0x00];
        assert_eq!(rewrite(&target_call, 7, &[9].into()).unwrap().unwrap().0, [0x0f, 2, 0x60, 38, 7, 0x30, 3, 9, 0]);
    }
}
