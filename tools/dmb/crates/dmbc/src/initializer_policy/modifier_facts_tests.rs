use super::*;
use dm_ir::{ReadDomain, ResolvedMeaning};
use std::sync::atomic::AtomicU32;
struct Dependency(AtomicU32);
impl Resolver for Dependency {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        match query {
            ResolveQuery::Constant { .. } => {
                ResolvedMeaning::Value(SemanticValue::NumberBits(self.0.load(Ordering::Relaxed)))
            }
            _ => ResolvedMeaning::Unsupported(query),
        }
    }
    fn domain_version(&self, _: ReadDomain) -> Option<u128> {
        None
    }
}
struct Worker<'a> {
    resolver: &'a dyn Resolver,
    captures: &'a AtomicU64,
}

#[test]
fn prepared_modifier_locators_share_exact_inputs_but_replay_changed_semantics() {
    let mut symbols = SymbolTable::default();
    let original = write(&mut symbols);
    let dependency = Dependency(AtomicU32::new(8));
    let captures = AtomicU64::new(0);
    let worker = Worker {
        resolver: &dependency,
        captures: &captures,
    };
    let factory = ParallelEvaluator {
        factory: &worker,
        engine: None,
    };
    let store = InitializerArtifacts::default();
    let reuse = InitializerReuse {
        store: &store,
        resolver: &dependency,
        policy: 1,
        resource_search_context: None,
    };
    let writes = [original.clone()];
    let preparation = classification::token_roster::preparation::Preparation::new(&writes);
    let first = keys_in(&writes, factory, reuse, Some(&preparation)).unwrap();
    modifier_facts_reused(
        writes.iter(),
        &symbols,
        &worker,
        &[0],
        factory,
        reuse,
        &first,
    )
    .unwrap();
    let second = keys_in(&writes, factory, reuse, Some(&preparation)).unwrap();
    assert!(Arc::ptr_eq(&first[0].bytes, &second[0].bytes));
    assert!(Arc::ptr_eq(&first[0].input, &second[0].input));
    assert!(
        second[0].admitted.get().is_none(),
        "admission is always request-local"
    );
    let before = captures.load(Ordering::Relaxed);
    dependency.0.store(2, Ordering::Relaxed);
    let current = modifier_facts_reused(
        writes.iter(),
        &symbols,
        &worker,
        &[0],
        factory,
        reuse,
        &second,
    )
    .unwrap();
    assert!(matches!(current.as_slice(), [ModifierFact::Known(2)]));
    assert!(
        captures.load(Ordering::Relaxed) > before,
        "locator reuse cannot bypass actual semantic replay"
    );
    let mut changed = original;
    changed.declaration_flags = Some(8);
    let changed = keys_in(&[changed], factory, reuse, Some(&preparation)).unwrap();
    assert_eq!(
        changed[0].bytes, first[0].bytes,
        "same locator is not full input authority"
    );
    assert!(!Arc::ptr_eq(&changed[0].input, &first[0].input));
    let changed_policy = keys_in(
        &writes,
        factory,
        InitializerReuse { policy: 2, ..reuse },
        Some(&preparation),
    )
    .unwrap();
    assert_ne!(changed_policy[0].bytes, first[0].bytes);
}

