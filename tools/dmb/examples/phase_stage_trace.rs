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
    
    let paths=["/mob/living/proc/dq_do_phase_shift","/mob/living/proc/phase_in","/mob/living/proc/phase_out"];
    let targets=dmb.procs.iter().enumerate().filter_map(|(id,p)|{let path=String::from_utf8_lossy(dmb.string(p.strings[0])?).into_owned();paths.contains(&path.as_str()).then_some((id,path))}).collect::<Vec<_>>();
    for (id,path) in targets {
        let old=dmb.proc_code_words(id).ok_or("code missing")?.to_vec();
        let decoded=bytecode::decode(&old).map_err(|error|format!("{error:?}"))?;
        let mut values=vec![("time",select(V::World,time)),("src_type",select(V::Src,field(&dmb,"type")?))];
        let mut prefix=Vec::new();
        let guard:Option<usize>=None;
        values.push(("src_loc",select(V::Src,field(&dmb,"loc")?)));
        values.push(("arg0",V::Arg(0)));
        if path.ends_with("phase_in") {values.push(("component",V::Arg(1)));}        prefix.push(0x33);
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
        let mut starts=std::collections::BTreeMap::new();
        let mut branches=Vec::new();
        let mut words=prefix;
        for ins in &decoded {
            starts.insert(ins.offset,words.len());
            for at in ins.branch_target_word_offsets().map_err(|e|format!("{e:?}"))? {branches.push((words.len()+at-ins.offset,old[at] as usize));}
            words.push(ins.opcode);words.extend(&ins.operands);
            if [0x29,0x2a,0x30].contains(&ins.opcode) {
                let marker=dmb.strings.len() as u32;
                dmb.strings.push(DmString{data:format!("PHASE_STAGE {id} {path} after_call {:04x}",ins.offset).into_bytes(),long_chunks:0});
                words.push(0x33);words.extend(select(V::World,log).encode());words.extend([0x04,marker,0]);
                words.push(0x33);words.extend(select(V::Src,field(&dmb,"type")?).encode());words.push(0x51);
            }
        }
        starts.insert(old.len(),words.len());
        for(at,target)in branches {words[at]=*starts.get(&target).ok_or("bad branch boundary")? as u32;}        dmb.replace_proc_code(id,&bytecode::decode(&words).map_err(|error|format!("{error:?}"))?)?;
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




