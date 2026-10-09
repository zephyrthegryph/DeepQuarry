//! Regression for resolver-issued inherited callable identities in the real pipeline.
use super::*;
use crate::engine_host::{Completeness, ConstantCatalog, EngineResolverHost, RuntimeAliasCatalog};
use dm_ir::{ProcedureIdentity, SemanticValue, SymRef, SymbolId};

const SOURCE: &str = "/datum/capture_base/callback()\n    return 0\n/datum/capture_base/proc/callback()\n    return 1\n/datum/capture_base/callback()\n    return 2\n/datum/capture_base/verb/verb_callback()\n    return 3\n/datum/capture_child\n    parent_type = /datum/capture_base\n/datum/capture_child/callback()\n    return 4\n/datum/capture_child/proc/unqualified_probe()\n    return callback()\n/proc/typed_probe()\n    var/datum/capture_child/receiver\n    return receiver.callback()\n/proc/typed_verb_probe()\n    var/datum/capture_child/receiver\n    return receiver.verb_callback()\n";

#[test]
fn actual_engine_frontend_captures_declared_inherited_proc_and_verb_identities() {
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap()
    .with_bootstrap_catalog()
    .unwrap();
    let seed = engine.frontend_seed();
    let frontend = dm_tree::frontend::build_with_config(
        Path::new("project.dme"),
        &Source(SOURCE),
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 2,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let mut symbols = frontend.snapshot.tree.symbols().clone();
    let constants = ConstantCatalog::native_516_1687(&mut symbols).unwrap();
    let runtime = RuntimeAliasCatalog::new(
        engine.identity(),
        &symbols,
        Vec::new(),
        frontend
            .snapshot
            .tree
            .types()
            .iter()
            .map(|node| node.path)
            .collect(),
        Completeness::Partial,
    )
    .unwrap();
    let engine_host = EngineResolverHost::new(frontend.snapshot.tree.clone(), constants, runtime)
        .with_pinned_callables(&engine, &frontend)
        .unwrap();
    let startup = crate::startup::capture(&frontend).unwrap();
    let host = startup.resolver(&frontend, &engine_host).unwrap();
    let base = SymbolId::of("/datum/capture_base");
    let child = SymbolId::of("/datum/capture_child");
    let callback = SymbolId::of("callback");
    // Explicit child/proc/callback is not a declared formal path, even though
    // the receiver has an implicit override. Member dispatch must canonicalize
    // to the captured declaration rather than relaxing literal-path semantics.
    assert!(!matches!(
        host.resolve(ResolveQuery::ProcedureValue {
            owner: child,
            name: callback,
            verb: false,
            formal: true,
        }),
        ResolvedMeaning::Value(SemanticValue::Procedure(_))
    ));
    let batch = lower_frontend_with_statics(
        &frontend,
        &host,
        &NoParameters,
        LoweringConfig {
            workers: 2,
            max_chunk: 1,
        },
        &startup,
    );
    assert!(batch.diagnostics.is_empty(), "{:?}", batch.diagnostics);
    assert_eq!(batch.units.len(), frontend.bodies.len());
    for (owner, caller, callee, verb) in [
        (child, "unqualified_probe", "callback", false),
        (SymbolId::of("/"), "typed_probe", "callback", false),
        (SymbolId::of("/"), "typed_verb_probe", "verb_callback", true),
    ] {
        let unit = batch
            .units
            .iter()
            .find(|unit| unit.identity.owner == owner && unit.identity.name == SymbolId::of(caller))
            .unwrap();
        // Derive the expected occurrence from the actual emitted formal unit:
        // source encounter order differs from normalized semantic override depth.
        let identity = batch
            .units
            .iter()
            .find(|candidate| {
                candidate.identity.owner == base
                    && candidate.identity.name == SymbolId::of(callee)
                    && (candidate.identity.namespace == crate::lowering::Namespace::Verb) == verb
                    && frontend
                        .snapshot
                        .tree
                        .member(candidate.origin.member)
                        .is_some_and(|node| node.definition == dm_tree::DefinitionMode::Declare)
            })
            .unwrap()
            .identity;
        let identity = ProcedureIdentity {
            owner: identity.owner,
            name: identity.name,
            verb,
            occurrence: identity.occurrence,
        };
        assert_eq!(
            host.resolve(ResolveQuery::MethodProcedureValue {
                owner: child,
                name: identity.name,
                verb
            }),
            ResolvedMeaning::Value(SemanticValue::Procedure(identity))
        );
        let reference = if verb {
            SymRef::Verb {
                owner: base,
                name: identity.name,
                occurrence: identity.occurrence,
            }
        } else {
            SymRef::Proc {
                owner: base,
                name: identity.name,
                occurrence: identity.occurrence,
            }
        };
        assert_eq!(
            unit.code.procedure_values.get(&reference),
            Some(&identity),
            "{caller}"
        );
        let mut references = Vec::new();
        unit.code
            .procedure
            .code
            .for_each_reference(|reference| references.push(reference));
        assert!(references.contains(&reference), "{caller}: {references:?}");
        assert!(
            unit.code
                .procedure_values
                .values()
                .all(|captured| captured.owner != child),
            "fabricated child formal identity in {caller}"
        );
    }
    // Actual executable override occurrences are still distinct source units.
    let mut base_occurrences = batch
        .units
        .iter()
        .filter(|unit| unit.identity.owner == base && unit.identity.name == callback)
        .map(|unit| unit.identity.occurrence)
        .collect::<Vec<_>>();
    base_occurrences.sort_unstable();
    assert_eq!(base_occurrences, [0, 1, 2]);
    let first_authored = batch
        .units
        .iter()
        .find(|unit| {
            unit.identity.owner == base
                && unit.identity.name == callback
                && unit.origin.source.line == 1
        })
        .unwrap();
    assert_ne!(
        first_authored.identity.occurrence, 0,
        "implicit-before-formal identity must retain normalized override depth"
    );
}
