use byond_dmb::{dmb::Dmb,operands::Value};
use std::{env,fs,path::PathBuf};
fn main()->Result<(),Box<dyn std::error::Error>>{
let input=PathBuf::from(env::args_os().nth(1).ok_or("input")?);let output=PathBuf::from(env::args_os().nth(2).ok_or("output")?);
let mut dmb=Dmb::from_bytes(&fs::read(&input)?)?;
let names=["dq_air_alarm_receives_matching_status","dq_air_alarm_skips_unchanged_air","dq_blocked_airlock_wakes_from_blocker_movement","dq_closed_airlock_clears_stale_autoclose","dq_idle_meter_and_fire_alarm_hibernate"];
let base=dmb.classes.iter().position(|c|dmb.string(c.path_string_id())==Some(b"/datum/unit_test")).ok_or("base missing")?;
let candidates=dmb.variables.iter().enumerate().filter(|(_,v)|dmb.string(v.name)==Some(b"focus")).map(|(i,_)|i as u32).collect::<Vec<_>>();println!("focus VarIDs {:?}, base defining {:?}",candidates,dmb.lists.get(dmb.classes[base].defining_variable_list_id() as usize));
let vid=*candidates.iter().find(|v|dmb.lists.get(dmb.classes[base].defining_variable_list_id() as usize).map(|l|l.contains(v)).unwrap_or(false)).or(candidates.first()).ok_or("focus var missing")?;let mut selected=0;
for id in 0..dmb.classes.len(){let path=String::from_utf8_lossy(dmb.string(dmb.classes[id].path_string_id()).unwrap_or_default()).into_owned();if !path.starts_with("/datum/unit_test/") && path!="/datum/unit_test"{continue;}
let enabled=names.iter().any(|n|path==format!("/datum/unit_test/{n}"));if enabled{selected+=1;println!("focus {id} {path}");}
let mut entries=dmb.class_initial_values(id).unwrap_or_default();entries.retain(|v|v.variable_id!=vid);
let bits=if enabled{1f32}else{0f32}.to_bits();entries.push(byond_dmb::dmb::ClassInitialValue{variable_id:vid,value:Value{tag_word:42,data_word:bits>>16,extra_word:Some(bits&65535)}});
let mut words=Vec::new();for entry in entries{words.push(entry.variable_id);words.extend(entry.value.encode());}
if dmb.lists.len()==65535{dmb.lists.push(vec![]);}let list=dmb.lists.len() as u32;dmb.lists.push(words);dmb.classes[id].lists_and_procs[3]=list;
}
if selected!=5{return Err(format!("selected {selected}").into());}if dmb.lists.len()>65535{dmb.header.flags|=0x40000000;}
dmb.validate_references()?;let bytes=dmb.to_bytes()?;Dmb::from_bytes(&bytes)?.validate_references()?;fs::create_dir_all(output.parent().ok_or("parent")?)?;fs::write(&output,bytes)?;fs::copy(input.with_extension("rsc"),output.with_extension("rsc"))?;Ok(())}

