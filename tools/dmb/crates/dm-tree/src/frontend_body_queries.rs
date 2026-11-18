//! Optional body-syntax queries supplied by the compiler's existing query host.
//! Query keys are issuance-local, never authority minted from matching bytes.
use super::*;

/// Only the frontend can create this captured input. Query parameters hold it
/// weakly, so keeping graph metadata cannot retain obsolete source revisions.
pub struct BodySyntaxInput {
    id: u64,
    settled: std::sync::OnceLock<BodyInputSettlement>,
    span: dm_syntax::Span,
    parameter_admission: usize,
    original_code: Option<Arc<BodyCodeIdentity>>,
    // LAST: only actual Input allocation credit; independent of Code lifetime.
    allocation_owner:Arc<BodySyntaxInputWeak>,
}


/// Same Input weak locator and intrinsic allocation credit. No strong Input,
/// source, code, AST or query owner is retained by this resource holder.
pub struct BodySyntaxInputWeak {
 input:std::sync::Weak<BodySyntaxInput>,
 // Last: actual Weak is destroyed before its paid Arc-shell allocation.
 credit:std::sync::OnceLock<dm_syntax::SettingRootLease>,
}
impl std::fmt::Debug for BodySyntaxInputWeak{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{std::fmt::Debug::fmt(&self.input,f)}}
impl BodySyntaxInputWeak{
 fn new(input:std::sync::Weak<BodySyntaxInput>,credit:Option<dm_syntax::SettingRootLease>)->Self{Self{input,credit:credit.map_or_else(std::sync::OnceLock::new,std::sync::OnceLock::from)}}
 pub fn upgrade(&self)->Option<Arc<BodySyntaxInput>>{self.input.upgrade()}
 pub fn strong_count(&self)->usize{self.input.strong_count()}
 pub fn as_ptr(&self)->*const BodySyntaxInput{self.input.as_ptr()}
 pub fn ptr_eq(&self,other:&Self)->bool{self.input.ptr_eq(&other.input)}
 pub fn allocation_credit(&self)->Option<&dm_syntax::SettingRootLease>{self.credit.get()}
 pub fn matches(&self,input:&Arc<BodySyntaxInput>)->bool{self.input.as_ptr()==Arc::as_ptr(input)}
 pub fn visit_allocation_storage(&self,visit:&mut dyn FnMut(usize,usize,usize)){
  let(layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<Self>()).expect("actual Input resource owner Arc layout");visit(self as *const Self as usize,std::mem::size_of::<Self>(),layout.pad_to_align().size());
  visit(self.input.as_ptr()as usize,if self.input.strong_count()>0{std::mem::size_of::<BodySyntaxInput>()}else{0},unsettled_body_input_allocation_bytes());
  if let Some(credit)=self.credit.get(){credit.visit_counter_storage(|p,n|visit(p,n,n));}
 }
}

// Borrow the actual captured frontend owners for diagnostics only. No Input,
// Code, Item, query or source grant is constructed by this common writer.
fn write_captured_body_owner_resources(source:&dm_preprocess::SourceText,syntax:&DeclarationSyntax,span:dm_syntax::Span,output:&mut dyn std::io::Write){
        match syntax.original_committed_products_for_trace(span){
            Some(products)=>{let _=writeln!(output,"ORIGINAL_BODY_ADMISSION_COMMITTED (rows,live_inputs,product_grant,unique_input_grant_sum,missing_input_grants)={:?}",products.input_resource_summary());},
            None=>{let _=writeln!(output,"ORIGINAL_BODY_ADMISSION_COMMITTED existing_products=unavailable");},
        }
        match syntax.original_committed_items_for_trace(span){
            Some(items)=>{let _=writeln!(output,"ORIGINAL_BODY_ADMISSION_FOREST existing_committed_items={items:?}");},
            None=>{let _=writeln!(output,"ORIGINAL_BODY_ADMISSION_FOREST existing_committed_items=unavailable");},
        }
        // Actual owner grants and existing borrowed resource census only.
        // Reference-upper visitor columns may overlap and are not additive.
        let _=writeln!(output,"ORIGINAL_BODY_ADMISSION_ARENA source_bytes={} payload_grant={:?} control_grant={:?}",source.len(),source.source_arena_payload_credit().map(|credit|credit.reserved_bytes()),source.source_arena_control_credit().map(|credit|credit.reserved_bytes()));
        match syntax.original_body_tokens_header_only(span){
            Ok(tokens)=>{let _=writeln!(output,"ORIGINAL_BODY_ADMISSION_OWNER existing_header_token_census={tokens:?}");},
            Err(_)=>{let _=writeln!(output,"ORIGINAL_BODY_ADMISSION_OWNER existing_header_token_census=unavailable");},
        }
}

// Existing attachment DATA only: inspect the bank without issuing any rows.
// Actual Raw full-registry uses compact/eager; ordinary Analyze may be sparse.
fn write_existing_body_query_attachment(frontend:&ColdFrontend,inputs:&BodyQueryInputs,route:&'static str){
 if std::env::var_os("DMB_ORIGINAL_TRACE_BODY_PRESSURE").is_none(){return}
 use std::io::Write as _;
 let(mut rows,mut missing,mut sum)=(0usize,0usize,Some(0usize));
 let complete=inputs.visit_issued(&mut|_,input|{rows+=1;match input.committed_allocation_credit(){Some(credit)=>sum=sum.and_then(|total|total.checked_add(credit.bytes())),None=>missing+=1}}).is_ok();
 if !complete{sum=None;}
 let mut output=std::io::stderr().lock();
 let _=writeln!(output,"ORIGINAL_BODY_OWNER_DIAGNOSTIC trigger={route} issued_inputs={rows} input_grant_sum={sum:?} missing_input_grants={missing} inventory_complete={complete} bank_fixed_grant={:?}",inputs.owner.credit.as_ref().map(|credit|credit.bytes()));
 if let Some(body)=frontend.issued_bodies.first(){write_captured_body_owner_resources(&frontend.issued_arena,&frontend.issued_syntax,body.expanded_span,&mut output);}else{let _=writeln!(output,"ORIGINAL_BODY_OWNER_DIAGNOSTIC captured_context=empty_roster");}
}

#[derive(Debug)]
struct BodyInputSettlement {
    source: dm_preprocess::SourceText,
    syntax: Arc<DeclarationSyntax>,
    location: SourceLocation,
    mapping: BodyDiagnosticProjection,
}

#[derive(Debug)]
enum BodyDiagnosticProjection {
    Complete(Arc<SourceExportMapping>),
    Generation(Arc<super::generation::GenerationQuestionGeometry>),
}
/// Borrowed diagnostic coordinate DATA from its actual complete or generation
/// owner. This is not a checker registration, current-code grant or owned path.
pub struct BorrowedBodyUtilityPoint<'a>{inner:BodyUtilityPointOwner<'a>}
enum BodyUtilityPointOwner<'a>{Complete(BorrowedSourceNoteOrigin<'a>),Generation(super::generation::GenerationSourcePoint<'a>)}
impl BorrowedBodyUtilityPoint<'_>{
 pub fn reported_coordinates(&self)->(&Path,usize,usize){match &self.inner{
  BodyUtilityPointOwner::Complete(point)=>point.reported_coordinates(),
  BodyUtilityPointOwner::Generation(point)=>(point.path,point.line,point.byte_column),
 }}
}
impl BodyDiagnosticProjection {
    fn borrowed_utility_point(&self,offset:usize)->Result<BorrowedBodyUtilityPoint<'_>,&'static str>{
     let inner=match self{
      Self::Complete(mapping)=>BodyUtilityPointOwner::Complete(mapping.borrowed_source_note_point(offset)?),
      Self::Generation(mapping)=>BodyUtilityPointOwner::Generation(mapping.original_note_point(offset)?),
     };Ok(BorrowedBodyUtilityPoint{inner})
    }

    fn output(&self,offset:usize)->Option<SourceLocation>{match self{Self::Complete(mapping)=>mapping.output(offset),Self::Generation(mapping)=>mapping.output(offset)}}
}
// Existing issuance counter is shared by complete and generation-only inputs.
// Query key equality never substitutes for the actual private input issuer.
static NEXT_BODY_INPUT:std::sync::atomic::AtomicU64=std::sync::atomic::AtomicU64::new(1);

/// Exact demand-input Arc extent. The opt-in collector must reserve this on
/// its existing admission BEFORE construction and retain that grant through
/// transfer to final BodyQueries.inputs. This is not a source/completion grant.
pub(super) fn unsettled_body_input_allocation_bytes()->usize{
 let (layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<BodySyntaxInput>()).expect("static BodySyntaxInput Arc layout is representable");
 layout.pad_to_align().size()
}
pub(super) fn issue_unsettled_body(span:dm_syntax::Span,code:Arc<BodyCodeIdentity>,parameter_admission:usize)->Result<Arc<BodySyntaxInput>,BodySyntaxFailure>{issue_unsettled_body_with_credit(span,code,parameter_admission,None)}
pub(super) fn issue_unsettled_body_admitted(span:dm_syntax::Span,code:Arc<BodyCodeIdentity>,parameter_admission:usize,a:&dm_syntax::SettingAdmission<'_>)->Result<Arc<BodySyntaxInput>,BodySyntaxFailure>{
 let proxy=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}proxy.map_err(BodySyntaxFailure::Operational)?;
 let(layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<BodySyntaxInputWeak>()).expect("actual Input lease Arc layout");
 let bytes=unsettled_body_input_allocation_bytes().checked_add(layout.pad_to_align().size()).ok_or_else(||BodySyntaxFailure::Operational(std::io::ErrorKind::OutOfMemory.into()))?;
 let pending=a.reserve(bytes);if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}let credit=pending.map_err(BodySyntaxFailure::Operational)?;issue_unsettled_body_with_credit(span,code,parameter_admission,Some(credit))
}
fn issue_unsettled_body_with_credit(span:dm_syntax::Span,code:Arc<BodyCodeIdentity>,parameter_admission:usize,allocation_credit:Option<dm_syntax::SettingRootLease>)->Result<Arc<BodySyntaxInput>,BodySyntaxFailure>{
 if span.start>span.end{return Err(binding_error("early body input extent is reversed"))}
 let id=NEXT_BODY_INPUT.fetch_update(std::sync::atomic::Ordering::Relaxed,std::sync::atomic::Ordering::Relaxed,|value|value.checked_add(1)).map_err(|_|binding_error("body input issuance counter exhausted"))?;
 Ok(Arc::new_cyclic(|weak|BodySyntaxInput{id,settled:std::sync::OnceLock::new(),span,parameter_admission,original_code:Some(code),allocation_owner:Arc::new(BodySyntaxInputWeak::new(weak.clone(),allocation_credit))}))
}
impl BodySyntaxInput{
 /// The collector additionally authenticates its same primary/header/literal
 /// producer before this final actual-frontend settlement. No public DATA can
 /// supply a final binding, and the existing Arc/id/code are never replaced.
 pub(super) fn settle_for_final_frontend(&self,front:&ColdFrontend,ordinal:usize)->Result<(),BodySyntaxFailure>{
  if front.issued_syntax.body_has_parser_report_prefix(self.span){return Err(binding_error("report-only parser prefix cannot settle BODY Inputs"))}
  if self.settled.get().is_some(){return Err(binding_error("body input final binding was already settled"))}
  front.require_current_body_code_owners().map_err(BodySyntaxFailure::Syntax)?;
  let body=front.issued_bodies.get(ordinal).ok_or_else(||binding_error("final body ordinal is absent"))?;
  let code=front.issued_body_codes.get(ordinal).and_then(|owner|owner.identity.as_ref()).ok_or_else(||binding_error("final committed body code is absent"))?;
  self.settle_current_source(body,code,&front.issued_syntax,&front.issued_arena,&front.source_export_mapping)
 }
 fn settle_current_source(&self,body:&BodyOccurrence,code:&Arc<BodyCodeIdentity>,syntax:&Arc<DeclarationSyntax>,source:&dm_preprocess::SourceText,mapping:&Arc<SourceExportMapping>)->Result<(),BodySyntaxFailure>{
  if self.settled.get().is_some(){return Err(binding_error("body Input is already settled"))}
  if body.expanded_span!=self.span||!self.original_code.as_ref().is_some_and(|actual|Arc::ptr_eq(actual,code)){return Err(binding_error("final body span/code differs from actual Input"))}
  syntax.original_body_recipe_checked(body.expanded_span,code)?;
  let parameter_admission=syntax.item_path(&body.ast_path).map(|item|item.header_span().end.saturating_sub(item.header_span().start).saturating_mul(128).saturating_add(1024)).unwrap_or(usize::MAX);
  if parameter_admission!=self.parameter_admission{return Err(binding_error("final body header admission differs from actual Input"))}
  self.settled.set(BodyInputSettlement{source:source.clone(),syntax:Arc::clone(syntax),location:body.source.clone(),mapping:BodyDiagnosticProjection::Complete(Arc::clone(mapping))}).map_err(|_|binding_error("body input final binding raced another settlement"))
 }
}

