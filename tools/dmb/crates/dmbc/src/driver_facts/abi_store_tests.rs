//! Two sessions over one ABI core: the second finds, validates against its own answers, and claims the first one's variant.
use super::*;
use super::super::*;
use observations::{Boundary, Current, Inputs};

struct Host(bool);
impl Resolver for Host {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        match query {
            ResolveQuery::GlobalVar(_) if self.0 => ResolvedMeaning::Symbol(SymbolId::of("present")),
            ResolveQuery::GlobalVar(_) => ResolvedMeaning::Missing,
            _ => ResolvedMeaning::Unsupported(query),
        }
    }
}

fn session(core: &Arc<Core>) -> AbiStore {
    AbiStore::Shared { core: Arc::clone(core), lease: core.lease() }
}

fn engine() -> Arc<crate::runner_host::EnginePayload> {
    crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap()
}

fn inputs(engine: &Arc<crate::runner_host::EnginePayload>) -> Arc<Inputs> {
    Arc::new(Inputs {
        metadata: Arc::new(dm_ir::ProcedureMetadata {
            signature: dm_ir::ProcedureSignature {
                parameters: Arc::from([]),
                variadic: false,
                return_annotation: None,
            },
            settings: Arc::from([]),
        }),
        predecessor: None,
        engine: Arc::downgrade(engine),
        boundary: Boundary::Fresh,
        resource: None,
        evaluation_resource: None,
        lexical: true,
        pure_policy: None,
        ancestry: None,
        definition: None,
    })
}

fn unit() -> Artifact {
    Artifact::Unit(Arc::new(UnitArtifact {
        canonical: None,
        inputs: Arc::new(ProcedureInputs::default()),
        abi: Arc::new(PreparedAbi {
            layout: ProcLayout::default(),
            argument_sources: Vec::new(),
            source_helpers: Vec::new(),
        }),
    }))
}

fn reads_of(inputs: &Arc<Inputs>, query: ResolveQuery) -> admission::Reads {
    observations::reads(
        Arc::clone(inputs),
        vec![dm_session::ResolverRead { query, domain: query.domain(), answer: ResolvedMeaning::Missing }],
    )
    .into()
}

/// The validation the unit consumer runs: the receipt reads against the asking session answers.
fn admit(store: &AbiStore, key: &[u8], current: &Current<'_>) -> Option<Arc<Artifact>> {
    store
        .visit_receipted_with(
            key,
            &mut |reads| admission::changed(reads, current, None),
            &mut |value| matches!(value.as_ref(), Artifact::Unit(_)),
        )
        .0
        .map(|found| found.value)
}

#[test]
fn second_session_claims_the_first_variant_and_it_dies_with_the_last_lease() {
    let engine = engine();
    let core = Arc::new(Core::shared_current_rosters());
    let (first, second) = (session(&core), session(&core));
    let key = observations::locator(UnitIdentity {
        owner: SymbolId::of("/datum/a"),
        name: SymbolId::of("p"),
        namespace: Namespace::Proc,
        occurrence: 0,
    });
    let query = ResolveQuery::GlobalVar(SymbolId::of("missing"));
    let inputs = inputs(&engine);
    let stored = first
        .insert_with_receipt(Arc::clone(&key), reads_of(&inputs, query), 1, unit)
        .unwrap();

    // The second session has not claimed it yet: the scheduler sees a sibling variant.
    let mut seen = Vec::new();
    second.visit_candidates([key.as_ref()], |_, held| seen.push(held));
    first.visit_candidates([key.as_ref()], |_, held| seen.push(held));
    assert_eq!(seen, [false, true]);

    // Its own answers decide: a tree answering differently misses, an equal tree hits the SAME value.
    let changed = Current { inputs: Arc::clone(&inputs), resolver: &Host(true) };
    assert!(admit(&second, &key, &changed).is_none());
    let current = Current { inputs: Arc::clone(&inputs), resolver: &Host(false) };
    let shared = admit(&second, &key, &current).expect("an equal tree reuses the stored variant");
    assert!(Arc::ptr_eq(&shared, &stored));
    let mut seen = Vec::new();
    second.visit_candidates([key.as_ref()], |_, held| seen.push(held));
    assert_eq!(seen, [true]);

    // Computing the same unit again stores nothing new: the insert finds the equal variant.
    let again = second
        .insert_with_receipt(Arc::clone(&key), reads_of(&inputs, query), 1, || {
            panic!("an equal variant is stored")
        })
        .unwrap();
    assert!(Arc::ptr_eq(&again, &stored));

    let weak = Arc::downgrade(&stored);
    drop((stored, shared, again));
    drop(first);
    assert!(weak.upgrade().is_some(), "the second session still claims it");
    second.retain_current_keys(std::iter::empty());
    assert!(weak.upgrade().is_none(), "nothing claims it any more");
}

#[test]
fn claim_of_a_released_variant_is_declined() {
    let engine = engine();
    let core = Arc::new(Core::shared_current_rosters());
    let (first, second) = (session(&core), session(&core));
    let key: Arc<[u8]> = Arc::from(&b"unit"[..]);
    let reads = observations::reads(inputs(&engine), Vec::new()).into();
    let stored = first.insert_with_receipt(Arc::clone(&key), reads, 1, unit).unwrap();
    first.retain_current_keys(std::iter::empty());
    // The only holder released it: a row the scheduler validated meanwhile cannot claim it back.
    let AbiStore::Shared { lease, .. } = &second else { unreachable!() };
    assert!(!lease.claim_stored(&key, &stored));
}
