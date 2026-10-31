//! Borrowed original metadata adapter for the shared auto-tracking decision.
//! No variable/procedure/type index or source receipt is constructed here.
use crate::{auto_tracking_policy::{self as policy,Source,Variable,AutoSet},reactive_original_source::ReadSource,reactive_reads_native::Failure,key_policy_control::{self as kc,Control}};
use std::{collections::{BTreeSet,HashMap},borrow::Cow,io};
struct Native<'a,'s>{source:&'a ReadSource<'s>}
fn denial()->Failure{Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"auto-tracking metadata admission refused"))}
impl Native<'_,'_>{
 fn checked<T>(&self,pending:Result<T,String>)->Result<T,Failure>{
  if self.source.budget().denied(){return Err(denial())}self.source.checkpoint()?;self.source.require()?;pending.map_err(Failure::from)
 }
 fn checked_failure<T>(&self,pending:Result<T,Failure>)->Result<T,Failure>{
  // Preserve actual callback IO before translating the shared source budget's
  // legacy text boundary. A semantic refusal cannot hide a current stop.
  if matches!(&pending,Err(Failure::Operational(_))){return pending}
  if self.source.budget().denied(){return Err(denial())}
  self.source.checkpoint()?;self.source.require()?;pending
 }
}
impl Control for Native<'_,'_>{
 type Error=Failure;const CHECKED:bool=true;
 fn checkpoint(&mut self)->Result<(),Failure>{self.source.checkpoint()?;self.checked(self.source.require())}
 fn reserve(&mut self,n:usize)->Result<(),Failure>{self.source.reserve(Some(n)).map_err(|_|denial())}
 fn overflow(&mut self)->Failure{self.source.budget().deny();denial()}
 fn allocation_failed(&mut self)->Failure{self.source.budget().deny();denial()}
}
impl Source for Native<'_,'_>{
 fn variable(&mut self,owner:&str,var:&str)->Result<Option<Variable>,Failure>{
  let Some(v)=self.checked(self.source.variable(owner,var))?else{return Ok(None)};
  let is_list=v.declared=="/list"||v.declared.starts_with("/list/");
  let file=match v.file{Some(Cow::Owned(file))=>file,Some(Cow::Borrowed(file))=>kc::own(self,file)?,None=>String::new()};
  Ok(Some(Variable{file,is_static:v.is_static,is_const:v.is_const,is_list}))
 }
 fn subtype(&mut self,child:&str,parent:&str)->Result<bool,Failure>{self.checked(self.source.is_subtype(child,parent))}
 fn var_owner(&mut self,owner:&str,var:&str)->Result<Option<String>,Failure>{
  self.checked_failure(self.source.variable_declaring_owner(owner,var))?.map(|name|kc::own(self,name)).transpose()
 }
}
pub(crate) fn decide(source:&ReadSource<'_>,defs:&HashMap<String,Vec<String>>,candidates:&BTreeSet<(String,String)>,exclude:&[String])->Result<AutoSet,Failure>{
 policy::decide(&mut Native{source},defs,candidates,exclude)
}

/// Borrow actual frozen dependency candidate rows; same native metadata/control.
pub(crate) fn decide_rows<'a>(source:&ReadSource<'_>,defs:&HashMap<String,Vec<String>>,candidates:impl IntoIterator<Item=(&'a str,&'a str)>,exclude:&[&[String]])->Result<AutoSet,Failure>{policy::decide_rows(&mut Native{source},defs,candidates,exclude)}

