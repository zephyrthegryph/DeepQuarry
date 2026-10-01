//! Artifact-only diagnostic harness. Does not replace normal startup validation.
use byond_dmb::{bytecode, dmb::Dmb};
use std::{env, fs, path::PathBuf};
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let input = PathBuf::from(env::args_os().nth(1).ok_or("INPUT.dmb OUTPUT.dmb")?);
    let output = PathBuf::from(env::args_os().nth(2).ok_or("missing output")?);
    if input == output {
        return Err("diagnostic output must be separate".into());
    }
    let mut dmb = Dmb::from_bytes(&fs::read(&input)?)?;
    let test_id = dmb
        .procs
        .iter()
        .enumerate()
        .find(|(_, proc)| matches!(dmb.string(proc.strings[0]), Some(b"/proc/RunUnitTests")))
        .ok_or("RunUnitTests missing")?
        .0 as u32;
    let world_procs = dmb
        .lists
        .get(dmb.world.ids[3] as usize)
        .ok_or("world proc list missing")?;
    let proc_id = *world_procs
        .iter()
        .find(|id| {
            dmb.procs.get(**id as usize).is_some_and(|proc| {
                matches!(
                    dmb.string(proc.strings[0]),
                    Some(b"/world/New") | Some(b"/world/proc/New")
                )
            })
        })
        .ok_or("world/New missing")? as usize;
    let old = dmb
        .proc_code_words(proc_id)
        .ok_or("world/New code missing")?;
    let decoded = bytecode::decode(old).map_err(|error| format!("{error:?}"))?;
    let last = decoded.last().ok_or("empty code")?;
    if last.opcode != 0 || !last.operands.is_empty() {
        return Err("world/New must end in END".into());
    }
    // The compiler may append redundant ENDs after the parent continuation of
    // the final spawn. Instrument that reachable parent END, not the dead tail.
    let tail = decoded
        .iter()
        .filter(|instruction| instruction.opcode == 0x25)
        .map(|instruction| instruction.operands[0] as usize)
        .filter(|target| {
            old.get(*target..)
                .is_some_and(|tail| tail.iter().all(|word| *word == 0))
        })
        .max()
        .unwrap_or(last.offset);
    let old_end = old.len();
    let offline_id = dmb
        .strings
        .iter()
        .position(|string| string.data == b"sleep_offline")
        .ok_or("sleep_offline field missing")? as u32;
    let prefix = [
        0x50,
        0,
        0x34,
        65500,
        65509,
        offline_id,
        0x50,
        300,
        0x25,
        (tail + 15) as u32,
        0x30,
        0,
        test_id,
        0x51,
        0,
    ];
    let mut words = old.to_vec();
    words.splice(tail..tail, prefix);
    for instruction in &decoded {
        for at in instruction
            .branch_target_word_offsets()
            .map_err(|error| format!("{error:?}"))?
        {
            let target = old[at] as usize;
            let new_at = if at >= tail { at + prefix.len() } else { at };
            if target == old_end {
                words[new_at] = words.len() as u32;
            } else if target > tail {
                words[new_at] = (target + prefix.len()) as u32;
            }
        }
    }
    dmb.replace_proc_code(
        proc_id,
        &bytecode::decode(&words).map_err(|error| format!("{error:?}"))?,
    )?;
    // Prevent the later conditional Master.Initialize assignment from undoing
    // the diagnostic's unconditional world/New setting.
    let master_id = dmb
        .procs
        .iter()
        .enumerate()
        .find(|(_, proc)| {
            matches!(
                dmb.string(proc.strings[0]),
                Some(b"/datum/controller/master/Initialize")
                    | Some(b"/datum/controller/master/proc/Initialize")
            )
        })
        .ok_or("Master.Initialize missing")?
        .0;
    let mut master = dmb
        .proc_code_words(master_id)
        .ok_or("Master.Initialize code missing")?
        .to_vec();
    let master_instructions = bytecode::decode(&master).map_err(|error| format!("{error:?}"))?;
    let setters = master_instructions
        .windows(2)
        .filter_map(|pair| {
            (pair[0].opcode == 0x50
                && pair[0].operands == [1]
                && pair[1].opcode == 0x34
                && pair[1].operands == [65500, 65509, offline_id])
            .then_some(pair[0].offset + 1)
        })
        .collect::<Vec<_>>();
    if setters.is_empty() {
        return Err("Master.Initialize true sleep_offline setter missing".into());
    }
    for at in &setters {
        master[*at] = 0;
    }
    dmb.replace_proc_code(
        master_id,
        &bytecode::decode(&master).map_err(|error| format!("{error:?}"))?,
    )?;
    dmb.validate_references()?;
    let bytes = dmb.to_bytes()?;
    let check = Dmb::from_bytes(&bytes)?;
    check.validate_references()?;
    assert_eq!(
        &check.proc_code_words(proc_id).unwrap()[tail..tail + 15],
        &prefix
    );
    for at in setters {
        assert_eq!(check.proc_code_words(master_id).unwrap()[at], 0);
    }
    fs::create_dir_all(output.parent().ok_or("missing output directory")?)?;
    fs::write(&output, bytes)?;
    fs::copy(input.with_extension("rsc"), output.with_extension("rsc"))?;
    println!("diagnostic harness: world/New {proc_id} spawn(300) RunUnitTests {test_id}; offline sleeping disabled; validated readback");
    Ok(())
}
