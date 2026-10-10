use super::*;
use crate::runner_host::query_snapshot::{QueryAttempt, QueryState};
use std::sync::{Arc, Mutex};
struct Source(String);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok(self.0.clone())
    }
}
fn frontend(source: &str) -> dm_tree::frontend::ColdFrontend {
    dm_tree::frontend::build(
        std::path::Path::new("pages.dme"),
        &Source(source.into()),
        &Default::default(),
        1,
    )
    .unwrap()
}
fn request(front: &dm_tree::frontend::ColdFrontend, start: u32, limit: u32) -> QueryRequest {
    QueryRequest {
        project: "pages.dme".into(),
        defines: Default::default(),
        engine_template: None,
        bootstrap_catalog: false,
        expected_revision: Some(format!("{:032x}", front.snapshot.tree.identity())),
        expected_source_revision: Some(format!(
            "{:032x}",
            dm_analysis::tree_export::source_revision(front)
        )),
        queries: vec![],
        source_queries: vec![SourceQuery::OccurrencesPage { start, limit }],
    }
}
fn state(front: &dm_tree::frontend::ColdFrontend) -> QueryState {
    let state = Arc::new(Mutex::new(QueryState::default()));
    let mut attempt = QueryAttempt::new(Arc::clone(&state), true);
    attempt.capture(front);
    attempt.finish_analyzed();
    drop(attempt);
    Arc::try_unwrap(state).ok().unwrap().into_inner().unwrap()
}
#[test]
fn pages_enumerate_exact_current_order_and_validate_actual_reply_without_global_completeness() {
    let front = frontend("/datum/base\n    var/a=1\n/datum/base/child\n    var/b=2\n");
    let state = state(&front);
    let snapshot = state.snapshot.as_ref().unwrap();
    let total = front.snapshot.occurrences.source_order().len() as u32;
    let mut start = 0;
    let mut seen = 0;
    loop {
        let request = request(&front, start, 2);
        let reply = evaluate_snapshot(&request, &front.snapshot.tree, &state).unwrap();
        validate_reply(
            &reply,
            0,
            1,
            request.expected_revision.as_deref(),
            request.expected_source_revision.as_deref(),
        )
        .unwrap();
        occurrence_pages::validate_requested(&reply, &request.source_queries).unwrap();
        assert!(!reply.complete);
        let row: serde_json::Value = serde_json::from_str(reply.jsonl.trim()).unwrap();
        assert_eq!(row["total"], total);
        assert_eq!(row["page_complete"], true);
        assert_eq!(row["complete"], false);
        for item in row["items"].as_array().unwrap() {
            assert_eq!(
                item,
                &snapshot.occurrence(seen, &front.snapshot.tree).unwrap()
            );
            seen += 1;
        }
        match row["next_cursor"].as_u64() {
            Some(next) => start = next as u32,
            None => break,
        }
    }
    assert_eq!(seen, total);
    let end = evaluate_snapshot(&request(&front, total, 2), &front.snapshot.tree, &state).unwrap();
    let row: serde_json::Value = serde_json::from_str(end.jsonl.trim()).unwrap();
    assert_eq!(row["returned"], 0);
    assert!(row["next_cursor"].is_null());
}
#[test]
fn paging_rejects_bad_pins_ranges_overflow_and_tampered_or_unrequested_rows() {
    let text = (0..80)
        .map(|i| format!("/datum/t{i}\n"))
        .collect::<String>();
    let front = frontend(&text);
    let state = state(&front);
    for (start, limit) in [(0, 0), (0, 129), (81, 1)] {
        assert!(
            evaluate_snapshot(&request(&front, start, limit), &front.snapshot.tree, &state)
                .is_err()
        );
    }
    let mut missing = request(&front, 0, 2);
    missing.expected_source_revision = None;
    assert!(missing.validate().is_err());
    let mut stale = request(&front, 0, 2);
    stale.expected_source_revision = Some("00000000000000000000000000000000".into());
    assert!(evaluate_snapshot(&stale, &front.snapshot.tree, &state).is_err());
    let mut oversized = request(&front, 0, 128);
    oversized.source_queries = vec![
        SourceQuery::OccurrencesPage {
            start: 0,
            limit: 128
        };
        128
    ];
    assert!(
        evaluate_snapshot(&oversized, &front.snapshot.tree, &state).is_err(),
        "whole reply must be rejected, never silently truncated"
    );
    let request = request(&front, 0, 2);
    let reply = evaluate_snapshot(&request, &front.snapshot.tree, &state).unwrap();
    let mut row: serde_json::Value = serde_json::from_str(reply.jsonl.trim()).unwrap();
    row["items"][0]["occurrence"] = 17.into();
    assert!(occurrence_pages::validate(&row, reply.source_revision.as_deref()).is_err());
    let unexpected = [SourceQuery::OccurrencesPage { start: 1, limit: 2 }];
    assert!(occurrence_pages::validate_requested(&reply, &unexpected).is_err());
}
