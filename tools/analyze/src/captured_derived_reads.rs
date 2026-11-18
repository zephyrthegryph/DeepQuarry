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
type Names=Vec<(String,Vec<String>)>;
type Entries=Vec<(String,Vec<Entry>)>;
struct SealedSchema{vars:Names,typed:Names,tracked:Names,relations:Names,published:Vec<(String,String,String)>}
enum IndexSchema{Building(Schema),Sealed(SealedSchema)}
enum IndexEntries{Building(BTreeMap<String,Vec<Entry>>),Sealed(Entries)}
pub(crate) struct Index{schema:IndexSchema,entries:IndexEntries,entry_order:Vec<String>,set_calls:BTreeSet<String>}
impl Default for Index{
 fn default()->Self{Self{schema:IndexSchema::Building(Schema::default()),entries:IndexEntries::Building(BTreeMap::new()),entry_order:Vec::new(),set_calls:BTreeSet::new()}}
}
fn sorted_rows<'a,T>(rows:&'a[(String,T)],owner:&str)->Option<&'a T>{
 rows.binary_search_by(|(name,_)|name.as_str().cmp(owner)).ok().map(|n|&rows[n].1)
}
#[derive(Clone,Copy)]enum NameTable{Vars,Typed,Tracked,Relations}
impl Index{
 fn has(&self,table:NameTable,owner:&str,name:&str)->bool{
  let mut yes=false;
  schema::chain(owner,|_,owner|yes|=match &self.schema{
   IndexSchema::Building(s)=>match table{ NameTable::Vars=>&s.vars,NameTable::Typed=>&s.typed,NameTable::Tracked=>&s.tracked,NameTable::Relations=>&s.relations}.get(owner).is_some_and(|set|set.contains(name)),
   IndexSchema::Sealed(s)=>sorted_rows(match table{NameTable::Vars=>&s.vars,NameTable::Typed=>&s.typed,NameTable::Tracked=>&s.tracked,NameTable::Relations=>&s.relations},owner).is_some_and(|set|set.binary_search_by(|item|item.as_str().cmp(name)).is_ok()),
  });
  yes
 }
 fn entries(&self,owner:&str)->Option<&Vec<Entry>>{match &self.entries{IndexEntries::Building(rows)=>rows.get(owner),IndexEntries::Sealed(rows)=>sorted_rows(rows,owner)}}
 fn published(&self)->&[(String,String,String)]{match &self.schema{IndexSchema::Building(s)=>&s.published,IndexSchema::Sealed(s)=>&s.published}}
}
struct Seal<'a>{budget:&'a Budget,poll:&'a dyn Fn()->io::Result<()>,paid:usize}
impl Seal<'_>{
 fn rows<T>(&mut self,count:usize)->Result<Vec<T>,Failure>{
  check(self.budget,self.poll)?;
  let bytes=count.checked_mul(std::mem::size_of::<T>()).ok_or_else(||oom(self.budget,"sealed Derived row overflow"))?;
  let paid=self.paid.checked_add(bytes).ok_or_else(||oom(self.budget,"sealed Derived capacity overflow"))?;
  self.budget.charge(bytes).map_err(|m|oom(self.budget,m))?;
  let mut rows=Vec::new();
  rows.try_reserve_exact(count).map_err(|e|oom(self.budget,e.to_string()))?;
  if rows.capacity()!=count{return Err(oom(self.budget,"sealed Derived actual capacity differs"))}
  self.paid=paid;
  Ok(rows)
 }
 fn names(&mut self,table:SchemaTable)->Result<Names,Failure>{
  let mut result=self.rows(table.len())?;
  for (owner,names) in table{
   let mut rows=self.rows(names.len())?;
   for name in names{check(self.budget,self.poll)?;rows.push(name);}
   result.push((owner,rows));
  }
  Ok(result)
 }
 fn index(&mut self,index:Index)->Result<(Index,usize),Failure>{
  let Index{schema,entries,entry_order,set_calls}=index;
  let IndexSchema::Building(Schema{vars,typed,tracked,relations,published})=schema else{unreachable!("only the cold builder seals")};
  let IndexEntries::Building(entries)=entries else{unreachable!("only the cold builder seals")};
  debug_assert!(set_calls.is_empty());
  let schema=SealedSchema{vars:self.names(vars)?,typed:self.names(typed)?,tracked:self.names(tracked)?,relations:self.names(relations)?,published};
  let mut result=self.rows(entries.len())?;
  for row in entries{check(self.budget,self.poll)?;result.push(row);}
  let backing=sealed_index_backing(&schema,&result,&entry_order).ok_or_else(||oom(self.budget,"sealed Derived retained backing overflow"))?;
  let moved=backing.checked_sub(self.paid).ok_or_else(||oom(self.budget,"sealed Derived transferred backing mismatch"))?;
  self.budget.charge(moved).map_err(|m|oom(self.budget,m))?;
  Ok((Index{schema:IndexSchema::Sealed(schema),entries:IndexEntries::Sealed(result),entry_order,set_calls},backing))
 }
}
fn sealed_index_backing(schema:&SealedSchema,entries:&Entries,entry_order:&Vec<String>)->Option<usize>{
 let mut bytes=entry_order.capacity().checked_mul(std::mem::size_of::<String>())?;
 for owner in entry_order{bytes=bytes.checked_add(owner.capacity())?;}
 for table in [&schema.vars,&schema.typed,&schema.tracked,&schema.relations]{
  bytes=bytes.checked_add(table.capacity().checked_mul(std::mem::size_of::<(String,Vec<String>)>())?)?;
  for (owner,names) in table{
   bytes=bytes.checked_add(owner.capacity())?.checked_add(names.capacity().checked_mul(std::mem::size_of::<String>())?)?;
   for name in names{bytes=bytes.checked_add(name.capacity())?;}
  }
 }
 bytes=bytes.checked_add(schema.published.capacity().checked_mul(std::mem::size_of::<(String,String,String)>())?)?;
 for (owner,name,key) in &schema.published{bytes=bytes.checked_add(owner.capacity())?.checked_add(name.capacity())?.checked_add(key.capacity())?;}
 bytes=bytes.checked_add(entries.capacity().checked_mul(std::mem::size_of::<(String,Vec<Entry>)>())?)?;
 for (owner,rows) in entries{
  bytes=bytes.checked_add(owner.capacity())?.checked_add(rows.capacity().checked_mul(std::mem::size_of::<Entry>())?)?;
  for entry in rows{bytes=bytes.checked_add(entry_backing(entry)?)?;}
 }
 Some(bytes)
}
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
fn visit_entries(index:&Index,owner:&str,mut visit:impl FnMut(&Entry)){schema::chain(owner,|_,a|{if let Some(entries)=index.entries(a){for e in entries{visit(e)}}})}
struct Known<'a>{index:&'a Index,owner:&'a str}impl Membership for Known<'_>{type Error=Failure;fn contains(&self,name:&str)->Result<bool,Failure>{Ok(self.index.has(NameTable::Vars,self.owner,name))}}
struct Judge<'a>{index:&'a Index,writes:&'a dyn WriteKnowledge,file:&'a SourceFile,data:&'a RefCell<DerivedReadData>,budget:&'a Budget,poll:&'a dyn Fn()->io::Result<()>}
impl Facts for Judge<'_>{
 type Error=Failure;type Known<'a>=Known<'a> where Self:'a;
 fn known<'a>(&'a self,owner:&'a str)->Result<Known<'a>,Failure>{check(self.budget,self.poll)?;Ok(Known{index:self.index,owner})}
 fn has(&self,t:Table,owner:&str,name:&str)->Result<bool,Failure>{check(self.budget,self.poll)?;Ok(match t{Table::Tracked=>self.index.has(NameTable::Tracked,owner,name),Table::Relation=>self.index.has(NameTable::Relations,owner,name),Table::Object=>self.index.has(NameTable::Typed,owner,name),Table::Derived=>{let mut yes=false;visit_entries(self.index,owner,|e|yes|=e.kind=="derive"&&e.name.as_deref().is_some_and(|v|!v.is_empty()&&v==name));yes}})}
 fn exact(&self,owner:&str)->Result<bool,Failure>{let mut yes=false;schema::chain(owner,|_,a|yes|=self.index.entries(a).is_some_and(|es|!es.is_empty()));Ok(yes)}
 fn declared_value(&self,owner:&str,value:&str)->Result<bool,Failure>{self.has(Table::Derived,owner,value)}
 fn declared_read(&self,owner:&str,kind:&str,value:Option<&str>,name:&str)->Result<bool,Failure>{let mut yes=false;visit_entries(self.index,owner,|e|yes|=e.kind==kind&&value.is_none_or(|v|e.name.as_deref()==Some(v))&&e.has_local(name));Ok(yes)}
 fn published(&self,owner:&str,name:&str)->Result<bool,Failure>{let mut yes=false;schema::chain(owner,|_,a|{let mut last=None;for(t,v,k)in self.index.published(){if strip(t)==a&&v==name{last=Some(k.as_str())}}yes|=last.is_some_and(|k|!k.is_empty());});Ok(yes)}
 fn never_written(&self,owner:&str,name:&str)->Result<bool,Failure>{self.writes.never_written(self.index,owner,name)}
 fn allowed(&self,rel:&str,line:usize)->Result<bool,Failure>{if rel!=self.file.rel{return Err("derived ALLOW loan differs from current raw procedure file".into())}let mut c=Operation{budget:self.budget,poll:self.poll};let Some(kept)=crate::allow::kept_using(self.file,line,"derived_reads",&mut c)?else{return Ok(false)};let code=kept.code.unwrap_or_default();let mut data=self.data.borrow_mut();if !data.allows.iter().any(|a|a.rel==rel&&a.line as usize==kept.line&&a.name=="derived_reads"&&a.code==code){kc::row(&mut c,&mut data.allows)?;self.budget.charge(code.capacity()).map_err(|m|oom(self.budget,m))?;data.allows.push(AllowUse{rel:kc::own(&mut c,rel)?,line:u32::try_from(kept.line).map_err(|_|oom(self.budget,"derived ALLOW line overflow"))?,name:kc::own(&mut c,"derived_reads")?,code});}if !data.digests.contains_key(rel){kc::reserve(&mut c,||Some(2048))?;data.digests.insert(kc::own(&mut c,rel)?,crate::captured_raw_file::source_allow_digest(self.file));}Ok(true)}
}
fn procedures<C:Control>(file:&SourceFile,c:&mut C,mut visit:impl FnMut(usize,Procedure<'_>,&mut C)->Result<(),C::Error>)->Result<(),C::Error>{if file.rel==reaction::GENERATED_REL{return Ok(())}let code=file.code();for(number,line)in code.numbered(){c.checkpoint()?;let Some(header)=reaction::header_admitted(line,|groups|kc::temporary(c,0,||groups.checked_mul(4)?.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(std::mem::size_of::<crate::pat::Caps<'_>>()+64)))?else{continue};let owner=header.owner.trim_end_matches('/');let owner=if owner.is_empty(){"/"}else{owner};let first=number.checked_add(1).ok_or_else(||c.overflow())?;visit(number,Procedure{owner,name:header.name,relative:&file.rel,args:header.args,lines:Lines::IndentedCode{view:code,first}},c)?}Ok(())}
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
  .checked_add(entry.local.capacity().checked_mul(std::mem::size_of::<String>())?)?
  .checked_add(entry.remote.capacity().checked_mul(std::mem::size_of::<(Option<String>,String)>())?)?
  .checked_add(entry.hops.capacity().checked_mul(std::mem::size_of::<String>())?)?;
 for name in &entry.local{bytes=bytes.checked_add(name.capacity())?;}
 for (owner,name) in &entry.remote{bytes=bytes.checked_add(owner.as_ref().map_or(0,String::capacity))?.checked_add(name.capacity())?;}
 for hop in &entry.hops{bytes=bytes.checked_add(hop.capacity())?;}
 Some(bytes)
}

