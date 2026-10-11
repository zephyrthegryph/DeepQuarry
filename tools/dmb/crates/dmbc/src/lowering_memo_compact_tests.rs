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
#[test]
fn compact_disk_preserves_current_local_array_warning_receipts() {
    check_replay(
        "/proc/compact_probe()\n    var/list/value[2] = list(\"warning fixture\",2)\n    return value\n",
        false,
        false,
    );
}
#[test]
fn compact_disk_rebinds_lexer_warning_cursor_and_checked_current_eof() {
    check_replay("/proc/compact_probe()\n    var/value = input(\"warning fixture\") as text|anything\n    return value\n", false, false);
    check_replay(
        "/proc/compact_probe()\n    return input(\"warning fixture\") as text|anything\n",
        false,
        false,
    );
}
#[test]
fn compact_cursor_recipe_declines_unissued_skipped_directive_progression() {
    struct Included;
    impl dm_preprocess::SourceProvider for Included {
        fn read(&self, path: &Path) -> Result<String, String> {
            Ok(if path.extension().is_some_and(|extension| extension == "dme") {
                "#include \"probe.dm\"\n#undef X\n"
            } else {
                "/proc/compact_probe()\n    return input(\"warning fixture\") as text|anything\n"
            }.into())
        }
    }
    let frontend = dm_tree::frontend::build(
        Path::new("compact_unknown.dme"),
        &Included,
        &Default::default(),
        1,
    )
    .unwrap();
    let body = &frontend.bodies[0];
    let end = frontend.expanded.text.find("text|anything").unwrap() + "text|anything".len();
    assert!(frontend.diagnostic_cursor_after(end).is_none());
    let recipe = crate::debug_sources::RelativeDebugAnchor::LexerCursorAfterBodyOffset(
        end - body.expanded_span.start,
    );
    let bound = crate::lowering_memo::rebase_debug(&frontend, body, &[recipe]).unwrap();
    assert_eq!(bound.entries[0].line, 0);
    assert_eq!(bound.entries[0].semantic_path.as_ref(), "probe.dm");
    let wire = dm_wire::encode(0x0d1a_0001, &vec![recipe]).unwrap();
    let restored: Vec<crate::debug_sources::RelativeDebugAnchor> =
        dm_wire::decode(0x0d1a_0001, &wire, wire.len()).unwrap();
    assert_eq!(
        crate::lowering_memo::rebase_debug(&frontend, body, &restored),
        Some(bound)
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
    check_replay_features(source, helpers, modifiers, plain, Default::default());
}
#[test]
fn compact_disk_roundtrips_issued_source_features_without_opcode_inference() {
    check_replay_features(
        "/proc/compact_probe(x in list(1,2))\n    return \"hello\"\n",
        true,
        false,
        false,
        dm_codegen_byond::SourceFeatures {
            world_cpu: true,
            native_graphics: true,
        },
    );
}
fn check_replay_features(
    source: &'static str,
    helpers: bool,
    modifiers: bool,
    plain: bool,
    source_features: dm_codegen_byond::SourceFeatures,
) {
    let original_source = source;
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
    let mut unit = batch.units.pop().unwrap();
    // Transport contract: source-issued facts must survive even when no
    // corresponding opcode exists in this deliberately ordinary body/helper.
    unit.code.procedure.source_features = source_features;
    for helper in &mut unit.source_helpers {
        helper.code.procedure.source_features = source_features;
    }
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
            if unit.code.procedure.warnings.iter().any(|warning| {
                warning.code == dm_ir::WarningCode::AnythingWithoutList
                    && warning.source_ordinal.is_some_and(|ordinal| {
                        unit.debug_origins.entries.get(ordinal as usize) == Some(origin)
                    })
            }) {
                let end =
                    front.expanded.text.find("text|anything").unwrap() + "text|anything".len();
                return crate::debug_sources::RelativeDebugAnchor::LexerCursorAfterBodyOffset(
                    end - body.expanded_span.start,
                );
            }
            (0..body.expanded_span.end - body.expanded_span.start)
                .find(|offset| {
                    front
                        .origin(body.expanded_span.start + offset)
                        .ok()
                        .as_ref()
                        == Some(origin)
                })
                .map(crate::debug_sources::RelativeDebugAnchor::AtBodyOffset)
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
                    verify: false,
                    modified: Some(&issuer),
                },
                &abi.prepared.units()[0].1
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
                    verify: false,
                    modified: Some(&issuer),
                },
                &abi.prepared.units()[0].1
            )
            .is_err());
    }
    let ready = &abi.prepared.units()[0].1;
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
        verify: false,
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
    let featureless_schema = dm_wire::encode_bounded(0x0206_0010, &payload, MAX_RECORD).unwrap();
    assert!(
        decode(&featureless_schema).is_err(),
        "old compact schema cannot admit missing source-feature authority"
    );
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
    let fresh_warnings = crate::initializer_policy::warnings::render(
        &value
            .current_warnings(front.snapshot.tree.symbols())
            .unwrap(),
    )
    .unwrap();
    let disk_warnings = crate::initializer_policy::warnings::render(
        &restored
            .current_warnings(front.snapshot.tree.symbols())
            .unwrap(),
    )
    .unwrap();
    assert_eq!(fresh_warnings, disk_warnings);
    if !fresh_warnings.is_empty() {
        for ordinal in [None, Some(u32::MAX)] {
            let mut malformed = decode(&bytes).unwrap();
            malformed.executable.corrupt_warning_ordinal(ordinal);
            assert!(malformed.rebind(context(), ready).is_err());
        }
        let mut malformed = decode(&bytes).unwrap();
        malformed.executable.corrupt_warning_name();
        assert!(malformed.rebind(context(), ready).is_err());
        let cursor_warning = original_source.contains("as text|anything");
        let expected = if cursor_warning {
            "compact.dme:3:warning (anything_no_list): 'anything' has no meaning without a list\n"
        } else {
            "compact.dme:2:warning (list_double_init): value: list doubly initialized\n"
        };
        assert_eq!(fresh_warnings, [expected]);
        let shifted_text: &'static str =
            Box::leak(format!("// shifted\n\n{original_source}").into_boxed_str());
        let shifted = dm_tree::frontend::build_with_config(
            Path::new("compact.dme"),
            &Source(shifted_text),
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap();
        let (shifted_host, _) =
            crate::request_runner::runner_facts::prepare(&shifted, &engine).unwrap();
        let shifted_startup = crate::startup::capture(&shifted).unwrap();
        let shifted_abi =
            crate::driver_facts::prepare_pinned_source_abi_with_startup_on_executor_with_artifacts(
                &shifted,
                &engine,
                &shifted_host,
                &shifted_startup,
                None,
                &pool,
                None,
            )
            .unwrap();
        let shifted_policy =
            crate::driver_facts::FrozenPreparedPolicy::new(&shifted, &shifted_abi.prepared)
                .unwrap();
        let mut fresh = crate::lowering::lower_frontend_with_statics(
            &shifted,
            &shifted_host,
            &shifted_policy,
            Default::default(),
            &shifted_startup,
        );
        assert!(fresh.diagnostics.is_empty());
        let fresh = crate::symbolic::prepare_contribution(
            fresh.units.pop().unwrap(),
            shifted.snapshot.tree.symbols(),
            &source,
            &external,
            false,
        )
        .unwrap();
        let shifted_body = &shifted.bodies[0];
        let shifted_ready = &shifted_abi.prepared.units()[0].1;
        let shifted_debug =
            crate::lowering_memo::rebase_debug(&shifted, shifted_body, &offsets).unwrap();
        let artifact = value.shared_artifact();
        let moved_resident = crate::symbolic::PreparedContribution::rebind(
            &artifact,
            &shifted,
            shifted_body,
            shifted_ready,
            shifted_debug,
            &[],
        )
        .unwrap();
        let moved_disk = decode(&bytes)
            .unwrap()
            .rebind(
                crate::lowering_memo_wire::ProcedureReplayContext {
                    frontend: &shifted,
                    body: shifted_body,
                    parsed: None,
                    bindings: Some(bindings),
                    selections_only: false,
                    verify: false,
                    modified: None,
                },
                shifted_ready,
            )
            .unwrap();
        let rendered = |value: &crate::symbolic::PreparedContribution| {
            crate::initializer_policy::warnings::render(
                &value
                    .current_warnings(shifted.snapshot.tree.symbols())
                    .unwrap(),
            )
            .unwrap()
        };
        let shifted_expected = if cursor_warning {
            "compact.dme:5:warning (anything_no_list): 'anything' has no meaning without a list\n"
        } else {
            "compact.dme:4:warning (list_double_init): value: list doubly initialized\n"
        };
        assert_eq!(rendered(&fresh), [shifted_expected]);
        assert_eq!(rendered(&fresh), rendered(&moved_resident));
        assert_eq!(rendered(&fresh), rendered(&moved_disk));
        let artifact = value.shared_artifact();
        let resident = crate::symbolic::PreparedContribution::rebind_with_modified(
            &artifact,
            &front,
            body,
            ready,
            crate::lowering_memo::rebase_debug(&front, body, &offsets).unwrap(),
            std::sync::Arc::clone(value.required_types_owner()),
            Vec::new(),
            value.modified_recipes_owner().map(std::sync::Arc::clone),
        )
        .unwrap();
        assert!(std::sync::Arc::ptr_eq(
            value.required_types_owner(),
            resident.required_types_owner()
        ));
        assert!(std::sync::Arc::ptr_eq(
            value.modified_recipes_owner().unwrap(),
            resident.modified_recipes_owner().unwrap()
        ));
        assert_eq!(
            crate::initializer_policy::warnings::render(
                &resident
                    .current_warnings(front.snapshot.tree.symbols())
                    .unwrap()
            )
            .unwrap(),
            fresh_warnings
        );
    }
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
