//! Exact original declaration RHS source; additive and NOT selected by native
//! classification until typed initializer operational transport is complete.
use super::*;
use dm_ir::{InitializerValue, SymbolicExpression};

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
 Header{owner:std::sync::Weak<crate::procedure::OriginalProcedureHeaders>,value:dm_syntax::Span,ordinal:usize,count:usize},
 Static,
}
impl OriginalInitializerRecipe{
 fn matches_header(&self,i:&relative_declarations::OriginalInitializerTokenInput<'_>)->bool{match self{Self::Header{owner,value,ordinal,count}=>std::sync::Weak::ptr_eq(owner,&Arc::downgrade(i.owner))&&*value==i.value&&*ordinal==i.ordinal&&*count==i.count,Self::Static=>false}}
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
        let i=&input.input;
        if !self.recipe.matches_header(i){return Ok(None)}
        let current=input.expression()?;
        if !self.root.same_root(&current.root){return Ok(None)}
        Ok(Some(current))
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
          (OriginalInitializerSource::Header(i),OriginalInitializerRoot::Header(root))=>root.current_offset()==i.offset&&result.source.same_view(i.source)&&i.slots.contains_original(i.ordinal,root),
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
        let result = i
            .slots
            .obtain(i.ordinal, i.count, a, || {
                dm_syntax::prepare_setting_expression(i.source, i.tokens, i.value, a)
            })
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
            },
        })
}
/// SAME original token/root base as declaration-plan inputs, issued from an
/// actual selected variable instead of an adapted initializer write. No plan
/// scan or copied meaning/source can create this private receipt.
pub struct OriginalDeclarationExpressionInput<'source> {
    frontend:&'source ColdFrontend,
    expression:&'source SymbolicExpression,
    input:relative_declarations::OriginalInitializerTokenInput<'source>,
}
impl std::fmt::Debug for OriginalDeclarationExpressionInput<'_>{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("OriginalDeclarationExpressionInput")}}
impl<'source> OriginalDeclarationExpressionInput<'source>{
    pub fn prepare(&self,a:&dm_syntax::SettingAdmission<'_>)->Result<OriginalInitializerExpression<'source>,BodySyntaxFailure>{
        prepare_original_expression(self.frontend,self.expression,&self.input,a)
    }
    pub fn expression(&self)->Result<OriginalInitializerExpression<'source>,BodySyntaxFailure>{
        original_declaration_admission(self.frontend,|a|self.prepare(a))
    }
}
/// Private callback shape prevents omitted/repeated host calls from issuing a
/// result. The stack capability never escapes; the returned source borrow is
/// tied to the original frontend rather than this temporary provider Arc.
fn original_declaration_admission<T>(front:&ColdFrontend,operation:impl FnOnce(&dm_syntax::SettingAdmission<'_>)->Result<T,BodySyntaxFailure>)->Result<T,BodySyntaxFailure>{
    let provider=front.setting_expression_queries.as_ref().and_then(std::sync::Weak::upgrade).ok_or_else(||BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"original declaration requires existing native expression host")))?;
    let mut operation=Some(operation);let mut completed=None;
    let outer=provider.with_declaration_admission(&mut |a|{
        let operation=operation.take().ok_or_else(||BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"original declaration admission callback repeated")))?;
        let result=operation(a);
        if matches!(&result,Err(BodySyntaxFailure::Operational(_))){return result.map(|_|())}
        let status=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}status.map_err(BodySyntaxFailure::Operational)?;
        completed=Some(result);Ok(())
    });
    outer?;
    completed.ok_or_else(||BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"original declaration admission callback omitted")))?
}
/// Once-per-wave current source join. The existing target index is admitted
/// lazily once on the SAME owner/counter; no member-to-source sibling map.
pub struct OriginalDeclarationExpressionContext<'source>{
    frontend:&'source ColdFrontend,
    mapping:&'source source_export_mapping::SourceExportMapping,
}
impl std::fmt::Debug for OriginalDeclarationExpressionContext<'_>{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("OriginalDeclarationExpressionContext")}}
impl<'source> OriginalDeclarationExpressionContext<'source>{
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
            Ok(OriginalDeclarationExpressionInput{frontend:self.frontend,expression,input})
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
    struct OriginalHost(Arc<AtomicUsize>);
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
            counter: Arc<AtomicUsize>,
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
        let counter = Arc::new(AtomicUsize::new(0));
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
                0,
                "failed allocation never mints a root/lease"
            );
            native
                .limit
                .store(128 * 1024 * 1024, std::sync::atomic::Ordering::Release);
            let first = input.expression().unwrap();
            assert!(first.same_root(&input.expression().unwrap()));
            assert!(counter.load(std::sync::atomic::Ordering::Acquire) > 0);
        }
        assert_eq!(
            counter.load(std::sync::atomic::Ordering::Acquire),
            0,
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
        let counter = Arc::new(AtomicUsize::new(0));
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
            0,
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
        let counter = Arc::new(AtomicUsize::new(0));
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
        assert_eq!(counter.load(std::sync::atomic::Ordering::Acquire), 0);
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
        let root=input.expression().unwrap();
        assert!(original.same_root(&root));
        current.original_declaration_expression_context().unwrap().require_initializer(&input).unwrap();
        assert!(context.input(1).is_err());
        let other=front(text,&host);
        assert!(other.original_issued_initializer_context(&issued).is_err(),"equal text cannot promote another actual body/code frame");
    }

    struct StaticIncludes{q:String}
    impl dm_preprocess::SourceProvider for StaticIncludes{fn read(&self,path:&Path)->Result<String,String>{Ok(match path.file_name().and_then(|x|x.to_str()){Some("p.dm")=>"var/static/before=1+2\n/proc/p()\n    if(1)\n        var/static/value = 3+4\n    return value\nvar/static/after=5+6\n".into(),Some("q.dm")=>self.q.clone(),_=>"#include \"q.dm\"\n#include \"p.dm\"\n".into()})}}
    fn static_front(state:&mut RetainedSemanticTree,q:String,host:&Arc<dyn SettingExpressionQueries>)->ColdFrontend{
      let executor=dm_exec::BuildExecutor::new(1).unwrap();
      build_with_executor_and_semantic_state(Path::new("complete-static.dme"),&StaticIncludes{q},&Default::default(),FrontendConfig{workers:1,engine:None,observer:None},None,&executor,Some(state)).unwrap().with_setting_expression_queries(host).unwrap()
    }
    fn static_identity(front:&ColdFrontend,body:&BodyOccurrence)->dm_ir::ProcedureIdentity{
      let member=front.snapshot.tree.member(body.member).unwrap();dm_ir::ProcedureIdentity{owner:front.snapshot.tree.type_node(member.owner).unwrap().path,name:member.name,verb:false,occurrence:front.snapshot.tree.member_occurrence(body.member).unwrap()}
    }
    #[test]
    fn complete_static_source_shares_actual_var_rhs_and_projects_same_parent_across_prefix_rebind(){
      let counter=Arc::new(AtomicUsize::new(0));let host=Arc::new(OriginalHost(counter.clone())) as Arc<dyn SettingExpressionQueries>;
      let mut state=RetainedSemanticTree::default();
      let front=static_front(&mut state,q_chunk("",1),&host);let arena=BodyArena::new_typed(&front,|_|true);
      let body=front.bodies.iter().find(|body|front.snapshot.tree.member(body.member).unwrap().name==dm_ir::SymbolId::of("p")).unwrap();
      let (receipt,parent)=arena.with_parsed_checked(body,|parsed|(parsed.capture_stored_declarations(static_identity(&front,body)).unwrap(),parsed.shared_statement_body().unwrap())).unwrap();
      let draft=crate::initializers::capture_declaration_draft(&front.snapshot,&front.emission_order).unwrap();
      let issued=crate::initializers::finish_declaration_draft_issued(draft,&front,[(body.declaration,&receipt)]).unwrap();
      assert_eq!(issued.plan().writes.len(),3,"complete ordinals interleave declarations and stored procedure rows");
      let context=front.original_issued_initializer_context(&issued).unwrap();let input=context.input(1).unwrap();let root=input.expression().unwrap();
      let dm_syntax::StatementKind::If{then_branch,..}=&parent.parsed().statements[0].kind else{panic!("original if")};
      let dm_syntax::StatementKind::Var{value:Some(original),..}=&then_branch[0].kind else{panic!("original static Var")};
      assert!(std::ptr::eq(root.ast(),original));assert_eq!(root.source_text(root.ast().span),Some("3+4"));assert!(root.flat_source().is_none());
      let recipe=root.into_recipe();let relative=receipt.relative_payload().unwrap();
      let padded=static_front(&mut state,q_chunk("// current prefix\n\n",333),&host);
      let current_body=padded.bodies.iter().find(|body|padded.snapshot.tree.member(body.member).unwrap().name==dm_ir::SymbolId::of("p")).unwrap();
      let rebound=relative.bind(&padded,current_body).unwrap();
      let draft=crate::initializers::capture_declaration_draft(&padded.snapshot,&padded.emission_order).unwrap();
      let current=crate::initializers::finish_declaration_draft_issued(draft,&padded,[(current_body.declaration,&rebound)]).unwrap();
      let current_context=padded.original_issued_initializer_context(&current).unwrap();let current_input=current_context.input(1).unwrap();
      let warm=recipe.reborrow(&current_input).unwrap().unwrap();assert!(std::ptr::eq(warm.ast(),original));assert_eq!(warm.source_text(warm.ast().span),Some("3+4"));assert_eq!(&padded.expanded.text[warm.current_span().range()],"3+4");assert_ne!(warm.current_span(),warm.ast().span);
      assert!(padded.original_issued_initializer_context(&issued).is_err(),"body source frame cannot be supplied by old complete plan");
      let check=||Ok(());let other=Arc::new(AtomicUsize::new(0));let a=dm_syntax::SettingAdmission::new(&other,128*1024*1024,&check);
      assert!(matches!(current_input.prepare(&a),Err(BodySyntaxFailure::Operational(ref e)) if e.kind()==std::io::ErrorKind::InvalidInput));
      assert!(std::ptr::eq(current_input.expression().unwrap().ast(),original),"foreign counter refusal cannot replace original parent");
    }

}
