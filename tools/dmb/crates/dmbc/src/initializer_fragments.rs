//! Current-roster semantic continuations, validated by the common read ledger.
use super::receipts;
use crate::initializer_policy::ClassifiedInitializers;
#[cfg(test)]
use crate::initializer_policy::RuntimeValue;
use dm_codegen_byond::initializer::{
    AssignmentFragment, InitializerError, PreparedAssignmentGroup,
};
use dm_ir::Resolver;
use std::{
    collections::HashMap,
    sync::atomic::{AtomicU64, Ordering},
    sync::Arc,
};

pub struct InitializerFragments {
    values: receipts::Store<RetainedFragment>,
    pub hits: AtomicU64,
    pub recomputed: AtomicU64,
    pub declined: AtomicU64,
}
struct RetainedFragment {
    code: AssignmentFragment,
    recipes: Vec<crate::modified_initializers::ExpressionRecipe>,
}
impl Default for InitializerFragments {
    fn default() -> Self {
        Self {
            values: receipts::Store::current_revision(),
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
            declined: AtomicU64::new(0),
        }
    }
}
pub(super) fn current_keys(
    classified: &ClassifiedInitializers,
    policy: u128,
    resource_context: Option<u128>,
) -> Result<HashMap<usize, receipts::Binding>, String> {
    let mut keys = HashMap::new();
    let mut duplicates = HashMap::<Vec<u8>, usize>::new();
    for group in &classified.groups {
        for &index in &group.writes {
            let write = classified
                .writes
                .get(index)
                .ok_or("initializer group write missing")?;
            let runtime = write
                .runtime_value
                .as_ref()
                .ok_or("initializer runtime value missing")?;
            let inputs = receipts::FragmentInputs {
                write: write.write.clone(),
                shape: runtime.into(),
                policy,
                resource_context,
                debug_enabled: true,
                accepted: classified.accepted.get(index).cloned().flatten(),
            };
            let duplicate = duplicates
                .entry(receipts::fragment_locator(&write.write))
                .or_default();
            keys.insert(
                write.source_ordinal,
                receipts::Binding::fragment(*duplicate, inputs),
            );
            *duplicate += 1;
        }
    }
    Ok(keys)
}
#[cfg(test)]
fn semantic_key(
    write: &dm_ir::InitializerWrite,
    runtime: &RuntimeValue,
    policy: u128,
    resource_context: Option<u128>,
    debug_enabled: bool,
) -> receipts::Binding {
    receipts::Binding::fragment(
        0,
        receipts::FragmentInputs {
            write: write.clone(),
            shape: runtime.into(),
            policy,
            resource_context,
            debug_enabled,
            accepted: None,
        },
    )
}
impl InitializerFragments {
    pub(super) fn retain_keys(&self, keys: &HashMap<usize, receipts::Binding>) {
        self.values
            .retain_current_keys(keys.values().map(|binding| binding.key.as_ref()));
    }
    pub(super) fn fragment<R: Resolver>(
        &self,
        key: &receipts::Binding,
        prepared: &PreparedAssignmentGroup<'_>,
        index: usize,
        write: &dm_ir::InitializerWrite,
        host: &R,
    ) -> Result<Option<AssignmentFragment>, InitializerError> {
        let root = prepared.expression(index).ok_or_else(|| {
            InitializerError::Invalid("initializer current expression missing".into())
        })?;
        if let Some(fragment) = self.values.lookup(
            &key.key,
            &receipts::Host {
                binding: key,
                resolver: host,
            },
        ) {
            let current = crate::lowering_memo::RecordingResolver::new(host);
            let captured = fragment
                .recipes
                .iter()
                .map(|recipe| recipe.reissue(root, &current, prepared.symbols()))
                .collect::<Option<std::collections::BTreeMap<_, _>>>();
            if let Some(captured) = captured {
                if let Ok(code) = fragment.code.clone().bind_modified(captured) {
                    self.hits.fetch_add(1, Ordering::Relaxed);
                    return Ok(Some(code));
                }
            }
            // A recipe is only a candidate. Uncertain current binding executes
            // the ordinary producer, never reuses old source/AST authority.
            self.declined.fetch_add(1, Ordering::Relaxed);
        }
        let recorder = crate::lowering_memo::RecordingResolver::new(host);
        recorder.resolve(dm_ir::ResolveQuery::Ancestry(write.lexical_owner));
        if let Some(identity) = write.lexical_procedure {
            recorder.record_occurrence(identity);
        }
        let Some(fragment) = prepared.try_lower_fragment(index, &recorder)? else {
            self.declined.fetch_add(1, Ordering::Relaxed);
            return Ok(None);
        };
        self.recomputed.fetch_add(1, Ordering::Relaxed);
        let reads = receipts::reads(key, recorder.reads());
        let versions = receipts::versions(recorder.domain_receipts());
        let (stripped, captures) = fragment.clone().split_modified();
        let recipes = captures
            .iter()
            .map(|(reference, captured)| {
                crate::modified_initializers::ExpressionRecipe::from_capture(
                    *reference, captured, root,
                )
            })
            .collect::<Option<Vec<_>>>();
        // Only current-roster retention is constructed here. This inline charge
        // is not a resident byte estimate; full ownership remains census-only.
        if let Some(recipes) = recipes {
            let weight = std::mem::size_of::<RetainedFragment>();
            self.values
                .insert_with(Arc::clone(&key.key), reads, versions, weight, || {
                    RetainedFragment {
                        code: stripped,
                        recipes,
                    }
                });
        } else {
            self.declined.fetch_add(1, Ordering::Relaxed);
        }
        Ok(Some(fragment))
    }
}
#[cfg(test)]
#[path = "initializer_fragments_tests.rs"]
mod tests;
