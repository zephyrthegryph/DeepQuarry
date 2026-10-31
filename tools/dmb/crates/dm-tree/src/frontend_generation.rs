//! Generation-only native declaration preparation. Missing generated includes
//! remain explicit omissions; this type has no conversion to ColdFrontend,
//! DiagnosticFrontend, PolicyInputs, SemanticTree or a body/read receipt.
use super::*;
use super::declaration_demand::Demand;

#[derive(Debug)]
pub enum GenerationPreparationFailure {
    Preprocess(Vec<dm_preprocess::Diagnostic>),
    Frontend(FrontendBuildFailure),
    Syntax(Vec<(usize,dm_syntax::Diagnostic)>),
    Declarations(Vec<crate::AdapterError>),
}
pub struct GenerationDeclarationFrame {
    plan: dm_preprocess::regions::GenerationDirectivePlan,
    parsed: super::declaration_parse::ParsedDeclarations,
}
impl GenerationDeclarationFrame {
    pub fn omissions(&self)->impl Iterator<Item=&Path>{self.plan.omissions()}
    /// Original file-local generation data; no ordinary compiler completeness.
    pub fn original_sources(&self)->impl Iterator<Item=(&Path,Option<&dm_preprocess::SourceAcquisitionLease>)>{self.plan.original_sources()}
    pub fn root_source(&self)->Option<&Path>{self.plan.root_source()}
    /// Narrow authored declaration data only. No semantic resolution, callable
    /// lookup, body parser or source-export mapping is issued by this accessor.
    pub fn declarations(&self)->impl Iterator<Item=&crate::Skeleton>{self.parsed.adapted.skeletons.iter()}
    pub fn symbols(&self)->&dm_ir::SymbolTable{&self.parsed.adapted.symbols}
}
pub fn prepare_generation_declarations<P:SourceProvider>(
    project:&Path, provider:&P, defines:&BTreeMap<String,String>,
    omissions:dm_preprocess::regions::GenerationOmissions,
    config:FrontendConfig<'_>, executor:&dm_exec::BuildExecutor,
    host:&Arc<dyn SettingExpressionQueries>,
    read:&dyn Fn(&Path)->std::io::Result<Option<Arc<dm_preprocess::regions::prepared_source::PreparedSource>>>,
)->Result<GenerationDeclarationFrame,GenerationPreparationFailure>{
    let demand=super::declaration_demand::Checked{host};
    let result=(||{
        demand.run(|permit|permit.checkpoint()).map_err(GenerationPreparationFailure::Frontend)?;
        let plan=dm_preprocess::regions::GenerationDirectivePlan::prepare(project,provider,defines,omissions,read).map_err(|actual|GenerationPreparationFailure::Frontend(FrontendBuildFailure::Operational(actual)))?;
        if !plan.diagnostics().is_empty(){return Err(GenerationPreparationFailure::Preprocess(plan.diagnostics().to_vec()))}
        let expanded=plan.expand(executor);
        if !expanded.diagnostics.is_empty(){return Err(GenerationPreparationFailure::Preprocess(expanded.diagnostics.clone()))}
        let parsing_started=std::time::Instant::now();
        observe(config,FrontendStage::DeclarationParsing,ProgressKind::Started,std::time::Duration::ZERO,0,0);
        let mut parsed=super::declaration_parse::parse_declarations_with_demand(&expanded,config,None,executor,None,&demand).map_err(GenerationPreparationFailure::Frontend)?;
        observe(config,FrontendStage::DeclarationParsing,ProgressKind::Completed,parsing_started.elapsed(),parsed.adapted.skeletons.len(),parsed.adapted.skeletons.len());
        if !parsed.diagnostics.is_empty(){return Err(GenerationPreparationFailure::Syntax(std::mem::take(&mut parsed.diagnostics)))}
        if !parsed.declaration_errors.is_empty(){return Err(GenerationPreparationFailure::Declarations(std::mem::take(&mut parsed.declaration_errors)))}
        Ok(GenerationDeclarationFrame{plan,parsed})
    })();
    // Operational failure is never replaced by a later checkpoint or turned
    // into an absent generated file/source diagnostic.
    if matches!(&result,Err(GenerationPreparationFailure::Frontend(FrontendBuildFailure::Operational(_)))){return result}
    demand.run(|permit|permit.checkpoint()).map_err(GenerationPreparationFailure::Frontend)?;
    result
}