/// One immutable parse, borrowed by lowering, lint policies and checker passes.
/// Lossless children remain available for unsupported lowering constructs.
pub struct BodySyntax {
    issuance: u64,
    pub(super) item: Item,
    // Private resource receipt only; source/current/code gates remain separate.
    pub(super) paid_canonical_payload: bool,
    pub(super) opening_parenthesis: Option<dm_syntax::Span>,
    pub(super) parameters: dm_syntax::SharedParameterSignature,
    pub(super) statements: Arc<StatementBody>,
    input_bytes: usize,
    // Parser-product DATA only; no SourceSnapshot/tree/current model retained.
    original_code: Arc<BodyCodeIdentity>,
    original_window: dm_syntax::Span,
    original_body_span:dm_syntax::Span,
    native_primary_consumed:bool,
    // LAST: actual canonical Item/parameter/statement payload drops first.
    pub(super) _primary_credit:Option<dm_syntax::SettingRootLease>,
}

impl BodySyntaxInput {
    fn settlement(&self)->Result<&BodyInputSettlement,Diagnostic>{self.settled.get().ok_or_else(||internal("body input final source binding is unsettled"))}
    fn settlement_checked(&self)->Result<&BodyInputSettlement,BodySyntaxFailure>{self.settled.get().ok_or_else(||binding_error("body input final source binding is unsettled"))}
    pub(super) fn original_opening(&self)->Result<usize,String>{self.settled.get().ok_or("body input final source binding is unsettled")?.syntax.original_callable_opening(self.span,self.original_code.as_ref().ok_or("generation callable original code unissued")?)}
    /// Diagnostic DATA only, used after the original operational failure.
    /// Borrow existing settled mapping/source; never parse, allocate an Item,
    /// issue a Code/query owner or touch the admission/first-error channel.
    pub fn write_admission_failure_context(&self,output:&mut dyn std::io::Write){
        fn clipped(value:&str,characters:usize)->&str{let end=value.char_indices().nth(characters).map_or(value.len(),|(at,_)|at);&value[..end]}
        let Some(settled)=self.settled.get()else{let _=writeln!(output,"ORIGINAL_BODY_ADMISSION_CONTEXT body={:?} source=unsettled",self.span);return};
        let _=writeln!(output,"ORIGINAL_BODY_ADMISSION_INPUT current_allocation_grant={:?} current_code_grant={:?}",self.allocation_owner.allocation_credit().map(|credit|credit.bytes()),self.original_code.as_ref().and_then(|code|code.committed_allocation_credit()).map(|credit|credit.bytes()));
        write_captured_body_owner_resources(&settled.source,&settled.syntax,self.span,output);
        let prefix=settled.source.get(self.span.range()).and_then(|source|source.lines().next()).unwrap_or("");
        if let Ok(point)=settled.mapping.borrowed_utility_point(self.span.start){
            let(path,line,column)=point.reported_coordinates();
            let _=writeln!(output,"ORIGINAL_BODY_ADMISSION_CONTEXT body={:?} file={:?} line={} column={} source_prefix={:?}",self.span,clipped(path.to_str().unwrap_or("<non-UTF8-path>"),512),line,column,clipped(prefix,256));
        }else{let _=writeln!(output,"ORIGINAL_BODY_ADMISSION_CONTEXT body={:?} source=unmapped source_prefix={:?}",self.span,clipped(prefix,256));}
    }
    /// Diagnostic DATA only: borrow this Input's actual settled source identity.
    /// Never parses, queries, admits, upgrades an owner or reads a first error.
    #[doc(hidden)]
    pub fn write_captured_identity_context(&self,output:&mut dyn std::io::Write){
        fn clipped(value:&str,characters:usize)->&str{let end=value.char_indices().nth(characters).map_or(value.len(),|(at,_)|at);&value[..end]}
        let Some(settled)=self.settled.get()else{let _=writeln!(output,"input_key={} body={:?} source=unsettled",self.id,self.span);return};
        let prefix=settled.source.get(self.span.range()).map(|source|clipped(source,256)).and_then(|source|source.lines().next()).unwrap_or("");
        if let Ok(point)=settled.mapping.borrowed_utility_point(self.span.start){
            let(path,line,column)=point.reported_coordinates();
            let _=writeln!(output,"input_key={} body={:?} file={:?} line={} column={} source_prefix={:?}",self.id,self.span,clipped(path.to_str().unwrap_or("<non-UTF8-path>"),512),line,column,clipped(prefix,256));
        }else{let _=writeln!(output,"input_key={} body={:?} source=unmapped source_prefix={:?}",self.id,self.span,clipped(prefix,256));}
    }
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
        self.settlement()?;
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
        self.settlement_checked()?;
        let syntax=obtain(self)?;
        if syntax.issuance!=self.id{return Err(internal("body query returned a foreign parser issuance").into())}
        Ok(syntax)
    }
    /// Standalone compatibility behavior remains the same explicit parser path.
    pub fn parse(&self) -> Result<BodySyntax, Diagnostic> {
        let settled=self.settlement()?;
        self.parse_using(|item| {
            Ok(body_archive::parse_statements(
                item,
                &settled.source,
                &settled.syntax,
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
        let settled=match self.settlement_checked(){Ok(settled)=>settled,Err(refusal)=>return Err(admission.take_operational_error().map(BodySyntaxFailure::Operational).unwrap_or(refusal))};
        self.admit_native_allocation(admission).map_err(BodySyntaxFailure::Operational)?;
        let result = self.parse_using_observed(Some((admission, BodySyntaxFailure::Operational)), |item| {
            body_archive::parse_statements_with_body_literal_admission(
                item,
                &settled.source,
                &settled.syntax,
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
        let settled=self.settlement()?;
        let code=self.original_code.as_ref().ok_or_else(||internal("original body code input is unissued"))?;
        let recipe=if let Some((_,operational))=admission{settled.syntax.original_body_recipe_checked(self.span,code).map_err(|error|match error{BodySyntaxFailure::Operational(actual)=>operational(actual),BodySyntaxFailure::Syntax(source)=>source.into()})?}else{settled.syntax.original_body_recipe(self.span,code).map_err(|error|{observe(&error);Diagnostic{kind:syntax_kind(error.kind),stage:DiagnosticStage::Syntax,location:settled.mapping.output(error.span.start).or_else(||Some(settled.location.clone())),message:error.message}})?};
        let original_window=recipe.source_window().map_err(internal)?;
        let (issued,native_primary_consumed) = match admission {
            Some((a, operational)) => recipe.parse_native_admitted(a).map_err(operational)?,
            None => (recipe.parse_original(),false),
        };
        let mut issued = issued.map_err(|error| {observe(&error);Diagnostic {
                kind: syntax_kind(error.kind),
                stage: DiagnosticStage::Syntax,
                location: settled
                    .mapping
                    .output(error.span.start)
                    .or_else(|| Some(settled.location.clone())),
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
            native_primary_consumed,
            opening_parenthesis: issued.opening_parenthesis,
            parameters: issued.parameters.into_shared(),
            item,
            statements,
            input_bytes: self.span.end.saturating_sub(self.span.start),
            original_code: Arc::clone(code),
            original_window,
            original_body_span:self.span,
            paid_canonical_payload:false,
            _primary_credit:None,
        })
    }
}
impl std::fmt::Debug for BodySyntax {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("BodySyntax")
            .field("issuance", &self.issuance)
            .field("input_bytes", &self.input_bytes)
            .field("body", &self.original_body_span)
            .field("soft_estimate", &self.budget_charge())
            .field("literal_grant", &self.statements.literal_admission)
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
        if self.paid_canonical_payload{return CANONICAL_UNFUNDED_METADATA_ESTIMATE}
        syntax_budget_charge(self.input_bytes)
            // Replace ONLY the known primary-Item component of this SOFT
            // estimate. The actual lease remains live; this is no refund.
            .saturating_sub(self._primary_credit.as_ref().map_or(0,dm_syntax::SettingRootLease::bytes))
            .saturating_add(self.parameters.retained_bytes())
            .saturating_add(
                self.statements
                    .parsed()
                    .local_variables
                    .retained_admission(),
            )
    }
}

// Preserve the existing fixed soft metadata allowance. It remains an estimate,
// not a hard credit or claim that public Arc/Weak wrapper storage is admitted.
const CANONICAL_UNFUNDED_METADATA_ESTIMATE:usize=4096;
impl BodySyntax{
 pub(super) fn canonical_payload_admitted(primary:Option<&dm_syntax::SettingRootLease>,parameters:&dm_syntax::SharedParameterSignature,statements:&StatementBody,a:&dm_syntax::SettingAdmission<'_>)->bool{
  fn arc_bytes<T>()->Option<usize>{let(layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<T>()).ok()?;Some(layout.pad_to_align().size())}
  let metadata=arc_bytes::<BodySyntax>().and_then(|n|n.checked_add(arc_bytes::<StatementBody>()?)).and_then(|n|n.checked_add(arc_bytes::<OriginalBodySyntaxProduct>()?));
  primary.is_some_and(|credit|a.matches_lease_domain(credit))&&parameters.is_admitted_by(a)
   &&statements.is_native_literal_syntax_admitted_by(a)&&!statements.stored_candidates
   &&statements.declaration_headers.capacity()==0
   &&metadata.is_some_and(|bytes|bytes<=CANONICAL_UNFUNDED_METADATA_ESTIMATE)
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
    /// Synchronous first computation on the SAME canonical Kind4. The producer
    /// is borrowed for this call only; owned ordinary Params remain available
    /// for later settled recomputation after normal eviction.
    fn syntax_product_at_committed_input(
      &self,_:&Arc<BodySyntaxInput>,_:&dm_syntax::SettingAdmission<'_>,
      _produce:&mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->Result<OriginalBodySyntaxProduct,BodySyntaxFailure>,
    )->Result<Arc<OriginalBodySyntaxProduct>,BodySyntaxFailure>{
      Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"actual committed BODY first computation is unavailable")))
    }

    /// Quiescent admission boundary: collect expired issuance metadata once,
    /// never scan the whole graph for every body in a large program.
    fn begin_revision(&self) {}
    /// Refresh only already-registered canonical locators before pruning old
    /// weak issuances. No parse, source/model or new cache is created here.
    fn begin_revision_inputs(&self,_:&[Arc<BodySyntaxInput>]){self.begin_revision()}
    /// Explicit native demand capability. Defaults refuse, never silently
    /// replacing an actual complete roster with an empty compatibility slice.
    fn supports_ordinary_input_demand(&self)->bool{false}
    /// Cache-registration observation only: no allocation/query/pruning.
    fn has_registered_body_code(&self,_:&Arc<BodyCodeIdentity>)->bool{false}
    /// Rebind ONLY an existing native weak registry entry, without pruning.
    /// Native attachment calls begin_revision once AFTER all genuine hits.
    fn rebind_registered_body_input(&self,_:&Arc<BodySyntaxInput>)->Result<bool,BodySyntaxFailure>{Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"native sparse body registration is unavailable")))}

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

enum BodyQueryInputValue{Eager(Arc<[Arc<BodySyntaxInput>]>),Demand(Arc<dm_syntax::AdmittedOrdinalSlots<BodySyntaxInput>>)}
impl std::fmt::Debug for BodyQueryInputValue{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{match self{Self::Eager(rows)=>f.debug_tuple("Eager").field(&rows.len()).finish(),Self::Demand(slots)=>std::fmt::Debug::fmt(slots,f)}}}
struct BodyQueryInputOwner{value:BodyQueryInputValue,credit:Option<dm_syntax::SettingRootLease>}
impl std::fmt::Debug for BodyQueryInputOwner{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("BodyQueryInputOwner").field("value",&self.value).field("funded_bytes",&self.credit.as_ref().map(|c|c.bytes())).finish()}}
/// Shared opaque storage keeps its real grant through frontend/archive clones.
/// Eager slice remains a complete slice; demand never exposes a partial slice.
#[derive(Clone,Debug)]pub(super)struct BodyQueryInputs{owner:Arc<BodyQueryInputOwner>}
impl BodyQueryInputs{
 pub(super) fn eager(inputs:Arc<[Arc<BodySyntaxInput>]>)->Self{Self{owner:Arc::new(BodyQueryInputOwner{value:BodyQueryInputValue::Eager(inputs),credit:None})}}
 pub(super) fn eager_admitted(inputs:Arc<[Arc<BodySyntaxInput>]>,a:&dm_syntax::SettingAdmission<'_>)->Result<Self,BodySyntaxFailure>{let credit=Self::owner_credit(a)?;Ok(Self{owner:Arc::new(BodyQueryInputOwner{value:BodyQueryInputValue::Eager(inputs),credit:Some(credit)})})}
 fn owner_credit(a:&dm_syntax::SettingAdmission<'_>)->Result<dm_syntax::SettingRootLease,BodySyntaxFailure>{let(layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<BodyQueryInputOwner>()).map_err(|_|BodySyntaxFailure::Operational(std::io::ErrorKind::OutOfMemory.into()))?;a.reserve(layout.pad_to_align().size()).map_err(BodySyntaxFailure::Operational)}
 fn demand(a:&dm_syntax::SettingAdmission<'_>)->Result<Self,BodySyntaxFailure>{let credit=Self::owner_credit(a)?;let slots=dm_syntax::AdmittedOrdinalSlots::new_shared(a,0).map_err(BodySyntaxFailure::Operational)?;Ok(Self{owner:Arc::new(BodyQueryInputOwner{value:BodyQueryInputValue::Demand(slots),credit:Some(credit)})})}
 pub(super) fn eager_slice(&self)->Option<&[Arc<BodySyntaxInput>]>{match &self.owner.value{BodyQueryInputValue::Eager(inputs)=>Some(inputs),BodyQueryInputValue::Demand(_)=>None}}
 pub(super) fn requires_admission(&self)->bool{self.owner.credit.is_some()}
 pub(super) fn is_demand(&self)->bool{matches!(&self.owner.value,BodyQueryInputValue::Demand(_))}
 pub(super) fn issued(&self,ordinal:usize)->Option<Arc<BodySyntaxInput>>{match &self.owner.value{BodyQueryInputValue::Eager(inputs)=>inputs.get(ordinal).cloned(),BodyQueryInputValue::Demand(slots)=>slots.issued(ordinal)}}
 fn get_or_create(&self,count:usize,ordinal:usize,a:&dm_syntax::SettingAdmission<'_>,create:impl FnOnce()->Result<Arc<BodySyntaxInput>,BodySyntaxFailure>)->Result<Arc<BodySyntaxInput>,BodySyntaxFailure>{
  // Old portable eager attachment keeps its explicitly unqualified metadata
  // owner. Native admitted eager/demand owners must validate their SAME domain.
  if self.owner.credit.as_ref().is_some_and(|credit|!a.matches_lease_domain(credit)){return Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"body Input storage belongs to another admission domain")))}
  match &self.owner.value{BodyQueryInputValue::Eager(inputs)=>inputs.get(ordinal).cloned().ok_or_else(||binding_error("eager body ordinal absent")),BodyQueryInputValue::Demand(slots)=>{if self.owner.credit.is_none(){return Err(binding_error("native demanded Input storage has no actual fixed grant"))}slots.get_or_create(count,ordinal,a,create).map_err(|error|match error{dm_syntax::OrdinalSlotFailure::Admission(actual)=>BodySyntaxFailure::Operational(actual),dm_syntax::OrdinalSlotFailure::Value(actual)=>actual})}}
 }
 pub(super) fn visit_issued(&self,visit:&mut dyn FnMut(usize,&Arc<BodySyntaxInput>))->std::io::Result<()>{match &self.owner.value{BodyQueryInputValue::Eager(inputs)=>{for(ordinal,input)in inputs.iter().enumerate(){visit(ordinal,input)}Ok(())},BodyQueryInputValue::Demand(slots)=>slots.visit_issued(visit)}}
 pub(super) fn visit_storage(&self,visit:&mut dyn FnMut(usize,usize,usize))->std::io::Result<()>{
  let(layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<BodyQueryInputOwner>()).expect("actual body Input store Arc layout");visit(Arc::as_ptr(&self.owner)as usize,std::mem::size_of::<BodyQueryInputOwner>(),layout.pad_to_align().size());if let Some(credit)=&self.owner.credit{credit.visit_counter_storage(|p,n|visit(p,n,n));}
  match &self.owner.value{BodyQueryInputValue::Eager(inputs)=>{let bytes=std::mem::size_of_val(inputs.as_ref());visit(inputs.as_ptr()as usize,bytes,bytes);Ok(())},BodyQueryInputValue::Demand(slots)=>slots.visit_storage(visit)}
 }
}
#[derive(Clone,Debug)]pub(super)struct BodyQueries{pub host:Arc<dyn BodySyntaxQueries>,pub inputs:BodyQueryInputs}


impl ColdFrontend {
    /// Observe only actual attached owners; this never attaches or demands rows.
    pub(super) fn trace_attached_body_owners(&self,route:&'static str){
        if let Some(queries)=&self.body_queries{write_existing_body_query_attachment(self,&queries.inputs,route);}
        else if std::env::var_os("DMB_ORIGINAL_TRACE_BODY_PRESSURE").is_some(){
            use std::io::Write as _;
            let _=writeln!(std::io::stderr().lock(),"ORIGINAL_BODY_OWNER_DIAGNOSTIC trigger={route} actual_body_query_bank=unavailable");
        }
    }
    /// Opt in only after declaration construction. The source, occurrence list
    /// and syntax are captured together; callers cannot substitute foreign ASTs.
    pub fn with_body_queries(mut self, host: Arc<dyn BodySyntaxQueries>) -> Self {
        if self.original_primary.as_ref().is_some_and(|primary|primary.ordinary_code_demand()){return self}
        if self.issued_syntax.has_parser_report_prefix(){return self}
        if self.original_primary.as_ref().is_some_and(|primary|primary.has_committed_bodies()){
            if let Some(mut queries)=self.body_queries.take(){
                host.begin_revision_inputs(queries.inputs.eager_slice().expect("committed full input roster"));queries.host=host;self.body_queries=Some(queries);self.reused_body_queries=false;return self
            }
            // Unsettled preparations are never exported by the checked builder.
            // Do not mint a fresh input identity if that invariant is violated.
            return self
        }

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
                Arc::new_cyclic(|weak|BodySyntaxInput {
                    allocation_owner:Arc::new(BodySyntaxInputWeak::new(weak.clone(),None)),
                    id: NEXT_BODY_INPUT.fetch_add(1, std::sync::atomic::Ordering::Relaxed),
                    original_code: self
                        .issued_body_codes
                        .get(ordinal)
                        .and_then(|owner|owner.identity.as_ref().map(Arc::clone)),
                    settled:std::sync::OnceLock::from(BodyInputSettlement{
                        source:self.issued_arena.clone(),syntax:self.issued_syntax.clone(),
                        location:body.source.clone(),mapping:BodyDiagnosticProjection::Complete(Arc::clone(&self.source_export_mapping)),
                    }),
                    span:body.expanded_span,
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
        self.body_queries = Some(BodyQueries { host, inputs:BodyQueryInputs::eager(inputs) });
        self
    }
}


pub(super) fn issue_generation_body(
    geometry:&Arc<super::generation::GenerationQuestionGeometry>,
    syntax:&Arc<DeclarationSyntax>, body:&BodyOccurrence, code:Arc<BodyCodeIdentity>,
)->Arc<BodySyntaxInput>{
    Arc::new_cyclic(|weak|BodySyntaxInput{
        id:NEXT_BODY_INPUT.fetch_add(1,std::sync::atomic::Ordering::Relaxed),
        settled:std::sync::OnceLock::from(BodyInputSettlement{
            source:geometry.expanded.text.clone(),syntax:Arc::clone(syntax),location:body.source.clone(),
            mapping:BodyDiagnosticProjection::Generation(Arc::clone(geometry)),
        }),span:body.expanded_span,
        parameter_admission:syntax.item_path(&body.ast_path).map(|item|item.header_span().end.saturating_sub(item.header_span().start).saturating_mul(128).saturating_add(1024)).unwrap_or(usize::MAX),
        original_code:Some(code),allocation_owner:Arc::new(BodySyntaxInputWeak::new(weak.clone(),None)),
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
pub struct CurrentBodySyntax<'a>{original:&'a BodySyntax,input:&'a BodySyntaxInput,settled:&'a BodyInputSettlement,projection:dm_syntax::SyntaxProjection,deferred_literal_roots:usize}
fn binding_error(message:&str)->BodySyntaxFailure{BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,message))}
fn binding_view_error(error:dm_syntax::SyntaxViewError)->BodySyntaxFailure{binding_error(&format!("actual original code projection differs: {error:?}"))}
impl BodySyntaxInput{
 pub fn bind_original_product_checked<'a>(&'a self,original:&'a BodySyntax,admission:&dm_syntax::SettingAdmission<'_>)->Result<CurrentBodySyntax<'a>,BodySyntaxFailure>{
  let pending=(||{admission.checkpoint().map_err(BodySyntaxFailure::Operational)?;
   let settled=self.settlement_checked()?;
   self.admit_native_allocation(admission).map_err(BodySyntaxFailure::Operational)?;
   let code=self.original_code.as_ref().ok_or_else(||binding_error("current body code is unissued"))?;
   if !Arc::ptr_eq(code,&original.original_code){return Err(binding_error("current body code is not the parser product's original code owner"))}
   let recipe=settled.syntax.original_body_recipe_checked(self.span,code)?;
   // Actual current capture authenticated this private code identity. Only
   // parser-code DATA can converge: its current header/model owner is fresh.
   recipe.setting_headers().ok_or_else(||binding_error("current original header owner is absent"))?;
   if !original.statements.is_native_literal_syntax_admitted_by(admission){return Err(binding_error("parser product belongs to another native resource domain"))}
   let current_window=recipe.source_window().map_err(binding_error)?;
   if original.original_body_span.start<original.original_window.start||original.original_body_span.end>original.original_window.end||self.span.start<current_window.start||self.span.end>current_window.end{return Err(binding_error("actual original/current body escaped its primary source window"))}
   let projection=dm_syntax::SyntaxProjection::new(original.original_body_span,self.span).map_err(BodySyntaxFailure::Operational)?;
   dm_syntax::ProjectedParameterSignature::new(&original.parameters,projection).map_err(binding_view_error)?;
   admission.checkpoint().map_err(BodySyntaxFailure::Operational)?;
   let mut bound=CurrentBodySyntax{original,input:self,settled,projection,deferred_literal_roots:0};bound.deferred_literal_roots=bound.validate_issued_coordinates(admission)?;Ok(bound)
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
  dm_syntax::ProjectedPendingBodies::new(&self.original.statements.parsed().pending_bodies,self.projection).headers().map(move|at|{checkpoint().map_err(BodySyntaxFailure::Operational)?;let header=at.map_err(binding_view_error)?;let termination=dm_syntax::termination_after_with_context(&self.settled.source,header.end,&|offset|self.settled.syntax.declaration_header_at(offset));Ok(dm_syntax::PendingBody{header,termination})})
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
  self.validate_issued_coordinates_with_native_children(a,false)
 }
 fn validate_issued_coordinates_with_native_children(&self,a:&dm_syntax::SettingAdmission<'_>,native:bool)->Result<usize,BodySyntaxFailure>{
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
    if native{
      if let dm_syntax::ExprKind::Literal(text)=&root.original().kind{
       if text.owns_template_syntax()&&!text.native_parser_facts().is_some_and(|facts|facts.is_complete()&&!facts.recovered()&&!facts.deferred()){
        deferred=deferred.checked_add(1).ok_or_else(||binding_error("native deferred literal count overflows"))?;
       }
      }
    }
    if let dm_syntax::ExprKind::Literal(text)=&root.original().kind{if text.owns_template_syntax()&&!matches!(text.prepared_syntax_parts(),Some(Ok(_))){deferred=deferred.checked_add(1).ok_or_else(||binding_error("deferred literal count overflows"))?;continue}}
    if matches!(root.original().kind,dm_syntax::ExprKind::Literal(_)){if let Some(fragments)=root.literal_fragments().map_err(binding_view_error)?{for fragment in fragments{a.checkpoint().map_err(BodySyntaxFailure::Operational)?;let fragment=fragment.map_err(binding_view_error)?;for token in fragment.tokens(){a.checkpoint().map_err(BodySyntaxFailure::Operational)?;token.map_err(binding_view_error)?;}fragment.expression().map_err(binding_view_error)?;}}}
    let children=root.try_visit_children(|_,child|work.expression(Some(child.map_err(binding_view_error)?),a))?;children.map_err(binding_view_error)?;
   }
   BindingNode::Statement(row)=>{
    // Inspect only the original issued node. Projected setting children keep
    // the same payload and resource owner, with a composed current window.
    if let dm_syntax::StatementKind::ProjectedSet{value,..}=&row.original().kind{
      // Actual setting observation already folded before the private BODY seal.
      if !value.is_retained_in(a){return Err(binding_error("setting parser product belongs to another native resource domain"))}let value=dm_syntax::ProjectedSettingExpression::new(value,self.projection).map_err(binding_view_error)?;work.expression(Some(value.expression()),a)?;continue}
    use dm_syntax::ProjectedStatementKind as S;match row.kind().map_err(binding_view_error)?{
     S::If{condition,then_branch,else_branch}=>{work.expression(Some(condition),a)?;work.statements(then_branch,a)?;work.statements(else_branch,a)?;}
     S::While{condition,body}|S::DoWhile{condition,body}=>{work.expression(Some(condition),a)?;work.statements(body,a)?;}
     S::Spawn{delay,body}=>{work.expression(delay,a)?;work.statements(body,a)?;}
     S::Set{value,..}|S::Throw(value)|S::Delete(value)|S::Call(value)|S::Expression(value)=>work.expression(Some(value),a)?,
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
  front.body_queries.as_ref().unwrap().inputs.issued(ordinal).expect("eager test Input")
 }

 fn same_chunk(state:&mut RetainedSemanticTree,source:&str,host:&Arc<NativeHost>)->ColdFrontend{
  let input=Source(std::collections::BTreeMap::from([(PathBuf::from("same-body.dme"),acquired(source))]));let executor=dm_exec::BuildExecutor::new(1).unwrap();
  build_with_executor_and_semantic_state_for_policy_checked(Path::new("same-body.dme"),&input,&Default::default(),FrontendConfig{workers:1,engine:None,observer:None},None,&executor,Some(state),true,&(Arc::clone(host)as Arc<dyn SettingExpressionQueries>)).unwrap().with_body_queries(Arc::clone(host)as Arc<dyn BodySyntaxQueries>)
 }
 #[test]fn canonical_owned_primary_refusal_keeps_payload_credit_through_error_and_first_io_unwind(){
  let host=NativeHost::new();let root=host.counter.load(Ordering::Acquire);let a=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||Ok(()));
  let credit=a.reserve(4096).unwrap();let diagnostic=dm_syntax::parse_expression("1+").diagnostics.into_iter().next().unwrap();let pointer=diagnostic.message.as_ptr();let message=diagnostic.message.clone();
  let error=retain_owned_primary_unsupported(diagnostic,credit,&a);let BodySyntaxFailure::Operational(actual)=error else{panic!("owned operational syntax refusal")};assert_eq!(actual.kind(),std::io::ErrorKind::Unsupported);assert_eq!(actual.to_string(),message);
  let owned=actual.get_ref().unwrap().downcast_ref::<FundedPrimarySyntaxRefusal>().unwrap();assert_eq!(owned.message.as_ptr(),pointer,"same actual parser message moves without a clone");assert_eq!(host.counter.load(Ordering::Acquire),root+owned._credit.bytes());drop(actual);assert_eq!(host.counter.load(Ordering::Acquire),root);
  let credit=a.reserve(4096).unwrap();let diagnostic=dm_syntax::parse_expression("1+").diagnostics.into_iter().next().unwrap();let stopped=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||Err(std::io::Error::from_raw_os_error(1450)));let error=retain_owned_primary_unsupported(diagnostic,credit,&stopped);assert!(matches!(error,BodySyntaxFailure::Operational(ref actual)if actual.raw_os_error()==Some(1450)));drop(error);assert_eq!(host.counter.load(Ordering::Acquire),root);
  let credit=a.reserve(4096).unwrap();let diagnostic=dm_syntax::parse_expression("1+").diagnostics.into_iter().next().unwrap();let panicking=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||panic!("actual handoff checkpoint panic"));let result=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||retain_owned_primary_unsupported(diagnostic,credit,&panicking)));assert!(result.is_err());assert_eq!(host.counter.load(Ordering::Acquire),root);
 }
 #[test]fn canonical_token_cleanup_plan_rejects_foreign_code_body_and_domain_and_funds_actual_rejection(){
  let host=Arc::new(NativeHost::new());let mut state=RetainedSemanticTree::new();let front=same_chunk(&mut state,"/proc/p()\n    return 1+\n",&host);let original=input(&front);let settled=original.settlement_checked().unwrap();let code=original.original_code_owner().unwrap();let a=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||Ok(()));
  let other=same_chunk(&mut state,"/proc/p()\n    return 2\n",&host);let other_input=input(&other);let other_code=other_input.original_code_owner().unwrap();assert!(!Arc::ptr_eq(code,other_code));let before=host.counter.load(Ordering::Acquire);
  let make=||body_archive::reserve_installed_canonical_cleanup(&settled.syntax,&settled.source,original.span,code,&a).unwrap();
  assert!(make().into_lease(original.span,other_code,&a).is_err());assert_eq!(host.counter.load(Ordering::Acquire),before);
  assert!(make().into_lease(dm_syntax::Span::new(original.span.start,original.span.end-1),code,&a).is_err());assert_eq!(host.counter.load(Ordering::Acquire),before);
  let foreign=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let foreign_a=dm_syntax::SettingAdmission::new(&foreign,1<<26,&||Ok(()));assert!(make().into_lease(original.span,code,&foreign_a).is_err());assert_eq!(host.counter.load(Ordering::Acquire),before);
  let mut diagnostic=dm_syntax::parse_expression("1+").diagnostics.into_iter().next().unwrap();let at=settled.source.rfind("1+").unwrap();diagnostic.span.start+=at;diagnostic.span.end+=at;
  let cleanup=make().into_lease(original.span,code,&a).unwrap();let product=retain_canonical_rejection(Arc::clone(code),original.span,diagnostic,cleanup,&a).unwrap();assert!(product.bind_error(&original).unwrap().is_some());drop(product);assert_eq!(host.counter.load(Ordering::Acquire),before);
 }
 #[test]fn real_same_chunk_body_binding_after_length_change_and_earlier_shift_keeps_current_private_recipe(){
  let mut state=RetainedSemanticTree::new();let host=Arc::new(NativeHost::new());
  let long=format!("/proc/q()\n    return {}\n{}",123456789,P);let old=same_chunk(&mut state,&long,&host);let original=input(&old);let product=host.syntax_checked(&original).unwrap();
  let shorter=format!("/proc/q()\n    return 1\n{P}");let new=same_chunk(&mut state,&shorter,&host);let current=input(&new);assert!(current.span.start<original.span.start);let a=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||Ok(()));let view=current.bind_original_product_checked(&product,&a).unwrap();assert_eq!(host.parses.load(Ordering::Relaxed),1);
  assert_eq!(view.header_span(),current.settlement_checked().unwrap().syntax.item_path(&new.issued_bodies.iter().find(|row|row.expanded_span==current.span).unwrap().ast_path).unwrap().header_span());
  let first=view.statements().iter().next().unwrap().unwrap();let dm_syntax::ProjectedStatementKind::ProjectedSet{value,..}=first.kind().unwrap()else{panic!("real native setting statement")};let dm_syntax::StatementKind::ProjectedSet{value:old_root,..}=&first.original().kind else{panic!("one old retained root")};assert!(value.same_root(old_root));assert_eq!(value.original_source_window(),old_root.current_projection().original());assert_eq!(&current.settlement_checked().unwrap().source[value.current_span().range()],"\"p\"");
  let parameters=view.parameters().unwrap();let parameter=parameters.entries().unwrap().next().unwrap();assert_eq!(&current.settlement_checked().unwrap().source[parameter.default().unwrap().unwrap().span().range()],"list(1,2)");
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
  for(diagnostic,original)in diagnostics.iter().zip(&parsed.statements.parsed().diagnostics){let span=bound.projection().span(original.span).unwrap();let actual=current.settlement_checked().unwrap().mapping.output(span.start).unwrap();assert_eq!(diagnostic.message,original.message);assert_eq!(diagnostic.kind,syntax_kind(original.kind));assert_eq!(diagnostic.location.as_ref().unwrap().line,actual.line);assert_eq!(actual.line,old.settlement_checked().unwrap().mapping.output(original.span.start).unwrap().line+1);}
  assert!(std::ptr::eq(bound.original.statements.as_ref(),parsed.statements.as_ref()));assert_eq!(host.parses.load(Ordering::Relaxed),0,"product API executed native parser once directly, no host callback reparse");
 }

 const P:&str="/proc/p(value=list(1,2))\n    set name = \"p\"\n    var/local[2]=list(1,2)\n    if(value)\n        return \"a[value]z\"\n    return\n";
 #[test]fn actual_retained_body_product_binds_current_offset_and_all_private_ledgers_without_a_second_parse(){
  let mut state=RetainedSemanticTree::new();let host=Arc::new(NativeHost::new());let p=acquired(P);
  let old=front(&mut state,p.clone(),q(""),&host);let original_input=input(&old);let product=host.syntax_checked(&original_input).unwrap();assert_eq!(host.parses.load(Ordering::Relaxed),1);
  let shifted=front(&mut state,p.clone(),q("// real preceding edit changes the following expanded offset\n\n"),&host);let current=input(&shifted);assert_ne!(original_input.span.start,current.span.start);assert_ne!(original_input.key(),current.key());
  let a=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||Ok(()));let bound=current.bind_original_product_checked(&product,&a).unwrap();assert_eq!(bound.current_input_key(),current.key());assert_eq!(bound.body_span(),current.span);assert_eq!(host.parses.load(Ordering::Relaxed),1);
  let parameters=bound.parameters().unwrap();assert!(std::ptr::eq(parameters.original(),product.parameters.as_ref()));let parameter=parameters.entries().unwrap().next().unwrap();assert_eq!(&current.settlement_checked().unwrap().source[parameter.name().unwrap().range()],"value");let root=parameter.default().unwrap().unwrap();assert_eq!(&current.settlement_checked().unwrap().source[root.span().range()],"list(1,2)");assert!(std::ptr::eq(root.original(),product.parameters.entries().unwrap()[0].expressions().unwrap().unwrap().default().unwrap()));
  let locals=bound.locals().entries().unwrap().collect::<Vec<_>>();assert_eq!(locals.len(),1);assert_eq!(&current.settlement_checked().unwrap().source[locals[0].name().unwrap().range()],"local");assert!(bound.controls().entries().next().is_some());for pending in bound.pending_current_using(&||Ok(())){let pending=pending.unwrap();assert!(pending.header.end<=current.settlement_checked().unwrap().source.len());}
  let first=bound.statements().iter().next().unwrap().unwrap();assert!(std::ptr::eq(first.original(),&product.statements.parsed().statements[0]));if let dm_syntax::StatementKind::ProjectedSet{value:original,..}=&first.original().kind{let dm_syntax::ProjectedStatementKind::ProjectedSet{value:rebound,..}=first.kind().unwrap()else{panic!("actual retained setting root")};assert!(rebound.same_root(original));assert_eq!(rebound.original_source_window(),original.current_projection().original());assert_eq!(rebound.current_span(),bound.projection().span(original.current_span()).unwrap());}
  assert!(matches!(current.obtain_checked_using(|_|Ok(Arc::clone(&product))),Err(BodySyntaxFailure::Syntax(_))),"old foreign-issuance API must remain strict");
  let fresh=front(&mut RetainedSemanticTree::new(),p.clone(),q("// real preceding edit changes the following expanded offset\n\n"),&host);assert!(input(&fresh).bind_original_product_checked(&product,&a).is_err(),"equal source bytes never issue code authority");
  let changed=front(&mut state,acquired(P.replace("list(1,2)","list(3,4)")),q(""),&host);assert!(input(&changed).bind_original_product_checked(&product,&a).is_err(),"changed actual code must not bind");
  assert_eq!(host.parses.load(Ordering::Relaxed),1);
 }
 #[test]
 fn canonical_rejection_retires_startup_headroom_but_keeps_actual_product_until_drop(){
  let mut state=RetainedSemanticTree::new();let host=Arc::new(NativeHost::new());
  let front=same_chunk(&mut state,"/proc/p()\n    return\n",&host);let input=input(&front);
  let a=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||Ok(()));
  let before=host.counter.load(Ordering::Acquire);
  let diagnostic=dm_syntax::parse_expression("1+").diagnostics.into_iter().next().expect("actual parser error");
  let message=diagnostic.message.clone();
  let cleanup=a.reserve(1<<20).unwrap();
  let product=retain_canonical_rejection(Arc::clone(input.original_code_owner().unwrap()),input.span,diagnostic,cleanup,&a).unwrap();
  let OriginalBodySyntaxProduct::Rejected(error)=&product else{panic!("retained actual rejection")};
  let(layout,_)=std::alloc::Layout::new::<[AtomicUsize;2]>().extend(std::alloc::Layout::new::<OriginalBodySyntaxProduct>()).unwrap();
  let retained=layout.pad_to_align().size()+error.diagnostic.message.capacity();
  assert_eq!(error.diagnostic.message,message);
  assert_eq!(error._cleanup.bytes(),retained);
  assert_eq!(host.counter.load(Ordering::Acquire),before+retained);
  assert!(retained<1<<20,"source-width startup envelope must not remain live");
  let extra=a.reserve((1<<20)-retained).expect("same ledger reuses only retired headroom");drop(extra);
  drop(product);assert_eq!(host.counter.load(Ordering::Acquire),before);
 }
 #[test]
 fn canonical_rejection_preserves_first_io_and_refunds_failed_handoff(){
  let mut state=RetainedSemanticTree::new();let host=Arc::new(NativeHost::new());
  let front=same_chunk(&mut state,"/proc/p()\n    return\n",&host);let input=input(&front);
  let a=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||Ok(()));
  let before=host.counter.load(Ordering::Acquire);let cleanup=a.reserve(1<<20).unwrap();
  let fault=||Err(std::io::Error::from_raw_os_error(1450));
  let stopped=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&fault);
  let diagnostic=dm_syntax::parse_expression("1+").diagnostics.into_iter().next().unwrap();
  let Err(BodySyntaxFailure::Operational(actual))=retain_canonical_rejection(Arc::clone(input.original_code_owner().unwrap()),input.span,diagnostic,cleanup,&stopped) else{panic!("actual IO must win")};
  assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(host.counter.load(Ordering::Acquire),before);
 }
 #[test]fn actual_body_binding_preserves_typed_operational_failures_and_native_resource_identity(){
  let mut state=RetainedSemanticTree::new();let host=Arc::new(NativeHost::new());let first=front(&mut state,acquired(P),q(""),&host);let old=input(&first);let product=host.syntax_checked(&old).unwrap();let next=front(&mut state,acquired(P),q("// shifted\n"),&host);let current=input(&next);
  let foreign=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=dm_syntax::SettingAdmission::new(&foreign,1<<26,&||Ok(()));assert!(current.bind_original_product_checked(&product,&a).is_err());
  let fault=||Err(std::io::Error::from_raw_os_error(1450));let a=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&fault);let Err(BodySyntaxFailure::Operational(error))=current.bind_original_product_checked(&product,&a)else{panic!("real typed operational failure")};assert_eq!(error.raw_os_error(),Some(1450));
  let used=host.counter.load(Ordering::Acquire);let a=dm_syntax::SettingAdmission::new(&host.counter,used,&||Ok(()));let Err(BodySyntaxFailure::Operational(error))=current.bind_original_product_checked(&product,&a)else{panic!("actual temporary-work admission denied")};assert_eq!(error.kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(host.counter.load(Ordering::Acquire),used);
  let a=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||Ok(()));assert!(current.bind_original_product_checked(&product,&a).is_ok());assert_eq!(host.parses.load(Ordering::Relaxed),1);
 }

 #[test]
 fn native_only_bare_return_grant_uses_actual_product_end_and_current_coordinates(){
  for source in ["/proc/p()\n    return\n","/proc/p()\n    return\n/proc/later()\n    return 2\n"]{
   let mut state=RetainedSemanticTree::new();let host=Arc::new(NativeHost::new());
   let front=same_chunk(&mut state,source,&host);let input=input(&front);
   let a=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||Ok(()));
   let product=input.parse_original_product_with_setting_admission(&a).unwrap();
   let parsed=product.parsed().unwrap();let bound=input.bind_original_product_checked(parsed,&a).unwrap();
   let Err(BodySyntaxFailure::Operational(old))=bound.original_code_disposition()
    else{panic!("native-default fixture must not mint an Original-only profile")};
   assert_eq!(old.kind(),std::io::ErrorKind::Unsupported);
   assert_eq!(old.to_string(),"original body grammar profile is not actually issued");
   match bound.native_code_disposition_using(&a).unwrap(){
    NativeBodyDisposition::Complete(grant)=>{assert!(grant.belongs_to(&bound));assert_eq!(&input.settlement().unwrap().source[grant.statement_span().expect("sole actual statement").range()],"return");}
    _=>panic!("actual single bare-return production must complete"),
   }
   assert_eq!(host.parses.load(Ordering::Relaxed),0,"same direct actual producer, no reparse through query host");
  }
 }
 #[test]
 fn native_variadic_production_keeps_real_signature_and_separate_original_profile(){
  let mut state=RetainedSemanticTree::new();let host=Arc::new(NativeHost::new());
  let front=same_chunk(&mut state,"/proc/p(...)\n    return\n",&host);let input=input(&front);
  let a=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||Ok(()));
  let product=input.parse_original_product_with_setting_admission(&a).unwrap();
  let bound=input.bind_original_product_checked(product.parsed().unwrap(),&a).unwrap();
  let Err(BodySyntaxFailure::Operational(old))=bound.original_code_disposition() else{panic!("native-default must not issue Original grammar")};
  assert_eq!(old.kind(),std::io::ErrorKind::Unsupported);
  match bound.native_code_disposition_using(&a).unwrap(){NativeBodyDisposition::Complete(grant)=>assert!(grant.belongs_to(&bound)),_=>panic!("actual native variadic no-child production must complete")}
 }
 #[test]
 fn actual_early_body_input_refuses_unsettled_then_keeps_same_final_identity_and_weak_lifetime(){
  let mut state=RetainedSemanticTree::new();let host=Arc::new(NativeHost::new());let front=same_chunk(&mut state,"/proc/p()\n    return\n",&host);let ordinary=input(&front);let ordinal=front.issued_body_codes.iter().position(|code|code.identity.as_ref().is_some_and(|code|Arc::ptr_eq(code,ordinary.original_code.as_ref().unwrap()))).unwrap();
  let early=issue_unsettled_body(ordinary.span,Arc::clone(ordinary.original_code.as_ref().unwrap()),ordinary.parameter_admission).unwrap();let id=early.key();let weak=Arc::downgrade(&early);
  assert!(early.parse().is_err());assert!(early.obtain_checked(&*host).is_err());assert_eq!(host.parses.load(Ordering::Relaxed),0,"unset input cannot enter general query host");
  {let refusing=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||panic!("unset input refusal must not perform a fresh poll"));refusing.record_operational_error(std::io::Error::from_raw_os_error(1450));let Err(BodySyntaxFailure::Operational(actual))=early.parse_with_setting_admission(&refusing)else{panic!("earlier actual admission IO must stay first")};assert_eq!(actual.raw_os_error(),Some(1450));}
  early.settle_for_final_frontend(&front,ordinal).unwrap();assert_eq!(early.key(),id);assert!(early.settle_for_final_frontend(&front,ordinal).is_err(),"settlement is one-shot");
  let a=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||Ok(()));let product=early.parse_original_product_with_setting_admission(&a).unwrap();
  {let bound=early.bind_original_product_checked(product.parsed().unwrap(),&a).unwrap();assert_eq!(bound.current_input_key(),id);}
  let final_inputs:Arc<[Arc<BodySyntaxInput>]> =vec![Arc::clone(&early)].into();drop(early);assert!(weak.upgrade().is_some(),"actual final input owner keeps graph weak Params live");drop(final_inputs);assert!(weak.upgrade().is_none(),"product alone must not form a Header/Input cycle");drop(product);
 }
 #[test]
 fn actual_early_body_input_settlement_rejects_foreign_code_and_reports_exact_phase_extent(){
  #[allow(dead_code)]struct PriorInput{id:u64,source:dm_preprocess::SourceText,syntax:Arc<DeclarationSyntax>,span:dm_syntax::Span,location:SourceLocation,mapping:BodyDiagnosticProjection,parameter_admission:usize,original_code:Option<Arc<BodyCodeIdentity>>}
  let prior=std::mem::size_of::<PriorInput>();let current=std::mem::size_of::<BodySyntaxInput>();eprintln!("BODY_INPUT_PHASE_SIZE prior={prior} current={current} delta={}",current as isize-prior as isize);let allocation=unsettled_body_input_allocation_bytes();assert!(allocation>=current+2*std::mem::size_of::<std::sync::atomic::AtomicUsize>());assert_eq!(allocation%std::mem::align_of::<BodySyntaxInput>(),0);
  let host=Arc::new(NativeHost::new());let mut first_state=RetainedSemanticTree::new();let mut first=same_chunk(&mut first_state,"/proc/p()\n    return\n",&host);let actual=input(&first);let ordinal=first.issued_body_codes.iter().position(|code|code.identity.as_ref().is_some_and(|code|Arc::ptr_eq(code,actual.original_code.as_ref().unwrap()))).unwrap();let early=issue_unsettled_body(actual.span,Arc::clone(actual.original_code.as_ref().unwrap()),actual.parameter_admission).unwrap();
  let mut foreign_state=RetainedSemanticTree::new();let foreign=same_chunk(&mut foreign_state,"/proc/p()\n    return\n",&host);assert!(early.settle_for_final_frontend(&foreign,ordinal).is_err());assert!(early.settled.get().is_none());let public=Arc::clone(&first.bodies);first.bodies=Arc::from(Vec::<BodyOccurrence>::new());assert!(early.settle_for_final_frontend(&first,ordinal).is_err(),"mutated public roster cannot authorize final settlement from historical issued fields");assert!(early.settled.get().is_none());first.bodies=public;early.settle_for_final_frontend(&first,ordinal).unwrap();
 }
 #[test]
 fn native_only_census_separates_uncovered_and_deferred_from_original_availability(){
  let mut complete=0;let mut uncovered=0;let mut deferred=0;
  for(source,expected)in [
   ("/proc/p()\n    return\n",0),
   ("/proc/p()\n    return 1\n",0),
   ("/proc/p()\n    return\n    return\n",0),
   ("/proc/p(value)\n    return\n",0),
  ]{
   let mut state=RetainedSemanticTree::new();let host=Arc::new(NativeHost::new());
   let front=same_chunk(&mut state,source,&host);let input=input(&front);
   let a=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||Ok(()));
   let product=input.parse_original_product_with_setting_admission(&a).unwrap();
   let bound=input.bind_original_product_checked(product.parsed().unwrap(),&a).unwrap();
   let actual=match bound.native_code_disposition_using(&a).unwrap(){
    NativeBodyDisposition::Complete(_)=>{complete+=1;0},
    NativeBodyDisposition::NotCovered=>{uncovered+=1;1},
    NativeBodyDisposition::Deferred=>{deferred+=1;2},
    NativeBodyDisposition::Recovered=>3,
   };
   assert_eq!(actual,expected,"actual source native census, not Original relabeling: {source}");
  }
  assert_eq!((complete,uncovered,deferred),(4,0,0));
 }
 #[test]
 fn intrinsic_native_productions_complete_whole_scopes_without_original_relabeling(){
  for source in[
   "/proc/p(value)\n    return value+1\n",
   "/proc/p(value)\n    if(value)\n        return value+1\n    else\n        return value-1\n",
   "/proc/p(value)\n    while(value>0)\n        value-=1\n    return value\n",
   "/proc/p(value)\n    var/result=value+1\n    result+=2\n    return result\n",
   "/proc/p(value)\n    set waitfor = 0\n    return value+1\n",
  ]{
   let mut state=RetainedSemanticTree::new();let host=Arc::new(NativeHost::new());
   let front=same_chunk(&mut state,source,&host);let input=input(&front);
   let a=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||Ok(()));
   let product=input.parse_original_product_with_setting_admission(&a).unwrap();
   let body=product.parsed().expect("actual canonical body");
   let bound=input.bind_original_product_checked(body,&a).unwrap();
   let Err(BodySyntaxFailure::Operational(original))=bound.original_code_disposition()
    else{panic!("native-default expressions must not gain an Original profile")};
   assert_eq!(original.kind(),std::io::ErrorKind::Unsupported);
   assert_eq!(original.to_string(),"original body grammar profile is not actually issued");
   let NativeBodyDisposition::Complete(grant)=bound.native_code_disposition_using(&a).unwrap()else{panic!("actual canonical intrinsic production remains incomplete: {source}")};
   assert!(grant.belongs_to(&bound));assert_eq!(grant.scope_roots(),body.statement_storage().parsed().statements.len());
   assert_eq!(host.parses.load(Ordering::Relaxed),0,"one actual private product, no query reparse");
  }
 }
 #[test]
 fn native_only_grant_keeps_actual_io_foreign_domain_and_exported_data_boundaries(){
  let mut state=RetainedSemanticTree::new();let host=Arc::new(NativeHost::new());
  let front=same_chunk(&mut state,"/proc/p()\n    return\n",&host);let input=input(&front);
  let a=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||Ok(()));
  let product=input.parse_original_product_with_setting_admission(&a).unwrap();
  let parsed=product.parsed().unwrap();let bound=input.bind_original_product_checked(parsed,&a).unwrap();
  let mut exported=parsed.statement_storage().parsed().clone();
  exported.statements.clear();exported.diagnostics.clear();
  assert!(matches!(bound.native_code_disposition_using(&a).unwrap(),NativeBodyDisposition::Complete(_)),
   "mutable public DATA does not mutate the actual private retained product");
  let before=host.counter.load(Ordering::Acquire);
  let bad=||Err(std::io::Error::from_raw_os_error(1450));
  let stopped=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&bad);
  let Err(BodySyntaxFailure::Operational(actual))=bound.native_code_disposition_using(&stopped)
   else{panic!("first actual IO is not a native disposition")};
  assert_eq!(actual.raw_os_error(),Some(1450));
  assert_eq!(host.counter.load(Ordering::Acquire),before);
  let tight=dm_syntax::SettingAdmission::new(&host.counter,before,&||Ok(()));
  let Err(BodySyntaxFailure::Operational(actual))=bound.native_code_disposition_using(&tight)
   else{panic!("real current binding temporary work must be admitted")};
  assert_eq!(actual.kind(),std::io::ErrorKind::OutOfMemory);
  assert_eq!(host.counter.load(Ordering::Acquire),before);
  let foreign=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
  let other=dm_syntax::SettingAdmission::new(&foreign,1<<26,&||Ok(()));
  assert!(bound.native_code_disposition_using(&other).is_err(),"equal budget cannot reissue another resource owner's grant");
  assert!(matches!(bound.native_code_disposition_using(&a).unwrap(),NativeBodyDisposition::Complete(_)));
 }


 #[test]
 fn native_only_retained_bare_return_grant_uses_shifted_current_input_without_reparse(){
  let mut state=RetainedSemanticTree::new();let host=Arc::new(NativeHost::new());
  let source=acquired("/proc/p()\n    return\n");
  let old=front(&mut state,source.clone(),q(""),&host);let original=input(&old);
  let product=host.syntax_checked(&original).unwrap();
  let next=front(&mut state,source.clone(),q("// actual preceding source edit changes current expanded position\n\n"),&host);
  let current=input(&next);assert_ne!(original.span.start,current.span.start);
  let a=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||Ok(()));
  let bound=current.bind_original_product_checked(&product,&a).unwrap();
  let NativeBodyDisposition::Complete(grant)=bound.native_code_disposition_using(&a).unwrap()
   else{panic!("same private product must retain native completeness at its real current projection")};
  assert!(grant.belongs_to(&bound));
  assert_eq!(&current.settlement_checked().unwrap().source[grant.statement_span().expect("sole actual statement").range()],"return");
  assert_ne!(grant.statement_span(),Some(product.statements.parsed().statements[0].header_span));
  assert_eq!(host.parses.load(Ordering::Relaxed),1,"grant uses original canonical product, no parser replay");
  let fresh=front(&mut RetainedSemanticTree::new(),source,q("// actual preceding source edit changes current expanded position\n\n"),&host);
  assert!(input(&fresh).bind_original_product_checked(&product,&a).is_err(),"equal exported source DATA cannot reseal a foreign private product");
  let changed=front(&mut state,acquired("/proc/p()\n    return 1\n"),q(""),&host);
  assert!(input(&changed).bind_original_product_checked(&product,&a).is_err(),"changed canonical code cannot inherit native completion");
 }

 #[test]fn utility_body_projection_keeps_actual_first_io_and_rejects_foreign_current_code(){
  let mut state=RetainedSemanticTree::new();let host=Arc::new(NativeHost::new());let original=same_chunk(&mut state,"/proc/p()\n    return\n",&host);let old=input(&original);
  let a=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&||Ok(()));
  // Reuse the existing canonical rejection fixture and SAME real private code
  // owner. The diagnostic is an actual parser result, not invented text.
  let diagnostic=dm_syntax::parse_expression("1+").diagnostics.into_iter().next().unwrap();let cleanup=a.reserve(8192).unwrap();let product=retain_canonical_rejection(Arc::clone(old.original_code_owner().unwrap()),old.span,diagnostic,cleanup,&a).unwrap();
  let calls=std::cell::Cell::new(0);let before=host.counter.load(Ordering::Acquire);let stop=||Err(std::io::Error::from_raw_os_error(1450));let stopped=dm_syntax::SettingAdmission::new(&host.counter,1<<26,&stop);
  let Err(BodySyntaxFailure::Operational(error))=product.with_utility_error_current(&old,&stopped,|_,_|{calls.set(calls.get()+1);Ok(())})else{panic!("actual first IO must win before projection")};assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(calls.get(),0);assert_eq!(host.counter.load(Ordering::Acquire),before);
  let changed=same_chunk(&mut state,"/proc/p()\n    return 1\n",&host);let current=input(&changed);
  assert!(product.with_utility_error_current(&current,&a,|_,_|{calls.set(calls.get()+1);Ok(())}).is_err());assert_eq!(calls.get(),0,"another code owner cannot reach the borrowed-point callback");
 }

}

