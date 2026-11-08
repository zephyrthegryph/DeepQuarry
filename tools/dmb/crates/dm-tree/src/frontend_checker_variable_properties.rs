//! Shared checker-qualified view of ORIGINAL native variable metadata.
//! Does not change runtime declared_type/flags or copy a declaration/model.
use super::{BodyArchive, SourceNoteOrigin};
use crate::{DefinitionMode, MemberId, MemberKind, MemberMetadata};
use dm_ir::{PackedU128, SymbolId};
pub struct CheckerVariableProperties<'a> {
    pub formal: MemberId,
    pub owner: SymbolId,
    pub name: SymbolId,
    pub metadata: &'a MemberMetadata,
    pub qualifiers: u8,
    pub declared_type: Option<SymbolId>,
    pub list_element_type: Option<SymbolId>,
    /// Small ephemeral source-qualified hint; may name a type never interned.
    declared_hint: Option<String>,
}
impl CheckerVariableProperties<'_> {
    /// Already normalized through OWNED primary flags. Unknown nonempty type
    /// names remain typed; absence in the native tree does not erase a hint.
    pub fn declared_hint(&self) -> Option<&str> {
        self.declared_hint.as_deref()
    }
}
struct PropertyWork<'a,E>{reserve:&'a mut dyn FnMut(usize)->Result<(),E>,operational:&'a mut dyn FnMut(std::io::Error)->E}
impl<E> PropertyWork<'_,E>{fn fund(&mut self,bytes:usize)->Result<(),E>{(self.reserve)(bytes)}fn failed(&mut self,message:&'static str)->E{(self.operational)(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))}}
fn property_text<E>(parts:&[&str],work:&mut PropertyWork<'_,E>)->Result<String,E>{
 let mut length=0usize;for part in parts{work.fund(0)?;length=length.checked_add(part.len()).ok_or_else(||work.failed("original variable property text size overflow"))?;}
 let bound=length.checked_mul(4).ok_or_else(||work.failed("original variable property text capacity overflow"))?;let allocation_bytes=bound.checked_add(std::mem::size_of::<String>()+128).ok_or_else(||work.failed("original variable property text allocation geometry overflow"))?;work.fund(allocation_bytes)?;
 let mut output=String::new();output.try_reserve_exact(length).map_err(|e|(work.operational)(std::io::Error::new(std::io::ErrorKind::OutOfMemory,e)))?;if output.capacity()>bound{return Err(work.failed("original variable property text allocator exposed excess capacity"))}for part in parts{work.fund(0)?;output.push_str(part);}Ok(output)
}
#[cfg(test)]
fn cleaned_type(tree:&crate::SemanticTree,path:SymbolId,flags:u8)->Result<Option<String>,String>{
 let mut reserve=|_|Ok(());let mut operational=|actual:std::io::Error|actual.to_string();cleaned_type_using(tree,path,flags,&mut PropertyWork{reserve:&mut reserve,operational:&mut operational})
}
fn cleaned_type_using<E:From<String>+From<&'static str>>(tree:&crate::SemanticTree,path:SymbolId,flags:u8,work:&mut PropertyWork<'_,E>)->Result<Option<String>,E>{
 work.fund(0)?;let raw=tree.symbols().text(path).ok_or("checker variable native type spelling unavailable")?;if !raw.starts_with('/'){return Err("checker variable type is not a native absolute path".into())}
 let mut kept=Vec::new();
 for part in raw.split('/').filter(|part|!part.is_empty()){
  work.fund(0)?;let flag=match part{"final"|"SpacemanDMM_final"=>dm_syntax::CHECKER_VAR_FINAL,"SpacemanDMM_private"=>dm_syntax::CHECKER_VAR_PRIVATE,"SpacemanDMM_protected"=>dm_syntax::CHECKER_VAR_PROTECTED,"var"=>return Err("checker variable redundant namespace projection is not issued".into()),_=>{
   if kept.len()==kept.capacity(){let target=kept.len().checked_add(1).and_then(usize::checked_next_power_of_two).ok_or_else(||work.failed("original variable property path-part count overflow"))?;let bound=target.checked_mul(4).ok_or_else(||work.failed("original variable property path-part capacity overflow"))?;let allocation_bytes=bound.checked_mul(std::mem::size_of::<&str>()).and_then(|n|n.checked_add(128)).ok_or_else(||work.failed("original variable property path-part allocation geometry overflow"))?;work.fund(allocation_bytes)?;kept.try_reserve_exact(target-kept.len()).map_err(|e|(work.operational)(std::io::Error::new(std::io::ErrorKind::OutOfMemory,e)))?;if kept.capacity()>bound{return Err(work.failed("original variable property path-part allocator exposed excess capacity"))}}
   kept.push(part);continue
  }};if flags&flag==0{return Err("native type qualifier lacks original primary flag issuance".into())}
 }
 if kept.is_empty(){return Ok(None)}
 // SAME cleaned path value, without the old intermediate join String.
 let mut length=kept.len();for part in &kept{work.fund(0)?;length=length.checked_add(part.len()).ok_or_else(||work.failed("original variable property path size overflow"))?;}
 let bound=length.checked_mul(4).ok_or_else(||work.failed("original variable property path capacity overflow"))?;let allocation_bytes=bound.checked_add(std::mem::size_of::<String>()+128).ok_or_else(||work.failed("original variable property path allocation geometry overflow"))?;work.fund(allocation_bytes)?;
 let mut output=String::new();output.try_reserve_exact(length).map_err(|e|(work.operational)(std::io::Error::new(std::io::ErrorKind::OutOfMemory,e)))?;if output.capacity()>bound{return Err(work.failed("original variable property path allocator exposed excess capacity"))}for part in kept{work.fund(0)?;output.push('/');output.push_str(part);}Ok(Some(output))
}

