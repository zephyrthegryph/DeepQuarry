//! Per-write semantics, independently admitted by the shared dependency ledger.
//! Current declarations, ordinals and runtime syntax never escape into this store.
use super::*;
#[path = "shared_expression.rs"]
mod shared_expression;
use dm_ir::{ReadDomain, ResolveQuery, ResolvedMeaning, Resolver};
use std::sync::atomic::{AtomicU64, Ordering};
#[cfg(test)]
#[path = "artifact_tests.rs"]
mod tests;

enum RuntimeRecipe {
    Expression(shared_expression::SharedExpression),
    SizedArray(Arc<[u16]>),
}
pub(crate) struct SemanticClassification {
    default: DefaultValue,
    phase: Option<Phase>,
    runtime: Option<RuntimeRecipe>,
    key: Option<Vec<u8>>,
}
pub struct InitializerArtifacts {
    pub(in crate::initializer_policy) modifiers:
        crate::initializer_policy::modifier_facts::ModifierArtifacts,
    values: dm_session::ArtifactStore<SemanticClassification>,
    pub(super) roster: super::token_roster::CurrentRoster,
    pub(super) roster_enabled: bool,
    pub hits: AtomicU64,
    pub recomputed: AtomicU64,
    pub declined: AtomicU64,
}
impl Default for InitializerArtifacts {
    fn default() -> Self {
        Self {
            values: dm_session::ArtifactStore::current_revision(),
            modifiers: Default::default(),
            roster: Default::default(),
            roster_enabled: true,
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
            declined: AtomicU64::new(0),
        }
    }
}
impl InitializerArtifacts {
    pub(crate) fn visit_storage(
        &self,
        visitor: impl FnMut(dm_session::ArtifactStorageView<'_, SemanticClassification>),
    ) {
        self.values.visit_storage(visitor);
    }
    pub(crate) fn visit_modifier_storage(
        &self,
        visitor: impl FnMut(dm_session::ArtifactStorageView<'_, ModifierFact>),
    ) {
        self.modifiers.visit_storage(visitor);
    }

    /// Release recreatable runtime ASTs without changing semantic admission or
    /// the accepted-owner identities used by the canonical token roster.
    pub fn release_runtime_syntax(&self) {
        self.values.visit_storage(|storage| {
            if let dm_session::ArtifactStorageView::Entry { value, .. } = storage {
                if let Some(RuntimeRecipe::Expression(syntax)) = &value.runtime {
                    syntax.release_syntax();
                }
            }
        });
    }
    pub fn token_roster_reuse_counts(&self) -> (u64, u64) {
        (
            self.roster.hits.load(Ordering::Relaxed),
            self.roster.recomputed.load(Ordering::Relaxed),
        )
    }
    #[allow(clippy::type_complexity)]
    pub(crate) fn visit_token_roster(
        &self,
        visitor: impl FnOnce(
            &Vec<Arc<SemanticClassification>>,
            &Vec<Option<(u32, Arc<[u8]>)>>,
            &Vec<RuntimeGroup>,
        ),
    ) {
        self.roster.visit(visitor);
    }

    pub fn modifier_reuse_counts(&self) -> (u64, u64) {
        (
            self.modifiers.hits.load(Ordering::Relaxed),
            self.modifiers.recomputed.load(Ordering::Relaxed),
        )
    }

    pub fn with_limit(bytes: usize) -> Self {
        Self {
            values: dm_session::ArtifactStore::with_limit(bytes),
            // Preserve the explicit compatibility budget; the new full-current
            // modifier owner is enabled only by retained-session defaults.
            modifiers: crate::initializer_policy::modifier_facts::ModifierArtifacts::with_limit(0),
            roster: Default::default(),
            roster_enabled: false,
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
            declined: AtomicU64::new(0),
        }
    }
}
#[derive(Clone, Copy)]
pub struct InitializerReuse<'a> {
    pub store: &'a InitializerArtifacts,
    pub resolver: &'a dyn Resolver,
    pub policy: u128,
    pub resource_search_context: Option<u128>,
}
struct ResolverView<'a>(&'a dyn Resolver);
impl Resolver for ResolverView<'_> {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        self.0.resolve(query)
    }
    fn domain_version(&self, domain: ReadDomain) -> Option<u128> {
        self.0.domain_version(domain)
    }
}
pub(super) fn key(
    write: &InitializerWrite,
    fact: ModifierFact,
    reuse: InitializerReuse<'_>,
    factory_policy: u128,
) -> Vec<u8> {
    let mut key = b"dmbc-initializer-classification-v2\0".to_vec();
    key.extend_from_slice(&reuse.policy.to_le_bytes());
    key.extend_from_slice(&factory_policy.to_le_bytes());
    match reuse.resource_search_context {
        Some(context) => {
            key.push(1);
            key.extend_from_slice(&context.to_le_bytes());
        }
        None => key.push(0),
    }
    match fact {
        ModifierFact::Known(flags) => {
            key.push(0);
            key.extend_from_slice(&flags.to_le_bytes());
        }
        ModifierFact::MutableInstance => key.push(1),
        ModifierFact::Header(domain) => {
            key.push(2);
            key.extend_from_slice(domain.label().as_bytes());
            key.push(0);
        }
    }
    write.write_canonical(|bytes| key.extend_from_slice(bytes));
    key
}
pub(super) fn retain_roster(reuse: InitializerReuse<'_>, keys: &[Vec<u8>]) {
    reuse
        .store
        .values
        .retain_current_keys(keys.iter().map(Vec::as_slice));
}
impl SemanticClassification {
    #[allow(clippy::type_complexity)]
    pub(crate) fn visit_retained_parts(
        &self,
        visitor: impl FnOnce(
            &DefaultValue,
            Option<&Vec<u8>>,
            Option<&Arc<[u16]>>,
            Option<(&Arc<str>, Option<&Arc<dm_syntax::Expr>>)>,
        ),
    ) {
        match &self.runtime {
            Some(RuntimeRecipe::Expression(value)) => value.visit_retained(|source, syntax| {
                visitor(
                    &self.default,
                    self.key.as_ref(),
                    None,
                    Some((source, syntax)),
                );
            }),
            Some(RuntimeRecipe::SizedArray(value)) => {
                visitor(&self.default, self.key.as_ref(), Some(value), None);
            }
            None => visitor(&self.default, self.key.as_ref(), None, None),
        }
    }

