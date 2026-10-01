//! Read-only procedure lookup for diagnostic artifacts.
use byond_dmb::dmb::Dmb;
use std::{env,fs};
fn main()->Result<(),Box<dyn std::error::Error>>{
    let mut args=env::args().skip(1);
    let input=args.next().ok_or("INPUT.dmb PATH_SUBSTRING...")?;
    let patterns=args.collect::<Vec<_>>();
    let dmb=Dmb::from_bytes(&fs::read(input)?)?;
    for(id,proc)in dmb.procs.iter().enumerate(){
        let path=String::from_utf8_lossy(dmb.string(proc.strings[0]).unwrap_or_default());
        if patterns.iter().any(|pattern|path.contains(pattern)){
            println!("{id} {path} flags={} lists={:?}",proc.effective_flags(),proc.code_locals_args);
        }
    }
    Ok(())
}
