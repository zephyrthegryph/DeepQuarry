//! Optional body-syntax queries supplied by the compiler's existing query host.
//! Query keys are issuance-local, never authority minted from matching bytes.
use super::*;

/// Only the frontend can create this captured input. Query parameters hold it
/// weakly, so keeping graph metadata cannot retain obsolete source revisions.
#[derive(Debug)]
pub struct BodySyntaxInput {
    id: u64,
    source: dm_preprocess::SourceText,
    syntax: Arc<DeclarationSyntax>,
    span: dm_syntax::Span,
    location: SourceLocation,
    mapping: BodyDiagnosticProjection,
    parameter_admission: usize,
    original_code: Option<Arc<BodyCodeIdentity>>,
}

#[derive(Debug)]
enum BodyDiagnosticProjection {
    Complete(Arc<SourceExportMapping>),
    Generation(Arc<super::generation::GenerationQuestionGeometry>),
}
impl BodyDiagnosticProjection {
    fn output(&self,offset:usize)->Option<SourceLocation>{match self{Self::Complete(mapping)=>mapping.output(offset),Self::Generation(mapping)=>mapping.output(offset)}}
}
// Existing issuance counter is shared by complete and generation-only inputs.
// Query key equality never substitutes for the actual private input issuer.
static NEXT_BODY_INPUT:std::sync::atomic::AtomicU64=std::sync::atomic::AtomicU64::new(1);

/// One immutable parse, borrowed by lowering, lint policies and checker passes.
/// Lossless children remain available for unsupported lowering constructs.
pub struct BodySyntax {
    issuance: u64,
    pub(super) item: Item,
    pub(super) opening_parenthesis: Option<dm_syntax::Span>,
    pub(super) parameters: dm_syntax::SharedParameterSignature,
    pub(super) statements: Arc<StatementBody>,
    input_bytes: usize,
    // Parser-product DATA only; no SourceSnapshot/tree/current model retained.
    original_code: Arc<BodyCodeIdentity>,
    original_window: dm_syntax::Span,
    original_body_span:dm_syntax::Span,
}

impl BodySyntaxInput {
    pub(super) fn original_opening(&self)->Result<usize,String>{self.syntax.original_callable_opening(self.span,self.original_code.as_ref().ok_or("generation callable original code unissued")?)}
    pub fn key(&self) -> u64 {
        self.id
    }
    pub(super) fn captured_span(&self)->dm_syntax::Span{self.span}

    /// Pre-parse admission estimate, including a header-only receipt upper bound.
    /// This is a bounded-cohort estimate, not a bound on allocations or RSS.
    pub fn budget_charge(&self) -> usize {
        syntax_budget_charge(self.span.end.saturating_sub(self.span.start))
            .saturating_add(self.parameter_admission)
    }
    pub(super) fn obtain(
        self: &Arc<Self>,
        host: &dyn BodySyntaxQueries,
    ) -> Result<Arc<BodySyntax>, Diagnostic> {
        let syntax = host.syntax(self)?;
        if syntax.issuance != self.id {
            return Err(internal("body query returned a foreign parser issuance"));
        }
        Ok(syntax)
    }
    pub(super) fn obtain_checked(
        self: &Arc<Self>,
        host: &dyn BodySyntaxQueries,
    ) -> Result<Arc<BodySyntax>, BodySyntaxFailure> {
        self.obtain_checked_using(|input|host.syntax_checked(input))
    }
    pub(super) fn obtain_checked_using(
        self:&Arc<Self>,
        obtain:impl FnOnce(&Arc<Self>)->Result<Arc<BodySyntax>,BodySyntaxFailure>,
    )->Result<Arc<BodySyntax>,BodySyntaxFailure>{
        let syntax=obtain(self)?;
        if syntax.issuance!=self.id{return Err(internal("body query returned a foreign parser issuance").into())}
        Ok(syntax)
    }
    /// Standalone compatibility behavior remains the same explicit parser path.
    pub fn parse(&self) -> Result<BodySyntax, Diagnostic> {
        self.parse_using(|item| {
            Ok(body_archive::parse_statements(
                item,
                &self.source,
                &self.syntax,
                |_| false,
            ))
        })
    }
    /// Native Kind4 supplies its DIRECT stack capability; a setting leaf never
    /// invokes another query/provider/gate or resets this operation budget.
    pub fn parse_with_setting_admission(
        &self,
        admission: &dm_syntax::SettingAdmission<'_>,
    ) -> Result<BodySyntax, BodySyntaxFailure> {
        let result = self.parse_using_observed(Some((admission, BodySyntaxFailure::Operational)), |item| {
            body_archive::parse_statements_with_body_literal_admission(
                item,
                &self.source,
                &self.syntax,
                self.span,
                self.original_code.as_ref(),
                admission,
                |_| false,
            )
        }, &mut |_|{});
        if matches!(&result, Err(BodySyntaxFailure::Operational(_))) {
            return match admission.take_operational_error() {
                Some(actual) => Err(BodySyntaxFailure::Operational(actual)),
                None => result,
            };
        }
        let last = admission.checkpoint();
        if let Some(actual) = admission.take_operational_error() {
            return Err(BodySyntaxFailure::Operational(actual));
        }
        last.map_err(BodySyntaxFailure::Operational)?;
        result
    }
    fn parse_using<E: From<Diagnostic>>(
        &self,
        parse_statements: impl FnOnce(&mut Item) -> Result<Arc<StatementBody>, E>,
    ) -> Result<BodySyntax, E> {
        self.parse_using_observed(None,parse_statements,&mut |_|{})
    }
    fn parse_using_observed<E:From<Diagnostic>>(&self,admission:Option<(&dm_syntax::SettingAdmission<'_>,fn(std::io::Error)->E)>,parse_statements:impl FnOnce(&mut Item)->Result<Arc<StatementBody>,E>,observe:&mut dyn FnMut(&dm_syntax::Diagnostic))->Result<BodySyntax,E>{
        let code=self.original_code.as_ref().ok_or_else(||internal("original body code input is unissued"))?;
        let recipe=self.syntax.original_body_recipe(self.span,code).map_err(|error|{observe(&error);Diagnostic{kind:syntax_kind(error.kind),stage:DiagnosticStage::Syntax,location:self.mapping.output(error.span.start).or_else(||Some(self.location.clone())),message:error.message}})?;
        let original_window=recipe.source_window().map_err(internal)?;
        let issued = match admission {
            Some((a, operational)) => recipe.parse_original_admitted(a).map_err(operational)?,
            None => recipe.parse_original(),
        };
        let mut issued = issued.map_err(|error| {observe(&error);Diagnostic {
                kind: syntax_kind(error.kind),
                stage: DiagnosticStage::Syntax,
                location: self
                    .mapping
                    .output(error.span.start)
                    .or_else(|| Some(self.location.clone())),
                message: error.message,
            }})?;
        issued
            .parameters
            .admit_optional_expressions(self.parameter_admission);
        if issued.parameters.retained_bytes() > self.parameter_admission {
            return Err(
                internal("primary parameter receipt exceeded original header admission").into(),
            );
        }
        let mut item = issued.item;
        let statements = parse_statements(&mut item)?;
        Ok(BodySyntax {
            issuance: self.id,
            opening_parenthesis: issued.opening_parenthesis,
            parameters: issued.parameters.into_shared(),
            item,
            statements,
            input_bytes: self.span.end.saturating_sub(self.span.start),
            original_code: Arc::clone(code),
            original_window,
            original_body_span:self.span,
        })
    }
}
impl std::fmt::Debug for BodySyntax {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("BodySyntax")
            .field("issuance", &self.issuance)
            .field("input_bytes", &self.input_bytes)
            .finish_non_exhaustive()
    }
}
impl BodySyntax {
    pub fn parameter_storage(&self) -> &dm_syntax::SharedParameterSignature {
        &self.parameters
    }
    /// Borrow canonical parser DATA. This does not issue a current source,
    /// frontend, completed setting model or compiler-admissible body.
    pub fn statement_storage(&self)->&Arc<StatementBody>{&self.statements}