/// Source-neutral native grammar result, never a current frontend/model.
/// Both success and author failure retain canonical code DATA only. A caller
/// must obtain an actual current-input binding before reporting source points.
#[derive(Debug)]
pub enum OriginalBodySyntaxProduct{Parsed(Arc<BodySyntax>),Rejected(OriginalBodySyntaxError)}
pub struct OriginalBodySyntaxError{code:Arc<BodyCodeIdentity>,body:dm_syntax::Span,diagnostic:dm_syntax::Diagnostic,
 // LAST: canonical diagnostic/product storage retires before its actual grant.
 _cleanup:dm_syntax::SettingRootLease,
}
impl OriginalBodySyntaxProduct{
 pub fn budget_charge(&self)->usize{match self{Self::Parsed(syntax)=>syntax.budget_charge(),Self::Rejected(error)=>std::mem::size_of::<Self>().saturating_add(error.diagnostic.message.capacity())}}
 pub fn parsed(&self)->Option<&Arc<BodySyntax>>{match self{Self::Parsed(syntax)=>Some(syntax),Self::Rejected(_)=>None}}
 pub fn bind_error(&self,input:&BodySyntaxInput)->Result<Option<Diagnostic>,BodySyntaxFailure>{input.settlement_checked()?;match self{Self::Parsed(_)=>Ok(None),Self::Rejected(error)=>error.bind_current(input).map(Some)}}
 /// Utility-only NoCode DATA after exactly the same private current binding as
 /// bind_error. This avoids cloning diagnostic text and grants no CHECK code.
 pub fn rejects_current_input_admitted(&self,input:&BodySyntaxInput,a:&dm_syntax::SettingAdmission<'_>)->Result<bool,BodySyntaxFailure>{
  let pending=(||{a.checkpoint().map_err(BodySyntaxFailure::Operational)?;input.settlement_checked()?;input.admit_native_allocation(a).map_err(BodySyntaxFailure::Operational)?;match self{Self::Parsed(_)=>Ok(false),Self::Rejected(error)=>{if !a.matches_lease_domain(&error._cleanup){return Err(binding_error("actual utility rejection belongs to another resource domain"))}error.bound_current_location(input)?;Ok(true)}}})();
  if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}pending
 }
}
impl OriginalBodySyntaxError{
 fn bound_current_location(&self,input:&BodySyntaxInput)->Result<SourceLocation,BodySyntaxFailure>{
  let settled=input.settlement_checked()?;
  let code=input.original_code.as_ref().ok_or_else(||binding_error("actual current body code is absent"))?;
  if !Arc::ptr_eq(code,&self.code){return Err(binding_error("native grammar refusal belongs to different code"))}
  settled.syntax.original_body_recipe_checked(input.span,code)?;
  let projection=dm_syntax::SyntaxProjection::new(self.body,input.span).map_err(BodySyntaxFailure::Operational)?;
  let span=projection.span(self.diagnostic.span).ok_or_else(||binding_error("native grammar refusal escapes actual body recipe"))?;
  settled.mapping.output(span.start).ok_or_else(||binding_error("actual current source point for native refusal absent"))
 }
 fn bind_current(&self,input:&BodySyntaxInput)->Result<Diagnostic,BodySyntaxFailure>{
  let location=self.bound_current_location(input)?;
  Ok(Diagnostic{kind:syntax_kind(self.diagnostic.kind),stage:DiagnosticStage::Syntax,message:self.diagnostic.message.clone(),location:Some(location)})
 }
}
impl BodySyntaxInput{
 /// Locator DATA is usable only with this actual private input/current recipe.
 /// Holding the tiny code Arc in graph Params prevents pointer reuse/ABA until
 /// that node is removed; it retains no source, parser AST, tree or model.
 pub fn original_code_owner(&self)->Option<&Arc<BodyCodeIdentity>>{self.original_code.as_ref()}
 pub fn parse_original_product_with_setting_admission(&self,a:&dm_syntax::SettingAdmission<'_>)->Result<OriginalBodySyntaxProduct,BodySyntaxFailure>{
  canonical_body_checkpoint(a)?;let settled=self.settlement_checked()?;self.admit_native_allocation(a).map_err(BodySyntaxFailure::Operational)?;
  let code=self.original_code.as_ref().ok_or_else(||binding_error("canonical primary code is unissued"))?;let recipe=settled.syntax.original_body_recipe_checked(self.span,code)?;let original_window=recipe.source_window().map_err(binding_error)?;
  // Declared BEFORE the returned Item/Diagnostic so every failure retires its
  // actual payload before its exact structural allocation credit.
  let mut primary_credit=None;
  let Some(mut primary)=recipe.parse_native_owned_admitted(a).map_err(BodySyntaxFailure::Operational)?else{return self.parse_original_product_with_coarse_cleanup(a)};
  let native_primary_consumed=primary.complete();let result=primary.take_result();primary_credit=Some(primary.into_credit());
  canonical_body_checkpoint(a)?;
  let mut issued=match result{Ok(issued)=>issued,Err(diagnostic)=>return retain_owned_primary_rejection(Arc::clone(code),self.span,diagnostic,primary_credit.take().expect("actual primary credit"),a)};
  if issued.item.span!=self.span{return Err(binding_error("canonical primary Item changed its logical BODY identity"))}
  issued.parameters.admit_optional_expressions(self.parameter_admission);if issued.parameters.retained_bytes()>self.parameter_admission{return Err(binding_error("primary parameter receipt exceeded original header allowance"))}
  let mut item=issued.item;
  let cleanup=body_archive::reserve_installed_canonical_cleanup_after_primary(&item,&settled.syntax,&settled.source,self.span,code,a)?;
  let statements=body_archive::parse_statements_with_body_literal_cleanup(&mut item,&settled.source,&settled.syntax,self.span,Some(code),a,cleanup)?;
  canonical_body_checkpoint(a)?;
  let parameters=issued.parameters.into_shared();let paid_canonical_payload=BodySyntax::canonical_payload_admitted(primary_credit.as_ref(),&parameters,&statements,a);
  Ok(OriginalBodySyntaxProduct::Parsed(Arc::new(BodySyntax{issuance:self.id,item,opening_parenthesis:issued.opening_parenthesis,parameters,paid_canonical_payload,statements,input_bytes:self.span.end-self.span.start,original_code:Arc::clone(code),original_window,original_body_span:self.span,native_primary_consumed,_primary_credit:primary_credit})))
 }
 fn parse_original_product_with_coarse_cleanup(&self,a:&dm_syntax::SettingAdmission<'_>)->Result<OriginalBodySyntaxProduct,BodySyntaxFailure>{
  canonical_body_checkpoint(a)?;let mut original_error=None;let settled=self.settlement_checked()?;self.admit_native_allocation(a).map_err(BodySyntaxFailure::Operational)?;
  let mut cleanup=Some(body_archive::reserve_installed_canonical_cleanup(&settled.syntax,&settled.source,self.span,self.original_code.as_ref().ok_or_else(||binding_error("canonical cleanup code is unissued"))?,a)?);
  let parsed=self.parse_using_observed(Some((a,BodySyntaxFailure::Operational)),|item|{
   let actual=cleanup.take().ok_or_else(||binding_error("actual canonical cleanup lease was already transferred"))?;
   body_archive::parse_statements_with_body_literal_cleanup(item,&settled.source,&settled.syntax,self.span,self.original_code.as_ref(),a,actual)
  },&mut|error|{original_error=Some(error.clone());});
  if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}
  if matches!(&parsed,Err(BodySyntaxFailure::Operational(_))){return parsed.map(|_|unreachable!())}
  canonical_body_checkpoint(a)?;
  match parsed{
   Ok(syntax)=>{if cleanup.is_some(){return Err(binding_error("actual successful BODY omitted its cleanup handoff"))}Ok(OriginalBodySyntaxProduct::Parsed(Arc::new(syntax)))},
   Err(BodySyntaxFailure::Syntax(error))=>match original_error{
    Some(diagnostic)=>{let code=self.original_code.as_ref().ok_or_else(||binding_error("native grammar refusal has no actual code owner"))?;let cleanup=cleanup.take().ok_or_else(||binding_error("actual rejection occurred after cleanup transfer"))?;retain_canonical_rejection(Arc::clone(code),self.span,diagnostic,cleanup.into_lease(self.span,code,a)?,a)},
    None=>Err(BodySyntaxFailure::Syntax(error)),
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
   let location=self.settled.mapping.output(span.start).ok_or_else(||binding_error("current recovering diagnostic source point absent"))?;
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
#[derive(Debug)]
struct UnissuedOriginalBodyGrammar;
impl std::fmt::Display for UnissuedOriginalBodyGrammar {
 fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
  formatter.write_str("genuine original per-body grammar outcome is not issued for this syntax")
 }
}
impl std::error::Error for UnissuedOriginalBodyGrammar {}

impl<'syntax> CurrentBodySyntax<'syntax>{
 /// Distinguishes a missing parser witness from other Unsupported errors.
 pub fn is_unissued_original_grammar(error: &std::io::Error) -> bool {
  error.get_ref().is_some_and(|cause| cause.is::<UnissuedOriginalBodyGrammar>())
 }
 /// Initial exact grammar coverage is deliberately closed and falsifiable:
 /// empty, void/simple return and actual simple arithmetic missing-RHS branch.
 /// Remaining grammar is unissued, not inferred available/None from errors.
 pub fn original_code_disposition<'loan>(&'loan self)->Result<OriginalBodyDisposition<'loan,'syntax>,BodySyntaxFailure>{
  let code=self.input.original_code.as_ref().ok_or_else(||binding_error("original code disposition lacks actual canonical code identity"))?;
  let recipe=self.settled.syntax.original_body_recipe_checked(self.input.span,code)?;
  if !recipe.setting_headers().is_some_and(|headers|headers.checker_body_profile()){return Err(unissued_original_body("original body grammar profile is not actually issued"))}
  let parsed:&'syntax dm_syntax::ParsedBody=self.original.statements.parsed();let outcome=parsed.original_grammar.as_ref().ok_or_else(|| {
   if std::env::var_os("DMB_ORIGINAL_TRACE_BODY_PRESSURE").is_some()
    || cfg!(debug_assertions)&&std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some() {
    // Actual settled source DATA only. Bound diagnostic output; never parse,
    // allocate another grammar owner, or replace the original refusal on IO.
    fn clipped(value:&str,characters:usize)->&str{let end=value.char_indices().nth(characters).map_or(value.len(),|(at,_)|at);&value[..end]}
    use std::io::Write as _;let mut output=std::io::stderr().lock();
    if let Some(source)=self.settled.mapping.output(self.input.span.start){
     let _=writeln!(output,"original.body_unissued file={:?} line={} body={:?} proc_header={:?} statements={} diagnostics={} pending={}",clipped(&source.semantic_path,512),source.line,self.input.span,clipped(&self.original.item.header,256),parsed.statements.len(),parsed.diagnostics.len(),parsed.pending_bodies.len());
    }else{let _=writeln!(output,"original.body_unissued source=unmapped body={:?} proc_header={:?} statements={} diagnostics={} pending={}",self.input.span,clipped(&self.original.item.header,256),parsed.statements.len(),parsed.diagnostics.len(),parsed.pending_bodies.len());}
    for (index,row) in parsed.diagnostics.iter().take(3).enumerate(){let _=writeln!(output,"original.body_unissued diagnostic={} kind={:?} span={:?} message={:?}",index,row.kind,row.span,clipped(&row.message,256));}
    for (index,row) in parsed.statements.iter().take(3).enumerate(){let _=writeln!(output,"original.body_unissued statement={} kind={:?} span={:?} header={:?}",index,std::mem::discriminant(&row.kind),row.header_span,clipped(&row.raw_header,256));}
   }
   BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::Unsupported, UnissuedOriginalBodyGrammar))
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

/// Native-only coverage from the actual private BODY producer. It is not
/// Original availability, lowering coverage, or independent Checker parity.
pub enum NativeBodyDisposition<'loan,'syntax> {
 Complete(NativeBodyCodeGrant<'loan,'syntax>),
 Recovered,
 NotCovered,
 Deferred,
}
pub struct NativeBodyCodeGrant<'loan,'syntax> {
 body:&'loan CurrentBodySyntax<'syntax>,
 statement:Option<dm_syntax::Span>,
 scope_roots:usize,
}
impl NativeBodyCodeGrant<'_,'_> {
 pub fn belongs_to(&self,body:&CurrentBodySyntax<'_>)->bool{std::ptr::eq(self.body,body)}
 pub fn statement_span(&self)->Option<dm_syntax::Span>{self.statement}
 pub fn scope_roots(&self)->usize{self.scope_roots}
}
impl<'syntax> CurrentBodySyntax<'syntax> {
 /// Actual native production consumption, settled children and containing-input
 /// termination; Original compatibility and semantic/lowering proof stay separate.
 /// Source-neutral/parser-exported DATA cannot manufacture this borrowed grant.
 pub fn native_code_disposition_using<'loan>(&'loan self,a:&dm_syntax::SettingAdmission<'_>)
  ->Result<NativeBodyDisposition<'loan,'syntax>,BodySyntaxFailure>{
  let pending=(||{
   // Reuse SAME private input/product/projection/resource checks on each loan.
   let _current=self.input.bind_original_product_checked(self.original,a)?;
   let parsed=self.original.statements.parsed();
   let header=match self.original.statements.native_parser_facts{
    Some(dm_syntax::NativeBodyParserFacts::BareReturn{header})=>Some(header),
    Some(dm_syntax::NativeBodyParserFacts::Intrinsic{scope_roots,..})=>{
      if scope_roots!=self.original.item.children.len(){return Err(binding_error("native consumed root roster differs from private primary product"))}
      None
    },
    Some(dm_syntax::NativeBodyParserFacts::Recovered)=>return Ok(NativeBodyDisposition::Recovered),
    Some(dm_syntax::NativeBodyParserFacts::Deferred)=>return Ok(NativeBodyDisposition::Deferred),
    _=>return Ok(NativeBodyDisposition::NotCovered),
   };
   if header.is_none()||self.original.native_primary_consumed{
    if !self.original.native_primary_consumed{return Ok(NativeBodyDisposition::Deferred)}
    if !self.original.statements.original_literal_syntax_complete()
      ||self.deferred_literal_roots!=0{return Ok(NativeBodyDisposition::Deferred)}
    let parameters=self.parameters()?;
    for declaration in parameters.absolute_declarations().map_err(binding_view_error)?{
      a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
      declaration.span().map_err(binding_view_error)?;
    }
    for parameter in parameters.entries().map_err(binding_view_error)?{
      a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
      if !matches!(parameter.original().native_child_observation(),Some((true,false,false))){return Ok(NativeBodyDisposition::Deferred)}
      match parameter.original().expressions(){
        Ok(Some(roots))=>for root in roots.default_root().into_iter().chain(roots.source_root()).chain(roots.dimensions().iter().filter_map(Option::as_ref)){
          a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
          if !root.is_retained_in(a){return Ok(NativeBodyDisposition::Deferred)}
        },
        Ok(None)=>(),
        Err(_)=>return Ok(NativeBodyDisposition::Deferred),
      }
    }
    // Local dimension roots still originate in the compatibility declaration
    // ledger. Until that actual producer retains native facts they are deferred,
    // never certified from an equal AST or a matching dimension count.
    for local in self.locals().entries().map_err(binding_view_error)?{
      a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
      if local.array().is_some_and(|array|array.dimensions().next().is_some()){
        return Ok(NativeBodyDisposition::Deferred)
      }
    }
    // Reuse the existing admitted projection/child kernel, adding only reads
    // of actual immutable child completion facts. No second parser/AST owner.
    if self.validate_issued_coordinates_with_native_children(a,true)?!=0{
      return Ok(NativeBodyDisposition::Deferred)
    }
    a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
    let only=if let [only]=parsed.statements.as_slice(){Some(self.projection.span(only.header_span).ok_or_else(||binding_error("native sole statement escapes current source"))?)}else{None};
    return Ok(NativeBodyDisposition::Complete(NativeBodyCodeGrant{body:self,statement:only,scope_roots:parsed.statements.len()}))
   }
   let header=header.unwrap();
   // Result-bearing real header metadata: failed optional parsing cannot turn
   // into the empty parameter roster accepted by this initial slice.
   let parameters=self.parameters()?;
   if parameters.entries().map_err(binding_view_error)?.next().is_some()
    ||parameters.absolute_declarations().map_err(binding_view_error)?.next().is_some(){
    return Ok(NativeBodyDisposition::Deferred)
   }
   if self.deferred_literal_roots!=0 || !parsed.pending_bodies.is_empty()
    || !parsed.control_origins.is_empty()
    || self.locals().entries().map_err(binding_view_error)?.next().is_some(){
    return Ok(NativeBodyDisposition::Deferred)
   }
   let [only]=parsed.statements.as_slice() else{return Err(binding_error("native production roster differs from private parser facts"))};
   let [child]=self.original.item.children.as_slice() else{return Err(binding_error("native production child consumption differs"))};
   if only.header_span!=header || child.header_span!=header || !child.children.is_empty()
    || !matches!(&only.kind,dm_syntax::StatementKind::Return(None))
    || !parsed.diagnostics.is_empty(){
    return Err(binding_error("native bare-return production differs from retained canonical data"))
   }
   let code=self.input.original_code.as_ref().ok_or_else(||binding_error("native grant has no actual code owner"))?;
   let recipe=self.settled.syntax.original_body_recipe_checked(self.input.span,code)?;
   let _window=recipe.source_window().map_err(binding_error)?;
   let header=self.projection.span(header).ok_or_else(||binding_error("native production escapes actual current body"))?;
   let tokens=self.settled.syntax.original_body_tokens(self.input.span,code).map_err(|message|binding_error(&message))?;
   let actual=tokens.tokens(header).map_err(binding_error)?;
   let mut saw_keyword=false;
   for(kind,span,text)in actual{
    a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
    match(kind,text){
     (dm_syntax::TokenKind::Whitespace|dm_syntax::TokenKind::Newline|dm_syntax::TokenKind::Comment,_)=>(),
     (dm_syntax::TokenKind::Ident,"return")if !saw_keyword&&span.start==header.start=>saw_keyword=true,
     _=>return Err(binding_error("native bare-return header differs from actual token loan")),
    }
   }
   if !saw_keyword{return Err(binding_error("native return token was not consumed"))}
   // Actual primary layout may emit a semicolon or enclosing close here.
   // Reuse its same owned delimiter producer, not raw-text lookahead or a
   // procedure-length EOF. Later declarations remain real forward tokens.
   if tokens.native_statement_terminator_using(header,a).map_err(BodySyntaxFailure::Operational)?.is_none(){
    return Ok(NativeBodyDisposition::Deferred)
   }
   a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
   Ok(NativeBodyDisposition::Complete(NativeBodyCodeGrant{body:self,statement:Some(header),scope_roots:1}))
  })();
  if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}
  pending
 }
}

// Only the actual procedure-commit collector can invoke this early producer.
// General current-input entry points still require final settlement.
impl BodySyntaxInput{
 pub(super) fn parse_at_committed_primary(
  &self,mut input:dm_syntax::OriginalCommittedBodyInput<'_,'_>,code:&super::relative_declarations::CommittedBodyCodeIssue<'_>,
  parameters:dm_syntax::SharedParameterSignature,settings:Option<&super::committed_bodies::CommittedSettingRoots>,a:&dm_syntax::SettingAdmission<'_>,
 )->Result<(OriginalBodySyntaxProduct,dm_syntax::NativeBodySyntaxTraversal,dm_syntax::OriginalPrimaryProducerIdentity),BodySyntaxFailure>{
  let checkpoint=|a:&dm_syntax::SettingAdmission<'_>|{let proxy=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}proxy.map_err(BodySyntaxFailure::Operational)};
  checkpoint(a)?;
  if self.settled.get().is_some()||!input.literal_facts().admitted_by(a)
   ||!code.producer.same_producer(input.primary_producer())||code.header!=input.item().header_span||code.body!=input.item().span
   ||self.span!=code.body||!self.original_code.as_ref().is_some_and(|owner|Arc::ptr_eq(owner,&code.identity))
   ||matches!(input.body_collection(),dm_syntax::OriginalCommittedBodyCollection::NotCallable|dm_syntax::OriginalCommittedBodyCollection::FailedPrefix){
   return Err(binding_error("early BODY producer lacks its actual primary/input/code/collection loan"))
  }
  let producer=input.take_primary_producer().ok_or_else(||binding_error("actual committed BODY producer was already taken"))?;
  let entries=parameters.entries().map_err(|reason|BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::Unsupported,reason)))?;
  if entries.iter().any(|entry|entry.native_child_observation()!=Some((true,false,false))){return Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::Unsupported,"actual committed formal child syntax is unissued")))}
  let source=input.source();let span=input.item().span;let window=dm_syntax::Span::new(0,source.len());
  let mut primary_credit=None;
  let syntax_span=dm_syntax::original_callable_syntax_extent_using(source,span,input.item().header_span,input.token_window(),Some(input.literal_facts()),a).map_err(BodySyntaxFailure::Operational)?.map_err(|reason|BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::Unsupported,reason)))?;
  let _syntax_tail=if syntax_span.end>span.end{Some(a.reserve(syntax_span.end.checked_sub(span.end).and_then(|n|n.checked_mul(512)).ok_or_else(||BodySyntaxFailure::Operational(std::io::ErrorKind::OutOfMemory.into()))?).map_err(|proxy|BodySyntaxFailure::Operational(a.take_operational_error().unwrap_or(proxy)))?)}else{None};
  let mut primary=dm_syntax::parse_proc_with_committed_native_consumption_from_window_admitted(source,syntax_span,input.token_window(),0,parameters,input.literal_facts(),a).map_err(BodySyntaxFailure::Operational)?;
  let native_primary_consumed=primary.complete();let parsed=primary.take_result();primary_credit=Some(primary.into_credit());
  checkpoint(a)?;
  if !native_primary_consumed{return Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::Unsupported,"actual committed procedure primary consumption is incomplete")))}
  drop(_syntax_tail);
  let mut issued=match parsed{Ok(issued)=>issued,Err(diagnostic)=>{if diagnostic.kind==dm_syntax::DiagnosticKind::Unsupported{return Err(retain_owned_primary_unsupported(diagnostic,primary_credit.take().expect("actual refused primary credit"),a))}return Ok((retain_owned_primary_rejection(Arc::clone(&code.identity),span,diagnostic,primary_credit.take().expect("actual committed primary credit"),a)?,dm_syntax::NativeBodySyntaxTraversal::Rejected,producer))}};
  if issued.item.span!=span{return Err(binding_error("actual syntax extent changed its logical BODY identity"))}
  issued.parameters.admit_optional_expressions(self.parameter_admission);
  if issued.parameters.retained_bytes()>self.parameter_admission{return Err(binding_error("early BODY parameter receipt exceeds its actual header allowance"))}
  let mut item=issued.item;
  let cleanup=body_archive::reserve_committed_canonical_cleanup_after_primary(&item,&input,&code.identity,a)?;
  let mut traversal=None;
  let statements=body_archive::parse_statements_at_committed_input(&mut item,input,&code.identity,a,cleanup,settings,&mut|actual|traversal=Some(actual));
  if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}
  let statements=statements?;checkpoint(a)?;
  let traversal=traversal.ok_or_else(||binding_error("actual committed statement producer omitted its transient syntax report"))?;
  if traversal==dm_syntax::NativeBodySyntaxTraversal::Unissued{return Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::Unsupported,"actual committed BODY syntax traversal is unissued")))}
  let parameters=issued.parameters.into_shared();let paid_canonical_payload=BodySyntax::canonical_payload_admitted(primary_credit.as_ref(),&parameters,&statements,a);
  Ok((OriginalBodySyntaxProduct::Parsed(Arc::new(BodySyntax{issuance:self.id,item,opening_parenthesis:issued.opening_parenthesis,parameters,paid_canonical_payload,statements,input_bytes:span.end-span.start,original_code:Arc::clone(&code.identity),original_window:window,original_body_span:span,native_primary_consumed,_primary_credit:primary_credit})),traversal,producer))
 }
 /// Product/input identity check only. This cannot settle source/currentness.
 pub fn require_product_issuance(&self,product:&OriginalBodySyntaxProduct)->Result<(),BodySyntaxFailure>{
  let code=self.original_code.as_ref().ok_or_else(||binding_error("actual BODY input code owner absent"))?;
  match product{
   OriginalBodySyntaxProduct::Parsed(syntax) if syntax.issuance==self.id&&Arc::ptr_eq(&syntax.original_code,code)&&syntax.original_body_span==self.span=>Ok(()),
   OriginalBodySyntaxProduct::Rejected(error) if Arc::ptr_eq(&error.code,code)&&error.body==self.span=>Ok(()),
   _=>Err(binding_error("BODY product does not belong to this actual input/code issuance")),
  }
 }
}

