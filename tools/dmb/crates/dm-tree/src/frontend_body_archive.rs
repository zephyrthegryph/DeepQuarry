//! Current parser-issued body inputs, shared without retaining a frontend revision.
use super::*;
use crate::SemanticTree;

/// Only ColdFrontend can issue this archive. Coordinates belong to this exact
/// tree/source/syntax owner; an archive cannot be rebound to a different revision.
pub struct BodyArchive {
    source: dm_preprocess::SourceText,
    syntax: Arc<DeclarationSyntax>,
    bodies: Arc<[BodyOccurrence]>,
    tree: Arc<SemanticTree>,
    mapping: Arc<SourceExportMapping>,
    callables: Arc<CallableRoster>,
    body_indices: Arc<HashMap<OccurrenceId, usize>>,
}
pub struct ArchivedBody<'a> {
    archive: &'a BodyArchive,
    occurrence: &'a BodyOccurrence,
    statements: Arc<StatementBody>,
    header: Item,
}
impl ArchivedBody<'_> {
    pub fn occurrence(&self) -> &BodyOccurrence {
        self.occurrence
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
            source: self.issued_arena.clone(),
            syntax: Arc::clone(&self.issued_syntax),
            bodies: Arc::clone(&self.issued_bodies),
            tree: Arc::clone(&self.snapshot.tree),
            mapping: Arc::clone(self.source_export_mapping()?),
            callables: Arc::clone(&self.callable_roster),
            body_indices: Arc::clone(&self.body_by_declaration),
        }))
    }
}
impl BodyArchive {
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
            return Err(internal("body archive query exceeds 1 MiB input limit"));
        }
        let mut item = dm_syntax::parse_proc_at_span(&self.source, occurrence.expanded_span)
            .map_err(|error| Diagnostic {
                kind: syntax_kind(error.kind),
                stage: DiagnosticStage::Syntax,
                location: self
                    .mapping
                    .output(error.span.start)
                    .or_else(|| Some(occurrence.source.clone())),
                message: error.message,
            })?;
        let statements = parse_statements(&mut item, &self.source, &self.syntax, |_| true);
        Ok(ArchivedBody {
            archive: self,
            occurrence,
            statements,
            header: item,
        })
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
        declaration_headers,
        stored_candidates,
    })
}