fn index_file(index:&mut Index,file:&SourceFile,scratch:&mut impl Control<Error=Failure>,retained:&mut Operation<'_>,transfer:bool)->Result<(),Failure>{
 let IndexEntries::Building(entries)=&mut index.entries else{unreachable!("cannot insert into sealed Derived entries")};
 let mut own=if file.rel==reaction::GENERATED_REL{Schema::default()}else{schema::file(file.code(),scratch)?};
 procedures(file,scratch,|header,proc,scratch|{
  schema::relations(&mut own,Procedure{owner:proc.owner,name:proc.name,relative:proc.relative,args:proc.args,lines:proc.lines},scratch)?;
  if proc.name=="derived"&&proc.owner!="/"{
   let owner=proc.owner;
   let key=strip(owner);
   if !entries.contains_key(key){
    kc::reserve(retained,||Some(2048))?;
    entries.insert(kc::own(retained,key)?,Vec::new());
    kc::row(retained,&mut index.entry_order)?;
    index.entry_order.push(kc::own(retained,owner)?);
   }
   let rows=crate::derived_entry_policy::entries(proc,header,scratch)?;
   let target=entries.get_mut(key).unwrap();
   for entry in rows{
    if transfer{kc::reserve(retained,||entry_backing(&entry))?;}
    kc::row(retained,target)?;
    target.push(entry);
   }
  }Ok(())
 })?;
 let IndexSchema::Building(schema)=&mut index.schema else{unreachable!("cannot insert into sealed Derived schema")};
 merge(schema,own,retained,transfer)
}

