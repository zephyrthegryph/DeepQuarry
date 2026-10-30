//! Current parser-issued body inputs, shared without retaining a frontend revision.
use super::*;
use crate::SemanticTree;

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
        self.source
            .get(entry.name.range())
            .ok_or_else(|| "local name outside original source arena".into())
    }
    pub fn type_path_width(&self, entry: &dm_syntax::LocalVariableSyntax) -> Result<usize, String> {
        self.require_entry(entry)?;
        let mut width = if entry.array_suffix { 5usize } else { 0 };
        for span in &entry.type_components {
            let text = self
                .source
                .get(span.range())
                .ok_or("local type component outside original source arena")?;
            width = width
                .checked_add(text.len())
                .and_then(|n| n.checked_add(1))
                .ok_or("original local type width overflow")?;
        }
        Ok(width)
    }
    /// Conservative transient type-map admission, computed without formatting
    /// or allocating. It is not retained model data or an RSS measurement.
    pub fn scope_admission(&self) -> Result<usize, String> {
        Ok(self.scope_charge)
    }
    fn compute_scope_admission(&self) -> Result<usize, String> {
        self.entries()?.iter().try_fold(4096usize, |sum, entry| {
            self.name(entry)?
                .len()
                .checked_add(self.type_path_width(entry)?)
                .and_then(|n| n.checked_mul(4))
                .and_then(|n| n.checked_add(256))
                .and_then(|n| sum.checked_add(n))
                .ok_or_else(|| "original local scope admission overflow".into())
        })
    }
    pub fn type_path(
        &self,
        entry: &dm_syntax::LocalVariableSyntax,
    ) -> Result<Option<String>, String> {
        self.require_entry(entry)?;
        entry.type_path(self.source).map_err(str::to_owned)
    }
}
pub(super) fn checked_source_locals<'a>(
    tree: &'a SemanticTree,
    occurrence: &'a BodyOccurrence,
    syntax: &'a StatementBody,
    source: &'a str,
) -> Result<SourceLocalView<'a>, String> {
    if !syntax.syntax_complete() {
        return Err("local source body has unissued syntax".into());
    }
    let mut view = SourceLocalView {
        tree,
        occurrence,
        syntax,
        source,
        scope_charge: 0,
    };
    view.scope_charge = view.compute_scope_admission()?;
    Ok(view)
}
pub struct ArchivedBody<'a> {
    archive: &'a BodyArchive,
    occurrence: &'a BodyOccurrence,
    statements: Arc<StatementBody>,
    header: Item,
    opening_parenthesis: Option<dm_syntax::Span>,
    parameters: Arc<dm_syntax::ParameterSignature>,
}
/// Opaque original source binding, not a table copied from runtime metadata.
/// Only an exact original body owner can issue this stack-only borrowed view.
#[derive(Clone, Copy)]
pub struct SourceParameterView<'a> {
    tree: &'a SemanticTree,
    occurrence: &'a BodyOccurrence,
    signature: &'a dm_syntax::ParameterSignature,
    source: &'a str,
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
        self.source
            .get(p.name().range())
            .ok_or_else(|| "parameter name outside exact original arena".into())
    }
    pub fn type_path(&self, p: &dm_syntax::ParameterSyntax) -> Result<Option<String>, String> {
        self.require_entry(p)?;
        p.type_path(self.source).map_err(str::to_owned)
    }
}
/// Request-local handle for the SAME existing parameter root allocation.
/// Its frontend/occurrence references keep their original issuer lifetime;
/// cloning the Arc cannot create a copied AST or another semantic owner.
pub struct OriginalHeaderExpressionHandle<'frontend> {
    frontend: &'frontend ColdFrontend,
    occurrence: &'frontend BodyOccurrence,
    parameters: Arc<dm_syntax::ParameterSignature>,
    metadata: &'frontend dm_ir::ProcedureMetadata,
    source: &'frontend str,
}
pub(super) fn capture_header_expression_handle<'frontend>(
    frontend: &'frontend ColdFrontend,
    occurrence: &'frontend BodyOccurrence,
    parameters: Arc<dm_syntax::ParameterSignature>,
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
        }
        .header_expressions()?;
        view.require_for(&self.frontend.snapshot.tree, self.occurrence, self.metadata)?;
        Ok(view)
    }
    pub fn storage(&self) -> &Arc<dm_syntax::ParameterSignature> {
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
    if parameters.header() != header.header_span {
        return Err("parameter receipt belongs to another original header".into());
    }
    let member = tree
        .member(occurrence.member)
        .ok_or("parameter callable member unavailable")?;
    let metadata = member
        .metadata
        .procedure
        .as_ref()
        .ok_or("parameter callable signature unavailable")?;
    for (ordinal, declaration) in parameters.absolute_declarations()?.iter().enumerate() {
        if declaration.ordinal() != ordinal {
            return Err("absolute header declaration ordinal mismatch".into());
        }
        let path = declaration.written_path(source)?;
        let id = tree
            .lookup_type(dm_ir::SymbolId::of(path))
            .ok_or("original absolute header type declaration was not issued by native frontend")?;
        let actual = tree
            .type_node(id)
            .ok_or("original absolute header type unavailable")?;
        if tree.symbols().text(actual.path) != Some(path) {
            return Err("original absolute header type spelling differs".into());
        }
    }
    let mut native = metadata.signature.parameters.iter();
    let mut variadic = false;
    for (ordinal, entry) in parameters.entries()?.iter().enumerate() {
        if entry.ordinal() != ordinal {
            return Err("parameter original ordinal mismatch".into());
        }
        let name = source
            .get(entry.name().range())
            .ok_or("parameter name outside exact original arena")?;
        if entry.variadic() {
            if name != "..." || variadic {
                return Err("parameter variadic receipt mismatch".into());
            }
            variadic = true;
            continue;
        }
        let actual = native
            .next()
            .ok_or("parameter primary/runtime ordinal mismatch")?;
        if tree.symbols().text(actual.name) != Some(name) {
            return Err("parameter primary/runtime name mismatch".into());
        }
    }
    if native.next().is_some() || metadata.signature.variadic != variadic {
        return Err("parameter primary/runtime roster mismatch".into());
    }
    Ok(SourceParameterView {
        tree,
        occurrence,
        signature: parameters,
        source,
    })
}
impl ArchivedBody<'_> {
    pub fn source_locals(&self) -> Result<SourceLocalView<'_>, String> {
        checked_source_locals(
            self.tree(),
            self.occurrence(),
            self.statement_body(),
            self.archive_owner().expanded_source(),
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
    pub fn parameter_storage(&self) -> &Arc<dm_syntax::ParameterSignature> {
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
                parameters: Arc::clone(&shared.parameters),
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
            parameters: Arc::new(issued.parameters),
            header: item,
        })
    }
    /// Borrow only the newly retained original header input metadata. Current
    /// archive/source/tree authority and source bytes remain their existing owners.
    pub fn visit_original_header_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        for chunk in self.syntax.chunks().iter() {
            chunk
                .shared_relative()
                .visit_original_header_storage(&mut visit);
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
    finish_statements(item, parsed, supported)
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
    struct Original<'a, 'op> {
        syntax: &'a DeclarationSyntax,
        body: dm_syntax::Span,
        code: &'a Arc<BodyCodeIdentity>,
        admission: &'a dm_syntax::SettingAdmission<'op>,
    }
    impl dm_syntax::SettingSyntaxProvider for Original<'_, '_> {
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
    let parsed = dm_syntax::parse_body_items_with_context_and_settings(
        &item.children,
        source,
        &|at| syntax.declaration_header_at(at),
        &provider,
        admission,
    );
    if let Some(actual) = admission.take_operational_error() {
        return Err(BodySyntaxFailure::Operational(actual));
    }
    admission
        .checkpoint()
        .map_err(BodySyntaxFailure::Operational)?;
    Ok(finish_statements(item, parsed, supported))
}
fn finish_statements(
    item: &mut Item,
    parsed: dm_syntax::ParsedBody,
    supported: fn(&[dm_syntax::Statement]) -> bool,
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
    pub fn callable_header_policy_origin(&self,member:crate::MemberId)->Result<SourceNoteOrigin,String>{
        if !matches!(self.tree.member(member).ok_or("callable header member unavailable")?.kind,crate::MemberKind::Proc|crate::MemberKind::Verb){
            return Err("callable header requires source procedure/verb".into());
        }
        let ordinal=self.callables.ordinal(member).ok_or("callable header member not in original roster")?;
        let occurrence=self.bodies.get(ordinal).ok_or("callable header original occurrence absent")?;
        if occurrence.member!=member{return Err("callable header roster occurrence differs".into());}
        let code=self.body_codes.get(ordinal).ok_or("callable header original code absent")?;
        let opening=self.syntax.original_callable_opening(occurrence.expanded_span,&code.identity)?;
        self.source_note_point(opening)
    }
    pub fn callable_note_origin(
        &self,
        identity: dm_ir::ProcedureIdentity,
    ) -> Result<SourceNoteOrigin, String> {
        self.callable_note_origin_with(identity, |archive, ordinal| {
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
        if !body.belongs_to(self)
            || !std::ptr::eq(body.occurrence(), &self.occurrences()[ordinal])
            || !body.statement_body().syntax_complete()
        {
            return Err("callable note primary source unavailable".into());
        }
        let opening = body
            .signature_opening_parenthesis()
            .ok_or("primary callable opening token unavailable")?;
        self.source_note_point(opening.start).map_err(E::from)
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
}

#[path = "frontend_checker_variable_properties.rs"]
mod checker_variable_properties;
pub use checker_variable_properties::CheckerVariableProperties;

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
