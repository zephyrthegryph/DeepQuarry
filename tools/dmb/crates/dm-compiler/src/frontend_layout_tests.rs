use super::{OutlineSession, OutlineStats};

#[test]
fn procedure_digests_follow_current_spans_without_path_aliases() {
    let original = "/obj/example\n\tproc/value()\n\t\treturn 1\n/proc/repeated()\n\treturn 2\n/proc/repeated()\n\treturn 3\n";
    let shifted = format!("// preceding edit\n{original}");
    let edited = shifted.replace("return 2", "return 42");
    let mut session = OutlineSession::default();
    for source in [original, shifted.as_str(), edited.as_str()] {
        let (ast, _) = session.compact_snapshot(source).unwrap();
        let descriptors = crate::bootstrap::outline_descriptors(&ast).unwrap();
        let digests = session.procedure_digests(source).unwrap();
        assert_eq!(digests.len(), 3);
        for descriptor in descriptors {
            assert_eq!(
                digests.get(&(descriptor.start, descriptor.end)),
                Some(&crate::incremental::digest(source[descriptor.start..descriptor.end].as_bytes()))
            );
        }
    }
    assert!(session.procedure_digests(original).is_none());
    session.release_source_frames();
    assert!(session.procedure_digests(&edited).is_none());
}

fn fixture() -> String {
    let mut source = String::from(
        "/obj/container\n\tvar/stable = 1\n\tproc/nested_value()\n\t\treturn stable\n",
    );
    for index in 0..80 {
        if index == 16 {
            source.push_str("// START\n");
        }
        if index == 60 {
            source.push_str("// END */\n");
        }
        source.push_str(&format!(
            "/proc/value_{index}()\n\treturn {index}\n//{}\n",
            "padding".repeat(600)
        ));
    }
    source
}

#[test]
fn cached_resource_literals_match_full_scanner_after_edits() {
    let source = fixture().replace(
        "return 40\n",
        "return list('first.dmi', \"nested [file('second.png')]\")\n",
    );
    let edited = source.replace("'second.png'", "'changed.png'");
    let commented = edited.replace("// START\n", "/* START\n");
    let mut session = OutlineSession::default();
    for source in [&source, &edited, &commented] {
        let mut expected = Vec::new();
        crate::bootstrap::resource_scan::visit_resources(source, &mut |literal| {
            expected.push(literal.to_owned())
        });
        assert_eq!(session.resource_literals(source).unwrap(), expected);
    }
}

#[test]
fn resource_inventory_restarts_from_disk_syntax() {
    let directory = std::env::temp_dir().join(format!(
        "dm-resource-inventory-{}-{}",
        std::process::id(),
        super::TEMP_SEQUENCE.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    ));
    let source =
        "/proc/assets()\n\treturn list('first.dmi', \"[file('nested.png')]\", 'first.dmi')\n";
    let mut initial = OutlineSession::new(Some(directory.clone()));
    let expected = initial.resource_literals(source).unwrap();
    drop(initial);
    let mut restarted = OutlineSession::new(Some(directory.clone()));
    assert_eq!(restarted.resource_literals(source).unwrap(), expected);
    assert_eq!(restarted.stats().disk_hits, 1);
    let path = super::shard_path(&directory, &crate::incremental::digest(source.as_bytes()));
    let bytes = std::fs::read(&path).unwrap();
    let newline = bytes.iter().position(|byte| *byte == b'\n').unwrap();
    let mut stored: super::StoredChunk = serde_json::from_slice(&bytes[newline + 1..]).unwrap();
    stored.resources[0][1] = source.len() + 1;
    let payload = serde_json::to_vec(&stored).unwrap();
    let mut bytes = crate::incremental::digest(&payload).into_bytes();
    bytes.push(b'\n');
    bytes.extend(payload);
    std::fs::write(&path, bytes).unwrap();
    let mut repaired = OutlineSession::new(Some(directory.clone()));
    assert_eq!(repaired.resource_literals(source).unwrap(), expected);
    assert_eq!(repaired.stats().parsed_chunks, 1);
    let edited = source.replace("'nested.png'", "'changed.png'");
    let mut exact = Vec::new();
    crate::bootstrap::resource_scan::visit_resources(&edited, &mut |literal| {
        exact.push(literal.to_owned())
    });
    assert_eq!(restarted.resource_literals(&edited).unwrap(), exact);
    std::fs::remove_dir_all(directory).unwrap();
}