    /// Provisional admission charge until the shared ownership census supplies
    /// exact AST allocation sizes. Does not claim to measure process RSS.
    pub fn budget_charge(&self) -> usize {
        syntax_budget_charge(self.input_bytes)
            .saturating_add(self.parameters.retained_bytes())
            .saturating_add(
                self.statements
                    .parsed()
                    .local_variables
                    .retained_admission(),
            )
    }
}

fn syntax_budget_charge(input_bytes: usize) -> usize {
    input_bytes.saturating_mul(64).saturating_add(4096)
}

#[cfg(test)]
mod budget_tests {
    #[test]
    fn input_and_result_admission_estimate_has_shared_saturating_boundaries() {
        assert_eq!(super::syntax_budget_charge(0), 4096);
        assert_eq!(super::syntax_budget_charge(1), 4160);
        assert_eq!(super::syntax_budget_charge(usize::MAX), usize::MAX);
    }

    #[test]
    fn original_body_syntax_charge_includes_real_local_array_owners() {
        use std::{path::Path, sync::Arc};
        struct Original(dm_preprocess::AcquiredSource);
        impl dm_preprocess::SourceProvider for Original {
            fn read(&self, _: &Path) -> Result<String, String> {
                Err("original acquisition required".into())
            }
            fn acquired_source(
                &self,
                _: &Path,
            ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
                Ok(Some(self.0.clone()))
            }
            fn source_acquisition(
                &self,
                _: &Path,
                text: &dm_preprocess::SourceText,
            ) -> Option<dm_preprocess::AcquiredSource> {
                self.0
                    .lease()
                    .source_text()
                    .same_view(text)
                    .then(|| self.0.clone())
            }
        }
        #[derive(Debug)]
        struct Observe;
        impl super::BodySyntaxQueries for Observe {
            fn syntax(
                &self,
                input: &Arc<super::BodySyntaxInput>,
            ) -> Result<Arc<super::BodySyntax>, super::Diagnostic> {
                let syntax = input.parse()?;
                let actual = syntax
                    .statements
                    .parsed()
                    .local_variables
                    .retained_admission();
                assert!(actual > 0);
                assert_eq!(
                    syntax.budget_charge(),
                    super::syntax_budget_charge(syntax.input_bytes)
                        .saturating_add(syntax.parameters.retained_bytes())
                        .saturating_add(actual)
                );
                Ok(Arc::new(syntax))
            }
        }
        let source = Original(dm_preprocess::AcquiredSource::from_original_bytes(
            b"/proc/p()\n    var/x[3][4]\n".to_vec(),
            (),
        ));
        let frontend = crate::frontend::build(
            Path::new("array-budget.dme"),
            &source,
            &Default::default(),
            1,
        )
        .unwrap()
        .with_body_queries(Arc::new(Observe));
        let archive = frontend.body_archive().unwrap();
        assert!(archive.parse(0).is_ok());
    }
}

pub trait BodySyntaxQueries: std::fmt::Debug + Send + Sync {
    /// Quiescent admission boundary: collect expired issuance metadata once,
    /// never scan the whole graph for every body in a large program.
    fn begin_revision(&self) {}
    /// Refresh only already-registered canonical locators before pruning old
    /// weak issuances. No parse, source/model or new cache is created here.
    fn begin_revision_inputs(&self,_:&[Arc<BodySyntaxInput>]){self.begin_revision()}
    fn prepare_syntax_product_input(&self,_:&Arc<BodySyntaxInput>)->Result<(),BodySyntaxFailure>{
        Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"native current BODY context preparation is unavailable")))
    }
    /// Additive canonical product route. Default is an explicit unavailable
    /// native contract, never a compatibility parse or a second frontend.
    fn syntax_product_checked(&self,_:&Arc<BodySyntaxInput>)->Result<Arc<OriginalBodySyntaxProduct>,BodySyntaxFailure>{
        Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"native canonical BODY product contract is not implemented by this host")))
    }
    /// Preserve this host's existing input registration/eviction before a
    /// direct active-context loan. Does not get/parse/reset any query.
    fn prepare_checked_input(&self,_:&Arc<BodySyntaxInput>)->Result<(),BodySyntaxFailure>{Ok(())}
    fn syntax(&self, input: &Arc<BodySyntaxInput>) -> Result<Arc<BodySyntax>, Diagnostic>;
    /// Compatibility hosts have syntax failures only. Native hosts must
    /// override this before admitted settings can produce operational errors.
    /// No default converts quota/cancellation into a fabricated Diagnostic.
    fn syntax_checked(
        &self,
        input: &Arc<BodySyntaxInput>,
    ) -> Result<Arc<BodySyntax>, BodySyntaxFailure> {
        self.syntax(input).map_err(BodySyntaxFailure::Syntax)
    }
}

#[derive(Clone, Debug)]
pub(super) struct BodyQueries {
    pub host: Arc<dyn BodySyntaxQueries>,
    pub inputs: Arc<[Arc<BodySyntaxInput>]>,
}

impl ColdFrontend {
    /// Opt in only after declaration construction. The source, occurrence list
    /// and syntax are captured together; callers cannot substitute foreign ASTs.
    pub fn with_body_queries(mut self, host: Arc<dyn BodySyntaxQueries>) -> Self {
        if self.reused_body_queries
            && self.source_export_mapping().is_some()
            && self.callable_roster().is_ok()
            && self
                .body_queries
                .as_ref()
                .is_some_and(|queries| Arc::ptr_eq(&queries.host, &host))
        {
            // Native same-original-acquisition/whole-program proof reissued the
            // source wrapper; the immutable original parser input is unchanged.
            self.reused_body_queries = false;
            return self;
        }
        self.reused_body_queries = false;
        let inputs:Arc<[Arc<BodySyntaxInput>]> = self
            .issued_bodies
            .iter()
            .enumerate()
            .map(|(ordinal, body)| {
                Arc::new(BodySyntaxInput {
                    id: NEXT_BODY_INPUT.fetch_add(1, std::sync::atomic::Ordering::Relaxed),
                    original_code: self
                        .issued_body_codes
                        .get(ordinal)
                        .map(|owner| Arc::clone(&owner.identity)),
                    source: self.issued_arena.clone(),
                    syntax: self.issued_syntax.clone(),
                    span: body.expanded_span,
                    location: body.source.clone(),
                    mapping: BodyDiagnosticProjection::Complete(Arc::clone(&self.source_export_mapping)),
                    parameter_admission: self
                        .issued_syntax
                        .item_path(&body.ast_path)
                        .map(|item| {
                            item.header_span()
                                .end
                                .saturating_sub(item.header_span().start)
                                .saturating_mul(128)
                                .saturating_add(1024)
                        })
                        .unwrap_or(usize::MAX),
                })
            })
            .collect::<Vec<_>>()
            .into();
        host.begin_revision_inputs(&inputs);
        self.body_queries = Some(BodyQueries { host, inputs });
        self
    }
}


