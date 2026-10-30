//! Explicit analyze-policy fixture admission over the already captured native request.
//! No filesystem reads, parser/model construction or baseline mutation occurs here.
use super::SourceSnapshot;
// A source feature accidentally enabled by another dependency must not quietly
// re-link the retired frontend into the native host.
const _: () = assert!(
    !dq_analyze::LEGACY_SEMANTICS_ENABLED,
    "native compiler host requires dq-analyze without legacy-sem"
);
use dq_analyze::{captured_policy_metadata::LINTS, captured_raw_policy::RawRun};
use serde::{
    ser::{SerializeMap, SerializeSeq},
    Serialize, Serializer,
};
use std::{io, path::Path, sync::Arc};
impl SourceSnapshot {
    pub(crate) fn write_native_analyze_policy_fixture(
        &self,
        root: &Path,
        configuration: &Path,
        lints: &[String],
        tree: &dm_tree::SemanticTree,
        output: &mut impl io::Write,
    ) -> io::Result<()> {
        crate::daemon::control::checkpoint()?;
        // Acquired-byte encoding proof is required even before a warm cache hit.
        self.require_semantic_source_encoding()?;
        self.named_policy_capture(tree)?;
        if !root.is_absolute() || !configuration.is_absolute() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "analyze-policy paths must be caller-absolute",
            ));
        }
        if !self.matches_tree(tree) {
            return Err(io::Error::other("analyze policy semantic snapshot differs"));
        }
        let pin = self.policy_revision.ok_or_else(|| {
            io::Error::other("analyze policy requires an explicitly bound captured policy revision")
        })?;
        let captured = self
            .native_policy_inputs
            .as_ref()
            .ok_or_else(|| io::Error::other("analyze policy inputs unavailable"))?;
        if captured.policy_revision() != Some(pin) {
            return Err(io::Error::other(
                "analyze policy receipt differs from snapshot",
            ));
        }
        let bytes = captured.configuration_bytes(configuration)?;
        let queries = self
            .native_raw_queries
            .as_ref()
            .ok_or_else(|| io::Error::other("compiler analyze-policy query graph unavailable"))?;
        let input = queries.raw_cohort(Arc::clone(captured), root, configuration)?;
        // Reserve the entire daemon output buffer, including any earlier rows,
        // including conservative Vec grow overlap (old <=MAX, new <=2MAX),
        // plus bounded stack-report/revision/path coordination. No
        // JSON Value tree or cloned findings are retained outside the gate.
        let reserve = output_reservation(root, configuration, lints)?;
        queries.with_analyze_fixture_output(&input, lints, reserve, |runs| {
            let report = Report {
                snapshot: self,
                tree,
                root,
                configuration,
                lints,
                pin,
                configuration_present: bytes.is_some(),
                runs,
            };
            write_report(&report, output, crate::daemon::query::MAX_OUTPUT)
        })
    }
}
fn output_reservation(root: &Path, configuration: &Path, lints: &[String]) -> io::Result<usize> {
    lints.iter().try_fold(
        crate::daemon::query::MAX_OUTPUT
            .checked_mul(3)
            .and_then(|n| n.checked_add(16384))
            .and_then(|n| {
                n.checked_add(
                    root.as_os_str()
                        .len()
                        .checked_add(configuration.as_os_str().len())?
                        .checked_mul(8)?,
                )
            })
            .ok_or_else(|| io::Error::other("typed output metadata accounting overflow"))?,
        |n, name| {
            n.checked_add(
                name.len()
                    .checked_mul(8)
                    .ok_or_else(|| io::Error::other("typed output metadata overflow"))?,
            )
            .ok_or_else(|| io::Error::other("typed output metadata overflow"))
        },
    )
}
// io::Write::write_all retries Interrupted. Internal writers must latch the
// ACTUAL first error and return a nonretryable proxy; only the completed outer
// serialization boundary restores that original error/source to the caller.
#[derive(Default)]
struct Failure(Option<io::Error>);
impl Failure {
    fn fail<T>(&mut self, error: io::Error) -> io::Result<T> {
        if self.0.is_none() {
            self.0 = Some(error);
        }
        Err(io::Error::other("bounded JSON writer stopped"))
    }
    fn require(&self) -> io::Result<()> {
        if self.0.is_some() {
            Err(io::Error::other("bounded JSON writer stopped"))
        } else {
            Ok(())
        }
    }
    fn restore<T>(&mut self, result: io::Result<T>) -> io::Result<T> {
        self.0.take().map_or(result, Err)
    }
}
struct Count {
    bytes: usize,
    limit: usize,
    failure: Failure,
}
impl io::Write for Count {
    fn write(&mut self, b: &[u8]) -> io::Result<usize> {
        self.failure.require()?;
        if let Err(error) = crate::daemon::control::checkpoint() {
            return self.failure.fail(error);
        }
        match self.bytes.checked_add(b.len()).filter(|n| *n < self.limit) {
            Some(n) => {
                self.bytes = n;
                Ok(b.len())
            }
            None => self.failure.fail(io::Error::other(
                "typed policy row exceeds bounded query output",
            )),
        }
    }
    fn flush(&mut self) -> io::Result<()> {
        self.failure.require()
    }
}
struct Forward<'a, W: io::Write> {
    output: &'a mut W,
    failure: Failure,
}
impl<W: io::Write> io::Write for Forward<'_, W> {
    fn write(&mut self, b: &[u8]) -> io::Result<usize> {
        self.failure.require()?;
        if let Err(error) = crate::daemon::control::checkpoint() {
            return self.failure.fail(error);
        }
        match self.output.write(b) {
            Ok(n) => Ok(n),
            Err(error) => self.failure.fail(error),
        }
    }
    fn flush(&mut self) -> io::Result<()> {
        self.failure.require()?;
        match self.output.flush() {
            Ok(()) => Ok(()),
            Err(error) => self.failure.fail(error),
        }
    }
}
fn serialization_error(error: serde_json::Error) -> io::Error {
    io::Error::new(
        error.io_error_kind().unwrap_or(io::ErrorKind::InvalidData),
        error,
    )
}
fn write_report(
    report: &impl Serialize,
    output: &mut impl io::Write,
    limit: usize,
) -> io::Result<()> {
    let mut count = Count {
        bytes: 0,
        limit,
        failure: Failure::default(),
    };
    let counted = serde_json::to_writer(&mut count, report).map_err(serialization_error);
    count.failure.restore(counted)?;
    crate::daemon::control::checkpoint()?;
    let mut forward = Forward {
        output,
        failure: Failure::default(),
    };
    let emitted = serde_json::to_writer(&mut forward, report).map_err(serialization_error);
    forward.failure.restore(emitted)?;
    // The newline uses the SAME adapter, never a raw retrying caller write_all.
    let ended = io::Write::write_all(&mut forward, b"\n");
    forward.failure.restore(ended)?;
    crate::daemon::control::checkpoint()
}
struct Report<'a> {
    snapshot: &'a SourceSnapshot,
    tree: &'a dm_tree::SemanticTree,
    root: &'a Path,
    configuration: &'a Path,
    lints: &'a [String],
    pin: u128,
    configuration_present: bool,
    runs: &'a [RawRun],
}
// Preserve the old serde_json::Value map's lexical key order exactly.
impl Serialize for Report<'_> {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut m = s.serialize_map(Some(16))?;
        m.serialize_entry("admission", "native_semantic_findings")?;
        m.serialize_entry("baseline_applied", &false)?;
        m.serialize_entry("configuration", self.configuration)?;
        m.serialize_entry(
            "configuration_scope",
            if self.configuration_present {
                "captured_configuration_bytes"
            } else {
                "proven_missing_configuration"
            },
        )?;
        m.serialize_entry("fixture_limits", &Limits)?;
        m.serialize_entry("full_policy_parity", &false)?;
        m.serialize_entry("lint_whitelist", LINTS)?;
        m.serialize_entry("policy_revision", &Hex(self.pin))?;
        m.serialize_entry("requested_lints", self.lints)?;
        m.serialize_entry("results", &Runs(self.runs))?;
        m.serialize_entry("root", self.root)?;
        m.serialize_entry("row", "source_native_analyze_policy_fixture")?;
        m.serialize_entry("schema", "dm-session-source-query-v1")?;
        m.serialize_entry("scope", "explicit_captured_files")?;
        m.serialize_entry("semantic_revision", &Hex(self.tree.identity()))?;
        m.serialize_entry("source_revision", &Hex(self.snapshot.source_revision))?;
        m.end()
    }
}
struct Limits;
impl Serialize for Limits {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut m = s.serialize_map(Some(4))?;
        m.serialize_entry("contract", "fixture_admission_not_cpu_or_rss")?;
        m.serialize_entry(
            "per_file_bytes",
            &dq_analyze::captured_raw_policy::MAX_FIXTURE_FILE_BYTES,
        )?;
        m.serialize_entry("sites", &dq_analyze::captured_raw_policy::MAX_FIXTURE_SITES)?;
        m.serialize_entry(
            "total_bytes",
            &dq_analyze::captured_raw_policy::MAX_FIXTURE_TOTAL_BYTES,
        )?;
        m.end()
    }
}
struct Runs<'a>(&'a [RawRun]);
impl Serialize for Runs<'_> {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut seq = s.serialize_seq(Some(self.0.len()))?;
        for run in self.0 {
            seq.serialize_element(&Run(run))?;
        }
        seq.end()
    }
}
struct Run<'a>(&'a RawRun);
impl Serialize for Run<'_> {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut m = s.serialize_map(Some(4))?;
        m.serialize_entry("allow_used", &Allows(&self.0.allow_used))?;
        m.serialize_entry("name", &self.0.name)?;
        m.serialize_entry("notes", &self.0.run.notes)?;
        m.serialize_entry("sites", &Sites(&self.0.run.sites))?;
        m.end()
    }
}
struct Sites<'a>(&'a [dq_analyze::lint::Site]);
impl Serialize for Sites<'_> {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut seq = s.serialize_seq(Some(self.0.len()))?;
        for v in self.0 {
            seq.serialize_element(&Site(v))?;
        }
        seq.end()
    }
}
struct Site<'a>(&'a dq_analyze::lint::Site);
impl Serialize for Site<'_> {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let v = self.0;
        let mut m = s.serialize_map(Some(6))?;
        m.serialize_entry("ident", &v.ident)?;
        m.serialize_entry("key", &v.key)?;
        m.serialize_entry("line", &v.line)?;
        m.serialize_entry("msg", &v.msg)?;
        m.serialize_entry("rel", &v.rel)?;
        m.serialize_entry("rule", &v.rule)?;
        m.end()
    }
}
struct Allows<'a>(&'a [dq_analyze::lint::AllowUse]);
impl Serialize for Allows<'_> {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut seq = s.serialize_seq(Some(self.0.len()))?;
        for v in self.0 {
            seq.serialize_element(&Allow(v))?;
        }
        seq.end()
    }
}
struct Allow<'a>(&'a dq_analyze::lint::AllowUse);
impl Serialize for Allow<'_> {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let v = self.0;
        let mut m = s.serialize_map(Some(4))?;
        m.serialize_entry("code", &v.code)?;
        m.serialize_entry("line", &v.line)?;
        m.serialize_entry("name", &v.name)?;
        m.serialize_entry("rel", &v.rel)?;
        m.end()
    }
}
#[cfg(test)]
#[path = "runner_query_analyze_policy_writer_tests.rs"]
mod tests;

struct Hex(u128);
impl Serialize for Hex {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.collect_str(&format_args!("{:032x}", self.0))
    }
}
