//! Lazy compiler-selected facts from the exact successful current capture owners.
use crate::{driver_facts::PreparedAbiUnits, engine_host::EngineResolverHost};
use dm_ir::Resolver;
use dm_resources::native_resolver::NativeResourceResolver;
use std::{cell::RefCell, collections::BTreeMap, io, sync::Arc};
pub(crate) type CapturedResolver =
    NativeResourceResolver<EngineResolverHost<dm_tree::constant_resolution::ScalarSnapshot>>;
pub(crate) type ScalarResolver = EngineResolverHost<dm_tree::constant_resolution::ScalarSnapshot>;
enum ResolverOwner {
    Native(Arc<CapturedResolver>),
    Analysis(Arc<ScalarResolver>),
}
impl ResolverOwner {
    fn host(&self) -> &ScalarResolver {
        match self {
            Self::Native(owner) => owner.tree(),
            Self::Analysis(owner) => owner,
        }
    }
}
impl dm_ir::Resolver for ResolverOwner {
    fn observes_reads(&self) -> bool {
        match self {
            Self::Native(owner) => owner.observes_reads(),
            Self::Analysis(owner) => owner.observes_reads(),
        }
    }
    fn domain_version(&self, domain: dm_ir::ReadDomain) -> Option<u128> {
        match self {
            Self::Native(owner) => owner.domain_version(domain),
            Self::Analysis(owner) => owner.domain_version(domain),
        }
    }
    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        match self {
            Self::Native(owner) => owner.resolve(query),
            Self::Analysis(owner) => owner.resolve(query),
        }
    }
}
pub(super) struct ResolvedContext {
    resolver: ResolverOwner,
    abi: Arc<PreparedAbiUnits>,
    startup: Arc<crate::startup::StartupFacts>,
}
impl ResolvedContext {
    pub(super) fn new(
        resolver: CapturedResolver,
        abi: Arc<PreparedAbiUnits>,
        startup: Arc<crate::startup::StartupFacts>,
    ) -> Self {
        Self {
            resolver: ResolverOwner::Native(Arc::new(resolver.into_metadata())),
            abi,
            startup,
        }
    }
    pub(super) fn for_analysis(
        resolver: ScalarResolver,
        abi: Arc<PreparedAbiUnits>,
        startup: Arc<crate::startup::StartupFacts>,
    ) -> Self {
        Self {
            resolver: ResolverOwner::Analysis(Arc::new(resolver)),
            abi,
            startup,
        }
    }
    pub(super) fn matches_current(&self, frontend: &dm_tree::frontend::ColdFrontend) -> bool {
        Arc::ptr_eq(&self.startup.plan().source.tree, &frontend.snapshot.tree)
            && Arc::ptr_eq(
                &self.startup.plan().source.occurrences,
                &frontend.snapshot.occurrences,
            )
            && Arc::ptr_eq(
                &self.resolver.host().shared_source().source.tree,
                &frontend.snapshot.tree,
            )
    }
    pub(super) fn write_queries(
        &self,
        queries: &[crate::daemon::query::QueryItem],
        output: &mut impl io::Write,
    ) -> io::Result<()> {
        let resolver = dm_tree::procedure_statics::StaticResolver::from_inventory(
            &self.resolver,
            Arc::clone(self.startup.static_inventory()),
        )
        .map_err(io::Error::other)?;
        for query in queries {
            crate::daemon::control::checkpoint()?;
            dm_analysis::tree_export::write_queries_jsonl(
                self.startup.plan().symbols.as_ref(),
                &resolver,
                [dm_analysis::tree_export::AnalysisQuery {
                    subject: query.subject.as_deref(),
                    query: query.query,
                }],
                output,
            )
            .map_err(io::Error::other)?;
        }
        Ok(())
    }
    pub(super) fn query(
        &self,
        archive: &dm_tree::frontend::BodyArchive,
        declaration: u32,
    ) -> io::Result<crate::selected_query::CurrentProcedureReferences> {
        crate::daemon::control::checkpoint()?;
        let index = archive
            .body_index(dm_tree::OccurrenceId(declaration))
            .ok_or_else(|| io::Error::other("current procedure occurrence unavailable"))?;
        let body = archive
            .parse(index)
            .map_err(|error| io::Error::other(error.message))?;
        crate::daemon::control::checkpoint()?;
        let occurrence = body.occurrence();
        let slot = archive
            .callables()
            .ordinal(occurrence.member)
            .ok_or_else(|| io::Error::other("current callable slot unavailable"))?;
        let (member, prepared) = self
            .abi
            .entries()
            .get(slot)
            .ok_or_else(|| io::Error::other("current prepared ABI unavailable"))?;
        if *member != occurrence.member || prepared.abi.is_none() {
            return Err(io::Error::other("current prepared ABI member differs"));
        }
        let identity = archive
            .callables()
            .identity(slot)
            .ok_or_else(|| io::Error::other("current callable identity unavailable"))?;
        let unit = crate::lowering::UnitIdentity {
            owner: identity.owner,
            name: identity.name,
            namespace: if identity.verb {
                crate::lowering::Namespace::Verb
            } else {
                crate::lowering::Namespace::Proc
            },
            occurrence: identity.occurrence,
        };
        let mut inputs = (*prepared.inputs).clone();
        if inputs
            .procedure_identity
            .is_some_and(|issued| issued != identity)
        {
            return Err(io::Error::other("current ABI identity differs"));
        }
        inputs.procedure_identity = Some(identity);
        let symbols = self.startup.plan().symbols.as_ref();
        let owner = symbols
            .text(identity.owner)
            .ok_or_else(|| io::Error::other("current owner spelling missing"))?;
        let name = symbols
            .text(identity.name)
            .ok_or_else(|| io::Error::other("current callable spelling missing"))?;
        inputs.current_type_path = (owner != "/").then(|| owner.into());
        inputs.current_proc_path = Some(format!(
            "{}/{}/{}",
            owner.trim_end_matches('/'),
            if identity.verb { "verb" } else { "proc" },
            name
        ));
        let current = if body.statement_body().may_contain_stored_declarations() {
            dm_tree::procedure_statics::capture_issued_statements(identity, body.statement_body())
        } else {
            dm_tree::procedure_statics::capture_declarations(identity, &[])
        }
        .map_err(io::Error::other)?;
        let issued = self
            .startup
            .procedure(occurrence.declaration)
            .ok_or_else(|| io::Error::other("current startup procedure missing"))?;
        if issued.procedure != current.procedure
            || issued.declarations != current.declarations
            || issued.origins != current.origins
        {
            return Err(io::Error::other("current startup mask differs"));
        }
        // Use the SAME startup-issued static inventory overlay as ordinary
        // analysis/lowering; the scalar host alone cannot resolve local statics.
        let resolver = dm_tree::procedure_statics::StaticResolver::from_inventory(
            &self.resolver,
            Arc::clone(self.startup.static_inventory()),
        )
        .map_err(io::Error::other)?;
        let removed: std::collections::HashSet<_> = current
            .origins
            .iter()
            .map(|origin| (origin.header_span.start, origin.header_span.end))
            .collect();
        let statements = body.statement_body();
        let mask = dm_syntax::StatementMask::from_predicate(
            &statements.parsed().statements,
            |statement| {
                dm_tree::settings::is_setting_header(&statement.raw_header)
                    || removed.contains(&(statement.header_span.start, statement.header_span.end))
            },
        );
        let view = dm_syntax::StatementView::masked(&statements.parsed().statements, &mask);
        let typed_ready = statements
            .parsed()
            .diagnostics
            .iter()
            .all(|diagnostic| mask.hides_diagnostic(diagnostic))
            && dm_codegen_byond::typed_statement_view_supported(view);
        let metadata = body
            .tree()
            .member(occurrence.member)
            .and_then(|node| node.metadata.procedure.as_deref())
            .ok_or_else(|| io::Error::other("current signature missing"))?;
        let debug = Debug {
            body: &body,
            parameters: crate::argument_sources::ParameterDiagnosticSource::from_archive(
                &body, metadata, symbols,
            ),
            sites: RefCell::new(BTreeMap::new()),
        };
        let emitted = if typed_ready {
            crate::lowering::compile_selected_view(
                view,
                &inputs,
                symbols,
                &resolver,
                Some(&debug),
                occurrence.expanded_span,
            )
            .map(|(_, facts)| Some(facts))
        } else {
            // Consume the SAME lossless item producer and setting/static filters.
            // The fallback emitter currently issues no selected-reference ledger;
            // ordinary lowering reports this as unavailable coordinates as well.
            let executable = dm_tree::settings::strip_setting_items(body.header().children.clone());
            let executable =
                dm_tree::procedure_statics::filter_executable_items(executable, &removed);
            crate::lowering::compile_selected_lossless(
                &executable,
                &inputs,
                symbols,
                &resolver,
                Some(&debug),
            )
            .map(|_| None)
        };
        let facts =
            crate::lowering::append_selected_grammar(emitted, statements).map_err(|errors| {
                io::Error::other(format!(
                    "current selected producer rejected body: {}",
                    errors
                        .iter()
                        .map(|error| error.reason.as_str())
                        .collect::<Vec<_>>()
                        .join("; ")
                ))
            })?;
        crate::daemon::control::checkpoint()?;
        crate::selected_query::bind_current(unit, occurrence, facts.as_ref(), |offset| {
            body.location(offset)
        })
        .map_err(|errors| {
            io::Error::other(
                errors
                    .into_iter()
                    .map(|error| error.message)
                    .collect::<Vec<_>>()
                    .join("; "),
            )
        })
    }
    pub(super) fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        census.prepared_abi_units(&self.abi);
        census.startup_facts(&self.startup);
        match &self.resolver {
            ResolverOwner::Native(owner) => census.resolved_query_host(owner),
            ResolverOwner::Analysis(owner) => census.resolved_analysis_host(owner),
        }
    }
}
struct Debug<'a, 'archive> {
    body: &'a dm_tree::frontend::ArchivedBody<'archive>,
    parameters: Option<crate::argument_sources::ParameterDiagnosticSource<'a>>,
    sites: RefCell<BTreeMap<usize, u32>>,
}
impl dm_codegen_byond::DebugSourceProvider for Debug<'_, '_> {
    fn parameter_declaration(
        &self,
        name: &str,
    ) -> Result<Option<dm_codegen_byond::LowerSpan>, String> {
        match &self.parameters {
            Some(source) => source.declaration(name),
            None => Ok(None),
        }
    }
    fn entry_ordinal(&self) -> Result<u32, String> {
        self.ordinal(self.body.header().header_span.start)
    }
    fn ordinal(&self, offset: usize) -> Result<u32, String> {
        self.body
            .location(offset)
            .ok_or("current debug origin unavailable")?;
        let mut sites = self.sites.borrow_mut();
        let next = u32::try_from(sites.len()).map_err(|_| "current debug ordinal overflow")?;
        Ok(*sites.entry(offset).or_insert(next))
    }
}

#[cfg(test)]
#[path = "runner_query_resolved_tests.rs"]
mod tests;