pub(super) fn issue_generation_body(
    geometry:&Arc<super::generation::GenerationQuestionGeometry>,
    syntax:&Arc<DeclarationSyntax>, body:&BodyOccurrence, code:Arc<BodyCodeIdentity>,
)->Arc<BodySyntaxInput>{
    Arc::new(BodySyntaxInput{
        id:NEXT_BODY_INPUT.fetch_add(1,std::sync::atomic::Ordering::Relaxed),
        source:geometry.expanded.text.clone(),syntax:Arc::clone(syntax),
        span:body.expanded_span,location:body.source.clone(),
        mapping:BodyDiagnosticProjection::Generation(Arc::clone(geometry)),
        parameter_admission:syntax.item_path(&body.ast_path).map(|item|item.header_span().end.saturating_sub(item.header_span().start).saturating_mul(128).saturating_add(1024)).unwrap_or(usize::MAX),
        original_code:Some(code),
    })
}

#[cfg(test)]
mod optional_header_root_acceptance_tests {
    use super::*;
    struct Original(dm_preprocess::AcquiredSource);
    impl dm_preprocess::SourceProvider for Original {
        fn read(&self, _: &Path) -> Result<String, String> {
            Err("exact original acquisition required".into())
        }
        fn acquired_source(
            &self,
            _: &Path,
        ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
            Ok(Some(self.0.clone()))
        }
        fn source_acquisition(
            &self,
            _: &Path,
            text: &dm_preprocess::SourceText,
        ) -> Option<dm_preprocess::AcquiredSource> {
            self.0
                .lease()
                .source_text()
                .same_view(text)
                .then(|| self.0.clone())
        }
    }
    #[derive(Debug)]
    struct Observe;
    impl BodySyntaxQueries for Observe {
        fn syntax(&self, input: &Arc<BodySyntaxInput>) -> Result<Arc<BodySyntax>, Diagnostic> {
            let syntax = input.parse()?;
            assert!(syntax.parameters.retained_bytes() <= input.parameter_admission);
            Ok(Arc::new(syntax))
        }
    }
    #[test]
    fn deep_or_large_optional_header_roots_preserve_actual_native_body_syntax() {
        for expression in [
            std::iter::repeat_n("1", 600).collect::<Vec<_>>().join("+"),
            format!("{}1{}", "(".repeat(128), ")".repeat(128)),
            format!("\"{}\"", "[missing()]".repeat(7000)),
            format!("\"[{}1]\"", "!".repeat(4000)),
        ] {
            let source = format!("/proc/p(x={expression})\n    return 1\n");
            let provider = Original(dm_preprocess::AcquiredSource::from_original_bytes(
                source.as_bytes().to_vec(),
                (),
            ));
            let frontend = build(
                Path::new("optional-root-original.dme"),
                &provider,
                &Default::default(),
                1,
            )
            .unwrap()
            .with_body_queries(Arc::new(Observe));
            let archive = frontend.body_archive().unwrap();
            let body = archive.parse(0).unwrap();
            assert!(body.statement_body().syntax_complete());
            let parameters = body.parameter_storage();
            let entry = &parameters.entries().unwrap()[0];
            assert_eq!(entry.type_path(archive.expanded_source()).unwrap(), None);
            assert!(
                entry.expressions().is_err(),
                "optional root error is not body/type-path refusal"
            );
            assert!(matches!(
                body.statement_body().parsed().statements[0].kind,
                dm_syntax::StatementKind::Return(Some(_))
            ));
        }
    }
    #[test]
    fn dense_optional_headers_use_the_actual_body_query_admission_gate() {
        let parameters = (0..96)
            .map(|n| format!("x{n}={}1", "!".repeat(96)))
            .collect::<Vec<_>>()
            .join(",");
        let source = format!("/proc/p({parameters})\n    return 1\n");
        let provider = Original(dm_preprocess::AcquiredSource::from_original_bytes(
            source.as_bytes().to_vec(),
            (),
        ));
        let frontend = build(
            Path::new("dense-optional-root.dme"),
            &provider,
            &Default::default(),
            1,
        )
        .unwrap()
        .with_body_queries(Arc::new(Observe));
        let archive = frontend.body_archive().unwrap();
        let body = archive.parse(0).unwrap();
        assert!(body.statement_body().syntax_complete());
        assert_eq!(body.parameter_storage().entries().unwrap().len(), 96);
    }
}

/// A source-neutral original product is never accepted as a foreign current AST.
/// This borrowed binding is issued ONLY by the actual private current input and
/// its original current code/header recipe, under this host's native admission.
/// The existing obtain/foreign-issuance API remains strict and unchanged.
pub struct CurrentBodySyntax<'a>{original:&'a BodySyntax,input:&'a BodySyntaxInput,projection:dm_syntax::SyntaxProjection,deferred_literal_roots:usize}
fn binding_error(message:&str)->BodySyntaxFailure{BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,message))}
fn binding_view_error(error:dm_syntax::SyntaxViewError)->BodySyntaxFailure{binding_error(&format!("actual original code projection differs: {error:?}"))}
impl BodySyntaxInput{
 pub fn bind_original_product_checked<'a>(&'a self,original:&'a BodySyntax,admission:&dm_syntax::SettingAdmission<'_>)->Result<CurrentBodySyntax<'a>,BodySyntaxFailure>{
  let pending=(||{admission.checkpoint().map_err(BodySyntaxFailure::Operational)?;
   let code=self.original_code.as_ref().ok_or_else(||binding_error("current body code is unissued"))?;
   if !Arc::ptr_eq(code,&original.original_code){return Err(binding_error("current body code is not the parser product's original code owner"))}
   let recipe=self.syntax.original_body_recipe(self.span,code).map_err(|_|binding_error("current native body recipe does not authenticate code/span"))?;
   // Actual current capture authenticated this private code identity. Only
   // parser-code DATA can converge: its current header/model owner is fresh.
   recipe.setting_headers().ok_or_else(||binding_error("current original header owner is absent"))?;
   if !original.statements.is_native_literal_syntax_admitted_by(admission){return Err(binding_error("parser product belongs to another native resource domain"))}
   let current_window=recipe.source_window().map_err(binding_error)?;
   if original.original_body_span.start<original.original_window.start||original.original_body_span.end>original.original_window.end||self.span.start<current_window.start||self.span.end>current_window.end{return Err(binding_error("actual original/current body escaped its primary source window"))}
   let projection=dm_syntax::SyntaxProjection::new(original.original_body_span,self.span).map_err(BodySyntaxFailure::Operational)?;
   dm_syntax::ProjectedParameterSignature::new(&original.parameters,projection).map_err(binding_view_error)?;
   admission.checkpoint().map_err(BodySyntaxFailure::Operational)?;
   let mut bound=CurrentBodySyntax{original,input:self,projection,deferred_literal_roots:0};bound.deferred_literal_roots=bound.validate_issued_coordinates(admission)?;Ok(bound)
  })();
  if let Some(actual)=admission.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}
  pending
 }
}
impl<'a> CurrentBodySyntax<'a>{
 /// Canonical parser DATA, not current expanded coordinates or a model.
 pub fn canonical_statement_storage(&self)->&Arc<StatementBody>{&self.original.statements}
 /// Tiny identity/scalars from this already-validated canonical binding. These
 /// are cache locators only; current model/source authority stays on this loan.
 pub fn original_code_owner(&self)->&Arc<BodyCodeIdentity>{self.input.original_code.as_ref().expect("private current body binding checked actual original code")}
 pub fn canonical_window(&self)->dm_syntax::Span{self.original.original_window}
 pub fn canonical_body_span(&self)->dm_syntax::Span{self.original.original_body_span}

