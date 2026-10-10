use super::*;
use observations::{Boundary, Current, Inputs};
fn engine() -> Arc<crate::runner_host::EnginePayload> {
    crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap()
}
fn metadata() -> Arc<dm_ir::ProcedureMetadata> {
    Arc::new(dm_ir::ProcedureMetadata {
        signature: dm_ir::ProcedureSignature {
            parameters: Arc::from([]),
            variadic: false,
            return_annotation: None,
        },
        settings: Arc::from([]),
    })
}
struct Host(bool);
impl Resolver for Host {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        match query {
            ResolveQuery::GlobalVar(_) if self.0 => {
                ResolvedMeaning::Symbol(SymbolId::of("present"))
            }
            ResolveQuery::GlobalVar(_) => ResolvedMeaning::Missing,
            _ => ResolvedMeaning::Unsupported(query),
        }
    }
}
#[test]
fn typed_inputs_seal_exact_owner_boundary_predecessor_and_policy() {
    let owner = engine();
    let inputs = Arc::new(Inputs {
        metadata: metadata(),
        predecessor: None,
        engine: Arc::clone(&owner),
        boundary: Boundary::Fresh,
        resource: None,
        evaluation_resource: None,
        lexical: true,
        pure_policy: None,
    });
    let identity = UnitIdentity {
        owner: SymbolId::of("/datum/a"),
        name: SymbolId::of("p"),
        namespace: Namespace::Proc,
        occurrence: 0,
    };
    let key = observations::locator(identity);
    let store = AbiArtifacts::with_engine_owner(Arc::clone(&owner));
    let abi = Arc::new(PreparedAbi {
        layout: ProcLayout::default(),
        argument_sources: Vec::new(),
        source_helpers: Vec::new(),
    });
    assert!(store
        .store
        .insert_with_owned(
            Arc::clone(&key),
            observations::reads(Arc::clone(&inputs), Vec::new()),
            Vec::new(),
            0,
            || Artifact {
                canonical: None,
                inputs: Arc::new(ProcedureInputs::default()),
                abi: Arc::clone(&abi)
            }
        )
        .is_some());
    let host = Host(false);
    assert!(store
        .store
        .lookup(
            &key,
            &Current {
                inputs: Arc::clone(&inputs),
                resolver: &host
            }
        )
        .is_some());
    let mut variants = Vec::new();
    let mut changed = (*inputs).clone();
    changed.engine = engine();
    variants.push(changed);
    let mut changed = (*inputs).clone();
    changed.boundary = Boundary::Absent;
    variants.push(changed);
    let mut changed = (*inputs).clone();
    changed.resource = Some(0);
    variants.push(changed);
    let mut changed = (*inputs).clone();
    changed.evaluation_resource = Some(0);
    variants.push(changed);
    let mut changed = (*inputs).clone();
    changed.lexical = false;
    variants.push(changed);
    let mut changed = (*inputs).clone();
    changed.pure_policy = Some(0);
    variants.push(changed);
    let mut changed = (*inputs).clone();
    Arc::make_mut(&mut changed.metadata).signature.variadic = true;
    variants.push(changed);
    let mut changed = (*inputs).clone();
    changed.predecessor = Some(Arc::clone(&abi));
    variants.push(changed);
    let mut changed = (*inputs).clone();
    changed.boundary = Boundary::Engine {
        owner: identity.owner,
        name: identity.name,
        kind: MemberKind::Proc,
    };
    variants.push(changed);
    let mut changed = (*inputs).clone();
    changed.boundary = Boundary::Intrinsic {
        engine_identity: 1,
        owner: identity.owner,
        name: identity.name,
        layout: ProcLayout::default(),
    };
    variants.push(changed);
    for changed in variants {
        assert!(store
            .store
            .lookup(
                &key,
                &Current {
                    inputs: Arc::new(changed),
                    resolver: &host
                }
            )
            .is_none());
    }
    let predecessor = Arc::new(Inputs {
        predecessor: Some(Arc::clone(&abi)),
        ..(*inputs).clone()
    });
    assert!(store
        .store
        .insert_with_owned(
            Arc::clone(&key),
            observations::reads(Arc::clone(&predecessor), Vec::new()),
            Vec::new(),
            0,
            || Artifact {
                canonical: None,
                inputs: Arc::new(ProcedureInputs::default()),
                abi: Arc::clone(&abi)
            }
        )
        .is_some());
    let mut changed = (*predecessor).clone();
    Arc::make_mut(changed.predecessor.as_mut().unwrap())
        .argument_sources
        .push(dm_codegen_byond::procedure_abi::ArgumentSource::Builtin {
            kind: 1,
            parameter: 2,
        });
    assert!(store
        .store
        .lookup(
            &key,
            &Current {
                inputs: Arc::new(changed),
                resolver: &host
            }
        )
        .is_none());
    assert!(store
        .store
        .lookup(
            &key,
            &Current {
                inputs: predecessor,
                resolver: &host
            }
        )
        .is_some());
}
#[test]
fn typed_abi_negative_semantic_reads_replay_and_current_keys_replace_history() {
    let owner = engine();
    let inputs = Arc::new(Inputs {
        metadata: metadata(),
        predecessor: None,
        engine: Arc::clone(&owner),
        boundary: Boundary::Fresh,
        resource: None,
        evaluation_resource: None,
        lexical: true,
        pure_policy: None,
    });
    let store = AbiArtifacts::with_engine_owner(owner);
    let identity = UnitIdentity {
        owner: SymbolId::of("/datum/a"),
        name: SymbolId::of("p"),
        namespace: Namespace::Proc,
        occurrence: 0,
    };
    let key = observations::locator(identity);
    let query = ResolveQuery::GlobalVar(SymbolId::of("missing"));
    let reads = observations::reads(
        Arc::clone(&inputs),
        vec![dm_session::ResolverRead {
            query,
            domain: query.domain(),
            answer: ResolvedMeaning::Missing,
        }],
    );
    assert!(store
        .store
        .insert_with_owned(Arc::clone(&key), reads, Vec::new(), 0, || Artifact {
            canonical: None,
            inputs: Arc::new(ProcedureInputs::default()),
            abi: Arc::new(PreparedAbi {
                layout: ProcLayout::default(),
                argument_sources: Vec::new(),
                source_helpers: Vec::new()
            })
        })
        .is_some());
    assert!(store
        .store
        .lookup(
            &key,
            &Current {
                inputs: Arc::clone(&inputs),
                resolver: &Host(false)
            }
        )
        .is_some());
    assert!(store
        .store
        .lookup(
            &key,
            &Current {
                inputs,
                resolver: &Host(true)
            }
        )
        .is_none());
    store.prune(&Mutex::new(Vec::new()));
    let mut entries = 0;
    store.visit_storage(|view| {
        if let dm_session::ObservedArtifactStorageView::Store { entries: n, .. } = view {
            entries = n
        }
    });
    assert_eq!(entries, 0);
    let mut changed = identity;
    changed.occurrence = 1;
    assert_ne!(key, observations::locator(changed));
}
