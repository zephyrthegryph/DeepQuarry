use super::*;
use std::{path::Path, sync::Arc};
struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, path: &Path) -> Result<String, String> {
        match path.file_name().and_then(|name|name.to_str()) {
            Some("project.dme")=>Ok("#include \"skin.dmf\"\n#include \"source.dm\"\n#include \"map.dmm\"\n".into()),
            Some("source.dm")=>Ok("/turf/tile\n    var/asset\n/obj/plain\n".into()),
            Some("skin.dmf")=>Ok("macro \"default\"\nwindow \"default\"\n    elem \"main\"\n        type = MAIN\n        icon = 'tiny.png'\n".into()),
            Some("map.dmm")=>Ok("\"a\"=(/obj/plain,/turf/tile{asset='asset.txt'},/area)\n(1,1,1)={\"a\"}\n".into()),
            _=>Err("fixture input absent".into()),
        }
    }
}
impl dm_resources::capture::CaptureProvider for Source {
    fn read_candidate(&self, path: &Path) -> std::io::Result<Option<dm_resources::SharedBytes>> {
        let bytes = match path.file_name().and_then(|name| name.to_str()) {
            Some("skin.dmf") => dm_preprocess::SourceProvider::read(self, path)
                .unwrap()
                .into_bytes(),
            Some("tiny.png") => {
                include_bytes!("../../../../fixtures/translation/selected_skin/tiny.png").to_vec()
            }
            Some("asset.txt") => b"map asset".to_vec(),
            _ => return Ok(None),
        };
        Ok(Some(bytes.into()))
    }
}
#[derive(Clone, Copy)]
enum MissingDomain {
    Code,
    Map,
    Skin,
}
impl dm_preprocess::SourceProvider for MissingDomain {
    fn read(&self, path: &Path) -> Result<String, String> {
        match path.file_name().and_then(|name| name.to_str()) {
            Some("project.dme") => Ok(match self {
                Self::Code => "#include \"source.dm\"\n",
                Self::Map => "#include \"source.dm\"\n#include \"map.dmm\"\n",
                Self::Skin => "#include \"skin.dmf\"\n",
            }
            .into()),
            Some("source.dm") if matches!(self, Self::Code) => {
                Ok("/var/asset='missing.png'\n/proc/probe()\n    return 'missing.png'\n".into())
            }
            Some("map.dmm") => dm_preprocess::SourceProvider::read(&Source, path)
                .map(|text| text.replace("asset.txt", "missing.png")),
            Some("skin.dmf") => dm_preprocess::SourceProvider::read(&Source, path)
                .map(|text| text.replace("tiny.png", "missing.png")),
            _ => dm_preprocess::SourceProvider::read(&Source, path),
        }
    }
}
impl dm_resources::capture::CaptureProvider for MissingDomain {
    fn read_candidate(&self, path: &Path) -> std::io::Result<Option<dm_resources::SharedBytes>> {
        if path.file_name().and_then(|name| name.to_str()) == Some("skin.dmf") {
            return Ok(Some(
                dm_preprocess::SourceProvider::read(self, path)
                    .unwrap()
                    .into_bytes()
                    .into(),
            ));
        }
        dm_resources::capture::CaptureProvider::read_candidate(&Source, path)
    }
}
#[test]
fn contradictory_missing_lookups_preserve_first_literal_error() {
    use dm_resources::native_resolver::{CapturedResourceLookup, CapturedResourceOutcome};
    let bytes = include_bytes!("../../../../fixtures/native_template.bin");
    let engine = crate::engine::EngineSnapshot::from_bytes(bytes, 1).unwrap();
    let seed = engine.frontend_seed();
    let domain = MissingDomain::Code;
    let frontend = dm_tree::frontend::build_with_config(
        Path::new("game/project.dme"),
        &domain,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let nontext = crate::non_text::capture_with_map_memo(&frontend, &domain, None).unwrap();
    let demand = dm_resources::capture::discover_demand(
        &frontend.plan,
        &frontend.expanded,
        &nontext.assets.literals,
        &nontext.assets.skins,
    )
    .unwrap();
    let lookups = vec![
        CapturedResourceLookup {
            path: "asset.txt".into(),
            search_context: demand.context.identity(),
            outcome: CapturedResourceOutcome::Missing,
        },
        CapturedResourceLookup {
            path: "missing.png".into(),
            search_context: demand.context.identity(),
            outcome: CapturedResourceOutcome::Missing,
        },
        CapturedResourceLookup {
            path: "missing.png".into(),
            search_context: demand.context.identity(),
            outcome: CapturedResourceOutcome::Unsupported,
        },
    ];
    let error =
        reject_missing_demands(&frontend, &nontext, &demand.literals, &lookups).unwrap_err();
    assert!(
        error.ends_with("source.dm:1:error: 'missing.png': cannot find file"),
        "{error}"
    );
    let mut reordered = lookups;
    reordered.reverse();
    assert_eq!(
        reject_missing_demands(&frontend, &nontext, &demand.literals, &reordered).unwrap_err(),
        error
    );
}
#[test]
fn missing_literal_errors_preserve_domain_and_current_source_origin() {
    let bytes = include_bytes!("../../../../fixtures/native_template.bin");
    let engine = crate::engine::EngineSnapshot::from_bytes(bytes, 1).unwrap();
    let seed = engine.frontend_seed();
    let decoded = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
    for domain in [MissingDomain::Code, MissingDomain::Map, MissingDomain::Skin] {
        let frontend = dm_tree::frontend::build_with_config(
            Path::new("game/project.dme"),
            &domain,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap();
        let measurements = std::cell::RefCell::new(Vec::new());
        let observer = |measurement| measurements.borrow_mut().push(measurement);
        let result = capture_with_observer(
            &frontend,
            &domain,
            &domain,
            Tree(frontend.snapshot.tree.clone()),
            &decoded,
            &BTreeSet::new(),
            &[],
            Some(&observer),
        );
        let stages = measurements.borrow();
        assert!(stages
            .iter()
            .all(|stage: &CaptureMeasurement| stage.seconds >= 0.0));
        if !matches!(domain, MissingDomain::Skin) {
            assert_eq!(stages.last().unwrap().stage, CaptureStage::AssetCapture);
            assert!(!stages.last().unwrap().succeeded);
            assert_eq!(stages.len(), 3);
            assert_eq!(stages[0].stage, CaptureStage::NonTextParsing);
            assert_eq!(stages[1].stage, CaptureStage::ResourceDemand);
            assert!(stages[0].succeeded);
            assert!(stages[1].succeeded);
        }
        match domain {
            MissingDomain::Code => match result {
                Err(message) => assert!(
                    message.ends_with("source.dm:1:error: 'missing.png': cannot find file"),
                    "{message}"
                ),
                Ok(_) => panic!("missing DM literal accepted"),
            },
            MissingDomain::Map => match result {
                Err(message) => assert!(
                    message.ends_with("map.dmm:1:error: cannot find file"),
                    "{message}"
                ),
                Ok(_) => panic!("missing map literal accepted"),
            },
            MissingDomain::Skin => {
                let output = result.unwrap();
                assert_eq!(output.resources.records.len(), 1);
            }
        }
    }
}
struct Tree(Arc<dm_tree::SemanticTree>);
impl Resolver for Tree {
    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        dm_ir::Resolver::resolve(self.0.as_ref(), query)
    }
}
#[test]
fn map_skin_asset_capture_produces_shared_inventory_and_initializer_artifact() {
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
    let directives = vec![
        Directive::DefaultType {
            kind: DefaultKind::Turf,
            path: Some(SymbolId::of("/turf/tile")),
        },
        Directive::Dimension { axis: 0, value: 2 },
        Directive::Dimension { axis: 1, value: 1 },
        Directive::Dimension { axis: 2, value: 1 },
    ];
    let output = capture(
        &frontend,
        &Source,
        &Source,
        Tree(frontend.snapshot.tree.clone()),
        &decoded,
        &roots,
        &directives,
    )
    .unwrap();
    assert!(output.symbols.text(SymbolId::of("asset")).is_some());
    assert_eq!(
        output.symbols.text(SymbolId::of("asset.txt")),
        Some("asset.txt")
    );
    assert!(matches!(
        output.resolver.resolve(dm_ir::ResolveQuery::ResourceIn {
            path: SymbolId::of("asset.txt"),
            search_context: output.resource_search_context,
        }),
        dm_ir::ResolvedMeaning::Resource { .. }
    ));
    assert_eq!(output.map.as_ref().unwrap().dimensions, [2, 1, 1]);
    assert_eq!(
        output.map.as_ref().unwrap().instances[0].atom.type_path,
        SymbolId::of("/turf/tile")
    );
    assert_eq!(output.artifacts.len(), 1);
    let records =
        byond_dmb::rsc::read_all(&mut output.resources.archive.captured_bytes().unwrap()).unwrap();
    let aliases = records
        .iter()
        .map(|entry| match entry {
            byond_dmb::rsc::Entry::Named(named) => named.name.as_slice(),
            _ => panic!(),
        })
        .collect::<Vec<_>>();
    assert_eq!(
        aliases,
        [
            b"tiny.png".as_slice(),
            b"skin.dmf".as_slice(),
            b"asset.txt".as_slice()
        ]
    );
    let mut inventory = dm_link::LinkInventory::default();
    output.extend_inventory(&mut inventory).unwrap();
    assert!(inventory
        .entries
        .iter()
        .any(|entry| matches!(entry.key, dm_link::Key::MapInstance { .. })));
    let stage = output.stage(&frontend);
    crate::composition::NonTextOutputStage::validate_source(&stage, &frontend).unwrap();
    assert!(
        crate::composition::NonTextOutputStage::required_types(&stage)
            .contains(&SymbolId::of("/obj/plain"))
    );
}
#[test]
fn retained_source_only_capture_preserves_rows_and_skips_asset_reads() {
    struct Changed;
    impl dm_preprocess::SourceProvider for Changed {
        fn read(&self, path: &Path) -> Result<String, String> {
            let mut text = dm_preprocess::SourceProvider::read(&Source, path)?;
            if path.file_name().and_then(|name| name.to_str()) == Some("source.dm") {
                text.push_str("// source-only edit\n");
            }
            Ok(text)
        }
    }
    struct NoAssets;
    impl dm_resources::capture::CaptureProvider for NoAssets {
        fn read_candidate(&self, _: &Path) -> std::io::Result<Option<dm_resources::SharedBytes>> {
            panic!("retained capture reread asset payload")
        }
    }
    struct Facts;
    impl crate::input_snapshot::SnapshotProvider for Facts {
        fn stamp(&self, path: &Path) -> std::io::Result<crate::input_snapshot::Stamp> {
            let bytes =
                dm_resources::capture::CaptureProvider::read_candidate(&Source, path)?.unwrap();
            Ok(crate::input_snapshot::Stamp {
                size: bytes.len() as u64,
                modified_ns: 1,
                file_id: Some(1),
            })
        }
        fn read(&self, path: &Path) -> std::io::Result<(crate::input_snapshot::Stamp, Vec<u8>)> {
            Ok((
                self.stamp(path)?,
                dm_resources::capture::CaptureProvider::read_candidate(&Source, path)?
                    .unwrap()
                    .to_vec(),
            ))
        }
        fn list(&self, _: &Path) -> std::io::Result<crate::input_snapshot::FolderListing> {
            Ok(crate::input_snapshot::FolderListing::Missing)
        }
    }
    use crate::input_snapshot::SnapshotProvider;
    let bytes = include_bytes!("../../../../fixtures/native_template.bin");
    let engine = crate::engine::EngineSnapshot::from_bytes(bytes, 1).unwrap();
    let seed = engine.frontend_seed();
    let config = dm_tree::frontend::FrontendConfig {
        workers: 1,
        engine: Some(&seed),
        observer: None,
    };
    let frontend = dm_tree::frontend::build_with_config(
        Path::new("game/project.dme"),
        &Source,
        &Default::default(),
        config,
    )
    .unwrap();
    let decoded = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
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
    let directives = [Directive::DefaultType {
        kind: DefaultKind::Turf,
        path: Some(SymbolId::of("/turf/tile")),
    }];
    let cold = capture(
        &frontend,
        &Source,
        &Source,
        Tree(frontend.snapshot.tree.clone()),
        &decoded,
        &roots,
        &directives,
    )
    .unwrap();
    let mut inputs = crate::input_snapshot::InputSnapshot::new(10_000_000_000);
    for alias in &cold.resource_catalog.record().aliases {
        let (stamp, bytes) = Facts.read(&alias.disk_path).unwrap();
        inputs.record_file(&alias.disk_path, stamp, &bytes).unwrap();
    }
    let archive = cold.resources.archive.identity();
    let manifest = crate::resource_manifest::ResourceManifest::capture(
        7,
        &cold.resource_catalog,
        inputs,
        cold.resource_archive_order.clone(),
        archive,
    )
    .unwrap();
    let changed = dm_tree::frontend::build_with_config(
        Path::new("game/project.dme"),
        &Changed,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    assert_ne!(changed.expanded.text, frontend.expanded.text);
    let authenticated = std::cell::Cell::new(0);
    let admission = |demand: &dm_resources::capture::ResourceDemand| {
        manifest
            .validate(7, demand, &Facts, false, 20_000_000_000, |identity| {
                authenticated.set(authenticated.get() + 1);
                Ok(identity == archive)
            })
            .map_err(|error| error.to_string())
    };
    let retained = capture_with_resource_reuse(
        &changed,
        &Changed,
        &NoAssets,
        Tree(changed.snapshot.tree.clone()),
        &decoded,
        &roots,
        &directives,
        None,
        None,
        Some(&admission),
    )
    .unwrap();
    assert_eq!(authenticated.get(), 1);
    assert!(
        matches!(retained.resources.archive,crate::assets::ResourceArchive::Retained(identity) if identity==archive)
    );
    assert!(retained.resolver.resources().is_none());
    assert_eq!(cold.resources.records, retained.resources.records);
    assert_eq!(cold.resource_archive_order, retained.resource_archive_order);
    assert_eq!(
        cold.resource_catalog.identity(),
        retained.resource_catalog.identity()
    );
    assert_eq!(
        cold.resource_catalog.record(),
        retained.resource_catalog.record()
    );
    assert_eq!(
        cold.resources
            .inventory
            .iter()
            .map(|entry| (entry.key, entry.content.as_ref()))
            .collect::<Vec<_>>(),
        retained
            .resources
            .inventory
            .iter()
            .map(|entry| (entry.key, entry.content.as_ref()))
            .collect::<Vec<_>>()
    );
    assert_eq!(retained.artifacts.len(), cold.artifacts.len());
}
#[test]
fn unsupported_map_type_reports_current_origin_and_query_spellings() {
    struct ContextualSource;
    impl dm_preprocess::SourceProvider for ContextualSource {
        fn read(&self, path: &Path) -> Result<String, String> {
            if path.file_name().and_then(|name| name.to_str()) == Some("map.dmm") {
                Ok(
                    "\"a\"=(/obj/plain,/turf/tile{\nasset=new()\n},/area)\n(1,1,1)={\"a\"}\n"
                        .into(),
                )
            } else {
                dm_preprocess::SourceProvider::read(&Source, path)
            }
        }
    }
    struct OpaqueType(Tree);
    impl Resolver for OpaqueType {
        fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
            if matches!(query, dm_ir::ResolveQuery::DeclaredVarType { owner, name }
                if owner == SymbolId::of("/turf/tile") && name == SymbolId::of("asset"))
            {
                dm_ir::ResolvedMeaning::Unsupported(query)
            } else {
                self.0.resolve(query)
            }
        }
    }
    let bytes = include_bytes!("../../../../fixtures/native_template.bin");
    let engine = crate::engine::EngineSnapshot::from_bytes(bytes, 1).unwrap();
    let seed = engine.frontend_seed();
    let frontend = dm_tree::frontend::build_with_config(
        Path::new("game/project.dme"),
        &ContextualSource,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let measurements = std::cell::RefCell::new(Vec::new());
    let observer = |measurement| measurements.borrow_mut().push(measurement);
    let result = capture_with_observer(
        &frontend,
        &ContextualSource,
        &Source,
        OpaqueType(Tree(frontend.snapshot.tree.clone())),
        &byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap(),
        &BTreeSet::new(),
        &[],
        Some(&observer),
    );
    let message = match result {
        Err(message) => message,
        Ok(_) => panic!("opaque contextual map type was accepted"),
    };
    assert!(
        message.contains("map.dmm:1: unsupported map initializer for /turf/tile"),
        "{message}"
    );
    assert!(
        message.contains("owner=/turf/tile, field=asset"),
        "{message}"
    );
    let measurements = measurements.borrow();
    assert_eq!(
        measurements.last().unwrap().stage,
        CaptureStage::MapInitializers
    );
    assert!(!measurements.last().unwrap().succeeded);
}

#[path = "publication.rs"]
mod publication;

#[test]
fn prepared_nontext_releases_models_and_preserves_inventory_and_source_binding() {
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
    let directives = vec![
        Directive::DefaultType {
            kind: DefaultKind::Turf,
            path: Some(SymbolId::of("/turf/tile")),
        },
        Directive::Dimension { axis: 0, value: 2 },
        Directive::Dimension { axis: 1, value: 1 },
        Directive::Dimension { axis: 2, value: 1 },
    ];
    let output = capture(
        &frontend,
        &Source,
        &Source,
        Tree(frontend.snapshot.tree.clone()),
        &decoded,
        &roots,
        &directives,
    )
    .unwrap();
    use crate::composition::NonTextOutputStage;
    let model = Arc::downgrade(&output.captured.maps[0].model);
    let mut expected = dm_link::LinkInventory::default();
    output.extend_inventory(&mut expected).unwrap();
    let prepared = output.into_prepared(&frontend).unwrap();
    assert!(
        model.upgrade().is_none(),
        "prepared writer must release parsed map model"
    );
    let mut actual = dm_link::LinkInventory::default();
    prepared.extend_inventory(&mut actual).unwrap();
    assert_eq!(
        expected
            .entries
            .iter()
            .map(|entry| (entry.key, entry.content.as_ref()))
            .collect::<Vec<_>>(),
        actual
            .entries
            .iter()
            .map(|entry| (entry.key, entry.content.as_ref()))
            .collect::<Vec<_>>()
    );
    assert_eq!(expected.spellings, actual.spellings);
    assert_eq!(expected.slots, actual.slots);
    assert_eq!(expected.fixed, actual.fixed);
    assert_eq!(expected.orders, actual.orders);
    assert_eq!(expected.reserved_prefixes, actual.reserved_prefixes);
    assert_eq!(expected.append_orders, actual.append_orders);
    prepared.stage().validate_source(&frontend).unwrap();
    let mut changed = frontend;
    changed.plan.occurrences[0].semantic_path = Arc::from("different-debug-source.dme");
    assert!(prepared.stage().validate_source(&changed).is_err());
    let publication = prepared.into_publication();
    assert!(publication.archive.captured_bytes().is_some());
}

#[test]
fn prepared_nontext_rejects_tampered_descriptor_before_model_release() {
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
    let directives = vec![
        Directive::DefaultType {
            kind: DefaultKind::Turf,
            path: Some(SymbolId::of("/turf/tile")),
        },
        Directive::Dimension { axis: 0, value: 2 },
        Directive::Dimension { axis: 1, value: 1 },
        Directive::Dimension { axis: 2, value: 1 },
    ];
    let mut output = capture(
        &frontend,
        &Source,
        &Source,
        Tree(frontend.snapshot.tree.clone()),
        &decoded,
        &roots,
        &directives,
    )
    .unwrap();
    output.descriptors.as_mut().unwrap().entries[0].content =
        Arc::<[u8]>::from(b"invalid descriptor".as_slice()).into();
    assert!(output.into_prepared(&frontend).is_err());
}
