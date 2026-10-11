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
    roster: std::sync::Mutex<(Vec<Arc<[u8]>>, Vec<Arc<[u8]>>)>,
    pub hits: AtomicU64,
    pub recomputed: AtomicU64,
    pub declined: AtomicU64,
}
pub(super) struct FragmentWithRecipes {
    pub code: AssignmentFragment,
    pub recipes: Option<Vec<crate::modified_initializers::ExpressionRecipe>>,
}
pub(crate) struct RetainedFragment {
    code: RetainedCode,
    recipes: Vec<crate::modified_initializers::ExpressionRecipe>,
    references: Vec<dm_ir::SymRef>,
}
enum RetainedCode {
    Assignment(AssignmentFragment),
    Modified(dm_codegen_byond::lower_resolver::ResolverProc),
}
impl RetainedFragment {
    #[allow(clippy::type_complexity)]
    pub(crate) fn retained_parts(
        &self,
    ) -> (
        &dm_codegen_byond::lower_resolver::ResolverProc,
        &Vec<crate::modified_initializers::ExpressionRecipe>,
        &Vec<dm_ir::SymRef>,
    ) {
        (
            match &self.code { RetainedCode::Assignment(code) => code.code(), RetainedCode::Modified(code) => code },
            &self.recipes,
            match &self.code { RetainedCode::Assignment(code) => code.modified_references(), RetainedCode::Modified(_) => &self.references },
        )
    }
}
impl Default for InitializerFragments {
    fn default() -> Self {
        Self {
            values: receipts::Store::current_revision(),
            roster: Default::default(),
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
    /// Diagnostic-only borrowing; callback must not re-enter this store.
    pub(crate) fn visit_storage(&self, visit: impl FnMut(receipts::Storage<'_, RetainedFragment>)) {
        self.values.visit_storage(visit);
    }
    pub(crate) fn retain_keys(&self, keys: &HashMap<usize, receipts::Binding>) {
        let mut roster = self.roster.lock().unwrap();
        roster.0 = keys.values().map(|binding| Arc::clone(&binding.key)).collect();
        self.values.retain_current_keys(roster.0.iter().chain(&roster.1).map(|key| key.as_ref()));
    }
    pub(crate) fn retain_modified_keys(&self, keys: Vec<Arc<[u8]>>) {
        let mut roster = self.roster.lock().unwrap();
        roster.1 = keys;
        self.values.retain_current_keys(roster.0.iter().chain(&roster.1).map(|key| key.as_ref()));
    }
    pub(crate) fn visit_key_roster(&self, visit: impl FnOnce(&Vec<Arc<[u8]>>, &Vec<Arc<[u8]>>)) {
        let roster = self.roster.lock().unwrap();
        visit(&roster.0, &roster.1);
    }
    pub(crate) fn modified<R: Resolver>(&self, key: &receipts::Binding, host: &R) -> Option<dm_codegen_byond::lower_resolver::ResolverProc> {
        let value = self.values.lookup(&key.key, &receipts::Host { binding: key, resolver: host })?;
        let RetainedCode::Modified(code) = &value.code else { return None };
        self.hits.fetch_add(1, Ordering::Relaxed);
        Some(code.clone())
    }
    pub(crate) fn remember_modified(&self, key: &receipts::Binding, recorder: &crate::lowering_memo::RecordingResolver<'_, impl Resolver>, code: &dm_codegen_byond::lower_resolver::ResolverProc) {
        // Nested current expression captures require their own current recipe.
        // Decline retention rather than retaining their source AST or spans.
        if !code.modified_instances.is_empty() { self.declined.fetch_add(1, Ordering::Relaxed); return; }
        self.values.insert_with(Arc::clone(&key.key), receipts::reads(key, recorder.reads()), receipts::versions(recorder.domain_receipts()), std::mem::size_of::<RetainedFragment>(), || RetainedFragment {
            code: RetainedCode::Modified(code.clone()), recipes: Vec::new(), references: Vec::new(),
        });
        self.recomputed.fetch_add(1, Ordering::Relaxed);
    }
    #[cfg(test)]
    pub(super) fn fragment<R: Resolver>(
        &self,
        key: &receipts::Binding,
        prepared: &PreparedAssignmentGroup<'_>,
        index: usize,
        write: &dm_ir::InitializerWrite,
        host: &R,
    ) -> Result<Option<AssignmentFragment>, InitializerError> {
        self.fragment_with_recipes(key, prepared, index, write, host)
            .map(|value| value.map(|value| value.code))
    }
    pub(super) fn fragment_with_recipes<R: Resolver>(
        &self,
        key: &receipts::Binding,
        prepared: &PreparedAssignmentGroup<'_>,
        index: usize,
        write: &dm_ir::InitializerWrite,
        host: &R,
    ) -> Result<Option<FragmentWithRecipes>, InitializerError> {
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
                if let RetainedCode::Assignment(retained) = &fragment.code {
                if let Ok(code) = retained.clone().bind_modified(captured) {
                    self.hits.fetch_add(1, Ordering::Relaxed);
                    return Ok(Some(FragmentWithRecipes {
                        code,
                        recipes: Some(fragment.recipes.clone()),
                    }));
                }
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
        let handoff = recipes.clone();
        if let Some(recipes) = recipes {
            let weight = std::mem::size_of::<RetainedFragment>();
            self.values
                .insert_with(Arc::clone(&key.key), reads, versions, weight, || {
                    RetainedFragment {
                        references: Vec::new(),
                        code: RetainedCode::Assignment(stripped),
                        recipes,
                    }
                });
        } else {
            self.declined.fetch_add(1, Ordering::Relaxed);
        }
        Ok(Some(FragmentWithRecipes {
            code: fragment,
            recipes: handoff,
        }))
    }
}
#[cfg(test)]
#[path = "initializer_fragments_tests.rs"]
mod tests;
