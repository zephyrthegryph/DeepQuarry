//! Read-flow interpreter over the ORIGINAL native body graph.
//! WORKING DATA ONLY: callers may not install/publish this partial producer.
//! Unclosed semantics return Unsupported atomically rather than an empty set.
use crate::reactive_original_source::{ReadSource,ReadCallable,SelectedCallable};
use crate::reactive_read_facts::{Read,ReadKind,ReadSet,LookupArgument,LookupBound,LookupRead};
use dm_syntax::{Expr,ExprKind,Span,Statement,StatementKind,ForControl,ForInitializer};
use std::{collections::{BTreeMap,BTreeSet,HashMap},io};
const MAX_EXPRESSION_DEPTH:usize=256;
const MAX_CALL_DEPTH:usize=24; // pinned guard, entry compares > (not >=)
const MAX_HOPS:usize=4; // existing original read policy
#[derive(Debug)]
pub enum Failure{Unsupported(String),Operational(io::Error)}
impl From<String> for Failure{fn from(v:String)->Self{Self::Unsupported(v)}}
impl From<&str> for Failure{fn from(v:&str)->Self{Self::Unsupported(v.into())}}
impl From<io::Error> for Failure{fn from(v:io::Error)->Self{Self::Operational(v)}}
#[derive(Clone,Debug,Eq,PartialEq,Ord,PartialOrd)]
pub(crate) enum Root{Holder,Context(String),Act,Local,Scalar(LookupArgument),Lookup(Box<LookupBound>),Global(String)}
#[derive(Clone,Debug,Eq,PartialEq)]
struct Value{ty:Option<String>,root:Root,hops:Vec<String>,hop_ok:bool,list:bool,blame:Option<String>}
impl Value{
 fn local(ty:Option<String>)->Self{Self{ty,root:Root::Local,hops:Vec::new(),hop_ok:true,list:false,blame:None}}
 fn tracked(&self)->bool{matches!(self.root,Root::Holder|Root::Context(_)|Root::Lookup(_))}
 fn root_width(&self)->Option<usize>{match &self.root{Root::Context(s)|Root::Global(s)=>Some(s.len()),Root::Scalar(LookupArgument::Literal(s))=>Some(s.len()),Root::Scalar(LookupArgument::Path{root,path})=>path.iter().try_fold(root.len(),|n,s|n.checked_add(s.len()).and_then(|n|n.checked_add(std::mem::size_of::<String>()))),Root::Lookup(bound)=>lookup_bytes(bound),_=>Some(0)}}
 fn root_name(&self)->&str{match &self.root{Root::Holder=>"holder",Root::Context(n)=>n,_=>""}}
}
pub(crate) type Reads=ReadSet;
/// Unique read-policy annotations, NOT a DM type/procedure table. Native raw
/// producer issuance and inherited membership are still to be integrated.
pub(crate) trait GlobalFacts{
 fn constant_after_init(&self,name:&str)->Result<bool,Failure>;
 fn field_constant_after_init(&self,name:&str)->Result<bool,Failure>;
 fn is_written_on(&self,source:&ReadSource<'_>,owner:&str,name:&str)->Result<bool,Failure>;
}
pub(crate) struct Directives<'a>{pub facts:&'a crate::reactive_policy_facts_native::PolicyFacts,pub globals:Option<&'a dyn GlobalFacts>}
type MemoKey=(String,String,Root,Option<String>,Vec<(Root,Option<String>)>,bool);
struct MemoNode{own:Reads,children:Vec<(MemoKey,bool)>,trivial:bool}
type VisitKey=(String,String,Root,Vec<String>,Vec<(Root,Vec<String>)>);
struct Frame<'a,'body>{ordinal:usize,name:&'a str,rel:String,body:&'body dm_tree::frontend::ArchivedBody<'a>,this:Value,locals:BTreeMap<String,Value>,narrow:HashMap<String,Vec<String>>,ret:Option<Value>}
impl Frame<'_,'_>{fn note_return(&mut self,value:Value){if self.ret.is_none()&&value.tracked(){self.ret=Some(value);}}}
struct Walk<'a,'source,'op>{source:&'source ReadSource<'a>,directives:Directives<'source>,out:Reads,checkpoint:&'op mut dyn FnMut()->io::Result<()>,depth:usize,mute:usize,offset:usize,line:u32,block_depth:usize,call_depth:usize,closed:bool,visited:BTreeSet<VisitKey>,context_override:Option<String>,active_rel:String,override_depth:usize,engine_depth:usize,diag_ix:BTreeMap<(&'static str,String,u32,String),usize>,memo:BTreeMap<MemoKey,MemoNode>,children:Vec<(MemoKey,bool)>,computing:BTreeSet<MemoKey>,merged:BTreeSet<MemoKey>}
impl<'a,'source,'op> Walk<'a,'source,'op>{

