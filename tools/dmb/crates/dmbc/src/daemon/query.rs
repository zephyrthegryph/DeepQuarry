//! Bounded read-only queries against an existing retained semantic snapshot.
use serde::{Deserialize, Serialize};
#[path = "query/occurrence_pages.rs"]
mod occurrence_pages;
#[path = "query/selected_envelope.rs"]
mod selected_envelope;
mod semantic_pages;
pub mod semantic_client;
use std::{
    collections::BTreeMap,
    io::{self, Write},
    path::PathBuf,
};
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct QueryRequest {
    pub project: PathBuf,
    pub defines: BTreeMap<String, String>,
    pub engine_template: Option<PathBuf>,
    pub bootstrap_catalog: bool,
    /// Exact hexadecimal semantic revision. None explicitly discovers the current snapshot.
    pub expected_revision: Option<String>,
    pub queries: Vec<QueryItem>,
    #[serde(default)]
    pub expected_source_revision: Option<String>,
    #[serde(default)]
    pub source_queries: Vec<SourceQuery>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum SourceQuery {
    SemanticIntrinsicMembersPage {
        start: u32,
        limit: u32,
    },
    /// Dense semantic cursor belongs only to the explicitly pinned tree revision.
    SemanticTypesPage {
        start: u32,
        limit: u32,
    },
    SemanticMembersPage {
        start: u32,
        limit: u32,
    },
    /// Enumerate the current issued occurrence roster without a separate export.
    /// Cursor belongs only to both explicitly pinned revisions.
    OccurrencesPage {
        start: u32,
        limit: u32,
    },
    /// Only facts already issued by explicit analyze --resolved; never relowers.
    SelectedReferences {
        ordinal: u32,
    },
    /// Ordinal belongs only to the explicitly pinned current source revision.
    Occurrence {
        ordinal: u32,
    },
    Provenance {
        ordinal: u32,
    },
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct QueryItem {
    pub subject: Option<String>,
    pub query: dm_ir::ResolveQuery,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct QueryReply {
    pub schema: String,
    pub revision: String,
    pub complete: bool,
    pub coverage: String,
    pub query_count: usize,
    pub source_query_count: usize,
    pub source_revision: Option<String>,
    pub snapshot_outcome: String,
    pub last_request_outcome: String,
    pub publication_pair: Option<String>,
    pub jsonl: String,
}
/// Query an existing compatible daemon without starting, retiring or building it.
pub fn execute(mut request: QueryRequest) -> Result<QueryReply, Box<dyn std::error::Error>> {
    request.validate()?;
    let count = request.queries.len();
    let expected = request.expected_revision.clone();
    let source_count = request.source_queries.len();
    let expected_source = request.expected_source_revision.clone();
    let source_questions = request.source_queries.clone();
    let cwd = std::env::current_dir()?;
    if !request.project.is_absolute() {
        request.project = cwd.join(&request.project);
    }
    if let Some(engine) = &mut request.engine_template {
        if !engine.is_absolute() {
            *engine = cwd.join(&*engine);
        }
    }
    let endpoint = super::transport::Endpoint::current()?;
    let mut stream = super::transport::connect(&endpoint)?;
    super::transport::set_timeout(&mut stream, std::time::Duration::from_secs(20))?;
    let compiler = super::compiler_identity()?;
    super::protocol::send(
        &mut stream,
        &super::protocol::Request::Hello {
            version: super::protocol::VERSION,
            compiler,
        },
    )?;
    match super::protocol::receive::<super::protocol::Reply>(&mut stream)? {
        super::protocol::Reply::Hello {
            version,
            compiler: remote,
            retiring: false,
        } if version == super::protocol::VERSION && remote == compiler => {}
        _ => return Err("read-only query requires an existing compatible active daemon".into()),
    }
    super::protocol::send(&mut stream, &super::protocol::Request::Query(request))?;
    match super::protocol::receive_bounded::<super::protocol::Reply>(
        &mut stream,
        MAX_OUTPUT * 6 + 4096,
    )? {
        super::protocol::Reply::Query(reply) => {
            validate_reply(
                &reply,
                count,
                source_count,
                expected.as_deref(),
                expected_source.as_deref(),
            )?;
            occurrence_pages::validate_requested(&reply, &source_questions)?;
            semantic_pages::validate_requested(&reply, &source_questions)?;
            Ok(reply)
        }
        super::protocol::Reply::Rejected(error) => Err(error.into()),
        _ => Err("unexpected read-only query reply".into()),
    }
}
fn validate_reply(
    reply: &QueryReply,
    count: usize,
    source_count: usize,
    expected: Option<&str>,
    expected_source: Option<&str>,
) -> io::Result<()> {
    if reply.schema != "dm-session-query-v2"
        || reply.complete
        || reply.query_count != count
        || reply.source_query_count != source_count
        || reply.snapshot_outcome.len() > 128
        || reply.last_request_outcome.len() > 128
        || reply.publication_pair.as_ref().is_some_and(|pair| {
            pair.len() != 32 || !pair.bytes().all(|byte| byte.is_ascii_hexdigit())
        })
        || (reply.publication_pair.is_some() && reply.last_request_outcome != "published")
        || reply.source_revision.as_ref().is_some_and(|revision| {
            revision.len() != 32 || !revision.bytes().all(|byte| byte.is_ascii_hexdigit())
        })
        || expected_source.is_some_and(|expected| {
            !reply
                .source_revision
                .as_ref()
                .is_some_and(|revision| expected.eq_ignore_ascii_case(revision))
        })
        || reply.jsonl.len() > MAX_OUTPUT
        || reply.coverage.len() > 1024
        || reply.revision.len() != 32
        || !reply.revision.bytes().all(|byte| byte.is_ascii_hexdigit())
        || expected.is_some_and(|expected| !expected.eq_ignore_ascii_case(&reply.revision))
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "invalid bounded query reply",
        ));
    }
    let (mut rows, mut source_rows) = (0, 0);
    for line in reply.jsonl.lines() {
        let row: serde_json::Value = serde_json::from_str(line).map_err(io::Error::other)?;
        if row["row"] == "semantic_types_page"
            || row["row"] == "semantic_members_page"
            || row["row"] == "semantic_intrinsic_members_page"
        {
            semantic_pages::validate(&row, &reply.revision)?;
            source_rows += 1;
            continue;
        }
        if row["row"] == "source_occurrences_page" {
            occurrence_pages::validate(&row, reply.source_revision.as_deref())?;
            source_rows += 1;
            continue;
        }
        if row["row"] == "source_selected_references" {
            selected_envelope::validate(&row, reply.source_revision.as_deref())?;
            source_rows += 1;
            continue;
        }
        if (row["row"] == "source_occurrence" || row["row"] == "source_provenance")
            && row["schema"] == "dm-session-source-query-v1"
        {
            if row["source_revision"].as_str() != reply.source_revision.as_deref() {
                return Err(io::Error::other("source answer revision mismatch"));
            }
            source_rows += 1;
            continue;
        }
        if row["row"] != "resolved_query" || row["schema"] != "dm-resolved-query-v1" {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "invalid query answer row",
            ));
        }
        rows += 1;
    }
    if rows != count || source_rows != source_count {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "query answer count mismatch",
        ));
    }
    Ok(())
}
/// File input and response output are bounded independently of transport framing.
pub fn run_file(path: &std::path::Path, jsonl: bool) -> Result<(), Box<dyn std::error::Error>> {
    use std::io::Read;
    let mut bytes = Vec::new();
    std::fs::File::open(path)?
        .take((MAX_REQUEST + 1) as u64)
        .read_to_end(&mut bytes)?;
    if bytes.len() > MAX_REQUEST {
        return Err("query request file exceeds 64 KiB".into());
    }
    let reply = execute(serde_json::from_slice(&bytes)?)?;
    let mut output = std::io::stdout().lock();
    if jsonl {
        serde_json::to_writer(
            &mut output,
            &serde_json::json!({"row":"query_batch","schema":reply.schema,"revision":reply.revision,"complete":reply.complete,"coverage":reply.coverage,"query_count":reply.query_count,"source_query_count":reply.source_query_count,"source_revision":reply.source_revision,"snapshot_outcome":reply.snapshot_outcome,"last_request_outcome":reply.last_request_outcome,"publication_pair":reply.publication_pair}),
        )?;
        output.write_all(b"\n")?;
        output.write_all(reply.jsonl.as_bytes())?;
    } else {
        serde_json::to_writer(&mut output, &reply)?;
        output.write_all(b"\n")?;
    }
    output.flush()?;
    Ok(())
}
const MAX_QUERIES: usize = 128;
const MAX_REQUEST: usize = 65536;
pub(crate) const MAX_OUTPUT: usize = 524288;
impl QueryRequest {
    pub(super) fn validate(&self) -> io::Result<()> {
        if self.queries.len().saturating_add(self.source_queries.len()) > MAX_QUERIES
            || self.queries.iter().any(|query| {
                query
                    .subject
                    .as_ref()
                    .is_some_and(|subject| subject.len() > 256)
            })
        {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "query batch exceeds count or subject limit",
            ));
        }
        if self.source_queries.iter().any(|query| matches!(query, SourceQuery::OccurrencesPage { limit, .. } if !(1..=128).contains(limit))) {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "occurrence page limit must be 1..128"));
        }
        if serde_json::to_vec(self).map_err(io::Error::other)?.len() > MAX_REQUEST {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "query batch exceeds 64 KiB",
            ));
        }
        semantic_pages::validate_request(self)?;
        if self
            .source_queries
            .iter()
            .any(|query| !semantic_pages::is_semantic(query))
            && (self.expected_revision.is_none() || self.expected_source_revision.is_none())
        {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "source queries require both semantic and source revision pins",
            ));
        }
        if [
            self.expected_revision.as_ref(),
            self.expected_source_revision.as_ref(),
        ]
        .into_iter()
        .flatten()
        .any(|revision| {
            revision.len() != 32 || !revision.bytes().all(|byte| byte.is_ascii_hexdigit())
        }) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "query revision must be 32 hexadecimal digits",
            ));
        }
        Ok(())
    }
}
struct BoundedOutput(Vec<u8>);
impl Write for BoundedOutput {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        if bytes.len() > MAX_OUTPUT.saturating_sub(self.0.len()) {
            return Err(io::Error::other("query response exceeds 512 KiB"));
        }
        self.0.extend_from_slice(bytes);
        Ok(bytes.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}
#[cfg(test)]
pub(super) fn evaluate(
    request: &QueryRequest,
    tree: &dm_tree::SemanticTree,
) -> io::Result<QueryReply> {
    evaluate_snapshot(request, tree, &Default::default())
}
pub(super) fn evaluate_snapshot(
    request: &QueryRequest,
    tree: &dm_tree::SemanticTree,
    state: &crate::runner_host::query_snapshot::QueryState,
) -> io::Result<QueryReply> {
    request.validate()?;
    let revision = format!("{:032x}", tree.identity());
    if request
        .expected_revision
        .as_ref()
        .is_some_and(|expected| !expected.eq_ignore_ascii_case(&revision))
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "retained query revision is stale",
        ));
    }
    let snapshot = state
        .snapshot
        .as_ref()
        .filter(|snapshot| snapshot.matches_tree(tree));
    let source_revision = snapshot.map(|snapshot| format!("{:032x}", snapshot.source_revision));
    if request
        .expected_source_revision
        .as_ref()
        .is_some_and(|expected| {
            !source_revision
                .as_ref()
                .is_some_and(|current| expected.eq_ignore_ascii_case(current))
        })
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "retained source query revision is stale or unavailable",
        ));
    }
    let mut output = BoundedOutput(Vec::new());
    for query in &request.queries {
        super::control::checkpoint()?;
        dm_analysis::tree_export::write_queries_jsonl(
            tree.symbols(),
            tree,
            [dm_analysis::tree_export::AnalysisQuery {
                subject: query.subject.as_deref(),
                query: query.query,
            }],
            &mut output,
        )
        .map_err(io::Error::other)?;
    }
    for question in &request.source_queries {
        super::control::checkpoint()?;
        if semantic_pages::write(question, tree, &mut output)? {
            continue;
        }
        let snapshot = snapshot.ok_or_else(|| {
            io::Error::new(io::ErrorKind::NotFound, "source snapshot unavailable")
        })?;
        if let SourceQuery::OccurrencesPage { start, limit } = question {
            snapshot.write_occurrences_page(*start, *limit, tree, &mut output)?;
            continue;
        }
        if let SourceQuery::SelectedReferences { ordinal } = question {
            snapshot.write_selected(*ordinal, &mut output)?;
            continue;
        }
        let (ordinal, provenance) = match question {
            SourceQuery::Occurrence { ordinal } => (*ordinal, false),
            SourceQuery::Provenance { ordinal } => (*ordinal, true),
            SourceQuery::SelectedReferences { .. }
            | SourceQuery::OccurrencesPage { .. }
            | SourceQuery::SemanticTypesPage { .. }
            | SourceQuery::SemanticMembersPage { .. }
            | SourceQuery::SemanticIntrinsicMembersPage { .. } => {
                unreachable!("handled above")
            }
        };
        let mut row = snapshot.occurrence(ordinal, tree)?;
        if provenance {
            row["row"] = "source_provenance".into();
        }
        serde_json::to_writer(&mut output, &row).map_err(io::Error::other)?;
        output.write_all(b"\n")?;
    }
    Ok(QueryReply {
        schema: "dm-session-query-v2".into(), revision, complete: false,
        coverage: "semantic tree and bounded revision-pinned semantic type/authored member-node/captured intrinsic roster selectors (intrinsic completeness explicit; inherited effective lookup uses parent links and Resolver, not an expanded roster) plus caller-selected issued declaration occurrences and source/definition spans; bounded previously captured compiler-selected references only; complete executable resolution, full macro traces and pinned resource/runtime host facts excluded".into(),
        query_count: request.queries.len(), source_query_count: request.source_queries.len(), source_revision,
        snapshot_outcome: snapshot.map_or("semantic_snapshot_only", |snapshot| snapshot.outcome).into(),
        last_request_outcome: state.last_request_outcome.into(),
        publication_pair: state.publication_pair.clone(),
        jsonl: String::from_utf8(output.0).map_err(io::Error::other)?,
    })
}
#[cfg(test)]
mod tests {
    use super::*;
    fn request() -> QueryRequest {
        QueryRequest {
            project: "fixture.dme".into(),
            defines: BTreeMap::new(),
            engine_template: None,
            bootstrap_catalog: false,
            expected_revision: None,
            queries: vec![],
            expected_source_revision: None,
            source_queries: vec![],
        }
    }
    #[test]
    fn source_pin_changes_on_shift_and_outcomes_follow_actual_request_completion() {
        use crate::runner_host::query_snapshot::{QueryAttempt, QueryState};
        use std::sync::{Arc, Mutex};
        struct Source(&'static str);
        impl dm_preprocess::SourceProvider for Source {
            fn read(&self, _: &std::path::Path) -> Result<String, String> {
                Ok(self.0.into())
            }
        }
        let build = |text| {
            dm_tree::frontend::build_with_config(
                std::path::Path::new("fixture.dme"),
                &Source(text),
                &Default::default(),
                dm_tree::frontend::FrontendConfig {
                    workers: 1,
                    engine: None,
                    observer: None,
                },
            )
            .unwrap()
        };
        let original = build("/datum/example\n    var/value = 7\n");
        let shifted =
            build("// changed current source coordinates\n/datum/example\n    var/value = 7\n");
        assert_eq!(
            original.snapshot.tree.identity(),
            shifted.snapshot.tree.identity()
        );
        assert_ne!(
            dm_analysis::tree_export::source_revision(&original),
            dm_analysis::tree_export::source_revision(&shifted)
        );
        let state = Arc::new(Mutex::new(QueryState::default()));
        let mut attempt = QueryAttempt::new(Arc::clone(&state), true);
        attempt.capture(&original);
        let pair = crate::publish::OutputPair::from_bytes(b"fixture-dmb", b"fixture-rsc");
        attempt.finish_published(&pair);
        drop(attempt);
        let mut value = request();
        value.expected_revision = Some(format!("{:032x}", original.snapshot.tree.identity()));
        value.expected_source_revision = Some(format!(
            "{:032x}",
            dm_analysis::tree_export::source_revision(&original)
        ));
        value.source_queries = vec![SourceQuery::Occurrence { ordinal: 0 }];
        let old =
            evaluate_snapshot(&value, &original.snapshot.tree, &state.lock().unwrap()).unwrap();
        assert_eq!(old.snapshot_outcome, "published");
        assert_eq!(old.publication_pair.as_deref(), Some(pair.name().as_str()));
        validate_reply(
            &old,
            0,
            1,
            value.expected_revision.as_deref(),
            value.expected_source_revision.as_deref(),
        )
        .unwrap();
        {
            let mut failed = QueryAttempt::new(Arc::clone(&state), true);
            failed.capture(&shifted);
            // Simulates ABI/lowering failure after the admitted frontend.
        }
        assert!(evaluate_snapshot(&value, &shifted.snapshot.tree, &state.lock().unwrap()).is_err());
        value.expected_source_revision = Some(format!(
            "{:032x}",
            dm_analysis::tree_export::source_revision(&shifted)
        ));
        let current =
            evaluate_snapshot(&value, &shifted.snapshot.tree, &state.lock().unwrap()).unwrap();
        assert_eq!(current.snapshot_outcome, "frontend_analyzed_build_failed");
        assert_eq!(current.last_request_outcome, "failed");
        assert!(current.publication_pair.is_none());
        // Equal semantic hashes on independently issued trees cannot bind current source rows.
        assert!(
            evaluate_snapshot(&value, &original.snapshot.tree, &state.lock().unwrap()).is_err()
        );
        value
            .source_queries
            .push(SourceQuery::Provenance { ordinal: 0 });
        let both =
            evaluate_snapshot(&value, &shifted.snapshot.tree, &state.lock().unwrap()).unwrap();
        validate_reply(
            &both,
            0,
            2,
            value.expected_revision.as_deref(),
            value.expected_source_revision.as_deref(),
        )
        .unwrap();
        let rows = both
            .jsonl
            .lines()
            .map(|line| serde_json::from_str::<serde_json::Value>(line).unwrap())
            .collect::<Vec<_>>();
        assert_eq!(rows[0]["row"], "source_occurrence");
        assert_eq!(rows[1]["row"], "source_provenance");
        assert_eq!(rows[0]["target"], rows[1]["target"]);
        assert_eq!(rows[0]["start"], rows[1]["start"]);
        assert_eq!(rows[0]["definition_origins"], rows[1]["definition_origins"]);
        let old_row: serde_json::Value = serde_json::from_str(old.jsonl.trim()).unwrap();
        let current_row: serde_json::Value = serde_json::from_str(current.jsonl.trim()).unwrap();
        assert!(current_row["start"].as_u64().unwrap() > old_row["start"].as_u64().unwrap());
        let mut exported = Vec::new();
        dm_analysis::tree_export::write_jsonl(&shifted, &mut exported).unwrap();
        let metadata: serde_json::Value =
            serde_json::from_slice(exported.split(|byte| *byte == b'\n').next().unwrap()).unwrap();
        assert_eq!(metadata["semantic_revision"], current.revision);
        assert_eq!(
            metadata["source_revision"],
            current.source_revision.as_deref().unwrap()
        );
        value.expected_source_revision = None;
        assert!(value.validate().is_err());
        value.expected_source_revision = current.source_revision;
        value.source_queries = vec![SourceQuery::Occurrence { ordinal: u32::MAX }];
        assert!(evaluate_snapshot(&value, &shifted.snapshot.tree, &state.lock().unwrap()).is_err());
        value.source_queries.clear();
        value.expected_source_revision = None;
        let asset_changed_pair =
            crate::publish::OutputPair::from_bytes(b"fixture-dmb", b"changed-fixture-rsc");
        assert_ne!(pair.id, asset_changed_pair.id);
        let mut output_only = QueryAttempt::new(Arc::clone(&state), true);
        output_only.finish_published(&asset_changed_pair);
        drop(output_only);
        let replayed =
            evaluate_snapshot(&value, &shifted.snapshot.tree, &state.lock().unwrap()).unwrap();
        assert_eq!(replayed.last_request_outcome, "published");
        assert_eq!(
            replayed.publication_pair.as_deref(),
            Some(asset_changed_pair.name().as_str())
        );
        assert!(replayed.source_revision.is_none());
        assert_eq!(replayed.snapshot_outcome, "semantic_snapshot_only");
    }
    #[test]
    fn provenance_selection_uses_same_issued_row_and_rejects_unpinned_source() {
        let mut value = request();
        value.source_queries = vec![SourceQuery::Provenance { ordinal: 0 }];
        assert!(value.validate().is_err());
        value.expected_revision = Some("0".repeat(32));
        value.expected_source_revision = Some("1".repeat(32));
        value.validate().unwrap();
    }
    #[test]
    fn bounds_reject_count_wide_revision_and_output_overflow() {
        let mut value = request();
        value.queries = vec![
            QueryItem {
                subject: None,
                query: dm_ir::ResolveQuery::Type(dm_ir::SymbolId::of("/datum"))
            };
            129
        ];
        assert!(value.validate().is_err());
        value.queries.clear();
        value.expected_revision = Some("wrong".into());
        assert!(value.validate().is_err());
        let mut output = BoundedOutput(Vec::new());
        output.write_all(&vec![0; MAX_OUTPUT]).unwrap();
        assert!(output.write_all(&[1]).is_err());
        assert_eq!(output.0.len(), MAX_OUTPUT);
    }
    #[test]
    fn batch_uses_current_tree_answers_and_rejects_stale_revision() {
        struct Source;
        impl dm_preprocess::SourceProvider for Source {
            fn read(&self, _: &std::path::Path) -> Result<String, String> {
                Ok("/datum/example\n    var/value = 7\n".into())
            }
        }
        let front = dm_tree::frontend::build_with_config(
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
        let tree = &front.snapshot.tree;
        let mut value = request();
        value.expected_revision = Some(format!("{:032x}", tree.identity()));
        value.queries = vec![
            QueryItem {
                subject: Some("absence".into()),
                query: dm_ir::ResolveQuery::HasMemberVar {
                    owner: dm_ir::SymbolId::of("/datum/example"),
                    name: dm_ir::SymbolId::of("absent"),
                },
            },
            QueryItem {
                subject: Some("authored type".into()),
                query: dm_ir::ResolveQuery::Type(dm_ir::SymbolId::of("/datum/example")),
            },
        ];
        let reply = evaluate(&value, tree).unwrap();
        assert!(!reply.complete);
        assert_eq!(reply.query_count, 2);
        let rows = reply
            .jsonl
            .lines()
            .map(|line| serde_json::from_str::<serde_json::Value>(line).unwrap())
            .collect::<Vec<_>>();
        // Without the engine ancestry, absence is uncertain; it must not become false.
        assert_eq!(rows[0]["answer"]["status"], "unsupported");
        assert_eq!(rows[1]["answer"]["status"], "known");
        value.expected_revision = Some(format!("{:032x}", tree.identity() ^ 1));
        assert!(evaluate(&value, tree)
            .unwrap_err()
            .to_string()
            .contains("stale"));
    }
    #[test]
    fn remote_reply_limits_and_coverage_are_rechecked() {
        let mut reply = QueryReply {
            schema: "dm-session-query-v2".into(),
            revision: "0".repeat(32),
            complete: false,
            coverage: "partial".into(),
            query_count: 0,
            source_query_count: 0,
            source_revision: None,
            snapshot_outcome: "semantic_snapshot_only".into(),
            last_request_outcome: "unknown".into(),
            publication_pair: None,
            jsonl: String::new(),
        };
        validate_reply(&reply, 0, 0, None, None).unwrap();
        reply.complete = true;
        assert!(validate_reply(&reply, 0, 0, None, None).is_err());
        reply.complete = false;
        reply.jsonl = " ".repeat(MAX_OUTPUT + 1);
        assert!(validate_reply(&reply, 0, 0, None, None).is_err());
        reply.jsonl.clear();
        reply.query_count = 1;
        assert!(validate_reply(&reply, 1, 0, None, None).is_err());
    }
}

#[cfg(test)]
#[path = "query/selected_tests.rs"]
mod selected_tests;

#[cfg(test)]
#[path = "query/occurrence_pages_tests.rs"]
mod occurrence_pages_tests;