pub(crate) fn prepare(source:&ReadSource<'_>,poll:&dyn Fn()->io::Result<()>)->Result<Index,Failure>{
 let b=source.budget();check(b,poll)?;let mut scratch=Operation{budget:b,poll};let mut retained=Operation{budget:b,poll};let mut index=Index::default();
 files(&SemanticPages(source),|file|{index_file(&mut index,file,&mut scratch,&mut retained,false)?;Ok(true)})?;Ok(index)
}
/// Body-free selected raw DATA, not a source/model/preparation witness. There
/// is no public constructor, Clone, caller-hash binding or unchecked consume.
/// The index drops before its actual original operation's resource owner.
pub struct UnsealedDerivedIndexData{index:Index,backing:usize,funding:Arc<Budget>}
impl UnsealedDerivedIndexData{
 /// DATA-only consumption. The actual host must first bind its private raw
 /// recorder/current scope; this helper never issues a source/result witness.
 pub(crate) fn collect_held(self,source:&ReadSource<'_>,all_source:&ReadSource<'_>,globals:&GlobalResult,test_types:&BTreeSet<String>,poll:&dyn Fn()->io::Result<()>)->Result<DerivedReadData,Failure>{let Self{index,funding,..}=self;let pending=collect(source,all_source,index,globals,test_types,poll);drop(funding);pending}

