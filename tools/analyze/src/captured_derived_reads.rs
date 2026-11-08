//! Whole six-rule derived-read DATA fold over SAME original pages and native Globals.
//! No legacy Tree/Model, body cache, parser, report seal or producer installation.
use crate::{captured_generator_budget::Budget,captured_reactive_reads::{Failure,GlobalResult},reactive_original_source::ReadSource,reactive_global_source::Source,key_policy_control::{self as kc,Control},captured_allow_annotations::Operation,derived_schema_policy::{self as schema,Schema,Table as SchemaTable},derived_reads_judge::{self as judge,Finding,Facts,Table},derived_entry_policy::Entry,reactive_reaction_policy::{self as reaction,Procedure,Membership,Lines,OwnedProcedureKey},tree::SourceFile,lint::{Site,AllowUse}};
use std::{collections::{BTreeMap,BTreeSet},cell::RefCell,io,sync::Arc};
fn oom(b:&Budget,message:impl Into<String>)->Failure{b.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message.into()))}
fn check(b:&Budget,poll:&dyn Fn()->io::Result<()>)->Result<(),Failure>{b.require().map_err(|m|oom(b,m))?;poll()?;b.require().map_err(|m|oom(b,m))}
fn finish<T>(pending:Result<T,Failure>,b:&Budget,poll:&dyn Fn()->io::Result<()>)->Result<T,Failure>{if matches!(&pending,Err(Failure::Operational(_))){return pending}check(b,poll)?;pending}
#[derive(Default)]pub struct DerivedReadData{sites:Vec<Site>,source_text:Vec<String>,allows:Vec<AllowUse>,digests:BTreeMap<String,[u8;20]>,stale:bool}
impl DerivedReadData{
 pub fn metadata(&self)->&'static crate::lint::Meta{metadata()}pub fn sites(&self)->&[Site]{&self.sites}pub fn source_text(&self)->&[String]{&self.source_text}pub fn allow_used(&self)->&[AllowUse]{&self.allows}pub fn allow_source_digest(&self,rel:&str)->Option<&[u8;20]>{self.digests.get(rel)}pub fn notes(&self)->&[String]{&[]}
 pub fn generated_is_stale(&self)->bool{self.stale}pub fn post_judge_message(&self)->Option<&'static str>{self.stale.then_some("derived_reads: code/_generated/reads.dm is stale; run `analyze gen derived_reads` and commit it\n")}
 pub fn serialize_data<S:serde::Serializer>(&self,serializer:S)->Result<S::Ok,S::Error>{use serde::ser::SerializeTuple;let mut out=serializer.serialize_tuple(5)?;out.serialize_element(&self.sites)?;out.serialize_element(&self.source_text)?;out.serialize_element(&self.allows)?;out.serialize_element(&self.digests)?;out.serialize_element(&self.stale)?;out.end()}
 pub fn retained_charge(&self)->Option<usize>{let mut n=std::mem::size_of::<Self>().checked_add(self.sites.capacity().checked_mul(std::mem::size_of::<Site>())?)?.checked_add(self.source_text.capacity().checked_mul(std::mem::size_of::<String>())?)?.checked_add(self.allows.capacity().checked_mul(std::mem::size_of::<AllowUse>())?)?;for s in &self.sites{for w in [&s.rule,&s.rel,&s.msg,&s.key,&s.ident]{n=n.checked_add(w.capacity())?}}for t in &self.source_text{n=n.checked_add(t.capacity())?}for a in &self.allows{for t in [&a.rel,&a.name,&a.code]{n=n.checked_add(t.capacity())?}}for p in self.digests.keys(){n=n.checked_add(2048)?.checked_add(p.capacity())?}Some(n)}
}
pub fn metadata()->&'static crate::lint::Meta{&crate::derived_reads_metadata::META}
#[derive(Default)]pub(crate) struct Index{schema:Schema,entries:BTreeMap<String,Vec<Entry>>,entry_order:Vec<String>,set_calls:BTreeSet<String>}
fn strip(owner:&str)->&str{owner.strip_prefix('/').unwrap_or(owner)}
fn merge_one<C:Control>(into:&mut SchemaTable,mut owner:String,names:BTreeSet<String>,c:&mut C,transfer:bool)->Result<(),C::Error>{
 if owner.starts_with('/'){owner.remove(0);}
 if let Some(set)=into.get_mut(&owner){
  for name in names{c.checkpoint()?;if !set.contains(&name){
   kc::reserve(c,||512usize.checked_add(if transfer{name.capacity()}else{0}))?;
   set.insert(name);
  }}
 }else{
  kc::reserve(c,||if transfer{
   names.len().checked_mul(512)?.checked_add(2048)?.checked_add(owner.capacity())?
    .checked_add(names.iter().try_fold(0usize,|bytes,name|bytes.checked_add(name.capacity()))?)
  }else{Some(2048)})?;
  into.insert(owner,names);
 }Ok(())
}
fn merge<C:Control>(into:&mut Schema,from:Schema,c:&mut C,transfer:bool)->Result<(),C::Error>{
 for(owner,names)in from.vars{merge_one(&mut into.vars,owner,names,c,transfer)?}
 for(owner,names)in from.typed{merge_one(&mut into.typed,owner,names,c,transfer)?}
 for(owner,names)in from.tracked{merge_one(&mut into.tracked,owner,names,c,transfer)?}
 for(owner,names)in from.relations{merge_one(&mut into.relations,owner,names,c,transfer)?}
 for row in from.published{
  if transfer{kc::reserve(c,||row.0.capacity().checked_add(row.1.capacity())?.checked_add(row.2.capacity()))?;}
  kc::row(c,&mut into.published)?;into.published.push(row);
 }Ok(())
}
fn has(table:&SchemaTable,owner:&str,name:&str)->bool{let mut yes=false;schema::chain(owner,|_,a|yes|=table.get(a).is_some_and(|v|v.contains(name)));yes}
fn visit_entries(index:&Index,owner:&str,mut visit:impl FnMut(&Entry)){schema::chain(owner,|_,a|{if let Some(entries)=index.entries.get(a){for e in entries{visit(e)}}})}
struct Known<'a>{index:&'a Index,owner:&'a str}impl Membership for Known<'_>{type Error=Failure;fn contains(&self,name:&str)->Result<bool,Failure>{Ok(has(&self.index.schema.vars,self.owner,name))}}
struct Judge<'a>{index:&'a Index,writes:&'a dyn WriteKnowledge,file:&'a SourceFile,data:&'a RefCell<DerivedReadData>,budget:&'a Budget,poll:&'a dyn Fn()->io::Result<()>}
impl Facts for Judge<'_>{
 type Error=Failure;type Known<'a>=Known<'a> where Self:'a;
 fn known<'a>(&'a self,owner:&'a str)->Result<Known<'a>,Failure>{check(self.budget,self.poll)?;Ok(Known{index:self.index,owner})}
 fn has(&self,t:Table,owner:&str,name:&str)->Result<bool,Failure>{check(self.budget,self.poll)?;Ok(match t{Table::Tracked=>has(&self.index.schema.tracked,owner,name),Table::Relation=>has(&self.index.schema.relations,owner,name),Table::Object=>has(&self.index.schema.typed,owner,name),Table::Derived=>{let mut yes=false;visit_entries(self.index,owner,|e|yes|=e.kind=="derive"&&e.name.as_deref().is_some_and(|v|!v.is_empty()&&v==name));yes}})}
 fn exact(&self,owner:&str)->Result<bool,Failure>{let mut yes=false;schema::chain(owner,|_,a|yes|=self.index.entries.get(a).is_some_and(|es|!es.is_empty()));Ok(yes)}
 fn declared_value(&self,owner:&str,value:&str)->Result<bool,Failure>{self.has(Table::Derived,owner,value)}
 fn declared_read(&self,owner:&str,kind:&str,value:Option<&str>,name:&str)->Result<bool,Failure>{let mut yes=false;visit_entries(self.index,owner,|e|yes|=e.kind==kind&&value.is_none_or(|v|e.name.as_deref()==Some(v))&&e.local.contains(name));Ok(yes)}
 fn published(&self,owner:&str,name:&str)->Result<bool,Failure>{let mut yes=false;schema::chain(owner,|_,a|{let mut last=None;for(t,v,k)in &self.index.schema.published{if strip(t)==a&&v==name{last=Some(k.as_str())}}yes|=last.is_some_and(|k|!k.is_empty());});Ok(yes)}
 fn never_written(&self,owner:&str,name:&str)->Result<bool,Failure>{self.writes.never_written(self.index,owner,name)}
 fn allowed(&self,rel:&str,line:usize)->Result<bool,Failure>{if rel!=self.file.rel{return Err("derived ALLOW loan differs from current raw procedure file".into())}let mut c=Operation{budget:self.budget,poll:self.poll};let Some(kept)=crate::allow::kept_using(self.file,line,"derived_reads",&mut c)?else{return Ok(false)};let code=kept.code.unwrap_or_default();let mut data=self.data.borrow_mut();if !data.allows.iter().any(|a|a.rel==rel&&a.line as usize==kept.line&&a.name=="derived_reads"&&a.code==code){kc::row(&mut c,&mut data.allows)?;self.budget.charge(code.capacity()).map_err(|m|oom(self.budget,m))?;data.allows.push(AllowUse{rel:kc::own(&mut c,rel)?,line:u32::try_from(kept.line).map_err(|_|oom(self.budget,"derived ALLOW line overflow"))?,name:kc::own(&mut c,"derived_reads")?,code});}if !data.digests.contains_key(rel){kc::reserve(&mut c,||Some(2048))?;data.digests.insert(kc::own(&mut c,rel)?,crate::captured_raw_file::source_allow_digest(self.file));}Ok(true)}
}
fn procedures<C:Control>(file:&SourceFile,c:&mut C,mut visit:impl FnMut(usize,Procedure<'_>,&mut C)->Result<(),C::Error>)->Result<(),C::Error>{if file.rel==reaction::GENERATED_REL{return Ok(())}let code=file.code();for(number,line)in code.numbered(){c.checkpoint()?;let Some(header)=reaction::header_admitted(line,|groups|kc::reserve(c,||groups.checked_mul(4)?.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(std::mem::size_of::<crate::pat::Caps<'_>>()+64)))?else{continue};let owner=header.owner.trim_end_matches('/');let owner=if owner.is_empty(){"/"}else{owner};let first=number.checked_add(1).ok_or_else(||c.overflow())?;visit(number,Procedure{owner,name:header.name,relative:&file.rel,args:header.args,lines:Lines::IndentedCode{view:code,first}},c)?}Ok(())}
trait DerivedPages{
 fn budget(&self)->&Arc<Budget>;
 fn require(&self)->Result<(),Failure>;
 fn for_each(&self,visit:&mut dyn FnMut(&str,crate::captured_raw_file::RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>;
}
struct SemanticPages<'a,'s>(&'a ReadSource<'s>);
impl DerivedPages for SemanticPages<'_,'_>{
 fn budget(&self)->&Arc<Budget>{self.0.budget()}
 fn require(&self)->Result<(),Failure>{self.0.require().map_err(|message|oom(self.0.budget(),message))}
 fn for_each(&self,visit:&mut dyn FnMut(&str,crate::captured_raw_file::RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{self.0.with_policy_files(visit)}
}
struct RawPages<'a>{pages:&'a dyn crate::reactive_raw_policy_pages::RawPolicyPages,budget:&'a Arc<Budget>,poll:&'a dyn Fn()->io::Result<()>}
impl DerivedPages for RawPages<'_>{
 fn budget(&self)->&Arc<Budget>{self.budget}
 fn require(&self)->Result<(),Failure>{check(self.budget,self.poll)}
 fn for_each(&self,visit:&mut dyn FnMut(&str,crate::captured_raw_file::RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{check(self.budget,self.poll)?;let result=self.pages.for_each(visit);finish(result,self.budget,self.poll)}
}
impl crate::reactive_raw_lexical_source::Source for RawPages<'_>{
 fn budget(&self)->&Arc<Budget>{self.budget}
 fn checkpoint(&self)->io::Result<()>{(self.poll)()}
 fn require(&self)->Result<(),Failure>{DerivedPages::require(self)}
 fn reserve(&self,n:Option<usize>)->Result<(),Failure>{let n=n.ok_or_else(||oom(self.budget,"raw-derived lexical size overflow"))?;self.budget.charge(n).map_err(|m|oom(self.budget,m))}
 fn with_reaction_code(&self,hint:&str,visit:&mut dyn FnMut(&str,&crate::tree::View)->Result<bool,Failure>)->Result<(),Failure>{
  let all=DerivedPages::for_each(self,&mut|relative,views|{if !crate::captured_raw_file::is_code_dm(relative){return Err("raw-derived lexical source escaped actual CODE pages".into())}if !views.raw()?.contains(hint){return Ok(true)}visit(relative,views.code()?)})?;
  // A reaction query may deliberately stop at its first actual match. That is
  // not an EOF/completion receipt; the outer host still owns full traversal.
  let _=all;DerivedPages::require(self)
 }
}
trait WriteKnowledge{
 fn never_written(&self,index:&Index,owner:&str,name:&str)->Result<bool,Failure>;
 fn collects_set_calls(&self)->bool;
}
struct CompleteWrites<'a,'s>{source:&'a ReadSource<'s>,globals:&'a GlobalResult,poll:&'a dyn Fn()->io::Result<()>}
impl WriteKnowledge for CompleteWrites<'_,'_>{
 fn never_written(&self,index:&Index,owner:&str,name:&str)->Result<bool,Failure>{let budget=self.source.budget();check(budget,self.poll)?;if Source::variable(self.source,owner,name)?.is_some_and(|v|v.is_static||v.is_const){return Ok(true)}let mut c=Operation{budget,poll:self.poll};let list_name=kc::format(&mut c,format_args!("{}[]",name))?;Ok(!self.globals.outside_written_on(self.source,owner,name)?&&!index.set_calls.contains(name)&&!index.set_calls.contains(&list_name))}
 fn collects_set_calls(&self)->bool{true}
}
struct NoSemanticWrites;
impl WriteKnowledge for NoSemanticWrites{fn never_written(&self,_:&Index,_:&str,_:&str)->Result<bool,Failure>{Ok(false)}fn collects_set_calls(&self)->bool{false}}
fn files(source:&dyn DerivedPages,mut visit:impl FnMut(&SourceFile)->Result<bool,Failure>)->Result<(),Failure>{let all=source.for_each(&mut|relative,views|{if !relative.starts_with("code/")||!relative.ends_with(".dm"){return Err("derived source escaped hidden-inclusive CODE coverage".into())}visit(views.source_file()?)})?;if !all{return Err("derived full raw traversal stopped before CODE EOF".into())}source.require()?;Ok(())}
fn find_file<T>(source:&dyn DerivedPages,relative:&str,run:impl FnOnce(&SourceFile)->Result<T,Failure>)->Result<T,Failure>{let mut run=Some(run);let mut out=None;source.for_each(&mut|rel,views|{if rel!=relative{return Ok(true)}if out.is_some(){return Err("derived original raw file repeated".into())}out=Some(run.take().unwrap()(views.source_file()?)?);Ok(false)})?;out.ok_or_else(||Failure::Unsupported("derived finding original raw file absent".into()))}
/// Whole DATA only. Public registry/complete ALLOW roles remain unissued until
/// the actual host admits this consumer and its complete original acquisition.
fn entry_backing(entry:&Entry)->Option<usize>{
 let mut bytes=entry.rel.capacity().checked_add(entry.name.as_ref().map_or(0,String::capacity))?
  .checked_add(entry.local.len().checked_mul(512)?)?
  .checked_add(entry.remote.capacity().checked_mul(std::mem::size_of::<(Option<String>,String)>())?)?
  .checked_add(entry.hops.capacity().checked_mul(std::mem::size_of::<String>())?)?;
 for name in &entry.local{bytes=bytes.checked_add(name.capacity())?;}
 for (owner,name) in &entry.remote{bytes=bytes.checked_add(owner.as_ref().map_or(0,String::capacity))?.checked_add(name.capacity())?;}
 for hop in &entry.hops{bytes=bytes.checked_add(hop.capacity())?;}
 Some(bytes)
}

fn index_file(index:&mut Index,file:&SourceFile,scratch:&mut Operation<'_>,retained:&mut Operation<'_>,transfer:bool)->Result<(),Failure>{
 let mut own=if file.rel==reaction::GENERATED_REL{Schema::default()}else{schema::file(file.code(),scratch)?};
 procedures(file,scratch,|header,proc,scratch|{
  schema::relations(&mut own,Procedure{owner:proc.owner,name:proc.name,relative:proc.relative,args:proc.args,lines:proc.lines},scratch)?;
  if proc.name=="derived"&&proc.owner!="/"{
   let owner=proc.owner;
   let key=strip(owner);
   if !index.entries.contains_key(key){
    kc::reserve(retained,||Some(2048))?;
    index.entries.insert(kc::own(retained,key)?,Vec::new());
    kc::row(retained,&mut index.entry_order)?;
    index.entry_order.push(kc::own(retained,owner)?);
   }
   let rows=crate::derived_entry_policy::entries(proc,header,scratch)?;
   let target=index.entries.get_mut(key).unwrap();
   for entry in rows{
    if transfer{kc::reserve(retained,||entry_backing(&entry))?;}
    kc::row(retained,target)?;
    target.push(entry);
   }
  }Ok(())
 })?;
 merge(&mut index.schema,own,retained,transfer)
}

pub(crate) fn prepare(source:&ReadSource<'_>,poll:&dyn Fn()->io::Result<()>)->Result<Index,Failure>{
 let b=source.budget();check(b,poll)?;let mut scratch=Operation{budget:b,poll};let mut retained=Operation{budget:b,poll};let mut index=Index::default();
 files(&SemanticPages(source),|file|{index_file(&mut index,file,&mut scratch,&mut retained,false)?;Ok(true)})?;Ok(index)
}
/// Body-free selected raw DATA, not a source/model/preparation witness. There
/// is no public constructor, Clone, caller-hash binding or unchecked consume.
/// The index drops before its actual original operation's resource owner.
pub struct UnsealedDerivedIndexData{index:Index,funding:Arc<Budget>}
impl UnsealedDerivedIndexData{
 /// DATA-only consumption. The actual host must first bind its private raw
 /// recorder/current scope; this helper never issues a source/result witness.
 pub(crate) fn collect_held(self,source:&ReadSource<'_>,all_source:&ReadSource<'_>,globals:&GlobalResult,test_types:&BTreeSet<String>,poll:&dyn Fn()->io::Result<()>)->Result<DerivedReadData,Failure>{let Self{index,funding}=self;let pending=collect(source,all_source,index,globals,test_types,poll);drop(funding);pending}

 /// Conservative live backing bound only; not RSS or source authority.
 pub fn retained_charge(&self)->Option<usize>{
  let i=&self.index;let mut n=std::mem::size_of::<Self>().checked_add(std::mem::size_of::<Budget>())?.checked_add(2*std::mem::size_of::<usize>())?;
  for table in [&i.schema.vars,&i.schema.typed,&i.schema.tracked,&i.schema.relations]{n=n.checked_add(table.len().checked_add(1)?.checked_mul(2048)?)?;for(owner,names)in table{n=n.checked_add(owner.capacity())?.checked_add(names.len().checked_add(1)?.checked_mul(512)?)?;for name in names{n=n.checked_add(name.capacity())?}}}
  n=n.checked_add(i.schema.published.capacity().checked_mul(std::mem::size_of::<(String,String,String)>())?)?;for(a,b,c)in &i.schema.published{n=n.checked_add(a.capacity())?.checked_add(b.capacity())?.checked_add(c.capacity())?}
  n=n.checked_add(i.entries.len().checked_add(1)?.checked_mul(2048)?)?.checked_add(i.entry_order.capacity().checked_mul(std::mem::size_of::<String>())?)?;for owner in &i.entry_order{n=n.checked_add(owner.capacity())?}
  for(owner,entries)in &i.entries{n=n.checked_add(owner.capacity())?.checked_add(entries.capacity().checked_mul(std::mem::size_of::<Entry>())?)?;for e in entries{n=n.checked_add(e.rel.capacity())?.checked_add(e.name.as_ref().map_or(0,String::capacity))?.checked_add(e.local.len().checked_add(1)?.checked_mul(512)?)?.checked_add(e.remote.capacity().checked_mul(std::mem::size_of::<(Option<String>,String)>())?)?.checked_add(e.hops.capacity().checked_mul(std::mem::size_of::<String>())?)?;for v in &e.local{n=n.checked_add(v.capacity())?}for(t,v)in &e.remote{n=n.checked_add(t.as_ref().map_or(0,String::capacity))?.checked_add(v.capacity())?}for h in &e.hops{n=n.checked_add(h.capacity())?}}}
  n=n.checked_add(i.set_calls.len().checked_add(1)?.checked_mul(512)?)?;for c in &i.set_calls{n=n.checked_add(c.capacity())?}Some(n)
 }
}
struct PreflightPhase{funding:Arc<Budget>,complete:bool}impl Drop for PreflightPhase{fn drop(&mut self){if !self.complete{self.funding.keep_failed_scratch()}}}
/// SAME selected raw index builder, before any semantic frontend, PolicyInputs,
/// Globals or BODY. The host must later bind its genuine raw recorder/current
/// scope before any use with a semantic subject; DATA equality grants nothing.
pub fn prepare_selected_pages(pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<UnsealedDerivedIndexData,Failure>{
 check(budget,poll)?;let funding=Budget::scoped_temporaries(budget).map_err(|m|oom(budget,m))?;let mut phase=PreflightPhase{funding:Arc::clone(&funding),complete:false};
 let pending=(||{
  let mut index=Index::default();
  let mut retained=Operation{budget:&funding,poll};
  let all=pages.for_each(&mut|relative,views|{
   check(&funding,poll)?;
   if !relative.starts_with("code/")||!relative.ends_with(".dm"){return Err("derived preflight escaped its actual selected CODE phase".into())}
   // The recorder already issued a scratch owner for this exact raw view.
   // Source-neutral test/fixture lenders can lack it. Their local fallback
   // is also a child of the same operation, never of the retained index.
   let actual=views.allocation_budget(budget);
   let fallback=if std::ptr::eq(actual,budget.as_ref()){
    Some(Budget::scoped_temporaries(budget).map_err(|m|oom(budget,m))?)
   }else{None};
   let local=fallback.as_deref().unwrap_or(actual);
   let mut guard=PreflightPhase{funding:fallback.as_ref().map_or_else(||Arc::clone(&funding),Arc::clone),complete:fallback.is_none()};
   let mut scratch=Operation{budget:local,poll};
   index_file(&mut index,views.source_file()?,&mut scratch,&mut retained,true)?;
   guard.complete=true;
   Ok(true)
  })?;
  if !all{return Err("derived preflight stopped before actual selected raw EOF".into())}
  check(&funding,poll)?;Ok(index)
 })();
 let pending=finish(pending,&funding,poll);match pending{Ok(index)=>{let data=UnsealedDerivedIndexData{index,funding};phase.complete=true;drop(phase);Ok(data)},Err(actual)=>{drop(phase);drop(funding);Err(actual)}}
}
pub(crate) fn collect(source:&ReadSource<'_>,all_source:&ReadSource<'_>,mut index:Index,globals:&GlobalResult,test_types:&BTreeSet<String>,poll:&dyn Fn()->io::Result<()>)->Result<DerivedReadData,Failure>{
 let b=source.budget();check(b,poll)?;if !globals.matches(source.inputs())||!globals.matches(all_source.inputs()){return Err("derived Globals belong to another original source".into())}
 let writes=CompleteWrites{source,globals,poll};let lexical=crate::reactive_raw_lexical_source::SemanticLoan::borrow(source);
 collect_pages(&SemanticPages(source),&SemanticPages(all_source),&lexical,index,&writes,test_types,poll)
}
fn collect_pages(source:&dyn DerivedPages,all_source:&dyn DerivedPages,lexical:&dyn crate::reactive_raw_lexical_source::Source,mut index:Index,writes:&dyn WriteKnowledge,test_types:&BTreeSet<String>,poll:&dyn Fn()->io::Result<()>)->Result<DerivedReadData,Failure>{
 let b=source.budget();let mut c=Operation{budget:b,poll};
 // Old Model is already built. Now genuine Globals/writes precede eager setter
 // names from ALL CODE, including files exempt from this lint's model.
 if writes.collects_set_calls(){files(all_source,|file|{for call in crate::auto_setter_calls_policy::collect_file(&mut c,&file.rel,file.text(),||file.code().text.as_str())?{if !index.set_calls.contains(&call){kc::reserve(&mut c,||Some(512))?;index.set_calls.insert(call);}}Ok(true)})?;}
 let data=RefCell::new(DerivedReadData::default());let mut findings=Vec::new();
 for exact in [false,true]{files(source,|file|{let facts=Judge{index:&index,writes,file,data:&data,budget:b,poll};procedures(file,&mut c,|header,proc,c|{let mut output=|finding|{kc::row(&mut Operation{budget:b,poll},&mut findings)?;findings.push(finding);Ok(())};if exact{judge::exact(&facts,proc,header,c,&mut output)}else{judge::reactive(&facts,proc,true,c,&mut output)}})?;Ok(true)})?;}
 for owner in &index.entry_order{for e in &index.entries[strip(owner)]{find_file(source,&e.rel,|file|{let facts=Judge{index:&index,writes,file,data:&data,budget:b,poll};judge::entry(&facts,owner,e,&mut c,&mut|finding|{kc::row(&mut Operation{budget:b,poll},&mut findings)?;findings.push(finding);Ok(())})})?;}}
 for r in crate::reactive_reaction_native::reaction_reads_raw(lexical)?{let OwnedProcedureKey::Raw{relative,header}=r.procedure else{return Err("native derived reaction lacks authentic raw coordinates".into())};find_file(source,&relative,|file|{let line=file.code().line(header);let Some(h)=reaction::header_admitted(line,|groups|kc::reserve(&mut c,||groups.checked_mul(4)?.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(std::mem::size_of::<crate::pat::Caps<'_>>()+64)))?else{return Err("derived reaction original header absent".into())};let proc=Procedure{owner:&r.owner,name:h.name,relative:&relative,args:h.args,lines:Lines::IndentedCode{view:file.code(),first:header.checked_add(1).ok_or_else(||oom(b,"derived reaction header overflow"))?}};let facts=Judge{index:&index,writes,file,data:&data,budget:b,poll};judge::reaction(&facts,proc,r.kind,&r.reads,&mut c,&mut|finding|{kc::row(&mut Operation{budget:b,poll},&mut findings)?;findings.push(finding);Ok(())})})?;}
 kc::sort_data(&mut findings,&mut|a,b|{c.checkpoint()?;Ok::<_,Failure>(judge::compare(a,b))})?;let mut data=data.into_inner();for f in findings{find_file(source,&f.rel,|file|{let line=u32::try_from(f.line).map_err(|_|oom(b,"derived finding line overflow"))?;kc::row(&mut c,&mut data.sites)?;data.sites.push(Site{rule:kc::own(&mut c,f.rule)?,rel:kc::own(&mut c,&f.rel)?,line,msg:String::new(),key:String::new(),ident:String::new()});kc::row(&mut c,&mut data.source_text)?;kc::reserve(&mut c,||file.raw().line(f.line).len().checked_mul(4)?.checked_add(128))?;data.source_text.push(crate::util::normalize_ws(file.raw().line(f.line)));Ok(())})?;}
 let want=crate::reactive_derived_generator_native::generate_raw(lexical,test_types)?;data.stale=true;files(all_source,|file|{if file.rel==reaction::GENERATED_REL{data.stale=file.text()!=want}Ok(true)})?;check(b,poll)?;Ok(data)
}

#[cfg(all(test,feature="legacy-sem"))]
#[path="captured_derived_reads_tests.rs"]mod tests;

/// Output/baseline DATA only. No read or source/model fallback occurs here.
impl crate::baseline::SiteText for DerivedReadData{fn site_text(&self,relative:&str,line:usize)->String{self.sites.iter().zip(&self.source_text).find(|(site,_)|site.rel==relative&&site.line as usize==line).map(|(_,text)|text.clone()).unwrap_or_default()}}

#[cfg(test)]mod treefree_preflight_controls{
 use super::*;use std::cell::Cell;
 struct Pages{file:crate::captured_raw_file::File,fail:Cell<bool>,stop:Cell<bool>,passes:Cell<usize>}
 impl crate::reactive_raw_policy_pages::RawPolicyPages for Pages{fn for_each(&self,visit:&mut dyn FnMut(&str,crate::captured_raw_file::RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{if self.fail.get(){return Err(Failure::Operational(io::Error::from_raw_os_error(1450)))}self.passes.set(self.passes.get()+1);let all=self.file.with_policy_views(visit)?;Ok(all&&!self.stop.get())}}
 fn pages()->Pages{let root=std::env::current_dir().unwrap().join("derived-treefree-preflight");let text="/datum/probe\n    var/value\n/datum/probe/derived()\n    return list(drawn_from(nameof(value)))\n";Pages{file:crate::captured_raw_file::File::capture(&root,&root.join("code/probe.dm"),text.into()).unwrap(),fail:Cell::new(false),stop:Cell::new(false),passes:Cell::new(0)}}
 #[test]fn treefree_preflight_uses_same_identifier_index_without_semantic_source_and_keeps_credit_live(){let pages=pages();let budget=Budget::new(8*1024*1024).unwrap();let before=budget.used();let data=prepare_selected_pages(&pages,&budget,&||Ok(())).unwrap();assert_eq!(pages.passes.get(),1);assert!(data.index.schema.vars["datum/probe"].contains("value"));assert_eq!(data.index.entry_order,["/datum/probe"]);assert_eq!(data.index.entries["datum/probe"][0].kind,"drawn");assert!(data.index.set_calls.is_empty(),"setter names belong after actual semantic preparation");assert!(data.retained_charge().unwrap()>std::mem::size_of::<UnsealedDerivedIndexData>());assert!(budget.used()>before);let fixed=std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>();let held=budget.used();let payload=data.funding.used().checked_sub(fixed).unwrap();assert!(payload>0);drop(data);assert_eq!(budget.used(),held-payload);assert_eq!(budget.used(),before+2*fixed,"existing Budget contract conservatively retains both child Arc/control grants");}
 #[test]
 fn many_actual_file_scopes_reuse_scratch_without_refunding_retained_schema(){
  struct Repeated<'a>{root:&'a std::path::Path,budget:&'a Arc<Budget>,text:dm_preprocess::SourceText}
  impl crate::reactive_raw_policy_pages::RawPolicyPages for Repeated<'_>{
   fn for_each(&self,visit:&mut dyn FnMut(&str,crate::captured_raw_file::RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
    for number in 0..64{
     let path=self.root.join(format!("code/file_{number}.dm"));
     if !crate::captured_raw_file::with_original_policy_file_prepared(self.root,&path,0,self.budget,|_|Ok(self.text.clone()),visit)?{return Ok(false)}
    }Ok(true)
   }
  }
  let root=std::env::current_dir().unwrap().join("derived-file-scratch");
  let mut text=String::from("/datum/probe\n    var/value\n/datum/probe/derived()\n    return list(drawn_from(nameof(value)))\n");
  text.push_str(&"    return null\n".repeat(60));
  let budget=Budget::new(1024*1024).unwrap();
  let source=Repeated{root:&root,budget:&budget,text:text.into()};
  let data=prepare_selected_pages(&source,&budget,&||Ok(())).unwrap();
  assert!(data.index.schema.vars["datum/probe"].contains("value"));
  let rows=&data.index.entries["datum/probe"];
  assert_eq!(rows.len(),64);
  assert_eq!(rows[0].rel,"code/file_0.dm");
  assert_eq!(rows[63].rel,"code/file_63.dm");
  assert!(rows.iter().all(|entry|entry.local.contains("value")));
  assert!(data.funding.used()>=rows.iter().map(|entry|entry_backing(entry).unwrap()).sum::<usize>());
  let fixed=std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>();
  drop(data);
  assert_eq!(budget.used(),66*fixed,"one root, one retained child and exactly one file child per page leave only fixed grants");
 }
 #[test]fn treefree_preflight_refuses_actual_io_early_stop_and_quota_then_recovers(){let pages=pages();let budget=Budget::new(8*1024*1024).unwrap();pages.fail.set(true);assert!(matches!(prepare_selected_pages(&pages,&budget,&||Ok(())),Err(Failure::Operational(ref error))if error.raw_os_error()==Some(1450)));assert_eq!(pages.passes.get(),0);pages.fail.set(false);pages.stop.set(true);assert!(matches!(prepare_selected_pages(&pages,&budget,&||Ok(())),Err(Failure::Unsupported(_))));pages.stop.set(false);let tiny=Budget::new(256).unwrap();assert!(matches!(prepare_selected_pages(&pages,&tiny,&||Ok(())),Err(Failure::Operational(ref error))if error.kind()==io::ErrorKind::OutOfMemory));let fresh=Budget::new(8*1024*1024).unwrap();let data=prepare_selected_pages(&pages,&fresh,&||Ok(())).unwrap();assert_eq!(data.index.entry_order.len(),1);}
}

/// Source-neutral raw-only DATA for the old semantic-unavailable branch. This
/// accepts no caller None, fake Globals, PolicyInputs or absence/completion
/// witness. The host must separately authenticate its real failed preparation
/// and selected/all-CODE EOF, and must never cache this as a current source.
pub fn derived_reads_data_without_semantic_from_preflight_pages(preflight:UnsealedDerivedIndexData,selected_pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,test_types:&BTreeSet<String>,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<DerivedReadData,Failure>{
 check(budget,poll)?;let phase=Budget::scoped_temporaries(budget).map_err(|m|oom(budget,m))?;let mut held=Some(preflight);
 let pending=(||{let selected=RawPages{pages:selected_pages,budget:&phase,poll};let all=RawPages{pages,budget:&phase,poll};let UnsealedDerivedIndexData{index,funding}=held.take().expect("single actual raw index");let pending=collect_pages(&selected,&all,&selected,index,&NoSemanticWrites,test_types,poll);drop(funding);pending})();
 let pending=finish(pending,&phase,poll);let pending=match pending{Ok(data)=>{let n=data.retained_charge().ok_or_else(||oom(budget,"raw-only Derived retention overflow"))?;match budget.charge(n){Ok(())=>Ok(data),Err(m)=>{drop(data);Err(oom(budget,m))}}},Err(e)=>Err(e)};
 drop(held);if pending.is_err(){phase.keep_failed_scratch()}drop(phase);finish(pending,budget,poll)
}

#[cfg(all(test,feature="legacy-sem"))]
#[path="captured_derived_unavailable_tests.rs"]mod unavailable_controls;
