//! Bounded read-only queries against an existing retained semantic snapshot.
use serde::{Deserialize, Serialize};
mod analyze_policy;
mod control_batch;
mod effect_reports;
pub mod encoded_bytes;
mod effect_report_bytes;
mod generator_bytes;
mod named_policy;
#[cfg(test)]
#[path = "query/native_outer_tests.rs"]
mod native_outer_tests;
mod native_policy;
#[path = "query/occurrence_pages.rs"]
mod occurrence_pages;
#[cfg(test)]
#[path = "query/policy_revision_shape_tests.rs"]
mod policy_revision_shape_tests;
mod raw_policy;
#[path = "query/selected_envelope.rs"]
mod selected_envelope;
pub mod semantic_client;
mod semantic_pages;
mod variable_visibility;
mod workspace_policy;
use std::{
    collections::BTreeMap,
    io::{self, Write},
    path::PathBuf,
};
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct QueryRequest {
    /// Request budget after the generation handshake; absent preserves 20 seconds.
    #[serde(default)]
    pub timeout_seconds: Option<u16>,
    pub project: PathBuf,
    pub defines: BTreeMap<String, String>,
    pub engine_template: Option<PathBuf>,
    pub bootstrap_catalog: bool,
    /// Exact hexadecimal semantic revision. None explicitly discovers the current snapshot.
    pub expected_revision: Option<String>,
    pub queries: Vec<QueryItem>,
    #[serde(default)]
    pub expected_source_revision: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expected_policy_revision: Option<String>,
    #[serde(default)]
    pub source_queries: Vec<SourceQuery>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum SourceQuery {
    /// SAME current compiler host facts; both semantic/source revisions required.
    ResolvedQueries {
        queries: Vec<QueryItem>,
    },
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
    /// Current issued source envelopes/settings context, not executable syntax.
    BodyContextsPage {
        start: u32,
        limit: u32,
    },
    /// Lazily parse one exact currently issued body; both revision pins required.
    BodyModel {
        ordinal: u32,
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
    /// Migration-only policy findings, NOT complete checker coverage. The body
    /// is consumed in-process from the compiler archive; only findings cross IPC.
    NativeUntypedFixture {
        root: PathBuf,
    },
    /// Raw-only legacy policy over exact captured files/config; never a complete workspace.
    NativeRawPolicyFixture {
        root: PathBuf,
        configuration: PathBuf,
        lints: Vec<String>,
    },

    /// Raw-only typed discovery, bound to the current exact workspace policy pin.
    NativeWorkspaceRawPolicy {
        root: PathBuf,
        configuration: PathBuf,
        lints: Vec<String>,
        cursor: Option<crate::query_db::WorkspaceCursor>,
        limit: usize,
    },
    /// Explicit typed-policy fixture only, not production workspace admission.
    NativeAnalyzePolicyFixture {
        root: PathBuf,
        configuration: PathBuf,
        lints: Vec<String>,
    },
    NativeCheckerFixture {
        ordinal: u32,
        severity: String,
    },
    /// One migrated complete named rule over explicitly captured declarations;
    /// never the complete Analyze lint, baseline judgement or workspace inventory.
    NativeNamedRule {
        root: PathBuf,
        lint: String,
        rule: String,
        configuration: PathBuf,
    },
    /// One migrated body family with the complete pinned checker config schema.
    /// Exact configuration bytes/absence must be in the captured policy revision.
    /// One exact configured control-family union: one primary walk, event order.
    /// Request-local projection only; no persistent flow cache or full checker claim.
    NativeConfiguredControlBatch {
        ordinal: u32,
        families: Vec<String>,
        environment: PathBuf,
        configuration: Option<PathBuf>,
    },
    NativeConfiguredChecker {
        ordinal: u32,
        family: String,
        environment: PathBuf,
        configuration: Option<PathBuf>,
    },
    /// Exhaust both effect judgements over all original targets with the exact
    /// captured config. Other checker endpoints retain their existing roles.
    NativeEffectReports { environment:PathBuf, configuration:Option<PathBuf>, page_width:u32, target_window:u32 },
    NativeEffectReportBytes { environment:PathBuf, configuration:Option<PathBuf>, page_width:u32, target_window:u32, cursor:Option<encoded_bytes::ByteCursor>, limit:u32 },
    /// Full final generator artifact, only for a question admitted at preparation.
    NativeGeneratorBytes { #[serde(with="generator_bytes::name")] generator:crate::GeneratorName, cursor:Option<encoded_bytes::ByteCursor>, limit:u32 },
    /// All variable-visibility producer categories, not a per-body tag subset.
    NativeConfiguredVariableVisibility {
        environment: PathBuf,
        configuration: Option<PathBuf>,
    },
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
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
    /// Last admitted captured source, not an assertion about live filesystem
    /// bytes. A failed newer frontend may leave this predecessor queryable.
    pub source_revision: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub policy_revision: Option<String>,
    /// Outcome of the source/semantic capture answering this query.
    pub snapshot_outcome: String,
    /// Outcome of the latest attempted request, independently of its snapshot.
    pub last_request_outcome: String,
    /// Pair published by the latest request only. None after failure/analysis
    /// does not mean a previously published conventional pair was removed.
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
    let expected_policy = request.expected_policy_revision.clone();
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
    let compiler = super::compiler_identity()?;
    let endpoint = super::transport::Endpoint::generation(compiler)?;
    let mut stream = super::transport::connect(&endpoint)?;
    super::transport::set_timeout(&mut stream, std::time::Duration::from_secs(20))?;
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
    super::transport::set_timeout(&mut stream, request.timeout()?)?;
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
            if expected_policy.as_ref().is_some_and(|expected| {
                !reply
                    .policy_revision
                    .as_ref()
                    .is_some_and(|current| expected.eq_ignore_ascii_case(current))
            }) {
                return Err("retained policy query revision mismatch".into());
            }
            if reply.policy_revision.is_some()
                && expected_policy.is_none()
                && source_questions.iter().any(|query| {
                    matches!(query, SourceQuery::NativeUntypedFixture { .. })
                        || named_policy::reads_policy(query)
                        || control_batch::reads_policy(query)
                        || effect_reports::reads_policy(query)
                        || effect_report_bytes::reads_policy(query)
                        || generator_bytes::reads_policy(query)
                        || variable_visibility::reads_policy(query)
                        || raw_policy::reads_policy(query)
                        || workspace_policy::reads_policy(query)
                        || analyze_policy::reads_policy(query)
                })
            {
                return Err("explicit-policy result requires its requested policy pin".into());
            }
            validate_body_requests(&reply, &source_questions)?;
            native_policy::validate_requested(&reply, &source_questions)?;
            named_policy::validate_requested(&reply, &source_questions)?;
            control_batch::validate_requested(&reply, &source_questions)?;
            effect_reports::validate_requested(&reply,&source_questions)?;effect_report_bytes::validate_requested(&reply,&source_questions)?;generator_bytes::validate_requested(&reply,&source_questions)?;
            variable_visibility::validate_requested(&reply, &source_questions)?;
            raw_policy::validate_requested(&reply, &source_questions)?;
            workspace_policy::validate_requested(&reply, &source_questions)?;
            analyze_policy::validate_requested(&reply, &source_questions)?;
            validate_resolved_requests(&reply, &source_questions)?;
            occurrence_pages::validate_requested(&reply, &source_questions)?;
            semantic_pages::validate_requested(&reply, &source_questions)?;
            Ok(reply)
        }
        super::protocol::Reply::Rejected(error) => Err(error.into()),
        _ => Err("unexpected read-only query reply".into()),
    }
}
fn validate_resolved_requests(reply: &QueryReply, questions: &[SourceQuery]) -> io::Result<()> {
    let mut expected = questions.iter().filter_map(|question| match question {
        SourceQuery::ResolvedQueries { queries } => Some(queries),
        _ => None,
    });
    for line in reply.jsonl.lines() {
        let row: serde_json::Value = serde_json::from_str(line).map_err(io::Error::other)?;
        if row["row"] != "source_resolved_queries" {
            continue;
        }
        let queries = expected
            .next()
            .ok_or_else(|| io::Error::other("unrequested resolved batch"))?;
        let nested = row["captured_jsonl"]
            .as_str()
            .ok_or_else(|| io::Error::other("missing resolved batch"))?;
        if nested.lines().count() != queries.len() {
            return Err(io::Error::other("resolved request count differs"));
        }
        for (line, query) in nested.lines().zip(queries) {
            let row: serde_json::Value = serde_json::from_str(line).map_err(io::Error::other)?;
            if row["query_wire"].as_str()
                != Some(
                    serde_json::to_string(&query.query)
                        .map_err(io::Error::other)?
                        .as_str(),
                )
                || row["subject"].as_str() != query.subject.as_deref()
            {
                return Err(io::Error::other("resolved request identity differs"));
            }
        }
    }
    if expected.next().is_some() {
        return Err(io::Error::other("resolved batch missing"));
    }
    Ok(())
}
fn validate_body_requests(reply: &QueryReply, questions: &[SourceQuery]) -> io::Result<()> {
    let mut expected = questions.iter().filter_map(|q| match q {
        SourceQuery::BodyModel { ordinal } => Some(*ordinal),
        _ => None,
    });
    for line in reply.jsonl.lines() {
        let row: serde_json::Value = serde_json::from_str(line).map_err(io::Error::other)?;
        if row["row"] == "source_body_model"
            && expected.next().map(u64::from) != row["ordinal"].as_u64()
        {
            return Err(io::Error::other("body query response ordinal mismatch"));
        }
    }
    if expected.next().is_some() {
        return Err(io::Error::other("body query response missing"));
    }
    Ok(())
}
/// Describe scalar result-envelope metadata only. This is NOT request authority
/// and never reconstructs a semantic model. execute() separately checks every
/// row against the real requested roster after this outer shape/count admission.
fn native_row_descriptor(row: &serde_json::Value) -> io::Result<Option<SourceQuery>> {
    let path = |name: &str| -> io::Result<PathBuf> {
        serde_json::from_value(row[name].clone()).map_err(|_| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                format!("invalid native {name} path"),
            )
        })
    };
    let text = |name: &str| -> io::Result<String> {
        row[name].as_str().map(str::to_owned).ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                format!("invalid native {name} text"),
            )
        })
    };
    let ordinal = || -> io::Result<u32> {
        row["ordinal"]
            .as_u64()
            .and_then(|value| u32::try_from(value).ok())
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "invalid native ordinal"))
    };
    let configuration = || -> io::Result<Option<PathBuf>> {
        match row["configuration_explicit"].as_bool() {
            Some(true) => path("configuration").map(Some),
            Some(false) => Ok(None),
            None => Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "invalid native configuration selection",
            )),
        }
    };
    Ok(Some(match row["row"].as_str() {
        Some("source_native_untyped_fixture") => SourceQuery::NativeUntypedFixture {
            root: path("root")?,
        },
        Some("source_native_checker_fixture") => SourceQuery::NativeCheckerFixture {
            ordinal: ordinal()?,
            severity: text("policy")?,
        },
        Some("source_native_raw_policy_fixture") => SourceQuery::NativeRawPolicyFixture {
            root: path("root")?,
            configuration: path("configuration")?,
            lints: serde_json::from_value(row["requested_lints"].clone()).map_err(|_| {
                io::Error::new(io::ErrorKind::InvalidData, "invalid native lint roster")
            })?,
        },
        Some("source_native_workspace_raw_policy") => SourceQuery::NativeWorkspaceRawPolicy {
            root: path("root")?,
            configuration: path("configuration")?,
            cursor: if row["offset"].as_u64().unwrap_or(0) == 0 {
                None
            } else {
                Some(serde_json::from_value(serde_json::json!({"aggregate_id":row["aggregate_id"],"offset":row["offset"]})).map_err(|_| io::Error::new(io::ErrorKind::InvalidData,"invalid workspace continuation schema"))?)
            },
            limit: 128,
            lints: serde_json::from_value(row["requested_lints"].clone()).map_err(|_| {
                io::Error::new(io::ErrorKind::InvalidData, "invalid workspace lint roster")
            })?,
        },
        Some("source_native_analyze_policy_fixture") => SourceQuery::NativeAnalyzePolicyFixture {
            root: path("root")?,
            configuration: path("configuration")?,
            lints: serde_json::from_value(row["requested_lints"].clone()).map_err(|_| {
                io::Error::new(io::ErrorKind::InvalidData, "invalid native lint roster")
            })?,
        },
        Some("source_native_named_rule") => SourceQuery::NativeNamedRule {
            root: path("root")?,
            lint: text("lint")?,
            rule: text("rule")?,
            configuration: path("configuration")?,
        },
        Some("source_native_configured_variable_visibility") => {
            SourceQuery::NativeConfiguredVariableVisibility {
                environment: path("environment")?,
                configuration: configuration()?,
            }
        }
        Some("source_native_effect_report_bytes") => SourceQuery::NativeEffectReportBytes{environment:path("environment")?,configuration:configuration()?,page_width:effect_reports::row_u32(row,"page_width")?,target_window:effect_reports::row_u32(row,"target_window")?,cursor:effect_report_bytes::cursor(row,"requested_cursor")?,limit:effect_reports::row_u32(row,"limit")?},
        Some("source_native_generator_bytes") => SourceQuery::NativeGeneratorBytes{generator:serde_json::from_value(row["generator"].clone()).map_err(io::Error::other)?,cursor:effect_report_bytes::cursor(row,"requested_cursor")?,limit:effect_reports::row_u32(row,"limit")?},
        Some("source_native_effect_reports") => SourceQuery::NativeEffectReports { environment:path("environment")?,configuration:configuration()?,page_width:effect_reports::row_u32(row,"page_width")?,target_window:effect_reports::row_u32(row,"target_window")? },
        Some("source_native_configured_checker") => SourceQuery::NativeConfiguredChecker {
            ordinal: ordinal()?,
            family: text("family")?,
            environment: path("environment")?,
            configuration: configuration()?,
        },
        Some("source_native_configured_control_batch") => {
            SourceQuery::NativeConfiguredControlBatch {
                ordinal: ordinal()?,
                environment: path("environment")?,
                configuration: configuration()?,
                families: serde_json::from_value(row["families"].clone()).map_err(|_| {
                    io::Error::new(
                        io::ErrorKind::InvalidData,
                        "invalid native control family roster",
                    )
                })?,
            }
        }
        _ => return Ok(None),
    }))
}
/// Reuse the exact cohort validators instead of duplicating their evolving
/// schemas/raw-scope rules here. The one-row descriptor grants shape admission
/// only; a foreign/missing/extra requested row is still rejected by execute().
fn validate_native_outer_row(
    reply: &QueryReply,
    row: &serde_json::Value,
    question: SourceQuery,
) -> io::Result<()> {
    let shape = QueryRequest {
        timeout_seconds: None,
        project: PathBuf::new(),
        defines: BTreeMap::new(),
        engine_template: None,
        bootstrap_catalog: false,
        expected_revision: Some(reply.revision.clone()),
        expected_source_revision: reply.source_revision.clone(),
        expected_policy_revision: reply.policy_revision.clone(),
        queries: Vec::new(),
        source_queries: vec![question],
    };
    shape.validate().map_err(|error| {
        io::Error::new(
            io::ErrorKind::InvalidData,
            format!("invalid native row metadata: {error}"),
        )
    })?;
    let single = QueryReply {
        schema: reply.schema.clone(),
        revision: reply.revision.clone(),
        complete: reply.complete,
        coverage: reply.coverage.clone(),
        query_count: 0,
        source_query_count: 1,
        source_revision: reply.source_revision.clone(),
        policy_revision: reply.policy_revision.clone(),
        snapshot_outcome: reply.snapshot_outcome.clone(),
        last_request_outcome: reply.last_request_outcome.clone(),
        publication_pair: reply.publication_pair.clone(),
        jsonl: serde_json::to_string(row).map_err(io::Error::other)?,
    };
    native_policy::validate_requested(&single, &shape.source_queries)?;
    named_policy::validate_requested(&single, &shape.source_queries)?;
    control_batch::validate_requested(&single, &shape.source_queries)?;
    effect_reports::validate_requested(&single,&shape.source_queries)?;effect_report_bytes::validate_requested(&single,&shape.source_queries)?;generator_bytes::validate_requested(&single,&shape.source_queries)?;
    variable_visibility::validate_requested(&single, &shape.source_queries)?;
    raw_policy::validate_requested(&single, &shape.source_queries)?;
    workspace_policy::validate_requested(&single, &shape.source_queries)?;
    analyze_policy::validate_requested(&single, &shape.source_queries)
}