impl OriginalBodySyntaxError{pub(super) fn original_diagnostic(&self)->&dm_syntax::Diagnostic{&self.diagnostic}}

impl BodySyntaxInput{pub fn committed_allocation_credit(&self)->Option<&dm_syntax::SettingRootLease>{self.allocation_owner.credit.get()}
 pub fn weak_allocation_owner(&self)->Arc<BodySyntaxInputWeak>{Arc::clone(&self.allocation_owner)}
}
impl std::fmt::Debug for BodySyntaxInput{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("BodySyntaxInput").field("id",&self.id).field("settled",&self.settled).field("span",&self.span).field("parameter_admission",&self.parameter_admission).field("original_code",&self.original_code).finish()}}

fn canonical_body_checkpoint(a:&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>{let pending=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}pending.map_err(BodySyntaxFailure::Operational)}
struct FundedPrimarySyntaxRefusal{message:String,_credit:dm_syntax::SettingRootLease}
impl std::fmt::Debug for FundedPrimarySyntaxRefusal{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("FundedPrimarySyntaxRefusal").field("message",&self.message).finish_non_exhaustive()}}
impl std::fmt::Display for FundedPrimarySyntaxRefusal{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str(&self.message)}}
impl std::error::Error for FundedPrimarySyntaxRefusal{}
fn retain_owned_primary_unsupported(diagnostic:dm_syntax::Diagnostic,credit:dm_syntax::SettingRootLease,a:&dm_syntax::SettingAdmission<'_>)->BodySyntaxFailure{
 let mut pending=PendingCanonicalRejection{diagnostic,credit};
 let prepare=(||->Result<(),BodySyntaxFailure>{
  canonical_body_checkpoint(a)?;if !a.matches_lease_domain(&pending.credit){return Err(binding_error("primary refusal belongs to another allocation domain"))}
  // Fund the named payload Box plus the existing conservative 64-byte
  // allocation/control convention; std io::Error internals are not an ABI.
  const IO_ERROR_CONTROL_ENVELOPE:usize=std::mem::size_of::<std::io::Error>()+2*std::mem::size_of::<usize>()+64;
  let metadata=std::mem::size_of::<FundedPrimarySyntaxRefusal>().checked_add(IO_ERROR_CONTROL_ENVELOPE).ok_or_else(||BodySyntaxFailure::Operational(std::io::ErrorKind::OutOfMemory.into()))?;
  let bytes=pending.diagnostic.message.capacity().checked_add(metadata).ok_or_else(||BodySyntaxFailure::Operational(std::io::ErrorKind::OutOfMemory.into()))?;
  if bytes>pending.credit.bytes(){let extra=bytes-pending.credit.bytes();a.grow(&mut pending.credit,extra).map_err(|proxy|BodySyntaxFailure::Operational(a.take_operational_error().unwrap_or(proxy)))?;}
  let unused=pending.credit.bytes()-bytes;a.shrink(&mut pending.credit,unused).map_err(|proxy|BodySyntaxFailure::Operational(a.take_operational_error().unwrap_or(proxy)))?;Ok(())
 })();
 if let Err(actual)=prepare{return actual}
 let PendingCanonicalRejection{diagnostic,credit}=pending;
 BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::Unsupported,FundedPrimarySyntaxRefusal{message:diagnostic.message,_credit:credit}))
}
struct PendingCanonicalRejection{diagnostic:dm_syntax::Diagnostic,credit:dm_syntax::SettingRootLease}
fn retain_canonical_rejection(code:Arc<BodyCodeIdentity>,body:dm_syntax::Span,diagnostic:dm_syntax::Diagnostic,cleanup:dm_syntax::SettingRootLease,a:&dm_syntax::SettingAdmission<'_>)->Result<OriginalBodySyntaxProduct,BodySyntaxFailure>{retain_canonical_rejection_using(code,body,diagnostic,cleanup,a,false)}
fn retain_owned_primary_rejection(code:Arc<BodyCodeIdentity>,body:dm_syntax::Span,diagnostic:dm_syntax::Diagnostic,credit:dm_syntax::SettingRootLease,a:&dm_syntax::SettingAdmission<'_>)->Result<OriginalBodySyntaxProduct,BodySyntaxFailure>{retain_canonical_rejection_using(code,body,diagnostic,credit,a,true)}
fn retain_canonical_rejection_using(code:Arc<BodyCodeIdentity>,body:dm_syntax::Span,diagnostic:dm_syntax::Diagnostic,credit:dm_syntax::SettingRootLease,a:&dm_syntax::SettingAdmission<'_>,primary:bool)->Result<OriginalBodySyntaxProduct,BodySyntaxFailure>{
 // Infallible handoff BEFORE any checkpoint, resize or fallible metadata work.
 // Struct fields, unlike function parameters, release the payload FIRST.
 let mut pending=PendingCanonicalRejection{diagnostic,credit};
 canonical_body_checkpoint(a)?;if !a.matches_lease_domain(&pending.credit){return Err(binding_error("actual canonical rejection cleanup belongs to another budget"))}
 let(layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<OriginalBodySyntaxProduct>()).map_err(|_|BodySyntaxFailure::Operational(std::io::ErrorKind::OutOfMemory.into()))?;
 let bytes=layout.pad_to_align().size().checked_add(pending.diagnostic.message.capacity()).ok_or_else(||BodySyntaxFailure::Operational(std::io::ErrorKind::OutOfMemory.into()))?;
 if bytes>pending.credit.bytes(){if !primary{return Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"actual rejected product exceeds its existing cleanup reservation")))}let extra=bytes-pending.credit.bytes();a.grow(&mut pending.credit,extra).map_err(|proxy|BodySyntaxFailure::Operational(a.take_operational_error().unwrap_or(proxy)))?;}
 let unused=pending.credit.bytes()-bytes;a.shrink(&mut pending.credit,unused).map_err(|proxy|BodySyntaxFailure::Operational(a.take_operational_error().unwrap_or(proxy)))?;
 let PendingCanonicalRejection{diagnostic,credit}=pending;
 Ok(OriginalBodySyntaxProduct::Rejected(OriginalBodySyntaxError{code,body,diagnostic,_cleanup:credit}))
}