 pub fn deferred_literal_roots(&self)->usize{self.deferred_literal_roots}
 pub fn current_input_key(&self)->u64{self.input.key()}
 pub fn projection(&self)->dm_syntax::SyntaxProjection{self.projection}
 pub fn body_span(&self)->dm_syntax::Span{self.input.span}
 pub fn header_span(&self)->dm_syntax::Span{self.projection.span(self.original.item.header_span).expect("private actual code recipe checked header")}
 pub fn opening_parenthesis(&self)->Result<Option<dm_syntax::Span>,BodySyntaxFailure>{self.original.opening_parenthesis.map(|at|self.projection.span(at).ok_or_else(||binding_error("original opening escapes current recipe"))).transpose()}
 pub fn parameters(&self)->Result<dm_syntax::ProjectedParameterSignature<'a>,BodySyntaxFailure>{dm_syntax::ProjectedParameterSignature::new(&self.original.parameters,self.projection).map_err(binding_view_error)}
 pub fn statements(&self)->dm_syntax::ProjectedStatements<'a>{dm_syntax::ProjectedStatements::new(&self.original.statements.parsed().statements,self.projection)}
 pub fn locals(&self)->dm_syntax::ProjectedLocalLedger<'a>{dm_syntax::ProjectedLocalLedger::new(&self.original.statements.parsed().local_variables,self.projection)}
 pub fn controls(&self)->dm_syntax::ProjectedControlOrigins<'a>{dm_syntax::ProjectedControlOrigins::new(&self.original.statements.parsed().control_origins,self.projection)}
 pub fn pending_current_using<'b>(&'b self,checkpoint:&'b dyn Fn()->std::io::Result<()>)->impl Iterator<Item=Result<dm_syntax::PendingBody,BodySyntaxFailure>>+'b{
  dm_syntax::ProjectedPendingBodies::new(&self.original.statements.parsed().pending_bodies,self.projection).headers().map(move|at|{checkpoint().map_err(BodySyntaxFailure::Operational)?;let header=at.map_err(binding_view_error)?;let termination=dm_syntax::termination_after_with_context(&self.input.source,header.end,&|offset|self.input.syntax.declaration_header_at(offset));Ok(dm_syntax::PendingBody{header,termination})})
 }
}

