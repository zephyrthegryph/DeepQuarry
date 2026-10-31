//! Source-only join for the unique scalar selector. No selection policy lives here.
use super::*;
impl<'source> OriginalDeclarationExpressionContext<'source> {
 pub(crate) fn scalar_expression_admitted<'selected>(&self,selected:&crate::constant_resolution::SelectedScalarExpression<'selected>,a:&dm_syntax::SettingAdmission<'_>)->Result<OriginalDeclarationExpressionInput<'selected>,BodySyntaxFailure> where 'source:'selected {
  let pending=(|| {
   let reject=|message:&str|BodySyntaxFailure::Syntax(internal(message));
   a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
   let frontend=self.frontend;let tree=&frontend.snapshot.tree;
   if !std::ptr::eq(selected.tree(),tree.as_ref())||!std::ptr::eq(self.mapping,frontend.source_export_mapping.as_ref()){return Err(reject("scalar selection belongs to another original frontend"))}
   let member=tree.member(selected.member()).filter(|node|node.kind==crate::MemberKind::Var).ok_or_else(||reject("scalar selected variable unavailable"))?;
   let expression=selected.expression();
   let actual=match selected.query(){crate::constant_resolution::ScalarQuery::DeclaredDefault{..}=>member.metadata.declared_initializer.as_ref(),_=>member.metadata.initializer.as_ref()};
   if !actual.is_some_and(|actual|std::ptr::eq(actual,expression)){return Err(reject("scalar selected expression is not the exact metadata field"))}
   // Prefer this version's actual authored primary RHS even when semantic
   // interning shares token Arcs with an equal earlier authored expression.
   // Only a typed original-header None may continue inherited member history.
   let mut source=selected.source_member();let mut steps=0usize;
   let input=loop {
    a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
    steps=steps.checked_add(1).filter(|steps|*steps<=tree.members().len()).ok_or_else(||reject("scalar source member history is cyclic"))?;
    let node=tree.member(source).filter(|node|node.kind==crate::MemberKind::Var).ok_or_else(||reject("scalar source member unavailable"))?;
    if !node.metadata.initializer.as_ref().is_some_and(|native|Arc::ptr_eq(&native.tokens,&expression.tokens)){return Err(reject("scalar source member does not carry selected original tokens"))}
    let ids=frontend.snapshot.occurrences.for_target_admitted(crate::Target::Member(source),a).map_err(BodySyntaxFailure::Operational)?;
    let [occurrence_id]=ids else{return Err(reject("scalar source requires one exact original occurrence"))};
    let occurrence=frontend.snapshot.occurrences.get(*occurrence_id).ok_or_else(||reject("scalar original occurrence unavailable"))?;
    if occurrence.target!=crate::Target::Member(source){return Err(reject("scalar original occurrence target differs"))}
    let cursor=self.mapping.initializer_declaration_cursor(*occurrence_id).map_err(|message|reject(&message))?;
    match frontend.issued_syntax.initializer_token_input_if_authored(cursor,expression,tree.symbols()).map_err(|message|reject(&message))?{
     Some(input)=>break input,
     None=>source=node.previous.ok_or_else(||reject("scalar inherited initializer has no original authored predecessor"))?,
    }
   };
   a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
   Ok(OriginalDeclarationExpressionInput{frontend,expression,input:OriginalInitializerSource::Header(input)})
  })();
  if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}
  pending
 }
}