impl std::fmt::Debug for OriginalBodySyntaxError{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("OriginalBodySyntaxError").field("code",&self.code).field("body",&self.body).field("diagnostic",&self.diagnostic).finish()}}

impl BodySyntaxInput{
 /// Resource-only ingress for an existing compatibility DATA allocation.
 /// Early committed Inputs already carry this grant before allocation. Normal
 /// Inputs must acquire it before actual native registry/query/current use.
 /// No source, final settlement, code completeness or identity is issued here.
 #[doc(hidden)]pub fn admit_native_allocation(&self,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<Arc<BodySyntaxInputWeak>>{
  if let Some(actual)=a.take_operational_error(){return Err(actual)}
  if let Some(code)=&self.original_code{code.admit_native_allocation(a)?;}
  let(lease_layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<BodySyntaxInputWeak>()).expect("actual Input lease Arc layout");
  let required=unsettled_body_input_allocation_bytes().checked_add(lease_layout.pad_to_align().size()).ok_or(std::io::ErrorKind::OutOfMemory)?;
  let validate=|credit:&dm_syntax::SettingRootLease|->std::io::Result<Arc<BodySyntaxInputWeak>>{if !a.matches_lease_domain(credit)||credit.bytes()<required{return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"actual Input allocation uses another or incomplete resource grant"))}Ok(Arc::clone(&self.allocation_owner))};
  if let Some(credit)=self.allocation_owner.credit.get(){return validate(credit)}
  let pending=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(actual)}pending?;
  if self.original_code.as_ref().and_then(|code|code.committed_allocation_credit()).is_some_and(|credit|!a.matches_lease_domain(credit)){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"actual code/Input allocation domains differ"))}
  let reserved=a.reserve(required);if let Some(actual)=a.take_operational_error(){return Err(actual)}let credit=reserved?;if let Err(unused)=self.allocation_owner.credit.set(credit){drop(unused)}
  validate(self.allocation_owner.credit.get().expect("actual allocation initialization completed"))
 }
}