struct Reactions<'a,'s,'f>{base:Native<'a,'s>,facts:&'f crate::reactive_policy_facts_native::PolicyFacts}
impl Control for Reactions<'_,'_,'_>{type Error=Failure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Failure>{self.base.checkpoint()}fn reserve(&mut self,n:usize)->Result<(),Failure>{self.base.reserve(n)}fn overflow(&mut self)->Failure{self.base.overflow()}fn allocation_failed(&mut self)->Failure{self.base.allocation_failed()}}
impl Source for Reactions<'_,'_,'_>{fn variable(&mut self,o:&str,v:&str)->Result<Option<Variable>,Failure>{self.base.variable(o,v)}fn subtype(&mut self,a:&str,b:&str)->Result<bool,Failure>{self.base.subtype(a,b)}fn var_owner(&mut self,o:&str,v:&str)->Result<Option<String>,Failure>{self.base.var_owner(o,v)}}
impl policy::ReactiveSource for Reactions<'_,'_,'_>{fn declared_reactive(&mut self,o:&str,v:&str)->Result<bool,Failure>{self.base.checked_failure(self.facts.auto_declared_reactive(self.base.source,o,v))}}
struct Written<'a,'s,'f>{base:Reactions<'a,'s,'f>,globals:&'f dyn crate::captured_reactive_reads::GlobalProvider}
impl Control for Written<'_,'_,'_>{type Error=Failure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Failure>{self.base.checkpoint()}fn reserve(&mut self,n:usize)->Result<(),Failure>{self.base.reserve(n)}fn overflow(&mut self)->Failure{self.base.overflow()}fn allocation_failed(&mut self)->Failure{self.base.allocation_failed()}}
impl Source for Written<'_,'_,'_>{fn variable(&mut self,o:&str,v:&str)->Result<Option<Variable>,Failure>{self.base.variable(o,v)}fn subtype(&mut self,a:&str,b:&str)->Result<bool,Failure>{self.base.subtype(a,b)}fn var_owner(&mut self,o:&str,v:&str)->Result<Option<String>,Failure>{self.base.var_owner(o,v)}}
impl policy::ReactiveSource for Written<'_,'_,'_>{fn declared_reactive(&mut self,o:&str,v:&str)->Result<bool,Failure>{policy::ReactiveSource::declared_reactive(&mut self.base,o,v)}}
impl policy::CandidateSource for Written<'_,'_,'_>{
 fn outside_written_on(&mut self,o:&str,v:&str)->Result<bool,Failure>{
  let source=self.base.base.source;
  crate::captured_reactive_reads::with_global_question(self.globals,source.inputs(),&||source.checkpoint(),&mut|result|{
   result.outside_setters().is_written_on_checked(o,v,|o,v|Native{source}.var_owner(o,v),|a,b|Native{source}.subtype(a,b))
  })
 }
}
pub(crate) fn named_candidate(source:&ReadSource<'_>,facts:&crate::reactive_policy_facts_native::PolicyFacts,owner:&str,var:&str)->Result<bool,Failure>{policy::named_candidate(&mut Reactions{base:Native{source},facts},owner,var)}
pub(crate) fn candidate(source:&ReadSource<'_>,facts:&crate::reactive_policy_facts_native::PolicyFacts,globals:&dyn crate::captured_reactive_reads::GlobalProvider,calls:&BTreeSet<String>,owner:&str,var:&str)->Result<bool,Failure>{
 policy::candidate(&mut Written{base:Reactions{base:Native{source},facts},globals},calls,owner,var)
}

pub(crate) fn setter_defs(source:&ReadSource<'_>)->Result<HashMap<String,Vec<String>>,Failure>{
 let mut out:HashMap<String,Vec<String>>=HashMap::new();
 let result=source.visit_setter_definitions(|name,owner|{
  let mut control=Native{source};control.checkpoint()?;
  if !out.contains_key(name){
   // Same conservative hash entry accounting as other shared key policies;
   // admit growth and the new key before entering the allocator.
   kc::reserve(&mut control,||Some(256))?;
   out.try_reserve(1).map_err(|_|control.allocation_failed())?;
   let name=kc::own(&mut control,name)?;out.insert(name,Vec::new());
  }
  let owner=kc::own(&mut control,owner)?;
  let rows=out.get_mut(name).expect("admitted name entry");kc::row(&mut control,rows)?;rows.push(owner);Ok(())
 });
 Native{source}.checked_failure(result)?;Ok(out)
}
pub(crate) fn set_calls(source:&ReadSource<'_>)->Result<BTreeSet<String>,Failure>{
 let mut out=BTreeSet::new();
 let result=source.visit_setter_call_files(|relative,text,code|{
  let mut control=Native{source};
  let rows=crate::auto_setter_calls_policy::collect_file(&mut control,relative,text,||code)?;
  for name in rows{control.checkpoint()?;if !out.contains(&name){kc::reserve(&mut control,||Some(256))?;out.insert(name);}}
  Ok(())
 });Native{source}.checked_failure(result)?;Ok(out)
}

/// Completed unique auto-inference data for ONE current aggregate operation.
/// The source/facts/provider stay borrowed from its factory; no AST, copied
/// semantic model, replacement query cache or default-empty provider is kept.
pub(crate) struct NativeCandidates<'a,'s>{
 source:&'a ReadSource<'s>,facts:&'a crate::reactive_policy_facts_native::PolicyFacts,
 globals:&'a dyn crate::captured_reactive_reads::GlobalProvider,
 calls:BTreeSet<String>,called:BTreeSet<(String,String)>,
}
fn typed_calls<'a>(source:&ReadSource<'_>,slot:&'a mut Option<crate::auto_typed_set_calls_native::TypedSetterCalls>)->Result<&'a crate::auto_typed_set_calls_native::TypedSetterCalls,Failure>{
 if slot.is_none(){*slot=Some(crate::auto_typed_set_calls_native::collect(source)?);}
 Ok(slot.as_ref().expect("successful original typed-call result"))
}
impl<'a,'s> NativeCandidates<'a,'s>{
 pub(crate) fn capture(source:&'a ReadSource<'s>,facts:&'a crate::reactive_policy_facts_native::PolicyFacts,globals:&'a dyn crate::captured_reactive_reads::GlobalProvider)->Result<Self,Failure>{
  let defs=setter_defs(source)?;let calls=set_calls(source)?;let mut typed=None;let mut called=BTreeSet::new();
  let result=source.visit_own_declared_variables(|owner,name|{
   let mut control=Native{source};
   if policy::called_here(&mut control,&defs,||typed_calls(source,&mut typed),&calls,owner,name)?
      &&candidate(source,facts,globals,&calls,owner,name)?{
    kc::reserve(&mut control,||Some(256))?;let owner=kc::own(&mut control,owner)?;let name=kc::own(&mut control,name)?;called.insert((owner,name));
   }
   Ok(())
  });Native{source}.checked_failure(result)?;
  // Typed receivers and setter definitions are temporary unique producer work;
  // they are dropped here rather than copied into the completed candidate set.
  Ok(Self{source,facts,globals,calls,called})
 }
 pub(crate) fn candidate(&self,owner:&str,name:&str)->Result<bool,Failure>{candidate(self.source,self.facts,self.globals,&self.calls,owner,name)}
 pub(crate) fn named_candidate(&self,owner:&str,name:&str)->Result<bool,Failure>{named_candidate(self.source,self.facts,owner,name)}
 pub(crate) fn called_candidates(&self)->&BTreeSet<(String,String)>{&self.called}
}
