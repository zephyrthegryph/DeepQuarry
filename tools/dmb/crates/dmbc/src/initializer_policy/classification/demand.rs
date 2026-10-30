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
    fn prepared(e:&dyn CapturedInitializerEvaluator,w:&InitializerWrite,v:&SymbolicExpression)->Result<(Evaluation,Option<PreparedInitializerExpression>),Self::Failure>;
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
    fn prepared(e:&dyn CapturedInitializerEvaluator,w:&InitializerWrite,v:&SymbolicExpression)->Result<(Evaluation,Option<PreparedInitializerExpression>),Self::Failure>{e.evaluate_prepared_write(w,v).map_err(Into::into)}
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
    fn prepared(e:&dyn CapturedInitializerEvaluator,w:&InitializerWrite,v:&SymbolicExpression)->Result<(Evaluation,Option<PreparedInitializerExpression>),Self::Failure>{checked(||e.evaluate_prepared_write_checked(w,v))}
    fn write(e:&dyn CapturedInitializerEvaluator,w:&InitializerWrite,v:&SymbolicExpression)->Result<Evaluation,Self::Failure>{checked(||e.evaluate_write_checked(w,v))}
    fn fold(w:&InitializerWrite,a:&dm_syntax::Expr,s:&str,t:&SymbolTable,e:&dyn CapturedInitializerEvaluator)->Result<Option<[u32;6]>,Self::Failure>{transform::fold_checked(w,a,s,t,e).map_err(Into::into)}
    fn literal(a:&dm_syntax::Expr,w:&InitializerWrite,t:&SymbolTable,s:&str,e:&dyn CapturedInitializerEvaluator)->Result<bool,Self::Failure>{scalar_literal_checked(a,w,t,s,e).map_err(Into::into)}
    fn key(a:&dm_syntax::Expr,s:&str,w:&InitializerWrite,t:&SymbolTable,e:&dyn CapturedInitializerEvaluator)->Result<Option<Vec<u8>>,Self::Failure>{crate::initializer_tokens::construction_key_checked(a,s,w,t,e).map_err(Into::into)}
}