impl BodyArchive {
    /// Exact selected formal's ORIGINAL qualifier fact, using the SAME existing
    /// source occurrence grouping and native admission. No parallel property
    /// table, semantic graph, source parse or matching-header inference.
    pub fn checker_variable_qualifiers_admitted(&self,formal:MemberId,profile:PackedU128)->std::io::Result<u8>{
        use super::super::BodySyntaxFailure;
        let unsupported=|message:String|BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::Unsupported,message));
        let proof=self.tree().validated_checker_profile(profile).map_err(|e|std::io::Error::new(std::io::ErrorKind::Unsupported,format!("original variable qualifier profile: {e:?}")))?;
        let result=super::super::initializer_source::original_admission_using(self.setting_queries.as_ref(),|a|{
            a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
            let ordinal=*self.declarations.for_target_admitted(crate::Target::Member(formal),a).map_err(BodySyntaxFailure::Operational)?.first().ok_or_else(||unsupported("original variable formal source occurrence unavailable".into()))?;
            let flags=self.checker_variable_qualifiers_original_at(formal,ordinal,profile,&proof).map_err(unsupported)?;
            a.checkpoint().map_err(BodySyntaxFailure::Operational)?;Ok(flags)
        });
        match result{Ok(flags)=>Ok(flags),Err(BodySyntaxFailure::Operational(actual))=>Err(actual),Err(BodySyntaxFailure::Syntax(actual))=>Err(std::io::Error::new(std::io::ErrorKind::Unsupported,actual.message))}
    }
    /// SAME native property projector with typed operation-local allocation
    /// callbacks. Source flags still come only from this actual Original owner;
    /// callbacks cannot supply flags, types or alternate semantic answers.
    pub fn checker_variable_properties_with_work<E:From<String>+From<&'static str>>(&self,formal:MemberId,profile:PackedU128,reserve:&mut dyn FnMut(usize)->Result<(),E>,operational:&mut dyn FnMut(std::io::Error)->E)->Result<CheckerVariableProperties<'_>,E>{
        let flags=self.checker_variable_qualifiers_admitted(formal,profile).map_err(&mut*operational)?;
        properties_for_issued_original_using(self.tree(),formal,||Ok(flags),&mut PropertyWork{reserve,operational})
    }
    /// Flags are independent of normalized value typing (for example nested
    /// arrays); this borrows the same original formal/cursor-issued metadata.
    pub fn checker_variable_qualifiers(
        &self,
        formal: MemberId,
        profile: PackedU128,
    ) -> Result<u8, String> {
        self.tree()
            .validate_checker_builtin_profile(profile)
            .map_err(|e| format!("checker qualifier profile: {e:?}"))?;
        let node = self
            .tree()
            .member(formal)
            .ok_or("checker qualifier formal unavailable")?;
        if node.kind != MemberKind::Var
            || node.definition != DefinitionMode::Declare
            || node.metadata.inherited_opaque().is_some()
        {
            return Err("checker qualifier needs exact authored formal".into());
        }
        let ordinal = *self
            .declarations
            .for_target(crate::Target::Member(formal))
            .first()
            .ok_or("checker qualifier formal occurrence unavailable")?;
        self.mapping.declaration_checker_qualifiers(ordinal)
    }
    pub fn checker_variable_properties(
        &self,
        formal: MemberId,
        profile: PackedU128,
    ) -> Result<CheckerVariableProperties<'_>, String> {
        self.tree()
            .validate_checker_builtin_profile(profile)
            .map_err(|e| format!("checker variable profile unavailable: {e:?}"))?;
        let node = self
            .tree()
            .member(formal)
            .ok_or("checker formal variable member unavailable")?;
        if node.kind != MemberKind::Var
            || node.definition != DefinitionMode::Declare
            || node.metadata.inherited_opaque().is_some()
        {
            return Err("checker variable needs an exact authored formal declaration".into());
        }
        let ordinal = *self
            .declarations
            .for_target(crate::Target::Member(formal))
            .first()
            .ok_or("checker variable formal has no native source occurrence")?;
        self.checker_variable_properties_at(formal,ordinal)
    }
    fn require_original_variable_occurrence(&self,formal:MemberId,ordinal:crate::OccurrenceId,profile:PackedU128,proof:&crate::checker_builtins::ValidatedCheckerProfile<'_>)->Result<(),String>{
        proof.require(self.tree(),profile).map_err(|e|format!("checker variable profile unavailable: {e:?}"))?;
        if self.declarations.get(ordinal).is_none_or(|row|row.target!=crate::Target::Member(formal)){return Err("checker variable occurrence belongs to another original member".into())}Ok(())
    }
    /// Original current ordinal avoids constructing the legacy target grouping.
    pub fn checker_variable_qualifiers_original_at(&self,formal:MemberId,ordinal:crate::OccurrenceId,profile:PackedU128,proof:&crate::checker_builtins::ValidatedCheckerProfile<'_>)->Result<u8,String>{
        self.require_original_variable_occurrence(formal,ordinal,profile,proof)?;let node=self.tree().member(formal).ok_or("checker qualifier formal unavailable")?;if node.kind!=MemberKind::Var||node.definition!=DefinitionMode::Declare||node.metadata.inherited_opaque().is_some(){return Err("checker qualifier needs exact authored formal".into())}self.mapping.declaration_checker_qualifiers(ordinal)
    }
    pub fn checker_variable_properties_original_at(&self,formal:MemberId,ordinal:crate::OccurrenceId,profile:PackedU128,proof:&crate::checker_builtins::ValidatedCheckerProfile<'_>)->Result<CheckerVariableProperties<'_>,String>{self.require_original_variable_occurrence(formal,ordinal,profile,proof)?;self.checker_variable_properties_at(formal,ordinal)}
    fn checker_variable_properties_at(&self,formal:MemberId,ordinal:crate::OccurrenceId)->Result<CheckerVariableProperties<'_>,String>{
        properties_for_issued_original(self.tree(),formal,||self.mapping.declaration_checker_qualifiers(ordinal))
    }
    pub fn checker_variable_definition_point(
        &self,
        formal: MemberId,
        profile: PackedU128,
    ) -> Result<SourceNoteOrigin, String> {
        let _ = self.checker_variable_properties(formal, profile)?;
        self.member_policy_point(formal)
    }
}


