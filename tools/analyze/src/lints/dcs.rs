//! Port of `tools/ci/dcs_lints.py`: the DCS ban (doc/rewrite/object_model_core.md sec 10 and 16).
//!
//! The DCS (signals, components, elements) is deleted. Any use of the old API in `code/` fails;
//! there is no ceiling and no ALLOW annotation. Comments and strings are ignored.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::tree::{SourceFile, CODE_DM};

const HINT: &str = "The DCS is gone: use OM events, om_hook() and behaviours (object_model_core.md sec 10, 16)";

static META: Meta = Meta {
    name: "dcs",
    group: "",
    label: "dcs",
    legacy: "tools/ci/dcs_lints.py",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "register_signal", hint: HINT },
        RuleMeta { name: "send_signal", hint: HINT },
        RuleMeta { name: "add_component", hint: HINT },
        RuleMeta { name: "add_element", hint: HINT },
        RuleMeta { name: "comsig", hint: HINT },
    ],
    allow: &[],
    lists: &[],
};

struct Dcs {
    patterns: Vec<(&'static str, Pat)>,
}

impl Dcs {
    fn new() -> Dcs {
        Dcs {
            patterns: vec![
                ("register_signal", Pat::new(r"(?<![\w/])(?:RegisterSignals?|UnregisterSignal)\s*\(")),
                ("send_signal", Pat::new(r"(?<![\w/])(?:SEND_SIGNAL|SEND_GLOBAL_SIGNAL)\s*\(|\bSIGNAL_HANDLER\b")),
                (
                    "add_component",
                    Pat::new(
                        r"(?<![\w/])(?:AddComponent|AddComponentFrom|LoadComponent|GetComponents?|GetExactComponent)\s*\(|/datum/component\b",
                    ),
                ),
                ("add_element", Pat::new(r"(?<![\w/])(?:AddElement|RemoveElement)\s*\(|/datum/element\b")),
                ("comsig", Pat::new(r"\b(?:COMSIG_[A-Z0-9_]+|SIGNAL_ADDTRAIT|SIGNAL_REMOVETRAIT)\b")),
            ],
        }
    }
}

impl Lint for Dcs {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        for (no, line) in f.code().numbered() {
            for (name, pat) in &self.patterns {
                for _ in pat.find_iter(line) {
                    out.site(name, no);
                }
            }
        }
    }

    fn selftest(&self) -> Result<String, String> {
        let f = SourceFile::from_text("code/a.dm", "\tRegisterSignal(src, COMSIG_X, PROC_REF(a))\n\t// SEND_SIGNAL(src, X)\n\tx.AddElement(/datum/element/y)\n");
        let mut out = Sink::new();
        out.cur = f.rel.clone();
        let cx_scope = crate::scopes::LintScope::default();
        let tree = crate::tree::Tree::from_files(vec![]);
        let cx = Cx { tree: &tree, meta: &META, scope: &cx_scope };
        self.scan_file(&cx, &f, &mut out);
        let rules: Vec<&str> = out.sites.iter().map(|s| s.rule.as_str()).collect();
        if rules == ["register_signal", "comsig", "add_element", "add_element"] {
            Ok(String::new())
        } else {
            Err(format!("unexpected sites {:?}", rules))
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/dcs_lints.py"],
            old_raw: &[
                &["tools/ci/dcs_lints.py", "--report", "register_signal"],
                &["tools/ci/dcs_lints.py", "--report", "send_signal"],
                &["tools/ci/dcs_lints.py", "--report", "add_component"],
                &["tools/ci/dcs_lints.py", "--report", "add_element"],
                &["tools/ci/dcs_lints.py", "--report", "comsig"],
            ],
            blank: &[],
            parse: ParseKind::Bare,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Dcs::new());
}
