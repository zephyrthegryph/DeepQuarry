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
    let (host, _) = crate::request_runner::runner_facts::prepare(&front, &engine).unwrap();
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
    let source: std::collections::BTreeSet<_> = front
        .snapshot
        .tree
        .types()
        .iter()
        .map(|n| dm_ir::SymRef::Type(n.path))
        .collect();
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
    let payload = decode(&bytes).unwrap();
    assert!(payload.changed_read(&host).is_none());
    assert_eq!(!payload.helpers.0.is_empty(), helpers);
    assert_eq!(!payload.recipes.0.is_empty(), modifiers);
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
            .restore(&front, body, ready, bindings, offsets.len(), &extra)
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
