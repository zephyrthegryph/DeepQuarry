//! A command's answer as data (lean_unified "One program", 1+3 ENGINE): what `analyze check` found, per lint, with every site as a
//! [`Diagnostic`], and the text the command prints rendered from it.
//!
//! The text a command prints is [`Report::render`] of its report, byte for byte (standalone and in the daemon alike); the daemon
//! sends the report itself to its client, which renders it, and keeps it to answer the same request again while nothing it read
//! changed. [`Report::changes_since`] is the incremental form: which diagnostics appeared and which went between two reports.

use serde::{Deserialize, Serialize};

/// How a site counts.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub enum Severity {
    /// It fails the check: a new site of a ratcheted rule, any site of a hard ban, a rule over its ceiling.
    Error,
    /// A known legacy site the rule's baseline or ceiling still admits.
    Baselined,
    /// The lint judges its own sites (a custom or count policy): the lint's text says whether they fail.
    Note,
}

/// One site a lint reported.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub struct Diagnostic {
    pub lint: String,
    pub rule: String,
    pub file: String,
    pub line: u32,
    /// The column when the lint knows it (lints report lines today; 0 = not known).
    pub column: u32,
    pub message: String,
    pub severity: Severity,
}

/// An ALLOW annotation that kept a site.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub struct AllowUse {
    pub lint: String,
    pub file: String,
    pub line: u32,
    pub name: String,
    pub code: String,
}

/// One lint's result: its sites, the annotations it used, whether it failed, and the text it prints.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct LintReport {
    pub name: String,
    pub failed: bool,
    pub diagnostics: Vec<Diagnostic>,
    pub allow_uses: Vec<AllowUse>,
    pub text: String,
}

/// One printed piece of a command's output, in order.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub enum Part {
    /// Text the command prints that belongs to no lint (a selftest failure, the unused-ALLOW summary, the verdict line).
    Text(String),
    Lint(LintReport),
}

/// What a command answered: its parts in print order and its exit code.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Report {
    pub command: String,
    pub parts: Vec<Part>,
    pub exit: u8,
}

/// What changed between two reports (`changes_since`): diagnostics that appeared and diagnostics that went, each in report order.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Changes {
    pub added: Vec<Diagnostic>,
    pub removed: Vec<Diagnostic>,
    /// Lints whose verdict changed (name, failed now).
    pub verdicts: Vec<(String, bool)>,
}

impl Report {
    pub fn new(command: &str) -> Report {
        Report { command: command.to_string(), ..Default::default() }
    }

    /// Appends printed text (joined to a preceding text part).
    pub fn text(&mut self, s: impl AsRef<str>) {
        let s = s.as_ref();
        if s.is_empty() {
            return;
        }
        if let Some(Part::Text(t)) = self.parts.last_mut() {
            t.push_str(s);
        } else {
            self.parts.push(Part::Text(s.to_string()));
        }
    }

    /// `println!` into the report.
    pub fn line(&mut self, s: impl AsRef<str>) {
        let mut l = s.as_ref().to_string();
        l.push('\n');
        self.text(l);
    }

    pub fn lint(&mut self, l: LintReport) {
        self.parts.push(Part::Lint(l));
    }

    /// The bytes the command prints on stdout.
    pub fn render(&self) -> String {
        let mut out = String::new();
        for p in &self.parts {
            match p {
                Part::Text(t) => out.push_str(t),
                Part::Lint(l) => out.push_str(&l.text),
            }
        }
        out
    }

    pub fn lints(&self) -> impl Iterator<Item = &LintReport> {
        self.parts.iter().filter_map(|p| match p {
            Part::Lint(l) => Some(l),
            Part::Text(_) => None,
        })
    }

    /// Every diagnostic, in report order.
    pub fn diagnostics(&self) -> impl Iterator<Item = &Diagnostic> {
        self.lints().flat_map(|l| l.diagnostics.iter())
    }

    /// The report restricted to one file's diagnostics and allow uses (each lint keeps its verdict; texts are dropped: they are
    /// whole-tree summaries).
    pub fn for_file(&self, file: &str) -> Report {
        let parts = self
            .lints()
            .map(|l| {
                Part::Lint(LintReport {
                    name: l.name.clone(),
                    failed: l.failed,
                    diagnostics: l.diagnostics.iter().filter(|d| d.file == file).cloned().collect(),
                    allow_uses: l.allow_uses.iter().filter(|u| u.file == file).cloned().collect(),
                    text: String::new(),
                })
            })
            .collect();
        Report { command: self.command.clone(), parts, exit: self.exit }
    }