enum BindingNode<'a>{Statement(dm_syntax::ProjectedStatement<'a>),Expression(dm_syntax::ProjectedSyntaxExpr<'a>)}
struct BindingWork<'a>{nodes:Vec<BindingNode<'a>>,lease:dm_syntax::SettingRootLease}
impl<'a> BindingWork<'a>{
 fn new(a:&dm_syntax::SettingAdmission<'_>)->Result<Self,BodySyntaxFailure>{Ok(Self{nodes:Vec::new(),lease:a.reserve(std::mem::size_of::<Self>()).map_err(BodySyntaxFailure::Operational)?})}
 fn push(&mut self,node:BindingNode<'a>,a:&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>{
  a.checkpoint().map_err(BodySyntaxFailure::Operational)?;if self.nodes.len()==self.nodes.capacity(){let count=self.nodes.capacity().max(4).checked_mul(2).ok_or_else(||binding_error("binding node capacity overflows"))?;let bytes=count.checked_mul(4).and_then(|n|n.checked_mul(std::mem::size_of::<BindingNode<'_>>())).and_then(|n|n.checked_add(std::mem::size_of::<Self>()+128)).ok_or_else(||binding_error("binding node peak overflows"))?;if bytes>self.lease.bytes(){{let growth=bytes-self.lease.bytes();a.grow(&mut self.lease,growth)}.map_err(BodySyntaxFailure::Operational)?;}let mut next=Vec::new();next.try_reserve_exact(count).map_err(|actual|BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,actual)))?;if next.capacity()>count.checked_mul(4).ok_or_else(||binding_error("binding allocator peak overflows"))?{return Err(binding_error("binding allocator exceeds admitted geometry"))}next.append(&mut self.nodes);self.nodes=next;}
  self.nodes.push(node);Ok(())
 }
 fn statements(&mut self,rows:dm_syntax::ProjectedStatements<'a>,a:&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>{for row in rows.iter(){self.push(BindingNode::Statement(row.map_err(binding_view_error)?),a)?;}Ok(())}
 fn expression(&mut self,root:Option<dm_syntax::ProjectedSyntaxExpr<'a>>,a:&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>{if let Some(root)=root{self.push(BindingNode::Expression(root),a)?;}Ok(())}
}
impl<'a> CurrentBodySyntax<'a>{
 fn validate_issued_coordinates(&self,a:&dm_syntax::SettingAdmission<'_>)->Result<usize,BodySyntaxFailure>{
  let mut work=BindingWork::new(a)?;let mut deferred=0usize;
  let parameters=self.parameters()?;for declaration in parameters.absolute_declarations().map_err(binding_view_error)?{a.checkpoint().map_err(BodySyntaxFailure::Operational)?;declaration.span().map_err(binding_view_error)?;}
  for parameter in parameters.entries().map_err(binding_view_error)?{
   a.checkpoint().map_err(BodySyntaxFailure::Operational)?;parameter.name().map_err(binding_view_error)?;parameter.declaration_cursor().map_err(binding_view_error)?;for point in parameter.type_components().chain(parameter.array_brackets()){point.map_err(binding_view_error)?;}
   // A native optional-root refusal is real deferred syntax, not missing source
   // or a successful empty optional model. The typed accessor retains it.
   if parameter.original().expressions().is_err(){continue}
   work.expression(parameter.default().map_err(binding_view_error)?,a)?;work.expression(parameter.source().map_err(binding_view_error)?,a)?;for root in parameter.dimensions().map_err(binding_view_error)?{work.expression(root.map_err(binding_view_error)?,a)?;}
   if let Some(input)=parameter.input().map_err(binding_view_error)?{input.span().map_err(binding_view_error)?;for point in input.identifiers(){point.map_err(binding_view_error)?;}}
  }
  for local in self.locals().entries().map_err(binding_view_error)?{a.checkpoint().map_err(BodySyntaxFailure::Operational)?;local.name().map_err(binding_view_error)?;local.anchor().map_err(binding_view_error)?;for point in local.type_components(){point.map_err(binding_view_error)?;}if let Some(array)=local.array(){for point in array.brackets(){point.map_err(binding_view_error)?;}for root in array.dimensions(){work.expression(Some(root.map_err(binding_view_error)?),a)?;}}}
  for origin in self.controls().entries(){a.checkpoint().map_err(BodySyntaxFailure::Operational)?;origin.map_err(binding_view_error)?;}
  for header in dm_syntax::ProjectedPendingBodies::new(&self.original.statements.parsed().pending_bodies,self.projection).headers(){a.checkpoint().map_err(BodySyntaxFailure::Operational)?;header.map_err(binding_view_error)?;}
  work.statements(self.statements(),a)?;
  while let Some(node)=work.nodes.pop(){a.checkpoint().map_err(BodySyntaxFailure::Operational)?;match node{
   BindingNode::Expression(root)=>{
    if let dm_syntax::ExprKind::Literal(text)=&root.original().kind{if text.owns_template_syntax()&&!matches!(text.prepared_syntax_parts(),Some(Ok(_))){deferred=deferred.checked_add(1).ok_or_else(||binding_error("deferred literal count overflows"))?;continue}}
    if matches!(root.original().kind,dm_syntax::ExprKind::Literal(_)){if let Some(fragments)=root.literal_fragments().map_err(binding_view_error)?{for fragment in fragments{a.checkpoint().map_err(BodySyntaxFailure::Operational)?;let fragment=fragment.map_err(binding_view_error)?;for token in fragment.tokens(){a.checkpoint().map_err(BodySyntaxFailure::Operational)?;token.map_err(binding_view_error)?;}fragment.expression().map_err(binding_view_error)?;}}}
    let children=root.try_visit_children(|_,child|work.expression(Some(child.map_err(binding_view_error)?),a))?;children.map_err(binding_view_error)?;
   }
   BindingNode::Statement(row)=>{
    // Inspect only the original issued node. Projected setting children keep
    // the same payload and resource owner, with a composed current window.
    if let dm_syntax::StatementKind::ProjectedSet{value,..}=&row.original().kind{if !value.is_retained_in(a){return Err(binding_error("setting parser product belongs to another native resource domain"))}let value=dm_syntax::ProjectedSettingExpression::new(value,self.projection).map_err(binding_view_error)?;work.expression(Some(value.expression()),a)?;continue}
    use dm_syntax::ProjectedStatementKind as S;match row.kind().map_err(binding_view_error)?{
     S::If{condition,then_branch,else_branch}=>{work.expression(Some(condition),a)?;work.statements(then_branch,a)?;work.statements(else_branch,a)?;}
     S::While{condition,body}|S::DoWhile{condition,body}=>{work.expression(Some(condition),a)?;work.statements(body,a)?;}
     S::Spawn{delay,body}=>{work.expression(delay,a)?;work.statements(body,a)?;}
     S::Set{value,..}|S::Throw(value)|S::Call(value)|S::Expression(value)=>work.expression(Some(value),a)?,
     S::For{control,body}=>{use dm_syntax::ProjectedForControl as F;match control{F::All{..}=>{},F::Each{iterable,..}|F::Pair{iterable,..}=>work.expression(Some(iterable),a)?,F::Range{start,end,step,..}=>{work.expression(Some(start),a)?;work.expression(Some(end),a)?;work.expression(step,a)?;},F::RangeImplicitArray{end,step,..}=>{work.expression(Some(end),a)?;work.expression(step,a)?;},F::CStyle{initializer,condition,step}=>{if let Some(initializer)=initializer{match initializer{dm_syntax::ProjectedForInitializer::Declare{value,..}=>work.expression(value,a)?,dm_syntax::ProjectedForInitializer::Expr(root)=>work.expression(Some(root),a)?}}work.expression(condition,a)?;work.expression(step,a)?;}}work.statements(body,a)?;}
     S::Switch{selector,cases,else_branch,..}=>{work.expression(Some(selector),a)?;for case in cases.iter(){a.checkpoint().map_err(BodySyntaxFailure::Operational)?;case.projected_case_site().map_err(binding_view_error)?;for alternative in case.alternatives(){match alternative.map_err(binding_view_error)?{dm_syntax::ProjectedSwitchAlternative::Exact(root)=>work.expression(Some(root),a)?,dm_syntax::ProjectedSwitchAlternative::Range(start,end)=>{work.expression(Some(start),a)?;work.expression(Some(end),a)?;}}}work.statements(case.body(),a)?;}work.statements(else_branch,a)?;}
     S::Try{body,catch_body,..}=>{work.statements(body,a)?;work.statements(catch_body,a)?;}
     S::Label{body,..}=>work.statements(body,a)?,S::Return(root)|S::Var{value:root,..}=>work.expression(root,a)?,S::Assign{target,value,..}=>{work.expression(Some(target),a)?;work.expression(Some(value),a)?;}
     S::ProjectedSet{..}=>return Err(binding_error("setting projection must use its original root producer")),S::Goto(_)|S::Break|S::BreakLabel(_)|S::Continue|S::ContinueLabel(_)|S::Unsupported=>{},
    }
   }
  }}
  a.checkpoint().map_err(BodySyntaxFailure::Operational)?;Ok(deferred)
 }
}

#[cfg(test)]
mod current_original_body_product_binding_tests {
 use super::*;
 use std::sync::atomic::{AtomicUsize,Ordering};
 struct Source(std::collections::BTreeMap<std::path::PathBuf,dm_preprocess::AcquiredSource>);
 impl dm_preprocess::SourceProvider for Source{
  fn read(&self,_:&Path)->Result<String,String>{Err("real captured original acquisitions required".into())}
  fn acquired_source(&self,path:&Path)->Result<Option<dm_preprocess::AcquiredSource>,String>{Ok(self.0.get(path).cloned())}
  fn source_acquisition(&self,path:&Path,text:&dm_preprocess::SourceText)->Option<dm_preprocess::AcquiredSource>{self.0.get(path).filter(|s|s.lease().source_text().same_view(text)).cloned()}
 }
 #[derive(Debug)]struct NativeHost{counter:Arc<dm_syntax::SettingChargeCounter>,parses:AtomicUsize}
 impl NativeHost{fn new()->Self{Self{counter:dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap(),parses:AtomicUsize::new(0)}}}
 impl BodySyntaxQueries for NativeHost{
  fn syntax(&self,_:&Arc<BodySyntaxInput>)->Result<Arc<BodySyntax>,Diagnostic>{panic!("checked native admission only")}
  fn syntax_checked(&self,input:&Arc<BodySyntaxInput>)->Result<Arc<BodySyntax>,BodySyntaxFailure>{self.parses.fetch_add(1,Ordering::Relaxed);let a=dm_syntax::SettingAdmission::new(&self.counter,1<<26,&||Ok(()));input.parse_with_setting_admission(&a).map(Arc::new)}
 }

 impl SettingExpressionQueries for NativeHost{
  fn expression(&self,input:&SettingExpressionInput<'_>)->Result<dm_syntax::SettingExpression,BodySyntaxFailure>{let a=dm_syntax::SettingAdmission::new(&self.counter,1<<26,&||Ok(()));input.prepare(&a)}
  fn initializer<'s>(&self,input:&OriginalInitializerExpressionInput<'s>)->Result<OriginalInitializerExpression<'s>,BodySyntaxFailure>{let a=dm_syntax::SettingAdmission::new(&self.counter,1<<26,&||Ok(()));input.prepare(&a)}
  fn with_declaration_admission(&self,operation:&mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>)->Result<(),BodySyntaxFailure>{
   let a=dm_syntax::SettingAdmission::new(&self.counter,1<<26,&||Ok(()));let result=operation(&a);if matches!(&result,Err(BodySyntaxFailure::Operational(_))){return result}let status=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}status.map_err(BodySyntaxFailure::Operational)?;result
  }
 }
 fn acquired(bytes:impl AsRef<[u8]>)->dm_preprocess::AcquiredSource{dm_preprocess::AcquiredSource::from_original_bytes(bytes.as_ref().to_vec(),())}
 fn q(prefix:&str)->dm_preprocess::AcquiredSource{
  let tail=(0..10000).map(|n|format!("/proc/q_tail{n}()")).find(|h|h.bytes().fold(0xcbf29ce484222325u64,|x,b|(x^u64::from(b)).wrapping_mul(0x100000001b3))&15==0).unwrap();
  acquired(format!("{prefix}/proc/q()\n    return 2\n{tail}\n    return 3\n"))
 }
 fn front(state:&mut RetainedSemanticTree,p:dm_preprocess::AcquiredSource,q:dm_preprocess::AcquiredSource,host:&Arc<NativeHost>)->ColdFrontend{
  let source=Source(std::collections::BTreeMap::from([(PathBuf::from("body-bind.dme"),acquired("#include \"q.dm\"\n#include \"p.dm\"\n")),(PathBuf::from("q.dm"),q),(PathBuf::from("p.dm"),p)]));
  let executor=dm_exec::BuildExecutor::new(1).unwrap();
  build_with_executor_and_semantic_state_for_policy_checked(Path::new("body-bind.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:None,observer:None},None,&executor,Some(state),true,&(Arc::clone(host)as Arc<dyn SettingExpressionQueries>)).unwrap().with_body_queries(Arc::clone(host)as Arc<dyn BodySyntaxQueries>)
 }
 fn input(front:&ColdFrontend)->Arc<BodySyntaxInput>{
  let ordinal=front.issued_bodies.iter().position(|body|front.snapshot.tree.member(body.member).unwrap().name==dm_ir::SymbolId::of("p")).unwrap();
  Arc::clone(&front.body_queries.as_ref().unwrap().inputs[ordinal])
 }

 fn same_chunk(state:&mut RetainedSemanticTree,source:&str,host:&Arc<NativeHost>)->ColdFrontend{
  let input=Source(std::collections::BTreeMap::from([(PathBuf::from("same-body.dme"),acquired(source))]));let executor=dm_exec::BuildExecutor::new(1).unwrap();
  build_with_executor_and_semantic_state_for_policy_checked(Path::new("same-body.dme"),&input,&Default::default(),FrontendConfig{workers:1,engine:None,observer:None},None,&executor,Some(state),true,&(Arc::clone(host)as Arc<dyn SettingExpressionQueries>)).unwrap().with_body_queries(Arc::clone(host)as Arc<dyn BodySyntaxQueries>)
 }
 #[test]fn real_same_chunk_body_binding_after_length_change_and_earlier_shift_keeps_current_private_recipe(){
  let mut state=RetainedSemanticTree::new();let host=Arc::new(NativeHost::new());
  let long=format!("/proc/q()\n    return {}\n{}",123456789,P);let old=same_chunk(&mut state,&long,&host);let original=input(&old);let product=host.syntax_checked(&original).unwrap();
  let shorter=format!("/proc/q()\n    return 1\n{P}");let new=same_chunk(&mut state,&shorter,&host);let current=input(&new);assert!(current.span.start<original.span.start);let a=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||Ok(()));let view=current.bind_original_product_checked(&product,&a).unwrap();assert_eq!(host.parses.load(Ordering::Relaxed),1);
  assert_eq!(view.header_span(),current.syntax.item_path(&new.issued_bodies.iter().find(|row|row.expanded_span==current.span).unwrap().ast_path).unwrap().header_span());
  let first=view.statements().iter().next().unwrap().unwrap();let dm_syntax::ProjectedStatementKind::ProjectedSet{value,..}=first.kind().unwrap()else{panic!("real native setting statement")};let dm_syntax::StatementKind::ProjectedSet{value:old_root,..}=&first.original().kind else{panic!("one old retained root")};assert!(value.same_root(old_root));assert_eq!(value.original_source_window(),old_root.current_projection().original());assert_eq!(&current.source[value.current_span().range()],"\"p\"");
  let parameters=view.parameters().unwrap();let parameter=parameters.entries().unwrap().next().unwrap();assert_eq!(&current.source[parameter.default().unwrap().unwrap().span().range()],"list(1,2)");
  assert!(matches!(current.obtain_checked_using(|_|Ok(Arc::clone(&product))),Err(BodySyntaxFailure::Syntax(_))),"old issuance route remains strict even with authentic converged code");
  drop(view);drop(old);drop(original);
  // Canonical parser product survives without the old source wrapper/header.
  assert!(current.bind_original_product_checked(&product,&a).is_ok());assert_eq!(host.parses.load(Ordering::Relaxed),1);
 }
 #[test]fn canonical_native_body_product_rebinds_real_recovering_diagnostics_to_current_source_without_reparse(){
  let mut state=RetainedSemanticTree::new();let host=Arc::new(NativeHost::new());let bad="/proc/p(value=1)\n    return 1+\n";
  let before=same_chunk(&mut state,&format!("/proc/q()\n    return 222222\n{bad}"),&host);let old=input(&before);let a=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||Ok(()));
  let product=old.parse_original_product_with_setting_admission(&a).unwrap();let parsed=product.parsed().expect("native recovering BODY syntax is real data, not a successful semantic proof");assert!(!parsed.statements.parsed().diagnostics.is_empty());
  let after=same_chunk(&mut state,&format!("/proc/q()\n    return 1\n    // actual added source line before p\n{bad}"),&host);let current=input(&after);let bound=current.bind_original_product_checked(parsed,&a).unwrap();let diagnostics=bound.current_diagnostics().collect::<Result<Vec<_>,_>>().unwrap();assert_eq!(diagnostics.len(),parsed.statements.parsed().diagnostics.len());
  for(diagnostic,original)in diagnostics.iter().zip(&parsed.statements.parsed().diagnostics){let span=bound.projection().span(original.span).unwrap();let actual=current.mapping.output(span.start).unwrap();assert_eq!(diagnostic.message,original.message);assert_eq!(diagnostic.kind,syntax_kind(original.kind));assert_eq!(diagnostic.location.as_ref().unwrap().line,actual.line);assert_eq!(actual.line,old.mapping.output(original.span.start).unwrap().line+1);}
  assert!(std::ptr::eq(bound.original.statements.as_ref(),parsed.statements.as_ref()));assert_eq!(host.parses.load(Ordering::Relaxed),0,"product API executed native parser once directly, no host callback reparse");
 }

 const P:&str="/proc/p(value=list(1,2))\n    set name = \"p\"\n    var/local[2]=list(1,2)\n    if(value)\n        return \"a[value]z\"\n    return\n";
 #[test]fn actual_retained_body_product_binds_current_offset_and_all_private_ledgers_without_a_second_parse(){
  let mut state=RetainedSemanticTree::new();let host=Arc::new(NativeHost::new());let p=acquired(P);
  let old=front(&mut state,p.clone(),q(""),&host);let original_input=input(&old);let product=host.syntax_checked(&original_input).unwrap();assert_eq!(host.parses.load(Ordering::Relaxed),1);
  let shifted=front(&mut state,p.clone(),q("// real preceding edit changes the following expanded offset\n\n"),&host);let current=input(&shifted);assert_ne!(original_input.span.start,current.span.start);assert_ne!(original_input.key(),current.key());
  let a=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||Ok(()));let bound=current.bind_original_product_checked(&product,&a).unwrap();assert_eq!(bound.current_input_key(),current.key());assert_eq!(bound.body_span(),current.span);assert_eq!(host.parses.load(Ordering::Relaxed),1);
  let parameters=bound.parameters().unwrap();assert!(std::ptr::eq(parameters.original(),product.parameters.as_ref()));let parameter=parameters.entries().unwrap().next().unwrap();assert_eq!(&current.source[parameter.name().unwrap().range()],"value");let root=parameter.default().unwrap().unwrap();assert_eq!(&current.source[root.span().range()],"list(1,2)");assert!(std::ptr::eq(root.original(),product.parameters.entries().unwrap()[0].expressions().unwrap().unwrap().default().unwrap()));
  let locals=bound.locals().entries().unwrap().collect::<Vec<_>>();assert_eq!(locals.len(),1);assert_eq!(&current.source[locals[0].name().unwrap().range()],"local");assert!(bound.controls().entries().next().is_some());for pending in bound.pending_current_using(&||Ok(())){let pending=pending.unwrap();assert!(pending.header.end<=current.source.len());}
  let first=bound.statements().iter().next().unwrap().unwrap();assert!(std::ptr::eq(first.original(),&product.statements.parsed().statements[0]));if let dm_syntax::StatementKind::ProjectedSet{value:original,..}=&first.original().kind{let dm_syntax::ProjectedStatementKind::ProjectedSet{value:rebound,..}=first.kind().unwrap()else{panic!("actual retained setting root")};assert!(rebound.same_root(original));assert_eq!(rebound.original_source_window(),original.current_projection().original());assert_eq!(rebound.current_span(),bound.projection().span(original.current_span()).unwrap());}
  assert!(matches!(current.obtain_checked_using(|_|Ok(Arc::clone(&product))),Err(BodySyntaxFailure::Syntax(_))),"old foreign-issuance API must remain strict");
  let fresh=front(&mut RetainedSemanticTree::new(),p.clone(),q("// real preceding edit changes the following expanded offset\n\n"),&host);assert!(input(&fresh).bind_original_product_checked(&product,&a).is_err(),"equal source bytes never issue code authority");
  let changed=front(&mut state,acquired(P.replace("list(1,2)","list(3,4)")),q(""),&host);assert!(input(&changed).bind_original_product_checked(&product,&a).is_err(),"changed actual code must not bind");
  assert_eq!(host.parses.load(Ordering::Relaxed),1);
 }
 #[test]fn actual_body_binding_preserves_typed_operational_failures_and_native_resource_identity(){
  let mut state=RetainedSemanticTree::new();let host=Arc::new(NativeHost::new());let first=front(&mut state,acquired(P),q(""),&host);let old=input(&first);let product=host.syntax_checked(&old).unwrap();let next=front(&mut state,acquired(P),q("// shifted\n"),&host);let current=input(&next);
  let foreign=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=dm_syntax::SettingAdmission::new(&foreign,1<<26,&||Ok(()));assert!(current.bind_original_product_checked(&product,&a).is_err());
  let fault=||Err(std::io::Error::from_raw_os_error(1450));let a=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&fault);let Err(BodySyntaxFailure::Operational(error))=current.bind_original_product_checked(&product,&a)else{panic!("real typed operational failure")};assert_eq!(error.raw_os_error(),Some(1450));
  let used=host.counter.load(Ordering::Acquire);let a=dm_syntax::SettingAdmission::new(&host.counter,used,&||Ok(()));let Err(BodySyntaxFailure::Operational(error))=current.bind_original_product_checked(&product,&a)else{panic!("actual temporary-work admission denied")};assert_eq!(error.kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(host.counter.load(Ordering::Acquire),used);
  let a=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||Ok(()));assert!(current.bind_original_product_checked(&product,&a).is_ok());assert_eq!(host.parses.load(Ordering::Relaxed),1);
 }
}

