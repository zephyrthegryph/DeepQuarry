//! Explicit source-only role; ordinary runtime-resolved source queries unchanged.
use super::*;
struct NativeSourceContext<'a> {
    snapshot: &'a SourceSnapshot,
    tree: &'a dm_tree::SemanticTree,
}
impl NativeSourceContext<'_> {
    fn write(
        &self,
        questions: &[crate::daemon::query::QueryItem],
        output: &mut impl std::io::Write,
    ) -> std::io::Result<()> {
        use std::io;
        if !self.snapshot.matches_tree(self.tree) {
            return Err(io::ErrorKind::InvalidInput.into());
        }
        self.snapshot.require_semantic_source_encoding()?;
        self.snapshot
            .native_raw_queries
            .as_ref()
            .ok_or(io::ErrorKind::Unsupported)?
            .write_source_question_batch(
                self.snapshot
                    .source_answers
                    .as_deref()
                    .ok_or(io::ErrorKind::Unsupported)?,
                self.tree,
                self.snapshot
                    .source_mapping
                    .as_deref()
                    .ok_or(io::ErrorKind::Unsupported)?,
                self.snapshot
                    .body_archive
                    .as_deref()
                    .ok_or(io::ErrorKind::Unsupported)?,
                questions,
                self.snapshot.source_revision,
                output,
            )
    }
}
impl SourceSnapshot {
    pub(crate) fn require_source_query_role(
        &self,
        request: &crate::daemon::query::QueryRequest,
    ) -> std::io::Result<()> {
        if !self.source_question_role {
            return Ok(());
        }
        // Empty discovery reads pins only. Every substantive query must be the
        // ONE exact prepared ordered batch; generic/mixed questions cannot
        // bypass that authorization through another facade.
        if request.queries.is_empty()
            && (request.source_queries.is_empty()
                || matches!(
                    request.source_queries.as_slice(),
                    [crate::daemon::query::SourceQuery::ResolvedQueries { .. }]
                ))
        {
            return Ok(());
        }
        Err(std::io::Error::new(
            std::io::ErrorKind::Unsupported,
            "source-only prepared frame requires its exact resolved question batch",
        ))
    }
    pub(super) fn write_source_questions(
        &self,
        questions: &[crate::daemon::query::QueryItem],
        tree: &dm_tree::SemanticTree,
        output: &mut impl std::io::Write,
    ) -> std::io::Result<()> {
        NativeSourceContext {
            snapshot: self,
            tree,
        }
        .write(questions, output)
    }
}