impl OriginalBodySyntaxProduct{
 pub fn with_utility_error_current<T>(&self,input:&BodySyntaxInput,a:&dm_syntax::SettingAdmission<'_>,consume:impl FnOnce(&str,BorrowedBodyUtilityPoint<'_>)->std::io::Result<T>)->Result<Option<T>,BodySyntaxFailure>{let pending=(||{if !self.rejects_current_input_admitted(input,a)?{return Ok(None)}let Self::Rejected(error)=self else{return Err(binding_error("utility rejection product changed"))};let settled=input.settlement_checked()?;let projection=dm_syntax::SyntaxProjection::new(error.body,input.span).map_err(BodySyntaxFailure::Operational)?;let span=projection.span(error.diagnostic.span).ok_or_else(||binding_error("utility rejection diagnostic escaped actual current recipe"))?;let point=settled.mapping.borrowed_utility_point(span.start).map_err(binding_error)?;consume(&error.diagnostic.message,point).map(Some).map_err(BodySyntaxFailure::Operational)})();match a.take_operational_error(){Some(first)=>Err(BodySyntaxFailure::Operational(first)),None=>pending}}
}

pub(super) fn current_input_admitted(inputs:&BodyQueryInputs,bodies:&[BodyOccurrence],ordinal:usize,syntax:&Arc<DeclarationSyntax>,source:&dm_preprocess::SourceText,mapping:&Arc<SourceExportMapping>,a:&dm_syntax::SettingAdmission<'_>)->Result<Arc<BodySyntaxInput>,BodySyntaxFailure>{
 let body=bodies.get(ordinal).ok_or_else(||binding_error("current body ordinal absent"))?;
 let recipe=syntax.original_header_recipe(body.expanded_span).map_err(|e|binding_error(&e.message))?;
 // Validate fixed metadata and Code lease domains even on a warm Input hit.
 let code=recipe.code_identity_admitted(a)?;
 inputs.get_or_create(bodies.len(),ordinal,a,||{
  let parameter_admission=syntax.item_path(&body.ast_path).map(|item|item.header_span().end.saturating_sub(item.header_span().start).saturating_mul(128).saturating_add(1024)).unwrap_or(usize::MAX);
  let input=issue_unsettled_body_admitted(body.expanded_span,Arc::clone(&code),parameter_admission,a)?;
  input.settle_current_source(body,&code,syntax,source,mapping)?;Ok(input)
 })
}
impl ColdFrontend{
 /// Cache-admission observation only. No allocation, parser, query or rebind.
 pub fn peek_syntax_input(&self,ordinal:usize)->Option<Arc<BodySyntaxInput>>{self.body_queries.as_ref()?.inputs.issued(ordinal)}
 /// Resolve one genuine current Input under this SAME host's existing counter.
 pub fn syntax_input_checked(&self,ordinal:usize,poll:&dyn Fn()->std::io::Result<()>)->Result<Arc<BodySyntaxInput>,BodySyntaxFailure>{
  self.require_current_body_code_owners().map_err(BodySyntaxFailure::Syntax)?;
  let queries=self.body_queries.as_ref().ok_or_else(||binding_error("actual native body query host is absent"))?;
  if ordinal>=self.issued_bodies.len(){return Err(binding_error("actual body ordinal absent"))}poll().map_err(BodySyntaxFailure::Operational)?;
  if queries.inputs.owner.credit.is_none(){return queries.inputs.issued(ordinal).ok_or_else(||binding_error("eager body input ordinal absent"))}
  let settings=self.setting_expression_queries.as_ref().and_then(std::sync::Weak::upgrade).ok_or_else(||BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"current body demand has no actual live admission host")))?;
  if !std::ptr::addr_eq(settings.as_ref()as *const dyn SettingExpressionQueries,queries.host.as_ref()as *const dyn BodySyntaxQueries){return Err(binding_error("body query and admission hosts differ"))}
  let mut pending=None;
  settings.with_original_header_admission(&mut|a|{pending=Some(current_input_admitted(&queries.inputs,&self.issued_bodies,ordinal,&self.issued_syntax,&self.issued_arena,&self.source_export_mapping,a)?);Ok(())})?;
  pending.ok_or_else(||binding_error("body Input admission callback omitted"))
 }
 /// Explicit native-only attachment. Existing public eager attachment never
 /// fabricates a sparse roster or upgrades a source preparation purpose.
 pub fn with_ordinary_body_demand_queries_checked(mut self,host:Arc<dyn BodySyntaxQueries>,settings:Arc<dyn SettingExpressionQueries>)->Result<Self,BodySyntaxFailure>{
  self.require_current_body_code_owners().map_err(BodySyntaxFailure::Syntax)?;
  if !self.original_primary.as_ref().is_some_and(|primary|primary.ordinary_code_demand())||(!self.issued_bodies.is_empty()&&!self.issued_syntax.ordinary_code_demand())||!host.supports_ordinary_input_demand(){return Err(binding_error("ordinary body demand lacks its actual issued native mode/host"))}
  if !std::ptr::addr_eq(settings.as_ref()as *const dyn SettingExpressionQueries,host.as_ref()as *const dyn BodySyntaxQueries){return Err(binding_error("ordinary body demand hosts differ"))}
  self.setting_expression_queries=Some(Arc::downgrade(&settings));
  if self.reused_body_queries&&self.body_queries.as_ref().is_some_and(|queries|Arc::ptr_eq(&queries.host,&host)&&queries.inputs.is_demand()){self.reused_body_queries=false;return Ok(self)}
  settings.with_original_header_admission(&mut|a|{
   let inputs=BodyQueryInputs::demand(a)?;
   // One scan over actual already-issued current Codes. Pure membership is
   // observed before any mint; no full input directory or fake IDs are built.
   for(ordinal,owner)in self.issued_body_codes.iter().enumerate(){
    a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
    if let Some(code)=&owner.identity{if host.has_registered_body_code(code){let input=current_input_admitted(&inputs,&self.issued_bodies,ordinal,&self.issued_syntax,&self.issued_arena,&self.source_export_mapping,a)?;host.rebind_registered_body_input(&input)?;}}
   }
   // Every live matching Code has its actual current weak locator BEFORE the
   // existing quiescent prune. No query occurs while a sparse slot is locked.
   host.begin_revision();self.body_queries=Some(BodyQueries{host:Arc::clone(&host),inputs});Ok(())
  })?;
  self.reused_body_queries=false;Ok(self)
 }
}
