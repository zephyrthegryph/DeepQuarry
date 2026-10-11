//! Pinned modified_source_features controls through current startup/evaluator.
use super::*;
use crate::initializer_policy::Evaluator;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
#[test]
fn modified_nameof_rejection_preserves_source_class_and_skipped_control() {
    let engine = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    let seed = engine.snapshot.frontend_seed();
    for (text, rejected) in [
        (
            include_str!("../../../fixtures/native/modified_source_features/modified_cpu.dm"),
            true,
        ),
        (
            include_str!("../../../fixtures/native/modified_source_features/modified_graphics.dm"),
            true,
        ),
        (
            include_str!(
                "../../../fixtures/native/modified_source_features/modified_skipped_cpu.dm"
            ),
            false,
        ),
    ] {
        let front = dm_tree::frontend::build_with_config(
            std::path::Path::new("modified-nameof.dme"),
            &Source(text),
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap();
        let (host, _) =
            crate::request_runner::runner_facts::prepare(&front, &engine.snapshot).unwrap();
        let startup = crate::startup::capture(&front).unwrap();
        let evaluator = DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: &host,
            symbols: front.snapshot.tree.symbols(),
        };
        let write = startup
            .plan()
            .writes
            .iter()
            .find(|write| {
                matches!(write.target,
            dm_ir::InitializerTarget::Shared { name, .. } if name == SymbolId::of("value"))
            })
            .unwrap();
        let dm_ir::InitializerValue::Expression(expression) = &write.value else {
            panic!("authored expression")
        };
        let (value, _) = evaluator
            .evaluate_prepared_write(write, expression)
            .unwrap();
        if rejected {
            assert!(matches!(value, Evaluation::SourceError(ref reason)
                if reason == "nameof: requires a var, proc reference, or type path"));
        } else {
            assert!(matches!(
                value,
                Evaluation::Scalar(SemanticValue::ModifiedInstance(_))
            ));
        }
    }
}
