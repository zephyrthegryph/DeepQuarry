//! Current declaration modifier admission, independent of value evaluation.
use super::*;
use dm_ir::{ResolveQuery, Resolver};
use std::sync::atomic::{AtomicU64, Ordering};

fn header_domain(
    write: &InitializerWrite,
    symbols: &SymbolTable,
) -> Result<Option<HeaderDomain>, String> {
    if write.declaration_flags.is_some() {
        return Ok(None);
    }
    if crate::savefile_projection::is_header_target(&write.target, symbols) {
        return Ok(Some(HeaderDomain::Savefile));
    }
    if crate::world_projection::is_header_target(&write.target, symbols) {
        return Ok(Some(HeaderDomain::World));
    }
    if let InitializerTarget::Instance {
        declaring_owner,
        name,
        ..
    } = write.target
    {
        let name = symbols
            .text(name)
            .ok_or("client property spelling unavailable")?;
        if declaring_owner == SymbolId::of("/client")
            && crate::client_projection::is_header_field(name)
        {
            return Ok(Some(HeaderDomain::Client));
        }
    }
    Ok(None)
}
fn capture(
    write: &InitializerWrite,
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
    ordinal: usize,
) -> Result<ModifierFact, String> {
    if let Some(domain) = header_domain(write, symbols)? {
        return Ok(ModifierFact::Header(domain));
    }
    let knowledge = evaluator.binding_knowledge(write)?.ok_or_else(|| {
        let (owner, name) = match write.target {
            InitializerTarget::Instance {
                declaring_owner,
                name,
                ..
            } => (declaring_owner, name),
            InitializerTarget::Shared { owner, name, .. } => (owner, name),
            InitializerTarget::ProcedureStatic(identity) => {
                (identity.procedure.owner, identity.name)
            }
        };
        format!(
            "opaque initializer declaration modifiers: {}::{} (write {ordinal})",
            symbols.text(owner).unwrap_or("<unknown owner>"),
            symbols.text(name).unwrap_or("<unknown variable>")
        )
    })?;
    let flags = match knowledge {
        BindingKnowledge::Modifiers(flags) => flags,
        BindingKnowledge::MutableInstance {
            owner,
            name,
            receipt,
        } => {
            if write.declaration_flags.is_some()
                || receipt == 0
                || !matches!(write.target, InitializerTarget::Instance { declaring_owner, name: target_name, .. }
                            if owner == declaring_owner && name == target_name)
            {
                return Err("mutable instance knowledge disagrees with target".into());
            }
            return Ok(ModifierFact::MutableInstance);
        }
    };
    if write
        .declaration_flags
        .is_some_and(|source| source != flags)
    {
        return Err("captured initializer modifiers disagree with source facts".into());
    }
    if flags & !15 != 0 {
        return Err("unknown initializer modifiers".into());
    }
    Ok(ModifierFact::Known(flags))
}

pub(super) fn modifier_facts(
    writes: &[InitializerWrite],
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
) -> Result<Vec<ModifierFact>, ClassificationError> {
    modifier_facts_indexed(writes.iter(), symbols, evaluator, None)
}
pub(super) fn modifier_facts_indexed<'a>(
    writes: impl ExactSizeIterator<Item = &'a InitializerWrite>,
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
    ordinals: Option<&[usize]>,
) -> Result<Vec<ModifierFact>, ClassificationError> {
    collect(writes, ordinals, |write, ordinal| {
        capture(write, symbols, evaluator, ordinal)
    })
}
fn collect<'a>(
    writes: impl ExactSizeIterator<Item = &'a InitializerWrite>,
    ordinals: Option<&[usize]>,
    mut produce: impl FnMut(&InitializerWrite, usize) -> Result<ModifierFact, String>,
) -> Result<Vec<ModifierFact>, ClassificationError> {
    let mut facts = Vec::with_capacity(writes.len());
    let mut issues = Vec::new();
    for (local, write) in writes.enumerate() {
        let ordinal = ordinals.map_or(local, |ordinals| ordinals[local]);
        match produce(write, ordinal) {
            Ok(fact) => facts.push(fact),
            Err(reason) => issues.push(ClassificationIssue {
                kind: ClassificationIssueKind::Unsupported,
                source_ordinal: ordinal,
                reason,
            }),
        }
    }
    if issues.is_empty() {
        Ok(facts)
    } else {
        Err(ClassificationError { issues })
    }
}

