//! One shared emitter; one-shot composition does not capture a retained frame.
use super::*;
#[test]
fn one_shot_frame_emission_skips_retention_and_matches_retained_output() {
    use std::sync::Arc;
    let (mut batch, _) = ownership_fixture_source("/proc/cold_frame_probe()\n    return 1\n");
    batch.units[0].lowered.frame.local_count = 1;
    batch.units[0].lowered.frame.local_names = vec!["current_local".into()];
    let baseline =
        Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let emit = |retain| {
        let mut model = baseline.clone();
        let mut index = StringIndex::build(&model).unwrap();
        frame_contribution::emit(
            &mut model,
            &mut index,
            &batch.units[0],
            Arc::new(vec![1]),
            procedure_plan::ProcedureMetadata {
                path: Ok(Arc::from("/proc/cold_frame_probe")),
                default_display: Ok(Arc::from("cold frame probe")),
                value_sources: Vec::new(),
            },
            retain,
        )
        .unwrap();
        model
    };
    let cold = emit(false);
    assert!(batch.units[0]
        .metadata_recipe
        .frame_owner()
        .lock()
        .unwrap()
        .is_none());
    let retained = emit(true);
    assert!(cold == retained);
    let owner = batch.units[0]
        .metadata_recipe
        .frame_owner()
        .lock()
        .unwrap()
        .clone()
        .unwrap();
    let cold_again = emit(false);
    assert!(cold_again == retained);
    assert!(Arc::ptr_eq(
        &owner,
        batch.units[0]
            .metadata_recipe
            .frame_owner()
            .lock()
            .unwrap()
            .as_ref()
            .unwrap()
    ));
}
