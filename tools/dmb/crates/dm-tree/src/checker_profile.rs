//! Borrowed proof of the SAME immutable tree's complete pinned profile check.
//! No answers, source data, cache, new catalog or owner facade is retained.
use super::*;
#[derive(Clone,Copy)]pub struct ValidatedCheckerProfile<'tree>{tree:&'tree SemanticTree,profile:PackedU128}
impl SemanticTree{pub fn validated_checker_profile(&self,profile:PackedU128)->Result<ValidatedCheckerProfile<'_>,CheckerBuiltinError>{self.validate_checker_builtin_profile(profile)?;Ok(ValidatedCheckerProfile{tree:self,profile})}}
impl ValidatedCheckerProfile<'_>{
 pub fn require(&self,tree:&SemanticTree,profile:PackedU128)->Result<(),CheckerBuiltinError>{if !std::ptr::eq(self.tree,tree)||self.profile!=profile{return Err(CheckerBuiltinError::Shape("validated checker profile belongs to another immutable tree/profile"))}Ok(())}
 pub fn reborrow<'tree>(&self,tree:&'tree SemanticTree,profile:PackedU128)->Result<ValidatedCheckerProfile<'tree>,CheckerBuiltinError>{self.require(tree,profile)?;Ok(ValidatedCheckerProfile{tree,profile})}
 fn builtin(&self,query:Q,profile:PackedU128,owner:SymbolId,name:SymbolId,kind:MemberKind,presence:bool)->M{self.tree.resolve_checker_builtin_using(query,profile,owner,name,kind,presence,||self.require(self.tree,profile),None).expect("ordinary validated native builtin declaration encoding failed")}
}
impl dm_ir::Resolver for ValidatedCheckerProfile<'_>{
 fn source_owner(&self)->Option<*const ()>{dm_ir::Resolver::source_owner(self.tree)}fn observes_reads(&self)->bool{false}fn answer_world(&self)->Option<u128>{dm_ir::Resolver::answer_world(self.tree)}
 fn resolve(&self,query:Q)->M{match query{Q::CheckerIntrinsicCallable{profile,owner,name,verb}=>self.builtin(query,profile,owner,name,if verb{MemberKind::Verb}else{MemberKind::Proc},true),Q::CheckerBuiltinVar{profile,owner,name}=>self.builtin(query,profile,owner,name,MemberKind::Var,false),Q::CheckerBuiltinProc{profile,owner,name,verb}=>self.builtin(query,profile,owner,name,if verb{MemberKind::Verb}else{MemberKind::Proc},false),_=>dm_ir::Resolver::resolve(self.tree,query)}}
}
