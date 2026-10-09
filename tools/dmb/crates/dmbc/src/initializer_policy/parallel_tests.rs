use super::*;
struct Factory;
impl InitializerEvaluatorFactory for Factory {
    fn with_evaluator(
        &self,
        _: Option<&crate::engine::EngineSnapshot>,
        operation: &mut dyn FnMut(&dyn CapturedInitializerEvaluator),
    ) {
        operation(&Evaluator);
    }
}
#[test]
fn per_type_parallel_classification_preserves_interleaved_tokens_and_groups() {
    let mut symbols = SymbolTable::default();
    let first = symbols.intern("/datum/first").unwrap();
    let second = symbols.intern("/datum/second").unwrap();
    let name = symbols.intern("value").unwrap();
    let writes = [
        (first, "list(2)"),
        (second, "list(2)"),
        (first, "run()"),
        (second, "list(2)"),
        (first, "list(2,2)"),
    ]
    .into_iter()
    .map(|(owner, text)| {
        write(
            owner,
            name,
            InitializerValue::Expression(expression(text, &mut symbols).unwrap()),
        )
    })
    .collect::<Vec<_>>();
    for debug in [false, true] {
        let serial = classify_with_token_mode(&writes, &symbols, &Evaluator, debug).unwrap();
        for workers in [1, 2, 8] {
            let executor = dm_exec::BuildExecutor::new(workers).unwrap();
            let parallel = classify_with_token_mode_on_executor(
                &writes,
                &symbols,
                ParallelEvaluator {
                    factory: &Factory,
                    engine: None,
                },
                debug,
                &executor,
            )
            .unwrap();
            assert_eq!(parallel.writes.len(), serial.writes.len());
            for (actual, expected) in parallel.writes.iter().zip(&serial.writes) {
                assert_eq!(actual.source_ordinal, expected.source_ordinal);
                assert_eq!(actual.write, expected.write);
                assert_eq!(actual.default, expected.default);
                assert_eq!(actual.phase, expected.phase);
                assert_eq!(actual.runtime_value, expected.runtime_value);
            }
            assert_eq!(
                parallel
                    .groups
                    .iter()
                    .map(|group| (group.receiver, &group.writes))
                    .collect::<Vec<_>>(),
                serial
                    .groups
                    .iter()
                    .map(|group| (group.receiver, &group.writes))
                    .collect::<Vec<_>>()
            );
        }
    }
}
struct FailFactory(std::sync::atomic::AtomicUsize);
impl CapturedInitializerEvaluator for FailFactory {
    fn evaluate(&self, _: SymbolId, _: &SymbolicExpression) -> Result<Evaluation, String> {
        self.0.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        Err("deliberate value failure".into())
    }
}
impl InitializerEvaluatorFactory for FailFactory {
    fn with_evaluator(
        &self,
        _: Option<&crate::engine::EngineSnapshot>,
        operation: &mut dyn FnMut(&dyn CapturedInitializerEvaluator),
    ) {
        operation(self);
    }
}
#[test]
fn parallel_modifier_gate_retains_all_global_ordinals_and_does_not_evaluate() {
    let mut symbols = SymbolTable::default();
    let first = symbols.intern("/datum/first").unwrap();
    let second = symbols.intern("/datum/second").unwrap();
    let name = symbols.intern("value").unwrap();
    let value = InitializerValue::Expression(expression("run()", &mut symbols).unwrap());
    let mut writes = vec![
        write(first, name, value.clone()),
        write(second, name, value.clone()),
        write(first, name, value),
    ];
    writes[1].declaration_flags = None;
    writes[2].declaration_flags = None;
    let factory = FailFactory(std::sync::atomic::AtomicUsize::new(0));
    let executor = dm_exec::BuildExecutor::new(2).unwrap();
    let errors = classify_with_token_mode_on_executor(
        &writes,
        &symbols,
        ParallelEvaluator {
            factory: &factory,
            engine: None,
        },
        false,
        &executor,
    )
    .unwrap_err();
    assert_eq!(
        errors
            .issues
            .iter()
            .map(|issue| issue.source_ordinal)
            .collect::<Vec<_>>(),
        [1, 2]
    );
    assert!(errors.issues[0].reason.contains("write 1"));
    assert!(errors.issues[1].reason.contains("write 2"));
    assert_eq!(factory.0.load(std::sync::atomic::Ordering::Relaxed), 0);
}
#[test]
fn parallel_value_failure_is_source_ordered_and_all_buckets_join() {
    let mut symbols = SymbolTable::default();
    let first = symbols.intern("/datum/first").unwrap();
    let second = symbols.intern("/datum/second").unwrap();
    let name = symbols.intern("value").unwrap();
    let value = InitializerValue::Expression(expression("run()", &mut symbols).unwrap());
    let writes = [
        write(first, name, value.clone()),
        write(second, name, value),
    ];
    let factory = FailFactory(std::sync::atomic::AtomicUsize::new(0));
    let executor = dm_exec::BuildExecutor::new(2).unwrap();
    let errors = classify_with_token_mode_on_executor(
        &writes,
        &symbols,
        ParallelEvaluator {
            factory: &factory,
            engine: None,
        },
        false,
        &executor,
    )
    .unwrap_err();
    assert_eq!(errors.issues.len(), 1);
    assert_eq!(errors.issues[0].source_ordinal, 0);
    assert_eq!(factory.0.load(std::sync::atomic::Ordering::Relaxed), 2);
}

