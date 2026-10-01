//! Artifact-only diagnostic: disable offline sleeping at the world/New tail.
use byond_dmb::{bytecode, dmb::Dmb};
use std::{env, fs, path::PathBuf};
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let input = PathBuf::from(env::args_os().nth(1).ok_or("INPUT.dmb OUTPUT.dmb")?);
    let output = PathBuf::from(env::args_os().nth(2).ok_or("missing output")?);
    if input == output { return Err("diagnostic output must be separate".into()); }
    let mut dmb = Dmb::from_bytes(&fs::read(&input)?)?;
    let world_procs = dmb.lists.get(dmb.world.ids[3] as usize).ok_or("world proc list missing")?;
    let proc_id = *world_procs.iter().find(|id| dmb.procs.get(**id as usize).is_some_and(|proc| matches!(dmb.string(proc.strings[0]), Some(b"/world/New") | Some(b"/world/proc/New")))).ok_or("world/New missing")? as usize;
    let old = dmb.proc_code_words(proc_id).ok_or("world/New code missing")?;
    let decoded = bytecode::decode(old).map_err(|error| format!("{error:?}"))?;
    let last = decoded.last().ok_or("empty code")?;
    if last.opcode != 0 || !last.operands.is_empty() { return Err("world/New must end in END".into()); }
    let tail = last.offset;
    let old_end = old.len();
    let mut words = old.to_vec();
    words.splice(tail..tail, [0x50, 0, 0x34, 65500, 65509, 93]);
    for instruction in &decoded {
        for at in instruction.branch_target_word_offsets().map_err(|error| format!("{error:?}"))? {
            let target = old[at] as usize;
            if target == old_end { words[at] = words.len() as u32; }
            else if target > tail { return Err(format!("unexpected target {target} beyond final END").into()); }
            // A jump to the old END now reaches the setter at that same offset.
        }
    }
    dmb.replace_proc_code(proc_id, &bytecode::decode(&words).map_err(|error| format!("{error:?}"))?)?;
    dmb.validate_references()?;
    let bytes = dmb.to_bytes()?;
    let check = Dmb::from_bytes(&bytes)?;
    check.validate_references()?;
    assert_eq!(&check.proc_code_words(proc_id).unwrap()[tail..], &[0x50, 0, 0x34, 65500, 65509, 93, 0]);
    fs::create_dir_all(output.parent().ok_or("missing output directory")?)?;
    fs::write(&output, bytes)?;
    fs::copy(input.with_extension("rsc"), output.with_extension("rsc"))?;
    println!("world/New {proc_id} tail {tail}: unconditional sleep_offline=0 installed; validated readback");
    Ok(())
}
