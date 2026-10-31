//! Generation-only native declaration preparation. Missing generated includes
//! remain explicit omissions; this type has no conversion to ColdFrontend,
//! DiagnosticFrontend, PolicyInputs or a complete-program source/body receipt.
use super::*;
use super::declaration_demand::Demand;

#[derive(Debug)]
pub enum GenerationPreparationFailure {
    Preprocess(Vec<dm_preprocess::Diagnostic>),
    Frontend(FrontendBuildFailure),
    Syntax(Vec<(usize,dm_syntax::Diagnostic)>),
    Declarations(Vec<crate::AdapterError>),
    Assembly(Vec<Diagnostic>),
}
pub struct GenerationDeclarationFrame {
    plan: dm_preprocess::regions::GenerationDirectivePlan,
    parsed: super::declaration_parse::ParsedDeclarations,
    question_expansion: Option<ExpandedRegions>,
    question_host:Option<std::sync::Weak<dyn SettingExpressionQueries>>,
}
impl GenerationDeclarationFrame {
    pub fn omissions(&self)->impl Iterator<Item=&Path>{self.plan.omissions()}
    /// Original file-local generation data; no ordinary compiler completeness.
    pub fn original_sources(&self)->dm_preprocess::regions::GenerationOriginalSources<'_>{self.plan.original_sources()}
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
    prepare_generation_declarations_inner(project,provider,defines,omissions,config,executor,host,read,false)
}

/// Select actual native declaration/body questions before the single parse.
/// Missing outputs remain explicit and this grants no complete compiler role.
pub fn prepare_generation_question_declarations<P:SourceProvider>(
    project:&Path, provider:&P, defines:&BTreeMap<String,String>,
    omissions:dm_preprocess::regions::GenerationOmissions,
    config:FrontendConfig<'_>, executor:&dm_exec::BuildExecutor,
    host:&Arc<dyn SettingExpressionQueries>,
    read:&dyn Fn(&Path)->std::io::Result<Option<Arc<dm_preprocess::regions::prepared_source::PreparedSource>>>,
)->Result<GenerationDeclarationFrame,GenerationPreparationFailure>{
    prepare_generation_declarations_inner(project,provider,defines,omissions,config,executor,host,read,true)
}

fn prepare_generation_declarations_inner<P:SourceProvider>(
    project:&Path, provider:&P, defines:&BTreeMap<String,String>,
    omissions:dm_preprocess::regions::GenerationOmissions,
    config:FrontendConfig<'_>, executor:&dm_exec::BuildExecutor,
    host:&Arc<dyn SettingExpressionQueries>,
    read:&dyn Fn(&Path)->std::io::Result<Option<Arc<dm_preprocess::regions::prepared_source::PreparedSource>>>,
    questions:bool,
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
        Ok(GenerationDeclarationFrame{plan,parsed,question_expansion:questions.then_some(expanded),question_host:questions.then(||Arc::downgrade(host))})
    })();
    // Operational failure is never replaced by a later checkpoint or turned
    // into an absent generated file/source diagnostic.
    if matches!(&result,Err(GenerationPreparationFailure::Frontend(FrontendBuildFailure::Operational(_)))){return result}
    demand.run(|permit|permit.checkpoint()).map_err(GenerationPreparationFailure::Frontend)?;
    result
}

