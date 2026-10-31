//! Stack-only selection of the existing declaration algorithm. Compatibility
//! cannot produce operational errors; checked operations use the existing host
//! admission, never a new graph, parser, source model or error-status cache.
use super::*;
use super::declaration_state::{CurrentContribution, RetainedDeclarations};
use crate::procedure::{HeaderAllocationReceipt, OriginalProcedureHeaders};

#[derive(Debug)]
pub enum FrontendBuildFailure {
    Diagnostics(Vec<Diagnostic>),
    Operational(std::io::Error),
}
impl From<Vec<Diagnostic>> for FrontendBuildFailure {
    fn from(value: Vec<Diagnostic>) -> Self { Self::Diagnostics(value) }
}
impl std::fmt::Display for FrontendBuildFailure {
    fn fmt(&self, f:&mut std::fmt::Formatter<'_>)->std::fmt::Result {
        match self { Self::Diagnostics(errors)=>write!(f,"frontend rejected {} source diagnostics",errors.len()), Self::Operational(error)=>error.fmt(f) }
    }
}
impl std::error::Error for FrontendBuildFailure {
    fn source(&self)->Option<&(dyn std::error::Error+'static)> { match self {Self::Operational(error)=>Some(error),_=>None} }
}

pub(super) type Chunk = (usize, usize, Vec<dm_syntax::Diagnostic>, Option<(usize,dm_syntax::Span,Arc<[u8]>)>, Result<CurrentContribution,Vec<crate::AdapterError>>);
pub(super) trait Permit {
    type Failure: From<Vec<Diagnostic>> + Send;
    fn checkpoint(&self)->Result<(),Self::Failure>;
    fn retain_generation_metadata(&self,bytes:usize)->Result<dm_syntax::SettingRootLease,Self::Failure>;
    fn get(&self,state:&RetainedDeclarations,key:&[u8],text:&str,offset:usize)->Result<Option<CurrentContribution>,Self::Failure>;
    fn headers(&self,source:dm_preprocess::SourceText,items:&[Item],offset:usize,tokens:Option<Vec<dm_syntax::SpanToken>>,checker_settings:bool)->Result<Result<Arc<OriginalProcedureHeaders>,String>,Self::Failure>;
    fn cached_facts(&self,bytes:Option<&[u8]>,text:&str,offset:usize)->Option<(crate::AdaptedDeclarations,crate::allocation_ledger::AllocationLedger)>;
    fn adapt<'a>(&self,ast:&'a AstFile,source:&str,headers:&'a OriginalProcedureHeaders,offset:usize)->Result<Result<(crate::AdaptedDeclarations,HeaderAllocationReceipt<'a>),Vec<crate::AdapterError>>,Self::Failure>;
    fn capture(&self,state:&RetainedDeclarations,key:&[u8],source:dm_preprocess::SourceText,offset:usize,items:Vec<Item>,facts:crate::AdaptedDeclarations,ledger:crate::allocation_ledger::AllocationLedger,headers:Arc<OriginalProcedureHeaders>)->Result<Option<CurrentContribution>,Self::Failure>;
    fn adopt(&self,state:&RetainedDeclarations,chunks:&mut[Chunk])->Result<Option<()>,Self::Failure>;
    fn syntax(&self,syntax:&DeclarationSyntax)->Result<bool,Self::Failure>;
}
pub(super) trait Demand: Sync {
    type Failure: From<Vec<Diagnostic>> + Send;
    fn run<T>(&self, operation:impl FnOnce(&dyn Permit<Failure=Self::Failure>)->Result<T,Self::Failure>)->Result<T,Self::Failure>;
    fn attach(&self,frontend:ColdFrontend)->Result<ColdFrontend,Self::Failure>;
    fn finish<T>(&self,result:Result<T,Self::Failure>)->Result<T,Self::Failure>;
    fn merge_failure(&self,first:&mut Option<Self::Failure>,actual:Self::Failure);
}
pub(super) struct Compatibility;
impl Demand for Compatibility {
    type Failure=Vec<Diagnostic>;
    fn run<T>(&self,operation:impl FnOnce(&dyn Permit<Failure=Self::Failure>)->Result<T,Self::Failure>)->Result<T,Self::Failure>{operation(self)}
    fn attach(&self,frontend:ColdFrontend)->Result<ColdFrontend,Self::Failure>{Ok(frontend)}
    fn finish<T>(&self,result:Result<T,Self::Failure>)->Result<T,Self::Failure>{result}
    fn merge_failure(&self,first:&mut Option<Self::Failure>,actual:Self::Failure){if first.is_none(){*first=Some(actual)}}
}
impl Permit for Compatibility {
    type Failure=Vec<Diagnostic>;
    fn checkpoint(&self)->Result<(),Self::Failure>{Ok(())}
    fn retain_generation_metadata(&self,_:usize)->Result<dm_syntax::SettingRootLease,Self::Failure>{Err(vec![internal("generation metadata requires checked native admission")])}
    fn get(&self,state:&RetainedDeclarations,key:&[u8],text:&str,offset:usize)->Result<Option<CurrentContribution>,Self::Failure>{Ok(state.get_shared(key,text,offset))}
    fn headers(&self,source:dm_preprocess::SourceText,items:&[Item],offset:usize,tokens:Option<Vec<dm_syntax::SpanToken>>,checker_settings:bool)->Result<Result<Arc<OriginalProcedureHeaders>,String>,Self::Failure>{Ok(if checker_settings{OriginalProcedureHeaders::for_declaration_profile(source,items,offset,tokens,None,true).map_err(|failure|match failure{crate::procedure::header_input::OriginalHeaderFailure::Source(message)=>message,crate::procedure::header_input::OriginalHeaderFailure::Operational(actual)=>actual.to_string()})}else{match tokens{Some(tokens)=>OriginalProcedureHeaders::from_primary(source,items,offset,tokens),None=>OriginalProcedureHeaders::reissue(source,items,offset)}})}
    fn cached_facts(&self,bytes:Option<&[u8]>,text:&str,offset:usize)->Option<(crate::AdaptedDeclarations,crate::allocation_ledger::AllocationLedger)>{bytes.and_then(|bytes|chunkfacts::decode(bytes,text,offset))}
    fn adapt<'a>(&self,ast:&'a AstFile,source:&str,headers:&'a OriginalProcedureHeaders,offset:usize)->Result<Result<(crate::AdaptedDeclarations,HeaderAllocationReceipt<'a>),Vec<crate::AdapterError>>,Self::Failure>{Ok(crate::adapter::from_ast_with_source_headers(ast,SymbolTable::default(),FileId(0),0,0,source,headers,offset))}
    fn capture(&self,state:&RetainedDeclarations,key:&[u8],source:dm_preprocess::SourceText,offset:usize,items:Vec<Item>,facts:crate::AdaptedDeclarations,ledger:crate::allocation_ledger::AllocationLedger,headers:Arc<OriginalProcedureHeaders>)->Result<Option<CurrentContribution>,Self::Failure>{Ok(state.capture_source_headers(key,source,offset,items,facts,ledger,Some(headers)))}
    fn adopt(&self,state:&RetainedDeclarations,chunks:&mut[Chunk])->Result<Option<()>,Self::Failure>{Ok(state.adopt_authored(chunks.iter_mut().filter_map(|(_,_,_,_,current)|current.as_mut().ok())))}
    fn syntax(&self,_:&DeclarationSyntax)->Result<bool,Self::Failure>{Ok(true)}
}

