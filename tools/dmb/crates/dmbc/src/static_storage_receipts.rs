//! Regression for the frozen Master.random_seed shared/instance divergence.
#[test]
fn inherited_class_static_access_emits_shared_slot_operands() {
    use dm_codegen_byond::ProcedureInputs;
    use dm_ir::SymbolId;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok(
                "/datum/base\n    var/static/random_seed\n/datum/base/child\n    random_seed = 7\n"
                    .into(),
            )
        }
    }
    let frontend = dm_tree::frontend::build(
        std::path::Path::new("project.dme"),
        &Source,
        &Default::default(),
        1,
    )
    .unwrap();
    let parsed = dm_syntax::parse("/proc/probe()\n    random_seed = 1\n    return random_seed\n");
    for owner in ["/datum/base", "/datum/base/child"] {
        let lowered = dm_codegen_byond::compile_simple_proc_with_resolver(
            &parsed.items[0].children,
            &ProcedureInputs {
                current_type_path: Some(owner.into()),
                ..Default::default()
            },
            frontend.snapshot.tree.symbols(),
            frontend.snapshot.tree.as_ref(),
        )
        .unwrap();
        assert_eq!(lowered.slots.len(), 1);
        let (symbol, slot) = lowered.slots.iter().next().unwrap();
        assert_eq!(slot.owner, SymbolId::of("/datum/base"));
        assert_eq!(slot.name, SymbolId::of("random_seed"));
        assert_eq!(*symbol, dm_ir::SymRef::VariableSlot(slot.symbol));
        // Explicit fixture index tests the actual serialized VM storage kind.
        let mut bindings = dm_codegen_byond::Ledger::default();
        bindings.bind(*symbol, 77).unwrap();
        let code = dm_codegen_byond::link_proc(&lowered.procedure.code, &bindings).unwrap();
        assert!(code
            .words
            .windows(3)
            .any(|words| words == [0x34, 65499, 77]));
        assert!(code
            .words
            .windows(3)
            .any(|words| words == [0x33, 65499, 77]));
        assert!(!code
            .words
            .windows(3)
            .any(|words| words == [0x33, 65500, 65486]));
        assert!(!code
            .words
            .windows(3)
            .any(|words| words == [0x34, 65500, 65486]));
    }
}
