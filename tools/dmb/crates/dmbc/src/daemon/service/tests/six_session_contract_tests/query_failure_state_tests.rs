//! One real retained build/query fixture across failure and current-source recovery.
use super::*;
use crate::daemon::query::{QueryReply, QueryRequest, SourceQuery};

fn query_request(build: &BuildRequest) -> QueryRequest {
    QueryRequest {
        timeout_seconds: Some(5),
        project: build.project.clone(),
        defines: build.defines.clone(),
        engine_template: build.engine_template.clone(),
        bootstrap_catalog: build.bootstrap_catalog,
        expected_revision: None,
        expected_source_revision: None,
        queries: Vec::new(),
        source_queries: Vec::new(),
    }
}
fn query(
    shared: &Arc<Shared>,
    request: QueryRequest,
) -> Result<QueryReply, crate::request_failure::RequestFailure> {
    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos()
        ^ (u128::from(std::process::id()) << 64);
    // Test-owned transport namespace; the actual handler still authenticates
    // the immutable compiler identity. Never start a real user daemon.
    let endpoint = transport::Endpoint::generation(nonce).unwrap();
    let listener = transport::listener(&endpoint).unwrap();
    let expected = request.clone();
    std::thread::scope(|scope| {
        let server = scope.spawn(|| super::retirement_pipe::serve_once(&listener, shared));
        let mut client = super::retirement_pipe::hello(&endpoint, shared.compiler, false);
        protocol::send(&mut client, &Request::Query(request)).unwrap();
        let reply = match protocol::receive::<Reply>(&mut client).unwrap() {
            Reply::Query(reply) => {
                crate::daemon::query::validate_reply(
                    &reply,
                    expected.queries.len(),
                    expected.source_queries.len(),
                    expected.expected_revision.as_deref(),
                    expected.expected_source_revision.as_deref(),
                )
                .unwrap();
                Ok(reply)
            }
            Reply::Rejected(error) => Err(error),
            _ => panic!("unexpected source query protocol response"),
        };
        drop(client);
        server.join().unwrap().unwrap();
        reply
    })
}
fn pin(request: &QueryRequest, reply: &QueryReply) -> QueryRequest {
    let mut pinned = request.clone();
    pinned.expected_revision = Some(reply.revision.clone());
    pinned.expected_source_revision = reply.source_revision.clone();
    pinned.source_queries = vec![SourceQuery::OccurrencesPage {
        start: 0,
        limit: 128,
    }];
    pinned
}
fn assert_prior_pair(destination: &Path, pair: &(crate::publish::OutputPair, Vec<u8>, Vec<u8>)) {
    assert_eq!(
        std::fs::read(destination.join("probe.dmb")).unwrap(),
        pair.1
    );
    assert_eq!(
        std::fs::read(destination.join("probe.rsc")).unwrap(),
        pair.2
    );
}

