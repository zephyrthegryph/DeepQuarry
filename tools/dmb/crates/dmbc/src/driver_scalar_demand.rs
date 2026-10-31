//! Source selection for the SAME recursive scalar interpreter. Only semantic
//! callback refusal may enter its original String diagnostic accumulator;
//! operational errors travel directly through the recursive Result stack.
use super::*;
use crate::initializer_policy::InitializerFailure;
pub(super) enum Input<'a>{
    Detached,
    Declaration{owner:SymbolId,name:SymbolId,data:&'a dm_ir::DeclarationMeaning},
    ProcedureStatic{identity:dm_ir::ProcedureStaticIdentity,data:&'a dm_ir::ProcedureStaticDeclaration},
}
pub(super) trait Demand {
    type Frame<'a> where Self:'a;
    fn frame(&self)->Result<Self::Frame<'_>,Self::Error>;
    type Error:From<String>+for<'a>From<&'a str>;
    fn expression<T>(&self,evaluator:&DriverEvaluator<'_>,expression:&SymbolicExpression,input:Input<'_>,operation:impl FnOnce(&dm_syntax::Expr)->Result<T,Self::Error>)->Result<Option<T>,Self::Error>;
    fn semantic(&self,error:Self::Error)->Result<String,Self::Error>;
    fn finish<T>(&self,result:Result<T,Self::Error>)->Result<T,Self::Error>;
}
pub(super) struct Compatibility;
impl Demand for Compatibility{
    type Error=String;
    type Frame<'a>=();
    fn frame(&self)->Result<(),Self::Error>{Ok(())}
    fn expression<T>(&self,evaluator:&DriverEvaluator<'_>,expression:&SymbolicExpression,_:Input<'_>,operation:impl FnOnce(&dm_syntax::Expr)->Result<T,Self::Error>)->Result<Option<T>,Self::Error>{
        let text=expression.source_text(evaluator.symbols).ok_or("expression spelling is not captured")?;
        #[cfg(test)]SCALAR_TEXT_PARSES.with(|n|n.set(n.get()+1));
        let parsed=dm_syntax::parse_expression(&text);
        if !parsed.diagnostics.is_empty(){return Err("captured scalar expression failed parsing".into())}
        parsed.expr.as_ref().map(operation).transpose()
    }
    fn semantic(&self,error:Self::Error)->Result<String,Self::Error>{Ok(error)}
    fn finish<T>(&self,result:Result<T,Self::Error>)->Result<T,Self::Error>{result}
}
pub(super) struct Original<'context,'source,'admission,'op>{
    pub(super) context:&'context dm_tree::frontend::OriginalDeclarationExpressionContext<'source>,
    pub(super) admission:&'admission dm_syntax::SettingAdmission<'op>,
    pub(super) static_receipt:Option<&'context Arc<dm_tree::frontend::IssuedStaticPlan>>,
    pub(super) roots:Option<&'context dyn abi_artifacts::RootObserver>,
}
pub(super) fn source_domain_failure(error:dm_tree::frontend::BodySyntaxFailure)->InitializerFailure{match error{dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>InitializerFailure::Operational(actual),dm_tree::frontend::BodySyntaxFailure::Syntax(error)=>InitializerFailure::Unsupported(error.message)}}
pub(super) fn source_failure(error:dm_tree::frontend::BodySyntaxFailure)->InitializerFailure{
    match error{
        dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>InitializerFailure::Operational(actual),
        // Preserve the existing scalar parser policy, not a new root diagnostic.
        dm_tree::frontend::BodySyntaxFailure::Syntax(_)=>InitializerFailure::Unsupported("captured scalar expression failed parsing".into()),
    }
}
impl<'context,'source,'admission,'op> Demand for Original<'context,'source,'admission,'op>{
    type Error=InitializerFailure;
    type Frame<'a>=dm_syntax::SettingEvaluationFrame<'a,'op> where Self:'a;
    fn frame(&self)->Result<Self::Frame<'_>,Self::Error>{self.admission.evaluation_frame().map_err(InitializerFailure::Operational)}
    fn expression<T>(&self,_:&DriverEvaluator<'_>,_:&SymbolicExpression,input:Input<'_>,operation:impl FnOnce(&dm_syntax::Expr)->Result<T,Self::Error>)->Result<Option<T>,Self::Error>{
        let (root,subject)=match input{
            Input::Declaration{owner,name,data}=>(self.context.selected_admitted(owner,name,data,self.admission).map_err(source_domain_failure)?.prepare(self.admission).map_err(source_failure)?,abi_artifacts::RootSubject::Declaration{owner,name}),
            Input::ProcedureStatic{identity,data}=>{
                let receipt=self.static_receipt.ok_or_else(||InitializerFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"original scalar procedure-static producer receipt unavailable")))?;
                (self.context.selected_static_admitted(receipt,identity,data,self.admission).map_err(source_domain_failure)?.prepare(self.admission).map_err(source_failure)?,abi_artifacts::RootSubject::ProcedureStatic(identity))
            },
            Input::Detached=>return Err(InitializerFailure::Unsupported("native scalar expression requires an original source input".into())),
        };
        if let Some(roots)=self.roots{roots.record(subject,&root,self.admission)?;}
        operation(root.ast()).map(Some)
    }
    fn semantic(&self,error:Self::Error)->Result<String,Self::Error>{match error{InitializerFailure::Unsupported(reason)=>Ok(reason),actual@InitializerFailure::Operational(_)=>Err(actual)}}
    fn finish<T>(&self,result:Result<T,Self::Error>)->Result<T,Self::Error>{
        if matches!(&result,Err(InitializerFailure::Operational(_))){return result}
        let pending=self.admission.checkpoint();
        if let Some(actual)=self.admission.take_operational_error(){return Err(InitializerFailure::Operational(actual))}
        pending.map_err(InitializerFailure::Operational)?;result
    }
}

/// Request-local payload capture only. Operational failures leave directly via
/// the existing host callback, never as stored status or a semantic cache value.
pub(super) fn with_admission<T>(context:&dm_tree::frontend::OriginalDeclarationExpressionContext<'_>,operation:impl FnOnce(&dm_syntax::SettingAdmission<'_>)->Result<T,InitializerFailure>)->Result<T,InitializerFailure>{
    let mut operation=Some(operation);let mut completed=None;
    context.with_admission(&mut|admission|{
        let operation=operation.take().ok_or_else(||dm_tree::frontend::BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"scalar admission callback repeated")))?;
        match operation(admission){Err(InitializerFailure::Operational(actual))=>Err(dm_tree::frontend::BodySyntaxFailure::Operational(actual)),outcome=>{completed=Some(outcome);Ok(())}}
    }).map_err(source_domain_failure)?;
    completed.ok_or_else(||InitializerFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"scalar admission callback omitted")))?
}
