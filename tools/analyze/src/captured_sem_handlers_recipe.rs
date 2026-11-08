//! Partial sem/handlers recipe DATA from the existing actual raw-page protocol.
//! The concrete host keeps the discovery/current-source witness. A completed
//! callback bool is not a full-workspace or semantic-availability authority.
use crate::{captured_generator_budget::Budget,captured_reactive_reads::Failure,key_policy_control::{self as kc,Control},reactive_raw_policy_pages::RawPolicyPages,sem_handlers_partial_recipe::{Recipe,Selection}};
use std::{collections::HashMap,io,sync::Arc};
struct Native<'a>{budget:&'a Budget,poll:&'a dyn Fn()->io::Result<()>}
fn oom(budget:&Budget,message:impl Into<String>)->Failure{budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message.into()))}
impl Control for Native<'_>{type Error=Failure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Failure>{self.budget.require().map_err(|_|oom(self.budget,"partial recipe budget denied"))?;(self.poll)()?;self.budget.require().map_err(|_|oom(self.budget,"partial recipe budget denied"))}fn reserve(&mut self,n:usize)->Result<(),Failure>{self.budget.charge(n).map_err(|_|oom(self.budget,"partial recipe allocation denied"))}fn overflow(&mut self)->Failure{oom(self.budget,"partial recipe allocation overflow")}fn allocation_failed(&mut self)->Failure{oom(self.budget,"partial recipe allocator refused")}}
/// Unsealed policy DATA only; concrete recorded input owner still supplies all
/// currentness, purpose and preparation-availability authority.
pub struct SelectionPlan{pub recipe:Recipe,pub requires_full:bool}
pub fn select_from_pages(pages:&dyn RawPolicyPages,order:&HashMap<String,usize>,extra:&[String],budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<Recipe,Failure>{Ok(select_with_demand_from_pages(pages,order,extra,budget,poll)?.recipe)}
pub fn select_with_demand_from_pages(pages:&dyn RawPolicyPages,order:&HashMap<String,usize>,extra:&[String],budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<SelectionPlan,Failure>{
 select_scoped_from_pages(pages,order,extra,None,None,budget,poll)
}
pub fn select_scoped_from_pages(pages:&dyn RawPolicyPages,order:&HashMap<String,usize>,extra:&[String],scope:Option<&crate::scopes::LintScope>,manifest:Option<&str>,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<SelectionPlan,Failure>{
 let mut control=Native{budget,poll};control.checkpoint()?;
 let recipe_funding=Budget::scoped_temporaries(budget).map_err(|message|oom(budget,message))?;
 let mut control=Native{budget:&recipe_funding,poll};let mut selection=Selection::default();let mut previous=String::new();
 let marker_funding = Budget::scoped_temporaries(budget).map_err(|message| oom(budget,message))?;
 // One real source acquisition per selected page. Candidate classification and
 // the SAME original all-declarations marker scanner consume the SAME loan.
 let rows=crate::reactive_raw_policy_pages::collect_marker_rows_funded(|visit|pages.for_each(&mut|relative,views|{
  control.checkpoint()?;
  if !crate::captured_raw_file::is_code_dm(relative){return Err("handlers structural selector requires exact CODE_DM pages".into())}
  if previous.as_str() >= relative{return Err("handlers structural CODE_DM pages are not unique slash-string ordered".into())}
  previous.clear();
  if !recipe_funding.string(&mut previous,relative){return Err(oom(&recipe_funding,"handler source order allocation denied"));}
  let original=views.raw()?;let hash=blake3::hash(original.as_bytes());let fingerprint=u128::from_le_bytes(hash.as_bytes()[..16].try_into().expect("fixed digest width"));if scope.is_some_and(|scope|scope.exempt(relative)){
   selection.push_facts(relative,fingerprint,None,&mut control)?;
  }else if let Some(facts)=pages.handler_code_facts(){
   selection.push_facts(relative,fingerprint,Some(facts),&mut control)?;
  }else{
   selection.push_selected(relative,fingerprint,Some(views.code()?.text.as_str()),&mut control)?;
  }visit(relative,views)
 }),order,&marker_funding,crate::sem_handlers_partial_recipe::DECLARATION_MARKERS,true,true,true,poll)?;
 let declared=demand_from_rows(&rows,budget,poll)?;
 let mut generated=Vec::new();for marker in &rows.markers{control.checkpoint()?;if marker.name!="ACTION"||marker.args.iter().any(|arg|arg=="FIXED"){continue}let Some(name)=marker.args.first()else{continue};kc::row(&mut control,&mut generated)?;kc::reserve(&mut control,||name.len().checked_add(64))?;let name=name.replace('/',"_");generated.push(kc::format(&mut control,format_args!("act_{name}"))?);}
 drop(rows);
 drop(marker_funding);
 let recipe=selection.finish_with_manifest(extra,generated,manifest,&mut control)?;let requires_full=recipe.has_output_base||declared;control.checkpoint()?;
 let retained=recipe.retained_backing().ok_or_else(||oom(budget,"handler recipe retained storage overflow"))?;
 budget.charge(retained).map_err(|message|oom(budget,message))?;
 drop(previous);
 drop(recipe_funding);
 Ok(SelectionPlan{recipe,requires_full})
}
fn demand_from_rows(rows:&crate::captured_marker_rows::Rows<'_>,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<bool,Failure>{
 for row in &rows.markers {
  poll()?;
  budget.require()?;
  if row.name == "READS_AS" { return Ok(true); }
  if !crate::reactive_hooks_policy::is_handler_marker(&row.name) {
   continue;
  }
  // Preparation needs only the demand bit. The full policy separately owns
  // its handler list. Drop each projection before releasing its scratch.
  let scratch = Budget::scoped_temporaries(budget).map_err(|message| oom(budget,message))?;
  let mut control = Native{budget:&scratch,poll};
  let marker = crate::declare_policy::Marker{name:&row.name,rel:&row.rel,line:row.line,body:&row.body,args:&row.args,body_offset:row.body_offset,line_starts:&row.line_starts};
  let refs = crate::reactive_hooks_policy::discover_admitted(&[marker],&mut control)?;
  if !refs.is_empty() { return Ok(true); }
 }
 poll()?;
 budget.require()?;
 Ok(false)
}

#[cfg(test)]mod tests{
 use super::*;use crate::captured_raw_file::{File,RawPolicyViews};use std::cell::Cell;
 struct Pages{files:Vec<File>,stop:Cell<bool>,fail:Cell<bool>}
 impl RawPolicyPages for Pages{fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{if self.fail.get(){return Err(Failure::Operational(io::Error::from_raw_os_error(1450)))}if self.stop.get(){return Ok(false)}for file in &self.files{if !file.with_policy_views(visit)?{return Ok(false)}}Ok(true)}}
 fn fixture()->Pages{let root=std::env::current_dir().unwrap().join("handlers-native-recipe");let files=[("code/__defines/a.dm","#define A 1\n"),("code/a.dm","ACTION(a/b, mob/user)\n/proc/a(datum/act/A)\n    return\n"),("code/ordinary.dm","#define START ACT_ATTEMPT\nACTION(skipped, FIXED)\n"),("code/z.dm","ACTION(z)\n")].into_iter().map(|(rel,text)|File::capture(&root,&root.join(rel),text.to_owned().into()).unwrap()).collect();Pages{files,stop:Cell::new(false),fail:Cell::new(false)}}
 #[test]fn actual_pages_keep_partial_includes_and_all_action_vocabulary(){let pages=fixture();let recipe=select_from_pages(&pages,&HashMap::from([("code/z.dm".to_owned(),0)]),&["custom_try".to_owned()],&Budget::new(8*1024*1024).unwrap(),&||Ok(())).unwrap();assert_eq!(recipe.includes.iter().map(|i|i.relative.as_str()).collect::<Vec<_>>(),["code/__defines/a.dm","code/a.dm"]);assert_eq!(&recipe.try_calls[4..],["custom_try","act_z","act_a_b"]);assert!(!recipe.has_output_base);}
 #[test]fn successful_recipe_retains_only_transferred_payload_and_fixed_child_controls(){
  let root=std::env::current_dir().unwrap().join("handlers-recipe-retained");
  let file=File::capture(&root,&root.join("code/a.dm"),"READS_AS(/datum/probe, value)\nACTION(example)\n/proc/candidate(datum/act/A)\n    return\n".into()).unwrap();
  let pages=Pages{files:vec![file],stop:Cell::new(false),fail:Cell::new(false)};
  let budget=Budget::new(8*1024*1024).unwrap();let before=budget.used();
  let plan=select_with_demand_from_pages(&pages,&HashMap::new(),&[],&budget,&||Ok(())).unwrap();
  assert!(plan.requires_full);assert_eq!(plan.recipe.candidates[0].relative,"code/a.dm");
  assert_eq!(plan.recipe.try_calls.last().map(String::as_str),Some("act_example"));
  let fixed=std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>();
  assert_eq!(budget.used(),before+2*fixed+plan.recipe.retained_backing().unwrap());
 }
 #[test]
 fn handler_reuses_code_facts_on_marker_only_page_and_classifies_missing_page(){
  struct Mixed<'a>{root:&'a std::path::Path,budget:&'a Arc<Budget>,fact:Cell<Option<crate::sem_handlers_partial_recipe::HandlerCodeFacts>>,reuse:bool}
  impl RawPolicyPages for Mixed<'_>{
   fn handler_code_facts(&self)->Option<crate::sem_handlers_partial_recipe::HandlerCodeFacts>{self.fact.get()}
   fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
    for (index,relative) in ["code/a.dm","code/engine/b.dm"].into_iter().enumerate(){
     let text=if index==0{"/proc/candidate(datum/act/A)\n    return\nACTION(a)\n"}else{"/datum/probe/proc/draw()\n    act_try()\nACTION(b)\n"};
     let path=self.root.join(relative);
     let read=if self.reuse&&index==0{
      crate::captured_raw_file::with_original_policy_file_marker_prepared(self.root,&path,self.budget,|_|Ok(text.into()),&mut|rel,views|{
       self.fact.set(Some(crate::sem_handlers_partial_recipe::HandlerCodeFacts::Candidate));
       let result=visit(rel,views);self.fact.set(None);result
      })
     }else{
      crate::captured_raw_file::with_original_policy_file(self.root,&path,text.into(),0,self.budget,visit)
     };
     if !read?{return Ok(false)}
    }Ok(true)
   }
  }
  let root=std::env::current_dir().unwrap().join("handlers-code-reuse");
  let run=|reuse|{
   let budget=Budget::new(16*1024*1024).unwrap();
   select_with_demand_from_pages(&Mixed{root:&root,budget:&budget,fact:Cell::new(None),reuse},&HashMap::new(),&[],&budget,&||Ok(())).unwrap()
  };
  let expected=run(false);let actual=run(true);
  assert_eq!(actual.recipe,expected.recipe);
  assert_eq!(actual.requires_full,expected.requires_full);
  assert!(actual.recipe.has_output_base);
  assert_eq!(actual.recipe.candidates.len(),2);
 }
 #[test]fn stopped_and_operational_pages_never_become_available_empty_tu(){let pages=fixture();pages.stop.set(true);assert!(matches!(select_from_pages(&pages,&HashMap::new(),&[],&Budget::new(8*1024*1024).unwrap(),&||Ok(())),Err(Failure::Unsupported(_))));pages.stop.set(false);pages.fail.set(true);assert!(matches!(select_from_pages(&pages,&HashMap::new(),&[],&Budget::new(8*1024*1024).unwrap(),&||Ok(())),Err(Failure::Operational(e))if e.raw_os_error()==Some(1450)));pages.fail.set(false);assert!(!select_from_pages(&pages,&HashMap::new(),&[],&Budget::new(8*1024*1024).unwrap(),&||Ok(())).unwrap().candidates.is_empty());}
}