#[test]
fn modifier_locator_replays_full_inputs_and_shares_classification_write_owner() {
    let mut symbols = SymbolTable::default();
    let original = write(&mut symbols);
    let dependency = Dependency(AtomicU32::new(8));
    let captures = AtomicU64::new(0);
    let worker = Worker {
        resolver: &dependency,
        captures: &captures,
    };
    let factory = ParallelEvaluator {
        factory: &worker,
        engine: None,
    };
    let store = InitializerArtifacts::default();
    let reuse = InitializerReuse {
        store: &store,
        resolver: &dependency,
        policy: 1,
        resource_search_context: None,
    };
    let roster = vec![original.clone(), original.clone()];
    let candidates = keys(&roster, factory, reuse).unwrap();
    assert_ne!(
        candidates[0].bytes, candidates[1].bytes,
        "duplicate placement has independent slot"
    );
    modifier_facts_reused(
        roster.iter(),
        &symbols,
        &worker,
        &[0, 1],
        factory,
        reuse,
        &candidates,
    )
    .unwrap();
    let compact = store.modifiers.compact_for_pressure(1024 * 1024);
    assert_eq!(compact.retained_entries, 2);
    assert!(compact.charged_bytes > 2 * std::mem::size_of::<ModifierArtifact>());
    let before = captures.load(Ordering::Relaxed);
    modifier_facts_reused(
        roster.iter(),
        &symbols,
        &worker,
        &[0, 1],
        factory,
        reuse,
        &candidates,
    )
    .unwrap();
    assert_eq!(captures.load(Ordering::Relaxed), before);
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    super::super::classification::parallel::classify_with_reuse(
        &roster,
        &symbols,
        factory,
        false,
        &executor,
        Some(reuse),
    )
    .unwrap();
    let mut modifier_owners = Vec::new();
    store.visit_modifier_storage(|view| {
        if let dm_session::ArtifactStorageView::Entry { value, .. } = view {
            modifier_owners.push(Arc::clone(&value.input));
        }
    });
    let mut shared_count = 0;
    store.visit_storage(|view| {
        if let dm_session::ArtifactStorageView::Entry { value, .. } = view {
            let input = value.input_write().expect("classified exact input");
            assert!(modifier_owners
                .iter()
                .any(|write| Arc::ptr_eq(write, input)));
            shared_count += 1;
        }
    });
    assert_eq!(shared_count, 2);
    let mut edited = original;
    edited.declaration_flags = Some(8);
    let changed = keys(&[edited.clone()], factory, reuse).unwrap();
    assert_eq!(
        changed[0].bytes, candidates[0].bytes,
        "full input is receipt, not locator"
    );
    let before = captures.load(Ordering::Relaxed);
    modifier_facts_reused(
        std::iter::once(&edited),
        &symbols,
        &worker,
        &[0],
        factory,
        reuse,
        &changed,
    )
    .unwrap();
    assert_eq!(
        captures.load(Ordering::Relaxed),
        before + 1,
        "changed exact input must recompute"
    );
}
impl CapturedInitializerEvaluator for Worker<'_> {
    fn evaluate(&self, _: SymbolId, _: &SymbolicExpression) -> Result<Evaluation, String> {
        Err("modifier admission must not evaluate initializer values".into())
    }
    fn binding_knowledge(
        &self,
        write: &InitializerWrite,
    ) -> Result<Option<BindingKnowledge>, String> {
        self.captures.fetch_add(1, Ordering::Relaxed);
        match self.resolver.resolve(ResolveQuery::Constant {
            owner: write.lexical_owner,
            name: SymbolId::of("flags"),
        }) {
            ResolvedMeaning::Value(SemanticValue::NumberBits(flags)) => {
                Ok(Some(BindingKnowledge::Modifiers(flags)))
            }
            _ => Err("modifier dependency unsupported".into()),
        }
    }
}
impl InitializerEvaluatorFactory for Worker<'_> {
    fn recording_policy_identity(&self) -> Option<u128> {
        Some(42)
    }
    fn with_recording_evaluator(
        &self,
        _: Option<&crate::engine::EngineSnapshot>,
        resolver: &dyn Resolver,
        operation: &mut dyn FnMut(&dyn CapturedInitializerEvaluator),
    ) -> bool {
        operation(&Worker {
            resolver,
            captures: self.captures,
        });
        true
    }
    fn with_evaluator(
        &self,
        _: Option<&crate::engine::EngineSnapshot>,
        operation: &mut dyn FnMut(&dyn CapturedInitializerEvaluator),
    ) {
        operation(self);
    }
}
fn write(symbols: &mut SymbolTable) -> InitializerWrite {
    let owner = symbols.intern("/").unwrap();
    let name = symbols.intern("output").unwrap();
    InitializerWrite {
        source_site: dm_ir::InitializerSite::Declaration,
        target: InitializerTarget::Shared {
            slot: SymbolId::of("output.slot"),
            owner,
            name,
        },
        lexical_owner: owner,
        lexical_procedure: None,
        value: InitializerValue::NoAuthoredValue,
        declared_array: None,
        declaration_flags: None,
    }
}
#[test]
fn modifier_receipts_revalidate_current_answers_and_preserve_global_error_ordinals() {
    let mut symbols = SymbolTable::default();
    let write = write(&mut symbols);
    let dependency = Dependency(AtomicU32::new(8));
    let captures = AtomicU64::new(0);
    let worker = Worker {
        resolver: &dependency,
        captures: &captures,
    };
    let factory = ParallelEvaluator {
        factory: &worker,
        engine: None,
    };
    let store = InitializerArtifacts::default();
    let reuse = InitializerReuse {
        store: &store,
        resolver: &dependency,
        policy: 1,
        resource_search_context: None,
    };
    let roster = vec![write.clone()];
    let first_keys = keys(&roster, factory, reuse).unwrap();
    let first = modifier_facts_reused(
        roster.iter(),
        &symbols,
        &worker,
        &[0],
        factory,
        reuse,
        &first_keys,
    )
    .unwrap();
    assert!(matches!(first.as_slice(), [ModifierFact::Known(8)]));
    assert_eq!(captures.load(Ordering::Relaxed), 1);
    let unchanged = modifier_facts_reused(
        roster.iter(),
        &symbols,
        &worker,
        &[0],
        factory,
        reuse,
        &first_keys,
    )
    .unwrap();
    assert!(matches!(unchanged.as_slice(), [ModifierFact::Known(8)]));
    assert_eq!(captures.load(Ordering::Relaxed), 1);
    dependency.0.store(2, Ordering::Relaxed);
    let changed = modifier_facts_reused(
        roster.iter(),
        &symbols,
        &worker,
        &[0],
        factory,
        reuse,
        &first_keys,
    )
    .unwrap();
    assert!(matches!(changed.as_slice(), [ModifierFact::Known(2)]));
    assert_eq!(captures.load(Ordering::Relaxed), 2);
    dependency.0.store(16, Ordering::Relaxed);
    let large_roster = vec![write.clone(); 4];
    let keys = keys(&large_roster, factory, reuse).unwrap();
    let errors = match modifier_facts_reused(
        std::iter::once(&write),
        &symbols,
        &worker,
        &[3],
        factory,
        reuse,
        &keys,
    ) {
        Ok(_) => panic!("unknown modifiers must reject"),
        Err(errors) => errors,
    };
    assert_eq!(errors.issues.len(), 1);
    assert_eq!(errors.issues[0].source_ordinal, 3);
    assert_eq!(errors.issues[0].reason, "unknown initializer modifiers");
}
