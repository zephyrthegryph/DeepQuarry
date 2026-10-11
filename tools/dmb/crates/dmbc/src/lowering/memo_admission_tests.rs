use super::*;
use std::sync::atomic::{AtomicUsize, Ordering};

struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok("/proc/p()\n    return 1\n".into())
    }
}
struct Policy(AtomicUsize);
impl AbiPolicy for Policy {
    fn inputs(
        &self,
        _: UnitIdentity,
        _: &ProcedureMetadata,
        _: &SymbolTable,
        _: &SourceLocation,
    ) -> Result<ProcedureInputs, String> {
        self.0.fetch_add(1, Ordering::Relaxed);
        Ok(ProcedureInputs::default())
    }
}

#[test]
fn admission_defers_cold_producer_and_consumes_it_once_with_fresh_output() {
    let frontend = dm_tree::frontend::build(
        std::path::Path::new("admission.dme"),
        &Source,
        &Default::default(),
        1,
    )
    .unwrap();
    let arena = dm_tree::frontend::BodyArena::new(&frontend);
    let policy = Policy(AtomicUsize::new(0));
    let pending = super::super::admit_one_input(
        &frontend,
        &frontend.bodies[0],
        frontend.snapshot.tree.as_ref(),
        None,
        None,
        &policy,
        None,
        None,
        &arena,
        false,
        false,
        false,
        None,
        None,
    )
    .unwrap();
    assert!(matches!(&pending, Admission::NeedsLowering(_)));
    assert_eq!(policy.0.load(Ordering::Relaxed), 0);
    let produced = pending.finish().unwrap().into_lowered();
    assert_eq!(policy.0.load(Ordering::Relaxed), 1);
    // A fresh lowering owns a fresh one-shot parse arena. The pending attempt
    // above has already consumed its executable body exactly once.
    let fresh_arena = dm_tree::frontend::BodyArena::new(&frontend);
    let fresh = lower_one_input(
        &frontend,
        &frontend.bodies[0],
        frontend.snapshot.tree.as_ref(),
        None,
        &policy,
        None,
        None,
        &fresh_arena,
        false,
        false,
        false,
        None,
        None,
    )
    .unwrap()
    .into_lowered();
    assert_eq!(policy.0.load(Ordering::Relaxed), 2);
    assert_eq!(
        serde_json::to_vec(&produced.code.procedure).unwrap(),
        serde_json::to_vec(&fresh.code.procedure).unwrap()
    );
}

#[test]
fn admission_worker_slots_preserve_source_order_and_isolate_panics() {
    let executor = dm_exec::BuildExecutor::new(2).unwrap();
    let calls = AtomicUsize::new(0);
    let outcomes = map_stage(&executor, &[0, 1, 2, 3, 4], 2, &|value| {
        calls.fetch_add(1, Ordering::Relaxed);
        if *value == 2 {
            panic!("one failed admission");
        }
        value * 10
    });
    assert_eq!(outcomes, vec![Some(0), Some(10), None, Some(30), Some(40)]);
    assert_eq!(calls.load(Ordering::Relaxed), 5);
}
