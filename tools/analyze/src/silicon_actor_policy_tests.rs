//! Frozen old complete actor discovery/taint/helper traversal versus delegated judge.
//! This is not Native source/BODY adoption proof; full collector controls follow that port.
use std::{io,sync::{Arc,atomic::{AtomicUsize,Ordering}}};
#[path="../fixtures/native-silicon-actor/oracle.rs"]mod immutable;
#[path="../../dmb/shared/test_scratch.rs"]mod scratch;
const DEFINES:&str="#define issilicon(A) istype(A, /mob/living/silicon)\n#define isAI(A) istype(A, /mob/living/silicon/ai)\n#define isrobot(A) istype(A, /mob/living/silicon/robot)\n#define ispAI(A) istype(A, /mob/living/silicon/pai)\n";
const TYPES:&str="/datum/act\n    var/actor\n/datum/act/op\n/datum/act/timer\n/datum/prompt/choice\n/mob/living/silicon/ai\n/mob/living/silicon/robot\n/obj/machinery\n";
const CASES:&[(&str,&str)]=&[
 ("direct_macro","/obj/machinery/proc/use(datum/act/op/A)\n    return isAI(A.actor)\n"),
 ("macro_other_actor","/obj/machinery/proc/use(datum/act/op/A,mob/other)\n    return isrobot(other)\n"),
 ("literal_actor","/obj/machinery/proc/use(datum/act/op/A)\n    return istype(A.actor,/mob/living/silicon/ai)\n"),
 ("local_actor","/obj/machinery/proc/use(datum/act/op/A)\n    var/mob/user=A.actor\n    return istype(user,/mob/living/silicon/robot)\n"),
 ("flow_insensitive","/obj/machinery/proc/use(datum/act/op/A)\n    return istype(user,/mob/living/silicon/robot)\n    var/mob/user=A.actor\n"),
 ("ternary_actor","/obj/machinery/proc/use(datum/act/op/A)\n    var/mob/user=A.actor ? null : A.actor\n    return istype(user,/mob/living/silicon/robot)\n"),
 ("act_alias","/obj/machinery/proc/use(datum/act/op/A)\n    var/X=A\n    var/user=X.actor\n    return istype(user,/mob/living/silicon)\n"),
 ("helper","/obj/machinery/proc/use(datum/act/op/A)\n    return helper(A.actor)\n/obj/machinery/proc/helper(mob/user)\n    return isrobot(user)\n"),
 ("act_helper","/obj/machinery/proc/use(datum/act/op/A)\n    return helper(A)\n/obj/machinery/proc/helper(X)\n    return istype(X.actor,/mob/living/silicon)\n"),
 ("mixed_timer","/obj/machinery/proc/use(datum/act/op/A,datum/act/timer/T)\n    return isAI(A.actor)\n"),
 ("prompt_prepare","/datum/prompt/choice/prepare(datum/act/op/A)\n    return isAI(A.actor)\n"),
 ("base_prompt_prepare","/datum/prompt/proc/prepare(datum/act/op/A)\n    return isAI(A.actor)\n"),
 ("other_mob","/obj/machinery/proc/use(datum/act/op/A,mob/other)\n    return helper(other)\n/obj/machinery/proc/helper(mob/M)\n    return isAI(M)\n"),
 ("helper_handler_skipped","/obj/machinery/proc/use(datum/act/op/A)\n    return helper(A)\n/obj/machinery/proc/helper(datum/act/op/X)\n    return isAI(X.actor)\n"),
 ("global","/obj/machinery/proc/use(datum/act/op/A)\n    return global_helper(A.actor)\n/proc/global_helper(mob/M)\n    return issilicon(M)\n"),
 ("shared_helper","/obj/machinery/proc/zfirst(datum/act/op/A)\n    return helper(A.actor)\n/obj/machinery/proc/asecond(datum/act/op/A)\n    return helper(A.actor)\n/obj/machinery/proc/helper(M)\n    return issilicon(M)\n"),
 ("versions","/obj/machinery/proc/use(datum/act/op/A)\n    return isAI(A.actor)\n/obj/machinery/use(datum/act/op/A)\n    return isrobot(A.actor)\n"),
 ("if_else_lines","/obj/machinery/proc/use(datum/act/op/A)\n    if(isAI(A.actor))\n        return 1\n    else if(isrobot(A.actor))\n        return 2\n"),
 ("cyclic_helpers","/obj/machinery/proc/use(datum/act/op/A)\n    return one(A.actor)\n/obj/machinery/proc/one(M)\n    two(M)\n    return issilicon(M)\n/obj/machinery/proc/two(M)\n    return one(M)\n"),
 ("unselected_bad_body","/obj/machinery/proc/plain(M)\n    return )\n/obj/machinery/proc/use(datum/act/op/A)\n    return isAI(A.actor)\n"),
];
#[test]fn frozen_original_entire_actor_policy_matches_shared_judge_for_discovery_taint_helpers_and_order(){
 for(case,source)in CASES{let root=scratch::dir(&format!("silicon-actor-{case}"));let mut files=Vec::new();for(rel,text)in[("code/__defines/is.dm",DEFINES),("code/types.dm",TYPES),("code/probe.dm",*source)]{let path=root.join(rel);std::fs::create_dir_all(path.parent().unwrap()).unwrap();std::fs::write(&path,text).unwrap();files.push(crate::tree::SourceFile::from_text(rel,text));}let tree=crate::tree::Tree::from_files(files);let sem=crate::sem::Sem::build(&root,&tree).unwrap();let lines=|rel:&str,line:u32|tree.get(rel)?.code().numbered().find(|(n,_)|*n==line as usize).map(|(_,line)|line.to_owned());
 let old=immutable::actor_tests::actor_tests(&sem,&lines);let actual=crate::sem::actor_tests::actor_tests(&sem,&lines);assert_eq!(actual.iter().map(|r|(r.rule,&r.rel,r.line,&r.handler,&r.tested)).collect::<Vec<_>>(),old.iter().map(|r|(r.rule,&r.rel,r.line,&r.handler,&r.tested)).collect::<Vec<_>>(),"whole actor policy including output order: {case}");
 }
}
struct Probe{left:usize,polls:usize,fail_at:usize}impl crate::key_policy_control::Control for Probe{type Error=io::Error;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),io::Error>{self.polls+=1;if self.polls==self.fail_at{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}}fn reserve(&mut self,n:usize)->Result<(),io::Error>{self.left=self.left.checked_sub(n).ok_or(io::ErrorKind::OutOfMemory)?;Ok(())}fn overflow(&mut self)->io::Error{io::ErrorKind::OutOfMemory.into()}fn allocation_failed(&mut self)->io::Error{io::ErrorKind::OutOfMemory.into()}}
#[test]fn actual_native_actor_shapes_use_same_taint_judge_and_refuse_before_storage_growth(){
 let expression=dm_syntax::parse_expression("A.actor").expr.unwrap();let mut taint=crate::silicon_actor_policy::Taint::default();taint.acts.insert("A".into());assert!(taint.is_actor(&expression));let mut denied=Probe{left:0,polls:0,fail_at:usize::MAX};assert_eq!(taint.take_using("user",&expression,&mut denied).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert!(!taint.actors.contains("user"));let mut failed=Probe{left:1<<20,polls:0,fail_at:1};assert_eq!(taint.take_using("user",&expression,&mut failed).unwrap_err().raw_os_error(),Some(1450));assert!(!taint.actors.contains("user"));let mut healthy=Probe{left:1<<20,polls:0,fail_at:usize::MAX};taint.take_using("user",&expression,&mut healthy).unwrap();assert!(taint.is_actor(&dm_syntax::parse_expression("(user)").expr.unwrap()));assert!(!taint.is_actor(&dm_syntax::parse_expression("A.actor.field").expr.unwrap()));
}
#[test]fn final_actor_order_dedup_and_description_match_exact_original_contract(){
 use crate::silicon_actor_policy::*;let row=|rule,handler:&str|ActorTest{rule,rel:"code/probe.dm".into(),line:7,handler:handler.into(),tested:"macro".into()};let mut healthy=Probe{left:1<<20,polls:0,fail_at:usize::MAX};let actual=finalize_using(vec![row("helper_actor_check","/z/proc/use"),row("handler_actor_check","/z/proc/use"),row("handler_actor_check","/a/proc/use")],&mut healthy).unwrap();assert_eq!(actual.len(),1);assert_eq!(actual[0].handler,"/a/proc/use");assert_eq!(describe_using(&actual[0],&mut healthy).unwrap(),"an isAI()/issilicon()/isrobot()/ispAI() test in the op handler /a/proc/use");
}