/// Exact old full-model demand: handlers OR READS_AS, independently of the
/// structural candidate set and the standard-output-base flag.
pub fn declared_model_demand(pages:&dyn RawPolicyPages,order:&HashMap<String,usize>,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<bool,Failure>{
 let rows=crate::reactive_raw_policy_pages::collect_marker_rows_funded(|visit|pages.for_each(visit),order,budget,crate::sem_handlers_partial_recipe::DECLARATION_MARKERS,true,true,true,poll)?;demand_from_rows(&rows,budget,poll)
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
 #[test]
 fn handler_demand_releases_each_marker_projection_before_the_next() {
  let mut source = "CAPABILITIES(/datum/probe, when(0))\n".repeat(799);
  source.push_str("CAPABILITIES(/datum/probe, when(PROC_REF(check)))\n");
  let root = std::env::current_dir().unwrap();
  let file = File::capture(&root,&root.join("code/handler-demand.dm"),source.into()).unwrap();
  let mut markers = Vec::new();
  let mut count = 0;
  file.with_policy_views(&mut |relative, views| {
   crate::captured_marker_rows::collect_file_admitted(relative,views.marker()?,&Budget::new(32*1024*1024).unwrap(),
    &["CAPABILITIES"],true,true,true,&mut markers,&mut count,&mut||Ok::<_,Failure>(()))?;
   Ok(true)
  }).unwrap();
  assert_eq!(count,800);
  let budget = Budget::new(256*1024).unwrap();
  let rows = crate::captured_marker_rows::Rows{markers,engine_sources:Vec::new()};
  assert!(demand_from_rows(&rows,&budget,&||Ok(())).unwrap());
  assert!(budget.used()<128*1024,"only fixed scratch bookkeeping survives each projection");
 }
}
