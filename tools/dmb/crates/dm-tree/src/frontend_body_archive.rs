//! Current parser-issued body inputs, shared without retaining a frontend revision.
use super::*;
use crate::SemanticTree;
#[path="frontend_archive_owner.rs"]mod archive_owner;
pub use archive_owner::OriginalArchiveOwner;

/// Only ColdFrontend can issue this archive. Coordinates belong to this exact
/// tree/source/syntax owner; an archive cannot be rebound to a different revision.
pub struct BodyArchive {
    body_queries: Option<body_queries::BodyQueries>,
    setting_queries: Option<std::sync::Weak<dyn SettingExpressionQueries>>,
    source: dm_preprocess::SourceText,
    syntax: Arc<DeclarationSyntax>,
    bodies: Arc<[BodyOccurrence]>,
    tree: Arc<SemanticTree>,
    declarations: Arc<crate::OccurrenceTable>,
    mapping: Arc<SourceExportMapping>,
    callables: Arc<CallableRoster>,
    body_indices: Arc<HashMap<OccurrenceId, usize>>,
    body_codes: Arc<[body_code::BodyCodeOwner]>,
    settings_owners: Arc<[Option<Arc<dm_ir::ProcedureMetadata>>]>,
}
/// Completeness receipt for a lexical annotation-name superset only. It does
/// NOT prove truth, initial-prefix position, definition chronology, inheritance
/// or final target membership. Those need their existing exact source contracts.
/// The whole original metadata roster is present; unissued is never empty.
pub struct AnnotationCandidateRoster<'a> {
    archive: &'a BodyArchive,
}
impl AnnotationCandidateRoster<'_> {
    pub fn len(&self) -> usize {
        self.archive.bodies.len()
    }
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
    pub fn occurrence(&self, ordinal: usize) -> Option<&BodyOccurrence> {
        self.archive.bodies.get(ordinal)
    }
    pub fn lexically_may_set(&self, ordinal: usize, name: dm_ir::SymbolId) -> Result<bool, String> {
        fn contains(
            nodes: &[dm_ir::ProcedureSettingNode],
            name: dm_ir::SymbolId,
            depth: usize,
        ) -> Result<bool, String> {
            if depth > 256 {
                return Err("annotation metadata depth exceeds bounded candidate walk".into());
            }
            for node in nodes {
                match node {
                    dm_ir::ProcedureSettingNode::Setting(setting) => {
                        if setting.name == name {
                            return Ok(true);
                        }
                    }
                    dm_ir::ProcedureSettingNode::Conditional {
                        then_branch,
                        else_branch,
                        ..
                    } => {
                        if contains(then_branch, name, depth + 1)?
                            || contains(else_branch, name, depth + 1)?
                        {
                            return Ok(true);
                        }
                    }
                    dm_ir::ProcedureSettingNode::UnsupportedContext { children, .. } => {
                        if contains(children, name, depth + 1)? {
                            return Ok(true);
                        }
                    }
                }
            }
            Ok(false)
        }
        let metadata = self
            .archive
            .settings_owners
            .get(ordinal)
            .and_then(Option::as_ref)
            .ok_or("annotation candidate ordinal has no original metadata receipt")?;
        contains(&metadata.settings, name, 0)
    }
}
/// Stack-only source-local authority from the SAME issued original body.
/// Owns no AST, map, index or semantic state.
#[derive(Clone, Copy)]
pub struct SourceLocalView<'a> {
    tree: &'a SemanticTree,
    occurrence: &'a BodyOccurrence,
    syntax: &'a StatementBody,
    source: &'a str,
    projection: Option<dm_syntax::SyntaxProjection>,
    scope_charge: usize,
}
impl<'a> SourceLocalView<'a> {
    pub fn require_for(
        &self,
        tree: &SemanticTree,
        occurrence: &BodyOccurrence,
        syntax: &StatementBody,
    ) -> Result<(), String> {
        if !std::ptr::eq(self.tree, tree)
            || !std::ptr::eq(self.occurrence, occurrence)
            || !std::ptr::eq(self.syntax, syntax)
        {
            return Err(
                "local source view belongs to another original tree/body/syntax owner".into(),
            );
        }
        Ok(())
    }
    pub fn entries(&self) -> Result<&'a [dm_syntax::LocalVariableSyntax], String> {
        self.syntax
            .parsed()
            .local_variables
            .entries()
            .map_err(str::to_owned)
    }
    pub fn in_span(
        &self,
        span: dm_syntax::Span,
    ) -> Result<&'a [dm_syntax::LocalVariableSyntax], String> {
        self.syntax
            .parsed()
            .local_variables
            .in_span(span)
            .map_err(str::to_owned)
    }
    fn require_entry(&self, entry: &dm_syntax::LocalVariableSyntax) -> Result<(), String> {
        let entries = self.entries()?;
        let width = std::mem::size_of::<dm_syntax::LocalVariableSyntax>();
        let offset = (entry as *const _ as usize).checked_sub(entries.as_ptr() as usize);
        if !offset.is_some_and(|offset| {
            offset % width == 0
                && entries
                    .get(offset / width)
                    .is_some_and(|actual| std::ptr::eq(actual, entry))
        }) {
            return Err("local entry is foreign to original source ledger".into());
        }
        Ok(())
    }
    pub fn name(&self, entry: &dm_syntax::LocalVariableSyntax) -> Result<&'a str, String> {
        self.require_entry(entry)?;
        self.slice(entry.name).ok_or_else(|| "local name outside original source arena".into())
    }
    pub fn type_path_width(&self,entry:&dm_syntax::LocalVariableSyntax)->Result<usize,String>{self.type_path_width_using(entry,&||Ok(()),&|error|error)}
    fn point(&self,span:dm_syntax::Span)->Option<dm_syntax::Span>{match self.projection{Some(projection)=>projection.span(span),None=>Some(span)}}
    fn slice(&self,span:dm_syntax::Span)->Option<&'a str>{self.point(span).and_then(|span|self.source.get(span.range()))}
    /// Existing in_span takes canonical syntax coordinates. This explicitly named
    /// entry translates a genuine current source window before using that ledger.
    pub fn in_current_span(&self,span:dm_syntax::Span)->Result<&'a[dm_syntax::LocalVariableSyntax],String>{let original=match self.projection{Some(projection)=>projection.inverse().span(span).ok_or("current local window escapes body binding")?,None=>span};self.in_span(original)}
    fn type_path_width_using<E>(&self,entry:&dm_syntax::LocalVariableSyntax,checkpoint:&dyn Fn()->Result<(),E>,error:&dyn Fn(String)->E)->Result<usize,E>{
      self.require_entry(entry).map_err(error)?;let mut width=if entry.array_suffix{5usize}else{0};
      for span in &entry.type_components{checkpoint()?;let text=self.slice(*span).ok_or_else(||error("local type component outside original source arena".into()))?;width=width.checked_add(text.len()).and_then(|n|n.checked_add(1)).ok_or_else(||error("original local type width overflow".into()))?;}Ok(width)
    }
    /// Conservative transient type-map admission, computed without formatting
    /// or allocating. It is not retained model data or an RSS measurement.
    pub fn scope_admission(&self) -> Result<usize, String> {
        Ok(self.scope_charge)
    }
    fn compute_scope_admission_using<E>(&self,checkpoint:&dyn Fn()->Result<(),E>,error:&dyn Fn(String)->E)->Result<usize,E>{
      let mut sum=4096usize;for entry in self.entries().map_err(error)?{checkpoint()?;let width=self.type_path_width_using(entry,checkpoint,error)?;sum=self.name(entry).map_err(error)?.len().checked_add(width).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(256)).and_then(|n|sum.checked_add(n)).ok_or_else(||error("original local scope admission overflow".into()))?;}Ok(sum)
    }
    pub fn type_path(
        &self,
        entry: &dm_syntax::LocalVariableSyntax,
    ) -> Result<Option<String>, String> {
        self.require_entry(entry)?;
        entry.type_path_using(|span|self.slice(span).ok_or("native local component source unavailable")).map_err(str::to_owned)
    }
}
pub(super) fn checked_source_locals<'a>(tree:&'a SemanticTree,occurrence:&'a BodyOccurrence,syntax:&'a StatementBody,source:&'a str)->Result<SourceLocalView<'a>,String>{
 checked_source_locals_projected(tree,occurrence,syntax,source,None,false,&||Ok(()),&|error|error)
}
pub(super) fn checked_source_locals_projected<'a,E>(tree:&'a SemanticTree,occurrence:&'a BodyOccurrence,syntax:&'a StatementBody,source:&'a str,projection:Option<dm_syntax::SyntaxProjection>,original_literals:bool,checkpoint:&dyn Fn()->Result<(),E>,error:&dyn Fn(String)->E)->Result<SourceLocalView<'a>,E>{
 checkpoint()?;
 let complete=if original_literals{syntax.original_literal_syntax_complete()}else{syntax.syntax_complete()};
 if !complete{return Err(error("local source body has unissued syntax".into()))}
 let mut view=SourceLocalView{tree,occurrence,syntax,source,projection,scope_charge:0};view.scope_charge=view.compute_scope_admission_using(checkpoint,error)?;checkpoint()?;Ok(view)
}

