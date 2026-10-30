//! Real original source/runtime resolver comparison, not a hash equivalence.
//! This does NOT bind or promote frontend-only source Answers yet.
use super::*;
use dm_ir::{ResolveQuery as Q, Resolver, SymbolId};
struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok("/datum/answer_base\n    var/value = 1\n    proc/work(x)\n        return x\n/datum/answer_child\n    parent_type = /datum/answer_base\n    work(x)\n        return x\n".into())
    }
}
#[test]
fn original_generic_absence_and_qualified_hierarchy_runtime_startup_contracts() {
    let environment = PathBuf::from("source-answer-equivalence.dme");
    let mut host = crate::runner_host::BuildHost::one_shot();
    let engine = host
        .engine(
            environment.clone(),
            Default::default(),
            true,
            include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap();
    let front = dm_tree::frontend::build_with_config(
        &environment,
        &Source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(engine.frontend_seed()),
            observer: None,
        },
    )
    .unwrap();
    let (runtime, _) =
        crate::request_runner::runner_facts::prepare_retained(&front, &engine, None).unwrap();
    let startup = crate::startup::capture(&front).unwrap();
    let startup_resolver = startup.resolver(&front, &runtime).unwrap();
    let tree = front.snapshot.tree.as_ref();
    let child = SymbolId::of("/datum/answer_child");
    let absent = SymbolId::of("/datum/not_declared");
    let queries = [
        Q::Type(child),
        Q::Type(absent),
        Q::Type(SymbolId::of("/list")),
        Q::Parent(child),
        Q::Ancestry(child),
        Q::HasMemberVar {
            owner: child,
            name: SymbolId::of("value"),
        },
        Q::HasMemberVar {
            owner: child,
            name: SymbolId::of("missing"),
        },
        Q::DeclaredVarType {
            owner: child,
            name: SymbolId::of("value"),
        },
        Q::Proc {
            owner: child,
            name: SymbolId::of("work"),
            verb: false,
        },
        Q::Proc {
            owner: child,
            name: SymbolId::of("missing"),
            verb: false,
        },
        Q::DeclarationChain {
            owner: child,
            name: SymbolId::of("work"),
            verb: false,
        },
    ];
    let hierarchy = tree.certified_hierarchy().expect(
        "actual native engine seed must certify hierarchy independently of member inventory",
    );
    for path in [
        child,
        SymbolId::of("/list"),
        SymbolId::of("/datum/not_declared"),
    ] {
        for kind in [
            dm_ir::HierarchyQuestion::Type,
            dm_ir::HierarchyQuestion::Parent,
            dm_ir::HierarchyQuestion::Ancestry,
        ] {
            let question = Q::CertifiedHierarchy { kind, path };
            let original = hierarchy.answer(kind, path);
            assert_eq!(
                Resolver::resolve(tree, question),
                original,
                "actual native qualified source {question:?}"
            );
            assert_eq!(
                runtime.resolve(question),
                original,
                "actual runtime qualified delegation {question:?}"
            );
            assert_eq!(
                startup_resolver.resolve(question),
                original,
                "actual startup qualified delegation {question:?}"
            );
        }
    }
    // Record EVERY original finite source/runtime/startup result. These raw
    // questions have different completeness contracts; no generic equivalence
    // or guessed list of admissible richer-runtime variants is asserted.
    for question in queries {
        let original = Resolver::resolve(tree, question);
        let runtime_answer = runtime.resolve(question);
        let startup_answer = startup_resolver.resolve(question);
        eprintln!("actual raw answer {question:?}: source={original:?}; runtime={runtime_answer:?}; startup={startup_answer:?}");
        assert_eq!(
            runtime_answer, startup_answer,
            "actual startup delegation {question:?}"
        );
    }
    let absent = Q::Type(SymbolId::of("/datum/not_declared"));
    assert_eq!(
        Resolver::resolve(tree, absent),
        dm_ir::ResolvedMeaning::Unsupported(absent),
        "raw counterexample must remain visible"
    );
    assert_eq!(runtime.resolve(absent), dm_ir::ResolvedMeaning::Missing);
    assert_eq!(
        startup_resolver.resolve(absent),
        dm_ir::ResolvedMeaning::Missing
    );
    // Different-world/resource/static/profile questions are NOT covered by this
    // finite equivalence test. No frontend-only Answers binding is installed.
}
