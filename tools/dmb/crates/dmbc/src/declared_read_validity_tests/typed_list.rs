//! Typed list declarations license the list object, separately from its element type.
use super::*;
use dm_ir::SymbolId;

#[test]
fn real_typed_list_global_read_licenses_projected_runtime_list_type() {
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap();
    for prefix in ["", "// shifted current source\n\n"] {
        let source = format!("{prefix}/datum/probe\nvar/list/datum/probe/value = list()\n/proc/read()\n    return value\n");
        let front = frontend(&source, &engine);
        let (host, _) = crate::request_runner::runner_facts::prepare(&front, &engine).unwrap();
        let root = SymbolId::of("/");
        let value = SymbolId::of("value");
        let list = SymbolId::of("/list");
        let declared = Q::DeclaredVarType {
            owner: root,
            name: value,
        };
        assert_eq!(host.resolve(declared), M::DeclaredType(Some(list)));
        let M::Member { data, .. } = host.resolve(Q::GlobalVar(value)) else {
            panic!("authored global variable metadata missing");
        };
        assert_eq!(data.declared_type, Some(list));
        assert_eq!(data.list_element_type, Some(SymbolId::of("/datum/probe")));
        assert_eq!(
            host.resolve(Q::RuntimeType(list)),
            M::Unsupported(Q::RuntimeType(list))
        );
        let recorder = crate::lowering_memo::RecordingResolver::new(&host);
        let parsed = dm_syntax::parse(&source);
        assert!(parsed.diagnostics.is_empty());
        let procedure = parsed
            .items
            .iter()
            .find(|item| item.kind == dm_syntax::ItemKind::Proc)
            .unwrap();
        let code = dm_codegen_byond::compile_simple_proc_with_resolver(
            &procedure.children,
            &Default::default(),
            front.snapshot.tree.symbols(),
            &recorder,
        );
        assert!(code.is_ok(), "typed list read failed: {:?}", code.err());
        let reads = recorder.reads();
        assert!(reads
            .iter()
            .any(|read| read.query == declared && read.answer == M::DeclaredType(Some(list))));
        assert!(reads.iter().any(|read| read.query == Q::RuntimeType(list)
            && read.answer == M::Unsupported(Q::RuntimeType(list))));
    }
}