pub(super) struct ModifierArtifacts {
    values: crate::initializer_lowering::receipts::publication_store::Store<
        ModifierArtifact,
        dm_ir::ResolveQuery,
        dm_ir::ResolvedMeaning,
        dm_ir::ReadDomain,
    >,
    pub(super) hits: AtomicU64,
    pub(super) recomputed: AtomicU64,
}
pub(crate) struct ModifierArtifact {
    pub(crate) input: Arc<InitializerWrite>,
    fact: ModifierFact,
}
pub(super) struct ModifierKey {
    bytes: Arc<[u8]>,
    pub(super) input: Arc<InitializerWrite>,
    admitted: std::sync::OnceLock<Arc<InitializerWrite>>,
}
impl ModifierKey {
    pub(super) fn shared_input(&self) -> &Arc<InitializerWrite> {
        self.admitted.get().unwrap_or(&self.input)
    }
}
impl Default for ModifierArtifacts {
    fn default() -> Self {
        Self {
            values:
                crate::initializer_lowering::receipts::publication_store::Store::current_revision(),
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
        }
    }
}
impl ModifierArtifacts {
    pub(crate) fn compact_for_pressure(&self, bytes: usize) -> dm_session::PressurePrune {
        self.values.prune_for_pressure_shared(
            bytes,
            crate::heap_census::initializer_artifacts::compact_modifier_allocations,
        )
    }
    pub(super) fn for_request(&self, publishable: bool) -> Self {
        Self {
            values: self.values.for_request(publishable),
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
        }
    }
    pub(super) fn publish_successful(&self) -> bool {
        self.values.publish_successful()
    }

