//! Typed operation transport over the SAME existing initializer classifier.
use super::*;
mod sealed {pub trait Sealed {}}
pub(super) struct Compatibility;
pub(super) struct Checked;
impl sealed::Sealed for Compatibility{}
impl sealed::Sealed for Checked{}
#[derive(Debug)]
pub(super) enum ClassificationReadFailure {Semantic(ClassificationFailure),Operational(std::io::Error)}
impl From<ClassificationFailure> for ClassificationReadFailure {fn from(error:ClassificationFailure)->Self{Self::Semantic(error)}}
impl From<String> for ClassificationReadFailure {fn from(error:String)->Self{Self::Semantic(error.into())}}
impl From<&str> for ClassificationReadFailure {fn from(error:&str)->Self{Self::Semantic(error.into())}}
impl From<InitializerFailure> for ClassificationReadFailure {fn from(error:InitializerFailure)->Self{match error{InitializerFailure::Unsupported(reason)=>Self::Semantic(reason.into()),InitializerFailure::Operational(actual)=>Self::Operational(actual)}}}
pub(super) trait Demand:sealed::Sealed{
    type Failure:From<ClassificationFailure>+From<String>+for<'a>From<&'a str>;
    fn checkpoint()->Result<(),Self::Failure>;
    fn finish<T>(result:Result<T,Self::Failure>)->Result<T,Self::Failure>;
    fn discard<T>(result:Option<Result<T,Self::Failure>>)->Result<(),Self::Failure>;
    fn original<T>(operation:impl FnOnce()->Result<T,InitializerFailure>)->Result<T,Self::Failure>;
    fn source<T>(operation:impl FnOnce()->Result<T,dm_tree::frontend::BodySyntaxFailure>)->Result<T,Self::Failure>;
    fn original_prepared<'source>(e:&dyn CapturedInitializerEvaluator,i:&dm_tree::frontend::OriginalInitializerExpressionInput<'source>,w:&InitializerWrite)->Result<(Evaluation,Option<ScopedPreparedInitializerExpression<'source>>),Self::Failure>;
    fn dimension(e:&dyn CapturedInitializerEvaluator,i:&dm_tree::frontend::OriginalInitializerDimensionInput<'_>,w:&InitializerWrite)->Result<Evaluation,Self::Failure>;
    fn source_fold(w:&InitializerWrite,a:&dm_syntax::Expr,s:value_demand::Source<'_,'_>,t:&SymbolTable,e:&dyn CapturedInitializerEvaluator)->Result<Option<[u32;6]>,Self::Failure>;
    fn source_literal(a:&dm_syntax::Expr,w:&InitializerWrite,t:&SymbolTable,s:value_demand::Source<'_,'_>,e:&dyn CapturedInitializerEvaluator)->Result<bool,Self::Failure>;
    fn source_key(a:&dm_syntax::Expr,s:value_demand::Source<'_,'_>,w:&InitializerWrite,t:&SymbolTable,e:&dyn CapturedInitializerEvaluator)->Result<Option<Vec<u8>>,Self::Failure>;
    fn prepared<'source>(e:&'source dyn CapturedInitializerEvaluator,w:&InitializerWrite,v:&SymbolicExpression)->Result<(Evaluation,Option<ScopedPreparedInitializerExpression<'source>>),Self::Failure>;
    fn write(e:&dyn CapturedInitializerEvaluator,w:&InitializerWrite,v:&SymbolicExpression)->Result<Evaluation,Self::Failure>;
    fn fold(w:&InitializerWrite,a:&dm_syntax::Expr,s:&str,t:&SymbolTable,e:&dyn CapturedInitializerEvaluator)->Result<Option<[u32;6]>,Self::Failure>;
    fn literal(a:&dm_syntax::Expr,w:&InitializerWrite,t:&SymbolTable,s:&str,e:&dyn CapturedInitializerEvaluator)->Result<bool,Self::Failure>;
    fn key(a:&dm_syntax::Expr,s:&str,w:&InitializerWrite,t:&SymbolTable,e:&dyn CapturedInitializerEvaluator)->Result<Option<Vec<u8>>,Self::Failure>;
}
impl Demand for Compatibility{
    type Failure=ClassificationFailure;
    fn checkpoint()->Result<(),Self::Failure>{Ok(())}
    fn finish<T>(result:Result<T,Self::Failure>)->Result<T,Self::Failure>{result}
    fn discard<T>(_:Option<Result<T,Self::Failure>>)->Result<(),Self::Failure>{Ok(())}
    fn original<T>(_:impl FnOnce()->Result<T,InitializerFailure>)->Result<T,Self::Failure>{Err("compatibility classifier cannot use source-required admission".into())}
    fn source<T>(_:impl FnOnce()->Result<T,dm_tree::frontend::BodySyntaxFailure>)->Result<T,Self::Failure>{Err("compatibility classifier cannot issue original source".into())}
    fn original_prepared<'s>(_:&dyn CapturedInitializerEvaluator,_:&dm_tree::frontend::OriginalInitializerExpressionInput<'s>,_:&InitializerWrite)->Result<(Evaluation,Option<ScopedPreparedInitializerExpression<'s>>),Self::Failure>{Err("compatibility classifier has no original source input".into())}
    fn dimension(_:&dyn CapturedInitializerEvaluator,_:&dm_tree::frontend::OriginalInitializerDimensionInput<'_>,_:&InitializerWrite)->Result<Evaluation,Self::Failure>{Err("compatibility classifier has no original dimension input".into())}
    fn source_fold(_:&InitializerWrite,_:&dm_syntax::Expr,_:value_demand::Source<'_,'_>,_:&SymbolTable,_:&dyn CapturedInitializerEvaluator)->Result<Option<[u32;6]>,Self::Failure>{Err("compatibility classifier has no original source helper".into())}
    fn source_literal(_:&dm_syntax::Expr,_:&InitializerWrite,_:&SymbolTable,_:value_demand::Source<'_,'_>,_:&dyn CapturedInitializerEvaluator)->Result<bool,Self::Failure>{Err("compatibility classifier has no original source helper".into())}
    fn source_key(_:&dm_syntax::Expr,_:value_demand::Source<'_,'_>,_:&InitializerWrite,_:&SymbolTable,_:&dyn CapturedInitializerEvaluator)->Result<Option<Vec<u8>>,Self::Failure>{Err("compatibility classifier has no original source helper".into())}
    fn prepared<'source>(e:&'source dyn CapturedInitializerEvaluator,w:&InitializerWrite,v:&SymbolicExpression)->Result<(Evaluation,Option<ScopedPreparedInitializerExpression<'source>>),Self::Failure>{e.evaluate_prepared_write(w,v).map(|(evaluation,prepared)|(evaluation,prepared.map(ScopedPreparedInitializerExpression::from_owned))).map_err(Into::into)}
    fn write(e:&dyn CapturedInitializerEvaluator,w:&InitializerWrite,v:&SymbolicExpression)->Result<Evaluation,Self::Failure>{e.evaluate_write(w,v).map_err(Into::into)}
    fn fold(w:&InitializerWrite,a:&dm_syntax::Expr,s:&str,t:&SymbolTable,e:&dyn CapturedInitializerEvaluator)->Result<Option<[u32;6]>,Self::Failure>{transform::fold(w,a,s,t,e).map_err(Into::into)}
    fn literal(a:&dm_syntax::Expr,w:&InitializerWrite,t:&SymbolTable,s:&str,e:&dyn CapturedInitializerEvaluator)->Result<bool,Self::Failure>{scalar_literal(a,w,t,s,e).map_err(Into::into)}
    fn key(a:&dm_syntax::Expr,s:&str,w:&InitializerWrite,t:&SymbolTable,e:&dyn CapturedInitializerEvaluator)->Result<Option<Vec<u8>>,Self::Failure>{crate::initializer_tokens::construction_key(a,s,w,t,e).map_err(Into::into)}
}
fn checked<T>(operation:impl FnOnce()->Result<T,InitializerFailure>)->Result<T,ClassificationReadFailure>{
    crate::daemon::control::checkpoint().map_err(ClassificationReadFailure::Operational)?;
    let result=operation();
    if matches!(&result,Err(InitializerFailure::Operational(_))){return result.map_err(Into::into);}
    crate::daemon::control::checkpoint().map_err(ClassificationReadFailure::Operational)?;
    result.map_err(Into::into)
}
impl Demand for Checked{
    type Failure=ClassificationReadFailure;
    fn checkpoint()->Result<(),Self::Failure>{crate::daemon::control::checkpoint().map_err(ClassificationReadFailure::Operational)}
    fn finish<T>(result:Result<T,Self::Failure>)->Result<T,Self::Failure>{if matches!(&result,Err(ClassificationReadFailure::Operational(_))){return result;}Self::checkpoint()?;result}
    fn discard<T>(result:Option<Result<T,Self::Failure>>)->Result<(),Self::Failure>{if let Some(Err(actual@ClassificationReadFailure::Operational(_)))=result{return Err(actual);}Self::checkpoint()}
    fn original<T>(operation:impl FnOnce()->Result<T,InitializerFailure>)->Result<T,Self::Failure>{checked(operation)}
    fn source<T>(op:impl FnOnce()->Result<T,dm_tree::frontend::BodySyntaxFailure>)->Result<T,Self::Failure>{op().map_err(|failure|match failure{dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>ClassificationReadFailure::Operational(actual),dm_tree::frontend::BodySyntaxFailure::Syntax(source)=>ClassificationReadFailure::Semantic(source.message.into())})}
    fn original_prepared<'s>(e:&dyn CapturedInitializerEvaluator,i:&dm_tree::frontend::OriginalInitializerExpressionInput<'s>,w:&InitializerWrite)->Result<(Evaluation,Option<ScopedPreparedInitializerExpression<'s>>),Self::Failure>{checked(||e.evaluate_original_write_checked(i,w))}
    fn dimension(e:&dyn CapturedInitializerEvaluator,i:&dm_tree::frontend::OriginalInitializerDimensionInput<'_>,w:&InitializerWrite)->Result<Evaluation,Self::Failure>{checked(||e.evaluate_original_dimension_checked(i,w))}
    fn source_fold(w:&InitializerWrite,a:&dm_syntax::Expr,s:value_demand::Source<'_,'_>,t:&SymbolTable,e:&dyn CapturedInitializerEvaluator)->Result<Option<[u32;6]>,Self::Failure>{transform::fold_source_checked(w,a,s,t,e).map_err(Into::into)}
    fn source_literal(a:&dm_syntax::Expr,w:&InitializerWrite,t:&SymbolTable,s:value_demand::Source<'_,'_>,e:&dyn CapturedInitializerEvaluator)->Result<bool,Self::Failure>{scalar_literal_source_checked(a,w,t,s,e).map_err(Into::into)}
    fn source_key(a:&dm_syntax::Expr,s:value_demand::Source<'_,'_>,w:&InitializerWrite,t:&SymbolTable,e:&dyn CapturedInitializerEvaluator)->Result<Option<Vec<u8>>,Self::Failure>{crate::initializer_tokens::construction_key_source_checked(a,s,w,t,e).map_err(Into::into)}
    fn prepared<'source>(e:&'source dyn CapturedInitializerEvaluator,w:&InitializerWrite,v:&SymbolicExpression)->Result<(Evaluation,Option<ScopedPreparedInitializerExpression<'source>>),Self::Failure>{checked(||e.evaluate_scoped_write_checked(w,v))}
    fn write(e:&dyn CapturedInitializerEvaluator,w:&InitializerWrite,v:&SymbolicExpression)->Result<Evaluation,Self::Failure>{checked(||e.evaluate_write_checked(w,v))}
    fn fold(w:&InitializerWrite,a:&dm_syntax::Expr,s:&str,t:&SymbolTable,e:&dyn CapturedInitializerEvaluator)->Result<Option<[u32;6]>,Self::Failure>{transform::fold_checked(w,a,s,t,e).map_err(Into::into)}
    fn literal(a:&dm_syntax::Expr,w:&InitializerWrite,t:&SymbolTable,s:&str,e:&dyn CapturedInitializerEvaluator)->Result<bool,Self::Failure>{scalar_literal_checked(a,w,t,s,e).map_err(Into::into)}
    fn key(a:&dm_syntax::Expr,s:&str,w:&InitializerWrite,t:&SymbolTable,e:&dyn CapturedInitializerEvaluator)->Result<Option<Vec<u8>>,Self::Failure>{crate::initializer_tokens::construction_key_checked(a,s,w,t,e).map_err(Into::into)}
}
