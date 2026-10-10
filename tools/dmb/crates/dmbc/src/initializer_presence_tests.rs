use super::*;
use dm_ir::{InitializerScope, SemanticValue, SymbolId};
use std::path::Path;

struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(include_str!("../../../fixtures/native_compiler/unsized_array/contexts.dm").into())
    }
}

#[test]
fn unsized_instance_presence_matches_captured_init_without_allocating() {
    let frontend = dm_tree::frontend::build_with_config(
        Path::new("probe.dme"),
        &Source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
    )
    .unwrap();
    let declarations = dm_tree::initializers::capture_declaration_plan(
        &frontend.snapshot,
        &frontend.emission_order,
    )
    .unwrap();
    let plan = declarations.plan();
    let host = frontend.snapshot.tree.as_ref();
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: host,
        symbols: plan.symbols.as_ref(),
    };
    let lowered = lower(&frontend, plan, &evaluator, host, None).unwrap();
    let captured = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/unsized_array/contexts.native.bin"
    ))
    .unwrap();
    for path in [
        "/datum/empty_only",
        "/datum/empty_only/child",
        "/datum/shared_only",
        "/datum/explicit_only",
    ] {
        let expected = captured
            .classes
            .iter()
            .find(|class| captured.string(class.path_string_id()) == Some(path.as_bytes()))
            .unwrap();
        let actual = lowered
            .units
            .iter()
            .find(|unit| unit.scope == InitializerScope::Instance(SymbolId::of(path)));
        assert_eq!(
            actual.is_some(),
            expected.lists_and_procs[2] != 0xffff,
            "{path}"
        );
        if path == "/datum/empty_only" {
            let actual = actual.unwrap();
            assert!(actual.write_ordinals.is_empty());
            assert!(actual.debug_origins.entries.is_empty());
            assert!(actual.code.slots.is_empty());
            assert_eq!(
                captured
                    .proc_code_words(expected.lists_and_procs[2] as usize)
                    .unwrap(),
                &[0]
            );
            assert_eq!(actual.code.procedure.code.items.len(), 1);
            let dm_codegen_byond::Item::Instruction(instruction) =
                &actual.code.procedure.code.items[0]
            else {
                panic!("expected End")
            };
            assert_eq!(instruction.opcode, byond_dmb::bytecode::opcode::END);
        }
    }
    let empty = lowered
        .classified
        .writes
        .iter()
        .find(|write| write.write.lexical_owner == SymbolId::of("/datum/empty_only"))
        .unwrap();
    assert_eq!(
        empty.default,
        initializer_policy::DefaultValue::Scalar(SemanticValue::Null)
    );
    assert!(empty.phase.is_none());
    assert!(empty.runtime_value.is_none());
}
