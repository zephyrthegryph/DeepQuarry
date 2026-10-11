use super::*;
use std::sync::Arc;
fn assignment_plan(batch: &FrozenBatch) -> procedure_plan::CompositionPlan {
    procedure_plan::CompositionPlan {
        procedures: batch
            .units
            .iter()
            .map(|unit| {
                (
                    batch
                        .tables
                        .index(crate::symbolic::unit_key(unit.lowered.identity))
                        .unwrap(),
                    unit.lowered.identity,
                )
            })
            .collect(),
        ..Default::default()
    }
}
#[test]
fn issued_assignment_roster_requires_exact_owner_floor_and_current_artifact_order() {
    let source = "/proc/first()\n    return 1\n/proc/second()\n    return 2\n";
    let (mut batch, _) = ownership_fixture_source(source);
    let owner = RetainedGeneration::default();
    // Generic callers cannot certify that raw rows came from assignment traversal.
    owner.bind_plan(assignment_plan(&batch), &batch);
    assert!(owner.admit_assignment_plan(&batch, 0).is_none());
    let first = owner
        .bind_assignment_plan(assignment_plan(&batch), &batch, 0)
        .procedures
        .unwrap();
    let same = owner
        .admit_assignment_plan(&batch, 0)
        .unwrap()
        .procedures
        .unwrap();
    assert!(Arc::ptr_eq(&first, &same));
    // Changed bodies/metadata may retain these numeric slot mappings. Downstream
    // metadata/frame admission remains mandatory, independent of this witness.
    batch.units[0].lowered.frame = Arc::new(batch.units[0].lowered.frame.as_ref().clone());
    let same = owner
        .admit_assignment_plan(&batch, 0)
        .unwrap()
        .procedures
        .unwrap();
    assert!(Arc::ptr_eq(&first, &same));
    assert!(owner.admit_assignment_plan(&batch, 1).is_none());
    batch.units.swap(0, 1);
    assert!(owner.admit_assignment_plan(&batch, 0).is_none());
    batch.units.swap(0, 1);
    let removed = batch.units.pop().unwrap();
    assert!(owner.admit_assignment_plan(&batch, 0).is_none());
    batch.units.push(removed);
    let (fresh, _) = ownership_fixture_source(source);
    assert!(owner.admit_assignment_plan(&fresh, 0).is_none());
    owner.clear();
    assert!(owner.admit_assignment_plan(&batch, 0).is_none());
}
