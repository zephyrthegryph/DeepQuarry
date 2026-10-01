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
    let time=field(&dmb,"time")?;
    
    let log=field(&dmb,"log")?;
    
    let paths=["/area/LateInitialize","/obj/machinery/power/apc/Initialize","/obj/machinery/power/apc/proc/init","/obj/machinery/power/apc/proc/apply_area_power"];
    let targets=dmb.procs.iter().enumerate().filter_map(|(id,p)|{let path=String::from_utf8_lossy(dmb.string(p.strings[0])?).into_owned();paths.contains(&path.as_str()).then_some((id,path))}).collect::<Vec<_>>();
    for (id,path) in targets {
        let old=dmb.proc_code_words(id).ok_or("code missing")?.to_vec();
        let decoded=bytecode::decode(&old).map_err(|error|format!("{error:?}"))?;
        let mut values=vec![("time",select(V::World,time)),("src_type",select(V::Src,field(&dmb,"type")?))];
        let mut prefix=Vec::new();
        let guard:Option<usize>=None;
        if path=="/area/LateInitialize" {
            for name in ["apc","requires_power","power_equip","power_light","power_environ"] {values.push((name,select(V::Src,field(&dmb,name)?)));}
        } else {
            for name in ["area","operating","shorted","grid_check","failure_timer","lighting","equipment","environ"] {values.push((name,select(V::Src,field(&dmb,name)?)));}
        }        prefix.push(0x33);
        prefix.extend(select(V::World,log).encode());
        let mut template=format!("STARTUP_VALUES {id} {path}").into_bytes();
        for(name,value)in &values{
            template.extend(format!(" {name}=").as_bytes());
            template.extend([0xff,1]);
            prefix.push(0x33);
            prefix.extend(value.encode());
            if *name=="bucket_list_len"{prefix.push(0x6d);}
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


