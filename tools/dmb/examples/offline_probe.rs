//! Temporary runtime diagnosis: change one verified sleep_offline assignment.
use byond_dmb::{bytecode, dmb::Dmb};
use std::{env, fs, path::PathBuf};
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let input = PathBuf::from(env::args_os().nth(1).ok_or("INPUT.dmb OUTPUT.dmb")?);
    let output = PathBuf::from(env::args_os().nth(2).ok_or("missing output")?);
    if input == output { return Err("diagnostic output must be separate".into()); }
    let mut dmb = Dmb::from_bytes(&fs::read(&input)?)?;
    let mut words = dmb.proc_code_words(2282).ok_or("missing Master.Initialize")?.to_vec();
    if words.get(0x5cf..0x5d5) != Some(&[0x50, 1, 0x34, 65500, 65509, 93][..]) {
        return Err(format!("unexpected instruction sequence: {:?}", words.get(0x5cf..0x5d5)).into());
    }
    words[0x5d0] = 0;
    dmb.replace_proc_code(2282, &bytecode::decode(&words).map_err(|error| format!("{error:?}"))?)?;
    dmb.validate_references()?;
    let bytes = dmb.to_bytes()?;
    let readback = Dmb::from_bytes(&bytes)?;
    readback.validate_references()?;
    assert_eq!(readback.proc_code_words(2282).unwrap()[0x5d0], 0);
    fs::create_dir_all(output.parent().ok_or("missing output directory")?)?;
    fs::write(&output, bytes)?;
    fs::copy(input.with_extension("rsc"), output.with_extension("rsc"))?;
    println!("Master.Initialize sleep_offline operand changed 1 to 0; validated readback");
    Ok(())
}