pub struct ArchivedBody<'a> {
    archive: &'a BodyArchive,
    occurrence: &'a BodyOccurrence,
    statements: Arc<StatementBody>,
    header: Item,
    opening_parenthesis: Option<dm_syntax::Span>,
    parameters: dm_syntax::SharedParameterSignature,
}
/// Opaque original source binding, not a table copied from runtime metadata.
/// Only an exact original body owner can issue this stack-only borrowed view.
#[derive(Clone, Copy)]
pub struct SourceParameterView<'a> {
    tree: &'a SemanticTree,
    occurrence: &'a BodyOccurrence,
    signature: &'a dm_syntax::ParameterSignature,
    source: &'a str,
    projection: Option<dm_syntax::SyntaxProjection>,
}
impl std::fmt::Debug for SourceParameterView<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SourceParameterView")
            .field("member", &self.occurrence.member)
            .field("header", &self.signature.header())
            .finish_non_exhaustive()
    }
}
impl SourceParameterView<'_> {
    pub fn require_for(
        &self,
        tree: &SemanticTree,
        occurrence: &BodyOccurrence,
    ) -> Result<(), String> {
        if !std::ptr::eq(self.tree, tree) || !std::ptr::eq(self.occurrence, occurrence) {
            return Err("parameter source view belongs to another original tree/callable".into());
        }
        Ok(())
    }
    pub fn absolute_declarations(
        &self,
    ) -> Result<&[dm_syntax::HeaderTypeDeclarationSyntax], String> {
        self.signature
            .absolute_declarations()
            .map_err(str::to_owned)
    }
    pub fn entries(&self) -> Result<&[dm_syntax::ParameterSyntax], String> {
        self.signature.entries().map_err(str::to_owned)
    }
    fn require_entry(&self, p: &dm_syntax::ParameterSyntax) -> Result<(), String> {
        if !self
            .entries()?
            .get(p.ordinal())
            .is_some_and(|actual| std::ptr::eq(actual, p))
        {
            return Err("parameter entry is foreign to original source receipt".into());
        }
        Ok(())
    }
    pub fn name(&self, p: &dm_syntax::ParameterSyntax) -> Result<&str, String> {
        self.require_entry(p)?;
        self.slice(p.name()).ok_or_else(|| "parameter name outside exact original arena".into())
    }
    /// Borrow one actual source component without allocating a normalized path.
    pub fn type_component(&self,p:&dm_syntax::ParameterSyntax,index:usize)->Result<Option<&str>,String>{self.require_entry(p)?;p.type_components().get(index).map(|span|self.slice(*span).ok_or_else(||"original parameter component outside exact source arena".into())).transpose()}
    pub fn declaration_cursor(&self,p:&dm_syntax::ParameterSyntax)->Result<dm_syntax::Span,String>{self.require_entry(p)?;let at=self.point(p.declaration_cursor()).ok_or("parameter original declaration cursor is outside the actual source")?;if at.start>at.end||self.source.get(at.range()).is_none(){return Err("parameter original declaration cursor is outside the actual source".into())}Ok(at)}
    fn point(&self,span:dm_syntax::Span)->Option<dm_syntax::Span>{match self.projection{Some(projection)=>projection.span(span),None=>Some(span)}}
    fn slice(&self,span:dm_syntax::Span)->Option<&str>{self.point(span).and_then(|span|self.source.get(span.range()))}
    pub fn header_span(&self)->Result<dm_syntax::Span,String>{self.point(self.signature.header()).ok_or_else(||"parameter header escapes current source binding".into())}
    pub fn type_path(&self, p: &dm_syntax::ParameterSyntax) -> Result<Option<String>, String> {
        self.require_entry(p)?;
        p.type_path_using(|span|self.slice(span).ok_or("original parameter component outside arena")).map_err(str::to_owned)
    }
}
/// Request-local handle for the SAME existing parameter root allocation.
/// Its frontend/occurrence references keep their original issuer lifetime;
/// cloning the Arc cannot create a copied AST or another semantic owner.
pub struct OriginalHeaderExpressionHandle<'frontend> {
    frontend: &'frontend ColdFrontend,
    occurrence: &'frontend BodyOccurrence,
    parameters: dm_syntax::SharedParameterSignature,
    metadata: &'frontend dm_ir::ProcedureMetadata,
    source: &'frontend str,
}
pub(super) fn capture_header_expression_handle<'frontend>(
    frontend: &'frontend ColdFrontend,
    occurrence: &'frontend BodyOccurrence,
    parameters: dm_syntax::SharedParameterSignature,
) -> Result<OriginalHeaderExpressionHandle<'frontend>, String> {
    // The sole caller first validates its exact ParsedBody/source-parameter
    // binding; this private constructor cannot accept a public copied receipt.
    let metadata = frontend
        .snapshot
        .tree
        .member(occurrence.member)
        .and_then(|member| member.metadata.procedure.as_deref())
        .ok_or("original header metadata unavailable")?;
    Ok(OriginalHeaderExpressionHandle {
        frontend,
        occurrence,
        parameters,
        metadata,
        source: &frontend.issued_arena,
    })
}
impl OriginalHeaderExpressionHandle<'_> {
    pub fn require_for(
        &self,
        frontend: &ColdFrontend,
        occurrence: &BodyOccurrence,
        metadata: &dm_ir::ProcedureMetadata,
    ) -> Result<(), String> {
        if !std::ptr::eq(self.frontend, frontend) {
            return Err("original header handle belongs to another frontend acquisition".into());
        }
        self.view()?
            .require_for(&frontend.snapshot.tree, occurrence, metadata)
    }
    pub fn view(&self) -> Result<SourceHeaderExpressions<'_>, String> {
        let view = SourceParameterView {
            tree: &self.frontend.snapshot.tree,
            occurrence: self.occurrence,
            signature: &self.parameters,
            source: self.source,
            projection: None,
        }
        .header_expressions()?;
        view.require_for(&self.frontend.snapshot.tree, self.occurrence, self.metadata)?;
        Ok(view)
    }
    pub fn storage(&self) -> &dm_syntax::SharedParameterSignature {
        &self.parameters
    }
}
/// Stack-only original header expression view. This owns no syntax, metadata,
/// token table or semantic cache. Optional-root refusal never changes the
/// independent source type-path receipt or current compiler acceptance.
#[derive(Clone, Copy, Debug)]
pub struct SourceHeaderExpressions<'a> {
    parameters: SourceParameterView<'a>,
    metadata: &'a dm_ir::ProcedureMetadata,
}
impl<'a> SourceParameterView<'a> {
    pub fn header_expressions(self) -> Result<SourceHeaderExpressions<'a>, String> {
        let metadata = self
            .tree
            .member(self.occurrence.member)
            .and_then(|member| member.metadata.procedure.as_deref())
            .ok_or("original parameter metadata unavailable")?;
        // SourceParameterView was issued against the exact original roster.
        // Require the optional expression domain separately, without fallback.
        for entry in self.signature.entries()? {
            entry.expressions()?;
        }
        Ok(SourceHeaderExpressions {
            parameters: self,
            metadata,
        })
    }
}
impl<'a> SourceHeaderExpressions<'a> {
    pub fn require_for(
        &self,
        tree: &SemanticTree,
        occurrence: &BodyOccurrence,
        metadata: &dm_ir::ProcedureMetadata,
    ) -> Result<(), String> {
        self.parameters.require_for(tree, occurrence)?;
        if !std::ptr::eq(self.metadata, metadata) {
            return Err("header expressions belong to another selected metadata owner".into());
        }
        Ok(())
    }
    pub fn len(&self) -> usize {
        self.metadata.signature.parameters.len()
    }
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
    pub fn selected_metadata(&self) -> &'a dm_ir::ProcedureMetadata {
        self.metadata
    }
    fn entry(&self, ordinal: usize) -> Result<&'a dm_syntax::ParameterSyntax, String> {
        let entries: &'a [dm_syntax::ParameterSyntax] = self.parameters.signature.entries()?;
        entries
            .get(ordinal)
            .filter(|entry| !entry.variadic())
            .ok_or_else(|| "header expression ordinal is not an original formal".into())
    }
    fn check_tokens(
        &self,
        expression: &dm_syntax::Expr,
        native: &dm_ir::SymbolicExpression,
    ) -> Result<(), String> {
        if native.tokens.is_empty() {
            return Err("original expression token receipt is empty".into());
        }
        let first = native.tokens[0].relative_span.start;
        let mut previous = first;
        for token in native.tokens.iter() {
            if token.relative_span.start < previous {
                return Err("original expression token order differs".into());
            }
            let begin = expression
                .span
                .start
                .checked_add(
                    token
                        .relative_span
                        .start
                        .checked_sub(first)
                        .ok_or("header expression token precedes original first token")?,
                )
                .ok_or("header expression token coordinate overflow")?;
            let end = expression
                .span
                .start
                .checked_add(
                    token
                        .relative_span
                        .end
                        .checked_sub(first)
                        .ok_or("header expression token precedes original first token")?,
                )
                .filter(|end| *end <= expression.span.end)
                .ok_or("header expression token escapes original root")?;
            let spelling = self
                .parameters
                .source
                .get(begin..end)
                .ok_or("header expression token outside original source")?;
            if self.parameters.tree.symbols().text(token.text) != Some(spelling) {
                return Err(
                    "header expression token differs from selected original metadata".into(),
                );
            }
            previous = token.relative_span.end;
        }
        if previous.checked_sub(first) != Some(expression.span.end - expression.span.start) {
            return Err("header expression metadata does not cover original root".into());
        }
        Ok(())
    }
    fn expression(
        &self,
        ordinal: usize,
        source: bool,
    ) -> Result<Option<&'a dm_syntax::Expr>, String> {
        let entry = self.entry(ordinal)?;
        let roots = entry.expressions()?;
        let native = self
            .metadata
            .signature
            .parameters
            .get(ordinal)
            .ok_or("selected header expression formal unavailable")?;
        let symbolic = if source {
            native.source_expression.as_ref()
        } else {
            native.default.as_ref()
        };
        let root = roots.and_then(|roots| {
            if source {
                roots.source()
            } else {
                roots.default()
            }
        });
        match (root, symbolic) {
            (None, None) => Ok(None),
            (Some(root), Some(symbolic)) => {
                self.check_tokens(root, symbolic)?;
                Ok(Some(root))
            }
            _ => Err("original header root and selected metadata presence differ".into()),
        }
    }
    pub fn default(&self, ordinal: usize) -> Result<Option<&'a dm_syntax::Expr>, String> {
        self.expression(ordinal, false)
    }
    pub fn in_source(&self, ordinal: usize) -> Result<Option<&'a dm_syntax::Expr>, String> {
        self.expression(ordinal, true)
    }
}
pub(super) fn checked_source_parameters<'a>(
    tree: &'a SemanticTree,
    occurrence: &'a BodyOccurrence,
    header: &Item,
    parameters: &'a dm_syntax::ParameterSignature,
    source: &'a str,
) -> Result<SourceParameterView<'a>, String> {
    checked_source_parameters_projected(tree,occurrence,header.header_span,parameters,source,None,&||Ok(()),&|error|error)
}
/// SAME source-parameter validator for a real current archive/code binding.
/// Private callers must authenticate the canonical signature and projection first.
pub(super) fn checked_source_parameters_projected<'a,E>(
    tree:&'a SemanticTree,occurrence:&'a BodyOccurrence,header:dm_syntax::Span,
    parameters:&'a dm_syntax::ParameterSignature,source:&'a str,
    projection:Option<dm_syntax::SyntaxProjection>,checkpoint:&dyn Fn()->Result<(),E>,error:&dyn Fn(String)->E,
)->Result<SourceParameterView<'a>,E>{
    checkpoint()?;
    let view=SourceParameterView{tree,occurrence,signature:parameters,source,projection};
    if view.header_span().map_err(error)?!=header{return Err(error("parameter receipt belongs to another original header".into()))}
    let member=tree.member(occurrence.member).ok_or_else(||error("parameter callable member unavailable".into()))?;
    let metadata=member.metadata.procedure.as_ref().ok_or_else(||error("parameter callable signature unavailable".into()))?;
    for(ordinal,declaration)in parameters.absolute_declarations().map_err(|actual|error(actual.into()))?.iter().enumerate(){
        checkpoint()?;
        if declaration.ordinal()!=ordinal{return Err(error("absolute header declaration ordinal mismatch".into()))}
        let path=view.slice(declaration.span()).ok_or_else(||error("absolute header declaration outside original source".into()))?;
        let id=tree.lookup_type(dm_ir::SymbolId::of(path)).ok_or_else(||error("original absolute header type declaration was not issued by native frontend".into()))?;
        let actual=tree.type_node(id).ok_or_else(||error("original absolute header type unavailable".into()))?;
        if tree.symbols().text(actual.path)!=Some(path){return Err(error("original absolute header type spelling differs".into()))}
    }
    let mut native=metadata.signature.parameters.iter();let mut variadic=false;
    for(ordinal,entry)in parameters.entries().map_err(|actual|error(actual.into()))?.iter().enumerate(){
        checkpoint()?;
        if entry.ordinal()!=ordinal{return Err(error("parameter original ordinal mismatch".into()))}
        let name=view.name(entry).map_err(error)?;
        if entry.variadic(){if name!="..."||variadic{return Err(error("parameter variadic receipt mismatch".into()))}variadic=true;continue}
        let actual=native.next().ok_or_else(||error("parameter primary/runtime ordinal mismatch".into()))?;
        if tree.symbols().text(actual.name)!=Some(name){return Err(error("parameter primary/runtime name mismatch".into()))}
    }
    if native.next().is_some()||metadata.signature.variadic!=variadic{return Err(error("parameter primary/runtime roster mismatch".into()))}
    checkpoint()?;Ok(view)
}

