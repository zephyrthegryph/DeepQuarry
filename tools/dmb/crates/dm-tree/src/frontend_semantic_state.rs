//! Request-independent resolved declarations, never old source/body authority.
use super::EngineSeed;
use crate::{AdaptedDeclarations, Provenance, SemanticTree, Skeleton, SnapshotError, TreeSnapshot};
use std::sync::Arc;

#[derive(Default)]
pub struct RetainedSemanticTree {
    entry: Option<Entry>,
    hits: u64,
    rebuilds: u64,
}
struct Entry {
    skeletons: Vec<Skeleton>,
    symbols: Vec<(dm_ir::SymbolId, String)>,
    engine: Option<EngineSeed>,
    tree: Arc<SemanticTree>,
}
impl RetainedSemanticTree {
    pub fn new() -> Self {
        Self::default()
    }
    pub fn clear(&mut self) {
        self.entry = None;
    }
    pub fn hits(&self) -> u64 {
        self.hits
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
        // Capture admission inputs before consuming them; never memoize failures.
        let skeletons = adapted.skeletons.clone();
        let symbols = symbols
            .into_iter()
            .map(|(id, text)| (id, text.to_owned()))
            .collect();
        let snapshot =
            adapted.finish_with_engine_observed_on_executor(engine, on_error, executor)?;
        self.entry = Some(Entry {
            skeletons,
            symbols,
            engine: engine.cloned(),
            tree: Arc::clone(&snapshot.tree),
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
