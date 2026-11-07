//! Exact original declaration RHS source; additive and NOT selected by native
//! classification until typed initializer operational transport is complete.
use super::*;
use dm_ir::{InitializerValue, SymbolicExpression};
#[path="frontend_initializer_scalar_source.rs"]
mod scalar_source;
#[path="frontend_initializer_provenance.rs"]
mod provenance;
pub use provenance::OriginalInitializerRootProvenance;

/// Original source is BORROWED from its authenticated current owner. Only the
/// canonical AST root is retained, under its existing SAME-counter lease. No
/// raw source Arc, copied text or allocator role escapes through this handle.
pub struct OriginalInitializerExpression<'source> {
    root: OriginalInitializerRoot,
    source: &'source dm_preprocess::SourceText,
    authored: &'source SymbolicExpression,
    recipe: OriginalInitializerRecipe,
    current_body:Option<dm_syntax::Span>,
}
#[derive(Clone)]
enum OriginalInitializerRoot{
 Header(dm_syntax::SettingExpression),
 Static(super::static_receipt::OriginalStaticInitializerRoot),
}
impl OriginalInitializerRoot{
 fn ast(&self)->&dm_syntax::Expr{match self{Self::Header(root)=>root.original_expression(),Self::Static(root)=>root.ast()}}
 fn same_root(&self,other:&Self)->bool{match(self,other){(Self::Header(a),Self::Header(b))=>a.same_root(b),(Self::Static(a),Self::Static(b))=>a.same_root(b),_=>false}}
 fn visit_storage(&self,mut visit:impl FnMut(usize,usize)){match self{Self::Header(root)=>{root.visit_root_storage(&mut visit);root.visit_retention_storage(visit)},Self::Static(root)=>root.visit_storage(visit)}}
}
impl std::fmt::Debug for OriginalInitializerExpression<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("OriginalInitializerExpression")
            .field("current_span", &self.current_span())
            .finish_non_exhaustive()
    }
}
impl OriginalInitializerExpression<'_> {
    /// Borrow original immutable syntax for shape only. Its coordinates may
    /// precede a warm current prefix; use source_text/project_span explicitly.
    pub fn ast(&self)->&dm_syntax::Expr{self.root.ast()}
    /// Storage-only original owner/slot observation. No AST/source alias escapes.
    pub fn provenance(&self)->OriginalInitializerRootProvenance{provenance::issue(self)}
    /// Borrow-only preflight: caller admits the fixed Weak backing BEFORE
    /// creating/storing provenance. This does not clone a Weak/root/source.
    pub fn provenance_weak_backing_charge(&self)->usize{match &self.root{OriginalInitializerRoot::Header(_)=>std::mem::size_of::<crate::procedure::OriginalProcedureHeaders>(),OriginalInitializerRoot::Static(_)=>std::mem::size_of::<StatementBody>()}}
    /// A flat original-coordinate source exists only for header roots.
    pub fn flat_source(&self)->Option<&str>{matches!(&self.root,OriginalInitializerRoot::Header(_)).then_some(self.source)}
    pub fn project_span(&self,span:dm_syntax::Span)->Option<dm_syntax::Span>{
      match &self.root{
       OriginalInitializerRoot::Header(root)=>{if span.start>span.end||span.end>self.source.len(){return None}Some(dm_syntax::Span::new(span.start.checked_add(root.current_offset())?,span.end.checked_add(root.current_offset())?))},
       OriginalInitializerRoot::Static(root)=>{let old=root.original_body();let current=self.current_body?;if span.start<old.start||span.start>span.end||span.end>old.end{return None}Some(dm_syntax::Span::new(span.start.checked_sub(old.start)?.checked_add(current.start)?,span.end.checked_sub(old.start)?.checked_add(current.start)?))}
      }
    }
    pub fn source_text(&self,span:dm_syntax::Span)->Option<&str>{match &self.root{OriginalInitializerRoot::Header(_)=>self.source.get(span.range()),OriginalInitializerRoot::Static(_)=>self.source.get(self.project_span(span)?.range())}}
    pub fn authored(&self) -> &SymbolicExpression {
        &self.authored
    }
    pub fn current_span(&self) -> dm_syntax::Span {
        self.project_span(self.ast().span).expect("sealed original root span has current projection")
    }
    pub fn same_root(&self, other: &Self) -> bool {
        self.root.same_root(&other.root)
    }
    /// Consuming cache decomposition retains syntax ONLY. Source/authored
    /// references are released; current semantic/codegen use requires reborrow.
    pub fn into_recipe(self) -> InitializerExpressionRecipe {
        InitializerExpressionRecipe {
            root: self.root,
            recipe: self.recipe,
        }
    }
}
/// Private source recipe. A Weak token slice would keep its whole inline
/// allocation alive; this Weak points only at the original fixed owner payload.
/// No source, token buffer, metadata Arc or semantic result is retained here.
#[derive(Clone)]
enum OriginalInitializerRecipe {
 Header{owner:std::sync::Weak<crate::procedure::OriginalProcedureHeaders>,value:dm_syntax::Span,ordinal:usize,count:usize,dimension:bool},
 Static,
}
impl OriginalInitializerRecipe{
 fn matches_header(&self,i:&relative_declarations::OriginalInitializerTokenInput<'_>)->bool{match self{Self::Header{owner,value,ordinal,count,dimension}=>*dimension==i.dimension&&std::sync::Weak::ptr_eq(owner,&Arc::downgrade(i.owner))&&*value==i.value&&*ordinal==i.ordinal&&*count==i.count,Self::Static=>false}}
}
/// Owned AST-only syntax for runtime artifacts. This is NOT a source or scalar
/// evaluation receipt. Exact current input and host admission are required again
/// before any source, location, evaluation or codegen access.
#[derive(Clone)]
pub struct InitializerExpressionRecipe {
    root: OriginalInitializerRoot,
    recipe: OriginalInitializerRecipe,
}
impl std::fmt::Debug for InitializerExpressionRecipe {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("InitializerExpressionRecipe")
            .finish_non_exhaustive()
    }
}
impl InitializerExpressionRecipe {
    /// Shape only, in original chunk coordinates; no source is retained.
    pub fn ast(&self) -> &dm_syntax::Expr {
        self.root.ast()
    }
    pub fn same_root(&self, other: &Self) -> bool {
        self.root.same_root(&other.root)
    }
    /// SAME retained parent must be visited with the existing typed-body census
    /// when this AST-only recipe outlives startup's strong receipt.
    pub fn retained_statement_body(&self)->Option<&Arc<StatementBody>>{match &self.root{OriginalInitializerRoot::Static(root)=>Some(root.parent()),_=>None}}
    /// Existing root lease covers its original AST allocations. Artifact callers
    /// must separately admit inline recipe/Weak coordination and standard Arc
    /// control-block overhead; this is not total heap/RSS accounting.
    pub fn retained_root_charge(&self) -> Option<usize> {
        match &self.root{OriginalInitializerRoot::Header(root)=>root.retained_charge(),OriginalInitializerRoot::Static(_)=>None}
    }
    /// Exposed fixed owner payload retained by Weak, root payload and lease
    /// counter addresses. Existing syntax visitors still account AST children;
    /// live owner contents are visited by their original owning frame only.
    pub fn visit_storage(&self, mut visit: impl FnMut(usize, usize)) {
        if let OriginalInitializerRecipe::Header{owner,..}=&self.recipe{visit(owner.as_ptr() as usize,std::mem::size_of::<crate::procedure::OriginalProcedureHeaders>());}
        self.root.visit_storage(visit);
    }
    /// None is a genuine original-owner/slot decline and performs no root parse.
    /// Actual operational refusal is Err and must never become cache miss.
    /// Exact input authenticates the current plan/origin and source first;
    /// obtaining the same warm slot then checks current host/counter/control.
    pub fn reborrow_declaration<'source>(&self,input:&OriginalDeclarationExpressionInput<'source>)->Result<Option<OriginalInitializerExpression<'source>>,BodySyntaxFailure>{
        match &input.input{
          OriginalInitializerSource::Header(i)=>if !self.recipe.matches_header(i){return Ok(None)},
          OriginalInitializerSource::Static{root,..}=>if !matches!(self.recipe,OriginalInitializerRecipe::Static)||!matches!(&self.root,OriginalInitializerRoot::Static(old) if old.same_root(root)){return Ok(None)},
        }
        let current=input.expression()?;
        if !self.root.same_root(&current.root){return Ok(None)}
        Ok(Some(current))
    }
    pub fn reborrow_dimension<'source>(&self,input:&OriginalInitializerDimensionInput<'source>)->Result<Option<OriginalInitializerExpression<'source>>,BodySyntaxFailure>{
      match &input.input.input{
       OriginalInitializerSource::Header(i)=>if !self.recipe.matches_header(i){return Ok(None)},
       OriginalInitializerSource::Static{root,..}=>if !matches!(self.recipe,OriginalInitializerRecipe::Static)||!matches!(&self.root,OriginalInitializerRoot::Static(old) if old.same_root(root)){return Ok(None)},
      }
      let current=input.expression()?;Ok(self.root.same_root(&current.root).then_some(current))
    }
    pub fn reborrow<'source>(
        &self,
        input: &OriginalInitializerExpressionInput<'source>,
    ) -> Result<Option<OriginalInitializerExpression<'source>>, BodySyntaxFailure> {
        match &input.input{
          OriginalInitializerSource::Header(i)=>if !self.recipe.matches_header(i){return Ok(None)},
          OriginalInitializerSource::Static{root,..}=>if !matches!(self.recipe,OriginalInitializerRecipe::Static)||!matches!(&self.root,OriginalInitializerRoot::Static(old) if old.same_root(root)){return Ok(None)},
        }
        let current = input.expression()?;
        if !self.root.same_root(&current.root) {
            return Ok(None);
        }
        Ok(Some(current))
    }
}
#[derive(Clone,Copy)]
enum OriginalInitializerPlan<'source>{
    Declaration(&'source crate::initializers::DeclarationPlan<'source>),
    Issued(&'source crate::initializers::IssuedInitializerPlan),
}
impl<'source> OriginalInitializerPlan<'source>{
    fn plan(self)->&'source crate::initializers::InitializerPlan{match self{Self::Declaration(plan)=>plan.plan(),Self::Issued(plan)=>plan.plan()}}
    fn matches_frontend(self,frontend:&ColdFrontend)->bool{match self{Self::Declaration(plan)=>std::ptr::eq(plan.source(),&frontend.snapshot),Self::Issued(plan)=>plan.matches_frontend(frontend)}}
}
enum OriginalInitializerSource<'source>{
 Header(relative_declarations::OriginalInitializerTokenInput<'source>),
 Static{root:super::static_receipt::OriginalStaticInitializerRoot,current_body:dm_syntax::Span},
}
/// Exact original private declaration plan row. The adapted write supplied later
/// by classifier array recursion cannot issue or replace this source proof.
pub struct OriginalInitializerExpressionInput<'a> {
    frontend: &'a ColdFrontend,
    plan: OriginalInitializerPlan<'a>,
    ordinal: usize,
    expression: &'a SymbolicExpression,
    input: OriginalInitializerSource<'a>,
}
impl std::fmt::Debug for OriginalInitializerExpressionInput<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("OriginalInitializerExpressionInput")
            .field("ordinal", &self.ordinal)
            .finish_non_exhaustive()
    }
}
impl<'source> OriginalInitializerExpressionInput<'source> {
    /// Operation-local alias of the actual checked startup producer, when this
    /// exact complete row is procedure-static. Literal-only evaluation does not
    /// require the weak receipt to survive; transitive reads check it explicitly.
    pub fn source_static_receipt(&self)->Option<Arc<IssuedStaticPlan>>{match self.plan{OriginalInitializerPlan::Issued(plan)=>plan.static_receipt(self.ordinal),OriginalInitializerPlan::Declaration(_)=>None}}
    pub fn declaration_context(&self)->OriginalDeclarationExpressionContext<'source>{OriginalDeclarationExpressionContext{frontend:self.frontend,mapping:self.frontend.source_export_mapping.as_ref()}}
    pub fn original_write(&self) -> &dm_ir::InitializerWrite {
        &self.plan.plan().writes[self.ordinal]
    }
    pub fn original_origin(&self) -> &crate::initializers::InitializerOrigin {
        &self.plan.plan().origins[self.ordinal]
    }
    pub fn expression(&self) -> Result<OriginalInitializerExpression<'source>, BodySyntaxFailure> {
        let provider = self
            .frontend
            .setting_expression_queries
            .as_ref()
            .and_then(std::sync::Weak::upgrade)
            .ok_or_else(|| {
                BodySyntaxFailure::Operational(std::io::Error::new(
                    std::io::ErrorKind::NotConnected,
                    "original initializer requires existing native expression host",
                ))
            })?;
        let result = provider.initializer(self)?;
        let valid=match (&self.input,&result.root){
          (OriginalInitializerSource::Header(i),OriginalInitializerRoot::Header(root))=>root.current_offset()==i.offset&&result.source.same_view(i.source)&&(if i.dimension{i.slots.contains_dimension(i.ordinal,i.dimension_index,i.value,root)}else{i.slots.contains_original(i.ordinal,root)}),
          (OriginalInitializerSource::Static{root,current_body},OriginalInitializerRoot::Static(got))=>root.same_root(got)&&result.current_body==Some(*current_body)&&result.source.same_view(&self.frontend.issued_arena),
          _=>false,
        };
        if !valid || !Arc::ptr_eq(&result.authored.tokens,&self.expression.tokens){return Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"initializer provider returned foreign source/root/projection")))}
        Ok(result)
    }
    pub fn prepare(&self,a:&dm_syntax::SettingAdmission<'_>)->Result<OriginalInitializerExpression<'source>,BodySyntaxFailure>{
        match &self.input{
          OriginalInitializerSource::Header(i)=>prepare_original_expression(self.frontend,self.expression,i,a),
          OriginalInitializerSource::Static{root,current_body}=>{
            root.require_admission(a)?;
            Ok(OriginalInitializerExpression{root:OriginalInitializerRoot::Static(root.clone()),source:&self.frontend.issued_arena,authored:self.expression,recipe:OriginalInitializerRecipe::Static,current_body:Some(*current_body)})
          }
        }
    }
}
fn prepare_original_expression<'source>(frontend:&'source ColdFrontend,expression:&'source SymbolicExpression,i:&relative_declarations::OriginalInitializerTokenInput<'source>,a:&dm_syntax::SettingAdmission<'_>)->Result<OriginalInitializerExpression<'source>,BodySyntaxFailure>{
        let produce=||i.tokens.with_dense_using(a,|dense|Ok(dm_syntax::prepare_setting_expression_with_original_literal_facts(i.source,dense,i.value,a,i.owner.original_literal_facts()?))).map_err(dm_syntax::SettingSyntaxFailure::Operational)?;
        let pending=if i.dimension{i.slots.obtain_dimension(i.ordinal,i.count,i.dimension_index,i.dimension_count,i.value,a,produce)}else{i.slots.obtain(i.ordinal,i.count,a,produce)};
        let result=pending
            .and_then(|root| {
                root.project_current(i.offset, i.source.len())
                    .map_err(dm_syntax::SettingSyntaxFailure::Operational)
            });
        if let Some(actual) = a.take_operational_error() {
            return Err(BodySyntaxFailure::Operational(actual));
        }
        let root = result.map_err(|error| match error {
            dm_syntax::SettingSyntaxFailure::Operational(error) => {
                BodySyntaxFailure::Operational(error)
            }
            dm_syntax::SettingSyntaxFailure::Syntax(error) => {
                BodySyntaxFailure::Syntax(Diagnostic {
                    kind: syntax_kind(error.kind),
                    stage: DiagnosticStage::Syntax,
                    location: error
                        .span
                        .start
                        .checked_add(i.offset)
                        .and_then(|at| frontend.location(at)),
                    message: error.message,
                })
            }
        })?;
        Ok(OriginalInitializerExpression {
            root:OriginalInitializerRoot::Header(root),
            current_body:None,
            source: i.source,
            authored: expression,
            recipe: OriginalInitializerRecipe::Header {
                owner: Arc::downgrade(i.owner),
                value: i.value,
                ordinal: i.ordinal,
                count: i.count,
                dimension:i.dimension,
            },
        })
}
/// A dimension is a distinct authored source root, never the write's RHS.
pub struct OriginalInitializerDimensionInput<'source>{input:OriginalInitializerExpressionInput<'source>,dimension:usize}
impl std::fmt::Debug for OriginalInitializerDimensionInput<'_>{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("OriginalInitializerDimensionInput").field("dimension",&self.dimension).finish_non_exhaustive()}}
impl<'source> OriginalInitializerDimensionInput<'source>{
 pub fn declaration_context(&self)->OriginalDeclarationExpressionContext<'source>{self.input.declaration_context()}
 pub fn source_static_receipt(&self)->Option<Arc<IssuedStaticPlan>>{self.input.source_static_receipt()}
 pub fn dimension_index(&self)->usize{self.dimension}
 pub fn original_write(&self)->&dm_ir::InitializerWrite{self.input.original_write()}
 pub fn prepare(&self,a:&dm_syntax::SettingAdmission<'_>)->Result<OriginalInitializerExpression<'source>,BodySyntaxFailure>{self.input.prepare(a)}
 pub fn expression(&self)->Result<OriginalInitializerExpression<'source>,BodySyntaxFailure>{original_declaration_admission(self.input.frontend,|a|self.prepare(a))}
}
/// SAME original token/root base as declaration-plan inputs, issued from an
/// actual selected variable instead of an adapted initializer write. No plan
/// scan or copied meaning/source can create this private receipt.
pub struct OriginalDeclarationExpressionInput<'source> {
    frontend:&'source ColdFrontend,
    expression:&'source SymbolicExpression,
    input:OriginalInitializerSource<'source>,
}
impl std::fmt::Debug for OriginalDeclarationExpressionInput<'_>{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("OriginalDeclarationExpressionInput")}}
impl<'source> OriginalDeclarationExpressionInput<'source>{
    pub fn prepare(&self,a:&dm_syntax::SettingAdmission<'_>)->Result<OriginalInitializerExpression<'source>,BodySyntaxFailure>{
        match &self.input{
          OriginalInitializerSource::Header(i)=>prepare_original_expression(self.frontend,self.expression,i,a),
          OriginalInitializerSource::Static{root,current_body}=>{root.require_admission(a)?;Ok(OriginalInitializerExpression{root:OriginalInitializerRoot::Static(root.clone()),source:&self.frontend.issued_arena,authored:self.expression,recipe:OriginalInitializerRecipe::Static,current_body:Some(*current_body)})}
        }
    }
    pub fn expression(&self)->Result<OriginalInitializerExpression<'source>,BodySyntaxFailure>{
        original_declaration_admission(self.frontend,|a|self.prepare(a))
    }
}
/// Private callback shape prevents omitted/repeated host calls from issuing a
/// result. The stack capability never escapes; the returned source borrow is
/// tied to the original frontend rather than this temporary provider Arc.
fn original_declaration_admission<T>(front:&ColdFrontend,operation:impl FnOnce(&dm_syntax::SettingAdmission<'_>)->Result<T,BodySyntaxFailure>)->Result<T,BodySyntaxFailure>{
 original_admission_using(front.setting_expression_queries.as_ref(),operation)
}
/// One existing-provider FnMut-to-FnOnce adapter shared by declaration and
/// archived-syntax work. Completion is the typed callback result itself; actual
/// callback IO wins even if a provider proxies, swallows, or later fails.
pub(super) fn original_admission_using<T>(provider:Option<&std::sync::Weak<dyn SettingExpressionQueries>>,operation:impl FnOnce(&dm_syntax::SettingAdmission<'_>)->Result<T,BodySyntaxFailure>)->Result<T,BodySyntaxFailure>{
 let provider=provider.and_then(std::sync::Weak::upgrade).ok_or_else(||BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"original declaration requires existing native expression host")))?;
 let mut operation=Some(operation);let mut completed=None;
 let outer=provider.with_declaration_admission(&mut|a|{
  let Some(operation)=operation.take()else{
   if !matches!(&completed,Some(Err(BodySyntaxFailure::Operational(_)))){completed=Some(Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"original declaration admission callback repeated"))))}
   return Err(BodySyntaxFailure::Operational(std::io::ErrorKind::InvalidData.into()))
  };
  let result=operation(a);
  if let Err(BodySyntaxFailure::Operational(actual))=&result{let kind=actual.kind();completed=Some(result);return Err(BodySyntaxFailure::Operational(kind.into()))}
  let status=a.checkpoint();if let Some(actual)=a.take_operational_error(){completed=Some(Err(BodySyntaxFailure::Operational(actual)));return Err(BodySyntaxFailure::Operational(std::io::ErrorKind::Other.into()))}
  if let Err(actual)=status{let kind=actual.kind();completed=Some(Err(BodySyntaxFailure::Operational(actual)));return Err(BodySyntaxFailure::Operational(kind.into()))}
  completed=Some(result);Ok(())
 });
 match completed{Some(Err(BodySyntaxFailure::Operational(actual)))=>Err(BodySyntaxFailure::Operational(actual)),other=>{outer?;other.ok_or_else(||BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"original declaration admission callback omitted")))?}}
}
/// Once-per-wave current source join. The existing target index is admitted
/// lazily once on the SAME owner/counter; no member-to-source sibling map.
pub struct OriginalDeclarationExpressionContext<'source>{
    frontend:&'source ColdFrontend,
    mapping:&'source source_export_mapping::SourceExportMapping,
}
impl std::fmt::Debug for OriginalDeclarationExpressionContext<'_>{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("OriginalDeclarationExpressionContext")}}
impl<'source> OriginalDeclarationExpressionContext<'source>{
    /// The context has already authenticated the complete immutable source mapping.
    pub fn abi_source_input(&self,body:&BodyOccurrence,metadata:&dm_ir::ProcedureMetadata)->Result<OriginalAbiSourceInput<'source>,BodySyntaxFailure>{abi_source::OriginalAbiSourceInput::issue(self.frontend,body,metadata)}

