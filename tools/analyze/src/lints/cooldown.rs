//! Port of `tools/ci/cooldown_lint.py`: raw `world.time` cooldown compares
//! (doc/rewrite/object_model_core.md sec 16, "Rate-limit something").
//!
//! Counts the hand-rolled form: a line that compares `world.time` with something. Not counted, when
//! the line reads one of these: a var declared with `EXPIRY_DECLARE(name)` / `EXPIRY_TMP_DECLARE(name)`
//! anywhere in `code/` (collected by name first, which is why this is a tree scan), a var named for a
//! point in time (`*_at`, `*_until`, ...), a list slot read by a literal key or index, a reagent's
//! `data` slot under `code/modules/reagents`, a compare against a bare constant. Skipped: `#` lines
//! and the `exempt_prefixes` in `lint_scopes.toml` (the name index still reads those files).
//!
//! Quirks kept: the compare is tried on the `code_only` view, whose line numbers can drift from the raw
//! file after an unbalanced quote, and the fingerprint text is the raw line at that number; a name
//! declared in an EXPIRY macro inside a comment still joins the index; the Python read files with
//! `errors="ignore"` (invalid bytes dropped) where the engine's text has U+FFFD.

use std::collections::BTreeSet;
use std::sync::OnceLock;

use serde::{Deserialize, Serialize};

use crate::dm::pylines::recorded_into;
use crate::incr;
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::tree::CODE_DM;
use crate::util::py_lstrip;
use crate::util::py_strip;

static META: Meta = Meta {
    name: "cooldown",
    group: "",
    label: "cooldown",
    legacy: "tools/ci/cooldown_lint.py",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Sites {
        baseline: "tools/ci/cooldown_baseline.txt",
        header: &[
            "Raw world.time cooldown compares (tools/ci/cooldown_lint.py). rule<TAB>file<TAB>normalized line.",
            "Shrink-only: after a sweep, `python tools/ci/cooldown_lint.py --update`.",
        ],
        banned: &[],
    },
    rules: &[RuleMeta {
        name: "raw_compare",
        hint: "use COOLDOWN_START/COOLDOWN_FINISHED (code/__defines/cooldowns.dm) or om_after()",
    }],
    allow: &["cooldown"],
    lists: &[],
};

const CMP: &str = r"(?:>=|<=|(?<![<>=!])>(?![>=])|(?<![<>=])<(?![<=]))";
const CONST: &str = r"\d+(?:\.\d+)?(?:\s+(?:SECONDS?|MINUTES?|HOURS?|DECISECONDS?))?";

struct Patterns {
    compare: Pat,
    time_name: Pat,
    decl: Pat,
    data_slot: Pat,
    reagent_data: Pat,
    const_cmp: Pat,
}

impl Patterns {
    fn new() -> Patterns {
        Patterns {
            compare: Pat::new(&format!(r"(?<![\w.])world\.time\s*{cmp}|{cmp}\s*world\.time(?![\w])", cmp = CMP)),
            time_name: Pat::new(r"\b\w*(?:_at|_until|_since|deadline|expires|expires_at|expiry|timestamp|timeofdeath)\b"),
            decl: Pat::new(r"\b(?:STATIC_)?EXPIRY(?:_TMP)?_DECLARE\(\s*(\w+)\s*\)"),
            data_slot: Pat::new(r#"\[\s*(?:""|\d+)\s*\]"#),
            reagent_data: Pat::new(r"(?<![\w.])data\b"),
            const_cmp: Pat::new(&format!(
                r"world\.time\s*{cmp}\s*{c}\s*(?:\)|$|&&|\|\|)|(?:^|\(|&&|\|\|)\s*{c}\s*{cmp}\s*world\.time",
                cmp = CMP,
                c = CONST
            )),
        }
    }
}

struct Cooldown {
    p: Patterns,
}

#[derive(Serialize, Deserialize, Default, PartialEq)]
struct Names {
    names: Vec<String>,
}

fn not_a_cooldown(p: &Patterns, rel: &str, line: &str, stamp: &Option<Pat>) -> bool {
    if p.time_name.is_match(line) || p.data_slot.is_match(line) || p.const_cmp.is_match(py_strip(line)) {
        return true;
    }
    if let Some(s) = stamp {
        if s.is_match(line) {
            return true;
        }
    }
    rel.starts_with("code/modules/reagents/") && p.reagent_data.is_match(line)
}

impl Lint for Cooldown {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let p = &self.p;
        // `timestamp_names()`: every EXPIRY(_TMP)_DECLARE name in code/, exempt files included. One
        // file's names are cached by content; the union keys the per-file judgements.
        let all = cx.all_files();
        let declared = incr::facts("cooldown-names", &all, |f| {
            let text = f.text();
            let mut names: BTreeSet<String> = BTreeSet::new();
            if text.contains("EXPIRY") {
                for m in p.decl.captures_iter(text) {
                    names.insert(m.s(1).to_string());
                }
            }
            Names { names: names.into_iter().collect() }
        });
        let mut names: BTreeSet<String> = declared.into_iter().flat_map(|n| n.names).collect();
        names.remove("name");
        names.remove("time"); // would match every `world.time`
        let stamp: OnceLock<Option<Pat>> = OnceLock::new();
        let stamp_of = || {
            stamp.get_or_init(|| {
                if names.is_empty() {
                    None
                } else {
                    Some(Pat::new(&format!(r"(?<![\w])(?:{})\b", names.iter().cloned().collect::<Vec<_>>().join("|"))))
                }
            })
        };

        let files = cx.files();
        let key = incr::ctx_key(&names);
        let found = recorded_into(out, || {
            incr::keyed("cooldown-judge", key, &files, |f| {
                let mut lines: Vec<u32> = Vec::new();
                if !f.text().contains("world.time") {
                    return lines;
                }
                for (number, line) in f.code().numbered() {
                    if py_lstrip(line).starts_with('#') {
                        continue;
                    }
                    if p.compare.is_match(line) && !not_a_cooldown(p, &f.rel, line, stamp_of()) {
                        // ALLOW is asked only for a line that would count.
                        if !crate::dm::sys::kept_recorded(f, number, "cooldown") {
                            lines.push(number as u32);
                        }
                    }
                }
                lines
            })
        });
        for (f, lines) in files.iter().zip(found) {
            for number in lines {
                out.site_in("raw_compare", &f.rel, number as usize);
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/cooldown_lint.py"],
            old_raw: &[],
            blank: &["tools/ci/cooldown_baseline.txt"],
            parse: ParseKind::Tagged,
            update: Some(&["tools/ci/cooldown_lint.py", "--update"]),
            seed: Some(&["tools/ci/cooldown_lint.py", "--seed"]),
            files: &["tools/ci/cooldown_baseline.txt"],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Cooldown { p: Patterns::new() });
}