impl ArchivedBody<'_> {
    /// Current original token coordinates, borrowed from the SAME parser-owned
    /// chunk. No source scan, new token array, expression parse or owner clone.
    pub fn original_body_tokens(&self)->Result<crate::procedure::header_input::OriginalBodyTokens<'_>,String>{let index=*self.archive.body_indices.get(&self.occurrence.declaration).ok_or("original body token declaration absent")?;if !self.archive.bodies.get(index).is_some_and(|row|std::ptr::eq(row,self.occurrence)){return Err("original body token occurrence differs".into())}let code=self.archive.body_codes.get(index).ok_or("original body token code absent")?;self.archive.syntax.original_body_tokens(self.occurrence.expanded_span,&code.identity)}

    pub fn source_locals(&self) -> Result<SourceLocalView<'_>, String> {
        // Local declaration geometry uses the issued Original syntax. Runtime
        // text decoding is a separate contract and remains unchanged.
        checked_source_locals_projected(
            self.tree(),
            self.occurrence(),
            self.statement_body(),
            self.archive_owner().expanded_source(),
            None,
            self.archive_owner().source_mapping().initial_environment() == dm_preprocess::InitialEnvironment::OriginalChecker0290,
            &|| Ok(()),
            &|error| error,
        )
    }

    /// Checked ORIGINAL source type-path facts. This does not certify a
    /// default/input expression or runtime ABI meaning.
    pub fn source_parameters(&self) -> Result<SourceParameterView<'_>, String> {
        checked_source_parameters(
            self.archive.tree(),
            self.occurrence,
            &self.header,
            &self.parameters,
            self.archive.expanded_source(),
        )
    }
    pub fn source_header_expressions(&self) -> Result<SourceHeaderExpressions<'_>, String> {
        self.source_parameters()?.header_expressions()
    }
    pub fn checker_parameters(
        &self,
        profile: dm_ir::PackedU128,
    ) -> Result<SourceParameterView<'_>, String> {
        self.archive
            .tree()
            .validate_checker_builtin_profile(profile)
            .map_err(|e| format!("parameter checker profile: {e:?}"))?;
        self.source_parameters()
    }
    pub fn parameter_storage(&self) -> &dm_syntax::SharedParameterSignature {
        &self.parameters
    }
    pub fn signature_opening_parenthesis(&self) -> Option<dm_syntax::Span> {
        self.opening_parenthesis
    }
    /// Exact archive issuance, not equality of source bytes or semantic hashes.
    pub fn belongs_to(&self, archive: &BodyArchive) -> bool {
        std::ptr::eq(self.archive, archive)
    }
    pub fn occurrence(&self) -> &BodyOccurrence {
        self.occurrence
    }
    /// Borrow the ORIGINAL archive that issued this body; no caller can rebind it.
    pub fn archive_owner(&self) -> &BodyArchive {
        self.archive
    }
    pub fn statement_body(&self) -> &StatementBody {
        &self.statements
    }
    pub fn header(&self) -> &Item {
        &self.header
    }
    pub fn header_source(&self) -> Option<&str> {
        self.archive.source.get(self.header.header_span.range())
    }
    pub fn location(&self, offset: usize) -> Option<SourceLocation> {
        self.archive.mapping.output(offset)
    }
    pub fn tree(&self) -> &SemanticTree {
        &self.archive.tree
    }
}
/// Authored results of two independent legacy lookups. A selected fixed
/// builtin has neither an authored member nor a body in this archive.
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub struct OriginalImageDirCallable {
    pub formal: Option<crate::MemberId>,
    pub value: Option<crate::MemberId>,
    pub body: Option<usize>,
}

impl ColdFrontend {
    /// Capture handles only. Executable parsing occurs only for the selected body.
    pub fn body_archive(&self) -> Option<Arc<BodyArchive>> {
        if !Arc::ptr_eq(&self.bodies, &self.issued_bodies)
            || !Arc::ptr_eq(&self.syntax, &self.issued_syntax)
            || !self.expanded.text.same_view(&self.issued_arena)
            || self.callable_roster().is_err()
        {
            return None;
        }
        Some(Arc::new(BodyArchive {
            body_queries: self.body_queries.clone(),
            setting_queries: self.setting_expression_queries.clone(),
            source: self.issued_arena.clone(),
            syntax: Arc::clone(&self.issued_syntax),
            bodies: Arc::clone(&self.issued_bodies),
            tree: Arc::clone(&self.snapshot.tree),
            declarations: Arc::clone(&self.snapshot.occurrences),
            mapping: Arc::clone(self.source_export_mapping()?),
            callables: Arc::clone(&self.callable_roster),
            body_indices: Arc::clone(&self.body_by_declaration),
            body_codes: Arc::clone(&self.issued_body_codes),
            settings_owners: Arc::clone(&self.issued_settings),
        }))
    }
}
impl BodyArchive {
    /// Existing immutable original owner tuple, with no strong source/model pin.
    pub fn original_owner_witness(&self)->OriginalArchiveOwner{archive_owner::issue(self)}