fn oracle(source: &str, session: &mut OutlineSession) -> OutlineStats {
    let expected = crate::bootstrap::incremental_source_outline(source).unwrap();
    let actual = session.update_source(source).unwrap();
    assert_eq!(actual.abi_digest, expected.abi_digest);
    assert_eq!(actual.procedures.len(), expected.procedures.len());
    for (path, expected) in expected.procedures {
        let actual = &actual.procedures[&path];
        assert_eq!(actual.source, expected.source, "{path}");
        assert_eq!(actual.digest, expected.digest, "{path}");
        assert_eq!(actual.patchable, expected.patchable, "{path}");
    }
    session.stats()
}

#[test]
fn local_layout_edits_insert_delete_and_change_nested_declarations() {
    let source = fixture();
    let mut session = OutlineSession::default();
    oracle(&source, &mut session);
    let body = source.replace("return 40\n", "return 4000\n");
    let stats = oracle(&body, &mut session);
    assert!(stats.memory_hits > 4);
    assert!(stats.boundary_scanned_bytes < body.len() * 3 / 4);
    let inserted = body.replace(
        "/proc/value_40()",
        "/proc/inserted()\n\treturn 10\n/proc/value_40()",
    );
    oracle(&inserted, &mut session);
    let deleted = inserted.replace("/proc/inserted()\n\treturn 10\n", "");
    oracle(&deleted, &mut session);
    let nested = deleted.replace("return stable", "var/local = stable\n\t\treturn local + 1");
    oracle(&nested, &mut session);
    // Newline/UTF-8 growth at either edge must retain safe offset arithmetic.
    let unicode = format!("// Unicode: \u{00e9}\n{nested}\n/proc/new_tail()\n\treturn 3\n");
    oracle(&unicode, &mut session);
    oracle(&source, &mut session);
}

#[test]
fn comment_state_propagating_past_neighbors_uses_safe_full_scan() {
    let source = fixture();
    let mut session = OutlineSession::default();
    oracle(&source, &mut session);
    let edited = source.replace("// START\n", "/* START\n");
    let stats = oracle(&edited, &mut session);
    assert!(stats.boundary_scanned_bytes >= edited.len());
}

#[test]
fn macro_expanded_include_footprints_keep_outline_oracle_equivalence() {
    struct Sources(std::collections::BTreeMap<std::path::PathBuf, String>);
    impl dm_preprocess::SourceProvider for Sources {
        fn read(&self, path: &std::path::Path) -> Result<String, String> {
            self.0
                .get(path)
                .cloned()
                .ok_or_else(|| "missing source".into())
        }
    }
    let mut source = fixture();
    source = source.replace("return 40\n", "return VALUE\n");
    let mut sources = Sources(std::collections::BTreeMap::from([
        (
            "project.dme".into(),
            "#define VALUE 40\n#include \"head.dm\"\n#include \"body.dm\"\n".into(),
        ),
        (
            "head.dm".into(),
            "/obj/included\n\tproc/cross_file()\n".into(),
        ),
        ("body.dm".into(), format!("\t\treturn VALUE\n{source}")),
    ]));
    let mut session = OutlineSession::default();
    let preprocess = |sources: &Sources| {
        dm_preprocess::preprocess_project(
            std::path::Path::new("project.dme"),
            sources,
            &std::collections::BTreeMap::new(),
        )
    };
    oracle(&preprocess(&sources).text, &mut session);
    sources
        .0
        .get_mut(std::path::Path::new("body.dm"))
        .unwrap()
        .push_str("/proc/added()\n\treturn VALUE + 1\n");
    oracle(&preprocess(&sources).text, &mut session);
    sources.0.insert(
        "project.dme".into(),
        "#define VALUE 400\n#include \"head.dm\"\n#include \"body.dm\"\n".into(),
    );
    oracle(&preprocess(&sources).text, &mut session);
}