pub(super) struct Checked<'a>{pub host:&'a Arc<dyn SettingExpressionQueries>}
struct CheckedPermit<'a,'op>{admission:&'a dm_syntax::SettingAdmission<'op>}
fn actual_checkpoint(admission:&dm_syntax::SettingAdmission<'_>)->std::io::Result<()> {
    let result=admission.checkpoint();
    if let Some(actual)=admission.take_operational_error(){return Err(actual)}
    result
}
impl Demand for Checked<'_>{
    type Failure=FrontendBuildFailure;
    fn run<T>(&self, operation:impl FnOnce(&dyn Permit<Failure=Self::Failure>)->Result<T,Self::Failure>)->Result<T,Self::Failure>{
        let mut operation=Some(operation);
        let mut completed=None;
        let result=self.host.with_declaration_admission(&mut |admission|{
            let operation=operation.take().ok_or_else(||BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"declaration admission callback was repeated")))?;
            match operation(&CheckedPermit{admission}) {
                Err(FrontendBuildFailure::Operational(actual))=>Err(BodySyntaxFailure::Operational(actual)),
                result=>{completed=Some(result);Ok(())},
            }
        });
        match result {
            Err(BodySyntaxFailure::Operational(actual))=>return Err(FrontendBuildFailure::Operational(actual)),
            Err(BodySyntaxFailure::Syntax(error))=>return Err(FrontendBuildFailure::Diagnostics(vec![error])),
            Ok(())=>(),
        }
        completed.ok_or_else(||FrontendBuildFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"declaration admission callback was omitted")))?
    }
    fn finish<T>(&self,result:Result<T,Self::Failure>)->Result<T,Self::Failure>{
        if matches!(&result,Err(FrontendBuildFailure::Operational(_))){return result}
        self.run(|permit|permit.checkpoint())?;result
    }
    fn merge_failure(&self,first:&mut Option<Self::Failure>,actual:Self::Failure){
        if first.is_none() || (matches!(first,Some(FrontendBuildFailure::Diagnostics(_))) && matches!(&actual,FrontendBuildFailure::Operational(_))){*first=Some(actual)}
    }
    fn attach(&self,frontend:ColdFrontend)->Result<ColdFrontend,Self::Failure>{
        let valid=self.run(|permit|permit.syntax(&frontend.syntax))?;
        if !valid || (!frontend.emission_order.is_empty() && frontend.syntax.chunks().is_empty()){
            return Err(FrontendBuildFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"checked frontend lacks completed original declaration producers")));
        }
        frontend.with_setting_expression_queries(self.host).map_err(|error|FrontendBuildFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,error.message)))
    }
}
impl Permit for CheckedPermit<'_,'_>{
    type Failure=FrontendBuildFailure;
    fn checkpoint(&self)->Result<(),Self::Failure>{actual_checkpoint(self.admission).map_err(FrontendBuildFailure::Operational)}
    fn retain_generation_metadata(&self,bytes:usize)->Result<dm_syntax::SettingRootLease,Self::Failure>{
        let result=self.admission.reserve(bytes);
        if let Some(actual)=self.admission.take_operational_error(){return Err(FrontendBuildFailure::Operational(actual))}
        result.map_err(FrontendBuildFailure::Operational)
    }
    fn get(&self,state:&RetainedDeclarations,key:&[u8],text:&str,offset:usize)->Result<Option<CurrentContribution>,Self::Failure>{state.get_shared_checked(key,text,offset,self.admission).map_err(FrontendBuildFailure::Operational)}
    fn headers(&self,source:dm_preprocess::SourceText,items:&[Item],offset:usize,tokens:Option<Vec<dm_syntax::SpanToken>>,checker_settings:bool)->Result<Result<Arc<OriginalProcedureHeaders>,String>,Self::Failure>{
        use crate::procedure::header_input::OriginalHeaderFailure;
        match OriginalProcedureHeaders::for_declaration_profile(source,items,offset,tokens,Some(self.admission),checker_settings){
            Ok(headers)=>Ok(Ok(headers)),Err(OriginalHeaderFailure::Source(message))=>Ok(Err(message)),Err(OriginalHeaderFailure::Operational(actual))=>Err(FrontendBuildFailure::Operational(actual)),
        }
    }
    // Portable declaration payloads have no completed same-counter root owner.
    fn cached_facts(&self,_:Option<&[u8]>,_:&str,_:usize)->Option<(crate::AdaptedDeclarations,crate::allocation_ledger::AllocationLedger)>{None}
    fn adapt<'a>(&self,ast:&'a AstFile,source:&str,headers:&'a OriginalProcedureHeaders,offset:usize)->Result<Result<(crate::AdaptedDeclarations,HeaderAllocationReceipt<'a>),Vec<crate::AdapterError>>,Self::Failure>{crate::adapter::from_ast_with_source_headers_checked(ast,SymbolTable::default(),FileId(0),0,0,source,headers,offset,self.admission).map_err(FrontendBuildFailure::Operational)}
    fn capture(&self,state:&RetainedDeclarations,key:&[u8],source:dm_preprocess::SourceText,offset:usize,items:Vec<Item>,facts:crate::AdaptedDeclarations,ledger:crate::allocation_ledger::AllocationLedger,headers:Arc<OriginalProcedureHeaders>)->Result<Option<CurrentContribution>,Self::Failure>{state.capture_source_headers_checked(key,source,offset,items,facts,ledger,headers,self.admission).map_err(FrontendBuildFailure::Operational)}
    fn adopt(&self,state:&RetainedDeclarations,chunks:&mut[Chunk])->Result<Option<()>,Self::Failure>{state.adopt_authored_checked(chunks.iter_mut().filter_map(|(_,_,_,_,current)|current.as_mut().ok()),self.admission).map_err(FrontendBuildFailure::Operational)}
    fn syntax(&self,syntax:&DeclarationSyntax)->Result<bool,Self::Failure>{
        self.checkpoint()?;
        for chunk in syntax.chunks().iter(){if !chunk.shared_relative().initializer_admission_matches(self.admission).map_err(FrontendBuildFailure::Operational)?{return Ok(false)}}
        self.checkpoint()?;Ok(true)
    }
}