struct BorrowedFactory {
    source_addresses: std::collections::HashSet<usize>,
    modifier_reads: std::sync::atomic::AtomicUsize,
}
impl CapturedInitializerEvaluator for BorrowedFactory {
    fn evaluate(&self, owner: SymbolId, value: &SymbolicExpression) -> Result<Evaluation, String> {
        Evaluator.evaluate(owner, value)
    }
    fn binding_knowledge(
        &self,
        write: &InitializerWrite,
    ) -> Result<Option<BindingKnowledge>, String> {
        assert!(
            self.source_addresses
                .contains(&(std::ptr::from_ref(write) as usize)),
            "modifier workers must borrow the authored roster rather than copied bucket writes"
        );
        self.modifier_reads
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        Ok(write.declaration_flags.map(BindingKnowledge::Modifiers))
    }
}
impl InitializerEvaluatorFactory for BorrowedFactory {
    fn with_evaluator(
        &self,
        _: Option<&crate::engine::EngineSnapshot>,
        operation: &mut dyn FnMut(&dyn CapturedInitializerEvaluator),
    ) {
        operation(self);
    }
}
#[test]
fn parallel_buckets_borrow_authored_writes_and_keep_serial_output() {
    let mut symbols = SymbolTable::default();
    let first = symbols.intern("/datum/first").unwrap();
    let second = symbols.intern("/datum/second").unwrap();
    let name = symbols.intern("value").unwrap();
    let writes = [(first, "list(2)"), (second, "run()"), (first, "list(2,2)")]
        .into_iter()
        .map(|(owner, source)| {
            write(
                owner,
                name,
                InitializerValue::Expression(expression(source, &mut symbols).unwrap()),
            )
        })
        .collect::<Vec<_>>();
    let factory = BorrowedFactory {
        source_addresses: writes
            .iter()
            .map(|write| std::ptr::from_ref(write) as usize)
            .collect(),
        modifier_reads: std::sync::atomic::AtomicUsize::new(0),
    };
    let serial = classify_with_token_mode(&writes, &symbols, &Evaluator, false).unwrap();
    let executor = dm_exec::BuildExecutor::new(2).unwrap();
    let parallel = classify_with_token_mode_on_executor(
        &writes,
        &symbols,
        ParallelEvaluator {
            factory: &factory,
            engine: None,
        },
        false,
        &executor,
    )
    .unwrap();
    assert_eq!(
        factory
            .modifier_reads
            .load(std::sync::atomic::Ordering::Relaxed),
        writes.len()
    );
    assert_eq!(format!("{:?}", serial), format!("{:?}", parallel));
}
