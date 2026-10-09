use super::*;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
struct Evaluator;
impl crate::initializer_policy::CapturedInitializerEvaluator for Evaluator {
    fn evaluate(
        &self,
        _: SymbolId,
        value: &SymbolicExpression,
    ) -> Result<crate::initializer_policy::Evaluation, String> {
        let number: f32 = if value
            .tokens
            .first()
            .is_some_and(|token| token.text == SymbolId::of("4"))
        {
            4.0
        } else {
            3.0
        };
        Ok(crate::initializer_policy::Evaluation::Scalar(
            SemanticValue::NumberBits(number.to_bits()),
        ))
    }
}
fn project_source(
    store: &ClassProjections,
    source: &'static str,
    reverse: bool,
) -> ClassProjection {
    let frontend = dm_tree::frontend::build(
        std::path::Path::new("project.dme"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap();
    let mut order: Vec<_> = (0..frontend.snapshot.occurrences.source_order().len())
        .map(|index| OccurrenceId(index as u32))
        .collect();
    let plan = dm_tree::initializers::plan(&frontend.snapshot, &order).unwrap();
    let facts =
        crate::initializer_policy::classify(&plan.writes, &plan.symbols, &Evaluator).unwrap();
    if reverse {
        order.reverse();
    }
    let fresh = project_classified(&frontend.snapshot, &order, &plan, &facts, &[]).unwrap();
    let retained = project_classified_with_artifacts(
        &frontend.snapshot,
        &order,
        &plan,
        &facts,
        &[],
        Some(store),
    )
    .unwrap();
    assert_eq!(retained.fields, fresh.fields);
    assert_eq!(
        retained.procedure_declarations,
        fresh.procedure_declarations
    );
    assert_eq!(retained.shared_slot_order, fresh.shared_slot_order);
    assert_eq!(retained.runtime_writes, fresh.runtime_writes);
    assert_eq!(
        retained
            .chains
            .iter()
            .map(|chain| (chain.owner, chain.name, chain.verb, chain.entries.to_vec()))
            .collect::<Vec<_>>(),
        fresh
            .chains
            .iter()
            .map(|chain| (chain.owner, chain.name, chain.verb, chain.entries.to_vec()))
            .collect::<Vec<_>>()
    );
    retained
}
#[test]
fn interleaved_owner_payloads_rebind_shifted_sources_and_match_fresh_reorder() {
    let store = ClassProjections::default();
    let source="/datum/a\n    var/x = 3\n/datum/b\n    var/y = 3\n/datum/a/proc/p()\n    return 1\n/datum/b/proc/q()\n    return 2\n";
    project_source(&store, source, false);
    let before = store.hits.load(Ordering::Relaxed);
    project_source(&store,"\n\n/datum/a\n    var/x = 3\n/datum/b\n    var/y = 3\n/datum/a/proc/p()\n    return 4\n/datum/b/proc/q()\n    return 2\n",false);
    assert!(
        store.hits.load(Ordering::Relaxed) > before,
        "unchanged owner semantic payload must reuse"
    );
    let reversed = project_source(&store, source, true);
    assert_eq!(reversed.fields[0].name, SymbolId::of("y"));
    let changed=project_source(&store,"/datum/a\n    var/x = 4\n/datum/b\n    var/y = 3\n/datum/a/proc/p()\n    return 1\n/datum/b/proc/q()\n    return 2\n",false);
    assert_eq!(
        changed.fields[0].value,
        DefaultValue::Scalar(SemanticValue::NumberBits(4f32.to_bits()))
    );
}
