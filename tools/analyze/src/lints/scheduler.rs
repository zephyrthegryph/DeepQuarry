//! Port of `tools/ci/scheduler_lints.py`: the one-scheduler lints (roadmap S6,
//! doc/rewrite/object_model_core.md sec 4.11).
//!
//! Counts every site of the things the OM scheduler replaces across `code/` (unit tests, benchmarks
//! and the vendored TGS DMAPI are the `[lint.scheduler]` exemptions of `lint_scopes.toml`; `#define`
//! lines are macro plumbing and don't count). Each rule is ratcheted by
//! nothing (a hard ban, no baseline). A justified keep carries
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
    name: crate::allow_registry_fields::scheduler::SCOPE_META_0.name,
    group: crate::allow_registry_fields::scheduler::SCOPE_META_0.group,
    label: "scheduler",
    legacy: "tools/ci/scheduler_lints.py",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
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
    allow: crate::allow_registry_fields::scheduler::ALLOW_0,
    lists: crate::allow_registry_fields::scheduler::SCOPE_META_0.lists,
};

const SCHEDULER_PATTERN_SOURCES:&[(&str,&str)]=&[("spawn",r"(?<![\w./])spawn(?:\s*\(|\s*$|\s+[A-Za-z_])"),("addtimer",r"(?<![\w.])addtimer\s*\("),("invoke_async",r"\bINVOKE_ASYNC\b"),("do_after",r"(?<![\w./])do_after\s*\("),("sleep",r"(?<![\w./])sleep\s*\("),("stoplag",r"(?<![\w./])stoplag\s*\("),("prompts",r"(?<![\w./])(?:input|alert|tgui_input_\w+|tgui_alert)\s*\("),("set_waitfor",r"\bset\s+waitfor\b"),("weakref",r"(?i)weakref"),("del",r"(?<![\w./])del\s*\("),("blocking_builtins",r"(?<![\w./])(?:winget|winexists|shell)\s*\(|\.MeasureText\s*\(")];
struct Scheduler {
    /// `PATTERNS`, in the order the Python lists them (a line's matches are tried rule by rule).
    patterns: Vec<(&'static str, Pat)>,
}

impl Scheduler {
    fn new() -> Scheduler {
        Scheduler {
            patterns: vec![
                // A bare `spawn` (no delay) or `spawn x()` on one line is the same form.
                (SCHEDULER_PATTERN_SOURCES[0].0,Pat::new(SCHEDULER_PATTERN_SOURCES[0].1)),
                (SCHEDULER_PATTERN_SOURCES[1].0,Pat::new(SCHEDULER_PATTERN_SOURCES[1].1)),
                (SCHEDULER_PATTERN_SOURCES[2].0,Pat::new(SCHEDULER_PATTERN_SOURCES[2].1)),
                (SCHEDULER_PATTERN_SOURCES[3].0,Pat::new(SCHEDULER_PATTERN_SOURCES[3].1)),
                (SCHEDULER_PATTERN_SOURCES[4].0,Pat::new(SCHEDULER_PATTERN_SOURCES[4].1)),
                (SCHEDULER_PATTERN_SOURCES[5].0,Pat::new(SCHEDULER_PATTERN_SOURCES[5].1)),
                (SCHEDULER_PATTERN_SOURCES[6].0,Pat::new(SCHEDULER_PATTERN_SOURCES[6].1)),
                (SCHEDULER_PATTERN_SOURCES[7].0,Pat::new(SCHEDULER_PATTERN_SOURCES[7].1)),
                (SCHEDULER_PATTERN_SOURCES[8].0,Pat::new(SCHEDULER_PATTERN_SOURCES[8].1)),
                (SCHEDULER_PATTERN_SOURCES[9].0,Pat::new(SCHEDULER_PATTERN_SOURCES[9].1)),
                // BYOND's blocking built-ins: client round trips and OS processes. Callers ask DX-exec
                // (dx_winget(), dx_winexists(), dx_measure_text(), dx_shell(), dx_shelleo()) instead.
                (SCHEDULER_PATTERN_SOURCES[10].0,Pat::new(SCHEDULER_PATTERN_SOURCES[10].1)),
            ],
        }
    }
}

impl Lint for Scheduler {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self,_cx:&Cx,f:&SourceFile,out:&mut Sink){scan_using(f,out,&self.patterns)}

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/scheduler_lints.py"],
            old_raw: &[&["tools/ci/scheduler_lints.py", "--report"]],
            blank: &[],
            parse: ParseKind::Report,
            update: Some(&["tools/ci/scheduler_lints.py", "--update"]),
            seed: Some(&["tools/ci/scheduler_lints.py", "--seed"]),
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Scheduler::new());
}