    /// One existing-host admission for a whole scalar traversal, including
    /// transitive selected roots. The permit never becomes source authority.
    pub fn with_admission(&self,operation:&mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>)->Result<(),BodySyntaxFailure>{
        original_declaration_admission(self.frontend,|a|operation(a))
    }

    /// Couple a top RHS with this SAME immutable original frontend frame before
    /// any transitive declaration read. No repeated whole-source validation.
    pub fn require_initializer(&self,input:&OriginalInitializerExpressionInput<'_>)->Result<(),BodySyntaxFailure>{
        if !std::ptr::eq(self.frontend,input.frontend)
            || !input.plan.matches_frontend(self.frontend)
            || !std::ptr::eq(self.mapping,self.frontend.source_export_mapping.as_ref()){
            return Err(BodySyntaxFailure::Syntax(internal("initializer and transitive declaration context use different original frames")));
        }
        Ok(())
    }

    /// Exact canonical metadata identity is proved before the bounded SAME
    /// procedure producer scan. No project/complete-plan lookup table is built.
    pub fn selected_static_admitted<'selected>(&self,receipt:&Arc<IssuedStaticPlan>,identity:dm_ir::ProcedureStaticIdentity,data:&'selected dm_ir::ProcedureStaticDeclaration,a:&dm_syntax::SettingAdmission<'_>)->Result<OriginalDeclarationExpressionInput<'selected>,BodySyntaxFailure> where 'source:'selected{
      let pending=(||{
        let reject=|message:&str|BodySyntaxFailure::Syntax(internal(message));
        a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
        let occurrence=receipt.source_occurrence();
        receipt.require_current_source(self.frontend,occurrence).map_err(|e|reject(&e))?;
        let relative=receipt.retained_relative_payload().ok_or_else(||reject("static canonical metadata has not been issued by original producer"))?;
        let canonical=relative.canonical_declarations();let index=canonical.binary_search_by_key(&identity,|row|row.identity).map_err(|_|reject("selected static canonical identity unavailable"))?;
        if !std::ptr::eq(data,canonical[index].as_ref())||data.identity!=identity{return Err(reject("selected static metadata is not original canonical object"))}
        let InitializerValue::Expression(expression)=&data.initializer else{return Err(reject("selected static has no authored RHS expression"))};
        let plan=receipt.plan();if plan.declarations.len()!=plan.origins.len(){return Err(reject("original static source roster incomplete"))}
        let mut header=None;
        for (declaration,origin) in plan.declarations.iter().zip(&plan.origins){
          a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
          if declaration.identity==identity{
            let InitializerValue::Expression(native)=&declaration.initializer else{return Err(reject("selected static producer RHS unavailable"))};
            if !Arc::ptr_eq(&native.tokens,&expression.tokens){return Err(reject("selected static token Arc differs from original producer"))}
            if header.replace(origin.header_span).is_some(){return Err(reject("selected static source identity is ambiguous"))}
          }
        }
        let header=header.ok_or_else(||reject("selected static original source header unavailable"))?;
        let root=receipt.original_initializer_root(identity,header).map_err(|e|reject(&e))?;
        root.require_admission(a)?;
        let index=*self.frontend.body_by_declaration.get(&occurrence).ok_or_else(||reject("selected static current body unavailable"))?;
        let current_body=self.frontend.issued_bodies.get(index).ok_or_else(||reject("selected static current body index unavailable"))?.expanded_span;
        a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
        Ok(OriginalDeclarationExpressionInput{frontend:self.frontend,expression,input:OriginalInitializerSource::Static{root,current_body}})
      })();
      if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}
      pending
    }
    pub fn selected(&self,owner:dm_ir::SymbolId,name:dm_ir::SymbolId,data:&dm_ir::DeclarationMeaning)->Result<OriginalDeclarationExpressionInput<'source>,BodySyntaxFailure>{
        original_declaration_admission(self.frontend,|a|self.selected_admitted(owner,name,data,a))
    }
    pub fn selected_admitted(&self,owner:dm_ir::SymbolId,name:dm_ir::SymbolId,data:&dm_ir::DeclarationMeaning,a:&dm_syntax::SettingAdmission<'_>)->Result<OriginalDeclarationExpressionInput<'source>,BodySyntaxFailure>{
        let pending=(||{
            a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
            let reject=|text:&str|BodySyntaxFailure::Syntax(internal(text));
            let frontend=self.frontend;let tree=&frontend.snapshot.tree;
            let owner_id=tree.lookup_type(owner).ok_or_else(||reject("selected declaration owner unavailable"))?;
            let member_id=tree.resolve(owner_id,name,crate::MemberKind::Var).ok_or_else(||reject("selected declaration variable unavailable"))?;
            let member=tree.member(member_id).ok_or_else(||reject("selected declaration member unavailable"))?;
            if tree.type_node(member.owner).map(|node|node.path)!=Some(owner) || member.name!=name || !std::ptr::eq(data,member.metadata.as_ref()){
                return Err(reject("selected declaration is not original current metadata owner"));
            }
            let expression=member.metadata.initializer.as_ref().ok_or_else(||reject("selected declaration has no authored RHS"))?;
            let ids=self.frontend.snapshot.occurrences.for_target_admitted(crate::Target::Member(member_id),a).map_err(BodySyntaxFailure::Operational)?;
            let [occurrence_id]=ids else{return Err(reject("selected declaration requires one exact original occurrence"))};
            let occurrence=self.frontend.snapshot.occurrences.get(*occurrence_id).ok_or_else(||reject("selected original occurrence unavailable"))?;
            if occurrence.target!=crate::Target::Member(member_id){return Err(reject("selected original occurrence target mismatch"))}
            let cursor=self.mapping.initializer_declaration_cursor(*occurrence_id).map_err(|e|reject(&e))?;
            let input=self.frontend.issued_syntax.initializer_token_input(cursor,expression,tree.symbols()).map_err(|e|reject(&e))?;
            a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
            Ok(OriginalDeclarationExpressionInput{frontend:self.frontend,expression,input:OriginalInitializerSource::Header(input)})
        })();
        if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}
        pending
    }
}
impl ColdFrontend{
    pub fn original_declaration_expression_context(&self)->Result<OriginalDeclarationExpressionContext<'_>,BodySyntaxFailure>{
        let reject=|text:&str|BodySyntaxFailure::Syntax(internal(text));
        if !Arc::ptr_eq(&self.syntax,&self.issued_syntax)||!self.expanded.text.same_view(&self.issued_arena){return Err(reject("declaration context is not original current frontend source"))}
        let mapping=self.source_export_mapping().ok_or_else(||reject("declaration current source mapping is unissued"))?;
        Ok(OriginalDeclarationExpressionContext{frontend:self,mapping})
    }
}
/// Stack-only native traversal over the actual original suffix tokens. No
/// source/semantic roster or AST is copied; empty suffix ordinals remain visible.
pub struct OriginalInitializerDimensions<'source>{context:OriginalInitializerContext<'source>,ordinal:usize,array:&'source dm_ir::ArrayDeclaration,header:Option<relative_declarations::OriginalInitializerDimensionTokens<'source>>,next:usize,finished:bool}
impl<'source> Iterator for OriginalInitializerDimensions<'source>{
 type Item=Result<(usize,Option<OriginalInitializerDimensionInput<'source>>),BodySyntaxFailure>;
 fn next(&mut self)->Option<Self::Item>{
  if self.finished{return None}
  if let Some(header)=&mut self.header{
   match header.next_input(self.array,&self.context.plan.plan().symbols){
    Err(message)=>{self.finished=true;Some(Err(BodySyntaxFailure::Syntax(internal(&message))))},
    Ok(None)=>{self.finished=true;None},
    Ok(Some((index,input)))=>{
     self.next=index+1;
     let value=input.map(|input|{let expression=self.array.dimensions[index].as_ref().expect("original cursor verifies expression presence");OriginalInitializerDimensionInput{input:OriginalInitializerExpressionInput{frontend:self.context.frontend,plan:self.context.plan,ordinal:self.ordinal,expression,input:OriginalInitializerSource::Header(input)},dimension:index}});
     Some(Ok((index,value)))
    }
   }
  }else{
   let index=self.next;if index>=self.array.dimensions.len(){self.finished=true;return None}self.next+=1;
   if self.array.dimensions[index].is_none(){Some(Ok((index,None)))}else{Some(self.context.dimension_input(self.ordinal,index).map(|input|(index,Some(input))))}
  }
 }
}
/// One stack-only admission of the immutable current declaration wave. Full
/// source/include/mapping validation happens ONCE here, never per initializer.
pub struct OriginalInitializerContext<'source> {
    frontend: &'source ColdFrontend,
    plan: OriginalInitializerPlan<'source>,
    mapping: &'source source_export_mapping::SourceExportMapping,
}
impl std::fmt::Debug for OriginalInitializerContext<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("OriginalInitializerContext")
    }
}
impl<'source> OriginalInitializerContext<'source> {
    /// Native array consumers exhaust this one-pass cursor before publishing
    /// their result. Individual completed immutable roots may remain reusable.
    pub fn dimensions(&self,ordinal:usize)->Result<OriginalInitializerDimensions<'source>,BodySyntaxFailure>{
      let reject=|message:&str|BodySyntaxFailure::Syntax(internal(message));let ledger=self.plan.plan();
      let write=ledger.writes.get(ordinal).ok_or_else(||reject("original dimension write ordinal unavailable"))?;let origin=ledger.origins.get(ordinal).ok_or_else(||reject("original dimension origin unavailable"))?;
      let array=write.declared_array.as_ref().or_else(||match &write.value{InitializerValue::ArrayAllocation(array)=>Some(array),_=>None}).ok_or_else(||reject("original write has no declared dimensions"))?;
      let header=match origin.kind{
       crate::initializers::InitializerOriginKind::Declaration(member)=>{
        let occurrence=self.frontend.snapshot.occurrences.get(origin.occurrence).ok_or_else(||reject("dimension declaration occurrence unavailable"))?;
        if occurrence.target!=crate::Target::Member(member)||occurrence.provenance!=origin.provenance{return Err(reject("dimension origin does not select original declaration"))}
        let member=self.frontend.snapshot.tree.member(member).filter(|m|m.kind==crate::MemberKind::Var).ok_or_else(||reject("dimension original variable member unavailable"))?;
        let native=member.metadata.array.as_ref().ok_or_else(||reject("original declaration array metadata unavailable"))?;if !Arc::ptr_eq(native,array){return Err(reject("dimension array Arc is not original declaration metadata"))}
        let cursor=self.mapping.initializer_declaration_cursor(origin.occurrence).map_err(|e|reject(&e))?;
        Some(self.frontend.issued_syntax.initializer_dimension_cursor(cursor).map_err(|e|reject(&e))?)
       }
       crate::initializers::InitializerOriginKind::ProcedureStatic{identity,expanded_span}=>{
        let OriginalInitializerPlan::Issued(issued)=self.plan else{return Err(reject("static dimension requires original complete issued plan"))};let receipt=issued.static_receipt(ordinal).ok_or_else(||reject("static dimension producer receipt expired"))?;
        receipt.require_current_source(self.frontend,origin.occurrence).map_err(|e|reject(&e))?;let declaration=receipt.original_declaration(expanded_span).ok_or_else(||reject("static dimension original declaration unavailable"))?;let native=declaration.declared_array.as_ref().ok_or_else(||reject("static array metadata unavailable"))?;
        if declaration.identity!=identity||!Arc::ptr_eq(native,array){return Err(reject("static dimension original metadata Arc/identity differs"))}None
       }
      };
      Ok(OriginalInitializerDimensions{context:OriginalInitializerContext{frontend:self.frontend,plan:self.plan,mapping:self.mapping},ordinal,array,header,next:0,finished:false})
    }

    /// The exact declared suffix ordinal includes empty dimensions; an empty
    /// suffix has no Expr root and is refused rather than synthesized.
    pub fn dimension_input(&self,ordinal:usize,dimension:usize)->Result<OriginalInitializerDimensionInput<'source>,BodySyntaxFailure>{
      let reject=|message:&str|BodySyntaxFailure::Syntax(internal(message));
      let ledger=self.plan.plan();let write=ledger.writes.get(ordinal).ok_or_else(||reject("original dimension write ordinal unavailable"))?;
      let origin=ledger.origins.get(ordinal).ok_or_else(||reject("original dimension origin unavailable"))?;
      let array=write.declared_array.as_ref().or_else(||match &write.value{InitializerValue::ArrayAllocation(array)=>Some(array),_=>None}).ok_or_else(||reject("original write has no declared dimensions"))?;
      let expression=array.dimensions.get(dimension).and_then(Option::as_ref).ok_or_else(||reject("original dimension is empty or unavailable"))?;
      let frontend=self.frontend;
      let input=match origin.kind{
       crate::initializers::InitializerOriginKind::Declaration(member)=>{
        let occurrence=frontend.snapshot.occurrences.get(origin.occurrence).ok_or_else(||reject("dimension declaration occurrence unavailable"))?;
        if occurrence.target!=crate::Target::Member(member)||occurrence.provenance!=origin.provenance{return Err(reject("dimension origin does not select original declaration"))}
        let member=frontend.snapshot.tree.member(member).filter(|m|m.kind==crate::MemberKind::Var).ok_or_else(||reject("dimension original variable member unavailable"))?;
        let native=member.metadata.array.as_ref().ok_or_else(||reject("original declaration array metadata unavailable"))?;
        if !Arc::ptr_eq(native,array){return Err(reject("dimension array Arc is not original declaration metadata"))}
        let cursor=self.mapping.initializer_declaration_cursor(origin.occurrence).map_err(|e|reject(&e))?;
        let input=frontend.issued_syntax.initializer_dimension_token_input(cursor,dimension,array.dimensions.len(),expression,&ledger.symbols).map_err(|e|reject(&e))?;
        OriginalInitializerSource::Header(input)
       }
       crate::initializers::InitializerOriginKind::ProcedureStatic{identity,expanded_span}=>{
        let OriginalInitializerPlan::Issued(issued)=self.plan else{return Err(reject("static dimension requires original complete issued plan"))};
        let receipt=issued.static_receipt(ordinal).ok_or_else(||reject("static dimension producer receipt expired"))?;
        receipt.require_current_source(frontend,origin.occurrence).map_err(|e|reject(&e))?;
        let declaration=receipt.original_declaration(expanded_span).ok_or_else(||reject("static dimension original declaration unavailable"))?;
        let native=declaration.declared_array.as_ref().ok_or_else(||reject("static array metadata unavailable"))?;
        if declaration.identity!=identity||!Arc::ptr_eq(native,array){return Err(reject("static dimension original metadata Arc/identity differs"))}
        let root=receipt.original_dimension_root(identity,expanded_span,dimension,array.dimensions.len()).map_err(|e|reject(&e))?;
        let index=*frontend.body_by_declaration.get(&origin.occurrence).ok_or_else(||reject("static dimension body unavailable"))?;
        let current_body=frontend.issued_bodies.get(index).ok_or_else(||reject("static dimension body index unavailable"))?.expanded_span;
        OriginalInitializerSource::Static{root,current_body}
       }
      };
      Ok(OriginalInitializerDimensionInput{input:OriginalInitializerExpressionInput{frontend,plan:self.plan,ordinal,expression,input},dimension})
    }

    pub fn input(
        &self,
        ordinal: usize,
    ) -> Result<OriginalInitializerExpressionInput<'source>, BodySyntaxFailure> {
        let frontend = self.frontend;
        let plan = self.plan;
        let mapping = self.mapping;
        let reject = |text: &str| BodySyntaxFailure::Syntax(internal(text));
        let ledger = plan.plan();
        let write = ledger
            .writes
            .get(ordinal)
            .ok_or_else(|| reject("original initializer ordinal unavailable"))?;
        let origin = ledger
            .origins
            .get(ordinal)
            .ok_or_else(|| reject("original initializer origin unavailable"))?;
        let InitializerValue::Expression(expression)=&write.value else{return Err(reject("initializer has no authored RHS expression"))};
        if let crate::initializers::InitializerOriginKind::ProcedureStatic{identity,expanded_span}=origin.kind{
            let OriginalInitializerPlan::Issued(issued)=plan else{return Err(reject("static source requires original complete issued plan"))};
            let receipt=issued.static_receipt(ordinal).ok_or_else(||reject("complete static original producer receipt expired"))?;
            receipt.require_current_source(frontend,origin.occurrence).map_err(|e|reject(&e))?;
            let declaration=receipt.original_declaration(expanded_span).ok_or_else(||reject("complete static row has no exact producer declaration"))?;
            let InitializerValue::Expression(native)=&declaration.initializer else{return Err(reject("static producer has no authored RHS expression"))};
            if !Arc::ptr_eq(&native.tokens,&expression.tokens){return Err(reject("static authored token Arc differs from original producer"))}
            let root=receipt.original_initializer_root(identity,expanded_span).map_err(|e|reject(&e))?;
            let index=*frontend.body_by_declaration.get(&origin.occurrence).ok_or_else(||reject("static source current body unavailable"))?;
            let current_body=frontend.issued_bodies.get(index).ok_or_else(||reject("static source current body index invalid"))?.expanded_span;
            return Ok(OriginalInitializerExpressionInput{frontend,plan,ordinal,expression,input:OriginalInitializerSource::Static{root,current_body}});
        }
        let crate::initializers::InitializerOriginKind::Declaration(member) = origin.kind else {
            return Err(reject(
                "procedure-static initializer roots require original body issuer",
            ));
        };
        let occurrence = frontend
            .snapshot
            .occurrences
            .get(origin.occurrence)
            .ok_or_else(|| reject("original initializer occurrence unavailable"))?;
        if occurrence.target != crate::Target::Member(member)
            || occurrence.provenance != origin.provenance
        {
            return Err(reject(
                "initializer origin does not select original declaration",
            ));
        }
        let member = frontend
            .snapshot
            .tree
            .member(member)
            .filter(|m| m.kind == crate::MemberKind::Var)
            .ok_or_else(|| reject("initializer origin is not a variable declaration"))?;
        let InitializerValue::Expression(expression) = &write.value else {
            return Err(reject("initializer has no authored RHS expression"));
        };
        let native = member
            .metadata
            .initializer
            .as_ref()
            .ok_or_else(|| reject("original initializer metadata unavailable"))?;
        if !Arc::ptr_eq(&expression.tokens, &native.tokens) {
            return Err(reject(
                "initializer token Arc is not the original member metadata",
            ));
        }
        let cursor = mapping
            .initializer_declaration_cursor(origin.occurrence)
            .map_err(|e| reject(&e))?;
        let input = frontend
            .issued_syntax
            .initializer_token_input(cursor, expression, frontend.snapshot.tree.symbols())
            .map_err(|e| reject(&e))?;
        Ok(OriginalInitializerExpressionInput {
            frontend,
            plan,
            ordinal,
            expression,
            input:OriginalInitializerSource::Header(input),
        })
    }
}
impl ColdFrontend {
    pub fn original_initializer_context<'source>(
        &'source self,
        plan: &'source crate::initializers::DeclarationPlan<'source>,
    ) -> Result<OriginalInitializerContext<'source>, BodySyntaxFailure> {
        let reject = |text: &str| BodySyntaxFailure::Syntax(internal(text));
        if !std::ptr::eq(plan.source(), &self.snapshot)
            || !Arc::ptr_eq(&self.syntax, &self.issued_syntax)
            || !self.expanded.text.same_view(&self.issued_arena)
        {
            return Err(reject(
                "initializer plan is not this original frontend snapshot",
            ));
        }
        let mapping = self
            .source_export_mapping()
            .ok_or_else(|| reject("initializer current source mapping is unissued"))?;
        Ok(OriginalInitializerContext {
            frontend: self,
            plan: OriginalInitializerPlan::Declaration(plan),
            mapping,
        })
    }
    /// Actual complete ordinal from the SAME checked declaration/static merge.
    /// Public detached InitializerPlan values cannot issue this source context.
    pub fn original_issued_initializer_context<'source>(&'source self,plan:&'source crate::initializers::IssuedInitializerPlan)->Result<OriginalInitializerContext<'source>,BodySyntaxFailure>{
        if !plan.matches_frontend(self) || !Arc::ptr_eq(&self.syntax,&self.issued_syntax) || !self.expanded.text.same_view(&self.issued_arena){return Err(BodySyntaxFailure::Syntax(internal("complete initializer plan is not this original current frontend frame")))}
        let mapping=self.source_export_mapping().ok_or_else(||BodySyntaxFailure::Syntax(internal("complete initializer source mapping is unissued")))?;
        Ok(OriginalInitializerContext{frontend:self,plan:OriginalInitializerPlan::Issued(plan),mapping})
    }
    /// Bounded single-input convenience. Native multi-write waves retain one
    /// original_initializer_context and use its input() for every ordinal.
    pub fn original_initializer_input<'source>(
        &'source self,
        plan: &'source crate::initializers::DeclarationPlan<'source>,
        ordinal: usize,
    ) -> Result<OriginalInitializerExpressionInput<'source>, BodySyntaxFailure> {
        self.original_initializer_context(plan)?.input(ordinal)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        path::Path,
        sync::{atomic::AtomicUsize, Arc},
    };
    struct Source(dm_preprocess::AcquiredSource);
    impl dm_preprocess::SourceProvider for Source {
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
    struct OriginalHost(Arc<dm_syntax::SettingChargeCounter>);
    impl SettingExpressionQueries for OriginalHost {
        fn statements(&self,input:&mut SettingStatementsInput<'_,'_>)->Result<Arc<StatementBody>,BodySyntaxFailure>{let check=||Ok(());let a=dm_syntax::SettingAdmission::new(&self.0,128*1024*1024,&check);input.prepare(&a)}
        fn with_declaration_admission(&self,operation:&mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>)->Result<(),BodySyntaxFailure>{
            let checkpoint=||Ok(());let a=dm_syntax::SettingAdmission::new(&self.0,128*1024*1024,&checkpoint);
            let result=operation(&a);
            if matches!(&result,Err(BodySyntaxFailure::Operational(_))){return result}
            let status=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}status.map_err(BodySyntaxFailure::Operational)?;result
        }
        fn expression(
            &self,
            input: &SettingExpressionInput<'_>,
        ) -> Result<dm_syntax::SettingExpression, BodySyntaxFailure> {
            let checkpoint = || Ok(());
            let a = dm_syntax::SettingAdmission::new(&self.0, 128 * 1024 * 1024, &checkpoint);
            input.prepare(&a)
        }
        fn initializer<'source>(
            &self,
            input: &OriginalInitializerExpressionInput<'source>,
        ) -> Result<OriginalInitializerExpression<'source>, BodySyntaxFailure> {
            let checkpoint = || Ok(());
            let a = dm_syntax::SettingAdmission::new(&self.0, 128 * 1024 * 1024, &checkpoint);
            input.prepare(&a)
        }
    }
    #[derive(Debug)]
    struct NoBody;
    impl BodySyntaxQueries for NoBody {
        fn syntax(&self, _: &Arc<BodySyntaxInput>) -> Result<Arc<BodySyntax>, Diagnostic> {
            panic!("top-level declaration root cannot demand BodySyntax")
        }
    }
    fn front(source: &str, host: &Arc<dyn SettingExpressionQueries>) -> ColdFrontend {
        let source = Source(dm_preprocess::AcquiredSource::from_original_bytes(
            source.as_bytes().to_vec(),
            (),
        ));
        build(
            Path::new("original-initializer.dme"),
            &source,
            &Default::default(),
            1,
        )
        .unwrap()
        .with_setting_expression_queries(host)
        .unwrap()
        .with_body_queries(Arc::new(NoBody))
    }
    #[test]
    fn exact_private_declaration_plan_origin_and_token_arc_issue_one_original_rhs_root() {
        let host = Arc::new(OriginalHost(Arc::new(AtomicUsize::new(0))))
            as Arc<dyn SettingExpressionQueries>;
        for text in [
            "var/static/value = 1+2",
            "var/static/num/value = 1 + /* original */ 2 as num",
        ] {
            let source = format!("/datum/probe\n    {text}\n/proc/no_body()\n    return 1\n");
            let front = front(&source, &host);
            let plan = crate::initializers::capture_declaration_plan(
                &front.snapshot,
                &front.emission_order,
            )
            .unwrap();
            assert_eq!(plan.plan().writes.len(), 1);
            let input = front.original_initializer_input(&plan, 0).unwrap();
            assert!(std::ptr::eq(input.original_write(), &plan.plan().writes[0]));
            assert!(std::ptr::eq(
                input.original_origin(),
                &plan.plan().origins[0]
            ));
            let root = input.expression().unwrap();
            let warm = input.expression().unwrap();
            assert!(root.same_root(&warm));
            assert!(std::ptr::eq(root.ast(), warm.ast()));
            assert_eq!(
                root.source_text(root.ast().span).unwrap().trim(),
                if text.contains("/*") {
                    // Original preprocessing blanks comments without changing byte spans.
                    "1 +                2"
                } else {
                    "1+2"
                }
            );
            assert_eq!(
                &front.expanded.text[root.current_span().range()],
                root.source_text(root.ast().span).unwrap(),
                "current expanded projection and original primary chunk agree"
            );
            let actual = dm_syntax::parse_expression(root.source_text(root.ast().span).unwrap());
            assert!(
                actual.diagnostics.is_empty(),
                "independent existing parser validates genuine original root grammar"
            );
            assert!(front.original_initializer_input(&plan, 1).is_err());
            let copied = front.snapshot.clone();
            let foreign =
                crate::initializers::capture_declaration_plan(&copied, &front.emission_order)
                    .unwrap();
            assert!(
                front.original_initializer_input(&foreign, 0).is_err(),
                "equal snapshot bytes do not bind private source receipt"
            );
        }
    }
    #[test]
    fn absent_native_initializer_provider_does_not_reparse_symbolic_text() {
        let source = Source(dm_preprocess::AcquiredSource::from_original_bytes(
            b"var/static/value=1+2\n".to_vec(),
            (),
        ));
        let front = build(
            Path::new("bare-initializer.dme"),
            &source,
            &Default::default(),
            1,
        )
        .unwrap();
        let plan =
            crate::initializers::capture_declaration_plan(&front.snapshot, &front.emission_order)
                .unwrap();
        let input = front.original_initializer_input(&plan, 0).unwrap();
        let error = input
            .expression()
            .err()
            .expect("original source host required");
        assert!(
            matches!(error,BodySyntaxFailure::Operational(ref e) if e.kind()==std::io::ErrorKind::NotConnected)
        );
    }
    #[test]
    fn original_initializer_real_slot_admission_refusal_retries_same_source_and_counter() {
        #[derive(Debug)]
        struct BudgetHost {
            counter: Arc<dm_syntax::SettingChargeCounter>,
            limit: AtomicUsize,
        }
        impl SettingExpressionQueries for BudgetHost {
            fn expression(
                &self,
                _: &SettingExpressionInput<'_>,
            ) -> Result<dm_syntax::SettingExpression, BodySyntaxFailure> {
                panic!("initializer is not a setting")
            }
            fn initializer<'source>(
                &self,
                input: &OriginalInitializerExpressionInput<'source>,
            ) -> Result<OriginalInitializerExpression<'source>, BodySyntaxFailure> {
                let checkpoint = || Ok(());
                let a = dm_syntax::SettingAdmission::new(
                    &self.counter,
                    self.limit.load(std::sync::atomic::Ordering::Acquire),
                    &checkpoint,
                );
                input.prepare(&a)
            }
        }
        let counter = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let native = Arc::new(BudgetHost {
            counter: Arc::clone(&counter),
            limit: AtomicUsize::new(0),
        });
        let host = Arc::clone(&native) as Arc<dyn SettingExpressionQueries>;
        {
            let front = front("var/static/value=1+2\n", &host);
            let plan = crate::initializers::capture_declaration_plan(
                &front.snapshot,
                &front.emission_order,
            )
            .unwrap();
            let input = front.original_initializer_input(&plan, 0).unwrap();
            let error = input
                .expression()
                .err()
                .expect("actual zero same-counter admission");
            assert!(
                matches!(error,BodySyntaxFailure::Operational(ref e) if e.kind()==std::io::ErrorKind::OutOfMemory)
            );
            assert_eq!(
                counter.load(std::sync::atomic::Ordering::Acquire),
                dm_syntax::SettingChargeCounter::root_allocation_bytes(),
                "failed allocation never mints a root/lease"
            );
            native
                .limit
                .store(128 * 1024 * 1024, std::sync::atomic::Ordering::Release);
            let first = input.expression().unwrap();
            assert!(first.same_root(&input.expression().unwrap()));
            assert!(counter.load(std::sync::atomic::Ordering::Acquire) > dm_syntax::SettingChargeCounter::root_allocation_bytes());
        }
        assert_eq!(
            counter.load(std::sync::atomic::Ordering::Acquire),
            dm_syntax::SettingChargeCounter::root_allocation_bytes(),
            "original syntax and all leased roots physically released"
        );
    }
    struct Includes {
        q: String,
    }
    impl dm_preprocess::SourceProvider for Includes {
        fn read(&self, path: &Path) -> Result<String, String> {
            Ok(match path.file_name().and_then(|n| n.to_str()) {
                Some("p.dm") => "var/static/value=1+2\n".into(),
                Some("q.dm") => self.q.clone(),
                _ => "#include \"q.dm\"\n#include \"p.dm\"\n".into(),
            })
        }
    }
    fn q_chunk(padding: &str, value: u32) -> String {
        let closes = |header: &str| {
            header.bytes().fold(0xcbf29ce484222325u64, |h, b| {
                (h ^ u64::from(b)).wrapping_mul(0x100000001b3)
            }) & 15
                == 0
        };
        let tail = (0..)
            .map(|i| format!("/proc/q_tail{i}()"))
            .find(|h| closes(h))
            .unwrap();
        format!("{padding}/proc/q()\n    return {value}\n{tail}\n    return {value}\n")
    }
    fn included(
        state: &mut RetainedSemanticTree,
        host: &Arc<dyn SettingExpressionQueries>,
        q: String,
    ) -> ColdFrontend {
        let executor = dm_exec::BuildExecutor::new(1).unwrap();
        build_with_executor_and_semantic_state(
            Path::new("initializer-offset.dme"),
            &Includes { q },
            &Default::default(),
            FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
            None,
            &executor,
            Some(state),
        )
        .unwrap()
        .with_setting_expression_queries(host)
        .unwrap()
        .with_body_queries(Arc::new(NoBody))
    }
    #[test]
    fn original_initializer_warm_include_keeps_exact_root_and_current_projection_and_refuses_foreign_counter(
    ) {
        let host = Arc::new(OriginalHost(Arc::new(AtomicUsize::new(0))))
            as Arc<dyn SettingExpressionQueries>;
        let mut state = RetainedSemanticTree::default();
        let old = included(&mut state, &host, q_chunk("", 1));
        let old_plan =
            crate::initializers::capture_declaration_plan(&old.snapshot, &old.emission_order)
                .unwrap();
        assert_eq!(old_plan.plan().writes.len(), 1);
        let first = old
            .original_initializer_input(&old_plan, 0)
            .unwrap()
            .expression()
            .unwrap();
        let current = included(
            &mut state,
            &host,
            q_chunk("// earlier include changed\n\n", 333),
        );
        let current_plan = crate::initializers::capture_declaration_plan(
            &current.snapshot,
            &current.emission_order,
        )
        .unwrap();
        let now = current
            .original_initializer_input(&current_plan, 0)
            .unwrap()
            .expression()
            .unwrap();
        assert!(first.same_root(&now));
        assert!(std::ptr::eq(first.ast(), now.ast()));
        assert_eq!(
            first.ast().span,
            now.ast().span,
            "original chunk syntax never shifted"
        );
        assert_ne!(first.current_span(), now.current_span());
        assert_eq!(&current.expanded.text[now.current_span().range()], "1+2");
        let other = Arc::new(OriginalHost(Arc::new(AtomicUsize::new(0))))
            as Arc<dyn SettingExpressionQueries>;
        let foreign = included(
            &mut state,
            &other,
            q_chunk("// earlier include changed\n\n", 333),
        );
        let foreign_plan = crate::initializers::capture_declaration_plan(
            &foreign.snapshot,
            &foreign.emission_order,
        )
        .unwrap();
        let error = foreign
            .original_initializer_input(&foreign_plan, 0)
            .unwrap()
            .expression()
            .err()
            .expect("same original root cannot migrate counter domains");
        assert!(
            matches!(error,BodySyntaxFailure::Operational(ref e) if e.kind()==std::io::ErrorKind::InvalidInput)
        );
        assert!(now.same_root(
            &current
                .original_initializer_input(&current_plan, 0)
                .unwrap()
                .expression()
                .unwrap()
        ));
    }
    #[test]
    fn initializer_original_lookup_descends_existing_nested_arena_without_root_admission_or_cap() {
        let counter = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let host =
            Arc::new(OriginalHost(Arc::clone(&counter))) as Arc<dyn SettingExpressionQueries>;
        let mut source = String::from("/datum/deep\n");
        for n in 0..64 {
            source.push_str(&format!("{}level{n}\n", " ".repeat(4 * (n + 1))));
        }
        source.push_str(&format!("{}var/static/value=1+2\n", " ".repeat(4 * 65)));
        let front = front(&source, &host);
        let plan =
            crate::initializers::capture_declaration_plan(&front.snapshot, &front.emission_order)
                .unwrap();
        assert_eq!(plan.plan().writes.len(), 1);
        let input = front.original_initializer_input(&plan, 0).unwrap();
        assert_eq!(
            counter.load(std::sync::atomic::Ordering::Acquire),
            dm_syntax::SettingChargeCounter::root_allocation_bytes(),
            "source lookup itself allocates no root/slot work"
        );
        let root = input.expression().unwrap();
        assert_eq!(root.source_text(root.ast().span).unwrap(), "1+2");
    }
    #[test]
    fn initializer_wave_validates_full_current_mapping_once_for_all_original_ordinals() {
        let host = Arc::new(OriginalHost(Arc::new(AtomicUsize::new(0))))
            as Arc<dyn SettingExpressionQueries>;
        let mut source = String::new();
        for n in 0..32 {
            source.push_str(&format!("var/static/value{n}={n}+1\n"));
        }
        let front = front(&source, &host);
        let plan =
            crate::initializers::capture_declaration_plan(&front.snapshot, &front.emission_order)
                .unwrap();
        assert_eq!(plan.plan().writes.len(), 32);
        super::super::source_export_mapping::reset_full_source_admissions_for_test();
        let context = front.original_initializer_context(&plan).unwrap();
        for ordinal in 0..plan.plan().writes.len() {
            let input = context.input(ordinal).unwrap();
            assert!(std::ptr::eq(
                input.original_write(),
                &plan.plan().writes[ordinal]
            ));
            input.expression().unwrap();
        }
        assert_eq!(
            super::super::source_export_mapping::full_source_admissions_for_test(),
            1,
            "full captured source/include admission belongs to the wave, never each field"
        );
    }
    #[test]
    fn initializer_recipe_outlives_source_without_retaining_source_and_declines_equal_text_owner() {
        let counter = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let host =
            Arc::new(OriginalHost(Arc::clone(&counter))) as Arc<dyn SettingExpressionQueries>;
        let (recipe, pointer) = {
            let front = front("var/static/value=1+2\n", &host);
            let plan = crate::initializers::capture_declaration_plan(
                &front.snapshot,
                &front.emission_order,
            )
            .unwrap();
            let root = front
                .original_initializer_input(&plan, 0)
                .unwrap()
                .expression()
                .unwrap();
            let pointer = root.ast() as *const dm_syntax::Expr;
            (root.into_recipe(), pointer)
        };
        assert!(
            matches!(&recipe.recipe,OriginalInitializerRecipe::Header{owner,..} if owner.upgrade().is_none()),
            "recipe keeps no source owner alive"
        );
        assert_eq!(recipe.ast() as *const dm_syntax::Expr, pointer);
        let charged = counter.load(std::sync::atomic::Ordering::Acquire);
        assert!(
            charged > 0,
            "same root physical storage retains its original lease"
        );
        let new = front("var/static/value=1+2\n", &host);
        let plan =
            crate::initializers::capture_declaration_plan(&new.snapshot, &new.emission_order)
                .unwrap();
        let input = new.original_initializer_input(&plan, 0).unwrap();
        assert!(
            recipe.reborrow(&input).unwrap().is_none(),
            "equal text is not an original owner receipt"
        );
        assert_eq!(
            counter.load(std::sync::atomic::Ordering::Acquire),
            charged,
            "decline does not populate new slot"
        );
        let alias = recipe.clone();
        assert!(recipe.same_root(&alias));
        drop(recipe);
        assert_eq!(alias.ast() as *const dm_syntax::Expr, pointer);
        drop(alias);
        assert_eq!(counter.load(std::sync::atomic::Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
    }
    #[test]
    fn initializer_recipe_reborrows_same_root_at_current_offset_and_preserves_foreign_domain_error()
    {
        let host = Arc::new(OriginalHost(Arc::new(AtomicUsize::new(0))))
            as Arc<dyn SettingExpressionQueries>;
        let mut state = RetainedSemanticTree::default();
        let old = included(&mut state, &host, q_chunk("", 1));
        let old_plan =
            crate::initializers::capture_declaration_plan(&old.snapshot, &old.emission_order)
                .unwrap();
        let first = old
            .original_initializer_input(&old_plan, 0)
            .unwrap()
            .expression()
            .unwrap();
        let old_span = first.current_span();
        let pointer = first.ast() as *const dm_syntax::Expr;
        let recipe = first.into_recipe();
        let current = included(
            &mut state,
            &host,
            q_chunk("// preceding include changed\n\n", 31),
        );
        let plan = crate::initializers::capture_declaration_plan(
            &current.snapshot,
            &current.emission_order,
        )
        .unwrap();
        let input = current.original_initializer_input(&plan, 0).unwrap();
        let root = recipe
            .reborrow(&input)
            .unwrap()
            .expect("same exact retained original owner");
        assert_eq!(root.ast() as *const dm_syntax::Expr, pointer);
        assert_ne!(root.current_span(), old_span);
        assert_eq!(&current.expanded.text[root.current_span().range()], "1+2");
        let other = Arc::new(OriginalHost(Arc::new(AtomicUsize::new(0))))
            as Arc<dyn SettingExpressionQueries>;
        let foreign = included(
            &mut state,
            &other,
            q_chunk("// preceding include changed\n\n", 31),
        );
        let plan = crate::initializers::capture_declaration_plan(
            &foreign.snapshot,
            &foreign.emission_order,
        )
        .unwrap();
        let error = recipe
            .reborrow(&foreign.original_initializer_input(&plan, 0).unwrap())
            .err()
            .expect("domain refusal is not a decline");
        assert!(
            matches!(error,BodySyntaxFailure::Operational(ref actual) if actual.kind()==std::io::ErrorKind::InvalidInput)
        );
        assert!(recipe.reborrow(&input).unwrap().is_some());
    }
    #[test]
    fn selected_declaration_source_requires_exact_current_metadata_and_reuses_original_plan_root_without_body_demand(){
        let host=Arc::new(OriginalHost(Arc::new(AtomicUsize::new(0)))) as Arc<dyn SettingExpressionQueries>;
        let front=front("/datum/probe\n    var/const/value=unknown+1\n/datum/child\n    parent_type=/datum/probe\n/proc/no_body()\n    return 1\n",&host);
        let tree=&front.snapshot.tree;let owner=dm_ir::SymbolId::of("/datum/probe");let name=dm_ir::SymbolId::of("value");let member=tree.resolve(tree.lookup_type(owner).unwrap(),name,crate::MemberKind::Var).unwrap();let metadata=&tree.member(member).unwrap().metadata;
        let context=front.original_declaration_expression_context().unwrap();
        let input=context.selected(owner,name,metadata).unwrap();let first=input.expression().unwrap();
        assert_eq!(first.source_text(first.ast().span).unwrap(),"unknown+1");
        let warm=context.selected(owner,name,metadata).unwrap().expression().unwrap();assert!(first.same_root(&warm));
        let recipe=first.into_recipe();let rebound=recipe.reborrow_declaration(&input).unwrap().unwrap();assert!(std::ptr::eq(recipe.ast(),rebound.ast()));
        let copied=metadata.as_ref().clone();assert!(context.selected(owner,name,&copied).is_err(),"copied semantic meaning is not original source authority");
        assert!(context.selected(dm_ir::SymbolId::of("/datum/child"),name,metadata).is_err(),"inherited lookup must keep actual declaring owner");
        let plan=crate::initializers::capture_declaration_plan(&front.snapshot,&front.emission_order).unwrap();
        let ordinal=plan.plan().origins.iter().position(|origin|matches!(origin.kind,crate::initializers::InitializerOriginKind::Declaration(id)if id==member)).unwrap();
        let original=front.original_initializer_input(&plan,ordinal).unwrap().expression().unwrap();assert!(original.same_root(&rebound),"both exact issuers borrow one original header slot");
    }
    #[test]
    fn selected_source_foreign_frontend_cannot_reborrow_equal_text_recipe(){
        let host=Arc::new(OriginalHost(Arc::new(AtomicUsize::new(0)))) as Arc<dyn SettingExpressionQueries>;
        let a=front("var/const/value=unknown+1\n",&host);let b=front("var/const/value=unknown+1\n",&host);
        let select=|front:&ColdFrontend|{let tree=&front.snapshot.tree;tree.resolve(tree.lookup_type(dm_ir::SymbolId::of("/")).unwrap(),dm_ir::SymbolId::of("value"),crate::MemberKind::Var).unwrap()};
        let ai=select(&a);let bi=select(&b);
        let ac=a.original_declaration_expression_context().unwrap();let bc=b.original_declaration_expression_context().unwrap();
        let input=ac.selected(dm_ir::SymbolId::of("/"),dm_ir::SymbolId::of("value"),&a.snapshot.tree.member(ai).unwrap().metadata).unwrap();let recipe=input.expression().unwrap().into_recipe();
        let input=bc.selected(dm_ir::SymbolId::of("/"),dm_ir::SymbolId::of("value"),&b.snapshot.tree.member(bi).unwrap().metadata).unwrap();
        assert!(recipe.reborrow_declaration(&input).unwrap().is_none(),"equal authored bytes cannot substitute fixed original owner");
    }

    #[test]
    fn transitive_context_requires_same_top_initializer_frontend_even_for_equal_source(){
        let host=Arc::new(OriginalHost(Arc::new(AtomicUsize::new(0)))) as Arc<dyn SettingExpressionQueries>;
        let a=front("var/const/value=unknown+1\n",&host);let b=front("var/const/value=unknown+1\n",&host);
        let pa=crate::initializers::capture_declaration_plan(&a.snapshot,&a.emission_order).unwrap();let pb=crate::initializers::capture_declaration_plan(&b.snapshot,&b.emission_order).unwrap();
        let ai=a.original_initializer_input(&pa,0).unwrap();let bi=b.original_initializer_input(&pb,0).unwrap();
        let context=a.original_declaration_expression_context().unwrap();
        context.require_initializer(&ai).unwrap();assert!(context.require_initializer(&bi).is_err(),"equal source/semantic meaning is not original frame authority");
    }
    #[test]
    fn transitive_context_shared_admission_reuses_original_root_without_new_body_demand() {
        let host=Arc::new(OriginalHost(Arc::new(AtomicUsize::new(0)))) as Arc<dyn SettingExpressionQueries>;
        let front=front("var/const/value=unknown+1\n",&host);let context=front.original_declaration_expression_context().unwrap();
        let tree=&front.snapshot.tree;let owner=dm_ir::SymbolId::of("/");let name=dm_ir::SymbolId::of("value");let id=tree.resolve(tree.lookup_type(owner).unwrap(),name,crate::MemberKind::Var).unwrap();let metadata=&tree.member(id).unwrap().metadata;
        let mut root=None;context.with_admission(&mut|a|{let _frame=a.evaluation_frame().map_err(BodySyntaxFailure::Operational)?;root=Some(context.selected_admitted(owner,name,metadata,a)?.prepare(a)?);Ok(())}).unwrap();
        let warm=context.selected(owner,name,metadata).unwrap().expression().unwrap();assert!(root.unwrap().same_root(&warm));
    }

    #[test]
    fn complete_issued_declaration_ordinals_reuse_private_original_roots_and_refuse_foreign_frame() {
        let host=Arc::new(OriginalHost(Arc::new(AtomicUsize::new(0)))) as Arc<dyn SettingExpressionQueries>;
        let text="/datum/probe\n    var/static/value=1+2\n/proc/no_body()\n    return 1\n";
        let current=front(text,&host);
        let declarations=crate::initializers::capture_declaration_plan(&current.snapshot,&current.emission_order).unwrap();
        let original=current.original_initializer_input(&declarations,0).unwrap().expression().unwrap();
        let draft=crate::initializers::capture_declaration_draft(&current.snapshot,&current.emission_order).unwrap();
        let issued=crate::initializers::finish_declaration_draft_issued(draft,&current,std::iter::empty()).unwrap();
        let context=current.original_issued_initializer_context(&issued).unwrap();
        let input=context.input(0).unwrap();
        assert!(std::ptr::eq(input.original_write(),&issued.plan().writes[0]));
        assert!(input.source_static_receipt().is_none(),"complete declaration row has no static producer");
        let root=input.expression().unwrap();
        assert!(original.same_root(&root));
        current.original_declaration_expression_context().unwrap().require_initializer(&input).unwrap();
        assert!(context.input(1).is_err());
        let other=front(text,&host);
        assert!(other.original_issued_initializer_context(&issued).is_err(),"equal text cannot promote another actual body/code frame");
    }

    struct StaticIncludes{q:String}
    impl dm_preprocess::SourceProvider for StaticIncludes{fn read(&self,path:&Path)->Result<String,String>{Ok(match path.file_name().and_then(|x|x.to_str()){Some("p.dm")=>"var/static/before=1+2\n/proc/p()\n    if(1)\n        var/static/value = 3+4\n        var/static/list/items[2+1][][4+1]\n    return value\nvar/static/after=5+6\n".into(),Some("q.dm")=>self.q.clone(),_=>"#include \"q.dm\"\n#include \"p.dm\"\n".into()})}}
    fn static_front(state:&mut RetainedSemanticTree,q:String,host:&Arc<dyn SettingExpressionQueries>)->ColdFrontend{
      let executor=dm_exec::BuildExecutor::new(1).unwrap();
      build_with_executor_and_semantic_state(Path::new("complete-static.dme"),&StaticIncludes{q},&Default::default(),FrontendConfig{workers:1,engine:None,observer:None},None,&executor,Some(state)).unwrap().with_setting_expression_queries(host).unwrap()
    }
    fn static_identity(front:&ColdFrontend,body:&BodyOccurrence)->dm_ir::ProcedureIdentity{
      let member=front.snapshot.tree.member(body.member).unwrap();dm_ir::ProcedureIdentity{owner:front.snapshot.tree.type_node(member.owner).unwrap().path,name:member.name,verb:false,occurrence:front.snapshot.tree.member_occurrence(body.member).unwrap()}
    }
    #[test]
    fn complete_static_source_shares_actual_var_rhs_and_projects_same_parent_across_prefix_rebind(){
      let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let host=Arc::new(OriginalHost(counter.clone())) as Arc<dyn SettingExpressionQueries>;
      let mut state=RetainedSemanticTree::default();
      let front=static_front(&mut state,q_chunk("",1),&host);let arena=BodyArena::new_typed(&front,|_|true);
      let body=front.bodies.iter().find(|body|front.snapshot.tree.member(body.member).unwrap().name==dm_ir::SymbolId::of("p")).unwrap();
      let (receipt,parent)=arena.with_parsed_checked(body,|parsed|(parsed.capture_stored_declarations(static_identity(&front,body)).unwrap(),parsed.shared_statement_body().unwrap())).unwrap();
      let draft=crate::initializers::capture_declaration_draft(&front.snapshot,&front.emission_order).unwrap();
      let issued=crate::initializers::finish_declaration_draft_issued(draft,&front,[(body.declaration,&receipt)]).unwrap();
      assert_eq!(issued.plan().writes.len(),4,"complete ordinals interleave declarations and stored procedure rows");
      let context=front.original_issued_initializer_context(&issued).unwrap();let input=context.input(1).unwrap();assert!(Arc::ptr_eq(&input.source_static_receipt().unwrap(),&receipt),"exact same actual producer receipt, no plan scan");let root=input.expression().unwrap();
      let dm_syntax::StatementKind::If{then_branch,..}=&parent.parsed().statements[0].kind else{panic!("original if")};
      let dm_syntax::StatementKind::Var{value:Some(original),..}=&then_branch[0].kind else{panic!("original static Var")};
      assert!(std::ptr::eq(root.ast(),original));assert_eq!(root.source_text(root.ast().span),Some("3+4"));assert!(root.flat_source().is_none());
      let dimension=context.dimension_input(2,0).unwrap().expression().unwrap();let dimension_pointer=dimension.ast() as *const dm_syntax::Expr;let dimension_recipe=dimension.into_recipe();
      let canonical=receipt.canonical_declarations().unwrap();let data=canonical.iter().find(|row|row.identity.name==dm_ir::SymbolId::of("value")).unwrap();
      let declarations=input.declaration_context();declarations.require_initializer(&input).unwrap();
      let mut selected=None;declarations.with_admission(&mut|a|{selected=Some(declarations.selected_static_admitted(&receipt,data.identity,data,a)?.prepare(a)?);Ok(())}).unwrap();
      assert!(root.same_root(&selected.unwrap()),"nested static source uses SAME canonical Var RHS");
      let copied=data.as_ref().clone();declarations.with_admission(&mut|a|{assert!(declarations.selected_static_admitted(&receipt,copied.identity,&copied,a).is_err(),"equal cloned metadata cannot issue static source");Ok(())}).unwrap();
      let calls=std::cell::Cell::new(0);let stop=||{let n=calls.get()+1;calls.set(n);if n==2{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}};let failed=dm_syntax::SettingAdmission::new(&counter,128*1024*1024,&stop);
      let error=declarations.selected_static_admitted(&receipt,data.identity,data,&failed).err().expect("actual bounded row poll");assert!(matches!(error,BodySyntaxFailure::Operational(ref actual) if actual.raw_os_error()==Some(1450)));
      let aliases=Arc::strong_count(&parent);let provenance=root.provenance();assert_eq!(Arc::strong_count(&parent),aliases,"static provenance retains no parent/AST strong alias");assert_eq!(provenance.weak_backing_charge(),std::mem::size_of::<StatementBody>());
      let recipe=root.into_recipe();let relative=receipt.relative_payload().unwrap();
      let padded=static_front(&mut state,q_chunk("// current prefix\n\n",333),&host);
      let current_body=padded.bodies.iter().find(|body|padded.snapshot.tree.member(body.member).unwrap().name==dm_ir::SymbolId::of("p")).unwrap();
      let rebound=relative.bind(&padded,current_body).unwrap();
      let draft=crate::initializers::capture_declaration_draft(&padded.snapshot,&padded.emission_order).unwrap();
      let current=crate::initializers::finish_declaration_draft_issued(draft,&padded,[(current_body.declaration,&rebound)]).unwrap();
      let current_context=padded.original_issued_initializer_context(&current).unwrap();let current_input=current_context.input(1).unwrap();
      let warm=recipe.reborrow(&current_input).unwrap().unwrap();assert!(std::ptr::eq(warm.ast(),original));assert_eq!(warm.source_text(warm.ast().span),Some("3+4"));assert_eq!(&padded.expanded.text[warm.current_span().range()],"3+4");assert_ne!(warm.current_span(),warm.ast().span);
      let warm_dimension=dimension_recipe.reborrow_dimension(&current_context.dimension_input(2,0).unwrap()).unwrap().unwrap();assert_eq!(warm_dimension.ast() as *const dm_syntax::Expr,dimension_pointer);assert_eq!(warm_dimension.source_text(warm_dimension.ast().span),Some("2+1"));assert_eq!(&padded.expanded.text[warm_dimension.current_span().range()],"2+1");
      let current_declarations=current_input.declaration_context();let mut selected_current=None;current_declarations.with_admission(&mut|a|{selected_current=Some(current_declarations.selected_static_admitted(&rebound,data.identity,data,a)?);Ok(())}).unwrap();let selected_current=selected_current.unwrap();current_declarations.with_admission(&mut|a|{assert!(provenance.matches_declaration(&selected_current,a)?);Ok(())}).unwrap();let selected_warm=recipe.reborrow_declaration(&selected_current).unwrap().unwrap();assert!(std::ptr::eq(selected_warm.ast(),original));assert_eq!(selected_warm.current_span(),warm.current_span());
      assert!(padded.original_issued_initializer_context(&issued).is_err(),"body source frame cannot be supplied by old complete plan");
      let check=||Ok(());let other=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=dm_syntax::SettingAdmission::new(&other,128*1024*1024,&check);
      assert!(matches!(current_input.prepare(&a),Err(BodySyntaxFailure::Operational(ref e)) if e.kind()==std::io::ErrorKind::InvalidInput));
      assert!(std::ptr::eq(current_input.expression().unwrap().ast(),original),"foreign counter refusal cannot replace original parent");
    }

    #[test]
    fn original_header_dimensions_are_distinct_authored_roots_in_same_slot_family(){
      let host=Arc::new(OriginalHost(Arc::new(AtomicUsize::new(0)))) as Arc<dyn SettingExpressionQueries>;
      let front=front("var/static/list/value[1 + 2][][3 / 2]=null\n",&host);
      let plan=crate::initializers::capture_declaration_plan(&front.snapshot,&front.emission_order).unwrap();let context=front.original_initializer_context(&plan).unwrap();
      let rhs=context.input(0).unwrap().expression().unwrap();let first=context.dimension_input(0,0).unwrap();let root=first.expression().unwrap();
      assert_eq!(root.source_text(root.ast().span),Some("1 + 2"));assert!(!rhs.same_root(&root));
      assert!(context.dimension_input(0,1).is_err(),"empty suffix has no synthesized expression");assert!(context.dimension_input(0,3).is_err());
      let second=context.dimension_input(0,2).unwrap().expression().unwrap();assert_eq!(second.source_text(second.ast().span),Some("3 / 2"));assert!(!root.same_root(&second));
      let recipe=root.into_recipe();let warm=recipe.reborrow_dimension(&first).unwrap().unwrap();assert!(std::ptr::eq(warm.ast(),first.expression().unwrap().ast()));
      assert!(recipe.reborrow(&context.input(0).unwrap()).unwrap().is_none(),"dimension source cannot masquerade as the write RHS");
      let check=||Ok(());let other=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=dm_syntax::SettingAdmission::new(&other,128*1024*1024,&check);
      assert!(matches!(first.prepare(&a),Err(BodySyntaxFailure::Operational(ref e)) if e.kind()==std::io::ErrorKind::InvalidInput));
      assert_eq!(first.expression().unwrap().source_text(warm.ast().span),Some("1 + 2"));
    }
    #[test]
    fn complete_static_dimensions_borrow_primary_ledger_roots_without_rhs_reparse(){
      let host=Arc::new(OriginalHost(Arc::new(AtomicUsize::new(0)))) as Arc<dyn SettingExpressionQueries>;
      let source=Source(dm_preprocess::AcquiredSource::from_original_bytes(b"/proc/p()\n    var/static/list/value[2 + 1][][4 + 1]\n    return value\n".to_vec(),()));
      let front=build(Path::new("static-dimensions.dme"),&source,&Default::default(),1).unwrap().with_setting_expression_queries(&host).unwrap();let body=&front.bodies[0];let arena=BodyArena::new_typed(&front,|_|true);
      let (receipt,parent)=arena.with_parsed_checked(body,|parsed|(parsed.capture_stored_declarations(static_identity(&front,body)).unwrap(),parsed.shared_statement_body().unwrap())).unwrap();
      let draft=crate::initializers::capture_declaration_draft(&front.snapshot,&front.emission_order).unwrap();let issued=crate::initializers::finish_declaration_draft_issued(draft,&front,[(body.declaration,&receipt)]).unwrap();let context=front.original_issued_initializer_context(&issued).unwrap();
      let first=context.dimension_input(0,0).unwrap().expression().unwrap();let second=context.dimension_input(0,2).unwrap().expression().unwrap();
      let row=&parent.parsed().local_variables.entries().unwrap()[0];let array=&row.array_syntax.as_ref().unwrap().root;
      assert!(std::ptr::eq(first.ast(),&array.dimensions[array.dimension_slots[0].unwrap()]));assert!(std::ptr::eq(second.ast(),&array.dimensions[array.dimension_slots[2].unwrap()]));
      assert_eq!(first.source_text(first.ast().span),Some("2 + 1"));assert_eq!(second.source_text(second.ast().span),Some("4 + 1"));assert!(context.dimension_input(0,1).is_err());
      assert!(context.input(0).is_err(),"implicit array allocation is distinct from an authored RHS");
    }

    #[test]
    fn native_dimension_cursor_visits_original_header_once_and_uses_direct_slots(){
      let host=Arc::new(OriginalHost(Arc::new(AtomicUsize::new(0)))) as Arc<dyn SettingExpressionQueries>;
      let count=128;let source=format!("var/static/list/value{}\n","[1 + 2]".repeat(count));let front=front(&source,&host);
      let plan=crate::initializers::capture_declaration_plan(&front.snapshot,&front.emission_order).unwrap();assert!(matches!(plan.plan().writes[0].value,InitializerValue::ArrayAllocation(_)),"fixture must retain its implicit no-RHS allocation");let context=front.original_initializer_context(&plan).unwrap();
      crate::procedure::reset_array_dimension_steps();let mut pointers=Vec::new();
      for row in context.dimensions(0).unwrap(){let(index,input)=row.unwrap();assert_eq!(index,pointers.len());let root=input.unwrap().expression().unwrap();assert_eq!(root.source_text(root.ast().span),Some("1 + 2"));pointers.push(root.ast() as *const dm_syntax::Expr);}
      assert_eq!(pointers.len(),count);let first=crate::procedure::array_dimension_steps();assert!(first<count*16,"one suffix grammar pass, not a full header pass per dimension: {first}");
      crate::procedure::reset_array_dimension_steps();for row in context.dimensions(0).unwrap(){let(index,input)=row.unwrap();let root=input.unwrap().expression().unwrap();assert_eq!(root.ast() as *const dm_syntax::Expr,pointers[index]);}
      assert_eq!(crate::procedure::array_dimension_steps(),first,"warm enumeration is likewise one source pass; roots stay original");
    }

    #[test]
    fn dimension_source_does_not_treat_path_component_as_as_annotation(){
      let host=Arc::new(OriginalHost(Arc::new(AtomicUsize::new(0)))) as Arc<dyn SettingExpressionQueries>;
      let front=front("var/static/list/as[1+2]\n",&host);let plan=crate::initializers::capture_declaration_plan(&front.snapshot,&front.emission_order).unwrap();assert!(matches!(plan.plan().writes[0].value,InitializerValue::ArrayAllocation(_)),"fixture must retain its implicit no-RHS allocation");let context=front.original_initializer_context(&plan).unwrap();
      let rows=context.dimensions(0).unwrap().collect::<Result<Vec<_>,_>>().unwrap();assert_eq!(rows.len(),1);let root=rows[0].1.as_ref().unwrap().expression().unwrap();assert_eq!(root.source_text(root.ast().span),Some("1+2"));
    }

    #[test]
    fn implicit_array_terminator_at_ancestor_end_keeps_original_dimension_owner(){
      let host=Arc::new(OriginalHost(Arc::new(AtomicUsize::new(0)))) as Arc<dyn SettingExpressionQueries>;
      let source="/datum/source_probe\n    var/value=7\n    var/list/items[2+1]\n/datum/source_probe/proc/read_value()\n    return 1\n";
      let current=front(source,&host);let plan=crate::initializers::capture_declaration_plan(&current.snapshot,&current.emission_order).unwrap();
      let ordinal=plan.plan().writes.iter().position(|write|matches!(write.value,InitializerValue::ArrayAllocation(_))).unwrap();
      let context=current.original_initializer_context(&plan).unwrap();let rows=context.dimensions(ordinal).unwrap().collect::<Result<Vec<_>,_>>().unwrap();assert_eq!(rows.len(),1);
      let input=rows[0].1.as_ref().unwrap();let first=input.expression().unwrap();assert_eq!(first.source_text(first.ast().span),Some("2+1"));let warm=input.expression().unwrap();assert!(first.same_root(&warm));
      assert!(context.input(ordinal).is_err(),"genuine no-RHS allocation remains distinct from an authored initializer");
    }

    fn provenance_selected(front:&ColdFrontend)->OriginalDeclarationExpressionInput<'_>{
      let owner=dm_ir::SymbolId::of("/");let name=dm_ir::SymbolId::of("value");let tree=&front.snapshot.tree;let member=tree.resolve(tree.lookup_type(owner).unwrap(),name,crate::MemberKind::Var).unwrap();front.original_declaration_expression_context().unwrap().selected(owner,name,&tree.member(member).unwrap().metadata).unwrap()
    }
    #[test]
    fn original_root_provenance_keeps_no_ast_and_foreign_equal_owner_declines_before_prepare(){
      let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let host=Arc::new(OriginalHost(counter.clone())) as Arc<dyn SettingExpressionQueries>;
      let provenance={let current=front("var/const/value=unknown+1\n",&host);let input=provenance_selected(&current);let root=input.expression().unwrap();let backing=root.provenance_weak_backing_charge();let provenance=root.provenance();assert_eq!(provenance.weak_backing_charge(),backing);let check=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,128*1024*1024,&check);assert!(provenance.matches_declaration(&input,&a).unwrap());assert!(provenance.weak_backing_charge()>0);let mut buffers=Vec::new();provenance.visit_storage(|address,bytes|buffers.push((address,bytes)));assert_eq!(buffers.len(),1);assert_eq!(buffers[0].1,provenance.weak_backing_charge());provenance};
      assert_eq!(counter.load(std::sync::atomic::Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes(),"weak provenance does not retain original AST/slot lease after actual source owner drops");
      let foreign=front("var/const/value=unknown+1\n",&host);let input=provenance_selected(&foreign);let before=counter.load(std::sync::atomic::Ordering::Acquire);let check=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,128*1024*1024,&check);assert!(!provenance.matches_declaration(&input,&a).unwrap());assert_eq!(counter.load(std::sync::atomic::Ordering::Acquire),before,"equal-text foreign owner decline cannot parse/allocate a replacement root");
      let current=input.prepare(&a).unwrap();let current=current.provenance();assert!(current.matches_declaration(&input,&a).unwrap());
      let other=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let foreign_counter=dm_syntax::SettingAdmission::new(&other,128*1024*1024,&check);assert!(matches!(current.matches_declaration(&input,&foreign_counter),Err(BodySyntaxFailure::Operational(ref error))if error.kind()==std::io::ErrorKind::InvalidInput));
      let stop=||Err(std::io::Error::from_raw_os_error(1450));let stopped=dm_syntax::SettingAdmission::new(&counter,128*1024*1024,&stop);assert!(matches!(current.matches_declaration(&input,&stopped),Err(BodySyntaxFailure::Operational(ref error))if error.raw_os_error()==Some(1450)));assert!(current.matches_declaration(&input,&a).unwrap());
    }
    #[test]
    fn original_root_provenance_reissues_same_header_slot_across_current_prefix_mapping(){
      let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let host=Arc::new(OriginalHost(counter.clone())) as Arc<dyn SettingExpressionQueries>;let mut state=RetainedSemanticTree::default();let old=included(&mut state,&host,q_chunk("",1));let first=provenance_selected(&old).expression().unwrap();let pointer=first.ast() as *const dm_syntax::Expr;let span=first.current_span();let provenance=first.provenance();drop(first);
      let current=included(&mut state,&host,q_chunk("// changed earlier include\n\n",333));let input=provenance_selected(&current);let check=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,128*1024*1024,&check);assert!(provenance.matches_declaration(&input,&a).unwrap());let warm=input.prepare(&a).unwrap();assert_eq!(warm.ast() as *const dm_syntax::Expr,pointer);assert_ne!(warm.current_span(),span);assert_eq!(&current.expanded.text[warm.current_span().range()],"1+2");
    }

    #[test]
    fn original_root_provenance_reissues_actual_private_rhs_and_distinct_dimension_inputs(){
      let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let host=Arc::new(OriginalHost(counter.clone())) as Arc<dyn SettingExpressionQueries>;let current=front("var/static/list/value[1+2][][3+4]=null\n",&host);let plan=crate::initializers::capture_declaration_plan(&current.snapshot,&current.emission_order).unwrap();let context=current.original_initializer_context(&plan).unwrap();let rhs=context.input(0).unwrap();let dimension=context.dimension_input(0,0).unwrap();let other=context.dimension_input(0,2).unwrap();let check=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,128*1024*1024,&check);
      let rhs_root=rhs.prepare(&a).unwrap().provenance();let dimension_root=dimension.prepare(&a).unwrap().provenance();assert!(rhs_root.matches_initializer(&rhs,&a).unwrap());assert!(dimension_root.matches_dimension(&dimension,&a).unwrap());let before=counter.load(std::sync::atomic::Ordering::Acquire);assert!(!rhs_root.matches_dimension(&dimension,&a).unwrap());assert!(!dimension_root.matches_initializer(&rhs,&a).unwrap());assert!(!dimension_root.matches_dimension(&other,&a).unwrap());assert_eq!(counter.load(std::sync::atomic::Ordering::Acquire),before,"wrong role/suffix declines before preparing a different original root");
    }


    #[test]
    fn original_scalar_selector_reuses_authored_versions_and_preserves_declared_effective_outcomes(){
        use crate::constant_resolution::{self as scalar,ScalarQuery};
        let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let host=Arc::new(OriginalHost(Arc::clone(&counter))) as Arc<dyn SettingExpressionQueries>;
        let text="/datum/scalar_base\n    var/const/value=1+2\n/datum/scalar_child\n    parent_type=/datum/scalar_base\n    value=4+5\n/datum/scalar_leaf\n    parent_type=/datum/scalar_child\n/proc/no_body()\n    return 0\n";
        let provider=Source(dm_preprocess::AcquiredSource::from_original_bytes(text.as_bytes().to_vec(),()));
        let executor=dm_exec::BuildExecutor::new(1).unwrap();
        let frontend=build_with_executor_and_semantic_state_for_policy_checked(Path::new("original-scalar-source.dme"),&provider,&Default::default(),FrontendConfig{workers:1,engine:None,observer:None},None,&executor,None,true,&host).unwrap().with_body_queries(Arc::new(NoBody));
        let requests=[
            ScalarQuery::Const{owner:dm_ir::SymbolId::of("/datum/scalar_base"),name:dm_ir::SymbolId::of("value")},
            ScalarQuery::DeclaredDefault{owner:dm_ir::SymbolId::of("/datum/scalar_child"),name:dm_ir::SymbolId::of("value")},
            ScalarQuery::EffectiveDefault{owner:dm_ir::SymbolId::of("/datum/scalar_child"),name:dm_ir::SymbolId::of("value")},
            ScalarQuery::EffectiveDefault{owner:dm_ir::SymbolId::of("/datum/scalar_leaf"),name:dm_ir::SymbolId::of("value")},
        ];
        let decode=|_:&dm_syntax::LiteralText|None;let nameof=|_:&dm_syntax::Expr|None;
        let old=scalar::resolve_with_predefined_and_calls(&frontend.snapshot,&requests,&scalar::ScalarBackend{identity:711,decode_string:&decode,nameof:&nameof},None,None);
        let current=scalar::resolve_original_pinned_with_artifacts(&frontend,&requests,711,decode,nameof,None,None,None).unwrap();
        assert_eq!(old.outcomes,current.outcomes);assert_eq!(old.dependencies,current.dependencies);
        assert!(matches!(current.outcome(requests[0]),Some(scalar::ScalarOutcome::Value(_))));
        assert_eq!(current.outcome(requests[0]),current.outcome(requests[1]));
        assert_eq!(current.outcome(requests[2]),current.outcome(requests[3]));
        assert_ne!(current.outcome(requests[1]),current.outcome(requests[2]));
        let plan=crate::initializers::capture_declaration_plan(&frontend.snapshot,&frontend.emission_order).unwrap();
        let before=plan.plan().writes.iter().enumerate().filter_map(|(ordinal,write)|matches!(write.value,dm_ir::InitializerValue::Expression(_)).then_some(ordinal)).map(|ordinal|frontend.original_initializer_input(&plan,ordinal).unwrap().expression().unwrap()).collect::<Vec<_>>();
        let used=counter.load(std::sync::atomic::Ordering::Acquire);
        let warm=scalar::resolve_original_pinned_with_artifacts(&frontend,&requests,711,decode,nameof,None,None,None).unwrap();
        assert_eq!(warm.outcomes,current.outcomes);assert_eq!(counter.load(std::sync::atomic::Ordering::Acquire),used,"same original slots and target grouping remain warm");
        for (ordinal,write) in plan.plan().writes.iter().enumerate(){if matches!(write.value,dm_ir::InitializerValue::Expression(_)){let root=frontend.original_initializer_input(&plan,ordinal).unwrap().expression().unwrap();assert!(before.iter().any(|old|old.same_root(&root)));}}
    }

    #[test]
    fn original_scalar_source_prefers_equal_authored_override_and_only_follows_genuine_no_rhs(){
        use crate::constant_resolution::{self as scalar,ScalarQuery};
        for authored in [true,false]{
            let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let host=Arc::new(OriginalHost(counter)) as Arc<dyn SettingExpressionQueries>;
            let text=if authored{"/datum/scalar_origin\n    var/static/value=1+2\n/datum/scalar_origin\n    value=1+2\n/proc/no_body()\n    return 0\n"}else{"/datum/scalar_origin\n    value=1+2\n/datum/scalar_origin\n    var/static/value\n/proc/no_body()\n    return 0\n"};
            let provider=Source(dm_preprocess::AcquiredSource::from_original_bytes(text.as_bytes().to_vec(),()));let executor=dm_exec::BuildExecutor::new(1).unwrap();
            let frontend=build_with_executor_and_semantic_state_for_policy_checked(Path::new("scalar-authored-origin.dme"),&provider,&Default::default(),FrontendConfig{workers:1,engine:None,observer:None},None,&executor,None,true,&host).unwrap().with_body_queries(Arc::new(NoBody));
            let plan=crate::initializers::capture_declaration_plan(&frontend.snapshot,&frontend.emission_order).unwrap();
            let authored_rows=plan.plan().writes.iter().enumerate().filter_map(|(i,w)|matches!(w.value,dm_ir::InitializerValue::Expression(_)).then_some(i)).collect::<Vec<_>>();
            assert!(!authored_rows.is_empty());if authored{assert_eq!(authored_rows.len(),2)}
            let expected=frontend.original_initializer_input(&plan,*authored_rows.last().unwrap()).unwrap().expression().unwrap();
            let roots=||{let mut roots=Vec::new();for chunk in frontend.issued_syntax.chunks().iter(){chunk.shared_relative().visit_setting_roots(|root|roots.push(root.original_expression() as *const dm_syntax::Expr as usize));}roots.sort_unstable();roots.dedup();roots};
            let before=roots();assert_eq!(before.len(),1,"only the expected non-const original RHS is prepared before selection");assert!(before.contains(&(expected.ast() as *const dm_syntax::Expr as usize)));
            let request=ScalarQuery::EffectiveDefault{owner:dm_ir::SymbolId::of("/datum/scalar_origin"),name:dm_ir::SymbolId::of("value")};let decode=|_:&dm_syntax::LiteralText|None;let nameof=|_:&dm_syntax::Expr|None;
            let old=scalar::resolve_with_predefined_and_calls(&frontend.snapshot,&[request],&scalar::ScalarBackend{identity:712,decode_string:&decode,nameof:&nameof},None,None);
            assert!(matches!(old.outcome(request),Some(scalar::ScalarOutcome::Value(_))),"actual old policy supplies inherited/equal-authored scalar");
            let native=scalar::resolve_original_pinned_with_artifacts(&frontend,&[request],712,decode,nameof,None,None,None).unwrap();assert_eq!(old.outcomes,native.outcomes);assert_eq!(before,roots(),"actual selected physical original root was already warmed; equal token text cannot select another slot");
            if authored{let original=frontend.original_initializer_input(&plan,authored_rows[0]).unwrap().expression().unwrap();assert!(!original.same_root(&expected),"equal authored RHS versions retain distinct original source slots");}
        }
    }
}