    /// Borrow the SAME original source-neutral code identity and current
    /// lexical boundary issued by the frontend. No parse, copied roster or key.
    pub fn body_code<'a>(
        &'a self,
        body: &BodyOccurrence,
    ) -> Result<IssuedBodyCode<'a>, Diagnostic> {
        let index = self
            .body_indices
            .get(&body.declaration)
            .copied()
            .ok_or_else(|| internal("archived body code declaration missing"))?;
        let occurrence = self
            .bodies
            .get(index)
            .ok_or_else(|| internal("archived body code occurrence missing"))?;
        if !std::ptr::eq(occurrence, body) {
            return Err(internal(
                "archived body code requires its original occurrence",
            ));
        }
        let owner = self
            .body_codes
            .get(index)
            .ok_or_else(|| internal("archived body code owner missing"))?;
        Ok(body_code::issue_archived_code(occurrence, owner))
    }
    pub fn visit_body_code_storage(&self, visit: impl FnMut(usize, usize, usize)) {
        body_code::visit_issued_code_storage(&self.body_codes, visit)
    }
    pub fn settings_owner_storage(&self) -> &Arc<[Option<Arc<dm_ir::ProcedureMetadata>>]> {
        &self.settings_owners
    }
    /// Authenticate the SAME source extractor's complete settings roster without
    /// parsing any body. Unknown source metadata refuses the entire capability.
    pub fn annotation_candidates(&self) -> Result<AnnotationCandidateRoster<'_>, String> {
        if self.settings_owners.len() != self.bodies.len() {
            return Err("annotation candidate metadata roster is incomplete".into());
        }
        for (body, issued) in self.bodies.iter().zip(self.settings_owners.iter()) {
            let issued = issued
                .as_ref()
                .ok_or("annotation candidate source metadata is unissued")?;
            let actual = self
                .tree
                .member(body.member)
                .and_then(|m| m.metadata.procedure.as_ref())
                .ok_or("annotation candidate original callable metadata unavailable")?;
            if !Arc::ptr_eq(&issued.settings, &actual.settings)
                && issued.settings != actual.settings
            {
                return Err("annotation candidate original metadata receipt differs".into());
            }
        }
        Ok(AnnotationCandidateRoster { archive: self })
    }
    /// SAME original ordered occurrence ledger; no grouping/index is built.
    pub fn original_declaration_occurrences(&self)->&crate::OccurrenceTable{&self.declarations}
    pub(super) fn original_image_dir_callable(
        &self, owner: dm_ir::SymbolId, name: dm_ir::SymbolId,
        checkpoint: &mut dyn FnMut()->std::io::Result<()>,
    ) -> std::io::Result<OriginalImageDirCallable> {
        use crate::{DefinitionMode, MemberKind, Target};
        use std::io::{Error,ErrorKind};
        let invalid=|message:&'static str|BodySyntaxFailure::Operational(Error::new(ErrorKind::InvalidData,message));
        let run=super::initializer_source::original_admission_using(self.setting_queries.as_ref(),|a|{
            let mut poll=||{checkpoint().map_err(BodySyntaxFailure::Operational)?;a.checkpoint().map_err(BodySyntaxFailure::Operational)};
            let catalog=crate::checker_builtins::pinned_catalog().map_err(|_|invalid("ImageDir pinned callable catalog unavailable"))?;
            let mut formal=None;
            let mut value=None;
            let mut formal_resolved=false;
            let mut value_resolved=false;
            let mut cursor=self.tree.lookup_type(owner);
            while let Some(ty)=cursor {
                poll()?;
                let owner=self.tree.type_node(ty).ok_or_else(||invalid("ImageDir callable owner absent"))?.path;
                let mut fixed_formal=false;
                let mut fixed_value=false;
                for verb in [false,true] {
                    let Some(row)=catalog.own_callable(owner,name,verb) else { continue };
                    if !row.metadata.procedure.as_ref().is_some_and(|proc|proc.signature.return_annotation.is_none()) {
                        return Err(invalid("ImageDir fixed callable has unexpected return metadata"));
                    }
                    match row.definition {
                        DefinitionMode::Declare => fixed_formal=true,
                        DefinitionMode::Implicit => (),
                        _ => return Err(invalid("ImageDir fixed callable has unexpected declaration mode")),
                    }
                    fixed_value=true;
                }
                let mut first_formal:Option<(crate::OccurrenceId,crate::MemberId)>=None;
                let mut last_implicit:Option<(crate::OccurrenceId,crate::MemberId)>=None;
                for kind in [MemberKind::Proc,MemberKind::Verb] {
                    let mut next=self.tree.resolve(ty,name,kind);
                    let mut remaining=self.tree.members().len();
                    while let Some(member)=next {
                        poll()?;
                        remaining=remaining.checked_sub(1).ok_or_else(||invalid("ImageDir callable source chain cycles"))?;
                        let node=self.tree.member(member).ok_or_else(||invalid("ImageDir callable member absent"))?;
                        if node.owner!=ty { break; }
                        if node.kind!=kind || node.name!=name || node.metadata.procedure.is_none() {
                            return Err(invalid("ImageDir callable source chain changed kind, name or metadata"));
                        }
                        let targets=self.declarations.for_target_admitted(Target::Member(member),a).map_err(BodySyntaxFailure::Operational)?;
                        let [authored]=targets else { return Err(invalid("ImageDir callable lacks its single actual authored occurrence")); };
                        let pair=(*authored,member);
                        if node.definition==DefinitionMode::Declare {
                            if first_formal.is_none_or(|(earlier,_)|authored.0<earlier.0) { first_formal=Some(pair); }
                        } else if node.definition==DefinitionMode::Implicit {
                            if last_implicit.is_none_or(|(later,_)|authored.0>later.0) { last_implicit=Some(pair); }
                        } else {
                            return Err(invalid("ImageDir callable mode has no pinned source ordering"));
                        }
                        next=node.previous;
                    }
                }
                // Fixed declarations are registered before source. Their
                // annotation and body are empty. Later explicit source
                // values go to the front; an implicit value goes to the end.
                if !formal_resolved && (fixed_formal || first_formal.is_some()) {
                    formal_resolved=true;
                    formal=first_formal.filter(|_|!fixed_formal).map(|(_,member)|member);
                }
                if !value_resolved && (fixed_value || first_formal.is_some() || last_implicit.is_some()) {
                    value_resolved=true;
                    value=last_implicit.or(first_formal.filter(|_|!fixed_value));
                }
                if formal_resolved && value_resolved { break; }
                cursor=self.tree.parent(ty);
            }
            let value_member=value.map(|(_,member)|member);
            let body=value.map(|(ordinal,_)|self.body_index(ordinal).ok_or_else(||invalid("ImageDir source value lacks its issued body recipe"))).transpose()?;
            if body.is_some_and(|ordinal|self.occurrences().get(ordinal).map(|row|row.member)!=value_member) {
                return Err(invalid("ImageDir selected body is not the issued value occurrence"));
            }
            poll()?;
            Ok(OriginalImageDirCallable{formal,value:value_member,body})
        });
        match run{
            Ok(value)=>Ok(value),
            Err(BodySyntaxFailure::Operational(error))=>Err(error),
            Err(BodySyntaxFailure::Syntax(error))=>Err(Error::new(ErrorKind::Unsupported,error.message)),
        }
    }
    pub fn source_mapping(&self) -> &Arc<SourceExportMapping> {
        &self.mapping
    }
    /// Acquisition provenance belongs to this exact issued source mapping.
    pub fn source_acquisition(
        &self,
        include_occurrence: usize,
    ) -> Option<&dm_preprocess::SourceAcquisitionLease> {
        self.mapping.source_acquisition(include_occurrence)
    }
    /// Existing issued syntax inputs for dependency edges in the same graph.
    pub fn syntax_inputs(&self) -> Option<&[Arc<BodySyntaxInput>]> {
        self.body_queries
            .as_ref()
            .map(|queries| queries.inputs.as_ref())
    }
    /// Semantic policies must use the compiler's graph, not another host that
    /// happens to parse equal source bytes.
    pub fn uses_body_queries(&self, host: &dyn BodySyntaxQueries) -> bool {
        self.body_queries
            .as_ref()
            .is_some_and(|queries| std::ptr::addr_eq(queries.host.as_ref(), host))
    }
    /// Borrow the existing compiler syntax-query host. Never constructs a DB.
    pub fn body_query_host(&self) -> Option<&dyn BodySyntaxQueries> {
        self.body_queries
            .as_ref()
            .map(|queries| queries.host.as_ref())
    }
    /// Existing expanded arena, used only for primary-issued selector origins.
    pub fn expanded_source(&self) -> &str {
        self.source.as_str()
    }
    /// Borrow the same immutable semantic owner captured from the compiler.
    pub fn tree(&self) -> &SemanticTree {
        &self.tree
    }
    /// Issued body roster in compiler source order, without copying metadata.
    /// Existing eager signatures are still borrowed. On a scoped-lazy
    /// archive, realize only the chosen header with this same host's permit;
    /// neither the metadata nor this local borrow becomes another cache.
    pub fn with_header_parameters_using<T>(
        &self, ordinal: usize, checkpoint: &dyn Fn() -> std::io::Result<()>,
        consume: impl for<'loan> FnOnce(SourceParameterView<'loan>) -> Result<T,BodySyntaxFailure>,
    ) -> Result<T,BodySyntaxFailure> {
      checkpoint().map_err(BodySyntaxFailure::Operational)?;
      let occurrence=self.bodies.get(ordinal).ok_or_else(||internal("header-only original body ordinal is unavailable"))?;
      let code=self.body_codes.get(ordinal).ok_or_else(||internal("header-only original code owner is unavailable"))?;
      if !self.syntax.requires_admitted_original_header_parameters(occurrence.expanded_span,&code.identity)? {
       return consume(self.header_parameters_after_checkpoint(ordinal,checkpoint)?);
      }
      let host=self.setting_queries.as_ref().and_then(std::sync::Weak::upgrade)
       .ok_or_else(||BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"current original header-only demand has no live syntax host")))?;
      let mut consume=Some(consume);
      let mut result=None;
      host.with_original_header_admission(&mut |a|{
       let consume=consume.take().ok_or_else(||internal("current original header admission callback repeated"))?;
       result=Some(self.with_header_parameters_admitted(ordinal,a,|view|{
        checkpoint().map_err(BodySyntaxFailure::Operational)?;
        consume(view)
       })?);
       Ok(())
      })?;
      result.ok_or_else(||internal("current original header admission callback omitted").into())
    }
    /// Inspect original formals without parsing any statement BODY.
    pub fn header_parameters_using(&self,ordinal:usize,checkpoint:&dyn Fn()->std::io::Result<()>)->Result<SourceParameterView<'_>,BodySyntaxFailure>{
      checkpoint().map_err(BodySyntaxFailure::Operational)?;
      self.header_parameters_after_checkpoint(ordinal,checkpoint)
    }
    fn header_parameters_after_checkpoint(&self,ordinal:usize,checkpoint:&dyn Fn()->std::io::Result<()>)->Result<SourceParameterView<'_>,BodySyntaxFailure>{
      let occurrence=self.bodies.get(ordinal).ok_or_else(||internal("header-only original body ordinal is unavailable"))?;
      let code=self.body_codes.get(ordinal).ok_or_else(||internal("header-only original code owner is unavailable"))?;
      let(parameters,projection)=self.syntax.original_header_parameters(occurrence.expanded_span,&code.identity).map_err(|error|internal(&error.message))?;
      let header=projection.span(parameters.header()).ok_or_else(||internal("actual original header projection escaped source"))?;
      checked_source_parameters_projected(&self.tree,occurrence,header,parameters,&self.source,Some(projection),&||checkpoint().map_err(BodySyntaxFailure::Operational),&|message|internal(&message).into())
    }
    /// Exact header-only demand on the current native admission. The view
    /// cannot escape the one realized metadata owner or request BODY syntax.
    pub fn with_header_parameters_admitted<T>(
        &self, ordinal: usize, a: &dm_syntax::SettingAdmission<'_>,
        consume: impl for<'loan> FnOnce(SourceParameterView<'loan>) -> Result<T,BodySyntaxFailure>,
    ) -> Result<T, BodySyntaxFailure> {
      a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
      let occurrence=self.bodies.get(ordinal).ok_or_else(||internal("header-only original body ordinal is unavailable"))?;
      let code=self.body_codes.get(ordinal).ok_or_else(||internal("header-only original code owner is unavailable"))?;
      self.syntax.with_original_header_parameters_admitted(occurrence.expanded_span,&code.identity,a,|parameters,projection|{
       let header=projection.span(parameters.header()).ok_or_else(||internal("actual original header projection escaped source"))?;
       let view=checked_source_parameters_projected(&self.tree,occurrence,header,parameters,&self.source,Some(projection),&||a.checkpoint().map_err(BodySyntaxFailure::Operational),&|message|internal(&message).into())?;
       consume(view)
      })
    }
    pub fn occurrences(&self) -> &[BodyOccurrence] {
        &self.bodies
    }
    pub fn location(&self, expanded_offset: usize) -> Option<SourceLocation> {
        self.mapping.output(expanded_offset)
    }
    /// First authored occurrence of this archive's member. Member IDs are
    /// meaningful only in `tree()`; no foreign tree or source table is accepted.
    /// This borrows the existing target/occurrence index and provenance projection.
    pub fn member_location(&self, member: crate::MemberId) -> Option<SourceLocation> {
        self.tree.member(member)?;
        let ordinal = *self
            .declarations
            .for_target(crate::Target::Member(member))
            .first()?;
        self.mapping.location_of(ordinal)
    }
    /// A bound callable body already carries a mapped location for its exact
    /// declaration. Presence does not need the first matching expanded token.
    pub fn has_member_location(&self, member: crate::MemberId) -> bool {
        if let Some(body) = self.callables.ordinal(member).and_then(|index| self.bodies.get(index)) {
            let first = self.declarations.for_target(crate::Target::Member(member)).first();
            if body.member == member && first == Some(&body.declaration)
                && self.declarations.get(body.declaration).is_some_and(|occurrence| {
                    let provenance = &occurrence.provenance;
                    provenance.include_occurrence as usize == body.source.include_occurrence
                        && provenance.span.file == body.source.span.file
                        && provenance.span.start == body.source.span.start
                }) {
                return true;
            }
        }
        self.member_location(member).is_some()
    }
    pub fn body_index(&self, declaration: OccurrenceId) -> Option<usize> {
        self.body_indices.get(&declaration).copied()
    }
    pub fn callables(&self) -> &Arc<CallableRoster> {
        &self.callables
    }

    pub fn matches_tree(&self, tree: &SemanticTree) -> bool {
        std::ptr::eq(self.tree.as_ref(), tree)
    }
    pub fn len(&self) -> usize {
        self.bodies.len()
    }
    pub fn is_empty(&self) -> bool {
        self.bodies.is_empty()
    }
    pub fn parse(&self, ordinal: usize) -> Result<ArchivedBody<'_>, Diagnostic> {
        self.parse_with(
            ordinal,
            |input, host| input.obtain(host),
            |item, _| Ok(parse_statements(item, &self.source, &self.syntax, |_| true)),
        )
    }
    pub fn parse_checked(&self, ordinal: usize) -> Result<ArchivedBody<'_>, BodySyntaxFailure> {
        self.parse_with(
            ordinal,
            |input, host| input.obtain_checked(host),
            |item, occurrence| self.checked_statements(item, occurrence),
        )
    }
    /// Borrow the EXACT syntax returned by an active native query context.
    /// The existing private input issuance check is mandatory AFTER obtaining.
    /// This path never falls back to standalone parsing or re-gets the host.
    pub fn parse_checked_using(
        &self,ordinal:usize,
        obtain:impl FnOnce(&Arc<BodySyntaxInput>)->Result<Arc<BodySyntax>,BodySyntaxFailure>,
    )->Result<ArchivedBody<'_>,BodySyntaxFailure>{
        if self.body_queries.is_none(){return Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"observed body demand requires original native query inputs")))}
        self.parse_with(ordinal,|input,host|{host.prepare_checked_input(input)?;input.obtain_checked_using(obtain)},|_,_|Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"observed body demand cannot use standalone statements"))))
    }
    fn checked_statements(
        &self,
        item: &mut Item,
        occurrence: &BodyOccurrence,
    ) -> Result<Arc<StatementBody>, BodySyntaxFailure> {
        let ordinal = self
            .body_index(occurrence.declaration)
            .ok_or_else(|| internal("archived setting occurrence unavailable"))?;
        let owner = self
            .settings_owners
            .get(ordinal)
            .and_then(Option::as_ref)
            .ok_or_else(|| internal("archived original settings owner unavailable"))?;
        if owner.settings.is_empty() {
            return Ok(parse_statements(item, &self.source, &self.syntax, |_| true));
        }
        let code = self
            .body_code(occurrence)
            .map_err(BodySyntaxFailure::Syntax)?;
        let provider = self
            .setting_queries
            .as_ref()
            .and_then(std::sync::Weak::upgrade)
            .ok_or_else(|| {
                BodySyntaxFailure::Operational(std::io::Error::new(
                    std::io::ErrorKind::NotConnected,
                    "archived original settings require the existing native host provider",
                ))
            })?;
        let mut input = setting_queries::SettingStatementsInput::issued(
            &self.source,
            &self.syntax,
            code,
            item,
            |_| true,
        );
        let statements = provider.statements(&mut input)?;
        if !input.accepts(&statements) {
            return Err(BodySyntaxFailure::Operational(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "settings provider returned foreign archived statement result",
            )));
        }
        Ok(statements)
    }
    fn parse_with<E: From<Diagnostic>>(
        &self,
        ordinal: usize,
        obtain: impl FnOnce(&Arc<BodySyntaxInput>, &dyn BodySyntaxQueries) -> Result<Arc<BodySyntax>, E>,
        statements: impl FnOnce(&mut Item, &BodyOccurrence) -> Result<Arc<StatementBody>, E>,
    ) -> Result<ArchivedBody<'_>, E> {
        let occurrence = self
            .bodies
            .get(ordinal)
            .ok_or_else(|| internal("body archive ordinal unavailable"))?;
        if occurrence
            .expanded_span
            .end
            .saturating_sub(occurrence.expanded_span.start)
            > 1024 * 1024
        {
            return Err(internal("body archive query exceeds 1 MiB input limit").into());
        }
        if let Some(queries) = &self.body_queries {
            let shared = obtain(&queries.inputs[ordinal], queries.host.as_ref())?;
            let mut header = shared.item.clone();
            if shared.statements.parsed().diagnostics.is_empty() {
                header.children = Vec::new();
            }
            return Ok(ArchivedBody {
                archive: self,
                occurrence,
                statements: Arc::clone(&shared.statements),
                opening_parenthesis: shared.opening_parenthesis,
                parameters: shared.parameters.clone(),
                header,
            });
        }
        let issued = self
            .syntax
            .parse_original_procedure(
                occurrence.expanded_span,
                &self
                    .body_codes
                    .get(ordinal)
                    .ok_or_else(|| internal("original archive body code missing"))?
                    .identity,
            )
            .map_err(|error| Diagnostic {
                kind: syntax_kind(error.kind),
                stage: DiagnosticStage::Syntax,
                location: self
                    .mapping
                    .output(error.span.start)
                    .or_else(|| Some(occurrence.source.clone())),
                message: error.message,
            })?;
        let mut item = issued.item;
        let statements = statements(&mut item, occurrence)?;
        Ok(ArchivedBody {
            archive: self,
            occurrence,
            statements,
            opening_parenthesis: issued.opening_parenthesis,
            parameters: issued.parameters.into_shared(),
            header: item,
        })
    }
    /// Borrow only the newly retained original header input metadata. Current
    /// archive/source/tree authority and source bytes remain their existing owners.
    pub fn visit_original_header_storage(&self, visit: impl FnMut(usize, usize, usize)) {
        self.visit_original_header_storage_with_backing_filter(visit, &mut |_| false);
    }

    /// Policy accounting only. Full heap/storage visitors use the ordinary walk.
    #[doc(hidden)]
    pub fn visit_original_header_storage_with_backing_filter(&self, mut visit: impl FnMut(usize, usize, usize), skip:&mut dyn FnMut(&dyn std::any::Any)->bool) {
        for chunk in self.syntax.chunks().iter() {
            chunk
                .shared_relative()
                .visit_original_header_storage_with_backing_filter(&mut visit, skip);
        }
    }
    /// Resource-only walk of token loan owners, excluding every other header
    /// allocation. The archive retains each owner throughout this callback.
    #[doc(hidden)]
    pub fn try_visit_original_header_token_backing_owners(
        &self,
        mut visit: impl FnMut(&dyn std::any::Any) -> std::io::Result<()>,
    ) -> std::io::Result<()> {
        for chunk in self.syntax.chunks().iter() {
            if let Some(tokens) = chunk.shared_relative().original_shared_span_tokens() {
                tokens.try_visit_backing_owners(&mut visit)?;
            }
        }
        Ok(())
    }
    /// Policy accounting only. Actual syntax leases are checked against the
    /// provided native domain on every walk; unknown header storage is charged.
    #[doc(hidden)]
    pub fn visit_original_header_storage_classified(&self, a:&dm_syntax::SettingAdmission<'_>, mut visit:impl FnMut(usize,usize,usize,bool), skip:&mut dyn FnMut(&dyn std::any::Any)->bool) {
        for chunk in self.syntax.chunks().iter() {
            chunk.shared_relative().visit_original_header_storage_classified(a,&mut visit,skip);
        }
    }
    pub fn binding_storage(&self) -> (&Arc<CallableRoster>, &Arc<HashMap<OccurrenceId, usize>>) {
        (&self.callables, &self.body_indices)
    }
    pub fn visit_storage(
        &self,
        visit: impl FnOnce(&dm_preprocess::SourceText, &Arc<DeclarationSyntax>, &Arc<[BodyOccurrence]>),
    ) {
        visit(&self.source, &self.syntax, &self.bodies);
    }
}
pub(super) fn parse_statements(
    item: &mut Item,
    source: &str,
    syntax: &DeclarationSyntax,
    supported: fn(&[dm_syntax::Statement]) -> bool,
) -> Arc<StatementBody> {
    let parsed = dm_syntax::parse_body_items_with_context(&item.children, source, &|offset| {
        syntax.declaration_header_at(offset)
    });
    finish_statements(item, parsed, supported, None)
}
/// Native parser only: exact original-source provider and SAME in-scope permit.
pub(super) fn parse_statements_with_setting_admission(
    item: &mut Item,
    source: &str,
    syntax: &DeclarationSyntax,
    body: dm_syntax::Span,
    code: Option<&Arc<BodyCodeIdentity>>,
    admission: &dm_syntax::SettingAdmission<'_>,
    supported: fn(&[dm_syntax::Statement]) -> bool,
) -> Result<Arc<StatementBody>, BodySyntaxFailure> {
    parse_statements_admitted(item,source,syntax,body,code,admission,supported,false)
}
pub(super) fn parse_statements_with_body_literal_admission(
    item:&mut Item,source:&str,syntax:&DeclarationSyntax,body:dm_syntax::Span,
    code:Option<&Arc<BodyCodeIdentity>>,admission:&dm_syntax::SettingAdmission<'_>,
    supported:fn(&[dm_syntax::Statement])->bool,
)->Result<Arc<StatementBody>,BodySyntaxFailure>{
    parse_statements_admitted(item,source,syntax,body,code,admission,supported,true)
}
fn parse_statements_admitted(
    item:&mut Item,source:&str,syntax:&DeclarationSyntax,body:dm_syntax::Span,
    code:Option<&Arc<BodyCodeIdentity>>,admission:&dm_syntax::SettingAdmission<'_>,
    supported:fn(&[dm_syntax::Statement])->bool,complete_literals:bool,
)->Result<Arc<StatementBody>,BodySyntaxFailure>{
    struct Original<'a, 'op> {
        syntax: &'a DeclarationSyntax,
        body: dm_syntax::Span,
        code: &'a Arc<BodyCodeIdentity>,
        admission: &'a dm_syntax::SettingAdmission<'op>,
    }
    impl dm_syntax::SettingSyntaxProvider for Original<'_, '_> {
        fn original_expression(&self,source:&str,offset:usize)->std::io::Result<Option<dm_syntax::ParsedExpr>>{self.syntax.original_body_expression(self.body,self.code,source,offset,self.admission)}
        fn original_joined_return(&self, header: dm_syntax::Span) -> std::io::Result<bool> {
            use dm_syntax::TokenKind;
            use std::io::{Error, ErrorKind};

            self.admission.checkpoint()?;
            let tokens = self.syntax.original_body_tokens(self.body, self.code)
                .map_err(|reason| Error::new(ErrorKind::InvalidData, reason))?;
            let mut tokens = tokens.tokens(header)
                .map_err(|reason| Error::new(ErrorKind::InvalidData, reason))?;
            let Some((TokenKind::Ident, keyword, "return")) = tokens.next() else {
                return Ok(false);
            };
            let Some((_, next, _)) = tokens.next() else {
                return Ok(false);
            };
            // Original consumes the exact identifier before parsing an optional
            // expression. A following token is not proof that it is valid.
            Ok(keyword.start == header.start && keyword.end == next.start)
        }
        fn original_statement_block_open(&self, gap: dm_syntax::Span) -> std::io::Result<bool> {
            self.admission.checkpoint()?;
            let tokens = self.syntax.original_body_tokens(self.body, self.code)
                .map_err(|message| std::io::Error::new(std::io::ErrorKind::InvalidData, message))?;
            let mut open = false;
            let Ok(gap) = tokens.tokens(gap) else { return Ok(false); };
            for (kind, _, spelling) in gap {
                self.admission.checkpoint()?;
                if matches!(kind, dm_syntax::TokenKind::Whitespace | dm_syntax::TokenKind::Newline | dm_syntax::TokenKind::Comment) {
                    continue;
                }
                if open || kind != dm_syntax::TokenKind::Punctuation || spelling != "{" {
                    return Ok(false);
                }
                open = true;
            }
            Ok(open)
        }
        fn switch_case_cursor(&self,item:&Item)->Result<dm_syntax::OriginalCaseCursor,&'static str>{
            let mut checkpoint=||{self.admission.checkpoint().map_err(|actual|{self.admission.record_operational_error(actual);"native case cursor operation stopped"})};
            let tokens=self.syntax.original_body_tokens(self.body,self.code).map_err(|_|"original case body token owner unavailable")?;tokens.switch_case_cursor_using(item.header_span,item.span,&mut checkpoint)
        }
        fn setting(
            &self,
            item: &Item,
        ) -> Result<dm_syntax::SettingStatement, dm_syntax::Diagnostic> {
            match self.syntax.setting_statement_expression(
                self.body,
                self.code,
                item,
                self.admission,
            ) {
                Ok((attribute, relation, value)) => Ok(dm_syntax::SettingStatement {
                    attribute,
                    relation,
                    value,
                }),
                Err(dm_syntax::SettingSyntaxFailure::Syntax(error)) => Err(error),
                Err(dm_syntax::SettingSyntaxFailure::Operational(error)) => {
                    self.admission.record_operational_error(error);
                    // Parser recovery control only. The enclosing typed boundary
                    // extracts ACTUAL IO and never publishes this as syntax.
                    Err(dm_syntax::Diagnostic {
                        span: item.header_span,
                        kind: dm_syntax::DiagnosticKind::Unsupported,
                        message: "native settings operation stopped".into(),
                    })
                }
            }
        }
    }
    let code = code.ok_or_else(|| {
        BodySyntaxFailure::Syntax(internal("original body code input is unissued"))
    })?;
    let provider = Original {
        syntax,
        body,
        code,
        admission,
    };
    // Failure cleanup is admitted BEFORE the ordinary body AST is built.
    // It is coordination headroom only, not a global native-input/AST cap.
    let cleanup=if complete_literals{
        let bytes=body.end.checked_sub(body.start).and_then(|n|n.checked_mul(512)).and_then(|n|n.checked_add(8192)).ok_or_else(||BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"body literal cleanup source envelope overflow")))?;
        Some(admission.reserve(bytes).map_err(BodySyntaxFailure::Operational)?)
    }else{None};
    if let Some(cleanup)=cleanup{
        let prepared=dm_syntax::parse_body_items_with_admitted_literals(
            &item.children,source,&|at|syntax.declaration_header_at(at),&provider,admission,cleanup,
        ).map_err(BodySyntaxFailure::Operational)?;
        let (parsed,literals)=prepared.into_parts();
        if let Some(actual)=admission.take_operational_error(){
            dm_syntax::drop_body_literal_syntax(parsed,Some(literals));
            return Err(BodySyntaxFailure::Operational(actual));
        }
        Ok(finish_statements(item,parsed,supported,Some(literals)))
    }else{
        let parsed=dm_syntax::parse_body_items_with_context_and_settings(
            &item.children,source,&|at|syntax.declaration_header_at(at),&provider,admission,
        );
        if let Some(actual)=admission.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual));}
        admission.checkpoint().map_err(BodySyntaxFailure::Operational)?;
        Ok(finish_statements(item,parsed,supported,None))
    }
}
fn finish_statements(
    item: &mut Item,
    parsed: dm_syntax::ParsedBody,
    supported: fn(&[dm_syntax::Statement]) -> bool,
    literal_admission:Option<dm_syntax::BodyLiteralAdmission>,
) -> Arc<StatementBody> {
    fn headers(items: &[Item], result: &mut std::collections::HashSet<(usize, usize)>) {
        for item in items {
            if item.header.trim_start().starts_with("var/") {
                result.insert((item.header_span.start, item.header_span.end));
            }
            headers(&item.children, result);
        }
    }
    let stored_candidates =
        crate::procedure_statics::items_may_contain_stored_declarations(&item.children);
    let mut declaration_headers = std::collections::HashSet::new();
    // This roster certifies only extracted stored-local declarations. The
    // existing negative proof excludes all such origins; ordinary locals
    // need neither header traversal nor HashSet backing allocation.
    if stored_candidates {
        headers(&item.children, &mut declaration_headers);
    }
    if parsed.diagnostics.is_empty() && supported(&parsed.statements) {
        item.children = Vec::new();
    }
    Arc::new(StatementBody {
        parsed,
        syntax_complete: std::sync::OnceLock::new(),
        declaration_headers,
        stored_candidates,
        literal_admission,
    })
}