pub(super) fn validate_reply(
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
        || reply.policy_revision.as_ref().is_some_and(|revision| {
            revision.len() != 32 || !revision.bytes().all(|byte| byte.is_ascii_hexdigit())
        })
        || (reply.policy_revision.is_some() && reply.source_revision.is_none())
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
        if row["row"] == "source_occurrences_page" || row["row"] == "source_body_contexts_page" {
            occurrence_pages::validate(&row, reply.source_revision.as_deref())?;
            source_rows += 1;
            continue;
        }
        if row["row"] == "source_resolved_queries" {
            if row["schema"] != "dm-session-source-query-v1"
                || row["source_revision"].as_str() != reply.source_revision.as_deref()
                || row["semantic_revision"].as_str() != Some(reply.revision.as_str())
                || row["complete"] != false
            {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "invalid current resolved query envelope",
                ));
            }
            let nested = row["captured_jsonl"]
                .as_str()
                .ok_or_else(|| io::Error::other("missing resolved rows"))?;
            let count = row["query_count"]
                .as_u64()
                .ok_or_else(|| io::Error::other("missing resolved count"))?;
            if count == 0 || count > MAX_QUERIES as u64 || nested.lines().count() as u64 != count {
                return Err(io::Error::other("invalid resolved row count"));
            }
            for line in nested.lines() {
                let nested: serde_json::Value =
                    serde_json::from_str(line).map_err(io::Error::other)?;
                if nested["schema"] != "dm-resolved-query-v1" || nested["row"] != "resolved_query" {
                    return Err(io::Error::other("invalid resolved row"));
                }
            }
            source_rows += 1;
            continue;
        }
        if let Some(question) = native_row_descriptor(&row)? {
            validate_native_outer_row(reply, &row, question)?;
            source_rows += 1;
            continue;
        }
        if row["row"] == "source_body_model" {
            if row["schema"] != "dm-session-source-query-v1"
                || row["source_revision"].as_str() != reply.source_revision.as_deref()
                || row["ordinal"]
                    .as_u64()
                    .and_then(|n| u32::try_from(n).ok())
                    .is_none()
                || row["typed_jsonl"].as_str().is_none()
                || row["lexical_jsonl"].as_str().is_none()
                || row["semantic_resolution_complete"] != false
            {
                return Err(io::Error::other("invalid current body model envelope"));
            }
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
    pub(crate) fn timeout(&self) -> io::Result<std::time::Duration> {
        let seconds = self.timeout_seconds.unwrap_or(20);
        if !(1..=300).contains(&seconds) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "query timeout_seconds must be 1..300",
            ));
        }
        Ok(std::time::Duration::from_secs(u64::from(seconds)))
    }
    pub(crate) fn validate(&self) -> io::Result<()> {
        self.timeout()?;
        named_policy::validate_request(self)?;
        control_batch::validate_request(self)?;
        effect_reports::validate_request(self)?;effect_report_bytes::validate_request(self)?;generator_bytes::validate_request(self)?;
        variable_visibility::validate_request(self)?;
        raw_policy::validate_request(self)?;
        workspace_policy::validate_request(self)?;
        analyze_policy::validate_request(self)?;
        let source_count = self
            .source_queries
            .iter()
            .map(|query| match query {
                SourceQuery::ResolvedQueries { queries } => queries.len(),
                _ => 1,
            })
            .sum::<usize>();
        if self.queries.len().saturating_add(source_count) > MAX_QUERIES
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
        if self.source_queries.iter().any(|query| matches!(query, SourceQuery::ResolvedQueries { queries } if queries.is_empty() || queries.iter().any(|item| item.subject.as_ref().is_some_and(|subject| subject.len() > 256)))) {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "resolved query batch is empty or subject exceeds limit"));
        }
        if self.source_queries.iter().any(|query| matches!(query, SourceQuery::NativeCheckerFixture { severity, .. } if !matches!(severity.as_str(), "disabled" | "warning" | "error"))) {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "native checker fixture severity must be disabled, warning or error"));
        }
        if self.source_queries.iter().any(|query| matches!(query, SourceQuery::OccurrencesPage { limit, .. } | SourceQuery::BodyContextsPage { limit, .. } if !(1..=128).contains(limit))) {
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
            self.expected_policy_revision.as_ref(),
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
pub(crate) fn evaluate_snapshot(
    request: &QueryRequest,
    tree: &dm_tree::SemanticTree,
    state: &crate::runner_host::query_snapshot::QueryState,
) -> io::Result<QueryReply> {
    request.validate()?;
    if let Some(snapshot) = state.snapshot.as_ref() {
        snapshot.require_source_query_role(request)?;
    }
    if state
        .snapshot
        .as_ref()
        .is_some_and(|snapshot| snapshot.diagnostic_tree().is_some())
        && (!request.queries.is_empty()
            || request.source_queries.iter().any(|question| {
                !matches!(question,SourceQuery::NativeConfiguredVariableVisibility{..})
                    && !matches!(question,SourceQuery::NativeConfiguredChecker{family,..}if matches!(family.as_str(),"unknown_linter_setting"|"unknown_setting"|"invalid_lint_directive_value"))
            }))
    {
        return Err(io::Error::other("diagnostic declaration frame admits only variable-visibility, unknown-setting, or invalid-directive syntax questions; no ordinary ABI/model query"));
    }
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
    let policy_revision = snapshot
        .and_then(|snapshot| snapshot.policy_revision)
        .map(|pin| format!("{pin:032x}"));
    if request
        .expected_policy_revision
        .as_ref()
        .is_some_and(|expected| {
            !policy_revision
                .as_ref()
                .is_some_and(|current| expected.eq_ignore_ascii_case(current))
        })
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "retained policy query revision is stale or unavailable",
        ));
    }
    if policy_revision.is_some()
        && request.expected_policy_revision.is_none()
        && request.source_queries.iter().any(|query| {
            matches!(query, SourceQuery::NativeUntypedFixture { .. })
                || named_policy::reads_policy(query)
                || control_batch::reads_policy(query)
                        || effect_reports::reads_policy(query)
                        || effect_report_bytes::reads_policy(query)
                        || generator_bytes::reads_policy(query)
                || variable_visibility::reads_policy(query)
                || raw_policy::reads_policy(query)
                || workspace_policy::reads_policy(query)
                || analyze_policy::reads_policy(query)
        })
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "explicit-policy query requires its exact policy revision",
        ));
    }
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
        if let SourceQuery::ResolvedQueries { queries } = question {
            snapshot.write_resolved_queries(queries, tree, &mut output)?;
            continue;
        }
        if let SourceQuery::OccurrencesPage { start, limit } = question {
            snapshot.write_occurrences_page(*start, *limit, tree, &mut output)?;
            continue;
        }
        if let SourceQuery::BodyContextsPage { start, limit } = question {
            snapshot.write_body_contexts_page(*start, *limit, tree, &mut output)?;
            continue;
        }
        if let SourceQuery::BodyModel { ordinal } = question {
            snapshot.write_body_model(*ordinal, tree, &mut output)?;
            continue;
        }
        if let SourceQuery::NativeRawPolicyFixture {
            root,
            configuration,
            lints,
        } = question
        {
            snapshot.write_native_raw_policy_fixture(
                root,
                configuration,
                lints,
                tree,
                &mut output,
            )?;
            continue;
        }
        if let SourceQuery::NativeWorkspaceRawPolicy {
            root,
            configuration,
            lints,
            cursor,
            limit,
        } = question
        {
            snapshot.write_native_workspace_raw_policy(
                root,
                configuration,
                lints,
                cursor.as_ref(),
                *limit,
                tree,
                &mut output,
            )?;
            continue;
        }
        if let SourceQuery::NativeAnalyzePolicyFixture {
            root,
            configuration,
            lints,
        } = question
        {
            snapshot.write_native_analyze_policy_fixture(
                root,
                configuration,
                lints,
                tree,
                &mut output,
            )?;
            continue;
        }
        if let SourceQuery::NativeUntypedFixture { root } = question {
            snapshot.write_native_untyped_fixture(root, tree, &mut output)?;
            continue;
        }
        if let SourceQuery::NativeCheckerFixture { ordinal, severity } = question {
            snapshot.write_native_checker(*ordinal, severity, tree, &mut output)?;
            continue;
        }
        if let SourceQuery::NativeConfiguredVariableVisibility {
            environment,
            configuration,
        } = question
        {
            snapshot.write_native_configured_variable_visibility(
                environment,
                configuration.as_deref(),
                tree,
                &mut output,
            )?;
            continue;
        }
        if let SourceQuery::NativeConfiguredControlBatch {
            ordinal,
            families,
            environment,
            configuration,
        } = question
        {
            snapshot.write_native_configured_control_batch(
                *ordinal,
                families,
                environment,
                configuration.as_deref(),
                tree,
                &mut output,
            )?;
            continue;
        }
        if let SourceQuery::NativeNamedRule {
            root,
            lint,
            rule,
            configuration,
        } = question
        {
            snapshot.write_native_named_rule(root, lint, rule, configuration, tree, &mut output)?;
            continue;
        }
        if let SourceQuery::NativeGeneratorBytes{generator,cursor,limit}=question{snapshot.write_native_generator_bytes(*generator,*cursor,*limit as usize,tree,&mut output)?;continue;}
        if let SourceQuery::NativeEffectReportBytes{environment,configuration,page_width,target_window,cursor,limit}=question{snapshot.write_native_effect_byte_request(*page_width as usize,*target_window as usize,*cursor,*limit as usize,environment,configuration.as_deref(),tree,&mut output)?;continue;}
        if let SourceQuery::NativeEffectReports{environment,configuration,page_width,target_window}=question{
            snapshot.write_native_effect_request(*page_width as usize,*target_window as usize,environment,configuration.as_deref(),tree,&mut output)?;continue;
        }
        if let SourceQuery::NativeConfiguredChecker {
            ordinal,
            family,
            environment,
            configuration,
        } = question
        {
            snapshot.write_native_configured_checker(
                *ordinal,
                family,
                environment,
                configuration.as_deref(),
                tree,
                &mut output,
            )?;
            continue;
        }
        if let SourceQuery::SelectedReferences { ordinal } = question {
            snapshot.write_selected(*ordinal, &mut output)?;
            continue;
        }
        let (ordinal, provenance) = match question {
            SourceQuery::Occurrence { ordinal } => (*ordinal, false),
            SourceQuery::Provenance { ordinal } => (*ordinal, true),
            SourceQuery::ResolvedQueries { .. }
            | SourceQuery::BodyModel { .. }
            | SourceQuery::NativeCheckerFixture { .. }
            | SourceQuery::NativeUntypedFixture { .. }
            | SourceQuery::NativeRawPolicyFixture { .. }
            | SourceQuery::NativeWorkspaceRawPolicy { .. }
            | SourceQuery::NativeAnalyzePolicyFixture { .. }
            | SourceQuery::NativeNamedRule { .. }
            | SourceQuery::NativeConfiguredChecker { .. }
            | SourceQuery::NativeEffectReports { .. }
            | SourceQuery::NativeEffectReportBytes { .. }
            | SourceQuery::NativeGeneratorBytes { .. }
            | SourceQuery::NativeConfiguredControlBatch { .. }
            | SourceQuery::NativeConfiguredVariableVisibility { .. }
            | SourceQuery::SelectedReferences { .. }
            | SourceQuery::OccurrencesPage { .. }
            | SourceQuery::BodyContextsPage { .. }
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
        coverage: "semantic tree and bounded revision-pinned semantic type/authored member-node/captured intrinsic roster selectors (intrinsic completeness explicit; inherited effective lookup uses parent links and Resolver, not an expanded roster) plus caller-selected issued declaration occurrences and source/definition spans; bounded lazy compiler-selected references and explicitly source-pinned current compiler-host queries; full aggregate executable coverage and implicit external host reads remain excluded".into(),
        query_count: request.queries.len(), source_query_count: request.source_queries.len(), source_revision, policy_revision,
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
            timeout_seconds: None,
            project: "fixture.dme".into(),
            defines: BTreeMap::new(),
            engine_template: None,
            bootstrap_catalog: false,
            expected_revision: None,
            queries: vec![],
            expected_policy_revision: None,
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
            policy_revision: None,
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

#[cfg(test)]
#[path = "query/deadline_tests.rs"]
mod deadline_tests;

#[cfg(test)]pub(crate) fn validate_effect_batch_for_test(request:&QueryRequest,reply:&QueryReply)->io::Result<()>{validate_reply(reply,request.queries.len(),request.source_queries.len(),request.expected_revision.as_deref(),request.expected_source_revision.as_deref())?;effect_reports::validate_requested(reply,&request.source_queries)?;effect_report_bytes::validate_requested(reply,&request.source_queries)?;control_batch::validate_requested(reply,&request.source_queries)?;generator_bytes::validate_requested(reply,&request.source_queries)?;named_policy::validate_requested(reply,&request.source_queries)}
