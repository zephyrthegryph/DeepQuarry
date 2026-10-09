//! Request-independent resolved declarations, never old source/body authority.
use super::EngineSeed;
use crate::{AdaptedDeclarations, Provenance, SemanticTree, Skeleton, SnapshotError, TreeSnapshot};
use std::sync::Arc;

#[derive(Default)]
pub struct RetainedSemanticTree {
    pub(super) declarations: super::declaration_state::RetainedDeclarations,
    entry: Option<Entry>,
    hits: u64,
    rebuilds: u64,
    metadata_updates: u64,
}
struct Entry {
    skeletons: Vec<Skeleton>,
    symbols: Vec<(dm_ir::SymbolId, String)>,
    engine: Option<EngineSeed>,
    tree: Arc<SemanticTree>,
    metadata_dependencies: Option<crate::metadata_update::MetadataDependencies>,
}
impl RetainedSemanticTree {
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
    /// Explicit census; callback must not mutate/reenter this retained store.
    pub fn visit_declaration_storage(&self, visit: impl FnMut(super::DeclarationStorageView<'_>)) {
        self.declarations.visit_storage(visit);
    }
    pub fn declaration_retention_stats(&self) -> super::DeclarationRetentionStats {
        self.declarations.stats()
    }
    pub fn new() -> Self {
        Self::default()
    }
    pub fn clear(&mut self) {
        self.entry = None;
        self.declarations.retain(&[]);
    }
    pub fn hits(&self) -> u64 {
        self.hits
    }
    pub fn metadata_updates(&self) -> u64 {
        self.metadata_updates
    }
    pub fn rebuilds(&self) -> u64 {
        self.rebuilds
    }
    pub(super) fn resolve(
        &mut self,
        adapted: AdaptedDeclarations,
        engine: Option<&EngineSeed>,
        mut on_error: impl FnMut(&SnapshotError, &[Skeleton], &[Provenance]),
        executor: &dm_exec::BuildExecutor,
    ) -> Result<TreeSnapshot, SnapshotError> {
        let symbols = adapted.symbols.ordered();
        let reusable =
            self.entry.as_ref().filter(|entry| {
                entry.skeletons == adapted.skeletons
                    && entry.symbols.len() == symbols.len()
                    && entry.symbols.iter().zip(&symbols).all(
                        |((id, text), (current_id, current))| {
                            id == current_id && text.as_str() == *current
                        },
                    )
                    && same_engine(entry.engine.as_ref(), engine)
            });
        if let Some(entry) = reusable {
            let tree = Arc::clone(&entry.tree);
            let occurrences =
                crate::OccurrenceTable::build(&tree, adapted.origins).map_err(|error| {
                    let error = SnapshotError::Origins(error);
                    on_error(&error, &adapted.skeletons, &[]);
                    error
                })?;
            self.hits += 1;
            return Ok(TreeSnapshot {
                tree,
                occurrences: Arc::new(occurrences),
            });
        }
        let updated = self.entry.as_ref().and_then(|entry| {
            if !same_engine(entry.engine.as_ref(), engine) {
                return None;
            }
            entry.metadata_dependencies.as_ref()?.update(
                &entry.tree,
                &entry.skeletons,
                &adapted.skeletons,
                adapted.symbols.clone(),
                executor,
            )
        });
        if let Some(mut tree) = updated {
            let (identity, hierarchy) =
                crate::adapter::projected_identity(&adapted.skeletons, engine).map_err(
                    |error| {
                        let error = SnapshotError::Tree(error);
                        on_error(&error, &adapted.skeletons, &adapted.origins);
                        error
                    },
                )?;
            tree.refresh_metadata_identity(identity, hierarchy);
            let tree = Arc::new(tree);
            let occurrences =
                crate::OccurrenceTable::build(&tree, adapted.origins).map_err(|error| {
                    let error = SnapshotError::Origins(error);
                    on_error(&error, &adapted.skeletons, &[]);
                    error
                })?;
            let entry = self
                .entry
                .as_mut()
                .expect("updated tree has its retained producer");
            entry.tree = Arc::clone(&tree);
            entry.skeletons = adapted.skeletons;
            entry.symbols = symbols
                .into_iter()
                .map(|(id, text)| (id, text.to_owned()))
                .collect();
            self.metadata_updates += 1;
            return Ok(TreeSnapshot {
                tree,
                occurrences: Arc::new(occurrences),
            });
        }
        // Capture admission inputs before consuming them; never memoize failures.
        let skeletons = adapted.skeletons.clone();
        let symbols = symbols
            .into_iter()
            .map(|(id, text)| (id, text.to_owned()))
            .collect();
        let snapshot =
            adapted.finish_with_engine_observed_on_executor(engine, on_error, executor)?;
        let metadata_dependencies =
            crate::metadata_update::MetadataDependencies::capture(&snapshot.tree, &skeletons);
        self.entry = Some(Entry {
            skeletons,
            symbols,
            engine: engine.cloned(),
            tree: Arc::clone(&snapshot.tree),
            metadata_dependencies,
        });
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
