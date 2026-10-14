//! Port of `tools/ci/stance_examine_lint.py`: stance and examine-text (roadmap I6b and I2b,
//! doc/rewrite/interactions.md sections 8 and 12). Both ceilings are 0.
//!
//! I6b: the deleted stance-read macros (`IS_HELPING` ...), `use_stance()`, the `a_intent` mirror,
//! and `input_stance()` outside the input layer (`input_stance_readers` in `lint_scopes.toml`).
//! I2b: any `description_info`.
//!
//! Quirks kept: the banned patterns are tried on the raw line (comments and strings count); only
//! `input_stance()` ignores a trailing `//` comment; `os.walk` scanned dot-files and dot-directories
//! of `code/` and `maps/` (`hidden: true`).

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat;
use crate::tree::{Select, SourceFile};
use crate::util::{before_slashes, starts_with_any};

const WHY_MACRO: &str = "stance-read macro; declare a stance on the interaction and read interaction.stance";
const WHY_USE: &str = "use_stance() is gone; the interaction that ran carries the stance";
const WHY_INTENT: &str = "a_intent is gone; the interaction that ran carries the stance";
const WHY_DESC: &str = "description_info is gone; examine text is generated from the interactions and properties";
const WHY_INPUT: &str = "input_stance() outside the input layer; take the stance from the interaction or a stance argument";

static META: Meta = Meta {
    name: "stance_examine",
    group: "",
    label: "stance_examine",
    legacy: "tools/ci/stance_examine_lint.py",
    select: Select { roots: &[("code", "dm"), ("maps", "dm")], hidden: true },
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "stance_macro", hint: WHY_MACRO },
        RuleMeta { name: "use_stance", hint: WHY_USE },
        RuleMeta { name: "a_intent", hint: WHY_INTENT },
        RuleMeta { name: "description_info", hint: WHY_DESC },
        RuleMeta { name: "input_stance", hint: WHY_INPUT },
    ],
    allow: &[],
    lists: &["input_stance_readers"],
};

struct StanceExamine;

impl Lint for StanceExamine {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, cx: &Cx, f: &SourceFile, out: &mut Sink) {
        let readers = cx.list("input_stance_readers");
        for (number, line) in f.raw().numbered() {
            if pat!(r"\bIS_(HELPING|HARMING|DISARMING|GRABBING)\b").is_match(line) {
                out.site_msg("stance_macro", number, WHY_MACRO);
            }
            if pat!(r"(?<![\w.])use_stance\s*\(|[.]use_stance\s*\(").is_match(line) {
                out.site_msg("use_stance", number, WHY_USE);
            }
            if pat!(r"\ba_intent\b").is_match(line) {
                out.site_msg("a_intent", number, WHY_INTENT);
            }
            if pat!(r"\bdescription_info\b").is_match(line) {
                out.site_msg("description_info", number, WHY_DESC);
            }
            if pat!(r"\binput_stance\s*\(").is_match(before_slashes(line)) && !starts_with_any(&f.rel, readers) {
                out.site_msg("input_stance", number, WHY_INPUT);
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/stance_examine_lint.py"],
            old_raw: &[&["tools/ci/stance_examine_lint.py"]],
            blank: &[],
            parse: ParseKind::FileLine,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(StanceExamine);
}