    pub(super) fn token_key(&self) -> Option<&Vec<u8>> {
        self.key.as_ref()
    }
    fn capture(pending: &PendingWrite, symbols: &SymbolTable) -> Option<Self> {
        let runtime = match pending.write.runtime_value.as_ref() {
            None => None,
            Some(RuntimeValue::SizedArray(dimensions)) => {
                Some(RuntimeRecipe::SizedArray(Arc::clone(dimensions)))
            }
            Some(RuntimeValue::Expression(expression)) => {
                let InitializerValue::Expression(value) = &pending.write.write.value else {
                    return None;
                };
                let source = value.source_text(symbols)?;
                Some(RuntimeRecipe::Expression(
                    shared_expression::SharedExpression::capture(source, expression)?,
                ))
            }
        };
        Some(Self {
            default: pending.write.default.clone(),
            phase: pending.write.phase,
            runtime,
            key: pending.key.clone(),
        })
    }
    fn bind(
        &self,
        write: &InitializerWrite,
        symbols: &SymbolTable,
        ordinal: usize,
    ) -> Option<PendingWrite> {
        // Canonical keys intentionally omit source offsets. Validate current
        // token issuance/spelling before accepting scalar hits as well as ASTs.
        if let InitializerValue::Expression(value) = &write.value {
            value.source_text(symbols)?;
        }
        if let Some(array) = &write.declared_array {
            for value in array.dimensions.iter().flatten() {
                value.source_text(symbols)?;
            }
        }
        let runtime_value = match &self.runtime {
            None => None,
            Some(RuntimeRecipe::SizedArray(dimensions)) => {
                Some(RuntimeValue::SizedArray(Arc::clone(dimensions)))
            }
            Some(RuntimeRecipe::Expression(syntax)) => {
                let InitializerValue::Expression(value) = &write.value else {
                    return None;
                };
                let text = value.source_text(symbols)?;
                Some(RuntimeValue::Expression(syntax.bind(&text)?))
            }
        };
        Some(PendingWrite {
            write: ClassifiedWrite {
                source_ordinal: ordinal,
                write: write.clone(),
                default: self.default.clone(),
                phase: self.phase,
                runtime_value,
            },
            key: None,
            accepted: None,
        })
    }
}
pub(super) fn classify_one(
    write: &InitializerWrite,
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
    fact: ModifierFact,
    ordinal: usize,
    factory: ParallelEvaluator<'_>,
    reuse: InitializerReuse<'_>,
) -> Result<PendingWrite, String> {
    let Some(factory_policy) = factory.factory.recording_policy_identity() else {
        reuse.store.declined.fetch_add(1, Ordering::Relaxed);
        let mut local = 0;
        let mut pending = classify_pending(
            std::iter::once(write),
            symbols,
            evaluator,
            &[fact],
            &mut local,
        )?
        .pop()
        .ok_or("initializer classification produced no write")?;
        pending.write.source_ordinal = ordinal;
        return Ok(pending);
    };
    let key = key(write, fact, reuse, factory_policy);
    let host = ResolverView(reuse.resolver);
    let recorder = crate::lowering_memo::RecordingResolver::new(&host);
    let mut result = None;
    let mut hit = false;
    let captured =
        factory
            .factory
            .with_recording_evaluator(factory.engine, &recorder, &mut |worker| {
                assert!(
                    result.is_none(),
                    "initializer recording factory invoked twice"
                );
                if let Some(value) = reuse.store.values.lookup(&key, &host) {
                    if let Some(mut current) = value.bind(write, symbols, ordinal) {
                        current.accepted = Some(Arc::clone(&value));
                        hit = true;
                        result = Some(Ok(vec![current]));
                        return;
                    }
                }
                recorder.resolve(ResolveQuery::Ancestry(write.lexical_owner));
                if let Some(identity) = write.lexical_procedure {
                    recorder.record_occurrence(identity);
                }
                match write.target {
                    InitializerTarget::Shared { owner, name, .. } => {
                        recorder.resolve(ResolveQuery::DeclaredVarType { owner, name });
                    }
                    InitializerTarget::Instance {
                        receiver_owner: owner,
                        name,
                        ..
                    } => {
                        recorder.resolve(ResolveQuery::DeclaredVarType { owner, name });
                    }
                    InitializerTarget::ProcedureStatic(identity) => {
                        recorder.resolve(ResolveQuery::ProcedureStatic {
                            procedure: identity.procedure,
                            name: identity.name,
                        });
                    }
                }
                let mut local = 0;
                result = Some(classify_pending(
                    std::iter::once(write),
                    symbols,
                    worker,
                    &[fact],
                    &mut local,
                ));
            });
    let mut pending = if captured {
        result.ok_or("initializer recording factory omitted operation")??
    } else {
        let mut local = 0;
        classify_pending(
            std::iter::once(write),
            symbols,
            evaluator,
            &[fact],
            &mut local,
        )?
    }
    .pop()
    .ok_or("initializer classification produced no write")?;
    pending.write.source_ordinal = ordinal;
    if captured && hit {
        reuse.store.hits.fetch_add(1, Ordering::Relaxed);
    } else if captured {
        let Some(value) = SemanticClassification::capture(&pending, symbols) else {
            reuse.store.declined.fetch_add(1, Ordering::Relaxed);
            reuse.store.recomputed.fetch_add(1, Ordering::Relaxed);
            return Ok(pending);
        };
        let reads = recorder.reads();
        let versions = recorder.domain_receipts();
        let dimensions = match &value.runtime {
            Some(RuntimeRecipe::SizedArray(dimensions)) => Some(dimensions),
            _ => None,
        };
        let admitted = crate::heap_census::resident_initializer_weight(
            &value.default,
            dimensions,
            value.key.as_ref(),
            &key,
            &reads,
            &versions,
        )
        .and_then(|weight| match &value.runtime {
            Some(RuntimeRecipe::Expression(syntax)) => {
                syntax.visit_retained(|source, expression| {
                    expression.and_then(|expression| {
                        crate::heap_census::resident_initializer_syntax_weight(source, expression)
                            .and_then(|extra| weight.checked_add(extra))
                    })
                })
            }
            _ => Some(weight),
        })
        .and_then(|weight| {
            reuse
                .store
                .values
                .insert_with_owned(key.into(), reads, versions, weight, || value)
        });
        if let Some(value) = admitted {
            pending.accepted = Some(value);
        } else {
            reuse.store.declined.fetch_add(1, Ordering::Relaxed);
        }
        reuse.store.recomputed.fetch_add(1, Ordering::Relaxed);
    }
    Ok(pending)
}
