//! Existing adapter policy with a typed, operation-local original-RHS demand.
//! This does not issue namespace/type semantics or own a parallel declaration model.
use super::*;
mod sealed{pub trait Sealed{}}
pub(super) enum WalkFailure<E>{Source(String),Operational(E)}
impl<E> From<String> for WalkFailure<E>{fn from(message:String)->Self{Self::Source(message)}}
impl<E> From<&str> for WalkFailure<E>{fn from(message:&str)->Self{Self::Source(message.into())}}
pub(super) enum VariableParts<'owner,'normalized>{
    Compatibility{declaration:&'normalized str,initializer:Option<&'normalized str>},
    Original(crate::procedure::header_input::IssuedVariableParts<'owner,'normalized>),
}
impl VariableParts<'_,'_>{
    pub(super) fn declaration(&self)->&str{match self{Self::Compatibility{declaration,..}=>declaration,Self::Original(parts)=>parts.declaration()}}
    pub(super) fn symbolic(&self,symbols:&mut SymbolTable)->Result<Option<dm_ir::SymbolicExpression>,String>{match self{Self::Compatibility{initializer,..}=>initializer.map(|text|crate::procedure::expression(text,symbols)).transpose(),Self::Original(parts)=>parts.symbolic(symbols)}}
}
pub(super) struct Compatibility;
pub(super) struct Checked<'op,'cap>{pub(super) admission:&'op dm_syntax::SettingAdmission<'cap>}
impl sealed::Sealed for Compatibility{}
impl sealed::Sealed for Checked<'_,'_>{}
pub(super) trait AdapterDemand:sealed::Sealed{
    type Operational;
    fn checkpoint(&self)->Result<(),Self::Operational>;
    fn allocation_failure(&self,error:std::collections::TryReserveError)->Result<(),Self::Operational>;
    fn variable<'o,'n>(&self,span:dm_syntax::Span,normalized:&'n str,headers:Option<(&'o crate::procedure::OriginalProcedureHeaders,usize)>)->Result<VariableParts<'o,'n>,WalkFailure<Self::Operational>>;
    fn constant(&self,parts:&VariableParts<'_,'_>,expression:Option<&dm_ir::SymbolicExpression>,symbols:&mut SymbolTable)->Result<Option<dm_ir::SemanticValue>,WalkFailure<Self::Operational>>;
    fn assignment(&self,span:dm_syntax::Span,header:&str,index:usize,headers:Option<(&crate::procedure::OriginalProcedureHeaders,usize)>,symbols:&mut SymbolTable)->Result<dm_ir::SymbolicExpression,WalkFailure<Self::Operational>>;
}
impl AdapterDemand for Compatibility{
    type Operational=std::convert::Infallible;
    fn checkpoint(&self)->Result<(),Self::Operational>{Ok(())}
    fn allocation_failure(&self,_:std::collections::TryReserveError)->Result<(),Self::Operational>{Ok(())}
    fn variable<'o,'n>(&self,_:dm_syntax::Span,header:&'n str,_:Option<(&'o crate::procedure::OriginalProcedureHeaders,usize)>)->Result<VariableParts<'o,'n>,WalkFailure<Self::Operational>>{
        let(declaration,initializer)=dm_syntax::top_level_assignment_index(header).map_or((header,None),|index|(header[..index].trim(),Some(header[index+1..].trim())));
        let initializer=initializer.map(crate::procedure::variable_initializer).transpose()?;
        Ok(VariableParts::Compatibility{declaration,initializer})
    }
    fn constant(&self,parts:&VariableParts<'_,'_>,_:Option<&dm_ir::SymbolicExpression>,symbols:&mut SymbolTable)->Result<Option<dm_ir::SemanticValue>,WalkFailure<Self::Operational>>{
        let VariableParts::Compatibility{initializer,..}=parts else{return Err("compatibility adapter received foreign original input".into())};
        initializer.and_then(|text|crate::constants::evaluate_with(text,|_|None,|_|None,|_|None)).map(|value|value.to_semantic(symbols)).transpose().map_err(|error|WalkFailure::Source(error.to_string()))
    }
    fn assignment(&self,_:dm_syntax::Span,header:&str,index:usize,_:Option<(&crate::procedure::OriginalProcedureHeaders,usize)>,symbols:&mut SymbolTable)->Result<dm_ir::SymbolicExpression,WalkFailure<Self::Operational>>{crate::procedure::expression(header[index+1..].trim(),symbols).map_err(Into::into)}
}
impl AdapterDemand for Checked<'_,'_>{
    type Operational=std::io::Error;
    fn checkpoint(&self)->Result<(),Self::Operational>{let status=self.admission.checkpoint();if let Some(actual)=self.admission.take_operational_error(){return Err(actual);}status}
    fn allocation_failure(&self,error:std::collections::TryReserveError)->Result<(),Self::Operational>{Err(std::io::Error::new(std::io::ErrorKind::OutOfMemory,error))}
    fn variable<'o,'n>(&self,span:dm_syntax::Span,normalized:&'n str,headers:Option<(&'o crate::procedure::OriginalProcedureHeaders,usize)>)->Result<VariableParts<'o,'n>,WalkFailure<Self::Operational>>{
        let(headers,offset)=headers.ok_or("checked variable requires original primary headers")?;
        Ok(VariableParts::Original(headers.variable_parts(span,offset,normalized)?))
    }
    fn constant(&self,parts:&VariableParts<'_,'_>,expression:Option<&dm_ir::SymbolicExpression>,symbols:&mut SymbolTable)->Result<Option<dm_ir::SemanticValue>,WalkFailure<Self::Operational>>{
        let VariableParts::Original(parts)=parts else{return Err("checked adapter cannot select compatibility source".into())};
        let Some(expression)=expression else{return Ok(None)};
        parts.constant(expression,symbols,self.admission).map_err(|failure|match failure{crate::procedure::header_input::OriginalHeaderFailure::Source(message)=>WalkFailure::Source(message),crate::procedure::header_input::OriginalHeaderFailure::Operational(actual)=>WalkFailure::Operational(actual)})
    }
    fn assignment(&self,span:dm_syntax::Span,_:&str,_:usize,headers:Option<(&crate::procedure::OriginalProcedureHeaders,usize)>,symbols:&mut SymbolTable)->Result<dm_ir::SymbolicExpression,WalkFailure<Self::Operational>>{
        let(headers,offset)=headers.ok_or("checked assignment requires original primary headers")?;
        headers.authored_initializer(span,offset,false,symbols).map_err(Into::into)
    }
}
