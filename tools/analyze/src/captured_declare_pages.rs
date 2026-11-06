//! Source-neutral Declare output from exhausted callback-local original loans.
//! Only the host may attach current workspace and domain completion witnesses.
use crate::{captured_generator_budget::Budget,captured_reactive_reads::Failure,reactive_raw_policy_pages::RawPolicyPages,sparse_slots_policy::Output};
use std::{collections::{BTreeSet,HashMap},io,sync::Arc};
use crate::key_policy_control::Control as _;
fn oom(budget:&Budget,message:impl Into<String>)->Failure{budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message.into()))}
struct Scratch{budget:Arc<Budget>,complete:bool}
impl Drop for Scratch{fn drop(&mut self){if !self.complete{self.budget.keep_failed_scratch()}}}
struct Control<'a>{budget:&'a Arc<Budget>,poll:&'a dyn Fn()->io::Result<()>}
impl crate::key_policy_control::Control for Control<'_>{
 type Error=Failure;const CHECKED:bool=true;
 fn checkpoint(&mut self)->Result<(),Failure>{self.budget.require().map_err(|message|oom(self.budget,message))?;(self.poll)()?;self.budget.require().map_err(|message|oom(self.budget,message))}
 fn reserve(&mut self,bytes:usize)->Result<(),Failure>{self.budget.charge(bytes).map_err(|message|oom(self.budget,message))}
 fn overflow(&mut self)->Failure{oom(self.budget,"Declare policy allocation overflow")}
 fn allocation_failed(&mut self)->Failure{oom(self.budget,"Declare policy allocation refused")}
}
fn finish<T>(result:Result<T,Failure>,control:&mut Control<'_>)->Result<T,Failure>{
 if matches!(&result,Err(Failure::Operational(_))){return result}
 control.checkpoint()?;result
}
/// No raw text or per-file semantic object escapes. The constructor summary
/// consists only of exact original /proc/ spellings and moves into the generator.
/// Caller owns the as-of source/domain proof, not this source-neutral result.
pub fn generate_from_pages(pages:&dyn RawPolicyPages,order:&HashMap<String,usize>,root:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<Output,Failure>{
 use crate::key_policy_control::{self as kc,Control as _};
 let mut entry=Control{budget:root,poll};entry.checkpoint()?;
 let mut scratch=Scratch{budget:Budget::scoped_temporaries(root).map_err(|message|oom(root,message))?,complete:false};
 let mut control=Control{budget:&scratch.budget,poll};
 let produced=(||{
  let rows=crate::reactive_raw_policy_pages::collect_marker_rows(|visit|pages.for_each(visit),order,&scratch.budget,crate::declare_policy::MARKERS,false,false,false,&mut||{scratch.budget.require().map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;poll()?;scratch.budget.require().map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))},&||scratch.budget.require().map_err(|message|oom(&scratch.budget,message)))?;
  if rows.markers.iter().any(|row| row.part.is_some()) {
   return Err(Failure::Unsupported(crate::captured_marker_rows::DECLARE_PARTS_UNSUPPORTED.into()));
  }
  let mut constructors=BTreeSet::new();
  let complete=pages.for_each(&mut|relative,views|{
   control.checkpoint()?;
   if relative.starts_with("code/engine/"){
    crate::declare_policy::visit_engine_constructors(&mut control,relative,views.raw()?,&mut|control,name|{
     if !constructors.contains(name){kc::reserve(control,||2048usize.checked_add(std::mem::size_of::<String>().checked_mul(16)?))?;constructors.insert(kc::own(control,name)?);}
     Ok(())
    })?;
   }
   control.checkpoint()?;Ok(true)
  })?;
  if !complete{return Err(Failure::Unsupported("Declare constructor traversal did not complete".into()))}
  let mut markers=Vec::new();
  for row in &rows.markers{kc::row(&mut control,&mut markers)?;markers.push(crate::declare_policy::Marker{name:&row.name,rel:&row.rel,line:row.line,body:&row.body,args:&row.args,body_offset:row.body_offset,line_starts:&row.line_starts});}
  let input=crate::declare_policy::Input{markers:&markers,engine_sources:&[],poll:None,budget:Some(Arc::clone(&scratch.budget))};
  let mut generated=crate::declare_policy::generate_with_constructors(&input,&mut control,Some(constructors))?;
  control.checkpoint()?;
  let mut output=Output::default();output.body=std::mem::take(&mut generated.body);output.diags=std::mem::take(&mut generated.diags);drop(generated);
  Ok(output)
 })();
 let produced=finish(produced,&mut control);drop(control);
 let funded=match produced{
  Ok(output)=>{
   let bytes=output.diags.capacity().checked_mul(std::mem::size_of::<crate::sparse_slots_policy::Diagnostic>()).and_then(|n|n.checked_add(output.body.capacity())).and_then(|n|n.checked_add(std::mem::size_of::<Output>())).and_then(|n|output.diags.iter().try_fold(n,|n,row|n.checked_add(row.rel.capacity())?.checked_add(row.msg.capacity())));
   match bytes.ok_or_else(||oom(root,"Declare output capacity overflow")).and_then(|bytes|root.charge(bytes).map_err(|message|oom(root,message))){Ok(())=>Ok(output),Err(actual)=>{drop(output);Err(actual)}}
  },Err(actual)=>Err(actual)
 };
 scratch.complete=funded.is_ok();drop(scratch);
 finish(funded,&mut entry)
}