/// The unique source-qualified type projector, using only an actually issued
/// original qualifier callback; it cannot infer flags from matching spelling.
pub(in crate::frontend) fn properties_for_issued_original<'a>(tree:&'a crate::SemanticTree,formal:MemberId,flags:impl FnOnce()->Result<u8,String>)->Result<CheckerVariableProperties<'a>,String>{
 let mut reserve=|_|Ok(());let mut operational=|actual:std::io::Error|actual.to_string();properties_for_issued_original_using(tree,formal,flags,&mut PropertyWork{reserve:&mut reserve,operational:&mut operational})
}
fn properties_for_issued_original_using<'a,E:From<String>+From<&'static str>>(tree:&'a crate::SemanticTree,formal:MemberId,flags:impl FnOnce()->Result<u8,String>,work:&mut PropertyWork<'_,E>)->Result<CheckerVariableProperties<'a>,E>{
 work.fund(0)?;let node=tree.member(formal).ok_or("checker formal variable member unavailable")?;if node.kind!=MemberKind::Var||node.definition!=DefinitionMode::Declare||node.metadata.inherited_opaque().is_some(){return Err("checker variable needs an exact authored formal declaration".into())}
 let flags=flags()?;let data=node.metadata.as_ref();
 let declared_hint=if let Some(array)=&data.array{
  if array.dimensions.len()!=1{return Err("nested array checker type projection is not issued".into())}
  let element=array.element_type.map(|path|cleaned_type_using(tree,path,flags,work)).transpose()?.flatten();if element.as_ref().is_some_and(|path|path=="/list"||path.starts_with("/list/")){return Err("array-of-list checker type projection is not issued".into())}
  Some(match element{Some(path)=>property_text(&["/list",&path],work)?,None=>property_text(&["/list"],work)?})
 }else if data.declared_type()==Some(SymbolId::of("/list")){
  Some(match data.list_element_type(){Some(element)=>match cleaned_type_using(tree,element,flags,work)?{Some(path)=>property_text(&["/list",&path],work)?,None=>property_text(&["/list"],work)?},None=>property_text(&["/list"],work)?})
 }else{data.declared_type().map(|path|cleaned_type_using(tree,path,flags,work)).transpose()?.flatten()};
 let(declared_type,list_element_type)=match declared_hint.as_deref(){None=>(None,None),Some(path)=>{let projected=dm_syntax::project_declaration_type(path);(Some(SymbolId::of(projected.runtime_path)),match projected.list_element_path{Some(tail)=>Some(SymbolId::of(&property_text(&["/",tail],work)?)),None=>None})}};
 Ok(CheckerVariableProperties{formal,owner:tree.type_node(node.owner).ok_or("checker variable owner unavailable")?.path,name:node.name,metadata:data,qualifiers:flags,declared_type,list_element_type,declared_hint})
}

