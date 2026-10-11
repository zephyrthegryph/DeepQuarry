//! Request-independent resolved declarations, never old source/body authority.
use super::EngineSeed;
use crate::{Provenance, SemanticTree, Skeleton, SnapshotError, TreeSnapshot};
use std::sync::Arc;

#[derive(Default)]
pub struct RetainedSemanticTree {
    pub(super) declarations: super::declaration_state::RetainedDeclarations,
    entry: Option<Entry>,
    callable_roster: Option<Arc<super::CallableRoster>>,
    normalization: crate::owner_normalization::RetainedNormalization,
    hits: u64,
    rebuilds: u64,
    metadata_updates: u64,
    symbol_only_rebinds: u64,
}
struct Entry {
    index: crate::declaration_contributions::KeyedDeclarations,
    symbols: Arc<dm_ir::SymbolTable>,
    symbol_catalog: Option<Arc<super::symbol_catalog::SymbolCatalog>>,
    engine: Option<EngineSeed>,
    tree: Arc<SemanticTree>,
    occurrence_index: Arc<crate::occurrence_index::TargetOccurrenceIndex>,
    metadata_dependencies: Option<crate::metadata_update::MetadataDependencies>,
}
impl RetainedSemanticTree {
    /// Stage source-neutral declaration claims for this request, independently
    /// of the current semantic/query tree. Dropping the guard aborts claims.
    pub fn begin_declaration_request(&mut self, publishable: bool) -> super::DeclarationRequest {
        self.declarations.begin_request(publishable)
    }
    fn discard_foreign_callable_roster(&mut self, tree: &Arc<SemanticTree>) {
        if let Some(roster) = &self.callable_roster {
            if !roster.authenticates_tree(tree) {
                self.callable_roster = roster.rebind_semantic_owner(tree);
            }
        }
    }
    pub(super) fn bind_callable_roster(
        &mut self,
        tree: &Arc<SemanticTree>,
        bodies: &[super::BodyOccurrence],
    ) -> Result<Arc<super::CallableRoster>, String> {
        if let Some(roster) = &self.callable_roster {
            if roster.matches(tree, bodies) {
                return Ok(Arc::clone(roster));
            }
        }
        let roster = super::CallableRoster::issue(tree, bodies)?;
        self.callable_roster = Some(Arc::clone(&roster));
        Ok(roster)
    }

    /// Actual immutable admission spellings; no separately owned text roster.
    pub fn retained_symbol_owner(&self) -> Option<&Arc<dm_ir::SymbolTable>> {
        self.entry.as_ref().map(|entry| &entry.symbols)
    }

    /// Immutable semantic authority only; no source occurrence or body issuance is retained.
    pub fn snapshot_tree(&self) -> Option<&Arc<SemanticTree>> {
        self.entry.as_ref().map(|entry| &entry.tree)
    }