 fn analyze_request(&mut self,receiver:&str,name:&str,context_override:Option<&str>)->Result<Reads,Failure>{
  self.tick()?;self.out=Reads::default();self.visited.clear();self.children.clear();self.computing.clear();self.merged.clear();self.diag_ix.clear();self.line=0;self.active_rel.clear();self.override_depth=0;self.engine_depth=0;
  self.reserve(receiver.len().checked_add(context_override.map_or(0,str::len)).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(1024)))?;self.context_override=context_override.map(str::to_owned);
  let SelectedCallable::Source(callee)=self.source.callable(receiver,name)?else{return Ok(Reads::default())};
  let this=Value{ty:Some(receiver.to_owned()),root:Root::Holder,hops:Vec::new(),hop_ok:true,list:false,blame:None};
  self.run_proc(callee.ordinal,this,&[],true,false)?;self.finish()?;self.tick()?;Ok(std::mem::take(&mut self.out))
 }
 fn run_proc(&mut self,ordinal:usize,this:Value,bind:&[Value],first_is_context:bool,no_act:bool)->Result<Option<Value>,Failure>{
  self.tick()?;if self.call_depth>MAX_CALL_DEPTH{return Ok(None);}
  let archive=self.source.inputs().archive();let tree=archive.tree();
  let occurrence=archive.occurrences().get(ordinal).ok_or("reactive callee original occurrence absent")?;
  let node=tree.member(occurrence.member).ok_or("reactive callee original member absent")?;
  let owner=tree.type_node(node.owner).and_then(|t|tree.symbols().text(t.path)).ok_or("reactive callee original owner absent")?;
  let name=tree.symbols().text(node.name).ok_or("reactive callee original name absent")?;
  let mut width=owner.len().checked_add(name.len()).and_then(|n|n.checked_add(this.root_width()?));
  for hop in &this.hops{width=width.and_then(|n|n.checked_add(hop.len()));}
  for v in bind{for hop in &v.hops{width=width.and_then(|n|n.checked_add(hop.len()));}width=width.and_then(|n|n.checked_add(v.root_width()?));}
  self.reserve(width.and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(bind.len().checked_mul(1024)?)).and_then(|n|n.checked_add(4096)))?;
  // Deliberately preserve old key: no version, types or local values. This is
  // unique read-flow cycle work, not a copied procedure/type/callgraph model.
  let key=(owner.to_owned(),name.to_owned(),this.root.clone(),this.hops.clone(),bind.iter().map(|v|(v.root.clone(),v.hops.clone())).collect());
  if !self.visited.insert(key){return Ok(None);}
  if !self.closed{self.out.followed.insert(format!("{}::{}",owner,name));}
  let context_free=self.closed&&self.mute==0&&!self.directives.facts.annotations.summaries.keys().any(|(ty,proc)|ty==owner&&proc==name)&&matches!(this.root,Root::Local|Root::Global(_))&&bind.iter().all(|value|matches!(value.root,Root::Local|Root::Global(_)));
  if context_free{
   let type_width=bind.iter().try_fold(this.ty.as_ref().map_or(0,String::len),|n,value|n.checked_add(value.ty.as_ref().map_or(0,String::len)));
   self.reserve(width.and_then(|n|n.checked_add(type_width?)).and_then(|n|n.checked_mul(32)).and_then(|n|n.checked_add(bind.len().checked_mul(2048)?)).and_then(|n|n.checked_add(8192)))?;
   let key=(owner.to_owned(),name.to_owned(),this.root.clone(),this.ty.clone(),bind.iter().map(|v|(v.root.clone(),v.ty.clone())).collect(),no_act);
   let outer=self.override_depth>0||self.engine_depth>0;
   if self.memo.get(&key).is_some_and(|node|node.trivial){return Ok(None)}
   if !self.memo.contains_key(&key)&&!self.computing.contains(&key){
    self.computing.insert(key.clone());
    let saved_out=std::mem::take(&mut self.out);let saved_visited=std::mem::take(&mut self.visited);let saved_children=std::mem::take(&mut self.children);let saved_ix=std::mem::take(&mut self.diag_ix);
    let saved_override=std::mem::take(&mut self.override_depth);let saved_engine=std::mem::take(&mut self.engine_depth);let saved_depth=std::mem::take(&mut self.call_depth);
    let outcome=self.enter_proc(ordinal,owner,name,this,bind,first_is_context,no_act);
    self.override_depth=saved_override;self.engine_depth=saved_engine;self.call_depth=saved_depth;self.visited=saved_visited;
    let own=std::mem::replace(&mut self.out,saved_out);let children=std::mem::replace(&mut self.children,saved_children);self.diag_ix=saved_ix;self.computing.remove(&key);outcome?;
    let bare=own.reads.is_empty()&&own.diags.is_empty()&&own.lookup_diags.is_empty()&&own.opaque.is_empty()&&own.ctx_fields.is_empty()&&own.sampled.is_empty();
    let trivial=bare&&children.iter().all(|(child,_)|self.memo.get(child).is_some_and(|node|node.trivial));
    self.memo.insert(key.clone(),MemoNode{own,children,trivial});if trivial{return Ok(None)}
   }
   if !self.source.budget().row(&mut self.children){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reactive memo child row refused")))}self.children.push((key,outer));return Ok(None)
  }
  self.enter_proc(ordinal,owner,name,this,bind,first_is_context,no_act)
 }
 fn enter_proc(&mut self,ordinal:usize,owner:&'a str,name:&'a str,this:Value,bind:&[Value],first_is_context:bool,no_act:bool)->Result<Option<Value>,Failure>{
  let archive=self.source.inputs().archive();
  if let Some((_,summary))=self.directives.facts.annotations.summaries.iter().find(|((ty,proc),_)|ty==owner&&proc==name){self.apply_summary(owner,name,summary,&this,bind)?;return Ok(None)}
  if !self.closed{
   let rel=self.source.site_line(ordinal,1)?.0;
   if crate::reactive_read_facts::ENGINE_DIRS.iter().any(|prefix|rel.starts_with(prefix)){
    if self.call_depth>0&&self.mute==0{
     self.reserve(owner.len().checked_add(name.len()).and_then(|n|n.checked_add(self.active_rel.len())).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(1024)))?;
     self.out.opaque.entry(format!("{}::{}",owner,name)).or_insert_with(||(self.active_rel.clone(),self.line));
    }
    return Ok(None)
   }
  }
  let body=self.source.parse_body(ordinal).map_err(|error|match error{dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>Failure::Operational(actual),dm_tree::frontend::BodySyntaxFailure::Syntax(error)=>Failure::Unsupported(error.message)})?;
  if !body.statement_body().has_native_literal_syntax(){return Err("reactive callee requires actual admitted original Kind4 syntax".into());}
  if !body.statement_body().syntax_complete(){return Err("reactive callee grammar is not completely issued".into());}
  let parameters=body.source_parameters()?;let entries=parameters.entries()?;
  self.reserve(entries.iter().try_fold(0usize,|n,p|n.checked_add(parameter_bytes(p)?)).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(entries.len().checked_mul(1024)?)))?;
  let rel=self.source.site_line(ordinal,1)?.0;let in_engine=self.closed&&crate::reactive_read_facts::ENGINE_DIRS.iter().any(|prefix|rel.starts_with(prefix));
  let mut frame=Frame{ordinal,name,rel,body:&body,this,locals:BTreeMap::new(),narrow:HashMap::new(),ret:None};
  for(i,parameter)in entries.iter().enumerate(){
   let name=parameters.name(parameter)?;let declared=parameters.type_path(parameter)?;
   let mut value=if let Some(value)=bind.get(i){self.value_copy(value)?}else{Value::local(declared.clone())};
   if let Some(declared)=declared{
    if value.ty.is_none()||value.root==Root::Local||value.ty.as_ref().is_some_and(|current|current!=&declared)&&match value.ty.as_deref(){Some(current)=>self.source.is_subtype(&declared,current)?,None=>false}{value.ty=Some(declared.clone());}
    if self.source.is_subtype(&declared,"/datum/act")?&&(first_is_context||bind.get(i).is_some())&&!no_act&&value.root==Root::Local{
     value.root=Root::Act;if i==0&&first_is_context{if let Some(context)=&self.context_override{self.reserve(context.len().checked_mul(4).and_then(|n|n.checked_add(512)))?;value.ty=Some(context.clone());}}
    }
   }
   self.bind(&mut frame,name,value)?;
  }
  // This is a negative work prefilter on the SAME already-issued expanded
  // body spelling, never source/meaning authority or another lexer. An actual
  // primary istype identifier must spell those ASCII bytes; comments/strings
  // can only cause harmless extra traversal. The original AST remains final.
  let occurrence=archive.occurrences().get(ordinal).ok_or("reactive narrowing occurrence absent")?;
  let code=archive.expanded_source().get(occurrence.expanded_span.range()).ok_or("reactive narrowing body source outside original arena")?;
  if code.contains("istype"){self.collect_narrowing(&mut frame)?;}
  let prior_rel=std::mem::replace(&mut self.active_rel,frame.rel.clone());
  let previous_offset=std::mem::replace(&mut self.offset,0);self.call_depth+=1;self.engine_depth+=usize::from(in_engine);
  let result=self.statements(&mut frame,&body.statement_body().parsed().statements);
  self.call_depth-=1;self.engine_depth-=usize::from(in_engine);self.offset=previous_offset;self.active_rel=prior_rel;result?;Ok(frame.ret)
 }
 fn tick(&mut self)->Result<(),Failure>{(self.checkpoint)()?;self.source.require()?;Ok(())}
 fn reserve(&self,n:Option<usize>)->Result<(),Failure>{self.source.reserve(n).map_err(|actual|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual)))}
 fn value_copy(&self,v:&Value)->Result<Value,Failure>{self.reserve(v.hops.iter().try_fold(v.ty.as_ref().map_or(0,String::len),|n,s|n.checked_add(s.len()).and_then(|n|n.checked_add(std::mem::size_of::<String>()))).and_then(|n|n.checked_add(v.root_width()?)).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(1024)))?;Ok(v.clone())}
 fn bind(&mut self,fr:&mut Frame<'a,'_>,name:&str,value:Value)->Result<(),Failure>{self.reserve(name.len().checked_mul(4).and_then(|n|n.checked_add(1024)))?;fr.locals.insert(name.to_owned(),value);Ok(())}
 fn diag(&mut self,fr:&Frame<'a,'_>,rule:&'static str,args:std::fmt::Arguments<'_>)->Result<(),Failure>{self.diag_at(&fr.rel,rule,args)}
 fn diag_at(&mut self,rel:&str,rule:&'static str,args:std::fmt::Arguments<'_>)->Result<(),Failure>{self.diag_at_line(rel,self.line,rule,args)}
 fn diag_at_line(&mut self,rel:&str,line:u32,rule:&'static str,args:std::fmt::Arguments<'_>)->Result<(),Failure>{
  let mut message=String::new();if !self.source.budget().append_fmt(&mut message,args){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reactive diagnostic text admission refused")))}
  self.reserve(message.len().checked_add(rel.len()).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(2048)))?;
  self.record_diagnostic(crate::reactive_read_facts::Diag{rule,closed_only:self.override_depth>0||self.engine_depth>0,rel:rel.to_owned(),line,msg:message})

 }
 fn record_diagnostic(&mut self,diagnostic:crate::reactive_read_facts::Diag)->Result<(),Failure>{
  self.reserve(diagnostic.msg.len().checked_add(diagnostic.rel.len()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(2048)))?;
  let key=(diagnostic.rule,diagnostic.rel.clone(),diagnostic.line,diagnostic.msg.clone());
  if let Some(&index)=self.diag_ix.get(&key){self.out.diags[index].closed_only&=diagnostic.closed_only;return Ok(())}
  if !self.source.budget().row(&mut self.out.diags){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reactive diagnostic row admission refused")))}
  self.diag_ix.insert(key,self.out.diags.len());self.out.diags.push(diagnostic);Ok(())
 }
 fn merge(&mut self,node:&Reads,outer:bool)->Result<(),Failure>{
  for read in &node.reads{self.tick()?;if !node.internal.contains(read){self.out.internal.remove(read);}}
  for read in &node.internal{self.tick()?;self.reserve(read_bytes(read).and_then(|n|n.checked_mul(16)).and_then(|n|n.checked_add(4096)))?;if !self.out.reads.contains(read){self.out.internal.insert(read.clone());}}
  for read in &node.reads{
   self.tick()?;self.reserve(read_bytes(read).and_then(|n|n.checked_add(node.sites.get(read).map_or(0,|s|s.0.len()))).and_then(|n|n.checked_mul(16)).and_then(|n|n.checked_add(4096)))?;
   self.out.reads.insert(read.clone());if let Some(site)=node.sites.get(read){self.out.sites.entry(read.clone()).or_insert_with(||site.clone());}
  }
  for(key,site)in &node.ctx_fields{self.tick()?;self.reserve(key.len().checked_add(site.0.len()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(1024)))?;self.out.ctx_fields.entry(key.clone()).or_insert_with(||site.clone());}
  for diagnostic in &node.diags{self.tick()?;self.reserve(diagnostic.msg.len().checked_add(diagnostic.rel.len()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(1024)))?;let mut current=diagnostic.clone();current.closed_only|=outer;self.record_diagnostic(current)?;}
  for diagnostic in &node.lookup_diags{self.tick()?;if !self.out.lookup_diags.contains(diagnostic){self.reserve(diagnostic.msg.len().checked_add(diagnostic.rel.len()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(1024)))?;if !self.source.budget().row(&mut self.out.lookup_diags){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reactive lookup merge row refused")))}self.out.lookup_diags.push(diagnostic.clone());}}
  for(key,site)in &node.opaque{self.tick()?;self.reserve(key.len().checked_add(site.0.len()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(1024)))?;self.out.opaque.entry(key.clone()).or_insert_with(||site.clone());}
  for site in &node.sampled{self.tick()?;self.reserve(site.0.len().checked_mul(4).and_then(|n|n.checked_add(1024)))?;self.out.sampled.insert(site.clone());}
  Ok(())
 }
 fn finish(&mut self)->Result<(),Failure>{
  let memo=std::mem::take(&mut self.memo);let mut stack=std::mem::take(&mut self.children);stack.reverse();
  let result=(||{
   while let Some((key,outer))=stack.pop(){
    self.tick()?;if self.merged.contains(&key){continue}self.reserve(memo_bytes(&key).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(4096)))?;self.merged.insert(key.clone());
    let Some(node)=memo.get(&key)else{continue};self.merge(&node.own,outer)?;
    for(child,flag)in node.children.iter().rev(){
     if !self.merged.contains(child){self.reserve(memo_bytes(child).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(1024)))?;if !self.source.budget().row(&mut stack){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reactive memo merge stack refused")))}stack.push((child.clone(),outer||*flag));}
    }
   }
   self.tick()
  })();self.memo=memo;result
 }
 fn lookup_diag(&mut self,fr:&Frame<'a,'_>,rule:&'static str,args:std::fmt::Arguments<'_>)->Result<(),Failure>{self.lookup_diag_at(&fr.rel,rule,args)}
 fn lookup_diag_at(&mut self,rel:&str,rule:&'static str,args:std::fmt::Arguments<'_>)->Result<(),Failure>{
  let mut message=String::new();if !self.source.budget().append_fmt(&mut message,args){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"lookup diagnostic text admission refused")))}
  self.reserve(message.len().checked_add(rel.len()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(1024)))?;
  let diagnostic=crate::reactive_read_facts::Diag{rule,closed_only:false,rel:rel.to_owned(),line:self.line,msg:message.clone()};
  if !self.out.lookup_diags.contains(&diagnostic){if !self.source.budget().row(&mut self.out.lookup_diags){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"lookup diagnostic row admission refused")))}self.out.lookup_diags.push(diagnostic);}
  self.diag_at(rel,rule,format_args!("{}",message))
 }
 fn lookup_read(&mut self,rel:&str,root:&Root,read:&mut Read)->Result<bool,Failure>{
  let Root::Lookup(binding)=root else{return Ok(true)};
  if !read.hops.is_empty(){self.lookup_diag_at(rel,"dynamic_read",format_args!("nested relations after a lookup need their own declared provider"))?;return Ok(false)}
  let facts=self.directives.facts;
  if read.kind==ReadKind::Var&&!(facts.is_tracked(self.source,&read.owner,&read.var)?||facts.is_stat(self.source,&read.owner,&read.var)?||facts.is_relation(self.source,&read.owner,&read.var)?||facts.is_derived(self.source,&read.owner,&read.var)?||self.source.variable(&read.owner,&read.var)?.is_some_and(|v|v.is_const)){
   self.lookup_diag_at(rel,"dynamic_read",format_args!("lookup result {}.{} is not tracked or a declared read producer",read.owner,read.var))?;return Ok(false)
  }
  self.reserve(lookup_bytes(binding).and_then(|n|n.checked_add(read.var.len())).and_then(|n|n.checked_mul(64)).and_then(|n|n.checked_add(4096)))?;
  let lookup=LookupRead{binding:binding.as_ref().clone(),field:std::mem::take(&mut read.var)};
  read.var=lookup.key();read.root="holder".to_owned();read.owner.clear();read.kind=ReadKind::Lookup(Box::new(lookup));Ok(true)
 }
 fn internal_read(&self,rel:&str,owner:&str,name:&str)->Result<bool,Failure>{
  if !crate::reactive_read_facts::framework_file(rel){return Ok(false)}
  if matches!(name,"contents"|"overlays"|"underlays"){return Ok(true)}
  Ok(self.source.variable(owner,name)?.is_some_and(|v|v.file.as_deref().is_some_and(crate::reactive_read_facts::framework_file)))
 }
 fn record_read(&mut self,rel:&str,root:&Root,mut read:Read)->Result<(),Failure>{
  if !self.lookup_read(rel,root,&mut read)?{return Ok(())}
  if self.mute!=0{return Ok(())}
  self.reserve(read.root.len().checked_add(read.owner.len()).and_then(|n|n.checked_add(read.var.len())).and_then(|n|n.checked_add(rel.len())).and_then(|n|n.checked_add(read.hops.iter().map(String::len).sum())).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(4096)))?;
  if self.closed&&read.kind==ReadKind::Var{if self.internal_read(rel,&read.owner,&read.var)?{if !self.out.reads.contains(&read){self.out.internal.insert(read.clone());}}else{self.out.internal.remove(&read);}}
  if !self.out.sites.contains_key(&read){self.out.sites.insert(read.clone(),(rel.to_owned(),self.line));}self.out.reads.insert(read);Ok(())
 }
 fn apply_summary(&mut self,owner:&str,name:&str,summary:&crate::reactive_annotations_policy::ProcSummary,this:&Value,bind:&[Value])->Result<(),Failure>{
  let entity=if owner=="/"{bind.iter().find(|v|v.tracked())}else{Some(this)};let Some(entity)=entity else{return Ok(())};
  self.reserve(self.active_rel.len().checked_add(entity.ty.as_ref().map_or(owner.len(),String::len)).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(1024)))?;
  let rel=self.active_rel.clone();let ty=entity.ty.as_deref().unwrap_or(owner);
  if entity.tracked(){for var in &summary.reads{
   self.tick()?;let declaring=self.source.variable(ty,var)?.map(|v|v.owner).unwrap_or(ty);
   self.reserve(entity.root_width().and_then(|n|n.checked_add(declaring.len())).and_then(|n|n.checked_add(var.len())).and_then(|n|n.checked_add(entity.hops.iter().map(String::len).sum())).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(4096)))?;
   let read=Read{root:entity.root_name().to_owned(),hops:entity.hops.clone(),var:var.clone(),owner:declaring.to_owned(),kind:ReadKind::Var,hop_ok:entity.hop_ok};self.record_read(&rel,&entity.root,read)?;
  }}
  for var in &summary.writes{
   self.tick()?;self.reserve(var.len().checked_add(ty.len()).and_then(|n|n.checked_add(name.len())).and_then(|n|n.checked_add(rel.len())).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(1024)))?;
   if !self.source.budget().row(&mut self.out.effects){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reactive summary effect row refused")))}
   self.out.effects.push(crate::reactive_read_facts::Effect{kind:"assign",name:var.clone(),owner:ty.to_owned(),proc:name.to_owned(),rel:rel.clone(),line:self.line});
  }
  Ok(())
 }
 fn add(&mut self,fr:&Frame<'a,'_>,v:&Value,owner:&str,name:&str,at:usize)->Result<(),Failure>{
  self.reserve(owner.len().checked_add(name.len()).and_then(|n|n.checked_add(v.hops.iter().map(String::len).sum())).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(4096)))?;
  let mut read=Read{root:v.root_name().to_owned(),hops:v.hops.clone(),var:name.to_owned(),owner:owner.to_owned(),kind:ReadKind::Var,hop_ok:v.hop_ok};
  self.record_read(&fr.rel,&v.root,read)
 }
 fn pseudo_hop(&mut self,fr:&Frame<'a,'_>,mut value:Value,kind:&str)->Result<Value,Failure>{
  let base=if kind=="area"{"/area"}else{"/turf"};
  if let Some(ty)=&value.ty{if self.source.is_subtype(ty,base)?{return Ok(value)}}
  self.reserve(value.hops.iter().try_fold(base.len()+kind.len(),|n,s|n.checked_add(s.len())).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(4096)))?;
  if kind=="area"&&value.hops.last().is_some_and(|h|h=="turf"){value.hops.pop();}
  self.add(fr,&value,"/atom",kind,0)?;
  value.hops.push(kind.to_owned());value.ty=Some(base.to_owned());value.list=false;value.blame=None;Ok(value)
 }
 fn collect_narrowing(&mut self,frame:&mut Frame<'a,'_>)->Result<(),Failure>{
  let source=self.source;let operation=&mut self.checkpoint;let visits=std::cell::Cell::new(0usize);let narrow=&mut frame.narrow;
  let result=dm_analysis::untyped::try_policy_expressions(frame.body.statement_body().view(),&mut ||{
   (operation)()?;source.require()?;let count=visits.get()+1;visits.set(count);
   if count>512{source.budget().deny();return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reactive narrowing exceeds current borrowed policy traversal work envelope")))}Ok(())
  },&mut |view,_|{
   let ExprKind::Call{callee,args}=&view.original().kind else{return Ok(())};if !matches!(&callee.kind,ExprKind::Ident(name)if name=="istype")||args.len()!=2{return Ok(())}
   let ExprKind::Ident(id)=&strip_groups(&args[0]).kind else{return Ok(())};
   let target=strip_groups(&args[1]);let path=match &target.kind{ExprKind::TypePath(path)=>path,ExprKind::ObjectInitializer{object,..}=>{let ExprKind::TypePath(path)=&object.kind else{return Ok(())};path},_=>return Ok(())};
   source.reserve(id.len().checked_add(path.len()).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(2048)))?;
   let rows=narrow.entry(id.to_owned()).or_default();if !source.budget().row(rows){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reactive narrowing row admission refused")))}rows.push(path.clone());Ok::<_,Failure>(())
  });
  match result{Ok(())=>Ok(()),Err(dm_analysis::untyped::PolicyVisitFailure::Callback(e))=>Err(e),Err(dm_analysis::untyped::PolicyVisitFailure::Unsupported(e))=>Err(e.into())}
 }
 fn narrow_receiver(&mut self,frame:&Frame<'a,'_>,value:&Value)->Result<Option<Vec<String>>,Failure>{
  let Some(ty)=value.ty.as_deref()else{return Ok(None)};let source=self.source;let operation=&mut self.checkpoint;
  let mut admit=|out:&mut Vec<String>,candidate:&str|{source.reserve(candidate.len().checked_mul(4).and_then(|n|n.checked_add(256)))?;if !source.budget().row(out){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reactive narrowing candidate admission refused")))}Ok(())};
  crate::reactive_read_facts::try_narrow_candidates(&frame.narrow,ty,|a,b|{(operation)()?;source.require()?;source.is_subtype(a,b).map_err(Failure::from)},Some(&mut admit))
 }
 fn global_internal(&self,fr:&Frame<'a,'_>,var:&str,ty:&str,decl_file:Option<&str>)->Result<bool,Failure>{
  if self.source.is_subtype(ty,"/datum/shared_cache")?{return Ok(true)}
  for prefix in ["_scs_","_sch_"]{if let Some(cache)=var.strip_prefix(prefix){
   self.reserve(cache.len().checked_mul(4).and_then(|n|n.checked_add(256)))?;
   if self.source.variable("/",&format!("_sc_{cache}"))?.is_some_and(|v|v.declared=="/datum/shared_cache"){return Ok(true)}
  }}
  if fr.rel=="code/engine/time/handles.dm"{return Ok(true)}
  Ok(crate::reactive_read_facts::framework_file(&fr.rel)&&decl_file.is_some_and(crate::reactive_read_facts::framework_file))
 }
 fn global_ident(&mut self,fr:&Frame<'a,'_>,name:&str)->Result<Option<Value>,Failure>{
  if !self.closed||matches!(name,"world"|"usr"|"src"|"args"|"vars"|"global"|"null"|"client"|"."|".."){return Ok(None)}
  if let Some(ty)=&fr.this.ty{if self.source.variable(ty,name)?.is_some_and(|v|v.owner!="/"){return Ok(None)}}
  let Some(variable)=self.source.variable("/",name)?else{return Ok(None)};if variable.owner!="/"{return Ok(None)}
  let globals=self.directives.globals.ok_or("native global write/boot classifier is not yet issued")?;
  if name!="GLOB"&&self.mute==0&&!variable.is_const&&!globals.constant_after_init(name)?&&!self.global_internal(fr,name,&variable.declared,variable.file.as_deref())?{self.diag(fr,"untracked_global",format_args!("{}",name))?;}
  let object=is_object(&variable.declared);let ty=(!variable.declared.is_empty()).then_some(variable.declared);
  if object{self.reserve(name.len().checked_mul(4).and_then(|n|n.checked_add(256)))?;Ok(Some(Value{ty,root:Root::Global(name.to_owned()),hops:Vec::new(),hop_ok:true,list:false,blame:None}))}else{Ok(Some(Value::local(ty)))}
 }
 fn global_field(&mut self,fr:&Frame<'a,'_>,value:Value,path:&str,name:&str)->Result<Value,Failure>{
  let Some(ty)=value.ty.as_deref()else{return Ok(Value::local(None))};let Some(variable)=self.source.variable(ty,name)?else{return Ok(Value::local(None))};
  let globals=self.directives.globals.ok_or("native global write/boot classifier is not yet issued")?;
  self.reserve(path.len().checked_add(name.len()).and_then(|n|n.checked_add(ty.len())).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(2048)))?;let child=format!("{path}.{name}");let is_glob=path=="GLOB";
  if !is_glob&&self.source.is_subtype(ty,"/datum/system")?&&self.directives.facts.is_tracked(self.source,variable.owner,name)?{
   let system=ty.trim_start_matches("/datum/system/").split('/').next().unwrap_or("");
   let read=Read{root:format!("system:{system}"),hops:Vec::new(),var:name.to_owned(),owner:ty.to_owned(),kind:ReadKind::System,hop_ok:true};self.record_read(&fr.rel,&Root::Local,read)?;
  }else if self.mute==0{
   let constant=variable.is_const||if is_glob{globals.constant_after_init(name)?}else{!globals.is_written_on(self.source,ty,name)?||(globals.field_constant_after_init(name)?&&!self.directives.facts.is_relation(self.source,ty,name)?)};
   if !constant&&!self.global_internal(fr,name,if is_glob{&variable.declared}else{ty},variable.file.as_deref())?{self.diag(fr,"untracked_global",format_args!("{}",child))?;}
  }
  let object=is_object(&variable.declared);let declared=(!variable.declared.is_empty()).then_some(variable.declared);
  if object&&child.matches('.').count()<MAX_HOPS{Ok(Value{ty:declared,root:Root::Global(child),hops:Vec::new(),hop_ok:true,list:false,blame:None})}else{Ok(Value::local(declared))}
 }
 fn field(&mut self,fr:&mut Frame<'a,'_>,value:Value,name:&str,at:usize)->Result<Value,Failure>{
  self.tick()?;
  if let Root::Global(path)=&value.root{self.reserve(path.len().checked_mul(4).and_then(|n|n.checked_add(128)))?;let path=path.clone();return self.global_field(fr,value,&path,name)}
  if name=="vars"&&value.tracked(){self.diag(fr,"dynamic_read",format_args!("vars[] reads are not allowed in a handler"))?;return Ok(Value::local(None));}
  let Some(ty)=value.ty.as_deref() else{return Ok(Value::local(None))};
  if name=="len"&&value.list{return Ok(Value::local(None));}
  if value.root==Root::Act{
   self.reserve(name.len().checked_mul(8).and_then(|n|n.checked_add(1024)))?;
   if !self.out.ctx_fields.contains_key(name){self.out.ctx_fields.insert(name.to_owned(),self.source.site(fr.ordinal,at)?);}
   let Some(variable)=self.source.variable(ty,name)?else{return Ok(Value::local(None))};
   let declared=(!variable.declared.is_empty()).then_some(variable.declared);
   let root=if name=="holder"{Root::Holder}else if declared.as_deref().is_some_and(is_object){Root::Context(name.to_owned())}else{Root::Scalar(LookupArgument::Path{root:"context".to_owned(),path:vec![name.to_owned()]})};
   return Ok(Value{ty:declared,root,hops:Vec::new(),hop_ok:true,list:false,blame:None});
  }
  if name=="loc"&&value.tracked()&&self.source.is_subtype(ty,"/turf")?{return self.pseudo_hop(fr,value,"area")}
  let mut resolved=self.source.variable(ty,name)?;let mut narrowed=None;
  if resolved.is_none(){if let Some(candidates)=self.narrow_receiver(fr,&value)?{for candidate in candidates{if let Some(variable)=self.source.variable(&candidate,name)?{resolved=Some(variable);narrowed=Some(candidate);break}}}}
  let Some(variable)=resolved else{
   // Unknown-field diagnostics require exact original source/callable absence;
   // do not quietly turn a tracked unresolved receiver into an empty result.
   if value.tracked()&&self.source.is_subtype(ty,ty)?&&matches!(self.source.callable(ty,name)?,SelectedCallable::Missing)&&!crate::reactive_read_facts::is_builtin_name(name){if matches!(value.root,Root::Lookup(_)){self.lookup_diag(fr,"unknown_field",format_args!("{} has no var \x60{}\x60",ty,name))?;}else{self.diag(fr,"unknown_field",format_args!("{} has no var \x60{}\x60",ty,name))?;}}
   return Ok(Value::local(None));
  };
  let ty_used=narrowed.as_deref().unwrap_or(ty);
  let declared=(!variable.declared.is_empty()).then_some(variable.declared);
  if !value.tracked(){return Ok(Value::local(declared));}
  if variable.owner=="/"{return Ok(Value::local(declared));}
  if matches!(name,"x"|"y"|"z")&&value.hops.is_empty()&&value.root==Root::Holder&&self.source.is_subtype(ty_used,"/turf")?{return Ok(Value::local(declared));}
  let owner=if variable.owner!=ty_used&&!self.directives.facts.is_tracked(self.source,variable.owner,name)?&&self.directives.facts.is_tracked(self.source,ty_used,name)?{ty_used}else{variable.owner};
  // Existing closed-read policy includes static fields too (old `!is_static||true`).
  self.add(fr,&value,owner,name,at)?;
  if !value.hop_ok||value.hops.len()>=MAX_HOPS{
   if let Some(message)=&value.blame{if !matches!(name,"type"|"parent_type")&&!crate::reactive_read_facts::framework_file(&fr.rel)&&self.mute==0{self.diag(fr,"hop_not_relation",format_args!("{}",message))?;}}
   return Ok(Value::local(declared));
  }
  let Some(declared)=declared else{return Ok(Value::local(None))};
  if is_object(&declared)||is_list(&declared){
   // A flyweight or pseudo loc/turf/area hop needs the original hierarchy
   // classifier before extension. Never guess it from a path prefix.
   let relation=self.directives.facts.is_relation(self.source,ty_used,name)?||self.directives.facts.is_relation(self.source,owner,name)?||name=="loc"&&(self.source.is_subtype(ty_used,"/atom")?||self.source.is_subtype(owner,"/atom")?)||matches!(name,"turf"|"area");
   if is_object(&declared)&&!relation{
    for flyweight in crate::raw_ownership_policy::FLYWEIGHT_TYPES{if self.source.is_subtype(&declared,flyweight)?{return Ok(Value::local(Some(declared)))}}
   }
   self.reserve(name.len().checked_add(declared.len()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(1024)))?;
   let mut blame=value.blame;
   if !relation&&is_object(&declared)&&self.mute==0&&blame.is_none()&&!(self.closed&&self.internal_read(&fr.rel,owner,name)?){
    let mut message=String::new();if !self.source.budget().append_fmt(&mut message,format_args!("hop through \x60{}\x60 ({}) which is not a declared relation or another hop kind",name,owner)){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reactive hop diagnostic admission refused")))}blame=Some(message);
   }
   let mut hops=value.hops;hops.push(name.to_owned());
   return Ok(Value{list:is_list(&declared),ty:Some(declared),root:value.root,hops,hop_ok:value.hop_ok&&relation,blame});
  }
  if matches!(value.root,Root::Holder|Root::Context(_))&&value.hop_ok&&(self.directives.facts.is_tracked(self.source,owner,name)?||variable.is_const){
   self.reserve(value.hops.iter().try_fold(name.len(),|n,s|n.checked_add(s.len())).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(1024)))?;
   let root=value.root_name().to_owned();let mut path=value.hops;path.push(name.to_owned());
   return Ok(Value{ty:Some(declared),root:Root::Scalar(LookupArgument::Path{root,path}),hops:Vec::new(),hop_ok:true,list:false,blame:None});
  }
  Ok(Value::local(Some(declared)))
 }
 fn ident(&mut self,fr:&mut Frame<'a,'_>,name:&str,at:usize)->Result<Value,Failure>{
  if name=="src"{return self.value_copy(&fr.this);}
  if name=="global"{return Ok(Value::local(None))}
  if let Some(v)=fr.locals.get(name){return self.value_copy(v);}
  if matches!(name,"."|".."){return Ok(Value::local(None));}
  if name=="global"{return Ok(Value::local(None))}
  if name=="vars"{self.diag(fr,"dynamic_read",format_args!("vars[] reads are not allowed in a handler"))?;return Ok(Value::local(None))}
  if let Some(value)=self.global_ident(fr,name)?{return Ok(value)}
  // A current source member can shadow a global; whole-source/global absence
  // still needs the original global classifier before this producer activates.
  let this=self.value_copy(&fr.this)?;self.field(fr,this,name,at)
 }
 fn literal_scalar(&self,raw:&str)->Result<Option<LookupArgument>,Failure>{
  if raw=="null"{self.reserve(Some(128))?;return Ok(Some(LookupArgument::Literal("null".to_owned())))}
  if !raw.as_bytes().first().is_some_and(|b|b.is_ascii_digit()||*b==b'.'){return Ok(None)}
  self.reserve(raw.len().checked_mul(8).and_then(|n|n.checked_add(1024)))?;
  let literal=match dm_syntax::numeric_form::numeric_form(raw).map_err(Failure::Unsupported)?{
   dm_syntax::numeric_form::NumericForm::Integer(value)=>value.to_string(),
   dm_syntax::numeric_form::NumericForm::Float=>{
    let clean:String=raw.chars().filter(|c|*c!='_').collect();
    let number=if clean.ends_with("#INF"){f32::INFINITY}else if clean.ends_with("#IND"){f32::NAN}else{clean.parse::<f32>().map_err(|_|Failure::Unsupported("issued numeric spelling has no original float projection".into()))?};number.to_string()
   }
  };
  Ok(Some(LookupArgument::Literal(literal)))
 }
 fn eval(&mut self,fr:&mut Frame<'a,'_>,e:&Expr)->Result<Value,Failure>{
  self.tick()?;
  if self.depth>=MAX_EXPRESSION_DEPTH{return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reactive expression work stack exceeds admitted operation")));}
  self.depth+=1;let result=self.eval_inner(fr,e);self.depth-=1;result
 }
 fn at(&self,span:Span)->Result<usize,Failure>{span.start.checked_add(self.offset).ok_or_else(||Failure::Unsupported("reactive projected source span overflow".into()))}
 fn eval_inner(&mut self,fr:&mut Frame<'a,'_>,e:&Expr)->Result<Value,Failure>{
  match &e.kind{
   ExprKind::Ident(name)=>{self.line=self.source.line_at(self.at(e.span)?)?;self.ident(fr,name,self.at(e.span)?)},
   ExprKind::Group(value)=>self.eval(fr,value),
   ExprKind::Literal(value)=>{
    self.line=self.source.line_at(self.at(e.span)?)?;
    // The actual demanded Kind4 body completed this cache before publication.
    // Borrow ONLY already-issued children: no parts()/standalone parser here.
    match value.retained_parts(){
     Some(Ok(Some(parts)))=>for child in &parts.expressions{self.eval(fr,child)?;},
     Some(Err(_))=>return Err("reactive interpolation has a deferred original syntax error".into()),
     Some(Ok(None))|None=>(),
    }
    if let Some(scalar)=self.literal_scalar(value.as_str())?{return Ok(Value{ty:None,root:Root::Scalar(scalar),hops:Vec::new(),hop_ok:true,list:false,blame:None})}
    Ok(Value::local(None))
   }
   ExprKind::TypeFilter{value,..}=>{self.eval(fr,value)?;Ok(Value::local(None))},
   ExprKind::ObjectInitializer{..}=>{self.line=self.source.line_at(self.at(e.span)?)?;Ok(Value::local(None))},
   ExprKind::TypePath(_)=>{self.line=self.source.line_at(self.at(e.span)?)?;Ok(Value::local(None))},
   ExprKind::Member{object,selector,..}|ExprKind::SafeMember{object,selector,..}=>{let v=self.eval(fr,object)?;self.field(fr,v,selector,self.at(e.span)?)},
   ExprKind::StaticMember{object,..}=>{self.eval(fr,object)?;Ok(Value::local(None))}, // original StaticField/ProcReference do not follow
   ExprKind::Unary{op,value}=>{if op=="new"{self.line=self.source.line_at(self.at(e.span)?)?;if let ExprKind::Call{args,..}=&value.kind{for arg in args{self.eval(fr,arg)?;}}return Ok(Value::local(None))}let value=self.eval(fr,value)?;if op=="-"{if let Root::Scalar(LookupArgument::Literal(number))=&value.root{if number!="null"{self.reserve(number.len().checked_mul(4).and_then(|n|n.checked_add(128)))?;return Ok(Value{ty:None,root:Root::Scalar(LookupArgument::Literal(format!("-{number}"))),hops:Vec::new(),hop_ok:true,list:false,blame:None})}}}Ok(Value::local(None))},
   ExprKind::Binary{op,lhs,rhs} if assignment(op)=>{let rv=self.eval(fr,rhs)?;self.assign(fr,lhs,op,&rv)?;Ok(rv)},
   ExprKind::Binary{lhs,rhs,..}=>{self.eval(fr,lhs)?;self.eval(fr,rhs)?;Ok(Value::local(None))},
   ExprKind::Conditional{condition,then_value,else_value}=>{
    self.eval(fr,condition)?;let a=self.eval(fr,then_value)?;let b=self.eval(fr,else_value)?;
    if a.tracked()&&b.tracked()&&a.root==b.root&&a.hops==b.hops&&a.ty==b.ty{Ok(a)}else{Ok(Value::local(None))}
   }
   ExprKind::Index{object,index}|ExprKind::SafeIndex{object,index}=>{
    let mut value=self.eval(fr,object)?;self.eval(fr,index)?;
    if value.tracked()&&value.list{if let Some(hop)=value.hops.last_mut(){self.reserve(hop.len().checked_add(128))?;if !hop.ends_with("[]"){hop.push_str("[]");}}value.ty=None;value.list=false;Ok(value)}else{Ok(Value::local(None))}
   }
   ExprKind::Call{callee,args}=>self.call(fr,callee,args,e.span),

  }
 }
 fn effect(&mut self,fr:&Frame<'a,'_>,kind:&'static str,name:&str,owner:&str,line:u32)->Result<(),Failure>{
  self.reserve(name.len().checked_add(owner.len()).and_then(|n|n.checked_add(fr.name.len())).and_then(|n|n.checked_add(fr.rel.len())).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(1024)))?;
  if !self.source.budget().row(&mut self.out.effects){return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reactive effect row refused")))}
  self.out.effects.push(crate::reactive_read_facts::Effect{kind,name:name.to_owned(),owner:owner.to_owned(),proc:fr.name.to_owned(),rel:fr.rel.clone(),line});Ok(())
 }
 fn note_call(&mut self,fr:&Frame<'a,'_>,name:&str,receiver:&Value)->Result<(),Failure>{
  if !self.closed&&(crate::reactive_read_facts::IMPURE_CALLS.contains(&name)||crate::reactive_read_facts::MESSAGE_CALLS.contains(&name)||name.starts_with("rel_")||name.starts_with("set_")){
   self.effect(fr,"call",name,receiver.ty.as_deref().unwrap_or(""),self.line)?;
  }Ok(())
 }
 fn assign(&mut self,fr:&mut Frame<'a,'_>,lhs:&Expr,op:&str,rv:&Value)->Result<(),Failure>{
  if let ExprKind::Ident(name)=&lhs.kind{
   if name=="."&&op=="="{let returned=self.value_copy(rv)?;fr.note_return(returned);let value=self.value_copy(rv)?;return self.bind(fr,name,value);}
   if let Some(previous)=fr.locals.get(name){
    let declared=self.value_copy(previous)?.ty;if op!="="{self.eval(fr,lhs)?;}
    let mut value=self.value_copy(rv)?;if value.ty.is_none(){value.ty=declared;}return self.bind(fr,name,value);
   }
   if op!="="{self.eval(fr,lhs)?;}if !self.closed{self.effect(fr,"assign",name,fr.this.ty.as_deref().unwrap_or(""),self.source.line_at(self.at(lhs.span)?)?)?;}return Ok(());
  }
  if let ExprKind::Member{object,selector,..}|ExprKind::SafeMember{object,selector,..}=&lhs.kind{
   let receiver=self.eval(fr,object)?;if op!="="{let copied=self.value_copy(&receiver)?;self.field(fr,copied,selector,self.at(lhs.span)?)?;}if !self.closed{self.effect(fr,"assign",selector,receiver.ty.as_deref().unwrap_or(""),self.source.line_at(self.at(lhs.span)?)?)?;}return Ok(());
  }
  self.eval(fr,lhs)?;Ok(())
 }
 fn accessor(&mut self,fr:&Frame<'a,'_>,value:&Value,key:&str,via:Option<&str>)->Result<(),Failure>{
  self.reserve(value.root_width().and_then(|n|n.checked_add(key.len())).and_then(|n|n.checked_add(via.map_or(0,str::len))).and_then(|n|n.checked_add(value.hops.iter().map(String::len).sum())).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(4096)))?;
  let mut hops=value.hops.clone();if let Some(via)=via{hops.push(via.to_owned())}
  let mut read=Read{root:value.root_name().to_owned(),hops,var:key.to_owned(),owner:String::new(),kind:ReadKind::Accessor,hop_ok:value.hop_ok};
  self.record_read(&fr.rel,&value.root,read)
 }
 fn run_virtual(&mut self,callee:ReadCallable<'a>,receiver:&str,name:&str,this:Value,args:&[Value])->Result<Option<Value>,Failure>{
  let source=self.source;let declaring=callee.owner;
  let primary=self.value_copy(&this)?;let result=self.run_proc(callee.ordinal,primary,args,false,false)?;
  if !self.closed||!this.tracked(){return Ok(result)}
  let shared=std::cell::RefCell::new(self);
  source.visit_overrides(receiver,name,||shared.borrow_mut().tick(),|overridden|{
   if overridden.owner==declaring{return Ok(())}
   let mut walk=shared.borrow_mut();let mut value=walk.value_copy(&this)?;
   walk.reserve(overridden.owner.len().checked_mul(4).and_then(|n|n.checked_add(512)))?;value.ty=Some(overridden.owner.to_owned());
   // Per-override diagnostic provenance is added alongside final diagnostic
   // producer below; only the primary tracked return escapes this union.
   walk.override_depth+=1;let result=walk.run_proc(overridden.ordinal,value,args,false,false);walk.override_depth-=1;result?;Ok::<_,Failure>(())
  })?;
  Ok(result)
 }
 fn method(&mut self,fr:&mut Frame<'a,'_>,value:Value,name:&str,args:&[Expr])->Result<Value,Failure>{
  self.reserve(args.len().checked_mul(std::mem::size_of::<Value>()*4).and_then(|n|n.checked_add(1024)))?;
  let mut argv=Vec::new();argv.try_reserve_exact(args.len()).map_err(|e|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,e)))?;
  for arg in args{argv.push(self.eval(fr,arg)?)}
  self.note_call(fr,name,&value)?;
  if self.closed&&crate::reactive_read_facts::effect_call(name)||value.root==Root::Act{return Ok(Value::local(None))}
  let Some(ty)=value.ty.as_deref()else{return Ok(Value::local(None))};
  if ty=="/datum/look"{
   if let Some((key,_))=self.directives.facts.reads_as(self.source,ty,name)?{
    let holder=argv.first().filter(|v|v.tracked()).unwrap_or(&fr.this);if holder.tracked(){self.accessor(fr,holder,key,None)?;}
   }
   return Ok(Value::local(None))
  }
  let selected=self.source.callable(ty,name)?;
  let SelectedCallable::Source(callee)=selected else{
   if matches!(selected,SelectedCallable::Missing)&&value.tracked()&&self.source.is_subtype(ty,ty)?&&!crate::reactive_read_facts::is_builtin_name(name)&&!self.source.is_subtype(ty,"/datum/act")?{self.diag(fr,"unknown_call",format_args!("{} has no proc \x60{}\x60",ty,name))?;}
   return Ok(Value::local(None))
  };
  if callee.owner=="/"{return Ok(Value::local(None))}
  if self.closed&&value.tracked()&&value.hops.last().is_some_and(|hop|hop=="loc")&&matches!(ty,"/atom"|"/atom/movable"|"/datum"){
   if self.mute==0&&!crate::reactive_read_facts::framework_file(&fr.rel){self.diag(fr,"hop_not_relation",format_args!("\x60{}()\x60 is called on a container of unbounded type ({})",name,ty))?;}
   return Ok(Value::local(None))
  }
  if matches!(value.root,Root::Global(_)){if self.closed{self.run_proc(callee.ordinal,value,&argv,false,false)?;}return Ok(Value::local(None))}
  if !value.tracked()||!value.hop_ok{
   if let Some(message)=&value.blame{if value.tracked()&&!crate::reactive_read_facts::framework_file(&fr.rel)&&self.mute==0{self.diag(fr,"hop_not_relation",format_args!("{}",message))?;}}
   return Ok(Value::local(None))
  }

  if let Some((key,via))=self.directives.facts.reads_as(self.source,ty,name)?{self.accessor(fr,&value,key,via.as_deref())?;return Ok(Value::local(None))}
  self.reserve(ty.len().checked_mul(4).and_then(|n|n.checked_add(512)))?;let receiver=ty.to_owned();
  Ok(self.run_virtual(callee,&receiver,name,value,&argv)?.unwrap_or_else(||Value::local(None)))
 }
 fn reporting<T>(&mut self,line:u32,operation:impl FnOnce(&mut Self)->Result<T,Failure>)->Result<T,Failure>{let previous=self.line;self.line=line;let result=operation(self);self.line=previous;result}
 fn lookup_diag_at_line(&mut self,fr:&Frame<'a,'_>,line:u32,rule:&'static str,args:std::fmt::Arguments<'_>)->Result<(),Failure>{self.reporting(line,|walk|walk.lookup_diag(fr,rule,args))}
 fn call(&mut self,fr:&mut Frame<'a,'_>,callee:&Expr,args:&[Expr],at:Span)->Result<Value,Failure>{
  if let ExprKind::Ident(name)=&callee.kind{
   let call_line=self.source.line_at(self.at(callee.span)?)?;self.line=call_line;
   if matches!(name.as_str(),"nameof"|"PROC_REF"|"TYPE_PROC_REF"|"GLOBAL_PROC_REF"|"initial"){return Ok(Value::local(None));}
   if matches!(name.as_str(),"list"|"."|"new"|"input"|"locate"|"pick"){
    for arg in args{self.eval(fr,arg)?;}return Ok(Value::local(None));
   }
   if name==".."{
    self.reserve(args.len().checked_mul(std::mem::size_of::<Value>()*4).and_then(|n|n.checked_add(1024)))?;
    let mut values=Vec::new();values.try_reserve_exact(args.len()).map_err(|actual|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual)))?;
    for arg in args{values.push(self.eval(fr,arg)?);}
    let Some(parent)=self.source.parent_callable(fr.ordinal)? else{return Ok(Value::local(None))};
    if values.is_empty(){
     let parameters=fr.body.source_parameters()?;let entries=parameters.entries()?;
     self.reserve(entries.len().checked_mul(std::mem::size_of::<Value>()*4).and_then(|n|n.checked_add(1024)))?;
     values.try_reserve_exact(entries.len()).map_err(|actual|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual)))?;
     for parameter in entries{let name=parameters.name(parameter)?;values.push(match fr.locals.get(name){Some(value)=>self.value_copy(value)?,None=>Value::local(None)});}
    }
    let this=self.value_copy(&fr.this)?;return Ok(self.run_proc(parent.ordinal,this,&values,false,false)?.unwrap_or_else(||Value::local(None)));
   }
   if name=="read_once"{
    self.reserve(Some(512))?;self.out.sampled.insert((fr.rel.clone(),self.line));self.mute+=1;
    let result=args.iter().try_for_each(|a|self.eval(fr,a).map(|_|()));self.mute-=1;result?;return Ok(Value::local(None));
   }
   self.reserve(args.len().checked_mul(std::mem::size_of::<Value>()*4).and_then(|n|n.checked_add(1024)))?;
   let mut argv=Vec::new();argv.try_reserve_exact(args.len()).map_err(|e|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,e)))?;
   for arg in args{argv.push(self.eval(fr,arg)?)}
   self.reporting(call_line,|walk|walk.note_call(fr,name,&fr.this))?;
   if self.closed&&crate::reactive_read_facts::effect_call(name){return Ok(Value::local(None))}
   let facts=self.directives.facts;
   if let Some(declaration)=facts.annotations.lookups.get(name){
    let Some(value)=argv.get(declaration.argument)else{self.lookup_diag_at_line(fr,call_line,"dynamic_read",format_args!("lookup {} argument is not a literal or a tracked root/relation field; declare a provider for getter/index expressions",name))?;return Ok(Value::local(None))};
    let Root::Scalar(argument)=&value.root else{self.lookup_diag_at_line(fr,call_line,"dynamic_read",format_args!("lookup {} argument is not a literal or a tracked root/relation field; declare a provider for getter/index expressions",name))?;return Ok(Value::local(None))};
    if matches!(argument,LookupArgument::Path{root,..}if root=="context"){self.lookup_diag_at_line(fr,call_line,"dynamic_read",format_args!("lookup {} uses a scalar act-context argument with no entity binding lifetime",name))?;return Ok(Value::local(None))}
    for provider in [declaration.registry.as_str(),declaration.identity_key.as_str(),name.as_str()]{
     if matches!(self.source.callable("/",provider)?,SelectedCallable::Missing){self.lookup_diag_at_line(fr,call_line,"dynamic_read",format_args!("lookup {} declares missing global provider {}",name,provider))?;return Ok(Value::local(None))}
    }
    self.reserve(value.root_width().and_then(|n|n.checked_add(declaration.registry.len())).and_then(|n|n.checked_add(declaration.identity_key.len())).and_then(|n|n.checked_add(declaration.result.len())).and_then(|n|n.checked_add(name.len())).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(2048)))?;
    let binding=LookupBound{registry:declaration.registry.clone(),identity_key:declaration.identity_key.clone(),lookup:name.clone(),argument:argument.clone()};
    return Ok(Value{ty:Some(declaration.result.clone()),root:Root::Lookup(Box::new(binding)),hops:Vec::new(),hop_ok:true,list:false,blame:None})
   }
   if name=="native"{
    if let Some(literal)=args.first().and_then(original_string_term){
     let mut writer=crate::captured_generator_budget::BudgetedText::new(self.source.budget());
     let emitted=literal.write_pinned_static_text(&mut writer);
     let emitted=match emitted{Ok(value)=>value,Err(_)if self.source.budget().denied()=>return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reactive native key output admission refused"))),Err(error)=>{self.reserve(Some(512))?;return Err(Failure::Unsupported(format!("reactive native key original lexical view unavailable: {error:?}")))}};
     if emitted{
      let key=writer.finish().map_err(|error|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,error)))?;
      self.reserve(fr.this.root_width().and_then(|n|n.checked_add(key.len())).and_then(|n|n.checked_add(fr.this.hops.iter().map(String::len).sum())).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(2048)))?;
      let read=Read{root:fr.this.root_name().to_owned(),hops:fr.this.hops.clone(),var:key,owner:String::new(),kind:ReadKind::Native,hop_ok:true};self.reporting(call_line,|walk|walk.record_read(&fr.rel,&fr.this.root,read))?;
     }
    }
    return Ok(Value::local(None))
   }
   if matches!(name.as_str(),"get_step"|"get_area"){
    let here=name=="get_area"||matches!(args.get(1),Some(Expr{kind:ExprKind::Literal(raw),..})if dm_syntax::numeric_form::numeric_form(raw.as_str())==Ok(dm_syntax::numeric_form::NumericForm::Integer(0)));
    if here{if let Some(value)=argv.first().filter(|v|v.tracked()){let value=self.value_copy(value)?;return self.reporting(call_line,|walk|walk.pseudo_hop(fr,value,if name=="get_area"{"area"}else{"turf"}))}}
    if name=="get_step"{self.reserve(Some(128))?;return Ok(Value::local(Some("/turf".to_owned())))}
   }
   if let Some(key)=facts.annotations.capkey_accessors.get(name){
    if let Some(value)=argv.first().filter(|v|v.tracked()){self.reporting(call_line,|walk|walk.accessor(fr,value,key,None))?;}
    return Ok(Value::local(None))
   }
   if let Some((system,var))=facts.annotations.accessors.get(name){
    self.reserve(system.len().checked_mul(32).and_then(|n|n.checked_add(var.len().checked_mul(8)?)).and_then(|n|n.checked_add(4096)))?;
    let owner=crate::system_accessors_policy::system_types(system).into_iter().find_map(|candidate|match self.source.is_subtype(&candidate,&candidate){Ok(true)=>Some(Ok(candidate)),Ok(false)=>None,Err(error)=>Some(Err(error))}).transpose()?.unwrap_or_default();
    if self.mute==0{
     let read=Read{root:format!("system:{system}"),hops:Vec::new(),var:var.clone(),owner,kind:ReadKind::System,hop_ok:true};
     if !self.out.sites.contains_key(&read){self.out.sites.insert(read.clone(),(fr.rel.clone(),call_line));}self.out.reads.insert(read);
    }
    return Ok(Value::local(None))
   }
   let this=self.value_copy(&fr.this)?;
   if let Some(ty)=this.ty.as_deref(){
    match self.source.callable(ty,name)?{
     SelectedCallable::Builtin=>return Ok(Value::local(None)),
     SelectedCallable::Source(callee)if callee.owner!="/"=>{
      if this.tracked(){
       if let Some((key,via))=facts.reads_as(self.source,ty,name)?{self.reporting(call_line,|walk|walk.accessor(fr,&this,key,via.as_deref()))?;return Ok(Value::local(None))}
       self.reserve(ty.len().checked_mul(4).and_then(|n|n.checked_add(512)))?;let receiver=ty.to_owned();
       return Ok(self.run_virtual(callee,&receiver,name,this,&argv)?.unwrap_or_else(||Value::local(None)))
      }
      if matches!(this.root,Root::Global(_))&&self.closed{self.run_proc(callee.ordinal,this,&argv,false,false)?;}
      return Ok(Value::local(None))
     }
     _=>(),
    }
   }
   let SelectedCallable::Source(global)=self.source.callable("/",name)?else{return Ok(Value::local(None))};
   if self.closed&&self.source.site_line(global.ordinal,1)?.0.starts_with("code/_helpers/logging/"){return Ok(Value::local(None))}
   if let Some((_,summary))=facts.annotations.summaries.iter().find(|((owner,proc),_)|owner=="/"&&proc==name){self.reporting(call_line,|walk|walk.apply_summary("/",name,summary,&Value::local(None),&argv))?;return Ok(Value::local(None))}
   if self.closed&&self.source.site_line(global.ordinal,1)?.0.starts_with("code/__defines/verdigris/"){self.diag_at_line(&fr.rel,call_line,"ffi_call",format_args!("`{}` is a Verdigris FFI call: declare what it reads and writes with PROC_SUMMARY(/proc/{}, ...)",name,name))?;return Ok(Value::local(None))}
   // Actual followed global body owns its original formal projection. Accessor
   // contracts need only selected current metadata names and remain header-only.
   if let Some(params)=facts.annotations.reads_from.get(name){
    if let Some((_,(key,via)))=facts.annotations.reads_as.iter().find(|((owner,proc),_)|owner=="/"&&proc==name){
     let tree=self.source.inputs().archive().tree();let metadata=tree.member(global.member).and_then(|m|m.metadata.procedure.as_ref()).ok_or("native global original signature unavailable")?;
     for(i,parameter)in metadata.signature.parameters.iter().enumerate(){
      let parameter=tree.symbols().text(parameter.name).ok_or("native global original formal spelling absent")?;
      if !params.iter().any(|p|p==parameter){continue}
      if let Some(value)=argv.get(i).filter(|v|v.tracked()){self.reporting(call_line,|walk|walk.accessor(fr,value,key,via.as_deref()))?;}
     }
     return Ok(Value::local(None))
    }
    let body=self.source.parse_body(global.ordinal).map_err(|e|match e{dm_tree::frontend::BodySyntaxFailure::Operational(e)=>Failure::Operational(e),dm_tree::frontend::BodySyntaxFailure::Syntax(e)=>Failure::Unsupported(e.message)})?;
    let formals=body.source_parameters()?;self.reserve(formals.entries()?.iter().try_fold(0usize,|n,p|n.checked_add(parameter_bytes(p)?)).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(1024)))?;
    self.reserve(formals.entries()?.len().checked_mul(std::mem::size_of::<Value>()*4).and_then(|n|n.checked_add(1024)))?;
    let mut bind=Vec::new();bind.try_reserve_exact(formals.entries()?.len()).map_err(|e|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,e)))?;
    for(i,parameter)in formals.entries()?.iter().enumerate(){
     let parameter_name=formals.name(parameter)?;
     let value=if params.iter().any(|p|p==parameter_name){match argv.get(i){Some(value)=>self.value_copy(value)?,None=>Value::local(None)}}else{Value::local(formals.type_path(parameter)?)};
     bind.push(value);
    }
    return Ok(self.run_proc(global.ordinal,Value::local(None),&bind,false,false)?.unwrap_or_else(||Value::local(None)))
   }
   if !self.closed{self.diag_at_line(&fr.rel,call_line,"unannotated_global",format_args!("global proc \x60{}\x60 is called without READS_FROM",name))?;return Ok(Value::local(None))}
   // Closed ordinary global calls keep tracked arguments but never propagate
   // the handler's Act context into unannotated helpers.
   self.reserve(argv.len().checked_mul(std::mem::size_of::<Value>()*4).and_then(|n|n.checked_add(1024)))?;
   let mut bind=Vec::new();bind.try_reserve_exact(argv.len()).map_err(|e|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,e)))?;
   for value in &argv{bind.push(if value.root==Root::Act{Value::local(None)}else{self.value_copy(value)?});}
   return Ok(self.run_proc(global.ordinal,Value::local(None),&bind,false,true)?.unwrap_or_else(||Value::local(None)))
  }
  if matches!(callee.kind,ExprKind::StaticMember{..}){self.line=self.source.line_at(self.at(callee.span)?)?;for arg in args{self.eval(fr,arg)?;}return Ok(Value::local(None))}
  if let ExprKind::Call{callee:primitive,args:first}=&callee.kind{
   if matches!(&primitive.kind,ExprKind::Ident(name)if name=="call"){
    let line=self.source.line_at(self.at(callee.span)?)?;self.line=line;for value in first.iter().chain(args){self.eval(fr,value)?;}
    self.diag_at_line(&fr.rel,line,"dynamic_read",format_args!("call() cannot be followed"))?;return Ok(Value::local(None))
   }
  }
  if let ExprKind::Member{object,selector,..}|ExprKind::SafeMember{object,selector,..}=&callee.kind{
   let value=self.eval(fr,object)?;return self.method(fr,value,selector,args)
  }
  Err("original native call shape has no pinned named/method/dynamic-call counterpart".into())
 }

 fn local_binding(&mut self,fr:&mut Frame<'a,'_>,header:Span,binding:&str)->Result<(String,Option<String>),Failure>{
  let locals=fr.body.source_locals()?;let rows=locals.in_span(header)?;
  if let [entry]=rows{
   let name=locals.name(entry)?;self.reserve(name.len().checked_add(locals.type_path_width(entry)?).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(1024)))?;
   return Ok((name.to_owned(),locals.type_path(entry)?));
  }
  if rows.is_empty()&&plain_name(binding){self.reserve(binding.len().checked_mul(4).and_then(|n|n.checked_add(512)))?;return Ok((binding.to_owned(),None));}
  Err("reactive loop binding lacks one exact original declaration or plain source name".into())
 }
 fn iteration(&mut self,fr:&mut Frame<'a,'_>,st:&Statement,control:&ForControl,body:&[Statement])->Result<(),Failure>{
  match control{
   ForControl::Each{binding,iterable}=>{
    let mut value=self.eval(fr,iterable)?;let(name,declared)=self.local_binding(fr,st.header_span,binding)?;
    if value.tracked()&&value.list{
     if let Some(last)=value.hops.last_mut(){self.reserve(last.len().checked_add(128))?;if !last.ends_with("[]"){last.push_str("[]");}}
     value.ty=declared;value.list=false;value.blame=None;
    }else{value=Value::local(declared);}
    self.bind(fr,&name,value)?;
   }
   ForControl::All{declaration}=>{let(name,ty)=self.local_binding(fr,st.header_span,declaration)?;self.bind(fr,&name,Value::local(ty))?;}
   ForControl::Pair{key_binding,value_binding,iterable}=>{
    self.eval(fr,iterable)?;let locals=fr.body.source_locals()?;let rows=locals.in_span(st.header_span)?;
    match rows{
     [] if plain_name(key_binding)&&plain_name(value_binding)=>{self.bind(fr,key_binding,Value::local(None))?;self.bind(fr,value_binding,Value::local(None))?;},
     [key,value]=>{
      let keyname=locals.name(key)?;let valuename=locals.name(value)?;
      self.reserve(locals.type_path_width(key)?.checked_add(keyname.len()).and_then(|n|n.checked_add(valuename.len())).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(2048)))?;
      self.bind(fr,keyname,Value::local(locals.type_path(key)?))?;self.bind(fr,valuename,Value::local(None))?;
     }
     [entry] if plain_name(value_binding)=>{
      let name=locals.name(entry)?;self.reserve(locals.type_path_width(entry)?.checked_add(name.len()).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(1024)))?;
      self.bind(fr,name,Value::local(locals.type_path(entry)?))?;self.bind(fr,value_binding,Value::local(None))?;
     }
     _=>return Err("reactive pair binding lacks exact original key/type and value name".into()),
    }
   }
   ForControl::Range{binding,start,end,step}=>{
    self.eval(fr,start)?;self.eval(fr,end)?;if let Some(step)=step{self.eval(fr,step)?;}
    let(name,_)=self.local_binding(fr,st.header_span,binding)?;self.bind(fr,&name,Value::local(None))?;
   }
   ForControl::RangeImplicitArray{binding,end,step}=>{
    // The pinned synthetic array start evaluates dimensions before end/step.
    let locals=fr.body.source_locals()?;let rows=locals.in_span(st.header_span)?;let[entry]=rows else{return Err("reactive range initializer source declaration missing".into())};
    if let Some(root)=entry.implicit_list_initializer(){for dimension in &root.dimensions{self.eval(fr,dimension)?;}}
    self.eval(fr,end)?;if let Some(step)=step{self.eval(fr,step)?;}
    let(name,_)=self.local_binding(fr,st.header_span,binding)?;self.bind(fr,&name,Value::local(None))?;
   }
   ForControl::CStyle{initializer,condition,step}=>{
    if let Some(initializer)=initializer{match initializer{
     ForInitializer::Expr(e)=>{self.eval(fr,e)?;},
     ForInitializer::Declare{declaration,value}=>{
      let(name,declared)=self.local_binding(fr,st.header_span,declaration)?;
      let mut v=if let Some(value)=value{self.eval(fr,value)?}else{let locals=fr.body.source_locals()?;let rows=locals.in_span(st.header_span)?;if let [entry]=rows{if let Some(initializer)=entry.implicit_list_initializer(){for dimension in &initializer.dimensions{self.eval(fr,dimension)?;}}}Value::local(None)};if declared.is_some(){v.ty=declared;}self.bind(fr,&name,v)?;
     }
    }}
    if let Some(condition)=condition{self.eval(fr,condition)?;}if let Some(step)=step{self.eval(fr,step)?;}
   }
  }
  self.statements(fr,body)
 }
 fn statements(&mut self,fr:&mut Frame<'a,'_>,statements:&[Statement])->Result<(),Failure>{
  self.tick()?;
  if self.block_depth>=MAX_EXPRESSION_DEPTH{return Err(Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"reactive statement work stack exceeds admitted operation")));}
  self.block_depth+=1;let result=self.statements_inner(fr,statements);self.block_depth-=1;result
 }
 fn statements_inner(&mut self,fr:&mut Frame<'a,'_>,statements:&[Statement])->Result<(),Failure>{
  for st in statements{
   self.tick()?;self.line=self.source.line_at(st.header_span.start)?;
   match &st.kind{
    StatementKind::Expression(e)|StatementKind::Call(e)|StatementKind::Throw(e)=>{self.eval(fr,e)?;},
    StatementKind::Assign{target,op,value}=>{let rv=self.eval(fr,value)?;self.assign(fr,target,op,&rv)?;},
    StatementKind::Return(Some(e))=>{let v=self.eval(fr,e)?;fr.note_return(v);},
    StatementKind::Return(None)|StatementKind::Break|StatementKind::Continue|StatementKind::Goto(_)|StatementKind::BreakLabel(_)|StatementKind::ContinueLabel(_)=>(),
    StatementKind::Set{value,..}=>{self.eval(fr,value)?;},
    StatementKind::ProjectedSet{value,..}=>{
     let old=self.offset;self.offset=value.current_offset();let result=self.eval(fr,value.original_expression());self.offset=old;result?;
    }
    StatementKind::Var{value,..}=>{
     let locals=fr.body.source_locals()?;let rows=locals.in_span(st.header_span)?;
     let [entry]=rows else{return Err("native reactive grouped source declaration projection is not yet integrated".into())};
     let name=locals.name(entry)?;self.reserve(locals.type_path_width(entry)?.checked_mul(8).and_then(|n|n.checked_add(1024)))?;
     let declared=locals.type_path(entry)?;
     let mut initial=if let Some(value)=value{self.eval(fr,value)?}else{
      if let Some(initializer)=entry.implicit_list_initializer(){for dim in &initializer.dimensions{self.eval(fr,dim)?;}}
      Value::local(None)
     };
     if declared.is_some(){initial.ty=declared;}self.bind(fr,name,initial)?;
    }
    StatementKind::If{..}=>{
     // Same original multi-arm statement: ALL conditions first, then each
     // branch. An explicit nested `else { if }` stays a separate statement.
     let mut arm=st;
     loop{let StatementKind::If{condition,else_branch,..}=&arm.kind else{unreachable!()};self.eval(fr,condition)?;match next_arm(else_branch){Some(next)=>arm=next,None=>break}}
     let mut arm=st;
     loop{let StatementKind::If{then_branch,else_branch,..}=&arm.kind else{unreachable!()};self.statements(fr,then_branch)?;match next_arm(else_branch){Some(next)=>arm=next,None=>{self.statements(fr,else_branch)?;break}}}
    }
    StatementKind::While{condition,body}|StatementKind::DoWhile{condition,body}=>{self.eval(fr,condition)?;self.statements(fr,body)?;},
    StatementKind::Spawn{delay,body}=>{if let Some(delay)=delay{self.eval(fr,delay)?;}self.statements(fr,body)?;},
    StatementKind::For{control,body}=>self.iteration(fr,st,control,body)?,
    StatementKind::Label{body,..}=>self.statements(fr,body)?,
    StatementKind::Switch{selector,cases,else_branch}=>{
     self.eval(fr,selector)?;
     for case in cases{for choice in &case.alternatives{match choice{dm_syntax::SwitchAlternative::Exact(e)=>{self.eval(fr,e)?;},dm_syntax::SwitchAlternative::Range(a,b)=>{self.eval(fr,a)?;self.eval(fr,b)?;}}}}
     for case in cases{self.statements(fr,&case.body)?;}self.statements(fr,else_branch)?;
    }
    StatementKind::Try{body,catch_body,..}=>{self.statements(fr,body)?;self.statements(fr,catch_body)?;},
    // Exact if-arm-first order, local/loop flow and source ledgers are required
    // before walking controls. A generic preorder visitor is not equivalent.
    StatementKind::Unsupported=>return Err("original native body contains unsupported statement syntax".into()),
   }
  }
  Ok(())
 }
}
fn strip_groups(mut expression:&Expr)->&Expr{while let ExprKind::Group(child)=&expression.kind{expression=child;}expression}
fn original_string_term(mut expression:&Expr)->Option<&dm_syntax::LiteralText>{
 loop{
  if let ExprKind::Literal(value)=&expression.kind{return Some(value)}
  expression=crate::reactive_annotations_native::continuation(expression)?;
 }
}
fn root_bytes(root:&Root)->Option<usize>{match root{Root::Context(s)|Root::Global(s)=>Some(s.len()),Root::Scalar(LookupArgument::Literal(s))=>Some(s.len()),Root::Scalar(LookupArgument::Path{root,path})=>path.iter().try_fold(root.len(),|n,s|n.checked_add(s.len()).and_then(|n|n.checked_add(std::mem::size_of::<String>()))),Root::Lookup(bound)=>lookup_bytes(bound),_=>Some(0)}}
fn memo_bytes(key:&MemoKey)->Option<usize>{key.4.iter().try_fold(key.0.len().checked_add(key.1.len())?.checked_add(root_bytes(&key.2)?)?.checked_add(key.3.as_ref().map_or(0,String::len))?,|n,(root,ty)|n.checked_add(root_bytes(root)?).and_then(|n|n.checked_add(ty.as_ref().map_or(0,String::len))).and_then(|n|n.checked_add(std::mem::size_of::<(Root,Option<String>)>())))}
fn read_bytes(read:&Read)->Option<usize>{let n=read.hops.iter().try_fold(read.root.len().checked_add(read.owner.len())?.checked_add(read.var.len())?,|n,s|n.checked_add(s.len()).and_then(|n|n.checked_add(std::mem::size_of::<String>())))?;if let ReadKind::Lookup(lookup)=&read.kind{n.checked_add(lookup_bytes(&lookup.binding)?).and_then(|n|n.checked_add(lookup.field.len()))}else{Some(n)}}
fn lookup_bytes(bound:&LookupBound)->Option<usize>{
 let base=bound.registry.len().checked_add(bound.identity_key.len())?.checked_add(bound.lookup.len())?;
 match &bound.argument{LookupArgument::Literal(s)=>base.checked_add(s.len()),LookupArgument::Path{root,path}=>path.iter().try_fold(base.checked_add(root.len())?,|n,s|n.checked_add(s.len()).and_then(|n|n.checked_add(std::mem::size_of::<String>())))}
}
fn parameter_bytes(parameter:&dm_syntax::ParameterSyntax)->Option<usize>{
 parameter.type_components().iter().try_fold(5usize,|n,span|n.checked_add(span.end.checked_sub(span.start)?).and_then(|n|n.checked_add(1)))
}
fn plain_name(name:&str)->bool{let mut chars=name.chars();chars.next().is_some_and(|c|c.is_ascii_alphabetic()||c=='_')&&chars.all(|c|c.is_ascii_alphanumeric()||c=='_')}
fn is_list(ty:&str)->bool{ty=="/list"||ty.starts_with("/list/")}
fn is_object(ty:&str)->bool{crate::reactive_read_facts::is_object_type(ty)}
fn assignment(op:&str)->bool{matches!(op,"="|"+="|"-="|"*="|"/="|"%="|"**="|"&="|"|="|"^="|"<<="|">>="|"&&="|"||=")}