#[cfg(test)]
mod tests {
    use super::*;
    fn tree(source: &str) -> crate::SemanticTree {
        let parsed = dm_syntax::parse(source);
        assert!(parsed.diagnostics.is_empty());
        let contribution = crate::from_ast(
            &parsed,
            dm_ir::SymbolTable::default(),
            dm_ir::FileId(0),
            0,
            0,
        )
        .unwrap();
        crate::build(contribution.symbols, &contribution.skeletons).unwrap()
    }
    #[test]
    fn proved_qualifiers_are_a_view_and_never_mutate_native_runtime_metadata() {
        let tree = tree("/datum/example\n    var/SpacemanDMM_private/datum/value\n");
        let owner = tree.lookup_type(SymbolId::of("/datum/example")).unwrap();
        let id = tree
            .resolve(owner, SymbolId::of("value"), crate::MemberKind::Var)
            .unwrap();
        let data = &tree.member(id).unwrap().metadata;
        let original = data.declared_type().unwrap();
        assert_eq!(
            tree.symbols().text(original),
            Some("/SpacemanDMM_private/datum")
        );
        assert_eq!(
            cleaned_type(&tree, original, dm_syntax::CHECKER_VAR_PRIVATE)
                .unwrap()
                .as_deref(),
            Some("/datum")
        );
        assert_eq!(data.declared_type(), Some(original));
        assert!(
            cleaned_type(&tree, original, 0).is_err(),
            "matching text alone cannot authorize qualifier removal"
        );
    }
    #[test]
    fn qualifier_only_type_is_untyped_and_unknown_named_type_is_not_inferred_away() {
        let tree = tree("/datum/example\n    var/SpacemanDMM_private/value\n    var/SpacemanDMM_protected/missing_type/other\n");
        let owner = tree.lookup_type(SymbolId::of("/datum/example")).unwrap();
        let raw = |name| {
            tree.member(
                tree.resolve(owner, SymbolId::of(name), crate::MemberKind::Var)
                    .unwrap(),
            )
            .unwrap()
            .metadata.declared_type()
            .unwrap()
        };
        assert_eq!(
            cleaned_type(&tree, raw("value"), dm_syntax::CHECKER_VAR_PRIVATE).unwrap(),
            None
        );
        assert_eq!(
            cleaned_type(&tree, raw("other"), dm_syntax::CHECKER_VAR_PROTECTED)
                .unwrap()
                .as_deref(),
            Some("/missing_type")
        );
        assert!(tree.lookup_type(SymbolId::of("/missing_type")).is_none());
    }
}