/// Actual native resolution of the incomplete generation traversal. It is not a
/// ColdFrontend, BodyArchive, PolicyInputs or complete-program source receipt.
/// Only the existing declaration builder creates its tree; executable bodies
/// use the existing BodySyntaxInput/Kind4 producer with exact current owners.
pub struct GenerationNativeQuestions {
    geometry: Arc<GenerationQuestionGeometry>,
    snapshot: TreeSnapshot,
    syntax: Arc<DeclarationSyntax>,
    bodies: Vec<BodyOccurrence>,
    expanded_spans:Vec<Span>,
    inputs: Vec<Arc<BodySyntaxInput>>,
    bodies_in_span_order:bool,
    host: Arc<dyn BodySyntaxQueries>,
    allocation_ledger: crate::allocation_ledger::AllocationLedger,
    // LAST: retained span backing is physically freed before its same-counter credit.
    retained_metadata:dm_syntax::SettingRootLease,
}
pub(super) struct GenerationQuestionGeometry {
    plan:dm_preprocess::regions::GenerationDirectivePlan,
    pub(super) expanded:ExpandedRegions,
    files:Vec<SourceFile>,
    by_path:Arc<HashMap<PathBuf,FileId>>,
}
impl std::fmt::Debug for GenerationQuestionGeometry {
    fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result {f.debug_struct("GenerationQuestionGeometry").field("files",&self.files.len()).finish_non_exhaustive()}
}
impl GenerationQuestionGeometry {
    pub(super) fn output(&self,offset:usize)->Option<SourceLocation>{
        Mapping{projection:Default::default(),plan:self.plan.source_geometry(),expanded:&self.expanded,files:&self.files,by_path:&self.by_path,hints:Default::default()}.output(offset)
    }
}
impl GenerationDeclarationFrame {
    /// Consumes the same parsed declarations exactly once. There is no retry as
    /// ordinary compiler input and no second lexer/parser or legacy model.
    pub fn into_native_questions(self,config:FrontendConfig<'_>,executor:&dm_exec::BuildExecutor,host:Arc<dyn BodySyntaxQueries>,control:&Arc<dyn SettingExpressionQueries>)->Result<GenerationNativeQuestions,GenerationPreparationFailure>{
        let demand=super::declaration_demand::Checked{host:control};
        let result=(||{
            demand.run(|permit|permit.checkpoint()).map_err(GenerationPreparationFailure::Frontend)?;
            let Self{plan,parsed,question_expansion,question_host}=self;
            if !question_host.and_then(|w|w.upgrade()).is_some_and(|issued|Arc::ptr_eq(&issued,control)) || !std::ptr::eq(Arc::as_ptr(control).cast::<()>(),Arc::as_ptr(&host).cast::<()>()){return Err(GenerationPreparationFailure::Assembly(vec![internal("generation question host differs from actual declaration admission owner")]))}
            let expanded=question_expansion.ok_or_else(||GenerationPreparationFailure::Assembly(vec![internal("generation question preparation was not selected before parsing")]))?;
            if plan.original_sources().any(|(_,lease)|lease.is_none()){return Err(GenerationPreparationFailure::Assembly(vec![internal("generation question actual original acquisition is absent")]))}
            let geometry=plan.source_geometry();
            // An omitted generated include retains only directive/dependency metadata,
            // never a source/text placeholder.
            // Every actual source occurrence used here must be genuinely captured.
            if geometry.regions.iter().any(|r|!geometry.source_texts.contains_key(geometry.occurrences[r.occurrence].path.as_ref())){return Err(GenerationPreparationFailure::Assembly(vec![internal("generation question source occurrence is unacquired")]))}
            let (files,by_path)=super::pipeline::build_source_index_geometry(geometry,geometry.source_texts,true).map_err(GenerationPreparationFailure::Assembly)?;
            let mapping=Mapping{projection:Default::default(),plan:geometry,expanded:&expanded,files:&files,by_path:&by_path,hints:Default::default()};
            let super::declaration_parse::ParsedDeclarations{syntax,mut adapted,allocation_ledger,..}=parsed;
            // This vector was transient in the common pipeline; generation now
            // retains it. Fund its actual bounded backing BEFORE projection.
            let span_capacity=adapted.origins.len().checked_mul(4).ok_or_else(||GenerationPreparationFailure::Frontend(FrontendBuildFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"generation retained span capacity overflow"))))?;
            let metadata_bytes=span_capacity.checked_mul(std::mem::size_of::<Span>()).and_then(|n|n.checked_add(std::mem::size_of::<Vec<Span>>()+std::mem::size_of::<dm_syntax::SettingRootLease>()+4*std::mem::size_of::<usize>())).ok_or_else(||GenerationPreparationFailure::Frontend(FrontendBuildFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"generation retained metadata overflow"))))?;
            let retained_metadata=demand.run(|permit|permit.retain_generation_metadata(metadata_bytes)).map_err(GenerationPreparationFailure::Frontend)?;
            let (spans,_regions,origins)=super::pipeline::project_declaration_origins(&mapping,&adapted.origins).map_err(GenerationPreparationFailure::Assembly)?;
            if spans.capacity()>span_capacity{return Err(GenerationPreparationFailure::Frontend(FrontendBuildFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"generation retained span capacity exceeds admission"))))}
            adapted.origins=origins;
            let mut failure=None;
            // The SAME native assembly/builtin catalogue rules. No fabricated
            // empty tree or conversion from the missing-output role exists.
            observe(config,FrontendStage::TreeResolution,ProgressKind::Started,Duration::ZERO,0,adapted.skeletons.len());
            let resolution_start=Instant::now();
            let symbols=adapted.symbols.clone();
            let snapshot=adapted.finish_with_engine_observed_on_executor(config.engine,|error,skeletons,origins|{failure=Some(duplicate_diagnostics::resolve(error,skeletons,origins,&mapping,config.engine.is_some(),&symbols,config.engine.map_or(&[][..],|seed|&seed.intrinsics[..])));},executor);
            let snapshot=snapshot.map_err(|_|GenerationPreparationFailure::Assembly(failure.expect("native resolver notifies original error observer")))?;
            observe(config,FrontendStage::TreeResolution,ProgressKind::Completed,resolution_start.elapsed(),snapshot.tree.declarations().len(),snapshot.tree.declarations().len());
            let declarations=super::pipeline::resolved_callable_declarations(&spans,&snapshot.tree);
            let syntax=Arc::new(syntax);let mut bodies=Vec::new();let mut settings=Vec::new();let mut codes=Vec::new();
            collect_bodies(&syntax,&snapshot.tree,&declarations,&mapping,&mut bodies,&mut settings,&mut codes).map_err(GenerationPreparationFailure::Assembly)?;
            let bodies_in_span_order=bodies.windows(2).all(|pair|pair[0].expanded_span.start<pair[1].expanded_span.start);
            drop(mapping);drop(settings);
            let geometry=Arc::new(GenerationQuestionGeometry{plan,expanded,files,by_path});
            host.begin_revision();
            let inputs=bodies.iter().zip(codes).map(|(body,code)|super::body_queries::issue_generation_body(&geometry,&syntax,body,code)).collect();
            Ok(GenerationNativeQuestions{geometry,snapshot,syntax,bodies,expanded_spans:spans,inputs,bodies_in_span_order,host,allocation_ledger,retained_metadata})
        })();
        if matches!(&result,Err(GenerationPreparationFailure::Frontend(FrontendBuildFailure::Operational(_)))){return result}
        demand.run(|permit|permit.checkpoint()).map_err(GenerationPreparationFailure::Frontend)?;
        result
    }
}
impl GenerationNativeQuestions {
    /// The actual incomplete native graph, for explicit generation policies.
    /// This reference cannot satisfy an ordinary source/ABI/checker role.
    pub fn body_host_is(&self,expected:&dyn BodySyntaxQueries)->bool{std::ptr::eq(Arc::as_ptr(&self.host).cast::<()>(),(expected as *const dyn BodySyntaxQueries).cast::<()>())}
    pub fn tree(&self)->&crate::SemanticTree{&self.snapshot.tree}
    pub fn source_file_count(&self)->usize{self.geometry.files.len()}
    pub fn root_source(&self)->Option<&Path>{self.geometry.plan.root_source()}
    pub fn file_id_for_path(&self,path:&Path)->Option<FileId>{self.geometry.by_path.get(path).copied()}
    /// Exact original qualifier issuance; source metadata is not inferred from spelling.
    pub fn variable_qualifiers_original_at(&self,formal:MemberId,ordinal:OccurrenceId,profile:dm_ir::PackedU128,proof:&crate::checker_builtins::ValidatedCheckerProfile<'_>)->Result<u8,String>{
        proof.require(self.tree(),profile).map_err(|e|format!("generation variable profile: {e:?}"))?;
        if self.snapshot.tree.declarations().get(ordinal.0 as usize)!=Some(&Target::Member(formal)){return Err("generation variable occurrence belongs to another actual declaration".into())}
        let node=self.tree().member(formal).ok_or("generation qualifier formal unavailable")?;
        if node.kind!=MemberKind::Var||node.definition!=crate::DefinitionMode::Declare||node.metadata.inherited_opaque.is_some(){return Err("generation qualifier needs exact authored formal".into())}
        let span=self.expanded_spans.get(ordinal.0 as usize).ok_or("generation variable original span missing")?;
        self.syntax.declaration_cursor_at_for_policy(span.start as usize).ok_or("generation original declaration cursor unissued")?;
        let flags=self.syntax.declaration_checker_qualifiers_at_for_policy(span.start as usize).ok_or("generation original variable qualifiers unavailable")?;
        if flags==dm_syntax::UNKNOWN_HEADER_QUALIFIERS||flags & !dm_syntax::CHECKER_VAR_MASK!=0{return Err("generation original variable qualifiers unissued".into())}Ok(flags)
    }
    pub fn variable_properties_original_at(&self,formal:MemberId,ordinal:OccurrenceId,profile:dm_ir::PackedU128,proof:&crate::checker_builtins::ValidatedCheckerProfile<'_>)->Result<CheckerVariableProperties<'_>,String>{
        super::body_archive::properties_for_issued_original(self.tree(),formal,||self.variable_qualifiers_original_at(formal,ordinal,profile,proof))
    }
    pub fn omissions(&self)->impl Iterator<Item=&Path>{self.geometry.plan.omissions()}
    pub fn original_sources(&self)->dm_preprocess::regions::GenerationOriginalSources<'_>{self.geometry.plan.original_sources()}
    pub fn bodies(&self)->&[BodyOccurrence]{&self.bodies}
    /// New generation-only retained backing. The phase subtracts this live
    /// same-counter reservation before minting its operation Budget.
    pub fn generation_metadata_charge(&self)->usize{self.retained_metadata.bytes()}
    /// DATA-only work shape; false keeps a checked fallback, no source authority.
    pub fn generation_definition_lookup_is_binary(&self)->bool{self.bodies_in_span_order}
    pub fn visit_generation_metadata(&self,mut visit:impl FnMut(usize,usize)){
        visit(&self.expanded_spans as *const _ as usize,std::mem::size_of::<Vec<Span>>());
        if self.expanded_spans.capacity()!=0{visit(self.expanded_spans.as_ptr() as usize,self.expanded_spans.capacity()*std::mem::size_of::<Span>())}
        visit(&self.retained_metadata as *const _ as usize,std::mem::size_of::<dm_syntax::SettingRootLease>());
        visit(&self.bodies_in_span_order as *const _ as usize,std::mem::size_of::<bool>());
        self.retained_metadata.visit_counter_storage(&mut visit);
    }
    pub fn source_point(&self,offset:usize)->Option<SourceLocation>{self.geometry.output(offset)}
    pub fn original_note_point(&self,offset:usize)->Result<GenerationSourcePoint<'_>,&'static str>{
        let plan=self.geometry.plan.source_geometry();
        let point=super::source_export_mapping::original_note_point_in(&self.geometry.expanded.origins,offset,|region|{let include=plan.regions.get(region).ok_or("note region unavailable")?.occurrence;let lease=plan.source_acquisitions.get(&include).ok_or("note original acquisition unavailable")?;Ok((include,lease))},|include|Ok(&plan.occurrences.get(include).ok_or("note include coordinates unavailable")?.path))?;Ok(GenerationSourcePoint{path:point.path.as_path(),line:point.line,byte_column:point.byte_column})
    }
    pub fn with_body_checked_using<R>(&self,ordinal:usize,obtain:impl FnOnce(&Arc<BodySyntaxInput>,&dyn BodySyntaxQueries)->Result<Arc<BodySyntax>,BodySyntaxFailure>,consume:impl for<'body>FnOnce(GenerationBodyLoan<'body>)->Result<R,BodySyntaxFailure>)->Result<R,BodySyntaxFailure>{
        let input=self.inputs.get(ordinal).ok_or_else(||BodySyntaxFailure::Syntax(internal("generation body ordinal is outside actual callable roster")))?;
        self.host.prepare_checked_input(input)?;
        let value=input.obtain_checked_using(|input|obtain(input,self.host.as_ref()))?;
        consume(GenerationBodyLoan{syntax:&value,questions:self,ordinal})
    }
}
/// A callback-local loan, with no BodySyntax/StatementBody Arc escape API.
pub struct GenerationBodyLoan<'a>{syntax:&'a BodySyntax,questions:&'a GenerationNativeQuestions,ordinal:usize}
impl GenerationBodyLoan<'_>{
    pub fn statements(&self)->&StatementBody{&self.syntax.statements}
    pub fn source_locals(&self)->Result<SourceLocalView<'_>,String>{super::body_archive::checked_source_locals(self.questions.tree(),&self.questions.bodies[self.ordinal],self.statements(),&self.questions.geometry.expanded.text)}
    pub fn source_parameters(&self)->Result<SourceParameterView<'_>,String>{super::body_archive::checked_source_parameters(self.questions.tree(),&self.questions.bodies[self.ordinal],&self.syntax.item,&self.syntax.parameters,&self.questions.geometry.expanded.text)}
    pub fn item(&self)->&Item{&self.syntax.item}
    pub fn parameters(&self)->&dm_syntax::ParameterSignature{&self.syntax.parameters}
}