    /// Exposed immutable payloads; private HashMap bucket backing remains unknown.
    pub fn visit_occurrence_index_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        if let Some(entry) = &self.entry {
            crate::occurrence_index::TargetOccurrenceIndex::visit_storage(
                &entry.occurrence_index,
                &mut visit,
            );
        }
    }
    /// Diagnostic-only current keyed declaration owner.
    pub fn retained_declaration_index(
        &self,
    ) -> Option<&crate::declaration_contributions::KeyedDeclarations> {
        self.entry.as_ref().map(|entry| &entry.index)
    }
    /// Explicit shared authored owner census; current source bindings are separate.
    pub fn visit_authored_storage(
        &self,
        visit: impl FnMut(
            dm_session::ObservedArtifactStorageView<
                '_,
                crate::declaration_contributions::TypeContribution,
                dm_ir::SymbolId,
                Option<Arc<[crate::declaration_contributions::DeclarationRow]>>,
                (),
            >,
        ),
    ) {
        self.declarations.visit_authored_storage(visit);
    }
    pub fn visit_normalization_storage(
        &self,
        visit: impl FnMut(crate::owner_normalization::NormalizationStorageView<'_>),
    ) {
        self.normalization.visit_storage(visit);
    }
    pub fn storage_owner_hits(&self) -> usize {
        self.normalization.storage.hits()
    }
    pub fn visit_storage_owner_storage(
        &self,
        visit: impl FnMut(
            dm_session::ObservedArtifactStorageView<
                '_,
                crate::StorageOwner,
                crate::StorageQuery,
                crate::StorageAnswer,
                (),
            >,
        ),
    ) {
        self.normalization.storage.visit_storage(visit);
    }
    pub fn callable_owner_hits(&self) -> usize {
        self.normalization.callables.hits()
    }
    pub fn visit_callable_owner_storage(
        &self,
        visit: impl FnMut(
            dm_session::ObservedArtifactStorageView<
                '_,
                crate::owner_callable::CallableOwner,
                crate::declaration_observations::SourceQuery,
                crate::declaration_observations::SourceAnswer,
                crate::declaration_observations::SourceDomain,
            >,
        ),
    ) {
        self.normalization.callables.visit_storage(visit);
    }
    pub fn type_path_hits(&self) -> usize {
        self.normalization.paths.hits()
    }
    pub fn visit_type_path_storage(
        &self,
        visit: impl FnMut(
            dm_session::ObservedArtifactStorageView<
                '_,
                crate::type_paths::LexicalPath,
                dm_ir::SymbolId,
                Option<String>,
                (),
            >,
        ),
    ) {
        self.normalization.paths.visit_storage(visit);
    }
    pub fn local_shape_hits(&self) -> usize {
        self.normalization.local.hits()
    }
    pub fn visit_local_shape_storage(
        &self,
        visit: impl FnMut(crate::owner_local_shape::LocalShapeStorageView<'_>),
    ) {
        self.normalization.local.visit_storage(visit);
    }
    pub fn metadata_resolution_stats(&self) -> crate::owner_metadata::MetadataResolutionStats {
        self.normalization.metadata.resolution_stats()
    }
    pub fn metadata_owner_hits(&self) -> usize {
        self.normalization.metadata.hits()
    }
    pub fn visit_effective_metadata_storage(
        &self,
        visit: impl FnMut(crate::owner_metadata::MetadataStorageView<'_>),
    ) {
        self.normalization.metadata.visit_storage(visit);
    }
    /// Diagnostic-only borrowed dependency backing; no roster is materialized.
    pub fn visit_metadata_dependency_storage(&self, visit: impl FnMut(usize, usize, usize)) {
        if let Some(graph) = self
            .entry
            .as_ref()
            .and_then(|entry| entry.metadata_dependencies.as_ref())
        {
            graph.visit_storage(visit);
        }
    }
    pub fn visit_metadata_dependency_edges(
        &self,
        visit: impl FnMut(&Arc<Vec<crate::declaration_contributions::DeclarationKey>>),
    ) {
        if let Some(graph) = self
            .entry
            .as_ref()
            .and_then(|entry| entry.metadata_dependencies.as_ref())
        {
            graph.visit_edges(visit);
        }
    }
    /// Explicit census; callback must not mutate/reenter this retained store.
    pub fn visit_grammar_storage(
        &self,
        visit: impl FnMut(
            dm_session::ObservedArtifactStorageView<
                '_,
                super::GrammarDescriptors,
                super::GrammarQuery,
                super::GrammarAnswer,
                (),
            >,
        ),
    ) {
        self.declarations.grammar.visit_storage(visit);
    }
    pub fn visit_declaration_storage(&self, visit: impl FnMut(super::DeclarationStorageView<'_>)) {
        self.declarations.visit_storage(visit);
    }
    pub fn declaration_retention_stats(&self) -> super::DeclarationRetentionStats {
        self.declarations.stats()
    }
    pub fn new() -> Self {
        Self::default()
    }
    pub fn with_shared_normalized(
        owner: Arc<crate::owner_normalization::SharedNormalizedDeclarations>,
    ) -> Self {
        Self {
            declarations: super::declaration_state::RetainedDeclarations::with_shared_authored(
                Arc::clone(&owner),
            ),
            normalization: crate::owner_normalization::RetainedNormalization::with_shared(owner),
            ..Self::default()
        }
    }
    pub fn clear(&mut self) {
        self.entry = None;
        self.callable_roster = None;
        self.normalization = self.normalization.fresh();
        self.declarations.clear();
    }
    pub fn hits(&self) -> u64 {
        self.hits
    }
    pub fn normalization_hits(&self) -> usize {
        self.normalization.hits()
    }
    pub fn symbol_only_rebinds(&self) -> u64 {
        self.symbol_only_rebinds
    }
    pub fn metadata_updates(&self) -> u64 {
        self.metadata_updates
    }
    pub fn rebuilds(&self) -> u64 {
        self.rebuilds
    }
    pub(super) fn resolve(
        &mut self,
        adapted: impl Into<crate::SharedAdaptedDeclarations>,
        engine: Option<&EngineSeed>,
        mut on_error: impl FnMut(&SnapshotError, &[Skeleton], &[Provenance]),
        executor: &dm_exec::BuildExecutor,
    ) -> Result<TreeSnapshot, SnapshotError> {
        let mut adapted = adapted.into();
        if adapted
            .symbol_catalog
            .as_ref()
            .is_some_and(|catalog| !adapted.symbols.is_empty_overlay_of(&catalog.symbols))
        {
            adapted.symbol_catalog = None;
        }
        let origins = std::mem::replace(&mut adapted.origins, Vec::new().into()).into_owned();
        let shared_catalog = self.entry.as_ref().is_some_and(|entry| {
            entry
                .symbol_catalog
                .as_ref()
                .zip(adapted.symbol_catalog.as_ref())
                .is_some_and(|(previous, current)| Arc::ptr_eq(previous, current))
        });
        let symbols = (self.entry.is_some() && !shared_catalog).then(|| adapted.symbols.ordered());
        let reusable = self.entry.as_ref().filter(|entry| {
            entry.index.skeletons().eq(adapted.skeletons.iter())
                && (shared_catalog
                    || symbols
                        .as_ref()
                        .is_some_and(|symbols| entry.symbols.ordered() == *symbols))
                && same_engine(entry.engine.as_ref(), engine)
        });
        if let Some(entry) = reusable {
            let tree = Arc::clone(&entry.tree);
            let occurrences = crate::OccurrenceTable::build_with_index(
                &tree,
                origins,
                Some(&entry.occurrence_index),
            )
            .map_err(|error| {
                let error = SnapshotError::Origins(error);
                on_error(&error, &adapted.skeletons.to_vec(), &[]);
                error
            })?;
            // A failed newer candidate may have replaced the issuer's Weak
            // current owner. Bind only after current occurrence validation.
            if let Some(issuer) = tree.owner_certificate_issuer() {
                issuer.bind_selection_owner(&tree);
            }
            self.hits += 1;
            return Ok(TreeSnapshot {
                tree,
                occurrences: Arc::new(occurrences),
            });
        }
        drop(symbols);
        // The catalog has already passed the empty-overlay check above. Its
        // immutable owner is the exact admission input, not a pointer-only key.
        // Standalone adapters clone map descriptors while sharing every Arcstr.
        let symbol_owner = adapted.symbol_catalog.as_ref().map_or_else(
            || Arc::new(adapted.symbols.clone()),
            |catalog| Arc::clone(&catalog.symbols),
        );
        // Exact per-owner equality shares immutable declaration contributions;
        // this index never carries a previous request's source authority.
        let index = self
            .declarations
            .take_authored_index(adapted.skeletons.view())
            .or_else(|| {
                crate::declaration_contributions::KeyedDeclarations::capture_view(
                    self.entry.as_ref().map(|entry| &entry.index),
                    adapted.skeletons.view(),
                )
                .ok()
                .map(|(index, _)| index)
            });
        let unchanged_declarations = self.entry.as_ref().is_some_and(|entry| {
            same_engine(entry.engine.as_ref(), engine)
                && entry.index.skeletons().eq(adapted.skeletons.iter())
        });
        let updated = self.entry.as_ref().and_then(|entry| {
            index.as_ref()?;
            if !same_engine(entry.engine.as_ref(), engine) {
                return None;
            }
            entry.metadata_dependencies.as_ref()?.update(
                &entry.tree,
                entry.index.skeletons(),
                adapted.skeletons.iter(),
                adapted.symbols.clone(),
                executor,
            )
        });
        if let Some(mut tree) = updated {
            tree.selection_publication_deferred = true;
            if !unchanged_declarations {
                let (identity, hierarchy) = crate::adapter::projected_identity_indexed(
                    index
                        .as_ref()
                        .expect("updated tree has current declaration index"),
                    engine,
                )
                .map_err(|error| {
                    let error = SnapshotError::Tree(error);
                    on_error(&error, &adapted.skeletons.to_vec(), &origins);
                    error
                })?;
                tree.refresh_metadata_identity(identity, hierarchy);
            }
            let prior_index = self
                .entry
                .as_ref()
                .expect("metadata update has retained entry");
            let occurrences = crate::OccurrenceTable::build_with_index(
                &tree,
                origins,
                Some(&prior_index.occurrence_index),
            )
            .map_err(|error| {
                let error = SnapshotError::Origins(error);
                on_error(&error, &adapted.skeletons.to_vec(), &[]);
                error
            })?;
            tree.publish_selection_owner();
            let tree = Arc::new(tree);
            let entry = self
                .entry
                .as_mut()
                .expect("updated tree has its retained producer");
            entry.occurrence_index = occurrences.target_index();
            entry.tree = Arc::clone(&tree);
            entry.index = index.expect("updated tree has its exact contribution index");
            entry.symbol_catalog = adapted.symbol_catalog.clone();
            entry.symbols = symbol_owner;
            // Body indexing follows this return and may fail. Do not keep the
            // previous tree rooted through its now-foreign callable roster.
            self.discard_foreign_callable_roster(&tree);
            self.normalization.release_publication();
            self.metadata_updates += 1;
            if unchanged_declarations {
                self.symbol_only_rebinds += 1;
            }
            return Ok(TreeSnapshot {
                tree,
                occurrences: Arc::new(occurrences),
            });
        }
        // Capture admission inputs before consuming them; never memoize failures.

        let symbol_catalog = adapted.symbol_catalog.clone();
        adapted.origins = origins.into();
        let snapshot = adapted.finish_with_engine_normalization(
            engine,
            on_error,
            executor,
            index.as_ref().map(|index| (index, &self.normalization)),
            self.entry
                .as_ref()
                .filter(|entry| same_engine(entry.engine.as_ref(), engine))
                .and_then(|entry| {
                    entry.metadata_dependencies.as_ref().map(|graph| {
                        crate::metadata_update::StructuralMetadata {
                            tree: &entry.tree,
                            declarations: &entry.index,
                            graph,
                        }
                    })
                }),
        )?;
        self.discard_foreign_callable_roster(&snapshot.tree);
        let next_entry = index.map(|index| {
            let previous = self.entry.as_ref().and_then(|entry| {
                entry
                    .metadata_dependencies
                    .as_ref()
                    .map(|graph| (graph, &entry.index))
            });
            let metadata_dependencies =
                crate::metadata_update::MetadataDependencies::capture_rebased(
                    &snapshot.tree,
                    &index,
                    previous,
                );
            Entry {
                index,
                symbols: symbol_owner,
                symbol_catalog,
                engine: engine.cloned(),
                tree: Arc::clone(&snapshot.tree),
                occurrence_index: snapshot.occurrences.target_index(),
                metadata_dependencies,
            }
        });
        self.entry = next_entry;
        self.rebuilds += 1;
        Ok(snapshot)
    }
}
fn same_engine(previous: Option<&EngineSeed>, current: Option<&EngineSeed>) -> bool {
    match (previous, current) {
        (None, None) => true,
        (Some(previous), Some(current)) => {
            previous.identity == current.identity
                && previous.hierarchy == current.hierarchy
                && previous.intrinsics == current.intrinsics
                && previous.fields == current.fields
                && previous.symbols.ordered() == current.symbols.ordered()
        }
        _ => false,
    }
}
#[cfg(test)]
#[path = "frontend_semantic_state_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "frontend_callable_lifecycle_tests.rs"]
mod callable_lifecycle_tests;

#[cfg(test)]
#[path = "frontend_semantic_symbol_tests.rs"]
mod symbol_owner_tests;
