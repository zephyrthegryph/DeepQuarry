//! Current-roster semantic continuations, validated by the common read ledger.
use crate::initializer_policy::{ClassifiedInitializers, RuntimeValue};
use dm_codegen_byond::initializer::{
    AssignmentFragment, InitializerError, PreparedAssignmentGroup,
};
use dm_ir::{ReadDomain, Resolver};
use std::{
    collections::HashMap,
    sync::atomic::{AtomicU64, Ordering},
};

pub struct InitializerFragments {
    values: dm_session::ArtifactStore<RetainedFragment>,
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
            values: dm_session::ArtifactStore::current_revision(),
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
) -> Result<HashMap<usize, Vec<u8>>, String> {
    let mut keys = HashMap::new();
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
            keys.insert(
                write.source_ordinal,
                // Production groups bind their current captured debug origins.
                semantic_key(&write.write, runtime, policy, resource_context, true),
            );
        }
    }
    Ok(keys)
}
fn semantic_key(
    write: &dm_ir::InitializerWrite,
    runtime: &RuntimeValue,
    policy: u128,
    resource_context: Option<u128>,
    debug_enabled: bool,
) -> Vec<u8> {
    let mut key = b"dmbc-initializer-continuation-v2-zero-frame-relative-debug\0".to_vec();
    key.extend_from_slice(&policy.to_le_bytes());
    key.push(u8::from(debug_enabled));
    match resource_context {
        Some(value) => {
            key.push(1);
            key.extend_from_slice(&value.to_le_bytes());
        }
        None => key.push(0),
    }
    write.write_canonical(|bytes| key.extend_from_slice(bytes));
    match runtime {
        RuntimeValue::Expression(_) => key.push(0),
        RuntimeValue::SizedArray(dimensions) => {
            key.push(1);
            key.extend_from_slice(&(dimensions.len() as u64).to_le_bytes());
            for dimension in dimensions.iter() {
                key.extend_from_slice(&dimension.to_le_bytes());
            }
        }
    }
    key
}
impl InitializerFragments {
    pub(super) fn retain_keys(&self, keys: &HashMap<usize, Vec<u8>>) {
        self.values
            .retain_current_keys(keys.values().map(Vec::as_slice));
    }
    pub(super) fn fragment<R: Resolver>(
        &self,
        key: &[u8],
        prepared: &PreparedAssignmentGroup<'_>,
        index: usize,
        write: &dm_ir::InitializerWrite,
        host: &R,
    ) -> Result<Option<AssignmentFragment>, InitializerError> {
        let root = prepared.expression(index).ok_or_else(|| {
            InitializerError::Invalid("initializer current expression missing".into())
        })?;
        if let Some(fragment) = self.values.lookup(key, host) {
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
        let reads = recorder.reads();
        let versions: Vec<(ReadDomain, u128)> = recorder.domain_receipts();
        let (stripped, captures) = fragment.clone().split_modified();
        let recipes = captures
            .iter()
            .map(|(reference, captured)| {
                crate::modified_initializers::ExpressionRecipe::from_capture(
                    *reference, captured, root,
                )
            })
            .collect::<Option<Vec<_>>>();
        let weight = recipes.as_ref().and_then(|recipes| {
            crate::heap_census::resident_initializer_fragment_weight(
                stripped.code(),
                key,
                &reads,
                &versions,
                recipes,
                stripped.modified_references(),
            )
        });
        if let Some(weight) = weight {
            let recipes = recipes.expect("weight requires complete current expression recipes");
            self.values
                .insert_with(key.into(), reads, versions, weight, || RetainedFragment {
                    code: stripped,
                    recipes,
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