/// Source-neutral native grammar result, never a current frontend/model.
/// Both success and author failure retain canonical code DATA only. A caller
/// must obtain an actual current-input binding before reporting source points.
#[derive(Debug)]
pub enum OriginalBodySyntaxProduct{Parsed(Arc<BodySyntax>),Rejected(OriginalBodySyntaxError)}
#[derive(Debug)]
pub struct OriginalBodySyntaxError{code:Arc<BodyCodeIdentity>,body:dm_syntax::Span,diagnostic:dm_syntax::Diagnostic}
impl OriginalBodySyntaxProduct{
 pub fn budget_charge(&self)->usize{match self{Self::Parsed(syntax)=>syntax.budget_charge(),Self::Rejected(error)=>std::mem::size_of::<Self>().saturating_add(error.diagnostic.message.capacity())}}
 pub fn parsed(&self)->Option<&Arc<BodySyntax>>{match self{Self::Parsed(syntax)=>Some(syntax),Self::Rejected(_)=>None}}
 pub fn bind_error(&self,input:&BodySyntaxInput)->Result<Option<Diagnostic>,BodySyntaxFailure>{match self{Self::Parsed(_)=>Ok(None),Self::Rejected(error)=>error.bind_current(input).map(Some)}}
}
impl OriginalBodySyntaxError{
 fn bind_current(&self,input:&BodySyntaxInput)->Result<Diagnostic,BodySyntaxFailure>{
  let code=input.original_code.as_ref().ok_or_else(||binding_error("actual current body code is absent"))?;
  if !Arc::ptr_eq(code,&self.code){return Err(binding_error("native grammar refusal belongs to different code"))}
  input.syntax.original_body_recipe(input.span,code).map_err(|_|binding_error("current native refusal recipe differs"))?;
  let projection=dm_syntax::SyntaxProjection::new(self.body,input.span).map_err(BodySyntaxFailure::Operational)?;
  let span=projection.span(self.diagnostic.span).ok_or_else(||binding_error("native grammar refusal escapes actual body recipe"))?;
  let location=input.mapping.output(span.start).ok_or_else(||binding_error("actual current source point for native refusal absent"))?;
  Ok(Diagnostic{kind:syntax_kind(self.diagnostic.kind),stage:DiagnosticStage::Syntax,message:self.diagnostic.message.clone(),location:Some(location)})
 }
}
impl BodySyntaxInput{
 /// Locator DATA is usable only with this actual private input/current recipe.
 /// Holding the tiny code Arc in graph Params prevents pointer reuse/ABA until
 /// that node is removed; it retains no source, parser AST, tree or model.
 pub fn original_code_owner(&self)->Option<&Arc<BodyCodeIdentity>>{self.original_code.as_ref()}
 pub fn parse_original_product_with_setting_admission(&self,a:&dm_syntax::SettingAdmission<'_>)->Result<OriginalBodySyntaxProduct,BodySyntaxFailure>{
  a.checkpoint().map_err(BodySyntaxFailure::Operational)?;let mut original_error=None;
  let parsed=self.parse_using_observed(Some((a,BodySyntaxFailure::Operational)),|item|body_archive::parse_statements_with_body_literal_admission(item,&self.source,&self.syntax,self.span,self.original_code.as_ref(),a,|_|false),&mut|error|{original_error=Some(error.clone());});
  if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}
  if matches!(&parsed,Err(BodySyntaxFailure::Operational(_))){return parsed.map(|_|unreachable!())}
  a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
  match parsed{
   Ok(syntax)=>Ok(OriginalBodySyntaxProduct::Parsed(Arc::new(syntax))),
   Err(BodySyntaxFailure::Syntax(error))=>match original_error{
    Some(diagnostic)=>{let code=self.original_code.as_ref().ok_or_else(||binding_error("native grammar refusal has no actual code owner"))?;Ok(OriginalBodySyntaxProduct::Rejected(OriginalBodySyntaxError{code:Arc::clone(code),body:self.span,diagnostic}))}
    None=>Err(BodySyntaxFailure::Syntax(error)), // actual unlocated contract failure; never fabricated raw syntax
   },
   Err(actual)=>Err(actual),
  }
 }
}
impl CurrentBodySyntax<'_>{
 /// Original recovering BODY diagnostics remain real raw native grammar rows;
 /// only the current private input binds their reported source coordinates.
 pub fn current_diagnostics(&self)->impl Iterator<Item=Result<Diagnostic,BodySyntaxFailure>>+'_{
  self.original.statements.parsed().diagnostics.iter().map(|row|{
   let span=self.projection.span(row.span).ok_or_else(||binding_error("recovering diagnostic escapes actual current body"))?;
   let location=self.input.mapping.output(span.start).ok_or_else(||binding_error("current recovering diagnostic source point absent"))?;
   Ok(Diagnostic{kind:syntax_kind(row.kind),stage:DiagnosticStage::Syntax,message:row.message.clone(),location:Some(location)})
  })
 }
}

