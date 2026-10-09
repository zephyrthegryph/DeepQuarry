//! Bounded read-only queries against an existing retained semantic snapshot.
use serde::{Deserialize, Serialize};
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
    pub jsonl: String,
}
/// Query an existing compatible daemon without starting, retiring or building it.
pub fn execute(mut request: QueryRequest) -> Result<QueryReply, Box<dyn std::error::Error>> {
    request.validate()?;
    let count = request.queries.len();
    let expected = request.expected_revision.clone();
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
            validate_reply(&reply, count, expected.as_deref())?;
            Ok(reply)
        }
        super::protocol::Reply::Rejected(error) => Err(error.into()),
        _ => Err("unexpected read-only query reply".into()),
    }
}
fn validate_reply(reply: &QueryReply, count: usize, expected: Option<&str>) -> io::Result<()> {
    if reply.schema != "dm-session-query-v1"
        || reply.complete
        || reply.query_count != count
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
    let mut rows = 0;
    for line in reply.jsonl.lines() {
        let row: serde_json::Value = serde_json::from_str(line).map_err(io::Error::other)?;
        if row["row"] != "resolved_query" || row["schema"] != "dm-resolved-query-v1" {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "invalid query answer row",
            ));
        }
        rows += 1;
    }
    if rows != count {
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
            &serde_json::json!({"row":"query_batch","schema":reply.schema,"revision":reply.revision,"complete":reply.complete,"coverage":reply.coverage,"query_count":reply.query_count}),
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
const MAX_OUTPUT: usize = 524288;
impl QueryRequest {
    pub(super) fn validate(&self) -> io::Result<()> {
        if self.queries.len() > MAX_QUERIES
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
        if serde_json::to_vec(self).map_err(io::Error::other)?.len() > MAX_REQUEST {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "query batch exceeds 64 KiB",
            ));
        }
        if self.expected_revision.as_ref().is_some_and(|revision| {
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
pub(super) fn evaluate(
    request: &QueryRequest,
    tree: &dm_tree::SemanticTree,
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
    Ok(QueryReply { schema: "dm-session-query-v1".into(), revision, complete: false,
        coverage: "retained semantic tree only; source occurrences, compiler-selected executable references and pinned resource/runtime host facts are not included".into(),
        query_count: request.queries.len(), jsonl: String::from_utf8(output.0).map_err(io::Error::other)? })
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
        }
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
            schema: "dm-session-query-v1".into(),
            revision: "0".repeat(32),
            complete: false,
            coverage: "partial".into(),
            query_count: 0,
            jsonl: String::new(),
        };
        validate_reply(&reply, 0, None).unwrap();
        reply.complete = true;
        assert!(validate_reply(&reply, 0, None).is_err());
        reply.complete = false;
        reply.jsonl = " ".repeat(MAX_OUTPUT + 1);
        assert!(validate_reply(&reply, 0, None).is_err());
        reply.jsonl.clear();
        reply.query_count = 1;
        assert!(validate_reply(&reply, 1, None).is_err());
    }
}