fn next_arm(else_branch:&[Statement])->Option<&Statement>{
 let [next]=else_branch else{return None};
 (matches!(&next.kind,StatementKind::If{..})&&next.header_span.start>next.span.start).then_some(next)
}
/// Actual original-output body entry, not yet registered as a generator/query.
/// Every unsupported flow exits the whole operation before any artifact exists.
pub(crate) fn original_output_reads<'a>(source:&ReadSource<'a>,ordinal:usize,directives:Directives<'_>,checkpoint:&mut dyn FnMut()->io::Result<()>)->Result<Reads,Failure>{original_reads(source,ordinal,directives,true,None,checkpoint)}
/// Same interpreter/policy, targeted mode retained for declared lookup purity.
pub(crate) fn original_reads<'a>(source:&ReadSource<'a>,ordinal:usize,directives:Directives<'_>,closed:bool,context_override:Option<&str>,checkpoint:&mut dyn FnMut()->io::Result<()>)->Result<Reads,Failure>{
 checkpoint()?;source.require()?;source.reserve(context_override.map_or(Some(0),|s|s.len().checked_mul(4).and_then(|n|n.checked_add(128))))?;
 let archive=source.inputs().archive();let tree=archive.tree();
 let occurrence=archive.occurrences().get(ordinal).ok_or("reactive original body ordinal absent")?;
 let node=tree.member(occurrence.member).ok_or("reactive original body member absent")?;
 let owner=tree.type_node(node.owner).and_then(|n|tree.symbols().text(n.path)).ok_or("reactive original body owner absent")?;
 let this=Value{ty:Some(owner.to_owned()),root:Root::Holder,hops:Vec::new(),hop_ok:true,list:false,blame:None};
 let mut walk=Walk{source,directives,out:Reads::default(),checkpoint,depth:0,mute:0,offset:0,line:0,block_depth:0,call_depth:0,closed,visited:BTreeSet::new(),context_override:context_override.map(str::to_owned),active_rel:String::new(),override_depth:0,engine_depth:0,diag_ix:BTreeMap::new(),memo:BTreeMap::new(),children:Vec::new(),computing:BTreeSet::new(),merged:BTreeSet::new()};
 walk.run_proc(ordinal,this,&[],true,false)?;
 walk.finish()?;walk.tick()?;Ok(walk.out)
}

