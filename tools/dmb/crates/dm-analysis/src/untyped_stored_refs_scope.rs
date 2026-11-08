//! Stored-reference local-place projection from ORIGINAL primary facts.
//! No source type parser, model, runtime inference or new body graph.
use super::{stored_refs::is_collection_type, *};
use dm_syntax::{LocalSourceKind, LocalVariableSyntax};
pub(crate) struct StoredScope<'a> {
    pub walker: Walker<'a, dm_tree::SemanticTree>,
    /// Every local shadows fields, even when it is not a persistent list.
    pub static_lists: HashMap<String, Span>,
}
fn plain(name: &str) -> bool {
    let mut c = name.chars();
    c.next().is_some_and(|c| c == '_' || c.is_alphabetic())
        && c.all(|c| c == '_' || c.is_alphanumeric())
}
struct Collect<'a,'w,W:crate::policy_body_demand::WorkspaceWork> {
    source: dm_tree::frontend::SourceLocalView<'a>,
    facts: &'a [LocalVariableSyntax],
    types: HashMap<String, String>,
    places: HashMap<String, Span>,
    error: Option<W::Error>,
    work:&'w mut W,
}
impl<'a,W:crate::policy_body_demand::WorkspaceWork> Collect<'a,'_,W> {
    fn entries(&mut self,span:Span)->Result<Vec<(usize,&'a LocalVariableSyntax)>,W::Error>{self.work.checkpoint()?;let start=self.facts.partition_point(|f|f.name.start<span.start);let mut out=Vec::new();for(i,fact)in self.facts[start..].iter().enumerate().take_while(|(_,f)|f.name.start<span.end){self.work.checkpoint()?;if W::CHECKED{self.work.retain(128)?;out.try_reserve(1).map_err(|_|self.work.allocation_failed())?;}out.push((start+i,fact));}Ok(out)}

    fn put(
        &mut self,
        index: usize,
        fact: &LocalVariableSyntax,
        span: Span,
        absent: bool,
        allow_static: bool,
    ) -> Result<(), W::Error> {
        self.work.checkpoint()?;
        let name = self.source.name(fact).map_err(Unsupported)?;
        if absent && self.types.contains_key(name) {
            return Ok(());
        }
        let ty = self
            .source
            .type_path(fact)
            .map_err(Unsupported)?
            .unwrap_or_default();
        if W::CHECKED{let bytes=name.len().checked_mul(4).and_then(|n|n.checked_add(ty.len().checked_mul(4)?)).and_then(|n|n.checked_add(512)).ok_or_else(||self.work.overflow())?;self.work.retain(bytes)?;self.types.try_reserve(1).map_err(|_|self.work.allocation_failed())?;self.places.try_reserve(1).map_err(|_|self.work.allocation_failed())?;}
        self.types.insert(name.to_owned(), ty.clone());
        self.places.remove(name);
        let grouped = self
            .facts
            .get(index + 1)
            .is_some_and(|next| next.source_kind == LocalSourceKind::CommaContinuation);
        if allow_static
            && fact.source_kind == LocalSourceKind::Statement
            && !grouped
            && fact.source_modifiers & 1 != 0
            && is_collection_type(&ty)
        {
            self.places.insert(name.to_owned(), span);
        }
        Ok(())
    }
    fn one(&mut self, span: Span, absent: bool, allow_static: bool) -> Result<(), W::Error> {
        let facts = self.entries(span)?;
        let [(i, fact)] = facts.as_slice() else {
            return Err(Unsupported(
                "stored local primary occurrence is missing or ambiguous".into(),
            ).into());
        };
        let i = *i;
        let fact = *fact;
        self.put(i, fact, span, absent, allow_static)
    }
    fn bare(&mut self, name: &str) -> Result<(), W::Error> {
        self.work.checkpoint()?;
        if !plain(name) {
            return Err(Unsupported("stored implicit typed/annotated for binding needs original primary declaration facts".into()).into());
        }
        if !self.types.contains_key(name) {
            if W::CHECKED{let bytes=name.len().checked_add(256).ok_or_else(||self.work.overflow())?;self.work.retain(bytes)?;self.types.try_reserve(1).map_err(|_|self.work.allocation_failed())?;}
            self.types.insert(name.to_owned(), String::new());
            self.places.remove(name);
        }
        Ok(())
    }
}
impl<W:crate::policy_body_demand::WorkspaceWork> TypedVisitor for Collect<'_,'_,W> {
    fn projected_expression(
        &mut self,
        _view: dm_syntax::ProjectedExprView<'_>,
        _path: &[dm_syntax::NodeStep],
    ) -> dm_syntax::VisitDecision {
        match self.work.checkpoint(){Ok(())=>VisitDecision::Descend,Err(e)=>{self.error=Some(e);VisitDecision::Stop}}
    }

