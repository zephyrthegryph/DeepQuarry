//! Zero-state selection of the existing value hooks. This neither issues source
//! syntax nor owns a second evaluator, model, result cache or error latch.
use super::*;
#[derive(Clone,Copy)]
pub(crate) enum Source<'view,'source>{
 Flat(&'view str),
 Original{input:&'view dm_tree::frontend::OriginalInitializerExpressionInput<'source>,root:&'view dm_tree::frontend::OriginalInitializerExpression<'source>},
}

mod sealed {pub trait Sealed {}}
pub(crate) struct Compatibility;
pub(crate) struct Checked;
impl sealed::Sealed for Compatibility {}
impl sealed::Sealed for Checked {}
pub(crate) trait Demand: sealed::Sealed {
    type Error: From<String> + for<'a> From<&'a str>;
    fn ast(evaluator:&dyn CapturedInitializerEvaluator,write:&InitializerWrite,ast:&dm_syntax::Expr,source:Source<'_,'_>,symbols:&SymbolTable)->Result<Evaluation,Self::Error>;
    fn scalar(evaluator:&dyn CapturedInitializerEvaluator,value:&SemanticValue)->Result<Vec<u8>,Self::Error>;
    fn constructor_type(evaluator:&dyn CapturedInitializerEvaluator,write:&InitializerWrite)->Result<Option<SymbolId>,Self::Error>;
    fn intrinsic(evaluator:&dyn CapturedInitializerEvaluator,write:&InitializerWrite,name:&str)->Result<bool,Self::Error>;
}
impl Demand for Compatibility {
    type Error=String;
    fn ast(e:&dyn CapturedInitializerEvaluator,w:&InitializerWrite,a:&dm_syntax::Expr,s:Source<'_,'_>,t:&SymbolTable)->Result<Evaluation,String>{match s{Source::Flat(s)=>e.evaluate_ast_write(w,a,s,t),Source::Original{..}=>Err("compatibility value demand cannot consume original source".into())}}
    fn scalar(e:&dyn CapturedInitializerEvaluator,v:&SemanticValue)->Result<Vec<u8>,String>{e.initializer_token_scalar(v)}
    fn constructor_type(e:&dyn CapturedInitializerEvaluator,w:&InitializerWrite)->Result<Option<SymbolId>,String>{e.initializer_constructor_type(w)}
    fn intrinsic(e:&dyn CapturedInitializerEvaluator,w:&InitializerWrite,n:&str)->Result<bool,String>{Ok(e.initializer_intrinsic_constructor(w,n))}
}
impl Demand for Checked {
    type Error=InitializerFailure;
    fn ast(e:&dyn CapturedInitializerEvaluator,w:&InitializerWrite,a:&dm_syntax::Expr,s:Source<'_,'_>,t:&SymbolTable)->Result<Evaluation,InitializerFailure>{match s{Source::Flat(s)=>e.evaluate_ast_write_checked(w,a,s,t),Source::Original{input,root}=>e.evaluate_original_ast_write_checked(input,w,root,a,t)}}
    fn scalar(e:&dyn CapturedInitializerEvaluator,v:&SemanticValue)->Result<Vec<u8>,InitializerFailure>{e.initializer_token_scalar_checked(v)}
    fn constructor_type(e:&dyn CapturedInitializerEvaluator,w:&InitializerWrite)->Result<Option<SymbolId>,InitializerFailure>{e.initializer_constructor_type_checked(w)}
    fn intrinsic(e:&dyn CapturedInitializerEvaluator,w:&InitializerWrite,n:&str)->Result<bool,InitializerFailure>{e.initializer_intrinsic_constructor_checked(w,n)}
}
