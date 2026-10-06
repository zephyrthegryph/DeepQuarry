//! Port of `tools/ci/scheduler_lints.py`: the one-scheduler lints (roadmap S6,
//! doc/rewrite/object_model_core.md sec 4.11).
//!
//! Counts every site of the things the OM scheduler replaces across `code/` (unit tests, benchmarks
//! and the vendored TGS DMAPI are the `[lint.scheduler]` exemptions of `lint_scopes.toml`; `#define`
//! lines are macro plumbing and don't count). Each rule is ratcheted by
//! `tools/ci/scheduler_lints_baseline.txt` (fingerprints; it only shrinks). A justified keep carries
//! `// ALLOW(scheduler): <reason>` on the site's line or the comment line above it.
//!
//! | rule | pattern | instead |
//! |---|---|---|
//! | spawn | `spawn(` | om_after, tasks |
//! | addtimer | `addtimer(` | om_after, clocks, contributions |
//! | invoke_async | `INVOKE_ASYNC` | nothing: the callee no longer sleeps |
//! | do_after | `do_after(` | om_task steps |
//! | sleep | `sleep(` | om_task steps |
//! | stoplag | `stoplag(` | a lane with a budget |
//! | prompts | `input(` `alert(` `tgui_input_*(` `tgui_alert(` | om_prompt |
//! | set_waitfor | `set waitfor` | nothing |
//! | weakref | `weakref` (any case) | relations, or OM handles |
//! | del | `del(` | qdel and the lifecycle verbs |
//! | blocking_builtins | `winget(` `winexists(` `shell(` `.MeasureText(` | DX-exec callbacks |
//!
//! Quirks kept: the patterns run on the `code_only` view, whose line numbers can drift from the raw
//! file after an unbalanced quote, while the ALLOW lookup and the baseline fingerprint read the raw
//! line at that number; every MATCH of every rule is a site of its own (a line with two `spawn(` is
//! two sites) and `allowed()` is asked once per match, so one annotation keeps them all.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::tree::{SourceFile, CODE_DM};
use crate::util::py_lstrip;

const LINT: &str = "scheduler";
const HINT: &str = "use the OM scheduler (om_after, om_task steps, om_prompt, OM handles, declared refs)";

macro_rules! rules {
    ($($n:literal),* $(,)?) => { &[$(RuleMeta { name: $n, hint: HINT }),*] };
}

static META: Meta = Meta {
    name: "scheduler",
    group: "",
    label: "scheduler",
    legacy: "tools/ci/scheduler_lints.py",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Sites {
        baseline: "tools/ci/scheduler_lints_baseline.txt",
        header: &[
            "scheduler lint legacy sites (tools/ci/scheduler_lints.py). rule<TAB>file<TAB>normalized line.",
            "A site not listed here fails. Shrink-only: after a sweep, `python tools/ci/scheduler_lints.py --update`.",
        ],
        banned: &[],
    },
    rules: rules![
        "spawn",
        "addtimer",
        "invoke_async",
        "do_after",
        "sleep",
        "stoplag",
        "prompts",
        "set_waitfor",
        "weakref",
        "del",
        "blocking_builtins",
    ],
    allow: &["scheduler"],
    lists: &[],
};

struct Scheduler {
    /// `PATTERNS`, in the order the Python lists them (a line's matches are tried rule by rule).
    patterns: Vec<(&'static str, Pat)>,
}

impl Scheduler {
    fn new() -> Scheduler {
        Scheduler {
            patterns: vec![
                // A bare `spawn` (no delay) or `spawn x()` on one line is the same form.
                ("spawn", Pat::new(r"(?<![\w./])spawn(?:\s*\(|\s*$|\s+[A-Za-z_])")),
                ("addtimer", Pat::new(r"(?<![\w.])addtimer\s*\(")),
                ("invoke_async", Pat::new(r"\bINVOKE_ASYNC\b")),
                ("do_after", Pat::new(r"(?<![\w./])do_after\s*\(")),
                ("sleep", Pat::new(r"(?<![\w./])sleep\s*\(")),
                ("stoplag", Pat::new(r"(?<![\w./])stoplag\s*\(")),
                ("prompts", Pat::new(r"(?<![\w./])(?:input|alert|tgui_input_\w+|tgui_alert)\s*\(")),
                ("set_waitfor", Pat::new(r"\bset\s+waitfor\b")),
                ("weakref", Pat::new(r"(?i)weakref")),
                ("del", Pat::new(r"(?<![\w./])del\s*\(")),
                // BYOND's blocking built-ins: client round trips and OS processes. Callers ask DX-exec
                // (dx_winget(), dx_winexists(), dx_measure_text(), dx_shell(), dx_shelleo()) instead.
                ("blocking_builtins", Pat::new(r"(?<![\w./])(?:winget|winexists|shell)\s*\(|\.MeasureText\s*\(")),
            ],
        }
    }
}

impl Lint for Scheduler {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        for (no, line) in f.code().numbered() {
            if py_lstrip(line).starts_with("#define") {
                continue;
            }
            for (name, pat) in &self.patterns {
                for _ in pat.find_iter(line) {
                    // A justified keep says why on its line (sec 4.11).
                    if out.allowed(f, no, LINT) {
                        continue;
                    }
                    out.site(name, no);
                }
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/scheduler_lints.py"],
            old_raw: &[&["tools/ci/scheduler_lints.py", "--report"]],
            blank: &[],
            parse: ParseKind::Report,
            update: Some(&["tools/ci/scheduler_lints.py", "--update"]),
            seed: Some(&["tools/ci/scheduler_lints.py", "--seed"]),
            files: &["tools/ci/scheduler_lints_baseline.txt"],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Scheduler::new());
}