#[cfg(test)]#[path="support/declare_before_ids.rs"]mod declare_before_ids;
#[cfg(test)]#[path="support/declare_before_policy.rs"]mod declare_before_policy;
#[cfg(test)]mod tests{
 use super::*;use crate::{captured_raw_file::{File,RawPolicyViews},key_policy_control::Control as _};use std::cell::Cell;
 struct Pages{files:Vec<File>,fail:Cell<bool>,stop:Cell<bool>}
 impl RawPolicyPages for Pages{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{for file in &self.files{if !file.with_policy_views(visit)?{return Ok(false)}}if self.fail.get(){return Err(Failure::Operational(io::Error::from_raw_os_error(1450)))}Ok(!self.stop.get())}}
 fn fixture()->Pages{
  let root=std::env::current_dir().unwrap().join("declare-growth-data");
  let sources=[("code/a.dm",r#"CAPABILITY_TYPE(cover, CAP_COVER, /datum/cover, key = material, prefix = cover, material = null)
CAPABILITY_DEF(light, CAP_LIGHT, radius = 3)
cap_keys(CAP_COVER, OPEN = TRUE, COUNT = 2)
STAGE_DEF(build, ready)
SOURCE_DEF(wall)
STATE_GRAPH(BUILD, stage(ready), source(wall))
STATIC_ENTRY(loot)
CAPABILITIES(/datum/device)
    section(first, "The controls")
    cover(material = "steel")
    ref_one(nameof(target), /datum, weak = TRUE, target_key = id)
    param(nameof(rate))
    factors(scale = 1)
    loot(table = list(/obj/a = 2))
    section(duplicate)
    section(duplicate)
    unknown(4)
CAPABILITIES(/obj/device)
    section(empty)
    bad_assignment = 2
"#),("code/tests/test.dm","CAPABILITIES(/datum/unit_test/probe)\n    cover()\n"),("code/engine/source.dm","/proc/factors(scale)\n/proc/covering(value)\n    return value\n")];
  Pages{files:sources.into_iter().map(|(relative,text)|File::capture(&root,&root.join(relative),text.to_owned().into()).unwrap()).collect(),fail:Cell::new(false),stop:Cell::new(false)}
 }
 #[test]fn declare_growth_policy_matches_complete_preport_output_and_ordered_diagnostics(){
  let pages=fixture();let order=HashMap::from([("code/tests/test.dm".to_owned(),0),("code/a.dm".to_owned(),1)]);let root=Budget::new(32*1024*1024).unwrap();let output=generate_from_pages(&pages,&order,&root,&||Ok(())).unwrap();
  let oldbudget=Budget::new(32*1024*1024).unwrap();let rows=crate::reactive_raw_policy_pages::collect_marker_rows(|visit|pages.for_each(visit),&order,&oldbudget,crate::declare_policy::MARKERS,false,false,false,&mut||Ok(()),&||Ok(() )).unwrap();
  let markers:Vec<_>=rows.markers.iter().map(|row|declare_before_policy::Marker{name:&row.name,rel:&row.rel,line:row.line,body:&row.body,args:&row.args,body_offset:row.body_offset,line_starts:&row.line_starts}).collect();
  let engines=vec![("code/engine/source.dm","/proc/factors(scale)\n/proc/covering(value)\n    return value\n")];
  let old=declare_before_policy::generate(&declare_before_policy::Input{markers:&markers,engine_sources:&engines,poll:None,budget:None},||Ok(())).unwrap();
  assert_eq!(output.body,old.body);assert_eq!(output.diags,old.diags);assert!(!output.diags.is_empty());assert!(output.body.contains("global.factors"));assert!(output.body.contains("weak_get"));assert!(output.body.contains("#if defined(UNIT_TESTS)"));
 }
 #[test]fn native_declare_refuses_parts_before_publishing_partial_composition(){
  let mut pages=fixture();
  let root=std::env::current_dir().unwrap().join("declare-growth-data");
  pages.files.push(File::capture(&root,&root.join("code/part.dm"),
      "CAPABILITIES_PART(/datum/device, device_extra)\n    cover()\n".into()).unwrap());
  let run=|pages:&Pages|generate_from_pages(pages,&HashMap::new(),&Budget::new(32*1024*1024).unwrap(),&||Ok(()));
  let error=run(&pages).unwrap_err();
  assert!(matches!(error,Failure::Unsupported(message) if message==crate::captured_marker_rows::DECLARE_PARTS_UNSUPPORTED));
  pages.files.pop();
  assert!(run(&pages).unwrap().body.contains("/datum/device/declared_entries"));
 }

 #[test]fn declare_growth_preserves_actual_io_quota_and_stopped_traversal_then_recovers(){
  let pages=fixture();pages.fail.set(true);let error=generate_from_pages(&pages,&HashMap::new(),&Budget::new(32*1024*1024).unwrap(),&||Ok(())).unwrap_err();assert!(matches!(error,Failure::Operational(ref actual)if actual.raw_os_error()==Some(1450)));pages.fail.set(false);pages.stop.set(true);assert!(matches!(generate_from_pages(&pages,&HashMap::new(),&Budget::new(32*1024*1024).unwrap(),&||Ok(())),Err(Failure::Unsupported(_))));pages.stop.set(false);
  let tiny=Budget::new(4096).unwrap();let error=generate_from_pages(&pages,&HashMap::new(),&tiny,&||if tiny.denied(){Err(io::ErrorKind::Interrupted.into())}else{Ok(())}).unwrap_err();assert!(matches!(error,Failure::Operational(ref actual)if actual.kind()==io::ErrorKind::OutOfMemory));assert!(!generate_from_pages(&pages,&HashMap::new(),&Budget::new(32*1024*1024).unwrap(),&||Ok(())).unwrap().body.is_empty());
 }
 #[test]fn declare_shared_text_and_call_helpers_keep_preport_unicode_escape_and_match_quirks(){
  for text in["", "  alpha\t beta ", "a\\\n  b", "a\\\r\n b", "α\u{2003}β\u{a0}γ", "\\\\\n", "a\r\nb", "\"a\\b\"", "name(\"one\", list(a, b))"]{
   assert_eq!(crate::declare_policy::one_line(text),declare_before_policy::one_line(text));assert_eq!(crate::declare_policy::quote(text),declare_before_policy::quote(text));
  }
  for text in["f(1)","outer(f(1), f(list(2,3)))", "obj.f(1); /proc/f(2); global.f(3)","αf(1) f(2)", "\"f(inside)\" + f(outside)","f (1) f(2) f("]{
   let rewrite=|args:&[String]|format!("replace[{}]",args.join("|"));assert_eq!(crate::declare_policy::rewrite_calls(text,"f",&rewrite),declare_before_policy::rewrite_calls(text,"f",&rewrite));
  }
 }
 #[test]fn declare_engine_padding_is_not_charged_as_marker_or_constructor_transform_work(){
  let root=std::env::current_dir().unwrap().join("declare-engine-padding");let text=format!("{}\n/proc/wall(a,b)\n", "// unused engine source padding\n".repeat(4096));
  let pages=Pages{files:[("code/a.dm","CAPABILITIES(/datum/probe)\n    wall(1, 2)\n".to_owned()),("code/engine/large.dm",text)].into_iter().map(|(relative,text)|File::capture(&root,&root.join(relative),text.into()).unwrap()).collect(),fail:Cell::new(false),stop:Cell::new(false)};
  let budget=Budget::new(3*1024*1024).unwrap();let before=budget.used();let out=generate_from_pages(&pages,&HashMap::new(),&budget,&||Ok(())).unwrap();assert!(out.body.contains("global.wall(1, 2)"));assert!(!budget.denied());
  let retained=out.body.capacity()+out.diags.capacity()*std::mem::size_of::<crate::sparse_slots_policy::Diagnostic>()+out.diags.iter().map(|row|row.rel.capacity()+row.msg.capacity()).sum::<usize>()+std::mem::size_of::<Output>();
  assert_eq!(budget.used()-before,retained+std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>(),"only actual moved output and fixed scratch metadata survive");
 }

 #[test]fn declare_preport_reference_projection_changes_only_nominal_cap_type_paths(){
  let frozen=include_str!("support/declare_before_policy.frozen");let projected=include_str!("support/declare_before_policy.rs");
  let expected=frozen.replace("    declare_ids_policy::{split_opt, Cap},\n","").replace("use std::collections::{BTreeMap, BTreeSet};","use std::collections::{BTreeMap,BTreeSet};\nuse super::declare_before_ids::{split_opt,Cap};").replace("crate::declare_ids_policy::parse_capability","super::declare_before_ids::parse_capability");assert_eq!(projected,expected);
 }

}