 /// Conservative live backing bound only; not RSS or source authority.
 pub fn retained_charge(&self)->Option<usize>{
  self.backing.checked_add(std::mem::size_of::<Self>()+std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>())
 }
}
/// Per-file matcher high water. Slot zero covers mutually exclusive schema,
/// header and outer entry captures. Entry arguments and nested relation
/// selectors can coexist with an outer capture and use separate slots.
struct MatcherScratch<'a>{
 operation:Operation<'a>,
 peaks:[usize;3],
}
impl Control for MatcherScratch<'_>{
 type Error=Failure;
 const CHECKED:bool=true;
 fn checkpoint(&mut self)->Result<(),Failure>{self.operation.checkpoint()}
 fn reserve(&mut self,bytes:usize)->Result<(),Failure>{self.operation.reserve(bytes)}
 fn temporary(&mut self,slot:usize,bytes:usize)->Result<(),Failure>{
  let Some(&old)=self.peaks.get(slot)else{return Err(self.overflow())};
  if bytes>old{
   self.operation.reserve(bytes-old)?;
   self.peaks[slot]=bytes;
  }
  Ok(())
 }
 fn overflow(&mut self)->Failure{self.operation.overflow()}
 fn allocation_failed(&mut self)->Failure{self.operation.allocation_failed()}
}
struct PreflightPhase{funding:Arc<Budget>,complete:bool}impl Drop for PreflightPhase{fn drop(&mut self){if !self.complete{self.funding.keep_failed_scratch()}}}
/// SAME selected raw index builder, before any semantic frontend, PolicyInputs,
/// Globals or BODY. The host must later bind its genuine raw recorder/current
/// scope before any use with a semantic subject; DATA equality grants nothing.
pub fn prepare_selected_pages(pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<UnsealedDerivedIndexData,Failure>{
 prepare_selected_pages_observed(pages,budget,poll,None)
}
/// Same cold fold; observes only CODE views already demanded by index_file.
pub fn prepare_selected_pages_with_code(
 pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,
 observe:&mut dyn FnMut(&str,Option<&crate::tree::View>)->Result<(),Failure>,
)->Result<UnsealedDerivedIndexData,Failure>{
 prepare_selected_pages_observed(pages,budget,poll,Some(observe))
}
fn prepare_selected_pages_observed(
 pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>,
 mut observe:Option<&mut dyn FnMut(&str,Option<&crate::tree::View>)->Result<(),Failure>>,
)->Result<UnsealedDerivedIndexData,Failure>{
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
   let mut scratch=MatcherScratch{operation:Operation{budget:local,poll},peaks:[0;3]};
   index_file(&mut index,views.source_file()?,&mut scratch,&mut retained,true)?;
   if let Some(observe)=&mut observe{
    if relative==reaction::GENERATED_REL{observe(relative,None)?;}else{observe(relative,Some(views.code()?))?;}
   }
   guard.complete=true;
   Ok(true)
  })?;
  if !all{return Err("derived preflight stopped before actual selected raw EOF".into())}
  check(&funding,poll)?;Ok(index)
 })();
 let index=finish(pending,&funding,poll)?;
 let sealed_funding=Budget::scoped_temporaries(budget).map_err(|m|oom(budget,m))?;
 let mut seal=Seal{budget:&sealed_funding,poll,paid:0};
 let (index,backing)=seal.index(index)?;
 check(&sealed_funding,poll)?;
 // Old BTree nodes are now gone and moved payload has independent funding.
 phase.complete=true;
 drop(phase);
 drop(funding);
 Ok(UnsealedDerivedIndexData{index,backing,funding:sealed_funding})
}
pub(crate) fn collect(source:&ReadSource<'_>,all_source:&ReadSource<'_>,mut index:Index,globals:&GlobalResult,test_types:&BTreeSet<String>,poll:&dyn Fn()->io::Result<()>)->Result<DerivedReadData,Failure>{
 let b=source.budget();check(b,poll)?;if !globals.matches(source.inputs())||!globals.matches(all_source.inputs()){return Err("derived Globals belong to another original source".into())}
 let writes=CompleteWrites{source,globals,poll};let lexical=crate::reactive_raw_lexical_source::SemanticLoan::borrow(source);
 collect_pages(&SemanticPages(source),&SemanticPages(all_source),&lexical,index,&writes,test_types,poll,None,JudgeMode::Ordinary)
}
/// Borrow actual typed rows before the ordinary Site reduction. No source
/// receipt, retained finding clone, writer or query completion is exposed.
pub struct FixtureFinding<'a>(&'a Finding);
impl FixtureFinding<'_>{
 pub fn rule(&self)->&'static str{self.0.rule}
 pub fn relative(&self)->&str{&self.0.rel}
 pub fn line(&self)->usize{self.0.line}
 pub fn owner(&self)->&str{&self.0.owner}
 pub fn procedure(&self)->&str{&self.0.proc}
 pub fn variable(&self)->Option<&str>{self.0.var.as_deref()}
 pub fn kind(&self)->Option<&str>{self.0.kind.as_deref()}
}
/// This borrow cannot escape the actual collect phase. It does not turn the
/// fixture result or caller callback into a current-workspace authority.
pub struct Fixture<'a>{findings:&'a[Finding],source:&'a dyn DerivedPages,lexical:&'a dyn crate::reactive_raw_lexical_source::Source,poll:&'a dyn Fn()->io::Result<()>}
pub type FixtureVisitor<'a>=dyn for<'f> FnMut(Fixture<'f>)->Result<(),Failure>+'a;
impl Fixture<'_>{
 pub fn findings(&self)->impl Iterator<Item=FixtureFinding<'_>>{self.findings.iter().map(FixtureFinding)}
 pub fn generated_text(&self,test_types:&BTreeSet<String>)->Result<String,Failure>{crate::reactive_derived_generator_native::generate_raw(self.lexical,test_types)}
 pub fn inspect(&self)->Result<crate::derived_selftest_policy::Outcome,Failure>{
  let b=self.source.budget();let mut c=Operation{budget:b,poll:self.poll};c.checkpoint()?;
  struct Owned{relative:String,owner:String,name:String,start:usize,body:Vec<usize>}
  let mut files_data=Vec::new();let mut owned=Vec::new();
  files(self.source,|file|{
   kc::row(&mut c,&mut files_data)?;files_data.push((kc::own(&mut c,&file.rel)?,kc::own(&mut c,file.text())?));
   procedures(file,&mut c,|header,proc,c|{
    let mut body=Vec::new();for(number,line)in proc.lines.iter(){c.checkpoint()?;if !crate::util::py_strip(line).is_empty(){kc::row(c,&mut body)?;body.push(number)}}
    kc::row(c,&mut owned)?;owned.push(Owned{relative:kc::own(c,proc.relative)?,owner:kc::own(c,proc.owner)?,name:kc::own(c,proc.name)?,start:header,body});Ok(())
   })?;Ok(true)
  })?;
  let mut coordinates=Vec::new();for proc in &owned{c.checkpoint()?;let mut body=Vec::new();for number in &proc.body{kc::row(&mut c,&mut body)?;body.push(*number)}kc::row(&mut c,&mut coordinates)?;coordinates.push(crate::derived_fix_policy::Procedure{relative:&proc.relative,owner:&proc.owner,name:&proc.name,start:proc.start,body});}
  struct Input<'a>{files:&'a[(String,String)],procs:Vec<crate::derived_fix_policy::Procedure<'a>>}
  impl crate::derived_fix_policy::Source for Input<'_>{fn procedures(&self)->&[crate::derived_fix_policy::Procedure<'_>]{&self.procs}fn raw_text(&self,relative:&str)->Option<&str>{self.files.iter().find(|(rel,_)|rel==relative).map(|(_,text)|text.as_str())}}
  let fixed=crate::derived_fix_policy::fix_texts(&Input{files:&files_data,procs:coordinates},self.findings,&mut c)?;
  let generated=self.generated_text(&BTreeSet::new())?;
  let mut findings=Vec::new();for row in self.findings{c.checkpoint()?;kc::row(&mut c,&mut findings)?;findings.push(Finding{rel:kc::own(&mut c,&row.rel)?,line:row.line,rule:row.rule,owner:kc::own(&mut c,&row.owner)?,proc:kc::own(&mut c,&row.proc)?,var:row.var.as_deref().map(|value|kc::own(&mut c,value)).transpose()?,kind:row.kind.as_deref().map(|value|kc::own(&mut c,value)).transpose()?});}
  c.checkpoint()?;Ok(crate::derived_selftest_policy::Outcome{fixed,generated,findings})
 }

}
// The historical callback intentionally tests explicit declarations with
// generated_covers=false and no semantic never-written exemption. This mode
// changes fixture DATA judgment only; it is not a failed-source witness.
#[derive(Clone,Copy)]enum JudgeMode{Ordinary,ExplicitFixture}
struct FixtureDeclaredOnly;
impl WriteKnowledge for FixtureDeclaredOnly{fn never_written(&self,_:&Index,_:&str,_:&str)->Result<bool,Failure>{Ok(false)}fn collects_set_calls(&self)->bool{false}}
pub(crate) fn collect_with_fixture(source:&ReadSource<'_>,all_source:&ReadSource<'_>,index:Index,globals:&GlobalResult,test_types:&BTreeSet<String>,poll:&dyn Fn()->io::Result<()>,visit:&mut FixtureVisitor<'_>)->Result<DerivedReadData,Failure>{
 let b=source.budget();check(b,poll)?;if !globals.matches(source.inputs())||!globals.matches(all_source.inputs()){return Err("derived fixture Globals belong to another original source".into())}
 let writes=FixtureDeclaredOnly;let lexical=crate::reactive_raw_lexical_source::SemanticLoan::borrow(source);
 collect_pages(&SemanticPages(source),&SemanticPages(all_source),&lexical,index,&writes,test_types,poll,Some(visit),JudgeMode::ExplicitFixture)
}

