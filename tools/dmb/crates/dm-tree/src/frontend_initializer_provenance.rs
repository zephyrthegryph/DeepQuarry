//! Source/storage provenance only, emitted from an actual prepared original root.
//! No strong AST, raw source, copied metadata or scalar answer is retained.
use super::*;
#[derive(Clone)]enum Provenance{
 Header{recipe:OriginalInitializerRecipe,root:usize},
 Static(super::super::static_receipt::OriginalStaticRootProvenance),
}
#[derive(Clone)]pub struct OriginalInitializerRootProvenance{inner:Provenance}
impl std::fmt::Debug for OriginalInitializerRootProvenance{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("OriginalInitializerRootProvenance")}}
pub(super) fn issue(original:&OriginalInitializerExpression<'_>)->OriginalInitializerRootProvenance{
 let inner=match &original.root{OriginalInitializerRoot::Header(root)=>Provenance::Header{recipe:original.recipe.clone(),root:root.original_expression() as *const dm_syntax::Expr as usize},OriginalInitializerRoot::Static(root)=>Provenance::Static(root.provenance())};OriginalInitializerRootProvenance{inner}
}
impl OriginalInitializerRootProvenance{
 /// False is an actual original-owner/slot decline BEFORE root preparation.
 /// Only a proven same immutable owner can ask its existing warm slot under
 /// the SAME held permit; actual IO is Err, never cache miss. Pointer equality
 /// is consulted only after original owner/locator and current input proof.
 pub fn matches_declaration(&self,input:&OriginalDeclarationExpressionInput<'_>,a:&dm_syntax::SettingAdmission<'_>)->Result<bool,BodySyntaxFailure>{self.matches_input(&input.input,a,||input.prepare(a))}
 pub fn matches_initializer(&self,input:&OriginalInitializerExpressionInput<'_>,a:&dm_syntax::SettingAdmission<'_>)->Result<bool,BodySyntaxFailure>{self.matches_input(&input.input,a,||input.prepare(a))}
 pub fn matches_dimension(&self,input:&OriginalInitializerDimensionInput<'_>,a:&dm_syntax::SettingAdmission<'_>)->Result<bool,BodySyntaxFailure>{self.matches_initializer(&input.input,a)}
 fn matches_input<'source>(&self,input:&OriginalInitializerSource<'source>,a:&dm_syntax::SettingAdmission<'_>,prepare:impl FnOnce()->Result<OriginalInitializerExpression<'source>,BodySyntaxFailure>)->Result<bool,BodySyntaxFailure>{
  checkpoint(a)?;
  match (&self.inner,input){
   (Provenance::Header{recipe,..},OriginalInitializerSource::Header(current))if recipe.matches_header(current)=>{},
   (Provenance::Static(old),OriginalInitializerSource::Static{root,..})if old.matches(root)=>{},
   _=>{checkpoint(a)?;return Ok(false)},
  }
  let current=prepare()?;
  let matches=match (&self.inner,&current.root){(Provenance::Header{root,..},OriginalInitializerRoot::Header(current))=>*root==current.original_expression() as *const dm_syntax::Expr as usize,(Provenance::Static(old),OriginalInitializerRoot::Static(current))=>old.matches_prepared(current),_=>false};
  checkpoint(a)?;Ok(matches)
 }
 /// Actual fixed allocations kept alive by Weak. Inline receipt/Vec storage
 /// and standard Arc control/allocator overhead belong to the caller envelope.
 pub fn weak_backing_charge(&self)->usize{match &self.inner{Provenance::Header{recipe:OriginalInitializerRecipe::Header{..},..}=>std::mem::size_of::<crate::procedure::OriginalProcedureHeaders>(),Provenance::Static(root)=>root.weak_backing_charge(),_=>0}}
 pub fn visit_storage(&self,mut visit:impl FnMut(usize,usize)){match &self.inner{Provenance::Header{recipe:OriginalInitializerRecipe::Header{owner,..},..}=>visit(owner.as_ptr() as usize,self.weak_backing_charge()),Provenance::Static(root)=>root.visit_storage(visit),_=>{}}}
}
fn checkpoint(a:&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>{let pending=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}pending.map_err(BodySyntaxFailure::Operational)}
