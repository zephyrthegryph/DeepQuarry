//! Exact engine-layering source facts over the one issued original native model.
//! No path-prefix target inference, new parser, body/model store or report issuer.
use crate::{checker_call_facts::{self,CallableFact},policy_inputs::PolicyInputs,policy_body_demand::WorkspaceWork,untyped::Unsupported};
use dm_ir::{PackedU128,SymbolId,ProcedureIdentity,Resolver,ResolveQuery as Q,ResolvedMeaning as M};
use dm_tree::{MemberId,MemberKind,DefinitionMode};
use std::path::Path;

pub struct Model<'a>{inputs:&'a PolicyInputs,root:&'a Path,profile:PackedU128}
impl<'a> Model<'a>{
 pub fn new(inputs:&'a PolicyInputs,root:&'a Path)->Result<Self,Unsupported>{let tree=inputs.archive().tree();let profile=tree.checker_builtin_profile().ok_or_else(||Unsupported("engine layering needs original fixed checker hierarchy/profile".into()))?;Ok(Self{inputs,root,profile})}
 pub fn inputs(&self)->&'a PolicyInputs{self.inputs}
 pub fn profile(&self)->PackedU128{self.profile}
 pub fn spelling(&self,symbol:SymbolId)->Result<&str,Unsupported>{let tree=self.inputs.archive().tree();tree.symbols().text(symbol).or_else(||tree.checker_builtin_spelling(self.profile,symbol)).ok_or_else(||Unsupported("engine original spelling is unavailable".into()))}
 pub fn type_exists<W:WorkspaceWork>(&self,path:&str,w:&mut W)->Result<bool,W::Error>{w.checkpoint()?;let tree=self.inputs.archive().tree();tree.checker_source_type_presence(self.profile,if path.is_empty(){"/"}else{path}).map_err(|e|Unsupported(format!("{e:?}")).into())}
 pub fn builtin_type<W:WorkspaceWork>(&self,path:&str,w:&mut W)->Result<bool,W::Error>{w.checkpoint()?;let tree=self.inputs.archive().tree();let proof=tree.validated_checker_profile(self.profile).map_err(|e|Unsupported(format!("{e:?}")))?;tree.checker_builtin_type_presence_validated(self.profile,path,&proof).map_err(|e|Unsupported(format!("{e:?}")).into())}
 /// Same get_proc namespace/winner as the original checker, including formal-front
 /// and implicit-back values around builtins. Unissued mixed proc/verb chronology
 /// is an explicit failure, never a Proc-first guess or a missing callable.
 pub fn method<W:WorkspaceWork>(&self,owner:&str,name:&str,w:&mut W)->Result<Option<CallableFact>,W::Error>{w.checkpoint()?;let owner=if owner.is_empty(){"/"}else{owner};if !self.type_exists(owner,w)?{return Ok(None)}let tree=self.inputs.archive().tree();let fact=checker_call_facts::callable_any_using(tree,tree,self.profile,SymbolId::of(owner),SymbolId::of(name),&mut||w.checkpoint())?;Ok((!matches!(fact,CallableFact::Missing)).then_some(fact))}
 pub fn global<W:WorkspaceWork>(&self,name:&str,w:&mut W)->Result<Option<CallableFact>,W::Error>{self.method("/",name,w)}
 fn source_member<W:WorkspaceWork>(&self,id:ProcedureIdentity,w:&mut W)->Result<MemberId,W::Error>{
  let archive=self.inputs.archive();let tree=archive.tree();let ty=tree.lookup_type(id.owner).ok_or("engine callable original owner absent")?;let kind=if id.verb{MemberKind::Verb}else{MemberKind::Proc};let mut at=tree.resolve(ty,id.name,kind);let mut left=tree.members().len();
  while let Some(member)=at{w.checkpoint()?;left=left.checked_sub(1).ok_or("engine original callable chain cycles")?;let row=tree.member(member).ok_or("engine original callable chain member absent")?;if row.owner!=ty||row.name!=id.name||row.kind!=kind{break}if archive.callables().identity_for_member(member)==Some(id){return Ok(member)}at=row.previous;}
  Err("engine selected callable has no same original source occurrence".into())
 }
 /// Fixed builtin provenance is a separate fact, not an empty/fake source path.
 pub fn callable_file<W:WorkspaceWork>(&self,fact:&CallableFact,w:&mut W)->Result<Option<String>,W::Error>{w.checkpoint()?;match fact{CallableFact::CheckerBuiltin{..}=>Ok(None),CallableFact::Missing=>Err("engine callable provenance asked of exact absence".into()),CallableFact::Source{identity,..}=>{let member=self.source_member(*identity,w)?;let origin=self.inputs.archive().callable_header_policy_line(member).map_err(Unsupported)?;self.point(&origin.path,origin.line,w).map(|p|Some(p.0))}}}
 pub fn point<W:WorkspaceWork>(&self,path:&Path,line:usize,w:&mut W)->Result<(String,u32),W::Error>{w.checkpoint()?;let file=self.inputs.file_exact(path).ok_or("engine original point is outside same captured model")?;if !file.is_compiled()||file.role()!=crate::policy_inputs::PolicyRole::DmSource{return Err("engine model point is not actual compiled DM source".into())}let line=file.analyze_display_line(line).map_err(|e|Unsupported(e.to_string()))?;if W::CHECKED{let bytes=path.as_os_str().len().checked_add(self.root.as_os_str().len()).and_then(|n|n.checked_mul(16)).and_then(|n|n.checked_add(512)).ok_or_else(||w.overflow())?;w.temporary(bytes)?;}let rel=dm_preprocess::regions::relative_filesystem_path(path,self.root).as_deref().unwrap_or(path).to_string_lossy().replace('\\',"/");Ok((rel,u32::try_from(line).map_err(|_|Unsupported("engine original line overflow".into()))?))}
 /// Formal declaration type only: no initializer/value or return hint inference.
 /// Unknown authored types stay typed; qualified/array shape comes from the same
 /// original primary declaration facts, never reparsed normalized spelling.
 pub fn declared<W:WorkspaceWork>(&self,owner:&str,name:&str,w:&mut W)->Result<Option<String>,W::Error>{w.checkpoint()?;let owner=if owner.is_empty(){"/"}else{owner};if !self.type_exists(owner,w)?{return Ok(None)}let archive=self.inputs.archive();let tree=archive.tree();let Some(fact)=crate::checker_variable_facts::variable_using(tree,tree,self.profile,SymbolId::of(owner),SymbolId::of(name),&mut||w.checkpoint())?else{return Ok(None)};
  if let Some(formal)=fact.formal{w.checkpoint()?;if W::CHECKED{let mut bytes=1024usize;for id in fact.metadata.declared_type.into_iter().chain(fact.metadata.list_element_type){bytes=bytes.checked_add(self.spelling(id)?.len().checked_mul(32).ok_or_else(||w.overflow())?).ok_or_else(||w.overflow())?;}w.temporary(bytes)?;}let properties=archive.checker_variable_properties(formal,self.profile).map_err(Unsupported)?;let hint=properties.declared_hint().unwrap_or("");if W::CHECKED{let bytes=hint.len().checked_mul(4).and_then(|n|n.checked_add(512)).ok_or_else(||w.overflow())?;w.temporary(bytes)?;}return Ok(Some(hint.to_owned()))}
  let Some(ty)=fact.metadata.declared_type else{return Ok(Some(String::new()))};let ty=self.spelling(ty)?;let element=if ty=="/list"{fact.metadata.list_element_type.map(|id|self.spelling(id)).transpose()?}else{None};if W::CHECKED{let bytes=ty.len().checked_add(element.map_or(0,str::len)).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(512)).ok_or_else(||w.overflow())?;w.temporary(bytes)?;}let mut hint=ty.to_owned();if let Some(element)=element{hint.push_str(element)}Ok(Some(hint))
 }
 pub fn parent<W:WorkspaceWork>(&self,owner:&str,w:&mut W)->Result<Option<String>,W::Error>{w.checkpoint()?;let tree=self.inputs.archive().tree();if !self.type_exists(owner,w)?{return Ok(None)}let query=Q::Ancestry(SymbolId::of(owner));if !matches!(Resolver::resolve(tree,query),M::Symbols(_)){return Err("engine original parent dependency unavailable".into())}let ty=tree.lookup_type(SymbolId::of(owner)).ok_or("engine original parent owner absent")?;let Some(parent)=tree.parent(ty)else{return Ok(None)};let path=tree.type_node(parent).ok_or("engine original parent missing")?.path;let path=self.spelling(path)?;if W::CHECKED{let bytes=path.len().checked_mul(4).and_then(|n|n.checked_add(256)).ok_or_else(||w.overflow())?;w.temporary(bytes)?;}Ok(Some(path.to_owned()))}
 /// Every original same-name source implementation in nearest-parent order.
 /// Builtin locations are not source files. Finding any genuine engine location
 /// authorizes a virtual interface even when the selected override is downstream.
 pub fn method_declaration_files<W:WorkspaceWork>(&self,owner:&str,name:&str,w:&mut W,emit:&mut impl FnMut(&str,&mut W)->Result<bool,W::Error>)->Result<(),W::Error>{
  let archive=self.inputs.archive();let tree=archive.tree();if !self.type_exists(owner,w)?{return Ok(())}let mut ty=tree.lookup_type(SymbolId::of(owner));let mut left=tree.types().len();
  while let Some(id)=ty{w.checkpoint()?;left=left.checked_sub(1).ok_or("engine original parent graph cycles")?;let node=tree.type_node(id).ok_or("engine virtual owner missing")?;let group=crate::checker_original_group::Group::issue_using(tree,self.profile,node.path,SymbolId::of(name),&mut||w.checkpoint())?;group.observe_using(tree,&mut||w.checkpoint())?;
   for member in node.members.iter(){w.checkpoint()?;let row=tree.member(*member).ok_or("engine original virtual value missing")?;if row.owner!=id||row.name!=SymbolId::of(name)||!matches!(row.kind,MemberKind::Proc|MemberKind::Verb){continue}let origin=archive.callable_header_policy_line(*member).map_err(Unsupported)?;let (rel,_)=self.point(&origin.path,origin.line,w)?;if !emit(&rel,w)?{return Ok(())}}
   ty=tree.parent(id);
  }Ok(())
 }
 /// Own selected formal declarations, not inherited defaults/typed references.
 pub fn formal_variables<W:WorkspaceWork>(&self,w:&mut W,emit:&mut impl FnMut(&str,&str,&str,u32,&str,&mut W)->Result<(),W::Error>)->Result<(),W::Error>{
  let archive=self.inputs.archive();let tree=archive.tree();let mut seen=std::collections::BTreeSet::new();
  for row in tree.members(){w.checkpoint()?;if row.kind!=MemberKind::Var||row.definition!=DefinitionMode::Declare{continue}let owner=tree.type_node(row.owner).ok_or("engine formal owner missing")?.path;if seen.contains(&(owner,row.name)){continue}if W::CHECKED{w.retain(4*std::mem::size_of::<(SymbolId,SymbolId)>()+128)?;}seen.insert((owner,row.name));let Some(formal)=tree.source_formal_variable_member(owner,row.name).map_err(Unsupported::from)?else{continue};if W::CHECKED{let node=tree.member(formal).ok_or("engine original formal property member absent")?;let mut bytes=1024usize;for id in node.metadata.declared_type.into_iter().chain(node.metadata.list_element_type).chain(node.metadata.array.as_ref().and_then(|a|a.element_type)){bytes=bytes.checked_add(self.spelling(id)?.len().checked_mul(32).ok_or_else(||w.overflow())?).ok_or_else(||w.overflow())?;}w.temporary(bytes)?;}let property=archive.checker_variable_properties(formal,self.profile).map_err(Unsupported)?;let origin=archive.member_policy_line(formal).map_err(Unsupported)?;let(rel,line)=self.point(&origin.path,origin.line,w)?;emit(self.spelling(owner)?,self.spelling(row.name)?,&rel,line,property.declared_hint().unwrap_or(""),w)?;
  }Ok(())
 }
 /// The original Sem provenance/def_at domain: selected own variable values,
 /// selected own formal declarations, and EVERY authored callable value. Root
 /// is included with its original empty owner path (not the native slash key).
 /// Header/body parsing is not triggered merely to format these source points.
 pub fn declaration_points<W:WorkspaceWork>(&self,w:&mut W,emit:&mut impl FnMut(DefinitionPoint<'_>,&mut W)->Result<(),W::Error>)->Result<(),W::Error>{
  let archive=self.inputs.archive();let tree=archive.tree();let mut seen=std::collections::BTreeSet::new();
  for row in tree.members(){w.checkpoint()?;if row.kind!=MemberKind::Var{continue}if seen.contains(&(row.owner,row.name)){continue}if W::CHECKED{w.retain(4*std::mem::size_of::<(dm_ir::TypeId,SymbolId)>()+128)?;}seen.insert((row.owner,row.name));let native_owner=tree.type_node(row.owner).ok_or("engine own variable owner missing")?.path;let spelling=self.spelling(native_owner)?;let owner=if spelling=="/"{""}else{spelling};let name=self.spelling(row.name)?;
   let winner=tree.resolve(row.owner,row.name,MemberKind::Var).ok_or("engine own variable value winner absent")?;let value=tree.member(winner).ok_or("engine own variable value member absent")?;if value.owner!=row.owner{return Err("engine own variable value resolved to inherited declaration".into())}
   if archive.original_declaration_occurrences().for_target(dm_tree::Target::Member(winner)).is_empty(){return Err("engine original variable value provenance is not issued; cannot authorize a type from an ABI row".into())}
   let origin=archive.member_policy_line(winner).map_err(Unsupported)?;let(file,line)=self.point(&origin.path,origin.line,w)?;emit(DefinitionPoint{owner,name,file:&file,line,kind:DefinitionPointKind::VariableValue},w)?;
   if let Some(formal)=tree.source_formal_variable_member(native_owner,row.name).map_err(Unsupported::from)?{if tree.member(formal).ok_or("engine selected formal member absent")?.owner==row.owner{let origin=archive.member_policy_line(formal).map_err(Unsupported)?;let(file,line)=self.point(&origin.path,origin.line,w)?;emit(DefinitionPoint{owner,name,file:&file,line,kind:DefinitionPointKind::FormalVariable},w)?;}}
  }
  for occurrence in archive.occurrences(){w.checkpoint()?;let row=tree.member(occurrence.member).ok_or("engine own callable value member absent")?;let native_owner=tree.type_node(row.owner).ok_or("engine own callable owner absent")?.path;let spelling=self.spelling(native_owner)?;let owner=if spelling=="/"{""}else{spelling};let name=self.spelling(row.name)?;let origin=archive.callable_header_policy_line(occurrence.member).map_err(Unsupported)?;let(file,line)=self.point(&origin.path,origin.line,w)?;emit(DefinitionPoint{owner,name,file:&file,line,kind:DefinitionPointKind::CallableValue},w)?;
  }Ok(())
 }

}

#[path="engine_layering_observer.rs"]mod observer;
pub use observer::{Use,observe_body_using};

#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum DefinitionPointKind{VariableValue,FormalVariable,CallableValue}
pub struct DefinitionPoint<'a>{pub owner:&'a str,pub name:&'a str,pub file:&'a str,pub line:u32,pub kind:DefinitionPointKind}

#[cfg(test)]#[path="engine_layering_native_tests.rs"]mod tests;