fn scan_using<P:crate::raw_fixture_policy::PatternApi>(f:&SourceFile,out:&mut Sink,patterns:&[(&'static str,P)]){
        for (no, line) in f.code().numbered() {
            if py_lstrip(line).starts_with("#define") {
                continue;
            }
            for (name, pat) in patterns {
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

#[cfg(feature="native-policy")]
struct NativeScheduler{legacy:std::sync::OnceLock<Scheduler>}
#[cfg(feature="native-policy")]
impl Lint for NativeScheduler{
 fn meta(&self)->&Meta{&META}
 fn scan_file(&self,cx:&Cx,f:&SourceFile,out:&mut Sink){
  if let Some(fixture)=cx.fixture{
   let patterns=[(SCHEDULER_PATTERN_SOURCES[0].0,fixture.pattern(SCHEDULER_PATTERN_SOURCES[0].1,crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(SCHEDULER_PATTERN_SOURCES[0].1))),(SCHEDULER_PATTERN_SOURCES[1].0,fixture.pattern(SCHEDULER_PATTERN_SOURCES[1].1,crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(SCHEDULER_PATTERN_SOURCES[1].1))),(SCHEDULER_PATTERN_SOURCES[2].0,fixture.pattern(SCHEDULER_PATTERN_SOURCES[2].1,crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(SCHEDULER_PATTERN_SOURCES[2].1))),(SCHEDULER_PATTERN_SOURCES[3].0,fixture.pattern(SCHEDULER_PATTERN_SOURCES[3].1,crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(SCHEDULER_PATTERN_SOURCES[3].1))),(SCHEDULER_PATTERN_SOURCES[4].0,fixture.pattern(SCHEDULER_PATTERN_SOURCES[4].1,crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(SCHEDULER_PATTERN_SOURCES[4].1))),(SCHEDULER_PATTERN_SOURCES[5].0,fixture.pattern(SCHEDULER_PATTERN_SOURCES[5].1,crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(SCHEDULER_PATTERN_SOURCES[5].1))),(SCHEDULER_PATTERN_SOURCES[6].0,fixture.pattern(SCHEDULER_PATTERN_SOURCES[6].1,crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(SCHEDULER_PATTERN_SOURCES[6].1))),(SCHEDULER_PATTERN_SOURCES[7].0,fixture.pattern(SCHEDULER_PATTERN_SOURCES[7].1,crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(SCHEDULER_PATTERN_SOURCES[7].1))),(SCHEDULER_PATTERN_SOURCES[8].0,fixture.pattern(SCHEDULER_PATTERN_SOURCES[8].1,crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(SCHEDULER_PATTERN_SOURCES[8].1))),(SCHEDULER_PATTERN_SOURCES[9].0,fixture.pattern(SCHEDULER_PATTERN_SOURCES[9].1,crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(SCHEDULER_PATTERN_SOURCES[9].1))),(SCHEDULER_PATTERN_SOURCES[10].0,fixture.pattern(SCHEDULER_PATTERN_SOURCES[10].1,crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(SCHEDULER_PATTERN_SOURCES[10].1)))];
   scan_using(f,out,&patterns)
  }else{self.legacy.get_or_init(Scheduler::new).scan_file(cx,f,out)}
 }
 fn parity(&self)->Option<Parity>{self.legacy.get_or_init(Scheduler::new).parity()}
}
#[cfg(feature="native-policy")]
pub fn register_native(reg:&mut Registry){reg.add(NativeScheduler{legacy:std::sync::OnceLock::new()})}