/// A borrowed disposition over the SAME actual canonical code/current recipe.
/// These grants have private fields: a diagnostic or a public parser DATA enum
/// cannot itself certify old Some/None or another current body's disposition.
pub enum OriginalBodyDisposition<'loan,'syntax>{Available(OriginalBodyCodeGrant<'loan,'syntax>),Skipped(OriginalBodyCodeGrant<'loan,'syntax>)}
pub struct OriginalBodyCodeGrant<'loan,'syntax>{body:&'loan CurrentBodySyntax<'syntax>,outcome:&'syntax dm_syntax::OriginalBodyGrammarOutcome}
impl OriginalBodyCodeGrant<'_,'_>{
 pub fn belongs_to(&self,body:&CurrentBodySyntax<'_>)->bool{std::ptr::eq(self.body,body)}
 pub fn statement_span(&self)->Result<Option<dm_syntax::Span>,BodySyntaxFailure>{self.outcome.statement_span().map(|span|self.body.projection.span(span).ok_or_else(||binding_error("genuine original body disposition escapes current source recipe"))).transpose()}
}
fn unissued_original_body(message:&'static str)->BodySyntaxFailure{BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::Unsupported,message))}
impl<'syntax> CurrentBodySyntax<'syntax>{
 /// Initial exact grammar coverage is deliberately closed and falsifiable:
 /// empty, void/simple return and actual simple arithmetic missing-RHS branch.
 /// Remaining grammar is unissued, not inferred available/None from errors.
 pub fn original_code_disposition<'loan>(&'loan self)->Result<OriginalBodyDisposition<'loan,'syntax>,BodySyntaxFailure>{
  let code=self.input.original_code.as_ref().ok_or_else(||binding_error("original code disposition lacks actual canonical code identity"))?;
  let recipe=self.input.syntax.original_body_recipe(self.input.span,code).map_err(|_|binding_error("original code disposition current recipe differs"))?;
  if !recipe.setting_headers().is_some_and(|headers|headers.checker_body_profile()){return Err(unissued_original_body("original body grammar profile is not actually issued"))}
  let parsed:&'syntax dm_syntax::ParsedBody=self.original.statements.parsed();let outcome=parsed.original_grammar.as_ref().ok_or_else(|| {
   if cfg!(debug_assertions) && std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some() {
    if let Some(source) = self.input.mapping.output(self.input.span.start) {
     let _ = std::io::Write::write_fmt(&mut std::io::stderr().lock(), format_args!(
      "original.body_unissued file={} line={}\n", source.semantic_path, source.line,
     ));
    }
   }
   unissued_original_body("genuine original per-body grammar outcome is not issued for this syntax")
  })?;
  if let Some(roots)=outcome.scope_roots(){
   if roots!=parsed.statements.len()||outcome.prefix_settings()>=roots||outcome.statement_span().is_some()||outcome.kind()!=dm_syntax::OriginalBodyGrammarKind::Available||!parsed.diagnostics.is_empty(){return Err(binding_error("original compound scope differs from the same consuming Native body"))}
  }else{match outcome.statement_span(){
   None=>if parsed.statements.len()!=outcome.prefix_settings()||!parsed.diagnostics.is_empty()||outcome.kind()!=dm_syntax::OriginalBodyGrammarKind::Available{return Err(binding_error("original empty/setting-only grammar outcome differs from native producer"))},
   Some(span)=>{
    let Some((only,prefix))=parsed.statements.split_last()else{return Err(binding_error("original terminal-statement outcome differs from native producer roster"))};if prefix.len()!=outcome.prefix_settings(){return Err(binding_error("original initial-setting prefix differs from native producer roster"))}
    if only.header_span!=span||self.projection.span(span).is_none(){return Err(binding_error("original sole-statement outcome has foreign source geometry"))}
    for scalar in[outcome.expression_span(),outcome.operator_span()].into_iter().flatten(){if scalar.start<span.start||scalar.end>span.end||self.projection.span(scalar).is_none(){return Err(binding_error("original grammar token outcome escapes actual current statement"))}}
    match outcome.kind(){dm_syntax::OriginalBodyGrammarKind::Available=>if !matches!(&only.kind,dm_syntax::StatementKind::Return(_))||!parsed.diagnostics.is_empty(){return Err(binding_error("original available-body outcome differs from actual native grammar"))},dm_syntax::OriginalBodyGrammarKind::SkippedMissingSimpleOperand=>if !matches!(&only.kind,dm_syntax::StatementKind::Unsupported)||parsed.diagnostics.is_empty()||outcome.operator_span().is_none(){return Err(binding_error("original skipped-body outcome lacks actual missing-operand production"))}}
   }
  }
  }
  if !parsed.statements.iter().take(outcome.prefix_settings()).all(|row|matches!(&row.kind,dm_syntax::StatementKind::Set{..}|dm_syntax::StatementKind::ProjectedSet{..})){return Err(binding_error("actual original setting prefix contains another native statement"))}
  let grant=OriginalBodyCodeGrant{body:self,outcome};Ok(match outcome.kind(){dm_syntax::OriginalBodyGrammarKind::Available=>OriginalBodyDisposition::Available(grant),dm_syntax::OriginalBodyGrammarKind::SkippedMissingSimpleOperand=>OriginalBodyDisposition::Skipped(grant)})
 }
}
