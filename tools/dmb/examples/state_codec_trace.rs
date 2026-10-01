//! Artifact-only dynamic startup state. No game source/compiler changes.
use byond_dmb::{bytecode,dmb::{Dmb,DmString},operands::Variable as V};
use std::{env,fs,path::PathBuf};
fn field(dmb:&Dmb,name:&str)->Result<u32,Box<dyn std::error::Error>>{
    Ok(dmb.strings.iter().position(|string|string.data==name.as_bytes()).ok_or_else(||format!("missing field {name}"))? as u32)
}
fn select(receiver:V,field:u32)->V{V::SetCache(Box::new(receiver),Box::new(V::Field(field)))}
fn main()->Result<(),Box<dyn std::error::Error>>{
    let input=PathBuf::from(env::args_os().nth(1).ok_or("INPUT.dmb OUTPUT.dmb")?);
    let output=PathBuf::from(env::args_os().nth(2).ok_or("missing output")?);
    if input==output{return Err("separate output required".into());}
    let mut dmb=Dmb::from_bytes(&fs::read(&input)?)?;
    let log=field(&dmb,"log")?;
    if let Some(id)=dmb.procs.iter().position(|proc|dmb.string(proc.strings[0])==Some(b"/proc/dq_lifecycle_time")) { dmb.replace_proc_code(id,&bytecode::decode(&[0x60,0,0,0x12,0]).map_err(|e|format!("{e:?}"))?)?; }
    for path in ["/datum/state_codec/proc/decode", "/datum/state_codec/child/encode", "/datum/state_context/proc/create_tree", "/datum/state_context/proc/apply_vars", "/datum/state_context/proc/refuse", "/world/Error"] {
        let id=dmb.procs.iter().position(|proc|dmb.string(proc.strings[0])==Some(path.as_bytes())).ok_or("missing proc")?;
        let old=dmb.proc_code_words(id).ok_or("code missing")?.to_vec();
        let decoded=bytecode::decode(&old).map_err(|error|format!("{error:?}"))?;
        let mut values=vec![("src_type",select(V::Src,field(&dmb,"type")?),false)];
        let mut prefix=Vec::new();
        let guard:Option<usize>=None;
        if path == "/world/Error" { values.clear(); for name in ["desc","file","line","name"] { values.push((name,select(V::Arg(0),field(&dmb,name)?),false)); } } else if path.ends_with("refuse") { values.push(("reason",V::Arg(0),false)); } else if path.ends_with("create_tree") {
            values.push(("blob",V::Arg(0),true));
            values.push(("loc",V::Arg(1),false));
            values.push(("id",V::Arg(2),false));
        } else if path.ends_with("apply_vars") {
            values.push(("owner_type",select(V::Arg(0),field(&dmb,"type")?),false));
            values.push(("blob",V::Arg(1),true));
        } else {
            values.push(("owner_type",select(V::Arg(0),field(&dmb,"type")?),false));
            values.push(("var_name",V::Arg(1),false));
            values.push(("value",V::Arg(2),path.ends_with("decode")));
            values.push(("ctx",V::Arg(3),false));
        }
        prefix.push(0x33);
        prefix.extend(select(V::World,log).encode());
        let mut template=format!("STATE_CODEC_VALUES {id} {path}").into_bytes();
        for(name,value,json)in &values{
            template.extend(format!(" {name}=").as_bytes());
            template.extend([0xff,1]);
            prefix.push(0x33);
            prefix.extend(value.encode());
            if *json {prefix.push(0x138);}
        }
        if dmb.strings.len()==65535{dmb.strings.push(DmString{data:vec![],long_chunks:0});}
        let marker=dmb.strings.len() as u32;
        dmb.strings.push(DmString{data:template,long_chunks:0});
        prefix.extend([0x04,marker,values.len() as u32]);
        if let Some(at)=guard{prefix[at]=prefix.len() as u32;}
        let added=prefix.len();
        let mut words=prefix;
        words.extend_from_slice(&old);
        for instruction in &decoded{
            for at in instruction.branch_target_word_offsets().map_err(|error|format!("{error:?}"))?{
                if old[at] as usize>old.len(){return Err("branch beyond code".into());}
                words[at+added]=old[at]+added as u32;
            }
        }
        dmb.replace_proc_code(id,&bytecode::decode(&words).map_err(|error|format!("{error:?}"))?)?;
        println!("state marker {id} {path}: {} values",values.len());
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