#[cfg(test)]
#[path = "frontend_body_archive_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "frontend_acquisition_tests.rs"]
mod acquisition_tests;

impl BodyArchive {
    pub fn original_note_origin(&self, offset: usize) -> Result<SourceNoteOrigin, String> {
        self.mapping.original_note_origin(offset)
    }
    pub fn source_note_point(&self, offset: usize) -> Result<SourceNoteOrigin, String> {
        self.mapping.source_note_point(offset)
    }
    /// Original callable opening-token origin without demanding executable body
    /// grammar. Uses the SAME private current code/header recipe as BodySyntax.
    pub fn callable_header_policy_origin(&self,member:crate::MemberId)->Result<SourceNoteOrigin,String>{self.callable_header_source().reported_point(member).map(super::BorrowedSourceNoteOrigin::into_owned)}
    /// Actual opening-token member/roster binding, with producer-certified policy
    /// line only. This cannot authorize a byte column or diagnostic source span.
    pub fn callable_header_policy_line(&self,member:crate::MemberId)->Result<SourcePolicyLineOrigin,String>{self.callable_header_source().reported_policy_line(member)}
    /// Borrow the SAME immutable current header owners. No body is demanded.
    pub fn callable_header_source(&self)->CallableHeaderSource<'_>{CallableHeaderSource{tree:&self.tree,callables:&self.callables,bodies:&self.bodies,codes:&self.body_codes,syntax:&self.syntax,mapping:&self.mapping}}
    pub fn callable_note_origin(
        &self,
        identity: dm_ir::ProcedureIdentity,
    ) -> Result<SourceNoteOrigin, String> {
        self.borrowed_callable_note_origin(identity)
            .map(super::BorrowedSourceNoteOrigin::into_owned)
    }