    /// What changed from `before` to this report: a multiset difference of the diagnostics (a site reported twice counts twice).
    pub fn changes_since(&self, before: &Report) -> Changes {
        use std::collections::HashMap;
        let mut count: HashMap<&Diagnostic, i64> = HashMap::new();
        for d in before.diagnostics() {
            *count.entry(d).or_default() += 1;
        }
        let mut added = Vec::new();
        for d in self.diagnostics() {
            match count.get_mut(d) {
                Some(n) if *n > 0 => *n -= 1,
                _ => added.push(d.clone()),
            }
        }
        let mut removed = Vec::new();
        let mut now: HashMap<&Diagnostic, i64> = HashMap::new();
        for d in self.diagnostics() {
            *now.entry(d).or_default() += 1;
        }
        for d in before.diagnostics() {
            match now.get_mut(d) {
                Some(n) if *n > 0 => *n -= 1,
                _ => removed.push(d.clone()),
            }
        }
        let was: HashMap<&str, bool> = before.lints().map(|l| (l.name.as_str(), l.failed)).collect();
        let verdicts = self.lints().filter(|l| was.get(l.name.as_str()) != Some(&l.failed)).map(|l| (l.name.clone(), l.failed)).collect();
        Changes { added, removed, verdicts }
    }
}

/// How a command's report is shown: the text it prints (the default), or as data: `--json` (the whole report), `--file F` (one
/// file's diagnostics) or `--since N` (what changed since the report of revision N). The flags select a view of one answer, so a
/// host keys the answer by the command line without them ([`View::split`]).
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct View {
    pub json: bool,
    pub since: Option<u64>,
    pub file: Option<String>,
}

impl View {
    /// The command line without the view flags, and the view they select.
    pub fn split(argv: &[String]) -> (Vec<String>, View) {
        let mut view = View::default();
        let mut out = Vec::with_capacity(argv.len());
        let mut it = argv.iter();
        while let Some(a) = it.next() {
            match a.as_str() {
                "--json" => view.json = true,
                "--since" => view.since = it.next().and_then(|n| n.parse().ok()).or(Some(0)),
                "--file" => view.file = it.next().map(|f| f.replace('\\', "/")),
                _ => out.push(a.clone()),
            }
        }
        (out, view)
    }

    pub fn is_text(&self) -> bool {
        !self.json && self.since.is_none() && self.file.is_none()
    }

    /// What the command prints in this view of `report`, made at `revision`; `base` is the report of revision `since` when the
    /// host still has it (without it every diagnostic counts as added, and `known` says so).
    pub fn render(&self, report: &Report, revision: u64, base: Option<&Report>) -> String {
        if self.is_text() {
            return report.render();
        }
        let shown = match &self.file {
            Some(f) => report.for_file(f),
            None => report.clone(),
        };
        let value = match self.since {
            Some(since) => {
                let empty = Report::new(&report.command);
                let before = match (base, &self.file) {
                    (Some(b), Some(f)) => b.for_file(f),
                    (Some(b), None) => b.clone(),
                    (None, _) => empty,
                };
                serde_json::json!({
                    "revision": revision,
                    "since": since,
                    "known": base.is_some(),
                    "exit": report.exit,
                    "changes": shown.changes_since(&before),
                })
            }
            None => serde_json::json!({ "revision": revision, "report": shown }),
        };
        let mut s = serde_json::to_string(&value).unwrap_or_default();
        s.push('\n');
        s
    }
}

/// The report the last command of this run made (`cli` sets it; a hosted request's host takes it with [`take`]).
static LAST: std::sync::Mutex<Option<Report>> = std::sync::Mutex::new(None);

pub(crate) fn publish(r: Report) {
    *LAST.lock().unwrap_or_else(|e| e.into_inner()) = Some(r);
}

/// The report of the command that just ran, if it made one.
pub fn take() -> Option<Report> {
    LAST.lock().unwrap_or_else(|e| e.into_inner()).take()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn d(file: &str, line: u32, msg: &str) -> Diagnostic {
        Diagnostic { lint: "x".into(), rule: "r".into(), file: file.into(), line, column: 0, message: msg.into(), severity: Severity::Error }
    }

    #[test]
    fn render_is_the_parts_in_order_and_changes_are_a_multiset_difference() {
        let mut a = Report::new("check");
        a.line("selftest FAILED: y");
        a.lint(LintReport { name: "x".into(), failed: true, diagnostics: vec![d("a.dm", 1, "m"), d("a.dm", 1, "m")], allow_uses: vec![], text: "x: r 2 FAIL\n".into() });
        a.line("Ratchet lints failed: x");
        assert_eq!(a.render(), "selftest FAILED: y\nx: r 2 FAIL\nRatchet lints failed: x\n");
        let mut b = Report::new("check");
        b.lint(LintReport { name: "x".into(), failed: false, diagnostics: vec![d("a.dm", 1, "m"), d("b.dm", 2, "n")], allow_uses: vec![], text: String::new() });
        let c = b.changes_since(&a);
        assert_eq!(c.added, vec![d("b.dm", 2, "n")]);
        assert_eq!(c.removed, vec![d("a.dm", 1, "m")]);
        assert_eq!(c.verdicts, vec![("x".to_string(), false)]);
        assert_eq!(b.for_file("b.dm").diagnostics().count(), 1);
    }
}
