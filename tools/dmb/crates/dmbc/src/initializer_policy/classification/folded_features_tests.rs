use super::*;
use std::sync::{atomic::AtomicBool, Mutex};
struct FeatureHost {
    changed: AtomicBool,
    opaque: AtomicBool,
    reads: Mutex<Vec<ResolveQuery>>,
}
impl Resolver for FeatureHost {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        self.reads.lock().unwrap().push(query);
        match query {
            ResolveQuery::RuntimeType(path) => ResolvedMeaning::Symbol(path),
            ResolveQuery::Ancestry(owner) if self.opaque.load(Ordering::Relaxed) => {
                ResolvedMeaning::Unsupported(ResolveQuery::Ancestry(owner))
            }
            ResolveQuery::Ancestry(owner) => ResolvedMeaning::Symbols(
                vec![if self.changed.load(Ordering::Relaxed) {
                    SymbolId::of("/datum")
                } else {
                    owner
                }]
                .into(),
            ),
            _ => ResolvedMeaning::Missing,
        }
    }
}
#[test]
fn folded_nameof_features_match_pinned_headers_and_survive_current_replay() {
    // byond-capture.json binds these output bytes to pinned 516.1687 and source
    // hashes. Both mutable and const defaults fold to strings without bytecode.
    for (case, source, fact) in [
        ("global_cpu", "nameof(world.cpu)", 8),
        ("constant_cpu", "nameof(world.cpu)", 10),
        ("global_graphics", "nameof(/obj::icon)", 8),
        ("constant_graphics", "nameof(/obj::icon)", 10),
        ("skipped_cpu", "0 && nameof(world.cpu)", 10),
        (
            "skipped_graphics",
            "1 ? \"constant\" : nameof(/obj::icon)",
            10,
        ),
    ] {
        let captured = byond_dmb::dmb::Dmb::from_bytes(
            &std::fs::read(
                std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                    .join("../../fixtures/native/folded_source_features")
                    .join(format!("{case}.byond.bin")),
            )
            .unwrap(),
        )
        .unwrap();
        let mut symbols = SymbolTable::default();
        for name in ["/", "/world", "/obj", "/datum"] {
            symbols.intern(name).unwrap();
        }
        let write = super::write(source, &mut symbols);
        let host = FeatureHost {
            changed: AtomicBool::new(false),
            opaque: AtomicBool::new(false),
            reads: Mutex::new(Vec::new()),
        };
        let store = InitializerArtifacts::with_limit(1024 * 1024);
        let evaluator = crate::driver_facts::DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: &host,
            symbols: &symbols,
        };
        let factory = evaluator.parallel_evaluator().unwrap();
        let reuse = InitializerReuse {
            store: &store,
            resolver: &host,
            policy: 1,
            resource_search_context: None,
        };
        let first = classify_one(
            &write,
            &symbols,
            &evaluator,
            ModifierFact::Known(fact),
            0,
            factory,
            reuse,
        )
        .unwrap();
        assert!(first.write.phase.is_none(), "{case}");
        assert!(
            matches!(first.write.default, DefaultValue::Scalar(_)),
            "{case}"
        );
        assert_eq!(
            first.write.source_features.world_cpu,
            captured.header.flags & 1 != 0,
            "{case}"
        );
        assert_eq!(
            first.write.source_features.native_graphics,
            captured.header.flags & 0x40 == 0,
            "{case}"
        );
        let replay = classify_one(
            &write,
            &symbols,
            &evaluator,
            ModifierFact::Known(fact),
            83,
            factory,
            reuse,
        )
        .unwrap();
        assert_eq!(replay.write.source_features, first.write.source_features);
        assert_eq!(replay.write.source_ordinal, 83);
        assert_eq!(store.hits.load(Ordering::Relaxed), 1);
        assert!(host
            .reads
            .lock()
            .unwrap()
            .iter()
            .any(|query| matches!(query, ResolveQuery::Ancestry(_))));
        // The string value stays equal, but changed semantic ancestry must
        // recompute the sidecar rather than accepting value-only equality.
        host.changed.store(true, Ordering::Relaxed);
        let changed = classify_one(
            &write,
            &symbols,
            &evaluator,
            ModifierFact::Known(fact),
            84,
            factory,
            reuse,
        )
        .unwrap();
        assert_eq!(changed.write.default, first.write.default);
        assert_eq!(changed.write.source_features, Default::default());
        assert_eq!(store.recomputed.load(Ordering::Relaxed), 2);
        host.opaque.store(true, Ordering::Relaxed);
        assert!(classify_one(
            &write,
            &symbols,
            &evaluator,
            ModifierFact::Known(fact),
            85,
            factory,
            reuse
        )
        .is_err());
    }
}
