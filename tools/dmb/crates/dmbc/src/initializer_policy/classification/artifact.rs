//! Per-write semantics, independently admitted by the shared dependency ledger.
//! Immutable input descriptors retain exact source-relative tokens. Current
//! ordinals/provenance never escape; runtime syntax uses the existing reissuer.
use super::*;
#[path = "receipts.rs"]
mod receipts;
#[path = "shared_expression.rs"]
mod shared_expression;
use dm_ir::{ReadDomain, ResolveQuery, ResolvedMeaning, Resolver};
pub(super) use receipts::ReceiptPool;
use std::sync::atomic::{AtomicU64, Ordering};
#[cfg(test)]
#[path = "artifact_tests.rs"]
mod tests;

enum RuntimeRecipe {
    Expression(shared_expression::SharedExpression),
    SizedArray(Arc<[u16]>),
    SizedArrayExplicit {
        dimensions: Arc<[u16]>,
        expression: Option<shared_expression::SharedExpression>,
    },
}
pub(crate) struct SemanticClassification {
    // This token identifies one admitted immutable result without retaining its
    // recreatable syntax/input payload through downstream placement receipts.
    identity: Arc<u8>,
    source_features: dm_codegen_byond::SourceFeatures,
    input: Option<ClassificationInput>,
    default: DefaultValue,
    phase: Option<Phase>,
    runtime: Option<RuntimeRecipe>,
    key: Option<Arc<[u8]>>,
}
#[derive(PartialEq, Eq)]
pub(crate) struct ClassificationInput {
    pub(crate) write: Arc<InitializerWrite>,
    fact: ModifierFact,
    policy: u128,
    factory_policy: u128,
    resource_context: Option<u128>,
    engine: Option<u128>,
}
impl ClassificationInput {
    fn new(
        write: Arc<InitializerWrite>,
        fact: ModifierFact,
        reuse: InitializerReuse<'_>,
        factory: ParallelEvaluator<'_>,
        factory_policy: u128,
    ) -> Self {
        Self {
            write,
            fact,
            policy: reuse.policy,
            factory_policy,
            resource_context: reuse.resource_search_context,
            engine: factory.engine.map(|engine| engine.identity()),
        }
    }
}
pub struct InitializerArtifacts {
    pub(in crate::initializer_policy) modifiers:
        crate::initializer_policy::modifier_facts::ModifierArtifacts,
    values: crate::initializer_lowering::receipts::publication_store::Store<
        SemanticClassification,
        dm_ir::ResolveQuery,
        dm_ir::ResolvedMeaning,
        dm_ir::ReadDomain,
    >,
    bounded: bool,
    pub(super) roster: Arc<super::token_roster::CurrentRoster>,
    roster_publication:
        Arc<dm_session::ArtifactPublication<Arc<super::token_roster::CurrentRoster>>>,
    roster_attempt: dm_session::ArtifactAttempt<Arc<super::token_roster::CurrentRoster>>,
    pub(super) roster_enabled: bool,
    pub hits: AtomicU64,
    pub recomputed: AtomicU64,
    pub declined: AtomicU64,
}
impl Default for InitializerArtifacts {
    fn default() -> Self {
        let roster = Arc::new(super::token_roster::CurrentRoster::default());
        let roster_publication = Arc::new(dm_session::ArtifactPublication::default());
        let roster_attempt = roster_publication.begin(Arc::clone(&roster));
        Self {
            values:
                crate::initializer_lowering::receipts::publication_store::Store::current_revision(),
            bounded: false,
            modifiers: Default::default(),
            roster,
            roster_publication,
            roster_attempt,
            roster_enabled: true,
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
            declined: AtomicU64::new(0),
        }
    }
}
impl InitializerArtifacts {
    pub(crate) fn compact_for_pressure(&self, bytes: usize) -> dm_session::PressurePrune {
        self.release_runtime_syntax();
        self.roster.clear();
        self.roster_publication
            .with_published(|roster| roster.clear());
        // Both stores share this aggregate logical cap. Every surviving modifier
        // retains its exact input and receipt; unknown nested owners decline.
        let mut report = self.values.prune_for_pressure_shared(
            bytes.saturating_sub(bytes / 4),
            crate::heap_census::initializer_artifacts::compact_allocations,
        );
        let modifiers = self
            .modifiers
            .compact_for_pressure(bytes.saturating_sub(report.charged_bytes));
        report.charged_bytes += modifiers.charged_bytes;
        report.payload_bytes += modifiers.payload_bytes;
        report.index_logical_bytes += modifiers.index_logical_bytes;
        report.retained_entries += modifiers.retained_entries;
        report.evicted_entries += modifiers.evicted_entries;
        report
    }
    pub(crate) fn for_request(&self, publishable: bool) -> Arc<Self> {
        let previous = self
            .roster_publication
            .with_published(Arc::clone)
            .unwrap_or_else(|| Arc::clone(&self.roster));
        let roster = Arc::new(previous.fork());
        let roster_attempt = if publishable {
            self.roster_publication.begin(Arc::clone(&roster))
        } else {
            self.roster_publication.begin_ephemeral(Arc::clone(&roster))
        };
        Arc::new(Self {
            values: self.values.for_request(publishable),
            modifiers: self.modifiers.for_request(publishable),
            bounded: self.bounded,
            roster_enabled: self.roster_enabled,
            roster,
            roster_publication: Arc::clone(&self.roster_publication),
            roster_attempt,
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
            declined: AtomicU64::new(0),
        })
    }
    pub(crate) fn publish_successful(&self) -> bool {
        let values = self.values.publish_successful();
        let modifiers = self.modifiers.publish_successful();
        let roster = self.roster_attempt.publish_successful();
        values && modifiers && roster
    }
    pub(crate) fn visit_storage(
        &self,
        visitor: impl FnMut(dm_session::ArtifactStorageView<'_, SemanticClassification>),
    ) {
        self.values.visit_storage(visitor);
    }
    pub(crate) fn visit_modifier_storage(
        &self,
        visitor: impl FnMut(
            dm_session::ArtifactStorageView<
                '_,
                crate::initializer_policy::modifier_facts::ModifierArtifact,
            >,
        ),
    ) {
        self.modifiers.visit_storage(visitor);
    }

    /// Release recreatable runtime ASTs without changing semantic admission or
    /// the accepted-owner identities used by the canonical token roster.
    pub fn release_runtime_syntax(&self) {
        self.values.visit_storage(|storage| {
            if let dm_session::ArtifactStorageView::Entry { value, .. } = storage {
                if let Some(
                    RuntimeRecipe::Expression(syntax)
                    | RuntimeRecipe::SizedArrayExplicit {
                        expression: Some(syntax),
                        ..
                    },
                ) = &value.runtime
                {
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
    pub(crate) fn visit_roster_storage(&self, mut visit: impl FnMut(usize, usize)) {
        visit(
            Arc::as_ptr(&self.roster) as usize,
            std::mem::size_of_val(self.roster.as_ref()),
        );
        self.roster_publication.with_published(|roster| {
            if !Arc::ptr_eq(roster, &self.roster) {
                visit(
                    Arc::as_ptr(roster) as usize,
                    std::mem::size_of_val(roster.as_ref()),
                );
            }
        });
    }

    #[allow(clippy::type_complexity)]
    pub(crate) fn visit_token_index(
        &self,
        mut visitor: impl FnMut(&crate::initializer_tokens::CanonicalTokens),
    ) {
        self.roster.visit_canonical(&mut visitor);
        self.roster_publication.with_published(|roster| {
            if !Arc::ptr_eq(roster, &self.roster) {
                roster.visit_canonical(&mut visitor);
            }
        });
    }
    pub(crate) fn visit_token_roster(
        &self,
        mut visitor: impl FnMut(&Vec<Arc<u8>>, &Vec<Option<(u32, Arc<[u8]>)>>, &Vec<RuntimeGroup>),
    ) {
        self.roster.visit(&mut visitor);
        self.roster_publication.with_published(|roster| {
            if !Arc::ptr_eq(roster, &self.roster) {
                roster.visit(&mut visitor);
            }
        });
    }
    pub(crate) fn visit_preparation(
        &self,
        mut visitor: impl FnMut(&Arc<super::token_roster::preparation::Preparation>),
    ) {
        self.roster.visit_preparation(&mut visitor);
        self.roster_publication.with_published(|roster| {
            if !Arc::ptr_eq(roster, &self.roster) {
                roster.visit_preparation(&mut visitor);
            }
        });
    }

    pub fn modifier_reuse_counts(&self) -> (u64, u64) {
        (
            self.modifiers.hits.load(Ordering::Relaxed),
            self.modifiers.recomputed.load(Ordering::Relaxed),
        )
    }

    fn admission_charge(&self, full_weight: impl FnOnce() -> Option<usize>) -> Option<usize> {
        if self.bounded {
            full_weight()
        } else {
            Some(std::mem::size_of::<SemanticClassification>())
        }
    }
    pub fn with_limit(bytes: usize) -> Self {
        let roster = Arc::new(super::token_roster::CurrentRoster::default());
        let roster_publication = Arc::new(dm_session::ArtifactPublication::default());
        let roster_attempt = roster_publication.begin(Arc::clone(&roster));
        Self {
            values: crate::initializer_lowering::receipts::publication_store::Store::with_limit(
                bytes,
            ),
            bounded: true,
            // Preserve the explicit compatibility budget; the new full-current
            // modifier owner is enabled only by retained-session defaults.
            modifiers: crate::initializer_policy::modifier_facts::ModifierArtifacts::with_limit(0),
            roster,
            roster_publication,
            roster_attempt,
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
    fn observes_reads(&self) -> bool {
        self.0.observes_reads()
    }
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
    let mut key = b"dmbc-initializer-classification-v6-folded-features\0".to_vec();
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
    key.push(u8::from(
        write.source_site == dm_ir::InitializerSite::Declaration,
    ));
    key.extend_from_slice(&crate::initializer_lowering::receipts::fragment_locator(
        write,
    ));
    key
}
pub(super) fn retain_roster(reuse: InitializerReuse<'_>, keys: &[Arc<[u8]>]) {
    reuse
        .store
        .values
        .retain_current_keys(keys.iter().map(AsRef::as_ref));
}
impl SemanticClassification {
    pub(crate) fn identity(&self) -> Arc<u8> {
        Arc::clone(&self.identity)
    }
    pub(crate) fn input_write(&self) -> Option<&Arc<InitializerWrite>> {
        self.input.as_ref().map(|input| &input.write)
    }
    #[allow(clippy::type_complexity)]
    pub(crate) fn visit_retained_parts(
        &self,
        visitor: impl FnOnce(
            &DefaultValue,
            Option<&Arc<[u8]>>,
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
            Some(RuntimeRecipe::SizedArrayExplicit {
                dimensions,
                expression,
            }) => {
                if let Some(value) = expression {
                    value.visit_retained(|source, syntax| {
                        visitor(
                            &self.default,
                            self.key.as_ref(),
                            Some(dimensions),
                            Some((source, syntax)),
                        )
                    });
                } else {
                    visitor(&self.default, self.key.as_ref(), Some(dimensions), None);
                }
            }
            Some(RuntimeRecipe::SizedArray(value)) => {
                visitor(&self.default, self.key.as_ref(), Some(value), None);
            }
            None => visitor(&self.default, self.key.as_ref(), None, None),
        }
    }

    pub(super) fn token_key(&self) -> Option<&Arc<[u8]>> {
        self.key.as_ref()
    }
    fn capture(pending: &mut PendingWrite, symbols: &SymbolTable) -> Option<Self> {
        let parsed_source = pending.parsed_runtime_source.take();
        let runtime = match pending.write.runtime_value.as_ref() {
            None => None,
            Some(RuntimeValue::SizedArray(dimensions)) => {
                Some(RuntimeRecipe::SizedArray(Arc::clone(dimensions)))
            }
            Some(RuntimeValue::SizedArrayExplicit {
                dimensions,
                expression,
            }) => {
                let syntax = if let Some(expression) = expression {
                    let InitializerValue::Expression(value) = &pending.write.write.value else {
                        return None;
                    };
                    Some(match parsed_source {
                        Some(source) => {
                            shared_expression::SharedExpression::from_parser(source, expression)
                        }
                        None => shared_expression::SharedExpression::capture(
                            value.source_text(symbols)?,
                            expression,
                        )?,
                    })
                } else {
                    None
                };
                Some(RuntimeRecipe::SizedArrayExplicit {
                    dimensions: Arc::clone(dimensions),
                    expression: syntax,
                })
            }
            Some(RuntimeValue::Expression(expression)) => {
                let InitializerValue::Expression(value) = &pending.write.write.value else {
                    return None;
                };
                let syntax = match parsed_source {
                    Some(source) => {
                        shared_expression::SharedExpression::from_parser(source, expression)
                    }
                    None => shared_expression::SharedExpression::capture(
                        value.source_text(symbols)?,
                        expression,
                    )?,
                };
                Some(RuntimeRecipe::Expression(syntax))
            }
        };
        Some(Self {
            identity: Arc::new(0),
            input: None,
            source_features: pending.write.source_features,
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
        let current_expression = match &write.value {
            InitializerValue::Expression(value) => Some(value.source_text(symbols)?),
            _ => None,
        };
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
            Some(RuntimeRecipe::SizedArrayExplicit {
                dimensions,
                expression,
            }) => Some(RuntimeValue::SizedArrayExplicit {
                dimensions: Arc::clone(dimensions),
                expression: match expression {
                    Some(syntax) => Some(syntax.bind(current_expression.as_deref()?)?),
                    None => None,
                },
            }),
            Some(RuntimeRecipe::Expression(syntax)) => Some(RuntimeValue::Expression(
                syntax.bind(current_expression.as_deref()?)?,
            )),
        };
        Some(PendingWrite {
            write: ClassifiedWrite {
                source_features: self.source_features,
                source_ordinal: ordinal,
                write: write.clone(),
                default: self.default.clone(),
                phase: self.phase,
                runtime_value,
            },
            key: None,
            accepted: None,
            parsed_runtime_source: None,
        })
    }
}
#[cfg(test)]
pub(super) fn classify_one(
    write: &InitializerWrite,
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
    fact: ModifierFact,
    ordinal: usize,
    factory: ParallelEvaluator<'_>,
    reuse: InitializerReuse<'_>,
) -> Result<PendingWrite, ClassificationFailure> {
    let prepared = factory
        .factory
        .recording_policy_identity()
        .map(|policy| Arc::<[u8]>::from(key(write, fact, reuse, policy)));
    classify_one_keyed(
        write,
        symbols,
        evaluator,
        fact,
        ordinal,
        factory,
        reuse,
        prepared.as_ref(),
    )
}
#[cfg(test)]
#[allow(clippy::too_many_arguments)]
pub(super) fn classify_one_keyed(
    write: &InitializerWrite,
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
    fact: ModifierFact,
    ordinal: usize,
    factory: ParallelEvaluator<'_>,
    reuse: InitializerReuse<'_>,
    prepared_key: Option<&Arc<[u8]>>,
) -> Result<PendingWrite, ClassificationFailure> {
    classify_one_keyed_grouped(
        write,
        symbols,
        evaluator,
        fact,
        ordinal,
        factory,
        reuse,
        prepared_key,
        None,
        None,
        None,
    )
}
#[allow(clippy::too_many_arguments)]
pub(super) fn classify_one_keyed_grouped(
    write: &InitializerWrite,
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
    fact: ModifierFact,
    ordinal: usize,
    factory: ParallelEvaluator<'_>,
    reuse: InitializerReuse<'_>,
    prepared_key: Option<&Arc<[u8]>>,
    receipt_pool: Option<&ReceiptPool>,
    shared_write: Option<&Arc<InitializerWrite>>,
    tokens: Option<&super::token_owner::RequestTokens>,
) -> Result<PendingWrite, ClassificationFailure> {
    classify_one_keyed_grouped_in(
        write,
        symbols,
        evaluator,
        fact,
        ordinal,
        factory,
        reuse,
        prepared_key,
        receipt_pool,
        shared_write,
        tokens,
        None,
    )
}
#[allow(clippy::too_many_arguments)]
pub(super) fn classify_one_keyed_grouped_in(
    write: &InitializerWrite,
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
    fact: ModifierFact,
    ordinal: usize,
    factory: ParallelEvaluator<'_>,
    reuse: InitializerReuse<'_>,
    prepared_key: Option<&Arc<[u8]>>,
    receipt_pool: Option<&ReceiptPool>,
    shared_write: Option<&Arc<InitializerWrite>>,
    tokens: Option<&super::token_owner::RequestTokens>,
    admission: Option<&super::super::current_admission::Admission<'_, '_>>,
) -> Result<PendingWrite, ClassificationFailure> {
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
    let key = prepared_key.expect("certified classification has a prepared key");
    let input = ClassificationInput::new(
        shared_write
            .cloned()
            .unwrap_or_else(|| Arc::new(write.clone())),
        fact,
        reuse,
        factory,
        factory_policy,
    );
    if input.write.as_ref() != write {
        return Err("classification shared input differs from current write".into());
    }
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
                if let Some(value) = super::super::current_admission::visit(
                    &reuse.store.values,
                    key,
                    &host,
                    admission,
                    &mut |value| value.input.as_ref() == Some(&input),
                )
                .0
                {
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
        if let Some(tokens) = tokens {
            if let Some(key) = pending.key.take() {
                pending.key = Some(tokens.share_key(key));
            }
        }
        let Some(mut value) = SemanticClassification::capture(&mut pending, symbols) else {
            reuse.store.declined.fetch_add(1, Ordering::Relaxed);
            reuse.store.recomputed.fetch_add(1, Ordering::Relaxed);
            return Ok(pending);
        };
        value.input = Some(input);
        let reads = recorder.reads();
        let versions = recorder.domain_receipts();
        let dimensions = match &value.runtime {
            Some(
                RuntimeRecipe::SizedArray(dimensions)
                | RuntimeRecipe::SizedArrayExplicit { dimensions, .. },
            ) => Some(dimensions),
            _ => None,
        };
        // Current-roster retention has no byte admission budget. This charge
        // describes inline storage only; opt-in census still visits all owners.
        let charge = reuse.store.admission_charge(|| {
            crate::heap_census::resident_initializer_weight(
                &value.default,
                dimensions,
                value.key.as_ref(),
                key,
                &reads,
                &versions,
            )
            .and_then(|weight| {
                crate::heap_census::resident_modifier_weight(
                    value.input_write()?,
                    &[],
                    &Vec::new(),
                    &Vec::new(),
                )
                .and_then(|input_weight| weight.checked_add(input_weight))
            })
            .and_then(|weight| match &value.runtime {
                Some(
                    RuntimeRecipe::Expression(syntax)
                    | RuntimeRecipe::SizedArrayExplicit {
                        expression: Some(syntax),
                        ..
                    },
                ) => syntax.visit_retained(|source, expression| {
                    expression.and_then(|expression| {
                        crate::heap_census::resident_initializer_syntax_weight(source, expression)
                            .and_then(|extra| weight.checked_add(extra))
                    })
                }),
                _ => Some(weight),
            })
        });
        let admitted = charge.and_then(|weight| {
            // Explicit byte-budget callers keep their original flat allocation
            // charge. Current-roster diagnostics count grouped owners directly.
            let receipt = receipts::capture(
                reads,
                write.lexical_owner,
                receipt_pool.filter(|_| !reuse.store.bounded),
            );
            reuse.store.values.insert_current_qualified_with(
                Arc::clone(key),
                receipt,
                versions.into(),
                weight,
                || value,
            )
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

#[cfg(test)]
#[path = "bind_text_tests.rs"]
mod bind_text_tests;