    pub(super) fn visit_storage(
        &self,
        visitor: impl FnMut(dm_session::ArtifactStorageView<'_, ModifierArtifact>),
    ) {
        self.values.visit_storage(visitor);
    }

    pub(super) fn with_limit(bytes: usize) -> Self {
        Self {
            values: crate::initializer_lowering::receipts::publication_store::Store::with_limit(
                bytes,
            ),
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
        }
    }
    pub(super) fn retain_keys(&self, keys: &[Vec<u8>]) {
        self.values
            .retain_current_keys(keys.iter().map(Vec::as_slice));
    }
}
struct Host<'a>(&'a dyn Resolver);
impl Resolver for Host<'_> {
    fn resolve_with_canonical(&self, query: ResolveQuery) -> dm_ir::CanonicalResolvedAnswer {
        self.0.resolve_with_canonical(query)
    }
    fn transparent_receipt_observer(&self) -> Option<dm_ir::TransparentReceiptObserver<'_>> {
        self.0.transparent_receipt_observer()
    }
    fn observes_reads(&self) -> bool {
        self.0.observes_reads()
    }
    fn resolve(&self, q: ResolveQuery) -> dm_ir::ResolvedMeaning {
        self.0.resolve(q)
    }
    fn domain_version(&self, d: dm_ir::ReadDomain) -> Option<u128> {
        self.0.domain_version(d)
    }
}
pub(super) fn keys(
    writes: &[InitializerWrite],
    factory: ParallelEvaluator<'_>,
    reuse: InitializerReuse<'_>,
) -> Option<Vec<ModifierKey>> {
    keys_in(writes, factory, reuse, None)
}
pub(super) fn keys_in(
    writes: &[InitializerWrite],
    factory: ParallelEvaluator<'_>,
    reuse: InitializerReuse<'_>,
    preparation: Option<&classification::token_roster::preparation::Preparation>,
) -> Option<Vec<ModifierKey>> {
    let policy = factory.factory.recording_policy_identity()?;
    let recipe_policy = classification::token_roster::preparation::Policy {
        classification: reuse.policy,
        factory: policy,
        resource: reuse.resource_search_context,
        engine: factory.engine.map(|engine| engine.identity()),
    };
    let produce = || {
        let mut duplicates = std::collections::HashMap::<Vec<u8>, usize>::new();
        let keys = writes
            .iter()
            .map(|write| {
                let mut key = b"dmbc-modifier-fact-v2-exact-input\0".to_vec();
                key.extend_from_slice(&reuse.policy.to_le_bytes());
                key.extend_from_slice(&policy.to_le_bytes());
                match reuse.resource_search_context {
                    Some(context) => {
                        key.push(1);
                        key.extend_from_slice(&context.to_le_bytes());
                    }
                    None => key.push(0),
                }
                match factory.engine {
                    Some(engine) => {
                        key.push(1);
                        key.extend_from_slice(&engine.identity().to_le_bytes());
                    }
                    None => key.push(0),
                }
                // The existing certified evaluator may inspect any write field. Full exact
                // inputs avoid inventing a weaker modifier-only policy contract.
                key.extend_from_slice(&crate::initializer_lowering::receipts::fragment_locator(
                    write,
                ));
                let duplicate = duplicates.entry(key.clone()).or_default();
                key.extend_from_slice(&(*duplicate as u128).to_le_bytes());
                *duplicate += 1;
                classification::token_roster::preparation::ModifierLocator {
                    bytes: key.into(),
                    input: Arc::new(write.clone()),
                }
            })
            .collect::<Vec<_>>();
        keys
    };
    let rows = match preparation {
        Some(preparation) => preparation
            .modifier_locations(writes, recipe_policy, produce)
            .rows
            .clone(),
        None => produce().into(),
    };
    // Admission state is request-local even when immutable locator/input owners
    // share the existing preparation recipe across requests.
    let keys: Vec<_> = rows
        .iter()
        .map(|row| ModifierKey {
            bytes: Arc::clone(&row.bytes),
            input: Arc::clone(&row.input),
            admitted: Default::default(),
        })
        .collect();
    reuse
        .store
        .modifiers
        .values
        .retain_current_keys(keys.iter().map(|key| key.bytes.as_ref()));
    Some(keys)
}
pub(super) fn modifier_facts_reused<'a>(
    writes: impl ExactSizeIterator<Item = &'a InitializerWrite>,
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
    ordinals: &[usize],
    factory: ParallelEvaluator<'_>,
    reuse: InitializerReuse<'_>,
    keys: &[ModifierKey],
) -> Result<Vec<ModifierFact>, ClassificationError> {
    modifier_facts_reused_in(
        writes, symbols, evaluator, ordinals, factory, reuse, keys, None,
    )
}
pub(super) fn modifier_facts_reused_in<'a>(
    writes: impl ExactSizeIterator<Item = &'a InitializerWrite>,
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
    ordinals: &[usize],
    factory: ParallelEvaluator<'_>,
    reuse: InitializerReuse<'_>,
    keys: &[ModifierKey],
    admission: Option<&super::current_admission::Admission<'_, '_>>,
) -> Result<Vec<ModifierFact>, ClassificationError> {
    let host = Host(reuse.resolver);
    collect(writes, Some(ordinals), |write, ordinal| {
        if keys[ordinal].input.as_ref() != write {
            return capture(write, symbols, evaluator, ordinal);
        }
        if let Some(value) = super::current_admission::visit(
            &reuse.store.modifiers.values,
            &keys[ordinal].bytes,
            &host,
            admission,
            &mut |value| value.input.as_ref() == write,
        )
        .0
        {
            let _ = keys[ordinal].admitted.set(Arc::clone(&value.input));
            reuse.store.modifiers.hits.fetch_add(1, Ordering::Relaxed);
            return Ok(value.fact);
        }
        let recording = crate::lowering_memo::RecordingResolver::new(&host);
        let mut result = None;
        let captured =
            factory
                .factory
                .with_recording_evaluator(factory.engine, &recording, &mut |worker| {
                    assert!(result.is_none(), "modifier recording factory invoked twice");
                    result = Some(capture(write, symbols, worker, ordinal));
                });
        let fact = if captured {
            result.ok_or("modifier recording factory omitted operation")??
        } else {
            capture(write, symbols, evaluator, ordinal)?
        };
        reuse
            .store
            .modifiers
            .recomputed
            .fetch_add(1, Ordering::Relaxed);
        if captured {
            let _ = keys[ordinal].admitted.set(Arc::clone(&keys[ordinal].input));
            let reads = recording.reads();
            let versions = recording.domain_receipts();
            if let Some(weight) = crate::heap_census::resident_modifier_weight(
                &keys[ordinal].input,
                &keys[ordinal].bytes,
                &reads,
                &versions,
            ) {
                reuse.store.modifiers.values.insert_current_qualified_with(
                    keys[ordinal].bytes.clone().into(),
                    reads.into(),
                    versions.into(),
                    weight,
                    || ModifierArtifact {
                        input: Arc::clone(&keys[ordinal].input),
                        fact,
                    },
                );
            }
        }
        Ok(fact)
    })
}

#[cfg(test)]
#[path = "modifier_facts_tests.rs"]
mod tests;