    fn statement(&mut self, st: &Statement, _: &[NodeStep]) -> VisitDecision {
        if self.error.is_some() {
            return VisitDecision::Stop;
        }
        let result = (|| -> Result<(), W::Error> {
            self.work.checkpoint()?;
            match &st.kind {
                StatementKind::Var { .. } => self.one(st.header_span, false, true)?,
                StatementKind::For { control, .. } => match control {
                    ForControl::All { .. } => self.one(st.header_span, true, false)?,
                    ForControl::Each { binding, .. } => {
                        if self.entries(st.header_span)?.is_empty() {
                            self.bare(binding)?
                        } else {
                            self.one(st.header_span, true, false)?
                        }
                    }
                    ForControl::Pair {
                        key_binding,
                        value_binding,
                        ..
                    } => {
                        let facts = self.entries(st.header_span)?;
                        if facts.is_empty() {
                            self.bare(key_binding)?;
                            self.bare(value_binding)?;
                        } else {
                            if facts.len() != 2 {
                                return Err(Unsupported(
                                    "stored pair-loop binding facts incomplete".into(),
                                ).into());
                            }
                            for (_, f) in facts {
                                let name = self.source.name(f).map_err(Unsupported)?;
                                self.bare(name)?;
                            }
                        }
                    }
                    ForControl::CStyle {
                        initializer: Some(ForInitializer::Declare { .. }),
                        ..
                    } => self.one(st.header_span, false, false)?,
                    // Actual old collect_locals deliberately has no ForRange case.
                    ForControl::Range { .. }
                    | ForControl::RangeImplicitArray { .. }
                    | ForControl::CStyle { .. } => (),
                },
                _ => (),
            }
            Ok(())
        })();
        if let Err(error) = result {
            self.error = Some(error);
            VisitDecision::Stop
        } else {
            VisitDecision::Descend
        }
    }
}
pub(crate) fn archived_stored_scope<'a>(
    body: &'a ArchivedBody<'_>,
    exempt_types: &'a [String],
    local_source: dm_tree::frontend::SourceLocalView<'a>,
) -> Result<StoredScope<'a>, Unsupported> {
    archived_stored_scope_using(body,exempt_types,local_source,&mut StoredScopeNoop)
}
pub(crate) fn archived_stored_scope_using<'a,W:crate::policy_body_demand::WorkspaceWork>(body:&'a ArchivedBody<'_>,exempt_types:&'a[String],local_source:dm_tree::frontend::SourceLocalView<'a>,work:&mut W)->Result<StoredScope<'a>,W::Error>{
    work.checkpoint()?;
    let archive = body.archive_owner();
    let tree = archive.tree();
    // The exact local view below already checked syntax completeness in the
    // archive's own language mode. Stored scope needs no runtime text decoding.
    if !body.belongs_to(archive) {
        return Err(Unsupported(
            "stored-reference body is not a complete original primary body".into(),
        ).into());
    }
    local_source
        .require_for(tree, body.occurrence(), body.statement_body())
        .map_err(Unsupported)?;
    let member = tree
        .member(body.occurrence().member)
        .ok_or_else(|| Unsupported("stored callable member unavailable".into()))?;
    let owner = tree
        .type_node(member.owner)
        .ok_or_else(|| Unsupported("stored callable owner unavailable".into()))?
        .path;
    let profile = tree
        .checker_builtin_profile()
        .ok_or_else(|| Unsupported("stored parameter source profile unavailable".into()))?;
    let parameters = body.checker_parameters(profile).map_err(Unsupported)?;
    let mut collect = Collect {
        source: local_source,
        facts: body
            .statement_body()
            .parsed()
            .local_variables
            .entries()
            .map_err(|e| Unsupported(e.into()))?,
        types: HashMap::new(),
        places: HashMap::new(),
        error: None,
        work,
    };
    parameters
        .require_for(tree, body.occurrence())
        .map_err(Unsupported)?;
    for parameter in parameters.entries().map_err(Unsupported)? {
        let name = parameters.name(parameter).map_err(Unsupported)?;
        let ty = parameters
            .type_path(parameter)
            .map_err(Unsupported)?
            .unwrap_or_default();
        collect.work.checkpoint()?;if W::CHECKED{let bytes=name.len().checked_add(ty.len()).and_then(|n|n.checked_add(256)).ok_or_else(||collect.work.overflow())?;collect.work.retain(bytes)?;collect.types.try_reserve(1).map_err(|_|collect.work.allocation_failed())?;}
        collect.types.insert(name.to_owned(), ty);
    }
    dm_syntax::visit_statements(&body.statement_body().parsed().statements, &mut collect);
    if let Some(error) = collect.error {
        return Err(error);
    }
    Ok(StoredScope {
        walker: Walker {
            tree,
            archive: Some(archive),
            resolver: tree,
            owner,
            locals: collect.types,
            exempt_types,
            found: BTreeMap::new(),
            error: None,
        },
        static_lists: collect.places,
    })
}

struct StoredScopeNoop;impl crate::policy_body_demand::WorkspaceWork for StoredScopeNoop{type Error=Unsupported;const CHECKED:bool=false;fn checkpoint(&mut self)->Result<(),Unsupported>{Ok(())}fn retain(&mut self,_:usize)->Result<(),Unsupported>{Ok(())}fn temporary(&mut self,_:usize)->Result<(),Unsupported>{Ok(())}fn overflow(&mut self)->Unsupported{Unsupported("stored scope geometry overflow".into())}fn allocation_failed(&mut self)->Unsupported{Unsupported("stored scope allocation refused".into())}fn body<'a>(&mut self,a:&'a dm_tree::frontend::BodyArchive,n:usize)->Result<ArchivedBody<'a>,Unsupported>{a.parse(n).map_err(|e|Unsupported(e.message))}}
