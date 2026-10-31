//! Runtime syntax retains one original AST and its private weak source recipe.
//! This owner grants shape/census access only. Emission and evaluation require
//! a successfully rebound current input; there is no source-text fallback.
use dm_tree::frontend::{BodySyntaxFailure,InitializerExpressionRecipe,OriginalInitializerExpression,OriginalInitializerExpressionInput};

#[derive(Clone,Debug)]
pub(crate) struct OriginalRuntimeExpression {
    recipe:InitializerExpressionRecipe,
}
/// Stack-only, source-lifetime-bound current expression. Its fields cannot be
/// constructed from AST equality, a source address, or a cached semantic row.
pub(crate) struct CurrentRuntimeExpression<'source> {
    root:OriginalInitializerExpression<'source>,
}
impl OriginalRuntimeExpression {
    pub(crate) fn from_original(root:OriginalInitializerExpression<'_>)->Self{Self{recipe:root.into_recipe()}}
    pub(crate) fn reborrow<'source>(&self,input:&OriginalInitializerExpressionInput<'source>)->Result<Option<CurrentRuntimeExpression<'source>>,BodySyntaxFailure>{
        self.recipe.reborrow(input).map(|root|root.map(|root|CurrentRuntimeExpression{root}))
    }
    /// This equality describes the same runtime AST shape as the preexisting
    /// owned-expression equality. It does not admit a current source or cache hit.
    pub(crate) fn same_shape(&self,other:&Self)->bool{self.recipe.ast()==other.recipe.ast()}
    pub(crate) fn same_root(&self,other:&Self)->bool{self.recipe.same_root(&other.recipe)}
    pub(crate) fn visit_storage(&self,visit:impl FnMut(usize,usize)){self.recipe.visit_storage(visit)}
    /// Original AST lease only; the runtime wrapper and its eventual container
    /// must be counted separately by the existing initializer artifact owner.
    pub(crate) fn retained_root_charge(&self)->Option<usize>{self.recipe.retained_root_charge()}
    /// Body-root variants share their existing admitted parent. The existing
    /// typed-body census must visit child buffers; None root-charge is not zero.
    pub(crate) fn retained_statement_body(&self)->Option<&std::sync::Arc<dm_tree::frontend::StatementBody>>{self.recipe.retained_statement_body()}
}
impl CurrentRuntimeExpression<'_> {
    pub(crate) fn ast(&self)->&dm_syntax::Expr{self.root.ast()}
    /// A flat view is available only when original AST coordinates already
    /// index this source directly. Rebased body statics use projection instead.
    pub(crate) fn flat_source(&self)->Option<&str>{self.root.flat_source()}
    pub(crate) fn source_text(&self,original:dm_syntax::Span)->Option<&str>{self.root.source_text(original)}
    pub(crate) fn project_span(&self,original:dm_syntax::Span)->Option<dm_syntax::Span>{self.root.project_span(original)}
    pub(crate) fn current_span(&self)->dm_syntax::Span{self.root.current_span()}
    pub(crate) fn into_recipe(self)->OriginalRuntimeExpression{OriginalRuntimeExpression::from_original(self.root)}
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{path::Path,sync::Arc};
    struct Source;
    impl dm_preprocess::SourceProvider for Source{
        fn read(&self,_:&Path)->Result<String,String>{Ok("var/static/value=1+2\n".into())}
    }
    fn front(host:&Arc<dyn dm_tree::frontend::SettingExpressionQueries>)->dm_tree::frontend::ColdFrontend{
        dm_tree::frontend::build(Path::new("original-runtime.dme"),&Source,&Default::default(),1).unwrap().with_setting_expression_queries(host).unwrap()
    }
    #[test]
    fn original_runtime_recipe_requires_current_owner_and_keeps_ast_without_source_after_frame_drop(){
        let db=Arc::new(crate::query_db::QueryDb::default());
        let host=db as Arc<dyn dm_tree::frontend::SettingExpressionQueries>;
        let recipe={
            let front=front(&host);
            let plan=dm_tree::initializers::capture_declaration_plan(&front.snapshot,&front.emission_order).unwrap();
            let input=front.original_initializer_input(&plan,0).unwrap();
            let root=input.expression().unwrap();let pointer=root.ast() as *const dm_syntax::Expr;
            let recipe=OriginalRuntimeExpression::from_original(root);
            let current=recipe.reborrow(&input).unwrap().expect("actual same original input");
            assert_eq!(current.ast() as *const dm_syntax::Expr,pointer);
            assert_eq!(current.source_text(current.ast().span),Some("1+2"));
            assert_eq!(current.project_span(current.ast().span),Some(current.current_span()));
            assert_eq!(&front.expanded.text[current.current_span().range()],"1+2");
            let again=current.into_recipe();assert!(again.same_root(&recipe));assert!(again.same_shape(&recipe));
            assert!(recipe.retained_root_charge().is_some());
            recipe
        };
        let equal_text=front(&host);
        let plan=dm_tree::initializers::capture_declaration_plan(&equal_text.snapshot,&equal_text.emission_order).unwrap();
        let input=equal_text.original_initializer_input(&plan,0).unwrap();
        assert!(recipe.reborrow(&input).unwrap().is_none(),"a fresh equal-text frame cannot mint the private original owner");
        let mut regions=0;recipe.visit_storage(|_,_|regions+=1);assert!(regions>0);
    }
}
