//! Weak observation of an actual archive's immutable ORIGINAL owner tuple.
//! No copied roster, source bytes, model, source equality or new anchor.
use super::*;
use std::sync::Weak;
#[derive(Clone)]
pub struct OriginalArchiveOwner{
 syntax:Weak<DeclarationSyntax>,tree:Weak<SemanticTree>,mapping:Weak<SourceExportMapping>,
 callables:Weak<CallableRoster>,body_indices:Weak<HashMap<OccurrenceId,usize>>,
 source:dm_preprocess::WeakSourceText,profile:Option<dm_ir::PackedU128>,
}
impl std::fmt::Debug for OriginalArchiveOwner{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("OriginalArchiveOwner")}}
pub(super) fn issue(archive:&BodyArchive)->OriginalArchiveOwner{
 OriginalArchiveOwner{syntax:Arc::downgrade(&archive.syntax),tree:Arc::downgrade(&archive.tree),mapping:Arc::downgrade(&archive.mapping),callables:Arc::downgrade(&archive.callables),body_indices:Arc::downgrade(&archive.body_indices),source:archive.source.downgrade(),profile:archive.tree.checker_builtin_profile()}
}
impl OriginalArchiveOwner{
 /// Every component upgrades to its ACTUAL original owner before comparison.
 /// New BodyArchive wrappers over the same frontend tuple remain compatible;
 /// another source/model/profile frame cannot acquire this receipt by text.
 pub fn matches(&self,current:&BodyArchive)->bool{
  let(Some(syntax),Some(tree),Some(mapping),Some(callables),Some(body_indices),Some(source))=(self.syntax.upgrade(),self.tree.upgrade(),self.mapping.upgrade(),self.callables.upgrade(),self.body_indices.upgrade(),self.source.upgrade())else{return false};
  Arc::ptr_eq(&syntax,&current.syntax)&&Arc::ptr_eq(&tree,&current.tree)&&Arc::ptr_eq(&mapping,&current.mapping)&&Arc::ptr_eq(&callables,&current.callables)&&Arc::ptr_eq(&body_indices,&current.body_indices)&&source.same_view(&current.source)&&self.profile==current.tree.checker_builtin_profile()
 }
 /// Fixed Weak-retained payloads only. Their child buffers are destroyed at
 /// last strong drop and remain inventoried by their original live owners.
 /// Standard Arc control/header and allocator overhead remains unknown.
 pub fn visit_storage(&self,mut visit:impl FnMut(&'static str,usize,usize,usize)){
  macro_rules! owner{($name:literal,$field:ident,$ty:ty)=>{{let bytes=std::mem::size_of::<$ty>();visit($name,self.$field.as_ptr() as usize,if self.$field.strong_count()>0{bytes}else{0},bytes);}}}
  owner!("syntax",syntax,DeclarationSyntax);owner!("tree",tree,SemanticTree);owner!("mapping",mapping,SourceExportMapping);owner!("callables",callables,CallableRoster);owner!("body_indices",body_indices,HashMap<OccurrenceId,usize>);
  self.source.visit_backing_storage(|p,n,c|visit("source_backing",p,n,c));
 }
 pub fn fixed_retention_capacity(&self)->Option<usize>{let mut bytes=Some(0usize);self.visit_storage(|_,_,_,capacity|bytes=bytes.and_then(|n|n.checked_add(capacity)));bytes}
}