#[cfg(test)]mod actual_property_allocation_tests{
 use super::*;
 #[derive(Debug)]enum Failure{Source(String),Io(std::io::Error)}impl From<String>for Failure{fn from(value:String)->Self{Self::Source(value)}}impl From<&'static str>for Failure{fn from(value:&'static str)->Self{Self::Source(value.to_owned())}}
 fn actual()->(crate::SemanticTree,MemberId){let parsed=dm_syntax::parse("/datum/holder\n    var/SpacemanDMM_private/list/datum/value\n");assert!(parsed.diagnostics.is_empty());let contribution=crate::from_ast(&parsed,dm_ir::SymbolTable::default(),dm_ir::FileId(0),0,0).unwrap();let tree=crate::build(contribution.symbols,&contribution.skeletons).unwrap();let id=tree.resolve(tree.lookup_type(SymbolId::of("/datum/holder")).unwrap(),SymbolId::of("value"),MemberKind::Var).unwrap();(tree,id)}
 #[test]fn same_native_property_projector_funds_actual_growth_and_preserves_all_original_values(){
  let(tree,formal)=actual();let flags=dm_syntax::CHECKER_VAR_PRIVATE;let legacy=properties_for_issued_original(&tree,formal,||Ok(flags)).unwrap();
  let mut funded=0usize;let mut reserve=|bytes|{funded+=bytes;Ok::<(),Failure>(())};let mut operational=Failure::Io;let current=properties_for_issued_original_using(&tree,formal,||Ok(flags),&mut PropertyWork{reserve:&mut reserve,operational:&mut operational}).unwrap();
  assert_eq!(current.declared_hint(),legacy.declared_hint());assert_eq!(current.declared_type,legacy.declared_type);assert_eq!(current.list_element_type,legacy.list_element_type);assert_eq!(current.qualifiers,legacy.qualifiers);assert!(std::ptr::eq(current.metadata,legacy.metadata));assert!(funded>current.declared_hint.as_ref().map_or(0,String::capacity));assert!(funded<32*1024,"only actual property parts/text, never a project/source multiplier");
 }
 #[test]fn same_native_property_projector_keeps_first_allocation_io_and_actual_quota_denial(){
  let(tree,formal)=actual();let flags=dm_syntax::CHECKER_VAR_PRIVATE;let mut operational=Failure::Io;
  let mut calls=0;let mut io=|bytes|{if bytes!=0{calls+=1;return Err(Failure::Io(std::io::Error::from_raw_os_error(1450)))}Ok(())};let actual=properties_for_issued_original_using(&tree,formal,||Ok(flags),&mut PropertyWork{reserve:&mut io,operational:&mut operational});assert!(matches!(actual,Err(Failure::Io(error))if error.raw_os_error()==Some(1450)));assert_eq!(calls,1,"actual first allocator funding refusal stops construction");
  let mut deny=|bytes|if bytes==0{Ok(())}else{Err(Failure::Io(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"actual property quota exhausted")))};assert!(matches!(properties_for_issued_original_using(&tree,formal,||Ok(flags),&mut PropertyWork{reserve:&mut deny,operational:&mut operational}),Err(Failure::Io(error))if error.kind()==std::io::ErrorKind::OutOfMemory));
  let mut allow=|_|Ok::<(),Failure>(());assert!(properties_for_issued_original_using(&tree,formal,||Ok(flags),&mut PropertyWork{reserve:&mut allow,operational:&mut operational}).is_ok());
 }
}
