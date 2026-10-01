//! Artifact-only fixed startup markers. No original instruction is removed.
use byond_dmb::{bytecode, dmb::{Dmb,DmString}};
use std::{env,fs,path::PathBuf};
fn main()->Result<(),Box<dyn std::error::Error>>{
    let input=PathBuf::from(env::args_os().nth(1).ok_or("INPUT.dmb OUTPUT.dmb")?);
    let output=PathBuf::from(env::args_os().nth(2).ok_or("missing output")?);
    if input==output{return Err("separate output required".into());}
    let mut dmb=Dmb::from_bytes(&fs::read(&input)?)?;
    let log_id=dmb.strings.iter().position(|string|string.data==b"log").ok_or("world.log field missing")? as u32;
    let paths=["/world/proc/HandleTestRun","/world/proc/RunUnattendedFunctions","/datum/controller/subsystem/ticker/proc/OnRoundstart","/datum/callback/proc/InvokeAsync","/proc/_addtimer","/datum/controller/subsystem/timer/fire"];
    for path in paths{
        let id=dmb.procs.iter().position(|proc|dmb.string(proc.strings[0])==Some(path.as_bytes())).ok_or_else(||format!("missing {path}"))?;
        let old=dmb.proc_code_words(id).ok_or("code missing")?.to_vec();
        let decoded=bytecode::decode(&old).map_err(|error|format!("{error:?}"))?;
        if dmb.strings.len()==65535{dmb.strings.push(DmString{data:vec![],long_chunks:0});}
        let marker_id=dmb.strings.len() as u32;
        dmb.strings.push(DmString{data:format!("STARTUP_TRACE {id} {path}").into_bytes(),long_chunks:0});
        let prefix=[0x33,65500,65509,log_id,0x60,6|((marker_id>>16)<<8),marker_id&65535,0x03];
        let mut words=prefix.to_vec();
        words.extend_from_slice(&old);
        for instruction in &decoded{
            for at in instruction.branch_target_word_offsets().map_err(|error|format!("{error:?}"))?{
                if old[at] as usize>old.len(){return Err("branch beyond code".into());}
                words[at+prefix.len()]=old[at]+prefix.len() as u32;
            }
        }
        dmb.replace_proc_code(id,&bytecode::decode(&words).map_err(|error|format!("{error:?}"))?)?;
        println!("entry marker {id} {path}");
    }
    if dmb.strings.len()>65535{dmb.header.flags|=0x40000000;}
    dmb.validate_references()?;
    let bytes=dmb.to_bytes()?;
    Dmb::from_bytes(&bytes)?.validate_references()?;
    fs::create_dir_all(output.parent().ok_or("missing directory")?)?;
    fs::write(&output,bytes)?;
    fs::copy(input.with_extension("rsc"),output.with_extension("rsc"))?;
    Ok(())
}