fn collect_pages(source:&dyn DerivedPages,all_source:&dyn DerivedPages,lexical:&dyn crate::reactive_raw_lexical_source::Source,mut index:Index,writes:&dyn WriteKnowledge,test_types:&BTreeSet<String>,poll:&dyn Fn()->io::Result<()>,fixture:Option<&mut FixtureVisitor<'_>>,mode:JudgeMode)->Result<DerivedReadData,Failure>{
 let b=source.budget();let mut c=Operation{budget:b,poll};
 // Old Model is already built. Now genuine Globals/writes precede eager setter
 // names from ALL CODE, including files exempt from this lint's model.
 if writes.collects_set_calls(){files(all_source,|file|{for call in crate::auto_setter_calls_policy::collect_file(&mut c,&file.rel,file.text(),||file.code().text.as_str())?{if !index.set_calls.contains(&call){kc::reserve(&mut c,||Some(512))?;index.set_calls.insert(call);}}Ok(true)})?;}
 let data=RefCell::new(DerivedReadData::default());let mut findings=Vec::new();
 for exact in [false,true]{files(source,|file|{let facts=Judge{index:&index,writes,file,data:&data,budget:b,poll};procedures(file,&mut c,|header,proc,c|{let mut output=|finding|{kc::row(&mut Operation{budget:b,poll},&mut findings)?;findings.push(finding);Ok(())};if exact{judge::exact(&facts,proc,header,c,&mut output)}else{judge::reactive(&facts,proc,matches!(mode,JudgeMode::Ordinary),c,&mut output)}})?;Ok(true)})?;}
 for owner in &index.entry_order{for e in index.entries(strip(owner)).ok_or("derived entry-order owner absent from its index")?{find_file(source,&e.rel,|file|{let facts=Judge{index:&index,writes,file,data:&data,budget:b,poll};judge::entry(&facts,owner,e,&mut c,&mut|finding|{kc::row(&mut Operation{budget:b,poll},&mut findings)?;findings.push(finding);Ok(())})})?;}}
 for r in crate::reactive_reaction_native::reaction_reads_raw(lexical)?{let OwnedProcedureKey::Raw{relative,header}=r.procedure else{return Err("native derived reaction lacks authentic raw coordinates".into())};find_file(source,&relative,|file|{let line=file.code().line(header);let Some(h)=reaction::header_admitted(line,|groups|kc::reserve(&mut c,||groups.checked_mul(4)?.checked_mul(std::mem::size_of::<Option<(usize,usize)>>())?.checked_add(std::mem::size_of::<crate::pat::Caps<'_>>()+64)))?else{return Err("derived reaction original header absent".into())};let proc=Procedure{owner:&r.owner,name:h.name,relative:&relative,args:h.args,lines:Lines::IndentedCode{view:file.code(),first:header.checked_add(1).ok_or_else(||oom(b,"derived reaction header overflow"))?}};let facts=Judge{index:&index,writes,file,data:&data,budget:b,poll};judge::reaction(&facts,proc,r.kind,&r.reads,&mut c,&mut|finding|{kc::row(&mut Operation{budget:b,poll},&mut findings)?;findings.push(finding);Ok(())})})?;}
 kc::sort_data(&mut findings,&mut|a,b|{c.checkpoint()?;Ok::<_,Failure>(judge::compare(a,b))})?;if let Some(visit)=fixture{c.checkpoint()?;visit(Fixture{findings:&findings,source,lexical,poll})?;c.checkpoint()?;}let mut data=data.into_inner();for f in findings{find_file(source,&f.rel,|file|{let line=u32::try_from(f.line).map_err(|_|oom(b,"derived finding line overflow"))?;kc::row(&mut c,&mut data.sites)?;data.sites.push(Site{rule:kc::own(&mut c,f.rule)?,rel:kc::own(&mut c,&f.rel)?,line,msg:String::new(),key:String::new(),ident:String::new()});kc::row(&mut c,&mut data.source_text)?;kc::reserve(&mut c,||file.raw().line(f.line).len().checked_mul(4)?.checked_add(128))?;data.source_text.push(crate::util::normalize_ws(file.raw().line(f.line)));Ok(())})?;}
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
 #[test]fn treefree_preflight_uses_same_identifier_index_without_semantic_source_and_keeps_credit_live(){let pages=pages();let budget=Budget::new(8*1024*1024).unwrap();let before=budget.used();let data=prepare_selected_pages(&pages,&budget,&||Ok(())).unwrap();assert_eq!(pages.passes.get(),1);assert!(data.index.has(NameTable::Vars,"datum/probe","value"));assert_eq!(data.index.entry_order,["/datum/probe"]);assert_eq!(data.index.entries("datum/probe").unwrap()[0].kind,"drawn");assert!(data.index.set_calls.is_empty(),"setter names belong after actual semantic preparation");assert!(data.retained_charge().unwrap()>std::mem::size_of::<UnsealedDerivedIndexData>());assert!(budget.used()>before);let fixed=std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>();let held=budget.used();let payload=data.funding.used().checked_sub(fixed).unwrap();assert!(payload>0);drop(data);assert_eq!(budget.used(),held-payload);assert_eq!(budget.used(),before+3*fixed,"builder, sealed index and fallback retain only child Arc/control grants");}
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
  assert!(data.index.has(NameTable::Vars,"datum/probe","value"));
  let rows=&data.index.entries("datum/probe").unwrap();
  assert_eq!(rows.len(),64);
  assert_eq!(rows[0].rel,"code/file_0.dm");
  assert_eq!(rows[63].rel,"code/file_63.dm");
  assert!(rows.iter().all(|entry|entry.has_local("value")));
  assert!(data.funding.used()>=rows.iter().map(|entry|entry_backing(entry).unwrap()).sum::<usize>());
  let fixed=std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>();
  drop(data);
  assert_eq!(budget.used(),67*fixed,"root, builder, sealed index and file children leave only fixed grants");
 }
 #[test]
 fn one_large_file_reuses_sequential_and_nested_matcher_slots(){
  struct Single<'a>{root:&'a std::path::Path,budget:&'a Arc<Budget>,text:dm_preprocess::SourceText}
  impl crate::reactive_raw_policy_pages::RawPolicyPages for Single<'_>{
   fn for_each(&self,visit:&mut dyn FnMut(&str,crate::captured_raw_file::RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
    crate::captured_raw_file::with_original_policy_file_code_prepared(
     self.root,&self.root.join("code/large.dm"),self.budget,|_|Ok(self.text.clone()),visit)
   }
  }
  let root=std::env::current_dir().unwrap().join("derived-matcher-scratch");
  let mut source="STAT(/datum/probe, value)\n".repeat(12_000);
  source.push_str("/datum/probe/derived()\n    return list(derive(nameof(output), nameof(value), rel_each(nameof(items), nameof(/obj/item::value))))\n");
  let budget=Budget::new(2*1024*1024).unwrap();
  let data=prepare_selected_pages(&Single{root:&root,budget:&budget,text:source.into()},&budget,&||Ok(())).unwrap();
  assert!(data.index.has(NameTable::Tracked,"datum/probe","value"));
  let rows=&data.index.entries("datum/probe").unwrap();
  assert_eq!(rows.len(),1);
  let row=&rows[0];
  assert_eq!(row.line,12_002);
  assert_eq!(row.name.as_deref(),Some("output"));
  assert!(row.has_local("value"));
  assert!(row.has_local("items"));
  assert_eq!(row.remote,[(Some("/obj/item".into()),"value".into())]);
 }
 #[test]
 fn sealed_entry_locals_preserve_sorted_unique_names_and_charge_actual_backing() {
  let root = std::env::current_dir().unwrap().join("derived-entry-locals");
  let source = concat!(
   "/datum/probe/derived()\n",
   "    return list(drawn_from(nameof(z), nameof(a), nameof(z), rel(nameof(m), nameof(remote)), nameof(m)))\n",
  );
  let pages = Pages {
   file: crate::captured_raw_file::File::capture(&root, &root.join("code/probe.dm"), source.into()).unwrap(),
   fail: Cell::new(false),
   stop: Cell::new(false),
   passes: Cell::new(0),
  };
  let budget = Budget::new(8 * 1024 * 1024).unwrap();
  let mut data = prepare_selected_pages(&pages, &budget, &|| Ok(())).unwrap();
  let IndexEntries::Sealed(entries) = &mut data.index.entries else { panic!("actual cold index must seal") };
  let entry = &mut entries[0].1[0];
  assert_eq!(entry.local, ["a", "m", "z"]);
  assert_eq!(entry.hops, ["m"]);
  assert!(entry.has_local("m"));
  assert!(!entry.has_local("remote"));
  let with_locals = entry_backing(entry).unwrap();
  let locals = std::mem::take(&mut entry.local);
  let local_storage = locals.capacity() * std::mem::size_of::<String>()
   + locals.iter().map(String::capacity).sum::<usize>();
  assert_eq!(with_locals - entry_backing(entry).unwrap(), local_storage);
 }

 #[test]
 fn sealed_derived_lookup_keeps_sorted_members_and_authored_entry_order(){
  let root=std::env::current_dir().unwrap().join("derived-sealed-order");
  let text=concat!(
   "/datum/z\n    var/last\n    var/first\n    /datum/z/derived()\n        return list(drawn_from(nameof(last)), ui_from(nameof(first)))\n",
   "/datum/a\n    var/other\n    /datum/a/derived()\n        return list(drawn_from(nameof(other)))\n",
   "PUBLISHED_BY(/datum/z, first, key_a)\nPUBLISHED_BY(/datum/z, first, key_b)\n");
  let pages=Pages{file:crate::captured_raw_file::File::capture(&root,&root.join("code/probe.dm"),text.into()).unwrap(),fail:false.into(),stop:false.into(),passes:0.into()};
  let budget=Budget::new(8*1024*1024).unwrap();
  let data=prepare_selected_pages(&pages,&budget,&||Ok(())).unwrap();
  let IndexSchema::Sealed(schema)=&data.index.schema else{panic!("cold index must seal")};
  let IndexEntries::Sealed(entries)=&data.index.entries else{panic!("cold entry index must seal")};
  for table in [&schema.vars,&schema.typed,&schema.tracked,&schema.relations]{
   assert_eq!(table.len(),table.capacity());
   assert!(table.windows(2).all(|w|w[0].0<w[1].0));
   for (_,names) in table{assert_eq!(names.len(),names.capacity());assert!(names.windows(2).all(|w|w[0]<w[1]));}
  }
  assert_eq!(entries.len(),entries.capacity());
  assert_eq!(entries.iter().map(|(owner,_)|owner.as_str()).collect::<Vec<_>>(),["datum/a","datum/z"]);
  assert_eq!(data.index.entry_order,["/datum/z","/datum/a"]);
  assert_eq!(data.index.entries("datum/z").unwrap().iter().map(|row|row.kind).collect::<Vec<_>>(),["drawn","ui"]);
  assert!(data.index.has(NameTable::Vars,"datum/z/child","first"));
  assert!(!data.index.has(NameTable::Vars,"datum/z/child","other"));
  assert_eq!(data.index.published().last().map(|row|row.2.as_str()),Some("key_b"));
  assert_eq!(data.backing,sealed_index_backing(schema,entries,&data.index.entry_order).unwrap());
  let fixed=std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>();
  assert_eq!(budget.used(),4*fixed+data.backing,"all successful builder grants have been retired");
 }
 #[test]fn treefree_preflight_refuses_actual_io_early_stop_and_quota_then_recovers(){let pages=pages();let budget=Budget::new(8*1024*1024).unwrap();pages.fail.set(true);assert!(matches!(prepare_selected_pages(&pages,&budget,&||Ok(())),Err(Failure::Operational(ref error))if error.raw_os_error()==Some(1450)));assert_eq!(pages.passes.get(),0);pages.fail.set(false);pages.stop.set(true);assert!(matches!(prepare_selected_pages(&pages,&budget,&||Ok(())),Err(Failure::Unsupported(_))));pages.stop.set(false);let tiny=Budget::new(256).unwrap();assert!(matches!(prepare_selected_pages(&pages,&tiny,&||Ok(())),Err(Failure::Operational(ref error))if error.kind()==io::ErrorKind::OutOfMemory));let fresh=Budget::new(8*1024*1024).unwrap();let data=prepare_selected_pages(&pages,&fresh,&||Ok(())).unwrap();assert_eq!(data.index.entry_order.len(),1);}
}

/// Source-neutral raw-only DATA for the old semantic-unavailable branch. This
/// accepts no caller None, fake Globals, PolicyInputs or absence/completion
/// witness. The host must separately authenticate its real failed preparation
/// and selected/all-CODE EOF, and must never cache this as a current source.
pub fn derived_reads_data_without_semantic_from_preflight_pages(preflight:UnsealedDerivedIndexData,selected_pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,test_types:&BTreeSet<String>,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<DerivedReadData,Failure>{
 check(budget,poll)?;let phase=Budget::scoped_temporaries(budget).map_err(|m|oom(budget,m))?;let mut held=Some(preflight);
 let pending=(||{let selected=RawPages{pages:selected_pages,budget:&phase,poll};let all=RawPages{pages,budget:&phase,poll};let UnsealedDerivedIndexData{index,funding,..}=held.take().expect("single actual raw index");let pending=collect_pages(&selected,&all,&selected,index,&NoSemanticWrites,test_types,poll,None,JudgeMode::Ordinary);drop(funding);pending})();
 let pending=finish(pending,&phase,poll);let pending=match pending{Ok(data)=>{let n=data.retained_charge().ok_or_else(||oom(budget,"raw-only Derived retention overflow"))?;match budget.charge(n){Ok(())=>Ok(data),Err(m)=>{drop(data);Err(oom(budget,m))}}},Err(e)=>Err(e)};
 drop(held);if pending.is_err(){phase.keep_failed_scratch()}drop(phase);finish(pending,budget,poll)
}

#[cfg(all(test,feature="legacy-sem"))]
#[path="captured_derived_unavailable_tests.rs"]mod unavailable_controls;