    /// Borrow the same retained callable note with its original FileList key.
    pub fn borrowed_callable_note_origin(
        &self,
        identity: dm_ir::ProcedureIdentity,
    ) -> Result<super::BorrowedSourceNoteOrigin<'_>, String> {
        self.borrowed_callable_note_origin_with(identity, |archive, ordinal| {
            archive.parse(ordinal).map_err(|e| e.message)
        })
    }
    /// Same original callable lookup, with caller-selected typed body transport.
    /// A returned body must be the exact selected occurrence in this archive.
    pub fn callable_note_origin_with<'a, E: From<String> + From<&'static str>>(
        &'a self,
        identity: dm_ir::ProcedureIdentity,
        parse: impl FnOnce(&'a Self, usize) -> Result<ArchivedBody<'a>, E>,
    ) -> Result<SourceNoteOrigin, E> {
        self.borrowed_callable_note_origin_with(identity, parse)
            .map(super::BorrowedSourceNoteOrigin::into_owned)
    }

    fn borrowed_callable_note_origin_with<'a, E: From<String> + From<&'static str>>(
        &'a self,
        identity: dm_ir::ProcedureIdentity,
        parse: impl FnOnce(&'a Self, usize) -> Result<ArchivedBody<'a>, E>,
    ) -> Result<super::BorrowedSourceNoteOrigin<'a>, E> {
        if self.body_query_host().is_none() {
            return Err("callable note needs original retained BodySyntax owner".into());
        }
        let mut selected = None;
        for (ordinal, occurrence) in self.occurrences().iter().enumerate() {
            let member = self
                .tree()
                .member(occurrence.member)
                .ok_or("callable note member unavailable")?;
            let issued = dm_ir::ProcedureIdentity {
                owner: self
                    .tree()
                    .type_node(member.owner)
                    .ok_or("callable note owner unavailable")?
                    .path,
                name: member.name,
                verb: member.kind == crate::MemberKind::Verb,
                occurrence: self
                    .tree()
                    .member_occurrence(occurrence.member)
                    .ok_or("callable note source occurrence unavailable")?,
            };
            if issued == identity && selected.replace(ordinal).is_some() {
                return Err("callable note identity ambiguous".into());
            }
        }
        let ordinal = selected.ok_or("callable note has no issued primary body")?;
        let body = parse(self, ordinal)?;
        self.callable_note_origin_borrowed_from_parsed(identity, ordinal, &body)
            .map_err(BorrowedCallableOriginError::into_error::<E>)
    }
}

