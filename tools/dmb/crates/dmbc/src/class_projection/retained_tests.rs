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
fn changed_default_refreshes_owner_and_next_unchanged_projection_hits() {
    let store = ClassProjections::default();
    let original = project_source(&store, "/datum/a\n    var/x = 3\n", false);
    let old_recomputed = store.recomputed.load(Ordering::Relaxed);
    let changed = project_source(&store, "/datum/a\n    var/x = 4\n", false);
    assert_ne!(original.fields[0].value, changed.fields[0].value);
    assert_eq!(
        changed.fields[0].value,
        DefaultValue::Scalar(SemanticValue::NumberBits(4f32.to_bits()))
    );
    assert!(store.recomputed.load(Ordering::Relaxed) > old_recomputed);
    let recomputed = store.recomputed.load(Ordering::Relaxed);
    let hits = store.hits.load(Ordering::Relaxed);
    let unchanged = project_source(&store, "/datum/a\n    var/x = 4\n", false);
    assert_eq!(unchanged.fields, changed.fields);
    assert_eq!(
        store.recomputed.load(Ordering::Relaxed),
        recomputed,
        "fresh owner must replace the rejected local-input candidate"
    );
    assert!(
        store.hits.load(Ordering::Relaxed) > hits,
        "next unchanged request must reuse the newly produced owner"
    );
    // project_source independently compares every retained projection with its
    // ordinary fresh producer, including changed and subsequently reused rows.
}

#[test]
fn interleaved_owner_payloads_rebind_shifted_sources_and_match_fresh_reorder() {
    let store = ClassProjections::default();
    let source = "/datum/a\n    var/x = 3\n/datum/b\n    var/y = 3\n/datum/a/proc/p()\n    return 1\n/datum/b/proc/q()\n    return 2\n";
    project_source(&store, source, false);
    let before = store.hits.load(Ordering::Relaxed);
    project_source(
        &store,
        "\n\n/datum/a\n    var/x = 3\n/datum/b\n    var/y = 3\n/datum/a/proc/p()\n    return 4\n/datum/b/proc/q()\n    return 2\n",
        false,
    );
    assert!(
        store.hits.load(Ordering::Relaxed) > before,
        "unchanged owner semantic payload must reuse"
    );
    let reversed = project_source(&store, source, true);
    assert_eq!(reversed.fields[0].name, SymbolId::of("y"));
    let changed = project_source(
        &store,
        "/datum/a\n    var/x = 4\n/datum/b\n    var/y = 3\n/datum/a/proc/p()\n    return 1\n/datum/b/proc/q()\n    return 2\n",
        false,
    );
    assert_eq!(
        changed.fields[0].value,
        DefaultValue::Scalar(SemanticValue::NumberBits(4f32.to_bits()))
    );
}

#[test]
fn current_ordered_projection_shares_admitted_field_rows_and_invalidates_values() {
    let store = ClassProjections::default();
    let source = "/datum/a\n    var/x = 3\n/datum/b\n    var/y = 3\n";
    let first = project_source(&store, source, false);
    let second = project_source(&store, source, false);
    assert_eq!(first.fields.len(), 2);
    for (a, b) in first.fields.iter().zip(second.fields.iter()) {
        assert!(Arc::ptr_eq(a, b));
    }
    let changed = project_source(
        &store,
        "/datum/a\n    var/x = 4\n/datum/b\n    var/y = 3\n",
        false,
    );
    assert!(!Arc::ptr_eq(&first.fields[0], &changed.fields[0]));
    assert!(Arc::ptr_eq(&first.fields[1], &changed.fields[1]));
    let moved = project_source(
        &store,
        "/datum/b\n    var/y = 3\n/datum/a\n    var/x = 4\n",
        false,
    );
    assert_eq!(moved.fields[0].name, SymbolId::of("y"));
    assert!(Arc::ptr_eq(&changed.fields[1], &moved.fields[0]));
}

