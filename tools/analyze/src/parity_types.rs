//! Parser-independent legacy comparison metadata; execution lives in parity.rs.
#[derive(Clone, Copy, Debug)]
pub enum ParseKind {
    /// `file:line: [label/rule] text`: compared on rule, file and line.
    Tagged,
    /// `file:line: anything`: compared on file and line.
    FileLine,
    /// `file:line: [rule] text` (the old output tagged only with the rule, no `label/`): compared on
    /// rule, file and line. The engine's own `[label/rule]` lines are read as `Tagged`.
    Bracketed,
    /// `file:line: rule` (a `--report` listing): compared on rule, file and line.
    Report,
    /// `file:line` alone on a line (a bare site listing): compared on file and line.
    Bare,
    /// `  file:line text` (an indented listing with no colon after the line): compared on file and line.
    Indented,
    /// `  file.dm:line: text`, `file.dm:line text` or `file.dm:line` (indented or colon-less output,
    /// paths with spaces): compared on file and line.
    FileLineAny,
    /// `B1  file.dm:line: text`, `B6  file.dm:line emits X` or `B5  free text` (a `--report` listing
    /// whose lines start with the rule name): rule, file and line; a line with no file is compared
    /// by its text (the file field), line 0.
    RulePrefixed,
    /// `check_grep.sh`: ANSI-coloured `NN- title` part headers, hits as `file:line:text` (or
    /// `file:text` when the old rule printed no line numbers), a few counted ratchets. Findings are
    /// attributed to the part's slug; see `parse_check_grep`.
    CheckGrep,
}

/// How to compare one lint with its legacy script. Paths are relative to the repo root.
#[derive(Clone, Copy, Debug)]
pub struct Parity {
    /// The old script and arguments for its CI run.
    pub old: &'static [&'static str],
    /// The old script's raw-sites invocations (each a `--report ...`), when it has ones that ignore
    /// baselines; their outputs are concatenated. Empty: use `blank` instead.
    pub old_raw: &'static [&'static [&'static str]],
    /// Baseline files to blank while running the old script raw (when it has no `--report`).
    pub blank: &'static [&'static str],
    pub parse: ParseKind,
    /// The old `--update` invocation.
    pub update: Option<&'static [&'static str]>,
    /// The old `--seed` invocation (written to the same files).
    pub seed: Option<&'static [&'static str]>,
    /// The baseline files `update`/`seed` rewrite.
    pub files: &'static [&'static str],
    /// The old `--selftest` invocation.
    pub selftest: Option<&'static [&'static str]>,
}

impl Parity {
    /// The common case: `python <script>` with ratchet output, blanking the given baselines for raw.
    pub const fn ratchet(
        script: &'static [&'static str],
        baselines: &'static [&'static str],
    ) -> Parity {
        Parity {
            old: script,
            old_raw: &[],
            blank: baselines,
            parse: ParseKind::Tagged,
            update: None,
            seed: None,
            files: baselines,
            selftest: None,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Finding {
    pub rule: String,
    pub rel: String,
    pub line: u32,
}
