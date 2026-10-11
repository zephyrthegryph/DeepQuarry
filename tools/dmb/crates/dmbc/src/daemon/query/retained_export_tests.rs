use super::*;
use crate::runner_host::query_snapshot::{QueryAttempt, QueryState};
use std::sync::{Arc, Mutex};
#[test]
fn retained_export_streams_current_facts_without_full_analysis_claims() {
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok("/datum/example\n    var/value = 7\n    proc/read(amount = 3)\n        set waitfor = 0\n        return value\n".into())
        }
    }
    let frontend = dm_tree::frontend::build_with_config(
        std::path::Path::new("fixture.dme"),
        &Source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
    )
    .unwrap();
    let state = Arc::new(Mutex::new(QueryState::default()));
    let mut attempt = QueryAttempt::new(Arc::clone(&state), true);
    attempt.capture(&frontend);
    attempt.finish_analyzed();
    drop(attempt);
    let mut request = QueryRequest {
        timeout_seconds: None,
        project: "fixture.dme".into(),
        defines: Default::default(),
        engine_template: None,
        bootstrap_catalog: false,
        expected_revision: Some(format!("{:032x}", frontend.snapshot.tree.identity())),
        expected_source_revision: Some(format!(
            "{:032x}",
            dm_analysis::tree_export::source_revision(&frontend)
        )),
        queries: vec![],
        source_queries: vec![],
    };
    let mut bytes = Vec::new();
    export_with(&request, &mut bytes, |page| {
        let reply = crate::daemon::query::evaluate_snapshot(
            &page,
            &frontend.snapshot.tree,
            &state.lock().unwrap(),
        )?;
        crate::daemon::query::validate_reply(
            &reply,
            0,
            1,
            page.expected_revision.as_deref(),
            page.expected_source_revision.as_deref(),
        )?;
        Ok(reply)
    })
    .unwrap();
    let rows: Vec<serde_json::Value> = std::str::from_utf8(&bytes)
        .unwrap()
        .lines()
        .map(|line| serde_json::from_str(line).unwrap())
        .collect();
    assert_eq!(rows[0]["schema"], SCHEMA);
    assert_eq!(rows[0]["complete"], false);
    assert_eq!(rows[0]["aggregate_max_items"], 524288);
    assert_eq!(rows[0]["aggregate_max_pages"], 4096);
    assert_eq!(rows[0]["frame_max_bytes"], 524288);
    assert_eq!(rows[0]["watchdog_seconds"], 300);
    assert_eq!(rows[0]["full_member_metadata_included"], true);
    assert_eq!(
        rows.iter()
            .filter(|row| row["row"] == "retained_roster_complete")
            .count(),
        5
    );
    assert!(rows
        .iter()
        .any(|row| row["row"] == "type" && row["path"] == "/datum/example"));
    assert!(rows
        .iter()
        .any(|row| row["row"] == "member" && row["name"] == "value"));
    assert!(rows.iter().any(|row| row["row"] == "occurrence"));
    assert!(rows
        .iter()
        .any(|row| row["row"] == "body" && row["executable_facts_included"] == false));
    assert_eq!(
        rows.iter().filter(|row| row["row"] == "type").count(),
        frontend.snapshot.tree.types().len()
    );
    assert_eq!(
        rows.iter().filter(|row| row["row"] == "member").count(),
        frontend.snapshot.tree.members().len()
    );
    // Every pre-existing full semantic field comes from the identical serializer,
    // while retained selectors add their current dense ordinal separately.
    let mut full = Vec::new();
    dm_analysis::tree_export::write_jsonl(&frontend, &mut full).unwrap();
    for full_row in std::str::from_utf8(&full)
        .unwrap()
        .lines()
        .map(|line| serde_json::from_str::<serde_json::Value>(line).unwrap())
        .filter(|row| {
            row["row"] == "member"
                || row["row"] == "type"
                || row["row"] == "body"
                || row["row"] == "occurrence"
        })
    {
        let resident = rows
            .iter()
            .find(|row| {
                row["row"] == full_row["row"]
                    && if full_row["row"] == "body" {
                        row["declaration"] == full_row["declaration"]
                    } else if full_row["row"] == "occurrence" {
                        row["occurrence"] == full_row["occurrence"]
                    } else {
                        row["id"] == full_row["id"]
                    }
            })
            .unwrap();
        for (field, value) in full_row.as_object().unwrap() {
            assert_eq!(&resident[field], value, "current semantic field {field}");
        }
    }
    assert_eq!(rows.last().unwrap()["row"], "retained_export_finished");
    request.expected_source_revision = Some("1".repeat(32));
    bytes.clear();
    assert!(export_with(&request, &mut bytes, |page| Ok(
        crate::daemon::query::evaluate_snapshot(
            &page,
            &frontend.snapshot.tree,
            &state.lock().unwrap()
        )?
    ))
    .is_err());
    assert!(!std::str::from_utf8(&bytes)
        .unwrap()
        .contains("retained_export_finished"));
    request.expected_source_revision = None;
    bytes.clear();
    assert!(export_with(&request, &mut bytes, |_| panic!(
        "unpinned export reached transport"
    ))
    .is_err());
    assert!(bytes.is_empty());
}

#[test]
fn export_rejects_invalid_aggregate_before_transport() {
    let request = QueryRequest {
        timeout_seconds: None,
        project: "fixture.dme".into(),
        defines: Default::default(),
        engine_template: None,
        bootstrap_catalog: false,
        expected_revision: Some("00000000000000000000000000000001".into()),
        expected_source_revision: Some("00000000000000000000000000000002".into()),
        queries: vec![],
        source_queries: vec![],
    };
    for limits in [
        ExportLimits {
            max_items: 0,
            max_pages: 1,
        },
        ExportLimits {
            max_items: 1,
            max_pages: 131073,
        },
    ] {
        let mut output = Vec::new();
        assert!(
            export_with_limits(&request, &mut output, limits, |_| panic!(
                "invalid quota reached transport"
            ))
            .is_err()
        );
        assert!(output.is_empty());
    }
}