#[test]
fn compact_owner_locator_keeps_exact_metadata_and_order_authority() {
    let store = ClassProjections::default();
    let first = project_source(&store, "/datum/a\n    var/x = 3\n    var/y = 3\n", false);
    let mut maximum_key = 0;
    let mut captured = 0;
    store.visit_storage(|view| {
        if let dm_session::ArtifactStorageView::Entry { key, value, .. } = view {
            maximum_key = maximum_key.max(key.len());
            captured += value.inputs.len();
            assert_eq!(value.inputs.len(), value.values.len());
        }
    });
    assert!(captured >= 2, "real owner payload was admitted");
    assert!(
        maximum_key < 80,
        "locator excludes metadata/default serialization"
    );
    let changed = project_source(&store, "/datum/a\n    var/x = 4\n    var/y = 3\n", false);
    assert!(!Arc::ptr_eq(&first.fields[0], &changed.fields[0]));
    let reordered = project_source(&store, "/datum/a\n    var/y = 3\n    var/x = 4\n", false);
    assert_eq!(reordered.fields[0].name, SymbolId::of("y"));
    assert!(
        !Arc::ptr_eq(&changed.fields[0], &reordered.fields[1]),
        "ordered input mismatch must recompute the owner"
    );
}

#[test]
fn admitted_method_roster_shares_body_shift_and_replaces_changed_membership() {
    let store = ClassProjections::default();
    let first = project_source(
        &store,
        "/datum/a/proc/p()\n    return 1\n/datum/b/proc/q()\n    return 2\n",
        false,
    );
    let shifted = project_source(
        &store,
        "// current source\n/datum/a/proc/p()\n    return 9\n/datum/b/proc/q()\n    return 8\n",
        false,
    );
    assert!(Arc::ptr_eq(
        &first.type_construction,
        &shifted.type_construction
    ));
    assert!(Arc::ptr_eq(&first.chains, &shifted.chains));
    assert!(Arc::ptr_eq(
        &first.procedure_membership,
        &shifted.procedure_membership
    ));
    assert!(Arc::ptr_eq(
        &first.procedure_declarations,
        &shifted.procedure_declarations
    ));
    let changed = project_source(
        &store,
        "/datum/a/proc/p()\n    return 1\n/datum/b/proc/added()\n    return 2\n",
        false,
    );
    assert!(!Arc::ptr_eq(&first.chains, &changed.chains));
    assert_ne!(first.procedure_membership, changed.procedure_membership);
    let weak = Arc::downgrade(&store.method_candidate().unwrap());
    // An incomplete candidate does not consume successful bookkeeping.
    drop(store.begin_methods());
    assert!(weak.upgrade().is_some());
    let rebuilt = project_source(
        &store,
        "/datum/a/proc/p()\n    return 1\n/datum/b/proc/added()\n    return 2\n",
        false,
    );
    assert_eq!(rebuilt.chains, changed.chains);
    assert!(Arc::ptr_eq(&rebuilt.chains, &changed.chains));
}

#[test]
fn streaming_method_admission_allocates_replacement_only_on_actual_difference() {
    use crate::class_projection::method_roster::{MethodInput, MethodRoster};
    let store = ClassProjections::default();
    let owner = SymbolId::of("/datum/a");
    let input = |name: &str, occurrence| {
        let name = SymbolId::of(name);
        MethodInput {
            owner,
            name,
            verb: false,
            key: Key::Proc {
                owner,
                name,
                occurrence,
            },
            declared: occurrence == 0,
        }
    };
    let original = [input("p", 0), input("q", 0), input("p", 1)];
    let mut request = store.begin_methods();
    for value in original {
        request.push(value);
    }
    let first = request.finish();
    let mut current = store.begin_methods();
    for value in original {
        current.push(value);
        assert!(
            current.replacement.is_none(),
            "exact admitted roster must not recreate ordered inputs"
        );
    }
    let second = current.finish();
    assert!(Arc::ptr_eq(&first, &second));
    let changed = [original[0], original[1], input("added", 0)];
    let mut current = store.begin_methods();
    current.push(changed[0]);
    current.push(changed[1]);
    assert!(current.replacement.is_none());
    current.push(changed[2]);
    assert_eq!(current.replacement.as_deref(), Some(changed.as_slice()));
    let replaced = current.finish();
    let fresh = MethodRoster::produce(changed.to_vec());
    assert_eq!(replaced.chains, fresh.chains);
    assert_eq!(replaced.membership, fresh.membership);
    assert!(!Arc::ptr_eq(&first, &replaced));
    let mut current = store.begin_methods();
    current.push(changed[0]);
    let shortened = current.finish();
    let fresh = MethodRoster::produce(vec![changed[0]]);
    assert_eq!(shortened.chains, fresh.chains);
    assert_eq!(shortened.membership, fresh.membership);
    let mut current = store.begin_methods();
    for value in original {
        current.push(value);
    }
    assert_eq!(current.finish().membership, first.membership);
}

#[path = "publication_tests.rs"]
mod publication_tests;