#[test]
fn compact_snapshot_rebases_cached_nodes_without_reparsing() {
    let source = fixture();
    let mut session = OutlineSession::default();
    let (ast, _) = session.compact_snapshot(&source).unwrap();
    assert_eq!(
        ast,
        crate::bootstrap::declaration_snapshot(&source).unwrap()
    );
    let edited = source.replace("return 40\n", "return 400\n");
    let (ast, _) = session.compact_snapshot(&edited).unwrap();
    assert_eq!(
        ast,
        crate::bootstrap::declaration_snapshot(&edited).unwrap()
    );
    assert!(session.stats().memory_hits > 4);
    let (ast, _) = session.compact_snapshot(&edited).unwrap();
    assert_eq!(
        ast,
        crate::bootstrap::declaration_snapshot(&edited).unwrap()
    );
    assert_eq!(session.stats().parsed_chunks, 0);
    assert_eq!(session.stats().boundary_scanned_bytes, 0);
}

#[test]
fn bounded_retention_trims_duplicate_bodies_and_preserves_layout() {
    // Use real body text: trailing padding comments need not belong to a
    // procedure fragment and therefore do not force body-storage trimming.
    let source = fixture().replace(
        "return 40\n",
        &format!("return \"{}\"\n", "payload".repeat(2048)),
    );
    let mut session = OutlineSession::default();
    oracle(&source, &mut session);
    let structural_bytes: usize = session
        .chunks
        .values()
        .map(|chunk| {
            let chunk = &chunk.parsed;
            chunk.without_bodies().resident_bytes + chunk.digest.len() + 256
        })
        .sum();
    session.cache_budget = source.len()
        + 16
        + structural_bytes
        + session.last_layout.capacity()
            * std::mem::size_of::<(usize, std::sync::Arc<super::ParsedChunk>)>()
        + 8192;
    let budget = session.cache_budget;
    oracle(&source, &mut session);
    assert!(session.last_source.is_some());
    assert!(session.chunks.values().all(|chunk| chunk
        .parsed
        .fragments
        .iter()
        .all(|fragment| fragment.source.is_none())));
    for value in 1000..1008 {
        let edited = source.replace("return 41\n", &format!("return {value}\n"));
        let stats = oracle(&edited, &mut session);
        assert!(stats.memory_hits > 4);
        assert!(session.resident_bytes() <= budget);
    }
}

#[test]
fn disk_outline_restarts_repair_corruption_and_reject_invalid_boundaries() {
    let directory = std::env::temp_dir().join(format!(
        "dm-frontend-{}-{}",
        std::process::id(),
        super::TEMP_SEQUENCE.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    ));
    let source = "/obj/cache\n\tvar/value = 2\n\tproc/test()\n\t\treturn value\n";
    oracle(source, &mut OutlineSession::new(Some(directory.clone())));
    let mut restarted = OutlineSession::new(Some(directory.clone()));
    oracle(source, &mut restarted);
    assert_eq!(restarted.stats().disk_hits, 1);
    assert_eq!(restarted.stats().parsed_chunks, 0);
    let path = super::shard_path(&directory, &crate::incremental::digest(source.as_bytes()));
    std::fs::write(&path, b"corrupt").unwrap();
    let mut repaired = OutlineSession::new(Some(directory.clone()));
    oracle(source, &mut repaired);
    assert_eq!(repaired.stats().parsed_chunks, 1);
    let mut after_repair = OutlineSession::new(Some(directory.clone()));
    oracle(source, &mut after_repair);
    assert_eq!(after_repair.stats().disk_hits, 1);
    let bytes = std::fs::read(&path).unwrap();
    let newline = bytes.iter().position(|byte| *byte == b'\n').unwrap();
    let mut stored: super::StoredChunk = serde_json::from_slice(&bytes[newline + 1..]).unwrap();
    stored.descriptors[0].end = source.len() + 10;
    let payload = serde_json::to_vec(&stored).unwrap();
    let mut invalid = crate::incremental::digest(&payload).into_bytes();
    invalid.push(b'\n');
    invalid.extend(payload);
    std::fs::write(&path, invalid).unwrap();
    let mut invalid_boundary = OutlineSession::new(Some(directory.clone()));
    oracle(source, &mut invalid_boundary);
    assert_eq!(invalid_boundary.stats().parsed_chunks, 1);
    std::fs::remove_dir_all(directory).unwrap();
}
