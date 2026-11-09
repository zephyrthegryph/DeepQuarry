//! Stack-only selection of the existing declaration algorithm. Compatibility
//! cannot produce operational errors; checked operations use the existing host
//! admission, never a new graph, parser, source model or error-status cache.
use super::*;
use super::declaration_state::{CurrentContribution, RetainedDeclarations};
use crate::procedure::{HeaderAllocationReceipt, OriginalProcedureHeaders};

#[derive(Debug)]
pub enum FrontendBuildFailure {
    Diagnostics(FrontendDiagnostics),
    Operational(std::io::Error),
}
impl From<Vec<Diagnostic>> for FrontendBuildFailure {
    fn from(value: Vec<Diagnostic>) -> Self { Self::Diagnostics(value.into()) }
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
    fn original_primary_admitted(&self)->bool{false}
    fn original_primary_failure(&self,primary:&super::original_declaration_input::OriginalPrimaryRetention,syntax:&DeclarationSyntax,mapping:&Mapping<'_>,plan:&FrontendDirectivePlan)->Result<Self::Failure,Self::Failure>;
    fn original_analysis_declarations(&self,expanded:&ExpandedRegions,engine:Option<&EngineSeed>,previous:Option<&DeclarationSyntax>)->Result<super::original_declaration_input::PreparedOriginalDeclarations,Self::Failure>;
    fn original_stream_declarations(&self,project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,executor:&dm_exec::BuildExecutor,engine:Option<&EngineSeed>,previous:Option<&DeclarationSyntax>,analyze_delivery:bool,lazy_body_parameters:bool,compact_compound:bool)->Result<(FrontendDirectivePlan,ExpandedRegions,super::original_declaration_input::PreparedOriginalDeclarations),Self::Failure>;
    fn borrow_authored_callables<'a>(
        &self, _: &'a crate::declaration_contributions::KeyedDeclarations,
        _: &'a crate::owner_callable::RetainedCallableOwners,
    ) -> Result<Option<crate::owner_callable::AuthoredCallableLoan<'a>>, Self::Failure> { Ok(None) }
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
    fn original_primary_failure(&self,_:&super::original_declaration_input::OriginalPrimaryRetention,_:&DeclarationSyntax,_:&Mapping<'_>,_:&FrontendDirectivePlan)->Result<Self::Failure,Self::Failure>{Err(vec![internal("actual original primary fatal reporting requires native checked admission")])}
    fn original_analysis_declarations(&self,_:&ExpandedRegions,_:Option<&EngineSeed>,_:Option<&DeclarationSyntax>)->Result<super::original_declaration_input::PreparedOriginalDeclarations,Self::Failure>{Err(vec![internal("Original Analyze primary preparation requires the existing checked native host")])}
    fn original_stream_declarations(&self,project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,executor:&dm_exec::BuildExecutor,engine:Option<&EngineSeed>,previous:Option<&DeclarationSyntax>,analyze_delivery:bool,_lazy_body_parameters:bool,_compact_compound:bool)->Result<(FrontendDirectivePlan,ExpandedRegions,super::original_declaration_input::PreparedOriginalDeclarations),Self::Failure>{Err(vec![internal("actual Original stream requires the existing checked native resource host")])}
    fn retain_generation_metadata(&self,_:usize)->Result<dm_syntax::SettingRootLease,Self::Failure>{Err(vec![internal("generation metadata requires checked native admission")])}
    fn get(&self,state:&RetainedDeclarations,key:&[u8],text:&str,offset:usize)->Result<Option<CurrentContribution>,Self::Failure>{Ok(state.get_shared(key,text,offset))}
    fn headers(&self,source:dm_preprocess::SourceText,items:&[Item],offset:usize,tokens:Option<Vec<dm_syntax::SpanToken>>,checker_settings:bool)->Result<Result<Arc<OriginalProcedureHeaders>,String>,Self::Failure>{Ok(if checker_settings{OriginalProcedureHeaders::for_declaration_profile(source,items,offset,tokens,None,true).map_err(|failure|match failure{crate::procedure::header_input::OriginalHeaderFailure::Source(message)=>message,crate::procedure::header_input::OriginalHeaderFailure::Operational(actual)=>actual.to_string()})}else{match tokens{Some(tokens)=>OriginalProcedureHeaders::from_primary(source,items,offset,tokens),None=>OriginalProcedureHeaders::reissue(source,items,offset)}})}
    fn cached_facts(&self,bytes:Option<&[u8]>,text:&str,offset:usize)->Option<(crate::AdaptedDeclarations,crate::allocation_ledger::AllocationLedger)>{bytes.and_then(|bytes|chunkfacts::decode(bytes,text,offset))}
    fn adapt<'a>(&self,ast:&'a AstFile,source:&str,headers:&'a OriginalProcedureHeaders,offset:usize)->Result<Result<(crate::AdaptedDeclarations,HeaderAllocationReceipt<'a>),Vec<crate::AdapterError>>,Self::Failure>{Ok(crate::adapter::from_ast_with_source_headers(ast,SymbolTable::default(),FileId(0),0,0,source,headers,offset))}
    fn capture(&self,state:&RetainedDeclarations,key:&[u8],source:dm_preprocess::SourceText,offset:usize,items:Vec<Item>,facts:crate::AdaptedDeclarations,ledger:crate::allocation_ledger::AllocationLedger,headers:Arc<OriginalProcedureHeaders>)->Result<Option<CurrentContribution>,Self::Failure>{Ok(state.capture_source_headers(key,source,offset,items,facts,ledger,Some(headers)))}
    fn adopt(&self,state:&RetainedDeclarations,chunks:&mut[Chunk])->Result<Option<()>,Self::Failure>{Ok(state.adopt_authored(chunks.iter_mut().filter_map(|(_,_,_,_,current)|current.as_mut().ok())))}
    fn syntax(&self,_:&DeclarationSyntax)->Result<bool,Self::Failure>{Ok(true)}
}