impl BodyArchive {
    pub fn original_policy_line(
        &self,
        offset: usize,
    ) -> Result<super::SourcePolicyLineOrigin, String> {
        self.mapping.original_policy_line(offset)
    }
}

impl BodyArchive {
    fn member_policy_occurrence(&self, member: crate::MemberId) -> Result<OccurrenceId, String> {
        if self.tree.member(member).ok_or("member unavailable")?.kind != MemberKind::Var {
            return Err("member is not a source variable".into());
        }
        self.declarations
            .for_target(crate::Target::Member(member))
            .first()
            .copied()
            .ok_or_else(|| "member has no authored occurrence".into())
    }
    pub fn member_policy_compatibility_cursor(
        &self,
        member: crate::MemberId,
    ) -> Result<super::SourceDeclarationPolicyCursor, String> {
        self.mapping
            .declaration_policy_compatibility_cursor(self.member_policy_occurrence(member)?)
    }
    /// Original declaration diagnostic location, including a proved terminal
    /// root lookahead. This is not the authored occurrence or a policy anchor.
    pub fn member_declaration_diagnostic_line(
        &self,
        member: crate::MemberId,
    ) -> Result<SourcePolicyLineOrigin, String> {
        self.mapping
            .declaration_diagnostic_line(self.member_policy_occurrence(member)?)
    }

    pub fn member_policy_line(
        &self,
        member: crate::MemberId,
    ) -> Result<SourcePolicyLineOrigin, String> {
        self.mapping
            .declaration_policy_line(self.member_policy_occurrence(member)?)
    }
    pub fn member_primary_policy_span(
        &self,
        member: crate::MemberId,
    ) -> Result<dm_syntax::Span, String> {
        self.mapping
            .declaration_primary_policy_span(self.member_policy_occurrence(member)?)
    }
    pub fn member_policy_point(&self, member: crate::MemberId) -> Result<SourceNoteOrigin, String> {
        self.mapping
            .declaration_policy_point(self.member_policy_occurrence(member)?)
    }

    pub fn borrowed_member_policy_point(
        &self,
        member: crate::MemberId,
    ) -> Result<super::BorrowedSourceNoteOrigin<'_>, String> {
        self.mapping
            .borrowed_declaration_policy_point(self.member_policy_occurrence(member)?)
    }
}

#[path = "frontend_checker_variable_properties.rs"]
mod checker_variable_properties;
pub use checker_variable_properties::CheckerVariableProperties;
pub(super) use checker_variable_properties::properties_for_issued_original;

impl BodyArchive {
    pub fn member_source_note_point(
        &self,
        member: crate::MemberId,
    ) -> Result<SourceNoteOrigin, String> {
        self.mapping
            .declaration_source_note_point(self.member_policy_occurrence(member)?)
    }
}

#[cfg(test)]
#[path = "frontend_parameter_syntax_tests.rs"]
mod parameter_syntax_tests;

/// Static projection failure classification preserves the original generic
/// error conversion: body guards used &str, mapping projection used String.
#[derive(Clone,Copy,Debug)]pub enum BorrowedCallableOriginError{Body(&'static str),Projection(&'static str)}
impl BorrowedCallableOriginError{pub fn message(self)->&'static str{match self{Self::Body(message)|Self::Projection(message)=>message}}fn into_error<E:From<String>+From<&'static str>>(self)->E{match self{Self::Body(message)=>E::from(message),Self::Projection(message)=>E::from(message.to_owned())}}}
impl BodyArchive{
    pub fn borrowed_source_note_point(&self,offset:usize)->Result<super::BorrowedSourceNoteOrigin<'_>,&'static str>{self.mapping.borrowed_source_note_point(offset)}
    pub fn callable_note_origin_borrowed_from_parsed(&self,identity:dm_ir::ProcedureIdentity,ordinal:usize,body:&ArchivedBody<'_>)->Result<super::BorrowedSourceNoteOrigin<'_>,BorrowedCallableOriginError>{
        use BorrowedCallableOriginError::Body;
        if self.body_query_host().is_none(){return Err(Body("callable note needs original retained BodySyntax owner"))}
        if self.callables().identity(ordinal)!=Some(identity)||!body.belongs_to(self)||self.occurrences().get(ordinal).is_none_or(|expected|!std::ptr::eq(body.occurrence(),expected))||!body.statement_body().syntax_complete(){return Err(Body("callable note primary source unavailable"))}
        let opening=body.signature_opening_parenthesis().ok_or(Body("primary callable opening token unavailable"))?;self.mapping.borrowed_source_note_point(opening.start).map_err(BorrowedCallableOriginError::Projection)
    }
    /// No new body demand or roster scan; owned projection stays compatible.
    pub fn callable_note_origin_from_parsed<E:From<String>+From<&'static str>>(&self,identity:dm_ir::ProcedureIdentity,ordinal:usize,body:&ArchivedBody<'_>)->Result<SourceNoteOrigin,E>{self.callable_note_origin_borrowed_from_parsed(identity,ordinal,body).map(super::BorrowedSourceNoteOrigin::into_owned).map_err(BorrowedCallableOriginError::into_error::<E>)}
}

