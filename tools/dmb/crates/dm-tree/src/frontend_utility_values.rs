//! Operation-local Original utility VALUE column on the retained native model.
//! No AST/model clone, filesystem read, persistent memo, or source grant.
use super::*;
use dm_preprocess::original_model_value::{self as value,ModelContext,ModelOutcome,ModelValue,ModelMessage};
use dm_syntax::{SettingAdmission,SettingRootLease};
use std::{cell::RefCell,io};
use crate::{MemberId,MemberKind,TypeId,DefinitionMode};
use dm_ir::SymbolId;
use crate::procedure::original_primary_signatures::{grow_funded_rows,allocate_funded_rows};

#[derive(Clone,Copy)]pub enum UtilityVariableOrigin{Source(MemberId),Builtin(usize)}
enum State{Unissued,Evaluating,Value(ModelValue)}
struct Row{owner:TypeId,name:SymbolId,origin:UtilityVariableOrigin,first:usize,is_const:bool,const_evaluable:bool,hint:Option<String>,declared:bool,state:RefCell<State>}
pub struct UtilityConstantError<'a>{pub origin:UtilityVariableOrigin,pub warning:bool,pub message:&'a str}
struct ErrorRow{site:usize,warning:bool,message:ModelMessage}
struct Candidate{name:SymbolId,origin:UtilityVariableOrigin,first:usize,last:usize}
struct Formal{owner:TypeId,name:SymbolId,origin:UtilityVariableOrigin,last:usize}
/// All vectors precede their actual allocator credits. Paid VALUE/message
/// buffers own their same-counter grants independently, including escaped DATA.
pub struct OriginalUtilityValues<'front,'permit,'op>{
 context:OriginalDeclarationExpressionContext<'front>,
 archive:Arc<BodyArchive>,
 a:&'permit SettingAdmission<'op>,
 catalog:Arc<crate::checker_builtins::CheckerBuiltinCatalog>,
 profile:dm_ir::PackedU128,
 rows:Vec<Row>,order:Vec<usize>,types:Vec<TypeId>,lexical:Vec<TypeId>,ranks:Vec<usize>,formals:Vec<Formal>,
 errors:RefCell<Vec<ErrorRow>>,
 file:RefCell<&'permit mut dyn FnMut(&std::path::Path)->io::Result<u32>>,
 row_credit:Option<SettingRootLease>,order_credit:Option<SettingRootLease>,type_credit:Option<SettingRootLease>,lexical_credit:Option<SettingRootLease>,
 property_credit:RefCell<Option<SettingRootLease>>,error_credit:RefCell<Option<SettingRootLease>>,rank_credit:SettingRootLease,formal_credit:Option<SettingRootLease>,
}
fn unsupported(message:&'static str)->io::Error{io::Error::new(io::ErrorKind::Unsupported,message)}
fn body_failure(error:BodySyntaxFailure)->io::Error{match error{BodySyntaxFailure::Operational(actual)=>actual,BodySyntaxFailure::Syntax(_)=>unsupported("actual utility initializer syntax is unissued")}}
enum PropertyFailure{Unavailable(String),Operational(io::Error)}
impl From<String> for PropertyFailure{fn from(value:String)->Self{Self::Unavailable(value)}}
impl From<&'static str> for PropertyFailure{fn from(value:&'static str)->Self{Self::Unavailable(value.into())}}
impl OriginalUtilityValues<'_,'_,'_>{
 fn check(&self)->io::Result<()>{let pending=self.a.checkpoint();match self.a.take_operational_error(){Some(first)=>Err(first),None=>pending}}
 fn property_fund(&self,bytes:usize)->Result<(),PropertyFailure>{
  let mut credit=self.property_credit.try_borrow_mut().map_err(|_|PropertyFailure::Operational(io::ErrorKind::WouldBlock.into()))?;
  let pending=match credit.as_mut(){Some(credit)=>self.a.grow(credit,bytes),None=>self.a.reserve(bytes).map(|value|{*credit=Some(value)})};
  match self.a.take_operational_error(){Some(first)=>Err(PropertyFailure::Operational(first)),None=>pending.map_err(PropertyFailure::Operational)}
 }
 fn path(&self,id:TypeId)->io::Result<&str>{self.archive.tree().type_node(id).and_then(|row|self.archive.tree().symbols().text(row.path).or_else(||self.catalog.spelling(row.path))).ok_or_else(||unsupported("utility actual type spelling unavailable"))}
 fn row(&self,owner:TypeId,name:SymbolId)->Option<usize>{self.rows.binary_search_by_key(&(owner.index(),name),|row|(row.owner.index(),row.name)).ok()}
 fn inherited_row(&self,mut owner:TypeId,name:SymbolId)->io::Result<Option<usize>>{
  for _ in 0..=self.archive.tree().types().len(){self.check()?;if let Some(index)=self.row(owner,name){return Ok(Some(index))}match self.archive.tree().parent(owner){Some(parent)=>owner=parent,None=>return Ok(None)}}
  Err(unsupported("utility actual parent chain did not terminate"))
 }
 fn failure(&self,message:std::fmt::Arguments<'_>,site:usize)->io::Result<ModelOutcome>{Ok(ModelOutcome::failure_format_using(message,self.a)?.at_site_if_absent(site))}
 fn lookup(&self,owner:TypeId,name:SymbolId,must_be_const:bool)->io::Result<ModelOutcome>{
  self.check()?;let Some(index)=self.inherited_row(owner,name)?else{return ModelOutcome::failure_format_using(format_args!("unknown variable: {}",self.archive.tree().symbols().text(name).or_else(||self.catalog.spelling(name)).ok_or_else(||unsupported("utility variable spelling unavailable"))?),self.a)};
  let row=&self.rows[index];
  let name=self.archive.tree().symbols().text(name).or_else(||self.catalog.spelling(name)).ok_or_else(||unsupported("utility actual variable spelling unavailable"))?;
  if !row.declared{return ModelOutcome::failure_format_using(format_args!("unknown variable: {name}"),self.a)}
  {
   let state=row.state.try_borrow().map_err(|_|io::Error::from(io::ErrorKind::WouldBlock))?;
   match &*state{State::Value(value)=>return Ok(ModelOutcome::Value(value.duplicate_using(self.a)?)),State::Evaluating=>return self.failure(format_args!("recursive constant reference: {name}"),index),State::Unissued=>()}
  }
  let input=match row.origin{UtilityVariableOrigin::Source(member)=>self.context.source_member_value_admitted(member,self.a).map_err(body_failure)?,UtilityVariableOrigin::Builtin(_)=>None};
  let dimension_count=match row.origin{UtilityVariableOrigin::Source(member)=>self.archive.tree().member(member).and_then(|node|node.metadata.array.as_ref()).map_or(0,|array|array.dimensions.iter().filter(|value|value.is_some()).count()),UtilityVariableOrigin::Builtin(_)=>0};
  if input.is_none()&&dimension_count==0{
   let value=ModelValue::null_using(Some(row.hint.as_deref().unwrap_or("")),self.a)?;
   let returned=value.duplicate_using(self.a)?;*row.state.try_borrow_mut().map_err(|_|io::Error::from(io::ErrorKind::WouldBlock))?=State::Value(value);return Ok(ModelOutcome::Value(returned))
  }
  if !row.const_evaluable{return self.failure(format_args!("non-const-evaluable variable: {name}"),index)}
  if must_be_const&&!row.is_const{return self.failure(format_args!("non-const variable: {name}"),index)}
  *row.state.try_borrow_mut().map_err(|_|io::Error::from(io::ErrorKind::WouldBlock))?=State::Evaluating;
  let scope=Scope{values:self,owner:row.owner,hint:row.hint.as_deref(),site:index};
  let mut file=|path:&std::path::Path|{let mut file=self.file.try_borrow_mut().map_err(|_|io::Error::from(io::ErrorKind::WouldBlock))?;file(path)};
  let outcome=if let Some(input)=input{input.original_value_using(self.a,&scope,&mut file).map_err(body_failure)?}else{
   let UtilityVariableOrigin::Source(member)=row.origin else{return Err(unsupported("utility implicit array source is unissued"))};let mut array=value::ModelArrayBuilder::new(dimension_count,self.a)?;
   let dimensions=self.context.source_member_dimensions_admitted(member,self.a).map_err(body_failure)?.ok_or_else(||unsupported("utility actual array suffix is unavailable"))?;let mut next=0;let mut failed=None;
   for dimension in dimensions{let(ordinal,input)=dimension.map_err(body_failure)?;if ordinal!=next{return Err(unsupported("utility actual array suffix order differs"))}next+=1;if let Some(input)=input{if let Some(error)=input.append_original_array_dimension_using(self.a,&scope,&mut file,&mut array).map_err(body_failure)?{failed=Some(error);break}}}
   match failed{Some(error)=>error,None=>ModelOutcome::Value(array.finish(self.a)?)}
  }.at_site_if_absent(index);
  match outcome{ModelOutcome::Value(value)=>{let returned=value.duplicate_using(self.a)?;*row.state.try_borrow_mut().map_err(|_|io::Error::from(io::ErrorKind::WouldBlock))?=State::Value(value);Ok(ModelOutcome::Value(returned))},other=>Ok(other)}
 }
 pub fn visit_types(&self,consume:&mut dyn FnMut(TypeId,&str)->io::Result<()>)->io::Result<()>{for id in &self.types{self.check()?;consume(*id,self.path(*id)?)?;}Ok(())}
 pub fn evaluate_all(&self)->io::Result<()>{
  // Same complete-only finish traversal and source insertion order. Prefix
  // callers never invoke this routine; their cached builtin values stay real.
  for &index in &self.order{self.check()?;let row=&self.rows[index];
   if row.declared&&(!row.is_const&&(!row.const_evaluable||self.path(row.owner)?=="/")){continue}
   if !row.declared{let name=self.archive.tree().symbols().text(row.name).or_else(||self.catalog.spelling(row.name)).ok_or_else(||unsupported("utility variable spelling unavailable"))?;let error=ModelOutcome::failure_format_using(format_args!("undefined var '{name}' on type '{}'",self.path(row.owner)?),self.a)?.at_site(index);if let ModelOutcome::SourceFailure(message)=error{self.record_error(index,message,false)?;}continue}
   match self.lookup(row.owner,row.name,false)?{
    ModelOutcome::Value(_)=>(),
    ModelOutcome::SourceFailure(message)=>self.record_error(index,message,false)?,
    ModelOutcome::SourceWarning(message)=>self.record_error(index,message,true)?,
    ModelOutcome::Unissued(_)=>return Err(unsupported("actual Original utility constant product is unissued")),
   }
  }self.check()
 }
 fn record_error(&self,index:usize,message:ModelMessage,warning:bool)->io::Result<()>{
  let site=message.site().unwrap_or(index);if site>=self.rows.len(){return Err(unsupported("utility constant diagnostic site is foreign"))}
  let mut errors=self.errors.try_borrow_mut().map_err(|_|io::Error::from(io::ErrorKind::WouldBlock))?;let mut credit=self.error_credit.try_borrow_mut().map_err(|_|io::Error::from(io::ErrorKind::WouldBlock))?;
  grow_funded_rows(&mut errors,&mut credit,self.a)?;errors.push(ErrorRow{site,warning,message});Ok(())
 }
 pub fn visit_errors(&self,consume:&mut dyn FnMut(UtilityConstantError<'_>)->io::Result<()>)->io::Result<()>{
  let errors=self.errors.try_borrow().map_err(|_|io::Error::from(io::ErrorKind::WouldBlock))?;
  for error in errors.iter(){self.check()?;let row=self.rows.get(error.site).ok_or_else(||unsupported("utility constant error origin absent"))?;consume(UtilityConstantError{origin:row.origin,warning:error.warning,message:error.message.as_str()})?;}self.check()
 }
 pub fn with_value(&self,owner:TypeId,name:&str,consume:&mut dyn FnMut(UtilityVariableOrigin,Option<&ModelValue>)->io::Result<()>)->io::Result<bool>{
  let Some(index)=self.inherited_row(owner,SymbolId::of(name))?else{return Ok(false)};let row=&self.rows[index];let state=row.state.try_borrow().map_err(|_|io::Error::from(io::ErrorKind::WouldBlock))?;
  consume(row.origin,match &*state{State::Value(value)=>Some(value),_=>None})?;self.check()?;Ok(true)
 }
}
struct Scope<'a,'f,'p,'op>{values:&'a OriginalUtilityValues<'f,'p,'op>,owner:TypeId,hint:Option<&'a str>,site:usize}
impl ModelContext for Scope<'_,'_,'_,'_>{
 fn type_hint(&self)->Option<&str>{self.hint}
 fn identifier(&self,name:&str,must_be_const:bool,_:&SettingAdmission<'_>)->io::Result<ModelOutcome>{self.values.lookup(self.owner,SymbolId::of(name),must_be_const).map(|outcome|outcome.at_site(self.site))}
 fn type_value(&self,parent:bool,a:&SettingAdmission<'_>)->io::Result<ModelOutcome>{
  let owner=if parent{match self.values.archive.tree().parent(self.owner){Some(parent)=>parent,None=>return ModelOutcome::failure_format_using(format_args!("no parent type for {}",self.values.path(self.owner)?),a)}}else{self.owner};
  Ok(ModelOutcome::Value(ModelValue::prefab_using(self.values.path(owner)?,a)?))
 }
 fn static_member(&self,path:&str,name:&str,_:&SettingAdmission<'_>)->io::Result<ModelOutcome>{
  let Some(owner)=self.values.archive.tree().lookup_type(SymbolId::of(path))else{return ModelOutcome::failure_format_using(format_args!("{path} was not a valid type"),self.values.a)};
  self.values.lookup(owner,SymbolId::of(name),false).map(|outcome|outcome.at_site(self.site))
 }
 fn resolve_prefab(&self,path:&str,_:&SettingAdmission<'_>)->io::Result<ModelOutcome>{self.values.resolve_prefab(self.owner,path)}
}


impl<'front,'permit,'op> OriginalUtilityValues<'front,'permit,'op>{
 pub fn capture(context:OriginalDeclarationExpressionContext<'front>,archive:Arc<BodyArchive>,a:&'permit SettingAdmission<'op>,file:&'permit mut dyn FnMut(&std::path::Path)->io::Result<u32>)->io::Result<Self>{
  context.require_utility_archive(&archive).map_err(body_failure)?;
  let profile=archive.tree().checker_builtin_profile().ok_or_else(||unsupported("utility Original builtin profile unissued"))?;
  archive.tree().validate_checker_builtin_profile(profile).map_err(|_|unsupported("utility Original builtin profile differs"))?;
  let catalog=crate::checker_builtins::pinned_catalog().map_err(|_|unsupported("utility Original builtin catalog unavailable"))?;
  if catalog.profile!=profile{return Err(unsupported("utility Original builtin catalog differs"))}
  let(mut ranks,rank_credit)=allocate_funded_rows::<usize>(archive.tree().types().len(),a)?;ranks.resize(archive.tree().types().len(),usize::MAX);
  let mut out=Self{context,archive:Arc::clone(&archive),a,catalog,profile,rows:Vec::new(),order:Vec::new(),types:Vec::new(),lexical:Vec::new(),ranks,formals:Vec::new(),errors:RefCell::new(Vec::new()),file:RefCell::new(file),row_credit:None,order_credit:None,type_credit:None,lexical_credit:None,property_credit:RefCell::new(None),error_credit:RefCell::new(None),rank_credit,formal_credit:None};
  let catalog=Arc::clone(&out.catalog);
  let root=archive.tree().lookup_type(SymbolId::of("/")).ok_or_else(||unsupported("utility actual root type unavailable"))?;
  out.encounter(root)?;
  for path in crate::checker_builtins::original_utility::owner_encounters(profile).map_err(|_|unsupported("utility builtin encounter profile differs"))?{out.encounter_path(path)?;}
  for target in archive.tree().declarations(){out.check()?;let owner=match target{crate::Target::Type(owner)=>*owner,crate::Target::Member(member)=>archive.tree().member(*member).ok_or_else(||unsupported("utility source declaration member absent"))?.owner};let path=archive.tree().type_node(owner).and_then(|node|archive.tree().symbols().text(node.path)).ok_or_else(||unsupported("utility source type spelling unavailable"))?;out.encounter_path(path)?;}
  for &owner in &out.types{grow_funded_rows(&mut out.lexical,&mut out.lexical_credit,a)?;out.lexical.push(owner);}
  out.lexical.sort_unstable_by(|left,right|{let path=|id|archive.tree().type_node(id).and_then(|node|archive.tree().symbols().text(node.path).or_else(||catalog.spelling(node.path))).expect("already authenticated utility type spelling");path(*left).split('/').cmp(path(*right).split('/'))});
  for(index,builtin)in out.catalog.declarations.iter().enumerate(){if builtin.kind==MemberKind::Var&&builtin.definition==DefinitionMode::Declare{let owner=archive.tree().lookup_type(builtin.owner).ok_or_else(||unsupported("utility builtin formal owner absent"))?;grow_funded_rows(&mut out.formals,&mut out.formal_credit,a)?;out.formals.push(Formal{owner,name:builtin.name,origin:UtilityVariableOrigin::Builtin(index),last:builtin.ordinal as usize});}}
  // Order readers borrow the SAME admitted Member index. A source var with
  // no initializer need not have demanded it during earlier value parsing.
  archive.original_declaration_occurrences().prepare_member_groups_admitted(a)?;
  for &owner in &out.types{let node=archive.tree().type_node(owner).ok_or_else(||unsupported("utility actual formal type absent"))?;for member in node.members.iter(){out.check()?;let row=archive.tree().member(*member).ok_or_else(||unsupported("utility actual formal member absent"))?;if row.kind==MemberKind::Var&&row.definition==DefinitionMode::Declare{if let Some(order)=archive.member_original_source_order(*member).map_err(|_|unsupported("utility formal source order unissued"))?{grow_funded_rows(&mut out.formals,&mut out.formal_credit,a)?;out.formals.push(Formal{owner,name:row.name,origin:UtilityVariableOrigin::Source(*member),last:out.catalog.declarations.len().checked_add(order).ok_or(io::ErrorKind::OutOfMemory)?});}}}}
  out.formals.sort_unstable_by_key(|row|(row.owner.index(),row.name,std::cmp::Reverse(row.last)));out.formals.dedup_by(|later,first|later.owner==first.owner&&later.name==first.name);
  // Materialize only actual own-value names. The formal is selected separately
  // through the same current parent chain; inherited values are never copied.
  for type_index in 0..out.types.len(){
   out.check()?;let owner=out.types[type_index];let node=archive.tree().type_node(owner).ok_or_else(||unsupported("utility type row absent"))?;
   let(mut candidates,mut credit)=(Vec::<Candidate>::new(),None);
   for(index,builtin)in out.catalog.declarations.iter().enumerate(){out.check()?;if builtin.owner==node.path&&builtin.kind==MemberKind::Var{grow_funded_rows(&mut candidates,&mut credit,a)?;candidates.push(Candidate{name:builtin.name,origin:UtilityVariableOrigin::Builtin(index),first:builtin.ordinal as usize,last:0});}}
   let builtin_span=out.catalog.declarations.len();
   for member in node.members.iter(){out.check()?;let value=archive.tree().member(*member).ok_or_else(||unsupported("utility own variable member absent"))?;if value.kind!=MemberKind::Var{continue}let Some(last)=archive.member_original_source_order(*member).map_err(|_|unsupported("utility source occurrence unavailable"))?else{continue};let first=archive.member_original_first_source_order(*member).map_err(|_|unsupported("utility first source occurrence unavailable"))?.ok_or_else(||unsupported("utility first source occurrence unissued"))?;
    grow_funded_rows(&mut candidates,&mut credit,a)?;candidates.push(Candidate{name:value.name,origin:UtilityVariableOrigin::Source(*member),first:builtin_span.checked_add(first).ok_or_else(||unsupported("utility source order overflow"))?,last:last.checked_add(1).ok_or_else(||unsupported("utility source order overflow"))?});
   }
   candidates.sort_unstable_by_key(|row|(row.name,row.last));
   let mut start=0;while start<candidates.len(){let mut end=start+1;while end<candidates.len()&&candidates[end].name==candidates[start].name{end+=1}let first=candidates[start..end].iter().map(|row|row.first).min().ok_or_else(||unsupported("utility own variable encounter absent"))?;let selected=&candidates[end-1];let row=out.make_row(owner,selected.name,selected.origin,first)?;grow_funded_rows(&mut out.rows,&mut out.row_credit,a)?;out.rows.push(row);start=end;}
   drop(candidates);drop(credit);
  }
  out.rows.sort_unstable_by_key(|row|(row.owner.index(),row.name));
  for index in 0..out.rows.len(){grow_funded_rows(&mut out.order,&mut out.order_credit,a)?;out.order.push(index);}
  out.order.sort_unstable_by_key(|index|{let row=&out.rows[*index];(out.ranks[row.owner.index()],row.first)});
  out.check()?;Ok(out)
 }
 fn encounter(&mut self,owner:TypeId)->io::Result<()>{self.check()?;let rank=self.ranks.get_mut(owner.index()).ok_or_else(||unsupported("utility type ID differs from actual arena"))?;if *rank==usize::MAX{grow_funded_rows(&mut self.types,&mut self.type_credit,self.a)?;*rank=self.types.len();self.types.push(owner)}Ok(())}
 fn encounter_path(&mut self,path:&str)->io::Result<()>{
  for(index,_)in path.match_indices('/').skip(1){let owner=self.archive.tree().lookup_type(SymbolId::of(&path[..index])).ok_or_else(||unsupported("utility lexical parent unavailable"))?;self.encounter(owner)?;}
  let owner=self.archive.tree().lookup_type(SymbolId::of(path)).ok_or_else(||unsupported("utility actual encounter type unavailable"))?;self.encounter(owner)
 }
}

impl OriginalUtilityValues<'_,'_,'_>{
 fn make_row(&self,owner:TypeId,name:SymbolId,origin:UtilityVariableOrigin,first:usize)->io::Result<Row>{
  let mut cursor=Some(owner);let mut source=None;let mut builtin=None;
  for _ in 0..=self.archive.tree().types().len(){self.check()?;let Some(current)=cursor else{break};if let Ok(index)=self.formals.binary_search_by_key(&(current.index(),name),|row|(row.owner.index(),row.name)){match self.formals[index].origin{UtilityVariableOrigin::Source(member)=>source=Some(member),UtilityVariableOrigin::Builtin(index)=>builtin=Some(index)}break}cursor=self.archive.tree().parent(current);}
  if cursor.is_some()&&source.is_none()&&builtin.is_none(){return Err(unsupported("utility formal parent chain did not terminate"))}
  let(declared,is_const,const_evaluable,hint)=if let Some(formal)=source{
   let mut reserve=|bytes|self.property_fund(bytes);let mut operational=PropertyFailure::Operational;
   let props=self.archive.checker_utility_variable_properties_with_work(formal,self.profile,&mut reserve,&mut operational).map_err(|error|match error{PropertyFailure::Operational(actual)=>actual,PropertyFailure::Unavailable(_)=>unsupported("utility actual variable type projection unissued")})?;
   let flags=props.metadata.flags;let is_const=flags&2!=0;let eligible=is_const||flags&(1|8)==0&&props.qualifiers&dm_syntax::CHECKER_VAR_PROTECTED==0;
   (true,is_const,eligible,props.into_declared_hint())
  }else if let Some(index)=builtin{
   let actual=&self.catalog.declarations[index];let flags=actual.reference_flags.ok_or_else(||unsupported("utility builtin reference flags unavailable"))?;let is_const=flags&4!=0;let eligible=is_const||flags&1==0&&flags&64==0;
   let hint=match crate::checker_builtins::original_utility::declared_hint(actual,self.profile).map_err(|_|unsupported("utility builtin type hint provenance differs"))?{None=>None,Some(text)=>{let bound=text.len().checked_mul(4).ok_or_else(||unsupported("utility builtin hint extent overflow"))?;self.property_fund(bound).map_err(|error|match error{PropertyFailure::Operational(actual)=>actual,PropertyFailure::Unavailable(_)=>unsupported("utility builtin hint admission failed")})?;let mut hint=String::new();hint.try_reserve_exact(text.len()).map_err(|actual|io::Error::new(io::ErrorKind::OutOfMemory,actual))?;if hint.capacity()>bound{return Err(io::Error::new(io::ErrorKind::OutOfMemory,"utility builtin hint exceeds admission"))}hint.push_str(text);Some(hint)}};
   (true,is_const,eligible,hint)
  }else{(false,false,false,None)};
  let state=match origin{UtilityVariableOrigin::Source(_)=>State::Unissued,UtilityVariableOrigin::Builtin(index)=>{
   match crate::checker_builtins::original_utility::initial_value(&self.catalog.declarations[index],self.profile).map_err(|_|unsupported("utility builtin initial value provenance differs"))?{
    crate::checker_builtins::original_utility::InitialValue::Absent=>State::Unissued,
    crate::checker_builtins::original_utility::InitialValue::Number(number)=>State::Value(ModelValue::number_using(number,self.a)?),
    crate::checker_builtins::original_utility::InitialValue::Text(text)=>State::Value(ModelValue::string_using(text,self.a)?),
    crate::checker_builtins::original_utility::InitialValue::Prefab(path)=>State::Value(ModelValue::prefab_using(path,self.a)?),
   }
  }};
  Ok(Row{owner,name,origin,first,is_const,const_evaluable,hint,declared,state:RefCell::new(state)})
 }
}


impl OriginalUtilityValues<'_,'_,'_>{
 fn child_path(&self,owner:TypeId,name:&str)->io::Result<Option<TypeId>>{
  let path=self.path(owner)?;for &candidate in &self.lexical{self.check()?;let actual=self.path(candidate)?;if let Some((parent,leaf))=actual.rsplit_once('/'){if leaf==name&&(if parent.is_empty(){"/"}else{parent})==path{return Ok(Some(candidate))}}}Ok(None)
 }
 fn lexical_parent(&self,owner:TypeId)->io::Result<Option<TypeId>>{let path=self.path(owner)?;if path=="/"{return Ok(None)}let(parent,_)=path.rsplit_once('/').ok_or_else(||unsupported("utility lexical path malformed"))?;Ok(self.archive.tree().lookup_type(SymbolId::of(if parent.is_empty(){"/"}else{parent})))}
 fn navigate(&self,owner:TypeId,op:u8,name:&str)->io::Result<Option<TypeId>>{match op{
  b'/'=>self.child_path(owner,name),
  b'.'=>{let mut current=Some(owner);for _ in 0..=self.types.len(){let Some(owner)=current else{return Ok(None)};if let Some(found)=self.child_path(owner,name)?{return Ok(Some(found))}current=self.lexical_parent(owner)?;}Err(unsupported("utility lexical parent chain did not terminate"))},
  b':'=>{if let Some(found)=self.child_path(owner,name)?{return Ok(Some(found))}let path=self.path(owner)?;for &child in &self.lexical{self.check()?;if child==owner{continue}let actual=self.path(child)?;let descendant=if path=="/"{actual!="/"}else{actual.strip_prefix(path).is_some_and(|rest|rest.starts_with('/'))};if descendant{if let Some(found)=self.child_path(child,name)?{return Ok(Some(found))}}}Ok(None)},
  _=>Err(unsupported("utility relative path operator unissued")),
 }}
 fn procedure_owner(&self,mut owner:TypeId,name:&str)->io::Result<Option<TypeId>>{
  let name=SymbolId::of(name);for _ in 0..=self.archive.tree().types().len(){self.check()?;let node=self.archive.tree().type_node(owner).ok_or_else(||unsupported("utility procedure owner unavailable"))?;let mut source=None;
   for member in node.members.iter(){let row=self.archive.tree().member(*member).ok_or_else(||unsupported("utility procedure row unavailable"))?;if row.name!=name||!matches!(row.kind,MemberKind::Proc|MemberKind::Verb){continue}if let Some(order)=self.archive.member_original_source_order(*member).map_err(|_|unsupported("utility procedure source order unavailable"))?{if source.is_none_or(|previous|order>previous){source=Some(order)}}}
   if source.is_some()||self.catalog.declarations.iter().any(|row|row.owner==node.path&&row.name==name&&matches!(row.kind,MemberKind::Proc|MemberKind::Verb)){return Ok(Some(owner))}
   match self.archive.tree().parent(owner){Some(parent)=>owner=parent,None=>return Ok(None)}
  }Err(unsupported("utility procedure parent chain did not terminate"))
 }
 fn resolve_prefab(&self,owner:TypeId,path:&str)->io::Result<ModelOutcome>{
  // path is canonical DATA from the actual parsed Expr, never a lexical source scan.
  let mut offset=0usize;let mut current=if path.starts_with('/'){self.archive.tree().lookup_type(SymbolId::of("/")).ok_or_else(||unsupported("utility root type absent"))?}else{owner};
  while offset<path.len(){self.check()?;let op=path.as_bytes()[offset];if !matches!(op,b'/'|b'.'|b':'){return Err(unsupported("utility canonical relative path has no operator"))}let start=offset+1;let end=path[start..].find(['/','.',':']).map_or(path.len(),|n|start+n);let name=&path[start..end];if name.is_empty(){return Err(unsupported("utility canonical relative path has an empty component"))}offset=end;
   if matches!(name,"proc"|"verb"){
    if offset<path.len(){let start=offset+1;let end=path[start..].find(['/','.',':']).map_or(path.len(),|n|start+n);let called=&path[start..end];let Some(actual_owner)=self.procedure_owner(current,called)?else{return ModelOutcome::failure_format_using(format_args!("could not resolve {path} relative to {}",self.path(owner)?),self.a)};return Ok(ModelOutcome::Value(ModelValue::prefab_format_using(format_args!("{}/{name}/{called}",self.path(actual_owner)?.trim_end_matches('/')),self.a)?))}
    return Ok(ModelOutcome::Value(ModelValue::prefab_format_using(format_args!("{}/{name}",self.path(current)?.trim_end_matches('/')),self.a)?))
   }
   let Some(next)=self.navigate(current,op,name)?else{return ModelOutcome::failure_format_using(format_args!("could not resolve {path} relative to {}",self.path(owner)?),self.a)};current=next;
  }
  Ok(ModelOutcome::Value(ModelValue::prefab_using(self.path(current)?,self.a)?))
 }
}


struct UtilityErrorRow{file:u16,line:u32,column:u16,sequence:usize,text:ModelMessage}
/// Diagnostic DATA accumulated under ONE actual initializer admission. No row
/// can turn a failed acquisition/unissued parser into a utility completion.
pub struct OriginalUtilityErrors{rows:Vec<UtilityErrorRow>,credit:Option<SettingRootLease>}
impl OriginalUtilityErrors{
 pub fn new()->Self{Self{rows:Vec::new(),credit:None}}
 pub fn push(&mut self,file:u16,line:usize,column:usize,text:ModelMessage,a:&SettingAdmission<'_>)->io::Result<()>{let line=u32::try_from(line).map_err(|_|unsupported("utility diagnostic line exceeds Original coordinate"))?;let column=u16::try_from(column).map_err(|_|unsupported("utility diagnostic column exceeds Original coordinate"))?;grow_funded_rows(&mut self.rows,&mut self.credit,a)?;let sequence=self.rows.len();self.rows.push(UtilityErrorRow{file,line,column,sequence,text});Ok(())}
 pub fn len(&self)->usize{self.rows.len()}
 pub fn write_prelude(&mut self,build:std::time::Duration,out:&mut impl std::io::Write,a:&SettingAdmission<'_>)->io::Result<()>{self.rows.sort_unstable_by_key(|row|(row.file,row.line,row.column,row.sequence));writeln!(out,"sem build: {:.2?}, {} parse errors",build,self.rows.len())?;for row in self.rows.iter().take(20){let pending=a.checkpoint();if let Some(first)=a.take_operational_error(){return Err(first)}pending?;writeln!(out,"  {}:{}: error: {}",row.line,row.column,row.text.as_str())?;}Ok(())}
}
impl OriginalUtilityValues<'_,'_,'_>{
 pub fn append_constant_errors(&self,errors:&mut OriginalUtilityErrors)->io::Result<()>{self.visit_errors(&mut|error|{if error.warning{return Ok(())}let UtilityVariableOrigin::Source(member)=error.origin else{return Err(unsupported("unexpected builtin constant error has no issued source point"))};let point=self.context.source_member_constant_point(member,self.a).map_err(body_failure)?;let(path,line,column)=point.reported_coordinates();let file={let mut lookup=self.file.try_borrow_mut().map_err(|_|io::Error::from(io::ErrorKind::WouldBlock))?;u16::try_from(lookup(path)?).map_err(|_|unsupported("utility Original file ID exceeds range"))?};let text=ModelMessage::copy_using(error.message,self.a)?;errors.push(file,line,column,text,self.a)})}
}


impl OriginalUtilityValues<'_,'_,'_>{
 pub fn debug_value(&self,owner:TypeId,name:&str)->io::Result<Option<ModelMessage>>{let Some(index)=self.inherited_row(owner,SymbolId::of(name))?else{return Ok(None)};let row=&self.rows[index];{let state=row.state.try_borrow().map_err(|_|io::Error::from(io::ErrorKind::WouldBlock))?;if let State::Value(value)=&*state{return value.debug_using(self.a).map(Some)}}let UtilityVariableOrigin::Source(member)=row.origin else{return Ok(None)};let mut file=|path:&std::path::Path|{let mut lookup=self.file.try_borrow_mut().map_err(|_|io::Error::from(io::ErrorKind::WouldBlock))?;lookup(path)};
  let formatted=if let Some(input)=self.context.source_member_value_admitted(member,self.a).map_err(body_failure)?{input.original_debug_using(self.a,&mut file).map_err(body_failure)?}else{let count=self.archive.tree().member(member).and_then(|row|row.metadata.array.as_ref()).map_or(0,|array|array.dimensions.iter().filter(|dimension|dimension.is_some()).count());if count==0{return Ok(None)}let mut out=dm_preprocess::original_expression_debug::ImplicitArray::new(count,self.a)?;let dimensions=self.context.source_member_dimensions_admitted(member,self.a).map_err(body_failure)?.ok_or_else(||unsupported("utility actual implicit array Debug roots absent"))?;for dimension in dimensions{let(_,input)=dimension.map_err(body_failure)?;if let Some(input)=input{out.push(input.original_debug_using(self.a,&mut file).map_err(body_failure)?,self.a)?;}}out.finish(self.a)?};
  if !matches!(formatted.support(),dm_preprocess::original_expression_debug::DebugSupport::Complete){return Err(unsupported("actual Original expression Debug coverage is unissued"))}ModelMessage::copy_using(formatted.as_str(),self.a).map(Some)
 }
}
