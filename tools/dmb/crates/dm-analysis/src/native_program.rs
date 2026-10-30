//! Private borrowed facade over the compiler's existing semantic owners.
//! It never copies a type tree, source table or executable body. Archive mode
//! lets the retained daemon analyze after the transient compiler frontend dies.
use crate::{checks::BodyView, untyped::Unsupported};
use dm_tree::{
    frontend::{
        ArchivedBody, BodyArchive, BodyArena, BodyOccurrence, CallableRoster, ColdFrontend,
        StatementBody,
    },
    SemanticTree,
};

#[derive(Clone, Copy)]
pub(crate) enum Origin<'a> {
    Live(&'a ColdFrontend),
    Archive(&'a BodyArchive),
}
impl<'a> Origin<'a> {
    pub(crate) fn tree(self) -> &'a SemanticTree {
        match self {
            Self::Live(frontend) => frontend.snapshot.tree.as_ref(),
            Self::Archive(archive) => archive.tree(),
        }
    }
    pub(crate) fn roster(self) -> Result<&'a CallableRoster, Unsupported> {
        match self {
            Self::Live(frontend) => frontend
                .callable_roster()
                .map(|r| r.as_ref())
                .map_err(Unsupported),
            Self::Archive(archive) => Ok(archive.callables().as_ref()),
        }
    }
    pub(crate) fn bodies(self) -> &'a [BodyOccurrence] {
        match self {
            Self::Live(frontend) => &frontend.bodies,
            Self::Archive(archive) => archive.occurrences(),
        }
    }
    pub(crate) fn is_live(self, candidate: &ColdFrontend) -> bool {
        matches!(self, Self::Live(frontend) if std::ptr::eq(frontend, candidate))
    }
    pub(crate) fn is_archive(self, candidate: &BodyArchive) -> bool {
        matches!(self, Self::Archive(archive) if std::ptr::eq(archive, candidate))
    }
    pub(crate) fn owns_archive_body(self, candidate: &ArchivedBody<'_>) -> bool {
        matches!(self, Self::Archive(archive) if candidate.belongs_to(archive))
    }
    /// The callback cannot return a borrow of a temporary archive parse. Native
    /// inference stores owned equations, never a second retained AST or model.
    pub(crate) fn with_body<T>(
        self,
        arena: Option<&BodyArena<'a>>,
        ordinal: usize,
        consume: impl FnOnce(
            &StatementBody,
            &BodyOccurrence,
            dm_tree::frontend::SourceParameterView<'_>,
            dm_tree::frontend::SourceLocalView<'_>,
        ) -> Result<T, Unsupported>,
    ) -> Result<T, Unsupported> {
        match self {
            Self::Live(frontend) => {
                let occurrence = frontend
                    .bodies
                    .get(ordinal)
                    .ok_or_else(|| Unsupported("native body ordinal absent".into()))?;
                arena
                    .ok_or_else(|| Unsupported("compiler body arena absent".into()))?
                    .with_parsed(occurrence, |body| {
                        let view = BodyView::new(frontend, body).map_err(Unsupported)?;
                        let locals = body.source_locals().map_err(Unsupported)?;
                        crate::untyped::require_local_source_projection(locals)?;
                        consume(
                            view.syntax(),
                            body.occurrence(),
                            body.source_parameters().map_err(Unsupported)?,
                            locals,
                        )
                    })
                    .map_err(|error| Unsupported(error.message))?
            }
            Self::Archive(archive) => {
                let body = archive
                    .parse(ordinal)
                    .map_err(|error| Unsupported(error.message))?;
                if !body.statement_body().syntax_complete() {
                    return Err(Unsupported(
                        "archive has unsupported or malformed native syntax".into(),
                    ));
                }
                let locals = body.source_locals().map_err(Unsupported)?;
                crate::untyped::require_local_source_projection(locals)?;
                consume(
                    body.statement_body(),
                    body.occurrence(),
                    body.source_parameters().map_err(Unsupported)?,
                    locals,
                )
            }
        }
    }
}