#[cfg(test)]mod original_admission_completion_tests{
 use super::*;use std::sync::{Arc,atomic::{AtomicUsize,AtomicBool,Ordering}};
 #[derive(Debug,Clone,Copy)]enum Mode{Once,Omit,Repeat,Swallow,LaterIo}
 #[derive(Debug)]struct Provider{mode:Mode,counter:Arc<dm_syntax::SettingChargeCounter>,cancel:AtomicBool}
 impl SettingExpressionQueries for Provider{
  fn expression(&self,_:&super::super::SettingExpressionInput<'_>)->Result<dm_syntax::SettingExpression,BodySyntaxFailure>{panic!("resource loan must never demand a new expression")}
  fn with_declaration_admission(&self,callback:&mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>)->Result<(),BodySyntaxFailure>{
   let checkpoint=||if self.cancel.load(Ordering::Acquire){Err(std::io::ErrorKind::Interrupted.into())}else{Ok(())};let admission=dm_syntax::SettingAdmission::new(&self.counter,1<<20,&checkpoint);
   match self.mode{Mode::Omit=>Ok(()),Mode::Once=>callback(&admission),Mode::Swallow=>{let _=callback(&admission);Ok(())},Mode::Repeat=>{let _=callback(&admission);let _=callback(&admission);Ok(())},Mode::LaterIo=>{let _=callback(&admission);Err(BodySyntaxFailure::Operational(std::io::Error::from_raw_os_error(1450)))}}
  }
 }
 fn provider(mode:Mode)->(Arc<Provider>,std::sync::Weak<dyn SettingExpressionQueries>){let actual=Arc::new(Provider{mode,counter:Arc::new(AtomicUsize::new(0)),cancel:AtomicBool::new(false)});let erased:Arc<dyn SettingExpressionQueries>=actual.clone();(actual,Arc::downgrade(&erased))}
 #[test]fn original_admission_callback_completes_exactly_once_and_does_not_invent_missing_success(){
  for mode in[Mode::Omit,Mode::Repeat]{let(_owner,weak)=provider(mode);let result=original_admission_using(Some(&weak),|_|Ok(17));assert!(matches!(result,Err(BodySyntaxFailure::Operational(ref actual))if actual.kind()==std::io::ErrorKind::InvalidData));}
  let(owner,weak)=provider(Mode::Once);assert_eq!(original_admission_using(Some(&weak),|_|Ok(17)).unwrap(),17);drop(owner);let result:Result<(),BodySyntaxFailure>=original_admission_using(Some(&weak),|_|panic!("expired provider must not run"));assert!(matches!(result,Err(BodySyntaxFailure::Operational(ref actual))if actual.kind()==std::io::ErrorKind::NotConnected));
 }
 #[test]fn original_admission_first_actual_io_survives_swallow_repeat_and_later_provider_io(){
  for mode in[Mode::Swallow,Mode::Repeat,Mode::LaterIo]{let(_owner,weak)=provider(mode);let result:Result<(),_>=original_admission_using(Some(&weak),|_|Err(BodySyntaxFailure::Operational(std::io::Error::from_raw_os_error(112))));assert!(matches!(result,Err(BodySyntaxFailure::Operational(ref actual))if actual.raw_os_error()==Some(112)));}
  let(_owner,weak)=provider(Mode::LaterIo);let result=original_admission_using(Some(&weak),|_|Ok(17));assert!(matches!(result,Err(BodySyntaxFailure::Operational(ref actual))if actual.raw_os_error()==Some(1450)));
 }
 #[test]fn original_admission_final_poll_preserves_actual_cancel_and_drops_returned_storage(){
  let(owner,weak)=provider(Mode::Once);let result=original_admission_using(Some(&weak),|a|{let lease=a.reserve(256).map_err(BodySyntaxFailure::Operational)?;owner.cancel.store(true,Ordering::Release);Ok(lease)});assert!(matches!(result,Err(BodySyntaxFailure::Operational(ref actual))if actual.kind()==std::io::ErrorKind::Interrupted));assert_eq!(owner.counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());owner.cancel.store(false,Ordering::Release);assert_eq!(original_admission_using(Some(&weak),|_|Ok(17)).unwrap(),17);
 }
}