/// One native query computation lends the SAME original source and unique memo
/// graph across all requested outputs. This is not another persistent cache.
/// An outer failure discards every partial artifact/result before publication.
pub(crate) fn original_closed_wave<'a,'r>(source:&ReadSource<'a>,directives:Directives<'_>,requests:impl IntoIterator<Item=(&'r str,&'r str,Option<&'r str>)>,checkpoint:&mut dyn FnMut()->io::Result<()>,mut emit:impl FnMut(&str,&str,Option<&str>,Reads)->Result<(),Failure>)->Result<(),Failure>{
 let mut walk=Walk{source,directives,out:Reads::default(),checkpoint,depth:0,mute:0,offset:0,line:0,block_depth:0,call_depth:0,closed:true,visited:BTreeSet::new(),context_override:None,active_rel:String::new(),override_depth:0,engine_depth:0,diag_ix:BTreeMap::new(),memo:BTreeMap::new(),children:Vec::new(),computing:BTreeSet::new(),merged:BTreeSet::new()};
 for(receiver,name,context)in requests{let result=walk.analyze_request(receiver,name,context)?;emit(receiver,name,context,result)?;}
 walk.tick()
}

/// Exact requested receiver entry (including inherited methods).
pub(crate) fn original_request(source:&ReadSource<'_>,directives:Directives<'_>,receiver:&str,procedure:&str,context:Option<&str>,closed:bool,checkpoint:&mut dyn FnMut()->io::Result<()>)->Result<Reads,Failure>{
 let mut walk=Walk{source,directives,out:Reads::default(),checkpoint,depth:0,mute:0,offset:0,line:0,block_depth:0,call_depth:0,closed,visited:BTreeSet::new(),context_override:None,active_rel:String::new(),override_depth:0,engine_depth:0,diag_ix:BTreeMap::new(),memo:BTreeMap::new(),children:Vec::new(),computing:BTreeSet::new(),merged:BTreeSet::new()};
 walk.analyze_request(receiver,procedure,context)
}