#[test]
fn actual_service_queries_preserve_exact_failed_build_snapshots_and_recover_current_includes() {
    let roots = Roots::new();
    let shared = shared();
    let initial_request = request(&roots, 0, false);
    let destination = initial_request.artifact_directory.clone().unwrap();
    let slot = shared.slot(
        initial_request.project.clone(),
        &initial_request.defines,
        Some(&initial_request),
    );
    let (initial, diagnostics) =
        run_captured(initial_request.clone(), &mut slot.lock_host().unwrap());
    assert!(diagnostics.is_empty());
    let initial = published(initial.unwrap(), &destination);
    let discover = query_request(&initial_request);
    let original = query(&shared, discover.clone()).unwrap();
    assert_eq!(original.snapshot_outcome, "published");
    assert_eq!(original.last_request_outcome, "published");
    assert_eq!(
        original.publication_pair.as_deref(),
        Some(initial.0.name().as_str())
    );
    let original_pin = pin(&discover, &original);
    assert!(query(&shared, original_pin.clone())
        .unwrap()
        .jsonl
        .contains("source_occurrences_page"));

    // Directive failure produces no new source model. The prior exact captured
    // source remains readable, explicitly separate from the failed attempt.
    std::fs::write(
        &initial_request.project,
        "#include \"probe.dm\"\n#include \"missing-query.dm\"\n",
    )
    .unwrap();
    let (failed, diagnostics) =
        run_captured(initial_request.clone(), &mut slot.lock_host().unwrap());
    assert_eq!(
        crate::request_failure::classify(failed.err().unwrap().as_ref()),
        crate::request_failure::FailureKind::Source
    );
    assert!(
        diagnostics
            .iter()
            .any(|line| line.contains("missing-query.dm")),
        "current missing include diagnostic must be captured"
    );
    let predecessor = query(&shared, original_pin.clone()).unwrap();
    assert_eq!(predecessor.revision, original.revision);
    assert_eq!(predecessor.source_revision, original.source_revision);
    assert_eq!(predecessor.snapshot_outcome, "published");
    assert_eq!(predecessor.last_request_outcome, "failed");
    assert!(predecessor.publication_pair.is_none());
    assert_prior_pair(&destination, &initial);

    // A complete new frontend followed by executable resolution failure issues
    // the CURRENT declaration/body snapshot, and cannot reuse predecessor pins.
    std::fs::write(&initial_request.project, "#include \"probe.dm\"\n").unwrap();
    let changed = SOURCE.replace("var/value = 7", "var/value = 9");
    roots.edit(
        0,
        &format!("{changed}/proc/rejected_query_body()\n    return missing_query_proc()\n"),
    );
    let (failed, diagnostics) =
        run_captured(initial_request.clone(), &mut slot.lock_host().unwrap());
    assert_eq!(
        crate::request_failure::classify(failed.err().unwrap().as_ref()),
        crate::request_failure::FailureKind::Source
    );
    assert!(diagnostics
        .iter()
        .any(|line| line.contains("missing_query_proc")));
    let current = query(&shared, discover.clone()).unwrap();
    assert_ne!(current.source_revision, original.source_revision);
    assert_eq!(current.snapshot_outcome, "frontend_analyzed_build_failed");
    assert_eq!(current.last_request_outcome, "failed");
    assert!(current.publication_pair.is_none());
    assert_eq!(
        query(&shared, original_pin.clone()).unwrap_err().kind,
        crate::request_failure::FailureKind::InvalidRequest
    );
    let current_pin = pin(&discover, &current);
    assert!(query(&shared, current_pin.clone())
        .unwrap()
        .jsonl
        .contains("rejected_query_body"));
    let mut body_request = current_pin.clone();
    body_request.source_queries = vec![SourceQuery::BodyContextsPage {
        start: 0,
        limit: 128,
    }];
    let body_page: serde_json::Value =
        serde_json::from_str(query(&shared, body_request.clone()).unwrap().jsonl.trim()).unwrap();
    let ordinal = body_page["total"].as_u64().unwrap() as u32 - 1;
    body_request.source_queries = vec![SourceQuery::BodyModel { ordinal }];
    let body = query(&shared, body_request).unwrap();
    assert!(body.jsonl.contains("missing_query_proc"));
    assert!(
        !body.complete,
        "source syntax must not claim complete resolved semantics"
    );
    assert_prior_pair(&destination, &initial);

    roots.edit(0, &changed);
    let (recovered, diagnostics) =
        run_captured(initial_request.clone(), &mut slot.lock_host().unwrap());
    assert!(diagnostics.is_empty());
    let recovered = published(recovered.unwrap(), &destination);
    assert_ne!(recovered.0, initial.0);
    let recovered_query = query(&shared, discover).unwrap();
    assert_eq!(recovered_query.snapshot_outcome, "published");
    assert_eq!(recovered_query.last_request_outcome, "published");
    assert_eq!(
        recovered_query.publication_pair.as_deref(),
        Some(recovered.0.name().as_str())
    );
    assert_eq!(
        query(&shared, current_pin).unwrap_err().kind,
        crate::request_failure::FailureKind::InvalidRequest
    );
    assert!(!query(
        &shared,
        pin(&query_request(&initial_request), &recovered_query)
    )
    .unwrap()
    .jsonl
    .contains("rejected_query_body"));
    assert_eq!(*shared.running.lock().unwrap(), 0);
    assert_eq!(*shared.workers.lock().unwrap(), 0);
    assert_eq!(shared.connections.load(Ordering::Acquire), 0);
}
