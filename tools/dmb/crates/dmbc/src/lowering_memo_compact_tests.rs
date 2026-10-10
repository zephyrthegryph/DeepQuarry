use super::*;
use crate::debug_sources::DebugOriginProvider;
use crate::lowering::DiskReplayBindings;
use dm_ir::Resolver;
use std::path::Path;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
#[test]
fn compact_disk_replays_checked_frozen_code_and_declines_changed_receipts_and_abi() {
    check_replay(
        "/proc/compact_probe(x)\n    return \"hello\"\n",
        false,
        false,
    );
}
#[test]
fn compact_disk_replays_current_abi_companions_and_rejects_changed_helper_order() {
    check_replay(
        "/proc/compact_probe(x in list(1, 2))\n    return \"hello\"\n",
        true,
        false,
    );
}
#[test]
fn compact_disk_reissues_modified_descriptor_from_current_source() {
    check_replay(
        "/obj/base\n    var/amount = 0\n/proc/compact_probe()\n    return (/obj/base{amount=1})\n",
        false,
        true,
    );
}
fn check_replay(source: &'static str, helpers: bool, modifiers: bool) {
    check_replay_mode(source, helpers, modifiers, false);
}
#[test]
fn compact_disk_replays_plain_instance_with_separate_current_binding_authority() {
    check_replay_mode(
        "/obj/plain\n/proc/compact_probe()\n    return /obj/plain\n",
        false,
        false,
        true,
    );
}
#[test]
fn compact_disk_replays_plain_instance_helper_with_current_abi_and_receipts() {
    check_replay_mode(
        "/obj/plain\n/proc/compact_probe(x in list(/obj/plain))\n    return \"hello\"\n",
        true,
        false,
        true,
    );
}
struct InstanceHost<'a, R>(&'a R, bool);
impl<R: Resolver> Resolver for InstanceHost<'_, R> {
    fn resolve(&self, query: ResolveQuery) -> dm_ir::ResolvedMeaning {
        if self.1 && query == ResolveQuery::RuntimeType(SymbolId::of("/obj/plain")) {
            dm_ir::ResolvedMeaning::Symbol(SymbolId::of("/obj"))
        } else {
            self.0.resolve(query)
        }
    }
}
fn check_replay_mode(source: &'static str, helpers: bool, modifiers: bool, plain: bool) {
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap()
    .with_bootstrap_catalog()
    .unwrap();
    let seed = engine.frontend_seed();
    let front = dm_tree::frontend::build_with_config(
        Path::new("compact.dme"),
        &Source(source),
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let (base_host, _) = crate::request_runner::runner_facts::prepare(&front, &engine).unwrap();
    let host = InstanceHost(&base_host, plain);
    let recorder = crate::lowering_memo::RecordingResolver::new(&host);
    recorder.resolve(ResolveQuery::GlobalVar(SymbolId::of("absent")));
    let startup = crate::startup::capture(&front).unwrap();
    let pool = dm_exec::BuildExecutor::new(1).unwrap();
    let abi =
        crate::driver_facts::prepare_pinned_source_abi_with_startup_on_executor_with_artifacts(
            &front, &engine, &host, &startup, None, &pool, None,
        )
        .unwrap();
    let policy = crate::driver_facts::FrozenPreparedPolicy::new(&front, &abi.prepared).unwrap();
    let mut source: std::collections::BTreeSet<_> = front
        .snapshot
        .tree
        .types()
        .iter()
        .map(|n| dm_ir::SymRef::Type(n.path))
        .collect();
    if plain {
        source.insert(dm_ir::SymRef::Instance(SymbolId::of("/obj/plain")));
    }
    let external = crate::symbolic::ReferenceBindings::default();
    let bindings = DiskReplayBindings {
        source: &source,
        external: &external,
    };
    let mut batch = crate::lowering::lower_frontend_with_statics(
        &front,
        &recorder,
        &policy,
        Default::default(),
        &startup,
    );
    assert!(batch.diagnostics.is_empty());
    assert_eq!(batch.units.len(), 1);
    let unit = batch.units.pop().unwrap();
    let body = &front.bodies[0];
    let bodies = dm_tree::frontend::BodyArena::new_typed(
        &front,
        dm_codegen_byond::typed_statements_supported_for_capture,
    );
    let issuer = CurrentModifiedIssuer {
        frontend: &front,
        body,
        bodies: &bodies,
        host: &host,
        parsed: None,
    };
    let offsets: Vec<_> = unit
        .debug_origins
        .entries
        .iter()
        .map(|origin| {
            (0..body.expanded_span.end - body.expanded_span.start)
                .find(|offset| {
                    front
                        .origin(body.expanded_span.start + offset)
                        .ok()
                        .as_ref()
                        == Some(origin)
                })
                .expect("every producer origin belongs to the current body")
        })
        .collect();
    let expected_debug = unit.debug_origins.clone();
    assert_eq!(
        crate::lowering_memo::rebase_debug(&front, body, &offsets),
        Some(expected_debug)
    );
    let value = crate::symbolic::prepare_contribution(
        unit,
        front.snapshot.tree.symbols(),
        &source,
        &external,
        false,
    )
    .unwrap();
    let bytes = encode(
        b"exact-source-and-policy",
        &recorder.reads(),
        &[],
        &value,
        &offsets,
    )
    .unwrap();
    let reads = recorder.reads();
    assert!(
        !reads.is_empty(),
        "ordinary producer must record dependencies"
    );
    let groups: std::sync::Arc<[std::sync::Arc<[ResolverRead]>]> = reads
        .iter()
        .cloned()
        .map(|read| std::sync::Arc::from([read]))
        .collect();
    let grouped = dm_session::Receipt::from_groups(groups).unwrap();
    assert!(grouped.flat().is_none());
    let grouped_bytes = encode(
        b"exact-source-and-policy",
        grouped.iter(),
        &[],
        &value,
        &offsets,
    )
    .unwrap();
    assert_eq!(
        grouped_bytes, bytes,
        "group boundaries cannot change canonical disk wire"
    );
    assert!(
        grouped.flat().is_none(),
        "encoding must not flatten receipt storage"
    );
    let payload = decode(&bytes).unwrap();
    assert!(payload.changed_read(&host).is_none());
    assert_eq!(!payload.helpers.0.is_empty(), helpers);
    assert_eq!(!payload.recipes.0.is_empty(), modifiers);
    assert_eq!(
        !payload.instances.0.is_empty()
            || payload
                .helpers
                .0
                .iter()
                .any(|helper| !helper.instances().is_empty()),
        plain
    );
    if helpers {
        let mut bad = decode(&bytes).unwrap();
        bad.helpers.0[0].argument = u32::MAX;
        assert!(bad
            .rebind(
                crate::lowering_memo_wire::ProcedureReplayContext {
                    frontend: &front,
                    body,
                    parsed: None,
                    bindings: Some(bindings),
                    selections_only: false,
                    modified: Some(&issuer),
                },
                &abi.prepared.units[0].1
            )
            .is_err());
        let mut bad = decode(&bytes).unwrap();
        bad.helpers.0.clear();
        assert!(bad
            .rebind(
                crate::lowering_memo_wire::ProcedureReplayContext {
                    frontend: &front,
                    body,
                    parsed: None,
                    bindings: Some(bindings),
                    selections_only: false,
                    modified: Some(&issuer),
                },
                &abi.prepared.units[0].1
            )
            .is_err());
    }
    let ready = &abi.prepared.units[0].1;
    if !modifiers {
        let extra = std::collections::BTreeSet::from([dm_ir::SymRef::Instance(
            dm_ir::SymbolId::of("unselected descriptor"),
        )]);
        assert!(decode(&bytes)
            .unwrap()
            .executable
            .restore(&front, body, ready, bindings, offsets.len(), &extra, &[])
            .is_none());
    }
    let context = || crate::lowering_memo_wire::ProcedureReplayContext {
        frontend: &front,
        body,
        parsed: None,
        bindings: Some(bindings),
        selections_only: false,
        modified: Some(&issuer),
    };
    if plain && !helpers {
        let mut bad = decode(&bytes).unwrap();
        bad.instances.0.push(bad.instances.0[0]);
        let duplicate = dm_wire::encode_bounded(SCHEMA, &bad, MAX_RECORD).unwrap();
        assert!(
            decode(&duplicate).is_err(),
            "plain roster keys must be strictly ordered and unique"
        );
        let mut unlicensed = source.clone();
        unlicensed.remove(&dm_ir::SymRef::Instance(SymbolId::of("/obj/plain")));
        let alias = SymbolId::of("/obj/plain");
        assert!(
            crate::symbolic::procedure_artifact::disk::plain_instance_licensed(
                alias,
                &payload.instances.0,
                bindings
            )
        );
        assert!(
            !crate::symbolic::procedure_artifact::disk::plain_instance_licensed(
                alias,
                &payload.instances.0,
                DiskReplayBindings {
                    source: &unlicensed,
                    external: &external
                }
            )
        );
        let mut bad = decode(&bytes).unwrap();
        bad.instances.0[0].1 = SymbolId::of("/datum");
        let bytes = dm_wire::encode_bounded(SCHEMA, &bad, MAX_RECORD).unwrap();
        assert!(
            decode(&bytes).is_err(),
            "tuple must match the recorded runtime answer"
        );
    }
    if plain && helpers {
        let mut bad = decode(&bytes).unwrap();
        bad.helpers.0[0].corrupt_instance_runtime();
        let bytes = dm_wire::encode_bounded(SCHEMA, &bad, MAX_RECORD).unwrap();
        assert!(
            decode(&bytes).is_err(),
            "helper tuple must match the recorded runtime answer"
        );
    }
    let identity = payload.identity;
    let framed = dm_cache::encode_variants(std::slice::from_ref(&bytes)).unwrap();
    let selected = crate::lowering_memo_wire::candidates(&framed)
        .unwrap()
        .procedure(
            b"exact-source-and-policy",
            identity,
            context(),
            &host,
            ready,
        );
    assert!(
        selected.prepared.is_some(),
        "ordinary disk hit bypasses rich IR replay"
    );
    assert!(selected.unit.is_none());
    let restored = payload.rebind(context(), ready).unwrap();
    assert_eq!(
        encode(
            b"exact-source-and-policy",
            &recorder.reads(),
            &[],
            &restored,
            &offsets
        )
        .unwrap(),
        bytes,
        "all procedure and companion frozen payloads roundtrip exactly"
    );
    assert_eq!(
        restored.shared_artifact().code().code().canonical_bytes(),
        value.shared_artifact().code().code().canonical_bytes()
    );
    let mut bad = decode(&bytes).unwrap();
    bad.abi = Cow::Borrowed(b"wrong current ABI");
    assert!(bad.rebind(context(), ready).is_err());
    let mut bad = decode(&bytes).unwrap();
    bad.reads.0[0].answer = Cow::Borrowed(b"changed negative answer");
    assert!(bad.changed_read(&host).is_some());
    let mut bad = decode(&bytes).unwrap();
    if modifiers {
        bad.recipes.0[0].corrupt_canonical();
    } else if plain {
        bad.required_types.0.clear();
    } else {
        bad.executable.corrupt_string();
    }
    assert!(bad.rebind(context(), ready).is_err());
    let mut tampered = bytes;
    *tampered.last_mut().unwrap() ^= 1;
    assert!(decode(&tampered).is_err());
}

#[test]
fn compact_sequence_rejects_advertised_oversize_before_payload_elements() {
    let bytes = dm_wire::encode(99, &vec![0u8; MAX_ITEMS + 1]).unwrap();
    assert!(dm_wire::decode::<BoundedVec<u8>>(99, &bytes, bytes.len()).is_err());
}
