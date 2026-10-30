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
fn capture_with<E: From<String> + From<&'static str>>(
    write: &InitializerWrite,
    symbols: &SymbolTable,
    knowledge: impl FnOnce() -> Result<Option<BindingKnowledge>, E>,
    ordinal: usize,
) -> Result<ModifierFact, E> {
    if let Some(domain) = header_domain(write, symbols)? {
        return Ok(ModifierFact::Header(domain));
    }
    let knowledge = knowledge()?.ok_or_else(|| {
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

fn capture(write: &InitializerWrite, symbols: &SymbolTable, evaluator: &dyn CapturedInitializerEvaluator, ordinal: usize) -> Result<ModifierFact, String> {
    capture_with(write, symbols, || evaluator.binding_knowledge(write), ordinal)
}
fn capture_checked(write: &InitializerWrite, symbols: &SymbolTable, evaluator: &dyn CapturedInitializerEvaluator, ordinal: usize) -> Result<ModifierFact, InitializerFailure> {
    capture_with(write, symbols, || evaluator.binding_knowledge_checked(write), ordinal)
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
enum ModifierEntryFailure<E> { Semantic(String), Operational(E) }
/// Operation-local transport. Semantic issue objects remain the existing cache
/// domain; an actual IO failure is never inserted into one of them.
pub(super) enum ModifierReadFailure { Semantic(ClassificationError), Operational(std::io::Error) }
impl std::fmt::Debug for ModifierReadFailure {
    fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result {
        match self { Self::Semantic(error)=>f.debug_tuple("Semantic").field(error).finish(),Self::Operational(error)=>f.debug_tuple("Operational").field(error).finish() }
    }
}
pub(super) fn modifier_facts_indexed_checked<'a>(
    writes: impl ExactSizeIterator<Item=&'a InitializerWrite>, symbols:&SymbolTable,
    evaluator:&dyn CapturedInitializerEvaluator, ordinals:Option<&[usize]>,
)->Result<Vec<ModifierFact>,ModifierReadFailure>{
    collect_checked(writes,ordinals,|write,ordinal|capture_checked(write,symbols,evaluator,ordinal))
}
fn collect_checked<'a>(writes:impl ExactSizeIterator<Item=&'a InitializerWrite>,ordinals:Option<&[usize]>,mut produce:impl FnMut(&InitializerWrite,usize)->Result<ModifierFact,InitializerFailure>)->Result<Vec<ModifierFact>,ModifierReadFailure>{
    crate::daemon::control::checkpoint().map_err(ModifierReadFailure::Operational)?;
    let result=collect_with(writes,ordinals,|write,ordinal|produce(write,ordinal).map_err(|failure|match failure {
        InitializerFailure::Unsupported(reason)=>ModifierEntryFailure::Semantic(reason),
        InitializerFailure::Operational(actual)=>ModifierEntryFailure::Operational(actual),
    })).map_err(ModifierReadFailure::Operational)?;
    crate::daemon::control::checkpoint().map_err(ModifierReadFailure::Operational)?;
    result.map_err(ModifierReadFailure::Semantic)
}

fn collect<'a>(
    writes: impl ExactSizeIterator<Item=&'a InitializerWrite>, ordinals:Option<&[usize]>,
    mut produce:impl FnMut(&InitializerWrite,usize)->Result<ModifierFact,String>,
)->Result<Vec<ModifierFact>,ClassificationError>{
    match collect_with::<std::convert::Infallible>(writes,ordinals,|write,ordinal|produce(write,ordinal).map_err(ModifierEntryFailure::Semantic)) {
        Ok(result)=>result,Err(never)=>match never{},
    }
}
fn collect_with<'a, E>(
    writes: impl ExactSizeIterator<Item = &'a InitializerWrite>,
    ordinals: Option<&[usize]>,
    mut produce: impl FnMut(&InitializerWrite, usize) -> Result<ModifierFact, ModifierEntryFailure<E>>,
) -> Result<Result<Vec<ModifierFact>, ClassificationError>, E> {
    let mut facts = Vec::with_capacity(writes.len());
    let mut issues = Vec::new();
    for (local, write) in writes.enumerate() {
        let ordinal = ordinals.map_or(local, |ordinals| ordinals[local]);
        match produce(write, ordinal) {
            Ok(fact) => facts.push(fact),
            Err(ModifierEntryFailure::Operational(actual)) => return Err(actual),
            Err(ModifierEntryFailure::Semantic(reason)) => issues.push(ClassificationIssue {
                kind: ClassificationIssueKind::Unsupported,
                source_ordinal: ordinal,
                reason,
            }),
        }
    }
    if issues.is_empty() {
        Ok(Ok(facts))
    } else {
        Ok(Err(ClassificationError { issues }))
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
                crate::initializer_lowering::receipts::publication_store::Store::shared_current_revision("initializer.modifiers"),
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
    fn answer_world(&self) -> Option<u128> {
        self.0.answer_world()
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
        let context_digest = {
            let mut context = b"dmbc-modifier-fact-v3-context-digest\0".to_vec();
            context.extend_from_slice(&reuse.policy.to_le_bytes());
            context.extend_from_slice(&policy.to_le_bytes());
            match reuse.resource_search_context {
                Some(value) => {
                    context.push(1);
                    context.extend_from_slice(&value.to_le_bytes());
                }
                None => context.push(0),
            }
            match factory.engine {
                Some(engine) => {
                    context.push(1);
                    context.extend_from_slice(&engine.identity().to_le_bytes());
                }
                None => context.push(0),
            }
            xxhash_rust::xxh3::xxh3_128(&context)
        };
        let keys = writes
            .iter()
            .map(|write| {
                // Digest of the parts every write of this classification shares; see `classification::artifact::key`.
                let mut key = Vec::with_capacity(64);
                key.push(3);
                key.extend_from_slice(&context_digest.to_le_bytes());
                // The existing certified evaluator may inspect any write field. Full exact
                // inputs avoid inventing a weaker modifier-only policy contract.
                key.extend_from_slice(&crate::initializer_lowering::receipts::fragment_locator(
                    write,
                ));
                let duplicate = duplicates.entry(key.clone()).or_default();
                key.extend_from_slice(&(*duplicate as u32).to_le_bytes());
                *duplicate += 1;
                classification::token_roster::preparation::shared_locator(key, write)
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
    collect(writes, Some(ordinals), |write, ordinal| {
        capture_reused_with(write,ordinal,evaluator,factory,reuse,keys,admission,||Ok(()),|worker|capture(write,symbols,worker,ordinal))
    })
}
pub(super) fn modifier_facts_reused_checked_in<'a>(
    writes:impl ExactSizeIterator<Item=&'a InitializerWrite>,symbols:&SymbolTable,evaluator:&dyn CapturedInitializerEvaluator,ordinals:&[usize],factory:ParallelEvaluator<'_>,reuse:InitializerReuse<'_>,keys:&[ModifierKey],admission:Option<&super::current_admission::Admission<'_,'_>>,
)->Result<Vec<ModifierFact>,ModifierReadFailure>{
    collect_checked(writes,Some(ordinals),|write,ordinal|capture_reused_with(write,ordinal,evaluator,factory,reuse,keys,admission,||crate::daemon::control::checkpoint().map_err(InitializerFailure::Operational),|worker|capture_checked(write,symbols,worker,ordinal)))
}
fn capture_reused_with<E:From<String>+From<&'static str>>(
    write:&InitializerWrite,ordinal:usize,evaluator:&dyn CapturedInitializerEvaluator,factory:ParallelEvaluator<'_>,reuse:InitializerReuse<'_>,keys:&[ModifierKey],admission:Option<&super::current_admission::Admission<'_,'_>>,checkpoint:impl Fn()->Result<(),E>,mut produce:impl FnMut(&dyn CapturedInitializerEvaluator)->Result<ModifierFact,E>,
)->Result<ModifierFact,E>{
    static ITEM: dm_profile::Accumulator = dm_profile::Accumulator::new("init.modifier.item");
    static VISIT: dm_profile::Accumulator = dm_profile::Accumulator::new("init.modifier.visit");
    static INPUT: dm_profile::Accumulator = dm_profile::Accumulator::new("init.modifier.input_eq");
    checkpoint()?;
    let host = Host(reuse.resolver);
        let _item = ITEM.time();
        let input_timer = INPUT.time();
        if keys[ordinal].input.as_ref() != write {
            return produce(evaluator);
        }
        drop(input_timer);
        let visit_timer = VISIT.time();
        let visited = super::current_admission::visit(
            &reuse.store.modifiers.values,
            &keys[ordinal].bytes,
            &host,
            admission,
            &mut |value| value.input.as_ref() == write,
        )
        .0;
        drop(visit_timer);
        if let Some(value) = visited {
            checkpoint()?;
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
                    result = Some(produce(worker));
                });
        let fact = if captured {
            result.ok_or("modifier recording factory omitted operation")??
        } else {
            produce(evaluator)?
        };
        checkpoint()?;
        reuse
            .store
            .modifiers
            .recomputed
            .fetch_add(1, Ordering::Relaxed);
        if captured {
            let _ = keys[ordinal].admitted.set(Arc::clone(&keys[ordinal].input));
            let reads = recording.reads();
            if let Some(weight) = crate::heap_census::resident_modifier_weight(
                &keys[ordinal].input,
                &keys[ordinal].bytes,
                &reads,
            ) {
                reuse.store.modifiers.values.insert_current_qualified_with(
                    keys[ordinal].bytes.clone().into(),
                    reads.into(),
                    weight,
                    || ModifierArtifact {
                        input: Arc::clone(&keys[ordinal].input),
                        fact,
                    },
                );
            }
        }
        Ok(fact)

}

#[cfg(test)]
#[path = "modifier_facts_tests.rs"]
mod tests;

#[cfg(test)]
#[path="modifier_checked_tests.rs"]
mod checked_tests;

#[cfg(test)]
#[path="modifier_reuse_checked_tests.rs"]
mod reuse_checked_tests;
