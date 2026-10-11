//! Real pinned engine storage and optional type knowledge are separate facts.
use dm_ir::{DeclaredTypeKnowledge, ResolveQuery as Q, ResolvedMeaning as M, Resolver};
use dm_tree::frontend::{ColdFrontend, FrontendConfig};
use std::path::Path;
struct Source<'a>(&'a str);
impl dm_preprocess::SourceProvider for Source<'_> {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn frontend(source: &str, engine: &crate::engine::EngineSnapshot) -> ColdFrontend {
    let seed = engine.frontend_seed();
    dm_tree::frontend::build_with_config(
        Path::new("native_read.dme"),
        &Source(source),
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap()
}
#[test]
fn pinned_native_proven_storage_reads_survive_opaque_declared_type_knowledge() {
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap();
    let initial = frontend("/proc/control()\n    return 1\n", &engine);
    let (host, _) = crate::request_runner::runner_facts::prepare(&initial, &engine).unwrap();
    let field = engine
        .field_bases()
        .into_iter()
        .find(|field| {
            field.owner != dm_ir::SymbolId::of("/")
                && field.declared_type == DeclaredTypeKnowledge::Unsupported
                && matches!(
                    host.resolve(Q::VarStorage {
                        owner: field.owner,
                        name: field.name
                    }),
                    M::InstanceField { .. }
                )
                && host.resolve(Q::DeclaredVarType {
                    owner: field.owner,
                    name: field.name,
                }) == M::Unsupported(Q::DeclaredVarType {
                    owner: field.owner,
                    name: field.name,
                })
        })
        .expect("pinned engine has a proven instance field with opaque type metadata");
    let owner = engine.symbols().text(field.owner).unwrap();
    let name = engine.symbols().text(field.name).unwrap();
    for prefix in ["", "// current shifted occurrence\n\n"] {
        let source = format!("{prefix}{owner}/proc/read()\n    return {name}\n");
        let front = frontend(&source, &engine);
        let (host, _) = crate::request_runner::runner_facts::prepare(&front, &engine).unwrap();
        let recorder = crate::lowering_memo::RecordingResolver::new(&host);
        let parsed = dm_syntax::parse(&source);
        assert!(parsed.diagnostics.is_empty());
        let inputs = dm_codegen_byond::ProcedureInputs {
            current_type_path: Some(owner.into()),
            ..Default::default()
        };
        let code = dm_codegen_byond::compile_simple_proc_with_resolver(
            &parsed.items[0].children,
            &inputs,
            front.snapshot.tree.symbols(),
            &recorder,
        );
        assert!(
            code.is_ok(),
            "proven native value read must not require unknown type metadata"
        );
        let query = Q::DeclaredVarType {
            owner: field.owner,
            name: field.name,
        };
        assert!(
            recorder
                .reads()
                .iter()
                .any(|read| read.query == query && read.answer == M::Unsupported(query)),
            "optional knowledge still enters the ordinary dependency ledger"
        );
    }
}
