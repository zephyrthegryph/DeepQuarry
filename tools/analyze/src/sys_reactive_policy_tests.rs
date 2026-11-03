//! Independent old helpers, not a second candidate algorithm.
use crate::{sys_reactive_policy as current,dm::dx,tree::{SourceFile,Tree}};
use std::collections::{HashMap,HashSet};
use crate::key_policy_control::Gate;
#[path="../fixtures/original_policies/dx_reactive.rs"]mod original;
fn texts()->Vec<(&'static str,&'static str)>{vec![
("code/reactive.dm",r#"/obj/proc/draw(datum/look/look)
    var/own = src
    var/ctx = user
    var/watched = look.watch(cell)
    var/near in look.neighbours(1)
    var/datum/capability/C
    var/payload = capability_data(src)
    initial(cell.power)
    own.cell.power
    cell.power
    watched.power
    near.power
    ctx.power
    payload.cell.power
    C.power
    GLOB.cell.power
    cell.reagents.total_volume
    cell.len
    cell.proc_call()
    var/list/L = list()
    L.Add(1)
    cell.set_power(1)
    state = 1
/obj/proc/should_run()
    return cell.power
/obj/proc/unrelated()
    return cell.power
/obj/proc/look_parts(value)
    return cell.power
"#),
("maps/reactive.dm",r#"/datum/capability/probe/proc/gate(target)
    target.power
/datum/capability/probe/proc/ui_data(target)
    target.cell.power
/obj/proc/timed_context()
    timed_set(src, nameof(power), 1)
    timed_set(src, "charge", 1)
/obj/proc/change()
    power = 2
    charge++
    other.power += 1
/obj/proc/set_power(value)
    power = value
/obj/sub/proc/change()
    power = 3
/obj_other/proc/change()
    power = 4
"#),
("code/caps.dm",r#"/obj
    var/state
    var/other
/obj/proc/capabilities(value)
    state
    value
    src.unknown
    nameof(state)
    PROC_REF(state)
    var/local
    local
    list(state = 1)
    other()
/atom/proc/capabilities()
    src.name
"#),
("code/edge.dm",r#"/datum/proc/gate_check()
    thing.value
/obj
    needs = PROC_REF(gate_check)
    TRACKED(/obj, power)
    REL(/obj, cell, WATCH)
/obj/proc/hidden_verbs()
    var/local = cap_of(src)
    local.cell.power
    src.cell.power
/obj/proc/tgui_data()
    return thing.value
relative_proc()
    return thing.value
"#)]}
#[test]fn frozen_original_raw_helpers_retain_full_line_and_proc_outputs(){
 let tree=Tree::from_files(texts().into_iter().map(|(p,t)|SourceFile::from_text(p,t)).collect());
 let selected=tree.select(&crate::tree::CODE_MAPS_DM);
 let mut table=HashMap::<String,HashSet<String>>::new();let mut procs=Vec::new();
 for file in &selected{let fd=dx::file_dx_using(file,&mut crate::key_policy_control::Compatibility,&mut crate::key_policy_control::Compatibility).unwrap();for(owner,names)in &fd.vars{table.entry(owner.clone()).or_default().extend(names.iter().cloned());}procs.extend(fd.procs.iter().cloned());}
 assert!(procs.len()>10,"fixture must exercise genuine absolute proc producer");
 let old_timed=original::timed_vars(&tree,&procs);let mut new_timed=HashMap::new();
 let mut needs=HashSet::new();needs.insert("gate_check".to_owned());
 let watched=HashSet::from(["cell".to_owned()]);let mut counts=[0usize;3];
 let mut old_cache=HashMap::new();let mut new_cache=HashMap::new();
 for proc in &procs{let file=tree.get(&proc.rel).unwrap();let lines:Vec<_>=(0..proc.body_len).map(|n|{let line=proc.body_start+n;(line,file.clean().line(line))}).collect();
  current::add_timed_vars(proc,&lines,&|n|file.line(n),&mut new_timed);
  assert_eq!(current::is_reactive(proc,&needs),original::is_reactive(proc,&needs));
  assert_eq!(current::own_roots_of(proc,&lines,&watched),original::own_roots_of(proc,&tree,&watched));
  let old=original::caps_reads(proc,&tree,&table);assert_eq!(current::caps_reads(proc,&lines,&table),old);counts[0]+=old.len();
  let old=original::reactive_writes(proc,&tree);let new=crate::reactive_writer_policy::reactive_writes_lines_using(proc,&lines,&mut crate::key_policy_control::Compatibility,&mut crate::key_policy_control::Compatibility).unwrap();assert_eq!(new,old);counts[1]+=old.len();
  let old=original::timed_writes(proc,&tree,&old_timed,&mut old_cache);assert_eq!(current::timed_writes(proc,&lines,&old_timed,&mut new_cache),old);counts[2]+=old.len();
 }
 assert_eq!(new_timed,old_timed);assert!(counts.into_iter().all(|n|n>0),"each old caps/write/timed branch must actually produce findings");
 let own=HashSet::from(["self_alias".to_owned()]);let context=HashSet::from(["ctx".to_owned()]);
 for line in ["cell.power","GLOB.cell.power","self_alias.cell.power","cell.reagents.total_volume","cell.type","ctx.cell.power","SSatoms.cell.power","cell.proc_call()","cell?.power + foreign?.other.value","cell.power + cell.power"]{
  assert_eq!(current::foreign_reads(line,&own,&context,&watched),original::foreign_reads(line,&own,&context,&watched),"{line}");
 }
}
struct Work{left:usize,polls:usize,fail_at:usize}
impl crate::key_policy_control::Control for Work{type Error=std::io::Error;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Self::Error>{self.polls+=1;if self.polls==self.fail_at{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}}fn reserve(&mut self,n:usize)->Result<(),Self::Error>{self.checkpoint()?;self.left=self.left.checked_sub(n).ok_or_else(||std::io::Error::from(std::io::ErrorKind::OutOfMemory))?;Ok(())}fn overflow(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}fn allocation_failed(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}}
#[test]fn actual_inner_1450_and_quota_never_become_clean_and_fresh_work_recovers(){
 let text="cell.power + cell.power + cell.power";let empty=HashSet::new();
 for fail_at in [3,7,13]{let gate=crate::key_policy_control::Controlled::new(Work{left:1024*1024,polls:0,fail_at});let rows=current::foreign_reads_using(text,&empty,&empty,&empty,&gate);assert!(!gate.checkpoint(),"failed operation must remain poisoned");let e=gate.finish(rows).unwrap_err();assert_eq!(e.raw_os_error(),Some(1450));}
 let gate=crate::key_policy_control::Controlled::new(Work{left:0,polls:0,fail_at:usize::MAX});let rows=current::foreign_reads_using(text,&empty,&empty,&empty,&gate);assert_eq!(gate.finish(rows).unwrap_err().kind(),std::io::ErrorKind::OutOfMemory);
 let gate=crate::key_policy_control::Controlled::new(Work{left:1024*1024,polls:0,fail_at:usize::MAX});let rows=current::foreign_reads_using(text,&empty,&empty,&empty,&gate);assert_eq!(gate.finish(rows).unwrap(),original::foreign_reads(text,&empty,&empty,&empty));
}