// Stack-only selection of the original body demand path. These strategies
// retain no source/model/cache and do not grant source or quota authority.
pub(crate) trait BodyDemand: Copy {
    type Failure: From<Unsupported>;
    fn with_archived<T>(
        self,
        archive: &BodyArchive,
        ordinal: usize,
        consume: impl FnOnce(&ArchivedBody<'_>) -> Result<T, Unsupported>,
    ) -> Result<T, Self::Failure>;
    fn with_body<'a, T>(
        self,
        origin: Origin<'a>,
        arena: Option<&BodyArena<'a>>,
        ordinal: usize,
        consume: impl FnOnce(
            &StatementBody,
            &BodyOccurrence,
            dm_tree::frontend::SourceParameterView<'_>,
            dm_tree::frontend::SourceLocalView<'_>,
        ) -> Result<T, Unsupported>,
    ) -> Result<T, Self::Failure>;
}
#[derive(Clone, Copy)]
pub(crate) struct CompatibilityBodyDemand;
impl BodyDemand for CompatibilityBodyDemand {
    type Failure = Unsupported;
    fn with_archived<T>(
        self,
        archive: &BodyArchive,
        ordinal: usize,
        consume: impl FnOnce(&ArchivedBody<'_>) -> Result<T, Unsupported>,
    ) -> Result<T, Self::Failure> {
        let body = archive.parse(ordinal).map_err(|e| Unsupported(e.message))?;
        consume(&body)
    }
    fn with_body<'a, T>(
        self,
        origin: Origin<'a>,
        arena: Option<&BodyArena<'a>>,
        ordinal: usize,
        consume: impl FnOnce(
            &StatementBody,
            &BodyOccurrence,
            dm_tree::frontend::SourceParameterView<'_>,
            dm_tree::frontend::SourceLocalView<'_>,
        ) -> Result<T, Unsupported>,
    ) -> Result<T, Self::Failure> {
        origin.with_body(arena, ordinal, consume)
    }
}
#[derive(Clone, Copy)]
pub(crate) struct CheckedBodyDemand;
impl BodyDemand for CheckedBodyDemand {
    type Failure = crate::value_query::ValueQueryFailure;
    fn with_archived<T>(
        self,
        archive: &BodyArchive,
        ordinal: usize,
        consume: impl FnOnce(&ArchivedBody<'_>) -> Result<T, Unsupported>,
    ) -> Result<T, Self::Failure> {
        let body = archive.parse_checked(ordinal)?;
        consume(&body).map_err(Into::into)
    }
    fn with_body<'a, T>(
        self,
        origin: Origin<'a>,
        arena: Option<&BodyArena<'a>>,
        ordinal: usize,
        consume: impl FnOnce(
            &StatementBody,
            &BodyOccurrence,
            dm_tree::frontend::SourceParameterView<'_>,
            dm_tree::frontend::SourceLocalView<'_>,
        ) -> Result<T, Unsupported>,
    ) -> Result<T, Self::Failure> {
        match origin {
            Origin::Live(frontend) => {
                let occurrence = frontend
                    .bodies
                    .get(ordinal)
                    .ok_or_else(|| Unsupported("native body ordinal absent".into()))?;
                arena
                    .ok_or_else(|| Unsupported("compiler body arena absent".into()))?
                    .with_parsed_checked(occurrence, |body| {
                        let view = BodyView::new(frontend, body).map_err(Unsupported)?;
                        let locals = body.source_locals().map_err(Unsupported)?;
                        crate::untyped::require_local_source_projection(locals)?;
                        consume(
                            view.syntax(),
                            body.occurrence(),
                            body.source_parameters().map_err(Unsupported)?,
                            locals,
                        )
                    })?
                    .map_err(Into::into)
            }
            Origin::Archive(archive) => {
                let body = archive.parse_checked(ordinal)?;
                if !body.statement_body().syntax_complete() {
                    return Err(Unsupported(
                        "archive has unsupported or malformed native syntax".into(),
                    )
                    .into());
                }
                let locals = body.source_locals().map_err(Unsupported)?;
                crate::untyped::require_local_source_projection(locals)?;
                consume(
                    body.statement_body(),
                    body.occurrence(),
                    body.source_parameters().map_err(Unsupported)?,
                    locals,
                )
                .map_err(Into::into)
            }
        }
    }
}