/// Stack-only loan over existing original procedure header/source owners.
/// Constructor is private; it never owns syntax, copies source or carries policy.
pub struct CallableHeaderSource<'a>{tree:&'a SemanticTree,callables:&'a CallableRoster,bodies:&'a[BodyOccurrence],codes:&'a[body_code::BodyCodeOwner],syntax:&'a DeclarationSyntax,mapping:&'a SourceExportMapping}
impl<'a> CallableHeaderSource<'a>{
 /// Statement points use this SAME privately issued current mapping; this
 /// borrowed data never rebinds an AST or registers a reported file.
 pub fn reported_source_point(&self,offset:usize)->Result<super::BorrowedSourceNoteOrigin<'a>,String>{self.mapping.borrowed_source_note_point(offset).map_err(str::to_owned)}

 fn cursor(&self,member:crate::MemberId)->Result<usize,String>{
  if !self.callables.authenticates_borrowed_tree(self.tree){return Err("callable header roster belongs to another original tree".into())}
  if !matches!(self.tree.member(member).ok_or("callable header member unavailable")?.kind,crate::MemberKind::Proc|crate::MemberKind::Verb){return Err("callable header requires source procedure/verb".into())}
  let ordinal=self.callables.ordinal(member).ok_or("callable header member not in original roster")?;let occurrence=self.bodies.get(ordinal).ok_or("callable header original occurrence absent")?;
  if occurrence.member!=member{return Err("callable header roster occurrence differs".into())}
  let code=self.codes.get(ordinal).ok_or("callable header original code absent")?;self.syntax.original_callable_opening(occurrence.expanded_span,&code.identity)
 }
 /// Authenticated actual parser records; no Q4/body/default grammar is run.
 pub fn formal_notices(&self,member:crate::MemberId)->Result<impl Iterator<Item=Result<(crate::OriginalFormalNotice,Option<&'a str>),String>>+'a,String>{self.cursor(member)?;let ordinal=self.callables.ordinal(member).ok_or("actual formal member absent")?;let occurrence=self.bodies.get(ordinal).ok_or("actual formal occurrence absent")?;let code=self.codes.get(ordinal).ok_or("actual formal code owner absent")?;self.syntax.original_formal_notice_rows(occurrence.expanded_span,&code.identity)}
 pub fn reported_policy_line(&self,member:crate::MemberId)->Result<SourcePolicyLineOrigin,String>{self.mapping.original_policy_line(self.cursor(member)?)}
 pub fn reported_point(&self,member:crate::MemberId)->Result<super::BorrowedSourceNoteOrigin<'a>,String>{self.mapping.borrowed_source_note_point(self.cursor(member)?).map_err(str::to_owned)}
    /// Resolve the exact authored version before projecting its primary header.
    /// No parameter/default or body syntax is demanded by a note.
    pub fn reported_point_for_identity(
        &self,
        identity: dm_ir::ProcedureIdentity,
    ) -> Result<super::BorrowedSourceNoteOrigin<'a>, String> {
        let ordinal = self.callables.ordinal_for_identity(identity)
            .ok_or("callable note has no issued primary body")?;
        let member = self.callables.members().get(ordinal).copied()
            .ok_or("callable note roster member unavailable")?;
        self.reported_point(member)
    }
 pub fn reported_span(&self,member:crate::MemberId)->Result<dm_syntax::Span,String>{let at=self.cursor(member)?;Ok(dm_syntax::Span::new(at,at.checked_add(1).ok_or("callable header point extent overflow")?))}
}
impl ColdFrontend{
 /// Validate this exact current mapping once, then lend immutable header views.
 /// The shared borrow prevents public compatibility mutation during the loan.
 pub fn callable_header_source(&self)->Result<CallableHeaderSource<'_>,String>{
  let callables=self.callable_roster()?;
  if !Arc::ptr_eq(&self.syntax,&self.issued_syntax)||!self.expanded.text.same_view(&self.issued_arena){return Err("callable header source differs from current frontend issuance".into())}
  let mapping=self.source_export_mapping().ok_or("callable header current source mapping unavailable")?;
  Ok(CallableHeaderSource{tree:&self.snapshot.tree,callables,bodies:&self.bodies,codes:&self.issued_body_codes,syntax:&self.syntax,mapping})
 }
}

impl ArchivedBody<'_>{
 /// Resource admission only, over the SAME original expression provider kept
 /// weakly by this archive. No gate/reset/Db, source recipe, or parse is minted.
 pub fn with_original_syntax_admission<T>(&self,operation:impl FnOnce(&dm_syntax::SettingAdmission<'_>)->Result<T,BodySyntaxFailure>)->Result<T,BodySyntaxFailure>{
  super::initializer_source::original_admission_using(self.archive.setting_queries.as_ref(),operation)
 }
}

#[derive(Debug)]
pub enum OriginalParentSourceFailure{Unsupported(String),Operational(std::io::Error)}
impl From<String> for OriginalParentSourceFailure{fn from(value:String)->Self{Self::Unsupported(value)}}
impl From<&'static str> for OriginalParentSourceFailure{fn from(value:&'static str)->Self{Self::Unsupported(value.into())}}

impl BodyArchive{
 /// One traversal over the existing native declaration AST. Selectors receive
 /// only observed type IDs; actual source assignments/cursors are borrowed
 /// here. This emits DATA, never source/semantic admission or a new parser.
 pub fn visit_original_parent_assignment_spans(&self,checkpoint:&dyn Fn()->std::io::Result<()>,mut select:impl FnMut(dm_ir::SymbolId)->Result<Option<dm_ir::SymbolId>,OriginalParentSourceFailure>,consume:impl FnMut(dm_ir::SymbolId,dm_ir::SymbolId,dm_syntax::Span)->Result<(),OriginalParentSourceFailure>)->Result<(),OriginalParentSourceFailure>{
  self.visit_original_parent_outcome_spans(checkpoint, |owner| Ok(select(owner)?.map(|requested| (requested, false))), consume)
 }
 /// The same current syntax/source coordinate traversal, with a separately
 /// authenticated fixed-root outcome where the requested type exists.
 pub fn visit_original_parent_outcome_spans(&self,checkpoint:&dyn Fn()->std::io::Result<()>,mut select:impl FnMut(dm_ir::SymbolId)->Result<Option<(dm_ir::SymbolId,bool)>,OriginalParentSourceFailure>,mut consume:impl FnMut(dm_ir::SymbolId,dm_ir::SymbolId,dm_syntax::Span)->Result<(),OriginalParentSourceFailure>)->Result<(),OriginalParentSourceFailure>{
  checkpoint().map_err(OriginalParentSourceFailure::Operational)?;if self.source_mapping().initial_environment()!=dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err("parent outcome requires actual Original source".into())}
  fn visit(item:super::ItemView<'_>,scope:&str,tree:&crate::SemanticTree,checkpoint:&dyn Fn()->std::io::Result<()>,select:&mut impl FnMut(dm_ir::SymbolId)->Result<Option<(dm_ir::SymbolId,bool)>,OriginalParentSourceFailure>,consume:&mut impl FnMut(dm_ir::SymbolId,dm_ir::SymbolId,dm_syntax::Span)->Result<(),OriginalParentSourceFailure>)->Result<(),OriginalParentSourceFailure>{
   checkpoint().map_err(OriginalParentSourceFailure::Operational)?;if item.kind()!=dm_syntax::ItemKind::Type{return Ok(())}let owner=crate::adapter::absolute(scope,item.header())?;let owner_id=dm_ir::SymbolId::of(&owner);
   if let Some((parent,sealed))=select(owner_id)?{
    let id=tree.lookup_type(owner_id).ok_or("parent outcome owner absent")?;if tree.parent(id).and_then(|id|tree.type_node(id)).is_none_or(|row|row.path!=dm_ir::SymbolId::of("/"))||tree.lookup_type(parent).is_some()!=sealed{return Err("parent outcome does not describe current root fallback".into())}
    if sealed && (!["/datum","/list","/alist","/savefile"].contains(&owner.as_str()) || scope!="/" || item.header().trim()!=owner) {
        return Err("sealed parent outcome lacks its issued direct builtin declaration".into());
    }
    let mut found=None;for child in item.children(){checkpoint().map_err(OriginalParentSourceFailure::Operational)?;if let Some((key,value))=child.header().split_once('='){if key.trim()=="parent_type"{if dm_ir::SymbolId::of(&crate::adapter::absolute("/",value.trim())?)!=parent||(sealed && tree.symbols().text(parent)!=Some(value.trim()))||found.is_some(){return Err("parent outcome source assignment is ambiguous".into())}let at=child.declaration_cursor().ok_or("parent assignment lacks actual primary token cursor")?;let end=at.checked_add(1).ok_or("parent primary cursor overflow")?;found=Some(dm_syntax::Span::new(at,end));}}}if let Some(span)=found{consume(owner_id,parent,span)?;}
   }
   for child in item.children(){visit(child,&owner,tree,checkpoint,select,consume)?;}Ok(())
  }
  for item in self.syntax.items(){visit(item,"/",self.tree(),checkpoint,&mut select,&mut consume)?;}checkpoint().map_err(OriginalParentSourceFailure::Operational)
 }
 pub fn original_parent_assignment_span(&self,wanted:dm_ir::SymbolId,parent:dm_ir::SymbolId,checkpoint:&dyn Fn()->std::io::Result<()>)->Result<dm_syntax::Span,OriginalParentSourceFailure>{
  let mut found=None;self.visit_original_parent_assignment_spans(checkpoint,|owner|Ok((owner==wanted).then_some(parent)),|_,_,span|{if found.replace(span).is_some(){return Err("parent outcome source assignment is ambiguous".into())}Ok(())})?;found.ok_or_else(||OriginalParentSourceFailure::from("parent outcome has no original native assignment"))
 }
}

#[path="frontend_current_body_archive.rs"]mod current_body;
pub use current_body::CurrentArchivedBody;
