//! Partial sem/handlers recipe DATA from the existing actual raw-page protocol.
//! The concrete host keeps the discovery/current-source witness. A completed
//! callback bool is not a full-workspace or semantic-availability authority.
use crate::{captured_generator_budget::Budget,captured_reactive_reads::Failure,key_policy_control::{self as kc,Control},reactive_raw_policy_pages::RawPolicyPages,sem_handlers_partial_recipe::{Recipe,Selection}};
use std::{collections::HashMap,io,sync::Arc};
struct Native<'a>{budget:&'a Budget,poll:&'a dyn Fn()->io::Result<()>}
fn oom(budget:&Budget,message:&str)->Failure{budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message))}
impl Control for Native<'_>{type Error=Failure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Failure>{self.budget.require().map_err(|_|oom(self.budget,"partial recipe budget denied"))?;(self.poll)()?;self.budget.require().map_err(|_|oom(self.budget,"partial recipe budget denied"))}fn reserve(&mut self,n:usize)->Result<(),Failure>{self.budget.charge(n).map_err(|_|oom(self.budget,"partial recipe allocation denied"))}fn overflow(&mut self)->Failure{oom(self.budget,"partial recipe allocation overflow")}fn allocation_failed(&mut self)->Failure{oom(self.budget,"partial recipe allocator refused")}}
/// Unsealed policy DATA only; concrete recorded input owner still supplies all
/// currentness, purpose and preparation-availability authority.
pub struct SelectionPlan{pub recipe:Recipe,pub requires_full:bool}
pub fn select_from_pages(pages:&dyn RawPolicyPages,order:&HashMap<String,usize>,extra:&[String],budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<Recipe,Failure>{Ok(select_with_demand_from_pages(pages,order,extra,budget,poll)?.recipe)}
pub fn select_with_demand_from_pages(pages:&dyn RawPolicyPages,order:&HashMap<String,usize>,extra:&[String],budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<SelectionPlan,Failure>{
 let mut control=Native{budget,poll};control.checkpoint()?;let mut selection=Selection::default();let mut previous=None::<String>;
 // One real source acquisition per selected page. Candidate classification and
 // the SAME original all-declarations marker scanner consume the SAME loan.
 let rows=crate::reactive_raw_policy_pages::collect_marker_rows_funded(|visit|pages.for_each(&mut|relative,views|{
  control.checkpoint()?;if !crate::captured_raw_file::is_code_dm(relative){return Err("handlers structural selector requires exact CODE_DM pages".into())}if previous.as_deref().is_some_and(|old|old>=relative){return Err("handlers structural CODE_DM pages are not unique slash-string ordered".into())}previous=Some(kc::own(&mut control,relative)?);
  let original=views.raw()?;let hash=blake3::hash(original.as_bytes());let fingerprint=u128::from_le_bytes(hash.as_bytes()[..16].try_into().expect("fixed digest width"));let code=views.code()?;selection.push(relative,fingerprint,&code.text,&mut control)?;visit(relative,views)
 }),order,budget,crate::sem_handlers_partial_recipe::DECLARATION_MARKERS,true,true,true,poll)?;
 let declared=demand_from_rows(&rows,&mut control)?;
 let mut generated=Vec::new();for marker in &rows.markers{control.checkpoint()?;if marker.name!="ACTION"||marker.args.iter().any(|arg|arg=="FIXED"){continue}let Some(name)=marker.args.first()else{continue};kc::row(&mut control,&mut generated)?;kc::reserve(&mut control,||name.len().checked_add(64))?;let name=name.replace('/',"_");generated.push(kc::format(&mut control,format_args!("act_{name}"))?);}
 let recipe=selection.finish(extra,generated,&mut control)?;let requires_full=recipe.has_output_base||declared;control.checkpoint()?;Ok(SelectionPlan{recipe,requires_full})
}
fn demand_from_rows<C:Control<Error=Failure>>(rows:&crate::captured_marker_rows::Rows<'_>,control:&mut C)->Result<bool,Failure>{let mut markers=Vec::new();for row in &rows.markers{control.checkpoint()?;kc::row(control,&mut markers)?;markers.push(crate::declare_policy::Marker{name:&row.name,rel:&row.rel,line:row.line,body:&row.body,args:&row.args,body_offset:row.body_offset,line_starts:&row.line_starts});}let refs=crate::reactive_hooks_policy::discover_admitted(&markers,control)?;control.checkpoint()?;Ok(!refs.is_empty()||rows.markers.iter().any(|marker|marker.name=="READS_AS"))}

#[cfg(test)]mod tests{
 use super::*;use crate::captured_raw_file::{File,RawPolicyViews};use std::cell::Cell;
 struct Pages{files:Vec<File>,stop:Cell<bool>,fail:Cell<bool>}
 impl RawPolicyPages for Pages{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{if self.fail.get(){return Err(Failure::Operational(io::Error::from_raw_os_error(1450)))}if self.stop.get(){return Ok(false)}for file in &self.files{if !file.with_policy_views(visit)?{return Ok(false)}}Ok(true)}}
 fn fixture()->Pages{let root=std::env::current_dir().unwrap().join("handlers-native-recipe");let files=[("code/__defines/a.dm","#define A 1\n"),("code/a.dm","ACTION(a/b, mob/user)\n/proc/a(datum/act/A)\n    return\n"),("code/ordinary.dm","#define START ACT_ATTEMPT\nACTION(skipped, FIXED)\n"),("code/z.dm","ACTION(z)\n")].into_iter().map(|(rel,text)|File::capture(&root,&root.join(rel),text.to_owned().into()).unwrap()).collect();Pages{files,stop:Cell::new(false),fail:Cell::new(false)}}
 #[test]fn actual_pages_keep_partial_includes_and_all_action_vocabulary(){let pages=fixture();let recipe=select_from_pages(&pages,&HashMap::from([("code/z.dm".to_owned(),0)]),&["custom_try".to_owned()],&Budget::new(8*1024*1024).unwrap(),&||Ok(())).unwrap();assert_eq!(recipe.includes.iter().map(|i|i.relative.as_str()).collect::<Vec<_>>(),["code/__defines/a.dm","code/a.dm"]);assert_eq!(&recipe.try_calls[4..],["custom_try","act_z","act_a_b"]);assert!(!recipe.has_output_base);}
 #[test]fn stopped_and_operational_pages_never_become_available_empty_tu(){let pages=fixture();pages.stop.set(true);assert!(matches!(select_from_pages(&pages,&HashMap::new(),&[],&Budget::new(8*1024*1024).unwrap(),&||Ok(())),Err(Failure::Unsupported(_))));pages.stop.set(false);pages.fail.set(true);assert!(matches!(select_from_pages(&pages,&HashMap::new(),&[],&Budget::new(8*1024*1024).unwrap(),&||Ok(())),Err(Failure::Operational(e))if e.raw_os_error()==Some(1450)));pages.fail.set(false);assert!(!select_from_pages(&pages,&HashMap::new(),&[],&Budget::new(8*1024*1024).unwrap(),&||Ok(())).unwrap().candidates.is_empty());}
}

/// Exact old full-model demand: handlers OR READS_AS, independently of the
/// structural candidate set and the standard-output-base flag.
pub fn declared_model_demand(pages:&dyn RawPolicyPages,order:&HashMap<String,usize>,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<bool,Failure>{
 let rows=crate::reactive_raw_policy_pages::collect_marker_rows_funded(|visit|pages.for_each(visit),order,budget,crate::sem_handlers_partial_recipe::DECLARATION_MARKERS,true,true,true,poll)?;let mut control=Native{budget,poll};demand_from_rows(&rows,&mut control)
}

#[cfg(all(test,feature="legacy-sem"))]mod declared_demand_tests{
 use super::*;use crate::{captured_raw_file::{File,RawPolicyViews},tree::{Tree,SourceFile}};
 struct Pages(File);impl RawPolicyPages for Pages{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{self.0.with_policy_views(visit)}}
 #[test]fn full_model_demand_matches_real_legacy_decls_for_entry_runtime_reads_as_and_empty(){
  let root=std::env::current_dir().unwrap().join("handlers-full-model-demand");
  for text in["/datum/ordinary\n","CAPABILITIES(/obj/probe,cover())\n","READS_AS(/obj/probe,value)\n","CAPABILITIES(/obj/probe,then(PROC_REF(handler)))\n","/proc/parts()\n    return list(then(TYPE_PROC_REF(/obj/probe,handler)))\n","/proc/install()\n    observe(host,/datum/notice/hit,listener,then(TYPE_PROC_REF(/obj/probe,handler)))\n","CAPABILITY_TYPE(probe,CAP_PROBE,/datum/capability/probe,holder=/obj/probe,then(CAP_PROC(handler)))\n"]{
   let tree=Tree::from_files(vec![SourceFile::from_text("code/a.dm",text)]);let declarations=crate::sem::decls::Decls::get(&tree);let expected=!crate::sem::hooks::discover(&declarations).is_empty()||declarations.markers_named("READS_AS").next().is_some();let pages=Pages(File::capture(&root,&root.join("code/a.dm"),text.to_owned().into()).unwrap());let actual=declared_model_demand(&pages,&HashMap::new(),&Budget::new(8*1024*1024).unwrap(),&||Ok(())).unwrap();assert_eq!(actual,expected,"actual old preflight demand for {text}");
  }
 }
}

#[cfg(test)]mod one_actual_raw_loan_controls{
 use super::*;use crate::captured_raw_file::{File,RawPolicyViews};use std::cell::Cell;
 struct Once{file:File,visits:Cell<usize>}impl RawPolicyPages for Once{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{let n=self.visits.get();self.visits.set(n+1);if n!=0{return Err("actual raw page acquisition repeated".into())}self.file.with_policy_views(visit)}}
 #[test]fn candidates_generated_calls_and_full_demand_use_one_same_recorded_page_pass(){let root=std::env::current_dir().unwrap().join("handler-one-source-preflight");for(text,demand,candidate)in[("ACTION(a/b)\n/proc/p(datum/act/A)\n    return\n",false,true),("READS_AS(/datum/probe,value)\n",true,false),("/datum/ordinary\n",false,false)]{let pages=Once{file:File::capture(&root,&root.join("code/a.dm"),text.to_owned().into()).unwrap(),visits:Cell::new(0)};let plan=select_with_demand_from_pages(&pages,&HashMap::new(),&[],&Budget::new(8*1024*1024).unwrap(),&||Ok(())).unwrap();assert_eq!(pages.visits.get(),1);assert_eq!(plan.requires_full,demand);assert_eq!(!plan.recipe.candidates.is_empty(),candidate);if text.starts_with("ACTION"){assert_eq!(&plan.recipe.try_calls[4..],["act_a_b"]);}}}
}
