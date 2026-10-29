//! Snapshot-as-of raw findings: refresh once with prepare-query, then read pages
//! from that exact published policy frame without filesystem IO or reparsing.
use super::SourceSnapshot;
use serde::Serialize;
use std::{
    io::{self, Write},
    path::Path,
    sync::{atomic::AtomicUsize, Arc},
};
#[derive(Serialize)]
struct Report<'a, P: Serialize> {
    row: &'static str,
    schema: &'static str,
    source_revision: String,
    policy_revision: String,
    semantic_revision: String,
    snapshot_as_of: &'static str,
    root: &'a Path,
    configuration: &'a Path,
    recursive_roots: &'a [std::path::PathBuf],
    requested_lints: &'a [String],
    lint_whitelist: &'static [&'static str],
    scope: &'static str,
    full_policy_parity: bool,
    baseline_applied: bool,
    admission: &'static str,
    configuration_scope: &'static str,
    #[serde(flatten)]
    page: P,
}
struct Count(usize);
impl Write for Count {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.0 = self
            .0
            .checked_add(bytes.len())
            .filter(|n| *n < crate::daemon::query::MAX_OUTPUT)
            .ok_or_else(|| io::Error::other("workspace row exceeds bounded query output"))?;
        Ok(bytes.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}
impl SourceSnapshot {
    pub(crate) fn write_native_workspace_raw_policy(
        &self,
        root: &Path,
        configuration: &Path,
        lints: &[String],
        cursor: Option<&crate::query_db::WorkspaceCursor>,
        limit: usize,
        tree: &dm_tree::SemanticTree,
        output: &mut impl Write,
    ) -> io::Result<()> {
        crate::daemon::control::checkpoint()?;
        if !root.is_absolute() || !configuration.is_absolute() || !self.matches_tree(tree) {
            return Err(io::Error::other(
                "workspace request does not name current absolute source scope",
            ));
        }
        let capture = self
            .native_workspace
            .as_ref()
            .ok_or_else(|| io::Error::other("current workspace capture unavailable"))?;
        if root != capture.root()
            || configuration != capture.configuration().0
            || self.policy_revision != Some(capture.policy_revision())
        {
            return Err(io::Error::other(
                "workspace request differs from exact registered policy capture",
            ));
        }
        let queries = self
            .native_raw_queries
            .as_ref()
            .ok_or_else(|| io::Error::other("current workspace compiler Db unavailable"))?;
        let guard = self.workspace_native_read()?;
        capture.require_scope(&guard)?;
        let metadata = capture
            .recursive_roots()
            .iter()
            .try_fold(crate::daemon::query::MAX_OUTPUT + 16384usize, |n, p| {
                n.checked_add(p.as_os_str().len().saturating_mul(8))
            })
            .and_then(|n| {
                n.checked_add(
                    (root.as_os_str().len() + configuration.as_os_str().len()).saturating_mul(8),
                )
            })
            .ok_or_else(|| io::Error::other("workspace wire metadata accounting overflow"))?;
        queries.with_workspace_raw_page(
            capture,
            &guard,
            lints,
            cursor,
            limit,
            Arc::new(AtomicUsize::new(0)),
            |reader| {
                let mut count = reader.max_items();
                loop {
                    crate::daemon::control::checkpoint()?;
                    capture.require_scope(&guard)?;
                    let page = reader.page(count)?;
                    let report = Report {
                        row: "source_native_workspace_raw_policy",
                        schema: "dm-session-source-query-v1",
                        source_revision: format!("{:032x}", self.source_revision),
                        policy_revision: format!("{:032x}", capture.policy_revision()),
                        semantic_revision: format!("{:032x}", tree.identity()),
                        snapshot_as_of: "policy_revision",
                        root,
                        configuration,
                        recursive_roots: capture.recursive_roots(),
                        requested_lints: lints,
                        lint_whitelist: dq_analyze::captured_raw_policy::RAW_FILE_LINTS,
                        scope: "typed_discovery_raw_files",
                        full_policy_parity: false,
                        baseline_applied: false,
                        admission: "raw_findings",
                        configuration_scope: if capture.configuration().1.is_some() {
                            "captured_configuration_bytes"
                        } else {
                            "proven_missing_configuration"
                        },
                        page,
                    };
                    let mut bytes = Count(0);
                    let measured = serde_json::to_writer(&mut bytes, &report)
                        .map_err(io::Error::other)
                        .and_then(|_| reader.require_output_admission(bytes.0 + 1, metadata));
                    if let Err(error) = measured {
                        if count > 1 {
                            count = (count / 2).max(1);
                            continue;
                        }
                        return Err(error); // one oversized item cannot masquerade as an empty page
                    }
                    crate::daemon::control::checkpoint()?;
                    serde_json::to_writer(&mut *output, &report).map_err(io::Error::other)?;
                    return output.write_all(b"\n");
                }
            },
        )
    }
}