/// Borrowed original declaration identity and physical primary source point.
/// No file/model rows or source owner can escape this callback-local view.
pub struct GenerationDefinitionPoint<'a>{
    pub member:MemberId,pub ordinal:OccurrenceId,pub line:usize,
    pub owner:&'a str,pub name:&'a str,pub path:&'a Path,
}
impl GenerationNativeQuestions{
    pub fn visit_definition_points<'a,E:From<String>+From<&'static str>>(&'a self,checkpoint:&mut impl FnMut()->Result<(),E>,emit:&mut impl FnMut(GenerationDefinitionPoint<'a>)->Result<(),E>)->Result<(),E>{
        let tree=self.tree();
        for(index,target)in tree.declarations().iter().enumerate(){
            checkpoint()?;let Target::Member(member)=*target else{continue};let node=tree.member(member).ok_or("generation definition member unavailable")?;
            let owner_id=tree.type_node(node.owner).ok_or("generation definition owner unavailable")?.path;
            let owner=tree.symbols().text(owner_id).ok_or("generation definition owner spelling unavailable")?;
            let name=tree.symbols().text(node.name).ok_or("generation definition name unavailable")?;
            let ordinal=OccurrenceId(u32::try_from(index).map_err(|_|"generation definition ordinal overflow")?);
            let cursor=match node.kind{
                MemberKind::Var=>{
                    if node.definition!=crate::DefinitionMode::Declare{continue}
                    if tree.source_formal_variable_member(owner_id,node.name).map_err(str::to_owned)?!=Some(member){continue}
                    if node.metadata.inherited_opaque.is_some()||node.metadata.procedure.is_some(){return Err("generation original variable metadata opaque".into())}
                    let span=self.expanded_spans.get(index).ok_or("generation definition expanded span unavailable")?;
                    self.syntax.declaration_cursor_at_for_policy(span.start as usize).ok_or("generation original variable cursor unissued")?
                },
                MemberKind::Proc|MemberKind::Verb=>{
                    let start=usize::try_from(self.expanded_spans.get(index).ok_or("generation callable expanded span unavailable")?.start).map_err(|_|"generation callable original span overflow")?;
                    // Actual body recipes are normally source ordered: O(log B),
                    // no new index/ABI/dependent roster. An unordered producer
                    // uses a polled O(B) fallback; its availability is unqualified.
                    let body=if self.bodies_in_span_order{self.bodies.binary_search_by_key(&start,|body|body.expanded_span.start).ok()}else{let mut found=None;for(i,body)in self.bodies.iter().enumerate(){checkpoint()?;if body.declaration==ordinal&&body.member==member{found=Some(i);break}}found}.ok_or("generation callable original occurrence unavailable")?;
                    if self.bodies[body].declaration!=ordinal||self.bodies[body].member!=member{return Err("generation callable original occurrence differs".into())}
                    self.inputs.get(body).ok_or("generation callable input unavailable")?.original_opening()?
                },
            };
            let point=self.original_note_point(cursor)?;
            emit(GenerationDefinitionPoint{member,ordinal,line:point.line,owner,name,path:point.path})?;
        }checkpoint()?;Ok(())
    }
}

/// Physical original token point for generation data only. This carries no
/// compiler FileList registration or ordinary checker-location capability.
pub struct GenerationSourcePoint<'a>{pub path:&'a Path,pub line:usize,pub byte_column:usize}
