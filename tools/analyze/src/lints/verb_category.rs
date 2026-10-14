//! Port of `tools/ci/verb_category_lint.py` (doc/rewrite unified plan 2.12).
//!
//! A verb's tab is a `VERB_CAT_*` define (code/__defines/verb_categories.dm), never a raw string:
//! `set category = "X"` and the category argument of `DEBUG_VERB` / `ADMIN_VERB` /
//! `ADMIN_VERB_AND_CONTEXT_MENU` are counted, and so is a define in verb_categories.dm that repeats
//! another define's string. `#define` lines (outside the ADMIN_VERB/DEBUG_VERB ones),
//! `code/modules/unit_tests` and `// ALLOW(verb_category): <reason>` lines are skipped.
//!
//! Quirks kept from the Python: the defines file itself is only scanned for duplicates (never for raw
//! categories); the ALLOW lookup indexes the raw lines with the line number of the `code_only` view
//! (which can drift after a string that swallows a newline); a file whose raw text has no
//! "category" is skipped.

use std::collections::HashMap;

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::Parity;
use crate::tree::{Select, SourceFile};
use crate::util::py_lstrip;

const BASELINE: &str = "tools/ci/verb_category_baseline.txt";
const DEFINES: &str = "code/__defines/verb_categories.dm";
const HINT: &str = "use a VERB_CAT_* define from code/__defines/verb_categories.dm";

static META: Meta = Meta {
    name: "verb_category",
    group: "",
    label: "verb_category",
    legacy: "tools/ci/verb_category_lint.py",
    select: Select::dm(&[("code", "dm"), ("interface", "dm")]),
    scan: ScanKind::File,
    policy: Policy::Sites {
        baseline: BASELINE,
        header: &[
            "Raw verb category strings (tools/ci/verb_category_lint.py). rule<TAB>file<TAB>normalized line.",
            "Shrink-only: after a sweep, `python tools/ci/verb_category_lint.py --update`.",
        ],
        banned: &[],
    },
    rules: &[RuleMeta { name: "raw_category", hint: HINT }, RuleMeta { name: "duplicate_define", hint: HINT }],
    allow: &["verb_category"],
    lists: &[],
};

struct VerbCategory;

impl Lint for VerbCategory {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        let set_category = crate::pat!(r#"\bset\s+category\s*=\s*""#);
        let macro_category = crate::pat!(r#"\b(?:DEBUG_VERB|ADMIN_VERB|ADMIN_VERB_AND_CONTEXT_MENU)\s*\((?:[^,()]*,){4}\s*""#);
        let define = crate::pat_match!(r##"#define\s+(VERB_CAT_\w+)\s+"([^"]*)""##);
        if f.rel == DEFINES {
            let mut seen: HashMap<String, String> = HashMap::new();
            for (number, line) in f.raw().numbered() {
                let Some(m) = define.captures(line) else { continue };
                let key = m.s(2).to_lowercase();
                if seen.contains_key(&key) {
                    out.site("duplicate_define", number);
                }
                seen.insert(key, m.s(1).to_string());
            }
            return;
        }
        if !f.text().contains("category") {
            return;
        }
        for (number, line) in f.code().numbered() {
            if py_lstrip(line).starts_with('#') && !line.contains("ADMIN_VERB") && !line.contains("DEBUG_VERB") {
                continue;
            }
            if (set_category.is_match(line) || macro_category.is_match(line)) && !out.allowed(f, number, "verb_category") {
                out.site("raw_category", number);
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        let mut p = Parity::ratchet(&["tools/ci/verb_category_lint.py"], &[BASELINE]);
        p.update = Some(&["tools/ci/verb_category_lint.py", "--update"]);
        p.seed = Some(&["tools/ci/verb_category_lint.py", "--seed"]);
        Some(p)
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(VerbCategory);
}
