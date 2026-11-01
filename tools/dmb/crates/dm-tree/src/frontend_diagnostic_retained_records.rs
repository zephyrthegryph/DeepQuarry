//! Original native records for a consuming valid diagnostic transfer.
use super::*;
use crate::frontend::ColdFrontend;
use std::sync::Weak;
pub(crate) struct DiagnosticRetainedRecords {
    index: crate::declaration_contributions::KeyedDeclarations,
    symbols: Arc<dm_ir::SymbolTable>,
    catalog: Option<Arc<crate::frontend::symbol_catalog::SymbolCatalog>>,
    engine: Option<EngineSeed>,
    owner: Weak<SemanticTree>,
}
impl DiagnosticRetainedRecords {
    pub(in crate::frontend) fn visit_storage(&self,mut visit:impl FnMut(crate::frontend::AnalysisRetentionStorage<'_>)){
        use crate::frontend::AnalysisRetentionStorage as V;
        visit(V::Declarations(&self.index));visit(V::Symbols(&self.symbols));
        if let Some(catalog)=&self.catalog{visit(V::Allocation{address:Arc::as_ptr(catalog)as usize,bytes:std::mem::size_of_val(catalog.as_ref())});let(symbols,source,engine)=catalog.storage_parts();visit(V::Symbols(symbols));visit(V::Symbols(source));if let Some(engine)=engine{visit(V::SymbolTable(engine));}}
        if let Some(engine)=&self.engine{visit(V::Engine(engine));}
    }

    pub(crate) fn engine_matches(&self,engine:Option<&EngineSeed>)->bool { same_engine(self.engine.as_ref(),engine) }
    pub(crate) fn capture(
        adapted: &crate::SharedAdaptedDeclarations,
        engine: Option<&EngineSeed>,
        state: Option<&RetainedSemanticTree>,
    ) -> Option<Self> {
        let catalog = adapted
            .symbol_catalog
            .as_ref()
            .filter(|catalog| adapted.symbols.is_empty_overlay_of(&catalog.symbols))
            .cloned();
        let symbols = catalog.as_ref().map_or_else(
            || Arc::new(adapted.symbols.clone()),
            |catalog| Arc::clone(&catalog.symbols),
        );
        let index = state
            .and_then(|state| {
                state
                    .declarations
                    .take_authored_index(adapted.skeletons.view())
            })
            .or_else(|| {
                crate::declaration_contributions::KeyedDeclarations::capture_view(
                    None,
                    adapted.skeletons.view(),
                )
                .ok()
                .map(|(index, _)| index)
            })?;
        Some(Self {
            index,
            symbols,
            catalog,
            engine: engine.cloned(),
            owner: Weak::new(),
        })
    }
    pub(crate) fn bind(mut self, tree: &Arc<SemanticTree>) -> Self {
        self.owner = Arc::downgrade(tree);
        self
    }
}
impl RetainedSemanticTree {
    pub(crate) fn adopt_valid_diagnostic_records(
        &mut self,
        records: DiagnosticRetainedRecords,
        snapshot: &TreeSnapshot,
    ) -> Result<(), String> {
        if !records
            .owner
            .upgrade()
            .is_some_and(|owner| Arc::ptr_eq(&owner, &snapshot.tree))
        {
            return Err("diagnostic records belong to another original tree".into());
        }
        let metadata_dependencies =
            crate::metadata_update::MetadataDependencies::capture(&snapshot.tree, &records.index);
        let entry = Entry {
            index: records.index,
            symbols: records.symbols,
            symbol_catalog: records.catalog,
            engine: records.engine,
            tree: Arc::clone(&snapshot.tree),
            occurrence_index: snapshot.occurrences.target_index(),
            metadata_dependencies,
        };
        self.discard_foreign_callable_roster(&snapshot.tree);
        release_in_background(self.entry.replace(entry));
        self.normalization.release_publication();
        self.rebuilds += 1;
        crate::change_set::record_outcome("frontend retained adoption: exact valid diagnostic tree and original native records; no rebuild".into());
        Ok(())
    }
    pub(crate) fn record_original_program_reuse(&mut self) {
        self.hits += 1;
    }
    pub(crate) fn admits_remembered_owner(
        &self,
        frontend: &ColdFrontend,
        engine: Option<&EngineSeed>,
    ) -> bool {
        self.entry.as_ref().is_some_and(|entry| {
            Arc::ptr_eq(&entry.tree, &frontend.snapshot.tree)
                && same_engine(entry.engine.as_ref(), engine)
        })
    }
}
