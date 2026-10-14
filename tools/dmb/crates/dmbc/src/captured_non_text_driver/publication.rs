use super::*;
use std::sync::atomic::{AtomicBool, Ordering};

struct DropHost {
    tree: Tree,
    dropped: Arc<AtomicBool>,
}
impl Resolver for DropHost {
    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        self.tree.resolve(query)
    }
}
impl Drop for DropHost {
    fn drop(&mut self) {
        self.dropped.store(true, Ordering::SeqCst);
    }
}

#[test]
fn publication_handoff_moves_exact_resource_facts_and_releases_capture_models() {
    let bytes = include_bytes!("../../../../fixtures/native_template.bin");
    let engine = crate::engine::EngineSnapshot::from_bytes(bytes, 1).unwrap();
    let seed = engine.frontend_seed();
    let frontend = dm_tree::frontend::build_with_config(
        Path::new("game/project.dme"),
        &Source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let roots = [
        "/",
        "/datum",
        "/obj",
        "/mob",
        "/turf",
        "/area",
        "/client",
        "/atom",
        "/image",
        "/mutable_appearance",
    ]
    .into_iter()
    .map(SymbolId::of)
    .collect();
    let decoded = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
    let directives = [
        Directive::DefaultType {
            kind: DefaultKind::Turf,
            path: Some(SymbolId::of("/turf/tile")),
        },
        Directive::Dimension { axis: 0, value: 2 },
        Directive::Dimension { axis: 1, value: 1 },
        Directive::Dimension { axis: 2, value: 1 },
    ];
    for retained_archive in [false, true] {
        let dropped = Arc::new(AtomicBool::new(false));
        let mut output = capture(
            &frontend,
            &Source,
            &Source,
            DropHost {
                tree: Tree(frontend.snapshot.tree.clone()),
                dropped: dropped.clone(),
            },
            &decoded,
            &roots,
            &directives,
        )
        .unwrap();
        let weak_model = Arc::downgrade(&output.captured.maps[0].model);
        let expected_archive = output.resources.archive.identity();
        if retained_archive {
            output.resources.archive = crate::assets::ResourceArchive::Retained(expected_archive);
        }
        let expected_pointer = output
            .resources
            .archive
            .captured_bytes()
            .map(|bytes| bytes.as_ptr());
        let expected_catalog = output.resource_catalog.record().clone();
        let expected_order = output.resource_archive_order.clone();
        let retained_inputs = crate::input_snapshot::InputSnapshot::new(123);
        let expected_inputs = serde_json::to_value(&retained_inputs).unwrap();
        output.retained_resource_inputs = Some(retained_inputs);
        assert!(!dropped.load(Ordering::SeqCst));
        let publication = output.into_publication();
        assert!(dropped.load(Ordering::SeqCst));
        assert!(weak_model.upgrade().is_none());
        assert_eq!(publication.archive.identity(), expected_archive);
        assert_eq!(
            publication
                .archive
                .captured_bytes()
                .map(|bytes| bytes.as_ptr()),
            expected_pointer
        );
        assert_eq!(publication.resource_catalog.record(), &expected_catalog);
        assert_eq!(publication.resource_archive_order, expected_order);
        assert_eq!(
            serde_json::to_value(publication.retained_resource_inputs.as_ref().unwrap()).unwrap(),
            expected_inputs
        );
    }
}
