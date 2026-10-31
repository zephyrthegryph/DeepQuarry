//! Exact original declaration RHS source; additive and NOT selected by native
//! classification until typed initializer operational transport is complete.
use super::*;
use dm_ir::{InitializerValue, SymbolicExpression};

/// Original source is BORROWED from its authenticated current owner. Only the
/// canonical AST root is retained, under its existing SAME-counter lease. No
/// raw source Arc, copied text or allocator role escapes through this handle.
pub struct OriginalInitializerExpression<'source> {
    root: dm_syntax::SettingExpression,
    source: &'source dm_preprocess::SourceText,
    authored: &'source SymbolicExpression,
    recipe: OriginalInitializerRecipe,
}
impl std::fmt::Debug for OriginalInitializerExpression<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("OriginalInitializerExpression")
            .field("current_span", &self.root.current_span())
            .finish_non_exhaustive()
    }
}
impl OriginalInitializerExpression<'_> {
    /// Shape is in stable original chunk coordinates. The SAME source() view
    /// indexes those spans; current diagnostic locations use current_span.
    pub fn ast(&self) -> &dm_syntax::Expr {
        self.root.original_expression()
    }
    pub fn source(&self) -> &str {
        &self.source
    }
    pub fn authored(&self) -> &SymbolicExpression {
        &self.authored
    }
    pub fn current_span(&self) -> dm_syntax::Span {
        self.root.current_span()
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
struct OriginalInitializerRecipe {
    owner: std::sync::Weak<crate::procedure::OriginalProcedureHeaders>,
    value: dm_syntax::Span,
    ordinal: usize,
    count: usize,
}
/// Owned AST-only syntax for runtime artifacts. This is NOT a source or scalar
/// evaluation receipt. Exact current input and host admission are required again
/// before any source, location, evaluation or codegen access.
#[derive(Clone)]
pub struct InitializerExpressionRecipe {
    root: dm_syntax::SettingExpression,
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
        self.root.original_expression()
    }
    pub fn same_root(&self, other: &Self) -> bool {
        self.root.same_root(&other.root)
    }
    /// Existing root lease covers its original AST allocations. Artifact callers
    /// must separately admit inline recipe/Weak coordination and standard Arc
    /// control-block overhead; this is not total heap/RSS accounting.
    pub fn retained_root_charge(&self) -> Option<usize> {
        self.root.retained_charge()
    }
    /// Exposed fixed owner payload retained by Weak, root payload and lease
    /// counter addresses. Existing syntax visitors still account AST children;
    /// live owner contents are visited by their original owning frame only.
    pub fn visit_storage(&self, mut visit: impl FnMut(usize, usize)) {
        visit(
            self.recipe.owner.as_ptr() as usize,
            std::mem::size_of::<crate::procedure::OriginalProcedureHeaders>(),
        );
        self.root.visit_root_storage(&mut visit);
        self.root.visit_retention_storage(visit);
    }
    /// None is a genuine original-owner/slot decline and performs no root parse.
    /// Actual operational refusal is Err and must never become cache miss.
    /// Exact input authenticates the current plan/origin and source first;
    /// obtaining the same warm slot then checks current host/counter/control.
    pub fn reborrow_declaration<'source>(&self,input:&OriginalDeclarationExpressionInput<'source>)->Result<Option<OriginalInitializerExpression<'source>>,BodySyntaxFailure>{
        let i=&input.input;
        if !std::sync::Weak::ptr_eq(&self.recipe.owner,&Arc::downgrade(i.owner)) || self.recipe.value!=i.value || self.recipe.ordinal!=i.ordinal || self.recipe.count!=i.count{return Ok(None)}
        let current=input.expression()?;
        if !self.root.same_root(&current.root){return Ok(None)}
        Ok(Some(current))
    }
    pub fn reborrow<'source>(
        &self,
        input: &OriginalInitializerExpressionInput<'source>,
    ) -> Result<Option<OriginalInitializerExpression<'source>>, BodySyntaxFailure> {
        let i = &input.input;
        if !std::sync::Weak::ptr_eq(&self.recipe.owner, &Arc::downgrade(i.owner))
            || self.recipe.value != i.value
            || self.recipe.ordinal != i.ordinal
            || self.recipe.count != i.count
        {
            return Ok(None);
        }
        let current = input.expression()?;
        if !self.root.same_root(&current.root) {
            return Ok(None);
        }
        Ok(Some(current))
    }
}
/// Exact original private declaration plan row. The adapted write supplied later
/// by classifier array recursion cannot issue or replace this source proof.
pub struct OriginalInitializerExpressionInput<'a> {
    frontend: &'a ColdFrontend,
    plan: &'a crate::initializers::DeclarationPlan<'a>,
    ordinal: usize,
    expression: &'a SymbolicExpression,
    input: relative_declarations::OriginalInitializerTokenInput<'a>,
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
        if result.root.current_offset() != self.input.offset
            || !result.source.same_view(self.input.source)
            || !Arc::ptr_eq(&result.authored.tokens, &self.expression.tokens)
            || !self
                .input
                .slots
                .contains_original(self.input.ordinal, &result.root)
        {
            return Err(BodySyntaxFailure::Operational(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "initializer provider returned foreign source/root/projection",
            )));
        }
        Ok(result)
    }
    pub fn prepare(&self,a:&dm_syntax::SettingAdmission<'_>)->Result<OriginalInitializerExpression<'source>,BodySyntaxFailure>{
        prepare_original_expression(self.frontend,self.expression,&self.input,a)
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
            root,
            source: i.source,
            authored: expression,
            recipe: OriginalInitializerRecipe {
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
    /// Couple a top RHS with this SAME immutable original frontend frame before
    /// any transitive declaration read. No repeated whole-source validation.
    pub fn require_initializer(&self,input:&OriginalInitializerExpressionInput<'_>)->Result<(),BodySyntaxFailure>{
        if !std::ptr::eq(self.frontend,input.frontend)
            || !std::ptr::eq(input.plan.source(),&self.frontend.snapshot)
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
    plan: &'source crate::initializers::DeclarationPlan<'source>,
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
            input,
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
            plan,
            mapping,
        })
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
                root.source()[root.ast().span.range()].trim(),
                if text.contains("/*") {
                    // Original preprocessing blanks comments without changing byte spans.
                    "1 +                2"
                } else {
                    "1+2"
                }
            );
            assert_eq!(
                &front.expanded.text[root.current_span().range()],
                &root.source()[root.ast().span.range()],
                "current expanded projection and original primary chunk agree"
            );
            let actual = dm_syntax::parse_expression(&root.source()[root.ast().span.range()]);
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
        assert_eq!(&root.source()[root.ast().span.range()], "1+2");
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
            recipe.recipe.owner.upgrade().is_none(),
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
        assert_eq!(&first.source()[first.ast().span.range()],"unknown+1");
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

}