pub(super) struct Checked<'a>{pub host:&'a Arc<dyn SettingExpressionQueries>,pub type_loan:Option<crate::declaration_contributions::TypeContributionLoan<'a>>}
struct CheckedPermit<'a,'op>{admission:&'a dm_syntax::SettingAdmission<'op>,host:&'a dyn SettingExpressionQueries,type_loan:Option<crate::declaration_contributions::TypeContributionLoan<'a>>}
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
            match operation(&CheckedPermit{admission,host:self.host.as_ref(),type_loan:self.type_loan}) {
                Err(FrontendBuildFailure::Operational(actual))=>Err(BodySyntaxFailure::Operational(actual)),
                result=>{completed=Some(result);Ok(())},
            }
        });
        match result {
            Err(BodySyntaxFailure::Operational(actual))=>return Err(FrontendBuildFailure::Operational(actual)),
            Err(BodySyntaxFailure::Syntax(error))=>return Err(FrontendBuildFailure::Diagnostics(vec![error].into())),
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
    fn original_primary_admitted(&self)->bool{true}
    fn original_primary_failure(&self,primary:&super::original_declaration_input::OriginalPrimaryRetention,syntax:&DeclarationSyntax,mapping:&Mapping<'_>,plan:&FrontendDirectivePlan)->Result<Self::Failure,Self::Failure>{
      use super::original_declaration_input::OriginalPrimaryFatal as F;
      self.checkpoint()?;let a=self.admission;let mut credit=a.reserve(0).map_err(FrontendBuildFailure::Operational)?;let mut rows=Vec::new();
      let(offset,fatal)=primary.frontier().ok_or_else(||FrontendBuildFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"actual original parser did not issue a fatal frontier")))?;
      let local=match fatal{F::Comma(actual)=>actual.token_span(),F::Parameter(actual)=>actual.token_span(),F::Input(actual)=>actual.token_span()};let at=offset.checked_add(local.start).ok_or_else(||FrontendBuildFailure::Operational(std::io::Error::from(std::io::ErrorKind::OutOfMemory)))?;
      let source_point=|at|source_export_mapping::original_note_point_in(&mapping.expanded.origins,at,|region|{let include=mapping.plan.regions.get(region).ok_or("formal original region absent")?.occurrence;let acquired=mapping.plan.source_acquisitions.get(&include).ok_or("formal original source acquisition absent")?;Ok((include,acquired))},|include|Ok(&mapping.plan.occurrences.get(include).ok_or("formal original include absent")?.path)).map_err(|reason|std::io::Error::new(std::io::ErrorKind::Unsupported,reason));
      primary.visit_formal_notices(&||actual_checkpoint(a),|notice,value|{
        if notice.span().start>at{return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"actual parser notice follows its consumed fatal frontier"))}
        let point=source_point(notice.span().start)?;let native=mapping.output_for_retained_report(notice.span().start,a,&mut credit)?;
        if native.path.as_path()!=point.path.as_path()||native.line!=point.line{return Err(std::io::Error::new(std::io::ErrorKind::Unsupported,"actual formal parser native/source cursor projection differs"))}
        let message=super::diagnostic_rows::message_using(a,&mut credit,|out|{notice.write_message(value,out)})?;
        super::diagnostic_rows::push(&mut rows,&mut credit,Diagnostic{kind:DiagnosticKind::OriginalFormalNotice{notice,byte_column:point.byte_column},stage:DiagnosticStage::Declaration,message,location:Some(native)},a)
      }).map_err(FrontendBuildFailure::Operational)?;
      let point=source_point(at).map_err(FrontendBuildFailure::Operational)?;let native=mapping.output_for_retained_report(at,a,&mut credit).map_err(FrontendBuildFailure::Operational)?;
      if native.path.as_path()!=point.path.as_path()||native.line!=point.line{return Err(FrontendBuildFailure::Operational(std::io::Error::new(std::io::ErrorKind::Unsupported,"actual original fatal native/source cursor projection differs")))}
      let earlier=syntax.first_original_outer_block_using(&||self.checkpoint())?.map_err(|reason|FrontendBuildFailure::Operational(std::io::Error::new(std::io::ErrorKind::Unsupported,reason)))?;
      let indentation=earlier.is_some_and(|before|before<at)||matches!(fatal,F::Parameter(actual)if actual.prior_outer_block())||matches!(fatal,F::Input(actual)if actual.prior_outer_block());
      let kind=match fatal{F::Comma(reason)=>DiagnosticKind::OriginalFatalDeclaration{reason,byte_column:point.byte_column,indentation},F::Parameter(reason)=>DiagnosticKind::OriginalFatalParameter{reason,byte_column:point.byte_column,indentation},F::Input(reason)=>DiagnosticKind::OriginalFatalInput{reason,byte_column:point.byte_column,indentation}};
      let retained_input=match fatal{F::Input(reason)=>Some(primary.input_fatal_message(offset,reason).map_err(FrontendBuildFailure::Operational)?),_=>None};
      let message=super::diagnostic_rows::message_using(a,&mut credit,|out|match fatal{F::Comma(reason)=>out.write_str(reason.message()),F::Parameter(reason)=>reason.write_message(out),F::Input(_)=>out.write_str(retained_input.expect("actual retained input message"))}).map_err(FrontendBuildFailure::Operational)?;
      super::diagnostic_rows::push(&mut rows,&mut credit,Diagnostic{kind,stage:DiagnosticStage::Declaration,message,location:Some(native)},a).map_err(FrontendBuildFailure::Operational)?;
      let report=FrontendDiagnostics::admitted(rows,credit,a).and_then(|report|report.retain_original_plan(plan)).map_err(FrontendBuildFailure::Operational)?;self.checkpoint()?;Ok(FrontendBuildFailure::Diagnostics(report))
    }

    type Failure=FrontendBuildFailure;
    fn checkpoint(&self)->Result<(),Self::Failure>{actual_checkpoint(self.admission).map_err(FrontendBuildFailure::Operational)}
    fn original_stream_declarations(&self,project:&Path,provider:&dyn SourceProvider,defines:&BTreeMap<String,String>,executor:&dm_exec::BuildExecutor,engine:Option<&EngineSeed>,previous:Option<&DeclarationSyntax>,analyze_delivery:bool,lazy_body_parameters:bool,compact_compound:bool)->Result<(FrontendDirectivePlan,ExpandedRegions,super::original_declaration_input::PreparedOriginalDeclarations),Self::Failure>{
      self.checkpoint()?;let a=self.admission;
      let source_work=self.host.original_source_work().map_err(|error|match error{BodySyntaxFailure::Operational(actual)=>FrontendBuildFailure::Operational(actual),BodySyntaxFailure::Syntax(actual)=>FrontendBuildFailure::Diagnostics(vec![actual].into())})?;
      let batch_host=super::original_stream::TreeOriginalBatchHost(self.host);
      let batch_provider=if analyze_delivery{Some(provider.original_batch_source().map_err(FrontendBuildFailure::Operational)?.ok_or_else(||FrontendBuildFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"actual Original Analyze source has no safe batch-provider loan")))?)}else{None};
      let batch=batch_provider.map(|provider|dm_preprocess::regions::OriginalBatchExecution::new(provider,&batch_host,executor));
      let omissions=dm_preprocess::regions::GenerationOmissions::probe(std::iter::empty(),&mut|_|Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"diagnostic preparation cannot omit a source")),&mut|_|actual_checkpoint(a)).map_err(FrontendBuildFailure::Operational)?;
      // No new per-file quota is invented here. The same actual source-work
      // family preadmits every allocation and enforces its unchanged allowance.
      if lazy_body_parameters && batch.is_none(){
       return Err(FrontendBuildFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"compound BODY parameter demand requires actual Original batch preparation")))
      }
      let streamed=if lazy_body_parameters{
       super::original_stream::prepare_original_stream_with_parameter_mode_using(project,provider,defines,omissions,usize::MAX,source_work,a,batch.as_ref(),true,compact_compound)
      }else{
       super::original_stream::prepare_original_stream_using(project,provider,defines,omissions,usize::MAX,source_work,a,batch.as_ref())
      }.map_err(FrontendBuildFailure::Operational)?;
      let(plan,expanded,prepared)=streamed.into_prepared(engine,previous,self.host,a)?;
      Ok((FrontendDirectivePlan::OriginalDiagnostic(plan),expanded,prepared))
    }
    fn original_analysis_declarations(&self,expanded:&ExpandedRegions,engine:Option<&EngineSeed>,previous:Option<&DeclarationSyntax>)->Result<super::original_declaration_input::PreparedOriginalDeclarations,Self::Failure>{
      let primary=super::original_declaration_input::OrderedOriginalDeclarations::parse(expanded.text.clone(),self.admission).map_err(FrontendBuildFailure::Operational)?;
      let current=primary.adapt_for_original_outcome(self.admission).and_then(|products|products.into_current(self.admission)).map_err(FrontendBuildFailure::Operational)?;
      current.retain_signature_aliases(self.host,self.admission).map_err(|error|match error{BodySyntaxFailure::Operational(actual)=>FrontendBuildFailure::Operational(actual),BodySyntaxFailure::Syntax(actual)=>FrontendBuildFailure::Diagnostics(vec![actual].into())})?;
      current.converge_previous_code(previous,self.admission).and_then(|current|current.into_prepared(engine,self.admission)).map_err(FrontendBuildFailure::Operational)
    }
    fn borrow_authored_callables<'a>(
        &self, declarations: &'a crate::declaration_contributions::KeyedDeclarations,
        prior: &'a crate::owner_callable::RetainedCallableOwners,
    ) -> Result<Option<crate::owner_callable::AuthoredCallableLoan<'a>>, Self::Failure> {
        crate::owner_callable::AuthoredCallableLoan::try_new(declarations, prior, self.admission)
            .map_err(FrontendBuildFailure::Operational)
    }
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
    fn adopt(&self,state:&RetainedDeclarations,chunks:&mut[Chunk])->Result<Option<()>,Self::Failure>{state.adopt_authored_checked(chunks.iter_mut().filter_map(|(_,_,_,_,current)|current.as_mut().ok()),self.admission,self.type_loan).map_err(FrontendBuildFailure::Operational)}
    fn syntax(&self,syntax:&DeclarationSyntax)->Result<bool,Self::Failure>{
        self.checkpoint()?;
        for chunk in syntax.chunks().iter(){if !chunk.shared_relative().initializer_admission_matches(self.admission).map_err(FrontendBuildFailure::Operational)?{return Ok(false)}}
        self.checkpoint()?;Ok(true)
    }
}
